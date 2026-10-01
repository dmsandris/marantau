// Misi Pembebasan TooGood: surat gubernur -> Tedsky -> diburu -> kode sandi -> Black Pearl -> Tedsky ditangkap -> TooGood merdeka.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('pembebas'); await u.call('api_createCharacter', ['Sang Pembebas', 'explorer']);
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  const tg = a => u.call('api_toogoodQuest', a);
  const clock = f => H.sql(`select game.cfg_set('WorldStartTimestamp', (game.now_ms() - ($1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint)::text)`, [f]);
  const winFight = async () => {
    await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '1') where player_id = $1`, [u.id]);
    let fr;
    for (let i = 0; i < 40; i++) {
      await H.sql('update game.ships set condition = greatest(condition, 90) where player_id = $1', [u.id]);
      fr = await u.call('api_resolveCombat', ['fire']); if (!fr.ongoing) break;
      if (fr.encounter.ammoRemaining === 0) await u.call('api_resolveCombat', ['reload']);
    }
    return fr;
  };

  let s = await u.call('api_getGameState', [null]);
  assert(s.toogood === null, 'belum tersedia sebelum misi Uda Gala');
  await go('toogood');
  await H.expectError(() => tg(['accept']), /belum mengenalmu/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6)`, [u.id]);
  s = await u.call('api_getGameState', [null]);
  assert(s.toogood && s.toogood.step === 0, 'tersedia setelah Uda Gala ' + JSON.stringify(s.toogood));
  let r = await tg(['accept']); assert(r.toogood.step === 1, 'terima');
  await H.expectError(() => tg(['accept']), /sudah berjanji/);
  await H.expectError(() => tg(['gov']), /Tidak ada gubernur/);

  // Sunda Empire: 8 Emas + 4 Gaharu (barang premium)
  await go('sunda_empire');
  r = await tg(['gov']); assert(r.taskAccepted === 'sunda_empire', 'tugas diterima');
  assert(r.toogood.govs.sunda_empire && !r.toogood.govs.skitraw, 'permintaan hanya terlihat setelah didengar');
  await H.expectError(() => tg(['gov']), /menunggu: 8 Emas \(baru 0\), 4 Gaharu \(baru 0\)/);
  await H.sql(`select game.adjust_inventory($1, 'emas', 9)`, [u.id]);
  await H.expectError(() => tg(['gov']), /menunggu: 4 Gaharu/);
  await H.sql(`select game.adjust_inventory($1, 'gaharu', 4)`, [u.id]);
  s = await u.call('api_getGameState', [null]); assert(s.toogood.progress.sunda_empire.ready && s.toogood.progress.sunda_empire.items.emas === 9, 'progres siap');
  r = await tg(['gov']); assert(r.letter === 'sunda_empire' && r.count === 1, 'surat 1');
  const inv = async id => Number(((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = $2`, [u.id, id]))[0] || { qty: 0 }).qty);
  assert(await inv('emas') === 1 && await inv('gaharu') === 0, 'barang terpakai');
  await H.expectError(() => tg(['gov']), /sudah menandatangani/);
  // Skitraw: 75.000 gold + 10 Mesiu
  await go('skitraw'); await tg(['gov']);
  await H.sql('update game.players set gold = 80000 where player_id = $1', [u.id]);
  await H.expectError(() => tg(['gov']), /10 Mesiu/);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 10)`, [u.id]);
  await H.sql('update game.players set gold = 70000 where player_id = $1', [u.id]);
  await H.expectError(() => tg(['gov']), /sumbangan 75000 gold/);
  await H.sql('update game.players set gold = 80000 where player_id = $1', [u.id]);
  r = await tg(['gov']); assert(r.count === 2 && (await gold()) === 5000 && await inv('mesiu') === 0, 'surat 2 + sumbangan');
  // Bjorneo: menang 5 kali (kemenangan sebelum tugas diterima tidak dihitung) + 15 Senjata
  await H.sql('select game.quest_combat_won($1)', [u.id]);
  await go('bjorneo'); await tg(['gov']);
  await H.expectError(() => tg(['gov']), /baru 0/);
  for (let i = 0; i < 5; i++) await H.sql('select game.quest_combat_won($1)', [u.id]);
  s = await u.call('api_getGameState', [null]); assert(s.toogood.progress.bjorneo.wins === 5 && !s.toogood.progress.bjorneo.ready, 'progres menang');
  await H.expectError(() => tg(['gov']), /15 Senjata/);
  await H.sql(`select game.adjust_inventory($1, 'arms', 15)`, [u.id]); await H.sql(`select game.adjust_inventory($1, 'kayu_cendana', 6)`, [u.id]);
  r = await tg(['gov']); assert(r.count === 3 && r.toogood.step === 2, 'surat 3 -> langkah 2');

  // IKN: Tedsky, diusir, berlayar paksa ke TooGood, dicegat pemburu
  await go('joungjava'); await H.expectError(() => tg(['ikn']), /IKN/);
  await go('ikn'); r = await tg(['ikn']);
  assert(r.expelled && r.sail.destinationCityId === 'toogood' && r.toogood.hunted, 'diusir ' + JSON.stringify(r).slice(0, 200));
  await H.expectError(() => tg(['zafa']), /Merapat dulu/);
  await H.shiftTime(3600000);
  s = await u.call('api_getGameState', [null]);
  assert(s.voyage.encounterPending && s.voyage.encounter.hunter && /Tedsky/.test(s.voyage.encounter.enemyName), 'pemburu mencegat');
  let fr = await winFight(); assert(fr.result === 'won', 'menang lawan pemburu');
  s = await u.call('api_getGameState', [null]); assert(s.city.CityId === 'toogood', 'tiba di TooGood');
  // setiap pelayaran dicegat (rute mana pun)
  for (let i = 0; i < 5; i++) assert((await H.sql(`select game.voy_roll_encounter($1, 'skitraw') e`, [u.id]))[0].e.hunter, 'selalu dicegat');

  r = await tg(['zafa']); assert(r.toogood.step === 4, 'lapor zafachmie');
  r = await tg(['euis']); assert(r.toogood.step === 5, 'Teh Euis menolak');
  await clock(0.3); await H.expectError(() => tg(['dwi']), /Daeng Sore/);
  await clock(0.8); r = await tg(['dwi']); assert(r.story && r.toogood.step === 6 && r.book.total === 14, 'kisah dwi');
  r = await tg(['dwi']); assert(r.needBook && r.toogood.step === 6, 'butuh buku ikan');
  await H.sql(`insert into game.mp_fish_book(player_id, fish_id, n, best_kg) select $1, id, 1, 1 from game.mp_fish_types on conflict do nothing`, [u.id]);
  r = await tg(['dwi']); assert(r.code === 'thepowerofdreams' && r.toogood.step === 7, 'kode sandi');

  // Black Pearl
  const own = (await u.call('api_getShipState', [])).ship;
  r = await tg(['unlock', 'bukan kode']); assert(r.wrong, 'kode salah');
  r = await tg(['unlock', 'The Power of Dreams!']);
  assert(r.pearl && r.ship.ShipName === 'Black Pearl' && r.visual.legend === 'pearl' && Number(r.ship.EffectiveMaxCondition) === 300, 'Black Pearl ' + JSON.stringify(r.ship).slice(0, 200));
  assert(r.ship.Speed === own.Speed + 25 && r.ship.EffectiveCargo === own.EffectiveCargo, 'stat Pearl, cargo sama');
  await H.expectError(() => u.call('api_saveShipLook', [{ hull: '#ffffff' }, 'Kapal Baru']), /Black Pearl/);
  assert((await H.sql(`select game.voy_roll_encounter($1, 'joungjava') e`, [u.id]))[0].e.hunter, 'masih diburu');

  // kabarkan ke 5 gubernur
  await go('ikn'); await H.expectError(() => tg(['inform']), /pulau lain/);
  for (const c of ['sunda_empire', 'joungjava', 'bjorneo', 'skitraw']) { await go(c); r = await tg(['inform']); assert(r.informed === c && r.toogood.step === 8 && r.toogood.informCount === 5, 'kabar ' + c); }
  await H.expectError(() => tg(['inform']), /sudah mendengar/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6) on conflict do nothing`, [u.id]);
  await go('paradiso'); r = await tg(['inform']); assert(r.arrest && r.toogood.step === 9 && !r.toogood.hunted && r.toogood.pearl, 'Tedsky ditangkap');
  assert((await H.sql(`select game.quest_boss_encounter($1, 'skitraw') e`, [u.id]))[0].e === null, 'tidak diburu lagi');

  // Final: TooGood merdeka
  await go('toogood'); const g0 = await gold();
  r = await tg(['zafa']);
  assert(r.freed && r.toogood.freed && (await gold()) - g0 === 100000, 'hadiah 100.000');
  assert(r.ship.ShipName === own.ShipName && r.ship.Speed === own.Speed && !r.visual.legend && Number(r.ship.Condition) === Number(r.ship.EffectiveMaxCondition), 'kapal sendiri kembali ' + JSON.stringify(r.ship).slice(0, 200));
  await H.expectError(() => tg(['zafa']), /belum ada yang perlu/);
  await u.call('api_saveShipLook', [{ hull: '#223344' }, own.ShipName]);
  // TooGood tidak lagi sarang penyamun bagi pemain ini
  let hits = 0; for (let i = 0; i < 30; i++) if ((await H.sql(`select game.voy_roll_encounter($1, 'toogood') e`, [u.id]))[0].e) hits++;
  assert(hits < 30, 'rute TooGood tidak selalu dicegat: ' + hits);
  const v = await H.user('biasa'); await v.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  for (let i = 0; i < 5; i++) assert((await H.sql(`select game.voy_roll_encounter($1, 'toogood') e`, [v.id]))[0].e, 'pemain lain tetap dicegat');
  assert((await v.call('api_getGameState', [null])).toogood === null, 'pemain lain tidak melihat misi');
  // penyembuhan di TooGood merdeka
  await H.sql('update game.ships set condition = 50 where player_id = $1', [u.id]);
  let t = await u.call('api_paradisoTick', []); assert(t.tick && t.tick.healed === 0, 'jam mulai');
  await H.sql(`update game.paradiso_heal set at = now() - interval '11 seconds' where player_id = $1`, [u.id]);
  t = await u.call('api_paradisoTick', []); assert(t.tick.healed === 2, 'sembuh di TooGood ' + JSON.stringify(t.tick));
  await go('toogood'); await H.expectError(() => v.call('api_toogoodQuest', ['accept']), /belum mengenalmu/);
  console.log('TOOGOOD QUEST TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
