'use strict';
// Tab Ekonomi dan Kapten. Memakai helper dari app.js lewat window.OPS.
(() => {
  const { $, $$, esc, n0, idr, signed, api, toast, board, table, load, empty, showErr, setVars, loaders, NF1 } = window.OPS;
  const pct1 = v => v == null || isNaN(+v) ? '-' : NF1.format(+v) + '%';
  const part = (el, d, key, fn) => {
    if (d[key] == null) { showErr(el, (d.errors && d.errors[key]) || 'tidak ada data', () => window.OPS.refresh()); return; }
    el.removeAttribute('aria-busy'); fn(d[key]);
  };

  // ---------- batang mendatar (HTML, lebar lewat variabel CSS) ----------
  // rows: [{ label, sub, segs: [{ w (persen 0-100), cls }], value, hot }]
  function hbars(rows) {
    if (!rows.length) return '<div class="empty">Tidak ada.</div>';
    return `<div class="hb">${rows.map(r => `<div class="hb-row"${r.title ? ` title="${esc(r.title)}"` : ''}>
      <div class="hb-l"><span>${esc(r.label)}</span>${r.sub ? `<small>${esc(r.sub)}</small>` : ''}</div>
      <div class="hb-t">${r.segs.map(s => `<i class="${s.cls}" data-w="${Math.max(0, Math.min(100, s.w)).toFixed(2)}"></i>`).join('')}</div>
      <div class="hb-v${r.hot ? ' hot' : ''}">${esc(r.value)}</div></div>`).join('')}</div>`;
  }

  // ---------- batang tegak (SVG) untuk deret harian yang bisa negatif ----------
  function vbars(rows, { key, fmt, dateKey }) {
    const W = 560, H = 170, mt = 8, mb = 6, n = rows.length;
    const vals = rows.map(r => +r[key] || 0);
    const lo = Math.min(0, ...vals), hi = Math.max(1, ...vals);
    const y = v => mt + (H - mt - mb) * (hi - v) / (hi - lo);
    const bw = (W / n) * 0.7, gap = W / n;
    const bars = rows.map((r, i) => {
      const v = vals[i], top = Math.min(y(v), y(0)), h = Math.max(1, Math.abs(y(v) - y(0)));
      const last = i === n - 1;
      return `<rect class="${v < 0 ? 'c-bar-neg' : 'c-bar'}" x="${(i * gap + (gap - bw) / 2).toFixed(1)}" y="${top.toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}"${last ? ' opacity="0.55"' : ''}><title>${esc(r[dateKey])}${last ? ' (berjalan)' : ''}: ${esc(fmt(v))}</title></rect>`;
    }).join('');
    return `<div class="chart"><svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="Laba dagang harian, ${rows.length} hari, terakhir ${esc(fmt(vals[n - 1]))}">
      <line class="c-grid" x1="0" x2="${W}" y1="${y(hi).toFixed(1)}" y2="${y(hi).toFixed(1)}"/><line class="c-axis" x1="0" x2="${W}" y1="${y(0).toFixed(1)}" y2="${y(0).toFixed(1)}"/>${bars}</svg>
      <div class="axis"><span>${esc(rows[0][dateKey].slice(5))}</span><span>tertinggi ${esc(fmt(Math.max(...vals)))}, terendah ${esc(fmt(Math.min(...vals)))}</span><span>${esc(rows[n - 1][dateKey].slice(5))}</span></div></div>`;
  }

  // ---------- garis tren dari snapshot harian ----------
  function trend(title, pts, key, fmt) {
    const W = 400, H = 140, P = 6;
    const ok = pts.filter(p => p[key] != null);
    if (ok.length < 2) return '';
    const vs = ok.map(p => +p[key]); const lo = Math.min(...vs), hi = Math.max(...vs), span = hi - lo || 1;
    const t0 = Date.parse(ok[0].hari), t1 = Date.parse(ok[ok.length - 1].hari);
    const x = p => P + (W - 2 * P) * (Date.parse(p.hari) - t0) / Math.max(1, t1 - t0);
    const y = v => H - P - (H - 2 * P) * (v - lo) / span;
    const d = ok.map((p, i) => (i ? 'L' : 'M') + x(p).toFixed(1) + ' ' + y(+p[key]).toFixed(1)).join('');
    const area = `${d}L${x(ok[ok.length - 1]).toFixed(1)} ${H - P}L${x(ok[0]).toFixed(1)} ${H - P}Z`;
    return `<div class="chart"><h3>${esc(title)}</h3><p class="cap">kini ${esc(fmt(vs[vs.length - 1]))}, awal ${esc(fmt(vs[0]))}</p>
      <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" role="img" aria-label="${esc(title)}: dari ${esc(fmt(vs[0]))} ke ${esc(fmt(vs[vs.length - 1]))}">
      <line class="c-grid" x1="0" x2="${W}" y1="${y(lo + span / 2)}" y2="${y(lo + span / 2)}"/><path class="c-area" d="${area}"/><path class="c-line" d="${d}"/></svg>
      <div class="axis"><span>${esc(ok[0].hari.slice(5))}</span><span>${esc(ok[ok.length - 1].hari.slice(5))}</span></div></div>`;
  }

  // ---------- Ekonomi ----------
  let pemainCache = null;
  async function loadEko(force) {
    const q = force ? '?fresh=1' : '';
    const [d, k] = await Promise.all([api('/api/ekonomi' + q), api('/api/kapten' + q).catch(() => null)]);
    pemainCache = k;
    $('#ekoStamp').textContent = 'Diambil ' + new Date(d.at).toLocaleTimeString('id-ID');

    part($('#ekoBoard'), d, 'ringkasan', rows => {
      const r = rows[0]; if (!r) { empty($('#ekoBoard'), 'Belum ada pemain.'); return; }
      $('#ekoBoard').innerHTML = board([
        { k: 'Online sekarang', v: n0(r.online_sekarang), s: `${n0(r.aktif_24j)} aktif 24 jam dari ${n0(r.pemain)} kapten` },
        { k: 'Total kekayaan', v: idr(r.total_kekayaan), s: `median per kapten ${idr(r.median_kekayaan)}` },
        { k: 'Saldo bank', v: idr(r.total_bank), s: `gold di tangan ${idr(r.total_gold)}` },
        { k: 'Bunga bank per hari nyata', v: idr(r.bunga_per_hari), s: `${n0(r.bunga_per_hari_game)} per hari game, bertingkat` },
        { k: 'Laba dagang, 24 jam', v: signed(r.laba_dagang_24j), s: 'hasil jual dikurangi biaya beli', level: r.laba_dagang_24j < 0 ? 'warn' : '' },
        { k: 'Pangsa kapten terkaya', v: pct1(r.pangsa_terkaya_pct), s: `3 terkaya ${pct1(r.pangsa_top3_pct)}, Gini ${r.gini == null ? '-' : NF1.format(r.gini)}`, level: r.pangsa_terkaya_pct >= 30 ? 'warn' : '' },
      ], 6);
      const rasio = r.laba_dagang_24j > 0 && r.rasio_bunga_dagang != null ? `, ${NF1.format(r.rasio_bunga_dagang)} kali laba dagang semua pemain dalam 24 jam terakhir` : `, sementara dagang semua pemain dalam 24 jam terakhir ${r.laba_dagang_24j < 0 ? 'rugi ' + n0(-r.laba_dagang_24j) : 'tidak menghasilkan laba'} gold`;
      $('#ekoTake').innerHTML = `Bunga bank menambah <b>${esc(n0(r.bunga_per_hari))}</b> gold per hari nyata${esc(rasio)}. Pemain terkaya memegang <b>${esc(pct1(r.pangsa_terkaya_pct))}</b> dari seluruh kekayaan server. Data per ${esc(r.diperbarui_wib)} WIB.`;
    });

    // kekayaan 12 kapten teratas, dipecah bank dan gold
    const kaya = $('#ekoKaya');
    if (!k || k.pemain == null) showErr(kaya, (k && k.errors && k.errors.pemain) || 'data kapten tidak terbaca', () => window.OPS.refresh());
    else {
      const top = k.pemain.slice().sort((a, b) => b.kekayaan - a.kekayaan).slice(0, 12), mx = top[0] ? top[0].kekayaan : 1;
      kaya.innerHTML = `<div class="legend"><span><i class="sq sq-bank"></i>saldo bank</span><span><i class="sq sq-gold"></i>gold di tangan</span></div>` + hbars(top.map(r => ({
        label: r.pemain, sub: `bunga ${n0(r.bunga_per_hari)} per hari`,
        segs: [{ w: 100 * r.bank / mx, cls: 'seg-bank' }, { w: 100 * r.gold / mx, cls: 'seg-gold' }],
        value: pct1(r.pangsa_pct), hot: r.pangsa_pct >= 20, title: `${r.pemain}: bank ${n0(r.bank)}, gold ${n0(r.gold)}` })));
      setVars(kaya); kaya.removeAttribute('aria-busy');
    }

    part($('#ekoDagang'), d, 'dagang', rows => {
      const el = $('#ekoDagang');
      el.innerHTML = vbars(rows, { key: 'laba', fmt: signed, dateKey: 'hari' });
    });

    part($('#ekoArus'), d, 'arus', rows => {
      const el = $('#ekoArus'), mx = Math.max(1, ...rows.map(r => Math.abs(r.gold)));
      if (!rows.length) { empty(el, '<b>Belum ada catatan.</b> Tidak ada kejadian bergold dalam 24 jam terakhir.'); return; }
      el.innerHTML = hbars(rows.map(r => ({ label: r.arus, sub: `${n0(r.kejadian)} kejadian, ${n0(r.pemain)} kapten`,
        segs: [{ w: 100 * Math.abs(r.gold) / mx, cls: /bank/i.test(r.arus) ? 'seg-gold' : 'seg-bank' }], value: idr(r.gold) })));
      setVars(el);
    });

    // tren dari snapshot
    const tren = $('#ekoTren'), rw = d.riwayat || [];
    if (rw.length < 2) empty(tren, `<b>Belum cukup data.</b> ${rw.length ? `Snapshot pertama dicatat ${esc(rw[0].hari)}.` : 'Snapshot pertama dicatat sebentar lagi.'} Grafik muncul setelah dua hari tercatat.`);
    else tren.innerHTML = `<div class="charts">${[
      trend('Total kekayaan', rw, 'kekayaan', idr), trend('Bunga bank per hari', rw, 'bunga', idr),
      trend('Gini', rw, 'gini', v => NF1.format(v)), trend('Pangsa kapten terkaya', rw, 'top1', pct1),
      trend('Kolam IKN', rw, 'ikn', idr), trend('Keping beredar', rw, 'keping', n0)].join('')}</div>`;
    tren.removeAttribute('aria-busy');

    part($('#ekoIkn'), d, 'ikn', rows => {
      const el = $('#ekoIkn'), r = rows[0]; if (!r) { empty(el, 'Proyek IKN tidak ditemukan.'); return; }
      const stages = Array.isArray(r.tahap_daftar) ? r.tahap_daftar : [];
      const target = stages.length ? stages.reduce((a, s) => a + (+s.need || 0), 0) : d.iknTarget;
      el.innerHTML = board([
        { k: 'Terkumpul', v: idr(r.total), s: `dari target ${idr(target)}` },
        { k: 'Sisa ke target', v: idr(Math.max(0, target - r.total)), s: r.selesai ? 'selesai' : `tahap ${r.tahap} tercapai` },
        { k: 'Donatur', v: n0(r.donatur), s: `terbesar ${idr(r.donatur_terbesar)}` },
        { k: 'Gold langsung', v: idr(r.dari_gold), s: `${n0(r.dari_keping)} keping ikut` },
        { k: 'Kongsi', v: idr(r.dari_kongsi), s: 'kerugian dan sumbangan Ki Dorus' },
        { k: 'Quest rahasia', v: idr(r.dari_duneks + r.dari_jtq), s: `Gudang Door ${idr(r.dari_duneks)}, J.T. ${idr(r.dari_jtq)}` },
      ], 6);
      let cum = 0;
      const cells = stages.map(s => {
        const from = cum; cum += +s.need;
        const state = r.total >= cum ? 'done' : (r.total >= from ? 'now' : 'next');
        const p = state === 'done' ? 100 : state === 'now' ? 100 * (r.total - from) / s.need : 0;
        return `<div class="stage" data-state="${state}"><span class="n">Tahap ${esc(s.n)}</span><span class="t">${esc(s.name)}</span><span class="m">${idr(from)} sampai ${idr(cum)}</span><span class="meter"><b data-p="${p.toFixed(1)}"></b></span></div>`;
      }).join('');
      el.insertAdjacentHTML('beforeend', `<div class="stages" aria-label="Tahap restorasi">${cells}</div>`);
      setVars(el);
    });

    part($('#ekoKongsi'), d, 'kongsiTier', rows => {
      const el = $('#ekoKongsi'); if (!rows.length) { empty(el, '<b>Belum ada kongsi.</b>'); return; }
      const by = {};
      for (const r of rows) {
        const t = by[r.tier] || (by[r.tier] = { tier: r.tier, selesai: 0, panggil: 0, jalan: 0, modal: 0, bayar: 0 });
        if (r.status === 'pulang') t.selesai += r.n; else if (r.status === 'panggil') t.panggil += r.n; else t.jalan += r.n;
        if (r.status === 'pulang' || r.status === 'panggil') { t.modal += r.modal; t.bayar += r.bayar; }
      }
      const list = Object.values(by);
      el.innerHTML = table([
        { h: 'Tingkat', k: 'tier', cls: () => 'name' }, { h: 'Pulang', k: 'selesai', num: 1, f: r => n0(r.selesai) }, { h: 'Dipanggil', k: 'panggil', num: 1, f: r => n0(r.panggil) },
        { h: 'Berjalan', k: 'jalan', num: 1, f: r => n0(r.jalan) }, { h: 'Modal', k: 'modal', num: 1, f: r => idr(r.modal) }, { h: 'Dibayar', k: 'bayar', num: 1, f: r => idr(r.bayar) },
        { h: 'Rasio', k: 'rasio', num: 1, f: r => r.modal ? Math.round(100 * r.bayar / r.modal) + '%' : '-', cls: r => r.modal && r.bayar > r.modal ? 'pos' : '' },
      ], list);
      if (d.kongsiMinggu && d.kongsiMinggu.length) el.insertAdjacentHTML('beforeend', `<h3 class="sub-h">Per minggu</h3>` + table([
        { h: 'Minggu', k: 'minggu' }, { h: 'Modal', k: 'modal', num: 1, f: r => idr(r.modal) }, { h: 'Dibayar', k: 'bayar', num: 1, f: r => idr(r.bayar) },
        { h: 'Laba Kongsi', k: 'laba', num: 1, f: r => signed(r.laba) }, { h: 'Donasi IKN', k: 'donasi', num: 1, f: r => idr(r.donasi) }, { h: 'Pengongsi', k: 'pengongsi', num: 1, f: r => n0(r.pengongsi) },
      ], d.kongsiMinggu));
    });

    part($('#ekoKeping'), d, 'keping', rows => {
      const el = $('#ekoKeping'), t = d.kepingTotal && d.kepingTotal[0];
      el.innerHTML = (t ? board([
        { k: 'Beredar', v: n0(t.beredar), s: 'saldo semua kapten' }, { k: 'Terbit, sepanjang masa', v: n0(t.terbit), s: 'keping dibagikan' }, { k: 'Terpakai, sepanjang masa', v: n0(t.terpakai), s: 'dibelanjakan atau disumbang' },
      ], 4) : '') + (rows.length ? table([
        { h: 'Sumber, 7 hari', k: 'sumber', cls: () => 'name' }, { h: 'Kejadian', k: 'n', num: 1, f: r => n0(r.n) }, { h: 'Terbit', k: 'terbit', num: 1, f: r => n0(r.terbit) }, { h: 'Terpakai', k: 'terpakai', num: 1, f: r => n0(r.terpakai) },
      ], rows) : '<div class="empty">Tidak ada perubahan keping dalam 7 hari.</div>');
    });

    part($('#ekoTony'), d, 'tony', rows => {
      const el = $('#ekoTony'), r = rows[0]; if (!r) { empty(el, 'Belum ada data.'); return; }
      el.innerHTML = board([
        { k: 'Korban', v: n0(r.korban), s: 'kali dicegat' }, { k: 'Emas dirampas', v: idr(r.emas), s: 'dari kantong pemain' },
        { k: 'Kargo dirampas', v: idr(r.kargo), s: 'nilai barang' }, { k: 'Perburuan', v: n0(r.perburuan), s: `harta ${idr(r.harta)}, dibayar ${idr(r.dibayar)}` },
      ], 4);
      if (d.tonyBuru && d.tonyBuru.length) el.insertAdjacentHTML('beforeend', table([
        { h: 'Rabu', k: 'hari' }, { h: 'Harta', k: 'harta', num: 1, f: r => idr(r.harta) }, { h: 'Kolam', k: 'pool', num: 1, f: r => idr(r.pool) },
        { h: 'Dibayar', k: 'dibayar', num: 1, f: r => idr(r.dibayar) }, { h: 'Peserta', k: 'peserta', num: 1, f: r => n0(r.peserta) }, { h: 'Tony kabur', k: 'kabur', f: r => r.kabur ? 'ya' : 'belum' },
      ], d.tonyBuru));
    });

    part($('#ekoPacu'), d, 'pacu', rows => {
      $('#ekoPacu').innerHTML = rows.length ? table([
        { h: 'Sabtu', k: 'sabtu' }, { h: 'Tema', k: 'tema' }, { h: 'Status', k: 'status' }, { h: 'Peserta', k: 'peserta', num: 1, f: r => n0(r.peserta) }, { h: 'Laba peserta', k: 'laba_peserta', num: 1, f: r => idr(r.laba_peserta) },
      ], rows) : '<div class="empty">Belum ada Pacu Dagang.</div>';
    });

    part($('#ekoStok'), d, 'stok', rows => {
      const el = $('#ekoStok'); if (!rows.length) { empty(el, 'Tidak ada data pasar.'); return; }
      const maxR = Math.max(1, ...rows.map(r => r.rasio_stok));
      el.innerHTML = table([
        { h: 'Barang', k: 'barang', cls: () => 'name' }, { h: 'Tier', k: 'tier' },
        { h: 'Stok rata-rata', k: 'rasio_stok', num: 1, html: 1, f: r => `<span class="bar-cell"><i data-w="${Math.max(2, Math.round(60 * r.rasio_stok / maxR))}"${r.rasio_stok < 0.3 ? ' data-level="bad"' : ''}></i><span>${Math.round(r.rasio_stok * 100)}%</span></span>` },
        { h: 'Stok terbaik', k: 'rasio_terbaik', num: 1, f: r => Math.round(r.rasio_terbaik * 100) + '%' },
        { h: 'Kota menipis', k: 'kota_menipis', num: 1, f: r => `${r.kota_menipis} dari ${r.kota}`, cls: r => r.kota_menipis > 0 ? 'hot' : 'dim' },
        { h: 'Beli 24 jam', k: 'beli_24j', num: 1, f: r => n0(r.beli_24j) }, { h: 'Pembeli', k: 'pembeli_24j', num: 1, f: r => n0(r.pembeli_24j) },
        { h: 'Harga min', k: 'harga_min', num: 1, f: r => n0(r.harga_min) }, { h: 'Harga maks', k: 'harga_max', num: 1, f: r => n0(r.harga_max) },
      ], rows, { tall: true });
      setVars(el);
    });
  }
  const EKO_IDS = ['#ekoBoard', '#ekoKaya', '#ekoDagang', '#ekoArus', '#ekoTren', '#ekoIkn', '#ekoKongsi', '#ekoKeping', '#ekoTony', '#ekoPacu', '#ekoStok'];
  loaders.ekonomi = () => load(EKO_IDS, () => loadEko(false));
  $('#ekoRefresh').addEventListener('click', async () => { const b = $('#ekoRefresh'); b.disabled = true; try { await loadEko(true); toast('Ekonomi dimuat ulang.'); } catch (e) { toast(e.message); } b.disabled = false; });

  // ---------- Kapten ----------
  const P = { q: '', s: 'kekayaan', d: 'desc', cq: '' };
  function readParams() {
    const h = location.hash, i = h.indexOf('?'); if (i < 0) return;
    const u = new URLSearchParams(h.slice(i + 1));
    P.q = u.get('q') || ''; P.s = u.get('s') || 'kekayaan'; P.d = u.get('d') === 'asc' ? 'asc' : 'desc'; P.cq = u.get('cq') || '';
  }
  function writeParams() {
    const u = new URLSearchParams();
    if (P.q) u.set('q', P.q); if (P.cq) u.set('cq', P.cq);
    if (P.s !== 'kekayaan' || P.d !== 'desc') { u.set('s', P.s); u.set('d', P.d); }
    const qs = u.toString();
    history.replaceState(null, '', location.pathname + location.search + '#/kapten' + (qs ? '?' + qs : ''));
  }
  const LEFT = ['pemain', 'arketipe', 'kapal', 'lokasi', 'bergabung', 'jam_sejak_aktif'];
  const levelOf = h => h < 1 ? 'ok' : h < 24 ? 'warn' : '';
  const sagaKey = s => /4/.test(s) ? 's4' : /3/.test(s) ? 's3' : /2/.test(s) ? 's2' : /1/.test(s) ? 's1' : '';
  let kapData = null;

  function renderKapTabel() {
    const el = $('#kapTabel'); if (!kapData || !kapData.pemain) return;
    const q = P.q.trim().toLowerCase();
    const rows = kapData.pemain.filter(r => !q || [r.pemain, r.arketipe, r.lokasi].some(v => String(v || '').toLowerCase().includes(q)))
      .sort((a, b) => { const x = a[P.s], y = b[P.s]; return (typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y))) * (P.d === 'asc' ? 1 : -1); });
    if (!rows.length) { empty(el, `<b>Tidak ada kapten</b> yang cocok dengan "${esc(P.q)}".`); return; }
    const col = (h, k, o = {}) => ({ h, k, sort: 1, aria: P.s === k ? (P.d === 'asc' ? 'ascending' : 'descending') : undefined, ...o });
    el.innerHTML = table([
      col('Kapten', 'pemain', { cls: () => 'name' }), col('Arketipe', 'arketipe'), col('Kapal', 'kapal'), col('Lokasi', 'lokasi'),
      col('Gold', 'gold', { num: 1, f: r => n0(r.gold), cls: r => r.gold === 0 ? 'dim' : '' }), col('Bank', 'bank', { num: 1, f: r => n0(r.bank), cls: r => r.bank === 0 ? 'dim' : '' }),
      col('Kekayaan', 'kekayaan', { num: 1, f: r => n0(r.kekayaan) }), col('Pangsa %', 'pangsa_pct', { num: 1, f: r => NF1.format(r.pangsa_pct), cls: r => r.pangsa_pct >= 20 ? 'hot' : '' }),
      col('Bunga/hari', 'bunga_per_hari', { num: 1, f: r => n0(r.bunga_per_hari), cls: r => r.bunga_per_hari === 0 ? 'dim' : '' }),
      col('Laba dagang 24j', 'selisih_dagang_24j', { num: 1, f: r => signed(r.selisih_dagang_24j), cls: r => r.selisih_dagang_24j < 0 ? 'neg' : r.selisih_dagang_24j > 0 ? 'pos' : 'dim' }),
      col('Layar 24j', 'layar_24j', { num: 1, f: r => n0(r.layar_24j) }), col('Nilai muatan', 'nilai_muatan', { num: 1, f: r => n0(r.nilai_muatan) }),
      col('Buku', 'buku', { num: 1, f: r => n0(r.buku) }), col('Utang', 'utang', { num: 1, f: r => n0(r.utang), cls: r => r.utang === 0 ? 'dim' : '' }),
      col('Aktif (jam lalu)', 'jam_sejak_aktif', { num: 1, html: 1, f: r => `<i class="sq" data-level="${levelOf(r.jam_sejak_aktif)}"></i> ${NF1.format(r.jam_sejak_aktif)}` }), col('Bergabung', 'bergabung'),
    ], rows, { tall: true });
  }
  function renderQuestTabel() {
    const el = $('#kapQuest'); if (!kapData || !kapData.questPemain) return;
    const q = P.cq.trim().toLowerCase();
    const rows = kapData.questPemain.filter(r => !q || [r.pemain, r.saga, r.quest_kini, r.quest_tamat, r.sampingan].some(v => String(v || '').toLowerCase().includes(q)));
    if (!rows.length) { empty(el, `<b>Tidak ada hasil</b> untuk "${esc(P.cq)}".`); return; }
    el.innerHTML = table([
      { h: 'Kapten', k: 'pemain', cls: () => 'name' },
      { h: 'Saga', k: 'saga', html: 1, f: r => `<span class="saga" data-s="${sagaKey(r.saga)}">${esc(r.saga)}</span>` },
      { h: 'Quest sekarang', k: 'quest_kini', cls: r => r.quest_no == null ? 'dim' : '' },
      { h: 'Langkah', k: 'langkah', html: 1, f: r => r.langkah == null ? '' : `<span class="steps">${r.langkah_akhir ? `<i><b data-p="${Math.min(100, Math.round(100 * r.langkah / r.langkah_akhir))}"></b></i>` : ''}<span>${n0(r.langkah)}${r.langkah_akhir ? ' dari ' + n0(r.langkah_akhir) : ''}</span></span>` },
      { h: 'Quest tamat', k: 'tamat', num: 1, f: r => n0(r.tamat), cls: r => r.tamat === 0 ? 'dim' : '' },
      { h: 'Daftar tamat', k: 'quest_tamat', cls: () => 'wrap dim' }, { h: 'Sampingan', k: 'sampingan', cls: () => 'wrap' },
      { h: 'Jejak Perantau', k: 'jejak_perantau', num: 1, f: r => r.jejak_perantau == null ? '' : n0(r.jejak_perantau), cls: () => 'dim' },
      { h: 'Gerak terakhir', k: 'gerak_terakhir' },
      { h: 'Aktif (jam lalu)', k: 'jam_sejak_aktif', num: 1, html: 1, f: r => `<i class="sq" data-level="${levelOf(r.jam_sejak_aktif)}"></i> ${NF1.format(r.jam_sejak_aktif)}` },
    ], rows, { tall: true });
    setVars(el);
  }

  async function loadKap(force) {
    const d = await api('/api/kapten' + (force ? '?fresh=1' : ''));
    kapData = d;
    $('#kapStamp').textContent = 'Diambil ' + new Date(d.at).toLocaleTimeString('id-ID');
    part($('#kapBoard'), d, 'pemain', rows => {
      const aktif1 = rows.filter(r => r.jam_sejak_aktif < 1).length, aktif24 = rows.filter(r => r.jam_sejak_aktif < 24).length, laut = rows.filter(r => /^laut/.test(r.lokasi)).length;
      const qp = d.questPemain || [], s4 = qp.filter(r => r.saga === 'Saga 4').length;
      const s4b2 = qp.filter(r => r.quest_no === 16).length, s4tamat = qp.filter(r => r.quest_kini === 'Tamat Saga 4').length;
      $('#kapBoard').innerHTML = board([
        { k: 'Kapten', v: n0(rows.length), s: 'terdaftar dan sudah membuat karakter' }, { k: 'Aktif kurang dari 1 jam', v: n0(aktif1), s: 'sedang atau baru saja main' },
        { k: 'Aktif 24 jam', v: n0(aktif24), s: `${n0(rows.length - aktif24)} lebih lama` }, { k: 'Sedang berlayar', v: n0(laut), s: 'di tengah laut sekarang' },
        { k: 'Sudah di Saga 4', v: n0(s4), s: 'Monopoli dan Mahkota' },
        { k: 'Saga 4 Bagian II', v: n0(s4b2), s: `Takhta Tanpa Mahkota · ${n0(s4tamat)} tamat` },
      ], 6);
    });
    part($('#kapTabel'), d, 'pemain', () => { renderKapTabel(); });
    part($('#kapSebaran'), d, 'questRingkas', rows => {
      const el = $('#kapSebaran'), mx = Math.max(1, ...rows.map(r => r.tamat + r.berjalan));
      el.innerHTML = `<div class="legend"><span><i class="sq sq-bank"></i>tamat</span><span><i class="sq sq-gold"></i>sedang berjalan</span></div>` + hbars(rows.map(r => ({
        label: r.quest, sub: r.saga, segs: [{ w: 100 * r.tamat / mx, cls: 'seg-bank' }, { w: 100 * r.berjalan / mx, cls: 'seg-gold' }],
        value: r.berjalan ? `${r.tamat} + ${r.berjalan}` : String(r.tamat) })));
      setVars(el);
    });
    part($('#kapQuest'), d, 'questPemain', () => { renderQuestTabel(); });
  }
  const KAP_IDS = ['#kapBoard', '#kapTabel', '#kapSebaran', '#kapQuest'];
  loaders.kapten = () => { readParams(); $('#cariKapten').value = P.q; $('#cariQuest').value = P.cq; return load(KAP_IDS, () => loadKap(false)); };
  $('#kapRefresh').addEventListener('click', async () => { const b = $('#kapRefresh'); b.disabled = true; try { await loadKap(true); toast('Kapten dimuat ulang.'); } catch (e) { toast(e.message); } b.disabled = false; });
  $('#cariKapten').addEventListener('input', e => { P.q = e.target.value; writeParams(); renderKapTabel(); });
  $('#cariQuest').addEventListener('input', e => { P.cq = e.target.value; writeParams(); renderQuestTabel(); });
  $('#kapTabel').addEventListener('click', e => {
    const b = e.target.closest('th button'); if (!b) return;
    const k = b.closest('th').dataset.k;
    P.d = P.s === k ? (P.d === 'asc' ? 'desc' : 'asc') : (LEFT.includes(k) ? 'asc' : 'desc'); P.s = k;
    writeParams(); renderKapTabel();
  });
})();
