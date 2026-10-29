// Tide v41 (hemat Disk IO): pasar ditulis ulang paling cepat tiap 180 dtk, kehadiran tiap 45 dtk.
// Tujuan tes: menulis lebih jarang, tapi yang dilihat pemain TIDAK berubah.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('hematio'); await u.call('api_createCharacter', ['Kapten Hemat IO', 'merchant']);
  await H.sql(`update game.player_location set city_id = 'bjorneo', destination_city_id = null where player_id = $1`, [u.id]);
  const row = async () => (await H.sql(`select stock::float8 s, extract(epoch from at)::float8 at from game.market where city_id = 'bjorneo' and commodity_id = 'lada'`))[0];
  const shown = async () => (await u.call('api_getMarket', ['bjorneo'])).items.find((i) => i.commodityId === 'lada');

  // 1) baris berumur 60 dtk (siklus sama) -> TIDAK ditulis ulang, tapi angka tampil = proyeksi saat ini
  await H.sql(`update game.market m set stock = c.ref * 1.6, at = now() - interval '60 seconds', cyc = game.mkt_cycle_index()
    from game.commodities c where c.id = m.commodity_id and m.city_id = 'bjorneo'`);
  const r0 = await row();
  const a = await shown();
  const r1 = await row();
  assert(r1.at === r0.at, 'baris 60 dtk tidak ditulis ulang');
  const exp = (await H.sql(`select floor(game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id,
      game.mkt_cycle_tags('bjorneo', game.mkt_cycle_index()), game.mkt_cycle_index()))::float8 s
    from game.market m join game.commodities c on c.id = m.commodity_id where m.city_id = 'bjorneo' and m.commodity_id = 'lada'`))[0].s;
  assert(Math.abs(a.stock - exp) <= 1, 'stok tampil = proyeksi (' + a.stock + ' vs ' + exp + ')');

  // 2) baris berumur 10 menit -> ditulis ulang, angka tetap sama dengan sebelum ditulis
  await H.sql(`update game.market set at = now() - interval '10 minutes' where city_id = 'bjorneo'`);
  const before = await shown();
  const r2 = await row();
  assert(r2.at > r1.at + 30, 'baris 10 menit ditulis ulang');
  const after = await shown();
  assert(after.stock === before.stock && after.buyPrice === before.buyPrice, 'harga & stok sama setelah ditulis ulang');

  // 3) kehadiran: cap waktu 30 dtk tidak ditulis ulang, 50 dtk ditulis ulang; tetap terhitung online
  await u.call('api_mpPulse', [{}]);
  const ts = async () => (await H.sql(`select extract(epoch from ts)::float8 t from game.mp_presence where player_id = $1`, [u.id]))[0].t;
  await H.sql(`update game.mp_presence set ts = now() - interval '30 seconds' where player_id = $1`, [u.id]);
  const t30 = await ts();
  const p1 = await u.call('api_mpPulse', [{}]);
  assert(await ts() === t30, 'kehadiran 30 dtk tidak ditulis ulang');
  assert(p1.online >= 1, 'tetap terhitung online');
  await H.sql(`update game.mp_presence set ts = now() - interval '50 seconds' where player_id = $1`, [u.id]);
  const t50 = await ts();
  await u.call('api_mpPulse', [{}]);
  assert(await ts() > t50 + 40, 'kehadiran 50 dtk ditulis ulang');

  // 4) index ts sudah tidak ada
  const idx = await H.sql(`select 1 from pg_indexes where schemaname = 'game' and indexname = 'mp_presence_ts_idx'`);
  assert(idx.length === 0, 'index mp_presence_ts_idx dibuang');

  console.log('HEMAT IO TESTS PASSED');
})().catch((e) => { console.error(e); process.exit(1); });
