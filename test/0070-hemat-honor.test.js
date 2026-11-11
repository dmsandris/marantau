// Tide v55 (hemat honor_state): membuktikan keluaran TIDAK berubah.
// Dua database dibangun: satu berhenti di 0069 (versi lama), satu dengan 0070
// (versi baru). State pemain dibuat identik, lalu keluaran dibandingkan.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const H0 = require('./harness');

// Kunci yang bergantung jam dinding -> tidak ikut dibandingkan.
const VOLATILE = new Set(['lotResetMs']);
const norm = (v) => {
  if (Array.isArray(v)) return v.map(norm);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) { if (!VOLATILE.has(k)) o[k] = norm(v[k]); }
    return o;
  }
  return v;
};
const eq = (a, b) => JSON.stringify(norm(a)) === JSON.stringify(norm(b));

// Semua ambang tier dilewati: 0 (Tamu) s/d di atas tier tertinggi.
const REPS = [0, 1, 4.5, 5, 14.9, 15, 34, 35, 59.5, 60, 99, 100, 250];
const CITIES = ['sunda_empire', 'joungjava', 'bjorneo', 'skitraw', 'toogood', 'ikn', 'paradiso', 'marie_regal'];

async function build(withNew) {
  const H = await H0.create({ only: (f) => withNew || !f.startsWith('0070') });
  const u = await H.user('honorbench');
  await u.call('api_createCharacter', ['Kapten Honor', 'merchant']);
  await H.sql(`insert into game.config(key, value) values ('KehormatanOpen','1')
               on conflict (key) do update set value = '1'`);
  // reputasi berbeda di tiap pulau, menyentuh beberapa tier sekaligus
  const rep = {};
  CITIES.forEach((c, i) => { rep[c] = REPS[(i * 3) % REPS.length]; });
  await H.sql(`update game.players set reputation = $2::jsonb where player_id = $1`, [u.id, JSON.stringify(rep)]);
  await H.sql(`update game.player_location set city_id = 'bjorneo', destination_city_id = null where player_id = $1`, [u.id]);
  return { H, u, rep };
}

(async () => {
  const oldDb = await build(false);
  const newDb = await build(true);

  // 1) honor_city_json: setiap kombinasi pulau x reputasi harus sama persis
  let n = 0;
  for (const c of CITIES) {
    for (const r of REPS) {
      const a = (await oldDb.H.sql(`select game.honor_city_json($1,$2,$3) j`, [oldDb.u.id, c, r]))[0].j;
      const b = (await newDb.H.sql(`select game.honor_city_json($1,$2,$3) j`, [newDb.u.id, c, r]))[0].j;
      assert(eq(a, b), `honor_city_json beda di ${c} rep=${r}\nlama: ${JSON.stringify(a)}\nbaru: ${JSON.stringify(b)}`);
      n++;
    }
  }
  console.log(`  honor_city_json: ${n} kombinasi identik`);

  // 2) honor_state utuh, di beberapa kota tempat pemain berdiri
  for (const here of ['bjorneo', 'sunda_empire', 'ikn', 'marie_regal']) {
    await oldDb.H.sql(`update game.player_location set city_id = $2 where player_id = $1`, [oldDb.u.id, here]);
    await newDb.H.sql(`update game.player_location set city_id = $2 where player_id = $1`, [newDb.u.id, here]);
    const a = (await oldDb.H.sql(`select game.honor_state($1) j`, [oldDb.u.id]))[0].j;
    const b = (await newDb.H.sql(`select game.honor_state($1) j`, [newDb.u.id]))[0].j;
    assert(a !== null && b !== null, 'honor_state tidak boleh null saat fitur hidup');
    assert(eq(a, b), `honor_state beda saat di ${here}\nlama: ${JSON.stringify(norm(a))}\nbaru: ${JSON.stringify(norm(b))}`);
    // kunci penting benar-benar ada (bukan dua-duanya kosong)
    assert(Array.isArray(b.cities) && b.cities.length > 0, 'daftar cities terisi');
    assert(b.here && b.here.id === here, 'blok here menunjuk kota sekarang');
    assert(Object.prototype.hasOwnProperty.call(b.here, 'lotMax'), 'here punya lotMax');
    assert(Object.prototype.hasOwnProperty.call(b.here, 'goods'), 'here punya goods');
  }
  console.log('  honor_state: identik di 4 kota');

  // 3) fitur mati -> tetap null, seperti sebelumnya
  for (const d of [oldDb, newDb]) {
    await d.H.sql(`update game.config set value = '0' where key = 'KehormatanOpen'`);
    await d.H.sql(`delete from game.config where key = 'FiturPenguji'`);
  }
  const an = (await oldDb.H.sql(`select game.honor_state($1) j`, [oldDb.u.id]))[0].j;
  const bn = (await newDb.H.sql(`select game.honor_state($1) j`, [newDb.u.id]))[0].j;
  assert(an === null && bn === null, 'fitur mati -> null di kedua versi');

  // 4) pemain tanpa karakter -> null
  const ax = (await oldDb.H.sql(`select game.honor_state(gen_random_uuid()) j`))[0].j;
  const bx = (await newDb.H.sql(`select game.honor_state(gen_random_uuid()) j`))[0].j;
  assert(ax === null && bx === null, 'pemain tak dikenal -> null di kedua versi');

  console.log('0070 hemat honor: keluaran identik dengan versi lama.');
})().catch((e) => { console.error(e); process.exit(1); });
