// Saga 2 · Quest 6 "Bunga yang Tak Pernah Layu": coco epan, pinjaman 10 hari (2x), Peti Bantuan IKN,
// Mata Syahbandar, melati -> Gading Island, Stumpy, makam, ikan Kerapu Fajar (fajar), Sandi Pelikan,
// pelunasan, adu gasing, surat untuk Marlya. Juga menjaga: Buku Ikan Quest 2 tetap 14, waktu tempuh
// antar-pulau lama tidak berubah, peran pasar kopi bertahan setelah migrasi diulang.
const fs = require('fs'), path = require('path');
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('cocoepan1'); await u.call('api_createCharacter', ['Pembawa Bunga', 'merchant']);
  const pid = u.id;
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const cb = a => u.call('api_cocoepan', a);
  const st = async () => (await u.call('api_cocoepan', ['status'])).cocoepan;
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [pid]))[0].gold);
  const bank = async () => Number((await H.sql('select bank_balance from game.players where player_id = $1', [pid]))[0].bank_balance);
  const item = async id => Number((await H.sql('select game.item_qty($1, $2) q', [pid, id]))[0].q);
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const dayLenMin = Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) v`)).v);
  // geser jam dunia ke pecahan hari tertentu (0..1)
  const setFrac = async f => {
    const r = await one(`select game.now_ms() n, game.cfg_num('WorldStartTimestamp', 0) s`);
    const len = dayLenMin * 60000, now = Number(r.n), start = Number(r.s);
    const cur = ((now - start) % len) / len;
    let d = f - cur; if (d < 0) d += 1;
    await H.shiftTime(Math.round(d * len) + 1000);
  };

  // --- Penjaga dunia: hal yang TIDAK boleh berubah untuk pemain lain ----------
  const book = await one(`select game.tg_book($1) b`, [pid]);
  assert(book.b.total === 14, 'Buku Ikan (syarat Quest 2) tetap 14 ikan: ' + JSON.stringify(book.b));
  const info = await u.call('api_mgFishInfo', []);
  assert(info.total === 14, 'Info dermaga tetap 14 ikan');
  const fb = await u.call('api_mgFishBook', []);
  assert(fb.length === 14 && !fb.some(f => f.id === 'kerapu_fajar'), 'Kerapu Fajar tidak muncul di Buku Ikan');
  const rng = await one(`select dmax, dmin from game.voy_dist_range()`);
  const rngOld = await one(`select max(game.voy_map_distance(a.city_id, b.city_id)) dmax from game.cities a join game.cities b on a.city_id < b.city_id
    where not game.spot_city(a.city_id) and not game.spot_city(b.city_id) and a.city_id <> 'gading_island' and b.city_id <> 'gading_island'`);
  assert(Math.abs(Number(rng.dmax) - Number(rngOld.dmax)) < 1e-9, 'rentang jarak dunia tidak ikut Gading Island');
  const tFar = Number((await one(`select game.voy_travel_seconds(game.voy_map_distance('sunda_empire', 'gading_island'), '{}'::jsonb) t`)).t);
  const tMax = Number((await one(`select game.voy_travel_seconds($1, '{}'::jsonb) t`, [Number(rng.dmax)])).t);
  const tNear = Number((await one(`select game.voy_travel_seconds(game.voy_map_distance('marie_regal', 'gading_island'), '{}'::jsonb) t`)).t);
  assert(tMax === 240 && tFar > 240 && tFar <= 300, 'Sunda -> Gading laut terbuka (>240 dtk, <=300): ' + tFar);
  assert(tNear < tFar, 'lewat Marie Regal lebih dekat: ' + tNear);
  // Gading tersembunyi untuk pemain biasa
  assert((await one(`select game.city_open($1, 'gading_island') o`, [pid])).o === false, 'Gading tertutup sebelum quest');
  assert(!(await u.call('api_getGameState', [null])).unlocks.includes('gading_island'), 'tidak ada di unlocks');
  // kopi premium: hanya produsen Gading, konsumen 4 kota, tidak bisa dibeli di kota lain
  const roles = await H.sql(`select city_id, role from game.market where commodity_id = 'kopi_bourbon_chiroso' order by city_id`);
  const R = Object.fromEntries(roles.map(r => [r.city_id, r.role]));
  assert(R.gading_island === 'produce' && R.sunda_empire === 'consume' && R.skitraw === 'consume' && R.joungjava === 'neutral', 'peran kopi ' + JSON.stringify(R));
  const gm = await H.sql(`select count(*)::int n from game.market where city_id = 'gading_island'`);
  assert(gm[0].n === 31, 'pasar Gading lengkap 31 barang: ' + gm[0].n);
  await go('sunda_empire');
  await H.expectError(() => u.call('api_buy', ['sunda_empire', 'kopi_sumatera_gayo', 1]), /Stok|tidak tersedia/);
  const mk = await u.call('api_getMarket', ['sunda_empire']);
  const gayo = mk.items.find(i => i.commodityId === 'kopi_sumatera_gayo');
  assert(gayo && gayo.group === 'minuman' && gayo.tier === 'premium' && Math.floor(gayo.stock) === 0, 'kopi tampil di pasar Sunda (bisa dijual): ' + JSON.stringify(gayo && { g: gayo.group, s: gayo.stock }));
  const missions = await H.sql(`select id from game.commodities where active and tier <> 'premium' and id like 'kopi\\_%' escape '\\'`);
  assert(missions.length === 0, 'kopi baru tidak masuk papan misi');

  // --- Prasyarat --------------------------------------------------------------
  assert((await st()) === null, 'tersembunyi sebelum Quest 5 selesai');
  await H.expectError(() => cb(['talk']), /masih tertutup/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at) values
    ($1, 'gala', 6, now()), ($1, 'toogood', 10, now()), ($1, 'warwerwor', 12, now()), ($1, 'barsati', 16, now()),
    ($1, 'kompas', 8, now())`, [pid]);
  let s = await st();
  assert(s && s.step === 0 && s.eligible && !s.timeOk && s.readyInMs > 0, 'menunggu 2 hari game ' + JSON.stringify(s));
  await go('joungjava');
  await H.expectError(() => cb(['talk']), /tidak menerima tamu/);
  await H.sql(`update game.player_quests set done_at = now() - (2.1 * $2 || ' minutes')::interval where player_id = $1 and quest_id = 'kompas'`, [pid, dayLenMin]);
  s = await st(); assert(s.timeOk && s.loanMax === 5000000 && s.bankNeed === 1000000, 'siap ' + JSON.stringify(s));

  // --- Babak 1 ----------------------------------------------------------------
  await H.sql('update game.players set gold = 1000, bank_balance = 500000, bank_last_interest_day = game.game_day() where player_id = $1', [pid]);
  await go('skitraw');
  await H.expectError(() => cb(['talk']), /Javasche Bank/);
  await go('joungjava');
  s = (await cb(['talk'])).cocoepan; assert(s.step === 1 && !s.bankOk, 'Babak 1, bank kurang');
  await H.expectError(() => cb(['loan', '1000000']), /Saldo Bank tidak cukup/);
  await H.sql('update game.players set bank_balance = 7000000 where player_id = $1', [pid]);
  await H.expectError(() => cb(['loan', '500000']), /minimal 1.000.000/);
  await H.expectError(() => cb(['loan', '6000000']), /Paling banyak/);
  s = (await cb(['decline'])).cocoepan; assert(s.declined && s.step === 1, 'tolak: tetap bisa kembali');
  // palka penuh -> tidak bisa menerima Peti Bantuan
  await H.sql(`select game.adjust_inventory($1, 'beras', 25)`, [pid]);
  await H.expectError(() => cb(['loan', '1500000']), /Kosongkan 10 ruang/);
  await H.sql(`select game.adjust_inventory($1, 'beras', -25)`, [pid]);
  // bunga bank tertunda dihitung dulu sebelum dipotong
  await H.sql('update game.players set bank_last_interest_day = game.game_day() - 2 where player_id = $1', [pid]);
  const accrued = Number((await one(`select (game.bank_state($1) ->> 'bankBalance')::bigint b`, [pid])).b);
  await H.sql('update game.players set bank_balance = 7000000, bank_last_interest_day = game.game_day() - 2 where player_id = $1', [pid]);
  const r1 = await cb(['loan', '1500000']);
  s = r1.cocoepan;
  assert(s.step === 2 && s.loan === 1500000 && s.repay === 3000000 && s.holdDaysLeft === 10 && s.returnInMs > 0, 'pinjaman 1,5 juta -> 3 juta ' + JSON.stringify(s));
  assert((await bank()) === accrued - 1500000 && r1.bank && r1.bank.bankBalance === accrued - 1500000, 'bank dipotong setelah bunga: ' + (await bank()) + ' vs ' + accrued);
  assert((await item('qi_peti_bantuan')) === 1 && s.hasCrate, 'Peti Bantuan di palka');
  await H.expectError(() => cb(['loan', '1000000']), /sudah kau berikan/);

  // --- Babak 2 ----------------------------------------------------------------
  await H.expectError(() => cb(['deliver']), /IKN/);
  await go('ikn');
  s = (await cb(['deliver'])).cocoepan; assert(s.step === 3 && !s.hasCrate, 'Peti dibagikan');
  // krisis Q5 di IKN & Joungjava pulih untuk pemain ini
  await H.sql(`update game.player_quests set done_at = now() where player_id = $1 and quest_id = 'kompas'`, [pid]);
  const mIkn = Number((await one(`select game.quest_price_mul($1, 'ikn', 'besi') m`, [pid])).m);
  const mSkt = Number((await one(`select game.quest_price_mul($1, 'skitraw', 'besi') m`, [pid])).m);
  assert(mIkn === 1 && mSkt !== 1, 'kota yang dibantu pulih lebih cepat: ' + mIkn + ' / ' + mSkt);
  await go('joungjava');
  await H.expectError(() => cb(['flower']), /titipan/);
  s = (await cb(['syahbandar', 'gagal'])).cocoepan; assert(!s.syah, 'gagal: boleh ulang');
  s = (await cb(['syahbandar', 'ok'])).cocoepan; assert(s.syah && s.step === 3, 'kapal penimbun tertangkap');

  // --- Babak 3 ----------------------------------------------------------------
  const rf = await cb(['flower']);
  assert(rf.cocoepan.step === 4 && rf.cocoepan.hasFlower, 'melati diterima');
  assert(rf.unlocks.includes('gading_island') && rf.citiesVersion === '5-gading' && rf.cities.some(c => c.CityId === 'gading_island' && c.Type === 'Gading' && c.TypeFlavor), 'peta meluas: unlocks + kota');
  assert((await u.call('api_getSailOptions', [])).some(o => o.cityId === 'gading_island'), 'Gading di daftar berlayar');
  await H.expectError(() => cb(['stumpy']), /Gading Island/);
  await go('gading_island');
  s = (await cb(['stumpy'])).cocoepan; assert(s.step === 5, 'felyx di Stumpy');
  const rg = await cb(['grave']);
  assert(rg.cocoepan.step === 6 && !rg.cocoepan.hasFlower && (await item('qi_buku_pancing_maudy')) === 1, 'makam & Buku Pancing Legenda');
  await H.expectError(() => cb(['mural']), /terkunci/);

  // ikan Kerapu Fajar: hanya fajar, hanya Gading, hanya langkah 6
  await setFrac(0.4);
  assert(Number((await one(`select game.fish_quest_weight($1, 'kerapu_fajar', 'gading_island') w`, [pid])).w) === 0, 'siang: tidak muncul');
  await setFrac(0.98);
  assert((await st()).dawn === true, 'fajar terdeteksi');
  assert(Number((await one(`select game.fish_quest_weight($1, 'kerapu_fajar', 'gading_island') w`, [pid])).w) > 1, 'fajar: muncul');
  assert(Number((await one(`select game.fish_quest_weight($1, 'kerapu_fajar', 'bjorneo') w`, [pid])).w) === 0, 'kota lain: tidak');
  assert(Number((await one(`select game.fish_quest_weight($1, 'peti', 'bjorneo') w`, [pid])).w) === 1, 'kait Peti Karam Barsati tetap jalan');
  await H.sql(`insert into game.mp_fish_book(player_id, fish_id, n, best_kg, best_gold) values ($1, 'kerapu_fajar', 1, 9.5, 1100)`, [pid]);
  const qi = (await one(`select game.fish_quest_catch($1, 'kerapu_fajar') q`, [pid])).q;
  s = await st();
  assert(s.step === 7 && Number(s.legendKg) === 9.5 && qi && qi.quest === 'cocoepan', 'Kerapu Fajar tertangkap ' + JSON.stringify(s));
  assert((await H.sql(`select 1 from game.mp_fish_book where player_id = $1 and fish_id = 'kerapu_fajar'`, [pid])).length === 0, 'tidak tercatat di Buku Ikan');
  assert((await u.call('api_mgFishInfo', [])).found === 0, 'temuan Buku Ikan tidak bertambah');

  // --- Babak 4 & 5 ------------------------------------------------------------
  s = (await cb(['mural'])).cocoepan; assert(s.step === 8, 'Sandi Pelikan selesai');
  await go('joungjava');
  await H.expectError(() => cb(['return']), /Belum waktunya/);
  await H.sql(`update game.player_quests set data = data || jsonb_build_object('loanDay', game.game_day() - 10) where player_id = $1 and quest_id = 'cocoepan'`, [pid]);
  s = await st(); assert(s.repayReady && s.holdDaysLeft === 0 && s.returnInMs === 0, 'hari kesepuluh');
  const g0 = await gold();
  const rr = await cb(['return']);
  assert(rr.cocoepan.step === 9 && rr.paid === 3000000 && (await gold()) === g0 + 3000000 && rr.newGold === g0 + 3000000, 'pelunasan 2x ke gold');
  await H.expectError(() => cb(['return']), /belum memanggilmu/);
  await H.expectError(() => cb(['surat']), /Tidak ada surat/);
  s = (await cb(['gasing', 'lost'])).cocoepan; assert(s.step === 10 && s.gasing === 'lost' && s.hasLetter, 'adu gasing -> surat');

  // --- Epilog -----------------------------------------------------------------
  await H.expectError(() => cb(['surat']), /Istana Hening/);
  await go('marie_regal');
  s = (await cb(['surat'])).cocoepan; assert(s.done && s.step === 11 && !s.hasLetter, 'Quest 6 selesai');
  const gs = await u.call('api_getGameState', [null]);
  assert(gs.cocoepan && gs.cocoepan.done && gs.unlocks.includes('gading_island'), 'state & Gading tetap terbuka');

  // --- Migrasi diulang: peran pasar kopi & Gading tetap ------------------------
  const dir = path.join(__dirname, '..', 'supabase', 'migrations');
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort()) await H.db.exec(fs.readFileSync(path.join(dir, f), 'utf8'));
  const R2 = Object.fromEntries((await H.sql(`select city_id, role from game.market where commodity_id = 'kopi_flores_bajawa'`)).map(r => [r.city_id, r.role]));
  assert(R2.gading_island === 'produce' && R2.paradiso === 'consume', 'peran kopi bertahan setelah migrasi diulang ' + JSON.stringify(R2));
  assert((await one(`select role from game.market where city_id = 'gading_island' and commodity_id = 'silk'`)).role === 'produce', 'peran Gading bertahan');
  assert((await one(`select game.tg_book($1) b`, [pid])).b.total === 14, 'Buku Ikan tetap 14 setelah diulang');
  assert((await st()).step === 11, 'progres quest utuh setelah diulang');
  console.log('COCOEPAN TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('ERROR:', e); process.exit(1); });
