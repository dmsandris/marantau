'use strict';
// Tab Iluminaty: Pesan Pribadi antar kapten (game.mp_pm). Hanya baca. Memakai helper dari app.js lewat window.OPS.
(() => {
  const { $, $$, esc, n0, api, toast, board, table, load, empty, showErr, loaders } = window.OPS;
  const S = { saring: '', sort: { s: 'akhir_ms', d: 'desc' } };
  let D = null;

  async function fetchMain(force) {
    D = await api('/api/iluminaty' + (force ? '?fresh=1' : ''));
    $('#iluStamp').textContent = 'Diambil ' + new Date(D.at).toLocaleTimeString('id-ID');
  }
  const pairBtn = (r, label) => `<button type="button" class="lnk" data-pair="${esc(r.pair)}" data-judul="${esc(r.kapten_a + ' & ' + r.kapten_b)}">${esc(label)}</button>`;

  function renderBoard() {
    const el = $('#iluBoard'), r = D && D.ringkas;
    if (!r) { showErr(el, (D && D.errors && D.errors.ringkas) || 'tidak ada data', () => refreshIlu(true)); return; }
    el.innerHTML = board([
      { k: 'Pesan 24 jam', v: n0(r.pm_24j), s: `${n0(r.pm_semua)} pesan tersimpan` },
      { k: 'Percakapan', v: n0(r.percakapan), s: 'pasangan kapten' },
      { k: 'Pengirim', v: n0(r.pengirim), s: 'kapten berbeda' },
      { k: 'Belum dibaca', v: n0(r.belum_dibaca), s: r.tertua ? 'tertua ' + r.tertua : 'belum ada pesan' },
    ], 4);
  }
  function renderDaftar() {
    const el = $('#iluDaftar');
    if (!D || !D.percakapan) { showErr(el, (D && D.errors && D.errors.percakapan) || 'tidak ada data', () => refreshIlu(true)); return; }
    const q = S.saring.trim().toLowerCase();
    const rows = D.percakapan.filter(r => !q || [r.kapten_a, r.user_a, r.kapten_b, r.user_b].some(v => String(v || '').toLowerCase().includes(q)));
    if (!rows.length) { empty(el, q ? `<b>Tidak ada</b> yang cocok dengan "${esc(S.saring)}".` : '<b>Belum ada pesan pribadi.</b>'); return; }
    const st = S.sort;
    rows.sort((a, b) => { const x = a[st.s], y = b[st.s]; const c = typeof x === 'number' ? x - y : String(x || '').localeCompare(String(y || '')); return st.d === 'asc' ? c : -c; });
    const cols = [
      { h: 'Kapten A', k: 'kapten_a', html: 1, f: r => pairBtn(r, r.kapten_a) + ` <span class="dim">${esc(r.user_a)}</span>`, cls: () => 'name' },
      { h: 'Kapten B', k: 'kapten_b', html: 1, f: r => pairBtn(r, r.kapten_b) + ` <span class="dim">${esc(r.user_b)}</span>`, cls: () => 'name' },
      { h: 'Pesan', k: 'jumlah', num: 1, f: r => n0(r.jumlah) },
      { h: 'A → B', k: 'dari_a', num: 1, f: r => n0(r.dari_a) }, { h: 'B → A', k: 'dari_b', num: 1, f: r => n0(r.dari_b) },
      { h: 'Belum dibaca', k: 'belum_dibaca', num: 1, f: r => n0(r.belum_dibaca), cls: r => r.belum_dibaca ? '' : 'dim' },
      { h: 'Mulai', k: 'mulai', cls: () => 'dim' }, { h: 'Terakhir', k: 'akhir_ms', f: r => r.terakhir },
    ];
    el.innerHTML = table(cols.map(c => ({ ...c, sort: 1, aria: st.s === c.k ? (st.d === 'asc' ? 'ascending' : 'descending') : undefined })), rows, { tall: true, id: 'tIluDaftar' });
  }
  function renderPengirim() {
    const el = $('#iluPengirim');
    if (!D || !D.pengirim) { showErr(el, (D && D.errors && D.errors.pengirim) || 'tidak ada data', () => refreshIlu(true)); return; }
    if (!D.pengirim.length) { empty(el, '<b>Belum ada pesan pribadi.</b>'); return; }
    el.innerHTML = table([
      { h: 'Kapten', k: 'kapten', cls: () => 'name' }, { h: 'Username', k: 'username', cls: () => 'dim' },
      { h: 'Pesan', k: 'jumlah', num: 1, f: r => n0(r.jumlah) }, { h: '24 jam', k: 'jumlah_24j', num: 1, f: r => n0(r.jumlah_24j) },
      { h: 'Lawan bicara', k: 'lawan', num: 1, f: r => n0(r.lawan) }, { h: 'Terakhir', k: 'terakhir', cls: () => 'dim' },
    ], D.pengirim, { tall: true });
  }
  function pesanTable(rows, withPair) {
    return table([
      { h: 'Waktu (WIB)', k: 'waktu', cls: () => 'dim' },
      { h: 'Dari', k: 'dari', html: 1, f: r => withPair ? `<button type="button" class="lnk" data-pair="${esc(r.pair)}" data-judul="${esc(r.dari + ' & ' + r.ke)}">${esc(r.dari)}</button>` : esc(r.dari), cls: () => 'name' },
      { h: 'Ke', k: 'ke' },
      { h: 'Isi', k: 'isi', cls: () => 'wrap' },
      { h: 'Dibaca', k: 'dibaca', f: r => r.dibaca ? (r.dibaca_pada || 'ya') : 'belum', cls: r => r.dibaca ? 'dim' : '' },
    ], rows, { tall: true });
  }
  async function bukaUtas(pair, judul) {
    const box = $('#iluUtasBox'), el = $('#iluUtas');
    box.classList.remove('hidden'); $('#iluUtasJudul').textContent = judul || '';
    delete el.dataset.ready;
    await load([el], async () => {
      const r = await api('/api/iluminaty/utas?pair=' + encodeURIComponent(pair));
      if (!r.utas) { showErr(el, (r.errors && r.errors.utas) || 'tidak ada data', () => bukaUtas(pair, judul)); return; }
      if (!r.utas.length) { empty(el, '<b>Percakapan sudah kosong</b> (lewat 7 hari).'); return; }
      el.innerHTML = pesanTable(r.utas, false);
    });
    box.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
  async function cari() {
    const q = $('#iluCari').value.trim(), box = $('#iluHasilBox'), el = $('#iluHasil');
    if (q.length < 2) { toast('Minimal 2 huruf.'); return; }
    box.classList.remove('hidden'); $('#iluHasilQ').textContent = '"' + q + '"';
    delete el.dataset.ready;
    await load([el], async () => {
      const r = await api('/api/iluminaty/cari?q=' + encodeURIComponent(q));
      if (!r.cari) { showErr(el, (r.errors && r.errors.cari) || 'tidak ada data', cari); return; }
      if (!r.cari.length) { empty(el, `<b>Tidak ada pesan</b> yang memuat "${esc(q)}".`); return; }
      el.innerHTML = pesanTable(r.cari, true) + (r.cari.length >= 300 ? '<p class="note">Menampilkan 300 terbaru.</p>' : '');
    });
  }
  function renderAll() { renderBoard(); renderDaftar(); renderPengirim(); }
  async function refreshIlu(force) {
    const ids = ['#iluBoard', '#iluDaftar', '#iluPengirim'];
    if (force) ids.forEach(id => { const e = $(id); if (e) delete e.dataset.ready; });
    await load(ids, async () => { if (!D || force) await fetchMain(force); renderAll(); });
  }
  loaders.iluminaty = () => refreshIlu(false);

  $('#iluRefresh').addEventListener('click', async () => { const b = $('#iluRefresh'); b.disabled = true; try { await refreshIlu(true); toast('Iluminaty dimuat ulang.'); } catch (e) { toast(e.message); } b.disabled = false; });
  $('#iluCariBtn').addEventListener('click', cari);
  $('#iluCari').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); cari(); } });
  let sT;
  $('#iluSaring').addEventListener('input', e => { S.saring = e.target.value; clearTimeout(sT); sT = setTimeout(renderDaftar, 150); });
  $('section[data-panel="iluminaty"]').addEventListener('click', e => {
    const b = e.target.closest('button.lnk[data-pair]');
    if (b) { bukaUtas(b.dataset.pair, b.dataset.judul); return; }
    const th = e.target.closest('#tIluDaftar th button'); if (!th) return;
    const k = th.closest('th').dataset.k, st = S.sort;
    st.d = st.s === k ? (st.d === 'asc' ? 'desc' : 'asc') : (/^kapten|^mulai/.test(k) ? 'asc' : 'desc'); st.s = k;
    renderDaftar();
  });
})();
