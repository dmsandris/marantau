// Quest rahasia "Surat yang Selalu Tertinggal Satu Pelabuhan" (Surat Pulang) + perk archetype hidup.
// Gerbang Saga 2 & SuratOpen, side quest satu per satu (dua arah), 15 langkah (kota, malam, barter palka, lampiran),
// Urut Cap diperiksa server (solver: satu urutan sah), Daftar Sensor, balasan -> varian (Pirate tertukar),
// rahasia (tanpa log/TJ/chat), dibekukan Saga 3 (perk ikut tidur), lalu efek perk 8 archetype + pagar.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const SOL = require('./surat-solver');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const cfg = (k, v) => H.sql(`insert into game.config(key, value) values ($1, $2) on conflict (key) do update set value = excluded.value`, [k, v]);
  const lenMs = async () => Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) * 60000 v`)).v);
  const setFrac = async (f) => { const L = await lenMs(); const now = Number((await one('select game.now_ms() v')).v); await cfg('WorldStartTimestamp', String(Math.round(now - f * L - 2000))); };
  const siang = () => setFrac(0.4), malam = () => setFrac(0.8);
  const ke = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const gold = async (u) => Number((await one('select gold g from game.players where player_id = $1', [u.id])).g);
  const setGold = (u, g) => H.sql('update game.players set gold = $2 where player_id = $1', [u.id, g]);
  const mk = async (name, uname, arch = 'merchant', saga2 = true) => {
    const u = await H.user(uname); await u.call('api_createCharacter', [name, arch]);
    if (saga2) await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'duatangan', 5, '{}')`, [u.id]);
    return u;
  };
  const STEPS = (await one('select game.sp_steps() s')).s;
  const LV = (await one('select game.sp_levels() l')).l;
  ok(STEPS.length === 15 && (await one('select game.sp_last() v')).v === 15, '15 langkah');
  ok((await one(`select game.side_quest_ids() v`)).v.join() === 'peregrin,duneks,jtq,surat', 'surat terdaftar sebagai side quest');
  ok((await one(`select value v from game.config where key = 'SuratOpen'`)).v === '1', 'SuratOpen bawaan terbuka');

  // ------------------------------------------------------------------ level: Urut Cap punya tepat satu urutan; server = solver
  const ANS = {};
  for (const k of ['l0', 'l7', 'l13']) {
    const L = LV[k];
    ok(SOL.countOrders(L) === 1, 'Urut Cap ' + k + ': tepat satu urutan sah (' + SOL.countOrders(L) + ')');
    ANS[k] = SOL.answer(L);
    ok(L.stamps.map(s => s.id).join() !== ANS[k].join(), 'Urut Cap ' + k + ': data tidak tersusun sebagai jawaban');
    ok((await one('select game.sp_check_cap($1, $2) e', [L, ANS[k]])).e === null, 'server menerima urutan solver: ' + k);
    const sw = ANS[k].slice(); [sw[0], sw[1]] = [sw[1], sw[0]];
    ok(/belum benar/.test((await one('select game.sp_check_cap($1, $2) e', [L, sw])).e), 'urutan salah ditolak: ' + k);
    ok((await one('select game.sp_check_cap($1, $2) e', [L, ANS[k].slice(1)])).e, 'urutan kurang ditolak: ' + k);
    ok((await one('select game.sp_check_cap($1, $2) e', [L, '"ok"'])).e, '"ok" ditolak: ' + k);
  }
  ok(ANS.l13[0] === 'jempol', 'cap paling bawah di Sunda = cap jempol');
  const rows = {}; LV.sensor.rows.forEach(r => { rows[r.id] = r; });
  ANS.sensor = LV.sensor.crates.filter(c => c.qty !== rows[c.row].qty || c.cap !== rows[c.row].cap || c.berat !== rows[c.row].berat).map(c => c.id);
  ok(ANS.sensor.length === 3 && ANS.sensor.includes('s9'), 'Daftar Sensor: 3 surat tidak cocok, termasuk suratmu');
  const answer = (d) => d.g === 'cap' || d.g === 'manifest' ? ANS[d.lv] : 'ok';

  // ------------------------------------------------------------------ gerbang
  const A = await mk('Kapten Surat', 'sp_a', 'merchant', false);
  await cfg('SuratOpen', '1');
  ok((await A.call('api_getGameState', [null])).surat === null, 'belum Saga 2: state null');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'duatangan', 5, '{}')`, [A.id]);
  await cfg('SuratOpen', '0');
  ok((await A.call('api_getGameState', [null])).surat === null, 'SuratOpen 0: state null');
  await cfg('FiturPenguji', 'sp_a');
  let s = await A.call('api_getGameState', [null]);
  ok(s.surat && s.surat.step === 0 && s.surat.done === false && s.surat.frozen === false, 'penguji: terbuka');
  ok(Object.keys(s.surat).sort().join() === 'done,frozen,lampiran,step', 'state tidak membocorkan perk/angka: ' + Object.keys(s.surat));
  await cfg('FiturPenguji', ''); await cfg('SuratOpen', '1');

  let r = await A.call('api_surat', ['level', 0]);
  ok(r.level && r.level.mode === 'cap' && r.level.stamps.length === 6, 'level langkah 0');
  await H.expectError(() => A.call('api_surat', ['level', 1]), /sepi/);
  await H.expectError(() => A.call('api_surat', ['bisikan']), /tidak dikenal/);   // perk belum bangun

  // ------------------------------------------------------------------ jalan 15 langkah
  await siang();
  await ke(A, 'karang_garam');
  await H.expectError(() => A.call('api_surat', ['maju', 0, ANS.l0]), /sepi/);
  await ke(A, 'sowtour');
  await H.expectError(() => A.call('api_surat', ['maju', 1, 'ok']), /bergeser/);
  await H.expectError(() => A.call('api_surat', ['maju', 0, 'ok']), /Belum benar/);
  r = await A.call('api_surat', ['maju', 0, ANS.l0]);
  ok(r.surat.step === 1, 'langkah 0 (Sowtour, Urut Cap)');
  await H.expectError(() => A.call('api_surat', ['maju', 0, ANS.l0]), /bergeser/);

  const logs0 = Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n);
  const chat0 = Number((await one(`select count(*) n from game.mp_chat`)).n);
  const run = async (u, i) => {
    const d = STEPS[i];
    await ke(u, d.c);
    if (d.t === 'malam') { await siang(); await H.expectError(() => u.call('api_surat', ['maju', i, answer(d)]), /lampu/); await malam(); }
    else await siang();
    if (d.g === 'tinta') await H.expectError(() => u.call('api_surat', ['maju', i, 'gagal']), /Belum terbaca/);
    if (d.g === 'manifest') await H.expectError(() => u.call('api_surat', ['maju', i, ANS[d.lv].slice(1)]), /Belum cocok/);
    if (d.barter) {
      await H.sql(`delete from game.inventory where player_id = $1 and item_id = 'rotan'`, [u.id]);
      await H.sql(`insert into game.warehouse(player_id, city_id, commodity_id, qty) values ($1, 'bjorneo', 'rotan', 5) on conflict do nothing`, [u.id]);
      await H.expectError(() => u.call('api_surat', ['maju', i, 'ok']), /palka/);
      await H.sql(`select game.adjust_inventory($1, 'rotan', 3)`, [u.id]);
    }
    return u.call('api_surat', ['maju', i, answer(d)]);
  };
  for (let i = 1; i < 14; i++) {
    r = await run(A, i);
    ok(r.surat.step === i + 1, 'langkah ' + i + ' maju');
  }
  ok(r.surat.lampiran.join() === 'kain,papan,tanah,gambar', 'empat lampiran: ' + r.surat.lampiran);
  ok(Number((await one(`select qty from game.inventory where player_id = $1 and item_id = 'rotan'`, [A.id])).qty) === 1, 'barter: 2 rotan dari palka');
  ok(Number((await one(`select coalesce(sum(qty),0) n from game.inventory i join game.item_catalog c on c.item_id = i.item_id where i.player_id = $1 and c.type = 'quest'`, [A.id])).n) === 0, 'lampiran tidak memakan palka');
  await H.expectError(() => A.call('api_surat', ['maju', 14, 'ok']), /balasanmu/);
  await H.expectError(() => A.call('api_surat', ['jawab', 14, 'C']), /balasanmu/);
  await siang();
  await H.expectError(() => A.call('api_surat', ['jawab', 14, 'A']), /lampu/);
  await malam();
  r = await A.call('api_surat', ['jawab', 14, 'B']);
  ok(r.surat.done === true && r.rak === 1, 'tamat; rak = 1 ' + JSON.stringify(r.rak));
  ok(r.surat.perk && r.surat.perk.arch === 'merchant' && r.surat.perk.varian === 'matang' && r.surat.perk.tingkat === 2, 'Merchant B = Matang');
  await H.expectError(() => A.call('api_surat', ['jawab', 14, 'A']), /sepi/);
  ok(Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n) === logs0, 'tidak ada log pemain');
  ok(!(await H.sql(`select msg from game.mp_chat order by id`)).slice(chat0).some(c => /surat|pustaka/i.test(JSON.stringify(c.msg))), 'tidak ada chat quest');
  ok((await H.sql(`select 1 from realtime.sent where payload::text ilike '%surat%'`)).length === 0, 'tidak ada Realtime quest');
  ok(!/surat/i.test(JSON.stringify((await one('select meta from game.players where player_id = $1', [A.id])).meta || {})), 'tidak ada Tanda Jasa khusus');

  // ------------------------------------------------------------------ side quest satu per satu (dua arah)
  const JS = require('./jtq-solver');
  const JL = (await one('select game.jt_levels() l')).l;
  const B = await mk('Kapten Antre', 'sp_b');
  await ke(B, 'marie_regal'); await siang();
  const kas = JL.l0.rounds.map(R => JS.kasAnswer(JL.l0.kinds, R));
  await B.call('api_jtq', ['maju', 0, kas]);
  ok((await B.call('api_getGameState', [null])).surat === null, 'Rekening J.T. berjalan: Surat Pulang tertahan');
  await ke(B, 'sowtour');
  await H.expectError(() => B.call('api_surat', ['maju', 0, ANS.l0]), /sepi/);
  const C = await mk('Kapten Pos', 'sp_c');
  await ke(C, 'sowtour');
  await C.call('api_surat', ['maju', 0, ANS.l0]);
  s = await C.call('api_getGameState', [null]);
  ok(s.jtq === null && s.duneks === null && s.peregrin === null, 'Surat Pulang berjalan: side quest lain tertahan');

  // ------------------------------------------------------------------ varian per archetype (Pirate tertukar)
  const V = [['merchant', 'A', 'lanjut'], ['navigator', 'B', 'matang'], ['pirate', 'A', 'matang'], ['pirate', 'B', 'lanjut'], ['adventurer', 'A', 'lanjut']];
  for (const [ar, jw, want] of V) ok((await one('select game.sp_varian($1, $2) v', [ar, jw])).v === want, 'varian ' + ar + ' ' + jw + ' = ' + want);
  ok((await one(`select game.sp_arch(null) a`)).a === 'adventurer', 'archetype kosong -> adventurer');

  // pemain perk siap pakai (langsung lewat alat GM)
  const perkUser = async (name, uname, arch, jawab) => {
    const u = await mk(name, uname, arch);
    await H.sql(`select game.admin_surat($1, 15, $2)`, [uname, jawab]);
    await siang();
    return u;
  };

  // ------------------------------------------------------------------ Merchant: Firasat Harga, Catatan Pasar, Bisikan
  await ke(A, 'joungjava'); await siang();
  let m = await A.call('api_getMarket', ['joungjava']);
  ok(m.perkTrend === true && m.items.every(x => ['up', 'down', 'flat'].includes(x.trend)), 'Merchant: arah harga di tiap barang');
  await A.call('api_setSail', ['sunda_empire']);
  await ke(A, 'sunda_empire');
  m = await A.call('api_getMarket', ['sunda_empire']);
  ok(m.perkCatatan && m.perkCatatan.length === 1 && m.perkCatatan[0].city === 'joungjava' && m.perkCatatan[0].items.length > 10, 'Merchant Matang: Catatan Pasar kota asal');
  const nonM = await mk('Kapten Biasa', 'sp_n');
  await ke(nonM, 'sunda_empire');
  m = await nonM.call('api_getMarket', ['sunda_empire']);
  ok(!('perkTrend' in m) && !m.items.some(x => 'trend' in x), 'tanpa perk: Market identik');
  r = await A.call('api_surat', ['bisikan']);
  const want = (await one(`select game.mkt_cycle_tags('sunda_empire', game.mkt_cycle_index() + 1) -> 'wanted' ->> 0 c`)).c;
  ok(r.bisikan && r.bisikan.commodityId === want, 'Bisikan Saudagar = Dicari siklus berikutnya');
  await H.expectError(() => A.call('api_surat', ['bisikan']), /tutup mulut/);    // Matang: Harian 1x

  // ------------------------------------------------------------------ Navigator: Jalur Pintas (Lanjut = 2x)
  const N = await perkUser('Kapten Arus', 'sp_nav', 'navigator', 'A');
  await ke(N, 'sunda_empire');
  const base = (await N.call('api_getSailOptions', [])).find(x => x.cityId === 'bjorneo').etaSeconds;
  r = await N.call('api_setSail', ['bjorneo', 'pintas']);
  ok(r.travelSeconds === Math.max(25, Math.round(base * 0.7)) && /Sea Reader/.test(r.perkNote), 'Jalur Pintas -30%: ' + base + ' -> ' + r.travelSeconds);
  await ke(N, 'sunda_empire');
  r = await N.call('api_setSail', ['bjorneo']);
  ok(r.travelSeconds === base && !r.perkNote, 'tanpa pintas: waktu normal');
  await ke(N, 'sunda_empire'); await N.call('api_setSail', ['bjorneo', 'pintas']);
  await ke(N, 'sunda_empire'); r = await N.call('api_setSail', ['bjorneo', 'pintas']);
  ok(r.travelSeconds === base, 'Lanjut: Jalur Pintas habis setelah 2x');

  // ------------------------------------------------------------------ Pirate: Nama yang Ditakuti, suap, Gertak, Rampas
  const P = await perkUser('Kapten Hitam', 'sp_pir', 'pirate', 'B');            // B = Lanjut (2x), Pasif level <= 2
  await cfg('PirateEncounterBaseChance', '60'); await cfg('PirateEncounterLevelMax', '1');
  let lewat = 0;
  for (let k = 0; k < 20; k++) { const e = (await one(`select game.voy_roll_encounter($1, 'bjorneo') e`, [P.id])).e; if (e === null) lewat++; }
  ok(lewat === 20, 'Nama yang Ditakuti: bajak laut level 1 tidak mencegat');
  await P.call('api_surat', ['takut', false]);
  let seen = 0;
  for (let k = 0; k < 20; k++) { const e = (await one(`select game.voy_roll_encounter($1, 'bjorneo') e`, [P.id])).e; if (e) seen++; }
  ok(seen > 0, 'sakelar mati: bajak laut kecil kembali mencegat');
  await P.call('api_surat', ['takut', true]);
  await cfg('PirateEncounterBaseChance', '12'); await cfg('PirateEncounterLevelMax', '5');
  const enc = (lvl, extra = {}) => Object.assign({ enemyLevel: lvl, enemyName: 'a notorious pirate frigate', enemyMaxHp: 140, enemyHp: 140, maxAmmo: 3, ammoRemaining: 3, randomPirate: true, round: 1, rolledAt: 'x' }, extra);
  const fight = (u, e) => H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = 'bjorneo', depart_at = now() - interval '1 hour', arrive_at = now() - interval '1 minute', pending_encounter = $2 where player_id = $1`, [u.id, JSON.stringify(e)]);
  await fight(P, enc(4)); await setGold(P, 100000);
  r = await P.call('api_resolveCombat', ['bribe']);
  ok(r.result === 'bribed' && await gold(P) === 100000 - Math.round(600 * 0.75) && /450 gold berpindah/.test(r.message), 'suap -25%: ' + r.message);
  await fight(P, enc(4)); await setGold(P, 500);
  r = await P.call('api_resolveCombat', ['bribe']);
  ok(r.result === 'bribed' && await gold(P) === 50, 'suap -25% lolos walau gold < harga penuh');
  await fight(P, enc(4, { boss: 'q' })); await setGold(P, 100000);
  await H.expectError(() => P.call('api_resolveCombat', ['gertak']), /tidak dikenali/);
  await fight(P, enc(4));
  r = await P.call('api_resolveCombat', ['gertak']);
  ok(r.result === 'fled' && r.ongoing === false && r.cityId === 'bjorneo' && await gold(P) === 100000, 'Gertak: lewat tanpa tempur & tanpa jarahan');
  await fight(P, enc(4));
  r = await P.call('api_resolveCombat', ['rampas']);
  ok(r.ongoing === true && r.encounter.rampas === true, 'Rampas: pertempuran ditandai');
  await H.expectError(() => P.call('api_resolveCombat', ['rampas']), /sudah siap/);
  await H.sql(`update game.player_location set pending_encounter = pending_encounter || '{"enemyHp": 1, "ammoRemaining": 3}' where player_id = $1`, [P.id]);
  await H.sql(`update game.character_stats set combat = 100 where player_id = $1`, [P.id]);
  for (let k = 0; k < 30; k++) {
    r = await P.call('api_resolveCombat', ['fire']);
    if (!r.ongoing) break;
    if (r.encounter.ammoRemaining <= 0) await P.call('api_resolveCombat', ['reload']);
  }
  ok(r.result === 'won' && r.rampas && r.rampas.qty >= 5 && r.rampas.qty <= 10, 'Rampas: menang -> barang biasa 5..10 ' + JSON.stringify(r.rampas));
  const rc = (await one(`select tier from game.commodities where id = $1`, [r.rampas.commodityId])).tier;
  ok(rc !== 'premium', 'rampasan bukan barang premium');
  await fight(P, enc(4));
  await H.expectError(() => P.call('api_resolveCombat', ['gertak']), /habis/);  // 2x terpakai (Gertak + Rampas)

  // ------------------------------------------------------------------ Explorer: peta harta & Firasat Karam
  const X = await perkUser('Kapten Peta', 'sp_exp', 'explorer', 'B');           // Matang: Peti Karam x1.5
  ok(Number((await one(`select game.fish_quest_weight($1, 'peti', 'sunda_empire') w`, [X.id])).w) === 1.5, 'Matang: Peti Karam x1.5');
  ok(Number((await one(`select game.fish_quest_weight($1, 'teri', 'sunda_empire') w`, [X.id])).w) === 1, 'ikan lain tidak tersentuh');
  await cfg('TreasureMapDropChance', '0');
  ok((await one(`select game.treasure_drop($1, 3) d`, [X.id])).d === null, 'peluang dasar 0 -> tetap 0');
  await cfg('TreasureMapDropChance', '15');
  let drops = 0, dropsN = 0;
  for (let k = 0; k < 300; k++) { if ((await one(`select game.treasure_drop($1, 3) d`, [X.id])).d) drops++; if ((await one(`select game.treasure_drop($1, 3) d`, [nonM.id])).d) dropsN++; }
  ok(drops > dropsN && drops > 40, 'Explorer: peta harta lebih sering (' + drops + ' vs ' + dropsN + ' / 300)');
  await ke(X, 'sunda_empire');
  let cast;
  for (let k = 0; k < 3; k++) {
    await H.sql(`update game.mp_fish set cooldown_until = 0 where player_id = $1`, [X.id]);
    cast = await X.call('api_mgFishCast', [0.9, 'cacing', false]);
    const f = (await one(`select fish from game.mp_fish where player_id = $1`, [X.id])).fish;
    ok(f === 'peti', 'Firasat Karam: lemparan dalam = Peti Karam (' + f + ')');
  }
  await H.sql(`update game.mp_fish set t0 = t0 - 200000 + 10000, wait_ms = 0, fight_ms = 0 where player_id = $1`, [X.id]);
  await H.sql(`update game.mp_fish set t0 = $2 where player_id = $1`, [X.id, Number((await one('select game.now_ms() v')).v) - 5000]);
  r = await X.call('api_mgFishReel', [cast.castId, 'caught', 1]);
  ok(r.caught && r.perkItem && /Treasure Hunter/.test(r.perkNote), 'Peti Karam pertama berisi peta harta');
  await H.sql(`update game.mp_fish set cooldown_until = 0 where player_id = $1`, [X.id]);
  await X.call('api_mgFishCast', [0.9, 'cacing', false]);
  ok((await one(`select current_setting('mt.perk_karam', true) v`)).v !== '1', 'GUC Firasat dibersihkan');

  // ------------------------------------------------------------------ Gambler: Taruhan Kedua
  const G = await perkUser('Kapten Dadu', 'sp_gam', 'gambler', 'B');            // Matang: Harian 1x, tukar +2
  await setGold(G, 100000);
  let refunds = 0;
  for (let k = 0; k < 25; k++) {
    r = await G.call('api_mgDice', [1000, 'besar']);
    if (r.refund) { refunds++; ok(r.refund === 1000, 'refund = taruhan'); }
  }
  ok(refunds === 1, 'Taruhan Kedua: tepat sekali per hari (Matang)');
  ok((await one('select game.perk_harian_max($1, $2) m', [G.id, 'tukar'])).m === 2, 'Matang: tukar Pesanan +2');

  // ------------------------------------------------------------------ Smuggler: gudang gratis, Kenalan Lama
  const S = await perkUser('Kapten Lorong', 'sp_smu', 'smuggler', 'A');
  await ke(S, 'bjorneo'); await setGold(S, 200000);
  await H.sql(`select game.adjust_inventory($1, 'beras', 20)`, [S.id]);
  r = await S.call('api_warehouseStore', ['bjorneo', 'beras', 20]);
  ok(Number(r.fee) === 0 && await gold(S) === 200000, 'gudang gratis (200 unit pertama)');
  await H.expectError(() => S.call('api_surat', ['kenalan', 'emas']), /Masih ada/);   // stok masih ada
  await H.sql(`update game.market set stock = 0, at = now(), cyc = game.mkt_cycle_index() where city_id = 'bjorneo' and commodity_id = 'emas'`);
  await H.expectError(() => S.call('api_surat', ['kenalan', 'beras']), /barang langka/);
  const unit = (await S.call('api_getMarket', ['bjorneo'])).items.find(x => x.commodityId === 'emas').buyPrice;
  r = await S.call('api_surat', ['kenalan', 'emas']);
  ok(r.kenalan.qty === 2 && r.kenalan.total === Math.ceil(2 * unit * 1.15), 'Kenalan Lama: 2 unit, harga +15% (' + r.kenalan.total + ' vs ' + unit + ')');
  ok(Number((await one(`select qty from game.inventory where player_id = $1 and item_id = 'emas'`, [S.id])).qty) === 2, 'emas masuk palka');
  const loan = await one(`select * from game.perk_pinjam where city_id = 'bjorneo' and commodity_id = 'emas'`);
  ok(loan && loan.qty === 2, 'pinjaman tercatat untuk siklus berikutnya');
  // siklus berikutnya: kiriman (batch) datang, lalu dipotong 2
  const cyc = Number((await one('select game.mkt_cycle_index() c')).c);
  await H.sql(`update game.market set cyc = $1 - 1 where city_id = 'bjorneo' and commodity_id = 'emas'`, [cyc]);
  await H.sql(`update game.perk_pinjam set cyc = $1 where city_id = 'bjorneo'`, [cyc]);
  const batch = Number((await one(`select ceil(ref * game.cfg_num('PremiumBatchFrac', 0.4)) b from game.commodities where id = 'emas'`)).b);
  const stk = Number((await one(`select game.mkt_lock('bjorneo', 'emas') s`)).s);
  ok(stk === Math.max(0, batch - 2), 'kiriman berikutnya berkurang 2: ' + stk + ' (batch ' + batch + ')');
  ok(!(await one(`select 1 x from game.perk_pinjam where city_id = 'bjorneo'`)), 'pinjaman lunas');

  // ------------------------------------------------------------------ Diplomat: tawaran tambahan, Surat Pengantar
  const D = await perkUser('Kapten Lidah', 'sp_dip', 'diplomat', 'A');
  const nB = (await one(`select jsonb_array_length(game.mission_board($1, 'sunda_empire') -> 'offers') n`, [nonM.id])).n;
  const nD = (await one(`select jsonb_array_length(game.mission_board($1, 'sunda_empire') -> 'offers') n`, [D.id])).n;
  ok(nD === nB + 1, 'Diplomat: +1 tawaran misi (' + nB + ' -> ' + nD + ')');
  ok((await one(`select jsonb_array_length(game.mission_tiers('sunda_empire')) n`)).n === nB, 'tier di luar papan tidak berubah');

  // ------------------------------------------------------------------ Adventurer: aus berkurang, Tambal di Laut
  const AD = await perkUser('Kapten Berani', 'sp_adv', 'adventurer', 'B');      // Matang: aus -35%
  const dN = Number((await one(`select game.voy_decay_for_voyage($1) d`, [nonM.id])).d);
  const dA2 = Number((await one(`select game.voy_decay_for_voyage($1) d`, [AD.id])).d);
  ok(Math.abs(dA2 - dN * 0.65) < 1e-6, 'aus lambung -35%: ' + dN + ' -> ' + dA2);
  await H.sql(`update game.ships set condition = 50 where player_id = $1`, [AD.id]);
  await H.sql(`update game.player_location set destination_city_id = 'joungjava', depart_at = now() - interval '1 hour', arrive_at = now() - interval '1 minute' where player_id = $1`, [AD.id]);
  r = await one(`select game.voy_finalize_arrival($1, 'joungjava', 'tiba') r`, [AD.id]);
  const c1 = Number((await one('select condition c from game.ships where player_id = $1', [AD.id])).c);
  ok(/Bold Sailor/.test(r.r.perkNote) && c1 >= 67 && c1 <= 70, 'Tambal di Laut +20% kondisi: ' + c1);
  await H.sql(`update game.player_location set destination_city_id = 'sunda_empire', depart_at = now() - interval '1 hour', arrive_at = now() - interval '1 minute' where player_id = $1`, [AD.id]);
  r = await one(`select game.voy_finalize_arrival($1, 'sunda_empire', 'tiba') r`, [AD.id]);
  ok(!r.r.perkNote, 'Matang: Tambal hanya sekali per hari');

  // ------------------------------------------------------------------ Saga 3: quest beku, perk tidur
  await cfg('PasirOpen', '1');
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);
  let fz = await one(`select game.sp_frozen($1) f, game.perk($1) p`, [AD.id]);
  ok(fz.f === true && fz.p === null, 'Saga 3 aktif: perk tidur');
  ok((await AD.call('api_getGameState', [null])).surat.perk === null, 'state: perk null selama Saga 3');
  await H.expectError(() => C.call('api_surat', ['maju', 1, 'ok']), /sepi/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'ps14', 6) on conflict (player_id, quest_id) do update set step = 6`, [AD.id]);
  fz = await one(`select game.sp_frozen($1) f, game.perk($1) p`, [AD.id]);
  ok(fz.f === false && fz.p && fz.p.arch === 'adventurer', 'Saga 3 tamat: perk bangun lagi');
  await H.sql(`delete from game.world_flags where key = 'saga3'`);
  await cfg('PasirOpen', '0');

  // ------------------------------------------------------------------ alat GM
  const st2 = await one(`select game.admin_surat('sp_c', 7) s`);
  ok(st2.s.step === 7 && st2.s.lampiran.join() === 'kain,papan,tanah', 'admin_surat menyetel langkah & lampiran');

  console.log('SURAT PULANG TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
