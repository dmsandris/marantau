// Harga buku per tier (Tide v24)
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const rows = await H.sql(`select book_id, tier, price::int p from game.book_catalog where source <> 'quest'`);
  const R = { I: [300, 1500], II: [2000, 9000], III: [10000, 35000], IV: [40000, 70000], V: [80000, 160000] };
  for (const r of rows) assert(R[r.tier] && r.p >= R[r.tier][0] && r.p <= R[r.tier][1], 'harga di luar rentang tier: ' + JSON.stringify(r));
  for (const t of Object.keys(R)) {
    const ps = rows.filter(r => r.tier === t).map(r => r.p);
    assert(ps.length && Math.min(...ps) === R[t][0] && Math.max(...ps) === R[t][1], 'tier ' + t + ' memakai rentang penuh ' + ps);
  }
  assert(rows.length === 41, 'jumlah buku ' + rows.length);
  console.log('BOOK PRICES TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
