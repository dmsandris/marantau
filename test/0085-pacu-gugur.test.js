// 0085 Pacu Gugur: babak gugur mingguan lawan AI, Sirkuit solo ditutup, hadiah harian dicabut.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const kota = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const gold = async (u) => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const oli = async (u) => Number((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'), 0) q`, [u.id])).q);

  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  const a = await H.user('pg_juara'), b = await H.user('pg_biasa');
  await a.call('api_createCharacter', ['Kapten Juara', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  await H.sql(`update game.players set gold = 1000000 where player_id = $1`, [a.id]);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1,'ps14',6,'{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await one(`select game.admin_mahkota('pg_juara', 40) s`);
  await kota(a, 'zentul');

  // Sirkuit solo lawan AI sudah ditutup, hadiah harian dicabut
  assert((await one('select game.trek_boleh($1) b', [a.id])).b === false, 'Sirkuit solo ditutup walau sudah tamat');
  assert(await H.expectError(() => a.call('api_trek', ['status'])), 'api_trek ditolak');
  assert((await one(`select game.trek_hadiah($1, 'pariopelan') h`, [a.id])).h === null, 'hadiah harian dicabut');
  assert((await one('select game.gugur_state($1) s', [b.id])).s === null, 'yang belum tamat: tanpa gelanggang');
  assert(await H.expectError(() => b.call('api_gugur', ['status'])), 'yang belum tamat ditolak');

  // status gelanggang
  let s = (await a.call('api_gugur', ['status'])).gugur;
  assert(s.buka && s.siap && s.babak === 1 && s.akhir === 4 && s.lawan === 'pariopelan' && s.status === 'jalan', 'babak 1 vs Pariopelan: ' + JSON.stringify(s));
  assert(s.kapal === 'penuh' && s.hadiah.oli === 12 && s.hadiah.gold === 120000 && s.menang === 0, 'kapal gelanggang + hadiah: ' + JSON.stringify(s.hadiah));

  const balap = async (skill) => {
    const m = await a.call('api_gugur', ['mulai']);
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [m.run.run]);
    const log = skill ? human((await one(`select game.trek_ships() -> $1 s`, [m.run.ship])).s, m.run.seed, skill).log : [];
    return a.call('api_gugur', ['selesai', m.run.run, log]);
  };
  // kalah = gugur (memang begitu aturannya); untuk menguji babak berikutnya, baris pekan disetel ulang
  const menang = async (max) => {
    const b = ((await a.call('api_gugur', ['status'])).gugur).babak;
    for (let i = 0; i < (max || 150); i++) {
      const r = await balap(SKILL.jago);
      if (r.hasil.win) return r;
      await H.sql(`update game.gugur_run set status = 'jalan', babak = $2 where player_id = $1 and week = game.gugur_week()`, [a.id, b]);
    }
    return null;
  };

  // babak 1-3: naik babak tiap menang
  let r = await menang();
  assert(r.hasil.win && r.gugur.babak === 2 && r.gugur.lawan === 'kapalmber' && r.gugur.menang === 1 && r.gugur.usTotal > 0, 'babak 2: ' + JSON.stringify(r.gugur));
  assert(r.hadiah == null, 'belum ada hadiah sebelum babak akhir');
  r = await menang();
  assert(r.hasil.win && r.gugur.babak === 3 && r.gugur.lawan === 'cangcimen', 'babak 3');
  r = await menang();
  assert(r.hasil.win && r.gugur.babak === 4 && r.gugur.lawan === 'yaptob', 'babak 4 vs Yaptob');

  // babak akhir: Yaptob sangat sulit — kalau tak terkalahkan, pakai suntikan agar jalur juara tetap teruji
  const g0 = await gold(a), o0 = await oli(a);
  r = await menang(400);
  assert(r && r.hasil.win, 'Yaptob terkalahkan dalam jatah percobaan');
  assert(r.gugur.status === 'juara' && r.hadiah.oli === 12 && r.hadiah.gold === 120000, 'juara + hadiah: ' + JSON.stringify(r.gugur.status));
  assert((await gold(a)) >= g0 + 120000 && (await oli(a)) === o0 + 12, 'hadiah masuk ke kapal');
  assert(r.gugur.lawan === null && r.gugur.didapat.gold === 120000, 'status juara: tidak ada lawan lagi');
  assert(await H.expectError(() => a.call('api_gugur', ['mulai'])), 'juara tidak bisa ulang pekan ini');

  // papan juara pekan ini
  const papan = (await one('select game.gugur_papan() p')).p;
  assert(papan.length === 1 && papan[0].nama === 'Kapten Juara' && papan[0].us > 0, 'papan juara: ' + JSON.stringify(papan));

  // pekan baru: jatah pulih
  await H.sql(`update game.gugur_run set week = week - 1 where player_id = $1`, [a.id]);
  s = (await a.call('api_gugur', ['status'])).gugur;
  assert(s.babak === 1 && s.status === 'jalan' && s.lawan === 'pariopelan', 'pekan baru: mulai dari babak 1');
  assert((await one('select game.gugur_papan() p')).p.length === 0, 'papan pekan ini kosong lagi');

  // kalah = gugur sampai pekan depan
  r = await balap(null);
  assert(!r.hasil.win && r.gugur.status === 'gugur' && r.gugur.lawan === null, 'kalah = gugur: ' + JSON.stringify(r.gugur.status));
  assert(await H.expectError(() => a.call('api_gugur', ['mulai'])), 'yang gugur tidak bisa balapan lagi');

  // di luar Zentul / berlayar / gerbang tutup
  await H.sql(`update game.gugur_run set status = 'jalan', babak = 1 where player_id = $1 and week = game.gugur_week()`, [a.id]);
  await kota(a, 'ikn');
  assert(await H.expectError(() => a.call('api_gugur', ['mulai'])), 'di luar Zentul ditolak');
  assert(((await a.call('api_gugur', ['status'])).gugur).siap === false, 'status: belum siap di luar Zentul');
  await kota(a, 'zentul');
  await H.sql(`update game.config set value = '1' where key = 'GugurTutup'`);
  assert(await H.expectError(() => a.call('api_gugur', ['mulai'])), 'GugurTutup menutup gelanggang');
  assert(((await a.call('api_gugur', ['status'])).gugur).buka === false, 'status: gelanggang tutup');
  await H.sql(`update game.config set value = '0' where key = 'GugurTutup'`);

  // run gelanggang tidak bisa diselesaikan lewat jalur lain
  const m = await a.call('api_gugur', ['mulai']);
  await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [m.run.run]);
  assert(await H.expectError(() => a.call('api_trek', ['selesai', m.run.run, []])), 'run gugur tidak bisa lewat api_trek');

  console.log('0085 pacu gugur: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
