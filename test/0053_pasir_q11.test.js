// Tide v41 · Pasir Batch 3 — Quest 11 "Kapal yang Tak Pernah Terdampar": surat Paman Ocid, jalan ke em pe'er de pe'er,
// biaya & Tempa Jangkar Waktu (Pusaka), Selam, lompatan ke Tahun Badai Besar, Gala muda (riak, Retak), kapal hantu, kembali.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const A = await H.user('q11_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5),($1,'tigasilang',12),($1,'gala',6)`, [pid]);
  // Q10 sudah tamat: harta di potret, Zaman Keadilan
  await H.sql(`update game.players set gold = 777777, bank_balance = 55555 where player_id = $1`, [pid]);
  await H.sql(`select game.pasir_ensure($1)`, [pid]);
  await H.sql(`select game.pv_ambil($1, 'sunda_empire')`, [pid]);
  await H.sql(`update game.pasir_state set data = data || '{"buka": []}'::jsonb, kaca = 1 where player_id = $1`, [pid]);
  await H.sql(`select game.ps_set($1, 'ps10', 11, '{}'::jsonb, true)`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const setGold = (g) => H.sql('update game.players set gold = $2 where player_id = $1', [pid, g]);

  // --- Pemicu: surat hanya bila gold >= 100.000 ---
  let s = await gs();
  ok(s.pasir.era === 'keadilan' && s.pasir.q['11'] === 0, 'gold 5.000: belum ada surat');
  ok(!s.unlocks.includes('empeer_depeer'), 'em pe\'er de pe\'er belum terbuka');
  await setGold(100000);
  s = await gs();
  ok(s.pasir.q11 && s.pasir.q11.step === 1, 'gold 100.000: surat Paman Ocid (langkah 1)');
  ok(Array.isArray(s.pasir.pusaka) && s.pasir.pusaka.length === 0, 'belum punya Pusaka');

  // --- Pustaka Sunda: jalan ke em pe'er de pe'er ---
  await place('joungjava');
  await H.expectError(() => act('mulai11'), /Pustaka Sunda/);
  await place('sunda_empire');
  await act('mulai11');
  s = await gs();
  ok(s.pasir.q11.step === 2, 'langkah 2');
  ok(s.unlocks.length === 1 && s.unlocks[0] === 'empeer_depeer', 'hanya em pe\'er de pe\'er yang terbuka: ' + JSON.stringify(s.unlocks));
  ok((await one(`select game.city_open($1, 'paradiso') o`, [pid])).o === false, 'Paradiso tetap tertutup');

  await setGold(99999);
  await H.expectError(() => act('bayar11'), /Kumpulkan dulu/);
  await setGold(150000);
  await act('bayar11');
  ok(await gold() === 50000, 'biaya Jangkar 100.000 dibayar');
  ok((await gs()).pasir.q11.step === 3, 'langkah 3');

  // --- Selam Mutiara di em pe'er de pe'er ---
  await H.expectError(() => act('selam11', 'ok'), /em pe'er de pe'er/);
  await place('empeer_depeer');
  await act('selam11', 'gagal');
  await H.expectError(() => act('selam11', 'ok'), /Istirahat/);
  await H.sql(`update game.player_quests set data = data - 'selamRest' where player_id = $1 and quest_id = 'ps11'`, [pid]);
  await act('selam11', 'ok');
  ok((await gs()).pasir.q11.step === 4, 'roda gigi diangkat');

  // --- Tempa Jangkar ---
  await H.expectError(() => act('tempa11', '95', '2000'), /dipanaskan/);
  let r = await act('tempa11', '30', '12000');
  ok(r.ok === false && r.pasir.q11.step === 4, 'jangkar retak: coba lagi');
  r = await act('tempa11', '75', '12000');
  ok(r.ok && r.grade === 'baik', 'mutu baik');
  s = await gs();
  ok(s.pasir.q11.step === 5 && s.pasir.pusaka.length === 1 && s.pasir.pusaka[0].id === 'jangkar' && s.pasir.pusaka[0].slot === 1 && s.pasir.pusaka[0].mutu === 'baik', 'Jangkar Waktu terpasang di slot 1');
  ok((await one(`select game.has_effect($1, 'px_jangkar') e`, [pid])).e === true, 'efek Pusaka lewat has_effect');
  ok(s.pasir.zaman.includes('badai'), 'Jam Agung menunjuk Tahun Badai Besar');

  // Pusaka: lepas & pasang
  await act('lepas', 'jangkar');
  ok((await one(`select game.has_effect($1, 'px_jangkar') e`, [pid])).e === false, 'dilepas: efek hilang');
  await H.expectError(() => act('lompat', 'badai'), /Pasang Jangkar/);
  await act('pasang', 'jangkar', '2');
  ok((await gs()).pasir.pusaka[0].slot === 2, 'dipasang di slot 2');
  await H.expectError(() => act('pasang', 'layar_garuda', '1'), /bukan milikmu/);

  // --- Lompatan ---
  await place('sunda_empire');
  await H.expectError(() => act('lompat', 'badai'), /Jam Agung ada di/);
  await place('empeer_depeer');
  await H.expectError(() => act('lompat', 'lampau'), /tidak mau menunjuk/);
  await act('lompat', 'badai');
  s = await gs();
  ok(s.pasir.era === 'badai' && s.pasir.tone === 'sepia' && s.city.CityId === 'skitraw', 'Tahun Badai Besar di Skitraw');
  ok(s.pasir.q11.step === 6, 'langkah 6');
  ok((await one('select game.ww_market_closed($1) c', [pid])).c === true, 'pasar masa lalu tutup');
  await H.expectError(() => A.call('api_setSail', ['joungjava']), /tak ada yang berlayar/);
  await H.expectError(() => act('lepas', 'jangkar'), /tidak akan pernah pulang/);

  // --- Gala muda ---
  await H.expectError(() => act('gala11', 'bantu'), /Aksi tidak dikenal/);
  r = await act('tambal11', '20', '9000');
  ok(r.ok === false, 'tambalan retak: ulang');
  await act('tambal11', '60', '9000');
  await act('gala11', 'cerita');
  s = await gs();
  ok(s.pasir.riak.gala_muda === 'cerita' && s.pasir.retak === 15, 'riak gala_muda=cerita, Retak +15');
  ok(!s.pasir.barang.includes('sabun_gala'), 'tanpa sabun');

  // --- Kapal hantu & kembali ---
  await act('kejar11', '1');
  s = await gs();
  ok(s.pasir.era === 'keadilan' && s.city.CityId === 'empeer_depeer' && s.pasir.kaca === 2 && s.pasir.sorot === true, 'kembali ke Zaman Keadilan, kaca kedua retak, lampu sorot');
  ok((await one('select game.ww_market_closed($1) c', [pid])).c === false, 'pasar Zaman Keadilan buka');
  const g0 = await gold();
  await act('paham11');
  s = await gs();
  ok(s.pasir.q11.step === 10 && s.pasir.q11.done, 'Quest 11 selesai');
  ok(await gold() === g0 + 100000, 'hadiah 100.000');
  ok(s.pasir.jangkarMs > 0, 'Jangkar didinginkan');
  ok(s.pasir.zaman.length === 1 && s.pasir.zaman[0] === 'lampau', 'Jam Agung kini menunjuk 40 Tahun Lalu');

  // --- Retak turun di Zaman Keadilan ---
  await H.sql(`update game.pasir_state set data = data || jsonb_build_object('retak_t', game.now_ms() - game.ww_day_ms() * 2) where player_id = $1`, [pid]);
  s = await gs();
  ok(s.pasir.retak === 3, 'Retak turun 6/hari (mutu baik): ' + s.pasir.retak);

  // Retak 100 di masa lalu = terlempar
  await H.sql(`update game.pasir_state set era = 'lampau', retak = 95 where player_id = $1`, [pid]);
  await place('ikn');
  ok((await one('select game.ps_retak_add($1, 10) t', [pid])).t === true, 'Retak 100: terlempar');
  s = await gs();
  ok(s.pasir.era === 'keadilan' && s.city.CityId === 'empeer_depeer' && s.pasir.jangkarMs > 3600000, 'terlempar ke Jam Agung, Jangkar dingin sehari');

  // --- Pilihan lain: sabun ---
  const B = await H.user('q11_budi');
  await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [B.id]);
  await H.sql(`select game.pasir_ensure($1)`, [B.id]);
  await H.sql(`update game.pasir_state set era = 'badai' where player_id = $1`, [B.id]);
  await H.sql(`select game.ps_set($1, 'ps11', 7, '{}'::jsonb)`, [B.id]);
  await B.call('api_pasir', ['gala11', 'bantu']);
  const sb = await B.call('api_getGameState', []);
  ok(sb.pasir.barang.includes('sabun_gala') && sb.pasir.retak === 0 && sb.pasir.riak.gala_muda === 'bantu', 'bantu: Sabun Kelapa Buatan Gala Muda, tanpa Retak');

  // Kerahasiaan: pemain tanpa Q9 tidak melihat apa pun
  const C = await H.user('q11_cici');
  await C.call('api_createCharacter', ['Kapten Cici', 'merchant']);
  await H.sql(`update game.players set gold = 500000 where player_id = $1`, [C.id]);
  ok(!('pasir' in await C.call('api_getGameState', [])), 'pemain biasa: tanpa key pasir');
  await H.expectError(() => C.call('api_pasir', ['pasang', 'jangkar', '1']), /Aksi tidak dikenal/);

  // Pulih: Pusaka tetap milik pemain
  await H.sql(`select game.admin_pasir('q11_ana', 'pulih')`);
  ok((await one(`select count(*)::int n from game.pv_pusaka where player_id = $1`, [pid])).n === 1, 'Pusaka tetap setelah pulih');

  console.log('0053 pasir q11: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
