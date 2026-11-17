// Panel Ops Marantau (rencana 1.5). Satu file, tanpa framework. Dependensi: pg.
// Login sandi + TOTP. Metrik host dari /host/proc. Docker lewat socket, hanya daftar container tetap.
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Pool } = require('pg');

const ENV = process.env;
const PORT = +(ENV.OPS_PORT || 8080);
const PROC = ENV.OPS_PROC || '/host/proc';
const DATA = ENV.OPS_DATA || '/data';
const BACKUP_DIR = ENV.OPS_BACKUP_DIR || '/backup';
const DISK_PATH = ENV.OPS_DISK_PATH || DATA;
const DOCKER_SOCK = ENV.OPS_DOCKER_SOCK || '/var/run/docker.sock';
const PASSWORD = ENV.OPS_PASSWORD || '';
const TOTP_SECRET = (ENV.OPS_TOTP_SECRET || '').replace(/\s+/g, '').toUpperCase();
const SESSION_KEY = ENV.OPS_SESSION_SECRET || crypto.randomBytes(32).toString('hex');
const TG_TOKEN = ENV.OPS_TELEGRAM_TOKEN || '';
const TG_CHAT = ENV.OPS_TELEGRAM_CHAT_ID || '';
const DEV = ENV.OPS_DEV === '1';

if (!PASSWORD || PASSWORD.length < 16 || !TOTP_SECRET) {
  console.error('OPS_PASSWORD (>=16) dan OPS_TOTP_SECRET wajib diisi.');
  process.exit(1);
}

// Container yang boleh dilihat & di-restart. Urutan = urutan tampil.
const SERVICES = [
  { name: 'supabase-db', label: 'Postgres', risky: true },
  { name: 'supabase-rest', label: 'PostgREST' },
  { name: 'supabase-auth', label: 'Auth (GoTrue)' },
  { name: 'realtime-dev.supabase-realtime', label: 'Realtime' },
  { name: 'supabase-envoy', label: 'API gateway (Envoy)' },
  { name: 'marantau-caddy', label: 'Caddy (HTTPS)' },
  { name: 'marantau-ops', label: 'Panel Ops (ini)' },
];
const SERVICE_NAMES = new Set(SERVICES.map(s => s.name));

const pool = new Pool({
  host: ENV.OPS_PG_HOST || 'db', port: +(ENV.OPS_PG_PORT || 5432), database: 'postgres',
  user: ENV.OPS_PG_USER || 'mt_ops_ro', password: ENV.OPS_PG_PASSWORD || '',
  max: 2, idleTimeoutMillis: 30000, connectionTimeoutMillis: 4000,
  application_name: 'marantau-ops',
});
pool.on('error', e => console.error('pg pool:', e.message));

// ---------- util ----------
const sleep = ms => new Promise(r => setTimeout(r, ms));
const now = () => Date.now();
function readProc(f) { try { return fs.readFileSync(path.join(PROC, f), 'utf8'); } catch { return ''; } }
function json(res, code, obj) {
  const b = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(b);
}
function clientIp(req) {
  const xf = (req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return xf || req.socket.remoteAddress || '?';
}
function readBody(req, limit = 4096) {
  return new Promise((resolve, reject) => {
    let n = 0; const chunks = [];
    req.on('data', c => { n += c.length; if (n > limit) { reject(new Error('body terlalu besar')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => { try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); } catch { reject(new Error('JSON tidak valid')); } });
    req.on('error', reject);
  });
}
function safeEq(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// ---------- TOTP (RFC 6238, SHA1, 6 digit, 30 dtk) ----------
function base32Decode(s) {
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits = 0, val = 0; const out = [];
  for (const ch of s.replace(/=+$/, '')) {
    const i = A.indexOf(ch); if (i < 0) continue;
    val = (val << 5) | i; bits += 5;
    if (bits >= 8) { out.push((val >>> (bits - 8)) & 255); bits -= 8; }
  }
  return Buffer.from(out);
}
const TOTP_KEY = base32Decode(TOTP_SECRET);
function totpAt(counter) {
  const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(counter));
  const h = crypto.createHmac('sha1', TOTP_KEY).update(b).digest();
  const o = h[h.length - 1] & 15;
  const code = ((h.readUInt32BE(o) & 0x7fffffff) % 1e6).toString().padStart(6, '0');
  return code;
}
let lastTotpCounter = 0; // cegah pakai ulang kode yang sama
function checkTotp(code) {
  code = String(code || '').replace(/\D/g, '');
  if (code.length !== 6) return false;
  const c = Math.floor(now() / 30000);
  for (const d of [0, -1, 1]) {
    if (c + d > lastTotpCounter && safeEq(totpAt(c + d), code)) { lastTotpCounter = c + d; return true; }
  }
  return false;
}

// ---------- sesi (cookie bertanda tangan HMAC, 12 jam) ----------
const SESSION_HOURS = 12;
function sign(v) { return crypto.createHmac('sha256', SESSION_KEY).update(v).digest('base64url'); }
function makeSession() {
  const exp = now() + SESSION_HOURS * 3600e3;
  const v = `${exp}.${crypto.randomBytes(9).toString('base64url')}`;
  return `${v}.${sign(v)}`;
}
function cookieOf(req, name) {
  const m = (req.headers.cookie || '').split(';').map(s => s.trim()).find(s => s.startsWith(name + '='));
  return m ? decodeURIComponent(m.slice(name.length + 1)) : '';
}
function authed(req) {
  const s = cookieOf(req, 'mt_ops');
  const i = s.lastIndexOf('.'); if (i < 0) return false;
  const v = s.slice(0, i), sig = s.slice(i + 1);
  if (!safeEq(sign(v), sig)) return false;
  return +v.split('.')[0] > now();
}
function setCookie(res, val, maxAge) {
  res.setHeader('Set-Cookie', `mt_ops=${encodeURIComponent(val)}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${maxAge}${DEV ? '' : '; Secure'}`);
}

// ---------- batas percobaan login ----------
const fails = new Map(); // ip -> [ts...]
let globalFails = [];
function tooMany(ip) {
  const cut = now() - 15 * 60e3;
  const a = (fails.get(ip) || []).filter(t => t > cut); fails.set(ip, a);
  globalFails = globalFails.filter(t => t > cut);
  return a.length >= 5 || globalFails.length >= 20;
}
function noteFail(ip) { (fails.get(ip) || fails.set(ip, []).get(ip)).push(now()); globalFails.push(now()); }

// ---------- metrik host ----------
const RING_MAX = 7 * 24 * 60; // 7 hari, 1 sampel/menit
let ring = [];
const RING_FILE = path.join(DATA, 'metrics.json');
try { ring = JSON.parse(fs.readFileSync(RING_FILE, 'utf8')).filter(x => x.t > now() - 7 * 86400e3); } catch {}
let lastCpu = null;
function cpuTimes() {
  const l = readProc('stat').split('\n')[0].trim().split(/\s+/).slice(1).map(Number);
  if (l.length < 5) return null;
  const [user, nice, sys, idle, iowait = 0, irq = 0, softirq = 0, steal = 0] = l;
  return { total: user + nice + sys + idle + iowait + irq + softirq + steal, idle, iowait, steal };
}
function memInfo() {
  const m = {};
  for (const line of readProc('meminfo').split('\n')) { const [k, v] = line.split(':'); if (v) m[k.trim()] = parseInt(v) * 1024; }
  const total = m.MemTotal || 0, avail = m.MemAvailable || 0;
  return { total, used: total - avail, swapTotal: m.SwapTotal || 0, swapUsed: (m.SwapTotal || 0) - (m.SwapFree || 0) };
}
function diskInfo() {
  try { const s = fs.statfsSync(DISK_PATH); const total = s.blocks * s.bsize, free = s.bavail * s.bsize; return { total, used: total - free }; }
  catch { return { total: 0, used: 0 }; }
}
function sample() {
  const c = cpuTimes(); let cpu = null, iow = null, steal = null;
  if (c && lastCpu) {
    const dt = c.total - lastCpu.total;
    if (dt > 0) {
      cpu = +(100 * (1 - (c.idle + c.iowait - lastCpu.idle - lastCpu.iowait) / dt)).toFixed(1);
      iow = +(100 * (c.iowait - lastCpu.iowait) / dt).toFixed(1);
      steal = +(100 * (c.steal - lastCpu.steal) / dt).toFixed(1);
    }
  }
  lastCpu = c;
  const m = memInfo(), d = diskInfo();
  const load = parseFloat(readProc('loadavg').split(' ')[0]) || 0;
  return {
    t: now(), cpu, iow, steal, load,
    mem: m.total ? +(100 * m.used / m.total).toFixed(1) : null,
    swapMb: Math.round(m.swapUsed / 1048576),
    disk: d.total ? +(100 * d.used / d.total).toFixed(1) : null,
  };
}
function current() {
  const m = memInfo(), d = diskInfo();
  const up = parseFloat(readProc('uptime').split(' ')[0]) || 0;
  return { ...(ring[ring.length - 1] || {}), memTotal: m.total, memUsed: m.used, swapTotal: m.swapTotal, swapUsed: m.swapUsed, diskTotal: d.total, diskUsed: d.used, uptimeSec: Math.round(up), cores: (readProc('cpuinfo').match(/^processor/mg) || []).length };
}
sample();
setInterval(() => {
  ring.push(sample());
  if (ring.length > RING_MAX) ring.splice(0, ring.length - RING_MAX);
}, 60e3);
setInterval(() => { try { fs.writeFileSync(RING_FILE + '.tmp', JSON.stringify(ring)); fs.renameSync(RING_FILE + '.tmp', RING_FILE); } catch (e) { console.error('simpan metrik:', e.message); } }, 10 * 60e3);

// ---------- Docker API (socket) ----------
function docker(method, p, { raw = false, timeout = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ socketPath: DOCKER_SOCK, method, path: '/v1.43' + p, timeout }, res => {
      const chunks = []; res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const b = Buffer.concat(chunks);
        if (res.statusCode >= 400) return reject(new Error(`docker ${res.statusCode}: ${b.toString().slice(0, 200)}`));
        if (raw) return resolve(b);
        try { resolve(b.length ? JSON.parse(b.toString()) : null); } catch { resolve(b.toString()); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('docker timeout')));
    req.on('error', reject); req.end();
  });
}
function demux(buf) { // log stream non-TTY: header 8 byte per frame
  const out = []; let i = 0;
  while (i + 8 <= buf.length) { const len = buf.readUInt32BE(i + 4); out.push(buf.slice(i + 8, i + 8 + len)); i += 8 + len; }
  return i === 0 ? buf.toString('utf8') : Buffer.concat(out).toString('utf8');
}
async function services() {
  let list = [];
  try { list = await docker('GET', '/containers/json?all=1'); } catch (e) { return { error: e.message, items: [] }; }
  const byName = new Map(list.map(c => [c.Names[0].replace(/^\//, ''), c]));
  return {
    items: SERVICES.map(s => {
      const c = byName.get(s.name);
      if (!c) return { ...s, state: 'tidak ada', health: '', status: '' };
      const h = (c.Status.match(/\((healthy|unhealthy|health: starting)\)/) || [])[1] || '';
      return { ...s, state: c.State, health: h.replace('health: ', ''), status: c.Status, image: c.Image };
    }),
  };
}
async function serviceStats() {
  const out = {};
  await Promise.all(SERVICES.map(async s => {
    try {
      const st = await docker('GET', `/containers/${encodeURIComponent(s.name)}/stats?stream=false&one-shot=true`, { timeout: 8000 });
      const cache = (st.memory_stats.stats && (st.memory_stats.stats.inactive_file || st.memory_stats.stats.total_inactive_file)) || 0;
      out[s.name] = { memMb: Math.round((st.memory_stats.usage - cache) / 1048576) };
    } catch {}
  }));
  return out;
}

// ---------- Database ----------
async function q(sql, params) { const r = await pool.query(sql, params); return r.rows; }
async function dbStats() {
  const tasks = {
    size: q(`select pg_size_pretty(pg_database_size('postgres')) as size`).then(r => r[0].size),
    conns: q(`select coalesce(usename,'(sistem)') as role, coalesce(state,'-') as state, count(*)::int as n
              from pg_stat_activity where datname = 'postgres' group by 1,2 order by 3 desc`),
    maxConn: q(`select current_setting('max_connections')::int as m`).then(r => r[0].m),
    waitingLocks: q(`select count(*)::int as n from pg_locks where not granted`).then(r => r[0].n),
    longTx: q(`select pid, usename as role, state, round(extract(epoch from now() - xact_start))::int as sec, left(query, 120) as query
               from pg_stat_activity where datname = 'postgres' and xact_start < now() - interval '10 seconds' and pid <> pg_backend_pid()
               order by xact_start limit 10`),
    slow: q(`select calls::int, round(mean_exec_time)::int as mean_ms, round(max_exec_time)::int as max_ms,
                    round(total_exec_time / 1000)::int as total_s,
                    coalesce(substring(query from 'public\\.(api_[a-zA-Z0-9_]+)'), left(regexp_replace(query, '\\s+', ' ', 'g'), 90)) as q
             from extensions.pg_stat_statements where calls > 5 order by mean_exec_time desc limit 15`),
    tables: q(`select c.relname as name, pg_size_pretty(pg_total_relation_size(c.oid)) as size, c.reltuples::bigint as rows_est
               from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'game' and c.relkind = 'r' order by pg_total_relation_size(c.oid) desc limit 12`),
    online: q(`select count(*)::int as n from game.mp_presence where ts > now() - interval '2 minutes'`).then(r => r[0].n),
  };
  const out = {};
  await Promise.all(Object.entries(tasks).map(async ([k, p]) => { try { out[k] = await p; } catch (e) { out[k] = null; (out.errors ||= {})[k] = e.message; } }));
  return out;
}

// ---------- 5xx dari log Caddy (api.) ----------
async function http5xx(hours = 24) {
  try {
    const since = Math.floor((now() - hours * 3600e3) / 1000);
    const buf = await docker('GET', `/containers/marantau-caddy/logs?stdout=1&stderr=1&since=${since}`, { raw: true, timeout: 20000 });
    let total = 0, err = 0; const perHour = {};
    for (const line of demux(buf).split('\n')) {
      if (!line.includes('"handled request"')) continue;
      const m = line.match(/"status":(\d{3})/); if (!m) continue;
      total++;
      if (+m[1] >= 500) {
        err++;
        const t = line.match(/"ts":(\d+)/); if (t) { const h = new Date(+t[1] * 1000).toISOString().slice(0, 13); perHour[h] = (perHour[h] || 0) + 1; }
      }
    }
    return { total, err, perHour };
  } catch (e) { return { error: e.message }; }
}

// ---------- Backup (folder hasil Fase 0 / 1.7) ----------
function backups() {
  try {
    const files = fs.readdirSync(BACKUP_DIR).filter(f => /\.age$|\.dump$|\.json$/.test(f)).map(f => {
      const st = fs.statSync(path.join(BACKUP_DIR, f)); return { name: f, size: st.size, mtime: st.mtimeMs };
    }).sort((a, b) => b.mtime - a.mtime);
    let status = null; try { status = JSON.parse(fs.readFileSync(path.join(BACKUP_DIR, 'status.json'), 'utf8')); } catch {}
    return { files: files.slice(0, 40), status };
  } catch { return { files: [], status: null, note: 'Folder backup belum ada (menunggu 1.7).' }; }
}

// ---------- Peringatan Telegram ----------
const alertState = new Map(); // key -> {active, last}
async function tg(text) {
  if (!TG_TOKEN || !TG_CHAT) return;
  try {
    await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendMessage`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: TG_CHAT, text, disable_web_page_preview: true }),
      signal: AbortSignal.timeout(10000),
    });
  } catch (e) { console.error('telegram:', e.message); }
}
function alertCheck(key, bad, msg) {
  const s = alertState.get(key) || { active: false, last: 0 };
  if (bad && (!s.active || now() - s.last > 6 * 3600e3)) { tg(`⚠️ Marantau: ${msg}`); s.active = true; s.last = now(); }
  else if (!bad && s.active) { tg(`✅ Marantau pulih: ${key}`); s.active = false; }
  alertState.set(key, s);
}
let badStreak = {};
async function runAlerts() {
  const c = current();
  const streak = (k, cond) => (badStreak[k] = cond ? (badStreak[k] || 0) + 1 : 0);
  alertCheck('RAM', streak('ram', c.mem > 85) >= 3, `RAM ${c.mem}% (>85%) selama 3 menit`);
  alertCheck('Swap', streak('swap', c.swapMb > 200) >= 3, `Swap terpakai ${c.swapMb} MB`);
  alertCheck('Disk', c.disk > 80, `Disk ${c.disk}% (>80%)`);
  alertCheck('IOwait', streak('iow', c.iow > 30) >= 5, `IOwait ${c.iow}% selama 5 menit`);
  const sv = await services();
  for (const s of sv.items || []) {
    const down = s.state !== 'running' || s.health === 'unhealthy';
    alertCheck(`Layanan ${s.label}`, streak('svc:' + s.name, down) >= 2, `${s.label} ${s.state}${s.health ? ' / ' + s.health : ''}`);
  }
  const b = backups();
  if (b.status && b.status.lastOk) alertCheck('Backup', now() - Date.parse(b.status.lastOk) > 30 * 3600e3, `backup terakhir berhasil ${b.status.lastOk}`);
}
let lastErrCount = null;
async function run5xxAlert() {
  const r = await http5xx(1);
  if (r.error) return;
  alertCheck('5xx', r.err >= 20, `${r.err} error 5xx dalam 1 jam terakhir`);
  lastErrCount = r.err;
}
if (TG_TOKEN && TG_CHAT) {
  setTimeout(() => tg('ℹ️ Panel Ops Marantau menyala.'), 5000);
  setInterval(() => runAlerts().catch(e => console.error('alert:', e.message)), 60e3);
  setInterval(() => run5xxAlert().catch(() => {}), 10 * 60e3);
}

// ---------- HTTP ----------
const PUB = path.join(__dirname, 'public');
const SEC_HEADERS = {
  'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
};
function sendFile(res, f, type) {
  try { const b = fs.readFileSync(path.join(PUB, f)); res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' }); res.end(b); }
  catch { res.writeHead(404); res.end(); }
}
const audit = (ip, what) => console.log(`[audit] ${new Date().toISOString()} ${ip} ${what}`);

const server = http.createServer(async (req, res) => {
  for (const [k, v] of Object.entries(SEC_HEADERS)) res.setHeader(k, v);
  const url = new URL(req.url, 'http://x');
  const p = url.pathname, ip = clientIp(req);
  try {
    if (req.method === 'GET' && (p === '/' || p === '/index.html')) return sendFile(res, 'index.html', 'text/html; charset=utf-8');
    if (req.method === 'GET' && p === '/app.js') return sendFile(res, 'app.js', 'text/javascript; charset=utf-8');
    if (req.method === 'GET' && p === '/app.css') return sendFile(res, 'app.css', 'text/css; charset=utf-8');
    if (req.method === 'GET' && p === '/healthz') return json(res, 200, { ok: true });

    // POST wajib header khusus (penangkal CSRF lintas situs, selain SameSite=Strict).
    if (req.method === 'POST' && req.headers['x-ops'] !== '1') return json(res, 403, { error: 'ditolak' });

    if (req.method === 'POST' && p === '/api/login') {
      if (tooMany(ip)) { audit(ip, 'login diblokir sementara'); return json(res, 429, { error: 'Terlalu banyak percobaan. Coba lagi 15 menit lagi.' }); }
      const b = await readBody(req);
      await sleep(400 + Math.random() * 300);
      if (!safeEq(b.password || '', PASSWORD) || !checkTotp(b.code)) {
        noteFail(ip); audit(ip, 'login gagal');
        return json(res, 401, { error: 'Sandi atau kode 2FA salah.' });
      }
      audit(ip, 'login berhasil');
      setCookie(res, makeSession(), SESSION_HOURS * 3600);
      return json(res, 200, { ok: true });
    }
    if (req.method === 'POST' && p === '/api/logout') { setCookie(res, '', 0); return json(res, 200, { ok: true }); }
    if (p === '/api/me') return json(res, 200, { authed: authed(req) });

    if (p.startsWith('/api/')) {
      if (!authed(req)) return json(res, 401, { error: 'Belum login.' });

      if (req.method === 'GET' && p === '/api/overview') {
        const [sv, stats] = await Promise.all([services(), serviceStats()]);
        return json(res, 200, { now: now(), host: current(), services: sv, stats, telegram: !!(TG_TOKEN && TG_CHAT) });
      }
      if (req.method === 'GET' && p === '/api/metrics') {
        const hours = Math.min(168, Math.max(1, +url.searchParams.get('hours') || 24));
        const cut = now() - hours * 3600e3;
        const pts = ring.filter(x => x.t >= cut);
        const step = Math.max(1, Math.floor(pts.length / 400)); // maks ±400 titik per grafik
        const out = [];
        for (let i = 0; i < pts.length; i += step) {
          const g = pts.slice(i, i + step), avg = k => { const v = g.map(x => x[k]).filter(x => x != null); return v.length ? +(v.reduce((a, b) => a + b, 0) / v.length).toFixed(1) : null; };
          const mx = k => { const v = g.map(x => x[k]).filter(x => x != null); return v.length ? Math.max(...v) : null; };
          out.push({ t: g[0].t, cpu: avg('cpu'), iow: mx('iow'), mem: mx('mem'), swapMb: mx('swapMb'), disk: avg('disk'), load: mx('load') });
        }
        return json(res, 200, { hours, points: out });
      }
      if (req.method === 'GET' && p === '/api/logs') {
        const name = url.searchParams.get('name');
        if (!SERVICE_NAMES.has(name)) return json(res, 400, { error: 'Layanan tidak dikenal.' });
        const buf = await docker('GET', `/containers/${encodeURIComponent(name)}/logs?stdout=1&stderr=1&tail=200&timestamps=1`, { raw: true });
        return json(res, 200, { name, text: demux(buf) });
      }
      if (req.method === 'POST' && p === '/api/restart') {
        const b = await readBody(req);
        if (!SERVICE_NAMES.has(b.name)) return json(res, 400, { error: 'Layanan tidak dikenal.' });
        audit(ip, `restart ${b.name}`);
        if (b.name === 'marantau-ops') { json(res, 200, { ok: true, note: 'Panel memulai ulang...' }); setTimeout(() => process.exit(0), 300); return; }
        await docker('POST', `/containers/${encodeURIComponent(b.name)}/restart?t=20`, { timeout: 60000 });
        tg(`🔁 ${b.name} di-restart dari Panel Ops`);
        return json(res, 200, { ok: true });
      }
      if (req.method === 'GET' && p === '/api/db') return json(res, 200, await dbStats());
      if (req.method === 'GET' && p === '/api/http') return json(res, 200, await http5xx(24));
      if (req.method === 'GET' && p === '/api/backup') return json(res, 200, backups());
      if (req.method === 'POST' && p === '/api/telegram-test') {
        if (!TG_TOKEN || !TG_CHAT) return json(res, 400, { error: 'OPS_TELEGRAM_TOKEN / OPS_TELEGRAM_CHAT_ID belum diisi di .env.' });
        await tg('🔔 Tes peringatan dari Panel Ops Marantau.');
        return json(res, 200, { ok: true });
      }
      return json(res, 404, { error: 'Tidak ada.' });
    }
    res.writeHead(404); res.end('Not found');
  } catch (e) {
    console.error(p, e.message);
    json(res, 500, { error: e.message });
  }
});
server.listen(PORT, () => console.log(`Panel Ops di :${PORT}${DEV ? ' (DEV)' : ''}`));
process.on('SIGTERM', () => { try { fs.writeFileSync(RING_FILE, JSON.stringify(ring)); } catch {} process.exit(0); });
