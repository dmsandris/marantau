// 0084: Zentul & Sirkuit tidak boleh terbuka lewat gerbang global.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const lihat = async (u) => (await one(`select game.zentul_open($1) v`, [u.id])).v;
  const trek = async (u) => (await one(`select game.trek_boleh($1) v`, [u.id])).v;
  const kota = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);

  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  const a = await H.user('zr_biasa'), b = await H.user('zr_saga');
  await a.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Saga', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1,'ps14',6,'{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [b.id]);

  // gerbang global TrekOpen = 1 tidak boleh membuka apa pun
  await H.sql(`update game.config set value = '1' where key = 'TrekOpen'`);
  for (const u of [a, b]) {
    assert((await lihat(u)) === false, 'TrekOpen global tidak membuka Zentul');
    assert((await trek(u)) === false, 'TrekOpen global tidak membuka Sirkuit');
    const unl = (await one(`select game.player_unlocks($1) u`, [u.id])).u || [];
    assert(JSON.stringify(unl).indexOf('zentul') < 0, 'zentul tidak ada di player_unlocks');
    assert((await one(`select game.city_open($1, 'zentul') v`, [u.id])).v === false, 'tidak bisa berlayar ke zentul');
  }
  await H.sql(`update game.config set value = '0' where key = 'TrekOpen'`);

  // langkah 9 membuka peta, bukan Sirkuit
  await one(`select game.admin_mahkota('zr_saga', 9) s`);
  assert((await lihat(b)) === true, 'langkah 9: Zentul terlihat');
  assert((await one(`select game.city_open($1, 'zentul') v`, [b.id])).v === true, 'langkah 9: boleh berlayar ke zentul');
  assert((await lihat(a)) === false, 'pemain lain tetap tidak melihat Zentul');
  await kota(b, 'zentul');
  assert((await trek(b)) === false, 'langkah 9: Sirkuit masih tertutup');
  assert(await H.expectError(() => b.call('api_trek', ['status'])), 'api_trek ditolak sebelum tamat');

  // langkah 15 (punya Mesin Jolt) pun belum boleh latihan
  await one(`select game.admin_mahkota('zr_saga', 15) s`);
  await kota(b, 'zentul');
  assert((await trek(b)) === false, 'langkah 15: Sirkuit masih tertutup');
  // balapan cerita tetap jalan lewat api_mahkota
  const st = (await b.call('api_mahkota', ['status'])).mahkota;
  assert(st && st.d, 'quest tetap berjalan: ' + JSON.stringify(st && st.d && st.d.at));

  // tamat: Sirkuit terbuka, tapi hanya saat merapat di Zentul
  await one(`select game.admin_mahkota('zr_saga', 40) s`);
  await kota(b, 'zentul');
  assert((await trek(b)) === true, 'tamat + di Zentul: Sirkuit terbuka');
  const t = (await b.call('api_trek', ['status'])).trek;
  assert(t && t.lawan.length === 4, 'empat lawan tersedia');
  await kota(b, 'ikn');
  assert((await trek(b)) === false, 'di luar Zentul: Sirkuit tertutup');
  await H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = 'ikn', depart_at = now(), arrive_at = now() + interval '5 minutes' where player_id = $1`, [b.id]);
  assert((await trek(b)) === false, 'sedang berlayar: Sirkuit tertutup');
  await kota(b, 'zentul');

  // sakelar darurat
  await H.sql(`update game.config set value = '1' where key = 'TrekTutup'`);
  assert((await trek(b)) === false, 'TrekTutup menutup Sirkuit');
  assert((await lihat(b)) === true, 'TrekTutup tidak menyembunyikan Zentul');
  await H.sql(`update game.config set value = '0' where key = 'TrekTutup'`);

  // penguji: nama terdaftar saja
  await H.sql(`update game.config set value = 'zr_biasa' where key = 'FiturPenguji'`);
  assert((await lihat(a)) === true && (await trek(a)) === true, 'penguji terdaftar boleh');
  const c = await H.user('zr_lain'); await c.call('api_createCharacter', ['Kapten Lain', 'merchant']);
  assert((await lihat(c)) === false && (await trek(c)) === false, 'yang tidak terdaftar tetap tertutup');
  await H.sql(`update game.config set value = '' where key = 'FiturPenguji'`);
  assert((await lihat(a)) === false, 'daftar penguji dikosongkan: tertutup lagi');

  console.log('0084 zentul rahasia: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
