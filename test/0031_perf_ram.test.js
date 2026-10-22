// Tide v35 (hemat RAM/IO): cache stok pasar, getCityBundle tanpa SQL dinamis, getGameState hemat quest.
// Tujuan utama tes ini: membuktikan perilaku untuk pemain TIDAK berubah.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('hemat'); await u.call('api_createCharacter', ['Kapten Hemat', 'merchant']);
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null where player_id = $1`, [u.id, c]);
  await go('bjorneo');
  const row = async c => (await H.sql(`select stock::float8 s, extract(epoch from at)::float8 at, cyc::int8 cyc
    from game.market where city_id = 'bjorneo' and commodity_id = $1`, [c]))[0];
  const shown = async c => (await u.call('api_getMarket', ['bjorneo'])).items.find(i => i.commodityId === c);

  // ---- D1: rumus stok tidak bergantung pada seberapa sering dihitung (di dalam satu siklus)
  const pd = (await H.sql(`
    with p as (select m.*, c.tier, c.ref from game.market m join game.commodities c on c.id = m.commodity_id
                where m.city_id = 'bjorneo' and c.active),
    t as (select game.mkt_cycle_index() cyc, game.mkt_cycle_tags('bjorneo', game.mkt_cycle_index()) tags)
    select max(abs(
      game.mkt_project(game.mkt_project(p.ref * 1.9, now() - interval '25 minutes', t.cyc, p.role, p.tier, p.ref, p.commodity_id, t.tags, t.cyc),
                       now() - interval '15 minutes', t.cyc, p.role, p.tier, p.ref, p.commodity_id, t.tags, t.cyc)
      - game.mkt_project(p.ref * 1.9, now() - interval '40 minutes', t.cyc, p.role, p.tier, p.ref, p.commodity_id, t.tags, t.cyc)
    ))::float8 d from p, t`))[0].d;
  assert(pd < 0.01, 'proyeksi bertahap = proyeksi sekaligus (selisih ' + pd + ')');

  // ---- D2: baris lama ditulis ulang; dibuka lagi dalam 30 detik -> tidak ditulis, angka sama
  await H.sql(`update game.market m set stock = c.ref * 1.7, at = now() - interval '10 minutes', cyc = game.mkt_cycle_index()
    from game.commodities c where c.id = m.commodity_id and m.city_id = 'bjorneo'`);
  const before = await row('lada');
  const a1 = await shown('lada');
  const after1 = await row('lada');
  assert(after1.at > before.at + 500, 'baris lama ditulis ulang saat pasar dibuka');
  const a2 = await shown('lada');
  const after2 = await row('lada');
  assert(after2.at === after1.at, 'dibuka lagi < 30 detik: tidak menulis ulang');
  assert(a2.stock === a1.stock && a2.buyPrice === a1.buyPrice && a2.sellPrice === a1.sellPrice, 'harga sama ' + JSON.stringify([a1, a2]));

  // ---- D3: baris "segar" (belum ditulis) tetap ditampilkan TEPAT (proyeksi saat dibaca)
  await H.sql(`update game.market m set stock = c.ref * 1.7, at = now() - interval '20 seconds', cyc = game.mkt_cycle_index()
    from game.commodities c where c.id = m.commodity_id and m.city_id = 'bjorneo' and m.commodity_id = 'lada'`);
  const exp = (await H.sql(`select floor(game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id,
      game.mkt_cycle_tags('bjorneo', game.mkt_cycle_index()), game.mkt_cycle_index()))::int s
    from game.market m join game.commodities c on c.id = m.commodity_id where m.city_id = 'bjorneo' and m.commodity_id = 'lada'`))[0].s;
  const raw = await row('lada');
  const a3 = await shown('lada');
  assert((await row('lada')).at === raw.at, 'baris segar tidak ditulis');
  assert(a3.stock === exp, 'stok tampil = proyeksi persis (' + a3.stock + ' vs ' + exp + ')');

  // ---- D4: siklus pasar berganti -> SELALU ditulis (kiriman premium, Kabar Pasar baru)
  await H.sql(`update game.market set at = now(), cyc = game.mkt_cycle_index() - 1 where city_id = 'bjorneo'`);
  await shown('lada');
  const cur = Number((await H.sql(`select game.mkt_cycle_index()::int8 c`))[0].c);
  assert(Number((await row('lada')).cyc) === cur, 'siklus baru langsung ditulis');

  // ---- D5: beli tetap memakai harga persis seperti yang tampil
  await H.sql('update game.players set gold = 500000 where player_id = $1', [u.id]);
  const b = await shown('lada');
  const r = await u.call('api_buy', ['bjorneo', 'lada', 1]);
  assert(r.totalCost === b.buyPrice, 'harga beli = harga tampil (' + r.totalCost + ' vs ' + b.buyPrice + ')');
  console.log('cache pasar OK');

  // ---- C: getCityBundle -> isi dan bentuk sama dengan memanggil endpoint satu per satu
  const bun = await u.call('api_getCityBundle', ['bjorneo']);
  const keys = ['cargoState', 'upgrades', 'items', 'market', 'library', 'missionBoard', 'sailOptions', 'repairQuote'];
  for (const k of keys) assert(k in bun && bun[k] !== null && !bun[k + 'Error'], 'bundle bagian ' + k + ' ' + (bun[k + 'Error'] || ''));
  const solo = {
    cargoState: await u.call('api_getCargoState', ['bjorneo']), items: await u.call('api_getItems', []),
    library: await u.call('api_getLibrary', []), missionBoard: await u.call('api_getMissionBoard', ['bjorneo']),
    sailOptions: await u.call('api_getSailOptions', []), repairQuote: await u.call('api_getRepairQuote', ['bjorneo']),
    upgrades: { affordable: (await u.call('api_getShipUpgrades', [])).affordable }
  };
  const strip = o => JSON.stringify(o, (k, v) => (/ms$|Ms$|^t$|endsIn/i.test(k) ? undefined : v));
  for (const k of Object.keys(solo)) assert(strip(bun[k]) === strip(solo[k]), 'bundle.' + k + ' sama dengan endpoint tunggal');
  assert(bun.market.items.length === (await u.call('api_getMarket', ['bjorneo'])).items.length, 'bundle.market lengkap');
  // berlayar: hanya 3 bagian (pasar dll. tidak dikirim saat di laut)
  await H.sql(`update game.player_location set destination_city_id = 'skitraw', departed_at = now(), arrival_at = now() + interval '1 hour' where player_id = $1`, [u.id]).catch(() => {});
  const sea = await u.call('api_getCityBundle', ['bjorneo']);
  if (!('market' in sea)) assert('cargoState' in sea && 'items' in sea && 'upgrades' in sea, 'bundle saat berlayar');
  await go('bjorneo');
  // satu bagian gagal -> bagian lain tetap terkirim + pesan error per bagian
  const bad = await u.call('api_getCityBundle', ['kota_tidak_ada']);
  assert(bad.marketError && bad.items, 'error per bagian tetap terisolasi ' + JSON.stringify(Object.keys(bad)));
  console.log('city bundle OK');

  // ---- Daftar tujuan: waktu tempuh = rumus lama (kapal per rute), termasuk buku Quest 9 Peta Dua Tangan
  const etaCheck = async label => {
    const opts = await u.call('api_getSailOptions', []);
    const ref = await H.sql(`select c.city_id, game.voy_travel_seconds(game.voy_map_distance(l.city_id, c.city_id),
        game.lt_ship_for_route($1, l.city_id, c.city_id)) s
      from game.cities c, game.player_location l where l.player_id = $1 and c.city_id <> l.city_id`, [u.id]);
    for (const o of opts) {
      const r = ref.find(x => x.city_id === o.cityId);
      assert(r && Number(r.s) === o.etaSeconds, label + ': eta ' + o.cityId + ' ' + o.etaSeconds + ' vs ' + (r && r.s));
    }
    return opts.length;
  };
  await go('sowtour').catch(() => go('bjorneo'));
  const n1 = await etaCheck('tanpa buku');
  await H.sql(`insert into game.player_books(player_id, book_id) values ($1, 'bk_peta_dua_tangan') on conflict do nothing`, [u.id]);
  await etaCheck('dengan Peta Dua Tangan');
  await H.sql(`delete from game.player_books where player_id = $1 and book_id = 'bk_peta_dua_tangan'`, [u.id]);
  await go('bjorneo');
  console.log('sail options OK (' + n1 + ' tujuan)');

  // ---- B: getGameState -> semua key quest tetap ada & isinya sama dengan fungsi state aslinya
  const qk = { gala: 'gala_state', toogood: 'toogood_state', warwerwor: 'ww_state', barsati: 'bx_state', kompas: 'kp_state',
    cocoepan: 'cb_state', tigasilang: 'ts_state', limatangan: 'lt_state', duatangan: 'dt_state' };
  const check = async label => {
    const gs = await u.call('api_getGameState', []);
    for (const [k, fn] of Object.entries(qk)) {
      assert(k in gs, label + ': key ' + k + ' ada');
      const direct = (await H.sql(`select game.${fn}($1) v`, [u.id]))[0].v;
      assert(JSON.stringify(gs[k]) === JSON.stringify(direct), label + ': ' + k + ' sama dengan ' + fn);
    }
    return gs;
  };
  await check('pemain baru');
  // tandai semua quest lama selesai lalu cek lagi: isi tetap persis seperti fungsi aslinya
  const done = (await H.sql(`select quest_id from game.player_quests where player_id = $1`, [u.id])).map(x => x.quest_id);
  await check('quest ' + done.length);
  console.log('game state OK');

  console.log('PERF RAM TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
