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
const BACKUP_REQ = ENV.OPS_BACKUP_REQ || '/backup-req';
const MCP_TOKEN = ENV.OPS_MCP_TOKEN || '';
const API_DOMAIN = ENV.OPS_API_DOMAIN || 'api.marantau.web.id';
const VERSION = '1.9.1';
const { Q: EKO, IKN_TARGET_DEFAULT } = require('./eko');
const { Q: AUD, J: JEJAK } = require('./audit');
const ILU = require('./iluminaty');
const IKN_TARGET = +(ENV.OPS_IKN_TARGET || IKN_TARGET_DEFAULT);

if (MCP_TOKEN && MCP_TOKEN.length < 32) { console.error('OPS_MCP_TOKEN minimal 32 karakter.'); process.exit(1); }
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
             from extensions.pg_stat_statements
             where calls > 5 and userid not in (select oid from pg_roles where rolname in ('mt_ops_ro', 'supabase_admin'))
             order by mean_exec_time desc limit 15`),
    tables: q(`select c.relname as name, pg_size_pretty(pg_total_relation_size(c.oid)) as size, c.reltuples::bigint as rows_est
               from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'game' and c.relkind = 'r' order by pg_total_relation_size(c.oid) desc limit 12`),
    online: q(`select count(*)::int as n from game.mp_presence where ts > now() - interval '2 minutes'`).then(r => r[0].n),
  };
  const out = {};
  await Promise.all(Object.entries(tasks).map(async ([k, p]) => { try { out[k] = await p; } catch (e) { out[k] = null; (out.errors ||= {})[k] = e.message; } }));
  return out;
}

// ---------- Ekonomi & Kapten (dashboard) ----------
// Pool sendiri supaya query berat tidak berebut koneksi dengan tab Database / connector MCP.
const dashPool = new Pool({
  host: ENV.OPS_PG_HOST || 'db', port: +(ENV.OPS_PG_PORT || 5432), database: 'postgres',
  user: ENV.OPS_PG_USER || 'mt_ops_ro', password: ENV.OPS_PG_PASSWORD || '',
  max: 2, idleTimeoutMillis: 30000, connectionTimeoutMillis: 4000, application_name: 'marantau-ops-dash',
});
dashPool.on('error', e => console.error('pg dash pool:', e.message));
async function dashRows(sql, params) {
  const c = await dashPool.connect();
  let broken = false;
  try {
    await c.query('begin read only');
    await c.query("set local statement_timeout = '15s'");
    await c.query("set local idle_in_transaction_session_timeout = '20s'");
    return (await c.query(sql, params || [])).rows;
  } finally {
    try { await c.query('rollback'); } catch { broken = true; }
    c.release(broken);
  }
}
const cacheMap = new Map(); // key -> { at, val, pending }
function cached(key, ttlMs, fn, force = false) {
  const e = cacheMap.get(key);
  if (e && e.val !== undefined && !force && now() - e.at < ttlMs) return Promise.resolve(e.val);
  if (e && e.pending) return e.pending;
  const pending = fn().then(val => { cacheMap.set(key, { at: now(), val }); return val; },
    err => { const o = cacheMap.get(key); if (o) delete o.pending; throw err; });
  cacheMap.set(key, { ...(e || {}), pending });
  return pending;
}
// Satu potongan gagal tidak boleh mematikan seluruh halaman: tiap potongan membawa errornya sendiri.
async function parts(map, params) {
  const out = {}, errors = {};
  await Promise.all(Object.entries(map).map(async ([k, sql]) => {
    const prm = params ? params.slice(0, (sql.match(/\$(\d+)/g) || []).reduce((m, x) => Math.max(m, +x.slice(1)), 0)) : undefined;
    try { out[k] = await dashRows(sql, prm); } catch (e) { out[k] = null; errors[k] = e.message; }
  }));
  return { out, errors };
}

const EKO_FILE = path.join(DATA, 'ekonomi-harian.json');
let ekoDays = {};
try { ekoDays = JSON.parse(fs.readFileSync(EKO_FILE, 'utf8')).days || {}; } catch {}
async function snapEkonomi() {
  const { out } = await parts({ r: EKO.ringkasan, k: EKO.kepingTotal, i: EKO.ikn });
  const r = out.r && out.r[0]; if (!r) return;
  ekoDays[wibDate()] = {
    pemain: r.pemain, aktif24: r.aktif_24j, aktif7: r.aktif_7h, gold: r.total_gold, bank: r.total_bank, utang: r.total_utang,
    kekayaan: r.total_kekayaan, median: r.median_kekayaan, top1: r.pangsa_terkaya_pct, top3: r.pangsa_top3_pct, gini: r.gini,
    bunga: r.bunga_per_hari, laba: r.laba_dagang_24j,
    ikn: out.i && out.i[0] ? out.i[0].total : null, keping: out.k && out.k[0] ? out.k[0].beredar : null,
  };
  const keys = Object.keys(ekoDays).sort();
  for (const k of keys.slice(0, Math.max(0, keys.length - 400))) delete ekoDays[k];
  try { fs.writeFileSync(EKO_FILE + '.tmp', JSON.stringify({ days: ekoDays })); fs.renameSync(EKO_FILE + '.tmp', EKO_FILE); }
  catch (e) { console.error('simpan ekonomi:', e.message); }
}
setTimeout(() => snapEkonomi().catch(e => console.error('snapshot ekonomi:', e.message)), 30e3);
setInterval(() => snapEkonomi().catch(e => console.error('snapshot ekonomi:', e.message)), 60 * 60e3);

function ekonomi(force) {
  return cached('ekonomi', 60e3, async () => {
    const { out, errors } = await parts({
      ringkasan: EKO.ringkasan, dagang: EKO.dagang, arus: EKO.arus, stok: EKO.stok, ikn: EKO.ikn,
      kongsiTier: EKO.kongsiTier, kongsiMinggu: EKO.kongsiMinggu, keping: EKO.keping, kepingTotal: EKO.kepingTotal,
      tony: EKO.tony, tonyBuru: EKO.tonyBuru, pacu: EKO.pacu,
    });
    const riwayat = Object.keys(ekoDays).sort().map(d => ({ hari: d, ...ekoDays[d] }));
    return { at: now(), iknTarget: IKN_TARGET, riwayat, errors, ...out };
  }, force);
}
function kapten(force) {
  return cached('kapten', 60e3, async () => {
    const { out, errors } = await parts({ pemain: EKO.pemain, questPemain: EKO.questPemain, questRingkas: EKO.questRingkas });
    return { at: now(), errors, ...out };
  }, force);
}

// ---------- Audit (hanya baca) ----------
// jam: 24 / 168 / 720 / null (semua catatan). Nilai lain ditolak ke 168.
const AUDIT_JAM = { '24': 24, '168': 168, '720': 720, semua: null };
const auditJam = v => (v in AUDIT_JAM ? AUDIT_JAM[v] : 168);
function auditData(jamKey, force) {
  const jam = auditJam(jamKey);
  return cached('audit:' + jam, 60e3, async () => {
    const { out, errors } = await parts({
      gudang: AUD.gudang, arusGudang: AUD.arusGudang, transfer: AUD.transfer, bursa: AUD.bursa, bursaOrder: AUD.bursaOrder, daftar: AUD.daftar,
    }, [jam]);
    return { at: now(), jam, errors, ...out };
  }, force);
}
async function auditJejak(kapten, jamKey) {
  const jam = auditJam(jamKey), nama = String(kapten || '').slice(0, 80);
  if (!nama) return { at: now(), jam, errors: { kapten: 'Pilih kapten.' } };
  const { out, errors } = await parts({ ringkas: JEJAK.ringkas, pola: JEJAK.pola, transfer: JEJAK.transfer, hakLot: JEJAK.hakLot, log: JEJAK.log }, [jam, nama]);
  return { at: now(), jam, kapten: nama, errors, ...out };
}

// ---------- Iluminaty: Pesan Pribadi antar kapten (hanya baca) ----------
function iluData(force) {
  return cached('iluminaty', 30e3, async () => {
    const { out, errors } = await parts({ ringkas: ILU.Q.ringkas, percakapan: ILU.Q.percakapan, pengirim: ILU.Q.pengirim });
    return { at: now(), errors, ...out, ringkas: out.ringkas ? out.ringkas[0] : null };
  }, force);
}
async function iluUtas(pair) {
  pair = String(pair || '');
  if (!ILU.PAIR_RE.test(pair)) return { at: now(), errors: { utas: 'Percakapan tidak dikenal.' } };
  const { out, errors } = await parts({ utas: ILU.Q.utas }, [pair]);
  return { at: now(), pair, errors, ...out };
}
async function iluCari(q) {
  q = String(q || '').trim();
  if (q.length < 2) return { at: now(), q, errors: { cari: 'Minimal 2 huruf.' } };
  const { out, errors } = await parts({ cari: ILU.Q.cari }, [ILU.likePat(q)]);
  return { at: now(), q, errors, ...out };
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
    let pending = []; try { pending = fs.readdirSync(BACKUP_REQ).filter(f => f === 'backup' || f === 'restore-test'); } catch {}
    return { files: files.slice(0, 40), status, pending };
  } catch { return { files: [], status: null, pending: [], note: 'Folder backup belum ada (jalankan VPS deploy).' }; }
}
function requestBackup(kind) {
  if (kind !== 'backup' && kind !== 'restore-test') throw new Error('Jenis tidak dikenal.');
  fs.writeFileSync(path.join(BACKUP_REQ, kind), new Date().toISOString());
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
  setTimeout(() => tg('ℹ️ Panel Ops Marantau menyala. Ketik /bantuan untuk daftar perintah.'), 5000);
  setInterval(() => runAlerts().catch(e => console.error('alert:', e.message)), 60e3);
  setInterval(() => run5xxAlert().catch(() => {}), 10 * 60e3);
}


// ---------- Redaksi rahasia ----------
const SECRET_VALUES = Object.entries(ENV)
  .filter(([k, v]) => v && v.length >= 8 && /PASSWORD|SECRET|TOKEN|KEY|PGRST_JWT/i.test(k))
  .map(([, v]) => v).sort((a, b) => b.length - a.length);
function redact(text) {
  let t = String(text);
  for (const v of SECRET_VALUES) t = t.split(v).join('[rahasia]');
  return t
    .replace(/eyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{8,}/g, '[JWT]')
    .replace(/\bsb_(publishable|secret)_[\w-]+/g, '[kunci-sb]')
    .replace(/(apikey|authorization|password|passwd|token|secret)(["'=:\s]+)(bearer\s+)?[^\s"',&]{6,}/gi, '$1$2[rahasia]')
    .replace(/postgres(ql)?:\/\/([^:\s/]+):[^@\s]+@/g, 'postgres://$2:[rahasia]@');
}

// ---------- Laporan debug (untuk dikirim ke Claude) ----------
const PROBLEM_RE = /\b(error|fatal|panic|fail(ed|ure)?|timeout|timed out|refused|denied|unhealthy|oom|killed|crash|exception|too many|reset by peer|could not)\b/i;
async function containerInfo(name) {
  try {
    const j = await docker('GET', `/containers/${encodeURIComponent(name)}/json`);
    return { restarts: j.RestartCount, oom: j.State.OOMKilled, started: j.State.StartedAt, exit: j.State.ExitCode, health: j.State.Health && j.State.Health.Status };
  } catch (e) { return { error: e.message }; }
}
async function logLines(name, tail = 400, sinceSec = 0) {
  const since = sinceSec ? `&since=${Math.floor(now() / 1000) - sinceSec}` : '';
  const buf = await docker('GET', `/containers/${encodeURIComponent(name)}/logs?stdout=1&stderr=1&tail=${tail}&timestamps=1${since}`, { raw: true, timeout: 20000 });
  return demux(buf).split('\n').filter(Boolean);
}
function certInfo(host) {
  return new Promise(resolve => {
    const tls = require('tls');
    const sock = tls.connect({ host: ENV.OPS_TLS_CHECK_HOST || 'caddy', port: 443, servername: host, rejectUnauthorized: false, timeout: 5000 }, () => {
      const c = sock.getPeerCertificate(); sock.end();
      if (!c || !c.valid_to) return resolve({ error: 'tidak ada sertifikat' });
      resolve({ issuer: (c.issuer && (c.issuer.O || c.issuer.CN)) || '?', validTo: new Date(c.valid_to).toISOString().slice(0, 10), daysLeft: Math.floor((Date.parse(c.valid_to) - now()) / 86400e3) });
    });
    sock.on('error', e => resolve({ error: e.message }));
    sock.on('timeout', () => { sock.destroy(); resolve({ error: 'timeout' }); });
  });
}
function peaks(hours) {
  const cut = now() - hours * 3600e3, pts = ring.filter(x => x.t >= cut);
  const mx = k => { const v = pts.map(x => x[k]).filter(x => x != null); return v.length ? Math.round(Math.max(...v) * 10) / 10 : '-'; };
  return `CPU ${mx('cpu')}% · IOwait ${mx('iow')}% · RAM ${mx('mem')}% · swap ${mx('swapMb')} MB · load ${mx('load')}`;
}
async function debugReport({ logLinesPer = 25 } = {}) {
  const L = [], add = (...a) => L.push(...a);
  const h0 = current(), r = v => v == null ? '-' : Math.round(v * 10) / 10;
  const h = { ...h0, cpu: r(h0.cpu), iow: r(h0.iow), steal: r(h0.steal), load: r(h0.load) };
  const [sv, stats, db, h5, certApi, certOps] = await Promise.all([
    services(), serviceStats(), dbStats().catch(e => ({ errors: { all: e.message } })), http5xx(24),
    certInfo(API_DOMAIN), certInfo(ENV.OPS_DOMAIN || 'ops.marantau.web.id'),
  ]);
  add(`# Laporan debug Marantau Ops v${VERSION}`, `Waktu: ${new Date().toISOString()} (WIB ${new Date(now() + 7 * 3600e3).toISOString().slice(11, 16)})`, '');
  add('## Host',
    `CPU ${h.cpu ?? '-'}% · IOwait ${h.iow ?? '-'}% · steal ${h.steal ?? '-'}% · load ${h.load ?? '-'} (${h.cores} core)`,
    `RAM ${Math.round(h.memUsed / 1048576)}/${Math.round(h.memTotal / 1048576)} MB · swap ${Math.round(h.swapUsed / 1048576)}/${Math.round(h.swapTotal / 1048576)} MB · disk ${(h.diskUsed / 1073741824).toFixed(1)}/${(h.diskTotal / 1073741824).toFixed(1)} GB · uptime ${Math.round(h.uptimeSec / 3600)} jam`,
    `Puncak 1 jam: ${peaks(1)}`, `Puncak 24 jam: ${peaks(24)}`, '');
  add('## Sertifikat HTTPS',
    `api: ${certApi.error || `${certApi.issuer}, berlaku s/d ${certApi.validTo} (${certApi.daysLeft} hari)`}`,
    `ops: ${certOps.error || `${certOps.issuer}, berlaku s/d ${certOps.validTo} (${certOps.daysLeft} hari)`}`, '');
  add('## Layanan');
  if (sv.error) add(`Docker tidak terbaca: ${sv.error}`);
  const infos = await Promise.all((sv.items || []).map(s => containerInfo(s.name)));
  (sv.items || []).forEach((s, i) => {
    const inf = infos[i];
    add(`- ${s.label} [${s.name}]: ${s.state}${s.health ? '/' + s.health : ''} · ${s.status || '-'} · RAM ${stats[s.name] ? stats[s.name].memMb + ' MB' : '-'} · restart ${inf.restarts ?? '-'}${inf.oom ? ' · OOMKilled!' : ''} · ${s.image || ''}`);
  });
  add('');
  add('## Database');
  if (db.errors) add(`Error: ${JSON.stringify(db.errors)}`);
  const conns = (db.conns || []).reduce((a, c) => a + c.n, 0);
  add(`Online ${db.online ?? '-'} · koneksi ${conns}/${db.maxConn ?? '-'} · kunci menunggu ${db.waitingLocks ?? '-'} · ukuran ${db.size ?? '-'}`);
  for (const c of db.conns || []) add(`  koneksi ${c.role}/${c.state}: ${c.n}`);
  for (const t of db.longTx || []) add(`  transaksi lama: pid ${t.pid} ${t.role} ${t.state} ${t.sec}s :: ${t.query}`);
  add('Endpoint terlambat (rata² ms / maks ms / panggilan):');
  for (const r of (db.slow || []).slice(0, 10)) add(`  ${r.q}: ${r.mean_ms} / ${r.max_ms} / ${r.calls}`);
  add('');
  add('## HTTP api (24 jam)', h5.error ? `Log Caddy tidak terbaca: ${h5.error}` : `${h5.total} permintaan · ${h5.err} error 5xx · per jam (UTC): ${JSON.stringify(h5.perHour)}`, '');
  const b = backups();
  add('## Backup', b.status ? JSON.stringify(b.status) : (b.note || 'belum ada status'), `File lokal: ${b.files.filter(f => f.name.endsWith('.age')).length} · antrean: ${b.pending.join(',') || '-'}`, '');
  add('## Peringatan aktif', [...alertState.entries()].filter(([, v]) => v.active).map(([k]) => k).join(', ') || '-', '');
  add(`## Log bermasalah (maks ${logLinesPer} baris per layanan, 24 jam terakhir)`);
  for (const s of SERVICES) {
    try {
      const lines = (await logLines(s.name, 2000, 86400)).filter(l => PROBLEM_RE.test(l) && !/"status":(2|3)\d\d/.test(l));
      add(`### ${s.name} (${lines.length} baris bermasalah)`);
      for (const l of lines.slice(-logLinesPer)) add(l.slice(0, 400));
    } catch (e) { add(`### ${s.name}: log tidak terbaca (${e.message})`); }
  }
  add('', '## Log terakhir (10 baris per layanan)');
  for (const s of SERVICES) {
    try { add(`### ${s.name}`, ...(await logLines(s.name, 10)).map(l => l.slice(0, 300))); } catch {}
  }
  return redact(L.join('\n'));
}

// ---------- Connector Claude (MCP, hanya-baca) ----------
const roPool = new Pool({
  host: ENV.OPS_PG_HOST || 'db', port: +(ENV.OPS_PG_PORT || 5432), database: 'postgres',
  user: ENV.OPS_PG_USER || 'mt_ops_ro', password: ENV.OPS_PG_PASSWORD || '',
  max: 2, idleTimeoutMillis: 30000, connectionTimeoutMillis: 4000, application_name: 'marantau-ops-mcp',
});
roPool.on('error', e => console.error('pg ro pool:', e.message));
const MAX_ROWS = 200;
let qSeq = 0;
async function readOnlyQuery(sql) {
  sql = String(sql || '').trim().replace(/;\s*$/, '');
  if (!sql) throw new Error('SQL kosong.');
  if (sql.length > 8000) throw new Error('SQL terlalu panjang (maks 8000 karakter).');
  const c = await roPool.connect();
  let broken = false;
  try {
    await c.query('begin read only');
    await c.query("set local statement_timeout = '5s'");
    await c.query("set local idle_in_transaction_session_timeout = '10s'");
    // Prepared statement (protokol extended) => Postgres menolak lebih dari SATU pernyataan.
    const name = 'mt_q' + (++qSeq);
    if (/^\s*(explain|show)\b/i.test(sql)) {
      const r = await c.query({ name, text: sql });
      return { columns: (r.fields || []).map(f => f.name), rows: r.rows.slice(0, MAX_ROWS), rowCount: r.rowCount, truncated: r.rows.length > MAX_ROWS };
    }
    // Lewat cursor supaya hasil besar tidak ditarik semua ke memori.
    await c.query({ name, text: `declare mt_cur no scroll cursor for ${sql}` });
    const r = await c.query(`fetch ${MAX_ROWS + 1} from mt_cur`);
    return { columns: (r.fields || []).map(f => f.name), rows: r.rows.slice(0, MAX_ROWS), rowCount: Math.min(r.rows.length, MAX_ROWS), truncated: r.rows.length > MAX_ROWS };
  } catch (e) {
    if (/syntax error at or near "(declare|;)"/i.test(e.message) || /cannot insert multiple commands/i.test(e.message)) e.message = 'Hanya SATU pernyataan SELECT/WITH/VALUES/EXPLAIN/SHOW. ' + e.message;
    throw e;
  } finally {
    try { await c.query('rollback'); await c.query('deallocate all'); } catch { broken = true; }
    c.release(broken);
  }
}
const MCP_TOOLS = [
  { name: 'server_status', description: 'Kondisi server Marantau di Biznet: CPU, IOwait, RAM, swap, disk, load, puncak 1/24 jam, status & RAM tiap layanan (Postgres, PostgREST, Auth, Realtime, Envoy, Caddy, Panel Ops).', inputSchema: { type: 'object', properties: {} } },
  { name: 'db_stats', description: 'Statistik database: pemain online, koneksi per role/state, kunci menunggu, transaksi > 10 detik, endpoint api_* paling lambat (pg_stat_statements), tabel terbesar schema game.', inputSchema: { type: 'object', properties: {} } },
  { name: 'db_query', description: `Jalankan SATU query SQL hanya-baca (role mt_ops_ro, transaksi read only, timeout 5 detik, maks ${MAX_ROWS} baris). Bisa membaca schema game & statistik Postgres; schema auth tidak bisa dibaca.`, inputSchema: { type: 'object', properties: { sql: { type: 'string', description: 'Satu pernyataan SELECT / WITH / EXPLAIN / SHOW' } }, required: ['sql'] } },
  { name: 'logs_tail', description: 'Baris log terakhir satu layanan (rahasia disamarkan).', inputSchema: { type: 'object', properties: { service: { type: 'string', enum: SERVICES.map(s => s.name) }, lines: { type: 'integer', minimum: 1, maximum: 500, default: 150 }, filter: { type: 'string', description: 'Opsional: hanya baris yang mengandung teks ini (tidak peka huruf besar/kecil)' } }, required: ['service'] } },
  { name: 'backup_list', description: 'Status backup VM (terakhir berhasil, ukuran, tes restore) dan daftar file backup lokal.', inputSchema: { type: 'object', properties: {} } },
  { name: 'debug_report', description: 'Laporan debug lengkap (sama dengan menu Debug di Panel Ops): host, sertifikat, layanan, database, 5xx, backup, peringatan, log bermasalah 24 jam.', inputSchema: { type: 'object', properties: {} } },
];
async function mcpCall(name, args = {}) {
  switch (name) {
    case 'server_status': {
      const [sv, stats] = await Promise.all([services(), serviceStats()]);
      return { host: current(), peak1h: peaks(1), peak24h: peaks(24), services: (sv.items || []).map(s => ({ ...s, memMb: stats[s.name] && stats[s.name].memMb })), dockerError: sv.error };
    }
    case 'db_stats': return dbStats();
    case 'db_query': return readOnlyQuery(args.sql);
    case 'logs_tail': {
      if (!SERVICE_NAMES.has(args.service)) throw new Error('Layanan tidak dikenal.');
      const n = Math.min(500, Math.max(1, +args.lines || 150));
      let lines = await logLines(args.service, args.filter ? 3000 : n);
      if (args.filter) { const f = String(args.filter).toLowerCase(); lines = lines.filter(l => l.toLowerCase().includes(f)).slice(-n); }
      return lines.join('\n');
    }
    case 'backup_list': return backups();
    case 'debug_report': return debugReport();
    default: throw new Error('Alat tidak dikenal: ' + name);
  }
}
const mcpHits = [];
async function handleMcp(req, res) {
  const cut = now() - 60e3; while (mcpHits.length && mcpHits[0] < cut) mcpHits.shift();
  if (mcpHits.length >= 60) return json(res, 429, { jsonrpc: '2.0', id: null, error: { code: -32000, message: 'Terlalu banyak permintaan (60/menit).' } });
  mcpHits.push(now());
  if (req.method === 'GET') { res.writeHead(405, { Allow: 'POST' }); return res.end(); }
  if (req.method === 'DELETE') { res.writeHead(200); return res.end(); }
  if (req.method !== 'POST') { res.writeHead(405); return res.end(); }
  let msg;
  try { msg = await readBody(req, 64 * 1024); } catch (e) { return json(res, 400, { jsonrpc: '2.0', id: null, error: { code: -32700, message: e.message } }); }
  const one = async m => {
    if (!m || m.jsonrpc !== '2.0' || typeof m.method !== 'string') return { jsonrpc: '2.0', id: m && m.id !== undefined ? m.id : null, error: { code: -32600, message: 'Permintaan tidak valid' } };
    if (m.id === undefined) return null; // notifikasi
    const ok = result => ({ jsonrpc: '2.0', id: m.id, result });
    try {
      switch (m.method) {
        case 'initialize': {
          const want = m.params && m.params.protocolVersion;
          const ver = ['2025-06-18', '2025-03-26', '2024-11-05'].includes(want) ? want : '2025-06-18';
          return ok({ protocolVersion: ver, capabilities: { tools: { listChanged: false } }, serverInfo: { name: 'marantau-ops', version: VERSION },
            instructions: 'Connector hanya-baca untuk server Marantau (Biznet self-host). Mulai dari server_status / debug_report. db_query: satu pernyataan, read only, 5 dtk, maks 200 baris; schema auth tidak terbaca. Tidak ada aksi restart/ubah data.' });
        }
        case 'ping': return ok({});
        case 'tools/list': return ok({ tools: MCP_TOOLS });
        case 'resources/list': return ok({ resources: [] });
        case 'prompts/list': return ok({ prompts: [] });
        case 'tools/call': {
          const { name, arguments: args } = m.params || {};
          console.log(`[mcp] ${new Date().toISOString()} ${name}${name === 'db_query' ? ' ' + String((args || {}).sql || '').slice(0, 120).replace(/\s+/g, ' ') : ''}`);
          try {
            const r = await mcpCall(name, args || {});
            let text = typeof r === 'string' ? r : JSON.stringify(r);
            text = redact(text);
            if (text.length > 120000) text = text.slice(0, 120000) + '\n…(dipotong)';
            return ok({ content: [{ type: 'text', text }] });
          } catch (e) { return ok({ content: [{ type: 'text', text: 'Error: ' + redact(e.message) }], isError: true }); }
        }
        default: return { jsonrpc: '2.0', id: m.id, error: { code: -32601, message: 'Metode tidak dikenal: ' + m.method } };
      }
    } catch (e) { return { jsonrpc: '2.0', id: m.id, error: { code: -32603, message: e.message } }; }
  };
  const out = Array.isArray(msg) ? (await Promise.all(msg.map(one))).filter(Boolean) : await one(msg);
  if (!out || (Array.isArray(out) && !out.length)) { res.writeHead(202); return res.end(); }
  return json(res, 200, out);
}


// ---------- Bot Telegram (perintah) ----------
// Hanya menjawab chat pemilik (OPS_TELEGRAM_CHAT_ID). Tidak ada perintah restart/ubah data.
const TG_STATE_FILE = path.join(DATA, 'tg-state.json');
let tgState = { offset: 0, lastDaily: '', onlinePeak: {} };
try { tgState = { ...tgState, ...JSON.parse(fs.readFileSync(TG_STATE_FILE, 'utf8')) }; } catch {}
function saveTgState() { try { fs.writeFileSync(TG_STATE_FILE, JSON.stringify(tgState)); } catch (e) { console.error('tg-state:', e.message); } }
const hEsc = t => String(t ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const wibDate = (t = now()) => new Date(t + 7 * 3600e3).toISOString().slice(0, 10);
const wibTime = (t = now()) => new Date(t + 7 * 3600e3).toISOString().slice(11, 16);
async function tgApi(method, body, timeoutMs = 15000) {
  const r = await fetch(`https://api.telegram.org/bot${TG_TOKEN}/${method}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs),
  });
  const j = await r.json();
  if (!j.ok) throw new Error(`telegram ${method}: ${j.description}`);
  return j.result;
}
async function tgHtml(html) {
  for (let i = 0; i < html.length; i += 3900) {
    await tgApi('sendMessage', { chat_id: TG_CHAT, text: html.slice(i, i + 3900), parse_mode: 'HTML', disable_web_page_preview: true });
  }
}
async function tgDoc(filename, text, caption) {
  const fd = new FormData();
  fd.append('chat_id', TG_CHAT);
  if (caption) fd.append('caption', caption);
  fd.append('document', new Blob([text], { type: 'text/plain' }), filename);
  const r = await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendDocument`, { method: 'POST', body: fd, signal: AbortSignal.timeout(30000) });
  const j = await r.json(); if (!j.ok) throw new Error('sendDocument: ' + j.description);
}

// Puncak pemain online per hari (WIB), sampel tiap 5 menit.
async function sampleOnline() {
  try {
    const r = await q(`select count(*)::int as n from game.mp_presence where ts > now() - interval '2 minutes'`);
    const d = wibDate(), n = r[0].n;
    if (!tgState.onlinePeak[d] || n > tgState.onlinePeak[d].n) tgState.onlinePeak[d] = { n, at: wibTime() };
    for (const k of Object.keys(tgState.onlinePeak)) if (k < wibDate(now() - 8 * 86400e3)) delete tgState.onlinePeak[k];
    saveTgState();
  } catch {}
}

const dot = (ok, warn) => ok ? '🟢' : warn ? '🟡' : '🔴';
const r1 = v => v == null ? '-' : Math.round(v * 10) / 10;
async function textStatus() {
  const h = current();
  const [sv, stats] = await Promise.all([services(), serviceStats()]);
  const memPct = h.memTotal ? Math.round(100 * h.memUsed / h.memTotal) : null;
  const diskPct = h.diskTotal ? Math.round(100 * h.diskUsed / h.diskTotal) : null;
  const L = [`<b>🖥 Status server</b> · ${wibTime()} WIB`,
    `${dot(h.cpu < 70, h.cpu < 90)} CPU ${r1(h.cpu)}% · load ${r1(h.load)}`,
    `${dot(h.iow < 10, h.iow < 30)} IOwait ${r1(h.iow)}%`,
    `${dot(memPct < 75, memPct < 85)} RAM ${memPct}% (${Math.round(h.memUsed / 1048576)}/${Math.round(h.memTotal / 1048576)} MB)`,
    `${dot(h.swapUsed < 50 * 1048576, h.swapUsed < 200 * 1048576)} Swap ${Math.round(h.swapUsed / 1048576)} MB`,
    `${dot(diskPct < 70, diskPct < 80)} Disk ${diskPct}% (${(h.diskUsed / 1073741824).toFixed(1)}/${(h.diskTotal / 1073741824).toFixed(0)} GB)`,
    `⏱ Uptime ${Math.floor(h.uptimeSec / 86400)}h ${Math.floor(h.uptimeSec % 86400 / 3600)}j`, '', '<b>Layanan</b>'];
  if (sv.error) L.push('🔴 Docker tidak terbaca: ' + hEsc(sv.error));
  for (const s of sv.items || []) {
    const ok = s.state === 'running' && s.health !== 'unhealthy';
    L.push(`${dot(ok && s.health !== 'starting', ok)} ${hEsc(s.label)}${stats[s.name] ? ` · ${stats[s.name].memMb} MB` : ''}${ok ? '' : ` · <b>${hEsc(s.state)}${s.health ? '/' + hEsc(s.health) : ''}</b>`}`);
  }
  const act = [...alertState.entries()].filter(([, v]) => v.active).map(([k]) => k);
  if (act.length) L.push('', '⚠️ Peringatan aktif: ' + hEsc(act.join(', ')));
  return L.join('\n');
}
async function textDb() {
  const d = await dbStats();
  const total = (d.conns || []).reduce((a, c) => a + c.n, 0);
  const pk = tgState.onlinePeak[wibDate()];
  const L = [`<b>🗄 Database</b> · ${wibTime()} WIB`,
    `👥 Online: <b>${d.online ?? '-'}</b>${pk ? ` (puncak hari ini ${pk.n} @${pk.at})` : ''}`,
    `${dot(total < (d.maxConn || 60) * 0.6, total < (d.maxConn || 60) * 0.85)} Koneksi ${total}/${d.maxConn ?? '-'}`,
    `${dot(!d.waitingLocks, d.waitingLocks <= 5)} Kunci menunggu ${d.waitingLocks ?? '-'}`,
    `💾 Ukuran ${hEsc(d.size ?? '-')}`];
  if ((d.longTx || []).length) L.push(`🐢 Transaksi > 10 dtk: ${d.longTx.length} (terlama ${d.longTx[0].sec} dtk)`);
  L.push('', '<b>Endpoint terlambat</b> (rata² / maks ms)');
  for (const r of (d.slow || []).slice(0, 6)) L.push(`${r.mean_ms > 1000 ? '🔴' : r.mean_ms > 300 ? '🟡' : '▫️'} ${hEsc(r.q)}: ${r.mean_ms} / ${r.max_ms} (${r.calls}x)`);
  if (!(d.slow || []).length) L.push('▫️ belum ada data');
  if (d.errors) L.push('', '⚠️ ' + hEsc(Object.entries(d.errors).map(([k, v]) => `${k}: ${v}`).join(' · ')));
  return L.join('\n');
}
function textBackup() {
  const b = backups(), s = b.status || {};
  const age = s.lastOk ? (now() - Date.parse(s.lastOk)) / 3600e3 : null;
  return [`<b>📦 Backup VM</b>`,
    `${dot(age != null && age < 26, age != null && age < 30)} Terakhir berhasil: ${s.lastOk ? `${wibDate(Date.parse(s.lastOk))} ${wibTime(Date.parse(s.lastOk))} WIB (${Math.round(age)} jam lalu)` : 'belum pernah'}`,
    `${s.lastResult === 'gagal' ? '🔴 Gagal terakhir: ' + hEsc(s.lastError) : '▫️ Hasil terakhir: ' + hEsc(s.lastResult || '-')}`,
    `▫️ Ukuran ${hEsc(s.size || '-')} · ${hEsc(s.tables || '-')} tabel · ${hEsc(s.rows || '-')} baris`,
    `${s.restoreTest === 'GAGAL' ? '🔴' : s.restoreTest === 'OK' ? '🟢' : '▫️'} Tes restore: ${hEsc(s.restoreTest || 'belum')}${s.restoreAt ? ' (' + wibDate(Date.parse(s.restoreAt)) + ')' : ''}`,
    `☁️ Google Drive: ${hEsc(s.driveFiles ?? '-')} file · lokal ${b.files.filter(f => f.name.endsWith('.age')).length} file`,
    s.running || b.pending.length ? `⏳ Sedang berjalan: ${hEsc(s.running || b.pending.join(', '))}` : ''].filter(Boolean).join('\n');
}
async function textDaily() {
  const yest = wibDate(now() - 86400e3), today = wibDate();
  const [d, h5, cert] = await Promise.all([dbStats().catch(() => ({})), http5xx(24), certInfo(API_DOMAIN)]);
  const sv = await services();
  const down = (sv.items || []).filter(s => s.state !== 'running' || s.health === 'unhealthy');
  const infos = await Promise.all((sv.items || []).map(s => containerInfo(s.name)));
  const restarts = (sv.items || []).map((s, i) => [s.label, infos[i].restarts]).filter(([, n]) => n > 0);
  const pk = tgState.onlinePeak[yest] || tgState.onlinePeak[today];
  const h = current();
  const L = [`<b>☀️ Laporan harian Marantau</b> · ${today}`, '',
    `<b>Server (24 jam)</b>`, 'Puncak: ' + hEsc(peaks(24)),
    `Kini: RAM ${Math.round(100 * h.memUsed / h.memTotal)}% · disk ${Math.round(100 * h.diskUsed / h.diskTotal)}% · uptime ${Math.round(h.uptimeSec / 3600)} jam`,
    sv.error ? '🔴 Docker tidak terbaca: ' + hEsc(sv.error) : down.length ? '🔴 Layanan bermasalah: ' + hEsc(down.map(s => s.label).join(', ')) : '🟢 Semua layanan sehat',
    restarts.length ? `🔁 Pernah restart: ${hEsc(restarts.map(([l, n]) => `${l} ${n}x`).join(', '))}` : '',
    '', `<b>Pemain & database</b>`,
    `👥 Online sekarang ${d.online ?? '-'}${pk ? ` · puncak ${pk.n} (@${pk.at})` : ''}`,
    `🐢 Endpoint terlambat: ${(d.slow || []).slice(0, 3).map(r => `${hEsc(r.q)} ${r.mean_ms} ms`).join(', ') || '-'}`,
    `💾 Ukuran DB ${hEsc(d.size ?? '-')}`,
    '', `<b>API</b>`,
    h5.error ? '⚠️ log tidak terbaca' : `${dot(h5.err === 0, h5.err < 20)} ${h5.total.toLocaleString('id-ID')} permintaan · ${h5.err} error 5xx`,
    cert.error ? `🔴 Sertifikat: ${hEsc(cert.error)}` : `${dot(cert.daysLeft > 20, cert.daysLeft > 7)} Sertifikat HTTPS ${cert.daysLeft} hari lagi`,
    '', textBackup()];
  const act = [...alertState.entries()].filter(([, v]) => v.active).map(([k]) => k);
  if (act.length) L.push('', '⚠️ Peringatan aktif: ' + hEsc(act.join(', ')));
  return L.filter(x => x !== '').join('\n').replace(/\n<b>/g, '\n\n<b>');
}
async function textErrors(hours = 1) {
  const L = [`<b>🧯 Log bermasalah ${hours} jam terakhir</b>`];
  for (const s of SERVICES) {
    try {
      const lines = (await logLines(s.name, 3000, hours * 3600)).filter(l => PROBLEM_RE.test(l) && !/"status":(2|3)\d\d/.test(l));
      L.push(`${lines.length ? '🔴' : '🟢'} ${hEsc(s.label)}: ${lines.length} baris`);
      for (const l of lines.slice(-3)) L.push(`<code>${hEsc(redact(l).slice(0, 220))}</code>`);
    } catch (e) { L.push(`⚠️ ${hEsc(s.label)}: ${hEsc(e.message)}`); }
  }
  return L.join('\n');
}
const LOG_ALIAS = { db: 'supabase-db', postgres: 'supabase-db', rest: 'supabase-rest', api: 'supabase-rest', auth: 'supabase-auth', realtime: 'realtime-dev.supabase-realtime', rt: 'realtime-dev.supabase-realtime', envoy: 'supabase-envoy', gateway: 'supabase-envoy', caddy: 'marantau-caddy', https: 'marantau-caddy', ops: 'marantau-ops', panel: 'marantau-ops' };
const TG_COMMANDS = [
  ['status', 'Kondisi server & layanan'],
  ['db', 'Pemain online, koneksi, endpoint terlambat'],
  ['backup', 'Status backup VM'],
  ['harian', 'Laporan harian sekarang'],
  ['error', 'Log bermasalah 1 jam (/error 6 = 6 jam)'],
  ['log', 'Log layanan: /log rest 30 (db, rest, auth, realtime, envoy, caddy, ops)'],
  ['debug', 'Laporan debug lengkap (.txt) untuk Claude'],
  ['backup_sekarang', 'Jalankan backup sekarang'],
  ['tes_restore', 'Backup + tes restore'],
  ['bantuan', 'Daftar perintah'],
];
async function tgCommand(text) {
  const [raw, ...args] = text.trim().split(/\s+/);
  const cmd = raw.replace(/^\//, '').replace(/@.*$/, '').toLowerCase();
  switch (cmd) {
    case 'start': case 'bantuan': case 'help':
      return tgHtml('<b>Marantau Ops</b>\n' + TG_COMMANDS.map(([c, d]) => `/${c} - ${hEsc(d)}`).join('\n') + `\n\nLaporan harian otomatis jam 07:00 WIB. Restart layanan hanya lewat Panel Ops.`);
    case 'status': return tgHtml(await textStatus());
    case 'db': return tgHtml(await textDb());
    case 'backup': return tgHtml(textBackup());
    case 'harian': case 'laporan': return tgHtml(await textDaily());
    case 'error': case 'errors': return tgHtml(await textErrors(Math.min(24, Math.max(1, +args[0] || 1))));
    case 'log': {
      const name = LOG_ALIAS[(args[0] || '').toLowerCase()] || args[0];
      if (!SERVICE_NAMES.has(name)) return tgHtml('Pakai: /log &lt;layanan&gt; [baris]\nLayanan: db, rest, auth, realtime, envoy, caddy, ops');
      const n = Math.min(80, Math.max(5, +args[1] || 30));
      const lines = (await logLines(name, n)).map(l => redact(l).slice(0, 300));
      return tgHtml(`<b>Log ${hEsc(name)}</b> (${lines.length} baris)\n<pre>${hEsc(lines.join('\n')).slice(0, 3700)}</pre>`);
    }
    case 'debug': {
      await tgHtml('⏳ Menyusun laporan debug…');
      const t = await debugReport();
      return tgDoc(`marantau-debug-${wibDate()}-${wibTime().replace(':', '')}.txt`, t, 'Laporan debug - kirim ke Claude bila ada masalah.');
    }
    case 'backup_sekarang': requestBackup('backup'); return tgHtml('📦 Backup dimulai. Hasilnya: /backup (±1-5 menit).');
    case 'tes_restore': requestBackup('restore-test'); return tgHtml('🧪 Backup + tes restore dimulai (±3-10 menit). Hasilnya: /backup');
    default: return tgHtml('Perintah tidak dikenal. /bantuan');
  }
}
async function tgPoll() {
  try { await tgApi('setMyCommands', { commands: TG_COMMANDS.map(([command, description]) => ({ command, description: description.slice(0, 250) })) }); }
  catch (e) { console.error('setMyCommands:', e.message); }
  for (;;) {
    try {
      const ups = await tgApi('getUpdates', { offset: tgState.offset, timeout: 50, allowed_updates: ['message'] }, 65000);
      for (const u of ups) {
        tgState.offset = u.update_id + 1; saveTgState();
        const m = u.message; if (!m || !m.text) continue;
        if (String(m.chat.id) !== String(TG_CHAT)) { console.log(`[tg] abaikan chat ${m.chat.id}`); continue; }
        if (!m.text.startsWith('/')) { await tgHtml('Ketik /bantuan untuk daftar perintah.'); continue; }
        console.log(`[tg] ${m.text.slice(0, 60)}`);
        try { await tgCommand(m.text); } catch (e) { await tgHtml('⚠️ Error: ' + hEsc(redact(e.message))).catch(() => {}); }
      }
    } catch (e) {
      console.error('tg poll:', e.message);
      await sleep(/409|Conflict/.test(e.message) ? 60000 : 10000);
    }
  }
}
async function dailyTick() {
  const t = now() + 7 * 3600e3, hh = new Date(t).getUTCHours(), today = wibDate();
  if (hh >= 7 && tgState.lastDaily !== today) {
    tgState.lastDaily = today; saveTgState();
    try { await tgHtml(await textDaily()); } catch (e) { console.error('laporan harian:', e.message); }
  }
}
if (TG_TOKEN && TG_CHAT) {
  if (!tgState.lastDaily) { tgState.lastDaily = wibDate(); saveTgState(); } // jangan kirim laporan saat pertama dipasang
  tgPoll();
  setInterval(() => dailyTick().catch(() => {}), 60e3);
  setInterval(() => sampleOnline(), 5 * 60e3); setTimeout(sampleOnline, 20000);
}

// ---------- HTTP ----------
const PUB = path.join(__dirname, 'public');
const SEC_HEADERS = {
  'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
};
function sendFile(res, f, type, cache = 'no-cache') {
  try { const b = fs.readFileSync(path.join(PUB, f)); res.writeHead(200, { 'Content-Type': type, 'Cache-Control': cache }); res.end(b); }
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
    if (req.method === 'GET' && /^\/(app|tokens|base)\.css$/.test(p)) return sendFile(res, p.slice(1), 'text/css; charset=utf-8');
    if (req.method === 'GET' && (p === '/ekonomi.js' || p === '/audit.js' || p === '/iluminaty.js')) return sendFile(res, p.slice(1), 'text/javascript; charset=utf-8');
    if (req.method === 'GET' && /^\/fonts\/[a-z0-9-]+\.woff2$/.test(p)) return sendFile(res, p.slice(1), 'font/woff2', 'public, max-age=31536000, immutable');
    if (req.method === 'GET' && p === '/healthz') return json(res, 200, { ok: true, v: VERSION });
    if (MCP_TOKEN && p.startsWith('/mcp/')) {
      if (!safeEq(p.slice(5).replace(/\/$/, ''), MCP_TOKEN)) { await sleep(300); res.writeHead(404); return res.end('Not found'); }
      return handleMcp(req, res);
    }

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
        return json(res, 200, { name, text: redact(demux(buf)) });
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
      if (req.method === 'GET' && p === '/api/ekonomi') return json(res, 200, await ekonomi(url.searchParams.get('fresh') === '1'));
      if (req.method === 'GET' && p === '/api/kapten') return json(res, 200, await kapten(url.searchParams.get('fresh') === '1'));
      if (req.method === 'GET' && p === '/api/audit') return json(res, 200, await auditData(url.searchParams.get('jam'), url.searchParams.get('fresh') === '1'));
      if (req.method === 'GET' && p === '/api/audit/jejak') return json(res, 200, await auditJejak(url.searchParams.get('kapten'), url.searchParams.get('jam')));
      if (req.method === 'GET' && p === '/api/iluminaty') return json(res, 200, await iluData(url.searchParams.get('fresh') === '1'));
      if (req.method === 'GET' && p === '/api/iluminaty/utas') { audit(ip, 'iluminaty buka utas'); return json(res, 200, await iluUtas(url.searchParams.get('pair'))); }
      if (req.method === 'GET' && p === '/api/iluminaty/cari') { audit(ip, 'iluminaty cari'); return json(res, 200, await iluCari(url.searchParams.get('q'))); }
      if (req.method === 'GET' && p === '/api/http') return json(res, 200, await http5xx(24));
      if (req.method === 'GET' && p === '/api/backup') return json(res, 200, backups());
      if (req.method === 'POST' && p === '/api/backup/run') {
        const b = await readBody(req);
        requestBackup(b.kind); audit(ip, 'minta ' + b.kind);
        return json(res, 200, { ok: true });
      }
      if (req.method === 'GET' && p === '/api/debug') {
        audit(ip, 'laporan debug');
        return json(res, 200, { text: await debugReport() });
      }
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
