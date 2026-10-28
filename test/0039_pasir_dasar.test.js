// Tide v41 · Pasir Batch 0 — gerbang, key state tersembunyi, era & nada, alat GM.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const cfg = (k, v) => H.sql('update game.config set value = $2 where key = $1', [k, v]);
  const gs = (P) => P.call('api_getGameState', []);

  const A = await H.user('ps_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const G = await H.user('abuy');
  await G.call('api_createCharacter', ['Kapten GM', 'navigator']);

  // --- Tertutup bawaan: tidak ada jejak sama sekali ---
  ok((await H.sql(`select value from game.config where key = 'PasirOpen'`))[0].value === '0', 'PasirOpen bawaan 0');
  let s = await gs(A);
  ok(!('pasir' in s), 'pemain biasa: key pasir tidak ada');
  s = await gs(G);
  ok(!('pasir' in s), 'GM tanpa FiturPenguji: key pasir tidak ada');
  await H.expectError(() => A.call('api_pasir', ['status']), /Aksi tidak dikenal/);
  await H.expectError(() => G.call('api_pasir', ['gm', 'era', 'lampau']), /Aksi tidak dikenal/);

  // Syarat dunia terpenuhi tapi fitur tertutup -> tetap tidak ada
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'duatangan', 5)`, [A.id]);
  ok(!('pasir' in await gs(A)), 'saga3 + Q9 tapi PasirOpen 0: tetap tertutup');

  // --- Dibuka: aktif, tapi key baru muncul setelah pemain masuk Saga ---
  await cfg('PasirOpen', '1');
  ok(!('pasir' in await gs(A)), 'aktif tapi belum masuk: key belum dikirim');
  ok((await H.sql('select game.pasir_aktif($1) a', [A.id]))[0].a === true, 'pasir_aktif untuk veteran Q9 + saga3');
  const B = await H.user('ps_budi');
  await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  ok((await H.sql('select game.pasir_aktif($1) a', [B.id]))[0].a === false, 'belum tamat Q9: tidak aktif');
  await H.sql(`delete from game.world_flags where key = 'saga3'`);
  ok((await H.sql('select game.pasir_aktif($1) a', [A.id]))[0].a === false, 'tanpa bendera saga3: tidak aktif');
  await H.sql(`insert into game.world_flags(key) values ('saga3')`);

  await H.sql('select game.pasir_ensure($1)', [A.id]);
  s = await gs(A);
  ok(s.pasir && s.pasir.era === 'kini' && s.pasir.tone === 'kini' && s.pasir.kacaMax === 7, 'masuk: era kini, 7 kaca');
  ok(!('gm' in s.pasir), 'pemain biasa tidak menerima bendera gm');
  ok(s.pasir.q && s.pasir.q['10'] === 0, 'langkah quest 0');
  ok(JSON.stringify(s.pasir).indexOf('keadilan') < 0 || s.pasir.era === 'keadilan', 'tidak membocorkan daftar era');

  // Era -> nada
  const tones = { kini: 'kini', keadilan: 'dingin', badai: 'sepia', lampau: 'emas', pusaran: 'kedip' };
  for (const [e, t] of Object.entries(tones)) {
    await H.sql(`select game.admin_pasir('ps_ana', 'era', $1)`, [e]);
    s = await gs(A);
    ok(s.pasir.era === e && s.pasir.tone === t, `era ${e} -> nada ${t}`);
    ok((await H.sql('select game.pasir_era($1) e', [A.id]))[0].e === e, 'pasir_era ' + e);
  }
  await H.expectError(() => H.sql(`select game.admin_pasir('ps_ana', 'era', 'masa_depan')`), /Era harus/);
  await H.expectError(() => H.sql(`select game.admin_pasir('tidakada', 'lihat')`), /tidak ditemukan/);

  // Bila fitur ditutup lagi, era kembali 'kini' untuk semua sistem
  await cfg('PasirOpen', '0');
  ok((await H.sql('select game.pasir_era($1) e', [A.id]))[0].e === 'kini', 'fitur ditutup: era kini');
  ok(!('pasir' in await gs(A)), 'fitur ditutup: key hilang');
  await cfg('PasirOpen', '1');

  // --- Pemain biasa tidak bisa memakai alat GM ---
  await H.expectError(() => A.call('api_pasir', ['gm', 'era', 'kini']), /Aksi tidak dikenal/);
  let r = await A.call('api_pasir', ['status']);
  ok(r.pasir && r.pasir.era === 'pusaran', 'status pemain');

  // --- GM (lolos syarat dunia, tetap butuh fitur terbuka) ---
  await H.sql(`delete from game.world_flags where key = 'saga3'`);
  s = await gs(G);
  ok(s.pasir && s.pasir.gm === true && s.pasir.era === 'kini', 'GM: key ada walau belum masuk, bendera gm');
  r = await G.call('api_pasir', ['gm', 'era', 'lampau']);
  ok(r.pasir.tone === 'emas' && r.gm.row.era === 'lampau', 'GM set era lewat api');
  r = await G.call('api_pasir', ['gm', 'retak', '150']);
  ok(r.pasir.retak === 100, 'retak dibatasi 100');
  r = await G.call('api_pasir', ['gm', 'kaca', '3']);
  ok(r.pasir.kaca === 3, 'kaca 3');
  r = await G.call('api_pasir', ['gm', 'langkah', 'ps12', '4']);
  ok(r.pasir.q['12'] === 4 && r.gm.quests.ps12.step === 4, 'langkah quest');
  await H.expectError(() => G.call('api_pasir', ['gm', 'langkah', 'gala', '4']), /ps10\.\.ps14/);
  r = await G.call('api_pasir', ['gm', 'reset']);
  ok(r.gm.row === null && Object.keys(r.gm.quests).length === 0 && r.pasir.era === 'kini', 'reset bersih');
  await H.expectError(() => G.call('api_pasir', ['gm', 'hapus_dunia']), /Aksi GM tidak dikenal/);

  // Fitur tertutup: GM pun tidak bisa
  await cfg('PasirOpen', '0');
  await H.expectError(() => G.call('api_pasir', ['status']), /Aksi tidak dikenal/);
  // Penguji tanpa membuka untuk umum
  await H.sql(`update game.config set value = 'abuy' where key = 'FiturPenguji'`);
  ok((await gs(G)).pasir.gm === true, 'GM lewat FiturPenguji');
  ok(!('pasir' in await gs(A)), 'pemain lain tetap tertutup saat hanya penguji');

  console.log('0039 pasir dasar: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
