// Tide v57: baris pasar yang lama tidak tersentuh tidak boleh membuat pasar error.
// Dulu exp(-menit/26) melempar "value out of range: underflow" setelah ±13 hari tanpa pengunjung
// (terjadi di produksi: 31 baris Titik Buta, 17 hari).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('tidur'); await u.call('api_createCharacter', ['Kapten Tidur', 'merchant']);
  await H.sql('update game.players set gold = 500000 where player_id = $1', [u.id]);
  await H.sql(`update game.player_location set city_id = 'bjorneo', destination_city_id = null where player_id = $1`, [u.id]);
  const proj = (city) => H.sql(`select m.commodity_id, c.tier, m.role,
      game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, '{}'::jsonb, game.mkt_cycle_index()) as v,
      game.mkt_eq(m.role, c.tier, c.ref, c.id, '{}'::jsonb) as eq
    from game.market m join game.commodities c on c.id = m.commodity_id where m.city_id = $1 and c.active`, [city]);

  // 1) Nilai untuk umur normal tidak berubah: stok meluruh menuju keseimbangan seperti biasa
  await H.sql(`update game.market set stock = 40, at = now() - interval '30 minutes' where city_id = 'bjorneo'`);
  const pendek = await proj('bjorneo');
  assert(pendek.some(r => Number(r.v) !== Number(r.eq)), '30 menit: stok belum sampai keseimbangan');

  // 2) Semua umur panjang (termasuk di atas batas lama ±12,8 hari) tidak error dan sampai keseimbangan
  for (const iv of ['13 days', '20 days', '365 days', '3650 days']) {
    await H.sql(`update game.market set stock = 40, at = now() - $1::interval where city_id = 'bjorneo'`, [iv]);
    const rows = await proj('bjorneo');
    assert(rows.length > 0, 'ada baris pasar');
    for (const r of rows) {
      const v = Number(r.v), eq = Number(r.eq);
      if (r.tier === 'premium' && r.role === 'produce') assert(v >= 0, iv + ' premium produsen: ' + r.commodity_id);
      else assert(v === Number(Math.max(0, eq).toFixed(3)), iv + ' ' + r.commodity_id + ' = keseimbangan (' + v + ' vs ' + eq + ')');
    }
  }

  // 3) Jalur pemain: buka pasar, bundle kota, beli, jual — tanpa error
  await H.sql(`update game.market set stock = 40, at = now() - interval '20 days' where city_id = 'bjorneo'`);
  const m = await u.call('api_getMarket', ['bjorneo']);
  assert(m.items.length > 0, 'api_getMarket setelah 20 hari');
  await H.sql(`update game.market set at = now() - interval '20 days' where city_id = 'bjorneo'`);
  const b = await u.call('api_getCityBundle', ['bjorneo']);
  assert(!b.marketError, 'bundle tanpa marketError: ' + b.marketError);
  await H.sql(`update game.market set at = now() - interval '20 days' where city_id = 'bjorneo'`);
  await u.call('api_buy', ['bjorneo', 'lada', 1]);
  await H.sql(`update game.market set at = now() - interval '20 days' where city_id = 'bjorneo'`);
  await u.call('api_sell', ['bjorneo', 'lada', 1]);

  console.log('pasar tidur: 13 hari s/d 10 tahun aman, beli & jual jalan');
  process.exit(0);
})().catch(e => { console.error('GAGAL:', e.message); process.exit(1); });
