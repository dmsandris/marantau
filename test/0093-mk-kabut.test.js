// 0093: langkah 10 (kabut) tidak lagi menuntut pemain sudah merapat di Zentul.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const kota = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  const a = await H.user('kabut1');
  await a.call('api_createCharacter', ['Kapten Kabut', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1,'ps14',6,'{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);

  const langkah = (await one('select game.mk_steps() s')).s;
  assert(langkah.length === 40, '40 langkah');
  assert(langkah[9].p === 'laut' && !langkah[9].c && langkah[9].g === 'angin', 'langkah 10 di laut tanpa syarat kota: ' + JSON.stringify(langkah[9]));
  assert(langkah[10].c === 'zentul' && langkah[10].cine === 'mk_zentul', 'sinematik pindah ke langkah 11: ' + JSON.stringify(langkah[10]));

  // di Paradiso (tempat langkah 9 selesai), langkah 10 boleh diselesaikan
  await one(`select game.admin_mahkota('kabut1', 9) s`);
  await kota(a, 'paradiso');
  let st = (await a.call('api_mahkota', ['status'])).mahkota;
  assert(st.d.n === 10, 'berada di langkah 10: ' + JSON.stringify(st.d && st.d.n));
  assert((await one(`select game.zentul_open($1) z`, [a.id])).z === true, 'Zentul sudah terbuka sejak langkah 9');
  const r = await a.call('api_mahkota', ['maju', 9, 'menang']);
  assert(r.mahkota.d.n === 11, 'langkah 10 selesai dari Paradiso: ' + JSON.stringify(r.mahkota.d && r.mahkota.d.n));

  // langkah 11 tetap menuntut berada di Zentul
  assert(await H.expectError(() => a.call('api_mahkota', ['maju', 10, 'ok'])), 'langkah 11 butuh Zentul');
  await kota(a, 'zentul');
  const r2 = await a.call('api_mahkota', ['maju', 10, 'ok']);
  assert(r2.mahkota.d.n === 12, 'langkah 11 selesai di Zentul');

  console.log('0093 kabut saat berlayar: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
