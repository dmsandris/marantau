'use strict';
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const gb = b => (b / 1073741824).toFixed(1) + ' GB';
const mb = b => Math.round(b / 1048576) + ' MB';
const fmtTime = t => new Date(t).toLocaleString('id-ID', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
const r1 = v => v == null ? null : Math.round(v * 10) / 10;
const dur = s => { const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return d ? `${d}h ${h}j` : h ? `${h}j ${m}m` : `${m}m`; };

async function api(path, opt = {}) {
  const r = await fetch(path, { ...opt, headers: { 'X-Ops': '1', 'Content-Type': 'application/json', ...(opt.headers || {}) }, credentials: 'same-origin' });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401 && path !== '/api/login') { showLogin(); throw new Error('Belum login'); }
  if (!r.ok) throw new Error(j.error || 'HTTP ' + r.status);
  return j;
}
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden'); clearTimeout(toast.h); toast.h = setTimeout(() => t.classList.add('hidden'), 3500); }

// ---------- login ----------
function showLogin() { $('#app').classList.add('hidden'); $('#login').classList.remove('hidden'); $('#pw').focus(); stopTimers(); }
function showApp() { $('#login').classList.add('hidden'); $('#app').classList.remove('hidden'); startTimers(); }
$('#loginForm').addEventListener('submit', async e => {
  e.preventDefault(); $('#loginErr').textContent = '';
  const btn = e.submitter; btn.disabled = true;
  try {
    await api('/api/login', { method: 'POST', body: JSON.stringify({ password: $('#pw').value, code: $('#code').value }) });
    $('#pw').value = ''; $('#code').value = ''; showApp();
  } catch (err) { $('#loginErr').textContent = err.message; }
  btn.disabled = false;
});
$('#logout').addEventListener('click', async () => { await api('/api/logout', { method: 'POST' }).catch(() => {}); showLogin(); });

// ---------- tab ----------
let tab = 'server';
$$('#tabs button').forEach(b => b.addEventListener('click', () => {
  tab = b.dataset.tab;
  $$('#tabs button').forEach(x => x.classList.toggle('on', x === b));
  $$('main section').forEach(s => s.classList.toggle('hidden', s.dataset.panel !== tab));
  refresh();
}));

// ---------- Server ----------
let hours = 24;
$$('#range button').forEach(b => b.addEventListener('click', () => {
  hours = +b.dataset.h; $$('#range button').forEach(x => x.classList.toggle('on', x === b)); loadCharts();
}));
function stat(k, v, s, level) { return `<div class="card stat ${level || ''}"><div class="k">${esc(k)}</div><div class="v">${esc(v)}</div><div class="s">${esc(s || '')}</div></div>`; }
const lvl = (v, w, b) => v == null ? '' : v >= b ? 'bad' : v >= w ? 'warn' : 'ok';
async function loadServer() {
  const o = await api('/api/overview');
  const h = o.host;
  $('#hostCards').innerHTML = [
    stat('CPU', h.cpu == null ? '…' : r1(h.cpu) + '%', `${h.cores} core · load ${r1(h.load) ?? '-'}`, lvl(h.cpu, 70, 90)),
    stat('IOwait', h.iow == null ? '…' : r1(h.iow) + '%', h.steal ? `steal ${r1(h.steal)}%` : 'tunggu disk', lvl(h.iow, 10, 30)),
    stat('RAM', h.memTotal ? Math.round(100 * h.memUsed / h.memTotal) + '%' : '-', `${gb(h.memUsed)} / ${gb(h.memTotal)}`, lvl(100 * h.memUsed / h.memTotal, 75, 85)),
    stat('Swap', mb(h.swapUsed), `dari ${mb(h.swapTotal)}`, h.swapUsed > 200 * 1048576 ? 'bad' : h.swapUsed > 50 * 1048576 ? 'warn' : 'ok'),
    stat('Disk', h.diskTotal ? Math.round(100 * h.diskUsed / h.diskTotal) + '%' : '-', `${gb(h.diskUsed)} / ${gb(h.diskTotal)}`, lvl(100 * h.diskUsed / h.diskTotal, 70, 80)),
    stat('Uptime', dur(h.uptimeSec), o.telegram ? 'Telegram aktif' : 'Telegram belum diatur'),
  ].join('');
  renderServices(o.services, o.stats);
}
function chart(title, pts, key, { max, unit = '', limit } = {}) {
  const W = 400, H = 120, P = 4;
  const vals = pts.map(p => p[key]).filter(v => v != null);
  const top = max ?? Math.max(1, ...vals) * 1.15;
  const last = vals.length ? r1(vals[vals.length - 1]) : null;
  const peak = vals.length ? r1(Math.max(...vals)) : null;
  if (pts.length < 2) return `<div class="card chart"><h3>${esc(title)}<span>belum ada data</span></h3><svg viewBox="0 0 ${W} ${H}"></svg></div>`;
  const t0 = pts[0].t, t1 = pts[pts.length - 1].t;
  const x = t => P + (W - 2 * P) * (t - t0) / Math.max(1, t1 - t0);
  const y = v => H - P - (H - 2 * P) * Math.min(v, top) / top;
  let d = '', started = false;
  for (const p of pts) { if (p[key] == null) { started = false; continue; } d += (started ? 'L' : 'M') + x(p.t).toFixed(1) + ' ' + y(p[key]).toFixed(1); started = true; }
  const first = pts.find(p => p[key] != null), lastP = [...pts].reverse().find(p => p[key] != null);
  const area = first ? `${d}L${x(lastP.t).toFixed(1)} ${H - P}L${x(first.t).toFixed(1)} ${H - P}Z` : '';
  const grid = [0.25, 0.5, 0.75].map(f => `<line class="grid" x1="0" x2="${W}" y1="${y(top * f)}" y2="${y(top * f)}"/>`).join('');
  const lim = limit != null && limit < top ? `<line class="lim" x1="0" x2="${W}" y1="${y(limit)}" y2="${y(limit)}"/>` : '';
  return `<div class="card chart"><h3>${esc(title)}<span>kini ${last ?? '-'}${unit} · puncak ${peak ?? '-'}${unit}</span></h3>
    <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${grid}${lim}<path class="area" d="${area}"/><path class="line" d="${d}"/></svg>
    <div class="row muted small"><span>${fmtTime(t0)}</span><span>${fmtTime(t1)}</span></div></div>`;
}
async function loadCharts() {
  const m = await api('/api/metrics?hours=' + hours);
  const p = m.points;
  $('#charts').innerHTML = [
    chart('CPU', p, 'cpu', { max: 100, unit: '%', limit: 90 }),
    chart('IOwait (puncak)', p, 'iow', { unit: '%', limit: 30 }),
    chart('RAM (puncak)', p, 'mem', { max: 100, unit: '%', limit: 85 }),
    chart('Swap terpakai', p, 'swapMb', { unit: ' MB', limit: 200 }),
    chart('Load 1 menit', p, 'load', { limit: 2 }),
    chart('Disk', p, 'disk', { max: 100, unit: '%', limit: 80 }),
  ].join('');
}
async function loadHttp() {
  const r = await api('/api/http');
  if (r.error) { $('#httpBox').textContent = 'Log Caddy tidak terbaca: ' + r.error; return; }
  const hrs = Object.entries(r.perHour || {}).sort().slice(-6).map(([h, n]) => `${h.slice(11)}:00 → ${n}`).join(' · ');
  $('#httpBox').innerHTML = `${r.total.toLocaleString('id-ID')} permintaan · <b class="${r.err ? 'err' : ''}">${r.err} error 5xx</b>${hrs ? '<br><span class="muted">Jam dengan 5xx (UTC): ' + esc(hrs) + '</span>' : ''}`;
}

// ---------- Layanan ----------
function renderServices(sv, stats = {}) {
  if (sv.error) { $('#svcList').innerHTML = `<div class="card err">Docker tidak terbaca: ${esc(sv.error)}</div>`; return; }
  $('#svcList').innerHTML = sv.items.map(s => {
    const st = s.state === 'running' ? (s.health === 'unhealthy' ? 'bad' : s.health === 'starting' ? 'warn' : 'ok') : 'bad';
    const mem = stats[s.name] ? ` · RAM ${stats[s.name].memMb} MB` : '';
    return `<div class="card svc"><span class="dot ${st}"></span><span class="name">${esc(s.label)}</span>
      <span class="meta">${esc(s.status || s.state)}${mem}<br>${esc(s.image || '')}</span>
      <button class="ghost" data-log="${esc(s.name)}">Log</button>
      <button class="${s.risky ? 'danger' : ''}" data-restart="${esc(s.name)}" data-label="${esc(s.label)}" data-risky="${s.risky ? 1 : ''}">Restart</button></div>`;
  }).join('');
}
$('#svcList').addEventListener('click', async e => {
  const b = e.target.closest('button'); if (!b) return;
  if (b.dataset.log) {
    $('#logBox').classList.remove('hidden'); $('#logTitle').textContent = 'Log ' + b.dataset.log; $('#logText').textContent = 'Memuat…';
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
function table(cols, rows, rowClass) {
  if (!rows || !rows.length) return '<p class="muted">Tidak ada.</p>';
  return `<table><tr>${cols.map(c => `<th class="${c.num ? 'num' : ''}">${esc(c.h)}</th>`).join('')}</tr>${rows.map(r =>
    `<tr class="${rowClass ? rowClass(r) : ''}">${cols.map(c => `<td class="${c.num ? 'num' : ''} ${c.q ? 'q' : ''}">${esc(r[c.k])}</td>`).join('')}</tr>`).join('')}</table>`;
}
async function loadDb() {
  const d = await api('/api/db');
  const total = (d.conns || []).reduce((a, c) => a + c.n, 0);
  $('#dbCards').innerHTML = [
    stat('Pemain online', d.online ?? '-', '2 menit terakhir'),
    stat('Koneksi', `${total} / ${d.maxConn ?? '?'}`, 'semua role', lvl(total / (d.maxConn || 60) * 100, 60, 85)),
    stat('Kunci menunggu', d.waitingLocks ?? '-', 'pg_locks', d.waitingLocks > 5 ? 'bad' : d.waitingLocks > 0 ? 'warn' : 'ok'),
    stat('Ukuran DB', d.size ?? '-', 'postgres'),
  ].join('') + (d.errors ? `<div class="card err">${esc(Object.entries(d.errors).map(([k, v]) => k + ': ' + v).join(' · '))}</div>` : '');
  $('#dbSlow').innerHTML = table([{ h: 'Endpoint / query', k: 'q', q: 1 }, { h: 'Panggilan', k: 'calls', num: 1 }, { h: 'Rata² ms', k: 'mean_ms', num: 1 }, { h: 'Maks ms', k: 'max_ms', num: 1 }, { h: 'Total dtk', k: 'total_s', num: 1 }], d.slow, r => r.mean_ms > 1000 ? 'bad' : '');
  $('#dbLong').innerHTML = table([{ h: 'PID', k: 'pid', num: 1 }, { h: 'Role', k: 'role' }, { h: 'State', k: 'state' }, { h: 'Detik', k: 'sec', num: 1 }, { h: 'Query', k: 'query', q: 1 }], d.longTx);
  $('#dbConns').innerHTML = table([{ h: 'Role', k: 'role' }, { h: 'State', k: 'state' }, { h: 'Jumlah', k: 'n', num: 1 }], d.conns);
  $('#dbTables').innerHTML = table([{ h: 'Tabel', k: 'name' }, { h: 'Ukuran', k: 'size', num: 1 }, { h: 'Baris (perkiraan)', k: 'rows_est', num: 1 }], d.tables);
}

// ---------- Backup ----------
const ago = iso => { if (!iso) return '-'; const m = Math.round((Date.now() - Date.parse(iso)) / 60000); return m < 60 ? `${m} menit lalu` : m < 2880 ? `${Math.round(m / 60)} jam lalu` : `${Math.round(m / 1440)} hari lalu`; };
async function loadBackup() {
  const [b, o] = await Promise.all([api('/api/backup'), api('/api/overview')]);
  const s = b.status || {};
  const running = s.running || (b.pending || []).join(', ');
  const okAge = s.lastOk ? (Date.now() - Date.parse(s.lastOk)) / 3600e3 : null;
  $('#bkStatus').innerHTML = !b.status && b.note ? `<span class="muted">${esc(b.note)}</span>` : `<div class="bk-grid">
    <div><span class="muted">Terakhir berhasil</span><b class="${okAge == null || okAge > 30 ? 'err' : ''}">${esc(s.lastOk ? fmtTime(s.lastOk) : 'belum pernah')}</b><span class="muted">${esc(ago(s.lastOk))}</span></div>
    <div><span class="muted">Hasil terakhir</span><b class="${s.lastResult === 'gagal' ? 'err' : ''}">${esc(s.lastResult || '-')}</b><span class="muted">${esc(s.lastError || '')}</span></div>
    <div><span class="muted">Ukuran / isi</span><b>${esc(s.size || '-')}</b><span class="muted">${esc(s.tables || '-')} tabel · ${esc(s.rows || '-')} baris · Realtime ${esc(s.realtimePolicies ?? '-')} kebijakan</span></div>
    <div><span class="muted">Tes restore</span><b class="${s.restoreTest === 'GAGAL' ? 'err' : ''}">${esc(s.restoreTest || 'belum')}</b><span class="muted">${esc(s.restoreAt ? fmtTime(s.restoreAt) : '')}</span></div>
    <div><span class="muted">Google Drive</span><b>${esc(s.driveFiles ?? '-')} file</b><span class="muted">vps/ · simpan 30 hari</span></div>
    <div><span class="muted">Sedang berjalan</span><b>${esc(running || 'tidak')}</b><span class="muted">jadwal 03:47 WIB · tes Minggu 04:20</span></div>
  </div>${s.restoreNote ? `<p class="muted">${esc(s.restoreNote)}</p>` : ''}`;
  $('#bkRun').disabled = $('#bkTest').disabled = !!running;
  $('#bkFiles').innerHTML = table([{ h: 'Berkas lokal (7 hari)', k: 'name' }, { h: 'Ukuran', k: 'sz', num: 1 }, { h: 'Waktu', k: 'tm' }],
    b.files.filter(f => f.name !== 'status.json').map(f => ({ ...f, sz: mb(f.size), tm: fmtTime(f.mtime) })));
  $('#tgState').textContent = o.telegram ? 'Aktif: RAM > 85%, swap, disk > 80%, IOwait, layanan mati, backup basi/gagal, lonjakan 5xx.' : 'Belum diatur. Jalankan di VM: sh /opt/marantau/selfhost/set-telegram.sh';
  $('#tgTest').disabled = !o.telegram;
  if (running) setTimeout(() => { if (tab === 'backup') loadBackup().catch(() => {}); }, 10000);
}
async function runBackup(kind, label) {
  if (!confirm(`${label}? Proses berjalan di latar belakang (±1–5 menit).`)) return;
  try { await api('/api/backup/run', { method: 'POST', body: JSON.stringify({ kind }) }); toast(`${label} dimulai.`); setTimeout(loadBackup, 3000); }
  catch (e) { toast(e.message); }
}
$('#bkRun').addEventListener('click', () => runBackup('backup', 'Backup sekarang'));
$('#bkTest').addEventListener('click', () => runBackup('restore-test', 'Backup + tes restore'));
$('#tgTest').addEventListener('click', async () => { try { await api('/api/telegram-test', { method: 'POST' }); toast('Pesan tes terkirim.'); } catch (e) { toast(e.message); } });

// ---------- Debug ----------
let dbgText = '';
$('#dbgMake').addEventListener('click', async () => {
  const b = $('#dbgMake'); b.disabled = true; b.textContent = 'Menyusun…';
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
    if (tab === 'server') await Promise.all([loadServer(), loadCharts(), loadHttp()]);
    if (tab === 'layanan') await loadServer();
    if (tab === 'db') await loadDb();
    if (tab === 'backup') await loadBackup();
    // tab debug: laporan hanya dibuat saat tombol ditekan
  } catch (e) { if (e.message !== 'Belum login') toast(e.message); }
}
let timers = [];
function startTimers() {
  stopTimers(); refresh();
  timers.push(setInterval(() => { if (!document.hidden && tab !== 'backup' && tab !== 'debug') refresh(); }, 30000));
  timers.push(setInterval(() => { $('#clock').textContent = new Date().toLocaleTimeString('id-ID'); }, 1000));
}
function stopTimers() { timers.forEach(clearInterval); timers = []; }

api('/api/me').then(r => r.authed ? showApp() : showLogin()).catch(showLogin);
