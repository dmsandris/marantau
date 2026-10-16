// Saga 2 · Quest 7 "Malam Tiga Tanda Silang": pemicu pelayaran ke-3 setelah Quest 6 -> Javasche Bank
// dibobol (Olah Jejak, dua pertanyaan, Peta Pengasingan) -> Otoland -> em pe'er de pe'er (Pesta Topeng,
// malam) -> FreeYork (tungku) -> Andry di Paradiso -> Titik Buta (malam) -> TooGood -> pemburu
// Sayap Patah -> Kunci Dua Jarum di Gading -> penutup di Joungjava. Juga menjaga: pulau tersembunyi
// untuk pemain lain, waktu tempuh lama tidak berubah, peran pasar bertahan, pasar dunia tidak dikacaukan.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('tigasilang1'); await u.call('api_createCharacter', ['Yang Keempat', 'merchant']);
  const other = await H.user('tigasilang2'); await other.call('api_createCharacter', ['Penonton', 'navigator']);
  const pid = u.id;
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const ts = a => u.call('api_tigasilang', a);
  const st = async () => (await u.call('api_tigasilang', ['status'])).tigasilang;
  const gold = async () => Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  const item = async id => Number((await one('select game.item_qty($1, $2) q', [pid, id])).q);
  const city = async () => (await one('select city_id from game.player_location where player_id = $1', [pid])).city_id;
  const dayLenMin = Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) v`)).v);
  const setFrac = async f => {
    const r = await one(`select game.now_ms() n, game.cfg_num('WorldStartTimestamp', 0) s`);
    const len = dayLenMin * 60000, cur = ((Number(r.n) - Number(r.s)) % len) / len;
    let d = f - cur; if (d < 0) d += 1;
    await H.shiftTime(Math.round(d * len) + 1000);
  };
  const night = () => setFrac(0.8), day = () => setFrac(0.35);
  const fightOut = async (tactic) => {
    let last = null;
    for (let i = 0; i < 160; i++) {
      const s = await u.call('api_getGameState', [null]);
      if (!s.voyage.inTransit || !s.voyage.encounterPending) return last;
      await H.sql('update game.ships set condition = greatest(condition, 90) where player_id = $1', [pid]);
      if (tactic === 'win') await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '1'::jsonb) - 'immuneFirst' where player_id = $1`, [pid]);
      const enc = s.voyage.encounter;
      last = await u.call('api_resolveCombat', [enc.ammoRemaining > 0 ? 'fire' : 'reload']);
    }
    return last;
  };
  const sail = async (dest, tactic) => { await u.call('api_setSail', [dest]); await H.shiftTime(400000); const s = await u.call('api_getGameState', [null]); await fightOut(tactic || 'win'); return s; };

  // --- Penjaga dunia ------------------------------------------------------------
  for (const c of ['otoland', 'empeer_depeer', 'freeyork']) {
    const row = await one('select hidden, map_x, map_y from game.cities where city_id = $1', [c]);
    assert(row && row.hidden === true, c + ' tersembunyi');
    assert((await one(`select game.city_open($1, $2) o`, [other.id, c])).o === false, c + ' tertutup untuk pemain lain');
    const n = await one(`select count(*)::int n from game.market where city_id = $1`, [c]);
    const all = await one(`select count(*)::int n from game.commodities where active`);
    assert(n.n === all.n, c + ' pasar lengkap: ' + n.n + '/' + all.n);
  }
  const R = async (c, comm) => (await one('select role from game.market where city_id = $1 and commodity_id = $2', [c, comm])).role;
  assert(await R('otoland', 'garam') === 'produce' && await R('otoland', 'batik') === 'consume', 'peran pasar Otoland');
  assert(await R('empeer_depeer', 'silk') === 'produce' && await R('empeer_depeer', 'sugar') === 'consume', "peran pasar em pe'er de pe'er");
  assert(await R('freeyork', 'besi') === 'produce' && await R('freeyork', 'kayu_jati') === 'consume', 'peran pasar FreeYork');
  assert(await R('sunda_empire', 'garam') === 'produce', 'peran pasar kota lama tidak berubah');
  const rng = await one(`select dmax from game.voy_dist_range()`);
  const rngOld = await one(`select max(game.voy_map_distance(a.city_id, b.city_id)) dmax from game.cities a join game.cities b on a.city_id < b.city_id
    where not game.spot_city(a.city_id) and not game.spot_city(b.city_id)
      and a.city_id not in ('gading_island','otoland','empeer_depeer','freeyork') and b.city_id not in ('gading_island','otoland','empeer_depeer','freeyork')`);
  assert(Math.abs(Number(rng.dmax) - Number(rngOld.dmax)) < 1e-9, 'rentang jarak dunia tidak ikut pulau baru');
  const tFy = Number((await one(`select game.voy_travel_seconds(game.voy_map_distance('sunda_empire', 'freeyork'), '{}'::jsonb) t`)).t);
  assert(tFy > 240 && tFy <= 360, 'Sunda -> FreeYork laut terbuka: ' + tFy);
  const missions = await H.sql(`select 1 from game.cities where city_id = 'otoland' and not hidden`);
  assert(missions.length === 0, 'pulau baru tidak dipakai papan misi (hidden)');
  const tiram = await one(`select l_available, l_time, cities from game.mp_fish_types where id = 'tiram_otoland'`);
  assert(tiram.l_available === true && tiram.l_time === 'pagi', 'Tiram Otoland bisa ditangkap (pagi)');
  const paus = await one(`select l_available, cities from game.mp_fish_types where id = 'paus_bisu'`);
  assert(paus.l_available === true && paus.cities[0] === 'empeer_depeer', "Paus Bisu di em pe'er de pe'er");

  // --- Prasyarat ------------------------------------------------------------------
  assert((await st()) === null, 'tersembunyi sebelum Quest 6 selesai');
  await H.expectError(() => ts(['vault']), /Langit masih biru/);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at, data) values
    ($1, 'gala', 6, now(), '{}'), ($1, 'toogood', 10, now(), '{}'), ($1, 'warwerwor', 12, now(), '{}'), ($1, 'barsati', 16, now(), '{}'),
    ($1, 'kompas', 8, now(), '{"truth":"bohong"}'), ($1, 'cocoepan', 11, now(), '{}')`, [pid]);
  await H.sql(`select game.item_adjust($1, 'qi_kompas_tedsky', 1)`, [pid]);
  // krisis pasar Quest 5 sudah lama mereda
  await H.sql(`update game.player_quests set done_at = now() - (10 * $2 || ' minutes')::interval, updated_at = now() - (10 * $2 || ' minutes')::interval where player_id = $1 and quest_id = 'kompas'`, [pid, dayLenMin]);
  await H.sql('update game.players set gold = 200000 where player_id = $1', [pid]);
  let s = await st();
  assert(s && s.step === 0 && s.sails === 0, 'menunggu pelayaran ' + JSON.stringify(s));
  await H.expectError(() => ts(['vault']), /Langit masih biru/);

  // --- Babak 0: pelayaran ke-3 ---------------------------------------------------------
  await go('sunda_empire');
  await sail('skitraw'); s = await st(); assert(s.step === 0 && s.sails === 1, 'pelayaran 1 normal');
  await sail('sunda_empire'); s = await st(); assert(s.step === 0 && s.sails === 2, 'pelayaran 2 normal');
  await u.call('api_setSail', ['skitraw']);
  s = await st(); assert(s.step === 1 && s.skyAt > 0, 'pelayaran 3: Langit Hitam ' + JSON.stringify(s));
  await H.shiftTime(400000); await u.call('api_getGameState', [null]); await fightOut('win');
  assert(await city() === 'skitraw', 'kapal tetap tiba di tujuan');

  // --- Babak 1: Javasche Bank ------------------------------------------------------------
  await H.expectError(() => ts(['vault']), /Javasche Bank/);
  await go('joungjava');
  s = (await ts(['vault'])).tigasilang; assert(s.step === 2, 'brankas');
  await H.expectError(() => ts(['map']), /ruang brankas/);
  await ts(['jejak']);
  await H.expectError(() => ts(['map']), /pertanyaanmu/);
  await ts(['ask', 'diri']); await ts(['ask', 'diri']); await H.expectError(() => ts(['ask', 'hantu']), /tidak dikenal/);
  await ts(['ask', 'tedsky']);
  let r = await ts(['map']);
  assert(r.tigasilang.step === 3 && r.unlocks.includes('otoland') && !r.unlocks.includes('empeer_depeer'), 'Otoland terbuka');
  assert(await item('qi_peta_pengasingan') === 1, 'Peta Pengasingan');
  assert((await one(`select game.city_open($1, 'otoland') o`, [pid])).o === true, 'boleh berlayar ke Otoland');

  // --- Babak 2: Otoland --------------------------------------------------------------------
  await H.expectError(() => ts(['upayy', 'bahagia']), /Otoland/);
  await go('otoland');
  const mk = await u.call('api_getMarket', ['otoland']);
  assert(mk.items && mk.items.length > 0, 'pasar Otoland buka');
  await H.expectError(() => ts(['gasing', 'won']), /belum selesai bercerita/);
  await ts(['upayy', 'sendiri']);
  await H.expectError(() => ts(['upayy', 'bahagia']), /sudah menjawab/);
  await H.expectError(() => ts(['sandi']), /masih ingin bicara/);
  await ts(['gasing', 'lost']);
  assert(await item('qi_joran_nansy') === 1 && await item('qi_kotak_alat_jam') === 1, 'Joran & Kotak Alat Jam');
  r = await ts(['sandi']);
  assert(r.tigasilang.step === 4 && r.unlocks.includes('empeer_depeer'), "em pe'er de pe'er terbuka");
  assert(r.tigasilang.upayy === 'sendiri', 'pilihan upayy tersimpan');

  // --- Babak 3: Pesta Topeng ------------------------------------------------------------------
  await go('empeer_depeer');
  await H.expectError(() => ts(['pantun', 'ok']), /undangan/);
  await day();
  await ts(['ocid']);
  await H.expectError(() => ts(['pantun', 'ok']), /hanya digelar saat malam/);
  await night();
  await ts(['pantun', 'gagal']); s = await st(); assert(!s.pantun, 'pantun gagal boleh diulang');
  await H.expectError(() => ts(['mata', 'ok']), /belum dibuka/);
  await ts(['pantun', 'ok']);
  await H.expectError(() => ts(['garlyena', 'simpan']), /tak diundang/);
  await ts(['mata', 'ok']);
  await day(); // pilihan nasib Garlyena boleh dibuat walau fajar sudah tiba
  r = await ts(['garlyena', 'simpan']);
  assert(r.tigasilang.step === 5 && r.unlocks.includes('freeyork') && await item('qi_kunci_jam_agung') === 1, 'FreeYork terbuka, Kunci Jam Agung');
  // Cap Restu Dewan hanya untuk "bongkar"
  assert(Number((await one(`select game.quest_price_mul($1, 'empeer_depeer', 'silk') m`, [pid])).m) === 1, 'tanpa diskon bila simpan');

  // --- Babak 4: FreeYork -----------------------------------------------------------------------
  await go('freeyork');
  await H.expectError(() => ts(['tempa', 'padam']), /Telusuri dulu/);
  await ts(['tassyaaa']); await ts(['jejak']);
  await H.expectError(() => ts(['tempa', 'padam']), /20 Beras/);
  await H.expectError(() => ts(['tempa', 'biarkan', 'garam']), /10 Beras atau 10 Garam/);
  await H.sql(`select game.adjust_inventory($1, 'garam', 12)`, [pid]);
  r = await ts(['tempa', 'biarkan', 'garam']);
  assert(r.tigasilang.step === 6 && r.tigasilang.tempa === 'biarkan' && await item('garam') === 2 && await item('qi_palu_tempa') === 1, 'tungku dibiarkan, 10 garam, palu');

  // --- Babak 5: Paradiso -----------------------------------------------------------------------
  await H.expectError(() => ts(['andry']), /Paradiso/);
  await go('paradiso');
  await H.expectError(() => ts(['gasing', 'won']), /belum selesai bicara/);
  await ts(['andry']);
  r = await ts(['dadu', 'besar']); assert(Array.isArray(r.dice) && r.dice.length === 3, 'dadu');
  await H.expectError(() => ts(['dadu', 'kecil']), /Satu ronde/);
  await day();
  assert((await one(`select game.city_open($1, 'titik_buta') o`, [pid])).o === false, 'Titik Buta tertutup sebelum Andry memberi surat');
  r = await ts(['gasing', 'won']);
  assert(r.tigasilang.step === 7 && await item('qi_surat_hitam') === 1, 'surat bersegel hitam');
  assert((await one(`select game.city_open($1, 'titik_buta') o`, [pid])).o === false, 'Titik Buta tertutup siang hari');
  await night();
  assert((await one(`select game.city_open($1, 'titik_buta') o`, [pid])).o === true, 'Titik Buta terbuka saat malam');
  assert((await u.call('api_getGameState', [null])).unlocks.includes('titik_buta'), 'titik_buta di unlocks');
  assert((await one(`select game.city_open($1, 'titik_buta') o`, [other.id])).o === false, 'Titik Buta tetap tertutup untuk pemain lain');

  // --- Babak 6: Titik Buta -----------------------------------------------------------------------
  await H.expectError(() => ts(['titikbuta']), /Titik Buta/);
  const combat0 = Number((await one('select combat from game.character_stats where player_id = $1', [pid])).combat);
  await u.call('api_setSail', ['titik_buta']); await H.shiftTime(5000);
  await H.sql(`update game.player_location set arrive_at = now() - interval '1 second' where player_id = $1`, [pid]);
  s = await u.call('api_getGameState', [null]);
  assert(!s.voyage.encounterPending, 'tanpa bajak laut di Titik Buta');
  assert(await city() === 'titik_buta', 'tiba di Titik Buta: ' + await city());
  r = await ts(['titikbuta']);
  assert(r.tigasilang.step === 8 && r.cityId === 'toogood' && await city() === 'toogood', 'terdampar di TooGood');
  assert(await item('qi_pemukul_andry') === 1, 'pemukul genderang Andry');
  assert(Number((await one('select combat from game.character_stats where player_id = $1', [pid])).combat) === combat0 + 5, '+5 Combat');
  assert((await one(`select game.city_open($1, 'titik_buta') o`, [pid])).o === false, 'Titik Buta tertutup lagi');

  // --- Babak 7: Seribu Lentera ---------------------------------------------------------------------
  const g0 = await gold();
  r = await ts(['pemakaman']);
  assert(r.tigasilang.step === 9 && await gold() === g0 + 50000 && await item('qi_wasiat_andry') === 1 && await item('qi_surat_hitam') === 0, 'pemakaman: wasiat & 50.000 gold');
  assert(r.tigasilang.hunted && r.tigasilang.huntChance === 75, 'diburu (bohong 100% - simpan 25%): ' + r.tigasilang.huntChance);
  await H.expectError(() => ts(['pemakaman']), /sudah dilepas/);

  // --- Babak 8: diburu & memutus jarum ------------------------------------------------------------------
  await ts(['jarum']);
  // Pemburu: paksa peluang 100% lewat pilihan (bongkar), cek sifat musuh
  await H.sql(`update game.player_quests set data = data || '{"garlyena":"bongkar"}' where player_id = $1 and quest_id = 'tigasilang'`, [pid]);
  s = await st(); assert(s.huntChance === 100, 'bohong tanpa surat Garlyena: 100%');
  await u.call('api_setSail', ['skitraw']); await H.shiftTime(400000);
  s = await u.call('api_getGameState', [null]);
  assert(s.voyage.encounterPending && s.voyage.encounter.boss === 'pemburu', 'dicegat Pemburu Sayap Patah');
  const enc = s.voyage.encounter;
  assert(enc.enemyMaxHp === 1170 && enc.immuneFirst === true && enc.softSink === true, 'bohong: +30% HP, tembakan pertama meleset ' + JSON.stringify({ hp: enc.enemyMaxHp, im: enc.immuneFirst }));
  await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /tidak berbendera/);
  const g1 = await gold();
  await fightOut('win');
  assert(await city() === 'skitraw' && await gold() >= g1 + 4000, 'menang: tiba di tujuan, +4000 gold');
  s = await st(); assert(s.huntWins === 1, 'catatan kemenangan pemburu');
  // kalah dari pemburu: kapal tidak tenggelam, kembali ke asal tanpa kehilangan muatan
  await H.sql(`select game.adjust_inventory($1, 'beras', 5)`, [pid]);
  await u.call('api_setSail', ['joungjava']); await H.shiftTime(400000);
  s = await u.call('api_getGameState', [null]);
  assert(s.voyage.encounterPending, 'dicegat lagi');
  await H.sql('update game.ships set condition = 1 where player_id = $1', [pid]);
  await H.sql(`update game.player_location set pending_encounter = pending_encounter || '{"enemyDmgMul": 50}' where player_id = $1`, [pid]);
  const g2 = await gold();
  for (let i = 0; i < 30; i++) {
    s = await u.call('api_getGameState', [null]);
    if (!s.voyage.encounterPending) break;
    r = await u.call('api_resolveCombat', ['reload']);
  }
  assert(await city() === 'skitraw' && await item('beras') === 5 && await gold() === g2, 'kalah: mundur ke asal, muatan & gold aman');
  // padamkan tungku = -30% HP & tanpa tembakan meleset
  await H.sql(`update game.player_quests set data = data || '{"tempa":"padam"}' where player_id = $1 and quest_id = 'tigasilang'`, [pid]);
  const e2 = (await one(`select game.ts_hunter_enc($1) e`, [pid])).e;
  assert(e2.enemyMaxHp === 819 && e2.immuneFirst === false, 'padam: -30% HP, tanpa meleset ' + e2.enemyMaxHp);
  // Kunci Dua Jarum di Gading Island
  await H.expectError(() => ts(['cut']), /Gading Island/);
  await go('gading_island');
  r = await ts(['cut']);
  assert(r.tigasilang.step === 11 && await item('qi_kompas_tedsky') === 0 && await item('qi_kompas_dua_jarum') === 1, 'Kompas Dua Jarum');
  s = await st(); assert(!s.hunted && s.huntChance === 0, 'pemburu berhenti');
  await go('sunda_empire');
  await u.call('api_setSail', ['skitraw']); await H.shiftTime(400000);
  s = await u.call('api_getGameState', [null]);
  assert(!(s.voyage.encounterPending && s.voyage.encounter.boss === 'pemburu'), 'tidak ada pemburu lagi');
  await fightOut('win');

  // --- Penutup ----------------------------------------------------------------------------------------
  await go('joungjava');
  r = await ts(['tutup']);
  assert(r.tigasilang.done && r.tigasilang.step === 12, 'selesai');
  assert(await item('qi_kunci_jam_agung') === 0 && await item('qi_kotak_alat_jam') === 0, 'kunci & kotak alat diserahkan');
  const gs = await u.call('api_getGameState', [null]);
  assert(gs.tigasilang && gs.tigasilang.done && ['otoland', 'empeer_depeer', 'freeyork'].every(c => gs.unlocks.includes(c)), 'tiga pulau tetap terbuka');
  // Cap Restu Dewan (bongkar)
  assert(Math.abs(Number((await one(`select game.quest_price_mul($1, 'empeer_depeer', 'silk') m`, [pid])).m) - 0.9) < 1e-9, 'Cap Restu Dewan -10%');
  assert(Number((await one(`select game.quest_price_mul($1, 'otoland', 'silk') m`, [pid])).m) === 1, 'diskon hanya di Dewan');
  // pemain lain tetap melihat dunia lama
  const og = await other.call('api_getGameState', [null]);
  assert(og.tigasilang === null && !og.unlocks.includes('otoland'), 'pemain lain: tidak ada perubahan');

  // --- Catatan lama "Maudy" dirapikan --------------------------------------------------------------------
  const logs = await H.sql(`select count(*)::int n from game.player_log where message like '%Maudy%'`);
  assert(logs[0].n === 0, 'tidak ada catatan Maudy');
  console.log('TIGASILANG TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
