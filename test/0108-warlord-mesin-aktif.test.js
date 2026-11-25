// 0108 Mesin Jolt Warlord benar-benar memangkas waktu tempuh (25 -> 20 dtk pulau terdekat).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const mentok = `jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0)`;
  const setMentok = (u) => H.sql(`update game.players set ship_upgrades = jsonb_build_object('speed', ${mentok}, 'cargo', ${mentok}, 'condition', ${mentok}, 'cannons', ${mentok}) where player_id = $1`, [u.id]);
  const dtk = async (u, jarak) => Number((await one(
    `select game.voy_travel_seconds(${jarak}, game.ship_json($1)) s`, [u.id])).s);

  const a = await H.user('wmpanglima'), b = await H.user('wmbiasa');
  await a.call('api_createCharacter', ['Panglima Cepat', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Mentok', 'merchant']);
  await setMentok(a); await setMentok(b);
  const { dmin, dmax } = await one('select dmin, dmax from game.voy_dist_range()');

  const b0 = await dtk(b, dmin), a0 = await dtk(a, dmin);
  assert(b0 === 25 && a0 === 25, 'sebelum Warlord: pulau terdekat 25 dtk (' + a0 + '/' + b0 + ')');

  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'speed')`, [a.id]);
  const a1 = await dtk(a, dmin), b1 = await dtk(b, dmin);
  assert(a1 === 20, 'Mesin Jolt Warlord: pulau terdekat 20 dtk, dapat ' + a1);
  assert(b1 === 25, 'kapten tanpa Warlord tetap 25 dtk, dapat ' + b1);

  const aJauh = await dtk(a, dmax), bJauh = await dtk(b, dmax);
  assert(aJauh < bJauh && Math.abs(aJauh - Math.round(bJauh * 0.8)) <= 1, 'rute jauh ikut -20%: ' + aJauh + ' vs ' + bJauh);

  // komponen lain saja tidak mempercepat
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'cargo')`, [b.id]);
  assert((await dtk(b, dmin)) === 25, 'Palka Warlord tidak mengubah waktu tempuh');

  // Black Pearl tetap 15
  const pearl = Number((await one(`select game.voy_travel_seconds(${dmin}, '{"Legend":"pearl","Warlord":["speed"]}'::jsonb) s`)).s);
  assert(pearl === 15, 'Black Pearl tetap 15 dtk, dapat ' + pearl);

  // api_getSailOptions memakai waktu baru
  const opt = await a.call('api_getSailOptions', []);
  const list = opt.destinations || opt.options || opt;
  if (Array.isArray(list) && list.length) {
    const min = Math.min(...list.map((d) => Number(d.etaSeconds)).filter((x) => x > 0));
    assert(min <= 24, 'daftar tujuan menampilkan waktu Warlord, tercepat ' + min);
  }

  console.log('0108 warlord mesin aktif: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
