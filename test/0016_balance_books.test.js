// Keseimbangan dagang (permintaan sisi beli + stok menumpuk) dan perpustakaan baru.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('borong'); await u.call('api_createCharacter', ['Tukang Borong', 'explorer']);
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null where player_id = $1`, [u.id, c]);
  await H.sql('update game.players set gold = 1000000 where player_id = $1', [u.id]);
  await H.sql('update game.ships set cargo = 400 where player_id = $1', [u.id]);
  await go('joungjava');
  const item = async id => (await u.call('api_getMarket', ['joungjava'])).items.find(i => i.commodityId === id);
  let it = await item('sugar');
  assert(it.buyPrice === it.buyNormal && it.demandScale === 100 && it.scarcityPct === 0, 'awal tanpa permintaan ' + JSON.stringify(it));
  const p0 = it.buyNormal;
  // beli 100 -> total = sum p0*(1+i/100), jauh di atas 100*p0
  const r = await u.call('api_buy', ['joungjava', 'sugar', 100]);
  let expect = 0; for (let i = 0; i < 100; i++) expect += Math.round(p0 * (1 + i / 100));
  assert(r.totalCost === expect && r.totalCost > p0 * 100 * 1.4, 'biaya borong naik ' + r.totalCost + ' vs ' + expect);
  it = await item('sugar');
  assert(it.buyPrice === Math.round(p0 * 2) && it.scarcityPct === 100, 'harga beli berikutnya dibatasi +100% ' + JSON.stringify(it));
  // pemain lain ikut merasakan
  const v = await H.user('lain'); await v.call('api_createCharacter', ['Kapten Lain', 'merchant']);
  await H.sql(`update game.player_location set city_id = 'joungjava' where player_id = $1`, [v.id]);
  const itv = (await v.call('api_getMarket', ['joungjava'])).items.find(i => i.commodityId === 'sugar');
  assert(itv.scarcityPct > 90, 'permintaan dibagi semua pemain');
  // pulih seiring waktu (half-life 150 menit)
  await H.sql(`update game.market_demand set at = at - interval '150 minutes'`);
  it = await item('sugar'); assert(Math.abs(it.demand - 50) < 0.5, 'permintaan meluruh setengah ' + it.demand);
  // menjual di kota yang sama mengurangi permintaan
  await u.call('api_sell', ['joungjava', 'sugar', 30]);
  it = await item('sugar'); assert(Math.abs(it.demand - 20) < 0.5, 'jual mengurangi permintaan ' + it.demand);
  // stok menumpuk lebih terasa: skala 80
  await go('ikn');
  const s = await u.call('api_sell', ['ikn', 'sugar', 70]);
  const sn = (await u.call('api_getMarket', ['ikn'])).items.find(i => i.commodityId === 'sugar').sellNormal;
  let exp2 = 0; for (let i = 0; i < 70; i++) exp2 += Math.max(Math.round(sn * 0.3), Math.round(sn / (1 + i / 80)));
  assert(s.totalRevenue === exp2, 'pendapatan dengan skala 80 ' + s.totalRevenue + ' vs ' + exp2);
  // konfigurasi tidak ditimpa ulang saat migrasi diulang
  await H.sql(`select game.cfg_set('DemandScale', '150')`);
  const cfg = await H.sql(`select value from game.config where key = 'BalanceVersion'`); assert(cfg[0].value === '16', 'versi keseimbangan');

  // Perpustakaan
  const n = (await H.sql(`select count(*)::int n from game.book_catalog where source <> 'quest'`))[0].n;
  assert(n === 36, 'jumlah buku ' + n);
  const pr = (await H.sql(`select price from game.book_catalog where book_id = 'bk_trading_1'`))[0].price;
  assert(Number(pr) === 450, 'harga +50% ' + pr);
  const cities = (await H.sql(`select distinct source from game.book_catalog where sort between 20 and 50`)).map(x => x.source).sort();
  assert(cities.join() === 'bjorneo,ikn,joungjava,paradiso,skitraw,sunda_empire,toogood', 'tersebar di semua kota ' + cities);
  const t4 = await H.sql(`select distinct source from game.book_catalog where tier = 'IV'`);
  assert(t4.length === 1 && t4[0].source === 'paradiso', 'Tier IV hanya di Paradiso');
  await go('sunda_empire');
  let lib = await u.call('api_getLibrary', []);
  assert(!lib.available.some(b => b.Tier === 'IV') && lib.available.some(b => b.BookId === 'bk_su_ledger'), 'perpustakaan Sunda');
  await H.expectError(() => u.call('api_buyBook', ['bk_pd_sage']), /tidak dijual di kota ini/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6)`, [u.id]);
  await go('paradiso');
  lib = await u.call('api_getLibrary', []);
  assert(lib.available.filter(b => b.Tier === 'IV').length === 5, 'Paradiso menjual 5 buku legenda');
  const g0 = Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  const st0 = (await H.sql('select knowledge from game.character_stats where player_id = $1', [u.id]))[0].knowledge;
  const b = await u.call('api_buyBook', ['bk_pd_sage']);
  assert(g0 - Number(b.newGold) === 15000, 'harga buku legenda');
  const st1 = (await H.sql('select knowledge from game.character_stats where player_id = $1', [u.id]))[0].knowledge;
  assert(st1 - st0 === 25, 'stat naik');
  console.log('BALANCE BOOKS TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
