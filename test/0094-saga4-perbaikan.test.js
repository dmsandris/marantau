// 0094 Saga 4 perbaikan: zona cukai 4 pulau, tempa Yaptob 2x/hari, balapan wajib menang 2x/hari.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const hariBaru = async () => {   // geser jam dunia mundur satu hari game
    const len = Number((await one(`select value from game.config where key = 'GameDayLengthRealMinutes'`)).value);
    await H.sql(`update game.config set value = (value::bigint - $1::bigint)::text where key = 'WorldStartTimestamp'`, [Math.round(len * 60000)]);
  };

  // ---- zona cukai: 4 pulau per hari ----
  assert(Number((await one(`select value from game.config where key = 'MhZonaN'`)).value) === 4, 'MhZonaN = 4');
  const day = (await one('select game.game_day() d')).d;
  for (let d = day; d < day + 10; d++) {
    const z = (await one('select game.mh_zona($1) z', [d])).z;
    assert(z.length === 4 && new Set(z).size === 4, 'zona hari ' + d + ': ' + z);
  }

  const a = await H.user('q94kapten');
  await a.call('api_createCharacter', ['Kapten Panas', 'merchant']);
  await H.sql(`update game.players set gold = 3000000 where player_id = $1`, [a.id]);
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);

  // ---- tempa Yaptob (langkah 15): 2 percobaan, ketiga ditolak sampai hari game berikutnya ----
  await one(`select game.admin_mahkota('q94kapten', 14) s`);
  await taruh(a, 'zentul');
  let s = await st(a);
  assert(s.d.n === 15 && s.d.g === 'tempa' && s.d.batas === true, 'langkah 15 bertanda batas');
  let r = await a.call('api_mahkota', ['coba', 14]);
  assert(r.coba === true && r.sisaHari === 1, 'percobaan 1: sisa 1');
  r = await a.call('api_mahkota', ['coba', 14]);
  assert(r.coba === true && r.sisaHari === 0, 'percobaan 2: sisa 0');
  await H.expectError(() => a.call('api_mahkota', ['coba', 14]), /Tungku tempa sudah terlalu panas, kembalilah besok/);
  await hariBaru();
  r = await a.call('api_mahkota', ['coba', 14]);
  assert(r.coba === true && r.sisaHari === 1, 'hari game baru: percobaan pulih');

  // ---- balapan lawan Pariopelan (16) & KapalMber (17): dua kali gagal = mesin panas ----
  await one(`select game.admin_mahkota('q94kapten', 15) s`);
  s = await st(a);
  assert(s.d.n === 16 && s.d.race === 'pariopelan' && s.d.batas === true, 'langkah 16 bertanda batas');
  await hariBaru();
  const kalah = async (n) => {
    const t = (await a.call('api_mahkota', ['balap', n - 1])).trek;
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    return a.call('api_mahkota', ['selesai', n - 1, t.run, []]);   // tanpa ketukan = kalah
  };
  let k = await kalah(16);
  assert(k.maju === false && k.panas === false && k.sisaHari === 1, 'kalah 1: sisa 1 -> ' + JSON.stringify([k.panas, k.sisaHari]));
  k = await kalah(16);
  assert(k.maju === false && k.panas === true && k.sisaHari === 0 && k.menit > 0, 'kalah 2: mesin panas -> ' + JSON.stringify([k.panas, k.sisaHari, k.menit]));
  await H.expectError(() => a.call('api_mahkota', ['balap', 15]), /Mesin sudah terlalu panas, bisa hancur kalau dipaksa terus/);
  assert((await st(a)).step === 15 && (await st(a)).data.kalah15 === 2, 'langkah tidak maju, kekalahan tetap dicatat');
  await hariBaru();
  let menang = false;
  for (let i = 0; i < 30 && !menang; i++) {   // hari baru: boleh lagi (batas dimatikan agar pencarian skill tak terkunci)
    await H.sql(`insert into game.config(key, value) values ('MkBatasHari', '0') on conflict (key) do update set value = '0'`);
    const t = (await a.call('api_mahkota', ['balap', 15])).trek;
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    const res = await a.call('api_mahkota', ['selesai', 15, t.run, human(t.ship, t.seed, SKILL.jago).log]);
    menang = res.maju === true;
  }
  assert(menang && (await st(a)).step === 16, 'menang di hari baru -> langkah 17 (KapalMber)');
  await H.sql(`update game.config set value = '2' where key = 'MkBatasHari'`);
  assert((await st(a)).d.race === 'kapalmber', 'langkah 17 lawan KapalMber');
  k = await kalah(17); k = await kalah(17);
  assert(k.panas === true, 'KapalMber: dua kali kalah = panas');
  await H.expectError(() => a.call('api_mahkota', ['balap', 16]), /terlalu panas/);

  console.log('0094 saga4 perbaikan: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
