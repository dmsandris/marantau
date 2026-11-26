// 0110 Perk Warlord: Palka (+15% kapasitas efektif), Lambung (batas aus 70), Meriam (batas peluang 97).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const ship = async (u) => (await one('select game.ship_json($1) j', [u.id])).j;
  const mentok = (cargoAcc, condAcc) => `jsonb_build_object('level', 5, 'tier', 4, 'accumulated', ${cargoAcc})`;
  const setUp = (u) => H.sql(`update game.players set ship_upgrades = jsonb_build_object(
    'speed', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0),
    'cargo', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 1902),
    'condition', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 1996),
    'cannons', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0)) where player_id = $1`, [u.id]);

  const a = await H.user('wpkapten'), b = await H.user('wpbiasa');
  await a.call('api_createCharacter', ['Perk Panglima', 'merchant']);
  await b.call('api_createCharacter', ['Perk Biasa', 'merchant']);
  await setUp(a); await setUp(b);
  const dasar = await ship(a);
  const cargoDasar = Number(dasar.Cargo), efDasar = Number(dasar.EffectiveCargo);
  assert(efDasar === cargoDasar + 1902, 'kapasitas efektif dasar = dasar + upgrade: ' + efDasar);

  // Palka Warlord
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'cargo')`, [a.id]);
  const p = await ship(a);
  const tambah = Number(p.EffectiveCargo) - efDasar;
  assert(tambah === Math.round((cargoDasar + 1902) * 0.15), 'Palka +15% dari kapasitas efektif: +' + tambah);
  assert(tambah > 250, 'Palka terasa (>250), dapat +' + tambah);
  assert(Number((await one('select game.effective_cargo($1) c', [a.id])).c) === Number(p.EffectiveCargo), 'effective_cargo (batas beli) ikut');
  assert(Number((await ship(b)).EffectiveCargo) === efDasar, 'pemain tanpa Palka Warlord tidak berubah');
  // buka Garasi Warlord (langkah 27), cara sama dengan tes 0078
  await H.sql(`update game.config set value = '1' where key = 'MahkotaOpen'`);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'ps14', 6, '{}', now() - interval '2 hours')
    on conflict (player_id, quest_id) do update set step = 6, done_at = now() - interval '2 hours'`, [a.id]);
  await H.sql(`update game.config set value = $1 where key = 'WorldStartTimestamp'`, [String(Date.now() - 2.4 * 60 * 60000)]);
  await one(`select game.admin_mahkota('wpkapten', 27) s`);
  const wlS = (await a.call('api_warlord', ['status'])).warlord;
  const efekPalka = wlS.komponen.find((k) => k.grup === 'cargo').efek;
  assert(efekPalka === 'Kapasitas palka +15% (+' + tambah + ' muatan)', 'teks efek Palka memuat angka nyata: ' + efekPalka);
  assert(wlS.komponen.find((k) => k.grup === 'speed').efek.includes('25'), 'efek komponen lain tidak berubah');

  // Lambung Warlord
  const dr0 = Number(dasar.DecayReductionPercent);
  assert(dr0 === 50, 'upgrade mentok: aus -50% (dapat ' + dr0 + ')');
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'condition')`, [a.id]);
  const l = await ship(a);
  assert(Number(l.DecayReductionPercent) === 60, 'Lambung Warlord: -10% jadi 60: ' + l.DecayReductionPercent);
  assert(Number((await ship(b)).DecayReductionPercent) === 50, 'tanpa Lambung Warlord tetap 50');
  assert(Number((await one(`select game.voy_decay_red($1) d`, [b.id])).d) === 50, 'voy_decay_red pemain biasa tetap 50');

  // Meriam Warlord
  const batas = async (sj) => Number((await one(`select game.voy_hit_max($1::jsonb) m`, [JSON.stringify(sj)])).m);
  assert((await batas({})) === 92 && (await batas({ Warlord: ['speed', 'cargo'] })) === 92, 'batas peluang 92 tanpa Meriam Warlord');
  assert((await batas({ Warlord: ['cannons'] })) === 97, 'batas peluang 97 dengan Meriam Warlord');
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'cannons')`, [a.id]);
  const m = await ship(a);
  assert(Array.isArray(m.Warlord) && m.Warlord.includes('cannons') && (await batas(m)) === 97, 'ship_json membawa Warlord -> batas 97');

  // Tembakan Meriam Warlord benar-benar bisa kena di atas 92% (pemain biasa tidak)
  const enc = { enemyLevel: 1, enemyName: 'uji', enemyMaxHp: 10000, enemyHp: 10000, maxAmmo: 3, ammoRemaining: 3, round: 1, dmgTaken: 1 };
  const stats = { Combat: 50 };
  const tembak = async (sj) => {
    let kena = 0; const N = 600;
    for (let i = 0; i < N; i++) {
      const r = (await one(`select game.voy_resolve_round('fire', $1::jsonb, $2::jsonb, $3::jsonb, 0::bigint) r`,
        [JSON.stringify(enc), JSON.stringify(stats), JSON.stringify(sj)])).r;
      if (Number(r.enemyDamage) > 0) kena++;
    }
    return kena / N;
  };
  const biasa = await tembak({ CannonBonusPercent: 80, CannonDmgMul: 1 });
  const wlRate = await tembak({ CannonBonusPercent: 85, CannonDmgMul: 1, Warlord: ['cannons'] });
  assert(biasa < 0.96, 'tanpa Warlord peluang ~92%: ' + biasa);
  assert(wlRate > biasa, 'Meriam Warlord peluang kena lebih tinggi (' + wlRate + ' vs ' + biasa + ')');

  console.log('0110 warlord perk aktif: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
