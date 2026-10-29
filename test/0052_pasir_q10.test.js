// Tide v41 · Pasir Batch 2 — Quest 10 "Penumpang Bergaun Putih": pemicu, titipan, pelayaran bersama,
// perpisahan, lonceng Jam Agung, pencurian, Hari Pertama, Tur Bukti, Paman Ocid; kisah lama tertutup.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const night = (on) => H.db.exec(`create or replace function game.fish_is_night() returns boolean language sql stable as $$ select ${on ? 'true' : 'false'} $$`);
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const A = await H.user('q10_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5),($1,'tigasilang',12),($1,'gala',6),($1,'toogood',10),($1,'warwerwor',13)`, [pid]);
  await H.sql(`update game.players set gold = 612345, bank_balance = 123457 where player_id = $1`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const q10 = async () => (await gs()).pasir.q10;
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const sailTo = async (dest) => { await A.call('api_setSail', [dest]); await H.shiftTime(900000); return A.call('api_pollVoyage', []); };

  // --- Pemicu: hanya di IKN saat malam ---
  await night(true);
  let s = await gs();
  ok(!('pasir' in s), 'di Sunda: belum ada apa-apa');
  await place('ikn'); await night(false);
  s = await gs();
  ok(!('pasir' in s), 'IKN siang: belum terpicu');
  await night(true);
  s = await gs();
  ok(s.pasir && s.pasir.era === 'kini' && s.pasir.q10.step === 1, 'IKN malam: Quest 10 langkah 1');
  ok(s.gala !== null && s.toogood !== null, 'masih di masa kini: kisah lama utuh');

  await H.expectError(() => act('terima'), /Aksi tidak dikenal/);   // Mata Pesta dulu
  await act('pesta');
  await act('terima');
  ok((await q10()).step === 2, 'titipan diterima');

  // --- Pelayaran bersama (diam, tanpa bajak laut) & bayaran ---
  const gold0 = Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const pv = await sailTo('empeer_depeer');
  s = await gs();
  ok(s.pasir.q10.step === 4, 'tiba di em pe\'er de pe\'er: langkah 4 (' + s.pasir.q10.step + ')');
  ok(!s.voyage.inTransit && s.city.CityId === 'empeer_depeer', 'merapat di em pe\'er de pe\'er');
  const gold1 = Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  ok(gold1 >= gold0 + 20000 - 1000, 'bayaran 20.000 gold diterima');
  ok(!('bayar' in s.pasir.q10.d), 'angka bayaran tidak dikirim di data quest');
  await H.expectError(() => act('pisah', 'a'), /Aksi tidak dikenal/);   // jawab dulu
  await act('jawab', 'pernah');
  s = await gs();
  ok(s.pasir.riak.jawab_malam === 'pernah', 'riak jawab_malam tersimpan');
  await act('pisah', 'tangga');
  ok((await q10()).step === 5, 'bebas di pulau');

  // --- Set sail berikutnya: lonceng Jam Agung ---
  await H.expectError(() => A.call('api_setSail', ['sunda_empire']), /Lonceng Jam Agung/);
  await act('jam');
  ok((await q10()).step === 6, 'adegan 999 anak tangga');
  await H.expectError(() => A.call('api_setSail', ['sunda_empire']), /Jam Agung masih berdentang/);

  // --- Pencurian ---
  await act('curi');
  s = await gs();
  ok(s.pasir.era === 'keadilan' && s.pasir.tone === 'dingin' && s.pasir.q10.step === 7, 'Zaman Keadilan');
  ok(s.player.gold === 5000 && s.city.CityId === 'sunda_empire', '5.000 gold, bangun di Sunda Empire');
  ok(s.pasir.kaca === 1, 'satu kaca retak');
  for (const k of ['gala', 'toogood', 'warwerwor', 'barsati', 'kompas', 'cocoepan', 'tigasilang', 'limatangan', 'duatangan', 'gotong', 'pacu']) ok(s[k] === null, 'kisah lama null: ' + k);
  ok(Array.isArray(s.unlocks) && s.unlocks.length === 0, 'peta awal');
  ok(!/612345|632345|123457/.test(JSON.stringify(s)), 'angka harta lama tidak muncul');
  ok((await one('select game.toogood_freed($1) f', [pid])).f === false, 'TooGood tidak merdeka');
  ok((await one(`select game.heal_city($1, 'paradiso') h`, [pid])).h === false, 'kota pemulih mati');
  ok((await one(`select game.quest_boss_encounter($1, 'toogood') e`, [pid])).e === null, 'bos kisah lama tidak muncul');

  // Gerbang: endpoint kisah lama & Pacu Dagang ditolak
  const gate = async (fn) => {
    await H.db.query(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.path', $2, false)`, [pid, '/rpc/' + fn]);
    try { await H.db.query('select public.mt_pre_request()'); return null; } catch (e) { return e.message; }
  };
  ok(/mengenal kisah itu/.test(await gate('api_galaquest') || ''), 'api_galaQuest ditolak');
  ok(/mengenal kisah itu/.test(await gate('api_duatangan') || ''), 'api_duatangan ditolak');
  ok(/Dewan Pajak Keadilan/.test(await gate('api_pacu') || ''), 'api_pacu ditolak dengan alasan cerita');
  ok(await gate('api_getgamestate') === null, 'endpoint lain lolos');
  ok(await gate('api_pasir') === null, 'api_pasir lolos');

  await H.expectError(() => act('catatan'), /Aksi tidak dikenal/);
  await act('paham');
  await act('catatan');
  ok((await q10()).step === 9, 'Tur Bukti dimulai');

  // --- Tur Bukti ---
  ok((await one(`select game.quest_arrival_redirect($1, 'sunda_empire', 'toogood') r`, [pid])).r.quiet === true, 'TooGood: Mr. GAP membiarkan lewat');
  await H.sql(`select game.ps_on_arrive($1, 'skitraw')`, [pid]);
  s = await gs();
  ok(s.pasir.q10.d.bukti.skitraw && !s.pasir.q10.d.bukti.laut, 'bukti Skitraw');
  await H.sql(`select game.ps_on_arrive($1, 'joungjava')`, [pid]);
  ok(!(await q10()).d.bukti.laut, 'baru 1 bukti: kapal putih belum lewat');
  await H.sql(`select game.ps_on_arrive($1, 'toogood')`, [pid]);
  ok((await q10()).d.bukti.toogood && !(await q10()).d.bukti.laut, 'bukti TooGood');
  ok((await one(`select game.quest_arrival_redirect($1, 'sunda_empire', 'toogood') r`, [pid])).r === null, 'TooGood kedua: kembali normal (bajak laut)');
  await H.sql(`select game.ps_on_arrive($1, 'sunda_empire')`, [pid]);
  ok((await q10()).d.bukti.laut && (await q10()).step === 9, 'pelayaran setelah 2 bukti: kapal putih');
  await H.sql(`select game.ps_on_arrive($1, 'ikn')`, [pid]);
  ok((await q10()).step === 10, 'bukti lengkap -> Paman Ocid');
  await place('ikn');
  await H.expectError(() => act('ocid'), /Pustaka Sunda/);
  await place('sunda_empire');
  await act('ocid');
  s = await gs();
  ok(s.pasir.q10.step === 11 && s.pasir.q10.done, 'Quest 10 selesai');
  ok(s.pasir.era === 'keadilan', 'tetap di Zaman Keadilan');

  // Pemain lain tanpa Q9 tidak terpicu
  const B = await H.user('q10_budi');
  await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  await H.sql(`update game.player_location set city_id = 'ikn' where player_id = $1`, [B.id]);
  ok(!('pasir' in await B.call('api_getGameState', [])), 'belum tamat Q9: tidak terpicu');

  // Kembali ke masa kini (GM pulih): kisah lama kembali
  await H.sql(`select game.admin_pasir('q10_ana', 'pulih')`);
  s = await gs();
  ok(s.pasir.era === 'kini' && s.gala !== null && s.unlocks.includes('paradiso'), 'pulih: kisah & peta lama kembali');
  ok((await one('select game.toogood_freed($1) f', [pid])).f === true, 'TooGood merdeka lagi');
  ok(await gate('api_galaquest') === null, 'gerbang terbuka lagi');

  console.log('0052 pasir q10: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
