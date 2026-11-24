// Penjaga: pemindai anomali perilaku kapten.
// Lapis 1 = aturan tetap di server (cepat, gratis, selalu jalan).
// Lapis 2 = Google Gemini menilai ringkasan angka yang sudah dihitung lapis 1 (bukan log mentah),
//           nama kapten disamarkan jadi kode (K01…) bila pengaturan "samarkan" aktif.
// Hanya membaca database (role baca-saja). Tidak pernah mengubah data game.
'use strict';
const fs = require('fs');
const path = require('path');
const ALIRAN = require('./aliran');
const AUD = require('./audit').Q;

const GEMINI_BASE = (process.env.OPS_GEMINI_API || 'https://generativelanguage.googleapis.com').replace(/\/$/, ''); // hanya diganti untuk uji lokal
const NAMA = `coalesce(nullif(p.character_name, ''), p.username)`;
const W = `l.ts > now() - ($1::int * interval '1 hour')`;

const Q = {
  pemain: `
select ${NAMA} as kapten, p.username, round((extract(epoch from now() - p.created_at) / 86400)::numeric, 1)::float8 as umur_hari,
  p.gold::float8 as gold, p.bank_balance::float8 as bank, p.debt_balance::float8 as utang,
  round((extract(epoch from now() - p.last_active) / 3600)::numeric, 1)::float8 as jam_sejak_aktif
from game.players p where p.archetype <> ''`,

  // Pola aktivitas per kapten di jendela waktu.
  aktivitas: `
with l as (select l.player_id, l.ts, l.message as m from game.player_log l where ${W}),
per as (select player_id, count(*)::int as aksi, count(distinct date_trunc('hour', ts))::int as jam_aktif,
  (count(*) filter (where m like 'Bought "%'))::int as beli_item, (count(*) filter (where m like 'Galian di %'))::int as galian,
  (count(*) filter (where m like 'Sold %x "%'))::int as jual_item, (count(*) filter (where m like 'Set sail%'))::int as layar
  from l group by 1),
menit as (select player_id, max(c)::int as maks_per_menit from (select player_id, count(*) as c from l group by player_id, date_trunc('minute', ts)) z group by 1),
gap as (select player_id, round((percentile_cont(0.5) within group (order by d))::numeric, 2)::float8 as jeda_median,
  (count(*) filter (where d < 1))::int as jeda_bawah_1 from
  (select player_id, extract(epoch from ts - lag(ts) over (partition by player_id order by ts)) as d from l) z where d is not null group by 1),
pola as (select distinct on (player_id) player_id, pola, c::int as pola_n from
  (select player_id, regexp_replace(regexp_replace(left(m, 90), '"[^"]*"', '"…"', 'g'), '[0-9][0-9.,]*', 'N', 'g') as pola, count(*) as c from l group by 1, 2) z
  order by player_id, c desc)
select ${NAMA} as kapten, p.username, per.aksi, per.jam_aktif, per.beli_item, per.galian, per.jual_item, per.layar,
  coalesce(menit.maks_per_menit, 0) as maks_per_menit, gap.jeda_median, coalesce(gap.jeda_bawah_1, 0) as jeda_bawah_1, pola.pola, pola.pola_n
from per join game.players p on p.player_id = per.player_id
left join menit on menit.player_id = per.player_id left join gap on gap.player_id = per.player_id left join pola on pola.player_id = per.player_id
where p.archetype <> ''`,

  transfer: `
with t as (select l.player_id, regexp_match(l.message, '^Mengirim ([0-9]+) gold ke (.+)\\.$') as r from game.player_log l
  where ${W} and l.message like 'Mengirim % gold ke %')
select ${NAMA} as pengirim, p.username as pengirim_u, coalesce(nullif(q.character_name, ''), t.r[2]) as penerima, q.username as penerima_u,
  sum(t.r[1]::float8)::float8 as total, count(*)::int as kali
from t join game.players p on p.player_id = t.player_id left join game.players q on q.character_name = t.r[2]
where t.r is not null group by 1, 2, 3, 4`,

  dadu: `
with d as (select l.player_id, l.message as m, regexp_match(l.message, 'duel dadu melawan (.+) \\(([+-])([0-9]+) gold') as r
  from game.player_log l where ${W} and l.message like '% duel dadu melawan %')
select ${NAMA} as kapten, p.username, d.r[1] as lawan, (count(*) filter (where d.r[2] = '+'))::int as menang,
  (count(*) filter (where d.r[2] = '-'))::int as kalah, sum(case when d.r[2] = '+' then d.r[3]::float8 else -d.r[3]::float8 end)::float8 as bersih
from d join game.players p on p.player_id = d.player_id where d.r is not null group by 1, 2, 3`,
};

const TINGKAT = s => (s >= 6 ? 'tinggi' : s >= 3 ? 'sedang' : 'rendah');
const jt = v => (Math.abs(v) >= 1e6 ? (v / 1e6).toFixed(1).replace('.', ',') + ' jt' : Math.round(v).toLocaleString('id-ID'));
const median = a => { const b = a.filter(x => x != null && Number.isFinite(+x)).map(Number).sort((x, y) => x - y); if (!b.length) return 0; const m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2; };

// Aturan. Setiap aturan menambah poin; poin total menentukan tingkat (≥6 tinggi, ≥3 sedang).
function nilai(ctx) {
  const { pemain, akt, aliran, transfer, dadu, bursa, kekayaan, jendela } = ctx;
  const byU = new Map();
  const get = (u, nama) => {
    if (!u) return null;
    if (!byU.has(u)) byU.set(u, { kapten: nama || u, username: u, skor: 0, tanda: [], angka: {} });
    return byU.get(u);
  };
  const tandai = (u, nama, kode, judul, bukti, poin) => { const f = get(u, nama); if (!f) return; f.tanda.push({ kode, judul, bukti, poin }); f.skor += poin; };
  const P = new Map(pemain.map(r => [r.username, r]));

  // Garis dasar server untuk pembanding.
  const deltaPos = [...kekayaan.values()].map(x => x.delta).filter(x => x > 0);
  const base = {
    pemain_aktif: akt.length,
    median_aksi: median(akt.map(r => r.aksi)),
    median_maks_per_menit: median(akt.map(r => r.maks_per_menit)),
    median_jeda_detik: median(akt.map(r => r.jeda_median)),
    median_kenaikan_kekayaan: median(deltaPos),
    median_masuk: median(aliran.map(r => r.masuk)),
  };

  for (const r of akt) {
    const f = get(r.username, r.kapten); Object.assign(f.angka, { aksi: r.aksi, jam_aktif: r.jam_aktif, maks_per_menit: r.maks_per_menit, jeda_median: r.jeda_median, beli_item: r.beli_item, galian: r.galian, jual_item: r.jual_item, pola: r.pola, pola_n: r.pola_n });
    if (r.maks_per_menit >= 150) tandai(r.username, r.kapten, 'ledakan', 'Ledakan aksi', `${r.maks_per_menit} aksi dalam satu menit (median server ${base.median_maks_per_menit})`, 6);
    else if (r.maks_per_menit >= 60) tandai(r.username, r.kapten, 'ledakan', 'Ledakan aksi', `${r.maks_per_menit} aksi dalam satu menit (median server ${base.median_maks_per_menit})`, 3);
    if (r.aksi >= 300 && r.jeda_median != null && r.jeda_median < 1.5 && r.jeda_bawah_1 >= r.aksi * 0.5)
      tandai(r.username, r.kapten, 'mesin', 'Ritme seperti mesin', `${r.aksi} aksi, jeda median ${r.jeda_median} dtk, ${r.jeda_bawah_1} jeda di bawah 1 dtk`, 4);
    if (r.pola_n >= 300 && r.pola_n >= r.aksi * 0.6)
      tandai(r.username, r.kapten, 'repetisi', 'Aksi yang sama berulang', `${r.pola_n} dari ${r.aksi} catatan berbunyi "${r.pola}"`, 3);
    const loop = r.beli_item + r.galian;
    if (loop >= 1000) tandai(r.username, r.kapten, 'loop', 'Loop peta dan galian', `${r.beli_item} beli item/peta, ${r.galian} galian, ${r.jual_item} jual artefak`, 6);
    else if (loop >= 100) tandai(r.username, r.kapten, 'loop', 'Loop peta dan galian', `${r.beli_item} beli item/peta, ${r.galian} galian, ${r.jual_item} jual artefak`, 3);
    if (jendela >= 20 && r.jam_aktif >= Math.ceil(jendela * 0.85)) tandai(r.username, r.kapten, 'nonstop', 'Aktif hampir tanpa jeda', `aktif di ${Math.min(r.jam_aktif, jendela)} dari ${jendela} jam`, 2);
  }

  for (const r of aliran) {
    const f = get(r.username, r.kapten);
    Object.assign(f.angka, { masuk: r.masuk, keluar: r.keluar, bersih: r.bersih, dari_dagang: r.dari_dagang, dari_harta: r.dari_harta, dari_kapten: r.dari_kapten, sumber_utama: r.sumber_utama });
    if (r.dari_harta >= 1e6 && (r.harta_pct || 0) >= 50)
      tandai(r.username, r.kapten, 'sumber', 'Gold dari galian dan artefak', `${jt(r.dari_harta)} (${r.harta_pct}% dari gold masuk), dagang hanya ${jt(r.dari_dagang)}`, 3);
  }

  for (const [u, k] of kekayaan) {
    const f = byU.get(u) || (k.delta >= 5e6 ? get(u, k.kapten) : null); if (!f) continue;
    Object.assign(f.angka, { kekayaan_kini: k.kini, kenaikan_kekayaan: k.delta });
    const batas = Math.max(5e6, 5 * (base.median_kenaikan_kekayaan || 0));
    if (k.delta >= batas) tandai(u, k.kapten, 'lonjakan', 'Kekayaan melonjak', `naik ${jt(k.delta)} dalam ${k.jam} jam (median kenaikan server ${jt(base.median_kenaikan_kekayaan)})`, 3);
  }

  // Transfer: penerima besar, banyak pengirim, saling kirim, akun baru.
  const terima = new Map();
  for (const t of transfer) {
    if (!t.penerima_u) continue;
    const e = terima.get(t.penerima_u) || { kapten: t.penerima, total: 0, dari: new Set() };
    e.total += t.total; e.dari.add(t.pengirim); terima.set(t.penerima_u, e);
  }
  for (const [u, e] of terima) {
    const umur = P.get(u) ? P.get(u).umur_hari : null;
    if (e.total >= 3e6 || e.dari.size >= 4) tandai(u, e.kapten, 'transfer', 'Menerima banyak transfer', `${jt(e.total)} dari ${e.dari.size} kapten (${[...e.dari].slice(0, 4).join(', ')})`, 2);
    if (umur != null && umur < 3 && e.total >= 1e6) tandai(u, e.kapten, 'akunbaru', 'Akun baru menerima gold besar', `umur akun ${umur} hari, menerima ${jt(e.total)}`, 3);
  }
  const pair = new Map(transfer.filter(t => t.penerima_u).map(t => [t.pengirim_u + '>' + t.penerima_u, t]));
  for (const t of transfer) {
    const back = pair.get(t.penerima_u + '>' + t.pengirim_u);
    if (back && t.pengirim_u < t.penerima_u && Math.min(t.total, back.total) >= 5e5) {
      const bukti = `${t.pengirim} → ${t.penerima} ${jt(t.total)}, balik ${jt(back.total)}`;
      tandai(t.pengirim_u, t.pengirim, 'pingpong', 'Saling kirim gold', bukti, 2);
      tandai(t.penerima_u, t.penerima, 'pingpong', 'Saling kirim gold', bukti, 2);
    }
  }

  // Bursa: harga jauh dari harga dasar dengan nilai besar = gold bisa dipindah lewat Bursa.
  const byName = new Map(pemain.map(r => [r.kapten, r.username]));
  for (const b of bursa) {
    if (b.selisih_pct == null || b.total < 1e5 || Math.abs(b.selisih_pct) < 60) continue;
    const bukti = `${b.pembeli} beli ${b.jumlah} ${b.barang} dari ${b.penjual} seharga ${jt(b.total)} (${b.selisih_pct > 0 ? '+' : ''}${b.selisih_pct}% dari harga dasar)`;
    tandai(byName.get(b.pembeli), b.pembeli, 'bursa', 'Harga Bursa tidak wajar', bukti, 3);
    tandai(byName.get(b.penjual), b.penjual, 'bursa', 'Harga Bursa tidak wajar', bukti, 3);
  }

  // Duel dadu sepihak dengan lawan yang sama.
  for (const d of dadu) {
    const n = d.menang + d.kalah;
    if (n >= 15 && Math.max(d.menang, d.kalah) / n >= 0.8)
      tandai(d.username, d.kapten, 'dadu', 'Duel dadu sepihak', `${n} duel melawan ${d.lawan}: menang ${d.menang}, kalah ${d.kalah}, bersih ${jt(d.bersih)}`, 2);
  }

  // Gabungkan tanda dengan kode sama (ambil poin terbesar, bukti digabung).
  const temuan = [];
  for (const f of byU.values()) {
    if (!f.tanda.length) continue;
    const m = new Map();
    for (const t of f.tanda) {
      const e = m.get(t.kode);
      if (!e) m.set(t.kode, { ...t });
      else { e.poin = Math.max(e.poin, t.poin); if (!e.bukti.includes(t.bukti)) e.bukti += '; ' + t.bukti; }
    }
    f.tanda = [...m.values()].sort((a, b) => b.poin - a.poin);
    f.skor = f.tanda.reduce((a, t) => a + t.poin, 0);
    f.tingkat = TINGKAT(f.skor);
    temuan.push(f);
  }
  temuan.sort((a, b) => b.skor - a.skor);
  return { base, temuan };
}

// ---------- Gemini ----------
const AI_SYSTEM = `Kamu analis anti-curang untuk "Marantau", game dagang kapal berbasis browser (gaya Tradewinds) dengan ±35 pemain.
Ekonomi: kapten membeli barang murah di satu pulau dan menjualnya di pulau lain, menyelesaikan misi gubernur, memancing, Pesanan Harian, Balai Kongsi (investasi), Bursa (jual-beli antar kapten), transfer gold antar kapten, duel dadu, dan menggali harta memakai peta harta (peta dibeli, digali, kadang menghasilkan artefak yang bisa dijual).
Pemain manusia normal: puluhan sampai beberapa ratus aksi per hari, jarang lebih dari 30 aksi per menit, ada jeda tidur.
Tanda curang yang pernah terjadi: seorang kapten memakai skrip membeli 12.000+ peta harta dan menggali ribuan kali dengan jeda 0,1 detik untuk mencetak gold dan artefak.
Tugasmu: nilai setiap kapten di data (yang sudah diringkas server) dan beri tingkat risiko: tinggi, sedang, rendah, atau wajar. Jelaskan alasan dalam Bahasa Indonesia yang singkat dan konkret, berdasarkan angka yang ada. Jangan mengarang angka. Bedakan pemain rajin dari pola otomatis atau eksploit. Sarankan tindakan GM yang proporsional (pantau, cek jejak di Panel Ops, tanya pemain, bekukan, kembalikan gold), tanpa menghukum tanpa bukti.
Juga sebutkan pola baru yang belum tertangkap aturan, bila ada.`;

const AI_SCHEMA = {
  type: 'OBJECT',
  properties: {
    ringkasan: { type: 'STRING' },
    kapten: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          id: { type: 'STRING' }, tingkat: { type: 'STRING', enum: ['tinggi', 'sedang', 'rendah', 'wajar'] },
          judul: { type: 'STRING' }, alasan: { type: 'ARRAY', items: { type: 'STRING' } }, saran: { type: 'STRING' },
        },
        required: ['id', 'tingkat', 'judul', 'alasan', 'saran'],
      },
    },
    pola_baru: { type: 'ARRAY', items: { type: 'STRING' } },
  },
  required: ['ringkasan', 'kapten'],
};

async function gemini({ key, model, system, prompt, schema, timeoutMs = 90000 }) {
  const url = `${GEMINI_BASE}/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const body = {
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0.2, responseMimeType: 'application/json', ...(schema ? { responseSchema: schema } : {}) },
  };
  const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key }, body: JSON.stringify(body), signal: AbortSignal.timeout(timeoutMs) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Gemini ${r.status}: ${(j.error && j.error.message) || r.statusText}`.slice(0, 300));
  const c = j.candidates && j.candidates[0];
  const text = c && c.content && c.content.parts ? c.content.parts.map(p => p.text || '').join('') : '';
  if (!text) throw new Error('Gemini tidak memberi jawaban' + (c && c.finishReason ? ` (${c.finishReason})` : ''));
  let out; try { out = JSON.parse(text); } catch { throw new Error('Jawaban Gemini bukan JSON yang sah.'); }
  return { out, usage: j.usageMetadata || null };
}

async function geminiModels(key) {
  const r = await fetch(`${GEMINI_BASE}/v1beta/models?pageSize=200`, { headers: { 'x-goog-api-key': key }, signal: AbortSignal.timeout(20000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Gemini ${r.status}: ${(j.error && j.error.message) || r.statusText}`.slice(0, 300));
  return (j.models || []).filter(m => (m.supportedGenerationMethods || []).includes('generateContent'))
    .map(m => ({ id: m.name.replace(/^models\//, ''), nama: m.displayName || m.name }))
    .filter(m => /gemini/i.test(m.id) && !/(tts|image|embedding|live|audio|vision)/i.test(m.id));
}

// ---------- Mesin Penjaga ----------
function create({ dataDir, dashRows, settings, kekayaanDelta, notify }) {
  const FILE = path.join(dataDir, 'penjaga.json');
  let st = { runs: [], aman: {}, alerted: {}, lastAuto: 0, lastAi: 0 };
  try { st = { ...st, ...JSON.parse(fs.readFileSync(FILE, 'utf8')) }; } catch {}
  const save = () => { try { fs.writeFileSync(FILE + '.tmp', JSON.stringify(st)); fs.renameSync(FILE + '.tmp', FILE); } catch (e) { console.error('simpan penjaga:', e.message); } };
  let running = null;

  const amanAktif = u => { const a = st.aman[u]; return a && a.sampai > Date.now() ? a : null; };

  async function kumpul(jam) {
    const q = async (sql, p) => { try { return { rows: await dashRows(sql, p) }; } catch (e) { return { rows: [], err: e.message }; } };
    const [pemain, akt, aliran, transfer, dadu, bursa] = await Promise.all([
      q(Q.pemain), q(Q.aktivitas, [jam]), q(ALIRAN.Q.kapten, [jam]), q(Q.transfer, [jam]), q(Q.dadu, [jam]), q(AUD.bursa, [jam]),
    ]);
    const errors = {};
    for (const [k, v] of Object.entries({ pemain, akt, aliran, transfer, dadu, bursa })) if (v.err) errors[k] = v.err;
    return { pemain: pemain.rows, akt: akt.rows, aliran: aliran.rows, transfer: transfer.rows, dadu: dadu.rows, bursa: bursa.rows, errors };
  }

  async function nilaiAi(run, data) {
    const cfg = settings.get();
    if (!cfg.gemini.key) throw new Error('Kunci API Gemini belum diisi (Pengaturan).');
    const samar = cfg.penjaga.samarkan;
    const kode = new Map(); const balik = new Map();
    const id = u => { if (!samar) return u; if (!kode.has(u)) { const c = 'K' + String(kode.size + 1).padStart(2, '0'); kode.set(u, c); balik.set(c, u); } return kode.get(u); };
    const samarTeks = s => { if (!samar || !s) return s; let t = String(s); for (const r of data.pemain) { if (r.kapten && r.kapten.length > 1) t = t.split(r.kapten).join(id(r.username)); } return t; };
    // Kandidat: semua yang punya tanda + 5 kapten dengan gold masuk terbesar sebagai pembanding.
    const calon = new Map(run.temuan.map(f => [f.username, f]));
    for (const r of [...data.aliran].sort((a, b) => b.masuk - a.masuk).slice(0, 5)) if (!calon.has(r.username)) calon.set(r.username, { username: r.username, kapten: r.kapten, skor: 0, tingkat: 'wajar', tanda: [], angka: {} });
    const A = new Map(data.akt.map(r => [r.username, r])), L = new Map(data.aliran.map(r => [r.username, r])), P = new Map(data.pemain.map(r => [r.username, r]));
    const kaptenData = [...calon.values()].slice(0, 25).map(f => {
      const a = A.get(f.username) || {}, l = L.get(f.username) || {}, p = P.get(f.username) || {}, k = (data.kd && data.kd.get(f.username)) || {};
      return {
        id: id(f.username), umur_akun_hari: p.umur_hari, aksi: a.aksi, jam_aktif: a.jam_aktif, maks_aksi_per_menit: a.maks_per_menit, jeda_median_detik: a.jeda_median,
        jeda_bawah_1_detik: a.jeda_bawah_1, pola_terbanyak: samarTeks(a.pola), pola_terbanyak_n: a.pola_n, beli_item_peta: a.beli_item, galian: a.galian, jual_artefak: a.jual_item, layar: a.layar,
        gold_masuk: l.masuk, gold_keluar: l.keluar, dari_dagang: l.dari_dagang, dari_galian_artefak: l.dari_harta, dari_kapten_lain: l.dari_kapten, sumber_utama: l.sumber_utama,
        kekayaan_kini: k.kini ?? ((p.gold || 0) + (p.bank || 0) - (p.utang || 0)), kenaikan_kekayaan: k.delta,
        tanda_aturan: f.tanda.map(t => ({ judul: t.judul, bukti: samarTeks(t.bukti), poin: t.poin })), skor_aturan: f.skor,
      };
    });
    const transfer = data.transfer.filter(t => t.total >= 2e5).slice(0, 40).map(t => ({ dari: id(t.pengirim_u), ke: t.penerima_u ? id(t.penerima_u) : 'tidak dikenal', total: t.total, kali: t.kali }));
    const prompt = `Jendela data: ${run.jendelaJam} jam terakhir. Garis dasar server: ${JSON.stringify(run.baseline)}.
Kapten yang dinilai (${kaptenData.length}): ${JSON.stringify(kaptenData)}
Transfer antar kapten ≥ 200 rb: ${JSON.stringify(transfer)}
Nilai setiap kapten (pakai id persis seperti di data).`;
    const t0 = Date.now();
    const { out, usage } = await gemini({ key: cfg.gemini.key, model: cfg.gemini.model, system: AI_SYSTEM, prompt, schema: AI_SCHEMA });
    const unsamar = s => { if (!samar || !s) return s; return String(s).replace(/\bK\d{2}\b/g, c => { const u = balik.get(c); const p = u && P.get(u); return p ? p.kapten : c; }); };
    return {
      at: Date.now(), model: cfg.gemini.model, ms: Date.now() - t0, samar, usage,
      ringkasan: unsamar(out.ringkasan || ''),
      kapten: (out.kapten || []).map(x => { const u = samar ? balik.get(x.id) : x.id; const p = P.get(u); return { username: u || x.id, kapten: p ? p.kapten : unsamar(x.id), tingkat: x.tingkat, judul: unsamar(x.judul), alasan: (x.alasan || []).map(unsamar), saran: unsamar(x.saran) }; })
        .sort((a, b) => ['tinggi', 'sedang', 'rendah', 'wajar'].indexOf(a.tingkat) - ['tinggi', 'sedang', 'rendah', 'wajar'].indexOf(b.tingkat)),
      pola_baru: (out.pola_baru || []).map(unsamar),
    };
  }

  // sumber: 'otomatis' | 'panel' | 'telegram'; ai: true/false/'auto'
  async function scan({ sumber = 'panel', ai = false, jam } = {}) {
    if (running) return running;
    running = (async () => {
      const cfg = settings.get();
      const jendela = Math.min(168, Math.max(1, +jam || cfg.penjaga.jendelaJam));
      const t0 = Date.now();
      const data = await kumpul(jendela);
      const kd = kekayaanDelta(jendela); data.kd = kd;
      const { base, temuan } = nilai({ ...data, kekayaan: kd, jendela });
      for (const f of temuan) { const a = amanAktif(f.username); if (a) f.aman = a; }
      const run = { id: t0.toString(36), at: t0, sumber, jendelaJam: jendela, ms: 0, baseline: base, temuan, errors: data.errors, ai: null };
      const perluAi = ai === true || (ai === 'auto' && cfg.penjaga.ai === 'auto' && cfg.gemini.key &&
        temuan.some(f => !f.aman && f.tingkat !== 'rendah') && Date.now() - st.lastAi > cfg.penjaga.aiJedaJam * 3600e3);
      if (perluAi && cfg.penjaga.ai !== 'off') {
        try { run.ai = await nilaiAi(run, data); st.lastAi = Date.now(); }
        catch (e) { run.ai = { at: Date.now(), error: e.message }; }
      }
      run.ms = Date.now() - t0;
      st.runs.unshift(run); st.runs = st.runs.slice(0, 30);
      if (sumber === 'otomatis') st.lastAuto = t0;
      save();
      try { await peringatan(run); } catch (e) { console.error('penjaga peringatan:', e.message); }
      return run;
    })().finally(() => { running = null; });
    return running;
  }

  async function peringatan(run) {
    const cfg = settings.get().penjaga;
    if (cfg.alert === 'off' || !notify) return;
    const min = cfg.alert === 'sedang' ? 3 : 6;
    const aiT = new Map(((run.ai && run.ai.kapten) || []).map(k => [k.username, k]));
    const baru = run.temuan.filter(f => !f.aman && (f.skor >= min || ['tinggi'].includes((aiT.get(f.username) || {}).tingkat)) &&
      Date.now() - (st.alerted[f.username] || 0) > 12 * 3600e3);
    if (!baru.length) return;
    for (const f of baru) st.alerted[f.username] = Date.now();
    save();
    await notify(run, baru);
  }

  function tandaiAman(username, hari = 7, catatan = '') {
    username = String(username || '').slice(0, 80);
    if (!username) throw new Error('Kapten tidak dikenal.');
    if (+hari <= 0) delete st.aman[username];
    else st.aman[username] = { sampai: Date.now() + Math.min(90, +hari || 7) * 86400e3, catatan: String(catatan || '').slice(0, 200), at: Date.now() };
    save();
    return st.aman;
  }

  function tick() {
    const cfg = settings.get().penjaga;
    if (!cfg.auto || running) return;
    if (Date.now() - st.lastAuto < cfg.intervalMenit * 60e3) return;
    scan({ sumber: 'otomatis', ai: 'auto' }).catch(e => console.error('penjaga:', e.message));
  }

  return {
    scan, tandaiAman, tick,
    status: () => ({ running: !!running, lastAuto: st.lastAuto, lastAi: st.lastAi, aman: st.aman }),
    runs: () => st.runs,
    last: () => st.runs[0] || null,
    get: id => st.runs.find(r => r.id === id) || null,
    tesAi: async () => { const cfg = settings.get(); if (!cfg.gemini.key) throw new Error('Kunci API Gemini belum diisi.'); const t0 = Date.now(); const { out } = await gemini({ key: cfg.gemini.key, model: cfg.gemini.model, system: 'Jawab dalam JSON.', prompt: 'Balas {"ok": true, "pesan": "<satu kalimat sapaan singkat dalam Bahasa Indonesia>"}', timeoutMs: 30000 }); return { ok: true, ms: Date.now() - t0, model: cfg.gemini.model, pesan: out.pesan || '' }; },
    models: async () => { const cfg = settings.get(); if (!cfg.gemini.key) throw new Error('Kunci API Gemini belum diisi.'); return geminiModels(cfg.gemini.key); },
  };
}

module.exports = { create, nilai, Q };
