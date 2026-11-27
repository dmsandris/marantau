// Workbench Marantau. Satu proses, tanpa framework. Login memakai sesi Panel Ops (cookie mt_ops, rahasia sama).
// Hanya bisa dijangkau lewat Caddy (/wb/*) di jaringan Docker; port tidak dipublikasikan.
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ENV = process.env;
const PORT = +(ENV.WB_PORT || 8080);
const DATA = ENV.WB_DATA || '/data';
const SESSION_KEY = ENV.OPS_SESSION_SECRET || '';
const OPS_DOMAIN = ENV.OPS_DOMAIN || 'ops.marantau.web.id';
const DEV = ENV.WB_DEV === '1';
const PUB = path.join(__dirname, 'public');
const VERSION = '1.0.0';

if (!SESSION_KEY || SESSION_KEY.length < 32) { console.error('OPS_SESSION_SECRET wajib diisi (sama dengan Panel Ops).'); process.exit(1); }

const settings = require('./settings').create(DATA, ENV);
const ai = require('./ai');
const tools = require('./tools');
const agents = require('./agents');
const runner = require('./runner').create({ settings, tools, ai, dataDir: DATA });

// ---------- sesi (format sama dengan Panel Ops) ----------
const sign = v => crypto.createHmac('sha256', SESSION_KEY).update(v).digest('base64url');
function safeEq(a, b) { const x = Buffer.from(String(a)), y = Buffer.from(String(b)); return x.length === y.length && crypto.timingSafeEqual(x, y); }
function cookieOf(req, name) {
  const m = (req.headers.cookie || '').split(';').map(s => s.trim()).find(s => s.startsWith(name + '='));
  try { return m ? decodeURIComponent(m.slice(name.length + 1)) : ''; } catch { return ''; }
}
function authed(req) {
  const s = cookieOf(req, 'mt_ops'); const i = s.lastIndexOf('.'); if (i < 0) return false;
  const v = s.slice(0, i); if (!safeEq(sign(v), s.slice(i + 1))) return false;
  return +v.split('.')[0] > Date.now();
}

// ---------- util ----------
const SEC = {
  'X-Frame-Options': 'DENY', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
};
function json(res, code, obj) { const b = JSON.stringify(obj); res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }); res.end(b); }
function readBody(req, limit = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let n = 0; const ch = [];
    req.on('data', c => { n += c.length; if (n > limit) { reject(new Error('Isian terlalu besar.')); req.destroy(); } else ch.push(c); });
    req.on('end', () => { try { resolve(ch.length ? JSON.parse(Buffer.concat(ch).toString('utf8')) : {}); } catch { reject(new Error('JSON tidak valid.')); } });
    req.on('error', reject);
  });
}
function sendFile(res, f, type) {
  try { res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-cache' }); res.end(fs.readFileSync(path.join(PUB, f))); }
  catch { res.writeHead(404); res.end(); }
}
const audit = (what) => console.log(`[audit] ${new Date().toISOString()} ${what}`);
const rate = new Map(); // batas kasar: 120 panggilan alat/menit
function tooMany() { const cut = Date.now() - 60000; const a = (rate.get('x') || []).filter(t => t > cut); a.push(Date.now()); rate.set('x', a); return a.length > 120; }

// Salinan repo: sinkron saat boot dan bila sudah >10 menit sebelum run baru. Gagal sync tidak menghentikan kerja bila salinan lama ada.
async function syncRepo(force) {
  const g = settings.get().github, st = tools.repoStatus();
  if (!force && st.ada && Date.now() - st.syncAt < 10 * 60e3 && st.repo === g.repo) return st;
  if (!force && st.ada && st.syncAt === 0) { /* salinan dari sebelum restart: tetap segarkan di latar belakang */ }
  return tools.repoSync(g.repo, g.base);
}
syncRepo(true).catch(e => console.error('sync repo awal:', e.message));

function publicRun(r, full) {
  if (!r) return null;
  const o = { ...r, cancel: undefined };
  if (!full) { o.log = r.log.slice(-40); }
  o.toolLog = r.toolLog.slice(-120);
  return o;
}

const server = http.createServer(async (req, res) => {
  for (const [k, v] of Object.entries(SEC)) res.setHeader(k, v);
  const url = new URL(req.url, 'http://x'); const p = url.pathname;
  try {
    if (p === '/healthz') return json(res, 200, { ok: true, v: VERSION });
    const pageReq = req.method === 'GET' && (p === '/' || p === '/index.html' || p === '/wb.js' || p === '/wb.css');
    if (!authed(req)) {
      if (req.method === 'GET' && (p === '/' || p === '/index.html')) { res.writeHead(302, { Location: '/', 'Cache-Control': 'no-store' }); return res.end(); }
      return json(res, 401, { error: 'Belum login. Masuk lewat Panel Ops dulu.' });
    }
    if (pageReq) return sendFile(res, p === '/' || p === '/index.html' ? 'index.html' : p.slice(1), p.endsWith('.js') ? 'text/javascript; charset=utf-8' : p.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/html; charset=utf-8');
    if (req.method === 'POST') {
      if (req.headers['x-ops'] !== '1') return json(res, 403, { error: 'ditolak' });
      const o = req.headers.origin; if (o && !DEV && o !== 'https://' + OPS_DOMAIN) return json(res, 403, { error: 'asal tidak dikenal' });
    }
    if (!p.startsWith('/api/')) { res.writeHead(404); return res.end('Not found'); }
    if (tooMany()) return json(res, 429, { error: 'Terlalu banyak permintaan.' });

    // ----- ringkasan & pengaturan -----
    if (req.method === 'GET' && p === '/api/state') {
      let db = { ok: false };
      try { await tools.dbQuery('select 1 as ok'); db = { ok: true }; } catch (e) { db = { ok: false, error: e.message }; }
      const pub = settings.publik();
      const team = agents.roster(settings);
      return json(res, 200, {
        v: VERSION, pengaturan: pub, db, repo: tools.repoStatus(), aktif: runner.activeId(),
        tim: team.map(a => ({ id: a.id, nama: a.nama, peran: a.peran, warna: a.warna, ringkas: a.ringkas, alat: a.alat, aktif: a.aktif, profil: a.profil, persona: a.persona, personaTambahan: a.personaTambahan })),
        dokumen: runner.docs().map(d => ({ id: d.id, nama: d.nama, tags: d.tags, ukuran: d.ukuran, diubah: d.diubah })),
        siap: { ai: pub.profiles.some(x => x.ada) && !!settings.forRole('orkestrator'), github: pub.github.ada, repo: tools.repoStatus().ada, db: db.ok },
      });
    }
    if (req.method === 'POST' && p === '/api/pengaturan') {
      const b = await readBody(req, 128 * 1024);
      audit('ubah pengaturan' + (b.profiles ? ' (profil AI)' : '') + (b.github && (b.github.token || b.github.hapusToken) ? ' (token GitHub)' : ''));
      const r = settings.ubah(b);
      if (b.github && (b.github.repo || b.github.base)) syncRepo(true).catch(() => {});
      return json(res, 200, r);
    }
    if (req.method === 'POST' && p === '/api/pengaturan/model') {
      const b = await readBody(req); const old = settings.profile(String(b.id || '')) || {};
      const pr = { provider: ['anthropic', 'gemini', 'openai'].includes(b.provider) ? b.provider : old.provider || 'anthropic',
        baseUrl: /^https:\/\/[a-z0-9.\-]+(:\d+)?(\/[\w.\-\/]*)?$/i.test(String(b.baseUrl || '').trim()) ? String(b.baseUrl).trim().replace(/\/+$/, '') : '',
        key: typeof b.key === 'string' && b.key.trim() ? b.key.replace(/\s+/g, '') : old.key || '' };
      try { return json(res, 200, { ok: true, models: await ai.listModels(pr) }); } catch (e) { return json(res, 200, { ok: false, error: ai.scrub(e.message, pr.key) }); }
    }
    if (req.method === 'POST' && p === '/api/pengaturan/tes-profil') {
      const b = await readBody(req); const pr = settings.profile(String(b.id || ''));
      if (!pr) return json(res, 404, { error: 'Profil tidak ada. Simpan dulu.' });
      try { return json(res, 200, await ai.test(pr)); } catch (e) { return json(res, 200, { ok: false, error: ai.scrub(e.message, pr.key) }); }
    }
    if (req.method === 'POST' && p === '/api/pengaturan/tes-github') {
      const g = settings.get().github;
      if (!g.token) return json(res, 200, { ok: false, error: 'Token belum diisi.' });
      try {
        const r = await fetch(`${ENV.WB_GH_API || 'https://api.github.com'}/repos/${g.repo}`, { headers: { authorization: 'Bearer ' + g.token, accept: 'application/vnd.github+json', 'user-agent': 'marantau-workbench' }, signal: AbortSignal.timeout(15000) });
        const j = await r.json().catch(() => ({}));
        if (!r.ok) return json(res, 200, { ok: false, error: `GitHub ${r.status}: ${String(j.message || '').slice(0, 200)}` });
        const perm = j.permissions || {};
        return json(res, 200, { ok: true, repo: j.full_name, privat: !!j.private, push: !!perm.push, catatan: perm.push ? 'Token bisa membuat branch dan PR.' : 'Token hanya bisa membaca: PR tidak akan bisa dibuat.' });
      } catch (e) { return json(res, 200, { ok: false, error: e.message }); }
    }

    // ----- baca langsung: database -----
    if (req.method === 'POST' && p === '/api/db/query') {
      const b = await readBody(req); audit('db query ' + String(b.sql || '').slice(0, 100).replace(/\s+/g, ' '));
      try { return json(res, 200, await tools.dbQuery(b.sql)); } catch (e) { return json(res, 200, { error: e.message }); }
    }
    if (req.method === 'GET' && p === '/api/db/schema') { try { return json(res, 200, await tools.dbSchema(url.searchParams.get('q'))); } catch (e) { return json(res, 200, { error: e.message }); } }
    if (req.method === 'GET' && p === '/api/db/functions') { try { return json(res, 200, await tools.dbFunctions(url.searchParams.get('q'))); } catch (e) { return json(res, 200, { error: e.message }); } }

    // ----- baca langsung: repo -----
    if (req.method === 'GET' && p === '/api/repo/status') return json(res, 200, tools.repoStatus());
    if (req.method === 'POST' && p === '/api/repo/sync') { try { return json(res, 200, await syncRepo(true)); } catch (e) { return json(res, 200, { error: e.message }); } }
    if (req.method === 'GET' && p === '/api/repo/tree') { try { return json(res, 200, await tools.repoTree(url.searchParams.get('path'))); } catch (e) { return json(res, 200, { error: e.message }); } }
    if (req.method === 'GET' && p === '/api/repo/file') { try { return json(res, 200, await tools.repoRead(url.searchParams.get('path'), url.searchParams.get('range'))); } catch (e) { return json(res, 200, { error: e.message }); } }
    if (req.method === 'GET' && p === '/api/repo/grep') { try { return json(res, 200, await tools.repoGrep(url.searchParams.get('q'), url.searchParams.get('path'))); } catch (e) { return json(res, 200, { error: e.message }); } }

    // ----- baca langsung: server -----
    if (req.method === 'GET' && p === '/api/ops/status') { try { return json(res, 200, { teks: await tools.opsTool('server_status') }); } catch (e) { return json(res, 200, { error: e.message }); } }
    if (req.method === 'GET' && p === '/api/ops/logs') {
      try { return json(res, 200, { teks: await tools.opsTool('logs_tail', { service: String(url.searchParams.get('service') || ''), lines: Math.min(300, +url.searchParams.get('lines') || 100), ...(url.searchParams.get('filter') ? { filter: url.searchParams.get('filter') } : {}) }) }); }
      catch (e) { return json(res, 200, { error: e.message }); }
    }

    // ----- tim & dokumen -----
    if (req.method === 'POST' && p === '/api/tim/impor') { const b = await readBody(req, 600 * 1024); audit('impor persona'); try { return json(res, 200, runner.importAgents(b)); } catch (e) { return json(res, 400, { error: e.message }); } }
    if (req.method === 'POST' && p === '/api/dokumen') { const b = await readBody(req, 600 * 1024); try { const d = runner.saveDoc(b); audit('simpan dokumen ' + d.id); return json(res, 200, { id: d.id, ukuran: d.ukuran }); } catch (e) { return json(res, 400, { error: e.message }); } }
    if (req.method === 'POST' && p === '/api/dokumen/hapus') { const b = await readBody(req); try { runner.delDoc(b.id); audit('hapus dokumen ' + b.id); return json(res, 200, { ok: true }); } catch (e) { return json(res, 400, { error: e.message }); } }
    if (req.method === 'GET' && p === '/api/dokumen') { const d = runner.docs().find(x => x.id === url.searchParams.get('id')); return d ? json(res, 200, d) : json(res, 404, { error: 'Tidak ada.' }); }

    // ----- run -----
    if (req.method === 'GET' && p === '/api/runs') return json(res, 200, { runs: runner.list(), aktif: runner.activeId() });
    if (req.method === 'POST' && p === '/api/runs') {
      const b = await readBody(req, 20 * 1024); audit('run baru');
      try { await syncRepo(false).catch(() => {}); const r = await runner.start(b.prompt, { auto: b.auto === true ? true : b.auto === false ? false : undefined }); return json(res, 200, { id: r.id }); }
      catch (e) { return json(res, 400, { error: e.message }); }
    }
    let m = p.match(/^\/api\/runs\/([a-z0-9]{6,20})(?:\/(\w+))?(?:\/(\d+))?$/);
    if (m) {
      const id = m[1], act = m[2];
      const r = runner.get(id);
      if (!r) return json(res, 404, { error: 'Run tidak ada.' });
      if (req.method === 'GET' && !act) return json(res, 200, { run: publicRun(r, true), hasil: runner.deliverables(id).map(f => ({ path: f.path, tugas: f.tugas, agent: f.agent, ukuran: f.content.length })) });
      if (req.method === 'GET' && act === 'berkas') { const f = runner.deliverables(id).find(x => x.path === url.searchParams.get('path')); return f ? json(res, 200, f) : json(res, 404, { error: 'Berkas tidak ada.' }); }
      if (req.method === 'GET' && act === 'img') {
        const fp = runner.imagePath(id, +m[3]); if (!fp) { res.writeHead(404); return res.end(); }
        res.writeHead(200, { 'Content-Type': /\.jpg$/.test(fp) ? 'image/jpeg' : /\.webp$/.test(fp) ? 'image/webp' : 'image/png', 'Cache-Control': 'private, max-age=3600' }); return res.end(fs.readFileSync(fp));
      }
      try {
        if (req.method === 'POST' && act === 'jawab') { const b = await readBody(req); await runner.answer(id, b.teks); return json(res, 200, { ok: true }); }
        if (req.method === 'POST' && act === 'setujui') { const b = await readBody(req); audit('setujui rencana ' + id); await runner.approve(id, b); return json(res, 200, { ok: true }); }
        if (req.method === 'POST' && act === 'lanjut') { await runner.resume(id); return json(res, 200, { ok: true }); }
        if (req.method === 'POST' && act === 'batal') { runner.cancel(id); return json(res, 200, { ok: true }); }
        if (req.method === 'POST' && act === 'hapus') { runner.remove(id); return json(res, 200, { ok: true }); }
        if (req.method === 'POST' && act === 'pr') {
          const b = await readBody(req, 8 * 1024);
          if (r.status !== 'done') return json(res, 400, { error: 'Run belum selesai.' });
          const pilih = new Set((Array.isArray(b.berkas) ? b.berkas : []).map(String));
          const files = runner.deliverables(id).filter(f => pilih.has(f.path));
          if (!files.length) return json(res, 400, { error: 'Pilih minimal satu berkas.' });
          audit(`buat PR dari run ${id}: ${files.map(f => f.path).join(', ')}`);
          const g = settings.get().github;
          const out = await tools.createPr(g, { title: b.judul || (r.report && r.report.judulPr) || 'Perubahan dari Workbench', body: `${(r.report && r.report.teks) || r.prompt}`, files, runId: id });
          runner.notePr(id, out); return json(res, 200, out);
        }
      } catch (e) { return json(res, 400, { error: ai.scrub(e.message) }); }
    }
    return json(res, 404, { error: 'Tidak ada.' });
  } catch (e) { console.error(p, e.message); json(res, 500, { error: ai.scrub(e.message) }); }
});
server.listen(PORT, () => console.log(`Workbench v${VERSION} di :${PORT}${DEV ? ' (DEV)' : ''}`));
process.on('SIGTERM', () => process.exit(0));
