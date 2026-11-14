// 0079 Mahkota langkah 34-40: setoran pengalih, genderang, tiga heat di IKN, pilihan stempel, penutup saga.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { D, human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const gold = async (u) => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const siap = async (u, n) => {
    await one(`select game.admin_mahkota($1, $2) s`, [u.name || 'q19kapten', n]);
  };

  const a = await H.user('q19kapten');
  await a.call('api_createCharacter', ['Kapten Gerbang', 'merchant']);
  await H.sql(`update game.players set gold = 5000000 where player_id = $1`, [a.id]);
  await H.sql(`update game.ships set cargo_capacity = 900 where player_id = $1`, [a.id]).catch(() => { });
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 2.4 * 60 * 60000)]);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await one(`select game.admin_mahkota('q19kapten', 33) s`);

  const balap = async (n, skill) => {
    const t = (await a.call('api_mahkota', ['balap', n - 1])).trek;
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    const log = skill ? human(t.ship, t.seed, skill).log : [];
    return { r: await a.call('api_mahkota', ['selesai', n - 1, t.run, log]), t: t };
  };
  const berlayarLagi = async () => { await a.call('api_setSail', ['joungjava']); await taruh(a, 'ikn'); };
  const menangkan = async (n, max) => {
    for (let i = 0; i < (max || 60); i++) {
      let x;
      try { x = await balap(n, SKILL.jago); } catch (e) {
        if (!/Mundur ke laut lepas/.test(e.message || '')) throw e;
        await berlayarLagi(); continue;
      }
      if (x.r.maju) return x.r;
      if (x.r.kunci) await berlayarLagi();
    }
    return null;
  };

  // ---- 34: Benteng Berjalan (IKN) ----
  let s = await st(a); assert(s.d.n === 34 && s.d.c === 'ikn' && s.d.cine === 'mk_benteng', 'langkah 34');
  await taruh(a, 'toogood');
  await H.expectError(() => a.call('api_mahkota', ['maju', 33, 'ok']), /Tidak ada yang perlu/);
  await taruh(a, 'ikn');
  await a.call('api_mahkota', ['maju', 33, 'ok']);

  // ---- 35: setor bahan pengalih di TooGood ----
  s = await st(a); assert(s.d.n === 35 && s.d.setorBahan === true, 'langkah 35');
  await taruh(a, 'toogood');
  await H.expectError(() => a.call('api_mahkota', ['maju', 34, 'ok']), /Bahan pengalih masih kurang: 20 Besi, 10 Mesiu, 20 Oli Hitam/);
  await H.sql(`select game.adjust_inventory($1, 'oli_hitam', 20)`, [a.id]);
  await H.sql(`select game.adjust_inventory($1, 'besi', 25)`, [a.id]);
  await H.expectError(() => a.call('api_mahkota', ['maju', 34, 'ok']), /10 Mesiu/);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 10)`, [a.id]);
  await a.call('api_mahkota', ['maju', 34, 'ok']);
  assert((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'besi'), 0) q`, [a.id])).q === 5, 'bahan terpakai persis');
  assert((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'), 0) q`, [a.id])).q === 0, 'Oli Hitam terpakai');

  // ---- 36: genderang di Paradiso (nilai baik = satu kesempatan ulang heat) ----
  s = await st(a); assert(s.d.n === 36 && s.d.g === 'genderang', 'langkah 36');
  await taruh(a, 'paradiso');
  await a.call('api_mahkota', ['maju', 35, 'menang']);
  assert((await st(a)).ulang === 1, 'genderang memberi satu kesempatan ulang');

  // ---- 37: heat pertama di IKN ----
  s = await st(a); assert(s.d.n === 37 && s.d.race === 'patroli_kuat' && s.d.heat === true, 'langkah 37');
  await taruh(a, 'paradiso');
  await H.expectError(() => a.call('api_mahkota', ['balap', 36]), /Tidak ada yang perlu/);
  await taruh(a, 'ikn');
  // kalah pertama memakai kesempatan dari genderang
  let x = await balap(37, null);
  assert(x.r.maju === false && x.r.kunci === false && (await st(a)).ulang === 0, 'kalah pertama memakai kesempatan genderang');
  // kalah kedua mengunci: harus berlayar lagi
  x = await balap(37, null);
  assert(x.r.maju === false && x.r.kunci === true, 'kalah kedua mengunci gerbang');
  await H.expectError(() => a.call('api_mahkota', ['balap', 36]), /Mundur ke laut lepas/);
  await a.call('api_setSail', ['joungjava']);
  await taruh(a, 'ikn');
  assert(!(await st(a)).data.heatKunci, 'berlayar membuka kunci heat');
  let r = await menangkan(37);
  assert(r && (await st(a)).step === 37, 'menang heat pertama');

  console.log('lolos 37');
  // ---- 38: heat kedua (tidak dilewati karena memilih "maafkan") ----
  await H.sql(`update game.player_quests set data = data || '{"marlya":"maafkan"}'::jsonb where player_id = $1 and quest_id = 'mahkota'`, [a.id]);
  s = await st(a); assert(s.d.n === 38, 'heat kedua ada untuk jalur maafkan');
  r = await menangkan(38);
  assert(r && (await st(a)).step === 38, 'menang heat kedua');

  console.log('lolos 38');
  // ---- 39: Juru Sita, daun hijau lebar karena "maafkan" ----
  s = await st(a); assert(s.d.n === 39 && s.d.race === 'cangcimen_final' && s.d.lebarBila === 'maafkan', 'langkah 39');
  const mulai = await a.call('api_mahkota', ['balap', 38]);
  assert(mulai.lebar === true, 'Kunci Gelombang: daun hijau lebih lebar');
  await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [mulai.trek.run]);
  const kalah39 = await a.call('api_mahkota', ['selesai', 38, mulai.trek.run, []]);
  assert(kalah39.maju === false && kalah39.kunci === true, 'kalah di Juru Sita juga mengunci gerbang');
  await berlayarLagi();
  r = await menangkan(39);
  assert(r && (await st(a)).step === 39, 'menang lawan cangcimen di gerbang rantai');

  console.log('lolos 39');
  // ---- 40: stempel, hadiah, penutup ----
  s = await st(a); assert(s.d.n === 40 && JSON.stringify(s.d.pilih) === '["patahkan","dewan","marlya"]', 'langkah 40');
  await H.expectError(() => a.call('api_mahkota', ['maju', 39, 'ok']), /Keputusannya ada di tanganmu/);
  await H.expectError(() => a.call('api_mahkota', ['pilih', 39, 'simpan']), /tidak dikenali/);
  const g0 = await gold(a);
  r = await a.call('api_mahkota', ['pilih', 39, 'dewan']);
  assert(r.maju === true && r.tamat === true && r.gold === 300000 && r.tanda === 'sagakeempat', 'hadiah Q19 + tanda jasa');
  assert((await gold(a)) === g0 + 300000, 'gold masuk');
  s = await st(a);
  assert(s.step === 40 && s.tamat === true && s.d === null && s.data.stempel === 'dewan', 'saga tamat, pilihan tersimpan');
  assert((await one(`select done_at is not null d from game.player_quests where player_id = $1 and quest_id = 'mahkota'`, [a.id])).d === true, 'quest ditandai tamat');

  // ---- sesudah tamat ----
  const m = await one('select * from game.mh_player where player_id = $1', [a.id]);
  assert(m.krisis === false && m.tembus === false && m.gelap === false, 'Krisis Monopoli padam');
  assert((await a.call('api_cukai', ['status'])).cukai === null, 'tanda CUKAI hilang dari peta');
  assert(s.jolt === false && s.penuh === false, 'Mesin Jolt pinjaman dilepas');
  assert(Math.abs(Number((await one('select game.ship_json($1) j', [a.id])).j.TravelMul) - 1) < 1e-9, 'waktu tempuh kembali normal');
  assert((await one('select game.trek_kapal($1) k', [a.id])).k === 'jolt', 'kapal Trektrek-an kembali ke profil dasar');
  await taruh(a, 'zentul');
  const trek = (await a.call('api_trek', ['status'])).trek;
  assert(JSON.stringify(trek.lawan) === '["pariopelan","kapalmber","cangcimen","yaptob"]', 'Sirkuit terbuka penuh: ' + JSON.stringify(trek.lawan));
  assert((await one(`select game.zentul_open($1) z`, [a.id])).z === true, 'Zentul tetap terbuka');

  // Set Kedai "Jaring Putus"
  const kd = await one(`select game.kd_list($1) l`, [a.id]);
  const set4 = kd.l.items.filter((i) => i.set === 'jaring_putus');
  assert(set4.length === 5 && set4.every((i) => !i.locked), 'Set Jaring Putus terbuka: ' + set4.length);
  assert((await one(`select game.kd_set_name('jaring_putus') n`)).n === 'Set Jaring Putus', 'nama set');

  // pemain lain belum melihat set itu
  const b = await H.user('q19biasa'); await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  const kdb = await one(`select game.kd_list($1) l`, [b.id]);
  assert(kdb.l.items.filter((i) => i.set === 'jaring_putus').length === 0, 'set tersembunyi untuk yang belum tamat');
  assert(kdb.l.items.length > 20, 'barang kedai lain tetap tampil');

  console.log('lolos tamat');
  // ---- jalur "kabarkan" melewati heat kedua ----
  await one(`select game.admin_mahkota('q19kapten', 37) s`);
  await H.sql(`update game.player_quests set data = data || '{"marlya":"kabarkan"}'::jsonb where player_id = $1 and quest_id = 'mahkota'`, [a.id]);
  await taruh(a, 'ikn');
  s = await st(a);
  assert(s.step === 37 && s.d.n === 39, 'jalur kabarkan: heat kedua dilewati');
  r = await menangkan(39);
  assert(r && r.lewati === true && (await st(a)).step === 39, 'langsung ke Juru Sita');

  console.log('0079 mahkota q19: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
