// 0100 Saga 4 Bagian II "Takhta Tanpa Mahkota": gerbang 3 hari game, langkah 41-60, Navy, Battle Akhir, tamat.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const st = async (u) => (await u.call('api_mahkota', ['status'])).mahkota;
  const dayMs = async () => Number((await one(`select value from game.config where key = 'GameDayLengthRealMinutes'`)).value) * 60000;
  const beri = (u, id, n) => one('select game.adjust_inventory($1, $2, $3) x', [u.id, id, n]);
  const kuat = (u) => H.sql(`select game.apply_condition_delta($1, 99999)`, [u.id]);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);

  const a = await H.user('mk2kapten');
  await a.call('api_createCharacter', ['Kapten Mahkota', 'merchant']);
  await H.sql(`update game.players set gold = 100000 where player_id = $1`, [a.id]);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data, done_at) values ($1, 'mahkota', 40, '{"stempel":"dewan","marlya":"kabarkan"}', now())`, [a.id]);
  await taruh(a, 'sunda_empire');

  // ---- gerbang: tertutup -> Bagian I apa adanya ----
  let s = await st(a);
  assert(s && s.step === 40 && !s.mk2 && s.d == null && s.tamat === true, 'tanpa gerbang: tetap langkah 40 tamat');
  await H.expectError(() => a.call('api_mahkota', ['maju', 40, 'ok']), /Bersambung/);
  await H.sql(`update game.config set value = 'mk2kapten' where key = 'FiturPenguji'`);
  s = await st(a);
  assert(!s.mk2, 'gerbang menyala tapi belum 3 hari game');
  const mundurHari = async (n) => H.sql(`update game.player_quests set done_at = now() - ($2 || ' milliseconds')::interval where player_id = $1 and quest_id = 'mahkota'`, [a.id, String(Math.round(n * await dayMs()))]);
  await mundurHari(2);
  assert(!(await st(a)).mk2, '2 hari game: belum');
  await mundurHari(3.05);
  s = await st(a);
  assert(s.mk2 && s.step === 40 && s.d && s.d.n === 41 && s.tamat === true, '3 hari game: langkah 41 muncul');
  assert(s.mk2.stempel === 'dewan' && s.mk2.marlya === 'kabarkan' && s.mk2.fate === 'dewan', 'varian pilihan Bagian I terbawa');
  // Bagian I tetap tamat
  assert((await one('select game.mk_tamat($1) t', [a.id])).t === true, 'mk_tamat tetap');
  assert((await one('select game.trek_kapal($1) k', [a.id])).k === 'jolt', 'Mesin Jolt tidak kembali');

  // ---- langkah 41: di pulau mana pun ----
  await H.expectError(() => a.call('api_mahkota', ['maju', 41, 'ok']), /bergeser/);
  let r = await a.call('api_mahkota', ['maju', 40, 'ok']);
  assert(r.maju && r.mahkota.step === 41 && r.mahkota.d.n === 42, 'langkah 41 selesai');
  assert((await one(`select step from game.player_quests where player_id = $1 and quest_id = 'mahkota'`, [a.id])).step === 40, 'baris Bagian I tidak berubah');
  // ---- langkah 42 salah kota ----
  await H.expectError(() => a.call('api_mahkota', ['maju', 41, 'ok']), /Tidak ada yang perlu dibicarakan/);
  await taruh(a, 'marie_regal');
  await H.expectError(() => a.call('api_mahkota', ['maju', 41, 'gagal']), /Belum berhasil/);
  r = await a.call('api_mahkota', ['maju', 41, 'ok']);
  assert(r.mahkota.step === 42 && r.mahkota.mk2.navy === 1, 'langkah 42 selesai, Navy Tier 1 aktif');

  // ---- Navy: 100% ke kota tujuan langkah aktif (43: Joungjava) ----
  await H.sql(`update game.player_location set destination_city_id = 'joungjava', depart_at = now() - interval '10 seconds', arrive_at = now() where player_id = $1`, [a.id]);
  let e = (await one('select game.kd_enc($1, null) e', [a.id])).e;
  assert(e && e.kind === 'navy' && e.mk2navy === 1 && e.enemyName === 'Patroli Stempel Biru', 'Navy Tier 1 mencegat');
  await H.sql(`update game.config set value = '0' where key = 'MkNavyPct'`);
  await H.sql(`update game.player_location set destination_city_id = 'skitraw' where player_id = $1`, [a.id]);
  assert((await one('select game.kd_enc($1, null) e', [a.id])).e == null, 'MkNavyPct 0: pelayaran lain aman');
  await H.sql(`update game.config set value = '50' where key = 'MkNavyPct'`);
  // pertempuran: kabur dikunci, menang -> Keping + navyMenang
  await H.sql(`update game.player_location set destination_city_id = 'joungjava', pending_encounter = $2 where player_id = $1`, [a.id, e]);
  await kuat(a);
  await H.expectError(() => a.call('api_resolveCombat', ['flee']), /Tidak ada celah untuk kabur/);
  await H.expectError(() => a.call('api_resolveCombat', ['bribe']), /Tidak ada suap/);
  const kepingAwal = Number((await one('select coalesce(keping, 0) k from game.players where player_id = $1', [a.id])).k || 0);
  let fr = null;
  for (let i = 0; i < 300; i++) {
    const enc = (await one('select pending_encounter e from game.player_location where player_id = $1', [a.id])).e;
    await kuat(a);
    fr = await a.call('api_resolveCombat', [enc.ammoRemaining > 0 ? 'fire' : 'reload']);
    if (!fr.ongoing) break;
  }
  assert(fr && fr.result === 'won' && fr.keping >= 1 && fr.keping <= 2 && /Keping Rantau/.test(fr.message), 'menang Navy T1: 1-2 Keping -> ' + JSON.stringify(fr && [fr.result, fr.keping]));
  const kepingAkhir = Number((await one('select coalesce(keping, 0) k from game.players where player_id = $1', [a.id])).k || 0);
  assert(kepingAkhir - kepingAwal >= fr.keping, 'Keping masuk ke saldo ' + JSON.stringify([kepingAwal, kepingAkhir, fr.keping]));
  assert((await st(a)).mk2.navyMenang === 1, 'navyMenang tercatat');
  // batas Keping: lewat 40 per hari -> 1
  await H.sql(`update game.player_quests set data = data || jsonb_build_object('nk', jsonb_build_object('h', game.game_day(), 'n', 40)) where player_id = $1 and quest_id = 'mahkota2'`, [a.id]);
  const hk = (await one('select game.mk2_navy_hadiah($1, 3) h', [a.id])).h;
  assert(hk.keping === 1 && Number(hk.gold) > 0, 'lewat batas 40: Keping = 1, gold tier tetap');

  // ---- Navy Tier 4: dua kapal dalam satu pencegatan ----
  await one(`select game.admin_mahkota2('mk2kapten', 55) s`);
  await taruh(a, 'freeyork');
  await H.sql(`update game.player_location set destination_city_id = 'rantai_lama', depart_at = now() - interval '10 seconds', arrive_at = now() where player_id = $1`, [a.id]);
  e = (await one('select game.kd_enc($1, null) e', [a.id])).e;
  assert(e.mk2navy === 4 && e.ke === 1, 'langkah 56 (dari 55 selesai): Tier 4');
  await H.sql(`update game.player_location set pending_encounter = $2 where player_id = $1`, [a.id, e]);
  await kuat(a);
  let chained = false;
  for (let i = 0; i < 400; i++) {
    const enc = (await one('select pending_encounter e from game.player_location where player_id = $1', [a.id])).e;
    if (!enc) break;
    await kuat(a);
    fr = await a.call('api_resolveCombat', [enc.ammoRemaining > 0 ? 'fire' : 'reload']);
    if (fr.chained) { chained = true; assert(fr.encounter.ke === 2, 'kapal kedua'); }
    if (!fr.ongoing) break;
    if (i % 10 === 9) await kuat(a);
  }
  assert(chained && fr.result === 'won' && fr.keping >= 1, 'Tier 4: kapal kedua lalu menang');

  // ---- setoran sekaligus (langkah 49 Ama Kerang) ----
  await one(`select game.admin_mahkota2('mk2kapten', 48) s`);
  await taruh(a, 'karang_garam');
  s = await st(a);
  assert(s.d.n === 49 && s.d.bahan.beras === 100, 'langkah 49 minta 100 Beras');
  await H.expectError(() => a.call('api_mahkota', ['maju', 48, 'ok']), /Serahkan dulu barangnya/);
  await H.expectError(() => a.call('api_mahkota', ['setor', 48]), /masih kurang, Kapten: 100 Beras/);
  await beri(a, 'beras', 100);
  r = await a.call('api_mahkota', ['setor', 48]);
  assert(r.setor && r.lengkap && r.mahkota.step === 48, 'beras diserahkan, mini game menyusul');
  assert((await one('select game.item_qty($1, $2) q', [a.id, 'beras'])).q === 0, 'beras diambil');
  r = await a.call('api_mahkota', ['maju', 48, 'ok']);
  assert(r.mahkota.step === 49, 'selam selesai -> langkah 49 tuntas');
  // langkah 50 tanpa mini game: setor langsung menutup langkah
  await taruh(a, 'freeyork');
  await beri(a, 'besi', 30); await beri(a, 'mesiu', 35);
  r = await a.call('api_mahkota', ['setor', 49]);
  assert(r.maju && r.mahkota.step === 50, 'setor 30 Besi + 35 Mesiu -> langkah 50 tuntas');

  // ---- cicilan ransum (langkah 54) ----
  await one(`select game.admin_mahkota2('mk2kapten', 53) s`);
  await taruh(a, 'toogood');
  await H.expectError(() => a.call('api_mahkota', ['setor', 53]), /belum membawa ransum/);
  await beri(a, 'beras', 120);
  r = await a.call('api_mahkota', ['setor', 53]);
  assert(r.lengkap === false && r.cicil.beras === 120 && r.mahkota.step === 53, 'cicilan pertama tersimpan');
  await beri(a, 'beras', 200); await beri(a, 'ikan_asin', 300); await beri(a, 'tuak', 150);
  const g0 = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  r = await a.call('api_mahkota', ['setor', 53]);
  assert(r.maju && r.mahkota.step === 54 && r.gold === 2000000 && r.tanda === 'janjirantai', 'ransum penuh -> hadiah Q21');
  assert((await one('select game.item_qty($1, $2) q', [a.id, 'beras'])).q === 20, 'kelebihan beras tetap di palka');
  assert(Number((await one('select gold from game.players where player_id = $1', [a.id])).gold) === g0 + 2000000, 'gold Q21 masuk');

  // ---- Battle Akhir Bersama ----
  await one(`select game.admin_mahkota2('mk2kapten', 57) s`);
  await taruh(a, 'rantai_lama');
  await H.sql(`update game.config set value = '0.2' where key = 'Mk2BossDmgKali'`);
  await H.expectError(() => a.call('api_mahkota', ['serang', 57]), /Tembus dulu zona bidik/);
  await H.expectError(() => a.call('api_mahkota', ['maju', 57, 'ok']), /Armada musuh masih berdiri/);
  await H.sql(`update game.player_quests set data = data || '{"kilat":true}' where player_id = $1 and quest_id = 'mahkota2'`, [a.id]);
  let mundur = 0, menang = false, langkah = [];
  for (let n = 0; n < 6 && !menang; n++) {
    s = await st(a);
    const idx = s.d.n - 1;
    r = await a.call('api_mahkota', ['serang', idx]);
    assert(r.encounter && r.encounter.mk2b, 'serang membuat pertempuran');
    for (let i = 0; i < 1500; i++) {
      const enc = (await one('select pending_encounter e from game.player_location where player_id = $1', [a.id])).e;
      if (!enc) break;
      if (n === 0 && i === 3 && enc.w === 0) { fr = await a.call('api_resolveCombat', ['flee']); mundur++; break; }
      await kuat(a);
      fr = await a.call('api_resolveCombat', [enc.ammoRemaining > 0 ? 'fire' : 'reload']);
      if (fr.chained) langkah.push(fr.encounter.w);
      if (!fr.ongoing) break;
      if (i % 6 === 5) await kuat(a);
    }
    if (fr.result === 'won' && !fr.ongoing) menang = true;
    await kuat(a);
  }
  s = await st(a);
  assert(mundur === 1, 'sempat mundur sekali (retreatOk)');
  assert(menang && s.mk2.menang && s.step === 59 && s.d.n === 60, 'Sovereign Mahkota karam -> langkah 60 menunggu pilihan: ' + JSON.stringify([menang, s.step, s.mk2 && s.mk2.ba]));
  assert(langkah.join(',') === '1,2,3,4,5,6,7', 'urutan gelombang 1..7 -> ' + langkah.join(','));
  // HP flagship tersimpan saat kalah
  await one(`select game.admin_mahkota2('mk2kapten', 59) s`);
  await H.sql(`update game.player_quests set data = data || '{"ba":6,"baHp":3000}' where player_id = $1 and quest_id = 'mahkota2'`, [a.id]);
  r = await a.call('api_mahkota', ['serang', 59]);
  assert(r.encounter.w === 6 && r.encounter.enemyHp === 3000 && r.encounter.phase === 2, 'lanjut fase 2 dengan HP tersimpan');
  await H.sql(`update game.player_location set destination_city_id = null, pending_encounter = null, depart_at = null, arrive_at = null where player_id = $1`, [a.id]);
  await H.sql(`update game.player_quests set data = data || '{"ba":8,"menang":true}' where player_id = $1 and quest_id = 'mahkota2'`, [a.id]);
  await H.expectError(() => a.call('api_mahkota', ['pilih', 59, 'tenggelamkan']), /tidak dikenali/);
  const g1 = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  r = await a.call('api_mahkota', ['pilih', 59, 'hancurkan']);
  assert(r.maju && r.tamat && r.gold === 2500000 && r.tanda === 'penakluk' && r.mahkota.step === 60 && r.mahkota.d == null, 'tamat Bagian II');
  assert(Number((await one('select gold from game.players where player_id = $1', [a.id])).gold) === g1 + 2500000, 'gold Q22 masuk');
  assert((await one(`select count(*)::int n from game.kd_owned where player_id = $1 and item_id = 'layar_takhta_bebas'`, [a.id]).catch(() => ({ n: 1 }))).n === 1, 'rupa Takhta Bebas diberikan');
  assert((await one('select game.mk2_tamat($1) t, game.mk2_navy_tier($1) n', [a.id])).t === true, 'mk2_tamat');
  assert((await one('select game.mk2_navy_tier($1) n', [a.id])).n === 0, 'Navy berhenti');
  await H.expectError(() => a.call('api_mahkota', ['maju', 60, 'ok']), /sudah bebas/);

  // ---- pemain tanpa Saga 4 tidak tersentuh ----
  const b = await H.user('mk2biasa');
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  assert((await st(b)) == null, 'pemain biasa: tanpa quest');
  await H.sql(`update game.player_location set destination_city_id = 'joungjava', depart_at = now() - interval '10 seconds', arrive_at = now() where player_id = $1`, [b.id]);
  assert((await one('select game.kd_enc($1, null) e', [b.id])).e == null, 'pemain biasa: tidak pernah dicegat Navy');

  console.log('MAHKOTA2 TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
