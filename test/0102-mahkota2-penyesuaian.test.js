// 0102 Saga 4 Bagian II: jumlah barang baru & kalibrasi Yaptob 2 percobaan per hari game (barang sekali).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const beri = (u, id, n) => one('select game.adjust_inventory($1, $2, $3) x', [u.id, id, n]);
  const qty = async (u, id) => (await one('select game.item_qty($1, $2) q', [u.id, id])).q;
  const hariBaru = async () => {
    const len = Number((await one(`select value from game.config where key = 'GameDayLengthRealMinutes'`)).value);
    await H.sql(`update game.config set value = (value::bigint - $1::bigint)::text where key = 'WorldStartTimestamp'`, [Math.round(len * 60000)]);
  };
  const a = await H.user('mk2tempa');
  await a.call('api_createCharacter', ['Kapten Tempa', 'merchant']);
  await H.sql(`update game.config set value = 'mk2tempa' where key = 'FiturPenguji'`);
  const steps = (await one('select game.mk2_steps() s')).s;
  assert(steps[8].bahan.beras === 100, 'langkah 49: 100 Beras');
  assert(steps[9].bahan.besi === 30 && steps[9].bahan.mesiu === 35, 'langkah 50: 30 Besi + 35 Mesiu');
  assert(steps[10].bahan.oli_hitam === 20 && steps[10].bahan.tools === 10 && steps[10].batas === true, 'langkah 51: 20 Oli + 10 Perkakas, bertanda batas');

  await one(`select game.admin_mahkota2('mk2tempa', 50) s`);
  await H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null where player_id = $1`, [a.id]);
  await H.expectError(() => a.call('api_mahkota', ['coba', 50]), /Serahkan dulu barangnya/);
  await beri(a, 'oli_hitam', 25); await beri(a, 'tools', 10);
  let r = await a.call('api_mahkota', ['setor', 50]);
  assert(r.setor && r.lengkap && r.mahkota.step === 50, 'barang diterima, mini game menyusul');
  assert(await qty(a, 'oli_hitam') === 5 && await qty(a, 'tools') === 0, 'diambil 20 Oli + 10 Perkakas');
  r = await a.call('api_mahkota', ['coba', 50]);
  assert(r.coba && r.sisaHari === 1, 'percobaan 1');
  r = await a.call('api_mahkota', ['coba', 50]);
  assert(r.coba && r.sisaHari === 0, 'percobaan 2');
  await H.expectError(() => a.call('api_mahkota', ['coba', 50]), /terlalu panas, kembalilah besok/);
  await hariBaru();
  r = await a.call('api_mahkota', ['coba', 50]);
  assert(r.coba && r.sisaHari === 1, 'hari game baru: percobaan pulih tanpa setor ulang');
  r = await a.call('api_mahkota', ['setor', 50]);
  assert(r.lengkap && await qty(a, 'oli_hitam') === 5, 'setor ulang tidak menagih lagi');
  r = await a.call('api_mahkota', ['maju', 50, 'ok']);
  assert(r.maju && r.mahkota.step === 51, 'kalibrasi berhasil -> langkah 51 tuntas');
  await H.expectError(() => a.call('api_mahkota', ['coba', 51]), /Tidak ada yang perlu ditempa/);
  console.log('0102 mahkota2 penyesuaian: semua lulus');
})().catch(e => { console.error(e); process.exit(1); });
