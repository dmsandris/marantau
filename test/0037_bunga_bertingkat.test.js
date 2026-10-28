// Tide v39: Bunga Bertingkat — bunga bank per bagian saldo, berhenti di atas 20 jt.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const P = await H.user('bunga_kapten');
  await P.call('api_createCharacter', ['Kapten Bunga', 'merchant']);
  const pid = P.id;
  const day = Number((await one('select game.game_day() d')).d);

  // Set saldo & mundurkan hari bunga n hari, lalu baca state bank
  const run = async (bal, days) => {
    await H.sql('update game.players set bank_balance = $1, bank_last_interest_day = $2 where player_id = $3', [bal, day - days, pid]);
    return await P.call('api_getBankState', []);
  };
  const near = (a, b, m) => ok(Math.abs(Number(a) - b) <= 1, m + ' (dapat ' + a + ', harap ' + b + ')');

  // Config & tingkat
  const cfg = await one(`select value from game.config where key = 'BankTier'`);
  ok(cfg && cfg.value === '5000000:0.5,10000000:0.3,20000000:0.2,inf:0', 'config BankTier default');
  let b = await run(1000, 0);
  ok(b.bankTiers === undefined && b.bankInterestDay === undefined && b.bankInterestCap === undefined, 'rincian tingkat tidak dikirim ke klien');
  ok(Number(b.bankRatePercent) === 0.5 && Number(b.bankRateMinPercent) === 0, 'klien hanya menerima rentang 0% s/d 0,5%');

  // Satu hari, tiap tingkat
  b = await run(1000000, 1);                 // 1 jt × 0,5%
  near(b.bankBalance, 1005000, 'saldo 1 jt: +5.000');
  b = await run(5000000, 1);                 // tepat 5 jt -> semuanya 0,5%
  near(b.bankBalance, 5025000, 'saldo 5 jt: +25.000');
  b = await run(8000000, 1);                 // 25.000 + 3 jt × 0,3%
  near(b.bankBalance, 8034000, 'saldo 8 jt: +34.000');
  b = await run(15000000, 1);                // 25.000 + 15.000 + 5 jt × 0,2%
  near(b.bankBalance, 15050000, 'saldo 15 jt: +50.000');
  b = await run(20000000, 1);
  near(b.bankBalance, 20060000, 'saldo 20 jt: +60.000');
  b = await run(35345842, 1);                // saldo terkaya: hanya 60.000
  near(b.bankBalance, 35405842, 'saldo 35 jt: tetap +60.000');

  // Banyak hari: di atas 20 jt tumbuh lurus, bukan majemuk
  b = await run(35000000, 80);               // 10 hari nyata
  near(b.bankBalance, 35000000 + 80 * 60000, '80 hari di atas 20 jt: lurus 60.000/hari');

  // Melintasi batas: mulai 19,99 jt, majemuk di bawah lalu lurus di atas
  b = await run(19990000, 3);
  ok(Number(b.bankBalance) > 20100000 && Number(b.bankBalance) <= 19990000 + 3 * 60000, 'melewati 20 jt: tidak lebih dari 60.000/hari');

  // Saldo kecil tetap majemuk 0,5% (sama seperti sebelumnya)
  b = await run(100000, 8);
  near(b.bankBalance, Math.round(100000 * Math.pow(1.005, 8)), 'saldo kecil: majemuk 0,5% seperti dulu');

  // Saldo nol / tidur sangat lama tidak error
  b = await run(0, 50);
  ok(Number(b.bankBalance) === 0, 'saldo nol tetap nol');
  b = await run(500, 20000);
  ok(Number(b.bankBalance) > 500, 'akun tidur lama: tetap terhitung tanpa error');

  // Hari bunga tersimpan (tidak dihitung dua kali)
  b = await run(10000000, 1);
  const again = await P.call('api_getBankState', []);
  ok(Number(again.bankBalance) === Number(b.bankBalance), 'panggilan kedua di hari sama tidak menambah bunga');

  // Setor tetap jalan dengan bunga bertingkat
  await H.sql('update game.players set gold = 50000, bank_balance = 21000000, bank_last_interest_day = $1 where player_id = $2', [day - 1, pid]);
  const dep = await P.call('api_bankDeposit', [10000]);
  near(dep.bankBalance, 21000000 + 60000 + 10000, 'setor: bunga tertunda + setoran');

  // Config bisa diubah GM (mis. kembali ke satu tingkat)
  await H.sql(`update game.config set value = 'inf:0.5' where key = 'BankTier'`);
  b = await run(35000000, 1);
  near(b.bankBalance, 35175000, 'config satu tingkat: 0,5% penuh');
  ok(Number(b.bankRateMinPercent) === 0.5, 'satu tingkat: rentang jadi 0,5% saja');
  await H.sql(`update game.config set value = '' where key = 'BankTier'`);
  b = await run(1000000, 1);
  near(b.bankBalance, 1005000, 'config kosong: kembali ke BankInterestRatePercent');

  console.log('0037 bunga bertingkat: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
