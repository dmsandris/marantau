// Bot Telegram Panel Ops: menu bertombol (inline keyboard), satu pesan yang berganti isi saat tombol ditekan.
// Hanya menjawab chat pemilik (OPS_TELEGRAM_CHAT_ID). Restart layanan dan ubah data game tetap hanya lewat Panel Ops.
// Yang boleh dilakukan bot: membaca semua informasi, minta backup / tes restore, pindai Penjaga, tandai kapten aman,
// dan mengubah pengaturan Penjaga & senyap peringatan.
'use strict';

const hEsc = t => String(t ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const NF = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 0 });
const n0 = v => v == null || isNaN(+v) ? '-' : NF.format(Math.round(+v));
const idr = v => { if (v == null || isNaN(+v)) return '-'; const a = Math.abs(+v), s = +v < 0 ? '-' : ''; if (a >= 1e9) return s + (a / 1e9).toFixed(1).replace('.', ',') + ' M'; if (a >= 1e6) return s + (a / 1e6).toFixed(1).replace('.', ',') + ' jt'; return s + NF.format(Math.round(a)); };
const sgn = v => v == null || isNaN(+v) ? '-' : (+v > 0 ? '+' : '') + idr(v);
const TK = { tinggi: '🔴', sedang: '🟡', rendah: '⚪', wajar: '🟢' };
const btn = (text, data) => ({ text, callback_data: String(data).slice(0, 64) });
const BACK = [btn('« Menu', 'm')];

function create(ctx) {
  const { TG_TOKEN, TG_CHAT, state, saveState, settings, penjaga } = ctx;
  const TG_BASE = (ctx.TG_BASE || 'https://api.telegram.org').replace(/\/$/, '');
  const wibDate = (t = Date.now()) => new Date(t + 7 * 3600e3).toISOString().slice(0, 10);
  const wibTime = (t = Date.now()) => new Date(t + 7 * 3600e3).toISOString().slice(11, 16);
  const aktif = !!(TG_TOKEN && TG_CHAT);

  async function api(method, body, timeoutMs = 15000) {
    const r = await fetch(`${TG_BASE}/bot${TG_TOKEN}/${method}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs),
    });
    const j = await r.json();
    if (!j.ok) throw new Error(`telegram ${method}: ${j.description}`);
    return j.result;
  }
  const cut = s => (s.length > 4000 ? s.slice(0, 3990) + '\n…' : s);
  async function send(html, keyboard) {
    if (!aktif) return;
    const chunks = []; for (let i = 0; i < html.length; i += 3900) chunks.push(html.slice(i, i + 3900));
    for (let i = 0; i < chunks.length; i++) {
      await api('sendMessage', { chat_id: TG_CHAT, text: chunks[i], parse_mode: 'HTML', disable_web_page_preview: true,
        ...(keyboard && i === chunks.length - 1 ? { reply_markup: { inline_keyboard: keyboard } } : {}) });
    }
  }
  async function edit(msg, html, keyboard) {
    try {
      await api('editMessageText', { chat_id: TG_CHAT, message_id: msg.message_id, text: cut(html), parse_mode: 'HTML', disable_web_page_preview: true, reply_markup: { inline_keyboard: keyboard || [BACK] } });
    } catch (e) {
      if (/not modified/.test(e.message)) return;
      await send(cut(html), keyboard || [BACK]); // pesan terlalu lama / terhapus: kirim baru
    }
  }
  async function doc(filename, text, caption) {
    const fd = new FormData();
    fd.append('chat_id', TG_CHAT); if (caption) fd.append('caption', caption);
    fd.append('document', new Blob([text], { type: 'text/plain' }), filename);
    const r = await fetch(`${TG_BASE}/bot${TG_TOKEN}/sendDocument`, { method: 'POST', body: fd, signal: AbortSignal.timeout(30000) });
    const j = await r.json(); if (!j.ok) throw new Error('sendDocument: ' + j.description);
  }

  // ---------- layar ----------
  const MENU_KB = [
    [btn('🖥 Server', 's'), btn('🧩 Layanan', 'l'), btn('🗄 Database', 'd')],
    [btn('💰 Ekonomi', 'e'), btn('🧭 Kapten', 'k'), btn('💸 Aliran dana', 'a:24')],
    [btn('🔎 Audit', 'au'), btn('🛡 Penjaga', 'p'), btn('👁 Iluminaty', 'i')],
    [btn('📦 Backup', 'b'), btn('🧯 Error', 'x:1'), btn('⚙️ Pengaturan', 'g')],
    [btn('☀️ Laporan harian', 'h'), btn('🧾 Debug .txt', 'dbg')],
  ];
  async function vMenu() {
    const h = ctx.current();
    const [sv, db] = await Promise.all([ctx.services().catch(() => ({})), ctx.dbStats().catch(() => ({}))]);
    const down = (sv.items || []).filter(s => s.state !== 'running' || s.health === 'unhealthy');
    const run = penjaga.last();
    const pj = run ? run.temuan.filter(f => !f.aman) : [];
    const tinggi = pj.filter(f => f.tingkat === 'tinggi').length, sedang = pj.filter(f => f.tingkat === 'sedang').length;
    const act = ctx.activeAlerts();
    const mute = settings.get().telegram.senyapSampai > Date.now();
    const memPct = h.memTotal ? Math.round(100 * h.memUsed / h.memTotal) : '-';
    const L = [`<b>⚓ Marantau Ops</b> · ${wibTime()} WIB`,
      `${down.length || sv.error ? '🔴' : act.length ? '🟡' : '🟢'} ${sv.error ? 'Docker tidak terbaca' : down.length ? 'Bermasalah: ' + hEsc(down.map(s => s.label).join(', ')) : act.length ? 'Peringatan: ' + hEsc(act.join(', ')) : 'Server dan semua layanan sehat'}`,
      `CPU ${h.cpu == null ? '-' : Math.round(h.cpu)}% · RAM ${memPct}% · 👥 ${db.online ?? '-'} online`,
      run ? `🛡 Penjaga ${wibTime(run.at)}: ${tinggi ? `🔴 ${tinggi} tinggi` : ''}${tinggi && sedang ? ', ' : ''}${sedang ? `🟡 ${sedang} sedang` : ''}${!tinggi && !sedang ? '🟢 tidak ada temuan penting' : ''}` : '🛡 Penjaga belum pernah memindai',
      mute ? `🔕 Peringatan disenyapkan sampai ${wibTime(settings.get().telegram.senyapSampai)} WIB` : ''];
    return [L.filter(Boolean).join('\n'), MENU_KB];
  }

  async function vLayanan() {
    const [sv, stats] = await Promise.all([ctx.services(), ctx.serviceStats()]);
    const L = ['<b>🧩 Layanan</b>'];
    if (sv.error) L.push('🔴 Docker tidak terbaca: ' + hEsc(sv.error));
    const kb = [];
    const alias = Object.entries(ctx.LOG_ALIAS).reduce((m, [a, n]) => (m[n] ||= a, m), {});
    for (const s of sv.items || []) {
      const ok = s.state === 'running' && s.health !== 'unhealthy';
      L.push(`${ok ? (s.health === 'starting' ? '🟡' : '🟢') : '🔴'} <b>${hEsc(s.label)}</b> · ${hEsc(s.status || s.state)}${stats[s.name] ? ` · ${stats[s.name].memMb} MB` : ''}`);
      if (alias[s.name]) kb.push(btn('Log ' + s.label, 'lg:' + alias[s.name]));
    }
    L.push('', 'Restart hanya lewat Panel Ops.');
    const rows = []; for (let i = 0; i < kb.length; i += 2) rows.push(kb.slice(i, i + 2));
    return [L.join('\n'), [...rows, [btn('🔄 Muat ulang', 'l'), ...BACK]]];
  }
  async function vLog(a) {
    const name = ctx.LOG_ALIAS[a] || a;
    const lines = (await ctx.logLines(name, 30)).map(l => ctx.redact(l).slice(0, 220));
    return [`<b>Log ${hEsc(name)}</b> (30 baris terakhir)\n<pre>${hEsc(lines.join('\n')).slice(-3500)}</pre>`, [[btn('🔄 Muat ulang', 'lg:' + a), btn('« Layanan', 'l')], BACK]];
  }

  async function vEkonomi() {
    const d = await ctx.ekonomi();
    const r = (d.ringkasan || [])[0] || {};
    const ikn = (d.ikn || [])[0] || {};
    const kt = (d.kepingTotal || [])[0] || {};
    const L = ['<b>💰 Ekonomi</b>',
      `👥 ${n0(r.online_sekarang)} online · ${n0(r.aktif_24j)} aktif 24 jam · ${n0(r.pemain)} kapten`,
      `Kekayaan total <b>${idr(r.total_kekayaan)}</b> (median ${idr(r.median_kekayaan)})`,
      `Bank ${idr(r.total_bank)} · di tangan ${idr(r.total_gold)} · utang ${idr(r.total_utang)}`,
      `Bunga bank ${idr(r.bunga_per_hari)}/hari nyata`,
      `Laba dagang 24 jam ${sgn(r.laba_dagang_24j)}`,
      `Terkaya ${r.pangsa_terkaya_pct ?? '-'}% · 3 teratas ${r.pangsa_top3_pct ?? '-'}% · Gini ${r.gini ?? '-'}`,
      `IKN ${idr(ikn.total)} dari ${idr(d.iknTarget)} (${ikn.total && d.iknTarget ? Math.round(100 * ikn.total / d.iknTarget) : 0}%) · ${n0(ikn.donatur)} donatur`,
      `Keping beredar ${n0(kt.beredar)}`];
    const al = await ctx.aliran(24).catch(() => ({}));
    const kat = (al.kategori || []).filter(k => k.arah !== 0);
    if (kat.length) {
      L.push('', '<b>Sumber gold 24 jam</b>'); for (const k of kat.filter(k => k.arah === 1).slice(0, 4)) L.push(`➕ ${hEsc(k.kat)}: ${idr(k.gold)}`);
      L.push('<b>Tujuan gold 24 jam</b>'); for (const k of kat.filter(k => k.arah === -1).slice(0, 4)) L.push(`➖ ${hEsc(k.kat)}: ${idr(k.gold)}`);
    }
    return [L.join('\n'), [[btn('💸 Aliran dana', 'a:24'), btn('🔄 Muat ulang', 'e')], BACK]];
  }

  // Kapten: daftar urut aktif terakhir, 10 per halaman.
  async function kaptenList() {
    const d = await ctx.kapten();
    return (d.pemain || []).slice().sort((a, b) => (a.jam_sejak_aktif ?? 1e9) - (b.jam_sejak_aktif ?? 1e9));
  }
  async function vKapten(page = 0, cari = '') {
    let rows = await kaptenList();
    if (cari) { const q = cari.toLowerCase(); rows = rows.filter(r => (r.pemain || '').toLowerCase().includes(q)); }
    const per = 10, max = Math.max(0, Math.ceil(rows.length / per) - 1); page = Math.min(Math.max(0, page), max);
    const sl = rows.slice(page * per, page * per + per);
    const kd = ctx.kekayaanDelta(24);
    const L = [`<b>🧭 Kapten</b>${cari ? ` · cari "${hEsc(cari)}"` : ''} · urut aktif terakhir`, ''];
    for (const r of sl) {
      const dlt = kd.get(r.username);
      const on = r.jam_sejak_aktif != null && r.jam_sejak_aktif < 0.05 ? '🟢' : r.jam_sejak_aktif < 24 ? '🟡' : '⚪';
      L.push(`${on} <b>${hEsc(r.pemain)}</b> · ${idr(r.kekayaan)}${dlt && dlt.delta ? ` (${sgn(dlt.delta)} 24j)` : ''} · ${hEsc(r.lokasi || '-')}`);
    }
    if (!sl.length) L.push('Tidak ada kapten yang cocok.');
    L.push('', 'Ketuk nama untuk detail. Cari: /kapten nama');
    const kb = []; for (let i = 0; i < sl.length; i += 2) kb.push(sl.slice(i, i + 2).map(r => btn(r.pemain, 'kd:' + r.username)));
    const nav = [];
    if (page > 0) nav.push(btn('◀ Sebelumnya', 'k:' + (page - 1)));
    if (page < max) nav.push(btn('Berikutnya ▶', 'k:' + (page + 1)));
    if (nav.length) kb.push(nav);
    kb.push(BACK);
    return [L.join('\n'), kb];
  }
  async function vKaptenDetail(username) {
    const [d, al] = await Promise.all([ctx.kapten(), ctx.aliran(24)]);
    const r = (d.pemain || []).find(x => x.username === username);
    const nama = r ? r.pemain : username;
    if (!r) return [`Kapten <b>${hEsc(username)}</b> tidak ditemukan.`, [[btn('« Kapten', 'k')], BACK]];
    const q = (d.questPemain || []).find(x => x.pemain === nama) || {};
    const a = (al.kapten || []).find(x => x.username === username) || {};
    const kd = ctx.kekayaanDelta(24).get(username);
    const run = penjaga.last(); const f = run && run.temuan.find(x => x.username === username);
    const ai = run && run.ai && run.ai.kapten && run.ai.kapten.find(x => x.username === username);
    const L = [`<b>🧭 ${hEsc(nama)}</b> (${hEsc(username)}) · ${hEsc(r.arketipe)} · kapal ${hEsc(r.kapal || '-')}`,
      `📍 ${hEsc(r.lokasi || '-')} · aktif ${r.jam_sejak_aktif == null ? '-' : r.jam_sejak_aktif < 1 ? Math.round(r.jam_sejak_aktif * 60) + ' mnt lalu' : r.jam_sejak_aktif + ' jam lalu'} · gabung ${hEsc(r.bergabung)}`,
      `💰 Kekayaan <b>${idr(r.kekayaan)}</b>${kd ? ` (${sgn(kd.delta)} dalam ${kd.jam} jam)` : ''}`,
      `Gold ${idr(r.gold)} · bank ${idr(r.bank)} · utang ${idr(r.utang)} · muatan ${idr(r.nilai_muatan)}`,
      `Pangsa ${r.pangsa_pct}% · bunga ${idr(r.bunga_per_hari)}/hari`,
      `📜 ${hEsc(q.quest_kini || '-')}${q.langkah ? ` langkah ${q.langkah}/${q.langkah_akhir}` : ''}`,
      '', '<b>Aliran dana 24 jam</b>',
      a.masuk != null ? `Masuk ${idr(a.masuk)} · keluar ${idr(a.keluar)} · bersih ${sgn(a.bersih)}` : 'Tidak ada catatan gold.',
      a.sumber_utama ? `Sumber utama: ${hEsc(a.sumber_utama)} ${idr(a.sumber_utama_gold)}` : '',
      a.tujuan_utama ? `Tujuan utama: ${hEsc(a.tujuan_utama)} ${idr(a.tujuan_utama_gold)}` : ''];
    if (f) {
      L.push('', `<b>🛡 Penjaga</b> ${TK[f.tingkat]} ${f.tingkat} (skor ${f.skor})${f.aman ? ' · ditandai aman' : ''}`);
      for (const t of f.tanda.slice(0, 5)) L.push(`▫️ ${hEsc(t.judul)}: ${hEsc(t.bukti)}`);
    }
    if (ai) L.push(`🤖 ${TK[ai.tingkat] || ''} ${hEsc(ai.judul)}${ai.saran ? '\nSaran: ' + hEsc(ai.saran) : ''}`);
    return [L.filter(x => x !== '').join('\n').replace(/\n<b>/g, '\n\n<b>'),
      [[btn('💸 Aliran 7 hari', 'ak:' + username), btn('🔄', 'kd:' + username)], [btn('🛡 Tandai aman 7 hari', 'pa:' + username)], [btn('« Kapten', 'k'), ...BACK]]];
  }

  async function vAliran(jam = 24) {
    const d = await ctx.aliran(jam);
    const kat = d.kategori || [];
    const masuk = kat.filter(k => k.arah === 1), keluar = kat.filter(k => k.arah === -1);
    const sum = a => a.reduce((s, k) => s + k.gold, 0);
    const label = jam === 24 ? '24 jam' : jam === 168 ? '7 hari' : jam + ' jam';
    const L = [`<b>💸 Aliran dana · ${label}</b>`, `Masuk <b>${idr(sum(masuk))}</b> · keluar <b>${idr(sum(keluar))}</b> · bersih ${sgn(sum(masuk) - sum(keluar))}`, '(setor/tarik bank tidak dihitung; bunga bank tidak tercatat di log)', '', '<b>Sumber terbesar</b>'];
    for (const k of masuk.slice(0, 7)) L.push(`➕ ${hEsc(k.kat)}: ${idr(k.gold)} · ${n0(k.pemain)} kapten`);
    L.push('', '<b>Tujuan terbesar</b>');
    for (const k of keluar.slice(0, 7)) L.push(`➖ ${hEsc(k.kat)}: ${idr(k.gold)} · ${n0(k.pemain)} kapten`);
    const kp = (d.kapten || []).slice(0, 6);
    if (kp.length) { L.push('', '<b>Gold masuk terbanyak</b>'); for (const r of kp) L.push(`▫️ ${hEsc(r.kapten)}: ${idr(r.masuk)} (bersih ${sgn(r.bersih)}) · ${hEsc(r.sumber_utama || '-')}`); }
    return [L.join('\n'), [[btn(jam === 24 ? '• 24 jam' : '24 jam', 'a:24'), btn(jam === 168 ? '• 7 hari' : '7 hari', 'a:168'), btn(jam === 720 ? '• 30 hari' : '30 hari', 'a:720')], BACK]];
  }
  async function vAliranKapten(username, jam = 168) {
    const [d, kp] = await Promise.all([ctx.aliran(jam), ctx.kapten()]);
    const kr = (kp.pemain || []).find(x => x.username === username);
    const nama = kr ? kr.pemain : (ctx.userKeNama(username) || username);
    const rows = (d.matriks || []).filter(r => r.kapten === nama);
    const L = [`<b>💸 Aliran ${hEsc(nama)} · ${jam === 168 ? '7 hari' : jam + ' jam'}</b>`];
    const masuk = rows.filter(r => r.arah === 1), keluar = rows.filter(r => r.arah === -1);
    if (!rows.length) L.push('Tidak ada catatan gold.');
    if (masuk.length) { L.push('', '<b>Masuk</b>'); for (const r of masuk.slice(0, 10)) L.push(`➕ ${hEsc(r.kat)}: ${idr(r.gold)} (${n0(r.kejadian)}x)`); }
    if (keluar.length) { L.push('', '<b>Keluar</b>'); for (const r of keluar.slice(0, 10)) L.push(`➖ ${hEsc(r.kat)}: ${idr(r.gold)} (${n0(r.kejadian)}x)`); }
    return [L.join('\n'), [[btn('« ' + nama, 'kd:' + username)], BACK]];
  }

  async function vAudit(sub = '') {
    if (sub === 't') {
      const d = await ctx.audit(24);
      const t = (d.transfer || []).slice(0, 15);
      const L = ['<b>🔎 Transfer gold · 24 jam</b>', `${n0((d.transfer || []).length)} transfer, total ${idr((d.transfer || []).reduce((s, r) => s + r.jumlah, 0))}`, ''];
      for (const r of t) L.push(`${hEsc(r.waktu.slice(11, 16))} ${hEsc(r.pengirim)} → ${hEsc(r.penerima)} <b>${idr(r.jumlah)}</b>`);
      if (!t.length) L.push('Tidak ada transfer.');
      return [L.join('\n'), [[btn('« Audit', 'au')], BACK]];
    }
    if (sub === 'b') {
      const d = await ctx.audit(168);
      const j = (d.bursa || []).filter(r => r.selisih_pct != null && Math.abs(r.selisih_pct) >= 50).slice(0, 15);
      const L = ['<b>🔎 Bursa dengan harga janggal · 7 hari</b>', 'Selisih ≥ 50% dari harga dasar.', ''];
      for (const r of j) L.push(`${hEsc(r.waktu.slice(5, 16))} ${hEsc(r.penjual)} → ${hEsc(r.pembeli)}: ${n0(r.jumlah)} ${hEsc(r.barang)} ${idr(r.total)} (${r.selisih_pct > 0 ? '+' : ''}${r.selisih_pct}%)`);
      if (!j.length) L.push('Tidak ada.');
      return [L.join('\n'), [[btn('« Audit', 'au')], BACK]];
    }
    if (sub === 'g') {
      const d = await ctx.audit(24);
      const per = new Map();
      for (const r of d.gudang || []) { if (r.palka) continue; const e = per.get(r.kapten) || { v: 0, u: 0 }; e.v += r.nilai_dasar; e.u += r.jumlah; per.set(r.kapten, e); }
      const L = ['<b>🔎 Gudang terbesar</b>', 'Nilai dari harga dasar barang.', ''];
      for (const [k, e] of [...per].sort((a, b) => b[1].v - a[1].v).slice(0, 12)) L.push(`▫️ ${hEsc(k)}: ${idr(e.v)} (${n0(e.u)} unit)`);
      return [L.join('\n'), [[btn('« Audit', 'au')], BACK]];
    }
    const d = await ctx.audit(24);
    const tr = d.transfer || [], bu = d.bursa || [];
    return [['<b>🔎 Audit · 24 jam</b>', `Transfer gold: ${n0(tr.length)}x, ${idr(tr.reduce((s, r) => s + r.jumlah, 0))}`, `Bursa: ${n0(bu.length)} transaksi, ${idr(bu.reduce((s, r) => s + r.total, 0))}`, 'Pilih bagian:'].join('\n'),
      [[btn('Transfer terbaru', 'au:t'), btn('Bursa janggal', 'au:b')], [btn('Gudang terbesar', 'au:g'), btn('💸 Aliran dana', 'a:24')], BACK]];
  }

  function teksRun(run, { detail = true } = {}) {
    if (!run) return 'Belum ada pindaian.';
    const t = run.temuan.filter(f => !f.aman);
    const L = [`<b>🛡 Penjaga</b> · ${wibDate(run.at).slice(5)} ${wibTime(run.at)} WIB · jendela ${run.jendelaJam} jam · ${hEsc(run.sumber)}`,
      `Garis dasar: median ${n0(run.baseline.median_aksi)} aksi, maks ${n0(run.baseline.median_maks_per_menit)}/menit`];
    if (!t.length) L.push('', '🟢 Tidak ada pola janggal.');
    for (const f of t.slice(0, detail ? 8 : 5)) {
      L.push('', `${TK[f.tingkat]} <b>${hEsc(f.kapten)}</b> · ${f.tingkat} (skor ${f.skor})`);
      for (const x of f.tanda.slice(0, detail ? 3 : 2)) L.push(`▫️ ${hEsc(x.judul)}: ${hEsc(x.bukti)}`);
    }
    const aman = run.temuan.filter(f => f.aman).length;
    if (aman) L.push('', `${aman} kapten ditandai aman, tidak ditampilkan.`);
    if (run.ai) {
      if (run.ai.error) L.push('', `🤖 AI gagal: ${hEsc(run.ai.error)}`);
      else {
        L.push('', `<b>🤖 Penilaian AI</b> (${hEsc(run.ai.model)})`, hEsc(run.ai.ringkasan));
        for (const k of run.ai.kapten.filter(k => k.tingkat !== 'wajar').slice(0, 5)) L.push(`${TK[k.tingkat]} <b>${hEsc(k.kapten)}</b>: ${hEsc(k.judul)}${k.saran ? ' · ' + hEsc(k.saran) : ''}`);
        for (const p of (run.ai.pola_baru || []).slice(0, 3)) L.push(`💡 ${hEsc(p)}`);
      }
    }
    return L.join('\n');
  }
  function kbRun(run) {
    const t = run ? run.temuan.filter(f => !f.aman && f.tingkat !== 'rendah').slice(0, 6) : [];
    const rows = []; for (let i = 0; i < t.length; i += 2) rows.push(t.slice(i, i + 2).map(f => btn(`${TK[f.tingkat]} ${f.kapten}`, 'kd:' + f.username)));
    const hasKey = !!settings.get().gemini.key;
    return [...rows, [btn('🔍 Pindai sekarang', 'p:scan'), ...(hasKey ? [btn('🤖 Pindai + AI', 'p:ai')] : [])], BACK];
  }
  async function vPenjaga() { const run = penjaga.last(); return [teksRun(run), kbRun(run)]; }

  async function vIluminaty() {
    const d = await ctx.iluminaty();
    const r = d.ringkas || {};
    const L = ['<b>👁 Iluminaty</b> · Pesan Pribadi', `Pesan 24 jam ${n0(r.pm_24j)} · tersimpan ${n0(r.pm_semua)} · percakapan ${n0(r.percakapan)} · pengirim ${n0(r.pengirim)} · belum dibaca ${n0(r.belum_dibaca)}`, '', '<b>Pengirim terbanyak</b>'];
    for (const p of (d.pengirim || []).slice(0, 8)) L.push(`▫️ ${hEsc(p.kapten)}: ${n0(p.jumlah)} pesan, ${n0(p.jumlah_24j)} dalam 24 jam, ${n0(p.lawan)} lawan bicara`);
    L.push('', 'Isi pesan hanya dibaca lewat Panel Ops (tercatat di log audit).');
    return [L.join('\n'), [[btn('🔄 Muat ulang', 'i')], BACK]];
  }

  async function vBackup() {
    return [ctx.textBackup(), [[btn('📦 Backup sekarang', 'b:run'), btn('🧪 Tes restore', 'b:test')], [btn('🔄 Muat ulang', 'b')], BACK]];
  }
  function vKonfirm(teks, ya, tidak) { return [teks, [[btn('✅ Ya, jalankan', ya), btn('Batal', tidak)]]]; }

  function vPengaturan() {
    const s = settings.get(); const p = s.penjaga;
    const mute = s.telegram.senyapSampai > Date.now();
    const L = ['<b>⚙️ Pengaturan</b>',
      `🛡 Pindai otomatis: <b>${p.auto ? 'nyala' : 'mati'}</b>, tiap ${p.intervalMenit} menit, jendela ${p.jendelaJam} jam`,
      `🤖 AI Gemini: <b>${p.ai === 'auto' ? 'otomatis bila ada temuan' : p.ai === 'manual' ? 'hanya lewat tombol' : 'mati'}</b>${s.gemini.key ? ` · ${hEsc(s.gemini.model)}` : ' · kunci belum diisi (isi di Panel Ops)'}`,
      `🔔 Peringatan Penjaga: <b>${p.alert === 'off' ? 'mati' : 'tingkat ' + p.alert + ' ke atas'}</b>`,
      `🔕 Senyap: <b>${mute ? 'sampai ' + wibTime(s.telegram.senyapSampai) + ' WIB' : 'tidak'}</b> (layanan mati tetap dikirim)`,
      `☀️ Laporan harian jam ${String(s.telegram.laporanJam).padStart(2, '0')}:00 WIB`,
      '', 'Kunci API Gemini hanya bisa diisi di Panel Ops, tab Pengaturan.'];
    return [L.join('\n'), [
      [btn(p.auto ? 'Matikan pindai otomatis' : 'Nyalakan pindai otomatis', 'g:auto')],
      [btn('AI: ganti mode', 'g:ai'), btn('Peringatan: ganti tingkat', 'g:alert')],
      [btn('🔕 Senyap 1 jam', 'g:mute:1'), btn('🔕 8 jam', 'g:mute:8'), ...(mute ? [btn('🔔 Bunyikan', 'g:mute:0')] : [])],
      BACK]];
  }

  async function vError(jam) {
    return [await ctx.textErrors(jam), [[btn('1 jam', 'x:1'), btn('6 jam', 'x:6'), btn('24 jam', 'x:24')], BACK]];
  }

  // ---------- perintah teks ----------
  const COMMANDS = [
    ['menu', 'Menu utama bertombol'],
    ['status', 'Kondisi server & layanan'],
    ['db', 'Pemain online, koneksi, endpoint terlambat'],
    ['ekonomi', 'Ringkasan ekonomi game'],
    ['kapten', 'Daftar kapten, atau /kapten nama'],
    ['aliran', 'Aliran dana (/aliran 168 = 7 hari)'],
    ['audit', 'Transfer, Bursa, gudang'],
    ['penjaga', 'Temuan anomali terakhir'],
    ['scan', 'Pindai anomali sekarang (/scan ai = dengan AI)'],
    ['iluminaty', 'Ringkasan pesan pribadi'],
    ['backup', 'Status backup VM'],
    ['harian', 'Laporan harian sekarang'],
    ['error', 'Log bermasalah (/error 6 = 6 jam)'],
    ['log', 'Log layanan: /log rest 30'],
    ['debug', 'Laporan debug lengkap (.txt) untuk Claude'],
    ['senyap', 'Senyapkan peringatan: /senyap 2 (jam), /senyap 0'],
    ['pengaturan', 'Pengaturan Penjaga & peringatan'],
    ['backup_sekarang', 'Jalankan backup sekarang'],
    ['tes_restore', 'Backup + tes restore'],
    ['bantuan', 'Daftar perintah'],
  ];

  async function onCommand(text) {
    const [raw, ...args] = text.trim().split(/\s+/);
    const cmd = raw.replace(/^\//, '').replace(/@.*$/, '').toLowerCase();
    const show = async v => { const [h, kb] = await v; return send(h, kb); };
    switch (cmd) {
      case 'start': case 'menu': return show(vMenu());
      case 'bantuan': case 'help':
        return send('<b>Marantau Ops</b>\n' + COMMANDS.map(([c, d]) => `/${c} - ${hEsc(d)}`).join('\n') + '\n\nPaling mudah: /menu lalu pakai tombol. Restart layanan hanya lewat Panel Ops.', [[btn('Buka menu', 'm')]]);
      case 'status': return send(await ctx.textStatus(), [[btn('🧩 Layanan', 'l'), btn('🗄 Database', 'd')], BACK]);
      case 'db': return send(await ctx.textDb(), [[btn('🔄 Muat ulang', 'd')], BACK]);
      case 'ekonomi': return show(vEkonomi());
      case 'kapten': {
        const q = args.join(' ').trim();
        if (!q) return show(vKapten(0));
        const rows = await kaptenList();
        const hit = rows.filter(r => (r.pemain || '').toLowerCase().includes(q.toLowerCase()) || (r.username || '').toLowerCase() === q.toLowerCase());
        const tepat = hit.find(r => (r.pemain || '').toLowerCase() === q.toLowerCase());
        if (tepat || hit.length === 1) return show(vKaptenDetail((tepat || hit[0]).username));
        return show(vKapten(0, q));
      }
      case 'aliran': return show(vAliran([24, 168, 720].includes(+args[0]) ? +args[0] : 24));
      case 'audit': return show(vAudit());
      case 'penjaga': return show(vPenjaga());
      case 'scan': case 'pindai': {
        await send(`⏳ Memindai${args[0] === 'ai' ? ' + menilai dengan AI' : ''}…`);
        const run = await penjaga.scan({ sumber: 'telegram', ai: args[0] === 'ai' });
        return send(teksRun(run), kbRun(run));
      }
      case 'iluminaty': return show(vIluminaty());
      case 'backup': return show(vBackup());
      case 'harian': case 'laporan': return send(await ctx.textDaily(), [BACK]);
      case 'error': case 'errors': return show(vError(Math.min(24, Math.max(1, +args[0] || 1))));
      case 'log': {
        const name = ctx.LOG_ALIAS[(args[0] || '').toLowerCase()] || args[0];
        if (!ctx.SERVICE_NAMES.has(name)) return send('Pakai: /log &lt;layanan&gt; [baris]\nLayanan: db, rest, auth, realtime, envoy, caddy, ops', [[btn('🧩 Layanan', 'l')]]);
        const n = Math.min(80, Math.max(5, +args[1] || 30));
        const lines = (await ctx.logLines(name, n)).map(l => ctx.redact(l).slice(0, 300));
        return send(`<b>Log ${hEsc(name)}</b> (${lines.length} baris)\n<pre>${hEsc(lines.join('\n')).slice(-3700)}</pre>`);
      }
      case 'debug': return kirimDebug();
      case 'senyap': case 'mute': {
        const jam = Math.min(48, Math.max(0, +(args[0] ?? 2) || 0));
        settings.ubah({ telegram: { senyapSampai: jam ? Date.now() + jam * 3600e3 : 0 } });
        return send(jam ? `🔕 Peringatan disenyapkan ${jam} jam (sampai ${wibTime(Date.now() + jam * 3600e3)} WIB). Layanan mati tetap dikirim.` : '🔔 Peringatan dibunyikan lagi.');
      }
      case 'pengaturan': return show(Promise.resolve(vPengaturan()));
      case 'backup_sekarang': ctx.requestBackup('backup'); return send('📦 Backup dimulai. Hasilnya: /backup (±1-5 menit).', [[btn('📦 Status backup', 'b')]]);
      case 'tes_restore': ctx.requestBackup('restore-test'); return send('🧪 Backup + tes restore dimulai (±3-10 menit).', [[btn('📦 Status backup', 'b')]]);
      default: return send('Perintah tidak dikenal.', [[btn('Buka menu', 'm')]]);
    }
  }

  async function kirimDebug() {
    await send('⏳ Menyusun laporan debug…');
    const t = await ctx.debugReport();
    return doc(`marantau-debug-${wibDate()}-${wibTime().replace(':', '')}.txt`, t, 'Laporan debug - kirim ke Claude bila ada masalah.');
  }

  // ---------- tombol ----------
  async function onCallback(cq) {
    const data = cq.data || '', msg = cq.message;
    const ans = text => api('answerCallbackQuery', { callback_query_id: cq.id, ...(text ? { text: text.slice(0, 190) } : {}) }).catch(() => {});
    const go = async v => { const [h, kb] = await v; await edit(msg, h, kb); };
    const [a, b, c] = data.split(':');
    try {
      switch (a) {
        case 'm': await ans(); return go(vMenu());
        case 's': await ans(); return edit(msg, await ctx.textStatus(), [[btn('🔄 Muat ulang', 's'), btn('🧩 Layanan', 'l')], BACK]);
        case 'l': await ans(); return go(vLayanan());
        case 'lg': await ans(); return go(vLog(b));
        case 'd': await ans(); return edit(msg, await ctx.textDb(), [[btn('🔄 Muat ulang', 'd')], BACK]);
        case 'e': await ans(); return go(vEkonomi());
        case 'k': await ans(); return go(vKapten(+b || 0));
        case 'kd': await ans(); return go(vKaptenDetail(data.slice(3)));
        case 'ak': await ans(); return go(vAliranKapten(data.slice(3)));
        case 'a': await ans(); return go(vAliran(+b || 24));
        case 'au': await ans(); return go(vAudit(b || ''));
        case 'p':
          if (b === 'scan' || b === 'ai') {
            await ans(b === 'ai' ? 'Memindai dan menilai dengan AI, ±30 detik…' : 'Memindai…');
            await edit(msg, `⏳ Memindai${b === 'ai' ? ' + menilai dengan AI' : ''}…`, [BACK]);
            const run = await penjaga.scan({ sumber: 'telegram', ai: b === 'ai' });
            return edit(msg, teksRun(run), kbRun(run));
          }
          await ans(); return go(vPenjaga());
        case 'pa': {
          const u = data.slice(3);
          await ans(); return go(Promise.resolve(vKonfirm(`Tandai <b>${hEsc(ctx.userKeNama(u) || u)}</b> (${hEsc(u)}) aman selama 7 hari? Penjaga tetap mencatat, tetapi tidak mengirim peringatan untuk kapten ini.`, 'pa!:' + u, 'kd:' + u)));
        }
        case 'pa!': { const u = data.slice(4); penjaga.tandaiAman(u, 7, 'dari Telegram'); await ans('Ditandai aman 7 hari.'); return go(vKaptenDetail(u)); }
        case 'i': await ans(); return go(vIluminaty());
        case 'b':
          if (b === 'run') { await ans(); return go(Promise.resolve(vKonfirm('Jalankan backup sekarang? (±1-5 menit, game tetap jalan)', 'b:run!', 'b'))); }
          if (b === 'test') { await ans(); return go(Promise.resolve(vKonfirm('Jalankan backup + tes restore? (±3-10 menit, game tetap jalan)', 'b:test!', 'b'))); }
          if (b === 'run!') { ctx.requestBackup('backup'); await ans('Backup dimulai.'); return edit(msg, '📦 Backup dimulai. Tekan Muat ulang dalam beberapa menit.', [[btn('🔄 Status backup', 'b')], BACK]); }
          if (b === 'test!') { ctx.requestBackup('restore-test'); await ans('Tes restore dimulai.'); return edit(msg, '🧪 Backup + tes restore dimulai.', [[btn('🔄 Status backup', 'b')], BACK]); }
          await ans(); return go(vBackup());
        case 'x': await ans('Membaca log…'); return go(vError(Math.min(24, Math.max(1, +b || 1))));
        case 'h': await ans('Menyusun laporan…'); return edit(msg, await ctx.textDaily(), [BACK]);
        case 'dbg': await ans('Menyusun laporan debug…'); return kirimDebug();
        case 'g': {
          const p = settings.get().penjaga;
          if (b === 'auto') settings.ubah({ penjaga: { auto: !p.auto } });
          if (b === 'ai') settings.ubah({ penjaga: { ai: { auto: 'manual', manual: 'off', off: 'auto' }[p.ai] } });
          if (b === 'alert') settings.ubah({ penjaga: { alert: { tinggi: 'sedang', sedang: 'off', off: 'tinggi' }[p.alert] } });
          if (b === 'mute') { const j = +c || 0; settings.ubah({ telegram: { senyapSampai: j ? Date.now() + j * 3600e3 : 0 } }); }
          await ans(b ? 'Tersimpan.' : ''); return go(Promise.resolve(vPengaturan()));
        }
        default: await ans('Tombol lama, buka menu lagi.'); return go(vMenu());
      }
    } catch (e) {
      await ans('Gagal: ' + e.message);
      await send('⚠️ ' + hEsc(ctx.redact(e.message)), [BACK]).catch(() => {});
    }
  }

  // ---------- peringatan ----------
  // kind: 'kritis' (layanan mati: tetap dikirim saat senyap) atau 'biasa'.
  async function alert(text, { kind = 'biasa', keyboard } = {}) {
    if (!aktif) return;
    if (kind !== 'kritis' && settings.get().telegram.senyapSampai > Date.now()) { console.log('[tg] senyap:', text.slice(0, 80)); return; }
    try { await send(text, keyboard || [[btn('🖥 Status', 's'), btn('🧯 Error 1 jam', 'x:1')], [btn('« Menu', 'm')]]); }
    catch (e) { console.error('telegram:', e.message); }
  }
  async function alertPenjaga(run, baru) {
    const L = ['<b>🛡 Penjaga menemukan pola janggal</b>'];
    const aiK = new Map(((run.ai && run.ai.kapten) || []).map(k => [k.username, k]));
    for (const f of baru.slice(0, 5)) {
      L.push('', `${TK[f.tingkat]} <b>${hEsc(f.kapten)}</b> · ${f.tingkat} (skor ${f.skor})`);
      for (const t of f.tanda.slice(0, 3)) L.push(`▫️ ${hEsc(t.judul)}: ${hEsc(t.bukti)}`);
      const k = aiK.get(f.username); if (k) L.push(`🤖 ${hEsc(k.judul)}${k.saran ? ' · ' + hEsc(k.saran) : ''}`);
    }
    const kb = baru.slice(0, 4).map(f => [btn('Detail ' + f.kapten, 'kd:' + f.username), btn('Tandai aman', 'pa:' + f.username)]);
    await alert(L.join('\n'), { keyboard: [...kb, [btn('🛡 Penjaga', 'p'), btn('« Menu', 'm')]] });
  }

  // ---------- loop ----------
  async function poll() {
    try { await api('setMyCommands', { commands: COMMANDS.map(([command, description]) => ({ command, description: description.slice(0, 250) })) }); }
    catch (e) { console.error('setMyCommands:', e.message); }
    try { await api('setChatMenuButton', { chat_id: TG_CHAT, menu_button: { type: 'commands' } }); } catch {}
    for (;;) {
      try {
        const ups = await api('getUpdates', { offset: state.offset, timeout: 50, allowed_updates: ['message', 'callback_query'] }, 65000);
        for (const u of ups) {
          state.offset = u.update_id + 1; saveState();
          const chat = u.message ? u.message.chat : u.callback_query && u.callback_query.message ? u.callback_query.message.chat : null;
          if (!chat || String(chat.id) !== String(TG_CHAT)) { console.log(`[tg] abaikan chat ${chat && chat.id}`); continue; }
          if (u.callback_query) { console.log(`[tg] tombol ${u.callback_query.data}`); onCallback(u.callback_query).catch(e => console.error('tg tombol:', e.message)); continue; }
          const m = u.message; if (!m.text) continue;
          if (!m.text.startsWith('/')) { await send('Pakai tombol di bawah, atau ketik /bantuan.', MENU_KB).catch(() => {}); continue; }
          console.log(`[tg] ${m.text.slice(0, 60)}`);
          try { await onCommand(m.text); } catch (e) { await send('⚠️ Error: ' + hEsc(ctx.redact(e.message))).catch(() => {}); }
        }
      } catch (e) {
        console.error('tg poll:', e.message);
        await new Promise(r => setTimeout(r, /409|Conflict/.test(e.message) ? 60000 : 10000));
      }
    }
  }
  async function dailyTick() {
    const jam = settings.get().telegram.laporanJam;
    const hh = new Date(Date.now() + 7 * 3600e3).getUTCHours(), today = wibDate();
    if (hh >= jam && state.lastDaily !== today) {
      state.lastDaily = today; saveState();
      try { await send(await ctx.textDaily(), [[btn('« Menu', 'm')]]); } catch (e) { console.error('laporan harian:', e.message); }
    }
  }
  function start() {
    if (!aktif) return;
    if (!state.lastDaily) { state.lastDaily = wibDate(); saveState(); } // jangan kirim laporan saat pertama dipasang
    poll();
    setInterval(() => dailyTick().catch(() => {}), 60e3);
  }

  return { start, alert, alertPenjaga, send, aktif, teksRun, COMMANDS };
}

module.exports = { create };
