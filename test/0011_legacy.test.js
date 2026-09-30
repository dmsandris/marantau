// Klaim kapten lama (Google Sheets) oleh akun Supabase baru. Data sintetis - bukan data pemain asli.
const crypto = require('crypto');
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
function legacyHash(p, salt) { let h = salt + '|' + p; for (let i = 0; i < 250; i++) h = crypto.createHash('sha256').update(h + '|' + salt, 'utf8').digest('hex'); return h; }
(async () => {
  const H = await require('./harness').create();
  // hash SQL == hash AuthService.gs (diimplementasi ulang di JS)
  const salt = 'c0ffee-salt', pw = 'Rahasia#Laut 9é';
  const sqlHash = (await H.sql('select game.legacy_hash($1, $2) h', [pw, salt]))[0].h;
  assert(sqlHash === legacyHash(pw, salt), 'hash SQL beda dengan versi Apps Script');

  // semua FK ke players sekarang ON UPDATE CASCADE
  const bad = await H.sql(`select conrelid::regclass::text t from pg_constraint where contype='f' and confrelid='game.players'::regclass and confupdtype <> 'c'`);
  assert(bad.length === 0, 'FK tanpa on update cascade: ' + bad.map(b => b.t));

  // kapten lama (placeholder) seperti hasil tools/import_legacy.py
  const old = crypto.randomUUID();
  await H.sql(`insert into game.players(player_id, username, character_name, archetype, gold, bank_balance, legacy_id)
    values ($1, 'lamo', 'Kapten Lamo', 'merchant', 4321, 999, 'lamo@gmail.com')`, [old]);
  await H.sql(`insert into game.character_stats(player_id) values ($1)`, [old]);
  await H.sql(`insert into game.ships(player_id, condition) values ($1, 77)`, [old]);
  await H.sql(`insert into game.player_location(player_id, city_id, arrived_game_day) values ($1, 'ikn', 1)`, [old]);
  await H.sql(`insert into game.inventory(player_id, item_id, qty) values ($1, 'rum', 7)`, [old]);
  await H.sql(`insert into game.player_books(player_id, book_id, date_acquired) values ($1, 'bk_trading_1', 1)`, [old]);
  await H.sql(`insert into game.player_missions(player_id, status, city_id, commodity_id, qty, deliver_to_city_id, reward, type, loaded_qty)
    values ($1, 'active', 'ikn', 'tools', 3, 'skitraw', 100, 'courier', 3)`, [old]);
  await H.sql(`insert into game.player_log(player_id, game_day, message) values ($1, 1, 'catatan lama')`, [old]);
  await H.sql(`insert into game.legacy_accounts(username, pass_hash, salt, player_id, legacy_id) values ('lamo', $1, $2, $3, 'lamo@gmail.com')`,
    [legacyHash('laut1234', 'sx'), 'sx', old]);

  const anon = await H.anon();
  // username lama tidak bisa didaftarkan orang lain
  assert((await anon.call('api_usernameAvailable', ['lamo'])).available === false, 'username lama harus terpakai');
  assert((await anon.call('api_legacyCheck', ['lamo', 'salah'])).ok === false, 'password salah harus ditolak');
  assert((await anon.call('api_legacyCheck', ['lamo', 'laut1234'])).ok === true, 'password benar harus lolos');
  assert((await anon.call('api_legacyCheck', ['tidakada', 'x'])).ok === false, 'username asing');

  // akun baru; sempat memanggil whoAmI (me() membuat baris kosong tanpa username) sebelum klaim
  const u = await H.user('lamo');
  const who0 = await u.call('api_authWhoAmI', []);
  assert(who0.hasCharacter === false, 'belum punya kapten sebelum klaim');
  await H.expectError(() => u.call('api_legacyClaim', ['salah']), /Password lama salah/);
  const c = await u.call('api_legacyClaim', ['laut1234']);
  assert(c.ok && c.name === 'Kapten Lamo', 'klaim: ' + JSON.stringify(c));
  const again = await u.call('api_legacyClaim', ['laut1234']);
  assert(again.already === true, 'klaim ulang oleh pemilik yang sama = aman');

  const s = await u.call('api_getGameState', [null]);
  assert(s.player.characterName === 'Kapten Lamo' && s.player.gold === 4321, 'state setelah klaim');
  assert(s.city.CityId === 'ikn', 'lokasi ikut pindah');
  const left = await H.sql('select count(*)::int n from game.players where player_id = $1', [old]);
  assert(left[0].n === 0, 'placeholder harus hilang');
  const kids = await H.sql(`select (select count(*) from game.inventory where player_id=$1)::int inv,
    (select count(*) from game.player_books where player_id=$1)::int bk, (select count(*) from game.player_missions where player_id=$1)::int ms,
    (select count(*) from game.player_log where player_id=$1)::int lg, (select condition from game.ships where player_id=$1) cond`, [u.id]);
  assert(kids[0].inv === 1 && kids[0].bk === 1 && kids[0].ms === 1 && kids[0].lg >= 2 && Number(kids[0].cond) === 77, 'data anak ikut pindah ' + JSON.stringify(kids[0]));
  const bundle = await u.call('api_getCityBundle', []);
  assert(bundle.market && bundle.cargoState, 'bundle kota jalan');
  // setelah diklaim, legacyCheck tidak lagi membuka jalur lama
  assert((await anon.call('api_legacyCheck', ['lamo', 'laut1234'])).ok === false, 'sudah diklaim');

  // akun lain dengan username berbeda tidak bisa klaim
  const x = await H.user('penyusup');
  await H.expectError(() => x.call('api_legacyClaim', ['laut1234']), /Tidak ada kapten lama/);

  // kunci setelah 10x salah
  const old2 = crypto.randomUUID();
  await H.sql(`insert into game.players(player_id, username, character_name, archetype) values ($1, 'lamo2', 'Kapten Dua', 'pirate')`, [old2]);
  await H.sql(`insert into game.legacy_accounts(username, pass_hash, salt, player_id, legacy_id) values ('lamo2', 'x', 'y', $1, 'x')`, [old2]);
  for (let i = 0; i < 10; i++) await anon.call('api_legacyCheck', ['lamo2', 'no']);
  await H.expectError(() => anon.call('api_legacyCheck', ['lamo2', 'no']), /Terlalu banyak/);
  console.log('LEGACY TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
