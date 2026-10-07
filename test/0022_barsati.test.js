// Quest 4 "Tiga Tanda Silang" (BarSaTi): Garuda roboh -> 3 armada berantai -> Karto -> a'dik (dadu, setor, peti)
// -> Titik Buta (malam) -> Armada Terakhir -> Mahkota Karam -> Pusaran Bjorneo -> Hasiolan -> topeng ->
// raid (3 penjelajah putih berantai + Satnislaus 2 fase) -> pilihan -> hadiah, Skitraw, Patroli Bebas.
const fs = require('fs'), path = require('path');
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('saudara4'); await u.call('api_createCharacter', ['Saudara Keempat', 'explorer']);
  const pid = u.id;
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [pid]))[0].gold);
  const cond = async () => Number((await H.sql('select condition from game.ships where player_id = $1', [pid]))[0].condition);
  const city = async () => (await H.sql('select city_id from game.player_location where player_id = $1', [pid]))[0].city_id;
  const bx = a => u.call('api_barsati', a);
  const st = async () => (await u.call('api_getGameState', [null])).barsati;
  const clock = f => H.sql(`select game.cfg_set('WorldStartTimestamp', (game.now_ms() - ($1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint)::text)`, [f]);
  const day = () => clock(0.3), night = () => clock(0.8);
  const sail = async (dest) => { await u.call('api_setSail', [dest]); await H.shiftTime(400000); return u.call('api_getGameState', [null]); };
  const setHp = hp => H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', to_jsonb($2::numeric)) where player_id = $1`, [pid, hp]);
  const enc = async () => (await H.sql('select pending_encounter e from game.player_location where player_id = $1', [pid]))[0].e;
  // Tembak sampai pertempuran berakhir ATAU berganti musuh (berantai)
  const fight = async (hpLeft) => {
    if (hpLeft != null) await setHp(hpLeft);
    let fr;
    for (let i = 0; i < 80; i++) {
      await H.sql('update game.ships set condition = greatest(condition, 90) where player_id = $1', [pid]);
      fr = await u.call('api_resolveCombat', ['fire']);
      if (!fr.ongoing || fr.chained) break;
      if (fr.encounter.ammoRemaining === 0) await u.call('api_resolveCombat', ['reload']);
    }
    return fr;
  };
  const sinkMe = async () => {
    let r;
    for (let i = 0; i < 40; i++) {
      await H.sql('update game.ships set condition = 1 where player_id = $1', [pid]);
      r = await u.call('api_resolveCombat', ['reload']); if (!r.ongoing) break;
    }
    return r;
  };
  await H.sql('update game.players set gold = 200000 where player_id = $1', [pid]);

  // --- Prasyarat & pemicu -------------------------------------------------
  assert((await st()) === null, 'tersembunyi sebelum Warwerwor selesai');
  await H.expectError(() => bx(['garuda']), /Laut masih tenang/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at) values ($1, 'gala', 6, now()), ($1, 'toogood', 10, now()), ($1, 'warwerwor', 12, now())`, [pid]);
  let s = await st();
  assert(s && s.step === 0 && s.eligible && !s.shout && s.shoutInMs > 0, 'menunggu 3 hari game ' + JSON.stringify(s));
  await go('ikn'); await H.expectError(() => bx(['garuda']), /Belum waktunya/);
  await H.sql(`update game.player_quests set done_at = now() - (3.1 * game.cfg_num('GameDayLengthRealMinutes', 60) || ' minutes')::interval where player_id = $1 and quest_id = 'warwerwor'`, [pid]);
  s = await st(); assert(s.shout, 'warga berteriak setelah 3 hari game');
  await go('skitraw'); await H.expectError(() => bx(['garuda']), /ke IKN/);
  await go('ikn');
  let r = await bx(['garuda']);
  assert(r.barsati.step === 1 && r.barsati.chain === 0 && r.next === 'joungjava', 'Garuda roboh');
  await H.expectError(() => bx(['garuda']), /sudah roboh/);
  await H.expectError(() => bx(['karto']), /Tak ada yang perlu/);

  // --- Babak 1: tiga armada berantai -------------------------------------
  s = await sail('skitraw');  // rute lain tidak dicegat armada BarSaTi
  assert(!s.voyage.encounterPending || !s.voyage.encounter.bx, 'hanya rute ke Joungjava');
  if (s.voyage.encounterPending) await fight(1);
  await go('ikn');
  s = await sail('joungjava');
  let e = s.voyage.encounter;
  assert(e && e.bx && e.boss === 'kuning' && e.displayLevel === 5 && e.enemyLevel < 5 && e.fleetNo === 1 && e.noRam && e.softSink && e.retreat, 'Armada Kuning ' + JSON.stringify(e));
  await H.expectError(() => u.call('api_resolveCombat', ['ram']), /tabrakan tak berpengaruh/);
  await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /Tak ada yang mau mendengarmu/);
  let g0 = await gold();
  r = await fight(1);
  assert(r.chained && r.ongoing && r.result === 'won' && r.questEvent === 'fleet' && r.encounter.boss === 'merah' && r.encounter.punishReload === 2, 'berantai ke Armada Merah ' + JSON.stringify(r).slice(0, 300));
  assert((await gold()) - g0 === 10000 && r.newCondition === (await cond()), 'hadiah 10.000 & kondisi terbawa');
  assert((await st()).chain === 1 && (await u.call('api_getGameState', [null])).voyage.inTransit, 'masih di tengah pelayaran');
  // merah: damage 2x saat reload
  r = await u.call('api_resolveCombat', ['fire']); // ronde biasa
  // kalah -> mundur ke IKN tanpa kehilangan muatan/gold, armada kuning tidak muncul lagi
  await H.sql(`select game.adjust_inventory($1, 'beras', 5)`, [pid]);
  await setHp(500); g0 = await gold();
  r = await sinkMe();
  assert(r.result === 'sunk' && (await gold()) === g0 && (await city()) === 'ikn', 'karam ringan -> IKN ' + JSON.stringify(r).slice(0, 200));
  assert(Number((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = 'beras'`, [pid]))[0].qty) === 5, 'muatan utuh');
  s = await sail('joungjava'); e = s.voyage.encounter;
  assert(e.boss === 'merah' && e.enemyHp === 500, 'Armada Merah menunggu dengan HP tersimpan ' + e.enemyHp);
  r = await fight(1);
  assert(r.chained && r.encounter.boss === 'hitam' && r.encounter.smoke === true, 'Armada Hitam berasap');
  r = await u.call('api_resolveCombat', ['reload']);
  assert(r.ongoing && r.encounter.smoke === false && /asap/.test(r.message), 'reload menyibak asap');
  g0 = await gold();
  r = await fight(1);
  assert(!r.ongoing && r.result === 'won' && r.questEvent === 'fleets' && r.cityId === 'joungjava' && (await gold()) - g0 === 15000, 'tiba di Joungjava ' + JSON.stringify(r).slice(0, 200));
  s = await st(); assert(s.step === 2 && s.chain === 3, 'langkah 2');

  // --- Karto & a'dik -----------------------------------------------------
  await go('ikn'); await H.expectError(() => bx(['karto']), /Warung Pantai Joungjava/);
  await go('joungjava'); r = await bx(['karto']); assert(r.barsati.step === 3, 'Karto');
  await H.expectError(() => bx(['dice', 'besar']), /Kasino Mutiara/);
  await go('paradiso');
  await H.expectError(() => bx(['pay']), /Dadu dulu/);
  await H.expectError(() => bx(['dice', 'tengah']), /Besar atau Kecil/);
  r = await bx(['dice', 'besar']);
  assert(r.dice.length === 3 && r.sum === r.dice.reduce((a, b) => a + b, 0) && r.win === (r.sum >= 11) && r.barsati.dice === (r.win ? 'won' : 'lost'), 'dadu ' + JSON.stringify(r));
  await H.expectError(() => bx(['dice', 'kecil']), /Satu ronde cukup/);
  await H.sql('update game.players set gold = 1000 where player_id = $1', [pid]);
  await H.expectError(() => bx(['pay']), /75.000 gold/);
  await H.sql('update game.players set gold = 200000 where player_id = $1', [pid]);
  const cap = (await u.call('api_getMarket', ['paradiso'])).cargoCapacity;
  await H.sql(`select game.adjust_inventory($1, 'beras', $2)`, [pid, cap - 5 - 5]); // sisa ruang 5 (beras ukuran 1? cek)
  const free0 = Number((await H.sql('select game.cargo_free($1) f', [pid]))[0].f);
  if (free0 >= 10) await H.sql(`select game.adjust_inventory($1, 'beras', $2)`, [pid, Math.ceil(free0 - 5)]);
  await H.expectError(() => bx(['pay']), /Kosongkan 10 ruang/);
  await H.sql(`update game.inventory set qty = 0 where player_id = $1 and item_id = 'beras'`, [pid]);
  const used0 = Number((await H.sql('select game.cargo_used($1) u', [pid]))[0].u);
  g0 = await gold();
  r = await bx(['pay']);
  assert(r.barsati.step === 4 && r.barsati.paid === 75000 && r.barsati.peti && r.barsati.coin && (await gold()) === g0 - 75000, 'setor 75.000 ' + JSON.stringify(r.barsati));
  assert(Number((await H.sql('select game.cargo_used($1) u', [pid]))[0].u) === used0 + 10, 'peti memakai tepat 10 ruang');
  const items = await u.call('api_getItems', []);
  assert(items.questItems.some(i => i.itemId === 'qi_peti_adik' && i.size === 10) && items.questItems.some(i => i.itemId === 'qi_koin_tiga_silang' && i.size === 0), 'barang quest terlihat');
  await H.expectError(() => u.call('api_sellItem', ['qi_peti_adik', 1]), /bukan barang dagangan/);
  await H.expectError(() => u.call('api_warehouseStore', ['paradiso', 'qi_peti_adik', 1]), /tidak cukup/);
  await H.expectError(() => u.call('api_sell', ['paradiso', 'qi_peti_adik', 1]), /./);

  // --- Titik Buta: hanya malam -------------------------------------------
  await day();
  assert(!(await u.call('api_getSailOptions', [])).some(o => o.cityId === 'titik_buta') && !(await u.call('api_getGameState', [null])).unlocks.includes('titik_buta'), 'siang: tidak ada di peta');
  await H.expectError(() => u.call('api_setSail', ['titik_buta']), /tidak dikenali/);
  await night();
  s = await u.call('api_getGameState', [null]);
  assert(s.unlocks.includes('titik_buta') && s.barsati.night && (await u.call('api_getSailOptions', [])).some(o => o.cityId === 'titik_buta'), 'malam: Titik Buta muncul');
  s = await sail('titik_buta'); e = s.voyage.encounter;
  assert(e.boss === 'pengintai' && e.displayLevel === 4 && e.bx, 'pengintai ' + JSON.stringify(e));
  r = await fight(1);
  assert(r.result === 'won' && r.questEvent === 'pengintai' && r.cityId === 'paradiso', 'menang lalu kembali ke pelabuhan asal');
  s = await st(); assert(s.step === 5 && !s.peti && s.coin && s.allies.length === 0, 'peti diambil, Babak 3');
  assert(Number((await H.sql('select game.cargo_used($1) u', [pid]))[0].u) === used0, 'ruang palka kembali');

  // --- Babak 3: Armada Terakhir ------------------------------------------
  await go('ikn'); await H.expectError(() => bx(['ally']), /Tak ada penguasa/);
  await go('bjorneo'); await H.expectError(() => bx(['ally']), /Orang Bjorneo tidak berlayar sendirian/);
  for (const c of ['sunda_empire', 'joungjava', 'skitraw', 'toogood', 'marie_regal']) { await go(c); r = await bx(['ally']); assert(r.ally === c && r.barsati.step === 5, 'sekutu ' + c); }
  await H.expectError(() => bx(['ally']), /sudah berdiri di belakangmu/);
  await go('bjorneo'); r = await bx(['ally']); assert(r.count === 6 && r.barsati.step === 6, 'Bjorneo terakhir');

  // --- Babak 3b: Peti Karam pasti berisi Mahkota Karam --------------------
  await H.expectError(() => bx(['crown']), /Pancinglah/);
  assert(Number((await H.sql(`select game.fish_quest_weight($1, 'peti', 'bjorneo') w`, [pid]))[0].w) === 8, 'peluang Peti Karam naik di Bjorneo');
  assert(Number((await H.sql(`select game.fish_quest_weight($1, 'peti', 'ikn') w`, [pid]))[0].w) === 1, 'hanya di Bjorneo');
  const cast = await u.call('api_mgFishCast', [0.9, 'cacing', false]);
  await H.sql(`update game.mp_fish set fish = 'peti', t0 = game.now_ms() - wait_ms - fight_ms - 2000 where player_id = $1`, [pid]);
  r = await u.call('api_mgFishReel', [cast.castId, 'caught', 1]);
  assert(r.caught && r.fish.id === 'peti' && r.questItem && r.questItem.itemId === 'art_sunken_crown', 'Mahkota Karam ' + JSON.stringify(r));
  s = await st(); assert(s.crown, 'punya mahkota');
  await u.call('api_equipArtifact', ['art_sunken_crown']); // terpasang pun tetap dihitung
  assert(Number((await H.sql(`select game.fish_quest_weight($1, 'peti', 'bjorneo') w`, [pid]))[0].w) === 1, 'peluang normal setelah dapat mahkota');
  r = await bx(['crown']);
  assert(r.barsati.step === 7 && r.unlocks.includes('pusaran'), 'Pusaran terbuka');

  // --- Babak 4: Pusaran Bjorneo ------------------------------------------
  assert((await u.call('api_getSailOptions', [])).some(o => o.cityId === 'pusaran'), 'pusaran di peta');
  await H.expectError(() => bx(['throw']), /Pusaran Bjorneo/);
  s = await sail('pusaran');
  assert(s.city.CityId === 'pusaran' && !s.voyage.inTransit && s.city.Type === 'Maelstrom', 'merapat di pusaran tanpa pertempuran');
  // tanpa pasar / misi / gudang / bank
  await H.expectError(() => u.call('api_buy', ['pusaran', 'beras', 1]), /Tak ada pedagang di tengah pusaran/);
  assert((await u.call('api_getMarket', ['pusaran'])).items.length === 0, 'pasar kosong');
  await H.expectError(() => u.call('api_acceptMission', ['pusaran', 0]), /papan misi/);
  await H.expectError(() => u.call('api_bankDeposit', [10]), /Tak ada gudang, bank/);
  await H.expectError(() => u.call('api_warehouseStore', ['pusaran', 'beras', 1]), /Tak ada gudang, bank/);
  // dirawat Armada Terakhir: +1 kondisi / 5 dtk
  await H.sql('update game.ships set condition = 50 where player_id = $1', [pid]);
  await H.sql(`update game.paradiso_heal set at = now() - interval '50 seconds' where player_id = $1`, [pid]);
  r = await u.call('api_paradisoTick', []);
  assert(r.tick && r.tick.healed >= 9 && (await cond()) >= 59, 'pulih di pusaran ' + JSON.stringify(r.tick));
  // repair tetap bisa
  assert((await u.call('api_getRepairQuote', ['pusaran'])).cost > 0, 'reparasi tersedia');
  r = await bx(['throw']);
  s = await st(); assert(r.barsati.step === 8 && !s.crown, 'mahkota dilempar (dari slot artefak)');
  await H.expectError(() => bx(['navigate', 'asal']), /tidak dikenal/);
  r = await bx(['navigate', 'ok']); assert(r.barsati.step === 9 && r.barsati.perfect === false, 'navigasi');
  // Hasiolan: kebal tembakan pertama (tidak sempurna)
  r = await bx(['engage']);
  e = r.encounter;
  assert(e.boss === 'hasiolan2' && e.immuneFirst && e.displayLevel === 8 && e.maelstrom && r.voyage.encounterPending && r.voyage.destinationCityId === 'pusaran', 'Hasiolan ' + JSON.stringify(e));
  await H.expectError(() => bx(['engage']), /Merapat dulu|masih berlangsung/);
  await H.expectError(() => u.call('api_resolveCombat', ['ram']), /bunuh diri/);
  let absorbed = false;
  for (let i = 0; i < 30 && !absorbed; i++) {
    await H.sql('update game.ships set condition = 300 where player_id = $1', [pid]);
    const hp0 = (await enc()).enemyHp;
    r = await u.call('api_resolveCombat', [(await enc()).ammoRemaining > 0 ? 'fire' : 'reload']);
    if (r.encounter && r.encounter.immuneFirst === false) { absorbed = true; assert(r.encounter.enemyHp === hp0 && /memantul/.test(r.message), 'tembakan pertama diserap'); }
  }
  assert(absorbed, 'kekebalan habis setelah satu tembakan kena');
  await setHp(1200);
  r = await u.call('api_resolveCombat', ['flee']);
  assert(r.result === 'fled' && r.cityId === 'pusaran', 'mundur tetap di pusaran');
  r = await bx(['engage']); assert(r.encounter.enemyHp === 1200 && r.encounter.immuneFirst, 'HP Hasiolan tersimpan');
  g0 = await gold(); r = await fight(1);
  assert(r.questEvent === 'hasiolan' && (await gold()) - g0 === 30000 && r.cityId === 'pusaran', 'Hasiolan kalah, 30.000');
  // sempurna: +2 amunisi & tanpa kekebalan
  await H.sql(`update game.player_quests set data = data || '{"perfect": true}' where player_id = $1 and quest_id = 'barsati'`, [pid]);
  e = (await H.sql(`select game.bx_enc($1, 'hasiolan2') e`, [pid]))[0].e;
  assert(!e.immuneFirst && e.maxAmmo === e.ammoRemaining && e.maxAmmo === (await u.call('api_getShipState', [])).ship.MaxCannonAmmo + 2, 'mini-game sempurna');

  // --- Babak 5-6 -----------------------------------------------------------
  await H.expectError(() => bx(['mask']), /Bukan saatnya/);
  r = await bx(['deck']); assert(r.barsati.step === 11, 'geladak Tedsky');
  r = await bx(['mask']); assert(r.barsati.step === 12 && r.barsati.putih === 0 && r.barsati.satHp === 18000, 'topeng');

  // --- Babak 7: raid berantai --------------------------------------------
  r = await bx(['engage']); e = r.encounter;
  assert(e.boss === 'putih' && e.putihNo === 1 && e.allyDmg > 0 && e.displayLevel === 9, 'penjelajah 1');
  r = await u.call('api_resolveCombat', ['fire']);
  assert(/Armada Terakhir menghujani/.test(r.message), 'sekutu menembak');
  r = await fight(1); assert(r.chained && r.encounter.putihNo === 2 && r.questEvent === 'putih', 'berantai ke penjelajah 2');
  await setHp(900);
  r = await u.call('api_resolveCombat', ['flee']); assert(r.result === 'fled', 'mundur dari raid');
  s = await st(); assert(s.putih === 1, 'penjelajah yang tenggelam tidak bangkit');
  r = await bx(['engage']); assert(r.encounter.putihNo === 2 && r.encounter.enemyHp === 900, 'lanjut penjelajah 2, HP tersimpan');
  r = await fight(1); assert(r.chained && r.encounter.putihNo === 3 && r.encounter.enemyHp === 2500, 'penjelajah 3 segar');
  r = await fight(1);
  e = r.encounter;
  assert(r.chained && e.boss === 'satnislaus' && e.phase === 1 && e.shield && e.hpFloor === 9000 && e.enemyHp === 18000 && e.displayLevel === 15, 'Satnislaus fase 1 ' + JSON.stringify(e));
  r = await u.call('api_resolveCombat', ['fire']);
  const satMid = r.encounter.enemyHp;
  assert(satMid < 18000, 'sekutu melukai Satnislaus');
  r = await u.call('api_resolveCombat', ['flee']);
  s = await st(); assert(s.satHp === satMid && s.putih === 3 && s.step === 12, 'HP Satnislaus tersimpan ' + s.satHp);
  r = await bx(['engage']); assert(r.encounter.boss === 'satnislaus' && r.encounter.enemyHp === satMid, 'langsung ke Satnislaus');
  r = await fight(9001);
  assert(r.result === 'won' && r.questEvent === 'aegis' && r.cityId === 'pusaran', 'separuh HP');
  s = await st(); assert(s.step === 13 && s.satHp === 9000, 'langkah 13');
  await H.expectError(() => bx(['engage']), /Tidak ada musuh/);
  r = await bx(['ram']); assert(r.barsati.step === 14, 'Black Pearl menabrak');
  r = await bx(['engage']); e = r.encounter;
  const sat1 = (await H.sql(`select game.bx_enc($1, 'sat1') e`, [pid]))[0].e;
  assert(e.phase === 3 && !e.shield && e.final && e.enemyHp === 9000 && e.hpFloor == null && e.enemyDmgMul === sat1.enemyDmgMul * 2, 'fase 3 ' + JSON.stringify(e));
  r = await fight(1);
  assert(r.result === 'won' && r.questEvent === 'satnislaus', 'Satnislaus tenggelam');
  s = await st(); assert(s.step === 15 && s.satHp === 0, 'langkah 15');

  // --- Pilihan & hadiah ----------------------------------------------------
  await H.expectError(() => bx(['choice', 'maybe']), /Putuskan dulu/);
  const nav0 = (await u.call('api_getGameState', [null])).stats.Navigation;
  const ship0 = (await u.call('api_getShipState', [])).ship;
  g0 = await gold();
  r = await bx(['choice', 'save']);
  assert(r.barsati.done && r.barsati.step === 16 && r.barsati.choice === 'save' && r.cityId === 'skitraw', 'selesai');
  assert((await gold()) - g0 === 650000 && r.rewards.total === 650000 && r.rewards.refund === 150000, 'hadiah 650.000');
  assert(r.rewards.artifact.equipped && r.rewards.book.new, 'artefak & buku');
  s = await u.call('api_getGameState', [null]);
  assert(s.city.CityId === 'skitraw' && !s.voyage.inTransit, 'merapat di Skitraw');
  assert(s.stats.Navigation === nav0 + 20, 'Navigation +20');
  assert(s.ship.CannonBonusPercent === ship0.CannonBonusPercent + 15 && s.ship.MaxCannonAmmo === ship0.MaxCannonAmmo + 2 && s.ship.TravelMul === 0.9, 'Meriam Satnislaus & Ivankov ' + JSON.stringify(s.ship));
  assert(!s.unlocks.includes('pusaran') && !(await u.call('api_getSailOptions', [])).some(o => o.cityId === 'pusaran'), 'pusaran tertutup');
  assert((await u.call('api_getLibrary', [])).owned.some(b => b.BookId === 'bk_ivankov_maelstrom'), 'buku dimiliki');
  await H.expectError(() => bx(['choice', 'drown']), /Belum ada yang perlu/);
  await u.call('api_unequipArtifact', []);
  await H.expectError(() => u.call('api_sellItem', ['art_satnislaus_cannon', 1]), /bukan barang dagangan/);
  // Meriam Satnislaus tidak pernah keluar dari galian harta
  assert(Number((await H.sql(`select count(*) n from game.item_catalog where type = 'artifact' and coalesce(source, '') <> 'quest' and item_id = 'art_satnislaus_cannon'`))[0].n) === 0, 'tidak bisa digali');

  // Waktu tempuh -10%, batas tercepat tetap, Black Pearl tetap 15 dtk
  const tt = async (ship) => Number((await H.sql(`select game.voy_travel_seconds(game.voy_map_distance('skitraw', 'bjorneo'), $1::jsonb) t`, [JSON.stringify(ship)]))[0].t);
  const base = { Speed: 50, SpeedMultiplier: 1 };
  const t1 = await tt(base), t2 = await tt({ ...base, TravelMul: 0.9 });
  assert(Math.abs(t2 - t1 * 0.9) <= 1, 'waktu tempuh -10% ' + t1 + ' ' + t2);
  const fast = { Speed: 50, SpeedMultiplier: 0.24 };
  assert((await tt(fast)) === (await tt({ ...fast, TravelMul: 0.9 })), 'batas tercepat tetap');
  const near = Number((await H.sql(`select game.voy_travel_seconds((select dmin from game.voy_dist_range()), '{"Speed":50,"SpeedMultiplier":0.24,"TravelMul":0.9}') t`))[0].t);
  assert(near === 25, 'pulau terdekat tetap 25 dtk ' + near);
  assert((await tt({ Legend: 'pearl', TravelMul: 0.9 })) === 15, 'Black Pearl 15 dtk');
  // titik laut quest tidak mengubah rentang jarak (waktu tempuh pemain lain tetap)
  const rg = (await H.sql(`select * from game.voy_dist_range()`))[0];
  assert(rg.dmin > 20 && rg.dmax > 80, 'rentang jarak tanpa titik laut ' + JSON.stringify(rg));

  // Patroli Bebas
  await H.sql(`select game.cfg_set('BarsatiPatrolChance', '100')`);
  await H.sql('update game.ships set condition = 40 where player_id = $1', [pid]);
  const pa0 = (await st()).patrolAt;
  await u.call('api_setSail', ['joungjava']);
  s = await st();
  const shipNow = (await u.call('api_getShipState', [])).ship;
  assert(s.patrolAt && s.patrolAt !== pa0 && shipNow.Condition === shipNow.EffectiveMaxCondition, 'Patroli Bebas memperbaiki kapal');
  await H.shiftTime(400000); s = await u.call('api_getGameState', [null]);
  if (s.voyage.encounterPending) await fight(1);
  await H.sql(`select game.cfg_set('BarsatiPatrolChance', '0')`);
  await H.sql('update game.ships set condition = 40 where player_id = $1', [pid]);
  const pa1 = (await st()).patrolAt;
  await go('skitraw'); await u.call('api_setSail', ['joungjava']);
  assert((await st()).patrolAt === pa1 && (await cond()) === 40, 'tanpa patroli bila peluang 0');
  await go('skitraw');

  // Pemain lain tidak terpengaruh
  const v = await H.user('biasa4'); await v.call('api_createCharacter', ['Pedagang Biasa', 'merchant']);
  assert((await v.call('api_barsati', ['status'])).barsati === null, 'pemain lain belum punya quest');
  assert(!(await v.call('api_getSailOptions', [])).some(o => ['pusaran', 'titik_buta'].includes(o.cityId)), 'pemain lain tidak melihat titik laut');

  // Aman diulang
  const before = await st();
  await H.db.exec(fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0022_barsati.sql'), 'utf8'));
  const after = await st();
  assert(JSON.stringify({ ...before, night: 0 }) === JSON.stringify({ ...after, night: 0 }), 'status utuh setelah migrasi diulang');
  console.log('BARSATI TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
