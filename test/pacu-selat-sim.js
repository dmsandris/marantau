// Memuat window.PacuSelat.sim (web/src/PacuSelat.html) di Node + pemain tiruan untuk tes & kalibrasi Pacu Selat.
const fs = require('fs'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'src', 'PacuSelat.html'), 'utf8').match(/<script>([\s\S]*)<\/script>/)[1];
const W = {};
new Function('window', 'document', 'performance', src)(W, {}, { now: () => 0 });
const S = W.PacuSelat.sim;
const PARTS = Object.keys(S.CONFIG.KOMPONEN);
const KELAS = Object.keys(S.CONFIG.KELAS_KAPAL);

function mk(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const T = (k) => Math.trunc(k * 25 / 3);
const SKILL = {
  pemula: { react: 0.33, sd: 0.11, boost: false },
  biasa: { react: 0.27, sd: 0.07, boost: true },
  jago: { react: 0.21, sd: 0.04, boost: true }
};

// Pemain manusia tiruan: membidik tengah bintang emas dengan galat waktu acak, tahan di gigi 5.
// Ketukan diterapkan sebelum step tick yang sama (persis urutan jalankan() dan game.ps_sim).
function human(kelas, parts, jarakMm, seed, sk, rasio) {
  const R = mk(seed), g = () => { let u = 0; for (let i = 0; i < 6; i++) u += R(); return u - 3; };
  const spec = S.spesifikasi(kelas, parts, rasio || '800'), M = S.waktuMeriam(seed);
  const s = S.buat(spec, { isPemain: true, jarakMm }), log = [];
  let plan = null, held = false;
  const react = Math.round(Math.max(120, (sk.react + g() * 0.05) * 1000));
  const press = (v, t) => { S.input(s, v, t); log.push([t, v]); };
  for (let k = 1; k <= 14400; k++) {
    const t = T(k) - M;
    if (!s.launched && t >= react && s.finishWaktuMs == null) { press(1, t); press(0, t); }
    else if (s.launched && s.gear < 5 && s.shiftLagMs <= 0 && plan == null) {
      const c = JSON.parse(JSON.stringify(s)), w = S.jendelaGigi(spec, s.gear), tgt = Math.trunc((w.starStartPermil + w.greenEndPermil) / 2);
      let kk = k; for (; kk < k + 2000; kk++) { S.step(c, kk, M); c.eventsTick = []; if (c.rpmPermil >= tgt) break; }
      plan = T(kk) - M + Math.round(g() * sk.sd * 1000);
    }
    if (plan != null && t >= plan && s.gear < 5) { press(1, t); plan = null; if (s.gear === 5 && sk.boost) held = true; else press(0, t); }
    if (held && s.boostUsed && s.boostLeftMs <= 0) { press(0, t); held = false; }
    S.step(s, k, M); s.eventsTick.length = 0;
    if (s.finishWaktuMs != null || s.exploded) break;
  }
  return { s, log, M };
}
// Log sembarang: ketukan kembar, sebelum meriam, tahan lama, lepas tanpa tekan.
function chaos(seed) {
  const R = mk(seed), n = 1 + Math.floor(R() * 24), log = []; let t = -900 + Math.floor(R() * 1400);
  for (let j = 0; j < n; j++) { log.push([t, R() < 0.7 ? 1 : 0]); if (R() < 0.15) log.push([t, R() < 0.5 ? 1 : 0]); t += R() < 0.1 ? 0 : Math.floor(R() * 2600); }
  return log;
}
// Hasil JS satu kapal pemain (lewat jalankan, sama dengan yang diputar klien)
function jsRun(kelas, parts, rasio, jarakMm, log, seed) {
  const o = S.jalankan({ jarakMm, rasioPreset: rasio, peserta: [{ id: 'p', isPemain: true, kelas, parts }] }, log, seed);
  return o.statistikPemain;
}
function jsAi(lawan, jarakMm, seed) {
  const o = S.jalankan({ jarakMm, peserta: [Object.assign({}, lawan, { id: 'x', isPemain: false })] }, [], seed);
  return o.finishPerKapal.x;
}
module.exports = { S, PARTS, KELAS, SKILL, mk, human, chaos, jsRun, jsAi };

if (require.main === module) {   // node test/pacu-selat-sim.js -> tabel waktu rata-rata 800 m
  for (const [k, p] of [['sekoci_standar', []], ['kolek_kilat', PARTS.slice(0, 4)], ['bahtera_petir', PARTS]]) {
    let line = (k + '/' + p.length).padEnd(20);
    for (const sk in SKILL) { let t = 0, n = 0; for (let i = 0; i < 40; i++) { const r = human(k, p, 800000, i * 31 + 7, SKILL[sk]).s; if (r.finishWaktuMs != null) { t += r.finishWaktuMs; n++; } } line += ` ${sk}:${(t / Math.max(1, n) / 1000).toFixed(2)}`; }
    console.log(line);
  }
}
