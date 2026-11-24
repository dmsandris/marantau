'use strict';
// Tab Audit: gudang, transfer gold, Bursa Kapten, jejak satu kapten. Memakai helper dari app.js lewat window.OPS.
(() => {
  const { $, $$, esc, n0, idr, signed, api, toast, board, table, load, empty, showErr, setVars, loaders, NF1, st } = window.OPS;
  const pct1 = v => v == null || isNaN(+v) ? '-' : NF1.format(+v) + '%';
  const pctS = v => v == null || isNaN(+v) ? '-' : (+v > 0 ? '+' : '') + n0(v) + '%';
  const JAM_TXT = { 24: '24 jam', 168: '7 hari', 720: '30 hari', semua: 'semua catatan' };

  // ---------- keadaan (disimpan di hash: #/audit?b=..&j=..&k=..&q=..) ----------
  const S = { b: 'aliran', j: '168', k: '', q: '', palka: false, ak: '' };
  const sorts = {};   // id tabel -> { s, d }
  function readParams() {
    const h = location.hash, i = h.indexOf('?'); if (i < 0) return;
    const u = new URLSearchParams(h.slice(i + 1));
    if (['aliran', 'gudang', 'transfer', 'bursa', 'jejak'].includes(u.get('b'))) S.b = u.get('b');
    if (u.get('j') in JAM_TXT) S.j = u.get('j');
    S.k = u.get('k') || ''; S.q = u.get('q') || '';
  }
  function writeParams() {
    const u = new URLSearchParams();
    if (S.b !== 'aliran') u.set('b', S.b); if (S.j !== '168') u.set('j', S.j);
    if (S.k) u.set('k', S.k); if (S.q) u.set('q', S.q);
    const qs = u.toString();
    history.replaceState(null, '', location.pathname + location.search + '#/audit' + (qs ? '?' + qs : ''));
  }
  const nameBtn = n => n ? `<button type="button" class="lnk" data-kapten="${esc(n)}">${esc(n)}</button>` : '';
  const match = (r, keys) => { const q = S.q.trim().toLowerCase(); return !q || keys.some(k => String(r[k] == null ? '' : r[k]).toLowerCase().includes(q)); };

  // Tabel yang bisa diurutkan: klik judul kolom. def = urutan bawaan { s, d }.
  function sortedTable(id, cols, rows, def, opt = {}) {
    const st = sorts[id] || (sorts[id] = { ...def });
    const list = rows.slice().sort((a, b) => {
      const x = a[st.s], y = b[st.s];
      const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x == null ? '' : x).localeCompare(String(y == null ? '' : y));
      return st.d === 'asc' ? c : -c;
    });
    return table(cols.map(c => ({ ...c, sort: 1, aria: st.s === c.k ? (st.d === 'asc' ? 'ascending' : 'descending') : undefined })), list, { tall: true, id, ...opt });
  }
  const TEXT_KEYS = new Set(['kapten', 'pulau', 'barang', 'tier', 'pengirim', 'penerima', 'pembeli', 'penjual', 'pasangan', 'lawan', 'arah', 'kat', 'sumber_utama', 'tujuan_utama']);

  // ---------- data ----------
  let D = null;
  async function fetchMain(force) {
    D = await api(`/api/audit?jam=${encodeURIComponent(S.j)}${force ? '&fresh=1' : ''}`);
    $('#audStamp').textContent = 'Diambil ' + new Date(D.at).toLocaleTimeString('id-ID');
    fillKapten();
  }
  const part = (el, key, fn) => {
    if (!D || D[key] == null) { showErr(el, (D && D.errors && D.errors[key]) || 'tidak ada data', () => refreshAud(true)); return false; }
    el.removeAttribute('aria-busy'); fn(D[key]); return true;
  };
  function fillKapten() {
    const sel = $('#audKapten'); if (!D || !D.daftar) return;
    const want = S.k;
    sel.innerHTML = `<option value="">Pilih kapten</option>` + D.daftar.map(r => `<option value="${esc(r.kapten)}"${r.kapten === want ? ' selected' : ''}>${esc(r.kapten)} (${esc(r.username)})</option>`).join('');
  }


  // ---------- Aliran dana ----------
  let AL = null;
  async function fetchAliran(force) {
    AL = await api(`/api/aliran?jam=${encodeURIComponent(S.j)}${force ? '&fresh=1' : ''}`);
    $('#audStamp').textContent = 'Diambil ' + new Date(AL.at).toLocaleTimeString('id-ID');
  }
  const alPart = (el, key, fn) => {
    if (!AL || AL[key] == null) { showErr(el, (AL && AL.errors && AL.errors[key]) || 'tidak ada data', () => refreshAud(true)); return false; }
    el.removeAttribute('aria-busy'); fn(AL[key]); return true;
  };
  function ledger(rows, cls) {
    if (!rows.length) return '<div class="empty">Tidak ada.</div>';
    const mx = Math.max(1, ...rows.map(r => r.gold)), tot = rows.reduce((a, r) => a + r.gold, 0);
    return `<div class="hb">${rows.map(r => `<div class="hb-row"><div class="hb-l"><span>${esc(r.kat)}</span><small>${esc(r.kel)}, ${n0(r.kejadian)} kejadian, ${n0(r.pemain)} kapten</small></div>
      <div class="hb-t"><i class="${cls}" data-w="${(100 * r.gold / mx).toFixed(2)}"></i></div><div class="hb-v">${esc(idr(r.gold))}<br><small class="dim">${NF1.format(100 * r.gold / (tot || 1))}%</small></div></div>`).join('')}</div>`;
  }
  function renderAliran() {
    alPart($('#audAlBoard'), 'kategori', rows => {
      const masuk = rows.filter(r => r.arah === 1), keluar = rows.filter(r => r.arah === -1);
      const tm = masuk.reduce((a, r) => a + r.gold, 0), tk = keluar.reduce((a, r) => a + r.gold, 0);
      const harta = masuk.filter(r => r.kel === 'Item dan harta').reduce((a, r) => a + r.gold, 0), hartaKeluar = keluar.filter(r => r.kel === 'Item dan harta').reduce((a, r) => a + r.gold, 0);
      const dagang = masuk.filter(r => r.kat === 'Jual barang dagang').reduce((a, r) => a + r.gold, 0) - keluar.filter(r => r.kel === 'Dagang').reduce((a, r) => a + r.gold, 0);
      const antar = masuk.filter(r => r.kat === 'Transfer masuk').reduce((a, r) => a + r.gold, 0);
      $('#audAlBoard').innerHTML = board([
        { k: 'Gold masuk', v: idr(tm), s: `${n0(masuk.length)} kategori sumber` },
        { k: 'Gold keluar', v: idr(tk), s: `${n0(keluar.length)} kategori tujuan` },
        { k: 'Bersih ke kantong kapten', v: signed(tm - tk), s: 'masuk dikurangi keluar', level: tm - tk > 0 ? '' : '' },
        { k: 'Laba dagang bersih', v: signed(dagang), s: 'jual barang dikurangi beli barang dan Hak Lot' },
        { k: 'Bersih dari peta dan galian', v: signed(harta - hartaKeluar), s: `masuk ${idr(harta)}, keluar ${idr(hartaKeluar)}`, level: harta - hartaKeluar > Math.max(1e6, Math.abs(dagang)) ? 'bad' : harta - hartaKeluar > 1e6 ? 'warn' : '' },
        { k: 'Transfer antar kapten', v: idr(antar), s: 'gold berpindah tangan, tidak menambah total' },
      ], 6);
      const top = masuk[0];
      $('#audAlTake').innerHTML = top ? `Sumber gold terbesar dalam ${esc(JAM_TXT[S.j])}: <b>${esc(top.kat)}</b>, ${esc(idr(top.gold))} atau ${esc(NF1.format(100 * top.gold / (tm || 1)))}% dari semua gold masuk.${harta - hartaKeluar > Math.abs(dagang) && harta > 1e6 ? ' <b>Peta dan galian menghasilkan lebih banyak dari dagang.</b> Cek kapten di tabel per kapten.' : ''}` : '';
      $('#audAlMasuk').innerHTML = ledger(masuk, 'seg-in'); setVars($('#audAlMasuk')); $('#audAlMasuk').removeAttribute('aria-busy');
      $('#audAlKeluar').innerHTML = ledger(keluar, 'seg-out'); setVars($('#audAlKeluar')); $('#audAlKeluar').removeAttribute('aria-busy');
      const nol = rows.filter(r => r.arah === 0);
      $('#audAlNol').innerHTML = nol.length ? table([{ h: 'Catatan', k: 'kat', cls: () => 'name' }, { h: 'Kejadian', k: 'kejadian', num: 1, f: r => n0(r.kejadian) }, { h: 'Kapten', k: 'pemain', num: 1, f: r => n0(r.pemain) }, { h: 'Gold disebut', k: 'gold', num: 1, f: r => n0(r.gold) }], nol) : '<div class="empty">Tidak ada.</div>';
      $('#audAlNol').removeAttribute('aria-busy');
    });
    alPart($('#audAlHarian'), 'harian', rows => {
      const el = $('#audAlHarian');
      const days = [...new Set(rows.map(r => r.hari))].sort();
      if (!days.length) { empty(el, 'Belum ada catatan.'); return; }
      const v = days.map(d => ({ hari: d, masuk: rows.filter(r => r.hari === d && r.arah === 1).reduce((a, r) => a + r.gold, 0), keluar: rows.filter(r => r.hari === d && r.arah === -1).reduce((a, r) => a + r.gold, 0) }));
      const W = 720, H = 200, mid = H / 2, mx = Math.max(1, ...v.map(x => Math.max(x.masuk, x.keluar))), gap = W / v.length, bw = Math.min(48, Math.max(2, gap * 0.62));
      const bars = v.map((x, i) => { const hi = (mid - 6) * x.masuk / mx, ho = (mid - 6) * x.keluar / mx, xx = (i * gap + (gap - bw) / 2).toFixed(1);
        return `<rect class="c-bar" x="${xx}" y="${(mid - hi).toFixed(1)}" width="${bw.toFixed(1)}" height="${Math.max(1, hi).toFixed(1)}"><title>${esc(x.hari)}: masuk ${esc(idr(x.masuk))}</title></rect><rect class="c-bar2" x="${xx}" y="${mid}" width="${bw.toFixed(1)}" height="${Math.max(1, ho).toFixed(1)}"><title>${esc(x.hari)}: keluar ${esc(idr(x.keluar))}</title></rect>`; }).join('');
      const best = v.reduce((a, x) => x.masuk > a.masuk ? x : a, v[0]);
      el.innerHTML = `<div class="chart chart--tall"><p class="legend legend--keys"><span><i class="key-in"></i>masuk</span><span><i class="key-out"></i>keluar</span></p><svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Gold masuk dan keluar per hari, ${v.length} hari. Masuk tertinggi ${esc(best.hari)} ${esc(idr(best.masuk))}">
        <line class="c-axis" x1="0" x2="${W}" y1="${mid}" y2="${mid}"/>${bars}</svg>
        <div class="axis"><span>${esc(days[0].slice(5))}</span><span>masuk tertinggi ${esc(best.hari.slice(5))}: ${esc(idr(best.masuk))}</span><span>${esc(days[days.length - 1].slice(5))}</span></div></div>`;
    });
    alPart($('#audAlKapten'), 'kapten', rows => {
      const list = rows.filter(r => match(r, ['kapten', 'username', 'sumber_utama']));
      if (!list.length) { empty($('#audAlKapten'), S.q ? `<b>Tidak ada</b> yang cocok dengan "${esc(S.q)}".` : '<b>Belum ada catatan.</b>'); return; }
      $('#audAlKapten').innerHTML = sortedTable('tAlKap', [
        { h: 'Kapten', k: 'kapten', html: 1, f: r => nameBtn(r.kapten), cls: () => 'name' },
        { h: 'Masuk', k: 'masuk', num: 1, f: r => n0(r.masuk) }, { h: 'Keluar', k: 'keluar', num: 1, f: r => n0(r.keluar) },
        { h: 'Bersih', k: 'bersih', num: 1, f: r => signed(r.bersih), cls: r => r.bersih < 0 ? 'neg' : '' },
        { h: 'Dari dagang', k: 'dari_dagang', num: 1, f: r => n0(r.dari_dagang), cls: r => r.dari_dagang ? '' : 'dim' },
        { h: 'Dari galian dan artefak', k: 'dari_harta', num: 1, f: r => r.dari_harta ? `${n0(r.dari_harta)} (${NF1.format(r.harta_pct || 0)}%)` : '0', cls: r => (r.harta_pct || 0) >= 50 && r.dari_harta >= 1e6 ? 'hot' : r.dari_harta ? 'warn' : 'dim' },
        { h: 'Dari kapten lain', k: 'dari_kapten', num: 1, f: r => n0(r.dari_kapten), cls: r => r.dari_kapten ? '' : 'dim' },
        { h: 'Sumber utama', k: 'sumber_utama' }, { h: 'Tujuan utama', k: 'tujuan_utama' },
        { h: 'Kekayaan kini', k: 'kekayaan_kini', num: 1, f: r => n0(r.kekayaan_kini) },
        { h: '', k: 'x', html: 1, f: r => `<button type="button" class="btn btn--small" data-al="${esc(r.kapten)}">Rincian</button>` },
      ], list, { s: 'masuk', d: 'desc' });
      renderAlRinci();
    });
  }
  function renderAlRinci() {
    const el = $('#audAlRinci');
    if (!S.ak || !AL || !AL.matriks) { el.classList.add('hidden'); return; }
    const rows = AL.matriks.filter(r => r.kapten === S.ak);
    const masuk = rows.filter(r => r.arah === 1), keluar = rows.filter(r => r.arah === -1);
    const t = cols => table([{ h: 'Kategori', k: 'kat', cls: () => 'name' }, { h: 'Kejadian', k: 'kejadian', num: 1, f: r => n0(r.kejadian) }, { h: 'Gold', k: 'gold', num: 1, f: r => n0(r.gold) }], cols);
    el.innerHTML = `<h3><span>Rincian ${esc(S.ak)}, ${esc(JAM_TXT[S.j])}</span><span class="tools">${nameBtn(S.ak).replace('class="lnk"', 'class="btn btn--small"').replace(`>${esc(S.ak)}<`, '>Buka jejak<')}<button type="button" class="btn btn--small" data-al="">Tutup</button></span></h3>
      <div class="grid2"><div><h4 class="sub-h">Masuk</h4>${masuk.length ? t(masuk) : '<div class="empty">Tidak ada.</div>'}</div><div><h4 class="sub-h">Keluar</h4>${keluar.length ? t(keluar) : '<div class="empty">Tidak ada.</div>'}</div></div>`;
    el.classList.remove('hidden');
  }

  // ---------- Gudang ----------
  function renderGudang() {
    part($('#audGudBoard'), 'gudang', rows => {
      const g = rows.filter(r => !r.palka);
      const kap = new Set(g.map(r => r.kapten)), pulau = new Set(g.map(r => r.pulau));
      const prem = g.filter(r => r.tier === 'premium');
      $('#audGudBoard').innerHTML = board([
        { k: 'Kapten dengan gudang', v: n0(kap.size), s: `di ${n0(pulau.size)} pulau` },
        { k: 'Unit di gudang', v: n0(g.reduce((a, r) => a + r.jumlah, 0)), s: `${n0(g.length)} baris barang` },
        { k: 'Nilai dasar gudang', v: idr(g.reduce((a, r) => a + r.nilai_dasar, 0)), s: 'semua kapten' },
        { k: 'Premium di gudang', v: n0(prem.reduce((a, r) => a + r.jumlah, 0)), s: `nilai ${idr(prem.reduce((a, r) => a + r.nilai_dasar, 0))}` },
      ], 4);
    });
    part($('#audGudKapten'), 'gudang', rows => {
      const by = {};
      for (const r of rows) {
        if (r.palka) continue;
        const k = by[r.kapten] || (by[r.kapten] = { kapten: r.kapten, pulau_set: new Set(), jumlah: 0, nilai_dasar: 0, premium: 0, barang_set: new Set() });
        k.pulau_set.add(r.pulau); k.barang_set.add(r.barang); k.jumlah += r.jumlah; k.nilai_dasar += r.nilai_dasar; if (r.tier === 'premium') k.premium += r.jumlah;
      }
      const list = Object.values(by).map(k => ({ ...k, pulau: [...k.pulau_set].sort().join(', '), n_pulau: k.pulau_set.size, n_barang: k.barang_set.size })).filter(r => match(r, ['kapten', 'pulau']));
      if (!list.length) { empty($('#audGudKapten'), S.q ? `<b>Tidak ada</b> yang cocok dengan "${esc(S.q)}".` : '<b>Gudang kosong.</b>'); return; }
      $('#audGudKapten').innerHTML = sortedTable('tGudKap', [
        { h: 'Kapten', k: 'kapten', html: 1, f: r => nameBtn(r.kapten), cls: () => 'name' },
        { h: 'Pulau', k: 'n_pulau', num: 1, f: r => n0(r.n_pulau) }, { h: 'Daftar pulau', k: 'pulau', cls: () => 'wrap dim' },
        { h: 'Jenis barang', k: 'n_barang', num: 1, f: r => n0(r.n_barang) }, { h: 'Unit', k: 'jumlah', num: 1, f: r => n0(r.jumlah) },
        { h: 'Unit premium', k: 'premium', num: 1, f: r => n0(r.premium), cls: r => r.premium ? '' : 'dim' },
        { h: 'Nilai dasar', k: 'nilai_dasar', num: 1, f: r => n0(r.nilai_dasar) },
      ], list, { s: 'nilai_dasar', d: 'desc' });
    });
    part($('#audGudRinci'), 'gudang', rows => {
      const list = rows.filter(r => (S.palka || !r.palka) && match(r, ['kapten', 'pulau', 'barang', 'tier']));
      if (!list.length) { empty($('#audGudRinci'), `<b>Tidak ada</b> yang cocok${S.q ? ` dengan "${esc(S.q)}"` : ''}.`); return; }
      $('#audGudRinci').innerHTML = sortedTable('tGudRinci', [
        { h: 'Kapten', k: 'kapten', html: 1, f: r => nameBtn(r.kapten), cls: () => 'name' },
        { h: 'Pulau', k: 'pulau', f: r => r.palka ? 'Palka kapal' : r.pulau + (r.tersembunyi ? ' (tersembunyi)' : ''), cls: r => r.palka ? 'dim' : '' },
        { h: 'Barang', k: 'barang' }, { h: 'Tier', k: 'tier' },
        { h: 'Jumlah', k: 'jumlah', num: 1, f: r => n0(r.jumlah) }, { h: 'Nilai dasar', k: 'nilai_dasar', num: 1, f: r => n0(r.nilai_dasar) },
        { h: 'Modal', k: 'modal', num: 1, f: r => r.modal == null ? '-' : n0(r.modal), cls: r => r.modal == null ? 'dim' : '' },
        { h: 'Pangsa', k: 'pangsa_pct', num: 1, f: r => pct1(r.pangsa_pct), cls: r => r.pangsa_pct >= 20 ? 'hot' : '' },
      ], list, { s: 'nilai_dasar', d: 'desc' });
    });
    part($('#audGudArus'), 'arusGudang', rows => {
      const list = rows.filter(r => match(r, ['kapten']));
      if (!list.length) { empty($('#audGudArus'), `<b>Tidak ada titip atau ambil</b> dalam ${esc(JAM_TXT[S.j])}.`); return; }
      $('#audGudArus').innerHTML = sortedTable('tGudArus', [
        { h: 'Kapten', k: 'kapten', html: 1, f: r => nameBtn(r.kapten), cls: () => 'name' },
        { h: 'Unit masuk', k: 'masuk', num: 1, f: r => n0(r.masuk) }, { h: 'Unit keluar', k: 'keluar', num: 1, f: r => n0(r.keluar) },
        { h: 'Bersih', k: 'bersih', num: 1, f: r => signed(r.bersih), cls: r => r.bersih > 0 ? 'pos' : r.bersih < 0 ? 'dim' : 'dim' },
        { h: 'Nilai masuk', k: 'nilai_masuk', num: 1, f: r => n0(r.nilai_masuk) }, { h: 'Nilai keluar', k: 'nilai_keluar', num: 1, f: r => n0(r.nilai_keluar) },
        { h: 'Kejadian', k: 'kejadian', num: 1, f: r => n0(r.kejadian) }, { h: 'Biaya titip', k: 'biaya', num: 1, f: r => n0(r.biaya) },
      ], list, { s: 'nilai_masuk', d: 'desc' });
    });
  }

  // ---------- Transfer gold ----------
  function sumBy(rows, key) {
    const m = {};
    for (const r of rows) { const o = m[r[key]] || (m[r[key]] = { kapten: r[key], n: 0, jumlah: 0, lawan: new Set() }); o.n++; o.jumlah += r.jumlah; o.lawan.add(r[key === 'penerima' ? 'pengirim' : 'penerima']); }
    return Object.values(m).map(o => ({ ...o, n_lawan: o.lawan.size })).sort((a, b) => b.jumlah - a.jumlah);
  }
  function renderTransfer() {
    part($('#audTrBoard'), 'transfer', rows => {
      const list = rows.filter(r => match(r, ['pengirim', 'penerima']));
      const tot = list.reduce((a, r) => a + r.jumlah, 0), maks = list.reduce((a, r) => Math.max(a, r.jumlah), 0);
      $('#audTrBoard').innerHTML = board([
        { k: 'Transfer', v: n0(list.length), s: JAM_TXT[S.j] + (rows.length >= 1000 ? ', dibatasi 1.000 terakhir' : '') },
        { k: 'Total gold', v: idr(tot), s: `rata-rata ${idr(list.length ? tot / list.length : 0)}` },
        { k: 'Transfer terbesar', v: idr(maks), s: 'satu kali kirim' },
        { k: 'Kapten terlibat', v: n0(new Set(list.flatMap(r => [r.pengirim, r.penerima])).size), s: `${n0(new Set(list.map(r => r.pengirim)).size)} pengirim, ${n0(new Set(list.map(r => r.penerima)).size)} penerima` },
      ], 4);
      const top = (el, key, label) => {
        const agg = sumBy(list, key).slice(0, 15);
        if (!agg.length) { empty(el, `<b>Tidak ada transfer</b> dalam ${esc(JAM_TXT[S.j])}.`); return; }
        el.innerHTML = table([
          { h: 'Kapten', k: 'kapten', html: 1, f: r => nameBtn(r.kapten), cls: () => 'name' },
          { h: 'Gold', k: 'jumlah', num: 1, f: r => n0(r.jumlah) }, { h: 'Kali', k: 'n', num: 1, f: r => n0(r.n) },
          { h: label, k: 'n_lawan', num: 1, f: r => n0(r.n_lawan) },
        ], agg);
      };
      top($('#audTrTerima'), 'penerima', 'Dari berapa kapten'); top($('#audTrKirim'), 'pengirim', 'Ke berapa kapten');

      const pair = {};
      for (const r of list) { const k = r.pengirim + '\u0000' + r.penerima; const o = pair[k] || (pair[k] = { pengirim: r.pengirim, penerima: r.penerima, n: 0, jumlah: 0 }); o.n++; o.jumlah += r.jumlah; }
      const pl = Object.values(pair).map(o => {
        const back = pair[o.penerima + '\u0000' + o.pengirim];
        return { ...o, balik: back ? back.jumlah : 0, n_balik: back ? back.n : 0, bersih: o.jumlah - (back ? back.jumlah : 0), pasangan: o.pengirim + ' ke ' + o.penerima };
      }).filter(o => o.bersih >= 0 && !(o.bersih === 0 && o.pengirim > o.penerima));
      const pe = $('#audTrPasang');
      if (!pl.length) empty(pe, `<b>Tidak ada transfer</b> dalam ${esc(JAM_TXT[S.j])}.`);
      else pe.innerHTML = sortedTable('tTrPasang', [
        { h: 'Pengirim', k: 'pengirim', html: 1, f: r => nameBtn(r.pengirim), cls: () => 'name' },
        { h: 'Penerima', k: 'penerima', html: 1, f: r => nameBtn(r.penerima), cls: () => 'name' },
        { h: 'Gold dikirim', k: 'jumlah', num: 1, f: r => n0(r.jumlah) }, { h: 'Kali', k: 'n', num: 1, f: r => n0(r.n) },
        { h: 'Arus balik', k: 'balik', num: 1, f: r => r.balik ? `${n0(r.balik)} (${n0(r.n_balik)} kali)` : '-', cls: r => r.balik ? 'hot' : 'dim' },
        { h: 'Bersih', k: 'bersih', num: 1, f: r => n0(r.bersih) },
      ], pl, { s: 'bersih', d: 'desc' });

      const de = $('#audTrDaftar');
      if (!list.length) { empty(de, `<b>Tidak ada transfer</b>${S.q ? ` yang cocok dengan "${esc(S.q)}"` : ` dalam ${esc(JAM_TXT[S.j])}`}.`); return; }
      de.innerHTML = sortedTable('tTrDaftar', [
        { h: 'Waktu (WIB)', k: 'waktu' },
        { h: 'Pengirim', k: 'pengirim', html: 1, f: r => nameBtn(r.pengirim), cls: () => 'name' },
        { h: 'Penerima', k: 'penerima', html: 1, f: r => r.penerima_dikenal ? nameBtn(r.penerima) : esc(r.penerima) + ' (nama tidak ditemukan)', cls: () => 'name' },
        { h: 'Gold', k: 'jumlah', num: 1, f: r => n0(r.jumlah) },
      ], list, { s: 'waktu', d: 'desc' });
    });
    if (!D || D.transfer == null) ['#audTrTerima', '#audTrKirim', '#audTrPasang', '#audTrDaftar'].forEach(id => showErr($(id), (D && D.errors && D.errors.transfer) || 'tidak ada data', () => refreshAud(true)));
  }

  // ---------- Bursa ----------
  function renderBursa() {
    part($('#audBuBoard'), 'bursa', rows => {
      const list = rows.filter(r => match(r, ['pembeli', 'penjual', 'barang']));
      const tot = list.reduce((a, r) => a + r.total, 0);
      const jauh = list.filter(r => r.selisih_pct != null && (r.selisih_pct <= -50 || r.selisih_pct >= 100));
      $('#audBuBoard').innerHTML = board([
        { k: 'Transaksi', v: n0(list.length), s: JAM_TXT[S.j] + (rows.length >= 1000 ? ', dibatasi 1.000 terakhir' : '') },
        { k: 'Nilai', v: idr(tot), s: 'gold berpindah lewat Bursa' },
        { k: 'Harga jauh dari dasar', v: n0(jauh.length), s: `separuh atau kurang, atau dua kali lipat, senilai ${idr(jauh.reduce((a, r) => a + r.total, 0))}` },
        { k: 'Kapten terlibat', v: n0(new Set(list.flatMap(r => [r.pembeli, r.penjual])).size), s: `${n0(new Set(list.map(r => r.penjual)).size)} penjual` },
      ], 4);
      const pair = {};
      for (const r of list) {
        const k = r.pembeli + '\u0000' + r.penjual;
        const o = pair[k] || (pair[k] = { pembeli: r.pembeli, penjual: r.penjual, n: 0, total: 0, dasar: 0 });
        o.n++; o.total += r.total; o.dasar += (r.harga_dasar || 0) * r.jumlah;
      }
      const pl = Object.values(pair).map(o => ({ ...o, selisih_pct: o.dasar ? Math.round(100 * (o.total / o.dasar - 1)) : null, selisih_gold: o.total - o.dasar }));
      const pe = $('#audBuPasang');
      if (!pl.length) empty(pe, `<b>Tidak ada transaksi Bursa</b> dalam ${esc(JAM_TXT[S.j])}.`);
      else pe.innerHTML = sortedTable('tBuPasang', [
        { h: 'Pembeli', k: 'pembeli', html: 1, f: r => nameBtn(r.pembeli), cls: () => 'name' },
        { h: 'Penjual', k: 'penjual', html: 1, f: r => nameBtn(r.penjual), cls: () => 'name' },
        { h: 'Kali', k: 'n', num: 1, f: r => n0(r.n) }, { h: 'Dibayar', k: 'total', num: 1, f: r => n0(r.total) },
        { h: 'Nilai dasar barang', k: 'dasar', num: 1, f: r => n0(r.dasar) },
        { h: 'Selisih gold', k: 'selisih_gold', num: 1, f: r => signed(r.selisih_gold) },
        { h: 'Selisih', k: 'selisih_pct', num: 1, f: r => pctS(r.selisih_pct), cls: r => r.selisih_pct != null && (r.selisih_pct <= -50 || r.selisih_pct >= 100) ? 'hot' : '' },
      ], pl, { s: 'total', d: 'desc' });
      const de = $('#audBuDaftar');
      if (!list.length) { empty(de, `<b>Tidak ada transaksi</b>${S.q ? ` yang cocok dengan "${esc(S.q)}"` : ''}.`); return; }
      de.innerHTML = sortedTable('tBuDaftar', [
        { h: 'Waktu (WIB)', k: 'waktu' },
        { h: 'Pembeli', k: 'pembeli', html: 1, f: r => nameBtn(r.pembeli), cls: () => 'name' },
        { h: 'Penjual', k: 'penjual', html: 1, f: r => nameBtn(r.penjual), cls: () => 'name' },
        { h: 'Barang', k: 'barang' }, { h: 'Tier', k: 'tier' },
        { h: 'Jumlah', k: 'jumlah', num: 1, f: r => n0(r.jumlah) }, { h: 'Harga satuan', k: 'harga_satuan', num: 1, f: r => n0(r.harga_satuan) },
        { h: 'Harga dasar', k: 'harga_dasar', num: 1, f: r => n0(r.harga_dasar) },
        { h: 'Selisih', k: 'selisih_pct', num: 1, f: r => pctS(r.selisih_pct), cls: r => r.selisih_pct != null && (r.selisih_pct <= -50 || r.selisih_pct >= 100) ? 'hot' : '' },
        { h: 'Total', k: 'total', num: 1, f: r => n0(r.total) },
      ], list, { s: 'waktu', d: 'desc' });
    });
    if (!D || D.bursa == null) ['#audBuPasang', '#audBuDaftar'].forEach(id => showErr($(id), (D && D.errors && D.errors.bursa) || 'tidak ada data', () => refreshAud(true)));
    part($('#audBuOrder'), 'bursaOrder', rows => {
      const list = rows.filter(r => match(r, ['penjual', 'pulau', 'barang']));
      if (!list.length) { empty($('#audBuOrder'), '<b>Tidak ada order terbuka.</b>'); return; }
      $('#audBuOrder').innerHTML = sortedTable('tBuOrder', [
        { h: 'Penjual', k: 'penjual', html: 1, f: r => nameBtn(r.penjual), cls: () => 'name' }, { h: 'Pulau', k: 'pulau' },
        { h: 'Barang', k: 'barang' }, { h: 'Tier', k: 'tier' }, { h: 'Jumlah', k: 'jumlah', num: 1, f: r => n0(r.jumlah) },
        { h: 'Harga satuan', k: 'harga_satuan', num: 1, f: r => n0(r.harga_satuan) }, { h: 'Harga dasar', k: 'harga_dasar', num: 1, f: r => n0(r.harga_dasar) },
        { h: 'Selisih', k: 'selisih_pct', num: 1, f: r => pctS(r.selisih_pct), cls: r => r.selisih_pct != null && (r.selisih_pct <= -50 || r.selisih_pct >= 100) ? 'hot' : '' },
        { h: 'Nilai', k: 'nilai', num: 1, f: r => n0(r.nilai) }, { h: 'Dipasang (WIB)', k: 'dipasang' },
      ], list, { s: 'nilai', d: 'desc' });
    });
  }

  // ---------- Jejak kapten ----------
  let JJ = null, JX = null;
  const JE_IDS = ['#audJeBoard', '#audJePenjaga', '#audJeKekayaan', '#audJeAliran', '#audJeTransfer', '#audJeLot', '#audJeLog'];
  async function fetchJejak() {
    if (!S.k) { JJ = null; JX = null; return; }
    JJ = await api(`/api/audit/jejak?kapten=${encodeURIComponent(S.k)}&jam=${encodeURIComponent(S.j)}`);
    const u = JJ.ringkas && JJ.ringkas[0] ? JJ.ringkas[0].username : '';
    const [kk, al, pj] = await Promise.all([u ? api('/api/kekayaan?u=' + encodeURIComponent(u)).catch(() => null) : null, api(`/api/aliran?jam=${encodeURIComponent(S.j)}`).catch(() => null), api('/api/penjaga').catch(() => null)]);
    JX = { u, kk, al, pj };
  }
  function renderJejakExtra() {
    const x = JX || {};
    const f = x.pj && x.pj.run && x.pj.run.temuan.find(t => t.username === x.u);
    const ai = x.pj && x.pj.run && x.pj.run.ai && x.pj.run.ai.kapten && x.pj.run.ai.kapten.find(k => k.username === x.u);
    const pel = $('#audJePenjaga'); pel.removeAttribute('aria-busy');
    pel.innerHTML = f ? `<div class="block"><h2>Temuan Penjaga ${st(f.tingkat === 'tinggi' ? 'bad' : f.tingkat === 'sedang' ? 'warn' : '', f.tingkat)}</h2><div class="find"><div class="body"><ul>${f.tanda.map(t => `<li><b>${esc(t.judul)}</b>: ${esc(t.bukti)}</li>`).join('')}</ul>${ai ? `<div class="ai"><b>AI, ${esc(ai.tingkat)}:</b> ${esc(ai.judul)}${ai.saran ? '. Saran: ' + esc(ai.saran) : ''}</div>` : ''}<p class="cap">Pindaian ${esc(new Date(x.pj.run.at).toLocaleString('id-ID'))}${f.aman ? ', ditandai aman' : ''}. <a class="go" href="#/penjaga">Buka Penjaga</a></p></div></div></div>` : '';
    const kel = $('#audJeKekayaan'); kel.removeAttribute('aria-busy');
    const seri = x.kk && x.kk.seri || [];
    if (seri.length < 2) empty(kel, '<b>Belum cukup snapshot.</b> Grafik terisi setelah panel mencatat dua snapshot (tiap 30 menit).');
    else {
      const W = 400, H = 140, P = 6, t0 = seri[0].t, t1 = seri[seri.length - 1].t, vs = seri.map(p => p.kekayaan), lo = Math.min(...vs), hi = Math.max(...vs), sp = hi - lo || 1;
      const X = t => P + (W - 2 * P) * (t - t0) / Math.max(1, t1 - t0), Y = v => H - P - (H - 2 * P) * (v - lo) / sp;
      const dd = seri.map((p, i) => (i ? 'L' : 'M') + X(p.t).toFixed(1) + ' ' + Y(p.kekayaan).toFixed(1)).join('');
      kel.innerHTML = `<div class="chart"><p class="cap">kini ${esc(idr(vs[vs.length - 1]))}, awal ${esc(idr(vs[0]))}, tertinggi ${esc(idr(hi))}</p><svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Kekayaan ${esc(S.k)} dari ${esc(idr(vs[0]))} ke ${esc(idr(vs[vs.length - 1]))}"><path class="c-area" d="${dd}L${X(t1).toFixed(1)} ${H - P}L${X(t0).toFixed(1)} ${H - P}Z"/><path class="c-line" d="${dd}"/></svg>
        <div class="axis"><span>${esc(new Date(t0).toLocaleDateString('id-ID', { day: '2-digit', month: 'short' }))}</span><span>${esc(new Date(t1).toLocaleDateString('id-ID', { day: '2-digit', month: 'short' }))}</span></div></div>`;
    }
    const ael = $('#audJeAliran'); ael.removeAttribute('aria-busy');
    const rows = (x.al && x.al.matriks || []).filter(r => r.kapten === S.k && r.arah !== 0);
    ael.innerHTML = rows.length ? table([{ h: 'Kategori', k: 'kat', cls: () => 'name' }, { h: 'Arah', k: 'arah', html: 1, f: r => st(r.arah > 0 ? 'ok' : '', r.arah > 0 ? 'masuk' : 'keluar') }, { h: 'Kejadian', k: 'kejadian', num: 1, f: r => n0(r.kejadian) }, { h: 'Gold', k: 'gold', num: 1, f: r => n0(r.gold) }], rows, { tall: true }) : '<div class="empty">Tidak ada catatan gold dalam rentang ini.</div>';
  }
  function renderJejak() {
    fillKapten();
    if (S.k) renderJejakExtra();
    if (!S.k) {
      empty($('#audJeBoard'), '<b>Pilih kapten</b> dari daftar, atau klik nama kapten di bagian lain.');
      JE_IDS.slice(1).forEach(id => { $(id).innerHTML = ''; $(id).removeAttribute('aria-busy'); });
      return;
    }
    const jp = (el, key, fn) => {
      if (!JJ || JJ[key] == null) { showErr(el, (JJ && JJ.errors && JJ.errors[key]) || 'tidak ada data', () => refreshAud(false)); return; }
      el.removeAttribute('aria-busy'); fn(JJ[key]);
    };
    jp($('#audJeBoard'), 'ringkas', rows => {
      const r = rows[0]; if (!r) { empty($('#audJeBoard'), `<b>Kapten "${esc(S.k)}" tidak ditemukan.</b>`); return; }
      const p = (JJ.pola && JJ.pola[0]) || {};
      $('#audJeBoard').innerHTML = board([
        { k: 'Kekayaan', v: idr(r.gold + r.bank), s: `gold ${n0(r.gold)}, bank ${n0(r.bank)}${r.utang ? `, utang ${n0(r.utang)}` : ''}` },
        { k: 'Nilai gudang', v: idr(r.nilai_gudang), s: `palka ${idr(r.nilai_palka)}, harga dasar` },
        { k: 'Keping', v: n0(r.keping), s: `${esc(r.username)}, ${esc(r.arketipe)}` },
        { k: 'Umur akun', v: NF1.format(r.umur_hari) + ' hari', s: `bergabung ${r.bergabung}` },
        { k: 'Transaksi pasar', v: n0(p.transaksi), s: `${JAM_TXT[S.j]}, jeda median ${p.jeda_median == null ? '-' : NF1.format(p.jeda_median) + ' detik'}` },
        { k: 'Jeda di bawah 2 detik', v: n0(p.jeda_bawah_2), s: `${pct1(p.jeda_bawah_2_pct)} dari semua jeda, terakhir aktif ${r.terakhir_aktif}`, level: p.jeda_bawah_2_pct >= 60 ? 'bad' : p.jeda_bawah_2_pct >= 30 ? 'warn' : '' },
      ], 6);
    });
    jp($('#audJeTransfer'), 'transfer', rows => {
      if (!rows.length) { empty($('#audJeTransfer'), `<b>Tidak ada transfer</b> dalam ${esc(JAM_TXT[S.j])}.`); return; }
      const masuk = rows.filter(r => r.arah === 'masuk').reduce((a, r) => a + r.jumlah, 0), keluar = rows.filter(r => r.arah === 'keluar').reduce((a, r) => a + r.jumlah, 0);
      $('#audJeTransfer').innerHTML = `<p class="cap">Masuk ${esc(n0(masuk))}, keluar ${esc(n0(keluar))}, bersih ${esc(signed(masuk - keluar))} gold.</p>` + sortedTable('tJeTr', [
        { h: 'Waktu (WIB)', k: 'waktu' }, { h: 'Arah', k: 'arah', cls: r => r.arah === 'masuk' ? 'pos' : '' },
        { h: 'Lawan', k: 'lawan', html: 1, f: r => nameBtn(r.lawan), cls: () => 'name' }, { h: 'Gold', k: 'jumlah', num: 1, f: r => n0(r.jumlah) },
      ], rows, { s: 'waktu', d: 'desc' });
    });
    jp($('#audJeLot'), 'hakLot', rows => {
      if (!rows.length) { empty($('#audJeLot'), '<b>Tidak memakai Hak Lot</b> dalam 14 hari.'); return; }
      $('#audJeLot').innerHTML = table([{ h: 'Hari', k: 'hari' }, { h: 'Pulau', k: 'pulau' }, { h: 'Lot', k: 'lot', num: 1, f: r => n0(r.lot) }], rows, { tall: true });
    });
    jp($('#audJeLog'), 'log', rows => {
      const q = S.q.trim().toLowerCase(), list = q ? rows.filter(r => r.catatan.toLowerCase().includes(q)) : rows;
      if (!list.length) { empty($('#audJeLog'), `<b>Tidak ada catatan</b>${q ? ` yang memuat "${esc(S.q)}"` : ` dalam ${esc(JAM_TXT[S.j])}`}.`); return; }
      $('#audJeLog').innerHTML = table([{ h: 'Waktu (WIB)', k: 'waktu' }, { h: 'Catatan', k: 'catatan', cls: () => 'wrap' }], list, { tall: true });
    });
  }

  // ---------- tampilan ----------
  const IDS = {
    aliran: ['#audAlBoard', '#audAlMasuk', '#audAlKeluar', '#audAlHarian', '#audAlKapten', '#audAlNol'],
    gudang: ['#audGudBoard', '#audGudKapten', '#audGudRinci', '#audGudArus'],
    transfer: ['#audTrBoard', '#audTrTerima', '#audTrKirim', '#audTrPasang', '#audTrDaftar'],
    bursa: ['#audBuBoard', '#audBuPasang', '#audBuDaftar', '#audBuOrder'],
    jejak: JE_IDS,
  };
  function renderAll() { if (S.b === 'aliran') renderAliran(); else if (S.b === 'gudang') renderGudang(); else if (S.b === 'transfer') renderTransfer(); else if (S.b === 'bursa') renderBursa(); else renderJejak(); }
  function syncControls() {
    $$('#audBagian button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.b === S.b)));
    $$('#audJam button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.j === S.j)));
    $$('section[data-panel="audit"] [data-aud]').forEach(el => el.classList.toggle('hidden', el.dataset.aud !== S.b));
    $('#audCari').value = S.q; $('#audPalka').checked = S.palka;
    $('#audCari').placeholder = S.b === 'jejak' ? 'Saring isi catatan' : S.b === 'transfer' ? 'Cari pengirim atau penerima' : S.b === 'aliran' ? 'Cari kapten atau sumber' : 'Cari kapten, pulau, atau barang';
  }
  async function refreshAud(force) {
    syncControls();
    const ids = IDS[S.b];
    if (force) ids.forEach(id => { const e = $(id); if (e) delete e.dataset.ready; });
    await load(ids, async () => {
      if (S.b === 'aliran') { if (!AL || force || AL.jam !== (S.j === 'semua' ? null : +S.j)) await fetchAliran(force); if (!D) fetchMain(false).catch(() => {}); }
      else if (!D || force || D.jam !== (S.j === 'semua' ? null : +S.j)) await fetchMain(force);
      if (S.b === 'jejak') await fetchJejak();
      renderAll();
    });
  }
  loaders.audit = () => { readParams(); return refreshAud(false); };

  $('#audRefresh').addEventListener('click', async () => { const b = $('#audRefresh'); b.disabled = true; try { await refreshAud(true); toast('Audit dimuat ulang.'); } catch (e) { toast(e.message); } b.disabled = false; });
  $('#audBagian').addEventListener('click', e => { const b = e.target.closest('button'); if (!b || b.dataset.b === S.b) return; S.b = b.dataset.b; S.q = ''; writeParams(); refreshAud(false); });
  $('#audJam').addEventListener('click', e => { const b = e.target.closest('button'); if (!b || b.dataset.j === S.j) return; S.j = b.dataset.j; writeParams(); refreshAud(false); });
  let cariT;
  $('#audCari').addEventListener('input', e => { S.q = e.target.value; clearTimeout(cariT); cariT = setTimeout(() => { writeParams(); renderAll(); }, 150); });
  $('#audPalka').addEventListener('change', e => { S.palka = e.target.checked; renderGudang(); });
  $('#audKapten').addEventListener('change', e => { S.k = e.target.value; writeParams(); refreshAud(false); });
  // klik nama kapten di tabel mana pun membuka Jejak; klik judul kolom mengurutkan
  $('section[data-panel="audit"]').addEventListener('click', e => {
    const al = e.target.closest('button[data-al]');
    if (al) { S.ak = al.dataset.al; renderAlRinci(); if (S.ak) $('#audAlRinci').scrollIntoView({ block: 'nearest' }); return; }
    const n = e.target.closest('button[data-kapten]');
    if (n) { S.k = n.dataset.kapten; S.b = 'jejak'; S.q = ''; writeParams(); fillKapten(); refreshAud(false); window.scrollTo({ top: 0 }); return; }
    const th = e.target.closest('th button'); if (!th) return;
    const tb = th.closest('table'); if (!tb || !tb.id || !sorts[tb.id]) return;
    const k = th.closest('th').dataset.k, st = sorts[tb.id];
    st.d = st.s === k ? (st.d === 'asc' ? 'desc' : 'asc') : (TEXT_KEYS.has(k) || k === 'waktu' ? (k === 'waktu' ? 'desc' : 'asc') : 'desc'); st.s = k;
    renderAll();
  });
})();
