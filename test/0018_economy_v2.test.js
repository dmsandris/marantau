// Ekonomi v2: 28 barang, stok terbatas, harga dari stok, drift & siklus, premium, ukuran palka, konversi Spices.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const fs = require('fs'), path = require('path');
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('dagang'); await u.call('api_createCharacter', ['Saudagar Uji', 'explorer']);
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null where player_id = $1`, [u.id, c]);
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  const item = async (city, id) => (await u.call('api_getMarket', [city])).items.find(i => i.commodityId === id);
  await H.sql('update game.players set gold = 500000 where player_id = $1', [u.id]);

  // katalog
  const cat = await H.sql(`select id, tier, grp from game.commodities where active order by sort`);
  assert(cat.length === 28, 'jumlah barang ' + cat.length);
  for (const g of ['pangan', 'minuman', 'rempah', 'bahan', 'kerajinan', 'mewah'])
    assert(cat.some(c => c.grp === g && c.tier === 'premium'), 'kelompok ' + g + ' punya premium');
  const m0 = await u.call('api_getMarket', ['bjorneo']);
  assert(m0.items.length === 28 && m0.cycle && m0.cycle.wanted.length === 2 && m0.cycle.surplus.length === 1, 'pasar 28 barang + kabar pasar');
  assert(m0.cargoCapacity === 30 && m0.cargoUsed === 0, 'kapasitas palka');

  // produsen murah, konsumen mahal
  await go('bjorneo');
  const ladaB = await item('bjorneo', 'lada'), ladaS = await item('skitraw', 'lada');
  assert(ladaB.role === 'produce' && ladaS.role === 'consume', 'peran kota');
  assert(ladaB.buyPrice < ladaS.sellPrice, 'rute Lada Bjorneo->Skitraw menguntungkan: ' + ladaB.buyPrice + ' vs ' + ladaS.sellPrice);

  // beli: stok turun, harga naik per unit, tidak bisa melebihi stok
  const s0 = ladaB.stock;
  let r = await u.call('api_buy', ['bjorneo', 'lada', 20]);
  assert(r.stockLeft === s0 - 20 && r.nextBuyPrice > ladaB.buyPrice && r.totalCost > ladaB.buyPrice * 20, 'beli menggeser harga ' + JSON.stringify(r));
  await H.expectError(() => u.call('api_buy', ['bjorneo', 'lada', s0]), /tinggal/);
  // palka memakai ukuran: 20 Lada x 0.5 = 10 ruang
  assert(Number((await H.sql('select game.cargo_used($1) v', [u.id]))[0].v) === 10, 'ruang terpakai 10');
  await H.expectError(() => u.call('api_buy', ['bjorneo', 'rotan', 14]), /Butuh 21 ruang, sisa 20/);
  // jual balik di kota yang sama selalu rugi (spread)
  const g0 = await gold(); await u.call('api_sell', ['bjorneo', 'lada', 20]);
  assert(await gold() < g0 + r.totalCost, 'tidak ada arbitrase di kota yang sama');
  assert((await item('bjorneo', 'lada')).stock === s0, 'stok kembali setelah dijual');

  // Emas: kecil (0.1 ruang/unit), premium hanya di produsen, kiriman per siklus
  const emas = await item('bjorneo', 'emas');
  assert(emas.tier === 'premium' && emas.size === 0.1 && emas.stock === 12, 'emas di Bjorneo ' + JSON.stringify(emas));
  assert((await item('sunda_empire', 'emas')).stock === 0, 'kota non-produsen tidak punya stok premium');
  await u.call('api_buy', ['bjorneo', 'emas', 12]);
  assert(Number((await H.sql('select game.cargo_used($1) v', [u.id]))[0].v) === 1.2, '12 emas = 1.2 ruang');
  assert((await item('bjorneo', 'emas')).stock === 0, 'emas habis');
  await H.sql(`update game.market set at = at - interval '30 minutes' where city_id = 'bjorneo'`);
  assert((await item('bjorneo', 'emas')).stock === 0, 'premium tidak tumbuh terus-menerus');
  await H.sql(`update game.market set cyc = cyc - 2 where city_id = 'bjorneo' and commodity_id = 'emas'`);
  assert((await item('bjorneo', 'emas')).stock === 8, 'kiriman 4 per siklus (2 siklus = 8)');
  // jual emas ke kota konsumen: harga wajar walau stok 0, lalu stok dikonsumsi pelan tanpa tumbuh kembali
  await go('sunda_empire');
  const eS = await item('sunda_empire', 'emas');
  assert(eS.sellPrice > emas.buyPrice && eS.sellPrice < 9000 * 1.6, 'harga jual emas di konsumen ' + eS.sellPrice);
  await u.call('api_sell', ['sunda_empire', 'emas', 4]);
  assert((await item('sunda_empire', 'emas')).stock === 4, 'stok bertambah setelah dijual');
  await H.sql(`update game.market set at = at - interval '300 minutes' where city_id = 'sunda_empire'`);
  assert((await item('sunda_empire', 'emas')).stock === 0, 'dikonsumsi');

  // drift: stok produsen yang dikuras terisi kembali (~90% dalam 60 menit)
  await go('bjorneo');
  // stok awal bisa bergeser oleh siklus Kabar Pasar (jam dinding) - kuras sebanyak yang ada
  const p0 = (await item('bjorneo', 'pala')).stock;
  await u.call('api_buy', ['bjorneo', 'pala', Math.min(30, p0)]);
  const p1 = (await item('bjorneo', 'pala')).stock;
  await H.sql(`update game.market set at = at - interval '60 minutes' where city_id = 'bjorneo'`);
  const p2 = (await item('bjorneo', 'pala')).stock;
  assert(p2 > p1 + 20, 'stok pulih ' + p1 + ' -> ' + p2);
  // kota konsumen menghabiskan kelebihan
  await go('skitraw');
  await u.call('api_sell', ['skitraw', 'pala', 30]).catch(() => null);
  const k0 = (await item('skitraw', 'garam')).stock;
  await H.sql(`select game.adjust_inventory($1, 'garam', 40)`, [u.id]);
  await u.call('api_sell', ['skitraw', 'garam', 40]);
  await H.sql(`update game.market set at = at - interval '60 minutes' where city_id = 'skitraw'`);
  assert((await item('skitraw', 'garam')).stock < k0 + 10, 'kelebihan stok dikonsumsi');

  // siklus: barang "Dicari" punya stok alami lebih rendah -> harga naik
  const tags = (await u.call('api_getMarket', ['ikn'])).cycle;
  const w = await item('ikn', tags.wanted[0]);
  assert(w.tag === 'wanted', 'tag dicari');

  // misi: tidak memakai barang premium; Pesanan mengambil stok sungguhan
  const board = await u.call('api_getMissionBoard', ['skitraw']);
  const prem = cat.filter(c => c.tier === 'premium').map(c => c.id);
  assert(!board.offers.some(o => prem.includes(o.commodityId)), 'misi tanpa barang premium');

  // konversi Spices lama -> Lada
  await H.sql(`insert into game.inventory(player_id, item_id, qty) values ($1, 'spices', 7) on conflict (player_id, item_id) do update set qty = 7`, [u.id]);
  const lada0 = Number(((await H.sql(`select qty from game.inventory where player_id = $1 and item_id = 'lada'`, [u.id]))[0] || { qty: 0 }).qty);
  await H.sql(`update game.commodities set active = true where id = 'spices'`);
  const db = H.db; await db.exec(fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0018_economy_v2.sql'), 'utf8'));
  const after = await H.sql(`select item_id, qty from game.inventory where player_id = $1 and item_id in ('spices', 'lada')`, [u.id]);
  assert(after.length === 1 && after[0].item_id === 'lada' && Number(after[0].qty) === lada0 + 7, 'spices -> lada ' + JSON.stringify(after));
  assert(!(await u.call('api_getMarket', ['bjorneo'])).items.some(i => i.commodityId === 'spices'), 'spices tidak dijual lagi');
  // Tide v23: skill selalu menambah untung & pulang-pergi di kota yang sama selalu rugi
  const prof = async (t, n, rep) => {
    await H.sql('update game.character_stats set trading = $2, negotiation = $3 where player_id = $1', [u.id, t, n]);
    await H.sql(`update game.players set reputation = (select jsonb_object_agg(city_id, $2::int) from game.cities) where player_id = $1`, [u.id, rep]);
  };
  const route = async () => (await H.sql(`
    select (select game.eco2_sell_value((c.base * mu.ev_mul)::numeric, c.ref, c.elast, m.stock, 20, mu.sell_mul, m.role, c.tier)
              from game.market m, game.commodities c, game.eco2_muls($1, 'skitraw', 'lada') mu where m.city_id = 'skitraw' and m.commodity_id = 'lada' and c.id = 'lada')
         - (select game.eco2_buy_cost((c.base * mu.ev_mul)::numeric, c.ref, c.elast, m.stock, 20, mu.buy_mul, m.role, c.tier)
              from game.market m, game.commodities c, game.eco2_muls($1, 'bjorneo', 'lada') mu where m.city_id = 'bjorneo' and m.commodity_id = 'lada' and c.id = 'lada') p`, [u.id]))[0].p;
  const roundTrip = async () => (await H.sql(`
    select count(*) filter (where sv >= bc) bad, count(*) filter (where sv > bc) gain, count(*) n, string_agg(case when sv >= bc then cid || '@' || city || ' q' || q || ' ' || bc || '/' || sv end, ', ') bads from (
      select m.commodity_id cid, m.city_id city, q, game.eco2_buy_cost((c.base * mu.ev_mul)::numeric, c.ref, c.elast, m.stock, q, mu.buy_mul, m.role, c.tier) bc,
             game.eco2_sell_value((c.base * mu.ev_mul)::numeric, c.ref, c.elast, m.stock - q, q, mu.sell_mul, m.role, c.tier) sv
      from game.market m join game.commodities c on c.id = m.commodity_id and c.active
        cross join lateral game.eco2_muls($1, m.city_id, m.commodity_id) mu
        cross join lateral (select unnest(array[1, least(10, floor(m.stock)::int), floor(m.stock)::int]) q) qq
      where m.stock >= 1 and q >= 1) x`, [u.id]))[0];
  const profiles = [[35, 35, 0], [50, 40, 0], [75, 55, 40], [100, 100, 200]];
  let prev = -Infinity;
  for (const [t, n, rep] of profiles) {
    await prof(t, n, rep);
    const pr = Number(await route());
    assert(pr > prev, 'skill harus menambah untung: ' + JSON.stringify([t, n, rep]) + ' ' + pr + ' <= ' + prev);
    prev = pr;
    const rt = await roundTrip();
    assert(Number(rt.gain) === 0 && Number(rt.bad) <= 2 && Number(rt.n) > 100, 'pulang-pergi kota sama tidak boleh untung ' + JSON.stringify([t, n, rep, rt]));
  }
  const mx = (await H.sql(`select buy_mul, sell_mul from game.eco2_muls($1, 'bjorneo', 'lada')`, [u.id]))[0];
  assert(Math.abs(mx.buy_mul - 1.015) < 1e-9 && Math.abs(mx.sell_mul - 0.985) < 1e-9, 'kapten maksimal: Lada beli 1.015 jual 0.985 ' + JSON.stringify(mx));
  await prof(35, 35, 0);
  const nw = (await H.sql(`select buy_mul, sell_mul from game.eco2_muls($1, 'bjorneo', 'lada')`, [u.id]))[0];
  assert(Math.abs(nw.buy_mul - 1.0645) < 1e-9 && Math.abs(nw.sell_mul - 0.9355) < 1e-9, 'pemula: Lada beli 1.0645 jual 0.9355 ' + JSON.stringify(nw));
  // Senjata TooGood: harga lokal lebih murah untuk semua (bukan diskon pribadi)
  const arms = (await H.sql(`select (select ev_mul from game.eco2_muls($1, 'toogood', 'arms')) tg, (select ev_mul from game.eco2_muls($1, 'skitraw', 'arms')) sk`, [u.id]))[0];
  assert(Math.abs(arms.tg / arms.sk - 0.8) < 1e-9, 'senjata TooGood 20% lebih murah ' + JSON.stringify(arms));
  console.log('skill monoton & anti-arbitrase OK: untung rute ' + prev);
  console.log('ECONOMY V2 TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
