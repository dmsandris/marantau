// Tide v61 · Buku Pancing Legenda: 8 halaman terakhir (#13, #15-#21), hadiah 14/20/21,
// rahasia Saga 3 untuk #20, dua joran #18, Hiu Kumis Hitam tanpa pengumuman.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const mk = async (name, arch) => { const u = await H.user(name); await u.call('api_createCharacter', ['Kapten ' + name, arch || 'explorer']); return u; };
  const u = await mk('lg_ani'), pid = u.id;
  const go = (p, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [p, c]);
  const w = async (p, fish, city) => Number((await one(`select game.fish_quest_weight($1, $2, $3) w`, [p, fish, city])).w);
  const dayLen = Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) v`)).v);
  const setFrac = async f => {
    const r = await one(`select game.now_ms() n, game.cfg_num('WorldStartTimestamp', 0) s`);
    const len = dayLen * 60000, cur = ((Number(r.n) - Number(r.s)) % len) / len;
    let d = f - cur; if (d < 0) d += 1;
    await H.shiftTime(Math.round(d * len) + 1000);
  };
  const SIANG = 0.4, MALAM = 0.8, FAJAR = 0.97;
  const give = (p, it, n) => H.sql(`select game.item_adjust($1, $2, $3)`, [p, it, n || 1]);
  const goods = (p, c, n) => H.sql(`select game.adjust_inventory($1, $2, $3)`, [p, c, n || 1]);
  const catchIt = async (p, fish) => (await one(`select game.fish_quest_catch($1, $2) r`, [p, fish])).r;
  await give(pid, 'qi_buku_pancing_maudy');

  // --- Katalog -----------------------------------------------------------------
  let b = await u.call('api_legendBook', []);
  assert(b.total === 21 && b.entries.every(e => e.available), 'semua 21 tersedia');
  const p20 = b.entries.find(e => e.no === 20);
  assert(p20.secret && p20.place === '???' && p20.time === '???' && p20.lockLabel === 'Halaman ini belum ditulis', 'rahasia Saga 3: #20 tanpa tempat ' + JSON.stringify(p20));
  assert(!JSON.stringify(b).includes('Sudyrman') && !JSON.stringify(b).includes('lampau'), 'tidak ada kata Sudyrman/lampau di buku pemain biasa');
  assert(b.entries.find(e => e.no === 13).req === 'Kompas Dua Jarum di palka', 'label syarat #13');

  // --- #13 Ikan Kabut ----------------------------------------------------------
  await go(pid, 'kabut_abu');
  assert(await w(pid, 'ikan_kabut', 'kabut_abu') === 0, '#13 tanpa kompas: tidak');
  await give(pid, 'qi_kompas_dua_jarum');
  assert(await w(pid, 'ikan_kabut', 'kabut_abu') === 4, '#13 dengan kompas: naik');
  let r = await catchIt(pid, 'ikan_kabut');
  assert(r.legend && r.no === 13 && /jarumnya sejajar/.test(r.message), '#13 tercatat ' + JSON.stringify(r));

  // --- #15 Ikan Rantai, #16 Lumba Gema, #17 Gurita Arsip -------------------------
  await setFrac(MALAM); await goods(pid, 'besi', 1);
  assert(await w(pid, 'ikan_rantai', 'rantai_lama') === 4, '#15 malam + besi');
  r = await catchIt(pid, 'ikan_rantai');
  assert(r.release && /angin/.test(r.message), '#15 dilepas (Rantai Lama belum jadi pelabuhan)');
  await setFrac(SIANG);
  assert(await w(pid, 'lumba_gema', 'sowtour') === 0, '#16 sebelum menara menyala: tidak');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'limatangan', 10)`, [pid]);
  assert(await w(pid, 'lumba_gema', 'sowtour') === 4, '#16 setelah menara menyala');
  assert(await w(pid, 'lumba_gema', 'gading_island') === 0, '#16 kota salah');
  await setFrac(MALAM); await goods(pid, 'silk', 1);
  assert(await w(pid, 'gurita_arsip', 'sowtour') === 4, '#17 malam + sutra');

  // --- #18 Kakap Dua Tangan: dua joran -----------------------------------------
  const v = await mk('lg_budi'); await give(v.id, 'qi_buku_pancing_maudy');
  await setFrac(FAJAR); await go(pid, 'teluk_dua_tangan'); await go(v.id, 'teluk_dua_tangan');
  assert(await w(pid, 'kakap_dua_tangan', 'teluk_dua_tangan') === 0, '#18 sendirian: tidak');
  await H.sql(`insert into game.lg_cast(player_id, city, at_ms) values ($1, 'teluk_dua_tangan', game.now_ms() - 7200000)`, [v.id]);
  assert(await w(pid, 'kakap_dua_tangan', 'teluk_dua_tangan') === 4, '#18 bayangan kapten lain (2 jam lalu)');
  await H.sql(`update game.lg_cast set at_ms = game.now_ms() - 30 * 3600000 where player_id = $1`, [v.id]);
  assert(await w(pid, 'kakap_dua_tangan', 'teluk_dua_tangan') === 0, '#18 bayangan > 24 jam: tidak');
  // lemparan sungguhan tercatat lewat api_mgFishCast
  const c1 = await v.call('api_mgFishCast', [0.5, 'cacing', false]);
  assert(c1.castId, 'lemparan Budi');
  assert(Number((await one(`select game.now_ms() - at_ms d from game.lg_cast where player_id = $1`, [v.id])).d) < 60000, 'lemparan di teluk dicatat');
  assert(await w(pid, 'kakap_dua_tangan', 'teluk_dua_tangan') === 8, '#18 dua joran sungguhan: bobot ganda');
  r = await catchIt(pid, 'kakap_dua_tangan');
  assert(r.mate === 'Kapten lg_budi' && /Dua joran/.test(r.message), '#18 pasangan ' + JSON.stringify(r));
  assert((await one(`select count(*)::int n from game.legend_catch where player_id = $1 and fish_id = 'kakap_dua_tangan'`, [v.id])).n === 1, 'pasangan ikut tercatat');
  assert((await one(`select count(*)::int n from game.mp_chat where msg ->> 'tx' like '%berjabat di Teluk Dua Tangan%'`)).n === 1, 'diumumkan Syahbandar');

  // --- #19 Hiu Kumis Hitam -----------------------------------------------------
  await go(pid, 'ikn'); await goods(pid, 'mesiu', 1);
  await H.sql(`insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day)
               values ('ikn', 'storm_surge', 'Gelombang Badai', 'Badai', 15, 0, game.game_day() + 3)`);
  assert(await w(pid, 'hiu_kumis_hitam', 'ikn') === 0, '#19 sebelum Saga 4 tamat: tidak');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'mahkota', 40)`, [pid]);
  assert(await w(pid, 'hiu_kumis_hitam', 'ikn') === 0, '#19 kapal belum Tier V: tidak');
  await H.sql(`create or replace function game.ship_tier_num(p_pid uuid) returns int language sql stable as $$ select 5 $$`);
  assert(await w(pid, 'hiu_kumis_hitam', 'ikn') === 4, '#19 badai + mesiu + Tier V + Saga 4');
  assert(Number((await one(`select rarity from game.mp_fish_types where id = 'hiu_kumis_hitam'`)).rarity) < 6, '#19 tidak masuk pengumuman Syahbandar (rarity < 6)');
  r = await catchIt(pid, 'hiu_kumis_hitam');
  assert(r.secret && /tidak dibicarakan/.test(r.message), '#19 rahasia');

  // --- #20 Matahari Penari: tidak pernah dari lemparan biasa; backfill pemain lama ---
  assert(await w(pid, 'matahari_penari', 'sudyrman_pelabuhan') === 0, '#20 bukan dari lemparan biasa');
  const lama = await mk('lg_cici'); await give(lama.id, 'qi_buku_pancing_maudy');
  await H.sql(`insert into game.pasir_state(player_id, riak) values ($1, '{"nansy_buku": true}')`, [lama.id]);
  // backfill yang dijalankan migrasi saat deploy (bagian terakhir 0083)
  const fs = require('fs'), path = require('path');
  const sqlAll = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0083-legenda-penutup.sql'), 'utf8');
  const bf = sqlAll.match(/insert into game\.legend_catch\(player_id, fish_id, n, best_kg\)\s+select s\.player_id[\s\S]*?do nothing;/);
  assert(bf, 'blok backfill ada');
  await H.db.exec(bf[0]);
  const bl = await lama.call('api_legendBook', []);
  const m20 = bl.entries.find(e => e.no === 20);
  assert(bl.found === 1 && m20.found && m20.name === 'Matahari Penari', 'pemain yang ikut Nansy tercatat ' + JSON.stringify(m20));
  // pemain yang tahu Sudyrman tapi tidak ikut Nansy
  const tolak = await mk('lg_dedi'); await give(tolak.id, 'qi_buku_pancing_maudy');
  await H.sql(`insert into game.pasir_state(player_id) values ($1)`, [tolak.id]);
  await H.sql(`select game.ps_set($1, 'ps12', 7, '{}'::jsonb)`, [tolak.id]);
  const t20 = (await tolak.call('api_legendBook', [])).entries.find(e => e.no === 20);
  assert(!t20.secret && t20.place === 'Pelabuhan Sudyrman' && t20.lockLabel === 'Fajar itu sudah lewat', 'yang menolak: halaman terlewat ' + JSON.stringify(t20));

  // --- Hadiah 14 & 20, #21, penutup --------------------------------------------
  const rest = ['hiu_garuda', 'belut_gunung', 'pari_batik', 'kakap_rendang', 'tongkol_kopi', 'kakap_asap', 'penyu_mutiara',
    'ubur_kaca', 'kerapu_fajar', 'koi_lampion', 'tiram_otoland', 'marlin_garam', 'paus_bisu', 'gurita_arsip', 'lumba_gema'];
  for (const f of rest.slice(0, 7)) await catchIt(pid, f);
  // 4 sebelumnya (#13, #15, #18, #19) + 7 = 11
  assert((await one(`select game.lg_n($1) n`, [pid])).n === 11, '11 halaman');
  const luck0 = Number((await one(`select luck from game.character_stats where player_id = $1`, [pid])).luck);
  await catchIt(pid, rest[7]); r = await catchIt(pid, rest[8]);
  assert(!r.rewards, '13 halaman: belum ada hadiah');
  r = await catchIt(pid, rest[9]);
  assert(r.rewards && r.rewards[0].id === 'bk_catatan_fajar', 'hadiah 14: Catatan Fajar ' + JSON.stringify(r.rewards));
  assert(Number((await one(`select luck from game.character_stats where player_id = $1`, [pid])).luck) === luck0 + 5, '+5 Luck');
  await setFrac(SIANG); await go(pid, 'ikn'); await goods(pid, 'besi', 1);
  assert(await w(pid, 'hiu_garuda', 'ikn') === 5, 'Catatan Fajar: bobot legenda ×1,25');
  for (const f of rest.slice(10, 14)) await catchIt(pid, f);
  assert((await one(`select game.lg_n($1) n`, [pid])).n === 18, '18 halaman');
  // #21: butuh 19 halaman lain (tanpa #20) + Joran Kecil Nansy
  await setFrac(FAJAR); await go(pid, 'gading_island'); await give(pid, 'qi_joran_nansy');
  assert(await w(pid, 'ikan_terakhir', 'gading_island') === 0, '#21: baru 18 halaman lain');
  await catchIt(pid, rest[14]);
  await give(pid, 'qi_joran_nansy', -1);
  assert(await w(pid, 'ikan_terakhir', 'gading_island') === 0, '#21: tanpa Joran Kecil');
  await give(pid, 'qi_joran_nansy');
  assert(await w(pid, 'ikan_terakhir', 'gading_island') === 100000, '#21 pasti naik');
  r = await catchIt(pid, 'ikan_terakhir');
  assert(/Yang besar itu ceritanya/.test(r.message) && r.complete === false, '#21 tercatat, buku belum 21 tanpa #20');
  assert(r.rewards && r.rewards[0].id === 'art_topi_pantai', 'hadiah 20: Topi Pantai ' + JSON.stringify(r.rewards));
  assert((await u.call('api_mgFishInfo', [])).topiPantai === true, 'Topi Pantai terpasang');
  await H.expectError(() => u.call('api_legendBook', ['stumpy']), /halaman yang kosong/);
  // #20 lewat Nansy (simulasi riak) -> 21/21
  await H.sql(`select game.lg_record($1, 'matahari_penari', 1)`, [pid]);
  await go(pid, 'ikn');
  await H.expectError(() => u.call('api_legendBook', ['stumpy']), /Kedai Stumpy di Gading/);
  await go(pid, 'gading_island');
  const g0 = Number((await one(`select gold from game.players where player_id = $1`, [pid])).gold);
  const t = await u.call('api_legendBook', ['stumpy']);
  assert(t.ok && t.gold === 300000 && Number((await one(`select gold from game.players where player_id = $1`, [pid])).gold) === g0 + 300000, 'penutup: 300.000 gold');
  await H.expectError(() => u.call('api_legendBook', ['stumpy']), /sudah selesai/);
  b = await u.call('api_legendBook', []);
  assert(b.found === 21 && b.complete && b.closed, 'buku selesai');

  // --- Hadiah ditahan selama Saga 3 berjalan ------------------------------------
  await H.sql(`update game.config set value = '1' where key = 'PasirOpen'`);
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);
  const s3 = await mk('lg_euis'); await give(s3.id, 'qi_buku_pancing_maudy');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'duatangan', 5)`, [s3.id]);
  await H.sql(`insert into game.pasir_state(player_id) values ($1)`, [s3.id]);
  for (const f of rest.slice(0, 14)) await H.sql(`select game.lg_record($1, $2, 1)`, [s3.id, f]);
  assert((await s3.call('api_legendBook', [])).rewards.length === 0, 'Saga 3 berjalan: hadiah ditahan');
  await H.sql(`select game.ps_set($1, 'ps14', 6, '{}'::jsonb, true)`, [s3.id]);
  assert((await s3.call('api_legendBook', [])).rewards[0].id === 'bk_catatan_fajar', 'setelah tamat: hadiah diberikan');

  console.log('LEGENDA PENUTUP TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('ERROR:', e); process.exit(1); });
