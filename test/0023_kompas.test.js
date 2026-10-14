// Saga 2 · Quest 5 "Kompas yang Berputar": pemicu (5 hari game + bank 1 juta) -> badai ke TooGood ->
// adu gasing dwi -> 3 pelayaran tersesat ke pulau acak -> Jaring Angin -> Marie Regal -> Marlya ->
// jaminan IKN -> jujur/bohong -> perbaikan kutub -> Kompas Tedsky; krisis pasar per pemain.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('kompas1'); await u.call('api_createCharacter', ['Penjinak Kutub', 'merchant']);
  const pid = u.id;
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [pid]))[0].gold);
  const city = async () => (await H.sql('select city_id from game.player_location where player_id = $1', [pid]))[0].city_id;
  const kp = a => u.call('api_kompas', a);
  const st = async () => (await u.call('api_getGameState', [null])).kompas;
  const fightOut = async () => {
    for (let i = 0; i < 120; i++) {
      const s = await u.call('api_getGameState', [null]);
      if (!s.voyage.inTransit || !s.voyage.encounterPending) return;
      await H.sql('update game.ships set condition = greatest(condition, 90) where player_id = $1', [pid]);
      await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '1'::jsonb) where player_id = $1`, [pid]);
      const fr = await u.call('api_resolveCombat', ['fire']);
      if (fr.ongoing && fr.encounter && fr.encounter.ammoRemaining === 0) await u.call('api_resolveCombat', ['reload']);
    }
  };
  const sail = async dest => { await u.call('api_setSail', [dest]); await H.shiftTime(400000); const s = await u.call('api_getGameState', [null]); await fightOut(); return s; };
  const priceMul = async (c, comm) => Number((await H.sql('select game.quest_price_mul($1, $2, $3) m', [pid, c, comm]))[0].m);
  const role = async (c, comm) => (await H.sql('select role from game.market where city_id = $1 and commodity_id = $2', [c, comm]))[0].role;

  await H.sql('update game.players set gold = 300000 where player_id = $1', [pid]);

  // --- Prasyarat ------------------------------------------------------------
  assert((await st()) === null, 'tersembunyi sebelum Quest 4 selesai');
  await H.expectError(() => kp(['marlya']), /masih menunjuk utara/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at) values
    ($1, 'gala', 6, now()), ($1, 'toogood', 10, now()), ($1, 'warwerwor', 12, now()), ($1, 'barsati', 16, now())`, [pid]);
  let s = await st();
  assert(s && s.step === 0 && s.eligible && !s.timeOk && !s.ready && s.readyInMs > 0 && s.bankNeed === 1000000, 'menunggu 5 hari game ' + JSON.stringify(s));
  await go('skitraw'); s = await sail('joungjava');
  assert((await city()) === 'joungjava' && (await st()).step === 0, 'belum terpicu sebelum 5 hari game');
  await H.sql(`update game.player_quests set done_at = now() - (5.1 * game.cfg_num('GameDayLengthRealMinutes', 60) || ' minutes')::interval where player_id = $1 and quest_id = 'barsati'`, [pid]);
  s = await st(); assert(s.timeOk && !s.bankOk && !s.ready, 'waktu cukup, bank belum');
  await go('skitraw'); await sail('joungjava');
  assert((await st()).step === 0, 'saldo bank < 1 juta -> tidak terpicu');
  await H.sql('update game.players set bank_balance = 1000000 where player_id = $1', [pid]);
  s = await st(); assert(s.ready && s.bankOk, 'siap ' + JSON.stringify(s));

  // --- Babak 1: badai ke TooGood ------------------------------------------------
  await go('skitraw');
  await u.call('api_setSail', ['sunda_empire']);
  s = await st(); assert(s.step === 1 && s.chosen === 'sunda_empire', 'badai terpicu saat berangkat');
  await H.shiftTime(400000);
  let gs = await u.call('api_getGameState', [null]);
  assert(!gs.voyage.inTransit && (await city()) === 'toogood', 'terdampar di TooGood ' + JSON.stringify(gs.voyage));
  s = gs.kompas;
  assert(s.step === 2 && s.redirect.kind === 'storm' && s.redirect.city === 'toogood' && s.redirect.from === 'sunda_empire', 'redirect badai');
  assert(s.crisis === 1, 'krisis pasar mulai');
  await H.sql('update game.players set bank_balance = 0 where player_id = $1', [pid]); // saldo boleh turun setelah mulai

  // --- Krisis pasar per pemain -------------------------------------------------
  for (const [c, comm] of [['joungjava', 'beras'], ['sunda_empire', 'kopi'], ['skitraw', 'besi']]) {
    const r = await role(c, comm), m = await priceMul(c, comm);
    assert(r === 'produce' ? Math.abs(m - 0.85) < 1e-9 : r === 'consume' ? Math.abs(m - 1.25) < 1e-9 : Math.abs(m - 1.15) < 1e-9, `krisis ${c}/${comm} ${r} ${m}`);
  }
  const other = await H.user('kompas2'); await other.call('api_createCharacter', ['Pedagang Lain', 'merchant']);
  assert(Number((await H.sql(`select game.quest_price_mul($1, 'joungjava', 'beras') m`, [other.id]))[0].m) === 1, 'pemain lain tidak terkena krisis');

  // --- Adu gasing dwi -------------------------------------------------------------
  await go('skitraw'); await H.expectError(() => kp(['gasing', 'won']), /Black's Alley, TooGood/);
  await go('toogood'); await H.expectError(() => kp(['gasing', 'seri']), /tidak dikenal/);
  await H.expectError(() => kp(['marlya']), /menelusuri arsip/);
  let g0 = await gold();
  let r = await kp(['gasing', 'won']);
  assert(r.kompas.step === 3 && r.kompas.gasing === 'won' && r.kompas.lost === 0 && (await gold()) === g0 + 2000, 'gasing menang +2.000');
  await H.expectError(() => kp(['gasing', 'won']), /sibuk/);
  await H.expectError(() => kp(['wind', 'ok']), /bertiup biasa/);

  // --- Babak 2: tiga pelayaran tersesat ---------------------------------------------
  const seen = [];
  for (let i = 1; i <= 3; i++) {
    const from = await city();
    const dest = from === 'joungjava' ? 'sunda_empire' : 'joungjava';
    await sail(dest);
    const to = await city(); s = await st();
    assert(to !== dest && to !== from && to !== 'toogood' && to !== 'marie_regal', `tersesat #${i}: ${from}->${dest} tiba ${to}`);
    assert(s.lost === i && s.redirect.kind === 'lost' && s.redirect.n === i && s.redirect.city === to && s.redirect.from === dest, 'jejak tersesat ' + JSON.stringify(s));
    seen.push(to);
  }
  s = await st(); assert(s.windDue && !s.wind && !s.windHold, 'pelayaran ke-4 akan butuh Jaring Angin');
  const here = await city(), dest4 = here === 'skitraw' ? 'joungjava' : 'skitraw';
  // Berangkat tidak ditolak lagi (Jaring Angin dimainkan di laut, sesaat sebelum tiba)
  await H.expectError(() => kp(['wind', 'ok']), /di tengah laut/);
  await u.call('api_setSail', [dest4]);
  s = await st(); assert(s.windHold && s.chosen === dest4, 'di laut: menunggu Jaring Angin ' + JSON.stringify(s));
  await H.shiftTime(400000);
  gs = await u.call('api_getGameState', [null]);
  assert(gs.voyage.inTransit && gs.voyage.etaSeconds === 0 && !gs.voyage.encounterPending, 'kapal tertahan di detik kedatangan ' + JSON.stringify(gs.voyage));
  await u.call('api_pollVoyage', []);
  assert((await u.call('api_getGameState', [null])).voyage.inTransit, 'pollVoyage tidak mendaratkan kapal tanpa Jaring Angin');
  await H.expectError(() => kp(['wind', 'hebat']), /tidak dikenal/);
  r = await kp(['wind', 'perfect']); assert(r.kompas.wind && !r.kompas.windHold, 'angin terjaring di laut');
  gs = await u.call('api_getGameState', [null]);
  s = gs.kompas;
  assert(!gs.voyage.inTransit && (await city()) === 'marie_regal' && s.step === 4 && s.redirect.kind === 'wind' && !s.wind, 'mendarat di Marie Regal ' + JSON.stringify(s));

  // Cadangan: pemain lain yang tidak memainkan Jaring Angin tetap mendarat setelah 10 menit
  const v = await H.user('kompas3'); await v.call('api_createCharacter', ['Kapten Lupa', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'kompas', 3, '{"lost": 3}')`, [v.id]);
  await H.sql(`update game.player_location set city_id = 'skitraw' where player_id = $1`, [v.id]);
  await v.call('api_setSail', ['joungjava']);
  await H.shiftTime(400000);
  assert((await v.call('api_getGameState', [null])).voyage.inTransit, 'kapal lain tertahan');
  await H.shiftTime(11 * 60000);
  const gv = await v.call('api_getGameState', [null]);
  assert(!gv.voyage.inTransit && gv.kompas.step === 4 && (await H.sql('select city_id from game.player_location where player_id = $1', [v.id]))[0].city_id === 'marie_regal', 'setelah 10 menit tetap mendarat di Marie Regal');

  // --- Babak 3: Marlya ----------------------------------------------------------------
  r = await kp(['marlya']); assert(r.kompas.step === 5, 'Marlya');
  await H.expectError(() => kp(['marlya']), /menelusuri arsip/);
  // navigasi kembali normal untuk pelayaran biasa
  await sail('ikn'); assert((await city()) === 'ikn', 'pelayaran ke IKN tepat sasaran');

  // --- Babak 4: jaminan & kabar dunia ---------------------------------------------------
  await H.sql('update game.players set gold = 1000 where player_id = $1', [pid]);
  await H.expectError(() => kp(['bail']), /Jaminan 50.000/);
  await H.sql('update game.players set gold = 120000 where player_id = $1', [pid]);
  await H.expectError(() => kp(['answer', 'jujur']), /tidak sedang bertanya/);
  r = await kp(['bail']);
  assert(r.kompas.step === 6 && r.kompas.bailPaid && (await gold()) === 70000, 'jaminan dibayar');
  await H.expectError(() => kp(['answer', 'mungkin']), /jujur atau bohong/);
  r = await kp(['answer', 'bohong']);
  assert(r.kompas.step === 7 && r.kompas.truth === 'bohong', 'pilihan tersimpan');

  // --- Babak 5: perbaikan kutub -----------------------------------------------------------
  await H.expectError(() => kp(['repair', '90']), /Marie Regal/);
  await sail('marie_regal'); assert((await city()) === 'marie_regal', 'Tedsky membaca bintang');
  g0 = await gold();
  r = await kp(['repair', '92']);
  assert(r.kompas.done && r.kompas.step === 8 && r.kompas.compass && r.rewards.gold === 150000 && (await gold()) === g0 + 150000, 'selesai ' + JSON.stringify(r));
  assert(Number((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = 'qi_kompas_tedsky'`, [pid]))[0].qty) === 1, 'Kompas Tedsky di inventori');
  await H.expectError(() => kp(['repair', '92']), /Belum ada/);

  // --- Krisis mereda dalam 3 hari game ------------------------------------------------------
  assert((await st()).crisis > 0.99, 'krisis masih penuh tepat setelah selesai');
  await H.sql(`update game.player_quests set done_at = now() - (1.5 * game.cfg_num('GameDayLengthRealMinutes', 60) || ' minutes')::interval where player_id = $1 and quest_id = 'kompas'`, [pid]);
  const half = (await st()).crisis; assert(half > 0.4 && half < 0.6, 'krisis separuh ' + half);
  await H.sql(`update game.player_quests set done_at = now() - (3.1 * game.cfg_num('GameDayLengthRealMinutes', 60) || ' minutes')::interval where player_id = $1 and quest_id = 'kompas'`, [pid]);
  assert((await st()).crisis === 0 && (await priceMul('joungjava', 'beras')) === 1, 'krisis berakhir');

  // --- Tidak terulang -------------------------------------------------------------------------
  await H.sql('update game.players set bank_balance = 2000000 where player_id = $1', [pid]);
  await sail('skitraw'); assert((await city()) === 'skitraw' && (await st()).step === 8, 'quest sekali seumur hidup');

  console.log('KOMPAS TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
