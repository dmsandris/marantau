// 0075 Quest Mahkota langkah 1-15: pemicu, urutan, tempat, malam, mini game, efek (Krisis, Zentul, Jolt).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { D, human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const malam = (on) => H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`,
    [String(Date.now() - (on ? 0.8 : 0.4) * 60 * 60000)]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const gold = async (u) => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);

  const a = await H.user('mkaptn'), b = await H.user('mkbiasa');
  await a.call('api_createCharacter', ['Kapten Mahkota', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  for (const u of [a, b]) {
    await H.sql(`update game.players set gold = 2000000 where player_id = $1`, [u.id]);
    await H.sql(`update game.ships set cargo_capacity = 400 where player_id = $1`, [u.id]).catch(() => { });
  }

  // ---- gerbang ----
  assert((await st(a)) === null && (await a.call('api_getGameState', [null])).mahkota == null, 'tertutup: tanpa state');
  await H.expectError(() => a.call('api_mahkota', ['maju', 0, 'ok']), /Tidak ada yang perlu/);
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  assert((await st(a)) === null, 'Saga 3 belum tamat: tetap tertutup');
  // Saga 3 tamat hari ini -> masih harus menunggu satu hari game
  for (const u of [a, b]) await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now())
    on conflict (player_id, quest_id) do update set step = 6, done_at = now()`, [u.id]);
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 2.4 * 60 * 60000)]);
  assert((await st(a)) === null, 'hari game yang sama: belum');
  await H.sql(`update game.player_quests set done_at = now() - interval '2 hours' where quest_id = 'ps14'`);
  const s0 = await st(a);
  assert(s0 && s0.step === 0 && s0.ada === 33 && s0.last === 40 && s0.d.n === 1, 'terbuka setelah 1 hari game: ' + JSON.stringify(s0 && s0.d));

  // ---- jalan 15 langkah ----
  const PANGGUNG = { 1: null, 2: 'ikn', 3: 'ikn', 4: 'joungjava', 5: 'joungjava', 6: 'toogood', 7: 'toogood', 8: 'paradiso', 9: 'paradiso' };
  let lalu = null;
  for (let n = 1; n <= 15; n++) {
    const s = await st(a), d = s.d;
    assert(s.step === n - 1 && d.n === n, 'langkah ' + n + ' aktif');
    const kota = d.c || PANGGUNG[1] || 'sunda_empire';
    if (d.c) {
      // salah tempat ditolak
      await taruh(a, d.c === 'ikn' ? 'joungjava' : 'ikn');
      await H.expectError(() => a.call('api_mahkota', [d.race ? 'balap' : 'maju', n - 1, 'ok']), /Tidak ada yang perlu/);
      await taruh(a, d.c);
    } else await taruh(a, kota);
    // langkah lain ditolak
    await H.expectError(() => a.call('api_mahkota', ['maju', n, 'ok']), /bergeser/);
    await H.expectError(() => a.call('api_mahkota', ['maju', n - 2, 'ok']), /bergeser/);
    if (d.t === 'malam') {
      await malam(false);
      await H.expectError(() => a.call('api_mahkota', ['maju', n - 1, 'ok']), /lampu-lampu dinyalakan/);
      await malam(true);
    }
    if (d.g) await H.expectError(() => a.call('api_mahkota', ['maju', n - 1, '']), /Belum berhasil/);

    if (d.race) {
      await H.expectError(() => a.call('api_mahkota', ['maju', n - 1, 'ok']), /garis start/);
      const t = await a.call('api_mahkota', ['balap', n - 1]);
      assert(t.trek.rival === d.race && t.trek.ship === 'tanpa' && t.trek.kind === 'turnamen', 'balapan langkah ' + n + ': kapal sendiri');
      await H.sql(`update game.trek_runs set created_at = now() - interval '40 seconds' where run_id = $1`, [t.trek.run]);
      const log = human('tanpa', t.trek.seed, SKILL.jago).log;
      await H.expectError(() => a.call('api_trek', ['selesai', t.trek.run, log]), /./);   // bukan lewat Sirkuit
      const r = await a.call('api_mahkota', ['selesai', n - 1, t.trek.run, log]);
      assert(r.maju === true && r.hasil.win === false, 'kalah dari Pariopelan dengan kapal sendiri, cerita tetap jalan');
    } else {
      const r = await a.call('api_mahkota', ['maju', n - 1, d.g === 'dadu' ? 'menang' : 'ok']);
      assert(r.maju === true, 'langkah ' + n + ' maju');
      if (n === 7) assert(r.gold === 50000, 'hadiah Q15: ' + r.gold);
      if (n === 8) assert(r.oli === 3 && Number((await one(`select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'`, [a.id])).qty) === 3, 'dadu menang: Oli Hitam');
      if (n === 15) assert(r.gold === 75000, 'hadiah Q16: ' + r.gold);
    }
    lalu = d;

    // efek per langkah
    const krisis = (await one(`select coalesce((select krisis from game.mh_player where player_id = $1), false) k`, [a.id])).k;
    assert(krisis === (n >= 2), 'Krisis Monopoli menyala setelah langkah 2 (n=' + n + ')');
    const zt = (await one('select game.zentul_open($1) z', [a.id])).z;
    assert(zt === (n >= 9), 'Zentul terbuka setelah langkah 9 (n=' + n + ')');
    if (n === 9) {
      assert((await one(`select game.city_open($1, 'zentul') o`, [a.id])).o === true, 'Zentul bisa dilayari');
      await taruh(a, 'zentul');
    }
    const ship = await one('select game.trek_kapal($1) k, game.ship_json($1) j', [a.id]);
    assert(ship.k === (n >= 15 ? 'jolt' : 'tanpa'), 'kapal trektrek-an (n=' + n + '): ' + ship.k);
    assert(Math.abs(Number(ship.j.TravelMul) - (n >= 15 ? 0.9 : 1)) < 1e-9, 'waktu tempuh -10% setelah Mesin Jolt (n=' + n + ')');
    const lawan = (await one('select game.trek_lawan($1) l', [a.id])).l;
    assert(JSON.stringify(lawan) === JSON.stringify(n >= 15 ? ['pariopelan'] : []), 'lawan Sirkuit (n=' + n + '): ' + JSON.stringify(lawan));
    const boleh = (await one('select game.trek_boleh($1) b', [a.id])).b;
    assert(boleh === (n >= 15), 'Sirkuit terbuka hanya setelah Mesin Jolt (n=' + n + ')');
  }

  // ---- setelah langkah 15 ----
  const s15 = await st(a);
  assert(s15.step === 15 && s15.d && s15.d.n === 16 && s15.jolt && s15.garasi && s15.zentul, 'langkah 16 aktif: ' + JSON.stringify(s15.d));
  await H.expectError(() => a.call('api_mahkota', ['maju', 15, 'ok']), /garis start/);
  assert((await gold(a)) > 2000000 + 50000 + 75000 - 1, 'hadiah masuk');
  // Sirkuit kini jalan dari Zentul, dengan Mesin Jolt
  const sk = await a.call('api_trek', ['status']);
  assert(sk.trek.ship === 'jolt' && JSON.stringify(sk.trek.lawan) === '["pariopelan"]', 'Sirkuit latihan: ' + JSON.stringify(sk.trek.lawan));
  await taruh(a, 'ikn');
  await H.expectError(() => a.call('api_trek', ['status']), /Aksi tidak dikenal/);
  await taruh(a, 'zentul');

  // ---- pemain lain tidak tersentuh ----
  assert((await st(b)).step === 0, 'pemain kedua: baru di langkah 1');
  assert((await one('select game.zentul_open($1) z', [b.id])).z === false, 'Zentul tetap tertutup untuk pemain lain');
  assert((await one('select game.trek_boleh($1) b', [b.id])).b === false, 'Sirkuit tertutup');
  assert(Math.abs(Number((await one('select game.ship_json($1) j', [b.id])).j.TravelMul) - 1) < 1e-9, 'waktu tempuh biasa');
  assert((await one(`select coalesce((select krisis from game.mh_player where player_id = $1), false) k`, [b.id])).k === false, 'tanpa Krisis Monopoli');
  // yang belum pernah mulai: tetap seperti sebelum Saga 4 (penguji Sirkuit)
  const c = await H.user('mkpenguji'); await c.call('api_createCharacter', ['Penguji', 'merchant']);
  await H.sql(`insert into game.config(key, value) values ('FiturPenguji', 'mkpenguji') on conflict (key) do update set value = 'mkpenguji'`);
  assert((await one('select game.trek_kapal($1) k', [c.id])).k === 'jolt' && (await one('select game.trek_boleh($1) b', [c.id])).b === true, 'penguji Trektrek-an tetap jalan');

  // ---- alat GM ----
  assert((await one(`select game.admin_mahkota('mkbiasa', 12) s`)).s.step === 12, 'admin_mahkota');
  assert((await one(`select krisis from game.mh_player where player_id = $1`, [b.id])).krisis === true, 'GM menyalakan Krisis');
  assert((await one(`select game.admin_mahkota('mkbiasa', 0) s`)).s.step === 0, 'GM mundur');
  assert((await one(`select krisis from game.mh_player where player_id = $1`, [b.id])).krisis === false, 'GM mematikan Krisis');

  console.log('0075 mahkota: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
