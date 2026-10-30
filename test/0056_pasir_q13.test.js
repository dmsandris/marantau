// Tide v41 · Pasir Batch 6 — Quest 13 "Laksamana yang Tak Pernah Tenggelam".
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const A = await H.user('q13a_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [pid]);
  await H.sql(`select game.pasir_ensure($1)`, [pid]);
  await H.sql(`select game.pv_ambil($1, 'sunda_empire')`, [pid]);
  await H.sql(`update game.pasir_state set data = data || '{"buka": ["empeer_depeer"], "sudyrman": true, "barang": ["sabun_gala"]}'::jsonb, kaca = 3, era = 'keadilan' where player_id = $1`, [pid]);
  await H.sql(`select game.ps_set($1, 'ps10', 11, '{}'::jsonb, true), game.ps_set($1, 'ps11', 10, '{}'::jsonb, true), game.ps_set($1, 'ps12', 7, '{}'::jsonb, true)`, [pid]);
  await H.sql(`insert into game.pv_pusaka(player_id, pusaka_id, mutu, slot) values ($1, 'jangkar', 'kasar', 1)`, [pid]);
  await H.sql(`update game.players set gold = 500000 where player_id = $1`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const era = (e) => H.sql(`update game.pasir_state set era = $2 where player_id = $1`, [pid, e]);
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const arrive = async (c) => { await place(c); await H.sql(`select game.ps_on_arrive($1, $2)`, [pid, c]); };
  const sailFight = async (dest) => {
    await A.call('api_setSail', [dest]); await H.shiftTime(900000);
    await A.call('api_pollVoyage', []);
    const pend = await one('select pending_encounter e from game.player_location where player_id = $1', [pid]);
    if (!pend.e) return { none: true };
    const enc = pend.e; let res = null, guard = 0;
    while (guard++ < 120) {
      await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);
      const e = (await one('select pending_encounter e from game.player_location where player_id = $1', [pid])).e;
      if (!e) break;
      const r = await A.call('api_resolveCombat', [Number(e.ammoRemaining) > 0 ? 'fire' : 'reload']);
      if (!r.ongoing) { res = r; break; }
    }
    return { enc, res };
  };
  await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);

  // --- Babak 1: undangan ---
  await place('ikn');
  let s = await gs();
  ok(s.pasir.q13 && s.pasir.q13.step === 1 && s.pasir.q13.rep === 0, 'Quest 13 dimulai di Zaman Keadilan');
  await H.expectError(() => act('undangan13'), /belum cukup dikenal/);
  await act('palsu13', 'gagal');
  await H.expectError(() => act('palsu13', 'ok'), /besok/);
  ok((await gs()).pasir.q13.palsuBesok === true, 'diusir sampai besok');
  for (const c of ['ikn', 'bjorneo', 'skitraw']) {
    await H.sql(`insert into game.player_missions(player_id, status, city_id, commodity_id, qty, reward) values ($1, 'completed', $2, 'beras', 10, 100)`, [pid, c]);
  }
  ok((await gs()).pasir.q13.rep === 3, 'tiga pulau mengenalmu');
  await act('undangan13');
  ok((await gs()).pasir.q13.step === 2, 'undangan di tangan');

  // --- Babak 2: Pesta Keadilan ---
  await place('skitraw');
  await H.expectError(() => act('pesta13'), /IKN/);
  await place('ikn');
  await act('pesta13');
  s = await gs();
  ok(s.pasir.q13.step === 3 && s.pasir.q13.d.surat2, 'Surat Franzi #2');

  // --- Babak 3: Uda Gala ---
  await H.expectError(() => act('gasing13', 'ok'), /Aksi tidak dikenal/);
  await place('skitraw');
  await act('gala13');
  await H.expectError(() => act('galapilih13', 'sabun'), /Aksi tidak dikenal/);
  await act('gasing13', 'ok');
  await act('galapilih13', 'sabun');
  s = await gs();
  ok(s.pasir.riak.gala_putih === 'belot' && !s.pasir.barang.includes('sabun_gala'), 'Gala membelot');
  ok(s.pasir.q13.step === 4 && s.pasir.tuju13.kota === 'sudyrman_lembah' && s.pasir.tuju13.era === 'lampau', 'tujuan pertama: Lembah Seribu Layar');
  ok(!JSON.stringify(s).includes('fzGm'), 'lokasi tidak bocor ke pemain biasa');

  // --- Babak 4: tiga penyusulan lintas zaman ---
  const susul = async (city, e, other, label) => {
    await era(e);
    await arrive(city);
    s = await gs();
    ok(s.pasir.kejar && s.pasir.kejar.susul === 'ada', label + ': tersusul di ' + city);
    await act('pesta_fz');
    let f = await sailFight(other), guard = 0;
    ok(f.enc && f.enc.boss === 'ps_janji' && f.enc.q13, label + ': Janji Putih (Q13) mencegat');
    while ((!f.res || f.res.result !== 'won') && guard++ < 6) {
      await H.sql(`select game.admin_pasir('q13a_ana', 'harian')`);
      await arrive(city); await act('pesta_fz'); f = await sailFight(other);
    }
    ok(f.res && f.res.result === 'won', label + ': menang');
    return f;
  };
  // salah zaman: tidak tersusul
  await era('keadilan');
  await arrive('bjorneo');
  ok((await gs()).pasir.kejar.susul !== 'ada', 'zaman salah: tidak ada');
  let f = await susul('sudyrman_lembah', 'lampau', 'sudyrman_pelabuhan', 'Lembah');
  ok(f.enc.perisai === true && Number(f.enc.dmgTaken) < 1, 'perisai pasir (Jangkar kasar)');
  s = await gs();
  ok(s.pasir.q13.d.n === 1 && s.pasir.q13.d.surat3 && s.pasir.kaca === 4, 'Surat #3, kaca 4');
  ok(s.pasir.kejar.besok === true, 'batas harian');
  await arrive('sudyrman_lembah');
  await era('keadilan'); await arrive('bjorneo');
  ok((await gs()).pasir.kejar.susul !== 'ada', 'besok baru tersusul lagi');
  await H.sql(`select game.admin_pasir('q13a_ana', 'harian')`);
  await H.sql(`update game.pv_pusaka set mutu = 'baik' where player_id = $1 and pusaka_id = 'jangkar'`, [pid]);
  f = await susul('bjorneo', 'keadilan', 'skitraw', 'Bjorneo');
  ok(f.enc.perisai === false && Number(f.enc.dmgTaken) === 1, 'Jangkar Baik menembus perisai');
  ok((await gs()).pasir.kaca === 5, 'kaca 5');
  await H.sql(`select game.admin_pasir('q13a_ana', 'harian')`);
  f = await susul('sudyrman_akademi', 'lampau', 'sudyrman_pelabuhan', 'Akademi');
  s = await gs();
  ok(s.pasir.q13.step === 5 && s.pasir.q13.d.surat5 && s.pasir.kaca === 6 && s.pasir.kejar === null, 'tiga penyusulan: langkah 5, kaca 6');

  // --- Babak 5: arsip ---
  await place('sudyrman_pelabuhan');
  await H.expectError(() => act('arsip13'), /Akademi/);
  await place('sudyrman_akademi');
  await act('arsip13');
  ok((await gs()).pasir.q13.step === 6, 'twist tujuh kaca');

  // --- Babak 6: Malam Pasang Besar (evakuasi) ---
  await place('sudyrman_akademi');
  await H.expectError(() => act('tebing13'), /belum tiba/);
  await place('sudyrman_pelabuhan');
  await act('pasang13', 'evakuasi');
  await H.expectError(() => act('angkut13'), /Beras/);
  await H.sql(`select game.adjust_inventory($1, 'beras', 300)`, [pid]);
  const rt0 = (await gs()).pasir.retak;
  for (let i = 0; i < 3; i++) {
    await place('sudyrman_pelabuhan');
    await act('angkut13');
    await H.expectError(() => act('angkut13'), /sudah penuh/);
    await arrive('joungjava');
  }
  s = await gs();
  ok(s.pasir.q13.d.evak === 3 && s.pasir.retak === Math.min(100, rt0 + 30), 'tiga pelayaran evakuasi, Retak +30');
  ok((await one(`select game.item_qty($1, 'beras') q`, [pid])).q === 0, '300 Beras terpakai');
  await place('sudyrman_akademi');
  const g0 = await gold();
  await act('tebing13');
  s = await gs();
  ok(s.pasir.q13.step === 7 && s.pasir.q13.done && s.pasir.riak.sudyrman === 'evakuasi', 'Quest 13 selesai (evakuasi)');
  ok(await gold() === g0 + 180000, 'hadiah 180.000');

  // --- Cabang lain: cerita & tonton ---
  const B = await H.user('q13b_budi');
  await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  const pb = B.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [pb]);
  await H.sql(`select game.pasir_ensure($1)`, [pb]);
  await H.sql(`update game.pasir_state set data = data || '{"sudyrman": true}'::jsonb, era = 'keadilan' where player_id = $1`, [pb]);
  await H.sql(`select game.ps_set($1, 'ps12', 7, '{}'::jsonb, true), game.ps_set($1, 'ps13', 3, '{"temu": true, "gasing": true}'::jsonb)`, [pb]);
  await H.sql(`update game.player_location set city_id = 'skitraw' where player_id = $1`, [pb]);
  await H.expectError(() => B.call('api_pasir', ['galapilih13', 'sabun']), /tidak membawa/);
  await B.call('api_pasir', ['galapilih13', 'cerita']);
  let sb = await B.call('api_getGameState', []);
  ok(sb.pasir.riak.gala_putih === 'peta' && sb.pasir.barang.includes('peta_armada'), 'Peta Rute Armada Putih');
  await H.sql(`select game.ps_set($1, 'ps13', 6, '{}'::jsonb)`, [pb]);
  await H.sql(`update game.pasir_state set era = 'lampau' where player_id = $1`, [pb]);
  await H.sql(`update game.player_location set city_id = 'sudyrman_pelabuhan' where player_id = $1`, [pb]);
  await B.call('api_pasir', ['pasang13', 'tonton']);
  await H.expectError(() => B.call('api_pasir', ['angkut13']), /Aksi tidak dikenal/);
  await H.sql(`update game.player_location set city_id = 'sudyrman_akademi' where player_id = $1`, [pb]);
  await B.call('api_pasir', ['tebing13']);
  sb = await B.call('api_getGameState', []);
  ok(sb.pasir.q13.done && sb.pasir.riak.sudyrman === 'tonton', 'cabang tonton');

  // Pemain biasa: tanpa Janji Putih
  const C = await H.user('q13c_cici');
  await C.call('api_createCharacter', ['Kapten Cici', 'merchant']);
  ok((await one(`select game.quest_boss_encounter($1, 'ikn') e`, [C.id])).e === null, 'pemain biasa: tanpa Janji Putih');
  ok((await C.call('api_getGameState', [])).pasir === undefined, 'pemain biasa: tanpa key pasir');

  console.log('0056 pasir q13: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
