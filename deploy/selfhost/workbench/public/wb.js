// Workbench Marantau: antarmuka. Satu berkas, tanpa framework. Tema dan komponen dari /app.css (Panel Ops).
'use strict';
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const n0 = n => new Intl.NumberFormat('id-ID').format(n || 0);
  const when = t => t ? new Date(t).toLocaleString('id-ID', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Jakarta' }) : '-';
  const kb = n => n > 1024 ? (n / 1024).toFixed(1) + ' KB' : n + ' B';

  async function api(path, body) {
    const opt = body === undefined ? {} : { method: 'POST', headers: { 'content-type': 'application/json', 'x-ops': '1' }, body: JSON.stringify(body) };
    const r = await fetch('/wb/api' + path, opt);
    if (r.status === 401) { location.href = '/'; throw new Error('Belum login'); }
    const j = await r.json().catch(() => ({ error: 'Respons tidak valid (' + r.status + ')' }));
    if (!r.ok && !j.error) j.error = 'Galat ' + r.status;
    return j;
  }
  let toastT;
  function toast(m) { const t = $('#toast'); t.textContent = m; t.classList.remove('hidden'); clearTimeout(toastT); toastT = setTimeout(() => t.classList.add('hidden'), 4200); }
  const errbox = m => `<div class="errbox"><span>${esc(m)}</span></div>`;

  // Markdown ringan (aman: semua di-escape dulu).
  function md(t) {
    const lines = esc(t).split('\n'); let out = '', list = '', code = false, para = [];
    const inline = s => s.replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>');
    const endP = () => { if (para.length) { out += `<p>${inline(para.join(' '))}</p>`; para = []; } };
    const endL = () => { if (list) { out += `</${list}>`; list = ''; } };
    for (const l of lines) {
      if (/^```/.test(l)) { endP(); endL(); out += code ? '</pre>' : '<pre>'; code = !code; continue; }
      if (code) { out += l + '\n'; continue; }
      let m;
      if ((m = l.match(/^#{1,4}\s+(.*)$/))) { endP(); endL(); out += `<h4>${inline(m[1])}</h4>`; }
      else if ((m = l.match(/^\s*[-*]\s+(.*)$/))) { endP(); if (list !== 'ul') { endL(); out += '<ul>'; list = 'ul'; } out += `<li>${inline(m[1])}</li>`; }
      else if ((m = l.match(/^\s*\d+[.)]\s+(.*)$/))) { endP(); if (list !== 'ol') { endL(); out += '<ol>'; list = 'ol'; } out += `<li>${inline(m[1])}</li>`; }
      else if (!l.trim()) { endP(); endL(); }
      else para.push(l.trim());
    }
    endP(); endL(); if (code) out += '</pre>';
    return `<div class="prose">${out}</div>`;
  }

  const S = { st: null, runs: [], draft: null, repo: { path: '', file: null }, poll: null, openKeys: new Set(), cur: '' };
  const TABS = ['mulai', 'tugas', 'db', 'repo', 'server', 'tim', 'dokumen', 'pengaturan'];
  const TITLES = { mulai: 'Mulai', tugas: 'Tugas', db: 'Database', repo: 'Repo', server: 'Server', tim: 'Tim', dokumen: 'Dokumen', pengaturan: 'Pengaturan' };
  const STATUS = { planning: ['Manager menyusun rencana', 'warn'], awaiting_answer: ['Manager bertanya', 'warn'], awaiting_approval: ['Menunggu persetujuan rencana', 'warn'], running: ['Tim bekerja', 'warn'], reporting: ['Manager menulis laporan', 'warn'], done: ['Selesai', 'ok'], failed: ['Gagal', 'bad'], cancelled: ['Dibatalkan', ''], interrupted: ['Terhenti', 'bad'] };
  const ACTIVE = new Set(['planning', 'running', 'reporting']);
  const stChip = s => { const [t, l] = STATUS[s] || [s, '']; return `<span class="chip" data-level="${l}">${esc(t)}</span>`; };
  const agentOf = id => (S.st.tim.find(a => a.id === id) || { nama: id, id });

  // ---------------- keadaan & navigasi ----------------
  async function loadState() {
    S.st = await api('/state');
    $('#ver').textContent = 'v' + S.st.v;
    const ok = S.st.siap;
    const nav = $('#navSet'); nav.textContent = ok.ai && ok.github ? '' : 'perlu diisi'; nav.dataset.level = ok.ai ? 'warn' : 'bad';
  }
  function route() { const h = location.hash.replace(/^#\/?/, '').split('/'); return { tab: TABS.includes(h[0]) ? h[0] : 'mulai', arg: h[1] || '' }; }
  async function render() {
    clearTimeout(S.poll);
    if (!S.st) await loadState();
    const { tab, arg } = route();
    $$('.tab[data-tab]').forEach(a => a.setAttribute('aria-current', a.dataset.tab === tab ? 'page' : 'false'));
    $('#menuBtn').textContent = 'Menu: ' + TITLES[tab];
    $('.side').dataset.open = 'false';
    const key = tab + '/' + arg;
    if (key !== S.cur) { S.openKeys = new Set(); S.cur = key; }
    const v = { mulai: vMulai, tugas: vTugas, db: vDb, repo: vRepo, server: vServer, tim: vTim, dokumen: vDokumen, pengaturan: vPengaturan }[tab];
    try { await v(arg); } catch (e) { $('#main').innerHTML = errbox(e.message); }
  }
  const setMain = h => {
    const keep = new Set($$('details[data-k][open]').map(d => d.dataset.k)); S.openKeys.forEach(k => keep.add(k));
    $('#main').innerHTML = h;
    $$('details[data-k]').forEach(d => { if (keep.has(d.dataset.k)) d.open = true; });
  };
  window.addEventListener('hashchange', render);
  $('#menuBtn').addEventListener('click', () => { const s = $('.side'); const o = s.dataset.open !== 'true'; s.dataset.open = String(o); $('#menuBtn').setAttribute('aria-expanded', String(o)); });
  setInterval(() => { $('#clock').textContent = new Date().toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Jakarta' }) + ' WIB'; }, 1000);

  // ---------------- Mulai ----------------
  function vMulai() {
    const s = S.st.siap, p = S.st.pengaturan;
    const cell = (k, ok, v, sub, href) => `<div class="cell" data-level="${ok ? 'ok' : 'bad'}"><div class="k">${k}<em>${ok ? 'siap' : 'belum'}</em></div><div class="v">${v}</div><div class="s">${sub}${ok ? '' : ` <a href="${href}">Atur</a>`}</div></div>`;
    const rp = S.st.repo;
    setMain(`<section>
      <div class="head"><div><h1>Mulai</h1><p class="sub">Tulis permintaan dengan bahasa biasa. Manager menyusun rencana, tim mengerjakan dengan data nyata dari repo dan database, Manager mereview, lalu Anda memutuskan.</p></div></div>
      <div class="block block--first"><h2>Alur kerja</h2>
        <ol class="steps-list">
          <li><div><b>Tulis permintaan</b><span>Di menu Tugas. Contoh: "periksa struktur tabel Pacu Selat dan buat migrasi untuk hadiah mingguan".</span></div></li>
          <li><div><b>Manager menyusun rencana</b><span>Manager membaca repo dan database lebih dulu, lalu membagi pekerjaan ke agent yang sesuai. Anda melihat dan menyetujui (atau mencoret tugas) sebelum tim mulai.</span></div></li>
          <li><div><b>Tim mengerjakan</b><span>Tiap agent memakai alat baca langsung: isi repo, struktur dan isi tabel (hanya baca), status dan log server. Tidak ada PR yang perlu dibuat untuk sekadar memeriksa.</span></div></li>
          <li><div><b>Manager mereview</b><span>Hasil yang menebak, tidak memeriksa data, atau tidak sesuai instruksi dikembalikan untuk direvisi (maksimal ${esc(p.limits.revisi)} kali per tugas).</span></div></li>
          <li><div><b>Laporan dan keputusan Anda</b><span>Anda membaca laporan, memilih berkas yang layak, lalu menekan Buat PR. Merge tetap Anda lakukan sendiri di GitHub.</span></div></li>
        </ol></div>
      <div class="block"><h2>Kesiapan</h2>
        <div class="board" data-n="4">
          ${cell('AI', s.ai, s.ai ? p.profiles.length + ' profil' : '0 profil', 'Profil dan peran model.', '#/pengaturan')}
          ${cell('Database', s.db, s.db ? 'Terhubung' : 'Gagal', S.st.db.ok ? 'Hanya baca (mt_ops_ro).' : esc(S.st.db.error || ''), '#/db')}
          ${cell('Salinan repo', s.repo, rp.ada ? esc(rp.commit || 'ada') : 'Belum', rp.ada ? esc(rp.repo + '@' + rp.branch) : esc(rp.error || 'Belum diambil.'), '#/repo')}
          ${cell('GitHub (PR)', s.github, s.github ? 'Token ada' : 'Belum', 'Untuk membuat PR saja.', '#/pengaturan')}
        </div></div>
      <div class="block"><h2>Batas keamanan</h2>
        <ul class="prose"><li>Database hanya bisa dibaca (satu pernyataan, 5 detik, 200 baris). Tidak ada tulis ke database.</li>
        <li>Satu-satunya cara mengubah repo: branch baru + PR. Tidak pernah langsung ke <code>${esc(p.github.base)}</code>, tidak menyentuh <code>.github/</code>, dan berkas berisi pola kunci/token ditolak.</li>
        <li>Kunci AI dan token GitHub tersimpan di server, tidak pernah dikirim balik ke browser.</li>
        <li>Setiap run dibatasi ${esc(p.limits.panggilanPerTugas)} panggilan AI.</li></ul></div>
    </section>`);
  }

  // ---------------- Tugas ----------------
  const CONTOH = [
    'Periksa struktur tabel Pacu Selat (lobi, balapan, hadiah): kolom, relasi, dan fungsi api_* yang memakainya. Ringkas dalam tabel.',
    'Audit migrasi Saga 5 terbaru (0105 sampai 0107): cari risiko bug uang atau progres dan laporkan dengan bukti baris.',
    'Buat patch notes untuk perubahan terakhir di repo, mengikuti format patch notes yang sudah ada.',
  ];
  async function vTugas(arg) {
    if (arg) return vRun(arg);
    const j = await api('/runs'); S.runs = j.runs;
    const lim = S.st.pengaturan.limits;
    setMain(`<section>
      <div class="head"><div><h1>Tugas</h1><p class="sub">Satu permintaan = satu run. Hanya satu run berjalan pada satu waktu.</p></div></div>
      <div class="block block--first"><h2>Permintaan baru</h2>
        <label class="lbl" for="rq">Apa yang Anda mau?<textarea id="rq" class="in" placeholder="Tulis seperti ke manajer proyek. Sebut fitur atau tabel bila tahu; kalau tidak, Manager yang mencari."></textarea></label>
        <div class="chips">${CONTOH.map((c, i) => `<button type="button" class="chip" data-act="contoh" data-i="${i}">Contoh ${i + 1}</button>`).join('')}</div>
        <label class="chk"><input type="checkbox" id="rqJeda" ${lim.jedaRencana ? 'checked' : ''}> Tunggu persetujuan saya atas rencana Manager sebelum tim bekerja</label>
        <div class="btns"><button type="button" class="btn btn--primary" data-act="mulai" ${j.aktif ? 'disabled' : ''}>Kirim ke Manager</button><span class="msg" id="rqMsg">${j.aktif ? 'Ada run yang sedang berjalan.' : ''}</span></div>
        ${S.st.siap.ai ? '' : `<div class="errbox"><span>Profil AI belum diatur. <a href="#/pengaturan">Atur di Pengaturan</a>.</span></div>`}
      </div>
      <div class="block"><h2>Riwayat</h2>
        ${S.runs.length ? `<div class="tw"><table><thead><tr><th>Status</th><th>Permintaan</th><th class="num">Tugas</th><th class="num">Panggilan AI</th><th>Waktu</th></tr></thead><tbody>${S.runs.map(r => `<tr><td>${stChip(r.status)}</td><td class="wrap"><a href="#/tugas/${r.id}">${esc(r.prompt)}</a></td><td class="num">${r.selesai}/${r.tugas}</td><td class="num">${r.calls}</td><td>${when(r.dibuat)}</td></tr>`).join('')}</tbody></table></div>` : '<div class="empty"><b>Belum ada run.</b> Mulai dengan permintaan di atas.</div>'}
      </div></section>`);
    const nav = $('#navTugas'); nav.textContent = j.aktif ? 'berjalan' : ''; nav.dataset.level = 'warn';
    if (j.aktif) S.poll = setTimeout(() => route().tab === 'tugas' && !route().arg && render(), 4000);
  }

  function phase(run) {
    const t = run.plan ? run.plan.tugas : [], ts = t.map(x => (run.tasks[x.id] || {}).status);
    const done = ts.filter(x => x === 'selesai').length;
    const failed = run.status === 'failed' || run.status === 'interrupted';
    const planS = ['planning', 'awaiting_answer', 'awaiting_approval'].includes(run.status) ? 'aktif' : run.plan ? 'selesai' : '';
    const timS = run.status === 'running' && !ts.includes('direview') ? 'aktif' : run.plan && run.status !== 'awaiting_approval' && done === t.length && t.length ? 'selesai' : run.status === 'running' ? 'selesai' : '';
    const revS = ts.includes('direview') ? 'aktif' : done === t.length && t.length && run.status !== 'awaiting_approval' ? 'selesai' : '';
    const repS = run.status === 'reporting' ? 'aktif' : run.status === 'done' ? 'selesai' : '';
    const a = [planS, timS, revS, repS];
    if (failed) { const i = a.findIndex(x => x === 'aktif'); a[i >= 0 ? i : (run.plan ? 1 : 0)] = 'gagal'; }
    return { a, done, total: t.length };
  }

  async function vRun(id) {
    const j = await api('/runs/' + id);
    if (j.error) { setMain(errbox(j.error) + '<p><a href="#/tugas">Kembali</a></p>'); return; }
    const r = j.run, ph = phase(r), team = S.st.tim;
    const busy = ACTIVE.has(r.status);
    let body = '';
    if (r.status === 'awaiting_answer') {
      body += `<div class="block"><h2>Manager bertanya</h2><div class="prose">${md(r.pertanyaan)}</div>
        <label class="lbl" for="jwb">Jawaban Anda<textarea id="jwb" class="in"></textarea></label>
        <div class="btns"><button class="btn btn--primary" data-act="jawab" data-id="${r.id}">Kirim jawaban</button></div></div>`;
    }
    if (r.plan) {
      body += `<div class="block"><h2>Rencana Manager</h2><div class="prose">${md(r.plan.ringkasan)}</div>${r.plan.risiko ? `<p class="note"><b>Risiko / perlu keputusan:</b> ${esc(r.plan.risiko)}</p>` : ''}`;
      if (r.status === 'awaiting_approval') {
        body += `<p class="note">Centang tugas yang boleh dijalankan. Mencoret satu tugas juga melewati tugas yang bergantung padanya.</p><div class="tw"><table><thead><tr><th></th><th>ID</th><th>Agent</th><th>Tugas</th></tr></thead><tbody>${r.plan.tugas.map(t => `<tr><td><input type="checkbox" class="pick" value="${esc(t.id)}" checked></td><td>${esc(t.id)}</td><td><span class="dot dot-${esc(t.agent)}"></span> ${esc(agentOf(t.agent).nama)}</td><td class="wrap"><b>${esc(t.judul)}</b><br><span class="dim">${esc(t.instruksi)}</span>${t.butuh.length ? `<br><span class="dim">menunggu: ${esc(t.butuh.join(', '))}</span>` : ''}</td></tr>`).join('')}</tbody></table></div>
          <div class="btns"><button class="btn btn--primary" data-act="setujui" data-id="${r.id}">Setujui dan jalankan</button><button class="btn" data-act="batal" data-id="${r.id}">Batalkan</button></div>`;
      }
      body += '</div>';
      if (r.status !== 'awaiting_approval') {
        body += `<div class="block"><h2>Kerja tim</h2><div class="cards">${r.plan.tugas.map(t => {
          const s = r.tasks[t.id] || {}, a = agentOf(t.agent), tl = [...new Set((r.toolLog || []).filter(x => x.task === t.id).map(x => x.alat + (x.galat ? '!' : '')))];
          const lv = s.status === 'selesai' ? 'ok' : s.status === 'dilewati' ? 'bad' : s.status ? 'warn' : '';
          return `<div class="ai-card"><h3><span class="agent"><span class="dot dot-${esc(t.agent)}"></span>${esc(a.nama)} <span class="dim">${esc(t.id)}</span></span><span class="chip" data-level="${lv}">${esc(s.status || 'menunggu')}</span></h3>
            <div class="judul">${esc(t.judul)}</div>
            <div class="chips">${tl.map(x => `<span class="chip" ${x.endsWith('!') ? 'data-level="bad"' : ''}>${esc(x)}</span>`).join('')}${s.revisi ? `<span class="chip" data-level="warn">revisi ${s.revisi}x</span>` : ''}${s.diterimaDenganCatatan ? '<span class="chip" data-level="warn">diterima dengan catatan</span>' : ''}</div>
            ${s.review ? `<p class="saran"><b>Review Manager (${esc(s.review.putusan)}):</b> ${esc(s.review.catatan)}</p>` : ''}
            <details class="d" data-k="i-${esc(t.id)}"><summary>Instruksi Manager</summary><div class="prose"><p>${esc(t.instruksi)}</p></div></details>
            ${s.output ? `<details class="d" data-k="o-${esc(t.id)}"><summary>Hasil</summary><div>${md(s.output)}</div></details>` : ''}
            ${(s.files || []).map((f, i) => `<details class="d" data-k="f-${esc(t.id)}-${i}"><summary>Berkas: ${esc(f.path)} <span class="dim">${kb(f.content.length)}</span></summary><div><pre>${esc(f.content.slice(0, 30000))}</pre></div></details>`).join('')}
          </div>`; }).join('')}</div></div>`;
      }
    }
    if (r.images && r.images.length) body += `<div class="block"><h2>Gambar</h2><div class="gal">${r.images.map(im => `<figure><img src="/wb/api/runs/${r.id}/img/${im.n}" alt="Gambar ${im.n}"><figcaption>#${im.n} ${esc(im.prompt.slice(0, 120))}</figcaption></figure>`).join('')}</div></div>`;
    if (r.report) {
      const bs = j.hasil;
      body += `<div class="block"><h2>Laporan akhir</h2>${md(r.report.teks)}</div>`;
      body += `<div class="block"><h2>Pull request</h2>${r.pr ? `<div class="empty"><b>PR dibuat:</b> <a href="${esc(r.pr.url)}" target="_blank" rel="noopener">#${esc(r.pr.nomor)}</a> (${esc(r.pr.berkas.join(', '))}). Periksa dan merge sendiri di GitHub.</div>` : bs.length ? `<p class="note">Pilih berkas yang layak masuk. PR dibuat sebagai branch baru; Anda yang merge.</p>
        <div class="tw"><table><thead><tr><th></th><th>Berkas</th><th>Dari</th><th class="num">Ukuran</th></tr></thead><tbody>${bs.map(f => `<tr><td><input type="checkbox" class="prf" value="${esc(f.path)}" checked></td><td class="name">${esc(f.path)}</td><td>${esc(agentOf(f.agent).nama)} (${esc(f.tugas)})</td><td class="num">${kb(f.ukuran)}</td></tr>`).join('')}</tbody></table></div>
        <label class="lbl" for="prj">Judul PR<input id="prj" class="in" value="${esc(r.report.judulPr || '')}"></label>
        <div class="btns"><button class="btn btn--primary" data-act="pr" data-id="${r.id}" ${S.st.siap.github ? '' : 'disabled'}>Buat PR</button>${S.st.siap.github ? '' : '<span class="msg" data-level="bad">Token GitHub belum diisi (Pengaturan).</span>'}<span class="msg" id="prMsg"></span></div>` : '<div class="empty">Tidak ada berkas untuk diajukan. Run ini hanya analisis.</div>'}</div>`;
    }
    const act = [];
    if (busy) act.push(`<button class="btn btn--danger" data-act="batal" data-id="${r.id}">Batalkan</button>`);
    if (['interrupted', 'failed'].includes(r.status)) act.push(`<button class="btn btn--primary" data-act="lanjut" data-id="${r.id}">Lanjutkan</button>`);
    if (!busy) act.push(`<button class="btn" data-act="hapus" data-id="${r.id}">Hapus run</button>`);
    const used = Object.entries(r.byProfile || {}).map(([k, v]) => `${esc((S.st.pengaturan.profiles.find(p => p.id === k) || { label: k }).label)} ×${v}`).join(', ');
    setMain(`<section>
      <div class="head"><div><p class="crumbs"><a href="#/tugas">Tugas</a> / <span>${esc(r.id)}</span></p><h1>${esc(r.prompt.length > 70 ? r.prompt.slice(0, 70) + '…' : r.prompt)}</h1><p class="sub">${stChip(r.status)} ${esc(r.prompt.length > 70 ? r.prompt : '')}</p></div><div class="tools">${act.join('')}</div></div>
      ${r.error ? errbox(r.error) : ''}
      <div class="pipe"><div data-s="${ph.a[0]}">1. Rencana Manager<small>${r.plan ? r.plan.tugas.length + ' tugas' : 'menyusun'}</small></div><div data-s="${ph.a[1]}">2. Tim bekerja<small>${ph.done}/${ph.total} selesai</small></div><div data-s="${ph.a[2]}">3. Review Manager<small>per tugas</small></div><div data-s="${ph.a[3]}">4. Laporan<small>${r.status === 'done' ? 'siap' : '-'}</small></div></div>
      ${body}
      <div class="block"><h2>Catatan teknis</h2><p class="note">${r.calls} panggilan AI · ${n0(r.token.masuk)} token masuk, ${n0(r.token.keluar)} keluar${used ? ' · ' + used : ''}</p>
        <details class="d" data-k="log"><summary>Log kejadian (${r.log.length})</summary><div><pre>${esc(r.log.slice(-60).map(l => new Date(l.t).toLocaleTimeString('id-ID', { timeZone: 'Asia/Jakarta' }) + '  ' + l.msg).join('\n'))}</pre></div></details>
        <details class="d" data-k="alat"><summary>Pemakaian alat (${(r.toolLog || []).length})</summary><div class="tw"><table><thead><tr><th>Tugas</th><th>Agent</th><th>Alat</th><th>Isi</th><th class="num">ms</th></tr></thead><tbody>${(r.toolLog || []).slice(-80).map(x => `<tr${x.galat ? ' data-level="bad"' : ''}><td>${esc(x.task)}</td><td>${esc(x.agent)}</td><td>${esc(x.alat)}</td><td class="q">${esc(x.arg)}</td><td class="num">${x.ms}</td></tr>`).join('')}</tbody></table></div></details></div>
    </section>`);
    if (busy) S.poll = setTimeout(() => { const rt = route(); if (rt.tab === 'tugas' && rt.arg === id) render(); }, 2500);
  }

  // ---------------- Database ----------------
  function tableHtml(r) {
    if (r.error) return errbox(r.error);
    if (!r.rows.length) return '<div class="empty">0 baris.</div>';
    const cell = v => v == null ? '<span class="dim">NULL</span>' : esc(typeof v === 'object' ? JSON.stringify(v) : String(v));
    return `<div class="tw tall"><table><thead><tr>${r.columns.map(c => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${r.rows.map(row => `<tr>${r.columns.map(c => `<td class="wrap">${cell(row[c])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>${r.truncated ? '<p class="note">Dibatasi 200 baris.</p>' : `<p class="note">${r.rows.length} baris.</p>`}`;
  }
  function vDb() {
    setMain(`<section>
      <div class="head"><div><h1>Database</h1><p class="sub">Baca langsung dari Postgres produksi lewat role hanya-baca. Tidak membuat PR, tidak bisa mengubah data.</p></div></div>
      <div class="block block--first"><h2>Struktur tabel</h2><p class="note">Ketik kata kunci nama tabel (pisahkan spasi, cocok salah satu). Mencari di schema <code>game</code>.</p>
        <div class="row2"><label class="lbl">Kata kunci<input id="sq" class="in" placeholder="pacu race selat" value="pacu race selat"></label><div class="btns"><button class="btn btn--primary" data-act="schema">Lihat struktur</button><button class="btn" data-act="fungsi">Lihat fungsi api_*</button></div></div>
        <div id="schemaOut"></div></div>
      <div class="block"><h2>Query</h2><p class="note">Satu pernyataan SELECT / WITH / EXPLAIN / SHOW. Maksimal 5 detik dan 200 baris. Schema <code>auth</code> tidak terbaca.</p>
        <label class="lbl" for="sql">SQL<textarea id="sql" class="in mono tall">select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'game'
  and (table_name ilike '%pacu%' or table_name ilike '%race%' or table_name ilike '%selat%')
order by table_name, ordinal_position;</textarea></label>
        <div class="btns"><button class="btn btn--primary" data-act="sql">Jalankan</button><span class="msg" id="sqlMsg"></span></div><div id="sqlOut"></div></div>
    </section>`);
  }
  async function doSchema(fn) {
    const q = $('#sq').value, out = $('#schemaOut'); out.innerHTML = '<div class="skel"><i></i><i></i></div>';
    const j = await api(fn === 'fungsi' ? '/db/functions?q=' + encodeURIComponent(q) : '/db/schema?q=' + encodeURIComponent(q));
    if (j.error) { out.innerHTML = errbox(j.error); return; }
    if (fn === 'fungsi') { out.innerHTML = j.fungsi.length ? `<div class="tw tall"><table><thead><tr><th>Fungsi</th><th>Argumen</th><th>Hasil</th></tr></thead><tbody>${j.fungsi.map(f => `<tr><td class="name">${esc(f.skema)}.${esc(f.nama)}</td><td class="q">${esc(f.argumen)}</td><td class="q">${esc(f.hasil)}</td></tr>`).join('')}</tbody></table></div>` : '<div class="empty">Tidak ada fungsi yang cocok.</div>'; return; }
    const names = Object.keys(j.tabel);
    out.innerHTML = names.length ? `<p class="note">${names.length} tabel cocok.</p><div class="cards">${names.map(t => `<div class="ai-card"><h3>game.${esc(t)}<span class="dim">${j.tabel[t].kolom.length} kolom</span></h3><div class="tw"><table><thead><tr><th>Kolom</th><th>Tipe</th><th>Null</th></tr></thead><tbody>${j.tabel[t].kolom.map(c => `<tr><td class="name">${esc(c.nama)}</td><td class="dim">${esc(c.tipe)}</td><td class="dim">${c.null ? 'ya' : 'tidak'}</td></tr>`).join('')}</tbody></table></div>${j.tabel[t].indeks.length ? `<details class="d" data-k="ix-${esc(t)}"><summary>${j.tabel[t].indeks.length} indeks</summary><div><pre>${esc(j.tabel[t].indeks.join('\n'))}</pre></div></details>` : ''}</div>`).join('')}</div>` : '<div class="empty">Tidak ada tabel yang cocok di schema game.</div>';
  }

  // ---------------- Repo ----------------
  async function vRepo() {
    const st = await api('/repo/status');
    setMain(`<section>
      <div class="head"><div><h1>Repo</h1><p class="sub">Salinan repo di server (baca langsung, tanpa PR). ${st.ada ? `Terakhir diambil ${when(st.syncAt)}: <b>${esc(st.commit)}</b> ${esc(st.pesan)}` : esc(st.error || 'Belum diambil.')}</p></div><div class="tools"><button class="btn" data-act="sync">Ambil terbaru</button></div></div>
      <div class="block block--first"><h2>Cari teks</h2><div class="row2"><label class="lbl">Pola (regex)<input id="gq" class="in" placeholder="pacu_selat"></label><label class="lbl">Folder (opsional)<input id="gp" class="in" placeholder="supabase/migrations"></label></div><div class="btns"><button class="btn btn--primary" data-act="grep">Cari</button></div><div id="grepOut"></div></div>
      <div class="block"><h2>Jelajah</h2><div id="repoOut"><div class="skel"><i></i><i></i></div></div></div>
    </section>`);
    if (st.ada) browse(S.repo.path); else $('#repoOut').innerHTML = '<div class="empty">Salinan repo belum ada. Tekan <b>Ambil terbaru</b>.</div>';
  }
  async function browse(p) {
    S.repo.path = p; const out = $('#repoOut'); if (!out) return;
    const j = await api('/repo/tree?path=' + encodeURIComponent(p));
    if (j.error) { out.innerHTML = errbox(j.error); return; }
    const parts = p ? p.split('/') : [];
    const crumbs = `<div class="crumbs"><a href="#" data-act="dir" data-p="">repo</a>${parts.map((x, i) => ` / <a href="#" data-act="dir" data-p="${esc(parts.slice(0, i + 1).join('/'))}">${esc(x)}</a>`).join('')}</div>`;
    out.innerHTML = crumbs + `<div class="tree">${j.item.map(i => `<a href="#" data-act="${i.tipe === 'dir' ? 'dir' : 'file'}" data-p="${esc(i.jalur)}">${i.tipe === 'dir' ? '📁 ' : ''}${esc(i.jalur.split('/').pop())}${i.tipe === 'dir' ? '/' : `<small>${kb(i.ukuran)}</small>`}</a>`).join('') || '<div class="empty">Kosong.</div>'}</div>`;
  }
  async function openFile(p, range) {
    const out = $('#repoOut'); const j = await api('/repo/file?path=' + encodeURIComponent(p) + (range ? '&range=' + range : ''));
    if (j.error) { out.innerHTML = errbox(j.error); return; }
    const dir = p.includes('/') ? p.slice(0, p.lastIndexOf('/')) : '';
    out.innerHTML = `<div class="crumbs"><a href="#" data-act="dir" data-p="${esc(dir)}">← ${esc(dir || 'repo')}</a> / <b>${esc(p.split('/').pop())}</b> <span class="dim">baris ${j.dari}-${j.sampai} dari ${j.baris}</span></div><pre>${esc(j.teks)}</pre>${j.potong ? '<p class="note">Dipotong. Pakai rentang baris untuk bagian lain.</p>' : ''}`;
  }

  // ---------------- Server ----------------
  const SVC = ['supabase-db', 'supabase-rest', 'supabase-auth', 'realtime-dev.supabase-realtime', 'supabase-envoy', 'marantau-caddy', 'marantau-ops'];
  function vServer() {
    setMain(`<section>
      <div class="head"><div><h1>Server</h1><p class="sub">Kondisi VM dan log layanan, lewat Panel Ops (hanya baca, rahasia disamarkan). Restart tetap dari Panel Ops.</p></div></div>
      <div class="block block--first"><h2>Kondisi</h2><div class="btns"><button class="btn btn--primary" data-act="ops-status">Ambil kondisi server</button></div><div id="opsOut"></div></div>
      <div class="block"><h2>Log layanan</h2><div class="row3"><label class="lbl">Layanan<select id="lsv" class="in">${SVC.map(s => `<option>${s}</option>`).join('')}</select></label><label class="lbl">Baris<input id="lln" class="in" type="number" min="10" max="300" value="100"></label><label class="lbl">Saring (opsional)<input id="lft" class="in" placeholder="error"></label></div><div class="btns"><button class="btn" data-act="ops-logs">Ambil log</button></div><div id="logOut"></div></div>
    </section>`);
  }

  // ---------------- Tim ----------------
  function vTim() {
    const p = S.st.pengaturan, profs = p.profiles;
    const roleName = r => (p.roleList.find(x => x.id === r) || {}).label || r;
    const roleProf = r => { const id = p.roles[r] || (r !== 'gambar' ? p.roles.orkestrator : ''); const pr = profs.find(x => x.id === id); return pr ? pr.label : 'belum diatur'; };
    setMain(`<section>
      <div class="head"><div><h1>Tim</h1><p class="sub">Sebelas agent. Tiap agent punya peran model (Coder, Cerita, dst.) yang menentukan AI mana yang dipakai. Bisa diganti per agent.</p></div></div>
      <div class="block block--first"><div class="cards">${S.st.tim.map(a => `<div class="ai-card" data-agent="${esc(a.id)}">
        <h3><span class="agent"><span class="dot dot-${esc(a.id)}"></span>${esc(a.nama)}</span><label class="chk"><input type="checkbox" data-f="aktif" ${a.aktif ? 'checked' : ''} ${a.id === 'manager' ? 'disabled' : ''}> aktif</label></h3>
        <p class="saran">${esc(a.ringkas)}</p>
        <div class="chips"><span class="chip">peran model: ${esc(roleName(a.peran))}</span>${a.alat.map(t => `<span class="chip">${esc(t)}</span>`).join('')}</div>
        <label class="lbl">Model untuk agent ini<select class="in" data-f="profil"><option value="">Ikut peran (${esc(roleProf(a.peran))})</option>${profs.map(x => `<option value="${esc(x.id)}" ${a.profil === x.id ? 'selected' : ''}>${esc(x.label)} · ${esc(x.model)}</option>`).join('')}</select></label>
        <details class="d" data-k="ps-${esc(a.id)}"><summary>Persona${a.personaTambahan ? ' (ada tambahan)' : ''}</summary><div><p class="note">Bawaan (ringkas, dari repo):</p><pre>${esc(a.persona)}</pre>
          <label class="lbl">Tambahan persona (disimpan di server, tidak di repo)<textarea class="in mono tall" data-f="persona">${esc(a.personaTambahan)}</textarea></label></div></details>
        <div class="btns"><button class="btn btn--small" data-act="simpan-agent" data-id="${esc(a.id)}">Simpan</button></div></div>`).join('')}</div></div>
      <div class="block"><h2>Impor persona lengkap</h2><p class="note">Unggah <code>agents.json</code> (format Workbench lama: <code>shared</code> + <code>agents[].persona</code>). Persona masuk ke kolom Tambahan tiap agent, konteks bersama menjadi dokumen. Disimpan di server, tidak masuk repo publik.</p>
        <input type="file" id="impFile" accept=".json,application/json" class="hide-file"><div class="btns"><button class="btn" data-act="impor">Pilih agents.json</button><span class="msg" id="impMsg"></span></div></div>
    </section>`);
  }

  // ---------------- Dokumen ----------------
  async function vDokumen() {
    const docs = S.st.dokumen, ids = ['semua', ...S.st.tim.map(a => a.id)];
    setMain(`<section>
      <div class="head"><div><h1>Dokumen</h1><p class="sub">Bahan rujukan yang dibaca agent (lore, aturan, patch notes). Hanya agent yang ditandai yang menerimanya, supaya hemat token. Disimpan di server, bukan di repo.</p></div></div>
      <div class="block block--first"><h2>Tersimpan</h2>${docs.length ? `<div class="tw"><table><thead><tr><th>Nama</th><th>Untuk</th><th class="num">Ukuran</th><th>Diubah</th><th></th></tr></thead><tbody>${docs.map(d => `<tr><td class="name">${esc(d.nama)}</td><td class="wrap">${d.tags.map(t => `<span class="chip">${esc(t)}</span>`).join(' ')}</td><td class="num">${kb(d.ukuran)}</td><td>${when(d.diubah)}</td><td><button class="btn btn--small" data-act="doc-edit" data-id="${esc(d.id)}">Ubah</button> <button class="btn btn--small btn--danger" data-act="doc-hapus" data-id="${esc(d.id)}">Hapus</button></td></tr>`).join('')}</tbody></table></div>` : '<div class="empty"><b>Belum ada dokumen.</b></div>'}</div>
      <div class="block"><h2>Tambah / ubah</h2>
        <input type="hidden" id="dId"><label class="lbl">Nama<input id="dNama" class="in" placeholder="Lore Marantau (kompendium)"></label>
        <div class="lbl">Dibaca oleh<div class="chips">${ids.map(t => `<label class="chk"><input type="checkbox" class="dtag" value="${esc(t)}" ${t === 'semua' ? '' : ''}> ${esc(t === 'semua' ? 'semua agent' : agentOf(t).nama)}</label>`).join('')}</div></div>
        <label class="lbl" for="dTeks">Isi<textarea id="dTeks" class="in mono tall" placeholder="Tempel teks, atau pilih berkas .md/.txt"></textarea></label>
        <input type="file" id="dFile" accept=".md,.txt,.markdown,.json,.csv,.sql" class="hide-file">
        <div class="btns"><button class="btn" data-act="doc-file">Pilih berkas</button><button class="btn btn--primary" data-act="doc-simpan">Simpan dokumen</button><span class="msg" id="dMsg"></span></div></div>
    </section>`);
  }

  // ---------------- Pengaturan ----------------
  const slug = s => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 32);
  function newDraft() { const p = S.st.pengaturan; return { profiles: p.profiles.map(x => ({ ...x, key: '' })), roles: { ...p.roles }, github: { repo: p.github.repo, base: p.github.base, token: '' }, limits: { ...p.limits } }; }
  function vPengaturan() {
    if (!S.draft) S.draft = newDraft();
    const d = S.draft, p = S.st.pengaturan;
    setMain(`<section>
      <div class="head"><div><h1>Pengaturan</h1><p class="sub">Isi lebih dari satu profil AI, lalu tentukan profil mana untuk tiap fungsi. Kunci disimpan di server dan tidak pernah ditampilkan lagi.</p></div><div class="tools"><button class="btn btn--primary" data-act="simpan-set">Simpan semua</button></div></div>
      <datalist id="models"><option>claude-opus-5-5</option><option>claude-sonnet-5-5</option><option>claude-haiku-5-5</option><option>claude-fable-5-2</option><option>gemini-2.5-pro</option><option>gemini-2.5-flash</option><option>gemini-2.5-flash-image</option></datalist>
      <div class="block block--first"><h2>1. Profil AI</h2><p class="note">Satu profil = satu penyedia + satu model + satu kunci. Contoh: "Claude Opus" (orkestrator), "Claude Sonnet" (coder), "Gemini Pro" (cerita), "Gemini Gambar". Penyedia OpenAI-kompatibel (OpenRouter, Groq, dll.) bisa dipakai lewat Base URL.</p>
        <div class="cards">${d.profiles.map((x, i) => `<div class="ai-card" data-i="${i}"><h3>${esc(x.label || 'Profil')}<span class="dim">${x.ada ? 'kunci …' + esc(x.akhir) : 'belum ada kunci'}</span></h3>
          <label class="lbl">Nama<input class="in" data-p="${i}.label" value="${esc(x.label)}"></label>
          <div class="row2"><label class="lbl">Penyedia<select class="in" data-p="${i}.provider">${p.providers.map(v => `<option value="${v}" ${x.provider === v ? 'selected' : ''}>${v === 'openai' ? 'openai / kompatibel' : v}</option>`).join('')}</select></label>
          <label class="lbl">Model<input class="in" list="models" data-p="${i}.model" value="${esc(x.model)}"></label></div>
          <label class="lbl">Kunci API<input class="in" type="password" autocomplete="new-password" data-p="${i}.key" placeholder="${x.ada ? 'biarkan kosong untuk tetap memakai yang lama' : 'tempel kunci'}"></label>
          <label class="lbl">Base URL (opsional, https)<input class="in" data-p="${i}.baseUrl" value="${esc(x.baseUrl || '')}" placeholder="kosong = alamat resmi penyedia"></label>
          <div class="btns"><button class="btn btn--small" data-act="tes-profil" data-i="${i}">Simpan dan tes</button><button class="btn btn--small btn--danger" data-act="hapus-profil" data-i="${i}">Hapus</button><span class="msg" id="tp${i}"></span></div></div>`).join('')}</div>
        <div class="btns"><button class="btn" data-act="tambah-profil">Tambah profil</button></div></div>
      <div class="block"><h2>2. Peran → profil</h2><p class="note">Tiap fungsi memakai profil yang Anda pilih. Peran kosong memakai Orkestrator (kecuali Gambar, yang wajib dipetakan ke model pembuat gambar).</p>
        <div class="row3">${p.roleList.map(r => `<label class="lbl">${esc(r.label)}<select class="in" data-r="${r.id}"><option value="">${r.id === 'orkestrator' ? '(pilih)' : r.id === 'gambar' ? '(tidak dipakai)' : '(ikut Orkestrator)'}</option>${d.profiles.map(x => `<option value="${esc(x.id)}" ${d.roles[r.id] === x.id ? 'selected' : ''}>${esc(x.label)} · ${esc(x.model)}</option>`).join('')}</select><small>${esc(r.hint)}</small></label>`).join('')}</div></div>
      <div class="block"><h2>3. GitHub (hanya untuk membuat PR)</h2><p class="note">Buat <b>fine-grained token</b> khusus repo ini dengan izin <b>Contents: Read and write</b> dan <b>Pull requests: Read and write</b>. Jangan beri izin Workflows atau Administration. Pastikan branch <code>main</code> dilindungi (wajib PR) agar token ini tidak pernah bisa menimpa <code>main</code>. Membaca repo tidak memerlukan token.</p>
        <div class="row3"><label class="lbl">Repo<input class="in" data-g="repo" value="${esc(d.github.repo)}"></label><label class="lbl">Branch dasar<input class="in" data-g="base" value="${esc(d.github.base)}"></label><label class="lbl">Token<input class="in" type="password" autocomplete="new-password" data-g="token" placeholder="${p.github.ada ? 'terisi (…' + esc(p.github.akhir) + '), kosong = tetap' : 'github_pat_…'}"></label></div>
        <div class="btns"><button class="btn btn--small" data-act="tes-github">Simpan dan tes token</button>${p.github.ada ? '<button class="btn btn--small btn--danger" data-act="hapus-token">Hapus token</button>' : ''}<span class="msg" id="tgMsg"></span></div></div>
      <div class="block"><h2>4. Batas</h2><div class="row3">
        <label class="lbl">Panggilan AI per run<input class="in" type="number" data-l="panggilanPerTugas" value="${esc(d.limits.panggilanPerTugas)}"><small>Pengaman biaya.</small></label>
        <label class="lbl">Maks token per jawaban<input class="in" type="number" data-l="maksToken" value="${esc(d.limits.maksToken)}"></label>
        <label class="lbl">Revisi per tugas<input class="in" type="number" data-l="revisi" value="${esc(d.limits.revisi)}"><small>0 = Manager tidak minta revisi.</small></label>
        <label class="lbl">Langkah alat per giliran<input class="in" type="number" data-l="langkahAlat" value="${esc(d.limits.langkahAlat)}"></label>
        <label class="chk"><input type="checkbox" data-l="jedaRencana" ${d.limits.jedaRencana ? 'checked' : ''}> Minta persetujuan rencana (bawaan)</label></div></div>
    </section>`);
  }
  function collect() {
    const d = S.draft;
    return { profiles: d.profiles.map(x => ({ id: x.id, label: x.label, provider: x.provider, model: x.model, baseUrl: x.baseUrl || '', key: x.key || '' })), roles: d.roles,
      github: { repo: d.github.repo, base: d.github.base, ...(d.github.token ? { token: d.github.token } : {}) }, limits: d.limits };
  }
  async function saveSettings(extra) {
    const j = await api('/pengaturan', { ...collect(), ...(extra || {}) });
    if (j.error) { toast(j.error); return false; }
    await loadState(); S.draft = newDraft(); return true;
  }

  // ---------------- Aksi (delegasi klik) ----------------
  document.addEventListener('input', e => {
    const t = e.target, d = S.draft; if (!d) return;
    if (t.dataset.p) { const [i, f] = t.dataset.p.split('.'); d.profiles[+i][f] = t.value; }
    else if (t.dataset.g) d.github[t.dataset.g] = t.value;
    else if (t.dataset.l) d.limits[t.dataset.l] = t.type === 'checkbox' ? t.checked : t.value;
    else if (t.dataset.r) d.roles[t.dataset.r] = t.value;
  });
  document.addEventListener('change', e => { const t = e.target; if (t.dataset && t.dataset.r && S.draft) S.draft.roles[t.dataset.r] = t.value; if (t.dataset && t.dataset.l && t.type === 'checkbox' && S.draft) S.draft.limits[t.dataset.l] = t.checked; });

  const busy = (b, on) => { if (b) { b.disabled = !!on; b.setAttribute('aria-busy', String(!!on)); } };
  document.addEventListener('click', async e => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    const act = b.dataset.act, id = b.dataset.id;
    if (['dir', 'file'].includes(act)) e.preventDefault();
    try {
      switch (act) {
        case 'contoh': $('#rq').value = CONTOH[+b.dataset.i]; break;
        case 'mulai': {
          const prompt = $('#rq').value.trim(); if (prompt.length < 10) { $('#rqMsg').textContent = 'Tulis permintaan yang lebih jelas.'; $('#rqMsg').dataset.level = 'bad'; break; }
          busy(b, true); const j = await api('/runs', { prompt, auto: !$('#rqJeda').checked }); busy(b, false);
          if (j.error) { $('#rqMsg').textContent = j.error; $('#rqMsg').dataset.level = 'bad'; break; }
          location.hash = '#/tugas/' + j.id; break;
        }
        case 'jawab': { const t = $('#jwb').value.trim(); if (!t) break; busy(b, true); const j = await api(`/runs/${id}/jawab`, { teks: t }); if (j.error) toast(j.error); render(); break; }
        case 'setujui': { const keep = $$('.pick:checked').map(x => x.value); if (!keep.length) { toast('Pilih minimal satu tugas.'); break; } busy(b, true); const j = await api(`/runs/${id}/setujui`, { rencana: { tugas: keep } }); if (j.error) toast(j.error); render(); break; }
        case 'batal': { if (!confirm('Batalkan run ini? Pekerjaan yang sudah jalan berhenti setelah panggilan AI berikutnya.')) break; await api(`/runs/${id}/batal`, {}); render(); break; }
        case 'lanjut': { const j = await api(`/runs/${id}/lanjut`, {}); if (j.error) toast(j.error); render(); break; }
        case 'hapus': { if (!confirm('Hapus run ini dari riwayat?')) break; const j = await api(`/runs/${id}/hapus`, {}); if (j.error) { toast(j.error); break; } location.hash = '#/tugas'; break; }
        case 'pr': {
          const berkas = $$('.prf:checked').map(x => x.value); if (!berkas.length) { toast('Pilih minimal satu berkas.'); break; }
          if (!confirm(`Buat PR berisi ${berkas.length} berkas ke GitHub?\n\n${berkas.join('\n')}\n\nPR tidak otomatis di-merge.`)) break;
          busy(b, true); $('#prMsg').textContent = 'Membuat branch dan PR…';
          const j = await api(`/runs/${id}/pr`, { berkas, judul: $('#prj').value }); busy(b, false);
          if (j.error) { $('#prMsg').textContent = j.error; $('#prMsg').dataset.level = 'bad'; break; }
          toast('PR dibuat: #' + j.nomor); render(); break;
        }
        case 'schema': case 'fungsi': busy(b, true); await doSchema(act); busy(b, false); break;
        case 'sql': {
          busy(b, true); $('#sqlMsg').textContent = ''; const t0 = performance.now();
          const j = await api('/db/query', { sql: $('#sql').value }); busy(b, false);
          $('#sqlOut').innerHTML = tableHtml(j); $('#sqlMsg').textContent = Math.round(performance.now() - t0) + ' ms'; break;
        }
        case 'sync': busy(b, true); { const j = await api('/repo/sync', {}); busy(b, false); toast(j.error ? j.error : 'Salinan repo diperbarui: ' + j.commit); render(); } break;
        case 'dir': browse(b.dataset.p); break;
        case 'file': openFile(b.dataset.p); break;
        case 'grep': {
          const q = $('#gq').value.trim(); if (!q) break; busy(b, true);
          const j = await api('/repo/grep?q=' + encodeURIComponent(q) + '&path=' + encodeURIComponent($('#gp').value.trim())); busy(b, false);
          $('#grepOut').innerHTML = j.error ? errbox(j.error) : j.hasil.length ? `<p class="note">${j.jumlah} kecocokan${j.terpotong ? ' (dipotong)' : ''}.</p><pre>${esc(j.hasil.join('\n'))}</pre>` : '<div class="empty">Tidak ada kecocokan.</div>'; break;
        }
        case 'ops-status': { busy(b, true); const j = await api('/ops/status'); busy(b, false); $('#opsOut').innerHTML = j.error ? errbox(j.error) : `<pre>${esc(j.teks)}</pre>`; break; }
        case 'ops-logs': { busy(b, true); const j = await api(`/ops/logs?service=${encodeURIComponent($('#lsv').value)}&lines=${+$('#lln').value || 100}&filter=${encodeURIComponent($('#lft').value)}`); busy(b, false); $('#logOut').innerHTML = j.error ? errbox(j.error) : `<pre>${esc(j.teks)}</pre>`; break; }
        case 'simpan-agent': {
          const card = b.closest('[data-agent]'); const aid = b.dataset.id;
          const o = { profil: $('[data-f=profil]', card).value, persona: $('[data-f=persona]', card).value }; const ak = $('[data-f=aktif]', card); if (ak && !ak.disabled) o.aktif = ak.checked;
          const j = await api('/pengaturan', { agents: { [aid]: o } }); toast(j.error || 'Tersimpan.'); await loadState(); break;
        }
        case 'impor': $('#impFile').click(); break;
        case 'doc-file': $('#dFile').click(); break;
        case 'doc-simpan': {
          const tags = $$('.dtag:checked').map(x => x.value);
          const j = await api('/dokumen', { id: $('#dId').value, nama: $('#dNama').value, tags: tags.length ? tags : ['semua'], teks: $('#dTeks').value });
          $('#dMsg').textContent = j.error || 'Tersimpan.'; $('#dMsg').dataset.level = j.error ? 'bad' : 'ok'; if (!j.error) { await loadState(); render(); } break;
        }
        case 'doc-edit': { const j = await api('/dokumen?id=' + encodeURIComponent(id)); if (j.error) { toast(j.error); break; } $('#dId').value = j.id; $('#dNama').value = j.nama; $('#dTeks').value = j.teks; $$('.dtag').forEach(x => { x.checked = j.tags.includes(x.value); }); $('#dNama').scrollIntoView({ block: 'center' }); break; }
        case 'doc-hapus': { if (!confirm('Hapus dokumen ini?')) break; await api('/dokumen/hapus', { id }); await loadState(); render(); break; }
        case 'tambah-profil': S.draft.profiles.push({ id: 'p' + Math.random().toString(36).slice(2, 6), label: 'Profil ' + (S.draft.profiles.length + 1), provider: 'anthropic', model: '', baseUrl: '', key: '', ada: false, akhir: '' }); vPengaturan(); break;
        case 'hapus-profil': { if (!confirm('Hapus profil ini? Peran yang memakainya dikosongkan.')) break; S.draft.profiles.splice(+b.dataset.i, 1); vPengaturan(); break; }
        case 'simpan-set': { busy(b, true); const ok = await saveSettings(); busy(b, false); if (ok) { toast('Pengaturan tersimpan.'); vPengaturan(); } break; }
        case 'tes-profil': {
          const i = +b.dataset.i, pid = S.draft.profiles[i].id; const m = $('#tp' + i); busy(b, true); m.textContent = 'Menyimpan…';
          if (!(await saveSettings())) { busy(b, false); m.textContent = ''; break; }
          m.textContent = 'Menguji…'; const j = await api('/pengaturan/tes-profil', { id: pid }); busy(b, false);
          vPengaturan(); const m2 = $('#tp' + i); if (m2) { m2.textContent = j.ok ? `Berhasil (${j.ms} ms)` : (j.error || 'Gagal'); m2.dataset.level = j.ok ? 'ok' : 'bad'; } break;
        }
        case 'tes-github': {
          busy(b, true); if (!(await saveSettings())) { busy(b, false); break; }
          const j = await api('/pengaturan/tes-github', {}); busy(b, false); vPengaturan(); const m = $('#tgMsg');
          if (m) { m.textContent = j.ok ? `${j.repo}${j.privat ? ' (privat)' : ' (publik)'}: ${j.catatan}` : (j.error || 'Gagal'); m.dataset.level = j.ok && j.push ? 'ok' : 'bad'; } break;
        }
        case 'hapus-token': { if (!confirm('Hapus token GitHub dari server?')) break; await api('/pengaturan', { github: { hapusToken: true } }); await loadState(); S.draft = newDraft(); vPengaturan(); break; }
      }
    } catch (err) { toast(err.message); busy(b, false); }
  });
  document.addEventListener('change', async e => {
    if (e.target.id === 'impFile' && e.target.files[0]) {
      const m = $('#impMsg'); try { const txt = await e.target.files[0].text(); const j = await api('/tim/impor', JSON.parse(txt)); m.textContent = j.error ? j.error : `Diimpor: ${j.agent} persona${j.konteks ? ' + konteks bersama' : ''}.`; m.dataset.level = j.error ? 'bad' : 'ok'; if (!j.error) { await loadState(); render(); } } catch (err) { m.textContent = 'Berkas tidak valid: ' + err.message; m.dataset.level = 'bad'; }
    }
    if (e.target.id === 'dFile' && e.target.files[0]) { const f = e.target.files[0]; $('#dTeks').value = await f.text(); if (!$('#dNama').value) $('#dNama').value = f.name.replace(/\.[^.]+$/, ''); }
  });

  render().then(() => api('/runs').then(j => { const nav = $('#navTugas'); if (nav) { nav.textContent = j.aktif ? 'berjalan' : ''; nav.dataset.level = 'warn'; } }));
})();
