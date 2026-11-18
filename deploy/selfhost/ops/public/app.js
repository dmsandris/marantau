'use strict';
// Panel Ops: inti (login, rute, helper, tab infrastruktur). Tab Ekonomi dan Kapten ada di ekonomi.js.
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const NF = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 0 });
const NF1 = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 1 });
const n0 = v => v == null || isNaN(+v) ? '-' : NF.format(Math.round(+v));
const gb = b => NF1.format(b / 1073741824) + ' GB';
const mb = b => NF.format(Math.round(b / 1048576)) + ' MB';
const fmtTime = t => new Date(t).toLocaleString('id-ID', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
const r1 = v => v == null ? null : Math.round(v * 10) / 10;
const dur = s => { const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return d ? `${d} hari ${h} jam` : h ? `${h} jam ${m} mnt` : `${m} mnt`; };
// Angka gold dipadatkan: 96,3 jt, 2,6 M. Di bawah satu juta ditulis penuh.
const idr = v => {
  if (v == null || isNaN(+v)) return '-';
  const a = Math.abs(+v), s = +v < 0 ? '-' : '';
  if (a >= 1e9) return s + NF1.format(a / 1e9) + ' M';
  if (a >= 1e6) return s + NF1.format(a / 1e6) + ' jt';
  return s + NF.format(Math.round(a));
};
const signed = v => v == null || isNaN(+v) ? '-' : (+v > 0 ? '+' : '') + NF.format(Math.round(+v));

async function api(path, opt = {}) {
  const r = await fetch(path, { ...opt, headers: { 'X-Ops': '1', 'Content-Type': 'application/json', ...(opt.headers || {}) }, credentials: 'same-origin' });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401 && path !== '/api/login') { showLogin(); throw new Error('Belum login'); }
  if (!r.ok) throw new Error(j.error || 'HTTP ' + r.status);
  return j;
}
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden'); clearTimeout(toast.h); toast.h = setTimeout(() => t.classList.add('hidden'), 3500); }

// ---------- keadaan: memuat, kosong, gagal ----------
const skel = el => { el.innerHTML = '<div class="skel" aria-hidden="true"><i></i><i></i><i></i></div>'; el.setAttribute('aria-busy', 'true'); };
const empty = (el, html) => { el.innerHTML = `<div class="empty">${html}</div>`; el.removeAttribute('aria-busy'); };
function showErr(el, msg, retry) {
  el.removeAttribute('aria-busy');
  el.innerHTML = `<div class="errbox" role="alert"><span>Gagal memuat: ${esc(msg)}</span><button type="button" class="btn btn--small">Coba lagi</button></div>`;
  el.querySelector('button').addEventListener('click', () => { skel(el); retry(); });
}
// Jalankan fn; tampilkan kerangka sampai data pertama datang, dan kotak galat bila gagal.
async function load(ids, fn) {
  const els = ids.map(id => typeof id === 'string' ? $(id) : id).filter(Boolean);
  els.forEach(e => { if (!e.dataset.ready) skel(e); });
  try { await fn(); els.forEach(e => { e.dataset.ready = '1'; e.removeAttribute('aria-busy'); }); }
  catch (err) {
    if (err.message === 'Belum login') return;
    els.forEach(e => { if (!e.dataset.ready) showErr(e, err.message, refresh); });
    toast(err.message);
  }
}
// Panjang batang dan persen diatur lewat variabel CSS (CSP melarang atribut style di markup).
function setVars(root) {
  root.querySelectorAll('[data-w]').forEach(e => e.style.setProperty('--w', e.dataset.w));
  root.querySelectorAll('[data-p]').forEach(e => e.style.setProperty('--p', e.dataset.p));
}
function board(cells, n) {
  return `<div class="board" data-n="${n || cells.length}">${cells.map(c => `<div class="cell"${c.level ? ` data-level="${c.level}"` : ''}>
    <div class="k">${c.level ? `<i class="sq" data-level="${c.level}"></i>` : ''}<span>${esc(c.k)}</span></div><div class="v">${esc(c.v)}</div><div class="s">${esc(c.s || '')}</div></div>`).join('')}</div>`;
}
// cols: { h, k, num, q, cls: (row)=>string, f: (row)=>text, sort }
function table(cols, rows, { rowLevel, tall, id } = {}) {
  if (!rows || !rows.length) return '<div class="empty">Tidak ada.</div>';
  return `<div class="tw${tall ? ' tall' : ''}"><table${id ? ` id="${id}"` : ''}><thead><tr>${cols.map(c => `<th scope="col" class="${c.num ? 'num' : ''}"${c.sort ? ` data-k="${esc(c.k)}"` : ''}${c.aria ? ` aria-sort="${c.aria}"` : ''}>${c.sort ? `<button type="button">${esc(c.h)}</button>` : esc(c.h)}</th>`).join('')}</tr></thead><tbody>${rows.map(r =>
    `<tr${rowLevel && rowLevel(r) ? ` data-level="${rowLevel(r)}"` : ''}>${cols.map(c => {
      const v = c.f ? c.f(r) : r[c.k];
      const cls = [c.num ? 'num' : '', c.q ? 'q' : '', c.cls ? c.cls(r) : ''].filter(Boolean).join(' ');
      return `<td class="${cls}">${c.html ? v : esc(v)}</td>`;
    }).join('')}</tr>`).join('')}</tbody></table></div>`;
}
const lvl = (v, w, b) => v == null || isNaN(v) ? '' : v >= b ? 'bad' : v >= w ? 'warn' : 'ok';

// ---------- login ----------
function showLogin() { $('#app').classList.add('hidden'); $('#login').classList.remove('hidden'); $('#pw').focus(); stopTimers(); }
function showApp() { $('#login').classList.add('hidden'); $('#app').classList.remove('hidden'); startTimers(); }
$('#loginForm').addEventListener('submit', async e => {
  e.preventDefault(); $('#loginErr').textContent = '';
  const btn = e.submitter; btn.disabled = true;
  try {
    await api('/api/login', { method: 'POST', body: JSON.stringify({ password: $('#pw').value, code: $('#code').value }) });
    $('#pw').value = ''; $('#code').value = ''; showApp();
  } catch (err) { $('#loginErr').textContent = err.message; $('#pw').focus(); }
  btn.disabled = false;
});
$('#logout').addEventListener('click', async () => { await api('/api/logout', { method: 'POST' }).catch(() => {}); showLogin(); });

// ---------- rute: tab disimpan di URL (#/ekonomi) ----------
const TABS = ['server', 'layanan', 'db', 'backup', 'debug', 'ekonomi', 'kapten'];
const TITLES = { server: 'Server', layanan: 'Layanan', db: 'Database', backup: 'Backup', debug: 'Debug', ekonomi: 'Ekonomi', kapten: 'Kapten' };
const loaders = {}; // diisi ekonomi.js
let tab = 'server';
function routeTab() { const h = location.hash.replace(/^#\/?/, ''); return TABS.includes(h) ? h : 'server'; }
function applyTab() {
  tab = routeTab();
  $$('#tabs .tab').forEach(a => { if (a.dataset.tab === tab) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current'); });
  $$('main section[data-panel]').forEach(s => s.classList.toggle('hidden', s.dataset.panel !== tab));
  document.title = `${TITLES[tab]} - Marantau Ops`;
  const cur = $(`#tabs .tab[data-tab="${tab}"]`); if (cur && cur.scrollIntoView) cur.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  refresh();
}
window.addEventListener('hashchange', () => { if (!$('#app').classList.contains('hidden')) applyTab(); });

// ---------- Server ----------
let hours = 24;
$$('#range button').forEach(b => b.addEventListener('click', () => {
  hours = +b.dataset.h; $$('#range button').forEach(x => x.setAttribute('aria-pressed', String(x === b))); loadCharts().catch(e => toast(e.message));
}));
async function loadServer() {
  const o = await api('/api/overview');
  const h = o.host;
  const memPct = h.memTotal ? 100 * h.memUsed / h.memTotal : null, diskPct = h.diskTotal ? 100 * h.diskUsed / h.diskTotal : null;
  $('#hostCards').innerHTML = board([
    { k: 'CPU', v: h.cpu == null ? '...' : r1(h.cpu) + '%', s: `${h.cores} core, load ${r1(h.load) ?? '-'}`, level: lvl(h.cpu, 70, 90) },
    { k: 'IOwait', v: h.iow == null ? '...' : r1(h.iow) + '%', s: h.steal ? `steal ${r1(h.steal)}%` : 'menunggu disk', level: lvl(h.iow, 10, 30) },
    { k: 'RAM', v: memPct == null ? '-' : Math.round(memPct) + '%', s: `${gb(h.memUsed)} dari ${gb(h.memTotal)}`, level: lvl(memPct, 75, 85) },
    { k: 'Swap', v: mb(h.swapUsed), s: `dari ${mb(h.swapTotal)}`, level: h.swapUsed > 200 * 1048576 ? 'bad' : h.swapUsed > 50 * 1048576 ? 'warn' : 'ok' },
    { k: 'Disk', v: diskPct == null ? '-' : Math.round(diskPct) + '%', s: `${gb(h.diskUsed)} dari ${gb(h.diskTotal)}`, level: lvl(diskPct, 70, 80) },
    { k: 'Uptime', v: dur(h.uptimeSec), s: o.telegram ? 'Telegram aktif' : 'Telegram belum diatur' },
  ], 6);
  renderServices(o.services, o.stats);
}
function chart(title, pts, key, { max, unit = '', limit } = {}) {
  const W = 400, H = 140, P = 4;
  const vals = pts.map(p => p[key]).filter(v => v != null);
  const top = max ?? Math.max(1, ...vals) * 1.15;
  const last = vals.length ? r1(vals[vals.length - 1]) : null;
  const peak = vals.length ? r1(Math.max(...vals)) : null;
  if (pts.length < 2) return `<div class="chart"><h3>${esc(title)}</h3><p class="cap">belum ada data</p><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(title)}, belum ada data"></svg></div>`;
  const t0 = pts[0].t, t1 = pts[pts.length - 1].t;
  const x = t => P + (W - 2 * P) * (t - t0) / Math.max(1, t1 - t0);
  const y = v => H - P - (H - 2 * P) * Math.min(v, top) / top;
  let d = '', started = false;
  for (const p of pts) { if (p[key] == null) { started = false; continue; } d += (started ? 'L' : 'M') + x(p.t).toFixed(1) + ' ' + y(p[key]).toFixed(1); started = true; }
  const first = pts.find(p => p[key] != null), lastP = [...pts].reverse().find(p => p[key] != null);
  const area = first ? `${d}L${x(lastP.t).toFixed(1)} ${H - P}L${x(first.t).toFixed(1)} ${H - P}Z` : '';
  const grid = [0.25, 0.5, 0.75].map(f => `<line class="c-grid" x1="0" x2="${W}" y1="${y(top * f)}" y2="${y(top * f)}"/>`).join('');
  const lim = limit != null && limit < top ? `<line class="c-lim" x1="0" x2="${W}" y1="${y(limit)}" y2="${y(limit)}"/>` : '';
  return `<div class="chart"><h3>${esc(title)}</h3><p class="cap">kini ${last ?? '-'}${unit}, puncak ${peak ?? '-'}${unit}</p>
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="${esc(title)}: kini ${last ?? '-'}${unit}, puncak ${peak ?? '-'}${unit}">${grid}${lim}<path class="c-area" d="${area}"/><path class="c-line" d="${d}"/></svg>
    <div class="axis"><span>${fmtTime(t0)}</span><span>${fmtTime(t1)}</span></div></div>`;
}
async function loadCharts() {
  const m = await api('/api/metrics?hours=' + hours);
  const p = m.points;
  $('#charts').innerHTML = [
    chart('CPU', p, 'cpu', { max: 100, unit: '%', limit: 90 }),
    chart('IOwait, puncak', p, 'iow', { unit: '%', limit: 30 }),
    chart('RAM, puncak', p, 'mem', { max: 100, unit: '%', limit: 85 }),
    chart('Swap terpakai', p, 'swapMb', { unit: ' MB', limit: 200 }),
    chart('Load 1 menit', p, 'load', { limit: 2 }),
    chart('Disk', p, 'disk', { max: 100, unit: '%', limit: 80 }),
  ].join('');
}
async function loadHttp() {
  const r = await api('/api/http');
  if (r.error) { $('#httpBox').innerHTML = `<div class="errbox" role="alert"><span>Log Caddy tidak terbaca: ${esc(r.error)}</span></div>`; return; }
  const hrs = Object.entries(r.perHour || {}).sort().slice(-6).map(([h, n]) => `${h.slice(11)}:00 sebanyak ${n}`).join(', ');
  $('#httpBox').innerHTML = board([
    { k: 'Permintaan', v: n0(r.total), s: '24 jam terakhir' },
    { k: 'Error 5xx', v: n0(r.err), s: hrs ? `jam UTC: ${hrs}` : 'tidak ada', level: r.err ? (r.err >= 20 ? 'bad' : 'warn') : 'ok' },
  ], 4);
}

// ---------- Layanan ----------
function renderServices(sv, stats = {}) {
  if (sv.error) { $('#svcList').innerHTML = `<div class="errbox" role="alert"><span>Docker tidak terbaca: ${esc(sv.error)}</span></div>`; return; }
  $('#svcList').innerHTML = `<div class="rows">${sv.items.map(s => {
    const st = s.state === 'running' ? (s.health === 'unhealthy' ? 'bad' : s.health === 'starting' ? 'warn' : 'ok') : 'bad';
    const word = st === 'ok' ? 'sehat' : st === 'warn' ? 'memulai' : (s.state === 'running' ? 'tidak sehat' : esc(s.state));
    const mem = stats[s.name] ? `RAM ${stats[s.name].memMb} MB` : '';
    return `<div class="svc"><i class="sq" data-level="${st}" aria-hidden="true"></i><span class="name">${esc(s.label)} <span class="muted">${word}</span></span>
      <span class="meta">${esc(s.status || s.state)}${mem ? ', ' + esc(mem) : ''}<br>${esc(s.image || '')}</span>
      <span class="acts"><button type="button" class="btn btn--small" data-log="${esc(s.name)}">Log</button>
      <button type="button" class="btn btn--small ${s.risky ? 'btn--danger' : ''}" data-restart="${esc(s.name)}" data-label="${esc(s.label)}" data-risky="${s.risky ? 1 : ''}">Restart</button></span></div>`;
  }).join('')}</div>`;
}
$('#svcList').addEventListener('click', async e => {
  const b = e.target.closest('button'); if (!b) return;
  if (b.dataset.log) {
    $('#logBox').classList.remove('hidden'); $('#logTitle').textContent = 'Log ' + b.dataset.log; $('#logText').textContent = 'Memuat...';
    try { const r = await api('/api/logs?name=' + encodeURIComponent(b.dataset.log)); $('#logText').textContent = r.text || '(kosong)'; $('#logText').scrollTop = 1e9; }
    catch (err) { $('#logText').textContent = err.message; }
  }
  if (b.dataset.restart) {
    const warn = b.dataset.risky ? '\n\nPERHATIAN: Postgres restart = semua pemain terputus ±10–30 detik.' : '';
    if (!confirm(`Restart ${b.dataset.label}?${warn}`)) return;
    b.disabled = true;
    try { const r = await api('/api/restart', { method: 'POST', body: JSON.stringify({ name: b.dataset.restart }) }); toast(r.note || `${b.dataset.label} di-restart.`); }
    catch (err) { toast('Gagal: ' + err.message); }
    b.disabled = false; setTimeout(refresh, 2000);
  }
});
$('#logClose').addEventListener('click', () => $('#logBox').classList.add('hidden'));

// ---------- Database ----------
async function loadDb() {
  const d = await api('/api/db');
  const total = (d.conns || []).reduce((a, c) => a + c.n, 0);
  $('#dbCards').innerHTML = board([
    { k: 'Pemain online', v: n0(d.online), s: '2 menit terakhir' },
    { k: 'Koneksi', v: `${total} / ${d.maxConn ?? '?'}`, s: 'semua role', level: lvl(total / (d.maxConn || 60) * 100, 60, 85) },
    { k: 'Kunci menunggu', v: n0(d.waitingLocks), s: 'pg_locks', level: d.waitingLocks > 5 ? 'bad' : d.waitingLocks > 0 ? 'warn' : 'ok' },
    { k: 'Ukuran database', v: d.size ?? '-', s: 'postgres' },
  ], 4) + (d.errors ? `<div class="errbox" role="alert"><span>${esc(Object.entries(d.errors).map(([k, v]) => k + ': ' + v).join(', '))}</span></div>` : '');
  $('#dbSlow').innerHTML = table([{ h: 'Endpoint atau query', k: 'q', q: 1 }, { h: 'Panggilan', k: 'calls', num: 1, f: r => n0(r.calls) }, { h: 'Rata-rata ms', k: 'mean_ms', num: 1, f: r => n0(r.mean_ms) }, { h: 'Maks ms', k: 'max_ms', num: 1, f: r => n0(r.max_ms) }, { h: 'Total detik', k: 'total_s', num: 1, f: r => n0(r.total_s) }], d.slow, { rowLevel: r => r.mean_ms > 1000 ? 'bad' : '' });
  $('#dbLong').innerHTML = (d.longTx || []).length ? table([{ h: 'PID', k: 'pid', num: 1 }, { h: 'Role', k: 'role' }, { h: 'State', k: 'state' }, { h: 'Detik', k: 'sec', num: 1 }, { h: 'Query', k: 'query', q: 1 }], d.longTx) : '<div class="empty"><b>Tidak ada.</b> Tidak ada transaksi yang berjalan lebih dari 10 detik.</div>';
  $('#dbConns').innerHTML = table([{ h: 'Role', k: 'role' }, { h: 'State', k: 'state' }, { h: 'Jumlah', k: 'n', num: 1 }], d.conns);
  $('#dbTables').innerHTML = table([{ h: 'Tabel', k: 'name' }, { h: 'Ukuran', k: 'size', num: 1 }, { h: 'Baris (perkiraan)', k: 'rows_est', num: 1, f: r => n0(r.rows_est) }], d.tables);
}

// ---------- Backup ----------
const ago = iso => { if (!iso) return '-'; const m = Math.round((Date.now() - Date.parse(iso)) / 60000); return m < 60 ? `${m} menit lalu` : m < 2880 ? `${Math.round(m / 60)} jam lalu` : `${Math.round(m / 1440)} hari lalu`; };
async function loadBackup() {
  const [b, o] = await Promise.all([api('/api/backup'), api('/api/overview')]);
  const s = b.status || {};
  const running = s.running || (b.pending || []).join(', ');
  const okAge = s.lastOk ? (Date.now() - Date.parse(s.lastOk)) / 3600e3 : null;
  $('#bkStatus').innerHTML = !b.status && b.note ? `<div class="empty">${esc(b.note)}</div>` : `<dl class="kv">
    <div><dt>Terakhir berhasil</dt><dd class="${okAge == null || okAge > 30 ? 'bad' : ''}">${esc(s.lastOk ? fmtTime(s.lastOk) : 'belum pernah')}</dd><dd class="s">${esc(ago(s.lastOk))}</dd></div>
    <div><dt>Hasil terakhir</dt><dd class="${s.lastResult === 'gagal' ? 'bad' : ''}">${esc(s.lastResult || '-')}</dd><dd class="s">${esc(s.lastError || '')}</dd></div>
    <div><dt>Ukuran dan isi</dt><dd>${esc(s.size || '-')}</dd><dd class="s">${esc(s.tables || '-')} tabel, ${esc(s.rows || '-')} baris, Realtime ${esc(s.realtimePolicies ?? '-')} kebijakan</dd></div>
    <div><dt>Tes restore</dt><dd class="${s.restoreTest === 'GAGAL' ? 'bad' : ''}">${esc(s.restoreTest || 'belum')}</dd><dd class="s">${esc(s.restoreAt ? fmtTime(s.restoreAt) : '')}</dd></div>
    <div><dt>Google Drive</dt><dd>${esc(s.driveFiles ?? '-')} file</dd><dd class="s">folder vps, simpan 30 hari</dd></div>
    <div><dt>Sedang berjalan</dt><dd>${esc(running || 'tidak ada')}</dd><dd class="s">jadwal 03:47 WIB, tes Minggu 04:20</dd></div>
  </dl>${s.restoreNote ? `<p class="note">${esc(s.restoreNote)}</p>` : ''}`;
  $('#bkRun').disabled = $('#bkTest').disabled = !!running;
  $('#bkFiles').innerHTML = table([{ h: 'Berkas lokal (7 hari)', k: 'name' }, { h: 'Ukuran', k: 'sz', num: 1 }, { h: 'Waktu', k: 'tm', num: 1 }],
    b.files.filter(f => f.name !== 'status.json').map(f => ({ ...f, sz: mb(f.size), tm: fmtTime(f.mtime) })));
  $('#tgState').textContent = o.telegram ? 'Aktif: RAM di atas 85%, swap, disk di atas 80%, IOwait, layanan mati, backup basi atau gagal, lonjakan 5xx.' : 'Belum diatur. Jalankan di VM: sh /opt/marantau/selfhost/set-telegram.sh';
  $('#tgTest').disabled = !o.telegram;
  if (running) setTimeout(() => { if (tab === 'backup') loadBackup().catch(() => {}); }, 10000);
}
async function runBackup(kind, label) {
  if (!confirm(`${label}? Proses berjalan di latar belakang (±1–5 menit).`)) return;
  try { await api('/api/backup/run', { method: 'POST', body: JSON.stringify({ kind }) }); toast(`${label} dimulai.`); setTimeout(() => loadBackup().catch(e => toast(e.message)), 3000); }
  catch (e) { toast(e.message); }
}
$('#bkRun').addEventListener('click', () => runBackup('backup', 'Backup sekarang'));
$('#bkTest').addEventListener('click', () => runBackup('restore-test', 'Backup + tes restore'));
$('#tgTest').addEventListener('click', async () => { try { await api('/api/telegram-test', { method: 'POST' }); toast('Pesan tes terkirim.'); } catch (e) { toast(e.message); } });

// ---------- Debug ----------
let dbgText = '';
$('#dbgMake').addEventListener('click', async () => {
  const b = $('#dbgMake'); b.disabled = true; b.textContent = 'Menyusun...';
  try {
    dbgText = (await api('/api/debug')).text;
    $('#dbgText').textContent = dbgText; $('#dbgText').classList.remove('hidden');
    $('#dbgCopy').disabled = $('#dbgSave').disabled = false;
  } catch (e) { toast(e.message); }
  b.disabled = false; b.textContent = 'Buat laporan';
});
$('#dbgCopy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(dbgText); toast('Laporan tersalin. Tempel ke chat Claude.'); }
  catch { const r = document.createRange(); r.selectNodeContents($('#dbgText')); getSelection().removeAllRanges(); getSelection().addRange(r); toast('Tekan Ctrl+C untuk menyalin.'); }
});
$('#dbgSave').addEventListener('click', () => {
  const d = new Date(), z = n => String(n).padStart(2, '0');
  const name = `marantau-debug-${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}-${z(d.getHours())}${z(d.getMinutes())}.txt`;
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([dbgText], { type: 'text/plain' })); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});

// ---------- refresh ----------
async function refresh() {
  try {
    if (tab === 'server') await Promise.all([
      load(['#hostCards'], loadServer), load(['#charts'], loadCharts), load(['#httpBox'], loadHttp)]);
    if (tab === 'layanan') await load(['#svcList'], loadServer);
    if (tab === 'db') await load(['#dbCards', '#dbSlow', '#dbLong', '#dbConns', '#dbTables'], loadDb);
    if (tab === 'backup') await load(['#bkStatus', '#bkFiles'], loadBackup);
    if (loaders[tab]) await loaders[tab]();
    // tab debug: laporan hanya dibuat saat tombol ditekan
  } catch (e) { if (e.message !== 'Belum login') toast(e.message); }
}
let timers = [];
function startTimers() {
  stopTimers(); applyTab();
  timers.push(setInterval(() => { if (!document.hidden && tab !== 'backup' && tab !== 'debug') refresh(); }, 30000));
  timers.push(setInterval(() => { $('#clock').textContent = new Date().toLocaleTimeString('id-ID'); }, 1000));
}
function stopTimers() { timers.forEach(clearInterval); timers = []; }

window.OPS = { $, $$, esc, n0, idr, signed, r1, api, toast, board, table, load, skel, empty, showErr, setVars, loaders, lvl, refresh, NF1 };
api('/api/me').then(r => r.authed ? showApp() : showLogin()).catch(showLogin);
