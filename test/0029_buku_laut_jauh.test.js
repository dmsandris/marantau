// Tide v33 · Buku Laut Jauh: 9 buku Tier VI hanya di Otoland, Gading Island, FreeYork; Rak Dalam;
// efek khusus (decay, jatah mancing, tempuh, reparasi, merapat, jarahan, misi, kondisi maks, tempur PvE,
// tenggelam); Black Pearl tidak ikut; Duel Lambung tidak berubah.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('lautjauh1'); await u.call('api_createCharacter', ['Kutu Buku', 'merchant']);
  const pid = u.id;
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const setGold = g => H.sql('update game.players set gold = $2 where player_id = $1', [pid, g]);
  const has = async e => (await one('select game.has_effect($1, $2) h', [pid, e])).h;
  const ship = async () => (await one('select game.ship_json($1) s', [pid])).s;
  const give = b => H.sql(`insert into game.player_books(player_id, book_id, date_acquired) values ($1, $2, 1) on conflict do nothing`, [pid, b]);
  const take = b => H.sql(`delete from game.player_books where player_id = $1 and book_id = $2`, [pid, b]);
  const num = v => Number(v);

  // --- Katalog -------------------------------------------------------------------
  const rows = await H.sql(`select book_id, source, price::int p, special_effect from game.book_catalog where tier = 'VI' order by sort`);
  assert(rows.length === 9, 'jumlah buku VI ' + rows.length);
  for (const c of ['otoland', 'gading_island', 'freeyork'])
    assert(rows.filter(r => r.source === c).length === 3, '3 buku di ' + c);
  assert(rows.every(r => r.p >= 78000 && r.p <= 500000 && r.special_effect), 'harga & efek');
  assert(Math.min(...rows.map(r => r.p)) === 78000 && Math.max(...rows.map(r => r.p)) === 500000, 'rentang harga 78.000-500.000');

  // --- Hanya dijual di pulaunya ------------------------------------------------------
  await setGold(5000000);
  await go('sunda_empire');
  let lib = await u.call('api_getLibrary', []);
  assert(!lib.available.some(b => b.Tier === 'VI'), 'tidak dijual di Sunda Empire');
  await H.expectError(() => u.call('api_buyBook', ['bk_oto_angin']), /tidak dijual di kota ini/);
  await go('otoland');
  lib = await u.call('api_getLibrary', []);
  const vi = lib.available.filter(b => b.Tier === 'VI');
  assert(vi.length === 3 && vi.every(b => b.Source === 'otoland'), 'Otoland: 3 buku Otoland saja');
  assert(vi.find(b => b.BookId === 'bk_oto_kincir').Locked, 'Hikayat Kincir Tua terkunci (Rak Dalam)');
  assert(!('Locked' in vi.find(b => b.BookId === 'bk_oto_angin')), 'buku biasa tanpa penanda Locked');
  assert(!lib.available.filter(b => b.Tier !== 'VI').some(b => 'Locked' in b), 'buku lama tidak berubah');

  // --- Rak Dalam -------------------------------------------------------------------
  await H.expectError(() => u.call('api_buyBook', ['bk_oto_kincir']), /Rak Dalam: 0\/2/);
  const g0 = await gold();
  const r1 = await u.call('api_buyBook', ['bk_oto_angin']);
  assert(num(r1.newGold) === g0 - 78000, 'bayar 78.000');
  await H.expectError(() => u.call('api_buyBook', ['bk_oto_kincir']), /Rak Dalam: 1\/2/);
  await u.call('api_buyBook', ['bk_oto_jaring']);
  lib = await u.call('api_getLibrary', []);
  assert(!('Locked' in lib.available.find(b => b.BookId === 'bk_oto_kincir')), 'Rak Dalam terbuka');
  await u.call('api_buyBook', ['bk_oto_kincir']);
  assert(await has('oto_angin') && await has('oto_jaring') && await has('oto_kincir'), 'efek Otoland aktif');
  // buku Gading tidak membuka Rak Dalam FreeYork
  await give('bk_gd_ramuan'); await give('bk_gd_lampion');
  assert((await one(`select game.book_buy_block($1, 'bk_fy_rantai') b`, [pid])).b, 'Rak Dalam per pulau');
  assert((await one(`select game.book_buy_block($1, 'bk_gd_fajar') b`, [pid])).b === null, 'Rak Dalam Gading terbuka');

  // --- oto_angin: decay -30% ---------------------------------------------------------
  const decayWith = num((await one('select game.voy_decay_for_voyage($1) d', [pid])).d);
  await take('bk_oto_angin');
  const decayWithout = num((await one('select game.voy_decay_for_voyage($1) d', [pid])).d);
  await give('bk_oto_angin');
  assert(decayWithout > 0 && Math.abs(decayWith - decayWithout * 0.7) < 1e-6, `decay ${decayWithout} -> ${decayWith}`);
  assert(num((await ship()).DecayReductionPercent) === 30, 'tampilan pengurangan decay');

  // --- oto_jaring: jatah 30, pulih 45 dtk --------------------------------------------
  const fi = await u.call('api_mgFishInfo', []);
  assert(fi.max === 30 && num(fi.regenMs) === 45000 && fi.left === 30, 'jatah mancing ' + JSON.stringify([fi.max, fi.regenMs, fi.left]));

  // --- oto_kincir: tempuh x0,9 (bertumpuk dengan Ivankov) ----------------------------
  assert(Math.abs(num((await ship()).TravelMul) - 0.9) < 1e-9, 'TravelMul 0,9');
  await give('bk_ivankov_maelstrom');
  assert(Math.abs(num((await ship()).TravelMul) - 0.81) < 1e-9, 'TravelMul 0,81 bersama Ivankov');
  await take('bk_ivankov_maelstrom');
  const dist = `game.voy_map_distance('sunda_empire', 'skitraw')`;
  const t1 = num((await one(`select game.voy_travel_seconds(${dist}, game.ship_json($1)) t`, [pid])).t);
  const t0 = num((await one(`select game.voy_travel_seconds(${dist}, game.ship_json($1) - 'TravelMul') t`, [pid])).t);
  assert(t1 < t0, `waktu tempuh lebih cepat ${t0} -> ${t1}`);

  // --- fy_ukir (+30) & Lambung Baja Regal (+50) kini juga untuk clamp/reparasi -------
  const m0 = num((await ship()).EffectiveMaxCondition);
  await give('bk_fy_ukir');
  const m1 = num((await ship()).EffectiveMaxCondition);
  assert(m1 === m0 + 30, `kondisi maks ${m0} -> ${m1}`);
  await give('bk_mr_hull');
  assert(num((await ship()).EffectiveMaxCondition) === m0 + 80, 'bertumpuk dengan Lambung Baja Regal');
  await H.sql('select game.apply_condition_delta($1, 1000)', [pid]);
  assert(num((await ship()).Condition) === m0 + 80, 'clamp kondisi memakai maks efektif');

  // --- gd_ramuan: reparasi -25%, +5% saat merapat ------------------------------------
  await H.sql('update game.ships set condition = 50 where player_id = $1', [pid]);
  const qWith = await one(`select game.voy_repair_quote($1, 'otoland') q`, [pid]);
  await take('bk_gd_ramuan');
  const qWithout = await one(`select game.voy_repair_quote($1, 'otoland') q`, [pid]);
  assert(num(qWith.q.cost) === Math.round(num(qWithout.q.cost) * 0.75), `reparasi ${qWithout.q.cost} -> ${qWith.q.cost}`);
  assert(num(qWith.q.maxCondition) === m0 + 80, 'reparasi sampai maks efektif');
  const arrive = async () => {
    await H.sql('update game.ships set condition = 50 where player_id = $1', [pid]);
    await H.sql(`update game.player_location set destination_city_id = 'otoland', depart_at = now() - interval '10 minutes', arrive_at = now() - interval '1 minute' where player_id = $1`, [pid]);
    await H.sql(`select game.voy_complete_arrival($1, 'otoland', 'tes')`, [pid]);
    return num((await ship()).Condition);
  };
  const cNo = await arrive();
  await give('bk_gd_ramuan');
  const cYes = await arrive();
  assert(Math.abs(cYes - cNo - Math.round((m0 + 80) * 0.05)) <= 1, `merapat ${cNo} -> ${cYes}`);
  await H.sql(`select game.voy_complete_arrival($1, 'otoland', 'tes')`, [pid]).catch(() => null);

  // --- Pertempuran PvE ---------------------------------------------------------------
  const startFight = async (enc) => {
    await go('otoland');
    await H.sql(`update game.player_location set destination_city_id = 'freeyork', depart_at = now() - interval '10 minutes', arrive_at = now() - interval '1 minute', pending_encounter = $2::jsonb where player_id = $1`,
      [pid, JSON.stringify(Object.assign({ enemyLevel: 5, enemyName: 'a tes sloop', enemyMaxHp: 165, enemyHp: 165, maxAmmo: 3, ammoRemaining: 3, round: 1 }, enc))]);
  };
  const winFight = async () => {
    let r = null;
    for (let i = 0; i < 200; i++) {
      await H.sql(`update game.player_location set pending_encounter = jsonb_set(jsonb_set(pending_encounter, '{enemyHp}', '1'::jsonb), '{ammoRemaining}', '3'::jsonb) where player_id = $1`, [pid]);
      await H.sql('update game.ships set condition = 200 where player_id = $1', [pid]);
      r = await u.call('api_resolveCombat', ['fire']);
      if (!r.ongoing) return r;
    }
    throw new Error('pertempuran tidak selesai');
  };
  // fy_tungku: +1 amunisi sekali per pertempuran
  await give('bk_fy_tungku');
  await startFight({ randomPirate: true });
  await H.sql('update game.ships set condition = 200 where player_id = $1', [pid]);
  let rr = await u.call('api_resolveCombat', ['reload']);
  assert(rr.ongoing && num(rr.encounter.maxAmmo) === 4 && rr.encounter.bljAmmo === true, 'amunisi +1 ' + JSON.stringify(rr.encounter));
  rr = await u.call('api_resolveCombat', ['reload']);
  assert(num(rr.encounter.maxAmmo) === 4, 'amunisi tidak bertambah dua kali');
  // voy_enc_book di kedatangan
  const eb = await one(`select game.voy_enc_book($1, '{"maxAmmo": 3, "ammoRemaining": 3}'::jsonb) e`, [pid]);
  assert(num(eb.e.maxAmmo) === 4 && num(eb.e.ammoRemaining) === 4, 'amunisi +1 saat musuh muncul');
  // gd_lampion: jarahan bajak laut acak >= 0,9 x 1,3 x 200 x lvl; bajak laut bukan-acak tetap <= 1,2 x 200 x lvl
  await setGold(1000000);
  await startFight({ randomPirate: true });
  let gb = await gold(); let res = await winFight();
  assert(res.result === 'won', 'menang ' + JSON.stringify(res).slice(0, 200));
  let gain = (await gold()) - gb;
  assert(gain >= Math.floor(0.9 * 1.3 * 200 * 5) - 1, 'jarahan Lampion ' + gain);
  await startFight({});
  gb = await gold(); res = await winFight(); gain = (await gold()) - gb;
  assert(gain <= 1.2 * 200 * 5 + 1, 'pemburu/bukan acak tanpa bonus ' + gain);

  // fy_rantai: tenggelam vs bajak laut acak -> gold aman, muatan -20%; vs pemburu quest -> aturan biasa
  const sinkFight = async (enc) => {
    await startFight(enc);
    for (let i = 0; i < 200; i++) {
      await H.sql('update game.ships set condition = 1 where player_id = $1', [pid]);
      const r = await u.call('api_resolveCombat', ['reload']);
      if (!r.ongoing) return r;
    }
    throw new Error('tidak tenggelam');
  };
  const cargo = async () => num((await one(`select game.item_qty($1, 'garam') q`, [pid])).q);
  await give('bk_fy_rantai');
  await H.sql(`delete from game.inventory where player_id = $1`, [pid]);
  await H.sql(`select game.adjust_inventory($1, 'garam', 10)`, [pid]);
  await setGold(1000000);
  res = await sinkFight({ randomPirate: true });
  assert(res.result === 'sunk', 'tenggelam ' + res.result);
  assert(await gold() === 1000000, 'gold aman ' + (await gold()));
  assert(await cargo() === 8, 'muatan hilang 20% ' + (await cargo()));
  res = await sinkFight({ enemyName: 'Pemburu Tedsky' });
  assert(res.result === 'sunk' && await gold() === 850000, 'pemburu quest: aturan biasa ' + (await gold()));
  assert(await cargo() === 4, 'pemburu quest: muatan -50% ' + (await cargo()));
  await go('otoland');

  // --- gd_fajar: misi +25% & Standing +2 ---------------------------------------------
  const mission = async () => {
    await go('skitraw');
    await H.sql(`update game.player_missions set status = 'completed' where player_id = $1 and status = 'active'`, [pid]);
    await H.sql(`insert into game.player_missions(player_id, status, city_id, commodity_id, qty, deliver_to_city_id, reward, type, loaded_qty)
      values ($1, 'active', 'sunda_empire', 'garam', 5, 'skitraw', 1000, 'courier', 5)`, [pid]);
    await H.sql(`update game.players set reputation = '{}'::jsonb where player_id = $1`, [pid]);
    const g = await gold();
    const r = await u.call('api_completeMission', []);
    const rep = (await one('select reputation r from game.players where player_id = $1', [pid])).r;
    return { r, gain: (await gold()) - g, rep };
  };
  let m = await mission();
  assert(m.gain === 1000 && m.rep.skitraw === 1 && !('bookBonus' in m.r), 'misi tanpa buku ' + JSON.stringify(m));
  await give('bk_gd_fajar');
  m = await mission();
  assert(m.gain === 1250 && m.r.reward === 1250 && m.r.bookBonus === 250, 'hadiah +25% ' + JSON.stringify(m.r));
  assert(m.rep.skitraw === 2 && m.rep.sunda_empire === 1, 'Standing tujuan +2, asal +1 ' + JSON.stringify(m.rep));

  // --- Black Pearl: efek kapal tidak berlaku -----------------------------------------
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'toogood', 8, '{}')
    on conflict (player_id, quest_id) do update set step = 8`, [pid]);
  assert((await one(`select game.ship_legend($1) l`, [pid])).l === 'pearl', 'menakhodai Black Pearl');
  for (const e of ['oto_angin', 'oto_kincir', 'gd_ramuan', 'fy_ukir', 'fy_tungku', 'regal_hull'])
    assert((await one('select game.ship_book_effect($1, $2) b', [pid, e])).b === false, e + ' tidak untuk Black Pearl');
  assert(num((await ship()).TravelMul) === 1, 'Black Pearl TravelMul 1');
  assert((await one(`select game.voy_enc_book($1, '{"maxAmmo": 3}'::jsonb) e`, [pid])).e.maxAmmo === 3, 'Black Pearl tanpa amunisi buku');
  await H.sql(`update game.player_quests set step = 10 where player_id = $1 and quest_id = 'toogood'`, [pid]);

  // --- Duel Lambung tidak berubah oleh buku tempur ----------------------------------
  await u.call('api_mpPulse', [{}]);
  const fBook = (await one('select game.mp_fighter($1) f', [pid])).f;
  await take('bk_fy_tungku'); await take('bk_fy_rantai'); await take('bk_gd_lampion');
  const fNo = (await one('select game.mp_fighter($1) f', [pid])).f;
  assert(JSON.stringify(fBook) === JSON.stringify(fNo), 'statistik duel sama: ' + JSON.stringify(fBook) + ' vs ' + JSON.stringify(fNo));

  console.log('BUKU LAUT JAUH TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
