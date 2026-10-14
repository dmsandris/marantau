// Buku Pancing Legenda: terbuka di Quest 6, 21 entri (10 bisa ditangkap), syarat kota/waktu/event/umpan,
// umpan dipakai saat tertangkap, ikan "dilepas", tidak mengganggu Buku Ikan (14) & Peti Karam Quest 4.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('legenda1'); await u.call('api_createCharacter', ['Murid Miss Nansy', 'explorer']);
  const pid = u.id;
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const w = async (fish, city) => Number((await one(`select game.fish_quest_weight($1, $2, $3) w`, [pid, fish, city])).w);
  const dayLen = Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) v`)).v);
  const setFrac = async f => {
    const r = await one(`select game.now_ms() n, game.cfg_num('WorldStartTimestamp', 0) s`);
    const len = dayLen * 60000, cur = ((Number(r.n) - Number(r.s)) % len) / len;
    let d = f - cur; if (d < 0) d += 1;
    await H.shiftTime(Math.round(d * len) + 1000);
  };
  const book = () => u.call('api_legendBook', []);

  // --- Terkunci sebelum Quest 6 ---------------------------------------------
  await H.expectError(() => book(), /belum ada di tanganmu/);
  let info = await u.call('api_mgFishInfo', []);
  assert(info.legendUnlocked === false && info.total === 14 && info.legendTotal === 21, 'info dermaga sebelum buku ' + JSON.stringify(info));
  await go('ikn'); await setFrac(0.4);
  await H.sql(`select game.adjust_inventory($1, 'besi', 3)`, [pid]);
  assert((await w('hiu_garuda', 'ikn')) === 0, 'tanpa buku: legenda tidak muncul');

  // --- Buku diterima (Quest 6 langkah 6) -------------------------------------
  await H.sql(`select game.item_adjust($1, 'qi_buku_pancing_maudy', 1)`, [pid]);
  let b = await book();
  assert(b.total === 21 && b.found === 0 && b.entries.length === 21, 'buku 21 entri');
  assert(b.entries.filter(e => e.available).length === 10, '10 legenda bisa ditangkap sekarang');
  assert(b.entries.every((e, i) => e.no === i + 1) && b.entries.every(e => e.name === null), 'urut 1..21, nama tersembunyi');
  const hiu = b.entries.find(e => e.id === 'hiu_garuda');
  assert(hiu.here && hiu.ready && hiu.bait === 'Besi' && hiu.time === 'Siang', 'Hiu Garuda siap di IKN siang dengan besi ' + JSON.stringify(hiu));
  assert(b.entries.find(e => e.no === 11).available === false && !b.entries.find(e => e.no === 11).ready, 'Tiram Otoland terkunci');

  // --- Syarat ----------------------------------------------------------------
  assert((await w('hiu_garuda', 'ikn')) === 4, 'IKN siang + besi: muncul');
  assert((await w('hiu_garuda', 'bjorneo')) === 0, 'kota salah: tidak muncul');
  await setFrac(0.8);
  assert((await w('hiu_garuda', 'ikn')) === 0, 'malam: Hiu Garuda tidak muncul');
  await setFrac(0.4);
  await H.sql(`select game.adjust_inventory($1, 'besi', -3)`, [pid]);
  assert((await w('hiu_garuda', 'ikn')) === 0, 'tanpa umpan besi: tidak muncul');
  await H.sql(`select game.adjust_inventory($1, 'besi', 2)`, [pid]);
  // event festival untuk Koi Lampion
  await setFrac(0.8);
  assert((await w('koi_lampion', 'gading_island')) === 0, 'Koi Lampion tanpa festival: tidak');
  await H.sql(`select game.adjust_inventory($1, 'silk', 1)`, [pid]);
  await H.sql(`insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day)
               values ('gading_island', 'festival', 'Festival Kota', 'Pesta', 0, 20, game.game_day() + 3)`);
  assert((await w('koi_lampion', 'gading_island')) === 4, 'Koi Lampion: malam + festival + sutra');
  // legenda yang belum tersedia & ikan biasa
  assert((await w('tiram_otoland', 'gading_island')) === 0 && (await w('ikan_terakhir', 'gading_island')) === 0, 'legenda terkunci tidak pernah muncul');
  assert((await w('teri', 'ikn')) === 1 && (await w('peti', 'bjorneo')) === 1, 'ikan biasa & Peti Karam tidak berubah');

  // --- Tangkapan -------------------------------------------------------------
  await setFrac(0.4); await go('ikn');
  await H.sql(`insert into game.mp_fish_book(player_id, fish_id, n, best_kg, best_gold) values ($1, 'hiu_garuda', 1, 72.5, 1300)`, [pid]);
  let r = (await one(`select game.fish_quest_catch($1, 'hiu_garuda') r`, [pid])).r;
  assert(r.legend && r.no === 1 && r.first && r.count === 1 && !r.release, 'Hiu Garuda tercatat ' + JSON.stringify(r));
  assert(Number((await one(`select game.item_qty($1, 'besi') q`, [pid])).q) === 1, 'umpan besi terpakai 1');
  assert((await H.sql(`select 1 from game.mp_fish_book where player_id = $1 and fish_id = 'hiu_garuda'`, [pid])).length === 0, 'tidak masuk Buku Ikan');
  assert((await u.call('api_mgFishInfo', [])).found === 0, 'Buku Ikan tetap 0/14');
  await H.sql(`insert into game.mp_fish_book(player_id, fish_id, n, best_kg, best_gold) values ($1, 'hiu_garuda', 1, 90, 1500)`, [pid]);
  r = (await one(`select game.fish_quest_catch($1, 'hiu_garuda') r`, [pid])).r;
  assert(!r.first && r.count === 1, 'tangkapan kedua: bukan entri baru');
  // ikan yang dilepas
  await H.sql(`select game.adjust_inventory($1, 'rum', 1)`, [pid]);
  r = (await one(`select game.fish_quest_catch($1, 'kakap_asap') r`, [pid])).r;
  assert(r.release && r.count === 2, 'Kakap Asap dilepas');
  b = await book();
  const h2 = b.entries.find(e => e.id === 'hiu_garuda');
  assert(b.found === 2 && h2.found && h2.name === 'Hiu Garuda Perunggu' && h2.n === 2 && Number(h2.bestKg) === 90, 'buku: nama & rekor terbuka ' + JSON.stringify(h2));
  info = await u.call('api_mgFishInfo', []);
  assert(info.legendUnlocked && info.legendFound === 2 && info.total === 14, 'info dermaga setelah buku');
  // Quest 2 tidak terpengaruh
  assert((await one(`select game.tg_book($1) b`, [pid])).b.total === 14, 'syarat Buku Ikan Quest 2 tetap 14');

  // --- Pemain Quest 6 lama (sudah menangkap ikan sebelum buku ada) ------------
  const v = await H.user('legenda2'); await v.call('api_createCharacter', ['Kapten Lama', 'merchant']);
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, data) values ($1, 'cocoepan', 8, '{"legend": true, "legendKg": 11.2}')`, [v.id]);
  const fs = require('fs'), path = require('path');
  await H.db.exec(fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0025_legend_book.sql'), 'utf8'));
  const lb = await v.call('api_legendBook', []);
  const kf = lb.entries.find(e => e.id === 'kerapu_fajar');
  assert(lb.found === 1 && kf.found && Number(kf.bestKg) === 11.2, 'Kerapu Fajar pemain lama tercatat ' + JSON.stringify(kf));
  console.log('LEGEND BOOK TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('ERROR:', e); process.exit(1); });
