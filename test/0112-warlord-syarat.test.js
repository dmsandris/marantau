// 0112 Syarat item Warlord per komponen + prasyarat Meriam (Mesin & Lambung dulu).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const qty = async (u, it) => Number((await H.sql(`select coalesce(sum(qty),0) q from game.inventory where player_id = $1 and item_id = $2`, [u.id, it]))[0].q);
  const gerak = (u) => H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id]);
  const a = await H.user('syarat1');
  await a.call('api_createCharacter', ['Syarat Warlord', 'merchant']);
  await H.sql(`update game.players set gold = 40000000 where player_id = $1`, [a.id]);
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 2.4 * 60 * 60000)]);
  await one(`select game.admin_mahkota('syarat1', 27) s`);
  const m = `jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0)`;
  await H.sql(`update game.players set ship_upgrades = jsonb_build_object('speed', ${m}, 'cargo', ${m}, 'condition', ${m}, 'cannons', ${m}) where player_id = $1`, [a.id]);
  await gerak(a);
  const st = async () => (await a.call('api_warlord', ['status'])).warlord;

  // status membawa syarat per komponen
  const w = await st();
  const k = (g) => w.komponen.find((x) => x.grup === g);
  const peta = (g) => Object.fromEntries(k(g).bahan.map((b) => [b.id, b.n]));
  assert(k('speed').oli === 10 && peta('speed').qi_mk_gigi === 6, 'Mesin: 10 Oli + 6 Gigi Jaring');
  assert(k('cargo').oli === 15 && peta('cargo').besi === 60 && peta('cargo').qi_mk_rantai === 12, 'Palka: 15 Oli + 60 Besi + 12 Rantai Biru');
  assert(k('condition').oli === 20 && peta('condition').besi === 30 && peta('condition').qi_mk_rantai === 12, 'Lambung: 20 Oli + 30 Besi + 12 Rantai Biru');
  assert(k('cannons').oli === 15 && peta('cannons').mesiu === 30 && peta('cannons').besi === 10, 'Meriam: 15 Oli + 30 Mesiu + 10 Besi');
  assert(w.komponen.every((x) => x.gold === 2500000), 'gold tetap 2,5 jt semua');
  assert(k('cannons').prasyarat.map((p) => p.grup).join() === 'speed,condition' && k('cannons').prasyaratOk === false, 'Meriam punya prasyarat Mesin + Lambung');
  assert(k('cargo').prasyaratOk === true && k('speed').prasyaratOk === true, 'komponen lain tanpa prasyarat');

  // batas simpan bahan tidak diubah (12) dan cukup untuk syarat Rantai Biru
  const cap = Number((await one(`select value from game.config where key = 'WarlordDropMax'`)).value);
  assert(cap === 12, 'batas simpan bahan tetap 12: ' + cap);

  // sediakan semua bahan
  await H.sql(`select game.adjust_inventory($1, 'oli_hitam', 100)`, [a.id]);
  await H.sql(`select game.adjust_inventory($1, 'besi', 100)`, [a.id]);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 30)`, [a.id]);
  await H.sql(`select game.item_adjust($1, 'qi_mk_rantai', 12)`, [a.id]);
  await H.sql(`select game.item_adjust($1, 'qi_mk_gigi', 6)`, [a.id]);

  // Meriam ditolak walau semua bahan ada: prasyarat belum
  await H.expectError(() => a.call('api_warlord', ['bangun', 'cannons']), /paling akhir.*Mesin Jolt Warlord dan Lambung Warlord/);
  await a.call('api_warlord', ['bangun', 'speed']);
  await H.expectError(() => a.call('api_warlord', ['bangun', 'cannons']), /paling akhir.*Lambung Warlord/);

  // syarat tiap bahan ditagih
  await H.sql(`select game.item_adjust($1, 'qi_mk_rantai', -1)`, [a.id]);           // 11 < 12
  await H.expectError(() => a.call('api_warlord', ['bangun', 'cargo']), /12 Rantai Biru/);
  await H.sql(`select game.item_adjust($1, 'qi_mk_rantai', 1)`, [a.id]);

  // Palka: -15 Oli, -60 Besi, -15 Rantai, -2,5 jt gold
  const g0 = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  let r = await a.call('api_warlord', ['bangun', 'cargo']);
  assert(Number(r.newGold) === g0 - 2500000, 'Palka: gold 2,5 jt');
  assert((await qty(a, 'oli_hitam')) === 100 - 10 - 15 && (await qty(a, 'besi')) === 40 && (await qty(a, 'qi_mk_rantai')) === 0, 'Palka memakai 15 Oli, 60 Besi, 12 Rantai');

  // Lambung: 20 Oli + 30 Besi + 15 Rantai
  await H.sql(`select game.item_adjust($1, 'qi_mk_rantai', 12)`, [a.id]);
  await a.call('api_warlord', ['bangun', 'condition']);
  assert((await qty(a, 'oli_hitam')) === 75 - 20 && (await qty(a, 'besi')) === 10 && (await qty(a, 'qi_mk_rantai')) === 0, 'Lambung memakai 20 Oli, 30 Besi, 12 Rantai');

  // Meriam: 15 Oli + 30 Mesiu + 10 Besi
  r = await a.call('api_warlord', ['bangun', 'cannons']);
  assert(r.warlord.penuh === true, 'empat komponen = penuh');
  assert((await qty(a, 'oli_hitam')) === 55 - 15 && (await qty(a, 'mesiu')) === 0 && (await qty(a, 'besi')) === 0, 'Meriam memakai 15 Oli, 30 Mesiu, 10 Besi');

  console.log('0112 warlord syarat: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
