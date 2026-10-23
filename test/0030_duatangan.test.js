// Saga 2 · Quest 9 "Tempat Dua Tangan Berjabat": prolog (3 hari game setelah Quest 8), Papan Armada di Sowtour
// (syarat, maks 2 veteran, Perbekalan Armada disetor & dikembalikan, larangan berlayar), Serbuan Bersama
// (giliran N kapal, fase bos, putus koneksi, Pertarungan Terakhir realtime dihitung server), Kartu Hasil,
// penutup (nasib Tedsky, hadiah, Rantai Lama per pemain), veteran.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const bot = require('./raidbot');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const dayMs = Number((await one(`select game.lt_len_ms() v`)).v);

  // kapten lulusan Quest 8
  const grad = async (u, name, bekal, opt) => {
    opt = opt || {};
    const c = await H.user(u); await c.call('api_createCharacter', [name, 'pirate']);
    const pid = c.id;
    await H.sql(`update game.players set gold = 100000 where player_id = $1`, [pid]);
    await H.sql(`update game.ships set tier = 'IV', cargo = 1000, condition = 100 where player_id = $1`, [pid]);
    await H.sql(`update game.character_stats set combat = 60, luck = 40, sailing = 50, navigation = 50, knowledge = 30 where player_id = $1`, [pid]);
    await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at, data) values
      ($1, 'gala', 6, now(), '{}'), ($1, 'toogood', 10, now(), '{}'), ($1, 'warwerwor', 12, now(), '{}'), ($1, 'barsati', 16, now(), '{}'),
      ($1, 'kompas', 8, now() - interval '30 days', '{"truth":"jujur"}'), ($1, 'cocoepan', 11, now(), '{}'),
      ($1, 'tigasilang', 12, now(), '{"tempa":"padamkan","garlyena":"bongkar","upayy_answer":"bahagia"}'),
      ($1, 'limatangan', 10, now() - interval '30 days', $2::jsonb)`, [pid, JSON.stringify(bekal)]);
    await H.sql(`update game.player_quests set updated_at = now() - interval '30 days' where player_id = $1`, [pid]);
    if (opt.recent) await H.sql(`update game.player_quests set done_at = now() where player_id = $1 and quest_id = 'limatangan'`, [pid]);
    await H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, opt.city || 'sowtour']);
    await H.sql(`select game.adjust_inventory($1, 'mesiu', 120), game.adjust_inventory($1, 'beras', 250)`, [pid]);
    const pub = (await c.call('api_mpPulse', [{}])).mePub;
    return { c, pid, pub, name };
  };
  const GOOD = { hookGrade: 'baik', beads: 4, hasiolan: 'percaya', jejakOk: true, drumBest: 70, cocoAdvice: 'bersama' };
  const POOR = { hookGrade: 'kasar', beads: 1, hasiolan: 'ambil', jejakOk: false, drumBest: 40, cocoAdvice: 'pilihan' };
  const A = await grad('dt_a', 'Kapten Alfa', GOOD);
  const B = await grad('dt_b', 'Kapten Bravo', POOR);
  const C = await grad('dt_c', 'Kapten Charlie', GOOD, { city: 'skitraw' });
  const D = await grad('dt_d', 'Kapten Delta', GOOD, { recent: true });
  const X = await H.user('dt_x'); await X.call('api_createCharacter', ['Belum Lima Tangan', 'merchant']);
  const dt = (u, a) => u.c.call('api_duaTangan', a);
  const raid = (u, a) => u.c.call('api_dtRaid', a);
  const qty = async (u, id) => Number((await one('select game.item_qty($1, $2) q', [u.pid, id])).q);
  const step = async u => Number((await one(`select game.dt_step($1) s`, [u.pid])).s);

  // --- syarat & prolog ------------------------------------------------------------
  ok((await X.call('api_duaTangan', ['status'])).duatangan === null, 'tersembunyi sebelum Quest 8 selesai');
  let s = (await dt(D, ['status'])).duatangan;
  ok(s && s.ready === false && s.openAt > Date.now(), 'jeda 3 hari game setelah penutup Quest 8');
  await H.expectError(() => dt(D, ['prolog']), /Belum tiga hari/);
  await H.sql(`update game.player_quests set done_at = now() - ($2 || ' milliseconds')::interval where player_id = $1 and quest_id = 'limatangan'`, [D.pid, String(3 * dayMs + 1000)]);
  ok((await dt(D, ['status'])).duatangan.ready === true, 'prolog terbuka setelah 3 hari game');
  await H.expectError(() => raid(A, ['open']), /Surat Teh Euis/);
  for (const u of [A, B, C, D]) { s = (await dt(u, ['prolog'])).duatangan; ok(s.step === 1, 'prolog ' + u.name); }
  const gs = await A.c.call('api_getGameState', [null]);
  ok(gs.duatangan && gs.duatangan.step === 1 && gs.duatangan.bekal.hookMul === 1.4 && gs.duatangan.bekal.lane === 160, 'getGameState duatangan + bekal ' + JSON.stringify(gs.duatangan && gs.duatangan.bekal));
  ok(s.bekal.cry === true && s.bekal.allies === 2, 'bekal Seruan & sekutu');
  const bb = (await dt(B, ['status'])).duatangan.bekal;
  ok(bb.hookMul === 1.0 && bb.lane === 70 && bb.immune === true && bb.cry === false && bb.allies === 1, 'bekal buruk ' + JSON.stringify(bb));
  await dt(A, ['tiba']);

  // --- lobi -------------------------------------------------------------------------
  await H.expectError(() => raid(C, ['open']), /dermaga Kota Sowtour/);
  await H.expectError(() => X.call('api_dtRaid', ['open']), /Lima Tangan/);
  let r = (await raid(A, ['open'])).raid;
  ok(r.status === 'lobby' && r.members.length === 1 && r.members[0].lead && r.members[0].hook === 'baik', 'armada dibuka');
  const chat = await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`);
  ok(chat && /Kapten Alfa menabuh genderang di Sowtour \(1\/4\)/.test(chat.msg.tx), 'pengumuman chat dunia ' + JSON.stringify(chat && chat.msg));
  const inbox = await one(`select count(*)::int n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'raid_open'`, [B.pid]);
  ok(inbox.n === 1, 'notifikasi ke kapten yang memenuhi syarat');
  await H.expectError(() => raid(A, ['open']), /sudah tercatat/);
  const board = await raid(B, ['board']);
  ok(board.board.length === 1 && board.board[0].leader === 'Kapten Alfa', 'Papan Armada');
  r = (await raid(B, ['join', r.id])).raid;
  ok(r.members.length === 2, 'Bravo bergabung');
  // tidak bisa berlayar selama di lobi
  await H.expectError(() => A.c.call('api_setSail', ['karang_garam']), /Papan Armada/);
  // depart butuh 2 siap
  await H.expectError(() => raid(A, ['depart']), /dua kapten yang siap/);
  await H.expectError(() => raid(B, ['depart']), /pembuka armada/);
  // Siap: setor Perbekalan Armada
  const m0 = await qty(A, 'mesiu'), b0 = await qty(A, 'beras');
  r = (await raid(A, ['ready', true])).raid;
  ok((await qty(A, 'mesiu')) === m0 - 50 && (await qty(A, 'beras')) === b0 - 100, 'setoran dipotong saat Siap');
  r = (await raid(A, ['ready', false])).raid;
  ok((await qty(A, 'mesiu')) === m0 && (await qty(A, 'beras')) === b0, 'setoran kembali saat batal siap');
  await H.sql(`select game.adjust_inventory($1, 'beras', -200)`, [B.pid]);
  await H.expectError(() => raid(B, ['ready', true]), /kurang 50 Beras/);
  await H.sql(`select game.adjust_inventory($1, 'beras', 200)`, [B.pid]);
  // keluar sebelum berangkat: setoran kembali, pembuka pindah
  await raid(A, ['ready', true]);
  await raid(A, ['leave']);
  ok((await qty(A, 'mesiu')) === m0, 'keluar = setoran kembali');
  r = (await raid(B, ['view'])).raid;
  ok(r.members.length === 1 && r.members[0].pub === B.pub && r.members[0].lead, 'pembuka berpindah');
  r = (await raid(A, ['join', r.id])).raid;
  // veteran: maks 2, minimal 1 pemain baru (diuji dengan menandai veteran lewat data)
  await H.sql(`update game.mp_raid_members set vet = true where raid_id = $1`, [r.id]);
  await raid(A, ['ready', true]); await raid(B, ['ready', true]);
  await H.expectError(() => raid(B, ['depart']), /belum pernah melihat akhirnya/);
  await H.sql(`update game.mp_raid_members set vet = false where raid_id = $1`, [r.id]);
  // kapten belum siap 5 menit dikeluarkan
  await H.sql(`update game.player_location set city_id = 'sowtour' where player_id = $1`, [C.pid]);
  await raid(C, ['join', r.id]);
  await H.sql(`update game.mp_raid_members set joined_ms = joined_ms - 301000 where raid_id = $1 and player_id = $2`, [r.id, C.pid]);
  r = (await raid(A, ['view'])).raid;
  ok(r.members.length === 2 && !r.members.some(m => m.pub === C.pub), 'tidak siap 5 menit = dikeluarkan');

  // --- serbuan: giliran pertama -------------------------------------------------------
  r = (await raid(B, ['depart'])).raid;
  ok(r.status === 'active' && r.phase === 'plan' && r.round === 1 && Object.keys(r.st.ships).length === 2, 'Angkat Sauh');
  ok(r.st.boss.hull === 1000 && r.st.boss.shield === 260 && r.st.boss.phase === 1, 'Sayap Patah utuh');
  ok(r.st.ships[B.pub].rlL === 0 && r.st.ships[A.pub].rlL === undefined, 'meriam kapten lain dirahasiakan');
  await H.expectError(() => A.c.call('api_setSail', ['karang_garam']), /menyerbu/);
  const ships0 = r.st.ships;
  r = (await raid(A, ['act', 1, { rud: 1, sails: 1, fl: true, fr: false, ammo: 'chain' }])).raid;
  ok(r.round === 1 && r.locked[A.pub] && !r.locked[B.pub], 'Alfa mengunci');
  const rb = (await raid(B, ['view'])).raid;
  ok(rb.myOrd === null && rb.locked[A.pub] === true && !JSON.stringify(rb).includes('"ammo":"chain","cry"'), 'perintah Alfa rahasia');
  r = (await raid(B, ['act', 1, { rud: -1, sails: 1, fl: false, fr: true, ammo: 'ball' }])).raid;
  ok(r.round === 2 && r.ev && r.ev.r === 1 && r.ev.tracks[A.pub].length === 12 && r.ev.boss.length === 12, 'giliran 1 dihitung, jejak animasi');
  ok(Math.hypot(r.st.ships[A.pub].x - ships0[A.pub].x, r.st.ships[A.pub].y - ships0[A.pub].y) > 20, 'kapal berlayar');
  ok(r.ev.shots.some(x => x.by === 'pearl'), 'Black Pearl ikut menembak');

  // putus koneksi: Bravo tidak terdengar -> giliran tidak menunggunya, kapalnya diam (layar setengah)
  await H.sql(`update game.mp_raid_members set seen_ms = seen_ms - 20000 where raid_id = $1 and player_id = $2`, [r.id, B.pid]);
  r = (await raid(A, ['act', 2, { rud: 0, sails: 1, fl: false, fr: false, ammo: 'ball' }])).raid;
  ok(r.round === 3 && r.ev.auto[B.pub] === 'off' && r.st.ships[B.pub].sails === 0 && r.st.ships[B.pub].rud === 0, 'kapal putus koneksi diam ' + JSON.stringify(r.ev.auto));

  // --- fase: perisai pecah -> Arus Pusaran -> Tangan yang Dipaksa -> Murka ----------------
  const sql = (q, p) => H.sql(q, [r.id].concat(p || []));
  await sql(`update game.mp_raids set st = jsonb_set(st, '{boss,shield}', '1') where id = $1`);
  r = (await raid(A, ['act', 3, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'chain' }])).raid;
  r = (await raid(B, ['act', 3, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'chain' }])).raid;
  ok(r.st.boss.phase === 2 && r.ev.cine === 'rantai' && r.st.boss.hull <= 700, 'perisai pecah, Arus Pusaran ' + JSON.stringify([r.st.boss.phase, r.ev.cine, r.st.boss.hull]));
  ok(r.planStart - r.t > 12000, 'jeda sinematik');
  // keluar jalur aman: Bravo (ambil) kebal pada tarikan pertama, Alfa terseret
  await sql(`update game.mp_raids set st = jsonb_set(jsonb_set(st, array['ships', $2, 'x'], '1100'), array['ships', $2, 'y'], '1000'),
    round_ts = round_ts - 20000 where id = $1`, [A.pub]);
  await sql(`update game.mp_raids set st = jsonb_set(jsonb_set(st, array['ships', $2, 'x'], '1100'), array['ships', $2, 'y'], '480') where id = $1`, [B.pub]);
  r = (await raid(A, ['act', 4, { rud: 0, sails: 0, fl: false, fr: false, ammo: 'ball' }])).raid;
  r = (await raid(B, ['act', 4, { rud: 0, sails: 0, fl: false, fr: false, ammo: 'ball' }])).raid;
  ok(r.ev.evs.some(e => e.k === 'pulled' && e.by === A.pub) && r.ev.evs.some(e => e.k === 'immune' && e.by === B.pub), 'arus: terseret & kebal ' + JSON.stringify(r.ev.evs));
  await sql(`update game.mp_raids set st = jsonb_set(st, '{boss,hull}', '501') where id = $1`);
  r = (await raid(A, ['act', 5, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'ball' }])).raid;
  r = (await raid(B, ['act', 5, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'ball' }])).raid;
  // tembakan bisa meleset: dorong sampai lewat 50%
  for (let i = 0; i < 6 && r.st.boss.phase === 2; i++) {
    await sql(`update game.mp_raids set st = jsonb_set(st, '{boss,hull}', '500.5') where id = $1`);
    r = (await raid(A, ['act', r.round, { rud: 0, sails: 1, fl: false, fr: false, ammo: 'ball' }])).raid;
    r = (await raid(B, ['act', r.round, { rud: 0, sails: 1, fl: false, fr: false, ammo: 'ball' }])).raid;
  }
  ok(r.st.boss.phase === 3 && r.ev.cine === 'paksa', 'Tangan yang Dipaksa -> Murka');
  // Seruan: Alfa (Kelemahan Tedsky) membungkam bos; Bravo tidak punya Seruan
  await sql(`update game.mp_raids set round_ts = round_ts - 20000 where id = $1`);
  r = (await raid(B, ['act', r.round, { rud: 0, sails: 1, fl: false, fr: false, ammo: 'ball', cry: true }])).raid;
  r = (await raid(A, ['act', r.round, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'ball', cry: true }])).raid;
  ok(r.ev.cry === A.pub && r.st.boss.stun === true && !r.ev.shots.some(x => x.by === 'boss') && r.st.ships[A.pub].cry === false, 'Seruan ' + JSON.stringify(r.ev.cry));
  ok(!r.ev.shots.some(x => x.by === A.pub), 'Seruan menggantikan tembakan');
  ok(r.stats[A.pub].cry === 1 && !(r.stats[B.pub] && r.stats[B.pub].cry), 'Seruan tercatat');

  // --- Pertarungan Terakhir --------------------------------------------------------------
  await sql(`update game.mp_raids set st = jsonb_set(st, '{boss,hull}', '301') where id = $1`);
  for (let i = 0; i < 8 && r.phase === 'plan'; i++) {
    r = (await raid(A, ['act', r.round, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'ball' }])).raid;
    r = (await raid(B, ['act', r.round, { rud: 0, sails: 1, fl: true, fr: true, ammo: 'ball' }])).raid;
    if (r.phase === 'plan') await sql(`update game.mp_raids set st = jsonb_set(st, '{boss,hull}', '300.2') where id = $1`);
  }
  ok(r.phase === 'final' && r.finalTs > r.t && r.finalEnd - r.finalTs === 75000, 'Pertarungan Terakhir realtime 75 dtk');
  let rt = await raid(A, ['rt', { x: 1, y: 1, h: 0 }, [{ k: 'f', s: 1 }], 0]);
  ok(rt.status === 'active' && rt.ev.length === 0, 'belum mulai: tembakan diabaikan');
  await H.sql(`update game.config set value = (value::bigint + $1)::text where key = 'DtClockOffset'`, [r.finalTs - r.t + 100]);
  // Alfa menempel di samping bos dan menembak; server menghitung damage bos
  const bs = rt.boss;
  const hb = bs.hull;
  rt = await raid(A, ['rt', { x: bs.x + 200 * Math.cos(bs.h), y: bs.y + 200 * Math.sin(bs.h), h: bs.h, v: 20 }, [{ k: 'f', s: -1, a: 'ball' }, { k: 'f', s: -1, a: 'ball' }], 0]);
  const fires = rt.ev.filter(e => e.ev.k === 'f' && e.ev.by === A.pub);
  ok(fires.length === 1, 'isi ulang realtime dijaga server ' + fires.length);
  // tembakan bisa meleset: coba lagi setelah isi ulang sampai kena
  let hitAny = rt.boss.hull < hb;
  for (let i = 0; i < 10 && !hitAny; i++) {
    await H.sql(`update game.config set value = (value::bigint + 3200)::text where key = 'DtClockOffset'`);
    const b2 = rt.boss;
    rt = await raid(A, ['rt', { x: b2.x + 150 * Math.cos(b2.h), y: b2.y + 150 * Math.sin(b2.h), h: b2.h, v: 20 }, [{ k: 'f', s: -1, a: 'ball' }, { k: 'f', s: 1, a: 'ball' }], rt.seq]);
    hitAny = rt.boss.hull < hb;
  }
  ok(hitAny, 'tembakan realtime mengurangi HP bos');
  ok(rt.ships[B.pub] && rt.ships[B.pub].on === false, 'kapal Bravo terlihat diam');
  // Serbu Geladak: harus menyentuh lambung bos
  const b3 = rt.boss;
  rt = await raid(B, ['rt', { x: b3.x + 400, y: b3.y, h: 0 }, [{ k: 'b', sc: 3 }], 0]);
  ok(!rt.ev.some(e => e.ev.k === 'b'), 'Serbu Geladak dari jauh ditolak');
  rt = await raid(B, ['rt', { x: rt.boss.x + 60, y: rt.boss.y, h: 0 }, [{ k: 'b', sc: 3 }], rt.seq]);
  ok(rt.ev.some(e => e.ev.k === 'b' && e.ev.ok && e.ev.petrik) && rt.petrik === B.pub, 'Serbu Geladak membebaskan Petrik');
  // tuntaskan: bos tinggal sedikit
  await sql(`update game.mp_raids set st = jsonb_set(st, '{boss,hull}', '0.5') where id = $1`);
  for (let i = 0; i < 12 && rt.status === 'active'; i++) {
    await H.sql(`update game.config set value = (value::bigint + 3200)::text where key = 'DtClockOffset'`);
    const b4 = rt.boss;
    rt = await raid(A, ['rt', { x: b4.x + 150 * Math.cos(b4.h), y: b4.y + 150 * Math.sin(b4.h), h: b4.h, v: 20 }, [{ k: 'f', s: -1, a: 'ball' }, { k: 'f', s: 1, a: 'ball' }], rt.seq]);
  }
  ok(rt.status === 'done' && rt.result === 'win', 'Sayap Patah tenggelam ' + JSON.stringify([rt.status, rt.result]));

  // --- Kartu Hasil -> penutup ---------------------------------------------------------------
  r = (await raid(A, ['card', r.id])).raid;
  ok(r.card && r.card.result === 'win' && r.card.rows.length === 2 && r.card.petrik === B.pub && r.card.first, 'Kartu Hasil ' + JSON.stringify(r.card && r.card.first));
  ok(r.card.rows.find(x => x.pub === A.pub).cry === 1 && r.card.rows.find(x => x.pub === B.pub).boards === 1, 'kontribusi per kapten');
  s = (await dt(A, ['status'])).duatangan;
  ok(s.step === 3 && s.raidWon === r.id && s.petrik === false && s.duo === true && s.history.length === 1 && s.fleet.length === 2, 'Alfa menang ' + JSON.stringify([s.step, s.duo]));
  ok((await dt(B, ['status'])).duatangan.petrik === true, 'Bravo Pemecah Rantai Petrik');
  const cond = Number((await one(`select condition c from game.ships where player_id = $1`, [A.pid])).c);
  ok(cond < 100 && cond >= 5, 'kapal lecet ' + cond);
  ok(((await raid(A, ['view'])).raid) === null, 'tidak lagi di armada');
  await H.expectError(() => raid(A, ['open']), /menunggu tanganmu di batu/);
  // nasib Tedsky
  await H.expectError(() => dt(A, ['tutup']), /Belum waktunya/);
  await H.expectError(() => dt(A, ['fate', 'laut']), /tidak dikenal/);
  await dt(A, ['fate', 'dewan']);
  await dt(B, ['fate', 'ikn']);
  const g0 = Number((await one('select gold from game.players where player_id = $1', [A.pid])).gold);
  const nav0 = Number((await one('select navigation n from game.character_stats where player_id = $1', [A.pid])).n);
  const out = await dt(A, ['tutup']);
  ok(out.paid === 750000 && out.cityId === 'toogood' && out.duatangan.done && out.duatangan.veteran, 'penutup: 750.000 gold, TooGood');
  ok(Number((await one('select gold from game.players where player_id = $1', [A.pid])).gold) === g0 + 750000, 'gold masuk');
  ok(Number((await one('select navigation n from game.character_stats where player_id = $1', [A.pid])).n) === nav0 + 15, 'Peta Dua Tangan +15 Navigation');
  ok((await one(`select count(*)::int n from game.ship_equipment where player_id = $1 and item_id = 'art_jabat_tangan'`, [A.pid])).n === 1 && out.equipped, 'Jabat Tangan terpasang');
  ok(out.unlocks.includes('teluk_dua_tangan'), 'Teluk Dua Tangan di peta');
  await dt(A, ['tutup']);
  ok(Number((await one('select gold from game.players where player_id = $1', [A.pid])).gold) === g0 + 750000, 'hadiah sekali');
  await dt(A, ['credits']);
  ok((await dt(A, ['status'])).duatangan.credits === true, 'credit ditonton');
  await dt(B, ['tutup']);

  // Rantai Lama: pelabuhan tetap untuk Alfa (Dewan), tetap kota hantu untuk Bravo (IKN)
  for (const u of [A, B]) await H.sql(`update game.player_location set city_id = 'rantai_lama' where player_id = $1`, [u.pid]);
  const mk = await A.c.call('api_getMarket', ['rantai_lama']).catch(e => e);
  ok(!(mk instanceof Error) || !/kota hantu/.test(mk.message), 'pasar Rantai Lama buka untuk Dewan');
  await H.expectError(() => B.c.call('api_buy', ['rantai_lama', 'besi', 1]), /kota hantu/);
  const rq = await one(`select game.voy_repair_quote($1, 'rantai_lama') q`, [A.pid]);
  ok(rq.q.blocked === null, 'galangan Rantai Lama buka untuk Dewan');
  const rq2 = await one(`select game.voy_repair_quote($1, 'rantai_lama') q`, [B.pid]);
  ok(/kota hantu/.test(rq2.q.blocked), 'galangan Rantai Lama tetap tutup untuk IKN');
  ok((await one(`select game.spot_city('rantai_lama') s`)).s === true, 'dunia: Rantai Lama tetap titik khusus (jarak tidak berubah)');
  // Jabat Tangan: harga jual Sowtour +10% tapi tetap di bawah harga beli
  const mu = await one(`select (game.eco2_muls($1, 'sowtour', 'porselen')).*`, [A.pid]);
  const mu2 = await one(`select (game.eco2_muls($1, 'sowtour', 'porselen')).*`, [C.pid]);
  ok(mu.sell_mul > mu2.sell_mul * 1.05 && mu.sell_mul < mu.buy_mul, 'Jabat Tangan: harga jual naik, tetap < harga beli ' + JSON.stringify([mu, mu2]));
  // Peta Dua Tangan: waktu tempuh rute Laut Timur -20%
  const tA = await one(`select game.voy_travel_seconds(game.voy_map_distance('freeyork', 'sowtour'), game.lt_ship_for_route($1, 'freeyork', 'sowtour')) t`, [A.pid]);
  const tA2 = await one(`select game.voy_travel_seconds(game.voy_map_distance('freeyork', 'sowtour'), game.ship_json($1)) t`, [A.pid]);
  ok(Number(tA.t) < Number(tA2.t) * 0.85, 'Peta Dua Tangan: waktu tempuh Laut Timur -20% ' + tA.t + ' vs ' + tA2.t);

  // --- veteran ------------------------------------------------------------------------------
  for (const u of [A, B, C, D]) await H.sql(`update game.player_location set city_id = 'sowtour' where player_id = $1`, [u.pid]);
  ok((await dt(A, ['status'])).duatangan.veteran, 'Alfa veteran');
  r = (await raid(A, ['open'])).raid;
  await raid(B, ['join', r.id]);
  await raid(C, ['join', r.id]);
  // armada A (vet), B (vet), C (baru): veteran ketiga tidak boleh
  const E = await grad('dt_e', 'Kapten Echo', GOOD); await dt(E, ['prolog']);
  await H.sql(`update game.player_quests set step = 5 where player_id = $1 and quest_id = 'duatangan'`, [E.pid]);
  await H.expectError(() => raid(E, ['join', r.id]), /dua veteran/);
  const mv = await qty(A, 'mesiu');
  r = (await raid(A, ['view'])).raid;
  ok(r.members.filter(m => m.vet).length === 2, 'dua veteran di armada');
  await raid(A, ['ready', true]);
  ok((await qty(A, 'mesiu')) === mv, 'veteran tidak menyetor');

  // simulasi serbuan berempat (A, B veteran; C, D baru) memakai bot
  if (!r.members.some(m => m.pub === C.pub)) await raid(C, ['join', r.id]);
  await raid(D, ['join', r.id]);
  await raid(B, ['ready', true]); await raid(C, ['ready', true]); await raid(D, ['ready', true]);
  r = (await raid(A, ['view'])).raid;
  ok(r.departAt && r.departAt - r.t <= 30000 && r.departAt - r.t > 25000, 'empat siap: hitung mundur 30 dtk');
  await H.sql(`update game.config set value = (value::bigint + 31000)::text where key = 'DtClockOffset'`);
  r = (await raid(A, ['view'])).raid;
  ok(r.status === 'active' && Object.keys(r.st.ships).length === 4, 'berangkat otomatis');
  const gA = Number((await one('select gold from game.players where player_id = $1', [A.pid])).gold);
  const res = await bot.runRaid(H, [A, B, C, D].map(u => ({ c: u.c, pub: u.pub })), { skill: 0.95 });
  console.log('serbuan 4 kapal:', res.result, 'giliran', res.turns, 'bos saat final', res.finalBoss);
  ok(res.status === 'done' && (res.result === 'win' || res.result === 'loss'), 'serbuan bot selesai');
  if (res.result === 'win') {
    ok(Number((await one('select gold from game.players where player_id = $1', [A.pid])).gold) >= gA + 100000, 'veteran +100.000');
    ok((await dt(A, ['status'])).duatangan.vetWins === 1 && (await step(C)) === 3, 'veteran tercatat, pemain baru ke penutup');
  } else {
    ok((await step(C)) === 1, 'kalah: pemain baru tetap di langkah 1');
  }
  // setoran Perbekalan Armada terpakai (pemain baru)
  ok((await qty(C, 'mesiu')) === 70 && (await qty(C, 'beras')) === 150, 'setoran terpakai saat berangkat');

  // kalah: semua mundur
  if (res.result === 'win') {
    // veteran menang lagi di hari yang sama: tanpa gold
    await H.sql(`update game.player_quests set step = 1 where player_id = $1 and quest_id = 'duatangan'`, [C.pid]);
  }
  r = (await raid(A, ['open'])).raid; await raid(C, ['join', r.id]);
  await raid(A, ['ready', true]); await raid(C, ['ready', true]);
  r = (await raid(A, ['depart'])).raid;
  await raid(A, ['flee']);
  r = (await raid(C, ['flee'])).raid;
  ok(r.status === 'done' && r.result === 'loss', 'semua mundur = kalah');
  ok((await step(C)) === 1 && (await dt(C, ['status'])).duatangan.tries >= 1, 'percobaan tercatat');

  console.log('0030_duatangan OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
