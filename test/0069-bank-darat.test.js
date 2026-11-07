// Tide v54 · Bank di Darat: bank & moneylender ditolak saat berlayar / saat bajak laut menghadang.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const MSG = /PelicanSystem sedang offline, Kapten\. Bank hanya melayani saat kapal merapat\./;

  const A = await H.user('bank_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  await H.sql(`update game.players set gold = 100000, bank_balance = 50000, debt_balance = 0 where player_id = $1`, [A.id]);
  const money = async () => one(`select gold, bank_balance, debt_balance from game.players where player_id = $1`, [A.id]);

  // --- Merapat: semua layanan jalan ---
  await A.call('api_bankDeposit', [10000]);
  await A.call('api_bankWithdraw', [5000]);
  await A.call('api_bankBorrow', [1000]);
  await A.call('api_bankRepay', [1000]);
  let m = await money();
  ok(Number(m.gold) === 95000 && Number(m.bank_balance) >= 55000 && Number(m.debt_balance) === 0, 'merapat: setor/tarik/pinjam/bayar berjalan');

  // --- Berlayar: semua ditolak, uang tidak bergerak ---
  const dest = (await one(`select city_id from game.cities where city_id <> game.current_city($1) and not coalesce(hidden, false) order by city_id limit 1`, [A.id])).city_id;
  await A.call('api_setSail', [dest]);
  ok((await one('select game.in_transit($1) t', [A.id])).t === true, 'sedang berlayar');
  const before = await money();
  await H.expectError(() => A.call('api_bankDeposit', [1000]), MSG);
  await H.expectError(() => A.call('api_bankWithdraw', [1000]), MSG);
  await H.expectError(() => A.call('api_bankBorrow', [1000]), MSG);
  await H.expectError(() => A.call('api_bankRepay', [1000]), MSG);
  m = await money();
  ok(m.gold === before.gold && m.bank_balance === before.bank_balance && m.debt_balance === before.debt_balance, 'berlayar: saldo tidak berubah');
  const lg = await H.sql(`select 1 from game.player_log where player_id = $1 and message like 'Deposited 1000 gold%'`, [A.id]);
  ok(lg.length === 0, 'berlayar: tidak ada log setor');
  // Status bank tetap bisa dilihat
  const bs = await A.call('api_getBankState', []);
  ok(bs && bs.bankBalance != null, 'berlayar: status bank tetap bisa dibaca');

  // --- Bajak laut menghadang (encounter tertunda, walau sudah di kota) ---
  await H.sql(`update game.player_location set destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = '{"kind":"pirate","level":3}'::jsonb where player_id = $1`, [A.id]);
  ok((await one('select game.in_transit($1) t', [A.id])).t === false, 'tidak berlayar, tapi ada pertempuran tertunda');
  await H.expectError(() => A.call('api_bankDeposit', [1000]), MSG);
  await H.expectError(() => A.call('api_bankBorrow', [1000]), MSG);

  // --- Merapat lagi: normal ---
  await H.sql(`update game.player_location set pending_encounter = null where player_id = $1`, [A.id]);
  await A.call('api_bankDeposit', [1000]);
  m = await money();
  ok(Number(m.gold) === Number(before.gold) - 1000, 'merapat lagi: setor berjalan');

  console.log('0069 bank darat: semua lulus');
  process.exit(0);
})().catch((e) => { console.error('GAGAL:', e && e.message || e); process.exit(1); });
