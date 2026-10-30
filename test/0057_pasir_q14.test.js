// Tide v41 · Pasir Batch 7 — Quest 14 "Pasir Terakhir", pengembalian, set Kedai Saga 3.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '1' where key in ('PasirOpen', 'KedaiOpen')`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const A = await H.user('q14a_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const pid = A.id;
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5)`, [pid]);
  // harta sebelum pencurian
  await H.sql(`update game.players set gold = 800000, bank_balance = 200000 where player_id = $1`, [pid]);
  await H.sql(`select game.pasir_ensure($1)`, [pid]);
  await H.sql(`select game.pv_ambil($1, 'sunda_empire')`, [pid]);
  ok(Number((await one('select gold from game.players where player_id = $1', [pid])).gold) === 5000, 'pencurian: 5.000 gold');
  await H.sql(`update game.pasir_state set data = data || '{"buka": ["empeer_depeer"], "sudyrman": true, "set_gemilang": true, "set_benang": true}'::jsonb, kaca = 6, era = 'keadilan',
    riak = '{"gala_putih": "belot", "jawab_malam": "pernah"}'::jsonb where player_id = $1`, [pid]);
  await H.sql(`select game.ps_set($1, 'ps10', 11, '{}'::jsonb, true), game.ps_set($1, 'ps11', 10, '{}'::jsonb, true), game.ps_set($1, 'ps12', 7, '{}'::jsonb, true), game.ps_set($1, 'ps13', 7, '{}'::jsonb, true)`, [pid]);
  await H.sql(`insert into game.pv_pusaka(player_id, pusaka_id, mutu, slot) values ($1, 'jangkar', 'kasar', 1), ($1, 'layar_garuda', null, 2)`, [pid]);
  await H.sql(`update game.players set gold = 400000 where player_id = $1`, [pid]);
  const gs = async () => A.call('api_getGameState', []);
  const act = (...x) => A.call('api_pasir', x);
  const place = (c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const pend = async () => (await one('select pending_encounter e from game.player_location where player_id = $1', [pid])).e;
  await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);

  // --- Babak 1: persiapan ---
  await place('empeer_depeer');
  let s = await gs();
  ok(s.pasir.q14 && s.pasir.q14.step === 1 && s.pasir.q14.pusaka === 2 && !s.pasir.q14.siap, 'Quest 14 dimulai: persiapan');
  ok(!s.pasir.zaman.includes('pusaran'), 'belum siap: Malam Pusaran belum ditawarkan');
  await place('joungjava');
  await H.expectError(() => act('setor14'), /Sunda/);
  await place('sunda_empire');
  await H.expectError(() => act('setor14'), /tidak membawa/);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 60), game.adjust_inventory($1, 'arms', 100), game.adjust_inventory($1, 'besi', 30)`, [pid]);
  let r = await act('setor14');
  ok(r.setor.mesiu === 60 && r.setor.arms === 100 && r.setor.besi === 30, 'setor dicicil');
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 80), game.adjust_inventory($1, 'besi', 70)`, [pid]);
  r = await act('setor14');
  ok(r.setor.mesiu === 100 && r.setor.besi === 100 && (await one(`select game.item_qty($1, 'mesiu') q`, [pid])).q === 40, 'setor tepat 100, sisa tetap di palka');
  await H.sql(`insert into game.pv_pusaka(player_id, pusaka_id, mutu, slot) values ($1, 'lunas_ulin', null, 3)`, [pid]);
  // tempa ulang jangkar
  await place('empeer_depeer');
  r = await act('tempa14', '80', '9000');
  ok(r.grade === 'baik' && r.naik, 'tempa ulang: Jangkar Baik');
  r = await act('tempa14', '55', '9000');
  ok(!r.naik && (await gs()).pasir.q14.jangkar === 'baik', 'tempa lebih buruk tidak menurunkan mutu');
  s = await gs();
  ok(s.pasir.q14.siap && s.pasir.zaman.includes('pusaran'), 'siap: Jam Agung menunjuk Malam Pusaran');

  // --- Babak 2: lompat ---
  await act('lompat', 'pusaran');
  s = await gs();
  ok(s.pasir.era === 'pusaran' && s.pasir.q14.step === 2, 'Malam Pusaran');
  await H.expectError(() => A.call('api_setSail', ['joungjava']), /pusaran/);
  await act('lihat14');
  ok((await gs()).pasir.q14.step === 3, 'langkah 3: bos');

  // --- Babak 3: bos 3 fase ---
  await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);
  await A.call('api_setSail', ['pusaran']); await H.shiftTime(900000); await A.call('api_pollVoyage', []);
  let e = await pend();
  ok(e && e.q14 === 1 && e.perisai === true && Number(e.dmgTaken) < 1, 'fase 1: Tirai Pasir (melawan arus)');
  // kalah sekali: HP tersimpan
  await H.sql(`update game.player_location set pending_encounter = jsonb_set(pending_encounter, '{enemyHp}', '1300') where player_id = $1`, [pid]);
  await H.sql(`update game.ships set condition = 1 where player_id = $1`, [pid]);
  let guard = 0, res;
  while (guard++ < 40) { const x = await pend(); if (!x) break; res = await A.call('api_resolveCombat', [Number(x.ammoRemaining) > 0 ? 'fire' : 'reload']); if (!res.ongoing) break; }
  ok(res && res.result === 'sunk', 'kalah: kembali');
  s = await gs();
  ok(s.pasir.q14.step === 3 && s.pasir.q14.d.fase === 1 && s.pasir.q14.d.hp <= 1300 && s.pasir.q14.d.kalah === 1, 'HP Janji Putih tersimpan');
  // baca arus, serang lagi, menang 3 fase berantai
  await place('empeer_depeer');
  await act('arus14', 'ok');
  const fight = async () => {
    await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);
    await A.call('api_setSail', ['pusaran']); await H.shiftTime(900000); await A.call('api_pollVoyage', []);
    const seen = []; let out = null, g = 0;
    while (g++ < 200) {
      await H.sql(`update game.ships set condition = 100 where player_id = $1`, [pid]);
      const x = await pend(); if (!x) break;
      if (!seen.includes(x.q14)) seen.push(x.q14);
      if (x.q14 === 1) ok(x.perisai === false, 'arus searah: perisai terbuka');
      if (x.q14 === 2) ok(Number(x.allyDmg) > 0, 'fase 2: Uda Gala datang');
      if (x.q14 === 3) ok(Number(x.kacaLimit) === 10, 'fase 3: Kaca Ketujuh (Jangkar Baik = 10 ronde)');
      out = await A.call('api_resolveCombat', [Number(x.ammoRemaining) > 0 ? 'fire' : 'reload']);
      if (!out.ongoing) break;
    }
    return { seen, out };
  };
  let f = await fight(); guard = 0;
  while ((await gs()).pasir.q14.step === 3 && guard++ < 8) { await place('empeer_depeer'); await act('arus14', 'ok'); f = await fight(); }
  s = await gs();
  ok(s.pasir.q14.step === 4, 'tiga fase dimenangkan (fase terlihat: ' + f.seen.join(',') + ')');

  // kaca ketujuh pecah bila terlalu lama
  const ek = await one(`select game.voy_enc_book($1, game.ps14_enc($1, 3, 500) || '{"round": 11}'::jsonb) e`, [pid]);
  ok(ek.e.kacaPecah === true && Number(ek.e.enemyDmgMul) >= 40, 'bilah penuh: kaca pecah');

  // --- Babak 4–7: lepas & pulih ---
  const g0 = Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  await H.expectError(() => act('nasib14', 'pergi'), /Aksi tidak dikenal/);
  r = await act('lepas14');
  ok(r.bunga === 100000, 'Bunga Waktu 10% dari gold & bank potret: ' + r.bunga);
  s = await gs();
  ok(s.pasir.era === 'kini' && s.pasir.q14.step === 5 && s.city.CityId === 'skitraw', 'bangun di Gaul-Wash, Masa Kini');
  const g1 = Number((await one('select gold from game.players where player_id = $1', [pid])).gold);
  ok(g1 === g0 + 800000 + 100000, 'gold kembali + gold selama saga + bunga');
  ok(Number((await one('select bank_balance b from game.players where player_id = $1', [pid])).b) === 200000, 'bank kembali');
  ok(s.pasir.zaman.length === 0, 'masa lalu tertutup selamanya');
  ok((await one(`select game.ps_toko_buka($1, 'pustaka') b`, [pid])).b === false, 'Pustaka Agung tertutup');
  ok((await one(`select count(*)::int n from game.pv_pusaka where player_id = $1`, [pid])).n === 3, 'Pusaka tetap dimiliki');
  await act('nasib14', 'dewan');
  s = await gs();
  ok(s.pasir.q14.done && s.pasir.riak.nasib_fz === 'dewan', 'epilog: nasib Franziska');

  // --- Kedai: set Saga 3 ---
  const kd = (await A.call('api_kedai', ['daftar'])).kedai.items;
  const ids = kd.map(i => i.id);
  ok(ids.includes('aura_pasir') && ids.includes('layar_surat') && ids.includes('lambung_pelitur'), 'set Saga 3 terlihat bagi yang membukanya');
  ok(kd.filter(i => i.set === 'pasir_waktu').every(i => !i.locked), 'Pasir Waktu terbuka');
  const C = await H.user('q14c_cici');
  await C.call('api_createCharacter', ['Kapten Cici', 'merchant']);
  const kc = (await C.call('api_kedai', ['daftar'])).kedai.items;
  ok(!kc.some(i => ['zaman_gemilang', 'benang_merah', 'pasir_waktu'].includes(i.set)), 'pemain biasa: tidak ada set Saga 3 di katalog');
  const rc = await C.call('api_rupa', ['status']);
  ok(!JSON.stringify(rc).includes('pasir_waktu') && !JSON.stringify(rc).includes('Benang Merah'), 'pemain biasa: Lemari Rupa tanpa set Saga 3');
  await H.sql(`update game.players set keping = 99999 where player_id = $1`, [C.id]);
  await H.expectError(() => C.call('api_kedai', ['beli', 'aura_pasir']), /tidak ada di Kedai/);
  ok((await C.call('api_getGameState', [])).pasir === undefined, 'pemain biasa: tanpa key pasir');

  console.log('0057 pasir q14: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
