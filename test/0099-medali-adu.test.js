// 0099 Medali Adu: juara adu dapat 1 medali (hanya bila kedua catatan masuk), tukar Oli/Gigi/Rantai.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const siap = async (u, uname, nama) => {
    await u.call('api_createCharacter', [nama, 'merchant']);
    await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1,'ps14',6,'{}', now() - interval '2 hours')
      on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [u.id]);
    await one(`select game.admin_mahkota($1, 40) s`, [uname]);
    await H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id]);
    await u.call('api_mpPulse', []);
  };
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  const a = await H.user('md_a'), b = await H.user('md_b');
  await siap(a, 'md_a', 'Kapten Alif'); await siap(b, 'md_b', 'Kapten Bima');
  const pub = async (u) => (await one(`select game.mp_pub_of($1) p`, [u.id])).p;
  const med = async (u) => Number((await one(`select game.medali_jml($1) n`, [u.id])).n);

  let lob = (await a.call('api_trekDuel', ['lobi'])).adu;
  assert(lob.medali === 0 && lob.tukar.gigi === 25 && lob.tukar.rantai === 35 && lob.tukar.oli === 10, 'lobi memuat medali & kurs: ' + JSON.stringify(lob.tukar));

  // adu normal: yang lebih cepat dapat 1 medali, yang kalah tidak
  let d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  await b.call('api_trekDuel', ['jawab', d.id, true]);
  const kapal = (await one(`select game.trek_ships() -> $1 s`, [d.kapalku])).s;
  const logA = human(kapal, d.seed, SKILL.jago).log, logB = human(kapal, d.seed, SKILL.pemula).log;
  await a.call('api_trekDuel', ['log', d.id, logA]);
  assert(await med(a) === 0, 'belum ada medali sebelum hasil keluar');
  await b.call('api_trekDuel', ['log', d.id, logB]);
  assert(await med(a) === 1 && await med(b) === 0, 'juara dapat 1 medali');
  await a.call('api_trekDuel', ['lihat', d.id]); await b.call('api_trekDuel', ['lihat', d.id]);
  assert(await med(a) === 1, 'tidak ganda saat hasil dilihat lagi');
  assert((await a.call('api_trekDuel', ['lobi'])).adu.medali === 1, 'lobi menampilkan medali');

  // menang WO (lawan tidak menyetor): tidak ada medali
  d = (await a.call('api_trekDuel', ['tantang', await pub(b)])).duel;
  await b.call('api_trekDuel', ['jawab', d.id, true]);
  await a.call('api_trekDuel', ['log', d.id, logA]);
  await H.sql(`update game.trek_duels set started = started - 120000 where id = $1`, [d.id]);
  await a.call('api_trekDuel', ['lihat', d.id]);
  assert(await med(a) === 1, 'menang WO tidak dapat medali');

  // tukar
  assert(await H.expectError(() => a.call('api_medali', ['tukar', 'oli', 1])), 'medali kurang ditolak');
  assert(await H.expectError(() => a.call('api_medali', ['tukar', 'emas', 1])), 'barang tak dikenal ditolak');
  await H.sql(`update game.medali set jumlah = 100 where player_id = $1`, [a.id]);
  const oli0 = Number((await one(`select game.adjust_inventory($1,'oli_hitam',0) n`, [a.id])).n || 0);
  let r = await a.call('api_medali', ['tukar', 'oli', 2]);
  assert(r.ok && r.medali === 80, 'tukar 2 oli = 20 medali: ' + JSON.stringify(r));
  r = await a.call('api_medali', ['tukar', 'gigi', 1]);
  assert(r.medali === 55, '25 medali = 1 gigi');
  r = await a.call('api_medali', ['tukar', 'rantai', 1]);
  assert(r.medali === 20, '35 medali = 1 rantai');
  assert(Number((await one(`select game.item_qty($1,'qi_mk_gigi') n`, [a.id])).n) >= 1, 'gigi masuk tas');
  assert(Number((await one(`select game.item_qty($1,'qi_mk_rantai') n`, [a.id])).n) >= 1, 'rantai masuk tas');
  assert(await H.expectError(() => a.call('api_medali', ['tukar', 'rantai', 1])), '20 medali tidak cukup untuk rantai');

  // batas simpan Warlord
  await H.sql(`update game.medali set jumlah = 1000 where player_id = $1`, [a.id]);
  await H.sql(`update game.config set value = '2' where key = 'WarlordDropMax'`);
  assert(await H.expectError(() => a.call('api_medali', ['tukar', 'gigi', 5])), 'melewati WarlordDropMax ditolak');
  assert((await med(a)) === 1000, 'medali utuh saat tukar gagal');

  // belum tahap Warlord: gigi/rantai ditolak, oli boleh
  await H.sql(`update game.medali set jumlah = 100 where player_id = $1`, [b.id]);
  await H.sql(`update game.player_quests set step = 10 where player_id = $1 and quest_id = 'mahkota'`, [b.id]);
  if (!(await one(`select game.wl_buka($1) w`, [b.id])).w) {
    assert(await H.expectError(() => b.call('api_medali', ['tukar', 'gigi', 1])), 'gigi sebelum Warlord ditolak');
  }

  console.log('0099 medali adu: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
