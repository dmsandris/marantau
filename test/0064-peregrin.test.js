// Quest rahasia "Mesin yang Hanyut" (Lorang Peregrin): gerbang Saga 2, 30 langkah, kota, malam/fajar,
// mini game, barter, palka, idempoten, pembekuan Saga 3, hadiah, rahasia (tanpa log/TJ/chat).
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const cfg = (k, v) => H.sql(`insert into game.config(key, value) values ($1, $2) on conflict (key) do update set value = excluded.value`, [k, v]);
  const lenMs = async () => Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) * 60000 v`)).v);
  const setFrac = async (f) => { const L = await lenMs(); const now = Number((await one('select game.now_ms() v')).v); await cfg('WorldStartTimestamp', String(Math.round(now - f * L - 2000))); };
  const siang = () => setFrac(0.4), malam = () => setFrac(0.8), fajar = () => setFrac(0.95);
  const ke = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null where player_id = $1`, [u.id, c]);
  const qty = async (u, it) => Number((await one('select game.item_qty($1, $2) q', [u.id, it])).q);
  const gold = async (u) => Number((await one('select gold g from game.players where player_id = $1', [u.id])).g);
  const free = async (u) => Number((await one('select game.cargo_free($1) f', [u.id])).f);
  const mk = async (name, uname) => { const u = await H.user(uname); await u.call('api_createCharacter', [name, 'merchant']); return u; };
  const STEPS = (await one('select game.pg_steps() s')).s;
  ok(STEPS.length === 30, '30 langkah: ' + STEPS.length);

  // ------------------------------------------------------------------ gerbang Saga 2
  const A = await mk('Kapten Kopi', 'pg_a');
  let s = await A.call('api_getGameState', [null]);
  ok(s.peregrin === null, 'belum selesai Saga 2: state null');
  await H.expectError(() => A.call('api_peregrin', ['maju', 0]), /Tidak ada yang perlu/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'duatangan', 5)`, [A.id]);
  s = await A.call('api_getGameState', [null]);
  ok(s.peregrin && s.peregrin.step === 0 && s.peregrin.done === false && s.peregrin.frozen === false, 'terbuka: ' + JSON.stringify(s.peregrin));
  ok(Object.keys(s.peregrin).sort().join() === 'done,frozen,step', 'state tidak membocorkan apa pun selain langkah');

  // ------------------------------------------------------------------ kota & idempoten
  await siang();
  await ke(A, 'sunda_empire');
  await H.expectError(() => A.call('api_peregrin', ['maju', 0]), /Tidak ada yang perlu/);
  await ke(A, 'gading_island');
  await H.expectError(() => A.call('api_peregrin', ['maju', 1]), /bergeser/);
  let r = await A.call('api_peregrin', ['maju', 0]);
  ok(r.peregrin.step === 1, 'langkah 0 di Stumpy');
  await H.expectError(() => A.call('api_peregrin', ['maju', 0]), /bergeser/);
  // berlayar = tidak bisa
  await H.sql(`update game.player_location set destination_city_id = 'marie_regal', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_peregrin', ['maju', 1]), /Merapat/);

  // ------------------------------------------------------------------ jalankan langkah satu per satu
  const logs0 = Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n);
  const run = async (i) => {
    const d = STEPS[i];
    await ke(A, d.c);
    if (d.t === 'malam') { await siang(); await H.expectError(() => A.call('api_peregrin', ['maju', i, 'ok']), /lampu/); await malam(); }
    else if (d.t === 'fajar') { await siang(); await H.expectError(() => A.call('api_peregrin', ['maju', i]), /fajar/); await fajar(); }
    else await siang();
    if (d.g) await H.expectError(() => A.call('api_peregrin', ['maju', i, 'gagal']), /Belum berhasil/);
    if (d.barter) {
      await H.expectError(() => A.call('api_peregrin', ['maju', i]), /Bawa 3/);
      await H.sql('select game.adjust_inventory($1, $2, $3)', [A.id, d.barter[0], d.barter[1]]);
    }
    return A.call('api_peregrin', ['maju', i, d.g ? 'ok' : '']);
  };
  for (let i = 1; i < 24; i++) {
    r = await run(i);
    ok(r.peregrin.step === i + 1, 'langkah ' + i + ' maju');
  }
  ok(await qty(A, 'qi_pg_hopper') === 1 && await qty(A, 'qi_pg_drum') === 1 && await qty(A, 'qi_pg_panel') === 1 &&
     await qty(A, 'qi_pg_cerobong') === 1 && await qty(A, 'qi_pg_burner') === 1 && await qty(A, 'qi_pg_nampan') === 1 &&
     await qty(A, 'qi_pg_rangka') === 1 && await qty(A, 'qi_pg_manual') === 1, '7 bagian + manual terkumpul');
  ok(await qty(A, 'tuak') === 0 && await qty(A, 'besi') === 0, 'barang barter diambil');

  // ------------------------------------------------------------------ aman dari Tony / kalah tempur / gudang
  await H.sql('select game.adjust_inventory($1, $2, 2)', [A.id, 'garam']);
  await H.sql('select game.voy_lose_cargo($1, 1.0)', [A.id]);
  ok(await qty(A, 'garam') === 0 && await qty(A, 'qi_pg_drum') === 1, 'kehilangan muatan hanya komoditas; bagian mesin aman');

  // langkah 24 butuh 7 bagian
  await H.sql(`select game.item_adjust($1, 'qi_pg_rangka', -1)`, [A.id]);
  await ke(A, 'freeyork');
  await H.expectError(() => A.call('api_peregrin', ['maju', 24]), /belum kau bawa/);
  await H.sql(`select game.item_adjust($1, 'qi_pg_rangka', 1)`, [A.id]);
  r = await A.call('api_peregrin', ['maju', 24]); ok(r.peregrin.step === 25, 'langkah 24');
  r = await run(25); ok(r.peregrin.step === 26 && await qty(A, 'qi_pg_kaca') === 1, 'kaca intip');

  // langkah 26: rakit -> palka penuh ditolak? (bagian yang diambil ikut dihitung: 22 ruang keluar, 15 masuk -> tidak butuh ruang)
  await ke(A, 'freeyork');
  const f0 = await free(A);
  r = await A.call('api_peregrin', ['maju', 26]);
  ok(r.peregrin.step === 27 && await qty(A, 'qi_pg_mesin') === 1 && await qty(A, 'qi_pg_drum') === 0 && await qty(A, 'qi_pg_kaca') === 0, 'mesin dirakit, bagian diambil');
  ok(await free(A) === f0 + 22 - 15, 'ruang palka: 22 keluar, 15 masuk');

  r = await run(27); ok(r.peregrin.step === 28, 'langkah 27');
  r = await run(28); ok(r.peregrin.step === 29, 'langkah 28 (fajar)');
  const g0 = await gold(A);
  r = await run(29);
  ok(r.peregrin.step === 30 && r.peregrin.done === true && r.gold === 25000 && await gold(A) === g0 + 25000, 'hadiah 25.000 gold');
  ok(await qty(A, 'qi_pg_mesin') === 0 && await qty(A, 'qi_pg_manual') === 0, 'mesin & manual diserahkan');
  await H.expectError(() => A.call('api_peregrin', ['maju', 30]), /Tidak ada yang perlu/);
  const done = await one(`select done_at from game.player_quests where player_id = $1 and quest_id = 'peregrin'`, [A.id]);
  ok(done.done_at, 'done_at terisi');

  // ------------------------------------------------------------------ rahasia
  ok(Number((await one('select count(*) n from game.player_log where player_id = $1', [A.id])).n) === logs0, 'tidak ada log pemain');
  const chat = await H.sql(`select 1 from game.mp_chat where msg::text ilike '%peregrin%' or msg::text ilike '%lorang%'`);
  ok(chat.length === 0, 'tidak ada chat dunia');
  const sent = await H.sql(`select 1 from realtime.sent where payload::text ilike '%peregrin%'`);
  ok(sent.length === 0, 'tidak ada siaran Realtime');
  const meta = await one('select meta from game.players where player_id = $1', [A.id]);
  ok(!/peregrin|lorang/i.test(JSON.stringify(meta.meta || {})), 'tidak menyentuh Tanda Jasa (meta)');

  // ------------------------------------------------------------------ palka penuh
  const B = await mk('Kapten Penuh', 'pg_b');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'duatangan', 5)`, [B.id]);
  await H.sql(`select game.admin_peregrin('pg_b', 6)`);
  ok(await qty(B, 'qi_pg_hopper') === 1, 'admin_peregrin mengisi bagian sebelumnya');
  const fb = await free(B);
  await H.sql('select game.adjust_inventory($1, $2, $3)', [B.id, 'garam', Math.floor(fb)]);
  await ke(B, 'freeyork'); await siang();
  await H.expectError(() => B.call('api_peregrin', ['maju', 6, 'ok']), /Kosongkan dulu palkamu/);
  ok((await B.call('api_getGameState', [null])).peregrin.step === 6, 'palka penuh: langkah tidak maju');
  await H.sql(`update game.inventory set qty = 0 where player_id = $1 and item_id = 'garam'`, [B.id]);
  r = await B.call('api_peregrin', ['maju', 6, 'ok']); ok(r.peregrin.step === 7, 'setelah palka dikosongkan');

  // ------------------------------------------------------------------ pembekuan Saga 3
  await cfg('PasirOpen', '1');
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);
  s = await B.call('api_getGameState', [null]);
  ok(s.peregrin.frozen === true, 'Saga 3 aktif: dibekukan');
  await ke(B, 'sowtour');
  await H.expectError(() => B.call('api_peregrin', ['maju', 7]), /Tidak ada yang perlu/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'ps14', 6)
               on conflict (player_id, quest_id) do update set step = 6`, [B.id]);
  s = await B.call('api_getGameState', [null]);
  ok(s.peregrin.frozen === false, 'Saga 3 tamat: lanjut lagi');
  r = await B.call('api_peregrin', ['maju', 7]); ok(r.peregrin.step === 8, 'lanjut setelah Saga 3');

  // pemain yang sudah tamat tetap tidak terganggu saat Saga 3 aktif
  s = await A.call('api_getGameState', [null]);
  ok(s.peregrin.done === true, 'tamat tetap tamat');

  console.log('PEREGRIN TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
