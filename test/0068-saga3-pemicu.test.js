// Tide v52 · Uji rantai pemicu Saga 3 dari ujung ke ujung (konfigurasi produksi: PasirOpen = 1).
// Sumbangan nyata (api_gotong) menyelesaikan Restorasi IKN -> bendera dunia 'saga3' -> Saga 3 aktif
// hanya untuk pemain non-GM yang sudah tamat Saga 2 -> Quest 10 terpicu di IKN saat malam.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const night = (on) => H.db.exec(`create or replace function game.fish_is_night() returns boolean language sql stable as $$ select ${on ? 'true' : 'false'} $$`);
  const cfg = (k, v) => H.sql(`insert into game.config(key, value) values ($1, $2) on conflict (key) do update set value = excluded.value`, [k, v]);
  await cfg('PasirOpen', '1');
  await cfg('GotongOpen', '1');
  await cfg('FiturPenguji', '');
  const place = (id, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [id, c]);
  const aktif = async (id) => (await one('select game.pasir_aktif($1) a', [id])).a;
  const flag = async () => (await one(`select game.world_flag('saga3') f`)).f;

  // V = veteran Saga 2, N = belum tamat Saga 2, D = penyumbang biasa
  const V = await H.user('s3_veteran'); await V.call('api_createCharacter', ['Kapten Veteran', 'merchant']);
  const N = await H.user('s3_baru'); await N.call('api_createCharacter', ['Kapten Baru', 'merchant']);
  const D = await H.user('s3_dermawan'); await D.call('api_createCharacter', ['Kapten Dermawan', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'gala',6),($1,'toogood',10),($1,'warwerwor',12),($1,'barsati',16),($1,'kompas',8),($1,'cocoepan',11),($1,'tigasilang',12),($1,'limatangan',10),($1,'duatangan',5)`, [V.id]);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',4)`, [N.id]);

  // --- Sebelum Restorasi selesai: tertutup untuk semua, tanpa jejak ---
  ok(!(await flag()), 'awal: belum ada bendera saga3');
  ok(!(await aktif(V.id)) && !(await aktif(N.id)), 'awal: Saga 3 belum aktif');
  await place(V.id, 'ikn'); await night(true);
  let s = await V.call('api_getGameState', []);
  ok(!('pasir' in s), 'veteran di IKN malam sebelum Restorasi selesai: tidak ada key pasir');
  await H.expectError(() => V.call('api_pasir', ['status']), /Aksi tidak dikenal/);

  // --- Kolam hampir penuh: tahap 4 selesai, kurang 1 juta untuk Menara Cahaya ---
  const goal = Number((await one(`select sum((e ->> 'need')::bigint) g from game.gr_projects, jsonb_array_elements(stages) e where id = 'ikn'`)).g);
  await H.sql(`update game.gr_projects set total = $1, stage = 4, done_at = null where id = 'ikn'`, [goal - 1000000]);
  await place(D.id, 'ikn');
  await H.sql(`update game.players set gold = 5000000 where player_id = $1`, [D.id]);
  await D.call('api_gotong', ['sumbang', 999000]);
  ok(!(await flag()), 'kurang 1.000 gold: bendera belum menyala');
  await D.call('api_gotong', ['sumbang', 2000000]);   // lewat dari target juga tidak apa-apa
  const g = await one(`select stage, done_at from game.gr_projects where id = 'ikn'`);
  ok(g.stage === 5 && g.done_at, 'Restorasi IKN selesai (tahap 5)');
  ok(await flag(), 'bendera dunia saga3 menyala');
  const chats = await H.sql(`select msg ->> 'tx' tx from game.mp_chat`);
  ok(chats.some((c) => /Menara Cahaya/.test(c.tx)), 'chat tahap Menara Cahaya tetap muncul seperti biasa');
  ok(!chats.some((c) => /saga|pasir|waktu|kaca/i.test(c.tx)), 'tidak ada chat yang membocorkan pemicu');
  const inb = await H.sql(`select item::text t from game.mp_inbox`);
  ok(!inb.some((r) => /saga|pasir/i.test(r.t)), 'tidak ada inbox yang membocorkan pemicu');
  await H.expectError(() => D.call('api_gotong', ['sumbang', 1000000]), /sudah selesai/);
  ok(await flag(), 'sumbangan setelah selesai ditolak, bendera tetap');

  // --- Sesudah: aktif hanya untuk veteran Saga 2 ---
  ok(await aktif(V.id), 'veteran Saga 2: Saga 3 aktif');
  ok(!(await aktif(N.id)), 'belum tamat Saga 2: tetap tertutup');
  ok(!(await aktif(D.id)), 'penyumbang tanpa Saga 2: tetap tertutup');
  await place(N.id, 'ikn');
  s = await N.call('api_getGameState', []);
  ok(!('pasir' in s), 'pemain belum tamat Saga 2 di IKN malam: tidak terpicu');

  // Veteran: Quest 10 terpicu saat merapat di IKN malam hari
  await place(V.id, 'sunda_empire');
  s = await V.call('api_getGameState', []);
  ok(!('pasir' in s), 'veteran di luar IKN: belum terpicu');
  await place(V.id, 'ikn'); await night(false);
  s = await V.call('api_getGameState', []);
  ok(!('pasir' in s), 'veteran di IKN siang: belum terpicu');
  await night(true);
  s = await V.call('api_getGameState', []);
  ok(s.pasir && s.pasir.era === 'kini' && s.pasir.q10 && s.pasir.q10.step === 1, 'veteran di IKN malam: Quest 10 langkah 1');
  ok(!('gm' in s.pasir), 'pemain biasa tidak menerima bendera gm');
  const st = await V.call('api_pasir', ['status']);
  ok(st && st.pasir, 'api_pasir status berjalan');

  // Pemain yang menamatkan Saga 2 SETELAH Restorasi selesai juga bisa ikut
  await H.sql(`update game.player_quests set step = 5 where player_id = $1 and quest_id = 'duatangan'`, [N.id]);
  ok(await aktif(N.id), 'tamat Saga 2 belakangan: Saga 3 ikut terbuka');
  s = await N.call('api_getGameState', []);
  ok(s.pasir && s.pasir.q10 && s.pasir.q10.step === 1, 'tamat belakangan: Quest 10 terpicu di IKN malam');

  console.log('0068 pemicu Saga 3: semua lulus');
  process.exit(0);
})().catch((e) => { console.error('GAGAL:', e && e.message || e); process.exit(1); });
