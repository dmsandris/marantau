// Saga 2 · Quest 8 "Lima Tangan": prolog di TooGood (syarat saldo bank) -> lima tangan (Skitraw, Joungjava,
// Marie Regal, Paradiso, Bjorneo) + bahan dok -> Black Pearl (ransum Laut Timur, kelaparan) -> FreeYork
// (Tempa Pengait) -> Jaring Angin & Karang Garam (Marlin, Selam Mutiara) -> Pelabuhan Rantai Lama (Sandi,
// Jejak, Hasiolan) -> Kota Sowtour (Blokade Gagak, tiga menara, Mata Seribu) -> genderang -> Topi di Kemudi.
// Juga menjaga: pulau tersembunyi untuk pemain lain, waktu tempuh lama, peran pasar, pasar dunia tidak dikacaukan.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('limatangan1'); await u.call('api_createCharacter', ['Nakhoda Keenam', 'merchant']);
  const other = await H.user('limatangan2'); await other.call('api_createCharacter', ['Penonton', 'navigator']);
  const pid = u.id;
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const lt = a => u.call('api_limatangan', a);
  const st = async () => (await u.call('api_limatangan', ['status'])).limatangan;
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const item = async id => Number((await one('select game.item_qty($1, $2) q', [pid, id])).q);
  const give = (id, n) => H.sql(`select game.adjust_inventory($1, $2, $3)`, [pid, id, n]);
  const city = async () => (await one('select city_id from game.player_location where player_id = $1', [pid])).city_id;
  const cond = async () => Number((await one(`select (game.ship_json($1) ->> 'Condition')::numeric c`, [pid])).c);
  const dayLenMin = Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) v`)).v);
  const hourMs = dayLenMin * 60000 / 24;
  const setFrac = async f => {
    const r = await one(`select game.now_ms() n, game.cfg_num('WorldStartTimestamp', 0) s`);
    const len = dayLenMin * 60000, cur = ((Number(r.n) - Number(r.s)) % len) / len;
    let d = f - cur; if (d < 0) d += 1;
    await H.shiftTime(Math.round(d * len) + 1000);
  };
  const night = () => setFrac(0.8), day = () => setFrac(0.35), dawn = () => setFrac(0.96), pagi = () => setFrac(0.15);
  const nextNight = async () => { await setFrac(0.3); await setFrac(0.8); };
  let lastFight = [];
  const fightOut = async (tactic) => {
    let last = null; lastFight = [];
    for (let i = 0; i < 200; i++) {
      const s = await u.call('api_getGameState', [null]);
      if (!s.voyage.inTransit || !s.voyage.encounterPending) return last;
      await H.sql('update game.ships set condition = greatest(condition, 90) where player_id = $1', [pid]);
      if (tactic === 'win') await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '1'::jsonb) - 'immuneFirst' where player_id = $1`, [pid]);
      const enc = s.voyage.encounter;
      if (tactic === 'flee') { last = await u.call('api_resolveCombat', ['flee']); lastFight.push(last); continue; }
      last = await u.call('api_resolveCombat', [enc.ammoRemaining > 0 ? 'fire' : 'reload']);
      lastFight.push(last);
    }
    return last;
  };
  const sail = async (dest, tactic) => { await u.call('api_setSail', [dest]); await H.shiftTime(900000); const s = await u.call('api_getGameState', [null]); await fightOut(tactic || 'win'); return s; };

  // --- Penjaga dunia ------------------------------------------------------------
  for (const c of ['karang_garam', 'rantai_lama', 'sowtour']) {
    const row = await one('select hidden from game.cities where city_id = $1', [c]);
    assert(row && row.hidden === true, c + ' tersembunyi');
    assert((await one(`select game.city_open($1, $2) o`, [other.id, c])).o === false, c + ' tertutup untuk pemain lain');
  }
  for (const c of ['karang_garam', 'sowtour']) {
    const n = await one(`select count(*)::int n from game.market where city_id = $1`, [c]);
    const all = await one(`select count(*)::int n from game.commodities where active`);
    assert(n.n === all.n, c + ' pasar lengkap');
  }
  const R = async (c, comm) => (await one('select role from game.market where city_id = $1 and commodity_id = $2', [c, comm])).role;
  assert(await R('karang_garam', 'garam') === 'produce' && await R('karang_garam', 'beras') === 'consume', 'peran pasar Karang Garam');
  assert(await R('sowtour', 'porselen') === 'produce' && await R('sowtour', 'beras') === 'consume', 'peran pasar Sowtour');
  assert(await R('freeyork', 'besi') === 'produce' && await R('sunda_empire', 'garam') === 'produce', 'peran pasar lama tidak berubah');
  assert((await one(`select game.spot_city('rantai_lama') s`)).s === true, 'Rantai Lama kota hantu (titik quest)');
  const rng = await one(`select dmax from game.voy_dist_range()`);
  const rngOld = await one(`select max(game.voy_map_distance(a.city_id, b.city_id)) dmax from game.cities a join game.cities b on a.city_id < b.city_id
    where not game.spot_city(a.city_id) and not game.spot_city(b.city_id) and not game.voy_far_city(a.city_id) and not game.voy_far_city(b.city_id)`);
  assert(Math.abs(Number(rng.dmax) - Number(rngOld.dmax)) < 1e-9, 'rentang jarak dunia tidak ikut tempat baru');
  const tFy = Number((await one(`select game.voy_travel_seconds(game.voy_map_distance('sunda_empire', 'freeyork'), '{}'::jsonb) t`)).t);
  assert(tFy > 240 && tFy <= 360, 'Sunda -> FreeYork tetap: ' + tFy);
  const marlin = await one(`select l_available, cities from game.mp_fish_types where id = 'marlin_garam'`);
  assert(marlin.l_available === true && marlin.cities[0] === 'karang_garam', 'Marlin Garam di Karang Garam');

  // --- Prasyarat ------------------------------------------------------------------
  assert((await st()) === null, 'tersembunyi sebelum Quest 7 selesai');
  await H.expectError(() => lt(['prolog']), /masih tertidur/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at, data) values
    ($1, 'gala', 6, now(), '{}'), ($1, 'toogood', 10, now(), '{}'), ($1, 'warwerwor', 12, now(), '{}'), ($1, 'barsati', 16, now(), '{}'),
    ($1, 'kompas', 8, now() - interval '30 days', '{"truth":"bohong"}'), ($1, 'cocoepan', 11, now(), '{}'),
    ($1, 'tigasilang', 12, now(), '{"tempa":"biarkan","garlyena":"simpan","upayy_answer":"sendiri"}')`, [pid]);
  await H.sql(`update game.player_quests set updated_at = now() - interval '30 days' where player_id = $1 and quest_id = 'kompas'`, [pid]);
  await H.sql(`select game.item_adjust($1, 'qi_kompas_dua_jarum', 1), game.item_adjust($1, 'qi_joran_nansy', 1), game.item_adjust($1, 'qi_palu_tempa', 1)`, [pid]);
  await H.sql('update game.players set gold = 2000000 where player_id = $1', [pid]);
  let s = await st();
  assert(s && s.step === 0 && s.bankOk === false, 'menunggu saldo bank ' + JSON.stringify(s && s.bankOk));
  await go('toogood');
  await H.expectError(() => lt(['prolog']), /Belum waktunya/);
  await H.sql('update game.players set bank_balance = 6000000 where player_id = $1', [pid]);
  await go('skitraw');
  await H.expectError(() => lt(['prolog']), /TooGood/);
  await go('toogood');
  s = (await lt(['prolog'])).limatangan;
  assert(s.step === 1 && s.hands.kunci === true && s.hands.kemudi === false, 'prolog -> Babak 1');
  await H.expectError(() => lt(['launch']), /lima tangan/);

  // --- Babak 1: bahan dok -------------------------------------------------------------
  await H.expectError(() => lt(['setor']), /tidak membawa bahan/);
  await give('kayu_jati', 12);
  let r = await lt(['setor']);
  assert(r.moved.kayu_jati === 12 && r.limatangan.dock.kayu_jati === 12 && !r.limatangan.dockReadyAt, 'setor dicicil');

  // Kemudi: Hasiolan (Balas Pantun)
  await go('skitraw');
  await lt(['pantun', 'gagal']);
  await H.expectError(() => lt(['pantun', 'ok']), /lidahmu/);
  await H.shiftTime(hourMs + 1000);
  s = (await lt(['pantun', 'ok', 'perfect'])).limatangan;
  assert(s.hands.kemudi && s.pantunPerfect, 'Hasiolan naik ke kemudi');

  // Peta: coco epan (kopi + ikan pertama saat fajar)
  await go('joungjava');
  await H.expectError(() => lt(['kopi']), /Gading Island/);
  await give('kopi_flores_bajawa', 6); await give('kopi_sumatera_gayo', 7);
  s = (await lt(['kopi'])).limatangan;
  assert(s.cocoKopi === 10 && await item('kopi_sumatera_gayo') === 3, 'sepuluh kopi Stumpy: ' + s.cocoKopi);
  await H.expectError(() => lt(['coco']), /ikan pertamanya/);
  await day();
  assert((await one(`select game.fish_quest_catch($1, 'teri') q`, [pid])).q === null, 'siang: belum fajar');
  await dawn();
  const fq = (await one(`select game.fish_quest_catch($1, 'teri') q`, [pid])).q;
  assert(fq && fq.event === 'cocoFish', 'ikan pertama saat fajar ' + JSON.stringify(fq));
  s = (await lt(['coco'])).limatangan;
  assert(s.hands.peta, 'coco epan naik');

  // Mata: dwi (laboratorium tanpa salah = Titik Inti)
  await go('marie_regal');
  s = (await lt(['lab', '0'])).limatangan;
  assert(s.hands.mata && s.titikInti, 'dwi naik + Titik Inti');

  // Meriam: Bang Rimba (Q5 bohong -> dadu dulu; gasing harus menang; kalah = malam berikutnya)
  await go('paradiso'); await day();
  await H.expectError(() => lt(['gasing', 'won']), /malam/);
  await night();
  await H.expectError(() => lt(['gasing', 'won']), /Untung dulu/);
  for (let i = 0; i < 60 && !(await st()).diceDone; i++) await lt(['dadu', i % 2 ? 'besar' : 'kecil']);
  assert((await st()).diceDone, 'dadu dimenangkan');
  await lt(['gasing', 'lost']);
  await H.expectError(() => lt(['gasing', 'won']), /besok malam/);
  await nextNight();
  s = (await lt(['gasing', 'won'])).limatangan;
  assert(s.hands.meriam && s.rimbaLoss === 1, 'Bang Rimba naik ke meriam');

  // Kayu: Nenek Ulin (tiga teka-teki)
  await go('bjorneo');
  r = await lt(['ulin', 'Lubang']);
  assert(r.correct === true && r.limatangan.ulinIdx === 1, 'teka-teki 1');
  r = await lt(['ulin', 'bayangan']);
  assert(r.correct === false, 'jawaban salah');
  await H.expectError(() => lt(['ulin', 'masa depan']), /menyalakan mercusuar/);
  await H.shiftTime(hourMs + 1000);
  r = await lt(['ulin', 'Masa Depan!']);
  r = await lt(['ulin', 'kayu ulin']);
  assert(r.item && r.item.itemId === 'qi_papan_ulin' && await item('qi_papan_ulin') === 1, 'Papan Ulin Tua');
  // Kuas Tedsky (opsional)
  await go('ikn'); await lt(['kuas']);
  assert(await item('qi_kuas_tedsky') === 1, 'kuas perunggu');

  // Setor sisa bahan -> satu hari game
  await go('toogood');
  await give('kayu_jati', 8); await give('besi', 15); await give('rotan', 10); await give('mesiu', 20);
  r = await lt(['setor']);
  assert(r.limatangan.dockReadyAt && !r.limatangan.dockReady && await item('qi_papan_ulin') === 0, 'bahan lengkap, tukang bekerja');
  await H.expectError(() => lt(['launch']), /tiang ulin/);
  await H.shiftTime(dayLenMin * 60000 + 1000);
  const ownName = (await one('select ship_name from game.ships where player_id = $1', [pid])).ship_name;
  r = await lt(['launch']);
  assert(r.limatangan.step === 2 && r.pearl && r.ship.ShipName === 'Black Pearl' && r.ship.Tier === 'V', 'Black Pearl berlayar');

  // --- Black Pearl & ransum -------------------------------------------------------------
  const opts = await u.call('api_getSailOptions', []);
  const oSk = opts.find(o => o.cityId === 'skitraw'), oFy = opts.find(o => o.cityId === 'freeyork');
  assert(oSk.etaSeconds === 15 && oSk.ransum === false, 'Mare Nusantara: 15 dtk, tanpa ransum');
  assert(oFy.etaSeconds > 15 && oFy.ransum === true, 'Laut Timur: waktu tempuh normal + ransum ' + oFy.etaSeconds);
  assert(!opts.find(o => o.cityId === 'karang_garam'), 'Karang Garam belum terbuka');
  // tanpa ransum: awak kelaparan, putar balik, -30%
  const c0 = await cond();
  await H.sql(`update game.inventory set qty = 0 where player_id = $1 and item_id in ('beras', 'garam', 'ikan_asin')`, [pid]);
  const sv = await u.call('api_setSail', ['freeyork']);
  assert(sv.ransum === 0, 'peringatan ransum 0');
  await H.shiftTime(900000); await u.call('api_getGameState', [null]);
  assert(await city() === 'toogood' && (await cond()) <= c0 - 89, 'kelaparan: kembali ke TooGood, kondisi -30% (' + c0 + ' -> ' + (await cond()) + ')');
  // ransum cukup: 10 Beras + 5 (Garam lalu Ikan Asin)
  await give('beras', 30); await give('garam', 3); await give('ikan_asin', 12);
  assert((await st()).ransum === 3, 'tiga jatah ransum');
  await sail('freeyork');
  assert(await city() === 'freeyork' && await item('beras') === 20 && await item('garam') === 0 && await item('ikan_asin') === 10, 'ransum terpakai');

  // --- Babak 3: FreeYork ------------------------------------------------------------------
  s = (await lt(['freeyork'])).limatangan;
  assert(s.step === 3 && s.lunasAt && !s.lunasReady && s.tempaFree, 'Dok Legenda menyala');
  await H.expectError(() => lt(['tempa', '95', '3000']), /dipanaskan/);
  r = await lt(['tempa', '40', '60000']);
  assert(r.grade === 'retak' && r.limatangan.hookGrade === 'retak', 'pengait retak');
  await H.expectError(() => lt(['fydone']), /belum jadi/);
  await H.expectError(() => lt(['tempa', '80', '60000']), /memanas/);
  await H.shiftTime(hourMs + 1000);
  await H.sql(`update game.inventory set qty = 0 where player_id = $1 and item_id = 'besi'`, [pid]);
  await H.expectError(() => lt(['tempa', '80', '60000']), /5 Besi/);
  await give('besi', 5);
  r = await lt(['tempa', '75', '60000']);
  assert(r.limatangan.hookGrade === 'baik' && await item('qi_pengait') === 1 && await item('besi') === 0, 'pengait baik');
  await H.expectError(() => lt(['tempa', '95', '60000']), /besok pagi/);
  await H.shiftTime(dayLenMin * 60000 + 1000);
  await give('besi', 10);
  r = await lt(['tempa', '60', '60000']);
  assert(r.limatangan.hookGrade === 'baik', 'tempa ulang lebih buruk: mutu lama dipertahankan');
  r = await lt(['fydone']);
  assert(r.limatangan.step === 4 && r.unlocks.indexOf('karang_garam') >= 0 && await item('qi_nasi_tassyaaa') === 1, 'FreeYork selesai');

  // --- Babak 4: Jaring Angin (kapal ditahan di mulut kabut) ---------------------------------
  await H.expectError(() => lt(['wind', '0']), /Angkat sauh/);
  const kgSail = await u.call('api_setSail', ['karang_garam']);
  await H.shiftTime(kgSail.travelSeconds * 1000 + 1000);
  let gs = await u.call('api_getGameState', [null]);
  assert(gs.voyage.inTransit && gs.limatangan.windDue, 'kapal ditahan di mulut kabut ' + JSON.stringify(gs.voyage) + ' ' + await city() + ' ' + JSON.stringify((await st()).windDone));
  const beras0 = await item('beras');
  r = await lt(['wind', '1']);
  assert(r.lost === 1 && await item('beras') === beras0 - 10, 'satu zona gagal = satu jatah ransum');
  gs = await u.call('api_getGameState', [null]);
  assert(await city() === 'karang_garam', 'tiba di Karang Garam');

  await H.expectError(() => lt(['selam', 'ok', '3']), /Marlin/);
  await lt(['ama']);
  await day(); await give('garam', 2);
  const w = Number((await one(`select game.fish_quest_weight($1, 'marlin_garam', 'karang_garam') w`, [pid])).w);
  assert(w === 40, 'Marlin Garam naik ke kail (siang, umpan garam): ' + w);
  const mq = (await one(`select game.fish_quest_catch($1, 'marlin_garam') q`, [pid])).q;
  assert(mq && mq.quest === 'limatangan' && (await st()).marlin, 'Marlin Garam untuk laut');
  await H.expectError(() => lt(['selam', 'ok', '3']), /pagi/);
  await pagi();
  r = await lt(['selam', 'gagal', '0']);
  assert(r.ok === false && r.limatangan.diveRestAt, 'pingsan: istirahat');
  await H.expectError(() => lt(['selam', 'ok', '3']), /Istirahat/);
  await H.shiftTime(hourMs / 2 + 1000);
  r = await lt(['selam', 'ok', '4']);
  assert(r.limatangan.diveHeart && r.limatangan.beads === 4, 'Hati Karang + 4 butir');
  const mut0 = await item('mutiara');
  r = await lt(['selam', 'ok', '5']);
  assert(r.limatangan.beads === 6 && r.extra === 3 && await item('mutiara') === mut0 + 3, 'kalung penuh, sisa mutiara ke palka');
  await H.expectError(() => lt(['kgdone']), /menunggu jawabanmu/);
  await lt(['advice', 'bersama']);
  r = await lt(['kgdone']);
  assert(r.limatangan.step === 5 && await item('qi_kalung_karang') === 1 && r.unlocks.indexOf('rantai_lama') >= 0, 'Kalung Karang');

  // --- Babak 5: Pelabuhan Rantai Lama ---------------------------------------------------------
  await give('beras', 60); await give('garam', 40);
  await sail('rantai_lama');
  assert(await city() === 'rantai_lama', 'tiba di kota hantu');
  await H.expectError(() => u.call('api_buy', ['rantai_lama', 'beras', 1]), /pedagang|pusaran/i);
  await H.sql('update game.ships set condition = 200 where player_id = $1', [pid]);
  await H.expectError(() => u.call('api_repairShip', ['rantai_lama']), /galangan/);
  await day();
  await H.expectError(() => lt(['sandi', 'ok']), /bulan/);
  await night();
  await lt(['sandi', 'gagal']);
  await H.expectError(() => lt(['sandi', 'ok']), /malam berikutnya/);
  await nextNight();
  s = (await lt(['sandi', 'ok'])).limatangan;
  assert(s.sandiDone && s.sandiNights === 1, 'pesan Marlya terbaca');
  await H.expectError(() => lt(['hasiolan', 'percaya']), /dibaca/);
  await lt(['jejak', 'benar']);
  await H.expectError(() => lt(['jejak', 'salah']), /sekali/);
  r = await lt(['hasiolan', 'percaya']);
  assert(r.limatangan.step === 6 && r.limatangan.jejakOk && r.limatangan.hasiolan === 'percaya' && r.unlocks.indexOf('sowtour') >= 0, 'Babak 5 selesai');

  // --- Babak 6: Blokade Gagak & tiga menara ------------------------------------------------------
  assert((await st()).waves === 3, 'tiga gelombang gagak');
  const g0 = await gold();
  await sail('sowtour');
  assert(await city() === 'sowtour', 'blokade tertembus, tiba di Sowtour');
  assert((await st()).blokWins === 3 && (await gold()) >= g0 + 15000, 'tiga gelombang +15.000 gold');
  assert(lastFight.filter(x => x && x.chained).length === 2, 'gelombang berantai');
  await H.expectError(() => u.call('api_repairShip', ['sowtour']), /Galangan Sowtour tutup/);
  await H.expectError(() => lt(['menara', 'ok', 'first']), /tangga menaranya/);
  await lt(['baayu']);
  await day();
  await H.expectError(() => lt(['menara', 'ok', 'first']), /malam/);
  await night();
  s = (await lt(['menara', 'ok', 'first'])).limatangan;
  assert(s.lit === 1 && s.clean === 1 && s.towerAllow === 0, 'menara Sapa');
  await H.expectError(() => lt(['menara', 'ok', 'first']), /satu cahaya/);
  await nextNight();
  s = (await lt(['menara', 'gagal'])).limatangan;
  assert(s.towerFails === 1 && s.waves === 3, 'cermin retak: +1 gelombang');
  await nextNight();
  assert((await st()).towerAllow === 2, 'katup: dua cahaya malam ini');
  await lt(['menara', 'ok']);
  s = (await lt(['menara', 'ok', 'first'])).limatangan;
  assert(s.step === 7 && s.lit === 3 && s.clean === 2 && s.waves === 0, 'kota bercahaya: ' + JSON.stringify([s.step, s.lit, s.clean]));

  // --- Mata Seribu: menghadang kapal yang meninggalkan Sowtour --------------------------------
  await u.call('api_repairShip', ['sowtour']);
  // mundur dari segmen A: HP tersimpan
  await u.call('api_setSail', ['karang_garam']); await H.shiftTime(900000); gs = await u.call('api_getGameState', [null]);
  assert(gs.voyage.encounterPending && gs.voyage.encounter.boss === 'ms_a', 'Mata Seribu menghadang');
  await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '7700'::jsonb) where player_id = $1`, [pid]);
  await fightOut('flee');
  assert(await city() === 'sowtour' && (await st()).msHp === 7700, 'mundur ke Sowtour, HP tersimpan');
  // menang fase 1 (A -> kawanan -> B; Titik Inti = tanpa kawanan kedua)
  await sail('karang_garam');
  const bosses = lastFight.map(x => x && x.encounter && x.encounter.boss).filter(Boolean);
  assert(bosses.join(',') === 'kawanan,ms_b', 'fase 1 berantai: ' + bosses.join(','));
  s = await st();
  assert(await city() === 'sowtour' && s.msPhase === 3 && s.msHp === 4500 && s.step === 7, 'fase 1 selesai, kembali ke Sowtour');
  assert(lastFight[lastFight.length - 1].questEvent === 'suara', 'sinematik suara yang dikenal');
  // fase 3: murka mengikuti menara bersih (2 -> 1,2x)
  await u.call('api_setSail', ['karang_garam']); await H.shiftTime(900000); gs = await u.call('api_getGameState', [null]);
  assert(gs.voyage.encounter.boss === 'ms3' && Math.abs(gs.voyage.encounter.enemyDmgMul - 3.25) < 1e-6 && gs.voyage.encounter.enemyHp === 4500, 'fase 3 murka 2.6x1.25');
  const g1 = await gold();
  await fightOut('win');
  s = await st();
  assert(s.step === 8 && await city() === 'sowtour' && (await gold()) >= g1 + 60000, 'Mata Seribu tumbang +60.000');

  // --- zafachmie, genderang, topi di kemudi ------------------------------------------------------
  await H.expectError(() => lt(['genderang', '90']), /dirantai/);
  await lt(['zafa']);
  s = (await lt(['genderang', '70'])).limatangan;
  assert(s.allies === 2 && s.drumAt, 'genderang: dua sekutu');
  await H.expectError(() => lt(['genderang', '90']), /istirahat/);
  await H.shiftTime(hourMs + 1000);
  s = (await lt(['genderang', '88'])).limatangan;
  assert(s.allies === 3 && s.drumBest === 88, 'skor tertinggi dipakai');
  s = (await lt(['sekutu'])).limatangan;
  assert(s.step === 9, 'jawaban dari barat');
  const g2 = await gold();
  r = await lt(['tutup']);
  assert(r.limatangan.step === 10 && r.limatangan.done && r.cityId === 'toogood', 'Quest 8 selesai');
  assert(await city() === 'toogood' && (await gold()) === g2 + 300000, 'hadiah 300.000, pulang ke TooGood');
  const ship = await one(`select game.ship_json($1) j, game.ship_legend($1) l`, [pid]);
  assert(ship.l === null && ship.j.ShipName === ownName, 'kapal sendiri kembali: ' + ship.j.ShipName);
  assert(await item('qi_topi_coco') === 1 && await item('qi_kunci_jam_agung') === 1 && await item('qi_kalung_karang') === 1, 'kenang-kenangan');
  const un = (await u.call('api_getGameState', [null])).unlocks;
  assert(un.indexOf('karang_garam') >= 0 && un.indexOf('sowtour') >= 0, 'pelabuhan tetap');
  // kapal sendiri ke Laut Timur: tanpa ransum
  const opts2 = await u.call('api_getSailOptions', []);
  assert(opts2.find(o => o.cityId === 'freeyork').ransum === false, 'aturan ransum berakhir');
  // pemain lain tidak terpengaruh
  const os = await other.call('api_getGameState', [null]);
  assert(os.limatangan === null && os.unlocks.indexOf('sowtour') < 0, 'pemain lain tidak terpengaruh');
  console.log('LIMATANGAN TESTS PASSED');
})().catch(e => { console.error('GAGAL:', e.message); process.exit(1); });
