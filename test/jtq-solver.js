// Solver Meja Kas (quest rahasia Rekening J.T., 0067). Aturan harus sama dengan game.jt_check_timbang / jt_check_kas.
// Timbang Koin: n koin (id c1..cn), k koin lebih berat (berat sama). Satu timbangan = dua piring berisi koin
// sama banyak; hasil = piring mana yang lebih berat (atau seimbang). Selesai bila hanya satu kemungkinan tersisa.
function combos(n, k) {
  const out = [];
  (function rec(s, cur) { if (cur.length === k) { out.push(cur.reduce((m, i) => m | (1 << i), 0)); return; } for (let i = s; i < n; i++) rec(i + 1, cur.concat(i)); })(0, []);
  return out;
}
const pop = (m) => { let c = 0; while (m) { m &= m - 1; c++; } return c; };
function outcome(h, L, R) { const a = pop(h & L), b = pop(h & R); return a > b ? 1 : a < b ? -1 : 0; }

/** Pencari strategi adaptif dengan simetri koin. Mengembalikan fungsi strat(S, d) -> [L, R] | true | null. */
function strategy(n) {
  const memo = new Map();
  function swapOk(S, set, i, j) {
    for (const h of S) { const bi = (h >> i) & 1, bj = (h >> j) & 1; let g = h; if (bi !== bj) g = h ^ (1 << i) ^ (1 << j); if (!set.has(g)) return false; }
    return true;
  }
  function go(S, d) {
    if (S.length <= 1) return true;
    if (d === 0 || S.length > Math.pow(3, d)) return null;
    const key = d + ':' + S.slice().sort((a, b) => a - b).join(',');
    if (memo.has(key)) return memo.get(key);
    const set = new Set(S), cls = [], seen = new Array(n).fill(false);
    for (let i = 0; i < n; i++) { if (seen[i]) continue; const c = [i]; seen[i] = true; for (let j = i + 1; j < n; j++) if (!seen[j] && swapOk(S, set, i, j)) { seen[j] = true; c.push(j); } cls.push(c); }
    let found = null;
    (function rec(ci, L, R, nl, nr) {
      if (found) return;
      if (ci === cls.length) {
        if (nl === 0 || nl !== nr) return;
        const parts = { '-1': [], '0': [], '1': [] };
        for (const h of S) parts[outcome(h, L, R)].push(h);
        if (Math.max(parts['-1'].length, parts['0'].length, parts['1'].length) === S.length) return;
        if (go(parts['-1'], d - 1) && go(parts['0'], d - 1) && go(parts['1'], d - 1)) found = [L, R];
        return;
      }
      const c = cls[ci];
      for (let l = 0; l <= c.length; l++) for (let r = 0; l + r <= c.length; r++) {
        let L2 = L, R2 = R;
        for (let t = 0; t < l; t++) L2 |= 1 << c[t];
        for (let t = l; t < l + r; t++) R2 |= 1 << c[t];
        rec(ci + 1, L2, R2, nl + l, nr + r);
        if (found) return;
      }
    })(0, 0, 0, 0, 0);
    memo.set(key, found);
    return found;
  }
  return go;
}

/** Ada strategi adaptif yang selalu menemukan k koin berat di antara n koin dalam d timbangan? */
function solvable(n, k, d) { return !!strategy(n)(combos(n, k), d); }

/** Mainkan strategi untuk koin berat tertentu -> { w: [{l, r}], pick } (lolos pemeriksaan server). */
function play(n, k, d, odd) {
  const go = strategy(n), truth = odd.map(id => +id.slice(1) - 1).reduce((m, i) => m | (1 << i), 0);
  const ids = (m) => { const a = []; for (let i = 0; i < n; i++) if (m & (1 << i)) a.push('c' + (i + 1)); return a; };
  let S = combos(n, k); const w = [];
  for (let step = d; S.length > 1; step--) {
    const mv = go(S, step); if (!mv || mv === true) throw new Error('tidak ada strategi');
    const o = outcome(truth, mv[0], mv[1]);
    S = S.filter(h => outcome(h, mv[0], mv[1]) === o);
    w.push({ l: ids(mv[0]), r: ids(mv[1]) });
  }
  return { w, pick: ids(S[0]) };
}

/** Hitung Kas: satu ronde -> { ok, min } (jumlah koin paling sedikit, atau null bila mustahil). Stok = koin baik saja. */
function kasRound(kinds, R) {
  const val = {}; kinds.forEach(k => { val[k.id] = k.val; });
  const ids = Object.keys(R.stock).filter(id => (R.stock[id] || 0) > 0);
  let best = null;
  // pencarian lengkap kecil: bagi stok ke baki satu per satu
  (function tray(t, left, coins) {
    if (best !== null && coins >= best) return;
    if (t === R.trays.length) { best = coins; return; }
    const target = R.trays[t];
    (function rec(i, rem, used, c) {
      if (best !== null && coins + c >= best) return;
      if (rem === 0) { tray(t + 1, Object.assign({}, left, ...Object.keys(used).map(k => ({ [k]: left[k] - used[k] }))), coins + c); return; }
      if (i === ids.length) return;
      const id = ids[i], max = Math.min(left[id] || 0, Math.floor(rem / val[id]));
      for (let q = max; q >= 0; q--) rec(i + 1, rem - q * val[id], Object.assign({}, used, { [id]: q }), c + q);
    })(0, target, {}, 0);
  })(0, Object.assign({}, R.stock), 0);
  return best;
}
/** Jawaban ronde dengan jumlah koin paling sedikit -> [ {kind: n}, ... per baki ] */
function kasAnswer(kinds, R) {
  const val = {}; kinds.forEach(k => { val[k.id] = k.val; });
  const ids = Object.keys(R.stock).filter(id => (R.stock[id] || 0) > 0).sort((a, b) => val[b] - val[a]);
  let best = null, bestAns = null;
  (function tray(t, left, coins, ans) {
    if (best !== null && coins >= best) return;
    if (t === R.trays.length) { best = coins; bestAns = ans; return; }
    (function rec(i, rem, used, c) {
      if (best !== null && coins + c >= best) return;
      if (rem === 0) { const l2 = Object.assign({}, left); Object.keys(used).forEach(k => { l2[k] -= used[k]; }); const u = {}; Object.keys(used).forEach(k => { if (used[k]) u[k] = used[k]; }); tray(t + 1, l2, coins + c, ans.concat([u])); return; }
      if (i === ids.length) return;
      const id = ids[i], max = Math.min(left[id] || 0, Math.floor(rem / val[id]));
      for (let q = max; q >= 0; q--) rec(i + 1, rem - q * val[id], Object.assign({}, used, { [id]: q }), c + q);
    })(0, R.trays[t], {}, 0);
  })(0, Object.assign({}, R.stock), 0, []);
  return bestAns;
}
module.exports = { solvable, play, kasRound, kasAnswer, combos, outcome };
