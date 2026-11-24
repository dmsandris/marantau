// 0103 Saga 4 Bagian II: pencegatan di tengah laut (langkah 55, 58, 59) + Medan Tempur Teluk Dalam + duel armada (60).
const { human, SKILL } = require('./trek-sim');
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const kuat = (u) => H.sql(`select game.apply_condition_delta($1, 99999)`, [u.id]);
  const data = async (u) => (await one(`select data from game.player_quests where player_id = $1 and quest_id = 'mahkota2'`, [u.id])).data;
  const loc = async (u) => one(`select city_id, destination_city_id, pending_encounter e, arrive_at, depart_at from game.player_location where player_id = $1`, [u.id]);
  const majukanJadwal = (u) => H.sql(`update game.player_quests set data = jsonb_set(data, '{laut,at}', to_jsonb(game.now_ms() - 10)) where player_id = $1 and quest_id = 'mahkota2' and data -> 'laut' ? 'at'`, [u.id]);
  const tibaSekarang = (u) => H.sql(`update game.player_location set arrive_at = now() - interval '1 second' where player_id = $1`, [u.id]);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  await H.sql(`update game.config set value = '0.2' where key = 'Mk2BossDmgKali'`);
  await H.sql(`update game.config set value = '0.2' where key = 'MkNavyDmgKali'`);

  const a = await H.user('lautkapten');
  await a.call('api_createCharacter', ['Kapten Laut', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'mahkota', 40, '{"stempel":"dewan","marlya":"maafkan"}', now() - interval '30 days')`, [a.id]);
  await H.sql(`update game.config set value = 'lautkapten' where key = 'FiturPenguji'`);
  // Rantai Lama sudah terbuka (Quest 8 tamat)
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'limatangan', 99, '{}') on conflict (player_id, quest_id) do update set step = 99`, [a.id]);
  assert((await one(`select game.city_open($1, 'rantai_lama') o`, [a.id])).o === true, 'Rantai Lama terbuka');

  // pertempuran sampai selesai; kembalikan respons terakhir + daftar musuh berantai
  const tempur = async (u, opts) => {
    const chain = []; let fr = null;
    for (let i = 0; i < 2000; i++) {
      const enc = (await loc(u)).e;
      if (!enc) break;
      if (opts && opts.kalah) await H.sql(`update game.ships set condition = 1 where player_id = $1`, [u.id]); else await kuat(u);
      fr = await u.call('api_resolveCombat', [enc.ammoRemaining > 0 ? 'fire' : 'reload']);
      if (fr.chained) chain.push(fr.encounter.lw + ':' + fr.encounter.ke);
      if (!fr.ongoing) break;
    }
    return { fr, chain };
  };

  // ================= langkah 55: blokade di tengah laut =================
  await one(`select game.admin_mahkota2('lautkapten', 54) s`);
  await taruh(a, 'toogood');
  let s = await st(a);
  assert(s.d.n === 55 && s.d.laut === 'blokade' && s.mk2.blokadeOk === false, 'langkah 55 menunggu blokade');
  await H.expectError(() => a.call('api_mahkota', ['maju', 54, 'ok']), /Blokade Kumis Hitam masih menutup/);
  let sail = await a.call('api_setSail', ['rantai_lama']);
  assert(sail.travelSeconds >= 12, 'pelayaran minimal 12 dtk');
  let d = await data(a);
  assert(d.laut.w === 'blokade' && d.laut.dest === 'rantai_lama' && Number(d.laut.at) > Date.now(), 'jadwal pencegatan +3 dtk');
  let pv = await a.call('api_pollVoyage', []);
  assert(pv.voyage.inTransit && !pv.voyage.encounterPending, 'sebelum 3 dtk: belum dicegat');
  // tiba lebih dulu dari jadwal? tetap ditahan sampai pencegatan
  await majukanJadwal(a);
  pv = await a.call('api_pollVoyage', []);
  let enc = pv.voyage.encounter;
  assert(pv.voyage.inTransit && enc && enc.midSea && enc.lw === 'blokade' && enc.ke === 1 && enc.navyLook, 'Navy Tier 4 mencegat di tengah laut');
  assert(enc.dmgTaken > 0 && enc.boss === 'mk2laut', 'jalur bos, Meriam Warlord tetap dihitung lewat dmgTaken');
  await H.expectError(() => a.call('api_resolveCombat', ['flee']), /kabur/);
  await H.expectError(() => a.call('api_resolveCombat', ['bribe']), /suap/i);
  const kepingAwal = Number((await one('select coalesce(keping, 0) k from game.players where player_id = $1', [a.id])).k || 0);
  let x = await tempur(a);
  assert(x.chain.join(',') === 'blokade:2', 'kapal kedua Tembok Mahkota menyusul: ' + x.chain.join(','));
  assert(x.fr.result === 'won' && x.fr.midSea && x.fr.lanjut === 'jalan' && x.fr.voyage.inTransit && !x.fr.voyage.encounterPending,
    'menang: pelayaran berlanjut -> ' + JSON.stringify([x.fr.result, x.fr.lanjut, x.fr.voyage && x.fr.voyage.inTransit]));
  assert(x.fr.voyage.destinationCityId === 'rantai_lama' && x.fr.voyage.etaSeconds >= 5, 'sisa pelayaran tersambung');
  assert(Number((await one('select coalesce(keping, 0) k from game.players where player_id = $1', [a.id])).k || 0) > kepingAwal, 'Keping Navy T4');
  d = await data(a);
  assert(d.blokadeOk === true && !d.laut, 'blokade jebol tercatat');
  await tibaSekarang(a);
  pv = await a.call('api_pollVoyage', []);
  let l = await loc(a);
  assert(!pv.voyage.inTransit && l.city_id === 'rantai_lama' && !l.e, 'sandar di Rantai Lama tanpa pencegatan kedua');
  let r = await a.call('api_mahkota', ['maju', 54, 'ok']);
  assert(r.mahkota.step === 55 && r.mahkota.d.n === 56, 'langkah 55 selesai');

  // kalah blokade: kembali ke pelabuhan asal, jadwal dibersihkan, coba lagi
  await one(`select game.admin_mahkota2('lautkapten', 54) s`);
  await H.sql(`update game.player_quests set data = data - 'blokadeOk' where player_id = $1 and quest_id = 'mahkota2'`, [a.id]);
  await taruh(a, 'toogood');
  await a.call('api_setSail', ['rantai_lama']);
  await majukanJadwal(a);
  await a.call('api_pollVoyage', []);
  x = await tempur(a, { kalah: true });
  l = await loc(a); d = await data(a);
  assert(x.fr.result === 'sunk' && l.city_id === 'toogood' && !l.destination_city_id && !d.laut && !d.blokadeOk, 'kalah: kembali ke TooGood -> ' + JSON.stringify([x.fr.result, l.city_id]));
  await kuat(a);

  // ================= langkah 58-59: Medan Tempur Teluk Dalam =================
  await one(`select game.admin_mahkota2('lautkapten', 57) s`);
  await taruh(a, 'freeyork');
  assert((await one(`select game.city_open($1, 'teluk_dalam') o`, [a.id])).o === true, 'Medan Tempur terbuka di langkah 58');
  assert((await one(`select game.player_unlocks($1) u`, [a.id])).u.indexOf('teluk_dalam') >= 0, 'muncul di peta');
  assert((await one(`select count(*)::int n from game.market where city_id = 'teluk_dalam'`)).n === 0, 'tanpa pasar');
  await H.expectError(() => a.call('api_setSail', ['teluk_dalam']), /berkumpul di Pelabuhan Rantai Lama/);
  await H.expectError(() => a.call('api_mahkota', ['serang', 57]), /Galangan Rantai Lama/);
  await taruh(a, 'rantai_lama');
  sail = await a.call('api_setSail', ['teluk_dalam']);
  assert(sail.travelSeconds >= 20, 'pelayaran ke Medan Tempur minimal 20 dtk');
  d = await data(a);
  assert(d.laut.w === 'g1' && d.kilat === false, 'jadwal Gelombang 1 (+5 dtk)');
  // gagal di Trektrek-an Kilat (mundur) -> Rantai Lama
  await majukanJadwal(a);
  pv = await a.call('api_pollVoyage', []);
  assert(pv.voyage.encounter && pv.voyage.encounter.lw === 'g1a' && pv.voyage.encounter.enemyName === 'KPD Tembok Utara', 'Gelombang 1: KPD Tembok Utara');
  x = await tempur(a);
  assert(x.fr.result === 'won' && x.fr.lanjut === 'kilat' && x.fr.voyage.inTransit, 'Tembok Utara tumbang -> Trektrek-an Kilat');
  s = await st(a);
  assert(s.mk2.laut.w === 'kilat' && s.mk2.laut.hold, 'klien melihat Kilat menunggu');
  await tibaSekarang(a);
  pv = await a.call('api_pollVoyage', []);
  assert(pv.voyage.inTransit, 'selama Kilat kapal ditahan, tidak sandar');
  await H.expectError(() => a.call('api_mahkota', ['kilat', 58]), /tidak menunggumu/);
  r = await a.call('api_mahkota', ['mundur', 57]);
  l = await loc(a); d = await data(a);
  assert(r.pulang && l.city_id === 'rantai_lama' && !l.destination_city_id && !d.laut && d.kilat === false, 'mundur -> Rantai Lama, Gelombang 1 diulang');

  // ulang Gelombang 1 sampai tuntas
  await kuat(a);
  await a.call('api_setSail', ['teluk_dalam']);
  await majukanJadwal(a);
  await a.call('api_pollVoyage', []);
  x = await tempur(a);
  assert(x.fr.lanjut === 'kilat', 'Tembok Utara lagi');
  let menangKilat = false;
  for (let i = 0; i < 40 && !menangKilat; i++) {
    const t = (await a.call('api_mahkota', ['kilat', 57])).trek;
    await H.sql(`update game.trek_runs set created_at = now() - interval '60 seconds' where run_id = $1`, [t.run]);
    const log = human(t.ship, t.seed, SKILL.jago).log;
    // pakai log yang menang saja; log kalah memulangkan kapal (diuji terpisah di atas lewat mundur)
    const sim = require('./trek-sim').D;
    const me = sim.replay(t.ship, log), op = sim.runAi('patroli', t.seed);
    if (!(me.fin != null && (op.fin == null || me.fin < op.fin))) continue;
    r = await a.call('api_mahkota', ['kilatSelesai', 57, t.run, log]);
    menangKilat = r.kilat === true;
  }
  assert(menangKilat && r.voyage.encounterPending && r.voyage.encounter.lw === 'g1b' && r.voyage.encounter.enemyName === 'KPD Tembok Selatan', 'Kilat menang -> KPD Tembok Selatan');
  x = await tempur(a);
  assert(x.fr.result === 'won' && x.fr.lanjut === 'jalan' && x.fr.voyage.inTransit && x.fr.voyage.destinationCityId === 'teluk_dalam', 'Gelombang 1 lolos, pelayaran berlanjut');
  s = await st(a); d = await data(a);
  assert(s.step === 58 && s.d.n === 59 && d.laut.w === 'g2' && Number(d.laut.at) > Date.now(), 'langkah 58 selesai, Gelombang 2 menunggu ringkasan ditutup');
  assert(d.laut.tunda === true && Number(d.laut.at) > Date.now() + 15000, 'cadangan 20 dtk sebelum ringkasan ditutup');
  r = await a.call('api_mahkota', ['lautMulai', 58]);
  d = await data(a);
  assert(!d.laut.tunda && Number(d.laut.at) <= Date.now() + 6000 && r.mahkota.mk2.laut.dalam <= 6000, 'ringkasan ditutup: Algojo +5 dtk');
  await majukanJadwal(a);
  pv = await a.call('api_pollVoyage', []);
  assert(pv.voyage.encounter && pv.voyage.encounter.lw === 'g2' && pv.voyage.encounter.allyDmg > 0, 'Gelombang 2: Algojo, sekutu menembak');
  x = await tempur(a);
  assert(x.chain.join(',') === 'g2:2,g2:3', 'tiga Algojo berantai: ' + x.chain.join(','));
  assert(x.fr.result === 'won' && x.fr.lanjut === 'jalan' && /Sayap mereka runtuh/.test(x.fr.message), 'Gelombang 2 lolos + dialog Hasiolan');
  s = await st(a);
  assert(s.step === 59 && s.d.n === 60 && s.mk2.hasiolan && !s.mk2.laut, 'langkah 59 selesai');
  await tibaSekarang(a);
  await a.call('api_pollVoyage', []);
  l = await loc(a);
  assert(l.city_id === 'teluk_dalam' && !l.e, 'tiba di Medan Tempur Teluk Dalam tanpa pencegatan acak');
  await H.expectError(() => a.call('api_mahkota', ['serang', 59]), /Galangan Rantai Lama/);

  // ================= langkah 60: duel armada =================
  let ar = (await a.call('api_mahkota', ['arena', 59])).arena;
  assert(ar.id && ar.hpKu >= 1500 && ar.dmgKu > 0 && ar.hpSov === 2600 && ar.hpNavy > 0 && ar.hpSekutu > 0 && ar.t === undefined, 'duel dimulai: angka dari server');
  await H.expectError(() => a.call('api_mahkota', ['arenaHasil', 59, 'palsu', { win: true, ms: 60000 }]), /tidak tercatat/);
  await H.expectError(() => a.call('api_mahkota', ['arenaHasil', 59, ar.id, { win: true, ms: 1000 }]), /tidak wajar/);
  r = await a.call('api_mahkota', ['arenaHasil', 59, ar.id, { win: false, ms: 1000 }]);
  assert(r.menang === false && r.mahkota.mk2.arenaKalah === 1 && !r.mahkota.mk2.menang, 'kalah duel: bisa diulang');
  ar = (await a.call('api_mahkota', ['arena', 59])).arena;
  await H.sql(`update game.player_quests set data = jsonb_set(data, '{arena,t}', to_jsonb(game.now_ms() - 90000)) where player_id = $1 and quest_id = 'mahkota2'`, [a.id]);
  r = await a.call('api_mahkota', ['arenaHasil', 59, ar.id, { win: true, ms: 85000 }]);
  assert(r.menang === true && r.mahkota.mk2.menang, 'menang duel armada');
  await H.expectError(() => a.call('api_mahkota', ['arena', 59]), /sudah karam/);
  r = await a.call('api_mahkota', ['pilih', 59, 'ocid']);
  l = await loc(a);
  assert(r.tamat && r.gold === 2500000 && r.pulang === 'rantai_lama' && l.city_id === 'rantai_lama', 'tamat: kembali ke Rantai Lama');
  assert((await one(`select game.city_open($1, 'teluk_dalam') o`, [a.id])).o === false, 'Medan Tempur tertutup setelah tamat');

  // ================= pemain lain tidak tersentuh =================
  const b = await H.user('lautbiasa');
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  await taruh(b, 'toogood');
  await b.call('api_setSail', ['joungjava']);
  assert(!(await one(`select count(*)::int n from game.player_quests where player_id = $1 and quest_id = 'mahkota2'`, [b.id])).n, 'tanpa baris mahkota2');
  assert((await one(`select game.city_open($1, 'teluk_dalam') o`, [b.id])).o === false, 'Medan Tempur tidak terlihat pemain lain');
  await H.expectError(() => b.call('api_setSail', ['teluk_dalam']), /tidak dikenali|perjalanan/);

  console.log('MAHKOTA2 LAUT TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
