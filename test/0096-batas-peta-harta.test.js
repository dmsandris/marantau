// Batas harian peta harta (0096): beli maks 5/hari, galian per lokasi minus setelah 30/hari.
const assert = require('assert');

(async () => {
  const H = await require('./harness').create({ only: f => /^(0001|0004|0096)/.test(f) });
  async function mkPlayer(username, gold, city) {
    const u = await H.user(username);
    await H.sql(`insert into game.players(player_id, username, character_name, archetype, gold) values ($1, $2, $3, 'merchant', $4)`,
      [u.id, username, username[0].toUpperCase() + username.slice(1), gold]);
    await H.sql('insert into game.character_stats(player_id) values ($1)', [u.id]);
    await H.sql('insert into game.ships(player_id) values ($1)', [u.id]);
    await H.sql('insert into game.player_location(player_id, city_id, arrived_game_day) values ($1, $2, 0)', [u.id, city]);
    return u;
  }
  const one = async (q, p) => (await H.sql(q, p))[0];
  const gold = async u => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  const invQty = async (u, item) => Number((await one('select coalesce((select qty from game.inventory where player_id = $1 and item_id = $2), 0) q', [u.id, item])).q);
  const geser = (u, hari) => H.sql('update game.treasure_daily set hari = hari - $2::int where player_id = $1', [u.id, hari]);

  // ---------------- beli: maks 5 per hari
  const A = await mkPlayer('moro', 100000, 'sunda_empire');
  for (let i = 0; i < 5; i++) await A.call('api_buyTreasureMap', ['tm_sunda_reef']);
  assert.strictEqual(await invQty(A, 'tm_sunda_reef'), 5);
  assert.strictEqual(await gold(A), 100000 - 5 * 250);
  await H.expectError(() => A.call('api_buyTreasureMap', ['tm_sunda_reef']), /hanya melayani 5 peta per hari/);
  await H.expectError(() => A.call('api_buyTreasureMap', ['tm_ikn_ruins']), /hanya melayani 5 peta per hari/);  // batas total, bukan per jenis
  assert.strictEqual(await gold(A), 100000 - 5 * 250, 'gold tidak berkurang saat ditolak');
  assert.strictEqual(await invQty(A, 'tm_sunda_reef'), 5);
  // hari berikutnya: slot kembali
  await geser(A, 1);
  await A.call('api_buyTreasureMap', ['tm_sunda_reef']);
  assert.strictEqual(await invQty(A, 'tm_sunda_reef'), 6);
  // pembelian paralel tidak bisa menembus batas
  const B = await mkPlayer('paralel', 100000, 'sunda_empire');
  const res = await Promise.allSettled(Array.from({ length: 12 }, () => B.call('api_buyTreasureMap', ['tm_sunda_reef'])));
  assert.strictEqual(res.filter(r => r.status === 'fulfilled').length, 5, 'paralel: tepat 5 berhasil');
  assert.strictEqual(await invQty(B, 'tm_sunda_reef'), 5);
  // ditolak bila gold kurang tidak memakan slot
  const C = await mkPlayer('miskin', 100, 'sunda_empire');
  await H.expectError(() => C.call('api_buyTreasureMap', ['tm_sunda_reef']), /Gold tidak cukup/);
  assert.strictEqual(Number((await one('select count(*) n from game.treasure_daily where player_id = $1', [C.id])).n), 0);
  console.log('batas beli ok');

  // ---------------- gali: 30 pertama normal, berikutnya minus
  const D = await mkPlayer('penggali', 5000, 'sunda_empire');
  await H.sql(`select game.item_adjust($1, 'tm_sunda_reef', 40)`, [D.id]);
  await H.sql('select setseed(0.4242)');
  const hasil = [];
  for (let i = 1; i <= 30; i++) {
    const g0 = await gold(D);
    const r = await D.call('api_digTreasure', ['tm_sunda_reef']);
    assert.notStrictEqual(r.outcome, 'terkuras', 'galian ' + i + ' belum terkuras');
    assert(r.goldDelta >= 0, 'galian normal tidak minus');
    assert.strictEqual(await gold(D), g0 + r.goldDelta);
    hasil.push(r.outcome);
  }
  const bank = async u => Number((await one('select bank_balance from game.players where player_id = $1', [u.id])).bank_balance);
  // galian ke-31: denda acak 1.000-100.000, gold dulu lalu bank (bank cukup besar -> total denda utuh)
  await H.sql('update game.players set gold = 50000, bank_balance = 1000000 where player_id = $1', [D.id]);
  for (let k = 0; k < 4; k++) {
    const g0 = await gold(D), b0 = await bank(D);
    const r = await D.call('api_digTreasure', ['tm_sunda_reef']);
    assert.strictEqual(r.outcome, 'terkuras');
    assert.strictEqual(r.grantedItem, null);
    assert.strictEqual(r.conditionDelta, 0);
    const denda = -(r.goldDelta + r.bankDelta);
    assert(denda >= 1000 && denda <= 100000, 'denda 1.000-100.000: ' + denda);
    assert(r.goldDelta <= 0 && r.bankDelta <= 0);
    assert.strictEqual(await gold(D), g0 + r.goldDelta);
    assert.strictEqual(await bank(D), b0 + r.bankDelta);
    assert.strictEqual(r.newGold, g0 + r.goldDelta);
    assert.strictEqual(r.newBank, b0 + r.bankDelta);
    assert.strictEqual(r.goldDelta, 0 - Math.min(g0, denda), 'gold dipotong dulu');
    assert(/terlalu sering hari ini/.test(r.message));
  }
  assert.strictEqual(await invQty(D, 'tm_sunda_reef'), 40 - 30 - 4, 'peta tetap habis terpakai');
  // gold 0, bank berisi: seluruh denda dari bank
  await H.sql('update game.players set gold = 0, bank_balance = 500000 where player_id = $1', [D.id]);
  let r = await D.call('api_digTreasure', ['tm_sunda_reef']);
  assert.strictEqual(r.goldDelta, 0); assert(r.bankDelta <= -1000 && r.bankDelta >= -100000, 'bank: ' + r.bankDelta);
  assert.strictEqual(await gold(D), 0);
  // gold sedikit + bank sedikit: keduanya sampai 0, tidak pernah negatif
  await H.sql('update game.players set gold = 10, bank_balance = 5 where player_id = $1', [D.id]);
  r = await D.call('api_digTreasure', ['tm_sunda_reef']);
  assert.strictEqual(await gold(D), 0); assert.strictEqual(await bank(D), 0);
  assert.strictEqual(r.goldDelta, -10); assert.strictEqual(r.bankDelta, -5);
  // gold 0 dan bank 0: tidak ada yang bisa diambil
  r = await D.call('api_digTreasure', ['tm_sunda_reef']);
  assert.strictEqual(r.goldDelta, 0); assert.strictEqual(r.bankDelta, 0);
  assert.strictEqual(await gold(D), 0); assert.strictEqual(await bank(D), 0);
  // lokasi lain dihitung terpisah
  await H.sql(`update game.player_location set city_id = 'joungjava' where player_id = $1`, [D.id]);
  await H.sql(`select game.item_adjust($1, 'tm_joungjava_grove', 1)`, [D.id]);
  const rj = await D.call('api_digTreasure', ['tm_joungjava_grove']);
  assert.notStrictEqual(rj.outcome, 'terkuras', 'lokasi lain tidak ikut terkuras');
  // hari berikutnya: hitungan galian kembali ke nol
  await H.sql(`update game.player_location set city_id = 'sunda_empire' where player_id = $1`, [D.id]);
  await geser(D, 1);
  const rb = await D.call('api_digTreasure', ['tm_sunda_reef']);
  assert.notStrictEqual(rb.outcome, 'terkuras', 'hari baru: normal lagi');
  console.log('batas gali ok');

  // ---------------- batas bisa diubah lewat config
  await H.sql(`update game.config set value = '2' where key = 'TreasureBuyPerDay'`);
  const E = await mkPlayer('config', 100000, 'sunda_empire');
  await E.call('api_buyTreasureMap', ['tm_sunda_reef']); await E.call('api_buyTreasureMap', ['tm_sunda_reef']);
  await H.expectError(() => E.call('api_buyTreasureMap', ['tm_sunda_reef']), /hanya melayani 2 peta per hari/);
  console.log('OK 0096 batas peta harta');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
