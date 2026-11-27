// Mesin kerja agent nyata: Manager menyusun rencana -> tim mengerjakan (dengan alat baca langsung) ->
// Manager mereview (revisi bila perlu) -> laporan akhir. Berjalan di server, tetap jalan walau browser ditutup.
// Perubahan repo hanya lewat PR yang diminta pemilik (createPr); runner sendiri tidak pernah menulis ke repo.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { SHARED, TOOLS, roster, toolHelp } = require('./agents');

function create({ settings, tools, ai, dataDir }) {
  const RUNS = path.join(dataDir, 'wb-runs');
  const DOCS = path.join(dataDir, 'wb-docs');
  fs.mkdirSync(RUNS, { recursive: true }); fs.mkdirSync(DOCS, { recursive: true });
  const runs = new Map();       // id -> run (memori)
  let activeId = '';            // satu run aktif pada satu waktu
  const now = () => Date.now();

  // ---------- penyimpanan ----------
  const runFile = id => path.join(RUNS, id + '.json');
  function persist(run) {
    try { fs.writeFileSync(runFile(run.id) + '.tmp', JSON.stringify(run), { mode: 0o600 }); fs.renameSync(runFile(run.id) + '.tmp', runFile(run.id)); } catch (e) { console.error('simpan run:', e.message); }
  }
  function log(run, msg) { run.log.push({ t: now(), msg: String(msg).slice(0, 300) }); if (run.log.length > 300) run.log.shift(); persist(run); }
  function load() {
    for (const f of fs.readdirSync(RUNS)) {
      if (!/^[a-z0-9]{6,20}\.json$/.test(f)) continue;
      try {
        const r = JSON.parse(fs.readFileSync(path.join(RUNS, f), 'utf8'));
        if (['planning', 'running', 'reporting'].includes(r.status)) { r.status = 'interrupted'; r.log.push({ t: now(), msg: 'Server dimulai ulang saat berjalan. Tekan Lanjutkan.' }); }
        runs.set(r.id, r);
      } catch {}
    }
  }
  load();

  // ---------- dokumen referensi ----------
  const docIdOk = id => typeof id === 'string' && /^[a-z0-9-]{3,40}$/.test(id);
  function docs() {
    const out = [];
    for (const f of fs.readdirSync(DOCS)) { try { out.push(JSON.parse(fs.readFileSync(path.join(DOCS, f), 'utf8'))); } catch {} }
    return out.sort((a, b) => a.nama.localeCompare(b.nama));
  }
  function saveDoc({ id, nama, tags, teks }) {
    nama = String(nama || '').trim().slice(0, 80);
    if (!nama) throw new Error('Nama dokumen kosong.');
    id = docIdOk(id) ? id : nama.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || crypto.randomBytes(4).toString('hex');
    teks = String(teks || '');
    if (teks.length > 400000) throw new Error('Dokumen terlalu besar (maks 400 ribu karakter).');
    const d = { id, nama, tags: (Array.isArray(tags) ? tags : ['semua']).map(String).filter(t => /^[a-z0-9-]{2,24}$/.test(t)).slice(0, 14), teks, ukuran: teks.length, diubah: now() };
    if (!d.tags.length) d.tags = ['semua'];
    fs.writeFileSync(path.join(DOCS, id + '.json'), JSON.stringify(d), { mode: 0o600 });
    return d;
  }
  function delDoc(id) { if (!docIdOk(id)) throw new Error('ID tidak valid.'); try { fs.unlinkSync(path.join(DOCS, id + '.json')); } catch {} }
  function docsFor(agentId) {
    let used = 0; const parts = [];
    for (const d of docs()) {
      if (!(d.tags.includes('semua') || d.tags.includes(agentId))) continue;
      if (used + d.teks.length > 90000) { parts.push(`### ${d.nama}\n(dilewati: melebihi batas konteks; minta dengan repo_read bila ada di repo)`); continue; }
      used += d.teks.length; parts.push(`### ${d.nama}\n${d.teks}`);
    }
    return parts.length ? '\n\n## Dokumen referensi\n' + parts.join('\n\n') : '';
  }

  // ---------- util ----------
  const cap = (s, n) => { s = String(s || ''); return s.length > n ? s.slice(0, n) + `\n…(dipotong, ${s.length - n} karakter lagi)` : s; };
  function extractJson(text) {
    let t = String(text || '').replace(/```(?:json)?/gi, '');
    const a = t.indexOf('{');
    if (a < 0) return null;
    for (let b = t.lastIndexOf('}'); b > a; b = t.lastIndexOf('}', b - 1)) { try { return JSON.parse(t.slice(a, b + 1)); } catch {} }
    return null;
  }
  // Tag resmi <alat>; model kadang menulis <antml nama=…> atau <tool nama=…>, itu diterima juga supaya alat benar-benar dijalankan (bukan dikarang).
  const parseTool = t => { const m = String(t).match(/<(alat|antml|tool)\s+nama="(\w+)">([\s\S]*?)<\/\1>/); return m ? { nama: m[2], arg: m[3].trim(), akhir: m.index + m[0].length } : null; };
  // Tambalan: <tambal jalur="x"><cari>..</cari><ganti>..</ganti>[...]</tambal>  -> { path, ops:[{cari,ganti}] }
  function parseEdits(t) {
    const out = []; const re = /<tambal\s+jalur="([^"]+)">([\s\S]*?)<\/tambal>/g; let m;
    const trim1 = s => s.replace(/^\r?\n/, '').replace(/\r?\n$/, '');
    while ((m = re.exec(String(t)))) {
      const ops = []; const pr = /<cari>([\s\S]*?)<\/cari>\s*<ganti>([\s\S]*?)<\/ganti>/g; let p;
      while ((p = pr.exec(m[2]))) ops.push({ cari: trim1(p[1]), ganti: trim1(p[2]) });
      out.push({ path: m[1].trim(), ops });
    }
    return out;
  }
  function parseFiles(t) {
    const out = []; const re = /<berkas\s+jalur="([^"]+)">\n?([\s\S]*?)\n?<\/berkas>/g; let m;
    while ((m = re.exec(String(t)))) out.push({ path: m[1].trim(), content: m[2] });
    return out;
  }
  const stripFiles = t => String(t).replace(/<berkas\s+jalur="([^"]+)">[\s\S]*?<\/berkas>/g, (_, p) => `[berkas: ${p}]`).replace(/<tambal\s+jalur="([^"]+)">[\s\S]*?<\/tambal>/g, (_, p) => `[tambal: ${p}]`).replace(/<(alat|antml|tool)[\s\S]*?<\/\1>/g, '').trim();
  function fmtRows(r) {
    if (!r.rows.length) return '(0 baris)';
    const cols = r.columns;
    const cell = v => v == null ? 'NULL' : typeof v === 'object' ? JSON.stringify(v) : String(v).replace(/\s+/g, ' ').slice(0, 200);
    return cols.join('\t') + '\n' + r.rows.map(row => cols.map(c => cell(row[c])).join('\t')).join('\n') + (r.truncated ? `\n…(dibatasi ${r.rows.length} baris)` : `\n(${r.rows.length} baris)`);
  }
  const checkCancel = run => { if (run.cancel) throw Object.assign(new Error('Dibatalkan oleh pemilik.'), { batal: true }); };

  async function callAI(run, profile, system, messages, label) {
    checkCancel(run);
    const lim = settings.get().limits;
    if (run.calls >= lim.panggilanPerTugas) throw new Error(`Batas ${lim.panggilanPerTugas} panggilan AI per run tercapai. Naikkan di Pengaturan bila perlu.`);
    run.calls++;
    const r = await ai.chat(profile, { system, messages, maxTokens: lim.maksToken });
    run.token.masuk += r.usage.in; run.token.keluar += r.usage.out;
    run.byProfile[profile.id] = (run.byProfile[profile.id] || 0) + 1;
    if (!r.text.trim()) throw new Error('AI mengembalikan jawaban kosong (' + label + ').');
    return r.text;
  }

  async function execTool(run, agent, name, arg, taskId) {
    checkCancel(run);
    if (!agent.alat.includes(name)) return `Alat "${name}" tidak tersedia untukmu. Yang ada: ${agent.alat.join(', ')}.`;
    const t0 = now();
    let out;
    try {
      switch (name) {
        case 'db_query': out = fmtRows(await tools.dbQuery(arg)); break;
        case 'db_schema': { const r = await tools.dbSchema(arg); out = r.jumlah ? Object.entries(r.tabel).map(([t, v]) => `# game.${t}\n` + v.kolom.map(c => `  ${c.nama} ${c.tipe}${c.null ? '' : ' not null'}${c.bawaan ? ' default ' + c.bawaan : ''}`).join('\n') + (v.indeks.length ? '\n  indeks:\n' + v.indeks.map(i => '   ' + i).join('\n') : '')).join('\n\n') : `Tidak ada tabel di schema game yang cocok dengan: ${r.cari.join(', ')}`; break; }
        case 'db_functions': { const r = await tools.dbFunctions(arg); out = r.fungsi.length ? r.fungsi.map(f => `${f.skema}.${f.nama}(${f.argumen}) -> ${f.hasil}`).join('\n') : 'Tidak ada fungsi yang cocok.'; break; }
        case 'repo_tree': { const r = await tools.repoTree(arg); out = r.item.map(i => (i.tipe === 'dir' ? i.jalur + '/' : `${i.jalur}  (${i.ukuran} B)`)).join('\n') + (r.terpotong ? '\n…(dipotong)' : '') || '(kosong)'; break; }
        case 'repo_read': { let p = arg, rg = ''; const m = arg.match(/^(.*):(\d*-\d*)$/); if (m) { p = m[1]; rg = m[2]; } const r = await tools.repoRead(p.trim(), rg); out = `${r.jalur} (baris ${r.dari}-${r.sampai} dari ${r.baris})${r.potong ? ' [dipotong, pakai rentang baris]' : ''}\n${r.teks}`; break; }
        case 'repo_grep': { const [pola, pre] = arg.split('|'); const r = await tools.repoGrep(pola, (pre || '').trim()); out = r.jumlah ? r.hasil.join('\n') + (r.terpotong ? '\n…(dipotong)' : '') : 'Tidak ada kecocokan.'; break; }
        case 'ops_status': out = await tools.opsTool('server_status'); break;
        case 'ops_logs': { const [service, lines, filter] = arg.split('|'); out = await tools.opsTool('logs_tail', { service: (service || '').trim(), lines: Math.min(300, +lines || 100), ...(filter ? { filter: filter.trim() } : {}) }); break; }
        case 'image': {
          if (run.images.length >= 4) return 'Batas 4 gambar per run tercapai.';
          const prof = settings.forRole('gambar');
          const im = await ai.image(prof, arg);
          const n = run.images.length + 1, ext = /jpe?g/.test(im.mime) ? 'jpg' : /webp/.test(im.mime) ? 'webp' : 'png';
          fs.mkdirSync(path.join(RUNS, run.id), { recursive: true });
          fs.writeFileSync(path.join(RUNS, run.id, `img-${n}.${ext}`), Buffer.from(im.b64, 'base64'));
          run.images.push({ n, ext, mime: im.mime, prompt: arg.slice(0, 400), task: taskId || '' });
          out = `Gambar #${n} dibuat dari deskripsi itu. Sebut sebagai "gambar #${n}" di laporanmu.`; break;
        }
        default: return `Alat tidak dikenal: ${name}`;
      }
    } catch (e) { out = 'GAGAL: ' + ai.scrub(e.message); }
    run.toolLog.push({ t: now(), task: taskId || 'rencana', agent: agent.id, alat: name, arg: cap(arg, 160), ms: now() - t0, galat: /^GAGAL/.test(out) });
    if (run.toolLog.length > 400) run.toolLog.shift();
    return cap(out, name === 'repo_read' ? 30000 : 12000);
  }

  // Satu agent bekerja: bisa memanggil alat berulang (maks langkahAlat), lalu menyerahkan jawaban akhir.
  async function agentLoop(run, agent, userMsg, taskId) {
    const profile = agent.profil && settings.profile(agent.profil) || settings.forRole(agent.peran);
    if (!profile) throw new Error(`Agent ${agent.nama}: belum ada profil AI untuk peran "${agent.peran}". Atur di Pengaturan.`);
    const system = [SHARED, `\n## Alat yang boleh kamu pakai\n${toolHelp(agent.alat)}`, `\n## Perananmu\n${agent.persona}${agent.personaTambahan ? '\n\n' + agent.personaTambahan : ''}`, docsFor(agent.id)].join('\n');
    const messages = [{ role: 'user', content: userMsg }];
    const maxStep = settings.get().limits.langkahAlat;
    let used = 0, last = '';
    for (;;) {
      const text = await callAI(run, profile, system, messages, agent.nama);
      last = text;
      const tl = parseTool(text);
      if (!tl) return text;
      if (used >= maxStep) { messages.push({ role: 'assistant', content: text }, { role: 'user', content: `Batas ${maxStep} pemakaian alat tercapai. Tulis jawaban akhir sekarang dari data yang sudah ada, tanpa tag alat. Sebutkan apa yang belum sempat diperiksa.` }); const fin = await callAI(run, profile, system, messages, agent.nama); return fin.replace(/<(alat|antml|tool)[\s\S]*?<\/\1>/g, ''); }
      used++;
      const res = await execTool(run, agent, tl.nama, tl.arg, taskId);
      messages.push({ role: 'assistant', content: text.slice(0, tl.akhir) }, { role: 'user', content: `<hasil alat="${tl.nama}">\n${res}\n</hasil>\nLanjutkan.` });
    }
  }

  // ---------- tahapan ----------
  const agentById = (r, id) => r.find(a => a.id === id);
  function teamText(team) { return team.map(a => `- id=${a.id} | ${a.nama} | peran model: ${a.peran} | ${a.ringkas} | alat: ${a.alat.join(', ')}`).join('\n'); }

  async function stagePlan(run, team) {
    const mgr = agentById(team, 'manager');
    run.status = 'planning'; log(run, 'Manager menyusun rencana…');
    const dl = docs().map(d => `- ${d.nama} (untuk: ${d.tags.join(', ')})`).join('\n') || '(belum ada)';
    const qa = run.klarifikasi.map(k => `Pertanyaan Manager: ${k.q}\nJawaban pemilik: ${k.a}`).join('\n');
    const msg = `PERMINTAAN PEMILIK:\n${run.prompt}\n${qa ? '\n' + qa + '\n' : ''}\nTIM YANG TERSEDIA:\n${teamText(team.filter(a => a.aktif && a.id !== 'manager'))}\n\nDOKUMEN REFERENSI TERSIMPAN:\n${dl}\n\nTugasmu: susun rencana kerja. Boleh memakai alat baca dulu untuk memahami keadaan nyata sebelum merencanakan. Setelah itu balas HANYA JSON (tanpa teks lain):\n{"ringkasan":"1-3 kalimat apa yang akan dicapai","pertanyaan":null,"tugas":[{"id":"t1","agent":"id agent","judul":"judul singkat","instruksi":"instruksi lengkap dan mandiri: apa yang diperiksa/dibuat, berkas/tabel yang relevan, bentuk hasil yang diharapkan","butuh":[]}],"risiko":"risiko atau hal yang perlu diputuskan pemilik"}\nAturan: maksimal 8 tugas; hanya id agent dari daftar; "butuh" berisi id tugas yang hasilnya harus ada dulu; tugas pemeriksaan/analisis mendahului tugas penulisan; "pertanyaan" hanya diisi bila jawabannya mengubah rencana (satu pertanyaan pendek, dengan rekomendasi) dan jangan membuat tugas bila bertanya; jangan membuat tugas yang tidak diminta.`;
    let out = await agentLoop(run, mgr, msg, 'rencana');
    let j = extractJson(out);
    if (!j) { run.calls < settings.get().limits.panggilanPerTugas && (out = await agentLoop(run, { ...mgr, alat: [] }, `Balasanmu sebelumnya bukan JSON valid. Ulangi HANYA sebagai JSON sesuai format.\n\nBalasan sebelumnya:\n${cap(out, 6000)}`, 'rencana')); j = extractJson(out); }
    if (!j) throw new Error('Manager tidak menghasilkan rencana yang bisa dibaca. Coba lagi atau perjelas permintaan.');
    if (j.pertanyaan && String(j.pertanyaan).trim() && !(Array.isArray(j.tugas) && j.tugas.length)) {
      run.pertanyaan = String(j.pertanyaan).slice(0, 600); run.status = 'awaiting_answer'; log(run, 'Manager bertanya ke pemilik.'); return;
    }
    const ids = new Set(); const tugas = [];
    for (const t of (j.tugas || []).slice(0, 8)) {
      const a = agentById(team, String(t.agent)); if (!a || !a.aktif || a.id === 'manager') continue;
      const id = /^[a-z0-9]{1,6}$/i.test(t.id) && !ids.has(t.id) ? t.id : 't' + (tugas.length + 1);
      ids.add(id); tugas.push({ id, agent: a.id, judul: String(t.judul || 'Tugas').slice(0, 90), instruksi: String(t.instruksi || '').slice(0, 4000), butuh: (Array.isArray(t.butuh) ? t.butuh : []).map(String) });
    }
    if (!tugas.length) throw new Error('Rencana Manager tidak berisi tugas untuk agent yang aktif.');
    for (const t of tugas) t.butuh = t.butuh.filter(b => b !== t.id && ids.has(b) && tugas.findIndex(x => x.id === b) < tugas.findIndex(x => x.id === t.id));
    run.plan = { ringkasan: String(j.ringkasan || '').slice(0, 800), risiko: String(j.risiko || '').slice(0, 800), tugas };
    run.pertanyaan = '';
    for (const t of tugas) run.tasks[t.id] = run.tasks[t.id] || { status: 'menunggu', revisi: 0, output: '', files: [], review: null, ringkasToolLog: [] };
    run.status = 'awaiting_approval';
    log(run, `Rencana siap: ${tugas.length} tugas.`);
  }

  async function stageTask(run, team, t) {
    const agent = agentById(team, t.agent), st = run.tasks[t.id], mgr = agentById(team, 'manager');
    const lim = settings.get().limits;
    for (;;) {
      st.status = 'dikerjakan'; log(run, `${agent.nama} mengerjakan ${t.id}: ${t.judul}${st.revisi ? ` (revisi ${st.revisi})` : ''}`);
      const dep = t.butuh.map(id => { const d = run.tasks[id], p = run.plan.tugas.find(x => x.id === id); return `### Hasil ${id} (${p.judul}, oleh ${agentById(team, p.agent).nama})\n${cap(d.output, 6000)}${d.files.length ? '\nBerkas yang dibuat: ' + d.files.map(f => f.path).join(', ') : ''}`; }).join('\n\n');
      const msg = `TUGAS ${t.id}: ${t.judul}\n\nPERMINTAAN ASLI PEMILIK (konteks):\n${cap(run.prompt, 3000)}\n\nINSTRUKSI MANAGER:\n${t.instruksi}\n${dep ? '\nHASIL TUGAS YANG KAMU BUTUHKAN:\n' + dep + '\n' : ''}${st.review && st.review.putusan === 'revisi' ? `\nCATATAN REVISI DARI MANAGER (perbaiki ini):\n${st.review.catatan}\n\nHASIL SEBELUMNYA:\n${cap(st.output, 6000)}\n` : ''}\nKerjakan sekarang. Periksa data nyata dengan alat sebelum menyimpulkan; jangan menebak. Akhiri dengan ringkasan hasil dan hal yang belum pasti.`;
      const text = await agentLoop(run, agent, msg, t.id);
      st.output = stripFiles(text);
      // Kumpulkan berkas baru (<berkas>) dan tambalan (<tambal>); periksa tiap berkas sendiri-sendiri terhadap repo.
      const cand = new Map();
      for (const f of parseFiles(text)) cand.set(tools.safePath(f.path), { path: f.path, content: f.content });
      for (const e of parseEdits(text)) { const k = tools.safePath(e.path); const cur = cand.get(k); cand.set(k, { path: e.path, ops: [...((cur && cur.ops) || []), ...e.ops] }); }
      const files = [], bad = [];
      for (const f of cand.values()) {
        try {
          const [rep] = await tools.inspect([f]);
          if (rep.masalah.length) bad.push(rep.masalah.join(' '));
          else files.push({ path: rep.path, content: rep.content, ...(rep.ops ? { ops: rep.ops } : {}), baru: rep.baru, plus: rep.plus, minus: rep.minus });
        } catch (e) { bad.push(e.message); }
      }
      st.files = files; if (bad.length) st.output += `\n\n[Peringatan sistem: berkas ditolak pemeriksaan otomatis: ${bad.join(' | ')}]`;
      if (bad.length && st.revisi < lim.revisi) {
        st.review = { putusan: 'revisi', catatan: `Pemeriksaan otomatis menolak berkas: ${bad.join(' | ')}`.slice(0, 1200) };
        st.revisi++; log(run, `${t.id}: berkas ditolak pemeriksaan otomatis, diminta revisi.`); continue;
      }
      st.ringkasToolLog = run.toolLog.filter(x => x.task === t.id).map(x => `${x.alat}${x.galat ? ' (gagal)' : ''}`);
      // Review Manager
      st.status = 'direview'; log(run, `Manager mereview ${t.id}…`);
      const rv = await agentLoop(run, { ...mgr, alat: [] }, `REVIEW HASIL TUGAS ${t.id}: ${t.judul} (oleh ${agent.nama})\n\nPERMINTAAN PEMILIK:\n${cap(run.prompt, 2000)}\n\nINSTRUKSI YANG DIBERIKAN:\n${t.instruksi}\n\nALAT YANG DIPAKAI AGENT: ${st.ringkasToolLog.join(', ') || '(tidak ada)'}\n\nHASIL:\n${cap(st.output, 12000)}\n${st.files.length ? '\nBERKAS DISERAHKAN (sudah lolos pemeriksaan otomatis: sintaks, tidak terpotong, tambalan cocok dengan repo):\n' + st.files.map(f => `--- ${f.path} (${f.baru ? 'BARU' : 'UBAH'}, +${f.plus} −${f.minus} baris)\n${cap(f.ops ? f.ops.map(o => `- ${cap(o.cari, 600)}\n+ ${cap(o.ganti, 1200)}`).join('\n…\n') : f.content, 3500)}`).join('\n') : ''}\n\nNilai dengan kritis. Putusan "revisi" bila: perubahan lebih besar dari yang diminta (bandingkan +/− baris dengan instruksi), alat yang dibutuhkan tidak dijalankan sehingga isi berkas hanya dugaan, hasil menebak tanpa data dari alat padahal data tersedia, nama tabel/kolom/fungsi tidak diperiksa, berkas tidak sesuai instruksi, ada kontradiksi, atau ada rahasia di berkas. Balas HANYA JSON: {"putusan":"ok" atau "revisi","catatan":"alasan singkat dan perbaikan yang diminta"}`, t.id);
      const rj = extractJson(rv) || { putusan: 'ok', catatan: 'Review tidak terbaca; diterima apa adanya.' };
      st.review = { putusan: rj.putusan === 'revisi' ? 'revisi' : 'ok', catatan: String(rj.catatan || '').slice(0, 1200) };
      if (st.review.putusan === 'ok') { st.status = 'selesai'; log(run, `${t.id} diterima.`); return; }
      if (st.revisi >= lim.revisi) { st.status = 'selesai'; st.diterimaDenganCatatan = true; st.files.forEach(f => { f.belumLolos = true; }); log(run, `${t.id} diterima dengan catatan (batas revisi).`); return; }
      st.revisi++;
    }
  }

  async function stageReport(run, team) {
    const mgr = agentById(team, 'manager');
    run.status = 'reporting'; log(run, 'Manager menulis laporan akhir…');
    const body = run.plan.tugas.map(t => { const s = run.tasks[t.id]; return `### ${t.id} ${t.judul} (${agentById(team, t.agent).nama}) — ${s.status}${s.diterimaDenganCatatan ? ' [diterima dengan catatan]' : ''}\nReview: ${s.review ? s.review.putusan + ' — ' + s.review.catatan : '-'}\n${cap(s.output, 5000)}${s.files.length ? '\nBerkas: ' + s.files.map(f => f.path).join(', ') : ''}`; }).join('\n\n');
    const txt = await agentLoop(run, { ...mgr, alat: [] }, `PERMINTAAN PEMILIK:\n${cap(run.prompt, 3000)}\n\nRENCANA: ${run.plan.ringkasan}\n\nHASIL TIM:\n${body}\n\nTulis LAPORAN AKHIR untuk pemilik (non-IT), Markdown, ringkas: 1) Hasil utama dalam 3-5 kalimat, 2) Temuan penting (hanya yang didukung hasil di atas), 3) Berkas yang siap diajukan sebagai PR dan apa fungsinya, 4) Risiko / yang belum diperiksa, 5) Satu langkah berikutnya yang disarankan. Jangan menambah fakta di luar hasil tim. Setelah laporan, di baris terakhir tulis: JUDUL-PR: <judul PR singkat bila ada berkas, atau kosong>`, 'laporan');
    const m = txt.match(/JUDUL-PR:\s*(.*)\s*$/i);
    run.report = { teks: txt.replace(/JUDUL-PR:.*$/i, '').trim(), judulPr: m ? m[1].trim().slice(0, 120) : '' };
    run.status = 'done'; run.selesai = now(); log(run, 'Selesai.');
  }

  // ---------- pengendali ----------
  function currentTeam() { return roster(settings); }
  async function drive(run) {
    if (activeId && activeId !== run.id) throw new Error('Ada run lain yang sedang berjalan. Tunggu atau batalkan dulu.');
    activeId = run.id; run.cancel = false; run.error = '';
    (async () => {
      try {
        const team = currentTeam();
        if (!run.plan) { await stagePlan(run, team); persist(run); if (run.status === 'awaiting_answer') return; }
        if (run.status === 'awaiting_approval' && !run.auto) return;
        run.status = 'running'; persist(run);
        for (const t of run.plan.tugas) {
          const st = run.tasks[t.id];
          if (st.status === 'selesai') continue;
          if (t.butuh.some(b => run.tasks[b].status !== 'selesai')) { st.status = 'dilewati'; continue; }
          await stageTask(run, team, t); persist(run);
        }
        await stageReport(run, team);
      } catch (e) {
        if (e.batal) { run.status = 'cancelled'; log(run, 'Dibatalkan.'); }
        else { run.status = 'failed'; run.error = ai.scrub(e.message); log(run, 'Gagal: ' + run.error); }
      } finally { if (activeId === run.id) activeId = ''; persist(run); }
    })();
  }

  return {
    docs, saveDoc, delDoc,
    list: () => [...runs.values()].sort((a, b) => b.dibuat - a.dibuat).map(r => ({ id: r.id, dibuat: r.dibuat, status: r.status, prompt: cap(r.prompt, 140), tugas: r.plan ? r.plan.tugas.length : 0, selesai: r.plan ? r.plan.tugas.filter(t => (r.tasks[t.id] || {}).status === 'selesai').length : 0, calls: r.calls })),
    get: id => runs.get(id) || null,
    activeId: () => activeId,
    async start(prompt, { auto } = {}) {
      prompt = String(prompt || '').trim();
      if (prompt.length < 10) throw new Error('Tulis permintaan yang lebih jelas (minimal 10 karakter).');
      if (prompt.length > 12000) throw new Error('Permintaan terlalu panjang (maks 12 ribu karakter).');
      if (activeId) throw new Error('Ada run lain yang sedang berjalan.');
      if (!settings.forRole('orkestrator')) throw new Error('Peran Orkestrator belum dipetakan ke profil AI. Atur di Pengaturan.');
      const run = { id: crypto.randomBytes(6).toString('hex'), dibuat: now(), prompt, auto: auto === true || (auto == null && !settings.get().limits.jedaRencana), status: 'planning', klarifikasi: [], pertanyaan: '', plan: null, tasks: {}, report: null, calls: 0, token: { masuk: 0, keluar: 0 }, byProfile: {}, toolLog: [], images: [], log: [], error: '', cancel: false };
      runs.set(run.id, run); persist(run); log(run, 'Permintaan diterima.');
      await drive(run); return run;
    },
    async answer(id, text) { const r = runs.get(id); if (!r || r.status !== 'awaiting_answer') throw new Error('Run tidak menunggu jawaban.'); r.klarifikasi.push({ q: r.pertanyaan, a: String(text || '').slice(0, 3000) }); r.pertanyaan = ''; r.plan = null; await drive(r); return r; },
    async approve(id, { rencana } = {}) {
      const r = runs.get(id); if (!r || r.status !== 'awaiting_approval') throw new Error('Run tidak menunggu persetujuan.');
      if (rencana && Array.isArray(rencana.tugas)) { // pemilik boleh mengubah/menghapus tugas (bukan menambah agent baru)
        const keep = new Set(rencana.tugas.map(String));
        r.plan.tugas = r.plan.tugas.filter(t => keep.has(t.id));
        for (const t of r.plan.tugas) t.butuh = t.butuh.filter(b => keep.has(b));
        if (!r.plan.tugas.length) throw new Error('Minimal satu tugas harus tersisa.');
      }
      r.auto = true; r.status = 'running'; await drive(r); return r;
    },
    async resume(id) { const r = runs.get(id); if (!r || !['interrupted', 'failed'].includes(r.status)) throw new Error('Run tidak bisa dilanjutkan.'); r.status = r.plan ? 'running' : 'planning'; await drive(r); return r; },
    cancel(id) { const r = runs.get(id); if (!r) throw new Error('Run tidak ada.'); r.cancel = true; if (!['planning', 'running', 'reporting'].includes(r.status)) { r.status = 'cancelled'; if (activeId === r.id) activeId = ''; persist(r); } return r; },
    imagePath(id, n) { const r = runs.get(id); const im = r && r.images.find(x => x.n === n); return im ? path.join(RUNS, id, `img-${n}.${im.ext}`) : null; },
    // File final = berkas terakhir per jalur dari tugas yang selesai.
    deliverables(id) {
      const r = runs.get(id); if (!r || !r.plan) return [];
      const m = new Map();
      for (const t of r.plan.tugas) { const s = r.tasks[t.id]; if (s && s.status === 'selesai') for (const f of s.files) m.set(f.path, { path: f.path, content: f.content, ops: f.ops || null, baru: !!f.baru, plus: f.plus || 0, minus: f.minus || 0, belumLolos: !!f.belumLolos, tugas: t.id, agent: t.agent }); }
      return [...m.values()];
    },
    notePr(id, pr) { const r = runs.get(id); if (r) { r.pr = pr; persist(r); } },
    remove(id) { const r = runs.get(id); if (!r) return; if (activeId === id) throw new Error('Run masih berjalan.'); runs.delete(id); try { fs.unlinkSync(runFile(id)); fs.rmSync(path.join(RUNS, id), { recursive: true, force: true }); } catch {} },
    importAgents(json) {
      const d = typeof json === 'string' ? JSON.parse(json) : json;
      if (!d || !Array.isArray(d.agents)) throw new Error('Format tidak dikenal: butuh {"shared":"...","agents":[{name,persona}]}.');
      const map = { manager: 'manager', design: 'design', frontend: 'frontend', backend: 'backend', 'lore & story': 'lore', 'quest designer': 'quest', 'systems & ekonomi': 'ekonomi', 'qa & audit': 'qa', devops: 'devops', 'live-ops': 'liveops', dokumentasi: 'docs' };
      const ov = {}; let n = 0;
      for (const a of d.agents) { const id = map[String(a.name || '').toLowerCase()]; if (id && a.persona) { ov[id] = { persona: String(a.persona).slice(0, 20000) }; n++; } }
      settings.ubah({ agents: ov });
      if (d.shared) saveDoc({ id: 'konteks-bersama-impor', nama: 'Konteks bersama (impor)', tags: ['semua'], teks: String(d.shared) });
      return { agent: n, konteks: !!d.shared };
    },
  };
}

module.exports = { create };
