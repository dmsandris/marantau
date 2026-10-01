// Tes Modul B - Ship, Voyage, Combat, World Events (0003_voyage.sql)
const assert = require('assert');

(async () => {
  const H = await require('./harness').create({ only: f => /^(0001|0003)/.test(f) });
  const u = await H.user('sailor');
  const pid = u.id;

  // --- Pemain dibuat langsung (character creation milik modul lain) ---
  await H.sql(`insert into game.players(player_id, username, character_name, archetype, gold) values ($1, 'sailor', 'Sailor', 'merchant', 50000)`, [pid]);
  await H.sql(`insert into game.character_stats(player_id) values ($1)`, [pid]);
  await H.sql(`insert into game.ships(player_id) values ($1)`, [pid]);
  await H.sql(`insert into game.player_location(player_id, city_id, arrived_game_day) values ($1, 'sunda_empire', 0)`, [pid]);

  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [pid]))[0].gold);
  const setGold = g => H.sql('update game.players set gold = $2 where player_id = $1', [pid, g]);
  const cond = async () => Number((await H.sql('select condition from game.ships where player_id = $1', [pid]))[0].condition);
  const setCond = c => H.sql('update game.ships set condition = $2 where player_id = $1', [pid, c]);
  const loc = async () => (await H.sql('select * from game.player_location where player_id = $1', [pid]))[0];
  const resolve = async () => (await H.sql('select game.resolve_arrival_if_due($1) r', [pid]))[0].r;
  const voyage = async () => (await H.sql('select game.voyage_state($1) v', [pid]))[0].v;
  const lastLog = async () => (await H.sql('select message from game.player_log where player_id = $1 order by id desc limit 1', [pid]))[0].message;
  const setStats = (o) => H.sql(`update game.character_stats set combat=$2, sailing=$3, negotiation=$4, luck=$5 where player_id=$1`,
    [pid, o.combat ?? 35, o.sailing ?? 35, o.negotiation ?? 35, o.luck ?? 15]);

  // ================= SHIP STATE =================
  let st = await u.call('api_getShipState', []);
  const s = st.ship;
  for (const k of ['ShipName', 'Tier', 'Hull', 'MaxHull', 'Cargo', 'Speed', 'Combat', 'Armor', 'Navigation', 'Condition',
    'ConditionDecayPerSail', 'MaxCondition', 'DamageThreshold', 'CargoBonus', 'EffectiveCargo', 'SpeedMultiplier',
    'CannonBonusPercent', 'MaxCannonAmmo', 'ShipUpgrades', 'EffectiveMaxCondition', 'ConditionPct', 'DecayReductionPercent']) {
    assert(k in s, 'field kapal hilang: ' + k);
  }
  assert.strictEqual(s.ShipName, 'The Wandering Gull');
  assert.strictEqual(s.Cargo, 30); assert.strictEqual(s.EffectiveCargo, 30); assert.strictEqual(s.CargoBonus, 0);
  assert.strictEqual(s.SpeedMultiplier, 1); assert.strictEqual(s.MaxCannonAmmo, 3);
  assert.strictEqual(s.EffectiveMaxCondition, 100); assert.strictEqual(s.Condition, 100); assert.strictEqual(s.ConditionPct, 100);
  assert.strictEqual(s.ConditionDecayPerSail, 0.03); assert.strictEqual(s.DamageThreshold, 45);
  assert.deepStrictEqual(s.ShipUpgrades.speed, { level: 0, tier: 0, accumulated: 0 });
  assert.strictEqual((await H.sql('select game.effective_cargo($1) c', [pid]))[0].c, 30);
  assert.strictEqual((await H.sql('select game.current_city($1) c', [pid]))[0].c, 'sunda_empire');
  assert.strictEqual((await H.sql('select game.in_transit($1) t', [pid]))[0].t, false);
  console.log('ship state OK');

  // ================= UPGRADES =================
  let up = await u.call('api_getShipUpgrades', []);
  assert(up.allCatalogs.speed.length === 4 && up.allCatalogs.cannons[3].ammoBonus === 4);
  assert.strictEqual(up.affordable.cargo.cost, 1000);
  assert.strictEqual(up.affordable.cargo.currentLabel, 'Belum di-upgrade');
  assert.strictEqual(up.affordable.cargo.nextLabel, 'Level I &middot; Tier I');
  assert.strictEqual(up.affordable.cargo.affordable, true);
  assert.deepStrictEqual(up.current.cargo, { level: 0, tier: 0, accumulated: 0 });

  await H.expectError(() => u.call('api_shipUpgrade', ['hull']), /^Grup upgrade tidak dikenali: hull/);
  let g0 = await gold();
  let r = await u.call('api_shipUpgrade', ['cargo']);
  assert.strictEqual(r.success, true); assert.strictEqual(r.goldSpent, 1000); assert.strictEqual(r.newGold, g0 - 1000);
  assert.strictEqual(r.newLevelTierLabel, 'Level I &middot; Tier I'); assert.strictEqual(r.effect, '+5 kapasitas');
  assert.strictEqual(await gold(), g0 - 1000);
  assert.strictEqual(await lastLog(), 'Upgraded ship cargo to Level I - Tier I (+5 kapasitas) for 1000 gold.');
  r = await u.call('api_shipUpgrade', ['cargo']); // tier 2: +15 -> total 20
  st = (await u.call('api_getShipState', [])).ship;
  assert.strictEqual(st.CargoBonus, 20); assert.strictEqual(st.EffectiveCargo, 50);
  assert.strictEqual((await H.sql('select game.effective_cargo($1) c', [pid]))[0].c, 50);

  await u.call('api_shipUpgrade', ['speed']); // 0.80
  await u.call('api_shipUpgrade', ['cannons']); // +5%, +1 ammo
  await u.call('api_shipUpgrade', ['condition']); // +10 max, 0% decay
  await u.call('api_shipUpgrade', ['condition']); // +20 max (acc 30), 5% decay
  st = (await u.call('api_getShipState', [])).ship;
  assert.strictEqual(st.SpeedMultiplier, 0.8); assert.strictEqual(st.CannonBonusPercent, 5); assert.strictEqual(st.MaxCannonAmmo, 4);
  assert.strictEqual(st.EffectiveMaxCondition, 130); assert.strictEqual(st.DecayReductionPercent, 5);
  assert.strictEqual(st.Condition, 100); assert.strictEqual(st.ConditionPct, 77);

  // Level rollover: cargo sudah tier 2 -> beli tier 3, tier 4, lalu Level II tier I (biaya x2)
  await u.call('api_shipUpgrade', ['cargo']); await u.call('api_shipUpgrade', ['cargo']);
  up = await u.call('api_getShipUpgrades', []);
  assert.strictEqual(up.affordable.cargo.nextLabel, 'Level II &middot; Tier I');
  assert.strictEqual(up.affordable.cargo.cost, 2000);
  assert.strictEqual(up.affordable.cargo.label, '+5 kapasitas (skala Level II)');
  r = await u.call('api_shipUpgrade', ['cargo']);
  assert.strictEqual(r.newLevel, 2); assert.strictEqual(r.newTier, 1);
  st = (await u.call('api_getShipState', [])).ship;
  assert.strictEqual(st.CargoBonus, 5 + 15 + 30 + 50 + 10);
  // Maxed
  await H.sql(`update game.players set ship_upgrades = jsonb_set(ship_upgrades, '{speed}', '{"level":5,"tier":4,"accumulated":0}') where player_id = $1`, [pid]);
  up = await u.call('api_getShipUpgrades', []);
  assert.strictEqual(up.affordable.speed.maxed, true); assert.strictEqual(up.affordable.speed.currentLabel, 'Level V &middot; Tier IV');
  await H.expectError(() => u.call('api_shipUpgrade', ['speed']), /sudah Level V Tier IV \(Legendary\)/);
  // Format lama: angka polos
  await H.sql(`update game.players set ship_upgrades = '{"speed":1,"cargo":2}' where player_id = $1`, [pid]);
  up = await u.call('api_getShipUpgrades', []);
  assert.deepStrictEqual(up.current.cargo, { level: 1, tier: 2, accumulated: 15 });
  assert.deepStrictEqual(up.current.cannons, { level: 0, tier: 0, accumulated: 0 });
  // Gold kurang
  await setGold(10);
  await H.expectError(() => u.call('api_shipUpgrade', ['cargo']), /^Gold tidak cukup\. Butuh 5000, kamu punya 10\./);
  // Setup upgrade yang dipakai sisa tes: speed L1T2 (0.65), condition L1T2 (+30 max, -5% decay), cannons L1T1
  await H.sql(`update game.players set ship_upgrades = '{"speed":{"level":1,"tier":2,"accumulated":0},"cargo":{"level":0,"tier":0,"accumulated":0},"condition":{"level":1,"tier":2,"accumulated":30},"cannons":{"level":1,"tier":1,"accumulated":0}}' where player_id = $1`, [pid]);
  await setGold(50000);
  console.log('upgrades OK');

  // ================= REPAIR =================
  await setCond(100);
  let q = await u.call('api_getRepairQuote', ['sunda_empire']);
  assert.deepStrictEqual(q, { currentCondition: 100, maxCondition: 130, missing: 30, cost: 450 });
  q = await u.call('api_getRepairQuote', ['bjorneo']); // rate 1.6
  assert.strictEqual(q.cost, 720);
  await H.expectError(() => u.call('api_repairShip', ['bjorneo']), /^Kamu harus berada di kota ini untuk reparasi\./);
  await setGold(100);
  await H.expectError(() => u.call('api_repairShip', ['sunda_empire']), /^Gold tidak cukup\. Butuh 450, kamu punya 100\./);
  await setGold(50000);
  r = await u.call('api_repairShip', ['sunda_empire']);
  assert.deepStrictEqual(r, { success: true, newCondition: 130, goldSpent: 450, newGold: 49550 });
  assert.strictEqual(await cond(), 130);
  await H.expectError(() => u.call('api_repairShip', ['sunda_empire']), /^Kapal sudah dalam kondisi penuh\./);
  assert(/^Repaired the ship at Sunda Empire for 450 gold/.test(await lastLog()));
  // apply_condition_delta clamp
  assert.strictEqual(Number((await H.sql('select game.apply_condition_delta($1, 500) c', [pid]))[0].c), 130);
  assert.strictEqual(Number((await H.sql('select game.apply_condition_delta($1, -2.4) c', [pid]))[0].c), 128);
  await setCond(130);
  console.log('repair OK');

  // ================= SAIL OPTIONS =================
  const opts = await u.call('api_getSailOptions', []);
  assert.strictEqual(opts.length, 5);
  assert(!opts.some(o => o.cityId === 'sunda_empire'));
  const jo = opts.find(o => o.cityId === 'joungjava');
  // sunda (25,55) -> joungjava (60,30): sqrt(35^2+25^2) = 43.01
  assert.strictEqual(jo.distance, 43);
  assert.strictEqual(jo.name, 'Joungjava');
  // waktu tempuh dalam detik: 60 (terdekat) .. 130 (terjauh) untuk kapal standar
  assert(jo.etaSeconds > 60 && jo.etaSeconds < 130, 'eta ' + jo.etaSeconds);
  const all = opts.map(o => o.etaSeconds); assert(all.every(x => x >= 60 && x <= 130), 'rentang ' + all);
  assert.strictEqual(jo.eventLabel, null); assert.strictEqual(jo.eventType, null);
  const ikn = opts.find(o => o.cityId === 'ikn'); // (50,62): sqrt(625+49)=25.96 -> 26.0; 6.49*0.65=4.2 -> min 5
  assert.strictEqual(ikn.distance, 26); assert(ikn.etaSeconds < jo.etaSeconds, 'IKN lebih dekat dari Joungjava');
  // Speed ship stat 100 -> factor 2
  await H.sql('update game.ships set speed = 100 where player_id = $1', [pid]);
  const opts2 = await u.call('api_getSailOptions', []);
  const bj1 = opts.find(o => o.cityId === 'bjorneo').etaSeconds, bj2 = opts2.find(o => o.cityId === 'bjorneo').etaSeconds;
  assert(bj2 < bj1 && bj2 >= 60, 'kapal cepat lebih singkat tapi >= 60: ' + bj1 + ' -> ' + bj2);
  // pasangan pulau terdekat = 60 dtk, terjauh = 130 dtk
  const ext = (await H.sql(`select min(game.voy_travel_seconds(game.voy_map_distance(a.city_id, b.city_id), '{"Speed":50,"SpeedMultiplier":1}'::jsonb)) lo, max(game.voy_travel_seconds(game.voy_map_distance(a.city_id, b.city_id), '{"Speed":50,"SpeedMultiplier":1}'::jsonb)) hi from game.cities a join game.cities b on a.city_id < b.city_id`))[0];
  assert(ext.lo === 60 && ext.hi === 130, 'batas ' + JSON.stringify(ext));
  await H.sql('update game.ships set speed = 50 where player_id = $1', [pid]);
  console.log('sail options OK');

  // ================= SET SAIL =================
  await H.expectError(() => u.call('api_setSail', ['atlantis']), /^Kota tujuan tidak dikenali: atlantis/);
  await H.expectError(() => u.call('api_setSail', ['sunda_empire']), /^Kamu sudah berada di kota ini\./);
  const bj = opts.find(o => o.cityId === 'bjorneo');
  let ss = await u.call('api_setSail', ['bjorneo']);
  assert.strictEqual(ss.originCityId, 'sunda_empire'); assert.strictEqual(ss.destinationCityId, 'bjorneo');
  assert.strictEqual(ss.travelSeconds, bj.etaSeconds);
  assert(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(ss.departAt));
  assert.strictEqual(new Date(ss.arriveAt) - new Date(ss.departAt), bj.etaSeconds * 1000);
  assert.strictEqual(await lastLog(), 'Set sail from Sunda Empire toward Bjorneo.');
  await H.expectError(() => u.call('api_setSail', ['joungjava']), /^Kamu sudah dalam perjalanan menuju kota lain\./);
  await H.expectError(() => u.call('api_repairShip', ['sunda_empire']), /^Kamu sedang berlayar - reparasi hanya bisa/);
  assert.strictEqual((await H.sql('select game.in_transit($1) t', [pid]))[0].t, true);

  let v = await voyage();
  assert.strictEqual(v.inTransit, true); assert.strictEqual(v.originCityId, 'sunda_empire'); assert.strictEqual(v.destinationCityId, 'bjorneo');
  assert.strictEqual(v.encounterPending, false); assert.strictEqual(v.encounter, null);
  assert(v.progress >= 0 && v.progress < 0.05, 'progress awal ' + v.progress);
  assert(Math.abs(v.etaSeconds - bj.etaSeconds) <= 2);
  assert.strictEqual(await resolve(), null); // belum waktunya
  await H.shiftTime(bj.etaSeconds * 500);  // separuh jalan
  v = await voyage();
  assert(Math.abs(v.progress - 0.5) < 0.02, 'progress tengah ' + v.progress);
  assert(Math.abs(v.etaSeconds - bj.etaSeconds / 2) <= 2);
  console.log('set sail + progress OK');

  // ================= ARRIVAL (damai) =================
  // Arrival dengan encounter: kalau peluang 1% kena, buang encounter & roll ulang.
  async function arrivePeaceful() {
    for (let i = 0; i < 50; i++) {
      const res = await resolve();
      if (res && res.pendingCombat) { await H.sql('update game.player_location set pending_encounter = null where player_id = $1', [pid]); continue; }
      return res;
    }
    throw new Error('tidak bisa tiba damai');
  }
  await H.sql(`select game.cfg_set('PirateEncounterBaseChance', '0')`);
  await H.sql(`select game.cfg_set('WorldEventRollChancePercent', '0')`);
  await setStats({ luck: 100 });
  await H.shiftTime(bj.etaSeconds * 500 + 1000);
  v = await voyage(); assert.strictEqual(v.progress, 1); assert.strictEqual(v.etaSeconds, 0);
  let g1 = await gold();
  let arr = await arrivePeaceful();
  assert.strictEqual(arr.cityId, 'bjorneo'); assert.strictEqual(arr.pendingCombat, false);
  assert(['calm', 'tailwind', 'storm'].includes(arr.event.type));
  assert.strictEqual(await gold(), Math.max(0, g1 + arr.event.goldDelta));
  // decay 3 poin * (1 - 5%) = 2.85 -> 130 - 2.85 = 127.15 -> 127
  assert.strictEqual(await cond(), 127);
  assert.strictEqual(await lastLog(), 'Made landfall at Bjorneo. ' + arr.event.message);
  let L = await loc();
  assert.strictEqual(L.city_id, 'bjorneo'); assert.strictEqual(L.destination_city_id, null); assert.strictEqual(L.depart_at, null);
  assert.strictEqual((await voyage()).inTransit, false);
  assert.strictEqual(await resolve(), null); // tidak diproses dua kali
  assert.strictEqual(await cond(), 127);
  console.log('arrival OK');

  // ================= WORLD EVENT =================
  await H.sql(`select game.cfg_set('WorldEventRollChancePercent', '100')`);
  await u.call('api_setSail', ['skitraw']);
  await H.shiftTime(15 * 60000);
  arr = await arrivePeaceful();
  assert.strictEqual(arr.cityId, 'skitraw');
  const ev = (await H.sql(`select game.city_event('skitraw') e`))[0].e;
  assert(ev, 'event kota harus muncul');
  assert.deepStrictEqual(Object.keys(ev).sort(), ['cityId', 'eventType', 'expiresGameDay', 'label', 'message', 'priceMultiplierPercent', 'rewardMultiplierPercent']);
  assert.strictEqual(ev.cityId, 'skitraw');
  assert(['storm_surge', 'harvest_bounty', 'festival', 'unrest'].includes(ev.eventType));
  const day = (await H.sql('select game.game_day() d'))[0].d;
  assert(ev.expiresGameDay >= day + 1 && ev.expiresGameDay <= day + 5);
  if (ev.eventType === 'storm_surge') assert(ev.priceMultiplierPercent >= 15 && ev.priceMultiplierPercent <= 25 && ev.rewardMultiplierPercent === 0);
  if (ev.eventType === 'harvest_bounty') assert(ev.priceMultiplierPercent <= -15 && ev.priceMultiplierPercent >= -25);
  if (ev.eventType === 'festival') assert(ev.rewardMultiplierPercent >= 20 && ev.rewardMultiplierPercent <= 40);
  if (ev.eventType === 'unrest') assert(ev.rewardMultiplierPercent <= -15 && ev.rewardMultiplierPercent >= -30);
  assert.strictEqual((await H.sql(`select game.event_price_pct('skitraw') p`))[0].p, ev.priceMultiplierPercent);
  // Tidak overlap: tiba lagi di skitraw tidak membuat event baru
  await u.call('api_setSail', ['joungjava']); await H.shiftTime(15 * 60000); await arrivePeaceful();
  await u.call('api_setSail', ['skitraw']); await H.shiftTime(15 * 60000); await arrivePeaceful();
  assert.strictEqual(Number((await H.sql(`select count(*) n from game.city_events where city_id = 'skitraw'`))[0].n), 1);
  // Sail options menampilkan event
  await u.call('api_setSail', ['joungjava']); await H.shiftTime(15 * 60000); await arrivePeaceful();
  const o3 = (await u.call('api_getSailOptions', [])).find(o => o.cityId === 'skitraw');
  assert.strictEqual(o3.eventLabel, ev.label); assert.strictEqual(o3.eventType, ev.eventType);
  // Kedaluwarsa
  await H.sql(`update game.city_events set expires_game_day = game.game_day() - 1`);
  assert.strictEqual((await H.sql(`select game.city_event('skitraw') e`))[0].e, null);
  await H.sql(`select game.cfg_set('WorldEventRollChancePercent', '0')`);
  console.log('world events OK');

  // ================= ENCOUNTER (TooGood) =================
  await H.sql(`update game.player_location set city_id = 'sunda_empire' where player_id = $1`, [pid]);
  await setCond(130);
  ss = await u.call('api_setSail', ['toogood']);
  await H.shiftTime(ss.travelSeconds * 1000 + 1000);
  const res1 = await resolve();
  assert.strictEqual(res1.pendingCombat, true); assert.strictEqual(res1.cityId, null); assert.strictEqual(res1.event, null);
  const enc = res1.encounter;
  assert(enc.enemyLevel >= 2 && enc.enemyLevel <= 5);
  assert(enc.enemyName.startsWith("TooGood's own "));
  assert.strictEqual(enc.enemyMaxHp, 40 + enc.enemyLevel * 25); assert.strictEqual(enc.enemyHp, enc.enemyMaxHp);
  assert.strictEqual(enc.maxAmmo, 4); assert.strictEqual(enc.ammoRemaining, 4); assert.strictEqual(enc.round, 1);
  assert.strictEqual(await lastLog(), 'Sails spotted on the horizon - a pirate vessel closes in!');
  const res2 = await resolve(); // tidak roll ulang
  assert.deepStrictEqual(res2.encounter, enc);
  v = await voyage(); assert.strictEqual(v.encounterPending, true); assert.deepStrictEqual(v.encounter, enc);
  await H.expectError(() => u.call('api_setSail', ['ikn']), /^Kapal sedang dicegat bajak laut/);
  await H.expectError(() => u.call('api_resolveCombat', ['dance']), /^Taktik tidak dikenali: dance/);

  // Encounter chance non-outlaw: base 60 dengan kapal rusak -> sering kena, level 1..5
  await H.sql(`select game.cfg_set('PirateEncounterBaseChance', '100')`);
  let hits = 0;
  for (let i = 0; i < 40; i++) {
    const e = (await H.sql(`select game.voy_roll_encounter($1, 'ikn') e`, [pid]))[0].e;
    if (e) { hits++; assert(e.enemyLevel >= 1 && e.enemyLevel <= 5); assert(!e.enemyName.startsWith('TooGood')); }
  }
  assert(hits >= 10 && hits < 40, 'hits ' + hits); // clamp 60%
  await H.sql(`select game.cfg_set('PirateEncounterBaseChance', '12')`);
  console.log('encounter OK');

  // ================= COMBAT =================
  // Helper: pasang encounter baru langsung di player_location (voyage sunda -> toogood)
  async function setEncounter(level, extra = {}) {
    const maxHp = 40 + level * 25;
    const e = Object.assign({ enemyLevel: level, enemyName: 'a test raider', rolledAt: new Date().toISOString(), enemyMaxHp: maxHp, enemyHp: maxHp, maxAmmo: 4, ammoRemaining: 4, round: 1 }, extra);
    await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = 'toogood', depart_at = now() - interval '1 hour', arrive_at = now() - interval '1 minute', pending_encounter = $2 where player_id = $1`, [pid, JSON.stringify(e)]);
    return e;
  }
  const curEnc = async () => (await loc()).pending_encounter;

  // --- Meriam kosong: error, ronde tidak dikonsumsi
  await setEncounter(3, { ammoRemaining: 0 });
  await H.expectError(() => u.call('api_resolveCombat', ['fire']), /^Meriam kosong - reload dulu sebelum menembak lagi\./);
  assert.strictEqual((await curEnc()).round, 1);

  // --- Reload: amunisi penuh, ronde +1
  await setCond(130);
  r = await u.call('api_resolveCombat', ['reload']);
  assert.strictEqual(r.ongoing, true); assert.strictEqual(r.encounter.ammoRemaining, 4); assert.strictEqual(r.encounter.round, 2);
  assert(r.message.startsWith('Ronde 1: kru buru-buru mengisi ulang meriam.'));
  assert.strictEqual(r.newCondition, await cond()); assert.strictEqual(r.newGold, await gold());
  if (/menghantam kapal \((-\d+) Condition\)/.test(r.message)) {
    const d = Number(r.message.match(/\((-\d+) Condition\)/)[1]);
    assert(d <= -(6 + 3) && d >= -(13 + 3)); assert.strictEqual(await cond(), 130 + d);
  }

  // --- Fire sampai amunisi habis (musuh HP besar supaya tidak mati)
  await setEncounter(1, { enemyMaxHp: 100000, enemyHp: 100000 });
  for (let i = 0; i < 4; i++) {
    await setCond(130);
    r = await u.call('api_resolveCombat', ['fire']);
    assert.strictEqual(r.ongoing, true); assert.strictEqual(r.encounter.ammoRemaining, 3 - i);
    assert(/tembakan meriam (menghantam|meleset)/.test(r.message));
    if (r.message.includes('menghantam')) { const dmg = Number(r.message.match(/\(-(\d+) HP musuh\)/)[1]); assert(dmg >= 18000 && dmg <= 32000); }
  }
  await H.expectError(() => u.call('api_resolveCombat', ['fire']), /^Meriam kosong/);
  assert.strictEqual((await curEnc()).round, 5);
  assert(Number((await H.sql('select count(*) n from game.combat_log where player_id = $1 and result = $2', [pid, 'round']))[0].n) >= 5);

  // --- Menang lewat fire (HP musuh 1) -> loot, treasure_drop stub (null) aman
  await setStats({ combat: 100 });
  let won = null;
  for (let i = 0; i < 60 && !won; i++) {
    await setEncounter(2, { enemyHp: 1 });
    await setCond(130);
    const gB = await gold();
    r = await u.call('api_resolveCombat', ['fire']);
    if (!r.ongoing) { won = r; won.gB = gB; }
  }
  assert(won, 'fire harus menang');
  assert.strictEqual(won.result, 'won'); assert.strictEqual(won.success, true); assert.strictEqual(won.cityId, 'toogood');
  assert.strictEqual(won.lootItem, null);
  const lootAmt = Number(won.message.match(/menjarah (\d+) gold/)[1]);
  assert(lootAmt >= 360 && lootAmt <= 480, 'loot ' + lootAmt);
  assert.strictEqual(won.newGold, won.gB + lootAmt);
  assert.strictEqual(await gold(), won.gB + lootAmt);
  assert.strictEqual(won.newCondition, 127); // decay setelah tiba
  L = await loc(); assert.strictEqual(L.city_id, 'toogood'); assert.strictEqual(L.pending_encounter, null); assert.strictEqual(L.destination_city_id, null);
  assert.strictEqual(await lastLog(), 'Made landfall at TooGood. ' + won.message);
  const cl = (await H.sql('select * from game.combat_log where player_id = $1 order by id desc limit 1', [pid]))[0];
  assert.strictEqual(cl.result, 'won'); assert.strictEqual(cl.action, 'fire'); assert.strictEqual(cl.enemy_level, 2);
  await H.expectError(() => u.call('api_resolveCombat', ['fire']), /^Tidak ada pertempuran yang sedang menunggu\./);

  // --- Menang dengan drop peta (override kontrak treasure_drop hanya di DB tes)
  await H.sql(`create or replace function game.treasure_drop(p_pid uuid, p_enemy_level int) returns jsonb language plpgsql as $$ begin return jsonb_build_object('itemId', 'map_test', 'name', 'Peta Tes Lv' || p_enemy_level); end $$`);
  won = null;
  for (let i = 0; i < 60 && !won; i++) {
    await setEncounter(2, { enemyHp: 1 }); await setCond(130);
    r = await u.call('api_resolveCombat', ['fire']);
    if (!r.ongoing) won = r;
  }
  assert.deepStrictEqual(won.lootItem, { itemId: 'map_test', name: 'Peta Tes Lv2' });
  assert(won.message.endsWith(' Among the wreckage, the crew salvages Peta Tes Lv2!'));
  assert(/Among the wreckage/.test((await H.sql('select loot from game.combat_log where player_id = $1 order by id desc limit 1', [pid]))[0].loot));
  await H.sql(`create or replace function game.treasure_drop(p_pid uuid, p_enemy_level int) returns jsonb language plpgsql as $$ begin return null; end $$`);

  // --- Ram menang (armor tinggi -> 90%)
  await H.sql('update game.ships set armor = 300 where player_id = $1', [pid]);
  won = null;
  for (let i = 0; i < 60 && !won; i++) {
    await setEncounter(3); await setCond(130);
    const gB = await gold();
    r = await u.call('api_resolveCombat', ['ram']);
    assert.strictEqual(r.ongoing, false);
    if (r.result === 'won') { won = r; won.gB = gB; }
  }
  assert(won, 'ram harus menang');
  assert.strictEqual(won.newGold, won.gB + 900); // 200 * 3 * 1.5
  assert(won.message.includes('kru menjarah 900 gold dari puing'));
  assert.strictEqual((await H.sql('select loot from game.combat_log where player_id = $1 order by id desc limit 1', [pid]))[0].loot, '900 gold (ram)');

  // --- Ram gagal (armor 0, combat 0, level 5 -> 5%) -> lost, tetap tiba di tujuan
  await H.sql('update game.ships set armor = 0 where player_id = $1', [pid]);
  await setStats({ combat: 0 });
  let lost = null;
  for (let i = 0; i < 60 && !lost; i++) {
    await setEncounter(5); await setCond(130);
    r = await u.call('api_resolveCombat', ['ram']);
    if (r.result === 'lost') lost = r;
  }
  assert(lost); assert.strictEqual(lost.success, false); assert.strictEqual(lost.cityId, 'toogood');
  const afterRam = await cond();
  assert(afterRam >= 130 - 35 - 3 && afterRam <= 130 - 22 - 2, 'cond setelah ram ' + afterRam);

  // --- Tenggelam (ram gagal dengan kondisi rendah): kembali ke asal, 25% kondisi, gold -15%, cargo -50%
  await H.sql(`insert into game.inventory(player_id, item_id, qty) values ($1, 'sugar', 9), ($1, 'rum', 1), ($1, 'map_x', 3)
    on conflict (player_id, item_id) do update set qty = excluded.qty`, [pid]);
  let sunk = null;
  for (let i = 0; i < 60 && !sunk; i++) {
    await setEncounter(5); await setCond(10); await setGold(1000);
    r = await u.call('api_resolveCombat', ['ram']);
    if (r.result === 'sunk') sunk = r;
    else await H.sql(`update game.inventory set qty = case item_id when 'sugar' then 9 when 'rum' then 1 else 3 end where player_id = $1`, [pid]);
  }
  assert(sunk); assert.strictEqual(sunk.cityId, 'sunda_empire'); assert.strictEqual(sunk.success, false);
  assert(sunk.message.includes('150 gold were lost to the sea'));
  assert.strictEqual(sunk.newGold, 850);
  // 0 + 130*0.25 = 32.5 -> 33 ; decay 2.85 -> 30.15 -> 30
  assert.strictEqual(await cond(), 30);
  const inv = Object.fromEntries((await H.sql('select item_id, qty from game.inventory where player_id = $1', [pid])).map(x => [x.item_id, x.qty]));
  assert.strictEqual(inv.sugar, 4); assert.strictEqual(inv.rum, 0); assert.strictEqual(inv.map_x, 3); // item bukan komoditas tidak hilang
  assert.strictEqual((await loc()).city_id, 'sunda_empire');

  // --- Flee (gagal = ronde lanjut, berhasil = fled)
  await setStats({ sailing: 100 });
  let fled = null, fleeFail = 0;
  for (let i = 0; i < 80 && !fled; i++) {
    if (!(await loc()).pending_encounter) await setEncounter(2);
    await setCond(130);
    r = await u.call('api_resolveCombat', ['flee']);
    if (r.ongoing) { fleeFail++; assert(/upaya kabur gagal/.test(r.message)); assert(r.newCondition <= 125 && r.newCondition >= 119); }
    else fled = r;
  }
  assert(fled); assert.strictEqual(fled.result, 'fled'); assert.strictEqual(fled.success, true); assert.strictEqual(fled.cityId, 'toogood');

  // --- Bribe: gold kurang -> error; cukup -> bribed, biaya sesuai HP tersisa
  await setEncounter(4); await setGold(10);
  await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /^Gold tidak cukup untuk menyuap \(butuh 600 gold\)\./);
  assert.strictEqual((await curEnc()).round, 1);
  await setGold(5000);
  await setEncounter(4, { enemyHp: 70 }); // 70/140 = 0.5 -> 150*4*0.5 = 300
  r = await u.call('api_resolveCombat', ['bribe']);
  assert.strictEqual(r.result, 'bribed'); assert.strictEqual(r.success, true); assert.strictEqual(r.newGold, 4700);
  assert(r.message.startsWith('Ronde 1: 300 gold berpindah tangan'));
  await setEncounter(1, { enemyHp: 1 }); // max(50, 150*1*0.25=37.5) = 50
  r = await u.call('api_resolveCombat', ['bribe']);
  assert.strictEqual(r.newGold, 4650);

  // --- Negotiate: gagal = upeti (min(200*L*0.3, gold)), berhasil = negotiated
  await setStats({ negotiation: 100 });
  let neg = null, negFail = 0;
  for (let i = 0; i < 80 && !neg; i++) {
    if (!(await loc()).pending_encounter) await setEncounter(2);
    await setGold(5000); await setCond(130);
    r = await u.call('api_resolveCombat', ['negotiate']);
    if (r.ongoing) { negFail++; assert.strictEqual(r.newGold, 5000 - 120); assert(r.message.includes('upeti kecil 120 gold')); }
    else neg = r;
  }
  assert(neg); assert.strictEqual(neg.result, 'negotiated'); assert.strictEqual(neg.success, true);
  // Upeti dibatasi gold yang ada
  await setStats({ negotiation: 0 });
  let capped = false;
  for (let i = 0; i < 80 && !capped; i++) {
    await setEncounter(5); await setGold(7);
    r = await u.call('api_resolveCombat', ['negotiate']);
    if (r.ongoing) { capped = true; assert.strictEqual(r.newGold, 0); assert(r.message.includes('upeti kecil 7 gold')); }
  }
  assert(capped);
  console.log('combat OK (flee gagal ' + fleeFail + 'x, negosiasi gagal ' + negFail + 'x)');

  // ================= Tanpa login =================
  const anon = await H.anon();
  await H.expectError(() => anon.call('api_getShipState', []), /AUTH_REQUIRED/);

  console.log('VOYAGE TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
