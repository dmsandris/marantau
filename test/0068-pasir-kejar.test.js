// Tide v53 · Pengejaran Franziska tanpa gantung: permainan jejak bergiliran, kabar tiba, hari game.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const A = await H.user('k53_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [pid]);
  await H.sql(`select game.pasir_ensure($1)`, [pid]);
  await H.sql(`select game.pv_ambil($1, 'sunda_empire')`, [pid]);
  await H.sql(`update game.pasir_state set data = data || '{"buka": ["empeer_depeer"], "sudyrman": true}'::jsonb, kaca = 3, era = 'lampau' where player_id = $1`, [pid]);
  await H.sql(`select game.ps_set($1, 'ps10', 11, '{}'::jsonb, true), game.ps_set($1, 'ps11', 10, '{}'::jsonb, true), game.ps_set($1, 'ps12', 5, '{"surat1": true}'::jsonb)`, [pid]);
  await H.sql(`select game.ps_kdata_set($1, '{"n": 1}'::jsonb)`, [pid]);
  await H.sql(`update game.players set gold = 100000 where player_id = $1`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const arrive = async (c) => { await place(c); await H.sql(`select game.ps_on_arrive($1, $2)`, [pid, c]); };
  const port = async (d) => (await one(`select game.ps_fz_port($1, game.ps_slot() + $2) p`, [pid, d || 0])).p;
  const liar = async (city, coba) => String((await one(`select (game.ps_warga_soal($1, game.ps_slot(), $2, $3) ->> 'bohong') b`, [pid, city, coba || 0])).b);
  const best = async (w) => (await one(`select string_agg((select o from unnest(array['sopan','akrab','langsung','kopi','cerita','bantu','halus','pancing']) o order by game.ps_kuli_nilai($1, r, o) desc limit 1), ',' order by r) a from generate_series(1,3) r`, [w])).a;
  const worst = async (w) => (await one(`select string_agg((select o from unnest(array['sopan','akrab','langsung','kopi','cerita','bantu','halus','pancing']) o where game.ps_kuli_nilai($1, r, o) > -1 or true order by game.ps_kuli_nilai($1, r, o) asc, o limit 1), ',' order by r) a from generate_series(1,3) r`, [w])).a;
  const shiftSlot = async () => { await H.shiftTime(45 * 60000); };

  // hari game
  ok(/^g\d+$/.test((await one(`select game.ps_hari() h`)).h), 'hari = hari game');

  // --- permainan jejak ---
  const games = [];
  for (let round = 0; round < 4; round++) {
    const Q = await port(-1);
    await place(Q);
    let s = await gs();
    if (!s.pasir.kejar || !s.pasir.kejar.main) console.log(JSON.stringify(s.pasir.kejar), Q, await port(0), JSON.stringify(s.pasir.q12));
    ok(s.pasir.kejar.baruPergi && s.pasir.kejar.main, 'baru pergi: permainan jejak ditawarkan (' + round + ')');
    const m = s.pasir.kejar.main;
    ok(['warga', 'buntuti', 'surat', 'kuli'].includes(m.game), 'permainan dikenal: ' + m.game);
    if (games.length) ok(m.game !== games[games.length - 1], 'tidak sama dengan permainan terakhir');
    games.push(m.game);
    await H.expectError(() => act('jejak', m.game === 'warga' ? 'kuli' : 'warga', '0'), /cara lain/);
    if (m.game === 'warga') {
      ok(m.saksi.length === 3 && m.fakta && !JSON.stringify(m).includes('bohong'), 'tiga saksi, pembohong tidak dikirim');
      const L = await liar(Q, 0), wrong = String((Number(L) + 1) % 3);
      let r = await act('jejak', 'warga', wrong);
      ok(r.ok === false && r.ulang, 'salah tunjuk: boleh ulang');
      ok((await gs()).pasir.kejar.main.coba === 1, 'percobaan kedua: saksi baru');
      r = await act('jejak', 'warga', await liar(Q, 1));
      ok(r.grade === 'lulus' && r.kand.length === 3, 'benar di ulangan: lulus, 3 kemungkinan');
    } else if (m.game === 'kuli') {
      let r = await act('jejak', 'kuli', await worst(m.watak));
      ok(r.ok === false, 'kuli tutup mulut');
      const m2 = (await gs()).pasir.kejar.main;
      r = await act('jejak', 'kuli', await worst(m2.watak));
      ok(r.grade === 'samar' && r.kand.length === 4, 'gagal dua kali: jejak samar, 4 kemungkinan');
    } else {
      const r = await act('jejak', m.game, 'sempurna');
      ok(r.grade === 'sempurna' && r.kand.length === 2, 'sempurna: 2 kemungkinan');
    }
    s = await gs();
    const P = await port(0);
    ok(s.pasir.kejar.jejak.kand.includes(P), 'kemungkinan memuat tujuan benar');
    ok(!s.pasir.kejar.main, 'permainan selesai untuk pelabuhan ini');
    // tiba di kemungkinan yang salah: dicoret otomatis
    const wrongC = s.pasir.kejar.jejak.kand.find(c => c !== P);
    await arrive(wrongC);
    s = await gs();
    ok(s.pasir.kejar.tiba && s.pasir.kejar.tiba.hasil === 'kosong' && s.pasir.kejar.jejak.coret.includes(wrongC), 'kosong: dicoret otomatis');
    await shiftSlot();
  }

  // jejak basi
  {
    const s0 = await gs(), j = s0.pasir.kejar.jejak;
    const c = j.kand.find(x => !j.coret.includes(x));
    await arrive(c);
    const s = await gs();
    ok(s.pasir.kejar.tiba.hasil === 'dingin' || s.pasir.kejar.susul === 'ada', 'jejak lewat slot: dingin (atau kebetulan tersusul)');
  }

  // Kopi Pahit untuk kuli: sempurna, kopi habis, bisa beli lagi
  {
    await H.sql(`select game.ps_barang_add($1, 'kopi_pahit')`, [pid]);
    let g = 0, m = null, Q;
    while (g++ < 30) {
      await H.sql(`select game.ps_kdata_set($1, '{"lastGame": null}'::jsonb)`, [pid]);
      Q = await port(-1); await place(Q);
      m = (await gs()).pasir.kejar.main;
      if (m && m.game === 'kuli') break;
      await shiftSlot();
    }
    ok(m && m.game === 'kuli', 'giliran kuli muncul');
    const r = await act('jejak', 'kuli', 'sopan,kopipahit,halus');
    ok(r.grade === 'sempurna' && r.kopi, 'Kopi Pahit: sempurna');
    ok(!(await gs()).pasir.barang.includes('kopi_pahit'), 'kopi habis');
    await place('sudyrman_pelabuhan');
    await act('kopi12');
    ok((await gs()).pasir.barang.includes('kopi_pahit'), 'kopi bisa dibeli lagi');
    await H.expectError(() => act('kopi12'), /sudah membawa/);
  }

  // Surat Tercecer menambah koleksi
  {
    let g = 0, m = null;
    while (g++ < 30) { await shiftSlot(); await H.sql(`select game.ps_kdata_set($1, '{"lastGame": null}'::jsonb)`, [pid]); await place(await port(-1)); m = (await gs()).pasir.kejar.main; if (m && m.game === 'surat') break; }
    ok(m && m.game === 'surat' && m.kiasan && !JSON.stringify(m).includes(await port(0)) && m.potong >= 6, 'surat: tujuan & jumlah sobekan');
    const n0 = (await gs()).pasir.kejar.surat;
    await act('jejak', 'surat', 'lulus');
    ok((await gs()).pasir.kejar.surat === n0 + 1, 'surat tersimpan');
  }

  // zaman salah
  await H.sql(`update game.pasir_state set era = 'keadilan' where player_id = $1`, [pid]);
  ok((await gs()).pasir.kejarZaman === 'lampau', 'di Zaman Keadilan: petunjuk zaman');
  await H.sql(`update game.pasir_state set era = 'lampau' where player_id = $1`, [pid]);

  // Quest 13: tujuan benar, zaman salah
  const B = await H.user('k53_budi');
  await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [B.id]);
  await H.sql(`select game.pasir_ensure($1)`, [B.id]);
  await H.sql(`update game.pasir_state set data = data || '{"sudyrman": true}'::jsonb, era = 'keadilan' where player_id = $1`, [B.id]);
  await H.sql(`select game.ps_set($1, 'ps12', 7, '{}'::jsonb, true), game.ps_set($1, 'ps13', 4, '{"n": 0}'::jsonb)`, [B.id]);
  await H.sql(`update game.player_location set city_id = 'sudyrman_lembah' where player_id = $1`, [B.id]);
  await H.sql(`select game.ps_on_arrive($1, 'sudyrman_lembah')`, [B.id]);
  const sb = await B.call('api_getGameState', []);
  ok(sb.pasir.kejar && sb.pasir.kejar.tiba && sb.pasir.kejar.tiba.hasil === 'zaman' && sb.pasir.kejar.tiba.era === 'lampau', 'Q13: zaman salah diberi tahu');

  console.log('0068 pasir kejar: semua lulus (' + games.join(', ') + ')');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
