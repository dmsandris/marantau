// Memuat MTTrekSim (web/src/TrekSim.html) di Node + pemain tiruan untuk tes & kalibrasi.
const fs = require('fs'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'src', 'TrekSim.html'), 'utf8').match(/<script>([\s\S]*)<\/script>/)[1];
const m = { exports: {} }; new Function('module', src)(m);
const D = m.exports;

function mk(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function crossK(s, k0, target) { const c = JSON.parse(JSON.stringify(s)); for (let k = k0 + 1; k < k0 + 700; k++) { D.step(c, k); if (c.rpm >= target) return k; } return k0 + 700; }
const SKILL = {
  pemula: { react: 0.33, sd: 0.11, boost: false },
  biasa: { react: 0.27, sd: 0.07, boost: true },
  jago: { react: 0.21, sd: 0.04, boost: true }
};
// Pemain manusia tiruan: membidik pita SEMPURNA dengan galat waktu acak (sd detik). Mengembalikan state + log ketukan.
function human(ship, seed, sk) {
  const R = mk(seed), g = () => { let u = 0; for (let i = 0; i < 6; i++) u += R(); return u - 3; };
  const react = Math.round(Math.max(120, (sk.react + g() * 0.05) * 1000)), s = D.create(ship), log = [];
  let plan = null;
  const dn = (t) => { D.input(s, 'd', t); log.push([t, 1]); }, up = (t) => { D.input(s, 'u', t); log.push([t, 0]); };
  for (let k = 1; k <= 3600 && s.fin == null; k++) {
    const t = Math.trunc(k * 25 / 3);
    if (!s.launched && t >= react) { dn(t); up(t); }
    if (s.launched && s.gear < 5 && s.shiftLeft <= 0 && plan == null && t - s.launchAt > 300) plan = Math.trunc(crossK(s, k, D.zone(s)[1] - D.BAND / 2) * 25 / 3) + Math.round(g() * sk.sd * 1000);
    if (plan != null && t >= plan && s.gear < 5) { dn(t); plan = null; if (!(sk.boost && s.gear === 5)) up(t); }
    D.step(s, k);
  }
  s.log = log; return s;
}
// Log sembarang (termasuk ketukan kembar, sebelum meriam, tahan lama) untuk uji kesamaan JS = SQL.
function chaos(seed) {
  const R = mk(seed), n = 1 + Math.floor(R() * 16), log = []; let t = -600 + Math.floor(R() * 1200);
  for (let j = 0; j < n; j++) { log.push([t, R() < 0.75 ? 1 : 0]); if (R() < 0.15) log.push([t, 1]); t += R() < 0.1 ? 0 : Math.floor(R() * 1700); }
  return log;
}
module.exports = { D, human, chaos, SKILL };

if (require.main === module) {   // node test/trek-sim.js -> tabel kalibrasi
  for (const ship of ['tanpa', 'jolt', 'penuh']) for (const k in SKILL) {
    let line = ship.padEnd(8) + k.padEnd(8), tt = 0; const N = 300;
    for (const rk in D.RIVALS) { let w = 0; tt = 0; for (let i = 0; i < N; i++) { const me = human(ship, i * 31 + 7, SKILL[k]); tt += me.fin; if (me.fin < D.runAi(rk, i * 13 + 1).fin) w++; } line += ` ${rk}:${Math.round(w / N * 100)}%`; }
    console.log(line + `  rata2 ${(tt / N / 1e6).toFixed(2)}`);
  }
}
