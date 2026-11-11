// Pemecah Urut Cap (quest Surat Pulang): menyusun batasan dari cap yang bertumpang (yang menimpa = lebih baru)
// dan tanggal yang terbaca, lalu menghitung berapa urutan yang mungkin. Level sah = tepat satu urutan.
function constraints(L) {
  const S = L.stamps, c = [];
  for (let i = 0; i < S.length; i++) for (let j = 0; j < S.length; j++) {
    if (i === j) continue;
    const a = S[i], b = S[j];
    const over = Math.hypot(a.x - b.x, a.y - b.y) < a.r + b.r;           // bertumpang -> urutan tampak dari siapa di atas
    const days = a.day != null && b.day != null && a.day < b.day;         // tanggal terbaca
    if ((over && a.z < b.z) || days) c.push([i, j]);                       // i lebih tua dari j
  }
  return c;
}
// jumlah urutan topologis (DP bitmask, n <= 16)
function countOrders(L) {
  const n = L.stamps.length, pre = new Array(n).fill(0);
  for (const [i, j] of constraints(L)) pre[j] |= (1 << i);
  const dp = new Array(1 << n).fill(0); dp[0] = 1;
  for (let m = 0; m < (1 << n); m++) {
    if (!dp[m]) continue;
    for (let k = 0; k < n; k++) if (!(m & (1 << k)) && (pre[k] & m) === pre[k]) dp[m | (1 << k)] += dp[m];
  }
  return dp[(1 << n) - 1];
}
function answer(L) { return L.stamps.slice().sort((a, b) => a.z - b.z).map(s => s.id); }
module.exports = { constraints, countOrders, answer };
