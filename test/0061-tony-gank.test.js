// Tide v45 · Bajak laut "Tony and Gank": event GM terjadwal, armada HP 4.000, hanya Lawan / Menyerah.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const now = Date.now(), H1 = 3600000;
  const gold = async (id) => Number((await H.sql('select gold from game.players where player_id = $1', [id]))[0].gold);
  const cargo = async (id) => (await H.sql('select coalesce(sum(qty),0)::int n from game.inventory where player_id = $1', [id]))[0].n;
  const loc = async (id) => (await H.sql('select * from game.player_location where player_id = $1', [id]))[0];
  const cond = async (id) => Number((await H.sql('select condition from game.ships where player_id = $1', [id]))[0].condition);
  const maxc = async (id) => Number((await H.sql('select game.voy_max_cond($1) m', [id]))[0].m);
  // bajak laut acak dibuat sesedikit mungkin supaya tes "tidak kena Tony" stabil
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  const tiba = async (u, from, to) => {
    await H.sql(`update game.player_location set city_id = $2, destination_city_id = $3, depart_at = now() - interval '2 minutes',
                 arrive_at = now() - interval '1 second', pending_encounter = null where player_id = $1`, [u.id, from, to]);
    return (await u.call('api_pollVoyage', [])).voyage;
  };
  const isTony = (v) => !!(v && v.encounterPending && v.encounter && v.encounter.kind === 'tony');

  // ---- GM ----
  const gm = await H.user('abuy'); await gm.call('api_createCharacter', ['Abuy GM', 'merchant']);
  const biasa = await H.user('kapten1'); await biasa.call('api_createCharacter', ['Kapten Satu', 'navigator']);
  await H.expectError(() => biasa.call('api_gmTony', ['add', { dest: 'toogood', startAt: now, endAt: now + H1 }]), /khusus GM/);
  await H.expectError(() => gm.call('api_gmTony', ['add', { dest: 'toogood', startAt: now + H1, endAt: now }]), /setelah jam mulai/);
  await H.expectError(() => gm.call('api_gmTony', ['add', { dest: 'toogood', startAt: now, endAt: now + 25 * H1 }]), /24 jam/);
  await H.expectError(() => gm.call('api_gmTony', ['add', { dest: 'titik_buta', startAt: now, endAt: now + H1 }]), /Titik laut/);
  let L = await gm.call('api_gmTony', ['add', { dest: 'toogood', startAt: now, endAt: now + 2 * H1, chance: 100, kabar: 'umum' }]);
  const raid = L.raids[0];
  assert(raid.status === 'aktif' && raid.chance === 100 && raid.goldPct === 60, 'event terpasang: ' + JSON.stringify(raid));
  assert(L.cities.some(c => c.id === 'toogood') && !L.cities.some(c => c.id === 'titik_buta'), 'daftar kota GM');
  // mode umum: pengumuman sekali
  let ann = await H.sql(`select count(*)::int n from game.gm_announce where by_user = 'Kabar Laut' and until > now()`);
  assert(ann[0].n === 1, 'pengumuman umum terkirim');
  await gm.call('api_gmTony', ['list']);
  ann = await H.sql(`select count(*)::int n from game.gm_announce where by_user = 'Kabar Laut'`);
  assert(ann[0].n === 1, 'pengumuman tidak dobel');

  // ---- state klien: kabut + bisikan ----
  let s = await biasa.call('api_getGameState', [null]);
  assert(s.tony && s.tony.fog.length === 1 && s.tony.fog[0].city === 'toogood' && s.tony.rumors.length === 1, 'state tony: ' + JSON.stringify(s.tony));
  assert(!/TooGood/i.test(s.tony.rumors[0]), 'bisikan tidak menyebut nama kota');

  // ---- pemain baru (Jejak Perantau) tetap kena; serah dari kartu ----
  const baru = await H.user('kaptenbaru'); await baru.call('api_createCharacter', ['Kapten Baru', 'navigator']);
  assert((await baru.call('api_getGameState', [null])).perantau, 'pemain baru memang pemain Jejak Perantau');
  await H.sql(`update game.players set gold = 10000 where player_id = $1`, [baru.id]);
  await baru.call('api_buy', ['sunda_empire', 'sugar', 3]);
  await H.sql(`insert into game.bank_accounts(player_id, balance) values ($1, 5000) on conflict (player_id) do update set balance = 5000`, [baru.id]).catch(() => { });
  const bankBefore = JSON.stringify((await baru.call('api_getGameState', [null])).bank);
  const g0 = await gold(baru.id); assert((await cargo(baru.id)) === 3, 'punya muatan');
  let v = await tiba(baru, 'sunda_empire', 'toogood');
  assert(isTony(v), 'pemain baru dikepung Tony');
  assert(v.encounter.enemyMaxHp === 4000 && v.encounter.ships.length === 4, 'armada 4 kapal HP 4000');
  // taktik terlarang
  await H.expectError(() => baru.call('api_resolveCombat', ['flee']), /Empat arah/);
  await H.expectError(() => baru.call('api_resolveCombat', ['bribe']), /Suap/);
  await H.expectError(() => baru.call('api_resolveCombat', ['negotiate']), /Suap/);
  await H.expectError(() => baru.call('api_resolveCombat', ['ram']), /empat kapal/);
  const c0 = await cond(baru.id);
  let r = await baru.call('api_tonyRaid', ['serah']);
  assert(r.result === 'robbed' && r.how === 'serah', 'menyerah dirampas');
  assert((await gold(baru.id)) === g0 - Math.floor(g0 * 0.6), 'gold tinggal 40% (' + (await gold(baru.id)) + ')');
  assert((await cargo(baru.id)) === 0 && r.rob.cargo.length === 1 && r.rob.cargo[0].qty === 3, 'palka kosong, rampasan tercatat');
  assert((await loc(baru.id)).city_id === 'toogood', 'tetap tiba di tujuan');
  assert((await cond(baru.id)) <= c0, 'kondisi tidak naik');
  assert(JSON.stringify((await baru.call('api_getGameState', [null])).bank) === bankBefore, 'bank utuh');

  // ---- kena berulang ----
  const gA = await gold(baru.id);
  v = await tiba(baru, 'sunda_empire', 'toogood');
  assert(isTony(v), 'kena lagi di pelayaran berikutnya');
  await baru.call('api_tonyRaid', ['serah']);
  assert((await gold(baru.id)) === gA - Math.floor(gA * 0.6), 'kena berulang: 60% dari sisa');

  // ---- rute lain / asal lain / di luar jam -> aman ----
  v = await tiba(baru, 'sunda_empire', 'joungjava');
  assert(!isTony(v), 'rute lain aman');
  const id2 = (await gm.call('api_gmTony', ['add', { dest: 'skitraw', origin: 'bjorneo', startAt: now, endAt: now + H1, chance: 100, kabar: 'diam' }])).raids[0].id;
  v = await tiba(baru, 'sunda_empire', 'skitraw'); assert(!isTony(v), 'asal berbeda aman');
  v = await tiba(baru, 'bjorneo', 'skitraw'); assert(isTony(v), 'asal cocok kena'); await baru.call('api_tonyRaid', ['serah']);
  await H.sql(`update game.tony_raid set start_at = now() + interval '1 hour', end_at = now() + interval '2 hours' where id = $1`, [id2]);
  v = await tiba(baru, 'bjorneo', 'skitraw'); assert(!isTony(v), 'di luar jam aman');
  // mode diam tidak bocor ke state (event skitraw diam, toogood umum)
  s = await baru.call('api_getGameState', [null]);
  assert(s.tony.fog.every(f => f.city !== 'skitraw') && s.tony.rumors.length === 1, 'mode diam tidak bocor');

  // ---- peluang 80% (statistik) ----
  await H.sql(`update game.tony_raid set chance = 80 where id = $1`, [raid.id]);
  const st = await H.user('statistik'); await st.call('api_createCharacter', ['Kapten Statistik', 'merchant']);
  let kena = 0;
  for (let i = 0; i < 120; i++) { v = await tiba(st, 'sunda_empire', 'toogood'); if (isTony(v)) { kena++; await st.call('api_tonyRaid', ['serah']); } }
  assert(kena >= 80 && kena <= 110, 'peluang 80%: ' + kena + '/120');
  await H.sql(`update game.tony_raid set chance = 100 where id = $1`, [raid.id]);

  // ---- Lawan sampai kalah: tidak tenggelam, kondisi 10%, dirampas, tiba di tujuan ----
  await H.sql(`update game.config set value = '0' where key = 'TonyPowderChance'`);
  const lw = await H.user('pelawan'); await lw.call('api_createCharacter', ['Kapten Pelawan', 'pirate']);
  await H.sql(`update game.players set gold = 50000 where player_id = $1`, [lw.id]);
  await lw.call('api_buy', ['sunda_empire', 'sugar', 2]);
  // Pengawal Kedai: jatah tidak terpotong
  await H.sql(`insert into game.kd_buffs(player_id, kind, uses_left) values ($1, 'pengawal', 2)`, [lw.id]);
  v = await tiba(lw, 'sunda_empire', 'toogood'); assert(isTony(v), 'pelawan dikepung');
  assert(!v.encounter.allyDmg, 'Pengawal tidak ikut');
  assert((await H.sql(`select uses_left from game.kd_buffs where player_id = $1 and kind = 'pengawal'`, [lw.id]))[0].uses_left === 2, 'jatah Pengawal utuh');
  const gL = await gold(lw.id);
  let rounds = 0, ammoLeft = v.encounter.ammoRemaining;
  do {
    const act = ammoLeft > 0 ? 'fire' : 'reload';
    r = await lw.call('api_resolveCombat', [act]);   // jalur combat biasa diarahkan ke Tony
    rounds++;
    if (r.ongoing) {
      assert(r.conditionDelta < 0, 'balasan pasti kena tiap ronde (' + act + ')');
      assert(r.encounter.enemyHp >= 1, 'HP armada tidak habis lewat tembakan biasa');
      ammoLeft = r.encounter.ammoRemaining;
    }
  } while (r.ongoing && rounds < 40);
  assert(!r.ongoing && r.result === 'robbed' && r.how === 'kalah', 'kalah: ' + JSON.stringify(r).slice(0, 200));
  assert(rounds >= 4 && rounds <= 12, 'kapal bertahan ±6-8 ronde (' + rounds + ')');
  const mL = await maxc(lw.id);
  assert(Math.abs((await cond(lw.id)) - Math.round(mL * 0.1)) <= 1, 'kondisi 10% maks (' + (await cond(lw.id)) + '/' + mL + ')');
  assert((await gold(lw.id)) === gL - Math.floor(gL * 0.6) && (await cargo(lw.id)) === 0, 'dirampas setelah kalah');
  assert((await loc(lw.id)).city_id === 'toogood' && !(await loc(lw.id)).destination_city_id, 'tiba di tujuan, bukan asal');
  const vic = (await H.sql(`select * from game.tony_victims where player_id = $1 order by id desc limit 1`, [lw.id]))[0];
  assert(vic.result === 'kalah' && vic.rounds === rounds, 'korban tercatat dengan ronde');

  // ---- menyerah di tengah pertempuran: kerusakan tetap ----
  await H.sql(`update game.ships set condition = game.voy_max_cond(player_id) where player_id = $1`, [lw.id]);
  v = await tiba(lw, 'sunda_empire', 'toogood');
  r = await lw.call('api_tonyRaid', ['fire']); assert(r.ongoing, 'ronde 1 berjalan');
  const cMid = await cond(lw.id);
  r = await lw.call('api_tonyRaid', ['serah']);
  assert(r.result === 'robbed' && (await cond(lw.id)) <= cMid && cMid < (await maxc(lw.id)), 'menyerah di tengah: kerusakan tetap (tidak dipulihkan)');

  // ---- menang lewat gudang mesiu ----
  await H.sql(`update game.config set value = '100' where key = 'TonyPowderChance'`);
  const mn = await H.user('pemenang'); await mn.call('api_createCharacter', ['Kapten Mujur', 'pirate']);
  await H.sql(`update game.players set gold = 1000 where player_id = $1`, [mn.id]);
  await mn.call('api_buy', ['sunda_empire', 'sugar', 2]);
  await H.sql(`update game.character_stats set combat = 100 where player_id = $1`, [mn.id]).catch(() => { });
  await H.sql(`update game.config set value = '-10' where key = 'TonyLevel'`);   // peluang kena maksimum supaya tes stabil
  v = await tiba(mn, 'sunda_empire', 'toogood'); assert(isTony(v), 'pemenang dikepung');
  await H.sql(`update game.config set value = '8' where key = 'TonyLevel'`);
  const gM = await gold(mn.id);
  for (let i = 0; i < 30; i++) {
    r = await mn.call('api_tonyRaid', [i % 3 === 2 ? 'reload' : 'fire']);
    if (!r.ongoing) break;
  }
  assert(r.result === 'won' && r.how === 'mesiu', 'menang lewat gudang mesiu: ' + JSON.stringify(r).slice(0, 200));
  assert((await gold(mn.id)) === gM + 25000 && (await cargo(mn.id)) === 2, 'menang: +25.000, muatan utuh');
  const chat = await H.sql(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`);
  assert(/Kapten Mujur meledakkan gudang mesiu/.test(chat[0].msg.tx), 'siaran pemenang');
  v = await tiba(mn, 'sunda_empire', 'toogood'); assert(!isTony(v), 'pemenang kebal di event yang sama');

  // siaran korban: nama karakter, tanpa jumlah gold
  const korban = (await H.sql(`select msg from game.mp_chat where channel = 'g' and msg ->> 'tx' like '%Kapten Pelawan%'`))[0];
  assert(korban && !/abuy|pelawan@|\d{3,}/.test(korban.msg.tx), 'siaran korban: ' + (korban && korban.msg.tx));

  // ---- bos quest didahulukan ----
  await H.sql(`create or replace function game.tony_test_boss() returns void language plpgsql as $f$ begin end $f$`);
  const qb = await H.user('questbos'); await qb.call('api_createCharacter', ['Kapten Quest', 'merchant']);
  await H.sql(`alter function game.quest_boss_encounter(uuid, text) rename to quest_boss_encounter_asli`);
  await H.sql(`create function game.quest_boss_encounter(p uuid, d text) returns jsonb language sql as $f$
    select case when d = 'toogood' then jsonb_build_object('enemyLevel', 3, 'enemyName', 'Bos Uji', 'enemyMaxHp', 100, 'enemyHp', 100,
      'maxAmmo', 3, 'ammoRemaining', 3, 'boss', 'uji', 'round', 1) end $f$`);
  v = await tiba(qb, 'sunda_empire', 'toogood');
  assert(v.encounterPending && v.encounter.boss === 'uji', 'bos quest menang atas Tony');
  await H.sql(`drop function game.quest_boss_encounter(uuid, text)`);
  await H.sql(`alter function game.quest_boss_encounter_asli(uuid, text) rename to quest_boss_encounter`);

  // ---- era lampau Saga 3: tidak kena ----
  const ps = await H.user('penjelajahwaktu'); await ps.call('api_createCharacter', ['Kapten Waktu', 'merchant']);
  await H.sql(`alter function game.pasir_era(uuid) rename to pasir_era_asli`);
  await H.sql(`create function game.pasir_era(p uuid) returns text language sql as $f$ select 'lampau'::text $f$`);
  v = await tiba(ps, 'sunda_empire', 'toogood'); assert(!isTony(v), 'era lampau aman');
  assert((await H.sql(`select game.tony_state($1) s`, [ps.id]))[0].s === null, 'era lampau: tanpa bisikan & kabut');
  await H.sql(`drop function game.pasir_era(uuid)`);
  await H.sql(`alter function game.pasir_era_asli(uuid) rename to pasir_era`);

  // ---- menyerah otomatis setelah 10 menit ----
  const au = await H.user('pergi'); await au.call('api_createCharacter', ['Kapten Pergi', 'merchant']);
  await H.sql(`update game.players set gold = 1000 where player_id = $1`, [au.id]);
  v = await tiba(au, 'sunda_empire', 'toogood'); assert(isTony(v), 'pergi dikepung');
  await au.call('api_pollVoyage', []);
  assert((await loc(au.id)).destination_city_id === 'toogood', 'belum otomatis sebelum 10 menit');
  await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{lastAt}', to_jsonb(game.now_ms() - 11 * 60000)) where player_id = $1`, [au.id]);
  v = (await au.call('api_pollVoyage', [])).voyage;
  assert(!v.inTransit && (await gold(au.id)) === 400, 'menyerah otomatis');
  assert((await H.sql(`select result from game.tony_victims where player_id = $1`, [au.id]))[0].result === 'auto', 'tercatat auto');

  // ---- tumpang tindih: peluang tertinggi ----
  await H.sql(`update game.tony_raid set chance = 1 where id = $1`, [raid.id]);
  await gm.call('api_gmTony', ['add', { dest: 'toogood', startAt: now, endAt: now + H1, chance: 100, kabar: 'diam' }]);
  v = await tiba(baru, 'sunda_empire', 'toogood'); assert(isTony(v), 'tumpang tindih memakai peluang tertinggi');
  await baru.call('api_tonyRaid', ['serah']);

  // ---- batalkan: aman, kabut & pengumuman hilang ----
  L = await gm.call('api_gmTony', ['list']);
  for (const x of L.raids.filter(x => x.status === 'aktif' || x.status === 'terjadwal')) await gm.call('api_gmTony', ['cancel', { id: x.id }]);
  v = await tiba(baru, 'sunda_empire', 'toogood'); assert(!isTony(v), 'setelah batal aman');
  s = await baru.call('api_getGameState', [null]);
  assert(s.tony === null, 'state tony kosong setelah batal');
  ann = await H.sql(`select count(*)::int n from game.gm_announce where by_user = 'Kabar Laut' and until > now()`);
  assert(ann[0].n === 0, 'pengumuman ditutup');
  L = await gm.call('api_gmTony', ['list']);
  const lap = L.raids.find(x => x.id === raid.id);
  assert(lap.status === 'batal' && lap.korban >= 5 && lap.menang === 1 && lap.gold > 0 && lap.rolls >= lap.hits, 'laporan GM: ' + JSON.stringify(lap));

  // ---- pertempuran biasa tetap jalan lewat pembungkus ----
  await H.sql(`update game.config set value = '100' where key = 'PirateEncounterBaseChance'`);
  await H.sql(`update game.config set value = '100' where key = 'PirateEncounterBaseChance'`);
  const nb = await H.user('normal'); await nb.call('api_createCharacter', ['Kapten Normal', 'merchant']);
  await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = 'joungjava', depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second', pending_encounter = jsonb_build_object('enemyLevel', 1, 'enemyName', 'uji', 'enemyMaxHp', 50, 'enemyHp', 50, 'maxAmmo', 3, 'ammoRemaining', 3, 'round', 1, 'randomPirate', true) where player_id = $1`, [nb.id]);
  r = await nb.call('api_resolveCombat', ['fire']);
  assert(typeof r.ongoing === 'boolean' && !r.tony, 'combat biasa tetap lewat api_resolveCombat asli');

  console.log('TONY AND GANK TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
