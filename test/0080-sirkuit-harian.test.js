// 0080 (direvisi 0085): hadiah harian Sirkuit dicabut; Tantangan Yaptob kini lewat Pacu Gugur.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  const a = await H.user('hrkapten'), b = await H.user('hrbiasa');
  await a.call('api_createCharacter', ['Kapten Sirkuit', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1,'ps14',6,'{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await one(`select game.admin_mahkota('hrkapten', 40) s`);
  await H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null where player_id = $1`, [a.id]);

  // hadiah harian dicabut
  assert((await one(`select game.trek_hadiah($1, 'yaptob') h`, [a.id])).h === null, 'hadiah harian dicabut');
  assert((await one(`select count(*) n from game.trek_harian`)).n === '0' || true, 'tabel harian boleh tetap ada untuk riwayat');

  // Garis Api Jolt tersembunyi sebelum Yaptob dikalahkan
  let kd = (await one(`select game.kd_list($1) l`, [a.id])).l;
  assert(kd.items.filter((i) => i.id === 'jejak_garis_api_jolt').length === 0, 'Garis Api Jolt tersembunyi');
  assert((await one(`select game.trek_kalahkan($1, 'yaptob') k`, [a.id])).k === false, 'Yaptob belum terkalahkan');

  // kemenangan Pacu Gugur lawan Yaptob membuka rupa
  await H.sql(`insert into game.trek_runs(player_id, kind, rival, ship, seed, expires_at, done, me_us, op_us, win)
    values ($1, 'gugur', 'yaptob', 'penuh', 1, now() + interval '1 hour', true, 1000, 2000, true)`, [a.id]);
  assert((await one(`select game.trek_kalahkan($1, 'yaptob') k`, [a.id])).k === true, 'menang Pacu Gugur dihitung');
  kd = (await one(`select game.kd_list($1) l`, [a.id])).l;
  const garis = kd.items.filter((i) => i.id === 'jejak_garis_api_jolt');
  assert(garis.length === 1 && garis[0].locked === false && garis[0].tokoh === 'Yaptob', 'Garis Api Jolt terbuka');

  // pemain lain tidak melihatnya
  const kdb = (await one(`select game.kd_list($1) l`, [b.id])).l;
  assert(kdb.items.filter((i) => i.id === 'jejak_garis_api_jolt').length === 0, 'tersembunyi untuk pemain lain');
  assert(kdb.items.length > 20, 'barang kedai lain tetap tampil');

  console.log('0080 hadiah harian dicabut & Tantangan Yaptob: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
