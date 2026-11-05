// Quest rahasia "Bunga yang Tak Pernah Dipetik" (Rekening J.T.): gerbang Saga 2, side quest satu per satu (dua arah),
// 9 langkah + pilihan, kota, malam, idempoten, Meja Kas A/B & Buku Besar diperiksa server (solver), jalur "Tedsky lupa"
// dikunci di langkah 6, gema Saga 3, sumbangan bertingkat dengan urutan sendiri (terpisah dari TheDuneks),
// GM tidak memakai urutan, tolak 250.000, kolam penuh -> Kamp Pemulung, penembus 100 jt tamat dalam satu transaksi,
// rahasia (tanpa log/TJ/chat khusus), dibekukan selama Saga 3.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const SOL = require('./jtq-solver');
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
  const mk = async (name, uname, saga2 = true, fate) => {
    const u = await H.user(uname); await u.call('api_createCharacter', [name, 'merchant']);
    if (saga2) await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'duatangan', 5, $2)`, [u.id, fate ? { fate } : {}]);
    return u;
  };
  const STEPS = (await one('select game.jt_steps() s')).s;
  const LV = (await one('select game.jt_levels() l')).l;
  ok(STEPS.length === 10, '10 langkah: ' + STEPS.length);
  ok((await one('select game.jt_last() v')).v === 10, 'jt_last 10');
  ok((await one(`select game.side_quest_ids() v`)).v.join() === 'peregrin,duneks,jtq', 'jtq terdaftar sebagai side quest');
  ok((await one(`select value v from game.config where key = 'JtqUpah'`)).v === '250000', 'upah tolak 250.000');
  ok((await one(`select value v from game.config where key = 'JtqTiers'`)).v === '5000000,4000000,3000000,2000000,500000', 'tingkat 5/4/3/2 jt + 500 rb');
  await cfg('GotongOpen', '1');

  // ------------------------------------------------------------------ level: semua bisa diselesaikan, server = solver
  const ANS = {};
  for (const k of Object.keys(LV)) {
    const L = LV[k];
    if (L.mode === 'kas') {
      const ans = [];
      L.rounds.forEach((R, i) => {
        const min = SOL.kasRound(L.kinds, R);
        ok(min !== null, 'kas ' + k + ' ronde ' + i + ' bisa dibayar pas');
        if (R.min != null) ok(R.min === min, 'kas ' + k + ' ronde ' + i + ': par = minimum sebenarnya (' + R.min + ' vs ' + min + ')');
        ok(Object.keys(R.cracked || {}).every(id => L.kinds.some(x => x.id === id)), 'koin retak dikenal: ' + k);
        ans.push(SOL.kasAnswer(L.kinds, R));
      });
      ANS[k] = ans;
      ok((await one('select game.jt_check_kas($1, $2) e', [L, ans])).e === null, 'server menerima jawaban solver: ' + k);
      // lebih/kurang, stok berlebih, koin asing, ronde kurang
      const bad1 = JSON.parse(JSON.stringify(ans)); const t0 = bad1[0][0]; const kk = Object.keys(t0)[0]; t0[kk] += 1;
      ok(/pas/.test((await one('select game.jt_check_kas($1, $2) e', [L, bad1])).e), 'jumlah tidak pas ditolak: ' + k);
      ok((await one('select game.jt_check_kas($1, $2) e', [L, ans.slice(1)])).e, 'ronde kurang ditolak: ' + k);
      const bad2 = JSON.parse(JSON.stringify(ans)); bad2[0][0] = { emas: 1 };
      ok(/tidak dikenal/.test((await one('select game.jt_check_kas($1, $2) e', [L, bad2])).e), 'koin asing ditolak: ' + k);
      const bad3 = JSON.parse(JSON.stringify(ans)); bad3[0][0] = { kepeng: L.rounds[0].trays[0] };
      ok((await one('select game.jt_check_kas($1, $2) e', [L, bad3])).e, 'stok laci dilampaui ditolak: ' + k);
      ok((await one('select game.jt_check_kas($1, $2) e', [L, '"ok"'])).e, '"ok" ditolak: ' + k);
    } else if (L.mode === 'timbang') {
      ok(SOL.solvable(L.n, L.odd.length, L.max), 'timbang ' + k + ' bisa diselesaikan dengan strategi adaptif');
      const sol = SOL.play(L.n, L.odd.length, L.max, L.odd);
      ANS[k] = sol;
      ok((await one('select game.jt_check_timbang($1, $2) e', [L, sol])).e === null, 'server menerima jawaban solver: ' + k);
      ok(/Bukan/.test((await one('select game.jt_check_timbang($1, $2) e', [L, { w: sol.w, pick: L.odd.length === 1 ? ['c1'] : ['c1', 'c2'] }])).e), 'tunjuk salah ditolak: ' + k);
      ok(/beruntung/.test((await one('select game.jt_check_timbang($1, $2) e', [L, { w: [], pick: L.odd }])).e), 'tebakan tanpa timbang ditolak: ' + k);
      ok(/Lilin/.test((await one('select game.jt_check_timbang($1, $2) e', [L, { w: sol.w.concat(sol.w).concat(sol.w), pick: L.odd }])).e), 'melebihi batas timbang ditolak: ' + k);
      ok(/sama banyak/.test((await one('select game.jt_check_timbang($1, $2) e', [L, { w: [{ l: ['c1', 'c2'], r: ['c3'] }], pick: L.odd }])).e), 'piring tak seimbang ditolak: ' + k);
      ok(/satu piring/.test((await one('select game.jt_check_timbang($1, $2) e', [L, { w: [{ l: ['c1'], r: ['c1'] }], pick: L.odd }])).e), 'koin di dua piring ditolak: ' + k);
      ok((await one('select game.jt_check_timbang($1, $2) e', [L, '"ok"'])).e, '"ok" ditolak: ' + k);
    } else {
      const rows = {}; L.rows.forEach(rw => { rows[rw.id] = rw; });
      ANS[k] = L.crates.filter(c => c.qty !== rows[c.row].qty || c.cap !== rows[c.row].cap || c.berat !== rows[c.row].berat).map(c => c.id);
      ok(ANS[k].length === 3 && ANS[k].every(id => L.crates.find(c => c.id === id).jt), 'Buku Besar: 3 slip tidak cocok, semuanya slip kadet');
      ok((await one('select game.dn_check_manifest($1, $2) e', [L, ANS[k]])).e === null, 'Buku Besar benar diterima');
      ok((await one('select game.dn_check_manifest($1, $2) e', [L, ANS[k].slice(1)])).e, 'Buku Besar kurang ditolak');
    }
  }
  // tebakan beruntung pada level 2 koin berat (satu timbangan saja)
  ok(/beruntung/.test((await one('select game.jt_check_timbang($1, $2) e', [LV.l5, { w: [ANS.l5.w[0]], pick: LV.l5.odd }])).e), 'satu timbangan belum cukup untuk 2 koin berat');

  const answer = (d) => d.g === 'kas' || d.g === 'timbang' || d.g === 'manifest' ? ANS[d.lv] : 'ok';

  // ------------------------------------------------------------------ gerbang Saga 2
  const A = await mk('Kapten Kas', 'jt_a', false);
  ok((await A.call('api_getGameState', [null])).jtq === null, 'belum Saga 2: state null');
  await H.expectError(() => A.call('api_jtq', ['maju', 0, ANS.l0]), /sibuk/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'duatangan', 5, '{"fate":"ikn"}')`, [A.id]);
  let s = await A.call('api_getGameState', [null]);
  ok(s.jtq && s.jtq.step === 0 && s.jtq.done === false && s.jtq.frozen === false, 'terbuka: ' + JSON.stringify(s.jtq));
  ok(Object.keys(s.jtq).sort().join() === 'done,frozen,jalur,saga3,step', 'state tidak membocorkan angka/hadiah: ' + Object.keys(s.jtq));
  ok(s.jtq.jalur === 'ikn' && s.jtq.saga3 === false, 'jalur dari nasib Tedsky (ikn), belum tamat Saga 3');

  // ------------------------------------------------------------------ level hanya untuk langkah sekarang
  let r = await A.call('api_jtq', ['level', 0]);
  ok(r.level && r.level.mode === 'kas' && r.level.rounds.length === 3, 'level langkah 0');
  await H.expectError(() => A.call('api_jtq', ['level', 2]), /sibuk/);
  await H.expectError(() => A.call('api_jtq', ['level', 1]), /sibuk/);   // langkah cerita tanpa level

  // ------------------------------------------------------------------ jalan 9 langkah
  await siang();
  await ke(A, 'joungjava');
  await H.expectError(() => A.call('api_jtq', ['maju', 0, ANS.l0]), /sibuk/);
  await ke(A, 'marie_regal');
  await H.expectError(() => A.call('api_jtq', ['maju', 1, 'ok']), /bergeser/);
  await H.expectError(() => A.call('api_jtq', ['maju', 0, 'ok']), /Belum pas/);
  r = await A.call('api_jtq', ['maju', 0, ANS.l0]);
  ok(r.jtq.step === 1, 'langkah 0 (Marie Regal, Meja Kas B)');
  await H.expectError(() => A.call('api_jtq', ['maju', 0, ANS.l0]), /bergeser/);
  await H.sql(`update game.player_location set destination_city_id = 'empeer_depeer', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_jtq', ['maju', 1, 'ok']), /Merapat/);

  const logs0 = Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n);
  const chat0 = Number((await one(`select count(*) n from game.mp_chat`)).n);
  const run = async (u, i) => {
    const d = STEPS[i];
    await ke(u, d.c);
    if (d.t === 'malam') { await siang(); await H.expectError(() => u.call('api_jtq', ['maju', i, answer(d)]), /lampu/); await malam(); }
    else await siang();
    if (d.g === 'jejak') await H.expectError(() => u.call('api_jtq', ['maju', i, 'gagal']), /Belum berhasil/);
    if (d.g === 'timbang') await H.expectError(() => u.call('api_jtq', ['maju', i, { w: [], pick: LV[d.lv].odd }]), /Belum pasti/);
    if (d.g === 'manifest') await H.expectError(() => u.call('api_jtq', ['maju', i, ANS[d.lv].slice(1)]), /Belum cocok/);
    return u.call('api_jtq', ['maju', i, answer(d)]);
  };
  for (let i = 1; i < 9; i++) {
    // jalur dikunci di langkah 6: ganti nasib Tedsky setelahnya tidak mengubah apa pun
    r = await run(A, i);
    ok(r.jtq.step === i + 1, 'langkah ' + i + ' maju');
    if (i === 6) {
      await H.sql(`update game.player_quests set data = '{"fate":"dewan"}' where player_id = $1 and quest_id = 'duatangan'`, [A.id]);
      ok((await A.call('api_jtq', ['status'])).jtq.jalur === 'ikn', 'jalur terkunci di langkah 6');
    }
  }
  const dA = (await one(`select data from game.player_quests where player_id = $1 and quest_id = 'jtq'`, [A.id])).data;
  ok(dA.jalur === 'ikn' && dA.lupa === true, 'data jalur & lupa tersimpan');
  await H.expectError(() => A.call('api_jtq', ['maju', 9, 'ok']), /keputusanmu/);
  await H.expectError(() => A.call('api_jtq', ['pilih', 9, 'mungkin']), /keputusanmu/);
  await ke(A, 'sunda_empire');
  await H.expectError(() => A.call('api_jtq', ['pilih', 9, 'setuju']), /sibuk/);
  await ke(A, 'ikn');

  // ------------------------------------------------------------------ pilih: urutan 1 = 5 jt
  const p0 = await pool(), g0 = await gold(A);
  r = await A.call('api_jtq', ['pilih', 9, 'setuju']);
  ok(r.choice === 'setuju' && r.amount === 5000000 && r.jtq.done === true && r.jtq.pilihan === 'setuju', 'urutan 1: 5 jt ' + JSON.stringify(r));
  ok(await pool() === p0 + 5000000, 'masuk kolam');
  ok(await mine(A) === 5000000, 'masuk total pribadi');
  ok(Number((await one(`select jtq from game.gr_donations where project_id = 'ikn' and player_id = $1`, [A.id])).jtq) === 5000000, 'kolom audit jtq');
  ok(await gold(A) === g0, 'gold pemain tidak berubah');
  ok(r.gotong && r.gotong.ikn && r.gotong.ikn.kat >= 1, 'kategori Restorasi naik (Tanda Jasa Restorasi biasa)');
  await H.expectError(() => A.call('api_jtq', ['pilih', 9, 'setuju']), /sibuk/);
  ok(Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n) === logs0, 'tidak ada log pemain');
  const chats = await H.sql(`select msg from game.mp_chat order by id`);
  ok(!chats.slice(chat0).some(c => /menyumbang|jtq|rekening|J\.T\./i.test(JSON.stringify(c.msg))), 'tidak ada chat "menyumbang N gold" atau quest');
  ok((await H.sql(`select 1 from realtime.sent where payload::text ilike '%jtq%'`)).length === 0, 'tidak ada Realtime quest');
  const meta = await one('select meta from game.players where player_id = $1', [A.id]);
  ok(!/jtq|rekening/i.test(JSON.stringify(meta.meta || {})), 'tidak ada Tanda Jasa khusus quest');
  s = await A.call('api_getGameState', [null]);
  ok(s.jtq.done === true && !('amount' in s.jtq) && !('rank' in s.jtq), 'state tamat tanpa angka/urutan');

  // ------------------------------------------------------------------ jalur dewan: nasib kosong / dewan
  const J = await mk('Kapten Lonceng', 'jt_j', true);
  ok((await J.call('api_getGameState', [null])).jtq.jalur === 'dewan', 'nasib kosong -> jalur dewan');

  // ------------------------------------------------------------------ side quest satu per satu (dua arah, dengan TheDuneks)
  const B = await mk('Kapten Gudang', 'jt_b');
  await ke(B, 'sunda_empire'); await siang();
  const DN = (await one('select game.dn_levels() l')).l;
  const DS = require('./duneks-solver');
  await B.call('api_duneks', ['maju', 0, DS.solve(DN.sunda, 1).first]);       // TheDuneks duluan
  ok((await B.call('api_getGameState', [null])).jtq === null, 'TheDuneks berjalan: Rekening J.T. tertahan');
  await ke(B, 'marie_regal');
  await H.expectError(() => B.call('api_jtq', ['maju', 0, ANS.l0]), /sibuk/);
  await H.sql(`select game.admin_duneks('jt_b', 8)`);                         // TheDuneks tamat
  ok((await B.call('api_getGameState', [null])).jtq.step === 0, 'TheDuneks tamat: Rekening J.T. bisa terpicu');
  const C = await mk('Kapten Bank', 'jt_c');
  await ke(C, 'marie_regal'); await siang();
  await C.call('api_jtq', ['maju', 0, ANS.l0]);                                // Rekening J.T. duluan
  ok((await C.call('api_getGameState', [null])).duneks === null, 'Rekening J.T. berjalan: TheDuneks tertahan');
  ok((await C.call('api_getGameState', [null])).peregrin === null, 'Rekening J.T. berjalan: felyx tertahan');
  await ke(C, 'sunda_empire');
  await H.expectError(() => C.call('api_duneks', ['maju', 0, DS.solve(DN.sunda, 1).first]), /sibuk/);

  // ------------------------------------------------------------------ urutan sendiri (TheDuneks tidak memengaruhi), tolak, GM
  await H.sql(`insert into game.dn_rank(player_id, rank, choice, amount) select player_id, 50, 'setuju', 1 from game.players where username = 'jt_j'`);
  const toEnd = async (u, uname) => { await H.sql(`select game.admin_jtq($1, 9)`, [uname]); await ke(u, 'ikn'); };
  // tolak: +250.000, urutan tidak terpakai
  await toEnd(B, 'jt_b');
  const gb = await gold(B), pb = await pool();
  r = await B.call('api_jtq', ['pilih', 9, 'tolak']);
  ok(r.choice === 'tolak' && r.gold === 250000 && await gold(B) === gb + 250000 && await pool() === pb, 'tolak: +250.000, kolam tetap');
  ok(r.jtq.pilihan === 'tolak' && await mine(B) === 0, 'tolak: tidak menyumbang');
  // GM
  await cfg('GmUsernames', 'jt_gm');
  const GM = await mk('Kapten GM', 'jt_gm');
  await toEnd(GM, 'jt_gm');
  const pg = await pool();
  r = await GM.call('api_jtq', ['pilih', 9, 'setuju']);
  ok(r.uji === true && r.amount === 4000000 && await pool() === pg && await mine(GM) === 0, 'GM: uji, urutan & kolam tidak tersentuh');
  ok(!(await one('select 1 x from game.jtq_rank where player_id = $1', [GM.id])), 'GM tidak tercatat di urutan');
  const amounts = [];
  for (let i = 2; i <= 6; i++) {
    const u = await mk('Kapten ' + i, 'jt_r' + i);
    await toEnd(u, 'jt_r' + i);
    r = await u.call('api_jtq', ['pilih', 9, 'setuju']);
    amounts.push(r.amount);
  }
  ok(amounts.join() === [4e6, 3e6, 2e6, 5e5, 5e5].join(), 'urutan 2..6 (terpisah dari TheDuneks): ' + amounts.join());
  const ranks = await H.sql(`select rank from game.jtq_rank where rank is not null order by rank`);
  ok(ranks.map(x => x.rank).join() === '1,2,3,4,5,6', 'urutan unik & berurutan');

  // ------------------------------------------------------------------ penembus 100 jt: Saga 3 terpicu, quest tamat di transaksi yang sama
  ok(!(await one(`select game.world_flag('saga3') f`)).f, 'Saga 3 belum terpicu');
  await H.sql(`update game.gr_projects set total = 99800000, stage = 4 where id = 'ikn'`);
  await cfg('PasirOpen', '1');
  const E = await mk('Kapten Penembus', 'jt_e');
  await toEnd(E, 'jt_e');
  r = await E.call('api_jtq', ['pilih', 9, 'setuju']);
  ok(r.choice === 'setuju' && r.amount === 500000 && r.jtq.done === true, 'penembus: quest tamat');
  ok((await one(`select game.world_flag('saga3') f`)).f, 'Saga 3 terpicu');
  s = await E.call('api_getGameState', [null]);
  ok(s.jtq.done === true && s.jtq.frozen === true, 'tamat walau langsung dibekukan Saga 3');

  // ------------------------------------------------------------------ kolam penuh -> Kamp Pemulung (tanpa urutan); tolak tetap 250.000
  await cfg('PasirOpen', '0');
  const F = await mk('Kapten Kamp', 'jt_f');
  await toEnd(F, 'jt_f');
  const pf = await pool(), maxRank = (await one('select max(rank) m from game.jtq_rank')).m;
  r = await F.call('api_jtq', ['pilih', 9, 'setuju']);
  ok(r.choice === 'kamp' && r.amount === 0 && await pool() === pf && (await one('select max(rank) m from game.jtq_rank')).m === maxRank, 'kolam penuh: Kamp Pemulung, tanpa urutan');
  ok(r.jtq.pilihan === 'kamp', 'pilihan kamp tercatat');
  const G = await mk('Kapten Tolak', 'jt_g');
  await toEnd(G, 'jt_g');
  const gg = await gold(G);
  r = await G.call('api_jtq', ['pilih', 9, 'tolak']);
  ok(r.gold === 250000 && await gold(G) === gg + 250000, 'kolam penuh: tolak tetap 250.000');

  // ------------------------------------------------------------------ pembekuan Saga 3 di tengah quest + gema Saga 3
  await H.sql(`update game.gr_projects set total = 30000000, stage = 2, done_at = null where id = 'ikn'`);
  const P = await mk('Kapten Beku', 'jt_p');
  await ke(P, 'marie_regal'); await siang();
  await P.call('api_jtq', ['maju', 0, ANS.l0]);
  await cfg('PasirOpen', '1');
  s = await P.call('api_getGameState', [null]);
  ok(s.jtq.frozen === true, 'Saga 3 aktif: dibekukan');
  await ke(P, 'empeer_depeer');
  await H.expectError(() => P.call('api_jtq', ['maju', 1, 'ok']), /sibuk/);
  await H.expectError(() => P.call('api_jtq', ['level', 1]), /sibuk/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'ps14', 6) on conflict (player_id, quest_id) do update set step = 6`, [P.id]);
  r = await P.call('api_jtq', ['maju', 1, 'ok']);
  ok(r.jtq.step === 2 && r.jtq.saga3 === true, 'Saga 3 tamat: lanjut lagi, gema Saga 3 aktif');

  // ------------------------------------------------------------------ alat GM
  const st = await one(`select game.admin_jtq('jt_p', 3) s`);
  ok(st.s.step === 3 && st.s.done === false, 'admin_jtq menyetel langkah');

  console.log('JTQ TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
