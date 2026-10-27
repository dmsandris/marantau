// Tide v39: cap last_active di game.me() memakai FOR UPDATE SKIP LOCKED.
// Tes ini memastikan perilaku untuk pemain tidak berubah (cap tetap diperbarui bila basi,
// tidak ditulis ulang bila masih segar, dan aksi yang mengunci baris tetap jalan).
// Perilaku "tidak menunggu kunci" butuh dua koneksi Postgres -> diuji terpisah di Postgres asli.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('aktif'); await u.call('api_createCharacter', ['Kapten Aktif', 'merchant']);
  const la = async () => (await H.sql(`select extract(epoch from last_active)::float8 t from game.players where player_id = $1`, [u.id]))[0].t;

  // 1) basi (> 1 menit) -> panggilan biasa memperbaruinya
  await H.sql(`update game.players set last_active = now() - interval '10 minutes' where player_id = $1`, [u.id]);
  const old = await la();
  await u.call('api_pollVoyage', []);
  const fresh = await la();
  assert(fresh > old + 500, 'last_active diperbarui saat basi');

  // 2) masih segar -> tidak ditulis ulang
  await u.call('api_getCargoState', ['sunda_empire']);
  assert(await la() === fresh, 'last_active tidak ditulis ulang < 1 menit');

  // 3) aksi yang mengunci baris pemain (game.me(true)) tetap memperbarui cap basi & berhasil
  await H.sql(`update game.players set last_active = now() - interval '10 minutes' where player_id = $1`, [u.id]);
  const before = await la();
  await u.call('api_bankDeposit', [100]);
  assert(await la() > before + 500, 'aksi terkunci tetap memperbarui last_active');
  const p = (await H.sql(`select bank_balance::int8 b from game.players where player_id = $1`, [u.id]))[0];
  assert(Number(p.b) === 100, 'setoran bank tetap tercatat');

  console.log('LAST ACTIVE TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
