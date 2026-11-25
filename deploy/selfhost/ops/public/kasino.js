'use strict';
// Tab Kasino: Kasino Mutiara (Tide v84). Jejak setiap ronde (money trace), arus gold, RTP per meja, kapten, audit Edge.
// Hanya baca. Memakai helper dari app.js lewat window.OPS.
(() => {
  const { $, $$, esc, n0, idr, signed, api, toast, board, table, load, empty, showErr, loaders, NF1 } = window.OPS;
  const S = { j: '24', kapten: '', meja: '', status: '' };
  const JAM_TXT = { 24: '24 jam', 168: '7 hari', 720: '30 hari', semua: 'semua' };
  const pct = v => v == null || isNaN(+v) ? '-' : NF1.format(+v) + '%';
  let D = null, F = null;

  async function fetchMain(force) {
    D = await api('/api/kasino?jam=' + S.j + (force ? '&fresh=1' : ''));
    $('#ksStamp').textContent = 'Diambil ' + new Date(D.at).toLocaleTimeString('id-ID');
  }
  function renderBoard() {
    const el = $('#ksBoard'), r = D && D.ringkas;
    if (!r) { showErr(el, (D && D.errors && D.errors.ringkas) || 'tidak ada data', () => refreshKs(true)); return; }
    const rtp = r.putaran ? 100 * r.bayaran / r.putaran : null;
    el.innerHTML = board([
      { k: 'Ronde (' + JAM_TXT[S.j] + ')', v: n0(r.ronde), s: `${n0(r.kapten)} kapten · ${n0(r.aktif_kini)} Blackjack berjalan` },
      { k: 'Putaran taruhan', v: idr(r.putaran), s: 'RTP nyata ' + pct(rtp) },
      { k: 'Sink (kalah kapten)', v: idr(r.sink), s: 'gold terserap bandar' },
      { k: 'Faucet (menang kapten)', v: idr(r.faucet), s: `${n0(r.kena_batas)}× dipotong batas harian` },
      { k: 'Bersih bandar', v: signed(r.bandar_bersih), s: r.gerbang === '1' ? 'kasino BUKA' : 'kasino TUTUP (gerbang KasinoOpen)', level: r.bandar_bersih < 0 ? 'warn' : '' },
    ], 5);
  }
  function renderMeja() {
    const el = $('#ksMeja');
    if (!D || !D.meja) { showErr(el, (D && D.errors && D.errors.meja) || 'tidak ada data', () => refreshKs(true)); return; }
    if (!D.meja.length) { empty(el, '<b>Belum ada ronde</b> di rentang ini.'); return; }
    el.innerHTML = table([
      { h: 'Meja', k: 'meja', cls: () => 'name' }, { h: 'Edge kini', k: 'edge_kini_pct', num: 1, f: r => (r.edge_kini_pct > 0 ? '+' : '') + pct(r.edge_kini_pct) },
      { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) }, { h: 'Putaran', k: 'putaran', num: 1, f: r => n0(r.putaran) },
      { h: 'Bayaran', k: 'bayaran', num: 1, f: r => n0(r.bayaran) }, { h: 'Bersih bandar', k: 'bandar_bersih', num: 1, f: r => signed(r.bandar_bersih) },
      { h: 'RTP nyata', k: 'rtp_pct', num: 1, f: r => pct(r.rtp_pct) }, { h: 'RTP target', k: 'rtp_target_pct', num: 1, f: r => pct(r.rtp_target_pct) },
      { h: 'Selisih', k: 'x', num: 1, f: r => r.rtp_pct == null ? '-' : (r.rtp_pct - r.rtp_target_pct > 0 ? '+' : '') + NF1.format(r.rtp_pct - r.rtp_target_pct) },
      { h: 'Kena batas', k: 'kena_batas', num: 1, f: r => n0(r.kena_batas) }, { h: 'Pengali maks', k: 'pengali_maks', num: 1, f: r => NF1.format(r.pengali_maks) + '×' },
    ], D.meja, { rowLevel: r => r.ronde >= 1000 && Math.abs(r.rtp_pct - r.rtp_target_pct) > 3 ? 'warn' : '' });
  }
  function renderHarian() {
    const el = $('#ksHarian');
    if (!D || !D.harian) { showErr(el, (D && D.errors && D.errors.harian) || 'tidak ada data', () => refreshKs(true)); return; }
    if (!D.harian.length) { empty(el, '<b>Belum ada ronde</b> dalam 30 hari.'); return; }
    el.innerHTML = table([
      { h: 'Hari (WIB)', k: 'hari' }, { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) }, { h: 'Kapten', k: 'kapten', num: 1, f: r => n0(r.kapten) },
      { h: 'Putaran', k: 'putaran', num: 1, f: r => n0(r.putaran) }, { h: 'Sink', k: 'sink', num: 1, f: r => n0(r.sink) },
      { h: 'Faucet', k: 'faucet', num: 1, f: r => n0(r.faucet) }, { h: 'Bersih bandar', k: 'bandar_bersih', num: 1, f: r => signed(r.bandar_bersih) },
    ], D.harian, { rowLevel: r => r.bandar_bersih < 0 ? 'warn' : '' });
  }
  const kaptenBtn = n => `<button type="button" class="lnk" data-ks-kapten="${esc(n)}">${esc(n)}</button>`;
  function renderKapten() {
    const el = $('#ksKapten');
    if (!D || !D.kapten) { showErr(el, (D && D.errors && D.errors.kapten) || 'tidak ada data', () => refreshKs(true)); return; }
    if (!D.kapten.length) { empty(el, '<b>Belum ada kapten</b> yang bermain di rentang ini.'); return; }
    el.innerHTML = table([
      { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten) + ` <span class="dim">${esc(r.username)}</span>`, cls: () => 'name' },
      { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) }, { h: 'Putaran', k: 'putaran', num: 1, f: r => n0(r.putaran) },
      { h: 'Menang', k: 'menang', num: 1, f: r => n0(r.menang) }, { h: 'Kalah', k: 'kalah', num: 1, f: r => n0(r.kalah) },
      { h: 'Bersih', k: 'bersih', num: 1, f: r => signed(r.bersih) }, { h: 'Bersih hari ini', k: 'bersih_hari_ini', num: 1, f: r => signed(r.bersih_hari_ini) },
      { h: 'Kena batas', k: 'kena_batas', num: 1, f: r => n0(r.kena_batas) }, { h: 'Gold kini', k: 'gold_kini', num: 1, f: r => n0(r.gold_kini) },
      { h: 'Terakhir', k: 'terakhir', cls: () => 'dim' },
    ], D.kapten, { tall: true, rowLevel: r => r.bersih_hari_ini >= 2500000 ? 'bad' : r.bersih_hari_ini >= 2000000 ? 'warn' : '' });
  }
  function renderAudit() {
    const el = $('#ksAudit');
    if (!D || !D.audit) { showErr(el, (D && D.errors && D.errors.audit) || 'tidak ada data', () => refreshKs(true)); return; }
    if (!D.audit.length) { empty(el, '<b>Edge belum pernah diubah</b> (semua meja masih 0%).'); return; }
    el.innerHTML = table([
      { h: 'Waktu (WIB)', k: 'waktu', cls: () => 'dim' }, { h: 'GM', k: 'gm' }, { h: 'Meja', k: 'meja' },
      { h: 'Edge lama', k: 'edge_lama_pct', num: 1, f: r => pct(r.edge_lama_pct) }, { h: 'Edge baru', k: 'edge_baru_pct', num: 1, f: r => pct(r.edge_baru_pct) },
      { h: 'Catatan', k: 'catatan', cls: () => 'wrap' },
    ], D.audit);
  }
  async function renderFeed() {
    const el = $('#ksFeed'); delete el.dataset.ready;
    await load([el], async () => {
      const q = new URLSearchParams({ jam: S.j, kapten: S.kapten, meja: S.meja, status: S.status });
      F = await api('/api/kasino/feed?' + q);
      if (!F.feed) { showErr(el, (F.errors && F.errors.feed) || 'tidak ada data', renderFeed); return; }
      if (!F.feed.length) { empty(el, '<b>Tidak ada ronde</b> yang cocok dengan saringan.'); return; }
      el.innerHTML = table([
        { h: 'Waktu (WIB)', k: 'waktu', cls: () => 'dim' }, { h: 'Hari game', k: 'hari_game', num: 1 },
        { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten), cls: () => 'name' }, { h: 'Meja', k: 'meja' },
        { h: 'Gold sebelum', k: 'gold_sebelum', num: 1, f: r => n0(r.gold_sebelum) }, { h: '− Taruhan', k: 'taruhan', num: 1, f: r => n0(r.taruhan) },
        { h: '+ Bayaran', k: 'bayaran', num: 1, f: r => n0(r.bayaran) }, { h: 'Selisih', k: 'selisih', num: 1, f: r => signed(r.selisih) },
        { h: 'Gold sesudah', k: 'gold_sesudah', num: 1, f: r => n0(r.gold_sesudah) }, { h: 'Edge', k: 'edge_pct', num: 1, f: r => pct(r.edge_pct) },
        { h: 'Status', k: 'status', f: r => r.status + (r.kena_batas ? ' · batas' : '') }, { h: 'Detail hasil', k: 'detail', cls: () => 'wrap dim' },
      ], F.feed, { tall: true, rowLevel: r => r.kena_batas ? 'warn' : r.status === 'active' ? 'ok' : '' }) + (F.feed.length >= 300 ? '<p class="note">Menampilkan 300 ronde terbaru.</p>' : '');
    });
  }
  function renderExtra() {
    const bad = (k) => ((D && D.errors && D.errors[k]) || 'tidak ada data');
    const put = (id, key, mk) => {
      const el = $(id); if (!el) return;
      if (!D || !D[key]) { showErr(el, bad(key), () => refreshKs(true)); return; }
      mk(el, D[key]);
    };
    put('#ksAlarm', 'alarm', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada ronde</b> yang tercatat.'); return; }
      el.innerHTML = table([
        { h: 'Meja', k: 'meja', cls: () => 'name' }, { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) }, { h: 'Minimal alarm', k: 'min_ronde', num: 1, f: r => n0(r.min_ronde) },
        { h: 'RTP nyata', k: 'rtp_pct', num: 1, f: r => pct(r.rtp_pct) }, { h: 'RTP target', k: 'rtp_target_pct', num: 1, f: r => pct(r.rtp_target_pct) },
        { h: 'z', k: 'z', num: 1, f: r => NF1.format(r.z) }, { h: 'Status', k: 'alarm', f: r => r.alarm ? 'ALARM' : r.ronde < r.min_ronde ? 'data belum cukup' : 'wajar' },
      ], rows, { rowLevel: r => r.alarm ? 'bad' : '' });
    });
    put('#ksGerbang', 'gerbang', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada konfigurasi</b> kasino di game.config (memakai nilai bawaan).'); return; }
      const v = k => (rows.find(r => r.key === k) || {}).value;
      const buka = v('KasinoOpen') === '1';
      el.innerHTML = `<p class="note"><b>${buka ? 'Kasino BUKA untuk semua kapten.' : 'Kasino TUTUP.'}</b> Penguji: ${esc(v('FiturPenguji') || '(kosong)')}</p>` + table([
        { h: 'Kunci', k: 'key', cls: () => 'name' }, { h: 'Nilai', k: 'value', cls: () => 'wrap' },
      ], rows, { rowLevel: r => /^KasinoOpen/.test(r.key) && r.value !== '1' ? 'warn' : /^KasinoEdge/.test(r.key) && +r.value !== 0 ? 'warn' : '' });
    });
    put('#ksAktif', 'aktif', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Tidak ada</b> ronde Blackjack yang sedang berjalan.'); return; }
      el.innerHTML = table([
        { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten) + ` <span class="dim">${esc(r.username)}</span>`, cls: () => 'name' },
        { h: 'Taruhan', k: 'taruhan', num: 1, f: r => n0(r.taruhan) }, { h: 'Gold sebelum', k: 'gold_sebelum', num: 1, f: r => n0(r.gold_sebelum) },
        { h: 'Umur (detik)', k: 'umur_detik', num: 1, f: r => n0(r.umur_detik) }, { h: 'Batas (detik)', k: 'batas_detik', num: 1, f: r => n0(r.batas_detik) },
      ], rows, { rowLevel: r => r.umur_detik > r.batas_detik * 2 ? 'bad' : r.umur_detik > r.batas_detik ? 'warn' : '' });
    });
    const topCols = [
      { h: '#', k: 'x', num: 1, f: (r, i) => String(i + 1) },
      { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten) + ` <span class="dim">${esc(r.username)}</span>`, cls: () => 'name' },
      { h: 'Total taruhan', k: 'putaran', num: 1, f: r => n0(r.putaran) }, { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) },
      { h: 'Menang bersih', k: 'bersih', num: 1, f: r => signed(r.bersih) },
    ];
    const withRank = rows => rows.map((r, i) => Object.assign({ _i: i }, r));
    put('#ksTopHari', 'topHari', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada</b> yang bermain hari ini.'); return; }
      el.innerHTML = table(topCols.map(c => c.k === 'x' ? Object.assign({}, c, { f: r => String(r._i + 1) }) : c), withRank(rows), { rowLevel: r => r._i < 3 ? 'ok' : '' });
    });
    put('#ksTopPekan', 'topPekan', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada</b> yang bermain pekan ini.'); return; }
      const h = $('#ksPekanH'); if (h) h.textContent = 'Pekan ini (sejak Senin ' + rows[0].sejak + ')';
      el.innerHTML = table(topCols.map(c => c.k === 'x' ? Object.assign({}, c, { f: r => String(r._i + 1) }) : c), withRank(rows), { rowLevel: r => r._i < 1 ? 'ok' : '' });
    });
    put('#ksKuota', 'kuota', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada</b> kapten yang bermain hari ini.'); return; }
      el.innerHTML = table([
        { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten) + ` <span class="dim">${esc(r.username)}</span>`, cls: () => 'name' },
        { h: 'Menang bersih', k: 'bersih', num: 1, f: r => signed(r.bersih) }, { h: 'Batas', k: 'batas', num: 1, f: r => n0(r.batas) },
        { h: 'Sisa kuota', k: 'sisa', num: 1, f: r => n0(r.sisa) }, { h: 'Terpakai', k: 'terpakai_pct', num: 1, f: r => n0(r.terpakai_pct) + '%' },
        { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) }, { h: 'Putaran', k: 'putaran', num: 1, f: r => n0(r.putaran) },
      ], rows, { rowLevel: r => r.sisa <= 0 ? 'bad' : r.terpakai_pct >= 80 ? 'warn' : '' });
    });
    put('#ksBesar', 'besar', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada ronde</b> di rentang ini.'); return; }
      el.innerHTML = table([
        { h: 'Waktu (WIB)', k: 'waktu', cls: () => 'dim' }, { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten), cls: () => 'name' }, { h: 'Meja', k: 'meja' },
        { h: 'Taruhan', k: 'taruhan', num: 1, f: r => n0(r.taruhan) }, { h: 'Bayaran', k: 'bayaran', num: 1, f: r => n0(r.bayaran) },
        { h: 'Selisih', k: 'selisih', num: 1, f: r => signed(r.selisih) }, { h: 'Pengali', k: 'pengali', num: 1, f: r => NF1.format(r.pengali) + '×' },
        { h: 'Batas', k: 'kena_batas', f: r => r.kena_batas ? 'dipotong' : '' },
      ], rows, { rowLevel: r => r.kena_batas ? 'warn' : '' });
    });
    put('#ksCuriga', 'curiga', (el, rows) => {
      if (!rows.length) { empty(el, '<b>Belum ada kapten</b> dengan minimal 100 ronde.'); return; }
      el.innerHTML = table([
        { h: 'Kapten', k: 'kapten', html: 1, f: r => kaptenBtn(r.kapten) + ` <span class="dim">${esc(r.username)}</span>`, cls: () => 'name' },
        { h: 'Ronde', k: 'ronde', num: 1, f: r => n0(r.ronde) }, { h: 'Putaran', k: 'putaran', num: 1, f: r => n0(r.putaran) },
        { h: 'RTP nyata', k: 'rtp_pct', num: 1, f: r => pct(r.rtp_pct) }, { h: 'RTP target', k: 'rtp_target_pct', num: 1, f: r => pct(r.rtp_target_pct) },
        { h: 'z', k: 'z', num: 1, f: r => NF1.format(r.z) }, { h: 'Bersih', k: 'bersih', num: 1, f: r => signed(r.bersih) },
      ], rows, { rowLevel: r => r.z > 4 ? 'bad' : r.z > 3 ? 'warn' : '' });
    });
  }
  function renderAll() { renderBoard(); renderMeja(); renderHarian(); renderKapten(); renderAudit(); renderExtra(); }
  async function refreshKs(force) {
    const ids = ['#ksBoard', '#ksMeja', '#ksHarian', '#ksKapten', '#ksAudit', '#ksAlarm', '#ksGerbang', '#ksAktif', '#ksTopHari', '#ksTopPekan', '#ksKuota', '#ksBesar', '#ksCuriga'];
    if (force) ids.forEach(id => { const e = $(id); if (e) delete e.dataset.ready; });
    await load(ids, async () => { if (!D || force || D.jam !== (S.j === 'semua' ? null : +S.j)) await fetchMain(force); renderAll(); });
    renderFeed();
  }
  loaders.kasino = () => refreshKs(false);

  $('#ksRefresh').addEventListener('click', async () => { const b = $('#ksRefresh'); b.disabled = true; try { await refreshKs(true); toast('Kasino dimuat ulang.'); } catch (e) { toast(e.message); } b.disabled = false; });
  $('#ksJam').addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b || b.dataset.j === S.j) return;
    S.j = b.dataset.j; $$('#ksJam button').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.j === S.j))); refreshKs(true);
  });
  let kT;
  $('#ksCari').addEventListener('input', e => { S.kapten = e.target.value.trim(); clearTimeout(kT); kT = setTimeout(renderFeed, 300); });
  $('#ksMejaSel').addEventListener('change', e => { S.meja = e.target.value; renderFeed(); });
  $('#ksStatusSel').addEventListener('change', e => { S.status = e.target.value; renderFeed(); });
  $('section[data-panel="kasino"]').addEventListener('click', e => {
    const b = e.target.closest('button.lnk[data-ks-kapten]'); if (!b) return;
    S.kapten = b.dataset.ksKapten; $('#ksCari').value = S.kapten; renderFeed();
    $('#ksFeedBox').scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
})();
