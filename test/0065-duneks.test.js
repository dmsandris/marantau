// Quest rahasia "Knock-knock Gudang Door" (TheDuneks): gerbang Saga 2, side quest satu per satu (dua arah),
// 8 langkah + pilihan, kota, malam, idempoten, Tata Gudang diperiksa server (solver), sumbangan bertingkat,
// GM tidak memakai urutan, tolak 25.000, kolam penuh -> Kamp Pemulung, penembus 100 jt tamat dalam satu transaksi,
// Balai Kongsi tetap atas nama Ki Dorus, rahasia (tanpa log/TJ/chat khusus).
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const SOL = require('./duneks-solver');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const cfg = (k, v) => H.sql(`insert into game.config(key, value) values ($1, $2) on conflict (key) do update set value = excluded.value`, [k, v]);
  const lenMs = async () => Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) * 60000 v`)).v);
  const setFrac = async (f) => { const L = await lenMs(); const now = Number((await one('select game.now_ms() v')).v); await cfg('WorldStartTimestamp', String(Math.round(now - f * L - 2000))); };
  const siang = () => setFrac(0.4), malam = () => setFrac(0.8);
  const ke = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null where player_id = $1`, [u.id, c]);
  const gold = async (u) => Number((await one('select gold g from game.players where player_id = $1', [u.id])).g);
  const pool = async () => Number((await one(`select total t from game.gr_projects where id = 'ikn'`)).t);
  const mine = async (u) => Number(((await one(`select total t from game.gr_donations where project_id = 'ikn' and player_id = $1`, [u.id])) || { t: 0 }).t);
  const mk = async (name, uname, saga2 = true) => {
    const u = await H.user(uname); await u.call('api_createCharacter', [name, 'merchant']);
    if (saga2) await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'duatangan', 5)`, [u.id]);
    return u;
  };
  const STEPS = (await one('select game.dn_steps() s')).s;
  const LV = (await one('select game.dn_levels() l')).l;
  ok(STEPS.length === 8, '8 langkah: ' + STEPS.length);
  ok((await one(`select game.side_quest_ids() v`)).v.slice(0, 2).join() === 'peregrin,duneks', 'duneks terdaftar sebagai side quest');
  await cfg('GotongOpen', '1');

  // ------------------------------------------------------------------ level: semua bisa diselesaikan, server = solver
  const SOLN = {}, MANI = {};
  for (const k of Object.keys(LV)) {
    const L = LV[k];
    if (L.mode === 'susun') {
      const r = SOL.solve(L, 1);
      ok(r.first && SOL.check(L, r.first).ok, 'level ' + k + ' bisa diselesaikan');
      ok(L.par >= L.items.length, 'par ' + k + ' >= jumlah peti');
      SOLN[k] = r.first;
      ok((await one('select game.dn_check_susun($1, $2) e', [L, r.first])).e === null, 'server menerima solusi solver: ' + k);
      // pelanggaran tiap aturan ditolak
      const bad = JSON.parse(JSON.stringify(r.first)), heavy = L.items.find(i => (i.tags || []).includes('berat'));
      bad[heavy.id] = { x: bad[heavy.id].x, y: L.h - 1, r: 0 };
      ok((await one('select game.dn_check_susun($1, $2) e', [L, bad])).e, 'server menolak susunan salah: ' + k);
      const miss = JSON.parse(JSON.stringify(r.first)); delete miss[L.items[0].id];
      ok(/lantai/.test((await one('select game.dn_check_susun($1, $2) e', [L, miss])).e), 'peti belum ditaruh ditolak: ' + k);
    } else {
      const rows = {}; L.rows.forEach(rw => { rows[rw.id] = rw; });
      MANI[k] = L.crates.filter(c => c.qty !== rows[c.row].qty || c.cap !== rows[c.row].cap || c.berat !== rows[c.row].berat).map(c => c.id);
      ok(MANI[k].length === 3, 'manifest ' + k + ': 3 peti tidak cocok');
      ok(MANI[k].every(id => L.crates.find(c => c.id === id).jt), 'peti tidak cocok bercap J.T.');
      ok((await one('select game.dn_check_manifest($1, $2) e', [L, MANI[k]])).e === null, 'manifest benar diterima: ' + k);
      ok((await one('select game.dn_check_manifest($1, $2) e', [L, MANI[k].slice(0, 2)])).e, 'manifest kurang ditolak: ' + k);
      ok((await one('select game.dn_check_manifest($1, $2) e', [L, MANI[k].concat([L.crates.find(c => !c.jt).id])])).e, 'manifest kelebihan ditolak: ' + k);
    }
  }
  // aturan khusus (dengan level kecil buatan)
  const T = { w: 3, h: 2, rules: ['berat', 'basah', 'rapuh', 'besok'], items: [
    { id: 'k', shape: [[0, 0]], tags: ['kain'] }, { id: 'b', shape: [[0, 0]], tags: ['basah'] },
    { id: 'r', shape: [[0, 0]], tags: ['rapuh'] }, { id: 'z', shape: [[0, 0]], tags: ['besok'] }] };
  const chk = async (pl) => (await one('select game.dn_check_susun($1, $2) e', [T, pl])).e;
  ok(/basah/.test(await chk({ k: { x: 0, y: 0 }, b: { x: 0, y: 1 }, r: { x: 1, y: 0 }, z: { x: 2, y: 0 } })), 'basah di atas kain ditolak');
  ok(/rapuh/.test(await chk({ k: { x: 1, y: 1 }, b: { x: 0, y: 0 }, r: { x: 1, y: 0 }, z: { x: 2, y: 0 } })), 'rapuh ditindih ditolak');
  ok(/pintu/.test(await chk({ k: { x: 0, y: 0 }, b: { x: 2, y: 0 }, r: { x: 2, y: 1 }, z: { x: 1, y: 0 } })), 'keluar besok jauh dari pintu ditolak');
  ok(/melayang/.test(await chk({ k: { x: 0, y: 0 }, b: { x: 1, y: 1 }, r: { x: 2, y: 1 }, z: { x: 2, y: 0 } })), 'peti melayang ditolak');
  ok(/bertumpuk/.test(await chk({ k: { x: 0, y: 0 }, b: { x: 0, y: 0 }, r: { x: 1, y: 0 }, z: { x: 2, y: 0 } })), 'peti bertumpuk ditolak');
  ok((await chk({ k: { x: 0, y: 0 }, b: { x: 1, y: 0 }, r: { x: 0, y: 1 }, z: { x: 2, y: 0 } })) === null, 'susunan benar diterima');
  ok(SOL.check(T, { k: { x: 0, y: 0 }, b: { x: 1, y: 0 }, r: { x: 0, y: 1 }, z: { x: 2, y: 0 } }).ok, 'solver & server sepakat');
  // putaran: 3x1 berat diputar tegak = melanggar berat; 2x1 diputar 90 = tegak
  const T2 = { w: 3, h: 3, rules: ['berat'], items: [{ id: 'u', shape: [[0, 0], [1, 0], [2, 0]], tags: ['berat'] }] };
  ok((await one('select game.dn_check_susun($1, $2) e', [T2, { u: { x: 0, y: 0, r: 0 } }])).e === null, 'ulin datar diterima');
  ok(/berat/.test((await one('select game.dn_check_susun($1, $2) e', [T2, { u: { x: 0, y: 0, r: 1 } }])).e), 'ulin tegak ditolak');
  ok(!SOL.check(T2, { u: { x: 0, y: 0, r: 1 } }).ok, 'solver juga menolak ulin tegak');

  // ------------------------------------------------------------------ gerbang Saga 2
  const A = await mk('Kapten Kuli', 'dn_a', false);
  ok((await A.call('api_getGameState', [null])).duneks === null, 'belum Saga 2: state null');
  await H.expectError(() => A.call('api_duneks', ['maju', 0, SOLN.sunda]), /sibuk/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'duatangan', 5)`, [A.id]);
  let s = await A.call('api_getGameState', [null]);
  ok(s.duneks && s.duneks.step === 0 && s.duneks.done === false && s.duneks.frozen === false, 'terbuka: ' + JSON.stringify(s.duneks));
  ok(Object.keys(s.duneks).sort().join() === 'done,frozen,step', 'state tidak membocorkan apa pun');

  // ------------------------------------------------------------------ level hanya untuk langkah sekarang
  let r = await A.call('api_duneks', ['level', 0]);
  ok(r.level && r.level.mode === 'susun' && r.level.w === LV.sunda.w, 'level langkah 0');
  await H.expectError(() => A.call('api_duneks', ['level', 4]), /sibuk/);

  // ------------------------------------------------------------------ jalan 7 langkah
  await siang();
  await ke(A, 'joungjava');
  await H.expectError(() => A.call('api_duneks', ['maju', 0, SOLN.sunda]), /sibuk/);
  await ke(A, 'sunda_empire');
  await H.expectError(() => A.call('api_duneks', ['maju', 1, 'ok']), /bergeser/);
  await H.expectError(() => A.call('api_duneks', ['maju', 0, 'ok']), /Belum rapi/);
  await H.expectError(() => A.call('api_duneks', ['maju', 0, {}]), /Belum rapi/);
  r = await A.call('api_duneks', ['maju', 0, SOLN.sunda]);
  ok(r.duneks.step === 1, 'langkah 0 (Sunda, susun)');
  await H.expectError(() => A.call('api_duneks', ['maju', 0, SOLN.sunda]), /bergeser/);
  await H.sql(`update game.player_location set destination_city_id = 'joungjava', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_duneks', ['maju', 1, 'ok']), /Merapat/);

  const logs0 = Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n);
  const chat0 = Number((await one(`select count(*) n from game.mp_chat`)).n);
  const run = async (u, i) => {
    const d = STEPS[i];
    await ke(u, d.c);
    if (d.t === 'malam') { await siang(); await H.expectError(() => u.call('api_duneks', ['maju', i, 'ok']), /lampu/); await malam(); }
    else await siang();
    const res = d.g === 'susun' ? SOLN[d.lv] : d.g === 'manifest' ? MANI[d.lv] : 'ok';
    if (d.g === 'syahbandar' || d.g === 'pesta') await H.expectError(() => u.call('api_duneks', ['maju', i, 'gagal']), /Belum berhasil/);
    if (d.g === 'manifest') await H.expectError(() => u.call('api_duneks', ['maju', i, res.slice(1)]), /Belum rapi/);
    return u.call('api_duneks', ['maju', i, res]);
  };
  for (let i = 1; i < 7; i++) { r = await run(A, i); ok(r.duneks.step === i + 1, 'langkah ' + i + ' maju'); }
  await H.expectError(() => A.call('api_duneks', ['maju', 7, 'ok']), /jawabanmu/);
  await H.expectError(() => A.call('api_duneks', ['pilih', 7, 'mungkin']), /jawabanmu/);

  // ------------------------------------------------------------------ pilih: urutan 1 = 10 jt
  const p0 = await pool(), g0 = await gold(A);
  r = await A.call('api_duneks', ['pilih', 7, 'setuju']);
  ok(r.choice === 'setuju' && r.amount === 10000000 && r.duneks.done === true && r.duneks.jalur === 'setuju', 'urutan 1: 10 jt ' + JSON.stringify(r));
  ok(await pool() === p0 + 10000000, 'masuk kolam');
  ok(await mine(A) === 10000000, 'masuk total pribadi');
  ok(await gold(A) === g0, 'gold pemain tidak berubah');
  ok(r.gotong && r.gotong.ikn && r.gotong.ikn.kat === 2, 'kategori Restorasi naik (Tanda Jasa Restorasi biasa)');
  ok(Number((await one(`select game.kd_qty($1, 'aura_lentera_ikn') q`, [A.id])).q) === 1, 'Lentera IKN diberikan');
  await H.expectError(() => A.call('api_duneks', ['pilih', 7, 'setuju']), /sibuk/);
  ok(Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n) === logs0, 'tidak ada log pemain');
  const chats = await H.sql(`select msg from game.mp_chat order by id`);
  ok(!chats.slice(chat0).some(c => /menyumbang|duneks|gudang|Bi Onah/i.test(JSON.stringify(c.msg))), 'tidak ada chat "menyumbang N gold" atau quest');
  ok((await H.sql(`select 1 from realtime.sent where payload::text ilike '%duneks%'`)).length === 0, 'tidak ada Realtime quest');
  const meta = await one('select meta from game.players where player_id = $1', [A.id]);
  ok(!/duneks|gudang/i.test(JSON.stringify(meta.meta || {})), 'tidak ada Tanda Jasa khusus quest');
  s = await A.call('api_getGameState', [null]);
  ok(s.duneks.done === true && !('amount' in s.duneks) && !('rank' in s.duneks), 'state tamat tanpa angka/urutan');

  // ------------------------------------------------------------------ side quest satu per satu (dua arah)
  const B = await mk('Kapten Kopi', 'dn_b');
  await ke(B, 'gading_island'); await siang();
  await B.call('api_peregrin', ['maju', 0]);                                   // felyx duluan
  ok((await B.call('api_getGameState', [null])).duneks === null, 'felyx berjalan: TheDuneks tertahan');
  await ke(B, 'sunda_empire');
  await H.expectError(() => B.call('api_duneks', ['maju', 0, SOLN.sunda]), /sibuk/);
  await H.sql(`select game.admin_peregrin('dn_b', 30)`);                     // felyx tamat
  ok((await B.call('api_getGameState', [null])).duneks.step === 0, 'felyx tamat: TheDuneks bisa terpicu');
  const C = await mk('Kapten Gudang', 'dn_c');
  await ke(C, 'sunda_empire'); await siang();
  await C.call('api_duneks', ['maju', 0, SOLN.sunda]);                         // TheDuneks duluan
  ok((await C.call('api_getGameState', [null])).peregrin === null, 'TheDuneks berjalan: felyx tertahan');
  await ke(C, 'gading_island');
  await H.expectError(() => C.call('api_peregrin', ['maju', 0]), /Tidak ada yang perlu/);

  // ------------------------------------------------------------------ urutan 2..7, tolak tidak memakai urutan, GM tidak memakai urutan
  const amounts = [];
  const toEnd = async (u, uname) => {
    await H.sql(`select game.admin_duneks($1, 7)`, [uname]);
    await ke(u, 'ikn');
  };
  // tolak: +25.000, urutan tidak terpakai
  await toEnd(B, 'dn_b');
  const gb = await gold(B), pb = await pool();
  r = await B.call('api_duneks', ['pilih', 7, 'tolak']);
  ok(r.choice === 'tolak' && r.gold === 25000 && await gold(B) === gb + 25000 && await pool() === pb, 'tolak: +25.000, kolam tetap');
  ok(r.duneks.jalur === 'tolak' && await mine(B) === 0, 'tolak: tidak menyumbang');
  // GM
  await cfg('GmUsernames', 'dn_gm');
  const GM = await mk('Kapten GM', 'dn_gm');
  await toEnd(GM, 'dn_gm');
  const pg = await pool();
  r = await GM.call('api_duneks', ['pilih', 7, 'setuju']);
  ok(r.uji === true && r.amount === 8000000 && await pool() === pg && await mine(GM) === 0, 'GM: uji, urutan & kolam tidak tersentuh');
  ok(!(await one('select 1 x from game.dn_rank where player_id = $1', [GM.id])), 'GM tidak tercatat di urutan');
  // urutan 2..7
  for (let i = 2; i <= 7; i++) {
    const u = await mk('Kapten ' + i, 'dn_r' + i);
    await toEnd(u, 'dn_r' + i);
    r = await u.call('api_duneks', ['pilih', 7, 'setuju']);
    amounts.push(r.amount);
  }
  ok(amounts.join() === [8e6, 6e6, 4e6, 3e6, 2e6, 2e6].join(), 'urutan 2..7: ' + amounts.join());
  const ranks = await H.sql(`select rank from game.dn_rank where rank is not null order by rank`);
  ok(ranks.map(x => x.rank).join() === '1,2,3,4,5,6,7', 'urutan unik & berurutan');

  // ------------------------------------------------------------------ total pribadi menumpuk dengan sumbangan sendiri
  const D = await mk('Kapten Dermawan', 'dn_d');
  await H.sql(`insert into game.gr_donations(project_id, player_id, gold, total, n) values ('ikn', $1, 1000000, 1000000, 1)`, [D.id]);
  await toEnd(D, 'dn_d');
  r = await D.call('api_duneks', ['pilih', 7, 'setuju']);
  ok(r.amount === 2000000 && await mine(D) === 3000000, 'sudah 1 jt + 2 jt = 3 jt');

  // ------------------------------------------------------------------ penembus 100 jt: Saga 3 terpicu, quest tamat di transaksi yang sama
  ok(!(await one(`select game.world_flag('saga3') f`)).f, 'Saga 3 belum terpicu');
  await H.sql(`update game.gr_projects set total = 99000000, stage = 4 where id = 'ikn'`);
  await cfg('PasirOpen', '1');
  const E = await mk('Kapten Penembus', 'dn_e');
  await toEnd(E, 'dn_e');
  r = await E.call('api_duneks', ['pilih', 7, 'setuju']);
  ok(r.choice === 'setuju' && r.duneks.done === true, 'penembus: quest tamat');
  ok((await one(`select game.world_flag('saga3') f`)).f, 'Saga 3 terpicu');
  ok((await one(`select done_at from game.gr_projects where id = 'ikn'`)).done_at, 'Restorasi IKN selesai');
  const stageChat = await H.sql(`select msg from game.mp_chat where msg::text ilike '%Menara Cahaya%'`);
  ok(stageChat.length === 1 && /Kapten Kapten Penembus/.test(JSON.stringify(stageChat[0].msg)), 'pengumuman tahap atas nama kapten');
  s = await E.call('api_getGameState', [null]);
  ok(s.duneks.done === true && s.duneks.frozen === true, 'tamat walau langsung dibekukan Saga 3');

  // ------------------------------------------------------------------ kolam penuh -> Kamp Pemulung (tanpa urutan); tolak tetap 25.000
  await cfg('PasirOpen', '0');
  const F = await mk('Kapten Kamp', 'dn_f');
  await toEnd(F, 'dn_f');
  const pf = await pool(), maxRank = (await one('select max(rank) m from game.dn_rank')).m;
  r = await F.call('api_duneks', ['pilih', 7, 'setuju']);
  ok(r.choice === 'kamp' && r.amount === 0 && await pool() === pf && (await one('select max(rank) m from game.dn_rank')).m === maxRank, 'kolam penuh: Kamp Pemulung, tanpa urutan');
  const G = await mk('Kapten Tolak', 'dn_g');
  await toEnd(G, 'dn_g');
  const gg = await gold(G);
  r = await G.call('api_duneks', ['pilih', 7, 'tolak']);
  ok(r.gold === 25000 && await gold(G) === gg + 25000, 'kolam penuh: tolak tetap 25.000');

  // ------------------------------------------------------------------ Balai Kongsi tetap atas nama Ki Dorus
  await H.sql(`update game.gr_projects set total = 30000000, stage = 2, done_at = null where id = 'ikn'`);
  await H.sql(`select game.kongsi_gr_pool(6000000)`);
  const kc = await H.sql(`select msg from game.mp_chat where msg::text ilike '%Dermaga Ulin%' order by id desc limit 1`);
  ok(kc.length && /Ki Dorus, Balai Kongsi/.test(JSON.stringify(kc[0].msg)), 'Balai Kongsi tetap atas nama Ki Dorus');

  // ------------------------------------------------------------------ pembekuan Saga 3 di tengah quest
  const P = await mk('Kapten Beku', 'dn_p');
  await ke(P, 'sunda_empire'); await siang();
  await P.call('api_duneks', ['maju', 0, SOLN.sunda]);
  await cfg('PasirOpen', '1');
  s = await P.call('api_getGameState', [null]);
  ok(s.duneks.frozen === true, 'Saga 3 aktif: dibekukan');
  await ke(P, 'joungjava');
  await H.expectError(() => P.call('api_duneks', ['maju', 1, 'ok']), /sibuk/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'ps14', 6) on conflict (player_id, quest_id) do update set step = 6`, [P.id]);
  r = await P.call('api_duneks', ['maju', 1, 'ok']);
  ok(r.duneks.step === 2, 'Saga 3 tamat: lanjut lagi');

  console.log('DUNEKS TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
