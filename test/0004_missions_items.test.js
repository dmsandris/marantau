// Tes Modul C: Missions (v8) + Items + Treasure
// Porting skenario misi dari /home/claude/gasemu/test_v8.js + tes item/treasure.
const assert = require('assert');

(async () => {
  const H = await require('./harness').create({ only: f => /^(0001|0004)/.test(f) });

  // Buat pemain langsung lewat SQL (pembuatan karakter milik modul lain)
  async function mkPlayer(username, gold, city) {
    const u = await H.user(username);
    await H.sql(`insert into game.players(player_id, username, character_name, archetype, gold) values ($1, $2, $3, 'merchant', $4)`,
      [u.id, username, username[0].toUpperCase() + username.slice(1), gold]);
    await H.sql('insert into game.character_stats(player_id) values ($1)', [u.id]);
    await H.sql('insert into game.ships(player_id) values ($1)', [u.id]);
    await H.sql('insert into game.player_location(player_id, city_id, arrived_game_day) values ($1, $2, 0)', [u.id, city]);
    return u;
  }
  const one = async (q, p) => (await H.sql(q, p))[0];
  const moveTo = (u, city) => H.sql('update game.player_location set city_id = $2, destination_city_id = null where player_id = $1', [u.id, city]);
  const gold = async u => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const mload = async u => (await one('select game.mission_load($1) n', [u.id])).n;
  const freeHold = async u => (await one('select game.effective_cargo($1) - game.cargo_total($1) n', [u.id])).n;
  const invQty = async (u, item) => ((await one('select coalesce((select qty from game.inventory where player_id = $1 and item_id = $2), 0) q', [u.id, item])).q);

  const A = await mkPlayer('nina', 20000, 'sunda_empire');
  const city = 'sunda_empire';
  const cap = (await one('select game.effective_cargo($1) c', [A.id])).c;
  assert.strictEqual(cap, 30);

  // ---------------- mission board
  const board = await A.call('api_getMissionBoard', [city]);
  console.log(board.offers.map(o => [o.offerIndex, o.type, o.unlocked, o.qty, o.commodityId, o.sourceCityId, o.deliverToCityId, o.reward].join(' ')).join('\n'));
  assert.strictEqual(board.offers.length, 4);
  assert.strictEqual(board.reputationHere, 0);
  assert.strictEqual(typeof board.gameDay, 'number');
  assert.strictEqual(board.offers[0].type, 'courier');
  assert.strictEqual(board.offers[1].type, 'procure');
  assert(board.offers[0].unlocked && board.offers[1].unlocked && !board.offers[2].unlocked && !board.offers[3].unlocked);
  assert.deepStrictEqual(board.offers.map(o => o.minReputation), [0, 0, 5, 15]);
  assert.strictEqual(board.offers[0].typeLabel, 'Titipan');
  assert.strictEqual(board.offers[1].typeLabel, 'Pesanan');
  for (const o of board.offers) {
    assert(Number.isInteger(o.reward) && o.reward >= 1 && Number.isInteger(o.qty));
    if (o.type === 'procure') assert(Number.isInteger(o.estCost) && o.reward > o.estCost);
    else assert(o.sourceCityId === null && o.deliverToCityId !== city);
  }
  // deterministik
  assert.deepStrictEqual(await A.call('api_getMissionBoard', [city]), board);
  const courier = board.offers.find(o => o.type === 'courier' && o.unlocked);
  const procure = board.offers.find(o => o.type === 'procure' && o.unlocked);
  assert(courier && procure, 'board needs both types');
  assert(procure.deliverToCityId === city && procure.sourceCityId && procure.sourceCityId !== city);
  // sumber benar-benar menjual barang itu
  assert((await one('select count(*)::int n from game.market where city_id = $1 and commodity_id = $2', [procure.sourceCityId, procure.commodityId])).n === 1);

  // IKN: 6 penawaran, reward dipotong
  const ikn = await A.call('api_getMissionBoard', ['ikn']);
  assert.strictEqual(ikn.offers.length, 6);
  assert(ikn.offers[4].unlocked && ikn.offers[5].unlocked);

  // World event multiplier (tiruan city_event modul B)
  await H.sql(`create or replace function game.city_event(p_city text) returns jsonb language plpgsql stable as $$
    begin if p_city = 'sunda_empire' then return '{"rewardMultiplierPercent":50}'::jsonb; end if; return null; end $$`);
  const boardEv = await A.call('api_getMissionBoard', [city]);
  assert(boardEv.offers[0].reward > courier.reward, 'event raises courier reward');
  assert(boardEv.offers[1].reward > procure.reward, 'event raises procure reward');
  assert.strictEqual(boardEv.offers[0].qty, courier.qty);
  await H.sql(`create or replace function game.city_event(p_city text) returns jsonb language plpgsql stable as $$ begin return null; end $$`);
  console.log('board ok');

  // reputation gating
  await H.expectError(() => A.call('api_acceptMission', [city, 2]), /Reputasimu di kota ini belum cukup \(butuh Standing 5, kamu punya 0\)/);
  await H.expectError(() => A.call('api_acceptMission', [city, 9]), /Penawaran misi tidak ditemukan/);
  await H.expectError(() => A.call('api_acceptMission', ['joungjava', 0]), /harus berada di kota ini/);
  await H.sql(`update game.player_location set destination_city_id = 'joungjava' where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_acceptMission', [city, 0]), /^Kamu sedang berlayar\.$/);
  await moveTo(A, city);

  // ---------------- courier: dimuat saat accept, terkunci, memakan palka
  assert.deepStrictEqual(await A.call('api_getMissionState', []), { hasActive: false });
  let ms = await A.call('api_acceptMission', [city, courier.offerIndex]);
  assert(ms.hasActive && ms.type === 'courier' && ms.typeLabel === 'Titipan' && ms.loadedQty === courier.qty, JSON.stringify(ms));
  assert.strictEqual(ms.originCityId, city); assert.strictEqual(ms.originCityName, 'Sunda Empire');
  assert.strictEqual(ms.sourceCityId, ''); assert.strictEqual(ms.sourceCityName, '');
  assert.strictEqual(ms.deliverToCityId, courier.deliverToCityId);
  assert.strictEqual(ms.reward, courier.reward);
  assert.deepStrictEqual(await A.call('api_getMissionState', []), ms);
  assert.strictEqual(await mload(A), courier.qty);
  assert.strictEqual(await freeHold(A), cap - courier.qty, 'hold counts mission load');
  // barang misi TIDAK di inventory -> tidak bisa dijual/dititip
  assert.strictEqual(await invQty(A, courier.commodityId), 0);
  await H.expectError(() => H.sql('select game.adjust_inventory($1, $2, -1)', [A.id, courier.commodityId]), /tidak boleh negatif/);
  await H.expectError(() => A.call('api_acceptMission', [city, procure.offerIndex]), /masih punya misi aktif/);
  await H.expectError(() => A.call('api_buyForMission', []), /bukan pesanan barang/);
  // hanya bisa diserahkan di tujuan
  await H.expectError(() => A.call('api_completeMission', []), new RegExp('belum sampai di ' + courier.deliverToCityName));
  await H.sql(`update game.player_location set city_id = $2, destination_city_id = $2 where player_id = $1`, [A.id, courier.deliverToCityId]);
  await H.expectError(() => A.call('api_completeMission', []), /masih berlayar/);
  await moveTo(A, courier.deliverToCityId);
  const g0 = await gold(A);
  const done = await A.call('api_completeMission', []);
  assert.deepStrictEqual(done, { reward: courier.reward, cityId: courier.deliverToCityId, type: 'courier' });
  assert.strictEqual(await gold(A), g0 + courier.reward);
  assert.strictEqual(await mload(A), 0);
  const rep = (await one('select reputation from game.players where player_id = $1', [A.id])).reputation;
  assert.strictEqual(rep[courier.deliverToCityId], 1);
  await H.expectError(() => A.call('api_completeMission', []), /^Tidak ada misi aktif\.$/);
  console.log('courier ok: reward', courier.reward);

  // ---------------- procure: hanya boleh dibeli di pulau sumber
  await moveTo(A, city);
  ms = await A.call('api_acceptMission', [city, procure.offerIndex]);
  assert(ms.type === 'procure' && ms.typeLabel === 'Pesanan' && ms.loadedQty === 0 && ms.sourceCityId === procure.sourceCityId);
  assert.strictEqual(ms.sourceCityName, procure.sourceCityName);
  assert.strictEqual(await mload(A), 0);
  await H.expectError(() => A.call('api_buyForMission', []), new RegExp('hanya boleh dibeli di ' + procure.sourceCityName));
  await H.expectError(() => A.call('api_completeMission', []), /belum dibeli/);
  await moveTo(A, procure.sourceCityId);
  const unit = (await one('select game.quote_buy($1, $2, $3) p', [A.id, procure.sourceCityId, procure.commodityId])).p;
  const gb = await gold(A);
  const bought = await A.call('api_buyForMission', []);
  assert(bought.bought === procure.qty && bought.mission.loadedQty === procure.qty);
  assert.strictEqual(bought.unitPrice, unit);
  assert.strictEqual(bought.totalCost, unit * procure.qty);
  assert.strictEqual(bought.newGold, gb - bought.totalCost);
  assert.strictEqual(await gold(A), gb - bought.totalCost);
  await H.expectError(() => A.call('api_buyForMission', []), /sudah lengkap/);
  assert.strictEqual(await mload(A), procure.qty);
  assert.strictEqual(await invQty(A, procure.commodityId), 0);
  await H.expectError(() => A.call('api_completeMission', []), /belum sampai/);
  await moveTo(A, city);
  const g1 = await gold(A);
  const done2 = await A.call('api_completeMission', []);
  assert.strictEqual(done2.type, 'procure');
  assert.strictEqual(await gold(A), g1 + procure.reward);
  console.log('procure ok: cost', bought.totalCost, 'reward', procure.reward, 'profit', procure.reward - bought.totalCost);

  // ---------------- abandon procure setelah beli -> barang jadi cargo biasa
  const board2 = await A.call('api_getMissionBoard', [city]);
  const p2 = board2.offers.find(o => o.type === 'procure' && o.unlocked);
  await A.call('api_acceptMission', [city, p2.offerIndex]);
  await moveTo(A, p2.sourceCityId);
  await A.call('api_buyForMission', []);
  const ab = await A.call('api_abandonMission', []);
  assert.strictEqual(ab.hasActive, false);
  assert.strictEqual(ab.note, 'Barang yang sudah dibeli (' + p2.qty + ') kembali ke palka biasa.');
  assert.strictEqual(await mload(A), 0);
  assert(await invQty(A, p2.commodityId) >= p2.qty);
  console.log('abandon ok:', ab.note);
  // abandon courier -> barang hilang
  await moveTo(A, city);
  const c2 = board2.offers.find(o => o.type === 'courier' && o.unlocked);
  await A.call('api_acceptMission', [city, c2.offerIndex]);
  const ab2 = await A.call('api_abandonMission', []);
  assert.strictEqual(ab2.note, 'Barang titipan dikembalikan ke pemiliknya.');
  assert.strictEqual(await mload(A), 0);
  assert.strictEqual(await invQty(A, c2.commodityId), c2.commodityId === p2.commodityId ? p2.qty : 0);
  await H.expectError(() => A.call('api_abandonMission', []), /Tidak ada misi aktif untuk dibatalkan/);

  // ---------------- courier butuh ruang palka
  const fill = await freeHold(A);
  await H.sql('select game.adjust_inventory($1, $2, $3)', [A.id, 'sugar', fill - 1]);
  assert.strictEqual(await freeHold(A), 1);
  await H.expectError(() => A.call('api_acceptMission', [city, c2.offerIndex]),
    new RegExp('Palka tidak cukup untuk barang titipan \\(butuh ' + c2.qty + ' ruang, sisa 1\\)'));
  // pesanan boleh diterima (belum memuat), tapi beli ditolak bila palka penuh
  await A.call('api_acceptMission', [city, p2.offerIndex]);
  await moveTo(A, p2.sourceCityId);
  await H.expectError(() => A.call('api_buyForMission', []), /Palka tidak cukup \(butuh \d+ ruang, sisa 1\)/);
  // gold tidak cukup
  await H.sql('select game.adjust_inventory($1, $2, $3)', [A.id, 'sugar', -(fill - 1)]);
  await H.sql('update game.players set gold = 1 where player_id = $1', [A.id]);
  await H.expectError(() => A.call('api_buyForMission', []), /Gold tidak cukup\. Butuh \d+ untuk \d+ unit, kamu punya 1\./);
  await A.call('api_abandonMission', []);
  console.log('hold check ok');

  // ---------------- legacy mission path (baris pra-v8)
  await moveTo(A, city);
  await H.sql(`insert into game.player_missions(player_id, status, accepted_at, city_id, commodity_id, qty, deliver_to_city_id, reward, type, source_city_id, loaded_qty)
               values ($1, 'active', 0, 'joungjava', 'rum', 2, $2, 111, '', '', 0)`, [A.id, city]);
  const lms = await A.call('api_getMissionState', []);
  assert.strictEqual(lms.type, 'legacy'); assert.strictEqual(lms.typeLabel, 'Kiriman'); assert.strictEqual(lms.loadedQty, 0);
  assert.strictEqual(await mload(A), 0);
  const rumBefore = await invQty(A, 'rum');
  if (rumBefore < 2) await H.expectError(() => A.call('api_completeMission', []), /Cargo tidak cukup - butuh 2 Rum\./);
  await H.sql('select game.adjust_inventory($1, $2, 2)', [A.id, 'rum']);
  const gl = await gold(A);
  const ld = await A.call('api_completeMission', []);
  assert.deepStrictEqual(ld, { reward: 111, cityId: city, type: 'legacy' });
  assert.strictEqual(await gold(A), gl + 111);
  assert.strictEqual(await invQty(A, 'rum'), rumBefore);
  // reputasi 5 membuka tier 2
  await H.sql(`update game.players set reputation = '{"sunda_empire": 5}' where player_id = $1`, [A.id]);
  const b3 = await A.call('api_getMissionBoard', [city]);
  assert(b3.offers[2].unlocked && !b3.offers[3].unlocked && b3.reputationHere === 5);
  console.log('legacy + reputation ok');

  // =====================================================================
  // ITEMS & TREASURE
  // =====================================================================
  const B = await mkPlayer('budi', 5000, 'sunda_empire');
  let items = await B.call('api_getItems', []);
  assert.deepStrictEqual(items.artifacts, {
    owned: [], equippedSlots: [{ slotKey: 'artifact', itemId: null }, { slotKey: 'artifact_2', itemId: null }], slotsFull: false });
  assert.deepStrictEqual(items.treasureMaps, []);
  assert.deepStrictEqual(items.shop, [{ itemId: 'tm_ikn_ruins', name: 'Peta Reruntuhan Istana', price: 800 }]);

  // beli peta
  await H.expectError(() => B.call('api_buyTreasureMap', ['art_sunken_crown']), /Item ini bukan treasure map\./);
  const bm = await B.call('api_buyTreasureMap', ['tm_ikn_ruins']);
  assert.deepStrictEqual(bm, { newGold: 4200, itemId: 'tm_ikn_ruins', name: 'Peta Reruntuhan Istana' });
  assert.strictEqual(await gold(B), 4200);
  items = await B.call('api_getItems', []);
  assert.strictEqual(items.treasureMaps.length, 1);
  const tm = items.treasureMaps[0];
  assert.deepStrictEqual(tm, {
    itemId: 'tm_ikn_ruins', name: 'Peta Reruntuhan Istana', qty: 1, siteId: 'site_ikn_ruins', siteName: 'Reruntuhan IKN',
    cityId: 'ikn', cityName: 'IKN', difficulty: 3, decoded: false,
    clue: 'Di antara reruntuhan ibu kota yang tumbang, ada ruang bawah tanah istana yang belum sepenuhnya dijarah.' });
  assert.deepStrictEqual(await B.call('api_getTreasureMapDetail', ['tm_ikn_ruins']), tm);
  await H.expectError(() => B.call('api_getTreasureMapDetail', ['tm_sunda_reef']), /Kamu tidak punya peta ini\./);
  await H.expectError(() => B.call('api_getTreasureMapDetail', ['art_current_charts']), /Item ini bukan treasure map\./);
  // gold kurang
  await H.sql('update game.players set gold = 100 where player_id = $1', [B.id]);
  await H.expectError(() => B.call('api_buyTreasureMap', ['tm_sunda_reef']), /Gold tidak cukup - butuh 250, kamu punya 100\./);
  await H.sql('update game.players set gold = 5000 where player_id = $1', [B.id]);

  // gali di kota yang salah / saat berlayar
  await H.expectError(() => B.call('api_digTreasure', ['tm_ikn_ruins']), /Peta ini menunjuk ke lokasi dekat IKN - berlayar ke sana dulu\./);
  await H.sql(`update game.player_location set city_id = 'ikn', destination_city_id = 'skitraw' where player_id = $1`, [B.id]);
  await H.expectError(() => B.call('api_digTreasure', ['tm_ikn_ruins']), /Kamu sedang berlayar - merapat dulu sebelum menggali\./);
  await moveTo(B, 'ikn');

  // decode lewat buku (tiruan tabel modul A di DB tes ini)
  assert.strictEqual((await one(`select game.has_effect($1, 'treasure_decoder_2') v`, [B.id])).v, false);
  await H.db.exec(`create table game.book_catalog(book_id text primary key, special_effect text);
               create table game.player_books(player_id uuid, book_id text);
               insert into game.book_catalog values ('bk_treasure_decoder_2', 'treasure_decoder_2'), ('bk_treasure_decoder_1', 'treasure_decoder_1');`);
  await H.sql(`insert into game.player_books values ($1, 'bk_treasure_decoder_2')`, [B.id]);
  assert.strictEqual((await one(`select game.has_effect($1, 'treasure_decoder_2') v`, [B.id])).v, true);
  assert.strictEqual((await one(`select game.has_effect($1, 'treasure_decoder_1') v`, [B.id])).v, false);
  const det = await B.call('api_getTreasureMapDetail', ['tm_ikn_ruins']);
  assert.strictEqual(det.decoded, true);
  assert(det.clue.startsWith('Ruang perbendaharaan istana lama'));
  // dig (decoded) di IKN
  const gB = await gold(B);
  const d1 = await B.call('api_digTreasure', ['tm_ikn_ruins']);
  assert(['big_gold', 'rare_item', 'small_gold', 'false_map'].includes(d1.outcome), JSON.stringify(d1));
  assert.strictEqual(await invQty(B, 'tm_ikn_ruins'), 0, 'map consumed');
  assert.strictEqual(d1.newGold, gB + d1.goldDelta);
  assert.strictEqual(await gold(B), d1.newGold);
  assert.strictEqual(typeof d1.newCondition, 'number');
  await H.expectError(() => B.call('api_digTreasure', ['tm_ikn_ruins']), /Kamu tidak punya peta ini\./);
  console.log('dig decoded:', d1.outcome, d1.message);

  // banyak galian (tanpa decode) untuk melihat jalur sukses & jebakan
  await H.sql('select setseed(0.4242)');
  await moveTo(B, 'sunda_empire');
  await H.sql(`select game.item_adjust($1, 'tm_sunda_reef', 40)`, [B.id]);
  const seen = {};
  for (let i = 0; i < 40 && !(seen.false_map && (seen.small_gold || seen.big_gold) && seen.rare_item); i++) {
    const before = { gold: await gold(B), cond: Number((await one('select condition from game.ships where player_id = $1', [B.id])).condition), maps: await invQty(B, 'tm_sunda_reef') };
    const r = await B.call('api_digTreasure', ['tm_sunda_reef']);
    seen[r.outcome] = (seen[r.outcome] || 0) + 1;
    assert.strictEqual(await invQty(B, 'tm_sunda_reef'), before.maps - 1);
    if (r.outcome === 'false_map') {
      assert.strictEqual(r.goldDelta, 0);
      assert(r.conditionDelta <= -8 && r.conditionDelta >= -18, 'damage range diff 1: ' + r.conditionDelta);
      assert.strictEqual(r.newCondition, Math.max(0, before.cond + r.conditionDelta));
      assert.strictEqual(r.grantedItem, null);
      assert(r.message.startsWith('Peta ternyata jebakan - galian di Karang Terlantar'));
      assert.strictEqual(await gold(B), before.gold);
    } else {
      assert(r.goldDelta > 0 && r.conditionDelta === 0);
      assert.strictEqual(await gold(B), before.gold + r.goldDelta);
      assert.strictEqual(r.newCondition, before.cond);
      if (r.outcome === 'small_gold') assert(r.goldDelta >= 105 && r.goldDelta <= 280, 'small ' + r.goldDelta);
      if (r.outcome === 'big_gold') assert(r.goldDelta >= 560 && r.goldDelta <= 980, 'big ' + r.goldDelta);
      if (r.outcome === 'rare_item') {
        assert(r.grantedItem && r.grantedItem.itemId.startsWith('art_'));
        assert(await invQty(B, r.grantedItem.itemId) >= 1);
      }
    }
  }
  console.log('dig outcomes:', seen);
  assert(seen.false_map, 'should see false_map');
  assert(seen.small_gold || seen.big_gold, 'should see gold outcome');

  // ---------------- artifact: equip / unequip 2 slot
  const C = await mkPlayer('cici', 1000, 'sunda_empire');
  for (const it of ['art_current_charts', 'art_smugglers_ring', 'art_sunken_crown']) await H.sql('select game.item_adjust($1, $2, 1)', [C.id, it]);
  await H.sql(`select game.item_adjust($1, 'art_current_charts', 1)`, [C.id]); // 2 salinan
  await H.expectError(() => C.call('api_equipArtifact', ['tm_sunda_reef']), /Item ini bukan artifact yang bisa dipasang\./);
  await H.expectError(() => C.call('api_unequipArtifact', ['artifact']), /Tidak ada artifact yang terpasang\./);
  assert.strictEqual((await one(`select game.has_effect($1, 'cargo_bonus_10') v`, [C.id])).v, false);
  let v = await C.call('api_equipArtifact', ['art_current_charts']);
  assert.deepStrictEqual(v.equippedSlots, [
    { slotKey: 'artifact', itemId: 'art_current_charts', name: 'Peta Arus Purba', specialEffect: 'cargo_bonus_10' },
    { slotKey: 'artifact_2', itemId: null }]);
  assert.strictEqual(v.slotsFull, false);
  assert.deepStrictEqual(v.owned.find(o => o.itemId === 'art_current_charts'),
    { itemId: 'art_current_charts', name: 'Peta Arus Purba', value: 1200, specialEffect: 'cargo_bonus_10', qty: 1 });
  assert.strictEqual(await invQty(C, 'art_current_charts'), 1, 'equip moves item out of inventory');
  await H.expectError(() => C.call('api_equipArtifact', ['art_current_charts']), /Artifact ini sudah terpasang\./);
  v = await C.call('api_equipArtifact', ['art_smugglers_ring']);
  assert.strictEqual(v.equippedSlots[1].itemId, 'art_smugglers_ring');
  assert.strictEqual(v.slotsFull, true);
  assert(!v.owned.some(o => o.itemId === 'art_smugglers_ring'));
  await H.expectError(() => C.call('api_equipArtifact', ['art_sunken_crown']), /Kedua slot equipment sudah penuh - copot salah satu dulu\./);
  assert.strictEqual((await one(`select game.has_effect($1, 'cargo_bonus_10') v`, [C.id])).v, true);
  assert.strictEqual((await one(`select game.has_effect($1, 'black_market_discount') v`, [C.id])).v, true);
  assert.strictEqual((await one(`select game.has_effect($1, 'treasure_decoder_1') v`, [C.id])).v, false);
  items = await C.call('api_getItems', []);
  assert.strictEqual(items.artifacts.slotsFull, true);
  // jual artifact terpasang ditolak
  await H.expectError(() => C.call('api_sellItem', ['art_smugglers_ring', 1]), /Copot dulu artifact ini sebelum dijual\./);
  // copot slot 2
  v = await C.call('api_unequipArtifact', ['artifact_2']);
  assert.deepStrictEqual(v.equippedSlots[1], { slotKey: 'artifact_2', itemId: null });
  assert.strictEqual(v.slotsFull, false);
  assert.strictEqual(await invQty(C, 'art_smugglers_ring'), 1);
  assert.strictEqual((await one(`select game.has_effect($1, 'black_market_discount') v`, [C.id])).v, false);
  await H.expectError(() => C.call('api_unequipArtifact', ['artifact_2']), /Slot itu sedang kosong\./);
  // slot kosong pertama dipakai (slot 2 terisi setelah slot 1 dicopot -> equip ke slot 1)
  await C.call('api_equipArtifact', ['art_sunken_crown']);
  v = await C.call('api_unequipArtifact', ['artifact']);
  assert.deepStrictEqual(v.equippedSlots[0], { slotKey: 'artifact', itemId: null });
  assert.strictEqual(v.equippedSlots[1].itemId, 'art_sunken_crown');
  v = await C.call('api_equipArtifact', ['art_current_charts']);
  assert.strictEqual(v.equippedSlots[0].itemId, 'art_current_charts');
  // unequip tanpa slotKey -> slot pertama yang terisi
  v = await C.call('api_unequipArtifact', []);
  assert.strictEqual(v.equippedSlots[0].itemId, null);
  assert.strictEqual(v.equippedSlots[1].itemId, 'art_sunken_crown');

  // ---------------- jual item
  const gc = await gold(C);
  const sold = await C.call('api_sellItem', ['art_smugglers_ring', 1]);
  assert.deepStrictEqual(sold, { newGold: gc + 1500, goldEarned: 1500 });
  assert.strictEqual(await gold(C), gc + 1500);
  assert.strictEqual(await invQty(C, 'art_smugglers_ring'), 0);
  await H.expectError(() => C.call('api_sellItem', ['art_smugglers_ring', 1]), /Jumlah item tidak cukup\./);
  await H.expectError(() => C.call('api_sellItem', ['nope', 1]), /Item tidak dikenali: nope/);
  const sold2 = await C.call('api_sellItem', ['art_current_charts', 'abc']); // qty tidak valid -> 1
  assert.strictEqual(sold2.goldEarned, 1200);
  console.log('items ok');

  // ---------------- treasure_drop (kontrak combat)
  await H.sql(`select game.cfg_set('TreasureMapDropChance', '100')`);
  const drop = (await one('select game.treasure_drop($1, 3) d', [C.id])).d;
  assert(drop && drop.itemId.startsWith('tm_') && typeof drop.name === 'string' && drop.name.length > 0, JSON.stringify(drop));
  assert(drop.note.includes(drop.name));
  assert.strictEqual(await invQty(C, drop.itemId), 1);
  await H.sql(`select game.cfg_set('TreasureMapDropChance', '0')`);
  assert.strictEqual((await one('select game.treasure_drop($1, 3) d', [C.id])).d, null);
  await H.sql(`select game.cfg_set('TreasureMapDropChance', '15')`);
  console.log('treasure drop ok:', drop.name);

  // log tercatat
  const logs = await H.sql('select message from game.player_log where player_id = $1 order by id', [A.id]);
  assert(logs.some(l => l.message.startsWith('Menerima titipan')) && logs.some(l => l.message.startsWith('Misi selesai di')));

  console.log('MISSIONS ITEMS TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
