// 0078 Warlord: tahap terakhir kapal (TierNum 6), syarat, bahan, efek, dan pagar HP duel.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const ship = async (u) => (await one('select game.ship_json($1) j', [u.id])).j;
  const wl = async (u) => (await u.call('api_warlord', ['status'])).warlord;

  const a = await H.user('wlkapten'), b = await H.user('wlbiasa');
  await a.call('api_createCharacter', ['Panglima Laut', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  for (const u of [a, b]) {
    await H.sql(`update game.players set gold = 30000000 where player_id = $1`, [u.id]);
    await H.sql(`update game.ships set cargo_capacity = 2000 where player_id = $1`, [u.id]).catch(() => { });
  }

  // tertutup sebelum langkah 27
  assert((await wl(a)) === null, 'Garasi Warlord tertutup');
  await H.expectError(() => a.call('api_warlord', ['bangun', 'speed']), /masih terkunci/);
  const dasar = await ship(a);
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 2.4 * 60 * 60000)]);
  await one(`select game.admin_mahkota('wlkapten', 27) s`);

  let w = await wl(a);
  assert(w && w.buka === true && w.komponen.length === 4 && w.komponen.every((k) => !k.punya && !k.siap), 'Garasi terbuka, belum ada komponen');
  assert(w.komponen.find((k) => k.grup === 'speed').bahanId === 'qi_mk_gigi' && w.komponen.find((k) => k.grup === 'condition').bahanId === 'qi_mk_rantai', 'bahan khusus');

  // syarat: grup harus mentok + di Zentul + bahan
  await taruh(a, 'zentul');
  await H.expectError(() => a.call('api_warlord', ['bangun', 'speed']), /belum mentok/);
  const mentok = `jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0)`;
  await H.sql(`update game.players set ship_upgrades = jsonb_build_object('speed', ${mentok}, 'cargo', ${mentok}, 'condition', ${mentok}, 'cannons', ${mentok}) where player_id = $1`, [a.id]);
  const mentokShip = await ship(a);
  assert(mentokShip.TierNum === 5, 'Tier V sebelum Warlord');
  await H.expectError(() => a.call('api_warlord', ['bangun', 'speed']), /Oli Hitam/);
  await H.sql(`select game.adjust_inventory($1, 'oli_hitam', 40)`, [a.id]);
  await H.expectError(() => a.call('api_warlord', ['bangun', 'speed']), /Gigi Jaring/);
  await H.sql(`select game.item_adjust($1, 'qi_mk_gigi', 6)`, [a.id]);
  await taruh(a, 'ikn');
  await H.expectError(() => a.call('api_warlord', ['bangun', 'speed']), /Hanya Yaptob/);
  await taruh(a, 'zentul');

  // bangun Mesin Jolt Warlord
  const g0 = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  let r = await a.call('api_warlord', ['bangun', 'speed']);
  assert(r.grup === 'speed' && Number(r.newGold) === g0 - 2500000, 'bayar 2,5 juta');
  assert(Number((await one(`select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'`, [a.id])).qty) === 30, 'Oli Hitam terpakai 10');
  assert((await H.sql(`select 1 from game.inventory where player_id = $1 and item_id = 'qi_mk_gigi' and qty > 0`, [a.id])).length === 0, 'Gigi Jaring terpakai 6');
  let s = await ship(a);
  assert(Number(s.SpeedMultiplier) === 0.2 && Number(mentokShip.SpeedMultiplier) === 0.24, 'batas waktu tempuh 25 -> 20 detik');
  assert(s.TierNum === 5, 'belum Tier VI sebelum empat komponen');
  await H.expectError(() => a.call('api_warlord', ['bangun', 'speed']), /sudah terpasang/);

  // tiga komponen lain
  await H.sql(`select game.item_adjust($1, 'qi_mk_rantai', 6)`, [a.id]);
  await H.sql(`select game.adjust_inventory($1, 'besi', 6)`, [a.id]);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 6)`, [a.id]);
  for (const g of ['cargo', 'condition', 'cannons']) await a.call('api_warlord', ['bangun', g]);
  s = await ship(a);
  assert(s.TierNum === 6 && s.Tier === 'VI' && (s.Warlord || []).length === 4, 'Tier VI setelah empat komponen');
  assert(Number(s.EffectiveCargo) === Number(mentokShip.EffectiveCargo) + Math.round(Number(s.Cargo) * 0.15), 'palka +15%');
  assert(Number(s.EffectiveMaxCondition) === Number(mentokShip.EffectiveMaxCondition) + 20, 'kondisi maks +20');
  assert(Number(s.DecayReductionPercent) === Math.min(60, Number(mentokShip.DecayReductionPercent) + 10), 'aus -10%');
  assert(Number(s.CannonBonusPercent) === Number(mentokShip.CannonBonusPercent) + 5 && Number(s.MaxCannonAmmo) === Number(mentokShip.MaxCannonAmmo) + 1, 'meriam +5% dan +1 amunisi');
  assert((await one('select game.trek_kapal($1) k', [a.id])).k === 'warlord', 'Trektrek-an memakai lambung Warlord');

  // pagar: HP duel tetap Tier V
  await H.sql(`insert into game.mp_presence(player_id, pub, f, s) values ($1, 'x', '{}'::jsonb, '{}'::jsonb)
    on conflict (player_id) do update set pub = 'x'`, [a.id]).catch(() => { });
  const f = (await one('select game.mp_fighter($1) f', [a.id])).f;
  if (f) {
    const hp5 = 80 + 5 * 20 + Math.round(Math.min(100, Number(f.cond)) / 5);
    assert(Number(f.maxHp) === hp5, 'HP duel dihitung Tier V: ' + f.maxHp + ' vs ' + hp5);
  }

  // pemain lain tidak tersentuh
  const sb = await ship(b);
  assert(sb.TierNum === dasar.TierNum && sb.Warlord === undefined && Number(sb.SpeedMultiplier) === Number(dasar.SpeedMultiplier), 'pemain tanpa Warlord identik');
  assert((await wl(b)) === null && (await one('select game.trek_kapal($1) k', [b.id])).k === 'jolt', 'pemain lain tanpa Garasi Warlord');

  console.log('0078 warlord: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
