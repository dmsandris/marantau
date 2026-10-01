// Quest Warwerwor: surat pelikan -> Marie Regal -> Surat Damai (akta penyerahan) -> Marlya -> alyfindi -> sekutu
// -> Perang Genderang (drone, alyfindi, logistik, Kapal Induk, pengkhianatan Hasiolan) -> Marie Regal merdeka.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('genderang'); await u.call('api_createCharacter', ['Penabuh Genderang', 'explorer']);
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  const ww = a => u.call('api_warwerwor', a);
  const st = async () => (await u.call('api_getGameState', [null])).warwerwor;
  const clock = f => H.sql(`select game.cfg_set('WorldStartTimestamp', (game.now_ms() - ($1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint)::text)`, [f]);
  const day = () => clock(0.3), night = () => clock(0.8);
  const qdata = async () => (await H.sql(`select step, data from game.player_quests where player_id = $1 and quest_id = 'warwerwor'`, [u.id]))[0];
  const sail = async (dest) => { await u.call('api_setSail', [dest]); await H.shiftTime(400000); return u.call('api_getGameState', [null]); };
  const fight = async (hpLeft) => {
    if (hpLeft != null) await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', to_jsonb($2::numeric)) where player_id = $1`, [u.id, hpLeft]);
    let fr;
    for (let i = 0; i < 60; i++) {
      await H.sql('update game.ships set condition = greatest(condition, 90) where player_id = $1', [u.id]);
      fr = await u.call('api_resolveCombat', ['fire']); if (!fr.ongoing) break;
      if (fr.encounter.ammoRemaining === 0) await u.call('api_resolveCombat', ['reload']);
    }
    return fr;
  };
  await H.sql('update game.players set gold = 100000 where player_id = $1', [u.id]);

  // belum tersedia sebelum TooGood merdeka
  assert((await st()) === null, 'tersembunyi sebelum TooGood merdeka');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6), ($1, 'toogood', 10)`, [u.id]);
  let s = await st();
  assert(s && s.step === 0 && !s.letter, 'belum ada surat');
  await H.expectError(() => ww(['accept']), /Tidak ada surat/);
  // berlayar dari pulau lain tidak memicu pelikan
  await go('skitraw'); await sail('joungjava');
  assert(!(await st()).letter, 'pelikan hanya datang dari TooGood');
  await go('toogood'); await u.call('api_setSail', ['skitraw']);
  s = (await ww(['status'])).warwerwor;
  assert(s.letter, 'pelikan datang saat berlayar dari TooGood');
  // surat bisa dibaca di tengah laut; sobek -> kembali 24 jam lagi
  let r = await ww(['tear']);
  assert(r.torn && !r.warwerwor.letter && r.warwerwor.letterInMs > 23 * 3600000, 'disobek ' + JSON.stringify(r.warwerwor));
  await H.expectError(() => ww(['accept']), /Tidak ada surat/);
  await H.sql(`update game.player_quests set data = data || jsonb_build_object('tornAt', game.now_ms() - 86400001) where player_id = $1 and quest_id = 'warwerwor'`, [u.id]);
  assert((await st()).letter, 'surat kembali setelah 24 jam');
  // Marie Regal belum di peta
  assert(!(await u.call('api_getSailOptions', [])).some(o => o.cityId === 'marie_regal'), 'Marie Regal tersembunyi');
  r = await ww(['accept']);
  assert(r.accepted && r.warwerwor.step === 1 && r.unlocks.includes('marie_regal') && r.warwerwor.marketClosed, 'diterima');
  assert(Math.abs(r.warwerwor.daysLeft - 60) < 0.2, 'tenggat 60 hari ' + r.warwerwor.daysLeft);
  await H.shiftTime(400000); await u.call('api_getGameState', [null]);

  // Babak 1: pasar terkunci untuk pemain ini saja
  await go('sunda_empire');
  const m = await u.call('api_getMarket', ['sunda_empire']);
  assert(m.closed === true, 'pasar tertutup');
  await H.expectError(() => u.call('api_buy', ['sunda_empire', 'beras', 1]), /Toko tutup. Kami diminta diam oleh Pemerintah/);
  await H.sql(`select game.adjust_inventory($1, 'beras', 5)`, [u.id]);
  await H.expectError(() => u.call('api_sell', ['sunda_empire', 'beras', 1]), /Toko tutup/);
  await H.expectError(() => u.call('api_mpPostOrder', ['beras', 1, 50]), /Toko tutup/);
  const v = await H.user('biasa'); await v.call('api_createCharacter', ['Pedagang Biasa', 'merchant']);
  await H.sql(`update game.player_location set city_id = 'sunda_empire' where player_id = $1`, [v.id]);
  assert((await v.call('api_buy', ['sunda_empire', 'beras', 2])).totalCost > 0, 'pemain lain tetap berdagang');
  assert(!(await v.call('api_getSailOptions', [])).some(o => o.cityId === 'marie_regal'), 'pemain lain tidak melihat Marie Regal');
  // potongan kertas warga
  r = await ww(['scrap']); assert(r.piece === 'Toko kami' && r.warwerwor.scraps.length === 1, 'potongan kertas');
  await go('ikn'); await H.expectError(() => ww(['scrap']), /terlalu takut/);

  // Babak 2: Marie Regal - hanya Istana Hening
  await go('ikn');
  assert((await u.call('api_getSailOptions', [])).some(o => o.cityId === 'marie_regal'), 'Marie Regal bisa dituju');
  s = await sail('marie_regal');
  assert(s.city.CityId === 'marie_regal' && s.city.Type === 'Regal', 'tiba di Marie Regal');
  await H.expectError(() => ww(['peace']), /tidak membawa Surat Damai/);
  r = await ww(['audience']); assert(r.warwerwor.step === 2, 'menghadap Ratu Marie');

  // Babak 3: tiga Surat Damai
  await go('ikn'); await H.expectError(() => ww(['peace']), /Tak ada gubernur/);
  for (const c of ['sunda_empire', 'bjorneo']) { await go(c); r = await ww(['peace']); assert(r.signed === c && !r.betrayed, 'tanda tangan ' + c); }
  await H.expectError(() => ww(['peace']), /sudah menandatangani/);
  await go('skitraw'); r = await ww(['peace']);
  assert(r.betrayed && r.warwerwor.step === 3, 'surat ketiga = penyerahan');
  // gubernur yang tertipu menolak memberi misi
  const board = await u.call('api_getMissionBoard', ['skitraw']);
  if (board.offers && board.offers.length) await H.expectError(() => u.call('api_acceptMission', ['skitraw', 0]), /Gubernur menolak/);

  // tenggat: lewat -> surat hangus, pasar terbuka, pelikan datang lagi 24 jam
  const keep = await qdata();
  await H.sql(`update game.player_quests set data = data || jsonb_build_object('deadline', game.now_ms() - 1) where player_id = $1 and quest_id = 'warwerwor'`, [u.id]);
  s = await st();
  assert(s.step === 0 && s.justExpired && !s.marketClosed && !s.letter && s.letterInMs > 23 * 3600000 && s.expired === 1, 'tenggat lewat ' + JSON.stringify(s));
  assert(!(await u.call('api_getSailOptions', [])).some(o => o.cityId === 'marie_regal'), 'Marie Regal hilang lagi');
  await H.sql(`update game.player_quests set step = $2, data = $3 where player_id = $1 and quest_id = 'warwerwor'`, [u.id, keep.step, keep.data]);

  // Babak 4: malam di Marie Regal
  await go('marie_regal'); await day();
  await H.expectError(() => ww(['marlya']), /Lampu-lampu kota masih menyala/);
  await night(); r = await ww(['marlya']);
  assert(r.warwerwor.step === 4 && !r.warwerwor.marketClosed && r.warwerwor.deadlineMs == null, 'Marlya dibebaskan, pasar buka');
  await H.expectError(() => u.call('api_buy', ['marie_regal', 'beras', 1]), /AKSES DITOLAK/);
  await go('sunda_empire'); assert((await u.call('api_buy', ['sunda_empire', 'beras', 1])).totalCost > 0, 'pasar buka lagi');

  // Babak 5: studio dwi, tuduhan, kios alyfindi
  await go('toogood'); await H.expectError(() => ww(['studio', 'x']), /Putuskan/);
  r = await ww(['studio', 'accuse']); assert(r.warwerwor.step === 5 && r.warwerwor.accused, 'menuduh Euis');
  await day(); await H.expectError(() => ww(['kiosk']), /Siang hari/);
  await night(); r = await ww(['kiosk']); assert(r.warwerwor.step === 6, 'kebenaran: alyfindi');
  r = await ww(['apologize']); assert(r.warwerwor.apologized, 'minta maaf');
  await H.expectError(() => ww(['apologize']), /Tidak ada yang perlu/);

  // sekutu
  await go('joungjava'); await H.expectError(() => ww(['restore']), /tidak pernah tertipu/);
  for (const c of ['sunda_empire', 'bjorneo']) { await go(c); r = await ww(['restore']); assert(r.restored === c && !r.war, 'pulih ' + c); }
  await go('skitraw'); r = await ww(['restore']); assert(!r.war, 'perang menunggu armada Skitraw');
  r = await ww(['skitraw']); assert(r.war && r.warwerwor.step === 7, 'PERANG GENDERANG dimulai');

  // Fase 1: setiap pelayaran dicegat drone (8), lalu alyfindi
  await go('toogood');
  for (let i = 1; i <= 8; i++) {
    s = await sail(i % 2 ? 'ikn' : 'toogood');
    assert(s.voyage.encounterPending && s.voyage.encounter.boss === 'drone' && s.voyage.encounter.droneNo === i, 'drone ' + i);
    if (i === 1) {
      await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /PERMINTAAN DITOLAK/);
      await H.expectError(() => u.call('api_resolveCombat', ['ram']), /tak ada lambung/);
    }
    const g0 = await gold(); r = await fight(1);
    assert(r.result === 'won' && r.questEvent === 'drone' && (await gold()) - g0 >= 600, 'drone jatuh ' + i + ' ' + JSON.stringify(r).slice(0, 160));
  }
  s = await sail('ikn');
  assert(s.voyage.encounter.boss === 'alyfindi', 'kapal komando alyfindi');
  r = await u.call('api_resolveCombat', ['flee']); assert(r.result === 'fled', 'mundur aman');
  s = await u.call('api_getGameState', [null]); assert(s.city.CityId === 'toogood', 'mundur ke pelabuhan asal');
  s = await sail('ikn'); assert(s.voyage.encounter.boss === 'alyfindi', 'alyfindi menunggu lagi');
  const g1 = await gold(); r = await fight(1);
  assert(r.questEvent === 'alyfindi' && (await gold()) - g1 >= 15000, 'alyfindi ditangkap');
  s = await st(); assert(s.step === 8, 'Fase 2');

  // Fase 2: logistik dicicil
  await go('toogood'); await H.expectError(() => ww(['supply']), /Palkamu tidak membawa/);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 50)`, [u.id]); await H.sql(`select game.adjust_inventory($1, 'arms', 10)`, [u.id]);
  r = await ww(['supply']); assert(!r.ready && r.moved.mesiu === 40 && r.moved.arms === 10 && r.warwerwor.supplies.mesiu === 40, 'cicilan 1 ' + JSON.stringify(r));
  assert(Number((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = 'mesiu'`, [u.id]))[0].qty) === 10, 'sisa mesiu tetap di palka');
  await H.sql(`select game.adjust_inventory($1, 'arms', 15)`, [u.id]); await H.sql(`select game.adjust_inventory($1, 'besi', 20)`, [u.id]);
  r = await ww(['supply']); assert(r.ready && r.warwerwor.step === 9 && r.warwerwor.indukHp === 3000, 'gudang penuh');

  // Fase 3: Kapal Induk - hanya di rute ke Marie Regal, HP tersimpan antar serangan
  s = await sail('ikn'); assert(!s.voyage.encounterPending || s.voyage.encounter.boss !== 'induk', 'tidak di rute lain');
  if (s.voyage.encounterPending) { await fight(1); }
  await go('toogood'); s = await sail('marie_regal');
  let e = s.voyage.encounter;
  assert(e.boss === 'induk' && e.enemyHp === 3000 && e.hpFloor === 1500 && e.allyDmg >= 50, 'Kapal Induk ' + JSON.stringify(e));
  r = await u.call('api_resolveCombat', ['fire']);
  assert(r.ongoing && r.encounter.enemyHp < 3000 && /menghujani musuh/.test(r.message), 'sekutu ikut menembak ' + r.message);
  const hpMid = r.encounter.enemyHp;
  r = await u.call('api_resolveCombat', ['flee']); assert(r.result === 'fled', 'mundur');
  s = await u.call('api_getGameState', [null]);
  assert(s.city.CityId === 'toogood' && s.warwerwor.indukHp === hpMid, 'HP tersimpan & kembali ke TooGood ' + s.warwerwor.indukHp + ' ' + hpMid);
  // karam ringan: tidak kehilangan muatan/gold
  s = await sail('marie_regal');
  const g2 = await gold(); await H.sql(`select game.adjust_inventory($1, 'beras', 10)`, [u.id]);
  const beras0 = Number((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = 'beras'`, [u.id]))[0].qty);
  await H.sql('update game.ships set condition = 1 where player_id = $1', [u.id]);
  for (let i = 0; i < 30; i++) { r = await u.call('api_resolveCombat', ['reload']); if (!r.ongoing) break; await H.sql('update game.ships set condition = 1 where player_id = $1', [u.id]); }
  assert(r.result === 'sunk' && (await gold()) === g2 && Number((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = 'beras'`, [u.id]))[0].qty) === beras0, 'karam ringan');
  s = await u.call('api_getGameState', [null]); assert(s.city.CityId === 'toogood', 'ditarik ke TooGood');
  // separuh HP -> pengkhianatan
  s = await sail('marie_regal'); r = await fight(1501);
  assert(r.questEvent === 'betrayal' && r.result === 'won', 'pengkhianatan ' + JSON.stringify(r).slice(0, 200));
  s = await u.call('api_getGameState', [null]);
  assert(s.warwerwor.step === 10 && s.warwerwor.indukHp === 1500 && s.city.CityId === 'toogood', 'Hasiolan berkhianat');
  // duel Hasiolan
  s = await sail('marie_regal'); e = s.voyage.encounter;
  assert(e.boss === 'hasiolan' && e.allyNote === 'Kapal Uda Gala', 'duel Hasiolan');
  r = await fight(1); assert(r.questEvent === 'hasiolan', 'Hasiolan kalah');
  s = await u.call('api_getGameState', [null]); assert(s.warwerwor.step === 11 && s.city.CityId === 'toogood', 'perisai padam');
  // serbuan terakhir
  s = await sail('marie_regal'); e = s.voyage.encounter;
  assert(e.boss === 'induk' && e.final && e.enemyHp === 1500 && e.hpFloor == null, 'serbuan terakhir ' + JSON.stringify(e));
  const g3 = await gold(); r = await fight(1);
  assert(r.questEvent === 'finale' && (await gold()) - g3 === 250000, 'hadiah 250.000');
  s = await u.call('api_getGameState', [null]);
  assert(s.warwerwor.done && s.city.CityId === 'marie_regal', 'Marie Regal merdeka, kapal tiba');
  // pasar & toko teknologi Marie Regal terbuka
  assert((await u.call('api_buy', ['marie_regal', 'beras', 1])).totalCost > 0, 'pasar Marie Regal buka');
  const lib = await u.call('api_getLibrary', []);
  assert(lib.available.some(b => b.BookId === 'bk_mr_engine'), 'toko teknologi');
  const sp0 = (await u.call('api_getShipState', [])).ship.Speed, cm0 = (await u.call('api_getShipState', [])).ship.EffectiveMaxCondition;
  await H.sql('update game.players set gold = 200000 where player_id = $1', [u.id]);
  await u.call('api_buyBook', ['bk_mr_engine']); await u.call('api_buyBook', ['bk_mr_hull']);
  const sh = (await u.call('api_getShipState', [])).ship;
  assert(sh.Speed === sp0 + 10 && sh.EffectiveMaxCondition === cm0 + 50, 'Mesin Uap Marlya & Lambung Baja');
  // setelah selesai tidak ada pertempuran perang lagi
  for (let i = 0; i < 5; i++) assert((await H.sql(`select game.ww_encounter($1, 'marie_regal') e`, [u.id]))[0].e === null, 'perang usai');
  console.log('WARWERWOR TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
