// S5 Fase B (0113): dunia seberang, titian, pencegatan cerita, Bagian II langkah 20-28.
const fs = require('fs'), path = require('path');
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const src = fs.readFileSync(path.join(__dirname, '..', 'web', 'src', 'S5Ombak.html'), 'utf8');
const NILAI = new Function(src.slice(src.indexOf('/*NILAI-MULAI*/'), src.indexOf('/*NILAI-SELESAI*/')) + '; return S5OmbakNilai;')();
function jalurAman(p) {
  const c = p.course; let lane = 1, endPrev = 0; const taps = [];
  for (const w of c) {
    const tuju = [0, 1, 2].filter(s => !(w.m & (1 << s))).sort((a, b) => Math.abs(a - lane) - Math.abs(b - lane))[0];
    let t = endPrev + 10; while (lane !== tuju) { const d = tuju > lane ? 1 : -1; taps.push({ t_ms: t, dir: d }); lane += d; t += 120; }
    endPrev = w.t + w.len;
  }
  return taps;
}

(async () => {
  const H = await require('./harness').create();
  // deploy kedua: semua migrasi diulang (pembungkus rename harus aman diulang)
  for (const f of fs.readdirSync(path.join(__dirname, '..', 'supabase', 'migrations')).filter(f => f.endsWith('.sql')).sort()) {
    try { await H.db.exec(fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', f), 'utf8')); }
    catch (e) { console.error('GAGAL: migrasi diulang', f, e.message); process.exit(1); }
  }
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const clock = f => H.sql(`select game.cfg_set('WorldStartTimestamp', (game.now_ms() - ($1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint)::text)`, [f]);
  let HARI = 20; const SIANG = () => clock(HARI + 0.5), MALAM = () => clock(HARI + 0.8);
  await SIANG();
  await H.sql(`select game.cfg_set('GmUsernames', 's5c_gm'), game.cfg_set('S5MgJedaMs', '0'), game.cfg_set('S5MgPerJam', '999')`);
  const G = await H.user('s5c_gm'); await G.call('api_createCharacter', ['Juru Uji', 'merchant']);
  const B = await H.user('s5c_budi'); await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  const ke = (u, c) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, c]);
  const loc = async u => one(`select city_id, destination_city_id from game.player_location where player_id = $1`, [u.id]);
  const st = async u => (await u.call('api_s5', ['status'])).s5;
  const gold = async u => Number((await one(`select gold from game.players where player_id = $1`, [u.id])).gold);
  const oli = async u => Number((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'), 0) q`, [u.id])).q);
  const err = async (fn, re, m) => { let e = null; try { await fn(); } catch (x) { e = x.message; } ok(e && re.test(e), m + ': ' + e); };
  const mundurSesi = (sid, ms) => H.sql(`update game.mg_session set issued_ms = issued_ms - $2 where id = $1`, [sid, ms]);
  async function mainOmbak(u, ctx, preset, step, menang = true) {
    const s = await u.call('api_mg_start', ['wave', ctx, preset, step == null ? '' : String(step)]);
    await mundurSesi(s.session_id, s.params.dur + 3000);
    const f = await u.call('api_mg_finish', [s.session_id, { taps: menang ? jalurAman(s.params) : [] }]);
    return { s, f };
  }

  // ================= 1. Kota seberang rahasia =================
  const cj = (await one(`select game.cities_json() v`)).v;
  ok(!cj.some(c => /^s5_/.test(c.CityId)), 'cities_json tidak memuat kota seberang');
  ok((await H.sql(`select 1 from game.market where city_id like 's5\\_%'`)).length === 0, 'dunia seberang tanpa pasar');
  const opsB = await B.call('api_getSailOptions', []);
  ok(!opsB.some(o => /^s5_/.test(o.cityId)), 'pemain biasa tak pernah melihat tujuan seberang');
  await err(() => B.call('api_setSail', ['s5_p1']), /tidak dikenali/, 'pemain biasa tak bisa berlayar ke seberang');

  // ================= 2. Langkah 20: melangkah ke cahaya (malam, Q25) =================
  await G.call('api_s5', ['gm_uji', '1']);
  await G.call('api_s5', ['gm_langkah', '20']);
  await ke(G, 'bjorneo');
  let s = await st(G);
  ok(s.d && s.d.n === 20 && s.gerbangB === true && s.ada === 28, 'langkah 20 terlihat untuk GM uji: ' + JSON.stringify(s.d));
  await err(() => G.call('api_s5', ['maju', 20, 'ok']), /lampu dinyalakan/, 'langkah 20 hanya malam');
  await MALAM();
  let g0 = await gold(G);
  let r = await G.call('api_s5', ['maju', 20, 'ok']);
  ok(r.gold === 350000 && (await gold(G)) === g0 + 350000, 'Q25 350.000 di langkah 20');
  s = await st(G);
  ok(s.titian && s.titian.buka && s.titian.pertama && s.titian.preset === 'pelangi' && s.titian.oli === 0, 'titian terbuka, pertama gratis: ' + JSON.stringify(s.titian));

  // ================= 3. Titian pertama =================
  await err(() => G.call('api_mg_start', ['wave', 'crossing', 'pelangi', '']), /Mesin Jolt Warlord/, 'titian butuh Mesin Jolt Warlord');
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'speed') on conflict do nothing`, [G.id]);
  await err(() => G.call('api_mg_start', ['wave', 'crossing', 'pelangi_ulang', '']), /berubah/, 'preset titian ditentukan server');
  await ke(G, 'joungjava');
  await err(() => G.call('api_mg_start', ['wave', 'crossing', 'pelangi', '']), /kawah Bjorneo/, 'titian hanya dari Bjorneo');
  await ke(G, 'bjorneo');
  let o = await mainOmbak(G, 'crossing', 'pelangi', null, false);
  ok(o.f.status === 'lost' && (await loc(G)).city_id === 'bjorneo', 'kalah di titian: ulang di tempat');
  o = await mainOmbak(G, 'crossing', 'pelangi', null, true);
  ok(o.f.status === 'won' && o.f.efek.tiba === 's5_t0' && o.f.efek.pertama === true, 'titian pertama: tiba di kaki titian ' + JSON.stringify(o.f.efek));
  ok((await loc(G)).city_id === 's5_t0' && (await one(`select dunia from game.s5_state where player_id = $1`, [G.id])).dunia === 'seberang', 'dunia seberang');
  s = await st(G);
  ok(s.step === 21 && s.d.n === 22 && s.kota.some(c => c.CityId === 's5_t0') && s.buka.join() === 's5_p1', 'langkah 21 tuntas; hanya pulau gerbang terbuka: ' + JSON.stringify(s.buka));
  ok((await oli(G)) === 0, 'titian pertama tidak memotong Oli');
  const opsG = await G.call('api_getSailOptions', []);
  ok(opsG.length === 1 && opsG[0].cityId === 's5_p1', 'di seberang hanya pulau seberang yang terbuka: ' + JSON.stringify(opsG.map(x => x.cityId)));

  // ================= 4. Langkah 22: dicegat sayap penjaga =================
  await G.call('api_setSail', ['s5_p1']);
  s = await st(G);
  ok(s.cegat && s.cegat.preset === 'valkyrie' && s.cegat.n === 22, 'pencegatan cerita terpasang: ' + JSON.stringify(s.cegat));
  await err(() => G.call('api_mg_start', ['wave', 'encounter', 'valkyrie', '22']), /cakrawala/, 'Lari belum bisa sebelum waktunya');
  await H.sql(`update game.s5_state set data = jsonb_set(data, '{cegat,at}', to_jsonb(game.now_ms() - 1)) where player_id = $1`, [G.id]);
  await H.sql(`update game.player_location set arrive_at = now() - interval '1 second' where player_id = $1`, [G.id]);
  const hold = (await one(`select game.resolve_arrival_if_due($1) v`, [G.id])).v;
  ok(hold && hold.hold === true && (await loc(G)).destination_city_id === 's5_p1', 'kapal ditahan sampai lolos: ' + JSON.stringify(hold));
  await err(() => G.call('api_mg_start', ['wave', 'encounter', 'ular_muda', '22']), /tenang/, 'preset pencegatan harus cocok');
  o = await mainOmbak(G, 'encounter', 'valkyrie', 22, false);
  ok(o.f.status === 'lost' && (await st(G)).step === 21, 'kalah Lari: langkah tidak maju');
  o = await mainOmbak(G, 'encounter', 'valkyrie', 22, true);
  ok(o.f.status === 'won' && o.f.efek.lolos === true, 'lolos');
  await H.sql(`select game.resolve_arrival_if_due($1)`, [G.id]);
  ok((await loc(G)).city_id === 's5_p1', 'tiba di pulau gerbang');
  s = await st(G); ok(s.step === 22 && !s.cegat, 'langkah 22 tuntas');

  // ================= 5. Langkah 23-25 =================
  await err(() => G.call('api_s5', ['maju', 23, 'gagal']), /Belum berhasil/, 'mini game lama harus ok');
  await G.call('api_s5', ['maju', 23, 'ok']);
  await G.call('api_s5', ['maju', 24, 'ok']);
  s = await st(G); ok(s.data.item_segel_penjaga === true && s.buka.join() === 's5_p1,s5_p2', 'segel penjaga membuka pulau raksasa');
  await G.call('api_s5', ['maju', 25, 'ok']);
  await err(() => G.call('api_s5', ['pulang']), /hari berikutnya/, 'tidak bisa pulang di hari yang sama dengan pergi (K3)');

  // ================= 6. Langkah 26: ular muda, 27 teka-teki, 28 papan + Q26 =================
  await G.call('api_setSail', ['s5_p2']);
  s = await st(G); ok(s.cegat && s.cegat.preset === 'ular_muda' && s.cegat.n === 26, 'pencegatan ular muda');
  await H.sql(`update game.s5_state set data = jsonb_set(data, '{cegat,at}', to_jsonb(game.now_ms() - 1)) where player_id = $1`, [G.id]);
  // mundur: kembali ke pelabuhan asal, pelayaran berikutnya dicegat lagi
  await G.call('api_s5', ['mundur']);
  ok((await loc(G)).city_id === 's5_p1' && !(await loc(G)).destination_city_id, 'mundur ke pelabuhan asal');
  await G.call('api_setSail', ['s5_p2']);
  await H.sql(`update game.s5_state set data = jsonb_set(data, '{cegat,at}', to_jsonb(game.now_ms() - 1)) where player_id = $1`, [G.id]);
  await H.sql(`update game.player_location set arrive_at = now() - interval '1 second' where player_id = $1`, [G.id]);
  o = await mainOmbak(G, 'encounter', 'ular_muda', 26, true);
  ok(o.f.status === 'won', 'lolos dari ular muda');
  await H.sql(`select game.resolve_arrival_if_due($1)`, [G.id]);
  ok((await loc(G)).city_id === 's5_p2', 'tiba di pulau raksasa');
  r = await G.call('api_s5', ['maju', 27, 'cinta']);
  ok(r.salah === true && r.s5.step === 26, 'jawaban salah');
  await err(() => G.call('api_s5', ['maju', 27, 'janji']), /Tunggu sebentar/, 'jeda 20 detik setelah salah');
  await H.sql(`update game.player_quests set data = data - 'tekaSampai' where player_id = $1 and quest_id = 's5'`, [G.id]);
  await G.call('api_s5', ['maju', 27, ' Janji! ']);
  g0 = await gold(G);
  r = await G.call('api_s5', ['maju', 28, 'ok']);
  ok(r.gold === 350000 && (await gold(G)) === g0 + 350000 && r.s5.step === 28, 'Q26 350.000 di langkah 28');
  await err(() => G.call('api_s5', ['maju', 29, 'ok']), /Bersambung/, 'setelah langkah 28: bersambung');

  // ================= 7. Dwarfsmith =================
  await err(() => H.sql(`select game.voy_repair_quote($1, 's5_p2')`, [G.id]), /Dwarfsmith/, 'pulau raksasa tanpa Dwarfsmith');
  const qMare = (await one(`select game.voy_repair_quote($1, 'bjorneo') v`, [G.id])).v;
  ok(qMare != null, 'reparasi biasa tetap jalan');
  ok(Number((await one(`select repair_cost_rate r from game.cities where city_id = 's5_p1'`)).r) === 3, 'tarif Dwarfsmith 3x');

  // ================= 8. Pulang (hari berikutnya), titian kedua dengan tiket Oli =================
  HARI += 1; await SIANG();
  await err(() => G.call('api_s5', ['pulang']), /pulau gerbang/, 'pulang hanya dari pulau gerbang');
  await ke(G, 's5_p1');
  r = await G.call('api_s5', ['pulang']);
  ok(r.pulang && (await loc(G)).city_id === 'bjorneo' && r.s5.dunia === 'mare', 'pulang: tiba di Bjorneo');
  ok((await G.call('api_getSailOptions', [])).every(x => !/^s5_/.test(x.cityId)), 'di Mare tidak ada tujuan seberang');
  s = await st(G);
  ok(s.titian.preset === 'pelangi_ulang' && s.titian.oli === 10 && s.titian.hari.ok === false, 'titian kedua: berbayar, tunggu hari berikutnya: ' + JSON.stringify(s.titian));
  HARI += 1; await SIANG();
  await err(() => G.call('api_mg_start', ['wave', 'crossing', 'pelangi_ulang', '']), /haus/, 'Oli kurang ditolak');
  await H.sql(`insert into game.inventory(player_id, item_id, qty) values ($1, 'oli_hitam', 12) on conflict (player_id, item_id) do update set qty = 12`, [G.id]);
  o = await mainOmbak(G, 'crossing', 'pelangi_ulang', null, false);
  ok(o.s.info.oli === 10 && (await oli(G)) === 2, 'tiket 10 Oli dipotong saat mulai (K6)');
  o = await mainOmbak(G, 'crossing', 'pelangi_ulang', null, true);
  ok(o.s.info.oli === 0 && (await oli(G)) === 2, 'mengulang di hari yang sama tidak memotong lagi');
  ok(o.f.status === 'won' && o.f.efek.tiba === 's5_p1' && (await loc(G)).city_id === 's5_p1', 'titian berikutnya: langsung di pulau gerbang');

  // ================= 9. Pemain tanpa S5 tidak terpengaruh =================
  await err(() => B.call('api_s5', ['pulang']), /tidak dikenal/, 'api_s5 tertutup bagi pemain lain');
  await err(() => B.call('api_mg_start', ['wave', 'crossing', 'pelangi', '']), /tidak dikenal/, 'titian tertutup bagi pemain lain');
  ok(!(await B.call('api_getGameState', [])).s5, 'state pemain lain tanpa key s5');

  console.log('OK 0113 dunia seberang: kota rahasia, titian (pertama & berbayar), pencegatan cerita, langkah 20-28, Dwarfsmith, pulang');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
