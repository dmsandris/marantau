// Tide v44 · Jejak Perantau: onboarding pemain baru (Hari Pertama + Catatan Perantau + Kabar Pelabuhan).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const fs = require('fs'), path = require('path');
(async () => {
  const H = await require('./harness').create();
  const gold = async (id) => Number((await H.sql('select gold from game.players where player_id = $1', [id]))[0].gold);

  // ---- pemain lama: karakter dibuat sebelum PerantauStartAt -> tidak mendapat apa pun ----
  const lama = await H.user('kaptenlama'); await lama.call('api_createCharacter', ['Kapten Lama', 'merchant']);
  await H.sql(`update game.player_log set ts = now() - interval '30 days' where player_id = $1`, [lama.id]);
  await H.sql(`update game.players set created_at = now() - interval '30 days' where player_id = $1`, [lama.id]);
  let s = await lama.call('api_getGameState', [null]);
  assert(s.perantau === null, 'pemain lama: perantau null');
  await H.expectError(() => lama.call('api_perantau', ['claim', 's1']), /kapten baru/);
  assert((await lama.call('api_perantauSuggest', [])).suggest === null, 'pemain lama: tanpa saran');
  // status tersimpan: pemain lama tetap tidak layak walau dipanggil ulang
  assert((await lama.call('api_getGameState', [null])).perantau === null, 'pemain lama tetap null');

  // ---- akun pindahan (legacy) -> tidak layak ----
  const pindah = await H.user('kaptenpindah'); await pindah.call('api_createCharacter', ['Kapten Pindah', 'merchant']);
  await H.sql(`insert into game.legacy_accounts(username, pass_hash, salt, player_id, legacy_id, claimed_by) values ('kaptenpindah', 'x', 'y', $1, 'acc:x', $1)`, [pindah.id]);
  assert((await pindah.call('api_getGameState', [null])).perantau === null, 'akun pindahan: null');

  // ---- pemain baru ----
  const u = await H.user('perantau'); await u.call('api_createCharacter', ['Kapten Perantau', 'navigator']);
  s = await u.call('api_getGameState', [null]);
  const p = s.perantau;
  assert(p && !p.intro && p.earned === 0 && p.total === 70000, 'pemain baru: state awal');
  const sum = p.catalog.reduce((a, e) => a + e.reward, 0);
  assert(sum === 70000, 'total katalog 70.000 (' + sum + ')');
  assert(p.catalog.filter(e => e.kind === 'step').reduce((a, e) => a + e.reward, 0) === 10000, 'Hari Pertama 10.000');

  assert((await u.call('api_perantau', ['intro'])).perantau.intro === true, 'intro tercatat');

  // langkah tanpa syarat
  const g0 = await gold(u.id);
  let r = await u.call('api_perantau', ['claim', 's1']);
  assert(r.reward === 500 && (await gold(u.id)) === g0 + 500 && r.perantau.claimed.s1, 'klaim s1');
  await H.expectError(() => u.call('api_perantau', ['claim', 's1']), /sudah diterima/);
  await u.call('api_perantau', ['claim', 's2']);
  await H.expectError(() => u.call('api_perantau', ['claim', 'xx']), /tidak dikenal/);

  // s3 butuh beli sungguhan
  await H.expectError(() => u.call('api_perantau', ['claim', 's3']), /belum selesai/);
  const sg = (await u.call('api_perantauSuggest', [])).suggest;
  assert(sg && sg.item && sg.dest && sg.dest !== 'sunda_empire' && sg.sellPrice > sg.buyPrice && sg.qty >= 1, 'saran rute untung: ' + JSON.stringify(sg));
  const dest = (await H.sql('select type, hidden from game.cities where city_id = $1', [sg.dest]))[0];
  assert(dest.type !== 'Outlaw' && !dest.hidden, 'tujuan saran bukan sarang penyamun / pulau tersembunyi');
  await u.call('api_buy', ['sunda_empire', sg.item, 1]);
  await u.call('api_perantau', ['claim', 's3']);
  await u.call('api_perantau', ['claim', 's4']);
  await H.expectError(() => u.call('api_perantau', ['claim', 's5']), /belum selesai/);
  await u.call('api_setSail', [sg.dest]);
  await u.call('api_perantau', ['claim', 's5']);
  await H.expectError(() => u.call('api_perantau', ['claim', 's6']), /belum selesai/);
  await H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, sg.dest]);
  await u.call('api_sell', [sg.dest, sg.item, 1]);
  await u.call('api_perantau', ['claim', 's6']);
  await H.expectError(() => u.call('api_perantau', ['claim', 's7']), /belum selesai/);
  await H.sql(`insert into game.player_missions(player_id, commodity_id, status) values ($1, 'garam', 'active')`, [u.id]).catch(async () => {
    await H.sql(`insert into game.player_missions(player_id, commodity_id, status) values ($1, (select id from game.commodities limit 1), 'active')`, [u.id]);
  });
  r = await u.call('api_perantau', ['claim', 's7']);
  assert(r.perantau.earned === 10000, 'Hari Pertama lunas 10.000 (' + r.perantau.earned + ')');

  // tugas Catatan Perantau: dari Tanda Jasa (meta) atau data server
  await H.expectError(() => u.call('api_perantau', ['claim', 'lapau_5']), /belum selesai/);
  await H.sql(`update game.players set meta = $2 where player_id = $1`, [u.id, JSON.stringify({ u: { lapau_5: 1, talk_10: 1, chat_1: 1 }, c: {}, v: [] })]);
  await u.call('api_perantau', ['claim', 'lapau_5']);
  await H.expectError(() => u.call('api_perantau', ['claim', 'book_1']), /belum selesai/);
  await H.sql(`insert into game.player_books(player_id, book_id, date_acquired) values ($1, (select book_id from game.book_catalog limit 1), 1)`, [u.id]);
  await u.call('api_perantau', ['claim', 'book_1']);
  await H.sql(`update game.players set gold = 20000 where player_id = $1`, [u.id]);
  r = await u.call('api_perantau', ['claim', 'gold_10k']);
  assert(r.reward === 9000 && (await gold(u.id)) === 29000, 'gold_10k: +9.000');

  // semua sisa tugas -> total tepat 70.000 dan tidak bisa lebih
  const all = {}; p.catalog.forEach(e => { all[e.id] = 1; });
  await H.sql(`update game.players set meta = $2 where player_id = $1`, [u.id, JSON.stringify({ u: all, c: {}, v: [] })]);
  await H.sql(`insert into game.combat_log(player_id, enemy_level) values ($1, 1)`, [u.id]).catch(() => { });
  for (const e of p.catalog) {
    const st = (await u.call('api_perantau', ['status'])).perantau;
    if (st.claimed[e.id]) continue;
    await u.call('api_perantau', ['claim', e.id]);
  }
  let st = (await u.call('api_perantau', ['status'])).perantau;
  assert(st.earned === 70000, 'total diterima 70.000 (' + st.earned + ')');
  assert(Object.keys(st.claimed).length === p.catalog.length, 'semua tugas tercatat');
  // pagar pengaman: total tidak bisa lewat batas walau katalog dimanipulasi
  await H.sql(`update game.player_quests set data = jsonb_set(data, '{c}', (data->'c') - 's1') where player_id = $1 and quest_id = 'perantau'`, [u.id]);
  r = await u.call('api_perantau', ['claim', 's1']);
  assert(r.reward === 0 && r.perantau.earned === 70000, 'batas 70.000 dijaga');

  // ---- Buat Kapten: cek nama di langkah 1 ----
  const baru = await H.user('kaptenbaru');
  assert((await baru.call('api_captainNameFree', ['kapten perantau'])).free === false, 'nama terpakai (beda huruf besar/kecil)');
  assert((await baru.call('api_captainNameFree', ['Kapten Belum Ada'])).free === true, 'nama bebas');
  assert((await baru.call('api_captainNameFree', ['  '])).free === false, 'nama kosong');

  // ---- Kabar Pelabuhan (20 Tanda Jasa) ----
  const v = await H.user('perantau2'); await v.call('api_createCharacter', ['Kapten Kedua', 'merchant']);
  await v.call('api_getGameState', [null]);
  await H.expectError(() => v.call('api_perantau', ['news']), /Belum ada kabar/);
  const m20 = { u: {} }; for (let i = 0; i < 20; i++) m20.u['a' + i] = 1;
  await H.sql(`update game.players set meta = $2 where player_id = $1`, [v.id, JSON.stringify(m20)]);
  r = await v.call('api_perantau', ['news']);
  assert(r.perantau.news === true && r.perantau.newsDay >= 0 && r.perantau.badges === 20, 'kabar tercatat ' + JSON.stringify(r.perantau).slice(0, 200));
  const day = r.perantau.newsDay;
  r = await v.call('api_perantau', ['news']);
  assert(r.perantau.newsDay === day, 'kabar hanya sekali');
  assert((await v.call('api_perantau', ['remind'])).perantau.remind === true, 'pengingat tercatat');
  assert((await v.call('api_perantau', ['skip'])).perantau.skipped === true, 'lewati tutorial');

  // ---- teks pemain baru tidak boleh menyebut tokoh/kota tujuan secara jelas ----
  const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'src', 'Perantau.html'), 'utf8');
  assert(!/\bgala\b|skitraw/i.test(src), 'Perantau.html tidak menyebut "Gala"/"Skitraw"');

  console.log('Jejak Perantau OK');
})().catch(e => { console.error(e); process.exit(1); });
