// Integrasi: semua migrasi dimuat bersama, alur main dari nol.
const assert = require('assert');
(async () => {
  const H = await require('./harness').create();
  const E = H.expectError;
  const anon = await H.anon();
  await E(() => anon.call('api_getGameState', []), /AUTH_REQUIRED/);
  assert.strictEqual((await anon.call('api_usernameAvailable', ['nina'])).available, true);
  const nina = await H.user('nina'), budi = await H.user('budi');
  assert.strictEqual((await anon.call('api_usernameAvailable', ['nina'])).available, false);
  let st = await nina.call('api_getGameState', [null]);
  assert(st.needsCharacter && st.username === 'nina', JSON.stringify(st));
  assert.strictEqual((await nina.call('api_authWhoAmI', [])).hasCharacter, false);
  await nina.call('api_createCharacter', ['Nina', 'merchant', { fem: 1, skin: 2 }]);
  await budi.call('api_createCharacter', ['Budi', 'pirate', null]);
  await E(() => budi.call('api_createCharacter', ['Budi2', 'pirate', null]), /sudah pernah dibuat/);
  st = await nina.call('api_getGameState', [null]);
  for (const k of ['player', 'stats', 'ship', 'city', 'citiesVersion', 'voyage', 'bank', 'mission', 'reputationHere', 'gameDay', 'minutesUntilNextGameDay', 'audio', 'logs', 'appearance', 'cities'])
    assert(k in st, 'missing ' + k);
  assert.strictEqual(st.player.characterName, 'Nina'); assert.strictEqual(st.city.CityId, 'sunda_empire');
  assert(st.ship.EffectiveCargo > 0 && st.stats.Trading > 0 && st.appearance.fem === 1);
  const st2 = await nina.call('api_getGameState', [st.citiesVersion]); assert(!('cities' in st2));
  console.log('state ok: gold', st.player.gold, 'cargo cap', st.ship.EffectiveCargo, 'logs', st.logs.length);

  // bundle
  const b = await nina.call('api_getCityBundle', ['sunda_empire']);
  for (const k of ['cargoState', 'upgrades', 'items', 'market', 'library', 'missionBoard', 'sailOptions', 'repairQuote']) assert(b[k], 'bundle missing ' + k + ' ' + (b[k + 'Error'] || ''));
  console.log('bundle ok');

  // trade -> sail -> arrive -> sell
  const mk = b.market.items.slice().sort((x, y) => x.buyPrice - y.buyPrice)[0];
  await nina.call('api_buy', ['sunda_empire', mk.commodityId, 10]);
  const opt = b.sailOptions.find(o => o.cityId === 'joungjava');
  await H.sql("insert into game.config(key,value) values ('PirateEncounterBaseChance','0') on conflict (key) do update set value='0'");
  const sail = await nina.call('api_setSail', ['joungjava']); assert(sail.arriveAt);
  st = await nina.call('api_getGameState', [st.citiesVersion]); assert(st.voyage.inTransit);
  await E(() => nina.call('api_buy', ['sunda_empire', mk.commodityId, 1]), /berlayar/);
  await H.shiftTime((opt.etaMinutes + 1) * 60000);
  const pv = await nina.call('api_pollVoyage', []);
  st = await nina.call('api_getGameState', [st.citiesVersion]);
  if (st.voyage.inTransit) { console.log('encounter happened; voyage', JSON.stringify(st.voyage).slice(0, 200)); }
  else { assert.strictEqual(st.city.CityId, 'joungjava'); const s = await nina.call('api_sell', ['joungjava', mk.commodityId, 10]); console.log('arrived + sold', s.totalRevenue); }

  // mission + multiplayer
  const board = await nina.call('api_getMissionBoard', [st.city.CityId]); assert(board.offers.length >= 4);
  const pulse = await nina.call('api_mpPulse', [{}]); assert('online' in pulse && pulse.mePub);
  assert(!JSON.stringify(pulse).includes(budi.id));
  console.log('mission board + pulse ok, online', pulse.online);
  console.log('\nINTEGRATION TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
