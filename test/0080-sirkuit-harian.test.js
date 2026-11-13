// 0080 Sirkuit harian: hadiah menang pertama per hari game, Tantangan Yaptob, rupa Garis Api Jolt.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { D, human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const gold = async (u) => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const oli = async (u) => Number((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'), 0) q`, [u.id])).q);

  const a = await H.user('hrkapten');
  await a.call('api_createCharacter', ['Kapten Sirkuit', 'merchant']);
  await H.sql(`update game.players set gold = 1000000 where player_id = $1`, [a.id]);
  await H.sql(`update game.ships set cargo = 900 where player_id = $1`, [a.id]).catch(() => { });
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 2.4 * 60 * 60000)]);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await one(`select game.admin_mahkota('hrkapten', 40) s`);   // saga tamat: Sirkuit terbuka penuh
  await taruh(a, 'zentul');

  const balap = async (rival, skill) => {
    const t = await a.call('api_trek', ['mulai', rival]);
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    const log = skill ? human(t.ship, t.seed, skill).log : [];
    return (await a.call('api_trek', ['selesai', t.run, log])).hasil;
  };
  const menang = async (rival, max) => {
    for (let i = 0; i < (max || 80); i++) { const r = await balap(rival, SKILL.jago); if (r.win) return r; }
    return null;
  };

  let s = (await a.call('api_trek', ['status'])).trek;
  assert(JSON.stringify(s.lawan) === '["pariopelan","kapalmber","cangcimen","yaptob"]', 'empat lawan');
  assert(s.harian.pariopelan.sudah === false && s.harian.yaptob.gold === 32000 && s.harian.pariopelan.gold === 4000, 'papan hadiah harian: ' + JSON.stringify(s.harian.yaptob));
  assert(s.total === 0 && s.yaptob === false, 'belum ada kemenangan');

  // menang pertama hari ini: dapat hadiah
  const g0 = await gold(a), o0 = await oli(a);
  let r = await menang('pariopelan');
  assert(r && r.harian && r.harian.oli === 2 && r.harian.gold === 4000, 'hadiah menang pertama: ' + JSON.stringify(r && r.harian));
  assert((await gold(a)) === g0 + 4000 && (await oli(a)) === o0 + 2, 'gold & Oli Hitam masuk');
  // menang kedua hari yang sama: tanpa hadiah
  const g1 = await gold(a);
  r = await menang('pariopelan');
  assert(r && !r.harian && (await gold(a)) === g1, 'menang kedua hari yang sama tidak berhadiah');
  s = (await a.call('api_trek', ['status'])).trek;
  assert(s.harian.pariopelan.sudah === true && s.harian.kapalmber.sudah === false, 'lawan lain masih berhadiah');
  assert(s.total >= 2, 'total menang dihitung: ' + s.total);

  // lawan lain, hadiah lebih besar
  const g2 = await gold(a);
  r = await menang('kapalmber');
  assert(r && r.harian.gold === 8000 && r.harian.oli === 4 && (await gold(a)) === g2 + 8000, 'KapalMber berhadiah dua kali lipat');

  // hari game berikutnya: hadiah pulih
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 4.5 * 60 * 60000)]);
  s = (await a.call('api_trek', ['status'])).trek;
  assert(s.harian.pariopelan.sudah === false, 'hari game baru: hadiah pulih');
  const g3 = await gold(a);
  r = await menang('pariopelan');
  assert(r && r.harian && (await gold(a)) === g3 + 4000, 'hadiah hari berikutnya');

  // palka penuh: hadiah gold tetap, Oli Hitam dilewati
  await H.sql(`update game.ships set cargo = 1 where player_id = $1`, [a.id]);
  await H.sql(`select game.adjust_inventory($1, 'beras', 1)`, [a.id]).catch(() => { });
  const g4 = await gold(a), o4 = await oli(a);
  r = await menang('kapalmber');
  assert(r && r.harian && r.harian.oli === 0 && (await gold(a)) === g4 + 8000 && (await oli(a)) === o4, 'palka penuh: Oli Hitam dilewati, gold tetap');
  await H.sql(`update game.ships set cargo = 900 where player_id = $1`, [a.id]);

  // ---- Tantangan Yaptob ----
  let kd = (await one(`select game.kd_list($1) l`, [a.id])).l;
  assert(kd.items.filter((i) => i.id === 'jejak_garis_api_jolt').length === 0, 'Garis Api Jolt tersembunyi sebelum Yaptob kalah');
  assert((await one(`select game.trek_kalahkan($1, 'yaptob') k`, [a.id])).k === false, 'Yaptob belum terkalahkan');
  // Yaptob sangat sulit: catat kemenangan lewat jalur normal bila dapat, kalau tidak suntik satu run menang
  r = await menang('yaptob', 40);
  if (!r) {
    await H.sql(`insert into game.trek_runs(player_id, kind, rival, ship, seed, expires_at, done, me_us, op_us, win)
      values ($1, 'sirkuit', 'yaptob', 'jolt', 1, now() + interval '1 hour', true, 1000, 2000, true)`, [a.id]);
  }
  assert((await one(`select game.trek_kalahkan($1, 'yaptob') k`, [a.id])).k === true, 'Yaptob terkalahkan');
  kd = (await one(`select game.kd_list($1) l`, [a.id])).l;
  const garis = kd.items.filter((i) => i.id === 'jejak_garis_api_jolt');
  assert(garis.length === 1 && garis[0].locked === false && garis[0].tokoh === 'Yaptob', 'Garis Api Jolt terbuka: ' + JSON.stringify(garis[0] && garis[0].locked));
  s = (await a.call('api_trek', ['status'])).trek;
  assert(s.yaptob === true, 'status menandai Yaptob sudah dikalahkan');

  // ---- pemain lain ----
  const b = await H.user('hrbiasa'); await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  const kdb = (await one(`select game.kd_list($1) l`, [b.id])).l;
  assert(kdb.items.filter((i) => i.id === 'jejak_garis_api_jolt').length === 0, 'tersembunyi untuk pemain lain');
  assert(kdb.items.length > 20, 'barang kedai lain tetap tampil');
  assert(Number((await one(`select coalesce((select count(*) from game.trek_harian where player_id = $1), 0) n`, [b.id])).n) === 0, 'tanpa catatan harian');

  console.log('0080 sirkuit harian: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
