// 0086 Rupa kapal: ship_visual membawa tier (1..5) dan wl (komponen Warlord) tanpa mengubah kunci lama.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const vis = async (u) => (await one('select game.ship_visual($1) j', [u.id])).j;
  const ship = async (u) => (await one('select game.ship_json($1) j', [u.id])).j;
  const lv = (n) => `jsonb_build_object('level', ${n}, 'tier', 1, 'accumulated', 0)`;
  const setUp = (u, a, b, c, d) => H.sql(`update game.players set ship_upgrades = jsonb_build_object('speed', ${lv(a)}, 'cargo', ${lv(b)}, 'condition', ${lv(c)}, 'cannons', ${lv(d)}) where player_id = $1`, [u.id]);

  const a = await H.user('rupakapten'), b = await H.user('rupabiasa');
  await a.call('api_createCharacter', ['Rupa Panglima', 'merchant']);
  await b.call('api_createCharacter', ['Rupa Biasa', 'pirate']);

  // kapal awal: Tier I, tanpa Warlord, kunci lama utuh
  let v = await vis(a);
  assert(v.tier === 1 && Array.isArray(v.wl) && v.wl.length === 0, 'kapal awal Tier I tanpa Warlord: ' + JSON.stringify([v.tier, v.wl]));
  for (const k of ['look', 'up', 'name', 'legend', 'kd']) assert(k in v, 'kunci lama masih ada: ' + k);
  const inti = (await one('select game.ship_visual_inti($1) j', [a.id])).j;
  for (const k of Object.keys(inti)) assert(JSON.stringify(inti[k]) === JSON.stringify(v[k]), 'kunci lama tidak berubah: ' + k);
  assert((await one('select game.ship_visual($1) j', ['00000000-0000-0000-0000-000000000000'])).j === null, 'pemain tak dikenal -> null');

  // tier mengikuti rata-rata Level, sama dengan TierNum di ship_json
  for (const [lvls, t] of [[[1, 1, 1, 1], 1], [[2, 2, 2, 1], 1], [[2, 2, 2, 2], 2], [[5, 3, 2, 2], 3], [[4, 4, 4, 4], 4], [[5, 5, 5, 4], 4], [[5, 5, 5, 5], 5]]) {
    await setUp(a, ...lvls);
    v = await vis(a);
    const s = await ship(a);
    assert(v.tier === t && s.TierNum === t, 'Level ' + lvls.join('/') + ' -> Tier ' + t + ', dapat ' + v.tier + ' / ' + s.TierNum);
  }

  // komponen Warlord satu per satu; tier rupa tetap 5 walau TierNum jadi 6
  const mentok = `jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0)`;
  await H.sql(`update game.players set ship_upgrades = jsonb_build_object('speed', ${mentok}, 'cargo', ${mentok}, 'condition', ${mentok}, 'cannons', ${mentok}) where player_id = $1`, [a.id]);
  const sBefore = await ship(a);
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'speed')`, [a.id]);
  v = await vis(a);
  assert(v.tier === 5 && JSON.stringify(v.wl) === '["speed"]', 'satu komponen: ' + JSON.stringify(v.wl));
  assert(v.up.speed === 20 && v.up.cannons === 20, 'langkah upgrade tetap 20');
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'cannons'), ($1, 'cargo'), ($1, 'condition')`, [a.id]);
  v = await vis(a);
  assert(v.tier === 5 && v.wl.length === 4 && ['cannons', 'cargo', 'condition', 'speed'].every((g) => v.wl.includes(g)), 'empat komponen: ' + JSON.stringify(v.wl));
  const sAfter = await ship(a);
  assert(sAfter.TierNum === 6, 'TierNum server tetap 6 saat Warlord lengkap');
  // 0086 tidak menyentuh angka: yang berubah hanya efek 0078 yang memang sudah ada
  assert(Number(sAfter.Combat) === Number(sBefore.Combat) && Number(sAfter.Armor) === Number(sBefore.Armor) && Number(sAfter.Cargo) === Number(sBefore.Cargo), 'angka dasar kapal tidak berubah');

  // ikut ke state pemain dan ke presence (kapten lain melihat rupa yang sama)
  const st = await a.call('api_getGameState', [null]);
  assert(st.shipVisual && st.shipVisual.tier === 5 && st.shipVisual.wl.length === 4, 'shipVisual di state membawa tier + wl');
  await H.sql('select game.mp_touch($1)', [a.id]);
  const pr = await one('select s from game.mp_presence where player_id = $1', [a.id]);
  assert(pr && pr.s && pr.s.tier === 5 && pr.s.wl.length === 4, 'presence membawa tier + wl: ' + JSON.stringify(pr && pr.s && [pr.s.tier, pr.s.wl]));

  // pemain lain tidak tersentuh
  const vb = await vis(b);
  assert(vb.tier === 1 && vb.wl.length === 0, 'pemain lain tetap Tier I tanpa Warlord');

  // simpan tampilan tetap jalan dan hasilnya membawa kunci baru
  const r = await a.call('api_saveShipLook', [{ hull: '#1f3a5a', emblem: 'star' }, 'Panglima Biru']);
  assert(r.visual.look.hull === '#1f3a5a' && r.visual.tier === 5 && r.visual.wl.length === 4 && r.visual.name === 'Panglima Biru', 'api_saveShipLook membawa tier + wl');

  console.log('0086 rupa warlord: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
