// Tide v37 · Fase 1: Keping Rantau (+ edit manual tercatat), golongan, Pesanan Harian (lembar, kejadian, hadiah,
// streak, Tali Tambat, Peti, tukar), kait di endpoint inti, Kedai Rantau (beli, pasang, jasa), Gotong Royong IKN.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const DAY = 86400000;
  const setOffsetDays = d => H.sql(`update game.config set value = $1 where key = 'HarianClockOffset'`, [String(d * DAY)]);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);

  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const A = await mk('hr_alfa', 'Kapten Alfa');
  const B = await mk('hr_bravo', 'Kapten Bravo');
  const keping = async u => Number((await one('select keping from game.players where player_id = $1', [u.id])).keping);
  const gold = async u => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const sheet = async u => one(`select * from game.hr_sheets where player_id = $1 and day = game.hr_today()`, [u.id]);
  const inbox = async u => (await H.sql(`select item from game.mp_inbox where player_id = $1 and item ->> 'type' = 'harian' order by seq`, [u.id])).map(r => r.item);
  const ev = (u, kind, amount, ctx) => H.sql(`select game.hr_hook($1, $2, $3, $4::jsonb)`, [u.id, kind, amount, JSON.stringify(ctx || {})]);
  const catalog = (await one(`select game.hr_catalog() c`)).c;
  const task = (code, gol) => {
    const e = catalog.find(x => x.c === code), n = e.n[(gol || 1) - 1], gl = [[1000, 2500, 5000], [5000, 15000, 30000], [20000, 50000, 100000]][(gol || 1) - 1];
    return { c: code, t: e.t, g: e.g || code, l: e.l, n, goal: e.goal === 'n' ? n : 1, p: 0, s: 0, x: [], done: false, gold: gl[e.t - 1], kp: [5, 10, 20][e.t - 1] };
  };
  const setTasks = (u, codes, gol) => H.sql(`update game.hr_sheets set tasks = $2::jsonb, lunas = false, sapu = false where player_id = $1 and day = game.hr_today()`,
    [u.id, JSON.stringify(codes.map(c => task(c, gol)))]);

  // --- gerbang fitur (mode penguji) ------------------------------------------------
  let gs = await A.call('api_getGameState', [null]);
  ok(gs.harian === null && gs.gotong === null, 'fitur tertutup: state null');
  await H.expectError(() => A.call('api_kedai', ['daftar']), /belum dibuka/);
  await H.sql(`update game.config set value = 'hr_alfa, someone' where key = 'FiturPenguji'`);
  gs = await A.call('api_getGameState', [null]);
  ok(gs.harian && gs.harian.open.harian && gs.harian.open.kedai && gs.harian.open.gotong, 'penguji melihat fitur ' + JSON.stringify(gs.harian && gs.harian.open));
  ok((await B.call('api_getGameState', [null])).harian === null, 'bukan penguji: tetap tertutup');
  ok(gs.harian.golName === 'Jukung' && gs.harian.keping === 0, 'golongan Jukung, keping 0');

  // --- golongan --------------------------------------------------------------------
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6)`, [B.id]);
  ok(Number((await one(`select game.golongan($1) g`, [B.id])).g) === 2, 'Quest 1 tamat = Pinisi');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'barsati', 16)`, [B.id]);
  ok(Number((await one(`select game.golongan($1) g`, [B.id])).g) === 3, 'Quest 4 tamat = Galiung');

  // --- keping: admin, edit manual tercatat, tidak bisa negatif -----------------------
  ok(/Kapten Alfa: 500 keping/.test((await one(`select game.admin_keping('hr_alfa', 500, 'uji') r`)).r), 'admin_keping');
  await H.sql(`update game.players set keping = 800 where player_id = $1`, [A.id]);
  const log = await H.sql(`select delta, saldo, sumber, catatan from game.keping_log where player_id = $1 order by id`, [A.id]);
  ok(log.length === 2 && log[0].sumber === 'admin' && log[0].catatan === 'uji' && log[1].sumber === 'manual' && Number(log[1].delta) === 300,
    'keping_log mencatat admin & edit manual ' + JSON.stringify(log));
  await H.expectError(() => H.sql(`select game.keping_add($1, -5000, 'uji')`, [A.id]), /tidak cukup/);
  ok(await keping(A) === 800, 'saldo tidak berubah setelah ditolak');
  ok(Number((await one(`select game.admin_keping_all(-100000, 'nol') n`)).n) >= 2 && await keping(A) === 0, 'admin_keping_all tidak membuat negatif');

  // --- lembar harian ----------------------------------------------------------------
  let s = gs.harian;
  ok(s.tasks.length === 3 && s.tasks.map(t => t.t).join() === '1,2,3', 'lembar 3 tingkat ' + JSON.stringify(s.tasks.map(t => t.c)));
  ok(new Set(s.tasks.map(t => t.g)).size === 3, 'tidak ada kelompok dobel');
  ok(s.resetInMs > 0 && s.resetInMs <= DAY, 'hitung mundur reset');
  ok(JSON.stringify((await A.call('api_harian', ['status'])).harian.tasks) === JSON.stringify(s.tasks), 'lembar tetap sama saat dibuka ulang');

  // untung pacu: lantai 0,6 x harga dasar
  ok(Number((await one(`select game.pacu_profit(1000, 10, null, 100) p`)).p) === 400, 'barang tanpa modal dinilai 60% harga dasar');
  ok(Number((await one(`select game.pacu_profit(1000, 10, 20, 100) p`)).p) === 400, 'modal murah (Bursa) terkena lantai');
  ok(Number((await one(`select game.pacu_profit(1000, 10, 80, 100) p`)).p) === 200, 'modal jujur dipakai apa adanya');

  // kejadian & hadiah
  await setTasks(A, ['M1', 'S1', 'T5']);
  const g0 = await gold(A);
  await ev(A, 'sell', 1000, { city: 'joungjava', comm: 'batik', qty: 10, avg: 90, base: 160 });   // untung 1000 - 10*max(90,96) = 40
  let sh = await sheet(A);
  ok(!sh.tasks[0].done && Number(sh.tasks[1].p) === 40, 'untung kecil belum memenuhi M1, S1 bertambah ' + JSON.stringify(sh.tasks));
  await ev(A, 'sell', 3000, { city: 'joungjava', comm: 'batik', qty: 10, avg: 90, base: 160 });   // untung 2040
  sh = await sheet(A);
  ok(sh.tasks[0].done && await gold(A) === g0 + 1000 && await keping(A) === 5, 'M1 selesai: +1000 gold, +5 keping');
  await ev(A, 'sell', 500, { city: 'joungjava', comm: 'batik', qty: 10, avg: 90, base: 160 });    // rugi 460
  sh = await sheet(A);
  ok(Number(sh.tasks[1].p) === 1620 && !sh.tasks[1].done, 'rugi mengurangi untung harian ' + sh.tasks[1].p);
  await ev(A, 'sell', 3000, { city: 'bjorneo', comm: 'batik', qty: 10, avg: 90, base: 160 });
  sh = await sheet(A);
  ok(sh.tasks[1].done && sh.lunas && !sh.sapu, 'S1 selesai -> Lunas (2/3)');
  let st = await one(`select * from game.hr_streak where player_id = $1`, [A.id]);
  ok(st.cur === 1 && await keping(A) === 5 + 10 + 5, 'streak hari 1 (+5 keping) ' + JSON.stringify(st));
  await ev(A, 'dig', 1, {});
  sh = await sheet(A);
  ok(sh.sapu && await keping(A) === 20 + 20 + 10, 'Sapu Bersih (+20 Tantangan, +10 bonus)');
  const ib = await inbox(A);
  ok(ib.length >= 3 && ib.some(i => i.lunas && i.streak && i.streak.cur === 1) && ib.some(i => i.sapu), 'kabar inbox harian ' + JSON.stringify(ib.map(i => [i.done.length, i.lunas, i.sapu])));

  // kait endpoint inti: beli di pulau penghasil (M5), kedatangan (M2)
  await setTasks(A, ['M5', 'M2', 'T2']);
  const prod = await one(`select m.commodity_id c from game.market m join game.commodities c on c.id = m.commodity_id
    where m.city_id = 'sunda_empire' and m.role = 'produce' and c.tier <> 'premium' and c.active order by c.base limit 1`);
  await A.call('api_buy', ['sunda_empire', prod.c, 2]);
  sh = await sheet(A);
  ok(sh.tasks[0].done, 'api_buy di pulau penghasil memenuhi M5 (' + prod.c + ')');
  ok((await one(`select src_city from game.inventory where player_id = $1 and item_id = $2`, [A.id, prod.c])).src_city === 'sunda_empire', 'asal beli tercatat');
  await A.call('api_setSail', ['joungjava']);
  await H.sql(`update game.player_location set arrive_at = now() - interval '1 second' where player_id = $1`, [A.id]);
  await A.call('api_getGameState', [null]);
  // peluang bajak laut minimal 1%: bila dicegat, tuntaskan kedatangan seperti setelah pertempuran
  if ((await one(`select destination_city_id d from game.player_location where player_id = $1`, [A.id])).d) {
    await H.sql(`select game.voy_complete_arrival($1, 'joungjava', 'uji')`, [A.id]);
  }
  sh = await sheet(A);
  ok(Number(sh.tasks[1].p) === 1 && sh.tasks[1].x[0] === 'joungjava', 'kedatangan tercatat untuk M2 ' + JSON.stringify(sh.tasks[1]));
  // jual di pulau jauh dari tempat beli (T2) lewat api_sell sungguhan
  const far = await one(`select c.city_id from game.cities c where not c.hidden and game.hr_far('sunda_empire', c.city_id) order by c.city_id limit 1`);
  ok(far && far.city_id, 'ada pulau jauh dari Sunda');
  await H.sql(`update game.player_location set city_id = $2, destination_city_id = null where player_id = $1`, [A.id, far.city_id]);
  await H.sql(`update game.inventory set cost = 1 where player_id = $1 and item_id = $2`, [A.id, prod.c]);   // modal sangat murah -> lantai yang dipakai
  const r = await A.call('api_sell', [far.city_id, prod.c, 2]);
  sh = await sheet(A);
  const exp = Number((await one(`select game.pacu_profit($1, 2, 0.5, (select base from game.commodities where id = $2)) p`, [r.totalRevenue, prod.c])).p);
  ok(sh.tasks[2].done === (exp > 0), 'api_sell di pulau jauh -> T2 (untung pacu ' + exp + ')');

  // --- tukar tugas ------------------------------------------------------------------
  await setTasks(A, ['M3', 'S3', 'T5']);
  s = (await A.call('api_harian', ['tukar', 0])).harian;
  ok(s.tasks[0].c !== 'M3' && s.tasks[0].t === 1 && s.rerollLeft === 0, 'tukar slot Mudah ' + s.tasks[0].c);
  await H.expectError(() => A.call('api_harian', ['tukar', 1]), /habis/);
  await H.sql(`update game.hr_sheets set reroll_bonus = 1, tasks = jsonb_set(tasks, '{1,p}', '1') where player_id = $1 and day = game.hr_today()`, [A.id]);
  await H.expectError(() => A.call('api_harian', ['tukar', 1]), /sudah dimulai/);

  // --- streak lintas hari, Tali Tambat, Peti ke-7 -------------------------------------
  const lunasDay = async () => { await A.call('api_harian', ['status']); await setTasks(A, ['M3', 'S3', 'T5']); await ev(A, 'fish', 1, {}); await ev(A, 'fish', 1, {}); await ev(A, 'fish', 1, {}); await ev(A, 'combat_win', 1, {}); };
  await setOffsetDays(1); await lunasDay();
  st = await one(`select * from game.hr_streak where player_id = $1`, [A.id]);
  ok(st.cur === 2, 'hari berikutnya: streak 2');
  await setOffsetDays(3); await lunasDay();   // hari ke-2 bolong -> Tali Tambat
  st = await one(`select * from game.hr_streak where player_id = $1`, [A.id]);
  ok(st.cur === 3 && st.tambat_day, 'Tali Tambat memaafkan satu hari bolong ' + JSON.stringify(st));
  await setOffsetDays(5); await lunasDay();   // bolong lagi dalam 7 hari -> mulai ulang
  st = await one(`select * from game.hr_streak where player_id = $1`, [A.id]);
  ok(st.cur === 1, 'bolong kedua dalam 7 hari: streak ulang');
  await H.sql(`update game.hr_streak set tambat_extra = 1 where player_id = $1`, [A.id]);
  await setOffsetDays(7); await lunasDay();   // bolong, Tali Tambat masih terpakai -> cadangan
  st = await one(`select * from game.hr_streak where player_id = $1`, [A.id]);
  ok(st.cur === 2 && st.tambat_extra === 0, 'Tali Tambat Cadangan menjaga streak');
  const kp0 = await keping(A);
  for (let d = 8; d <= 12; d++) { await setOffsetDays(d); await lunasDay(); }
  st = await one(`select * from game.hr_streak where player_id = $1`, [A.id]);
  ok(st.cur === 7 && st.peti_n === 1, 'hari ke-7: Peti Rantau ' + JSON.stringify(st));
  const peti = (await H.sql(`select item_id from game.kd_owned where player_id = $1 and source = 'peti'`, [A.id]));
  ok(peti.length === 1, 'isi peti masuk Kedai ' + JSON.stringify(peti));
  ok(await keping(A) === kp0 + 5 * (5 + 10) + 4 * 5 + 30, 'keping 5 hari (tugas + streak + peti) ' + (await keping(A) - kp0));
  await H.sql(`select game.hr_peti($1, 8)`, [A.id]);
  ok(Number((await one(`select game.kd_qty($1, 'panji_tujuh') q`, [A.id])).q) === 1, 'Panji Tujuh Tokoh dijamin pada Peti ke-8');
  await setOffsetDays(0);

  // --- Kedai Rantau ------------------------------------------------------------------
  await H.sql(`select game.admin_keping('hr_alfa', 5000, 'uji kedai')`);
  const k0 = await keping(A);
  let kd = (await A.call('api_kedai', ['daftar'])).kedai;
  const parang = kd.items.find(i => i.id === 'layar_parang');
  ok(parang && parang.price === 750 && parang.qty === 0, 'harga layar Biasa 750');
  kd = (await A.call('api_kedai', ['beli', 'layar_parang'])).kedai;
  ok(kd.keping === k0 - 750 && kd.items.find(i => i.id === 'layar_parang').qty === 1, 'beli rupa');
  await H.expectError(() => A.call('api_kedai', ['beli', 'layar_parang']), /sudah memiliki/);
  await H.expectError(() => A.call('api_kedai', ['beli', 'aura_lentera_ikn']), /tidak dijual/);
  await H.expectError(() => A.call('api_kedai', ['pasang', 'layar_songket']), /belum memiliki/);
  let rr = await A.call('api_kedai', ['pasang', 'layar_parang']);
  ok(rr.shipVisual && rr.shipVisual.kd && rr.shipVisual.kd.layar === 'layar_parang', 'rupa terpasang di ship_visual');
  const pres = await one(`select s from game.mp_presence where player_id = $1`, [A.id]);
  ok(pres && pres.s && pres.s.kd && pres.s.kd.layar === 'layar_parang', 'rupa terkirim ke kehadiran (kapten lain melihat)');
  rr = await A.call('api_kedai', ['lepas', 'layar']);
  ok(!rr.shipVisual.kd, 'lepas rupa');
  // harga: pengali & harga admin
  await H.sql(`update game.config set value = '2' where key = 'KedaiPriceMul'`);
  ok((await A.call('api_kedai', ['daftar'])).kedai.items.find(i => i.id === 'layar_songket').price === 1500, 'KedaiPriceMul x2');
  await H.sql(`update game.config set value = '1' where key = 'KedaiPriceMul'`);
  await H.sql(`update game.kd_items set price_admin = 1 where id = 'layar_kawung'`);
  ok((await A.call('api_kedai', ['daftar'])).kedai.items.find(i => i.id === 'layar_kawung').price === 1, 'price_admin menimpa harga');
  await H.sql(`update game.kd_items set price_admin = null where id = 'layar_kawung'`);
  // incaran
  ok((await A.call('api_kedai', ['incar', 'haluan_ikan'])).harian.incaranName === 'Haluan Ikan Terbang', 'incaran tampil di state');
  // jasa: Pembaca Arus (waktu tempuh -15%, 3 pelayaran)
  await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = null, arrive_at = null, depart_at = null where player_id = $1`, [A.id]);
  const normal = await A.call('api_setSail', ['joungjava']);
  await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = null, arrive_at = null, depart_at = null where player_id = $1`, [A.id]);
  await A.call('api_kedai', ['beli', 'jasa_arus']);
  rr = await A.call('api_kedai', ['pakai', 'jasa_arus']);
  ok(rr.kedai.buffs.arus === 3, 'Pembaca Arus aktif 3 pelayaran');
  await A.call('api_kedai', ['beli', 'jasa_pengawal']);
  await H.expectError(() => A.call('api_kedai', ['pakai', 'jasa_pengawal']), /satu waktu/);
  const fast = await A.call('api_setSail', ['joungjava']);
  ok(Math.abs(fast.travelSeconds - Math.round(normal.travelSeconds * 0.85)) <= 1, 'pelayaran 15% lebih cepat ' + normal.travelSeconds + ' -> ' + fast.travelSeconds);
  ok(Number((await one(`select uses_left from game.kd_buffs where player_id = $1 and kind = 'arus'`, [A.id])).uses_left) === 2, 'jatah Pembaca Arus berkurang');
  // jasa: Pengawal pada bajak laut acak, tidak pada bos quest
  await H.sql(`delete from game.kd_buffs where player_id = $1`, [A.id]);
  await A.call('api_kedai', ['pakai', 'jasa_pengawal']);
  const enc = (await one(`select game.kd_enc($1, '{"randomPirate":true,"enemyMaxHp":100}'::jsonb) e`, [A.id])).e;
  ok(enc.allyDmg === 12 && /Daeng/.test(enc.allyNote), 'Pengawal: perahu Daeng ikut menembak ' + JSON.stringify(enc));
  ok(!(await one(`select game.kd_enc($1, '{"boss":"mrgap","enemyMaxHp":600}'::jsonb) e`, [A.id])).e.allyDmg, 'tidak untuk bos quest');
  // jasa: Kupon Reparasi
  await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = null, arrive_at = null, depart_at = null where player_id = $1`, [A.id]);
  await H.sql(`update game.ships set condition = 40 where player_id = $1`, [A.id]);
  await A.call('api_kedai', ['beli', 'jasa_kupon']);
  const kup0 = Number((await one(`select game.kd_qty($1, 'jasa_kupon') q`, [A.id])).q);   // Peti Rantau mungkin sudah memberi kupon
  const gk = await gold(A);
  rr = await A.call('api_kedai', ['pakai', 'jasa_kupon']);
  ok(Number(rr.ship.Condition) > 40 && await gold(A) === gk && rr.kedai.items.find(i => i.id === 'jasa_kupon').qty === kup0 - 1, 'Kupon Reparasi gratis & berkurang satu ' + JSON.stringify([rr.ship.Condition, gk, await gold(A), rr.kedai.items.find(i => i.id === 'jasa_kupon').qty]));
  // jasa: Juru Taksir
  await H.sql(`select game.adjust_inventory($1, 'lada', 5)`, [A.id]);
  rr = await A.call('api_kedai', ['beli', 'jasa_taksir']); rr = await A.call('api_kedai', ['pakai', 'jasa_taksir']);
  ok(rr.taksir.length >= 1 && rr.taksir.find(t => t.comm === 'lada').best.length >= 1, 'Juru Taksir menunjukkan pelabuhan terbaik');
  // keping kurang
  await H.sql(`update game.players set keping = 10 where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_kedai', ['beli', 'haluan_ikan']), /tidak cukup/);

  // --- Gotong Royong: Restorasi IKN ----------------------------------------------------
  await H.expectError(() => A.call('api_gotong', ['sumbang', 10000, 0]), /IKN/);
  await H.sql(`update game.player_location set city_id = 'ikn', destination_city_id = null, arrive_at = null where player_id = $1`, [A.id]);
  await H.sql(`update game.players set gold = 6000000, keping = 600 where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_gotong', ['sumbang', 500, 0]), /minimal/);
  await H.expectError(() => A.call('api_gotong', ['sumbang', 9000000, 0]), /tidak cukup/);
  let gr = await A.call('api_gotong', ['sumbang', 4000000, 500]);
  ok(gr.gotong.total === 4500000 && gr.gotong.stage === 0 && gr.lentera && await keping(A) === 100, 'keping dihitung 1.000 gold; Lentera IKN untuk penyumbang besar');
  ok(Number((await one(`select game.kd_qty($1, 'aura_lentera_ikn') q`, [A.id])).q) === 1, 'Lentera IKN masuk Kedai');
  gr = await A.call('api_gotong', ['sumbang', 600000, 0]);
  ok(gr.stageUp && gr.gotong.stage === 1 && gr.gotong.goal === 100000000, 'tahap 1 (5 juta) selesai, total target 100 juta');
  const chat = await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`);
  ok(/Restorasi IKN tahap 1 selesai/.test(chat.msg.tx), 'pengumuman chat dunia');
  ok((await A.call('api_getGameState', [null])).gotong.ikn.stage === 1, 'tahap terlihat di state');
  ok(Number((await one(`select game.gr_repair_mul('ikn') m`)).m) === 1, 'diskon reparasi belum aktif');
  await H.sql(`update game.gr_projects set total = 35000000, stage = 3 where id = 'ikn'`);
  ok(Number((await one(`select game.gr_repair_mul('ikn') m`)).m) === 0.8, 'tahap 3: reparasi IKN -20%');
  await H.sql(`update game.gr_projects set total = 99999000, stage = 4 where id = 'ikn'`);
  await H.sql(`update game.players set gold = 10000 where player_id = $1`, [A.id]);
  gr = await A.call('api_gotong', ['sumbang', 2000, 0]);
  ok(gr.gotong.stage === 5, 'tahap 5 selesai');
  const fest = await one(`select * from game.city_events where city_id = 'ikn' and event_type = 'festival'`);
  ok(fest && fest.label === 'Festival Restorasi', 'Festival Restorasi dimulai');
  await H.expectError(() => A.call('api_gotong', ['sumbang', 2000, 0]), /sudah selesai/);

  // --- kait aman: error di Pesanan tidak menggagalkan jual ---------------------------------
  await H.sql(`update game.hr_sheets set tasks = '[{"c":"S1","goal":"x"}]'::jsonb where player_id = $1 and day = game.hr_today()`, [A.id]);
  await H.sql(`update game.player_location set city_id = 'sunda_empire' where player_id = $1`, [A.id]);
  await H.sql(`select game.adjust_inventory($1, 'garam', 3)`, [A.id]);
  ok((await A.call('api_sell', ['sunda_empire', 'garam', 3])).totalRevenue > 0, 'jual tetap jalan walau lembar rusak');

  console.log('0032_harian_kedai OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
