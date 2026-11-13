// 0076 Mahkota langkah 16-23: babak wajib menang, teka-teki Nenek Ulin, Tembus Jaring pertama, Pasar Gelap.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { D, human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const mh = async (u) => one('select * from game.mh_player where player_id = $1', [u.id]);
  const malam = (on) => H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`,
    [String(Date.now() - (on ? 2.8 : 2.4) * 60 * 60000)]);

  const a = await H.user('q17kapten');
  await a.call('api_createCharacter', ['Kapten Dua Detik', 'merchant']);
  await H.sql(`update game.players set gold = 3000000 where player_id = $1`, [a.id]);
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  await malam(false);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await one(`select game.admin_mahkota('q17kapten', 15) s`);
  await taruh(a, 'zentul');

  const balap = async (n, skill) => {
    const t = (await a.call('api_mahkota', ['balap', n - 1])).trek;
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    const log = skill ? human(t.ship, t.seed, skill).log : [];
    const menang = D.replay(t.ship, log).fin < D.runAi(t.rival, t.seed).fin;
    const r = await a.call('api_mahkota', ['selesai', n - 1, t.run, log]);
    assert(r.hasil.win === menang, 'hasil server = hitungan klien');
    return r;
  };

  // ---- 16: babak 1 ulang, wajib menang ----
  let s = await st(a);
  assert(s.d.n === 16 && s.d.race === 'pariopelan' && s.d.win === true, 'langkah 16: ' + JSON.stringify(s.d));
  assert((await one('select game.trek_kapal($1) k', [a.id])).k === 'jolt', 'pakai Mesin Jolt');
  let kalah = 0;
  for (let i = 0; i < 25; i++) {
    const r = await balap(16, null);           // tanpa ketukan = kalah
    if (r.maju === false) { kalah++; assert((await st(a)).step === 15, 'kalah: langkah tidak maju'); break; }
  }
  assert(kalah === 1 && (await st(a)).data.kalah15 === 1, 'kekalahan dicatat untuk kiat Yaptob');
  let menang = false;
  for (let i = 0; i < 25 && !menang; i++) { const r = await balap(16, SKILL.jago); menang = r.maju === true; }
  assert(menang && (await st(a)).step === 16, 'menang lawan Pariopelan -> langkah 17');

  // ---- 17: semifinal lawan KapalMber ----
  s = await st(a); assert(s.d.n === 17 && s.d.race === 'kapalmber', 'langkah 17');
  menang = false;
  for (let i = 0; i < 40 && !menang; i++) { const r = await balap(17, SKILL.jago); menang = r.maju === true; }
  assert(menang, 'menang lawan KapalMber');
  assert(JSON.stringify((await one('select game.trek_lawan($1) l', [a.id])).l) === '["pariopelan","kapalmber"]', 'lawan latihan bertambah');

  // ---- 18: lapor ke Yaptob ----
  await a.call('api_mahkota', ['maju', 17, 'ok']);
  // ---- 19: Skitraw ----
  s = await st(a); assert(s.d.n === 19 && s.d.c === 'skitraw' && s.d.g === 'sandi', 'langkah 19');
  await H.expectError(() => a.call('api_mahkota', ['maju', 18, 'ok']), /Tidak ada yang perlu/);
  await taruh(a, 'skitraw');
  await H.expectError(() => a.call('api_mahkota', ['maju', 18, '']), /Belum berhasil/);
  await a.call('api_mahkota', ['maju', 18, 'ok']);

  // ---- 20: teka-teki Nenek Ulin ----
  s = await st(a); assert(s.d.n === 20 && s.d.teka === true, 'langkah 20');
  await taruh(a, 'bjorneo');
  await H.expectError(() => a.call('api_mahkota', ['maju', 19, 'ok']), /Jawab dulu/);
  let rt = await a.call('api_mahkota', ['teka', 19, 'batu bata']);
  assert(rt.maju === false && rt.teka === false && rt.tunggu === 20 && /Bukan itu/.test(rt.pesan), 'jawaban salah: ' + JSON.stringify(rt));
  rt = await a.call('api_mahkota', ['teka', 19, 'baterai']);
  assert(rt.maju === false && rt.tunggu > 0 && /Sabar/.test(rt.pesan), 'jeda 20 detik berlaku walau jawabannya benar');
  assert((await st(a)).data.tekaSalah === 1 && (await st(a)).step === 19, 'salah tercatat, langkah tetap');
  await H.sql(`update game.player_quests set data = data || jsonb_build_object('tekaAt', 0) where player_id = $1 and quest_id = 'mahkota'`, [a.id]);
  for (const jawab of ['BATRE', ' batu  baterai ', 'baterei']) {
    await H.sql(`update game.player_quests set step = 19, data = data || jsonb_build_object('tekaAt', 0) where player_id = $1 and quest_id = 'mahkota'`, [a.id]);
    const r = await a.call('api_mahkota', ['teka', 19, jawab]);
    assert(r.maju === true, 'jawaban diterima: ' + jawab);
  }
  let m = await mh(a);
  assert(m.tembus && m.paksa && m.aman, 'langkah 20 menyalakan Tembus Jaring + patroli pasti + aman');

  // ---- 21: Tembus Jaring pertama ----
  s = await st(a); assert(s.d.n === 21 && s.d.zona === true, 'langkah 21');
  await H.expectError(() => a.call('api_mahkota', ['maju', 20, 'ok']), /bertanda cukai/);
  const day = (await one('select game.game_day() d')).d;
  const Z = (await one('select game.mh_zona($1) z', [day])).z;
  const zona = Z.find((c) => ['sunda_empire', 'skitraw', 'joungjava', 'bjorneo'].includes(c));
  const asal = ['sunda_empire', 'skitraw', 'joungjava', 'bjorneo'].find((c) => c !== zona);
  const layar = async () => {
    await taruh(a, asal);
    await a.call('api_setSail', [zona]);
    await H.sql(`update game.player_location set depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second' where player_id = $1`, [a.id]);
    return (await a.call('api_pollVoyage', [])).voyage;
  };
  await H.sql(`select game.adjust_inventory($1, 'mutiara', 6)`, [a.id]);
  let v = await layar();
  assert(v.encounter && v.encounter.kind === 'cukai' && v.encounter.rival === 'patroli_lemah' && v.encounter.tembus && v.encounter.aman, 'patroli lemah pasti mencegat: ' + JSON.stringify(v.encounter && v.encounter.rival));
  // kalah dulu: tidak menyita, langkah tidak maju
  let t = await a.call('api_cukai', ['tembus']);
  await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.trek.run]);
  let r = await a.call('api_cukai', ['selesai', t.trek.run, []]);
  assert(r.hasil.win === false && r.sita.length === 0 && (await st(a)).step === 20, 'kalah di langkah 21: aman, tidak maju');
  assert(Number((await one(`select qty from game.inventory where player_id = $1 and item_id = 'mutiara'`, [a.id])).qty) === 6, 'muatan utuh');
  // menang
  let win = false;
  for (let i = 0; i < 30 && !win; i++) {
    v = await layar();
    t = await a.call('api_cukai', ['tembus']);
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.trek.run]);
    const log = human(t.trek.ship, t.trek.seed, SKILL.jago).log;
    r = await a.call('api_cukai', ['selesai', t.trek.run, log]);
    win = !!(r.hasil && r.hasil.win);
  }
  assert(win && (await st(a)).step === 21 && (await st(a)).data.zona === zona, 'menang tembus -> langkah 22 di ' + zona);
  assert(r.mahkota && r.mahkota.step === 21, 'jawaban cukai membawa state quest baru');

  // ---- 22: koin bercap biru di pasar zona ----
  s = await st(a); assert(s.d.n === 22 && s.d.g === 'timbang', 'langkah 22');
  await taruh(a, asal);
  await H.expectError(() => a.call('api_mahkota', ['maju', 21, 'ok']), /menembus jaring/);
  await taruh(a, zona);
  await a.call('api_mahkota', ['maju', 21, 'ok']);
  m = await mh(a);
  assert(m.gelap === true && m.paksa === false && m.aman === false, 'Pasar Gelap resmi terbuka, patroli kembali normal');

  // ---- 23: Paradiso malam, hadiah Q17 ----
  s = await st(a); assert(s.d.n === 23 && s.d.t === 'malam', 'langkah 23');
  await taruh(a, 'paradiso');
  await H.expectError(() => a.call('api_mahkota', ['maju', 22, 'ok']), /lampu-lampu/);
  await malam(true);
  const g0 = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  r = await a.call('api_mahkota', ['maju', 22, 'ok']);
  assert(r.gold === 100000 && r.tanda === 'duadetik' && Number((await one('select gold from game.players where player_id = $1', [a.id])).gold) === g0 + 100000, 'hadiah Q17 + tanda jasa');
  s = await st(a); assert(s.step === 23 && s.d === null, 'langkah 24 belum dikoding');
  await H.expectError(() => a.call('api_mahkota', ['maju', 23, 'ok']), /Bersambung/);

  console.log('0076 mahkota q17: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
