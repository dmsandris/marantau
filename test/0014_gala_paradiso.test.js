// Misi rahasia Uda Gala -> Mr. GAP -> Kotak Hati -> buku +5 Speed & pulau Paradiso (+ penyembuhan).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('pemburu'); await u.call('api_createCharacter', ['Pemburu Harta', 'explorer']);
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  let s = await u.call('api_getGameState', [null]);
  assert(s.gala.step === 0 && !s.gala.eligible && s.unlocks.length === 0, 'awal');
  assert(!JSON.stringify(await u.call('api_getSailOptions', [])).includes('paradiso'), 'Paradiso tersembunyi');
  await H.expectError(() => u.call('api_setSail', ['paradiso']), /tidak dikenali/);
  await go('skitraw');
  await H.expectError(() => u.call('api_galaQuest', ['accept']), /20 Tanda Jasa/);
  const meta = { u: {} }; for (let i = 0; i < 20; i++) meta.u['a' + i] = 1;
  await H.sql('update game.players set meta = $2 where player_id = $1', [u.id, JSON.stringify(meta)]);
  await go('sunda_empire');
  await H.expectError(() => u.call('api_galaQuest', ['accept']), /Skitraw/);
  await go('skitraw');
  assert((await u.call('api_galaQuest', ['accept'])).gala.step === 1, 'terima');
  await H.expectError(() => u.call('api_galaQuest', ['accept']), /sudah menerima/);
  await H.expectError(() => u.call('api_galaQuest', ['investigate']), /bukan di pelabuhan ini/);
  await go('joungjava'); let r = await u.call('api_galaQuest', ['investigate']);
  assert(r.next === 'bjorneo' && r.gala.step === 2 && /Karto/.test(r.story), 'petunjuk 1');
  await go('bjorneo');
  r = await u.call('api_galaQuest', ['investigate', 'kemudi']); assert(r.wrong && r.gala.step === 2, 'salah jawab');
  await H.expectError(() => u.call('api_galaQuest', ['investigate', 'jangkar']), /menunggumu berpikir/);
  await H.sql(`update game.player_quests set data = '{}'`);
  r = await u.call('api_galaQuest', ['investigate', ' Jangkar ']); assert(r.next === 'ikn' && r.gala.step === 3, 'petunjuk 2');
  await go('ikn'); r = await u.call('api_galaQuest', ['investigate']); assert(r.next === 'toogood' && r.gala.step === 4, 'petunjuk 3');
  // rute lain tidak memunculkan bos
  assert((await H.sql(`select game.quest_boss_encounter($1, 'bjorneo') e`, [u.id]))[0].e === null, 'bos hanya di rute TooGood');
  await go('sunda_empire'); await u.call('api_setSail', ['toogood']); await H.shiftTime(3600000);
  s = await u.call('api_getGameState', [null]);
  assert(s.voyage.encounterPending && s.voyage.encounter.boss === 'gap' && s.voyage.encounter.enemyName === 'Mr. GAP', 'bos muncul');
  await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /tidak bisa disuap/);
  await H.expectError(() => u.call('api_resolveCombat', ['negotiate']), /tidak bisa disuap/);
  await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '1') where player_id = $1`, [u.id]);
  const g0 = await gold(); let fr;
  for (let i = 0; i < 40; i++) {
    await H.sql('update game.ships set condition = 140 where player_id = $1', [u.id]);
    fr = await u.call('api_resolveCombat', ['fire']); if (!fr.ongoing) break;
    if (fr.encounter.ammoRemaining === 0) await u.call('api_resolveCombat', ['reload']);
  }
  assert(fr.result === 'won' && fr.boss === 'gap' && fr.questItem && fr.questItem.text === 'Chafik is My One Piece', 'menang ' + JSON.stringify(fr));
  assert(await gold() - g0 === 10000, 'hadiah 10.000 gold ' + (await gold() - g0));
  s = await u.call('api_getGameState', [null]); assert(s.gala.step === 5 && s.gala.hasBox, 'bawa kotak');
  await go('ikn'); await H.expectError(() => u.call('api_galaQuest', ['deliver']), /Skitraw/);
  await go('skitraw'); const spd0 = (await u.call('api_getShipState', [])).ship.Speed;
  r = await u.call('api_galaQuest', ['deliver']);
  assert(r.done && r.unlocks[0] === 'paradiso' && r.ship.Speed === spd0 + 5, 'serahkan ' + JSON.stringify(r).slice(0, 200));
  assert((await H.sql(`select count(*)::int n from game.player_books where player_id = $1 and book_id = 'bk_gala_logbook'`, [u.id]))[0].n === 1, 'buku');
  await H.expectError(() => u.call('api_galaQuest', ['deliver']), /belum membawa/);
  // Paradiso terbuka hanya untuk dia
  assert(JSON.stringify(await u.call('api_getSailOptions', [])).includes('paradiso'), 'Paradiso di opsi layar');
  const v = await H.user('biasa'); await v.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  await H.expectError(() => v.call('api_setSail', ['paradiso']), /tidak dikenali/);
  const lib = await u.call('api_getLibrary', []); assert(!JSON.stringify(lib.available || []).includes('bk_gala_logbook'), 'buku tidak dijual');
  // penyembuhan di Paradiso
  await u.call('api_setSail', ['paradiso']); await H.shiftTime(3600000);
  s = await u.call('api_getGameState', [null]); assert(s.city.CityId === 'paradiso' && s.city.Type === 'Paradise', 'tiba di Paradiso');
  await H.sql('update game.ships set condition = 50 where player_id = $1', [u.id]);
  await H.sql(`update game.paradiso_heal set at = now() - interval '26 seconds' where player_id = $1`, [u.id]);
  let t = await u.call('api_paradisoTick', []); assert(t.tick.healed === 5 && Number(t.ship.Condition) === 55, 'sembuh ' + JSON.stringify(t.tick));
  t = await u.call('api_paradisoTick', []); assert(t.tick.healed === 0, 'tidak dobel');
  await H.sql(`update game.paradiso_heal set at = now() - interval '1 hour' where player_id = $1`, [u.id]);
  t = await u.call('api_paradisoTick', []); assert(t.tick.full && Number(t.ship.Condition) === 100, 'maks 100% ' + JSON.stringify(t.tick));
  // berangkat -> jam penyembuhan dihapus (tidak menumpuk saat pergi)
  await H.sql('update game.ships set condition = 40 where player_id = $1', [u.id]);
  await u.call('api_setSail', ['joungjava']);
  assert((await H.sql('select count(*)::int n from game.paradiso_heal where player_id = $1', [u.id]))[0].n === 0, 'jam dihapus saat berangkat');
  assert((await u.call('api_paradisoTick', [])).tick === null, 'tidak sembuh di laut');
  console.log('GALA PARADISO TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
