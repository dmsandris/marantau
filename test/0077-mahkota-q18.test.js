// 0077 Mahkota langkah 24-33: pilihan Marlya, Jolt Penuh, gerbang bambu, final turnamen, tiga Banjir Sutra.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { D, human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const gold = async (u) => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const malam = (on) => H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`,
    [String(Date.now() - (on ? 2.8 : 2.4) * 60 * 60000)]);

  const a = await H.user('q18kapten');
  await a.call('api_createCharacter', ['Kapten Banjir', 'merchant']);
  await H.sql(`update game.players set gold = 5000000 where player_id = $1`, [a.id]);
  await H.sql(`update game.ships set cargo_capacity = 900 where player_id = $1`, [a.id]).catch(() => { });
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  await H.sql(`update game.config set value = '6' where key = 'MhZonaN'`);   // semua pulau jadi zona supaya tiga Banjir muat di satu hari game
  await malam(true);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await one(`select game.admin_mahkota('q18kapten', 23) s`);

  const balap = async (n, skill) => {
    const t = (await a.call('api_mahkota', ['balap', n - 1])).trek;
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    const log = skill ? human(t.ship, t.seed, skill).log : [];
    return { r: await a.call('api_mahkota', ['selesai', n - 1, t.run, log]), t: t };
  };

  // ---- 24: robot di laboratorium (malam, Marie Regal) ----
  let s = await st(a); assert(s.d.n === 24 && s.d.c === 'marie_regal' && s.d.g === 'warga', 'langkah 24');
  await taruh(a, 'zentul');
  await H.expectError(() => a.call('api_mahkota', ['maju', 23, 'ok']), /Tidak ada yang perlu/);
  await taruh(a, 'marie_regal');
  await a.call('api_mahkota', ['maju', 23, 'ok']);

  // ---- 25: pilihan Marlya ----
  s = await st(a); assert(s.d.n === 25 && JSON.stringify(s.d.pilih) === '["maafkan","kabarkan"]', 'langkah 25');
  await H.expectError(() => a.call('api_mahkota', ['maju', 24, 'ok']), /tawaran Ratu/);
  await H.expectError(() => a.call('api_mahkota', ['pilih', 24, 'rampas']), /tidak dikenali/);
  let r = await a.call('api_mahkota', ['pilih', 24, 'maafkan']);
  assert(r.maju === true && (await st(a)).data.marlya === 'maafkan', 'pilihan tersimpan');

  // ---- 26: selam di Zentul ----
  s = await st(a); assert(s.d.n === 26 && s.d.c === 'zentul' && s.d.arr === true, 'langkah 26');
  await taruh(a, 'zentul');
  await a.call('api_mahkota', ['maju', 25, 'ok']);

  // ---- 27: Jolt Penuh + Garasi Warlord ----
  assert((await one('select game.trek_kapal($1) k', [a.id])).k === 'jolt', 'masih Mesin Jolt');
  r = await a.call('api_mahkota', ['maju', 26, 'ok']);
  assert((await one('select game.trek_kapal($1) k', [a.id])).k === 'penuh', 'Jolt Penuh terpasang');
  s = await st(a); assert(s.penuh === true && s.warlord === true, 'Garasi Warlord terbuka');
  assert(Math.abs(Number((await one('select game.ship_json($1) j', [a.id])).j.TravelMul) - 0.9) < 1e-9, 'waktu tempuh tetap -10%');

  // ---- 28: gerbang bambu < 10,30 detik ----
  s = await st(a); assert(s.d.n === 28 && s.d.targetUs === 'MkGerbangUs', 'langkah 28');
  let lambat = await balap(28, null);
  assert(lambat.r.maju === false && lambat.r.target === 10300000, 'terlalu lambat: tidak lolos');
  let lolos = null;
  for (let i = 0; i < 30 && !lolos; i++) { const x = await balap(28, SKILL.jago); if (x.r.maju) lolos = x; }
  assert(lolos && lolos.r.hasil.me < 10300000, 'lolos gerbang bambu: ' + (lolos && lolos.r.hasil.me));

  // ---- 29: final lawan cangcimen ----
  s = await st(a); assert(s.d.n === 29 && s.d.race === 'cangcimen_final' && s.d.win === true, 'langkah 29');
  let kalah = 0, menang = false;
  for (let i = 0; i < 60 && !menang; i++) {
    const x = await balap(29, i % 3 === 0 ? null : SKILL.jago);
    if (x.r.maju) menang = true; else kalah++;
  }
  assert(menang && kalah > 0, 'final bisa dimenangkan dengan Jolt Penuh (kalah ' + kalah + 'x dulu)');
  s = await st(a); assert(s.juara === true, 'juara Turnamen Obor');
  assert(JSON.stringify((await one('select game.trek_lawan($1) l', [a.id])).l) === '["pariopelan","kapalmber","cangcimen"]', 'cangcimen masuk daftar lawan Sirkuit');

  // ---- 30: Barisan Pacu ----
  s = await st(a); assert(s.d.n === 30 && s.d.g === 'susun', 'langkah 30');
  await a.call('api_mahkota', ['maju', 29, 'ok']);
  let m = await one('select * from game.mh_player where player_id = $1', [a.id]);
  assert(m.paksa === true && m.aman === true, 'patroli pasti mencegat selama Banjir');

  // ---- 31-33: tiga Banjir Sutra di tiga zona berbeda ----
  const day = (await one('select game.game_day() d')).d;
  const buka = (await H.sql(`select city_id from game.cities c where game.city_open($1, c.city_id)`, [a.id])).map((x) => x.city_id);
  const semua = (await one('select game.mh_zona($1) z', [day])).z.filter((z) => buka.includes(z));
  const game_spot = [];
  const layar = async (zona) => {
    const asal = buka.find((c) => c !== zona && c !== 'zentul' && !game_spot.includes(c));
    await taruh(a, asal);
    await a.call('api_setSail', [zona]);
    await H.sql(`update game.player_location set depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second' where player_id = $1`, [a.id]);
    return (await a.call('api_pollVoyage', [])).voyage;
  };
  const tembus = async (zona) => {
    for (let i = 0; i < 40; i++) {
      const v = await layar(zona);
      if (!(v.encounter && v.encounter.kind === 'cukai')) continue;
      const t = await a.call('api_cukai', ['tembus']);
      await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.trek.run]);
      const log = human(t.trek.ship, t.trek.seed, SKILL.jago).log;
      const rr = await a.call('api_cukai', ['selesai', t.trek.run, log]);
      if (rr.hasil && rr.hasil.win) return rr;
    }
    return null;
  };
  const isiPremium = async (n) => {
    await H.sql(`delete from game.inventory where player_id = $1`, [a.id]);
    await H.sql(`select game.adjust_inventory($1, 'mutiara', $2)`, [a.id, n]);
  };
  const GAME = { 31: 'pesta', 32: 'jejak', 33: 'kas' };
  const dibanjiri = [];
  for (let n = 31; n <= 33; n++) {
    s = await st(a);
    assert(s.d.n === n && s.d.g === GAME[n] && s.d.setor === true, 'langkah ' + n);
    const sisa = s.zonaSisa.filter((z) => !dibanjiri.includes(z) && buka.includes(z));
    assert(sisa.length >= 1, 'masih ada zona yang belum dibanjiri');
    const zona = sisa[0];
    await isiPremium(20);
    await H.expectError(() => a.call('api_mahkota', ['maju', n - 1, 'ok']), /belum kau tembus/);
    const rr = await tembus(zona);
    assert(rr, 'menembus jaring di ' + zona);
    assert((await st(a)).step === n - 1 && (await st(a)).data.tembusOk === n - 1, 'tembus membuka setoran, langkah belum maju');
    // harus di kota itu, dan premium cukup
    const lain = buka.find((z) => z !== zona && z !== 'zentul') || 'ikn';
    await taruh(a, lain);
    await H.expectError(() => a.call('api_mahkota', ['maju', n - 1, 'ok']), /menembus jaring/);
    await taruh(a, zona);
    await isiPremium(9);
    await H.expectError(() => a.call('api_mahkota', ['maju', n - 1, 'ok']), /butuh 15 unit/);
    await isiPremium(20);
    const g0 = await gold(a);
    r = await a.call('api_mahkota', ['maju', n - 1, 'ok']);
    assert(r.maju === true && r.bayar > 0 && (await gold(a)) === g0 + r.bayar + (r.gold || 0), 'setoran dibayar harga pasar');
    assert(Number((await one(`select qty from game.inventory where player_id = $1 and item_id = 'mutiara'`, [a.id])).qty) === 5, 'tepat 15 unit disetor');
    dibanjiri.push(zona);
    assert(JSON.stringify((await st(a)).banjir) === JSON.stringify(dibanjiri), 'zona tercatat sudah dibanjiri');
    if (n === 33) {
      assert(r.gold === 150000 && r.tanda === 'banjirsutra', 'hadiah Q18 + tanda jasa');
      m = await one('select * from game.mh_player where player_id = $1', [a.id]);
      assert(m.paksa === false && m.aman === false, 'patroli kembali normal setelah Banjir Ketiga');
    }
  }
  s = await st(a); assert(s.step === 33 && s.d === null, 'langkah 34 belum dikoding');
  await H.expectError(() => a.call('api_mahkota', ['maju', 33, 'ok']), /Bersambung/);

  console.log('0077 mahkota q18: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
