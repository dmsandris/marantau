// 0073 Zentul: pulau tersembunyi Laut Jauh, Oli Hitam premium, tanpa bank, Sirkuit hanya saat merapat.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const H0 = require('./harness');
(async () => {
  const H = await H0.create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const a = await H.user('zenta'), b = await H.user('zenbe');
  await a.call('api_createCharacter', ['Kapten Zen', 'merchant']);
  await b.call('api_createCharacter', ['Orang Biasa', 'pirate']);

  const z = await one(`select * from game.cities where city_id = 'zentul'`);
  assert(z && z.hidden === true && z.type === 'Zentul' && Number(z.map_x) > 150 && Number(z.map_y) < 30, 'Zentul di kanan atas peta, tersembunyi');
  assert((await one(`select game.voy_far_city('zentul') f`)).f === true && (await one(`select game.voy_far_city('sowtour') f`)).f === true && (await one(`select game.voy_far_city('skitraw') f`)).f === false, 'Laut Jauh: Zentul masuk, daftar lama utuh');
  assert(/oli/i.test((await one(`select game.city_flavor('Zentul') t`)).t) && (await one(`select game.city_flavor('TradeHub') t`)).t, 'flavor Zentul + flavor lama utuh');

  // tertutup untuk semua sampai dibuka
  for (const u of [a, b]) {
    assert((await one(`select game.city_open($1, 'zentul') o`, [u.id])).o === false, 'Zentul tertutup');
    assert(!(await one(`select game.player_unlocks($1) u`, [u.id])).u.includes('zentul'), 'tidak ada di unlocks');
  }
  const before = (await one(`select game.player_unlocks($1) u`, [b.id])).u;
  await H.sql(`insert into game.config(key, value) values ('FiturPenguji', 'zenta') on conflict (key) do update set value = 'zenta'`);
  assert((await one(`select game.city_open($1, 'zentul') o`, [a.id])).o === true && (await one(`select game.player_unlocks($1) u`, [a.id])).u.includes('zentul'), 'penguji melihat Zentul');
  assert((await one(`select game.city_open($1, 'zentul') o`, [b.id])).o === false, 'pemain lain tetap tidak');
  assert(JSON.stringify((await one(`select game.player_unlocks($1) u`, [b.id])).u) === JSON.stringify(before), 'unlocks pemain lain identik');
  assert((await one(`select game.city_open($1, 'sunda_empire') o`, [b.id])).o === true, 'kota lama tetap terbuka');

  // pasar: Oli Hitam premium, produksi hanya di Zentul
  const oli = await H.sql(`select city_id, role from game.market where commodity_id = 'oli_hitam'`);
  assert(oli.length > 5 && oli.filter(r => r.role === 'produce').length === 1 && oli.find(r => r.role === 'produce').city_id === 'zentul', 'Oli Hitam hanya diproduksi Zentul');
  assert((await one(`select tier from game.commodities where id = 'oli_hitam'`)).tier === 'premium', 'Oli Hitam premium');
  const zm = await H.sql(`select commodity_id, role from game.market where city_id = 'zentul'`);
  assert(zm.length >= 29 && zm.find(r => r.commodity_id === 'besi').role === 'produce' && zm.find(r => r.commodity_id === 'beras').role === 'consume', 'peran pasar Zentul');
  assert((await H.sql(`select 1 from game.market m join game.cities c using (city_id) where m.commodity_id = 'oli_hitam' and game.spot_city(c.city_id)`)).length === 0, 'titik laut tanpa pasar tetap tanpa pasar');

  // berlayar ke Zentul lalu berdagang & bank
  await H.expectError(() => b.call('api_setSail', ['zentul']), /./);
  await H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null, depart_at = null, arrive_at = null where player_id = $1`, [a.id]);
  const mk = await a.call('api_getMarket', ['zentul']);
  const rows = mk.market || mk.items || mk;
  assert(JSON.stringify(rows).includes('oli_hitam'), 'pasar Zentul menjual Oli Hitam');
  await H.sql(`update game.players set gold = 500000 where player_id = $1`, [a.id]);
  await H.expectError(() => a.call('api_bankDeposit', [1000]), /tidak punya bank/);
  await H.sql(`update game.player_location set city_id = 'sunda_empire' where player_id = $1`, [a.id]);
  await a.call('api_bankDeposit', [1000]);

  // Sirkuit: saat TrekOpen = 1 hanya di Zentul
  assert((await a.call('api_trek', ['status'])).trek, 'penguji: pintas #trek dari mana saja selama TrekOpen = 0');
  await H.sql(`update game.config set value = '1' where key = 'TrekOpen'`);
  await H.expectError(() => a.call('api_trek', ['status']), /Aksi tidak dikenal/);
  await H.sql(`update game.player_location set city_id = 'zentul' where player_id = $1`, [a.id]);
  assert((await a.call('api_trek', ['status'])).trek.ship === 'jolt', 'merapat di Zentul: Sirkuit terbuka');

  console.log('0073 zentul: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
