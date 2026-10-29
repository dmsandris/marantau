// Tide v41 · Pasir Batch 4 — Zaman 40 Tahun Lalu: lompatan, peta lampau + Benua Sudyrman (rahasia), masa lalu menolak koin,
// pelayaran tanpa bajak laut & kerusakan, Pustaka Agung, Dok Garuda & Galangan Lembah, efek buku & Pusaka, ekonomi tidak berubah.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  // Kerahasiaan: kota Sudyrman tidak pernah ada di daftar kota umum
  const C = await H.user('q12_cici');
  await C.call('api_createCharacter', ['Kapten Cici', 'merchant']);
  const sc = await C.call('api_getGameState', [null]);
  ok(Array.isArray(sc.cities) && sc.cities.length > 5, 'daftar kota terkirim');
  ok(!JSON.stringify(sc.cities).includes('Sudyrman'), 'Sudyrman tidak ada di daftar kota umum');
  ok(!('pasir' in sc), 'pemain biasa tanpa key pasir');

  const A = await H.user('q12_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5),($1,'gala',6)`, [pid]);
  await H.sql(`select game.pasir_ensure($1)`, [pid]);
  await H.sql(`select game.pv_ambil($1, 'sunda_empire')`, [pid]);
  await H.sql(`update game.pasir_state set data = data || '{"buka": ["empeer_depeer"]}'::jsonb, kaca = 2 where player_id = $1`, [pid]);
  await H.sql(`select game.ps_set($1, 'ps10', 11, '{}'::jsonb, true), game.ps_set($1, 'ps11', 10, '{}'::jsonb, true)`, [pid]);
  await H.sql(`insert into game.pv_pusaka(player_id, pusaka_id, mutu, slot) values ($1, 'jangkar', 'baik', 1)`, [pid]);
  await H.sql(`update game.players set gold = 2000000 where player_id = $1`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const market0 = await one(`select sum(current_price)::text p, sum(stock)::text s from game.market`);

  await place('empeer_depeer');
  let s = await gs();
  ok(s.pasir.zaman.includes('lampau'), 'Jam Agung menunjuk 40 Tahun Lalu');
  ok(s.pasir.toko.pustaka === null && s.pasir.kotaLampau.length === 0, 'Zaman Keadilan: toko masa lalu tertutup');
  await act('lompat', 'lampau');
  s = await gs();
  ok(s.pasir.era === 'lampau' && s.pasir.tone === 'emas' && s.city.CityId === 'ikn', 'mendarat di IKN 40 Tahun Lalu');
  ok(s.unlocks.length === 0, 'peta lampau: pulau awal saja (belum Sudyrman)');
  ok((await one(`select game.city_open($1, 'empeer_depeer') o`, [pid])).o === false, 'em pe\'er de pe\'er tidak ada di peta lampau');

  // Masa lalu menolak koin
  await H.expectError(() => A.call('api_buy', ['ikn', 'beras', 1]), /Rajanya saja belum lahir/);
  await H.expectError(() => A.call('api_bankDeposit', [100]), /Rajanya saja belum lahir/);
  await H.expectError(() => A.call('api_acceptMission', ['ikn', 'x']), /tidak mengenal benderamu|Rajanya/);

  // Pelayaran tanpa bajak laut acak
  let any = false;
  for (let i = 0; i < 40; i++) { const e = (await one(`select game.voy_roll_encounter($1, 'joungjava') e`, [pid])).e; if (e) any = true; }
  ok(!any, 'tanpa bajak laut acak di masa lalu');
  await H.sql(`update game.ships set condition = 90 where player_id = $1`, [pid]);
  await A.call('api_setSail', ['joungjava']); await H.shiftTime(900000); await A.call('api_pollVoyage', []);
  s = await gs();
  ok(s.city.CityId === 'joungjava' && Number(s.ship.Condition) === 90, 'tiba tanpa kerusakan (' + s.ship.Condition + ')');
  ok(s.pasir.era === 'lampau', 'tetap di 40 Tahun Lalu');

  // Pustaka Agung (IKN)
  await H.expectError(() => act('beli_buku', 'bk_pa_angin'), /Pustaka Agung tidak ada/);
  await place('ikn');
  s = await gs();
  ok(Array.isArray(s.pasir.toko.pustaka) && s.pasir.toko.pustaka.length === 7, '7 buku di Pustaka Agung');
  const sail0 = Number((await one('select sailing from game.character_stats where player_id = $1', [pid])).sailing);
  await act('beli_buku', 'bk_pa_angin');
  ok(await gold() === 2000000 - 120000, 'harga 120.000 (emas ditimbang)');
  ok(Number((await one('select sailing from game.character_stats where player_id = $1', [pid])).sailing) === sail0 + 15, '+15 Sailing');
  await H.expectError(() => act('beli_buku', 'bk_pa_angin'), /sudah punya/);
  await H.expectError(() => act('beli_buku', 'bk_ps_kadet'), /tidak ada di rak/);
  await act('beli_buku', 'bk_pa_bintang');
  ok(Number((await gs()).ship.TravelMul) === 0.95, 'Peta Bintang: waktu tempuh -5%');
  // tidak muncul di Library biasa
  const lib = await A.call('api_getLibrary', []);
  ok(!lib.available.some(b => /^bk_p[as]_/.test(b.BookId || b.bookId || b.id || '')), 'Pustaka Agung tidak bocor ke Library biasa');

  // Dok Garuda (IKN) & Galangan Lembah (Sudyrman)
  ok(s.pasir.toko.dok_garuda.length === 3 && s.pasir.toko.lembah === null, 'Dok Garuda: 3 Pusaka');
  const sp0 = Number((await gs()).ship.Speed);
  await act('beli_pusaka', 'layar_garuda');
  await H.expectError(() => act('beli_pusaka', 'lunas_ulin'), /Lembah Seribu Layar/);
  await act('pasang', 'layar_garuda', '2');
  ok(Number((await gs()).ship.Speed) === sp0 + 10, 'Layar Sutra Garuda +10 kecepatan');

  // Benua Sudyrman
  await H.sql(`select game.admin_pasir('q12_ana', 'sudyrman', '1')`);
  s = await gs();
  ok(s.unlocks.length === 3 && s.pasir.kotaLampau.length === 3 && s.pasir.sudyrman, 'Benua Sudyrman muncul di peta lampau');
  await A.call('api_setSail', ['sudyrman_lembah']); await H.shiftTime(1800000); await A.call('api_pollVoyage', []);
  s = await gs();
  ok(s.city.CityId === 'sudyrman_lembah' && s.city.Name === 'Lembah Seribu Layar', 'tiba di Lembah Seribu Layar');
  ok(s.pasir.toko.lembah.length === 3, 'Galangan Lembah: 3 Pusaka');
  await act('beli_pusaka', 'lunas_ulin');
  await act('pasang', 'lunas_ulin', '3');
  ok(Number((await gs()).ship.EffectiveMaxCondition) === 160, 'Lunas Ulin Purba +60 kondisi maksimal');
  await act('beli_pusaka', 'kemudi_ikn').catch(() => {});
  await H.sql(`insert into game.pv_pusaka(player_id, pusaka_id, slot) values ($1, 'kemudi_ikn', null) on conflict do nothing`, [pid]);
  await act('pasang', 'kemudi_ikn', '2');
  const enc = (await one(`select game.voy_enc_book($1, '{"enemyDmgMul": 2}'::jsonb) e`, [pid])).e;
  ok(Number(enc.enemyDmgMul) === 1.8 && enc.pxKemudi, 'Kemudi Perunggu: kerusakan musuh -10%');
  const enc2 = (await one(`select game.voy_enc_book($1, $2::jsonb) e`, [pid, JSON.stringify(enc)])).e;
  ok(Number(enc2.enemyDmgMul) === 1.8, 'tidak bertumpuk tiap ronde');

  // Tarik Jangkar: kembali ke Zaman Keadilan
  await act('tarik');
  s = await gs();
  ok(s.pasir.era === 'keadilan' && s.city.CityId === 'empeer_depeer', 'kembali ke Jam Agung');
  ok(s.pasir.kotaLampau.length === 0 && s.unlocks.length === 1 && s.unlocks[0] === 'empeer_depeer', 'peta Zaman Keadilan lagi');
  ok((await one(`select game.city_open($1, 'sudyrman_lembah') o`, [pid])).o === false, 'Sudyrman tak ada di masa kini');

  // Ekonomi tidak berubah sedikit pun
  const market1 = await one(`select sum(current_price)::text p, sum(stock)::text s from game.market`);
  ok(market1.p === market0.p && market1.s === market0.s, 'harga & stok pasar tetap');

  // Toko masa lalu tutup selamanya
  await H.sql(`select game.admin_pasir('q12_ana', 'tutup', '1')`);
  ok((await gs()).pasir.zaman.length === 0, 'setelah ditutup: Jam Agung tidak lagi menunjuk masa lalu');

  console.log('0043 pasir lampau: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
