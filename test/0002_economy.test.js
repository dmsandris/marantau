// Tes Modul A - Economy (0002_economy.sql)
const assert = require('assert');

const eq = assert.strictEqual;
const deq = assert.deepStrictEqual;

(async () => {
  const H = await require('./harness').create({ only: f => /^(0001|0002)/.test(f) });
  const E = (fn, re) => H.expectError(fn, re);
  const one = async (q, p) => (await H.sql(q, p))[0];
  const jsRound = x => Math.round(x);

  // ------------------------------------------------------------ archetypes
  const anon = await H.anon();
  const arch = await anon.call('api_getArchetypes', []);
  eq(arch.length, 8);
  deq(arch.map(a => a.id), ['merchant', 'navigator', 'pirate', 'explorer', 'gambler', 'smuggler', 'diplomat', 'adventurer']);
  deq(arch[0].bonuses, { Trading: 15 });
  deq(arch[3].bonuses, { Luck: 10, Navigation: 10 });
  deq(Object.keys(arch[6]).sort(), ['bio', 'bonuses', 'id', 'name', 'perkDesc', 'perkName', 'tagline']);
  eq((await one(`select game.archetype_json('diplomat') j`)).j.startingReputationBonus, 5);
  console.log('archetypes ok');

  // ------------------------------------------------------------ create character
  const alice = await H.user('alice');
  const bob = await H.user('bob');
  await E(() => alice.call('api_createCharacter', ['Alice', 'wizard', null]), /^Archetype tidak dikenali: wizard$/);
  await E(() => alice.call('api_createCharacter', ['   ', 'merchant', null]), /^Nama karakter tidak boleh kosong\.$/);
  await E(() => alice.call('api_createCharacter', ['x'.repeat(41), 'merchant', null]), /terlalu panjang \(maks 40 karakter\)/);

  const cs = await alice.call('api_createCharacter', ['  Alice  ', 'merchant', { fem: 1, skin: 3, head: 'peci' }]);
  eq(cs.player.characterName, 'Alice');
  eq(cs.player.archetype, 'merchant');
  eq(cs.player.gold, 5000);
  eq(cs.player.reputation, '{}');
  eq(cs.player.hasCharacter, true);
  deq(cs.stats, { Trading: 50, Negotiation: 35, Navigation: 35, Sailing: 35, Combat: 35, Luck: 15, Knowledge: 5 });
  deq(cs.archetype, { name: 'The Merchant', perkName: 'Market Sense', perkDesc: 'Setiap masuk kota baru, melihat 1 barang dengan perubahan harga terbesar.' });
  const ship = await one('select * from game.ships where player_id = $1', [alice.id]);
  eq(ship.ship_name, 'The Wandering Gull'); eq(ship.cargo, 30); eq(ship.tier, 'I'); eq(Number(ship.condition), 100);
  const loc = await one('select *, game.game_day() d from game.player_location where player_id = $1', [alice.id]);
  eq(loc.city_id, 'sunda_empire'); eq(loc.arrived_game_day, loc.d);
  const face = await one('select appearance from game.players where player_id = $1', [alice.id]);
  deq(face.appearance, { fem: 1, skin: 3, hair: 0, hairStyle: 0, facial: 0, head: 'peci', eyes: 0, seed: 0, iris: 0, brows: 0, outfit: 'arch', cloth: 0, eye: 'arch', ear: 'arch', neck: 'arch', mark: 'none', item: 'arch' });
  const lg = await one('select message from game.player_log where player_id = $1 order by id desc limit 1', [alice.id]);
  eq(lg.message, 'Began your journey as Alice, Merchant, in Sunda Empire.');
  await E(() => alice.call('api_createCharacter', ['Alice2', 'merchant', null]), /^Karakter untuk akun ini sudah pernah dibuat\.$/);

  // nama unik (case-insensitive, trim) - dicek sebelum archetype
  await E(() => bob.call('api_createCharacter', [' aLICE ', 'wizard', null]), /^Nama kapten " aLICE " sudah dipakai pemain lain\.$/);
  const csb = await bob.call('api_createCharacter', ['Bob', 'diplomat', null]);
  eq(csb.player.reputation, JSON.stringify({ sunda_empire: 5 }).replace(':', ': '));
  eq(csb.stats.Negotiation, 45);
  eq((await one('select appearance from game.players where player_id = $1', [bob.id])).appearance, null);
  console.log('create character ok');

  // ------------------------------------------------------------ market
  // Alice: Trading 50 -> 5%, Negotiation 35 -> 3.5%, reputasi 0
  let mk = await alice.call('api_getMarket', ['sunda_empire']);
  eq(mk.items.length, 6);
  eq(mk.cargoSpaceRemaining, 30);
  let sugar = mk.items.find(i => i.commodityId === 'sugar');
  eq(sugar.currentPrice, 100); eq(sugar.buyPrice, 95); eq(sugar.sellPrice, 95); eq(sugar.sellNormal, 95);
  eq(sugar.glut, 0); eq(sugar.glutScale, 120); eq(sugar.glutFloor, 0.35); eq(sugar.overstockPct, 0);
  eq(sugar.basePrice, 100); eq(sugar.priceRatio, 100); eq(sugar.ownedQty, 0); eq(sugar.name, 'Sugar');
  // Bob: Trading 35 -> 3.5% + rep 5*0.05=0.25 -> 3.75%; nego 4.5+0.25 -> clamp ke buy
  const bsug = (await bob.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'sugar');
  eq(bsug.buyPrice, jsRound(100 * (1 - 3.75 / 100))); eq(bsug.sellPrice, bsug.buyPrice);
  // quote_buy sama dengan harga di pasar
  eq((await one(`select game.quote_buy($1, 'sunda_empire', 'silk') q`, [alice.id])).q,
    mk.items.find(i => i.commodityId === 'silk').buyPrice);
  eq((await one(`select game.quote_buy($1, 'sunda_empire', 'nothing') q`, [alice.id])).q, 0);
  // TooGood arms -20% ekstra
  eq((await one(`select game.quote_buy($1, 'toogood', 'arms') q`, [alice.id])).q, jsRound(160 * (1 - 25 / 100)));
  // event harga kota (+20%) lewat game.event_price_pct -> game.city_event (stub modul B, ditimpa sementara)
  await H.sql(`create or replace function game.city_event(p_city text) returns jsonb language plpgsql stable as $$
    begin if p_city = 'skitraw' then return '{"priceMultiplierPercent":20}'::jsonb; end if; return null; end $$`);
  eq((await one(`select game.quote_buy($1, 'skitraw', 'sugar') q`, [alice.id])).q, jsRound(jsRound(95 * 1.2) * 0.95));
  await H.sql(`create or replace function game.city_event(p_city text) returns jsonb language plpgsql stable as $$ begin return null; end $$`);

  await E(() => alice.call('api_buy', ['sunda_empire', 'sugar', 0]), /^Jumlah beli tidak valid\.$/);
  await E(() => alice.call('api_buy', ['sunda_empire', 'sugar', 'abc']), /^Jumlah beli tidak valid\.$/);
  await E(() => alice.call('api_buy', ['joungjava', 'sugar', 1]), /^Kamu harus berada di kota ini untuk berdagang\.$/);
  await E(() => alice.call('api_buy', ['sunda_empire', 'unobtainium', 1]), /^Komoditas tidak tersedia di kota ini\.$/);
  await H.sql(`update game.player_location set destination_city_id = 'joungjava' where player_id = $1`, [alice.id]);
  await E(() => alice.call('api_buy', ['sunda_empire', 'sugar', 1]), /^Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat\.$/);
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [alice.id]);

  const b1 = await alice.call('api_buy', ['sunda_empire', 'sugar', '10.7']);
  deq(b1, { totalCost: 950, unitPrice: 95, newGold: 4050 });
  eq(Number((await one('select gold from game.players where player_id = $1', [alice.id])).gold), 4050);
  await E(() => alice.call('api_buy', ['sunda_empire', 'sugar', 21]), /^Kapasitas cargo tidak cukup\. Sisa ruang: 20\.$/);
  await H.sql('update game.players set gold = 10 where player_id = $1', [alice.id]);
  await E(() => alice.call('api_buy', ['sunda_empire', 'sugar', 1]), /^Gold tidak cukup\. Butuh 95, kamu punya 10\.$/);
  await H.sql('update game.players set gold = 4050 where player_id = $1', [alice.id]);
  mk = await alice.call('api_getMarket', ['sunda_empire']);
  eq(mk.cargoSpaceRemaining, 20);
  eq(mk.items.find(i => i.commodityId === 'sugar').ownedQty, 10);
  eq((await one('select message from game.player_log where player_id = $1 order by id desc limit 1', [alice.id])).message,
    'Bought 10 units of Sugar for 950 gold.');
  console.log('market buy ok');

  // ------------------------------------------------------------ sell + overstock
  const curve = (normal, g, q) => { let s = 0; for (let i = 0; i < q; i++) s += Math.max(Math.round(normal * 0.35), Math.round(normal / (1 + (g + i) / 120))); return s; };
  await E(() => alice.call('api_sell', ['sunda_empire', 'sugar', -1]), /^Jumlah jual tidak valid\.$/);
  await E(() => alice.call('api_sell', ['sunda_empire', 'spices', 1]), /^Kamu tidak punya cargo ini untuk dijual\.$/);
  await E(() => alice.call('api_sell', ['sunda_empire', 'sugar', 11]), /^Jumlah cargo tidak boleh negatif\.$/);
  const s1 = await alice.call('api_sell', ['sunda_empire', 'sugar', 5]);
  eq(s1.totalRevenue, curve(95, 0, 5));
  assert(s1.totalRevenue < 95 * 5, 'slippage dalam satu penjualan');
  eq(s1.unitPrice, Math.round(s1.totalRevenue / 5));
  eq(s1.newGold, 4050 + s1.totalRevenue);
  eq(s1.nextSellPrice, Math.round(95 / (1 + 5 / 120)));
  eq(s1.overstockPct, Math.round((1 - s1.nextSellPrice / 95) * 100));
  mk = await alice.call('api_getMarket', ['sunda_empire']);
  sugar = mk.items.find(i => i.commodityId === 'sugar');
  assert(Math.abs(sugar.glut - 5) < 0.01, 'glut 5: ' + sugar.glut);
  eq(sugar.sellPrice, s1.nextSellPrice); assert(sugar.sellPrice < 95);
  eq(sugar.buyPrice, 95); // harga beli TIDAK berubah
  eq(sugar.overstockPct, s1.overstockPct);
  // glut dibagi semua pemain: Bob melihat harga jual turun juga
  const bs2 = (await bob.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'sugar');
  assert(bs2.glut > 4.9 && bs2.sellPrice < bs2.sellNormal);
  // floor
  await H.sql(`update game.market_glut set glut = 100000, at = now() where city_id = 'sunda_empire' and commodity_id = 'sugar'`);
  sugar = (await alice.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'sugar');
  eq(sugar.sellPrice, Math.round(95 * 0.35)); eq(sugar.overstockPct, 65); eq(sugar.buyPrice, 95);
  const sf = await alice.call('api_sell', ['sunda_empire', 'sugar', 2]);
  eq(sf.totalRevenue, 2 * Math.round(95 * 0.35));
  // peluruhan: 2 half-life -> seperempat
  await H.sql(`update game.market_glut set glut = 40, at = now() - interval '240 minutes' where city_id = 'sunda_empire' and commodity_id = 'sugar'`);
  sugar = (await alice.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'sugar');
  assert(Math.abs(sugar.glut - 10) < 0.05, 'decay ' + sugar.glut);
  // pembelian menyerap glut
  const b2 = await alice.call('api_buy', ['sunda_empire', 'sugar', 3]);
  eq(b2.unitPrice, 95);
  sugar = (await alice.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'sugar');
  assert(Math.abs(sugar.glut - 7) < 0.05, 'absorb ' + sugar.glut); eq(sugar.buyPrice, 95);
  // glut yang sudah pulih dihapus
  await H.sql(`update game.market_glut set glut = 1, at = now() - interval '5000 minutes'`);
  sugar = (await alice.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'sugar');
  eq(sugar.glut, 0); eq(sugar.sellPrice, 95);
  await alice.call('api_buy', ['sunda_empire', 'rum', 2]);
  await alice.call('api_sell', ['sunda_empire', 'rum', 1]); // setGlut_ membersihkan entri yang sudah pulih
  deq((await H.sql('select commodity_id from game.market_glut')).map(r => r.commodity_id), ['rum']);
  console.log('market sell / overstock ok');

  // ------------------------------------------------------------ cargo
  // sugar: 10 - 5 - 2 + 3 = 6, rum 1
  await H.sql(`insert into game.inventory(player_id, item_id, qty) values ($1, 'art_smugglers_ring', 1)`, [alice.id]);
  deq(await alice.call('api_getCargo', []), [{ commodityId: 'sugar', name: 'Sugar', qty: 6 }, { commodityId: 'rum', name: 'Rum', qty: 1 }]);
  eq((await one('select game.cargo_total($1) n', [alice.id])).n, 7);
  let cst = await alice.call('api_getCargoState', ['sunda_empire']);
  deq(cst, { cargo: [{ commodityId: 'sugar', name: 'Sugar', qty: 6 }, { commodityId: 'rum', name: 'Rum', qty: 1 }], warehouse: [], missionLoad: 0 });
  // muatan misi (kontrak modul C, ditimpa sementara) ikut memakan ruang palka
  await H.sql(`create or replace function game.mission_load(p_pid uuid) returns int language plpgsql stable as $$ begin return 20; end $$`);
  eq((await alice.call('api_getCargoState', ['sunda_empire'])).missionLoad, 20);
  eq((await alice.call('api_getMarket', ['sunda_empire'])).cargoSpaceRemaining, 3);
  await E(() => alice.call('api_buy', ['sunda_empire', 'sugar', 4]), /Sisa ruang: 3\./);
  await H.sql(`create or replace function game.mission_load(p_pid uuid) returns int language plpgsql stable as $$ begin return 0; end $$`);
  console.log('cargo ok');

  // ------------------------------------------------------------ warehouse
  await E(() => alice.call('api_warehouseStore', ['sunda_empire', 'sugar', 0]), /^Jumlah tidak valid\.$/);
  await E(() => alice.call('api_warehouseStore', ['joungjava', 'sugar', 1]), /^Kamu harus berada di kota ini untuk titip barang\.$/);
  await E(() => alice.call('api_warehouseStore', ['sunda_empire', 'sugar', 7]), /^Cargo tidak cukup untuk dititipkan\.$/);
  await E(() => alice.call('api_warehouseStore', ['sunda_empire', 'art_smugglers_ring', 1]), /^Cargo tidak cukup untuk dititipkan\.$/);
  const g0 = Number((await one('select gold from game.players where player_id = $1', [alice.id])).gold);
  const ws = await alice.call('api_warehouseStore', ['sunda_empire', 'sugar', 4]);
  deq(ws, { fee: 8, newGold: g0 - 8 });
  await alice.call('api_warehouseStore', ['sunda_empire', 'sugar', 1]);
  deq(await alice.call('api_getWarehouse', ['sunda_empire']), [{ commodityId: 'sugar', name: 'Sugar', qty: 5 }]);
  deq(await alice.call('api_getWarehouse', ['joungjava']), []);
  cst = await alice.call('api_getCargoState', ['sunda_empire']);
  deq(cst.cargo, [{ commodityId: 'sugar', name: 'Sugar', qty: 1 }, { commodityId: 'rum', name: 'Rum', qty: 1 }]);
  deq(cst.warehouse, [{ commodityId: 'sugar', name: 'Sugar', qty: 5 }]);
  eq((await one('select message from game.player_log where player_id = $1 order by id desc limit 1', [alice.id])).message,
    'Stored 1 Sugar at the warehouse (fee: 2 gold).');
  await H.sql('update game.players set gold = 1 where player_id = $1', [alice.id]);
  await E(() => alice.call('api_warehouseStore', ['sunda_empire', 'rum', 1]), /^Gold tidak cukup untuk biaya titip \(2 gold\)\.$/);
  await H.sql('update game.players set gold = $2 where player_id = $1', [alice.id, g0 - 10]);
  await E(() => alice.call('api_warehouseWithdraw', ['joungjava', 'sugar', 1]), /^Kamu harus berada di kota ini untuk ambil barang dari gudang\.$/);
  await E(() => alice.call('api_warehouseWithdraw', ['sunda_empire', 'sugar', 6]), /^Jumlah di gudang tidak cukup\.$/);
  await E(() => alice.call('api_warehouseWithdraw', ['sunda_empire', 'sugar', 29]), /^Kapasitas cargo tidak cukup untuk mengambil semua ini\.$/);
  deq(await alice.call('api_warehouseWithdraw', ['sunda_empire', 'sugar', 3]), { ok: true });
  deq(await alice.call('api_getWarehouse', ['sunda_empire']), [{ commodityId: 'sugar', name: 'Sugar', qty: 2 }]);
  eq((await alice.call('api_getCargo', []))[0].qty, 4);
  console.log('warehouse ok');

  // ------------------------------------------------------------ bank
  await H.sql('update game.players set gold = 5000 where player_id = $1', [alice.id]);
  let bk = await alice.call('api_getBankState', []);
  deq(bk, { bankBalance: 0, debtBalance: 0, bankRatePercent: 0.5, debtRatePercent: 2, maxDebt: 5000, migrated: true });
  await E(() => alice.call('api_bankDeposit', [0]), /^Jumlah setor tidak valid\.$/);
  await E(() => alice.call('api_bankDeposit', [6000]), /^Gold tidak cukup\.$/);
  bk = await alice.call('api_bankDeposit', [1000]);
  eq(bk.bankBalance, 1000); eq(bk.newGold, 4000);
  await E(() => alice.call('api_bankWithdraw', [2000]), /^Saldo Bank tidak cukup\.$/);
  bk = await alice.call('api_bankWithdraw', [400]);
  eq(bk.bankBalance, 600); eq(bk.newGold, 4400);
  await E(() => alice.call('api_bankBorrow', [5001]), /^Melebihi batas pinjaman Moneylender \(maksimum utang 5000 gold\)\.$/);
  bk = await alice.call('api_bankBorrow', [1000]);
  eq(bk.debtBalance, 1000); eq(bk.newGold, 5400);
  await E(() => alice.call('api_bankBorrow', [4001]), /maksimum utang 5000 gold/);
  // bunga majemuk setelah 2 hari-game (60 menit per hari)
  await H.shiftTime(2 * 60 * 60000 + 1000);
  bk = await alice.call('api_getBankState', []);
  eq(bk.bankBalance, Math.round(600 * Math.pow(1.005, 2)));
  eq(bk.debtBalance, Math.round(1000 * Math.pow(1.02, 2)));
  // dibaca ulang di hari yang sama -> tidak berbunga dua kali
  deq(await alice.call('api_getBankState', []), bk);
  await H.shiftTime(60 * 60000);
  bk = await alice.call('api_getBankState', []);
  eq(bk.debtBalance, Math.round(Math.round(1000 * Math.pow(1.02, 2)) * 1.02));
  const debtNow = bk.debtBalance;
  await E(() => alice.call('api_bankRepay', [-5]), /^Jumlah bayar tidak valid\.$/);
  bk = await alice.call('api_bankRepay', [100]);
  eq(bk.debtBalance, debtNow - 100); eq(bk.newGold, 5300);
  bk = await alice.call('api_bankRepay', [999999]);
  eq(bk.debtBalance, 0); eq(bk.newGold, 5300 - (debtNow - 100));
  await E(() => alice.call('api_bankRepay', [10]), /^Tidak ada yang bisa dibayar \(cek gold atau utangmu\)\.$/);
  eq((await one('select message from game.player_log where player_id = $1 order by id desc limit 1', [alice.id])).message,
    `Repaid ${debtNow - 100} gold to the Moneylender.`);
  // kontrak bank_state
  eq((await one('select game.bank_state($1) s', [alice.id])).s.bankBalance, bk.bankBalance);
  console.log('bank ok');

  // ------------------------------------------------------------ library
  await H.sql('update game.players set gold = 5000 where player_id = $1', [alice.id]);
  let lib = await alice.call('api_getLibrary', []);
  eq(lib.owned.length, 0);
  deq(lib.available.map(b => b.BookId), ['bk_trading_1', 'bk_negotiation_1', 'bk_luck_1', 'bk_knowledge_1', 'bk_trading_2',
    'bk_negotiation_2', 'bk_sea_lore', 'bk_treasure_decoder_1']);
  deq(lib.available[0], { BookId: 'bk_trading_1', Name: 'Basic Bookkeeping', Tier: 'I', StatEffects: '{"Trading":5}', SpecialEffect: '', Price: 300, Source: 'sunda_empire' });
  await E(() => alice.call('api_buyBook', ['bk_nope']), /^Buku tidak dikenali: bk_nope$/);
  await E(() => alice.call('api_buyBook', ['bk_navigation_1']), /^Buku ini tidak dijual di kota ini\.$/);
  const bb = await alice.call('api_buyBook', ['bk_trading_2']);
  eq(bb.newGold, 4100); eq(bb.book.Name, "The Merchant's Codex");
  deq((await alice.call('api_getCharacterStats', [])).stats, { Trading: 60, Negotiation: 38, Navigation: 35, Sailing: 35, Combat: 35, Luck: 15, Knowledge: 5 });
  await E(() => alice.call('api_buyBook', ['bk_trading_2']), /^Kamu sudah punya buku ini\.$/);
  eq((await one('select message from game.player_log where player_id = $1 order by id desc limit 1', [alice.id])).message,
    `Purchased "The Merchant's Codex" for 900 gold.`);
  lib = await alice.call('api_getLibrary', []);
  deq(lib.owned.map(b => b.BookId), ['bk_trading_2']);
  assert(!lib.available.some(b => b.BookId === 'bk_trading_2'));
  // Trading 60 -> 6% diskon beli
  eq((await alice.call('api_getMarket', ['sunda_empire'])).items.find(i => i.commodityId === 'silk').buyPrice, jsRound(250 * 0.94));
  await H.sql('update game.players set gold = 100 where player_id = $1', [alice.id]);
  await E(() => alice.call('api_buyBook', ['bk_sea_lore']), /^Gold tidak cukup\. Butuh 2000, kamu punya 100\.$/);
  // Smuggler's Codebook (bjorneo) -> +5% diskon beli (black_market_discount)
  await H.sql(`update game.player_location set city_id = 'bjorneo' where player_id = $1`, [alice.id]);
  await H.sql('update game.players set gold = 5000 where player_id = $1', [alice.id]);
  await H.sql(`update game.player_location set destination_city_id = 'ikn' where player_id = $1`, [alice.id]);
  await E(() => alice.call('api_buyBook', ['bk_black_market']), /^Kamu sedang berlayar - tidak bisa mengunjungi Library sampai kapal merapat\.$/);
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [alice.id]);
  const before = (await one(`select game.quote_buy($1, 'bjorneo', 'arms') q`, [alice.id])).q;
  eq(before, jsRound(380 * (1 - 6 / 100)));
  await alice.call('api_buyBook', ['bk_black_market']);
  eq((await one(`select game.quote_buy($1, 'bjorneo', 'arms') q`, [alice.id])).q, jsRound(380 * (1 - 11 / 100)));
  deq((await one('select game.book_effects($1) e', [alice.id])).e, ['black_market_discount']);
  eq((await one(`select game.book_has_effect($1, 'black_market_discount') e`, [alice.id])).e, true);
  const mkb = await alice.call('api_getMarket', ['bjorneo']);
  const arms = mkb.items.find(i => i.commodityId === 'arms');
  eq(arms.buyPrice, jsRound(380 * 0.89));
  // Negotiation 38+5=43 -> 4.3%; sell clamp <= buy
  eq(arms.sellNormal, Math.min(jsRound(380 * 1.043), arms.buyPrice));
  console.log('library ok');

  // ------------------------------------------------------------ appearance / meta
  const ap = await bob.call('api_saveAppearance', [{ fem: 'yes', skin: 9, hair: -3, hairStyle: '2.7', facial: null, head: 'crown', eyes: true, seed: 1234567, extra: 'x' }]);
  deq(ap, { fem: 1, skin: 7, hair: 0, hairStyle: 2, facial: 0, head: 'arch', eyes: 1, seed: 999999, iris: 0, brows: 0, outfit: 'arch', cloth: 0, eye: 'arch', ear: 'arch', neck: 'arch', mark: 'none', item: 'arch' });
  deq(await bob.call('api_saveAppearance', [null]), { fem: 0, skin: 0, hair: 0, hairStyle: 0, facial: 0, head: 'arch', eyes: 0, seed: 0, iris: 0, brows: 0, outfit: 'arch', cloth: 0, eye: 'arch', ear: 'arch', neck: 'arch', mark: 'none', item: 'arch' });
  await bob.call('api_saveAppearance', [{ fem: 0, head: 'tricorne', skin: '4' }]);
  eq((await one('select appearance from game.players where player_id = $1', [bob.id])).appearance.head, 'tricorne');

  let mt = await alice.call('api_saveMeta', [{ u: { a: 100, b: 0, 'Bad-Key': 5 }, c: { x: '5.9', y: -3 }, v: ['p', 'p', '', 'q'.repeat(50)] }]);
  deq(mt, { u: { a: 100, b: 1 }, c: { x: 5, y: 0 }, v: ['p', 'q'.repeat(40)] });
  mt = await alice.call('api_saveMeta', [{ u: { a: 50, b: 7, c: 0 }, c: { x: 3, z: 2 }, v: ['r', 'p'] }]);
  deq(mt, { u: { a: 50, b: 1, c: 1 }, c: { x: 5, y: 0, z: 2 }, v: ['p', 'q'.repeat(40), 'r'] });
  mt = await alice.call('api_saveMeta', [{ u: { a: 80 } }]);
  eq(mt.u.a, 50);
  // batas 8000 karakter JSON (80 u + 40 c per simpan; gabungan dua simpanan melewati batas)
  const ghostM = await H.user('ghost');
  const mkMeta = p => {
    const m = { u: {}, c: {} };
    for (let i = 0; i < 80; i++) m.u[(p + 'u' + String(i).padStart(3, '0')).padEnd(24, 'z')] = 1e15 + i;
    for (let i = 0; i < 40; i++) m.c[(p + 'c' + String(i).padStart(3, '0')).padEnd(24, 'z')] = 1e12;
    return m;
  };
  const m1 = await ghostM.call('api_saveMeta', [mkMeta('a')]);
  eq(Object.keys(m1.u).length, 80); eq(Object.keys(m1.c).length, 40);
  await E(() => ghostM.call('api_saveMeta', [mkMeta('b')]), /^Data Tanda Jasa terlalu besar\.$/);
  eq(Object.keys((await one('select meta from game.players where player_id = $1', [ghostM.id])).meta.u).length, 80);
  console.log('appearance / meta ok');

  // ------------------------------------------------------------ leaderboard
  for (const [n, g] of [['cara', 100], ['dina', 9000], ['edo', 300], ['fajar', 50]]) {
    const u = await H.user(n);
    await u.call('api_createCharacter', [n.toUpperCase(), 'pirate', null]);
    await H.sql('update game.players set gold = $2 where player_id = $1', [u.id, g]);
  }
  // 'ghost' punya baris players tapi tanpa karakter -> tidak masuk papan
  const lb = await bob.call('api_getLeaderboard', []);
  eq(lb.length, 5);
  deq(lb.map(r => r.characterName), ['DINA', 'Bob', 'Alice', 'EDO', 'CARA']);
  deq(Object.keys(lb[0]).sort(), ['appearance', 'archetype', 'badges', 'characterName', 'gold']);
  assert(!JSON.stringify(lb).includes(alice.id) && !JSON.stringify(lb).includes(bob.id), 'id bocor');
  eq(lb[2].badges, 3); eq(lb[0].badges, 0); eq(lb[1].badges, 0); eq(lb[0].appearance, null);
  eq(lb[1].appearance.head, 'tricorne'); eq(lb[2].appearance.head, 'peci');
  eq(lb[0].gold, 9000); eq(lb[0].archetype, 'pirate');
  console.log('leaderboard ok');

  // ------------------------------------------------------------ delete character
  const ghost = await H.user('ghost');
  await E(() => ghost.call('api_deleteCharacter', []), /^Belum ada karakter untuk dihapus\.$/);
  await H.sql(`create table game.test_hook(pid uuid)`);
  await H.sql(`create or replace function game.zz_test_on_character_delete(p uuid) returns void language sql as $$ insert into game.test_hook values (p) $$`);
  await H.sql(`create table game.player_missions(player_id uuid, mission_id text)`);
  await H.sql(`insert into game.player_missions values ($1, 'm1'), ($2, 'm2')`, [alice.id, bob.id]);
  const del = await alice.call('api_deleteCharacter', []);
  deq(del, { success: true });
  for (const t of ['character_stats', 'ships', 'player_location', 'inventory', 'warehouse', 'player_log', 'player_books', 'player_missions']) {
    eq((await one(`select count(*)::int n from game.${t} where player_id = $1`, [alice.id])).n, 0, t);
  }
  eq((await one('select count(*)::int n from game.player_missions where player_id = $1', [bob.id])).n, 1);
  eq((await one('select count(*)::int n from game.test_hook where pid = $1', [alice.id])).n, 1);
  const pa = await one('select * from game.players where player_id = $1', [alice.id]);
  eq(pa.character_name, ''); eq(pa.archetype, ''); eq(Number(pa.gold), 0); deq(pa.reputation, {}); deq(pa.ship_upgrades, {});
  eq(pa.meta, null); eq(Number(pa.bank_balance), 0); eq(Number(pa.debt_balance), 0);
  assert(pa.appearance, 'appearance tetap disimpan');
  await E(() => alice.call('api_deleteCharacter', []), /^Belum ada karakter untuk dihapus\.$/);
  // nama bebas dipakai lagi (oleh siapa pun), karakter baru bersih
  const again = await alice.call('api_createCharacter', ['Alice', 'explorer', null]);
  eq(again.player.gold, 5000); eq(again.stats.Luck, 25); eq(again.stats.Trading, 35);
  deq(await alice.call('api_getCargo', []), []);
  eq((await alice.call('api_getLibrary', [])).owned.length, 0);
  eq((await alice.call('api_getBankState', [])).bankBalance, 0);

  // tanpa login
  await E(() => anon.call('api_getMarket', ['sunda_empire']), /AUTH_REQUIRED/);

  console.log('delete character ok');
  console.log('ECONOMY TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
