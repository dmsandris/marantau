// Tide v41 · Pasir Batch 5 — mesin pengejaran Franziska + Quest 12 "Kota yang Lampunya Sampai ke Laut".
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const A = await H.user('q12a_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [pid]);
  await H.sql(`select game.pasir_ensure($1)`, [pid]);
  await H.sql(`select game.pv_ambil($1, 'sunda_empire')`, [pid]);
  await H.sql(`update game.pasir_state set data = data || '{"buka": ["empeer_depeer"]}'::jsonb, kaca = 2 where player_id = $1`, [pid]);
  await H.sql(`select game.ps_set($1, 'ps10', 11, '{}'::jsonb, true), game.ps_set($1, 'ps11', 10, '{}'::jsonb, true)`, [pid]);
  await H.sql(`insert into game.pv_pusaka(player_id, pusaka_id, mutu, slot) values ($1, 'jangkar', 'baik', 1)`, [pid]);
  await H.sql(`update game.players set gold = 500000 where player_id = $1`, [pid]);
  await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const arrive = async (c) => { await place(c); await H.sql(`select game.ps_on_arrive($1, $2)`, [pid, c]); };
  const fz = async (d) => (await one(`select game.ps_fz_port($1, game.ps_slot() + $2) p`, [pid, d || 0])).p;
  // berlayar lalu bertempur sampai selesai (kapal diperbaiki di sela-sela supaya tidak karam)
  const sailFight = async (dest) => {
    await A.call('api_setSail', [dest]); await H.shiftTime(900000);
    let pv = await A.call('api_pollVoyage', []), res = null, guard = 0;
    const pend = await one('select pending_encounter e from game.player_location where player_id = $1', [pid]);
    if (!pend.e) return { none: true };
    const boss = pend.e.boss;
    while (guard++ < 80) {
      await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);
      const e = (await one('select pending_encounter e from game.player_location where player_id = $1', [pid])).e;
      if (!e) break;
      const r = await A.call('api_resolveCombat', [Number(e.ammoRemaining) > 0 ? 'fire' : 'reload']);
      if (!r.ongoing) { res = r; break; }
    }
    return { boss, res };
  };

  // --- Babak 1: IKN berjaya ---
  await place('empeer_depeer');
  await act('lompat', 'lampau');
  let s = await gs();
  ok(s.pasir.era === 'lampau' && s.pasir.q12 && s.pasir.q12.step === 1, 'lompatan pertama: Quest 12 langkah 1');
  ok(s.pasir.kejar === null, 'belum ada pengejaran');
  await act('mulai12');

  // --- Babak 2: Tedsky muda ---
  await H.expectError(() => act('tedsky12', 'lupa'), /Aksi tidak dikenal/);
  await act('tedsky12', 'padam');
  s = await gs();
  ok(s.pasir.riak.tedsky_lampu === 'padam' && s.pasir.retak === 20, 'riak tedsky_lampu=padam, Retak +20');
  ok((await one(`select count(*)::int n from game.player_books where player_id = $1 and book_id = 'bk_ps_almanak'`, [pid])).n === 1, 'Almanak Lampu IKN');

  // --- Babak 3: jejak pertama ---
  await act('jejak12');
  s = await gs();
  ok(s.pasir.q12.step === 4 && s.pasir.sudyrman && s.unlocks.length === 3, 'Benua Sudyrman muncul');
  ok(s.pasir.kejar && s.pasir.kejar.jejak.kand.includes('sudyrman_pelabuhan') && s.pasir.kejar.jejak.kand.length === 3, 'tiga kemungkinan tujuan');
  ok(!JSON.stringify(s).includes('fzGm'), 'lokasi Franziska tidak pernah dikirim');

  // --- Babak 4: Pelabuhan Sudyrman (tutorial) ---
  await H.expectError(() => act('pesta_fz'), /tidak ada di sini/);
  await arrive('sudyrman_pelabuhan');
  s = await gs();
  ok(s.pasir.kejar.susul === 'ada', 'Franziska di Pelabuhan Sudyrman');
  await act('pesta_fz');
  ok((await gs()).pasir.kejar.susul === 'kabur', 'ia kabur ke kapalnya');
  const g0 = await gold();
  await act('kopi12');
  ok(await gold() === g0 - 500 && (await gs()).pasir.barang.includes('kopi_pahit'), 'Kopi Pahit Sudyrman');
  await act('nansy12', 'ok');
  ok((await gs()).pasir.riak.nansy_buku === true, 'riak nansy_buku');
  let f = await sailFight('joungjava');
  ok(f.boss === 'ps_janji', 'pelayaran berikutnya dicegat Janji Putih: ' + JSON.stringify(f).slice(0, 120));
  let guard = 0;
  while (f.res && f.res.result !== 'won' && guard++ < 6) { f = await sailFight('joungjava'); }
  s = await gs();
  ok(s.pasir.q12.step === 5 && s.pasir.q12.d.surat1, 'menang: Surat Franzi #1, langkah 5');
  ok(s.pasir.kejar.besok === true, 'batas harian: baru tersusul lagi besok');
  ok(Number((await gs()).ship.Condition) > 0, 'kapal selamat');

  // --- Babak 5: mesin pengejaran penuh ---
  await H.sql(`select game.admin_pasir('q12a_ana', 'harian')`);
  const P = await fz(0), Q = await fz(-1);
  ok(P && Q && P !== Q, 'jadwal: pindah tiap slot (' + Q + ' -> ' + P + ')');
  ok((await fz(0)) === P, 'deterministik');
  const rep = await one(`select count(*)::int n from generate_series(1, 300) g where game.ps_fz_port($1, g) = game.ps_fz_port($1, g - 1)`, [pid]);
  ok(rep.n === 0, 'tak pernah dua slot berturut-turut di pelabuhan sama');
  s = await gs();
  ok(s.pasir.kejar.gosip === (await one('select game.city_name($1) n', [Q])).n, 'gosip menyebut pelabuhan yang baru ia tinggalkan');
  await place(Q);
  s = await gs();
  ok(s.pasir.kejar.baruPergi === true, 'di pelabuhan yang baru ia tinggalkan');
  await act('jejak');
  s = await gs();
  ok(s.pasir.kejar.jejak.kand.includes(P) && s.pasir.kejar.jejak.segar, 'Olah Jejak: kemungkinan memuat tujuan benar');
  const r = await act('manifes');
  ok(r.coret && r.coret !== P, 'Manifes Syahbandar mencoret satu kemungkinan yang salah');
  await H.expectError(() => act('manifes'), /sudah menunjukkan/);
  const wrong = s.pasir.kejar.jejak.kand.find(c => c !== P);
  await arrive(wrong);
  ok((await gs()).pasir.kejar.susul !== 'ada', 'pelabuhan salah: tidak ada');
  await arrive(P);
  ok((await gs()).pasir.kejar.susul === 'ada', 'tersusul di ' + P);
  await act('pesta_fz');
  f = await sailFight(P === 'ikn' ? 'joungjava' : 'ikn');
  guard = 0;
  while ((!f.res || f.res.result !== 'won') && guard++ < 6) {
    if ((await gs()).pasir.q12.step === 6) break;
    await H.sql(`select game.admin_pasir('q12a_ana', 'harian')`);
    const p2 = await fz(0); await arrive(p2); await act('pesta_fz');
    f = await sailFight(p2 === 'ikn' ? 'joungjava' : 'ikn');
  }
  s = await gs();
  ok(s.pasir.q12.step === 6, 'tersusul kedua: Akademi, langkah 6');

  // Mas Karto & Ulin muda
  await place('bjorneo');
  await H.expectError(() => act('karto12', 'beri'), /Joungjava/);
  await place('joungjava');
  await act('karto12', 'beri');
  s = await gs();
  ok(s.pasir.riak.karto_kopi === 'beri' && !s.pasir.barang.includes('kopi_pahit'), 'Kopi pahit untuk Mas Karto');
  await place('bjorneo');
  const rt = (await gs()).pasir.retak;
  await act('ulin12', 'beri');
  ok((await gs()).pasir.retak === rt + 5, 'teka-teki jangkar: Retak +5');

  // --- Babak 6: Akademi ---
  await place('sudyrman_akademi');
  const g1 = await gold();
  await act('akademi12');
  s = await gs();
  ok(s.pasir.q12.step === 7 && s.pasir.q12.done && s.pasir.kaca === 3, 'Quest 12 selesai, kaca ketiga');
  ok(await gold() === g1 + 120000, 'hadiah 120.000');
  ok(s.pasir.kejar === null, 'pengejaran selesai');

  // Pemain di masa kini tidak terpengaruh
  const C = await H.user('q12a_cici');
  await C.call('api_createCharacter', ['Kapten Cici', 'merchant']);
  ok((await one(`select game.quest_boss_encounter($1, 'ikn') e`, [C.id])).e === null, 'pemain biasa: tanpa Janji Putih');

  console.log('0055 pasir q12: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
