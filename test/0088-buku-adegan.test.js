// 0088 Buku Adegan: penanda adegan dicadangkan di server (api_seenMark + kunci 'seen' di api_getGameState).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const a = await H.user('bkalice'), b = await H.user('bkbob');
  await a.call('api_createCharacter', ['Kapten Alice', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Bob', 'merchant']);
  const seen = async (u) => (await u.call('api_getGameState', [null, 'seen'])).seen;

  // getGameState biasa tidak membawa 'seen'
  let gs = await a.call('api_getGameState', [null]);
  assert(gs.player && !('seen' in gs), 'tanpa permintaan, seen tidak dikirim');
  gs = await a.call('api_getGameState', []);
  assert(!('seen' in gs) && !('cities' in gs), 'argumen kosong: perilaku lama');

  // kapten baru (dibuat sesudah rilis): kosong, penjaga mati
  let s = await seen(a);
  assert(s && JSON.stringify(s.k) === '{}' && s.g === false, 'kapten baru: kosong & tanpa penjaga ' + JSON.stringify(s));

  // kapten lama (sebelum rilis), belum ada cadangan -> penjaga hidup
  await H.sql(`update game.players set created_at = now() - interval '30 days' where player_id = $1`, [b.id]);
  s = await seen(b);
  assert(s.g === true, 'kapten lama tanpa cadangan: penjaga hidup');

  // tandai: string = '1', pasangan [k, v] = nilai apa adanya
  let r = await a.call('api_seenMark', [['kp:bkalice:storm', ['ps:bkalice:benang', '{"a":1}'], ['bx:patrol:Kapten Alice', '12345'], 'th_open-2026-11-18', 'mt_pr_tj1:Kapten Alice', 'mt_trek_best', 'mt_seen_guard:bkalice']]);
  assert(r.ok && r.n === 7 && r.lewat === 0, 'tandai 7 ' + JSON.stringify(r));
  s = await seen(a);
  assert(s.k['kp:bkalice:storm'] === '1' && s.k['ps:bkalice:benang'] === '{"a":1}' && s.k['bx:patrol:Kapten Alice'] === '12345', 'nilai pulih persis');
  assert(Object.keys(s.k).length === 7 && s.g === false, '7 kunci');

  // idempotent: ulang = 0 berubah; nilai beda = diperbarui
  r = await a.call('api_seenMark', [['kp:bkalice:storm', 'kp:bkalice:storm']]);
  assert(r.n === 0 && r.lewat === 0, 'ulang tidak menambah ' + JSON.stringify(r));
  r = await a.call('api_seenMark', [[['bx:patrol:Kapten Alice', '99999']]]);
  assert(r.n === 1, 'nilai diperbarui');
  assert((await seen(a)).k['bx:patrol:Kapten Alice'] === '99999', 'nilai baru tersimpan');
  assert(Number((await H.sql(`select count(*) n from game.player_seen where player_id = $1`, [a.id]))[0].n) === 7, 'tetap 7 baris');

  // validasi pola & ukuran
  r = await a.call('api_seenMark', [['mt_sb_auth_v1', 'mt_snap_v3:bkalice', 'mt_volume', 'xx:a:b', 'kp:' + 'x'.repeat(100), ['kp:bkalice:big', 'y'.repeat(2001)], 42, null, { k: 1 }]]);
  assert(r.n === 0 && r.lewat === 9, 'pola terlarang / terlalu panjang ditolak ' + JSON.stringify(r));
  await H.expectError(() => a.call('api_seenMark', [Array.from({ length: 201 }, (_, i) => 'kp:bkalice:x' + i)]), /maks 200/);
  r = await a.call('api_seenMark', [null]);
  assert(r.ok && r.n === 0, 'argumen kosong aman');

  // hanya milik sendiri: Bob tidak melihat kunci Alice; penjaga Bob mati sesudah ada cadangan
  s = await seen(b);
  assert(JSON.stringify(s.k) === '{}', 'Bob tidak melihat kunci Alice');
  await b.call('api_seenMark', [['kp:bkbob:ikn5']]);
  s = await seen(b);
  assert(Object.keys(s.k).join() === 'kp:bkbob:ikn5' && s.g === false, 'Bob: kuncinya sendiri saja, penjaga mati');
  assert(!('kp:bkalice:storm' in s.k), 'tidak bocor');

  // hapus (argumen kedua)
  r = await a.call('api_seenMark', [[], ['ps:bkalice:benang', 'ps:bkalice:tidakada', 'mt_volume']]);
  assert(r.hapus === 1, 'hapus 1 ' + JSON.stringify(r));
  assert(!('ps:bkalice:benang' in (await seen(a)).k), 'terhapus');
  // Bob tidak bisa menghapus kunci Alice (kunci sama namanya pun hanya miliknya sendiri)
  await b.call('api_seenMark', [[], ['kp:bkalice:storm']]);
  assert((await seen(a)).k['kp:bkalice:storm'] === '1', 'kunci Alice aman dari Bob');

  // batas jumlah kunci per pemain
  await H.sql(`update game.config set value = '10' where key = 'SeenMaksKunci'`);
  r = await a.call('api_seenMark', [['kp:bkalice:n1', 'kp:bkalice:n2', 'kp:bkalice:n3', 'kp:bkalice:n4', 'kp:bkalice:n5', 'kp:bkalice:n6']]);
  assert(r.n === 4 && r.lewat === 2, 'batas 10 kunci ' + JSON.stringify(r));
  r = await a.call('api_seenMark', [[['kp:bkalice:storm', '2']]]);
  assert(r.n === 1, 'kunci lama tetap bisa diperbarui saat penuh');
  await H.sql(`update game.config set value = '3000' where key = 'SeenMaksKunci'`);

  // tanpa login: ditolak
  const anon = await H.anon();
  await H.expectError(() => anon.call('api_seenMark', [['kp:x:y']]), /./);

  console.log('OK 0088-buku-adegan');
})().catch(e => { console.error(e); process.exit(1); });
