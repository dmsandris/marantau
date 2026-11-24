// Tide v67 · 0087: damage meriam ikut upgrade Cannons (Meriam Warlord x5), Lambung Warlord 3.200,
// Tony and Gank kabur di HP armada <= 10%. Bos quest, Duel Lambung, Serbuan, Perburuan Tony tidak kena.
const fs = require('fs'), path = require('path');
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const ship = async (u) => (await one('select game.ship_json($1) j', [u.id])).j;
  const gold = async (u) => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const muatan = async (u) => (await one('select coalesce(sum(qty), 0)::int n from game.inventory where player_id = $1', [u.id])).n;
  const cond = async (u) => Number((await one('select condition from game.ships where player_id = $1', [u.id])).condition);
  const cfg = (k, v) => H.sql(`update game.config set value = $2 where key = $1`, [k, String(v)]);
  const dekat = (a, b) => Math.abs(Number(a) - Number(b)) < 1e-9;

  // ---------------- config ----------------
  const c0 = Object.fromEntries((await H.sql(`select key, value from game.config where key in
    ('MeriamDmgPerLangkah', 'MeriamDmgWarlord', 'WarlordLambungBonus', 'TonyKaburPct', 'TonyCegatDmgKali', 'TonyFleetHp', 'TonyDmgTaken')`)).map(r => [r.key, r.value]));
  assert(c0.MeriamDmgPerLangkah === '0.05' && c0.MeriamDmgWarlord === '5' && c0.WarlordLambungBonus === '1104' && c0.TonyKaburPct === '10', 'kenop config baru: ' + JSON.stringify(c0));
  assert(c0.TonyFleetHp === '4000' && c0.TonyDmgTaken === '0.04', 'kenop lama Tony tidak diubah');

  // ---------------- 1. pengali per langkah ----------------
  for (const [s, k] of [[0, 1], [1, 1.05], [9, 1.45], [10, 1.5], [20, 2], [25, 2], [-3, 1]]) {
    assert(dekat((await one('select game.meriam_dmg_langkah($1) k', [s])).k, k), 'pengali langkah ' + s + ' = ' + k);
  }
  const a = await H.user('dmwarlord'), b = await H.user('dmbiasa');
  await a.call('api_createCharacter', ['Panglima Meriam', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  for (const u of [a, b]) await H.sql(`update game.players set gold = 900000000 where player_id = $1`, [u.id]);
  assert(dekat((await ship(b)).CannonDmgMul, 1), 'belum upgrade: x1');
  for (let i = 0; i < 9; i++) await b.call('api_shipUpgrade', ['cannons']);
  assert(dekat((await ship(b)).CannonDmgMul, 1.45), 'langkah 9: x1,45');
  let up = await b.call('api_getShipUpgrades', []);
  assert(/damage tembakan &times;1,45 &rarr; &times;1,50/.test(up.affordable.cannons.effect), 'teks efek kartu Cannons: ' + up.affordable.cannons.effect);
  assert(/Peluang menang \+/.test(up.affordable.cannons.effect) && !/damage/.test(up.affordable.condition.effect), 'teks lama tetap, grup lain tidak berubah');
  // GM bisa menyetel
  await cfg('MeriamDmgPerLangkah', 0.1);
  assert(dekat((await ship(b)).CannonDmgMul, 1.9), 'MeriamDmgPerLangkah bisa disetel');
  await cfg('MeriamDmgPerLangkah', 0.05);

  for (const g of ['condition', 'cannons', 'speed', 'cargo']) for (let i = 0; i < 20; i++) await a.call('api_shipUpgrade', [g]);
  const mentok = await ship(a);
  assert(dekat(mentok.CannonDmgMul, 2), 'Cannons mentok: x2');
  assert(Number(mentok.EffectiveMaxCondition) === 2096, 'Hull mentok tanpa Warlord: 2.096 (' + mentok.EffectiveMaxCondition + ')');
  up = await a.call('api_getShipUpgrades', []);
  assert(/damage tembakan &times;2,00$/.test(up.affordable.cannons.effect), 'teks efek mentok: ' + up.affordable.cannons.effect);

  // mesin ronde: damage tembakan kena = max_hp x (0,18..0,32) x pengali
  const kena = async (encX, shipX, n) => {
    const out = [];
    for (let i = 0; i < n; i++) {
      const r = (await one(`select game.voy_resolve_round('fire', $1::jsonb, '{"Combat": 100}'::jsonb, $2::jsonb, 0) r`, [
        JSON.stringify(Object.assign({ enemyLevel: 1, enemyName: 'kapal uji', enemyMaxHp: 1000, enemyHp: 1000, ammoRemaining: 5, maxAmmo: 5, round: 1 }, encX)),
        JSON.stringify(Object.assign({ CannonBonusPercent: 100 }, shipX))])).r;
      if (Number(r.enemyDamage) > 0) out.push(Number(r.enemyDamage));
    }
    return out;
  };
  const rentang = (arr, lo, hi, m) => assert(arr.length >= 10 && arr.every(x => x >= lo && x <= hi), m + ' di luar ' + lo + '..' + hi + ': ' + JSON.stringify(arr.slice(0, 12)));
  rentang(await kena({}, {}, 40), 180, 320, 'tanpa pengali');
  rentang(await kena({}, { CannonDmgMul: 1.45 }, 40), 261, 464, 'x1,45');
  rentang(await kena({}, { CannonDmgMul: 2 }, 40), 360, 640, 'x2');
  rentang(await kena({}, { CannonDmgMul: 5 }, 40), 900, 1600, 'Warlord x5');
  rentang(await kena({ dmgTaken: 0.5 }, { CannonDmgMul: 5 }, 40), 450, 800, 'x5 bertumpuk dengan dmgTaken musuh bernama');
  // bos quest tidak kena
  rentang(await kena({ boss: 'gap' }, { CannonDmgMul: 5 }, 40), 180, 320, 'bos quest tetap x1');
  rentang(await kena({ boss: 'induk', dmgTaken: 0.1 }, { CannonDmgMul: 5 }, 40), 18, 32, 'bos quest ber-dmgTaken tetap');

  // ---------------- 2. Meriam Warlord x5 (menggantikan), Lambung Warlord > 3000 ----------------
  await H.sql(`update game.ships set condition = 1048 where player_id = $1`, [a.id]);     // 50% dari 2.096
  await cfg('WarlordLambungBonus', 20);                                                   // keadaan lama (0078): +20
  const kota = (await one('select city_id from game.player_location where player_id = $1', [a.id])).city_id;
  await H.sql(`insert into game.mk_warlord(player_id, grup, hp87_at) values ($1, 'condition', null)`, [a.id]);
  await H.sql(`update game.mk_warlord set hp87_at = null where player_id = $1`, [a.id]);   // pemilik lama: belum bertanda
  await H.sql(`update game.ships set condition = 0 where player_id = $1`, [a.id]);
  const lamaMaks = Number((await ship(a)).EffectiveMaxCondition);
  const lamaPenuh = Number((await a.call('api_getRepairQuote', [kota])).cost);
  assert(lamaMaks === 2116 && lamaPenuh > 0, 'keadaan lama: kondisi maks 2.116, reparasi penuh ' + lamaPenuh);
  await H.sql(`update game.ships set condition = 1058 where player_id = $1`, [a.id]);     // 50% dari 2.116
  await H.sql(`insert into game.mp_presence(player_id, pub, f, s) values ($1, 'dmx', '{}'::jsonb, '{}'::jsonb)
    on conflict (player_id) do update set pub = 'dmx'`, [a.id]).catch(() => { });
  const f0 = (await one('select game.mp_fighter($1) f', [a.id])).f;
  await cfg('WarlordLambungBonus', 1104);

  // migrasi dijalankan ulang (seperti tiap deploy): pemilik lama dinaikkan proporsional, sekali saja
  const dir = path.join(__dirname, '..', 'supabase', 'migrations');
  const ulang = async () => { for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort()) await H.db.exec(fs.readFileSync(path.join(dir, f), 'utf8')); };
  await ulang();
  let s = await ship(a);
  assert(Number(s.EffectiveMaxCondition) === 3200 && Number(s.EffectiveMaxCondition) > 3000, 'Lambung Warlord: kondisi maks 3.200 (' + s.EffectiveMaxCondition + ')');
  assert(Number(s.Condition) === 1600 && Number(s.ConditionPct) === 50, 'kondisi pemilik lama naik proporsional: ' + s.Condition);
  assert((await one(`select hp87_at from game.mk_warlord where player_id = $1 and grup = 'condition'`, [a.id])).hp87_at, 'penanda terpasang');
  await ulang();
  s = await ship(a);
  assert(Number(s.Condition) === 1600 && Number(s.EffectiveMaxCondition) === 3200, 'idempotent: tidak naik dua kali (' + s.Condition + ')');
  assert((await H.sql(`select 1 from game.config where key in ('MeriamDmgPerLangkah', 'MeriamDmgWarlord', 'WarlordLambungBonus', 'TonyKaburPct', 'TonyCegatDmgKali')`)).length === 5, 'config tidak dobel');
  assert(dekat((await ship(b)).CannonDmgMul, 1.45) && Number((await ship(b)).EffectiveMaxCondition) === 100, 'pemain lain utuh setelah migrasi ulang');

  // pagar reparasi: reparasi penuh tidak lebih mahal dari sebelumnya; separuh rusak juga tidak
  await H.sql(`update game.ships set condition = 0 where player_id = $1`, [a.id]);
  let q = await a.call('api_getRepairQuote', [kota]);
  assert(Number(q.maxCondition) === 3200 && Number(q.missing) === 3200 && Number(q.cost) === lamaPenuh, 'reparasi penuh tetap ' + lamaPenuh + ' (jadi ' + q.cost + ')');
  await H.sql(`update game.ships set condition = 1600 where player_id = $1`, [a.id]);
  q = await a.call('api_getRepairQuote', [kota]);
  assert(Math.abs(Number(q.cost) - lamaPenuh / 2) <= 1, 'reparasi separuh = separuh biaya lama: ' + q.cost);
  const g0 = await gold(a);
  const rp = await a.call('api_repairShip', [kota]);
  assert(Number(rp.newCondition) === 3200 && Number(rp.goldSpent) === Number(q.cost) && (await gold(a)) === g0 - Number(q.cost), 'reparasi memulihkan ke 3.200 dengan biaya berpagar');
  // pemain tanpa Lambung Warlord: biaya reparasi tidak berubah (missing x tarif)
  await H.sql(`update game.ships set condition = 40 where player_id = $1`, [b.id]);
  const qb = await b.call('api_getRepairQuote', [kota]);
  assert(Number(qb.missing) === 60 && Math.abs(Number(qb.cost) / 60 - lamaPenuh / 2116) < 0.01, 'reparasi pemain biasa tetap: ' + JSON.stringify(qb));

  // HP Duel Lambung tidak berubah (Tier V, dari persen kondisi), atk tidak memakai pengali damage
  await H.sql(`update game.ships set condition = 1600 where player_id = $1`, [a.id]);
  const f1 = (await one('select game.mp_fighter($1) f', [a.id])).f;
  assert(Number(f1.maxHp) === Number(f0.maxHp) && Number(f1.maxHp) === 80 + 5 * 20 + 10, 'HP duel tetap (kondisi 50%): ' + f0.maxHp + ' -> ' + f1.maxHp);
  assert(dekat(f1.atk, f0.atk) && Number(f1.ammoMax) === Number(f0.ammoMax), 'serangan duel tetap');

  // komponen baru dipasang: kondisi ikut naik proporsional (pemicu), Meriam Warlord x5
  const c = await H.user('dmbaru'); await c.call('api_createCharacter', ['Kapten Baru Pasang', 'merchant']);
  await H.sql(`update game.players set gold = 900000000 where player_id = $1`, [c.id]);
  for (const g of ['condition', 'cannons']) for (let i = 0; i < 20; i++) await c.call('api_shipUpgrade', [g]);
  await H.sql(`update game.ships set condition = 524 where player_id = $1`, [c.id]);      // 25% dari 2.096
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'condition')`, [c.id]);
  s = await ship(c);
  assert(Number(s.EffectiveMaxCondition) === 3200 && Number(s.Condition) === 800, 'pasang baru: kondisi naik proporsional (' + s.Condition + ')');
  await ulang();
  assert(Number((await ship(c)).Condition) === 800, 'pasang baru tidak dinaikkan lagi oleh migrasi');
  assert(dekat((await ship(c)).CannonDmgMul, 2), 'Lambung Warlord saja: pengali meriam tetap dari langkah');
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'cannons')`, [a.id]);
  assert(dekat((await ship(a)).CannonDmgMul, 5), 'Meriam Warlord: x5 (menggantikan x2)');
  f0.atk5 = (await one('select game.mp_fighter($1) f', [a.id])).f.atk;
  assert(dekat(f0.atk5, Number(f0.atk) + 5 * 0.08), 'duel: Meriam Warlord hanya +5% lama, tanpa pengali damage');
  await cfg('MeriamDmgWarlord', 4);
  assert(dekat((await ship(a)).CannonDmgMul, 4), 'MeriamDmgWarlord bisa disetel');
  await cfg('MeriamDmgWarlord', 5);
  up = await a.call('api_getShipUpgrades', []);
  assert(/damage tembakan &times;5 \(Meriam Warlord\)/.test(up.affordable.cannons.effect), 'teks efek Meriam Warlord: ' + up.affordable.cannons.effect);
  assert((await one(`select game.wl_efek('cannons') t`)).t.startsWith('Damage tembakan ×5') && /Kondisi maks \+1\.104/.test((await one(`select game.wl_efek('condition') t`)).t), 'teks efek komponen Garasi');

  // ---------------- 3. jalur kode: hanya tempur laut biasa + pencegatan Tony ----------------
  const pakai = (await H.sql(`select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('game', 'public') and p.prosrc ~ 'CannonDmgMul|meriam_dmg_kali' order by 1`)).map(r => r.proname);
  // mk2_laut_enc (0103): Navy Tier 4 di tengah laut memakai jalur bos, pengali Meriam Warlord ditumpangkan manual (keputusan K2)
  assert(JSON.stringify(pakai) === JSON.stringify(['mk2_laut_enc', 'ship_json', 'tony_act', 'voy_resolve_round']),
    'pengali meriam hanya dipakai mesin ronde & tony_act (bukan raid/duel/serbuan): ' + pakai);
  const ronde = (await H.sql(`select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('game', 'public') and p.prosrc ~ 'voy_resolve_round' order by 1`)).map(r => r.proname);
  assert(ronde.every(n => /resolvecombat|voy_resolve_round/.test(n)), 'voy_resolve_round hanya dipanggil api_resolveCombat: ' + ronde);
  const raid = (await H.sql(`select count(*)::int n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('game', 'public') and (p.proname like 'th\\_%' or p.proname like 'api_tonyhunt%' or p.proname like 'dt\\_%' or p.proname like 'mp\\_duel%')
      and p.prosrc ~ 'TonyKaburPct|TonyCegatDmgKali|CannonDmgMul|meriam_dmg'`))[0].n;
  assert(raid === 0, 'Perburuan Tony / Serbuan / Duel tidak menyentuh kenop baru');

  // lewat api_resolveCombat: bajak laut biasa kena x5, bos quest tidak
  const hadang = async (u, enc) => H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = 'joungjava',
    depart_at = now() - interval '2 minutes', arrive_at = now() + interval '5 minutes', pending_encounter = $2::jsonb where player_id = $1`, [u.id, JSON.stringify(enc)]);
  await H.sql(`update game.character_stats set combat = 100 where player_id = $1`, [a.id]);
  const tembakApi = async (encX) => {
    const base = Object.assign({ enemyLevel: 1, enemyName: 'kapal uji', enemyMaxHp: 100000, enemyHp: 100000, dmgTaken: 0.01, maxAmmo: 99, ammoRemaining: 99, round: 1, rolledAt: 'x' }, encX);
    await hadang(a, base);
    const out = []; let hp = base.enemyHp;
    for (let i = 0; i < 30 && out.length < 12; i++) {
      const r = await a.call('api_resolveCombat', ['fire']);
      assert(r.ongoing, 'pertempuran uji masih berjalan: ' + JSON.stringify(r).slice(0, 200));
      if (Number(r.encounter.enemyHp) < hp) out.push(hp - Number(r.encounter.enemyHp));
      hp = Number(r.encounter.enemyHp);
    }
    return out;
  };
  rentang(await tembakApi({ randomPirate: true }), 900, 1600, 'api: bajak laut acak x5');
  rentang(await tembakApi({ hunter: true }), 900, 1600, 'api: Pemburu Tedsky x5');
  rentang(await tembakApi({ boss: 'gap' }), 180, 320, 'api: bos quest tetap x1');
  await H.sql(`update game.player_location set destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [a.id]);

  // ---------------- 4. Tony and Gank kabur di <= 10% ----------------
  await cfg('TonyPowderChance', 0); await cfg('TonyHitPctMin', 0); await cfg('TonyHitPctMax', 0);   // deterministik: tanpa gudang mesiu, tanpa balasan
  await H.sql(`insert into game.tony_raid(dest_city, start_at, end_at, chance, kabar, announce_victims)
               values ('toogood', now() - interval '1 hour', now() + interval '5 hours', 100, 'diam', true)`);
  const cegat = async (u, hp) => {
    await H.sql(`update game.player_location set city_id = 'sunda_empire', destination_city_id = 'toogood', depart_at = now() - interval '2 minutes',
                 arrive_at = now() - interval '1 second', pending_encounter = null where player_id = $1`, [u.id]);
    await H.sql(`update game.player_location set pending_encounter = game.tony_roll($1) || jsonb_build_object('enemyHp', $2::numeric) where player_id = $1`, [u.id, hp]);
    const e = (await one('select pending_encounter e from game.player_location where player_id = $1', [u.id])).e;
    assert(e && e.kind === 'tony' && Number(e.enemyMaxHp) === 4000 && e.boss === 'tony', 'encounter Tony terpasang');
    return e;
  };
  await H.sql(`select game.adjust_inventory($1, 'sugar', 7)`, [a.id]);
  await H.sql(`update game.players set gold = 123456 where player_id = $1`, [a.id]);
  const chat0 = (await one('select count(*)::int n from game.mp_chat')).n;
  const m0 = await muatan(a), k0 = await cond(a);

  // pemilik Meriam Warlord: damage per tembakan kena = 4000 x 0,04 x (0,18..0,32) x 5 x 2,8
  let e = await cegat(a, 4000), r, dm = [];
  for (let i = 0; i < 12; i++) {
    r = await a.call('api_tonyRaid', ['fire']);
    if (!r.ongoing) break;
    if (r.hit) dm.push(Number(r.damage));
    assert(Number(r.encounter.enemyHp) > 400, 'di atas 10% pertempuran berlanjut');
  }
  assert(dm.length >= 2 && dm.every(x => x >= 403 && x <= 717), 'damage Meriam Warlord ke armada Tony: ' + dm);
  // lanjut sampai armada tinggal <= 10%
  for (let i = 0; i < 40 && r.ongoing; i++) r = await a.call('api_tonyRaid', [Number(r.encounter.ammoRemaining) > 0 ? 'fire' : 'reload']);
  assert(r.ongoing === false && r.tony === true && r.result === 'repelled' && r.how === 'kabur' && r.success === true, 'Tony kabur: ' + JSON.stringify(r).slice(0, 300));
  assert(Number(r.enemyHp) <= 400 && Number(r.enemyHp) >= 1, 'armada tinggal <= 10%, tidak tenggelam: ' + r.enemyHp);
  assert(/hilang ke kabut/.test(r.message) && /utuh/.test(r.message) && !r.rob && r.gold === undefined, 'pesan cerita, tanpa rampasan / hadiah');
  assert((await gold(a)) === 123456 && Number(r.newGold) === 123456, 'gold tidak dirampas dan tidak bertambah');
  assert((await muatan(a)) === m0 && m0 >= 7, 'muatan utuh');
  assert((await one('select count(*)::int n from game.tony_victims')).n === 0, 'tony_victims tidak bertambah');
  assert((await one('select count(*)::int n from game.mp_chat')).n === chat0, 'tanpa pengumuman chat dunia');
  let l = await one('select * from game.player_location where player_id = $1', [a.id]);
  assert(l.city_id === 'toogood' && !l.destination_city_id && l.pending_encounter === null, 'pelayaran selesai di kota tujuan');
  assert((await one(`select result from game.combat_log where player_id = $1 order by id desc limit 1`, [a.id])).result === 'repelled', 'log tempur: repelled');
  assert(k0 > 0, 'kondisi terbaca');

  // tepat di ambang: 401 HP belum kabur, tembakan kena berikutnya membuat kabur (HP dikunci minimal 1)
  e = await cegat(a, 401);
  r = { ongoing: true, encounter: e };
  for (let i = 0; i < 40 && r.ongoing; i++) {
    assert(Number(r.encounter.enemyHp) === 401, 'meleset: HP tetap 401');
    r = await a.call('api_resolveCombat', [Number(r.encounter.ammoRemaining) > 0 ? 'fire' : 'reload']);
  }
  assert(r.result === 'repelled' && Number(r.enemyHp) === 1, 'lewat api_resolveCombat: kabur, HP dikunci 1 (' + r.enemyHp + ')');

  // tanpa Meriam Warlord (Cannons langkah 9, x1,45): damage kecil, tidak bisa memukul mundur
  await H.sql(`update game.character_stats set combat = 100 where player_id = $1`, [b.id]);
  await H.sql(`update game.players set gold = 5000 where player_id = $1`, [b.id]);
  await H.sql(`select game.adjust_inventory($1, 'sugar', 4)`, [b.id]);
  e = await cegat(b, 4000); dm = [];
  for (let i = 0; i < 16; i++) {
    r = await b.call('api_tonyRaid', [Number(e.ammoRemaining) > 0 ? 'fire' : 'reload']);
    e = r.encounter || e;
    assert(r.ongoing, 'pemain biasa: pertempuran berlanjut');
    if (r.hit) dm.push(Number(r.damage));
  }
  assert(dm.length >= 2 && dm.every(x => x >= 117 && x <= 208), 'damage x1,45 ke armada Tony: ' + dm);
  // kalah tetap dirampas seperti dulu
  await cfg('TonyHitPctMin', 60); await cfg('TonyHitPctMax', 60);
  for (let i = 0; i < 6 && r.ongoing; i++) r = await b.call('api_tonyRaid', ['reload']);
  assert(r.result === 'robbed' && r.how === 'kalah' && (await muatan(b)) === 0 && (await gold(b)) === 2000, 'kalah: tetap dirampas (60% gold, semua muatan)');
  assert((await one('select count(*)::int n from game.tony_victims')).n === 1, 'korban dicatat hanya untuk yang dirampas');

  // TonyKaburPct = 0: Tony tidak pernah kabur (perilaku lama)
  await cfg('TonyHitPctMin', 0); await cfg('TonyHitPctMax', 0); await cfg('TonyKaburPct', 0);
  e = await cegat(a, 300);
  r = await a.call('api_tonyRaid', ['reload']);
  assert(r.ongoing === true && Number(r.encounter.enemyHp) === 300, 'TonyKaburPct 0: tidak kabur');
  await cfg('TonyKaburPct', 10);
  r = await a.call('api_tonyRaid', ['reload']);
  assert(r.result === 'repelled', 'di bawah ambang: kabur pada aksi berikutnya');

  console.log('0087 damage meriam: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
