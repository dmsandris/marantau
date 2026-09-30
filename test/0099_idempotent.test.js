// Semua migrasi dijalankan 2x di atas data yang sudah ada -> harus sukses & data pemain utuh.
const fs = require('fs'), path = require('path');
const H0 = require('./harness');
(async () => {
  const H = await H0.create();
  const u = await H.user('ulang');
  await u.call('api_createCharacter', ['Ulang Alik', 'merchant']);
  await u.call('api_buy', ['sunda_empire', 'sugar', 3]);
  const before = await u.call('api_getGameState', [null]);
  const ws = (await H.sql(`select value from game.config where key = 'WorldStartTimestamp'`))[0];
  const dir = path.join(__dirname, '..', 'supabase', 'migrations');
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.sql')).sort()) {
    try { await H.db.exec(fs.readFileSync(path.join(dir, f), 'utf8')); }
    catch (e) { console.error('GAGAL ulang', f, e.message); process.exit(1); }
  }
  const after = await u.call('api_getGameState', [null]);
  const ws2 = (await H.sql(`select value from game.config where key = 'WorldStartTimestamp'`))[0];
  const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.error('BEDA', m, a, b); process.exit(1); } };
  eq(before.player.gold, after.player.gold, 'gold');
  eq(before.player.characterName, after.player.characterName, 'nama');
  eq(ws, ws2, 'WorldStartTimestamp');
  const cargo = await u.call('api_getCargo', []);
  if (!JSON.stringify(cargo).includes('sugar')) { console.error('cargo hilang', cargo); process.exit(1); }
  console.log('IDEMPOTENT TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
