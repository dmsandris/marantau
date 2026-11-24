'use strict';
// Tab Penjaga (anomali kapten, aturan + AI Gemini) dan tab Pengaturan.
(() => {
  const { $, $$, esc, n0, idr, api, toast, board, table, load, empty, showErr, loaders, st, navBadge } = window.OPS;
  const LV = t => (t === 'tinggi' ? 'bad' : t === 'sedang' ? 'warn' : t === 'wajar' ? 'ok' : '');
  const when = t => new Date(t).toLocaleString('id-ID', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  const jejak = nama => `#/audit?b=jejak&k=${encodeURIComponent(nama)}`;

  let P = null, runId = null;

  function render() {
    const s = P.status || {}, cfg = (P.pengaturan || {}).penjaga || {}, g = (P.pengaturan || {}).gemini || {}, run = P.run;
    const aiMode = { auto: 'otomatis bila ada temuan sedang atau tinggi', manual: 'hanya lewat tombol', off: 'mati' }[cfg.ai] || '-';
    $('#pjStatus').innerHTML = `Pindai otomatis <b>${cfg.auto ? `tiap ${n0(cfg.intervalMenit)} menit` : 'mati'}</b>${s.lastAuto ? `, terakhir ${esc(when(s.lastAuto))}` : ''}. AI <b>${esc(aiMode)}</b>${g.ada ? `, model ${esc(g.model)}` : ', kunci belum diisi'}. Telegram <b>${cfg.alert === 'off' ? 'tidak dikirim' : 'tingkat ' + esc(cfg.alert) + ' ke atas'}</b>. <a class="go" href="#/pengaturan">Ubah pengaturan</a>`;
    $('#pjScanAi').disabled = !P.adaKunci || cfg.ai === 'off';
    $('#pjScanAi').title = !P.adaKunci ? 'Isi kunci API Gemini di Pengaturan dulu' : cfg.ai === 'off' ? 'AI dimatikan di Pengaturan' : '';
    if (s.running) { $('#pjScan').disabled = $('#pjScanAi').disabled = true; }

    if (!run) {
      empty($('#pjBoard'), '<b>Belum ada pindaian.</b> Tekan Pindai sekarang, atau tunggu pindai otomatis berikutnya.');
      ['#pjTemuan', '#pjAi'].forEach(id => { $(id).innerHTML = ''; $(id).removeAttribute('aria-busy'); });
    } else {
      const t = run.temuan, aktif = t.filter(f => !f.aman);
      const c = k => aktif.filter(f => f.tingkat === k).length;
      $('#pjBoard').innerHTML = board([
        { k: 'Tinggi', v: n0(c('tinggi')), s: 'skor 6 ke atas', level: c('tinggi') ? 'bad' : 'ok' },
        { k: 'Sedang', v: n0(c('sedang')), s: 'skor 3 sampai 5', level: c('sedang') ? 'warn' : 'ok' },
        { k: 'Rendah', v: n0(c('rendah')), s: 'tanda kecil, tidak dikirim' },
        { k: 'Kapten aktif dinilai', v: n0(run.baseline.pemain_aktif), s: `median ${n0(run.baseline.median_aksi)} aksi, maks ${n0(run.baseline.median_maks_per_menit)} per menit` },
        { k: 'Pindaian', v: when(run.at), s: `jendela ${run.jendelaJam} jam, ${run.sumber}, ${n0(run.ms)} ms` },
        { k: 'AI', v: run.ai ? (run.ai.error ? 'gagal' : 'dinilai') : 'tidak', s: run.ai ? (run.ai.error ? run.ai.error.slice(0, 80) : `${run.ai.model}, ${n0(run.ai.ms)} ms`) : 'hanya aturan', level: run.ai && run.ai.error ? 'bad' : '' },
      ], 6);
      if (Object.keys(run.errors || {}).length) $('#pjBoard').insertAdjacentHTML('beforeend', `<div class="errbox" role="alert"><span>Sebagian data gagal dibaca: ${esc(Object.entries(run.errors).map(([k, v]) => k + ': ' + v).join(', '))}</span></div>`);

      const aiK = new Map(((run.ai && run.ai.kapten) || []).map(k => [k.username, k]));
      $('#pjTemuan').innerHTML = t.length ? `<div class="find">${t.map(f => {
        const ai = aiK.get(f.username);
        const a = f.angka || {};
        const angka = [a.aksi != null ? `${n0(a.aksi)} aksi` : '', a.maks_per_menit ? `maks ${n0(a.maks_per_menit)} per menit` : '', a.jeda_median != null ? `jeda median ${a.jeda_median} detik` : '',
          a.masuk != null ? `gold masuk ${idr(a.masuk)}, keluar ${idr(a.keluar)}` : '', a.kenaikan_kekayaan != null ? `kekayaan ${a.kenaikan_kekayaan >= 0 ? 'naik' : 'turun'} ${idr(Math.abs(a.kenaikan_kekayaan))}` : ''].filter(Boolean).join(', ');
        return `<details><summary><span class="nm">${esc(f.kapten)}<small>${esc(f.username)}${f.aman ? ', ditandai aman' : ''}</small></span>${st(LV(f.tingkat), f.tingkat)}<span class="num">${n0(f.skor)}</span>
          <span class="tg">${esc(f.tanda.map(x => x.judul).join(', '))}</span><span class="open-hint">bukti</span></summary>
          <div class="body"><ul>${f.tanda.map(x => `<li><b>${esc(x.judul)}</b> (${x.poin} poin): ${esc(x.bukti)}</li>`).join('')}</ul>
          ${angka ? `<p class="cap">${esc(angka)}${a.pola ? `. Catatan terbanyak: "${esc(a.pola)}" ${n0(a.pola_n)} kali` : ''}.</p>` : ''}
          ${ai ? `<div class="ai"><b>AI, ${esc(ai.tingkat)}:</b> ${esc(ai.judul)}${ai.saran ? `. Saran: ${esc(ai.saran)}` : ''}</div>` : ''}
          <div class="actions"><a class="btn btn--small" href="${jejak(f.kapten)}">Buka jejak</a>
          ${f.aman ? `<button type="button" class="btn btn--small" data-aman="${esc(f.username)}" data-hari="0">Cabut tanda aman</button>` : `<button type="button" class="btn btn--small" data-aman="${esc(f.username)}" data-hari="7">Tandai aman 7 hari</button>`}</div></div></details>`;
      }).join('')}</div>` : '<div class="empty"><b>Tidak ada pola janggal</b> dalam jendela ini.</div>';
      $('#pjTemuan').removeAttribute('aria-busy');

      const ai = run.ai, el = $('#pjAi');
      if (!ai) empty(el, P.adaKunci ? '<b>Pindaian ini tanpa AI.</b> Tekan Pindai dan nilai dengan AI untuk penilaian Gemini.' : '<b>AI belum aktif.</b> Isi kunci API Gemini di Pengaturan. Aturan tetap berjalan tanpa AI.');
      else if (ai.error) showErr(el, 'AI: ' + ai.error, () => scan(true));
      else {
        const cards = ai.kapten.filter(k => k.tingkat !== 'wajar');
        el.innerHTML = `<div class="ai-sum"><p>${esc(ai.ringkasan)}</p><p class="cap">${esc(ai.model)}, ${n0(ai.ms)} ms${ai.samar ? ', nama disamarkan sebelum dikirim' : ''}${ai.usage && ai.usage.totalTokenCount ? `, ${n0(ai.usage.totalTokenCount)} token` : ''}.</p></div>` +
          (cards.length ? `<div class="ai-list">${cards.map(k => `<article class="ai-card"><h3><span>${esc(k.kapten)}</span>${st(LV(k.tingkat), k.tingkat)}</h3><p class="judul">${esc(k.judul)}</p>
            <ul>${(k.alasan || []).map(a => `<li>${esc(a)}</li>`).join('')}</ul>${k.saran ? `<p class="saran"><b>Saran:</b> ${esc(k.saran)}</p>` : ''}</article>`).join('')}</div>` : '<div class="empty"><b>AI menilai semua kapten wajar.</b></div>') +
          ((ai.pola_baru || []).length ? `<h3 class="sub-h">Pola yang belum tertangkap aturan</h3><ul>${ai.pola_baru.map(p => `<li>${esc(p)}</li>`).join('')}</ul>` : '');
      }
    }

    $('#pjRiwayat').innerHTML = (P.runs || []).length ? table([
      { h: 'Waktu', k: 'at', html: 1, f: r => `<button type="button" class="lnk" data-run="${esc(r.id)}">${esc(when(r.at))}</button>`, cls: r => r.id === (run && run.id) ? 'name' : '' },
      { h: 'Sumber', k: 'sumber' }, { h: 'Jendela', k: 'jendelaJam', num: 1, f: r => r.jendelaJam + ' jam' },
      { h: 'Tinggi', k: 'tinggi', num: 1, cls: r => r.tinggi ? 'hot' : 'dim' }, { h: 'Sedang', k: 'sedang', num: 1, cls: r => r.sedang ? 'warn' : 'dim' },
      { h: 'AI', k: 'ai', f: r => r.ai || '-', cls: r => r.ai === 'gagal' ? 'hot' : r.ai ? '' : 'dim' },
    ], P.runs, { tall: true }) : '<div class="empty">Belum ada.</div>';
    $('#pjRiwayat').removeAttribute('aria-busy');

    const aman = Object.entries(s.aman || {}).filter(([, v]) => v.sampai > Date.now());
    $('#pjAman').innerHTML = aman.length ? table([
      { h: 'Kapten', k: 'u', cls: () => 'name' }, { h: 'Sampai', k: 'sampai', f: r => when(r.sampai) }, { h: 'Catatan', k: 'catatan', cls: () => 'wrap dim' },
      { h: '', k: 'x', html: 1, f: r => `<button type="button" class="btn btn--small" data-aman="${esc(r.u)}" data-hari="0">Cabut</button>` },
    ], aman.map(([u, v]) => ({ u, ...v }))) : '<div class="empty">Tidak ada kapten yang ditandai aman.</div>';
    $('#pjAman').removeAttribute('aria-busy');

    const r0 = (P.runs || [])[0];
    navBadge('#navPenjaga', r0 ? (r0.tinggi ? r0.tinggi + ' tinggi' : r0.sedang ? r0.sedang + ' sedang' : '') : '', r0 && r0.tinggi ? 'bad' : r0 && r0.sedang ? 'warn' : '');
  }

  async function fetchP() { P = await api('/api/penjaga' + (runId ? '?id=' + encodeURIComponent(runId) : '')); render(); }
  async function scan(ai) {
    const btn = ai ? $('#pjScanAi') : $('#pjScan'), old = btn.textContent;
    $('#pjScan').disabled = $('#pjScanAi').disabled = true; btn.textContent = ai ? 'Menilai dengan AI…' : 'Memindai…';
    try {
      const r = await api('/api/penjaga/scan', { method: 'POST', body: JSON.stringify({ ai, jam: +$('#pjJam').value }) });
      runId = null; await fetchP();
      toast(r.run.ai && r.run.ai.error ? 'Aturan selesai, AI gagal: ' + r.run.ai.error : `Selesai: ${r.run.temuan.filter(f => f.tingkat === 'tinggi' && !f.aman).length} tinggi, ${r.run.temuan.filter(f => f.tingkat === 'sedang' && !f.aman).length} sedang.`);
    } catch (e) { toast('Gagal: ' + e.message); }
    btn.textContent = old; $('#pjScan').disabled = false; if (P) render();
  }
  loaders.penjaga = () => load(['#pjBoard', '#pjTemuan', '#pjAi', '#pjRiwayat', '#pjAman'], fetchP);
  $('#pjScan').addEventListener('click', () => scan(false));
  $('#pjScanAi').addEventListener('click', () => scan(true));
  $('section[data-panel="penjaga"]').addEventListener('click', async e => {
    const r = e.target.closest('[data-run]'); if (r) { runId = r.dataset.run; await fetchP().catch(err => toast(err.message)); $('#pjBoard').scrollIntoView({ block: 'start' }); return; }
    const a = e.target.closest('[data-aman]'); if (!a) return;
    const hari = +a.dataset.hari;
    if (hari && !confirm(`Tandai ${a.dataset.aman} aman ${hari} hari? Penjaga tetap mencatat, tetapi tidak mengirim peringatan untuk kapten ini.`)) return;
    a.disabled = true;
    try { await api('/api/penjaga/aman', { method: 'POST', body: JSON.stringify({ username: a.dataset.aman, hari, catatan: hari ? 'dari Panel Ops' : '' }) }); toast(hari ? 'Ditandai aman.' : 'Tanda aman dicabut.'); await fetchP(); }
    catch (err) { toast(err.message); a.disabled = false; }
  });

  // ---------- Pengaturan ----------
  let S = null;
  const msg = (id, text, level) => { const e = $(id); e.textContent = text; e.dataset.level = level || ''; };
  function fillSet() {
    const g = S.gemini, p = S.penjaga, t = S.telegram;
    $('#setAiState').innerHTML = g.ada ? `Kunci tersimpan, berakhiran <b>${esc(g.akhir)}</b>. Model <b>${esc(g.model)}</b>.` : 'Belum ada kunci. Penjaga berjalan dengan aturan saja.';
    $('#setKey').placeholder = g.ada ? `tersimpan, berakhiran ${g.akhir}; isi untuk mengganti` : 'AIza…';
    const sel = $('#setModel');
    if (![...sel.options].some(o => o.value === g.model)) sel.insertAdjacentHTML('afterbegin', `<option value="${esc(g.model)}">${esc(g.model)}</option>`);
    sel.value = g.model;
    $('#setHapus').disabled = $('#setTes').disabled = $('#setModels').disabled = !g.ada;
    $('#pjAuto').checked = p.auto;
    const setSel = (id, v) => { const e = $(id); if (![...e.options].some(o => o.value === String(v))) e.insertAdjacentHTML('beforeend', `<option value="${v}">${v}</option>`); e.value = String(v); };
    setSel('#pjInterval', p.intervalMenit); setSel('#pjJendela', p.jendelaJam); setSel('#pjJeda', p.aiJedaJam); $('#pjAlert').value = p.alert;
    $$('#setPj input[name="ai"]').forEach(r => { r.checked = r.value === p.ai; });
    $('#pjSamar').checked = p.samarkan;
    const mute = t.senyapSampai > Date.now();
    $('#setTgState').innerHTML = mute ? `Peringatan disenyapkan sampai <b>${esc(when(t.senyapSampai))}</b>.` : 'Peringatan aktif.';
    $('#tgSenyap').value = '0';
    if (!$('#tgJam').options.length) $('#tgJam').innerHTML = Array.from({ length: 24 }, (_, h) => `<option value="${h}">${String(h).padStart(2, '0')}:00 WIB</option>`).join('');
    $('#tgJam').value = String(t.laporanJam);
  }
  async function loadSet() { S = await api('/api/pengaturan'); fillSet(); }
  loaders.pengaturan = () => load([], loadSet);
  async function simpan(body, out, ok) {
    try { S = await api('/api/pengaturan', { method: 'POST', body: JSON.stringify(body) }); fillSet(); msg(out, ok, 'ok'); }
    catch (e) { msg(out, 'Gagal: ' + e.message, 'bad'); }
  }
  $('#setAi').addEventListener('submit', async e => {
    e.preventDefault();
    // Format kunci Google berubah-ubah (AIza…, AQ.…), jadi hanya dicek panjang dan tanpa spasi.
    const key = $('#setKey').value.replace(/\s+/g, ''), body = { gemini: { model: $('#setModel').value } };
    if (key) { if (!/^[\x21-\x7E]{20,200}$/.test(key)) { msg('#setAiMsg', 'Kunci terlihat tidak lengkap. Salin ulang dari Google AI Studio.', 'bad'); $('#setKey').focus(); return; } body.gemini.key = key; }
    await simpan(body, '#setAiMsg', key ? 'Kunci dan model tersimpan. Tekan Tes koneksi untuk memastikan.' : 'Model tersimpan.');
    $('#setKey').value = '';
  });
  $('#setTes').addEventListener('click', async () => {
    const b = $('#setTes'); b.disabled = true; msg('#setAiMsg', 'Menghubungi Gemini…');
    try { const r = await api('/api/pengaturan/tes-ai', { method: 'POST' }); msg('#setAiMsg', `Tersambung ke ${r.model} dalam ${n0(r.ms)} ms. ${r.pesan || ''}`, 'ok'); }
    catch (e) { msg('#setAiMsg', 'Gagal: ' + e.message, 'bad'); }
    b.disabled = false;
  });
  $('#setModels').addEventListener('click', async () => {
    const b = $('#setModels'); b.disabled = true; msg('#setAiMsg', 'Memuat daftar model…');
    try {
      const r = await api('/api/pengaturan/model'), cur = $('#setModel').value;
      $('#setModel').innerHTML = r.models.map(m => `<option value="${esc(m.id)}">${esc(m.id)}</option>`).join('');
      if (![...$('#setModel').options].some(o => o.value === cur)) $('#setModel').insertAdjacentHTML('afterbegin', `<option value="${esc(cur)}">${esc(cur)}</option>`);
      $('#setModel').value = cur; msg('#setAiMsg', `${r.models.length} model tersedia. Pilih lalu Simpan.`, 'ok');
    } catch (e) { msg('#setAiMsg', 'Gagal: ' + e.message, 'bad'); }
    b.disabled = false;
  });
  $('#setHapus').addEventListener('click', async () => {
    if (!confirm('Hapus kunci API Gemini dari server? Penjaga kembali memakai aturan saja.')) return;
    await simpan({ gemini: { hapus: true } }, '#setAiMsg', 'Kunci dihapus.');
  });
  $('#setPj').addEventListener('submit', async e => {
    e.preventDefault();
    const ai = ($$('#setPj input[name="ai"]').find(r => r.checked) || {}).value;
    await simpan({ penjaga: { auto: $('#pjAuto').checked, intervalMenit: +$('#pjInterval').value, jendelaJam: +$('#pjJendela').value, ai, aiJedaJam: +$('#pjJeda').value, alert: $('#pjAlert').value, samarkan: $('#pjSamar').checked } }, '#setPjMsg', 'Pengaturan Penjaga tersimpan.');
  });
  $('#setTg').addEventListener('submit', async e => {
    e.preventDefault();
    const j = +$('#tgSenyap').value, t = { laporanJam: +$('#tgJam').value };
    if (j) t.senyapSampai = Date.now() + j * 3600e3; else if (S && S.telegram.senyapSampai > Date.now()) t.senyapSampai = 0;
    await simpan({ telegram: t }, '#setTgMsg', j ? `Peringatan disenyapkan ${j} jam.` : 'Pengaturan Telegram tersimpan.');
  });
  $('#setTgTes').addEventListener('click', async () => {
    try { await api('/api/telegram-test', { method: 'POST' }); msg('#setTgMsg', 'Pesan tes terkirim. Cek Telegram.', 'ok'); }
    catch (e) { msg('#setTgMsg', 'Gagal: ' + e.message, 'bad'); }
  });
})();
