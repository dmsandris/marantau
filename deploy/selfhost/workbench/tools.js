// Alat baca langsung (tanpa PR): database (read only), salinan repo (git), Panel Ops (MCP lokal).
// Alat tulis hanya satu: membuat branch + PR ke GitHub (createPr), dengan penjagaan jalur dan rahasia.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const { Pool } = require('pg');

const ENV = process.env;
const DATA = ENV.WB_DATA || '/data';
const REPO_DIR = path.join(DATA, 'repo');
const MAX_ROWS = 200;
const GH_API = (ENV.WB_GH_API || 'https://api.github.com').replace(/\/+$/, '');
const GH_GIT = (ENV.WB_GH_GIT || 'https://github.com').replace(/\/+$/, '');

// ---------------- Database (sama ketatnya dengan connector marantau-ops) ----------------
const pool = new Pool({
  host: ENV.OPS_PG_HOST || 'db', port: +(ENV.OPS_PG_PORT || 5432), database: ENV.OPS_PG_DB || 'postgres',
  user: ENV.OPS_PG_USER || 'mt_ops_ro', password: ENV.OPS_PG_PASSWORD || '',
  max: 2, idleTimeoutMillis: 30000, connectionTimeoutMillis: 4000, application_name: 'marantau-workbench',
});
pool.on('error', e => console.error('pg pool:', e.message));
let qSeq = 0;
async function dbQuery(sql) {
  sql = String(sql || '').trim().replace(/;\s*$/, '');
  if (!sql) throw new Error('SQL kosong.');
  if (sql.length > 8000) throw new Error('SQL terlalu panjang (maks 8000 karakter).');
  const c = await pool.connect();
  let broken = false;
  try {
    await c.query('begin read only');
    await c.query("set local statement_timeout = '5s'");
    await c.query("set local idle_in_transaction_session_timeout = '10s'");
    const name = 'wb_q' + (++qSeq); // prepared statement => Postgres menolak lebih dari SATU pernyataan
    if (/^\s*(explain|show)\b/i.test(sql)) {
      const r = await c.query({ name, text: sql });
      return { columns: (r.fields || []).map(f => f.name), rows: r.rows.slice(0, MAX_ROWS), truncated: r.rows.length > MAX_ROWS };
    }
    await c.query({ name, text: `declare wb_cur no scroll cursor for ${sql}` });
    const r = await c.query(`fetch ${MAX_ROWS + 1} from wb_cur`);
    return { columns: (r.fields || []).map(f => f.name), rows: r.rows.slice(0, MAX_ROWS), truncated: r.rows.length > MAX_ROWS };
  } catch (e) {
    if (/syntax error at or near "(declare|;)"/i.test(e.message) || /cannot insert multiple commands/i.test(e.message)) e.message = 'Hanya SATU pernyataan SELECT/WITH/VALUES/EXPLAIN/SHOW. ' + e.message;
    throw e;
  } finally {
    try { await c.query('rollback'); await c.query('deallocate all'); } catch { broken = true; }
    c.release(broken);
  }
}
// Struktur tabel: kata kunci dipisah spasi/koma, dicocokkan ke nama tabel (ATAU). Selalu tanpa salah kurung.
async function dbSchema(q, schema = 'game') {
  const words = String(q || '').toLowerCase().split(/[\s,]+/).map(w => w.replace(/[^a-z0-9_]/g, '')).filter(Boolean).slice(0, 8);
  const pats = words.length ? words.map(w => `%${w}%`) : ['%'];
  const c = await pool.connect();
  try {
    await c.query('begin read only');
    await c.query("set local statement_timeout = '5s'");
    const r = await c.query(
      `select table_name, column_name, data_type, is_nullable, column_default
         from information_schema.columns
        where table_schema = $1 and table_name ilike any($2::text[])
        order by table_name, ordinal_position limit 600`, [schema, pats]);
    const idx = await c.query(
      `select tablename as table_name, indexname, indexdef from pg_indexes
        where schemaname = $1 and tablename ilike any($2::text[]) order by tablename, indexname limit 200`, [schema, pats]);
    const tables = {};
    for (const x of r.rows) (tables[x.table_name] = tables[x.table_name] || { kolom: [], indeks: [] }).kolom.push({ nama: x.column_name, tipe: x.data_type, null: x.is_nullable === 'YES', bawaan: x.column_default });
    for (const x of idx.rows) if (tables[x.table_name]) tables[x.table_name].indeks.push(x.indexdef);
    return { schema, cari: words, tabel: tables, jumlah: Object.keys(tables).length };
  } finally { try { await c.query('rollback'); } catch {} c.release(); }
}
// Fungsi api_* (nama + argumen) untuk memeriksa kontrak RPC.
async function dbFunctions(q) {
  const words = String(q || '').toLowerCase().split(/[\s,]+/).map(w => w.replace(/[^a-z0-9_]/g, '')).filter(Boolean).slice(0, 8);
  const pats = words.length ? words.map(w => `%${w}%`) : ['%'];
  const c = await pool.connect();
  try {
    await c.query('begin read only'); await c.query("set local statement_timeout = '5s'");
    const r = await c.query(
      `select n.nspname as skema, p.proname as nama, pg_get_function_identity_arguments(p.oid) as argumen, pg_get_function_result(p.oid) as hasil
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('public','game') and p.proname ilike any($1::text[]) order by n.nspname, p.proname limit 200`, [pats]);
    return { cari: words, fungsi: r.rows };
  } finally { try { await c.query('rollback'); } catch {} c.release(); }
}

// ---------------- Salinan repo (baca langsung) ----------------
function git(args, opts = {}) {
  return new Promise((resolve, reject) => {
    execFile('git', args, { cwd: opts.cwd || REPO_DIR, timeout: opts.timeout || 60000, maxBuffer: 8 * 1024 * 1024, env: { ...ENV, GIT_TERMINAL_PROMPT: '0', GIT_CONFIG_NOSYSTEM: '1' } },
      (err, stdout, stderr) => err ? reject(new Error((stderr || err.message).toString().slice(0, 400))) : resolve(stdout.toString()));
  });
}
let repoState = { ada: false, repo: '', branch: '', commit: '', pesan: '', tanggal: '', syncAt: 0, error: '' };
let syncing = null;
async function repoSync(repo, branch) {
  if (!/^[\w.\-]+\/[\w.\-]+$/.test(repo) || !/^[\w.\-\/]{1,60}$/.test(branch)) throw new Error('Nama repo/branch tidak valid.');
  if (syncing) return syncing;
  syncing = (async () => {
    try {
      fs.mkdirSync(DATA, { recursive: true });
      const url = `${GH_GIT}/${repo}.git`;
      const has = fs.existsSync(path.join(REPO_DIR, '.git'));
      if (has) {
        const cur = (await git(['remote', 'get-url', 'origin']).catch(() => '')).trim();
        if (cur !== url) { fs.rmSync(REPO_DIR, { recursive: true, force: true }); }
      }
      if (!fs.existsSync(path.join(REPO_DIR, '.git'))) await git(['clone', '--depth', '1', '--single-branch', '--branch', branch, url, REPO_DIR], { cwd: DATA, timeout: 180000 });
      else { await git(['fetch', '--depth', '1', 'origin', branch], { timeout: 120000 }); await git(['reset', '--hard', 'FETCH_HEAD']); }
      const log = (await git(['log', '-1', '--format=%h%x09%cI%x09%s'])).trim().split('\t');
      repoState = { ada: true, repo, branch, commit: log[0], tanggal: log[1], pesan: log[2], syncAt: Date.now(), error: '' };
    } catch (e) { repoState = { ...repoState, error: e.message }; throw e; }
    finally { syncing = null; }
    return repoState;
  })();
  return syncing;
}
function repoStatus() {
  if (!repoState.ada && fs.existsSync(path.join(REPO_DIR, '.git'))) repoState.ada = true; // setelah restart
  return repoState;
}
function safePath(p) {
  p = String(p || '').replace(/\\/g, '/').replace(/^\/+/, '').replace(/\/+$/, '');
  if (p.split('/').some(s => s === '..' || s === '.git') || p.includes('\0')) throw new Error('Jalur tidak valid.');
  return p;
}
async function repoTree(p) {
  p = safePath(p);
  const out = (await git(['ls-tree', '-l', 'HEAD', ...(p ? [p + '/'] : [])])).split('\n').filter(Boolean);
  const items = out.map(l => { const m = l.match(/^(\d+) (\w+) \w+\s+(\S+)\t(.+)$/); return m ? { tipe: m[2] === 'tree' ? 'dir' : 'file', ukuran: m[3] === '-' ? 0 : +m[3], jalur: m[4] } : null; }).filter(Boolean);
  items.sort((a, b) => (a.tipe === b.tipe ? a.jalur.localeCompare(b.jalur) : a.tipe === 'dir' ? -1 : 1));
  return { jalur: p, total: items.length, item: items.slice(0, 400), terpotong: items.length > 400 };
}
async function repoRead(p, range) {
  p = safePath(p);
  const abs = path.join(REPO_DIR, p);
  if (!abs.startsWith(REPO_DIR + path.sep)) throw new Error('Jalur tidak valid.');
  let st; try { st = fs.statSync(abs); } catch { throw new Error('Berkas tidak ada: ' + p); }
  if (st.isDirectory()) throw new Error('Itu folder, pakai repo_tree.');
  if (st.size > 2 * 1024 * 1024) throw new Error('Berkas terlalu besar (>2 MB).');
  const buf = fs.readFileSync(abs);
  if (buf.includes(0)) throw new Error('Berkas biner.');
  const lines = buf.toString('utf8').split('\n');
  let a = 1, b = lines.length;
  const m = String(range || '').match(/^(\d+)?-(\d+)?$/);
  if (m) { a = +m[1] || 1; b = +m[2] || lines.length; }
  let text = lines.slice(a - 1, b).map((l, i) => `${a + i}\t${l}`).join('\n');
  let potong = false;
  if (text.length > 40000) { text = text.slice(0, 40000); potong = true; }
  return { jalur: p, baris: lines.length, dari: a, sampai: Math.min(b, lines.length), potong, teks: text };
}
async function repoGrep(pattern, prefix) {
  pattern = String(pattern || '').slice(0, 200);
  if (!pattern) throw new Error('Pola kosong.');
  const args = ['grep', '-n', '-I', '-i', '-E', '--max-count=8', '-e', pattern, '--'];
  if (prefix) args.push(safePath(prefix));
  let out = '';
  try { out = await git(args); }
  catch (e) { if (/fatal|invalid|unmatched|repetition/i.test(e.message)) throw new Error('Pola regex tidak valid.'); out = ''; } // tanpa kecocokan: git keluar dengan kode 1
  const lines = out.split('\n').filter(Boolean);
  return { pola: pattern, jumlah: lines.length, hasil: lines.slice(0, 80).map(l => l.slice(0, 220)), terpotong: lines.length > 80 };
}

// ---------------- Panel Ops (MCP lokal): status server, log, backup ----------------
async function opsTool(name, args = {}) {
  const token = ENV.OPS_MCP_TOKEN || '';
  if (!token) throw new Error('OPS_MCP_TOKEN tidak diteruskan ke container Workbench.');
  const base = (ENV.WB_OPS_URL || 'http://ops:8080').replace(/\/+$/, '');
  const r = await fetch(`${base}/mcp/${token}`, { method: 'POST', headers: { 'content-type': 'application/json' }, signal: AbortSignal.timeout(20000),
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }) });
  const j = await r.json().catch(() => null);
  if (!j || j.error) throw new Error('Panel Ops menolak: ' + ((j && j.error && j.error.message) || r.status));
  const t = ((j.result || {}).content || []).map(c => c.text).join('\n');
  if (j.result && j.result.isError) throw new Error(t);
  return t;
}

// ---------------- Tulis: branch + PR (satu-satunya jalur ubah repo) ----------------
const DENY_PATH = [/^\.github\//i, /(^|\/)\.env/i, /(^|\/)node_modules\//, /\.(pem|key|p12|pfx)$/i, /^deploy\/selfhost\/volumes\//i];
const SECRET_RE = /(-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_\-]{20,}|AIza[A-Za-z0-9_\-]{35}|sk-[A-Za-z0-9]{40,}|OPS_(PASSWORD|TOTP_SECRET|SESSION_SECRET|MCP_TOKEN)\s*=\s*\S{8,})/;
function checkFiles(files) {
  if (!Array.isArray(files) || !files.length) throw new Error('Tidak ada berkas.');
  if (files.length > 12) throw new Error('Maksimal 12 berkas per PR.');
  const seen = new Set();
  return files.map(f => {
    const p = safePath(f.path);
    if (!p) throw new Error('Jalur berkas kosong.');
    if (seen.has(p)) throw new Error('Jalur ganda: ' + p); seen.add(p);
    if (!/\.(sql|js|mjs|html|css|md|json|yml|yaml|sh|txt)$/i.test(p)) throw new Error('Jenis berkas tidak diizinkan: ' + p);
    for (const re of DENY_PATH) if (re.test(p)) throw new Error('Jalur dilarang untuk Workbench: ' + p);
    const content = String(f.content == null ? '' : f.content);
    if (content.length > 300000) throw new Error('Berkas terlalu besar: ' + p);
    if (SECRET_RE.test(content)) throw new Error('Berkas ' + p + ' berisi pola rahasia (kunci/token/sandi). Ditolak.');
    return { path: p, content };
  });
}
async function gh(token, method, url, body) {
  const r = await fetch(GH_API + url, { method, headers: { authorization: 'Bearer ' + token, accept: 'application/vnd.github+json', 'x-github-api-version': '2022-11-28', 'content-type': 'application/json', 'user-agent': 'marantau-workbench' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30000) });
  const t = await r.text(); let j = null; try { j = JSON.parse(t); } catch {}
  if (!r.ok) throw new Error(`GitHub ${r.status}: ${((j && j.message) || t).toString().replace(token, '[token]').slice(0, 300)}`);
  return j;
}
async function createPr(cfg, { title, body, files, runId }) {
  const { repo, base, token } = cfg;
  if (!token) throw new Error('Token GitHub belum diisi di Pengaturan.');
  const fs_ = checkFiles(files);
  title = String(title || '').replace(/[\r\n]+/g, ' ').trim().slice(0, 120);
  if (!title) throw new Error('Judul PR kosong.');
  const ref = await gh(token, 'GET', `/repos/${repo}/git/ref/heads/${encodeURIComponent(base).replace(/%2F/g, '/')}`);
  const sha = ref.object.sha;
  const branch = `workbench/${(runId || 'run').slice(0, 16)}-${Date.now().toString(36)}`.replace(/[^\w.\-\/]/g, '-');
  if (branch === base) throw new Error('Nama branch bentrok dengan branch dasar.');
  await gh(token, 'POST', `/repos/${repo}/git/refs`, { ref: `refs/heads/${branch}`, sha });
  for (const f of fs_) {
    let exist = null;
    try { exist = await gh(token, 'GET', `/repos/${repo}/contents/${f.path.split('/').map(encodeURIComponent).join('/')}?ref=${encodeURIComponent(branch)}`); } catch (e) { if (!/GitHub 404/.test(e.message)) throw e; }
    await gh(token, 'PUT', `/repos/${repo}/contents/${f.path.split('/').map(encodeURIComponent).join('/')}`, {
      message: `${title}\n\nBerkas: ${f.path}`, content: Buffer.from(f.content, 'utf8').toString('base64'), branch, ...(exist && exist.sha ? { sha: exist.sha } : {}) });
  }
  const pr = await gh(token, 'POST', `/repos/${repo}/pulls`, { title, head: branch, base, body: `${String(body || '').slice(0, 6000)}\n\n---\nDibuat oleh Workbench (run ${runId || '-'}). Tidak otomatis merge: periksa lalu merge sendiri.` });
  return { url: pr.html_url, nomor: pr.number, branch, berkas: fs_.map(f => f.path) };
}

module.exports = { dbQuery, dbSchema, dbFunctions, repoSync, repoStatus, repoTree, repoRead, repoGrep, opsTool, createPr, checkFiles, safePath, REPO_DIR };
