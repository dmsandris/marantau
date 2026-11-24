'use strict';
// Tab Ringkas: satu layar untuk keadaan server dan game. Inti tab ini adalah daftar "Perlu dilihat".
(() => {
  const { $, esc, n0, idr, signed, api, toast, board, table, load, empty, loaders, NF1, st, ago, navBadge } = window.OPS;
  const r1 = v => v == null ? '-' : NF1.format(Math.round(v * 10) / 10);

  async function loadRingkas() {
    const d = await api('/api/ringkas');
    $('#rkStamp').textContent = 'Diambil ' + new Date(d.now).toLocaleTimeString('id-ID');
    if (d.v) $('#ver').textContent = 'v' + d.v;
    const h = d.host || {}, sv = (d.services && d.services.items) || [], e = d.ekonomi || {}, b = d.backup || {}, pj = d.penjaga, http = d.http || {};
    const memPct = h.memTotal ? 100 * h.memUsed / h.memTotal : null, diskPct = h.diskTotal ? 100 * h.diskUsed / h.diskTotal : null;
    const down = sv.filter(s => s.state !== 'running' || s.health === 'unhealthy');
    const okAge = b.lastOk ? (Date.now() - Date.parse(b.lastOk)) / 3600e3 : null;

    // ---------- Perlu dilihat ----------
    const W = []; // { lv, what, sub, href, go }
    if (d.services && d.services.error) W.push({ lv: 'bad', what: 'Docker tidak terbaca', sub: d.services.error, href: '#/layanan', go: 'Layanan' });
    for (const s of down) W.push({ lv: 'bad', what: `${s.label} ${s.state === 'running' ? 'tidak sehat' : s.state}`, sub: s.status, href: '#/layanan', go: 'Layanan' });
    for (const a of d.alerts || []) if (!/^Layanan /.test(a)) W.push({ lv: 'bad', what: `Peringatan aktif: ${a}`, sub: 'Dikirim juga ke Telegram', href: '#/server', go: 'Server' });
    if (okAge == null || okAge > 30) W.push({ lv: 'bad', what: 'Backup basi atau belum pernah berhasil', sub: b.lastOk ? `terakhir ${ago(b.lastOk)}` : 'belum ada backup berhasil', href: '#/backup', go: 'Backup' });
    else if (b.lastResult === 'gagal') W.push({ lv: 'bad', what: 'Backup terakhir gagal', sub: b.lastError || '', href: '#/backup', go: 'Backup' });
    if (b.restoreTest === 'GAGAL') W.push({ lv: 'bad', what: 'Tes restore gagal', sub: b.restoreNote || '', href: '#/backup', go: 'Backup' });
    if (http.err >= 20) W.push({ lv: 'bad', what: `${n0(http.err)} error 5xx dalam 24 jam`, sub: `dari ${n0(http.total)} permintaan`, href: '#/server', go: 'Server' });
    else if (http.err > 0) W.push({ lv: 'warn', what: `${n0(http.err)} error 5xx dalam 24 jam`, sub: `dari ${n0(http.total)} permintaan`, href: '#/server', go: 'Server' });
    if (diskPct != null && diskPct >= 70) W.push({ lv: diskPct >= 80 ? 'bad' : 'warn', what: `Disk ${Math.round(diskPct)}% terpakai`, sub: 'peringatan Telegram di atas 80%', href: '#/server', go: 'Server' });
    if (memPct != null && memPct >= 75) W.push({ lv: memPct >= 85 ? 'bad' : 'warn', what: `RAM ${Math.round(memPct)}% terpakai`, sub: `swap ${Math.round((h.swapUsed || 0) / 1048576)} MB`, href: '#/server', go: 'Server' });
    const slow = (d.db && d.db.slow) || [];
    if (slow[0] && slow[0].mean_ms > 1000) W.push({ lv: 'warn', what: `Endpoint lambat: ${slow[0].q}`, sub: `rata-rata ${n0(slow[0].mean_ms)} ms`, href: '#/db', go: 'Database' });
    if (pj) for (const f of (pj.temuan || []).filter(f => f.tingkat !== 'rendah').slice(0, 5))
      W.push({ lv: f.tingkat === 'tinggi' ? 'bad' : 'warn', what: `${f.kapten}: ${f.tanda[0].judul}`, sub: f.tanda[0].bukti, href: `#/penjaga`, go: 'Penjaga' });
    if (!pj) W.push({ lv: 'warn', what: 'Penjaga belum pernah memindai', sub: 'pindai pertama berjalan otomatis, atau tekan Pindai sekarang', href: '#/penjaga', go: 'Penjaga' });
    if (d.pengaturan && !d.pengaturan.gemini.ada) W.push({ lv: '', what: 'AI Gemini belum diaktifkan', sub: 'Penjaga tetap jalan dengan aturan; isi kunci API untuk penilaian AI', href: '#/pengaturan', go: 'Pengaturan' });
    if (!d.telegram) W.push({ lv: 'warn', what: 'Telegram belum diatur', sub: 'jalankan set-telegram.sh di VM', href: '#/backup', go: 'Backup' });
    W.sort((a, b) => ['bad', 'warn', ''].indexOf(a.lv) - ['bad', 'warn', ''].indexOf(b.lv));

    const nBad = W.filter(w => w.lv === 'bad').length, nWarn = W.filter(w => w.lv === 'warn').length;
    $('#rkVerdict').textContent = nBad ? `${nBad} hal perlu ditangani${nWarn ? `, ${nWarn} perlu dipantau` : ''}.` : nWarn ? `Server sehat. ${nWarn} hal perlu dipantau.` : 'Server dan game sehat. Tidak ada yang perlu ditangani.';
    const LW = { bad: 'tangani', warn: 'pantau', '': 'info' };
    $('#rkWatch').innerHTML = W.length ? `<ul class="watch">${W.map(w => `<li>${st(w.lv, LW[w.lv])}<span class="what"><b>${esc(w.what)}</b>${w.sub ? `<small>${esc(w.sub)}</small>` : ''}</span><a class="go" href="${w.href}">Buka ${esc(w.go)}</a></li>`).join('')}</ul>`
      : '<div class="watch-ok"><b>Semua aman.</b> Layanan sehat, backup segar, tidak ada temuan Penjaga.</div>';
    $('#rkWatch').removeAttribute('aria-busy');

    // ---------- Mesin ----------
    $('#rkMesin').innerHTML = board([
      d.services && d.services.error ? { k: 'Layanan', v: '-', s: 'Docker tidak terbaca', level: 'bad' }
        : { k: 'Layanan', v: `${sv.length - down.length} / ${sv.length}`, s: down.length ? 'bermasalah: ' + down.map(s => s.label).join(', ') : 'semua sehat', level: down.length ? 'bad' : 'ok' },
      { k: 'CPU', v: h.cpu == null ? '-' : r1(h.cpu) + '%', s: `load ${r1(h.load)}, IOwait ${r1(h.iow)}%`, level: h.cpu == null ? '' : h.cpu >= 90 ? 'bad' : h.cpu >= 70 ? 'warn' : 'ok' },
      { k: 'RAM', v: memPct == null ? '-' : Math.round(memPct) + '%', s: `swap ${Math.round((h.swapUsed || 0) / 1048576)} MB`, level: memPct == null ? '' : memPct >= 85 ? 'bad' : memPct >= 75 ? 'warn' : 'ok' },
      { k: 'Disk', v: diskPct == null ? '-' : Math.round(diskPct) + '%', s: 'volume data', level: diskPct == null ? '' : diskPct >= 80 ? 'bad' : diskPct >= 70 ? 'warn' : 'ok' },
      { k: 'Backup terakhir', v: b.lastOk ? ago(b.lastOk) : 'belum', s: `tes restore ${b.restoreTest || 'belum'}`, level: okAge == null || okAge > 30 ? 'bad' : okAge > 26 ? 'warn' : 'ok' },
      { k: 'Error 5xx, 24 jam', v: http.error ? '-' : n0(http.err), s: http.error ? 'log Caddy tidak terbaca' : `${n0(http.total)} permintaan`, level: http.error ? '' : http.err >= 20 ? 'bad' : http.err ? 'warn' : 'ok' },
    ], 6);

    // ---------- Game ----------
    const ikn = d.ikn || {};
    $('#rkGame').innerHTML = board([
      { k: 'Online sekarang', v: n0(d.db && d.db.online), s: `${n0(e.aktif_24j)} aktif 24 jam dari ${n0(e.pemain)} kapten` },
      { k: 'Total kekayaan', v: idr(e.total_kekayaan), s: `median per kapten ${idr(e.median_kekayaan)}` },
      { k: 'Laba dagang, 24 jam', v: signed(e.laba_dagang_24j), s: 'hasil jual dikurangi biaya beli', level: e.laba_dagang_24j < 0 ? 'warn' : '' },
      { k: 'Bunga bank per hari', v: idr(e.bunga_per_hari), s: 'per hari nyata, bertingkat' },
      { k: 'Pangsa terkaya', v: e.pangsa_terkaya_pct == null ? '-' : NF1.format(e.pangsa_terkaya_pct) + '%', s: `Gini ${e.gini == null ? '-' : NF1.format(e.gini)}`, level: e.pangsa_terkaya_pct >= 30 ? 'warn' : '' },
      { k: 'Restorasi IKN', v: d.iknTarget && ikn.total != null ? Math.round(100 * ikn.total / d.iknTarget) + '%' : '-', s: `${idr(ikn.total)} dari ${idr(d.iknTarget)}` },
    ], 6);

    // ---------- Penjaga terakhir ----------
    const pel = $('#rkPenjaga');
    if (!pj) empty(pel, '<b>Belum ada pindaian.</b> Buka tab Penjaga lalu tekan Pindai sekarang.');
    else {
      const t = (pj.temuan || []);
      pel.innerHTML = `<p class="cap">${esc(new Date(pj.at).toLocaleString('id-ID', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }))}, jendela ${pj.jendelaJam} jam, ${pj.tinggi} tinggi, ${pj.sedang} sedang${pj.ai ? `, AI ${esc(pj.ai)}` : ''}.</p>` +
        (t.length ? table([
          { h: 'Kapten', k: 'kapten', cls: () => 'name' },
          { h: 'Tingkat', k: 'tingkat', html: 1, f: r => st(r.tingkat === 'tinggi' ? 'bad' : r.tingkat === 'sedang' ? 'warn' : '', r.tingkat) },
          { h: 'Skor', k: 'skor', num: 1 }, { h: 'Tanda utama', k: 't', f: r => r.tanda[0].judul },
        ], t) : '<div class="empty"><b>Tidak ada pola janggal</b> di pindaian terakhir.</div>');
    }
    navBadge('#navPenjaga', pj ? (pj.tinggi ? pj.tinggi + ' tinggi' : pj.sedang ? pj.sedang + ' sedang' : '') : '', pj && pj.tinggi ? 'bad' : pj && pj.sedang ? 'warn' : '');
    navBadge('#navServer', (d.alerts || []).length ? d.alerts.length + ' peringatan' : '', (d.alerts || []).length ? 'bad' : '');

    $('#rkSlow').innerHTML = slow.length ? table([{ h: 'Endpoint', k: 'q', q: 1 }, { h: 'Rata-rata ms', k: 'mean_ms', num: 1, f: r => n0(r.mean_ms), cls: r => r.mean_ms > 1000 ? 'hot' : r.mean_ms > 300 ? 'warn' : '' }, { h: 'Maks ms', k: 'max_ms', num: 1, f: r => n0(r.max_ms) }, { h: 'Panggilan', k: 'calls', num: 1, f: r => n0(r.calls) }], slow)
      : '<div class="empty"><b>Belum ada data.</b> pg_stat_statements mengisi setelah ada panggilan.</div>';
  }

  const IDS = ['#rkWatch', '#rkMesin', '#rkGame', '#rkPenjaga', '#rkSlow'];
  loaders.ringkas = () => load(IDS, loadRingkas);
  $('#rkRefresh').addEventListener('click', async () => { const b = $('#rkRefresh'); b.disabled = true; try { await loadRingkas(); toast('Ringkas dimuat ulang.'); } catch (e) { toast(e.message); } b.disabled = false; });
})();
