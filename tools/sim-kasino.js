// Simulasi Kasino Mutiara (Tide v84): kalibrasi Edge Blackjack & cek RTP dasar slot.
// Aturan HARUS sama dengan supabase/migrations/0104-kasino-mutiara.sql (game.ks_bj_*).
//   node tools/sim-kasino.js            -> tabel EV Blackjack per "dorongan" k (basic strategy) + RTP slot
//   node tools/sim-kasino.js 2000000    -> jumlah tangan per titik k
'use strict';
const N = Number(process.argv[2]) || 600000;

// RNG cepat yang bisa diulang (mulberry32)
let seed = 20261124;
function rnd() { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }

// ---------- Slot ----------
const SLOT = { w: { pearl: 2, anchor: 2, compass: 3, tankard: 7, shell: 7 }, pay3: { pearl: 50, anchor: 30, compass: 20, tankard: 12, shell: 6 }, pay2pearl: 3, pay1pearl: 1 };
function slotR0() {
  const W = Object.values(SLOT.w).reduce((a, b) => a + b, 0), q = SLOT.w.pearl / W;
  let r = 0; for (const k in SLOT.w) r += Math.pow(SLOT.w[k] / W, 3) * SLOT.pay3[k];
  return r + 3 * q * q * (1 - q) * SLOT.pay2pearl + 3 * q * (1 - q) * (1 - q) * SLOT.pay1pearl;
}

// ---------- Blackjack ----------
const val = r => (r === 1 ? 11 : r >= 10 ? 10 : r);
function score(h) { let t = 0, a = 0; for (const r of h) { t += val(r); if (r === 1) a++; } while (t > 21 && a) { t -= 10; a--; } return t; }
function soft(h) { let t = 0, a = 0; for (const r of h) { t += val(r); if (r === 1) a++; } while (t > 21 && a) { t -= 10; a--; } return a > 0 && t <= 21; }
function shoe() { const s = []; for (let d = 0; d < 6; d++) for (let su = 0; su < 4; su++) for (let r = 1; r <= 13; r++) s.push(r); for (let i = s.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [s[i], s[j]] = [s[j], s[i]]; } return s; }
// Strategi dasar 6 dek, dealer stand soft 17, tanpa split/surrender. 'h' | 's' | 'd'
function basic(h, up) {
  const t = score(h), sf = soft(h), two = h.length === 2, u = val(up) === 11 ? 11 : val(up);
  const D = x => (two ? 'd' : x);
  if (sf) {
    if (t >= 19) return 's';
    if (t === 18) { if (u >= 3 && u <= 6) return D('s'); return u <= 8 ? 's' : 'h'; }
    if (t === 17) return u >= 3 && u <= 6 ? D('h') : 'h';
    if (t >= 15) return u >= 4 && u <= 6 ? D('h') : 'h';
    if (t >= 13) return u >= 5 && u <= 6 ? D('h') : 'h';
    return 'h';
  }
  if (t >= 17) return 's';
  if (t >= 13) return u <= 6 ? 's' : 'h';
  if (t === 12) return u >= 4 && u <= 6 ? 's' : 'h';
  if (t === 11) return u <= 10 ? D('h') : 'h';
  if (t === 10) return u <= 9 ? D('h') : 'h';
  if (t === 9) return u >= 3 && u <= 6 ? D('h') : 'h';
  return 'h';
}
// Satu ronde, taruhan 1. k > 0 membantu bandar (kartu yang membuat bandar bust diganti sekali dengan peluang k),
// k < 0 membantu kapten (kartu hit/double yang membuat kapten bust diganti dengan peluang min(1,|k|),
// lalu bila k < -1 diganti sekali lagi dengan peluang |k| - 1).
function bjRound(k) {
  const s = shoe(); let i = 0; const draw = () => s[i++];
  const p = [draw()], d = [draw()]; p.push(draw()); d.push(draw());
  const up = d[0], pbj = score(p) === 21, dbj = score(d) === 21;
  if ((val(up) >= 10) && dbj) return pbj ? 0 : -1;               // bandar mengintip
  if (pbj) return dbj ? 0 : 1.5;
  let bet = 1;
  const pdraw = () => {
    let c = draw();
    if (k < 0 && score(p.concat(c)) > 21 && rnd() < Math.min(1, -k)) c = draw();
    if (k < -1 && score(p.concat(c)) > 21 && rnd() < -k - 1) c = draw();      // dorongan kedua (k < -1)
    p.push(c);
  };
  for (;;) {
    const a = basic(p, up);
    if (a === 's') break;
    if (a === 'd') { bet = 2; pdraw(); break; }
    pdraw(); if (score(p) >= 21) break;
  }
  const ps = score(p); if (ps > 21) return -bet;
  while (score(d) < 17) { let c = draw(); if (k > 0 && score(d.concat(c)) > 21 && rnd() < k) c = draw(); d.push(c); }
  const ds = score(d);
  if (ds > 21 || ps > ds) return bet; if (ps === ds) return 0; return -bet;
}

console.log('Slot RTP dasar (R0):', slotR0().toFixed(6));
const ks = []; for (let k = -2; k <= 0.8001; k += 0.1) ks.push(Math.round(k * 10) / 10);
const out = [];
for (const k of ks) { let sum = 0; for (let n = 0; n < N; n++) sum += bjRound(k); out.push([k, sum / N]); console.log('k', k.toFixed(1).padStart(5), 'EV', (sum / N * 100).toFixed(3) + '%'); }
console.log('\nUntuk SQL (k, ev):', out.map(([k, e]) => `(${k},${e.toFixed(5)})`).join(','));
