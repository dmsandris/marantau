// 0090 Sorotan Pulau: jadwal adil & rahasia, batch premium x1,5-2, harga +5-25%, slot terpisah dari event kota,
// event Skitraw macet diakhiri, tanpa jejak di API pemain.
const fs = require('fs');
const path = require('path');
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  await H.sql(`update game.config set value = '1' where key = 'SorotanAktif'`);   // harness mematikannya bawaan
  const kota = async (d) => (await one('select game.sorotan_kota($1) k', [d])).k;
  const day = (await one('select game.game_day() d')).d;

  const elig = (await H.sql(`select c.city_id from game.cities c
      where exists (select 1 from game.market m where m.city_id = c.city_id) and not game.spot_city(c.city_id) order by 1`)).map(r => r.city_id);
  const n = elig.length;
  assert(n >= 10, 'pulau layak cukup banyak: ' + n);
  assert(elig.includes('gading_island') && elig.includes('zentul') && elig.includes('skitraw'), 'pulau tersembunyi dan terbuka ikut');

  // ---- jadwal: tiap putaran memuat tiap pulau tepat sekali, tak pernah berturut-turut, deterministik ----
  const r0 = Math.floor(day / n);
  const seq = [];
  for (let d = r0 * n; d < (r0 + 4) * n; d++) seq.push(await kota(d));
  for (let r = 0; r < 4; r++) {
    const win = seq.slice(r * n, (r + 1) * n);
    assert(new Set(win).size === n && win.every(c => elig.includes(c)), 'putaran ' + r + ' memuat semua pulau layak sekali');
  }
  for (let i = 1; i < seq.length; i++) assert(seq[i] !== seq[i - 1], 'tidak berturut-turut di indeks ' + i);
  assert(JSON.stringify(seq) === JSON.stringify(await Promise.all(Array.from({ length: seq.length }, (_, i) => kota(r0 * n + i)))), 'deterministik');

  // garam berbeda -> urutan berbeda (jadwal tak bisa dihitung dari repo)
  const garamAsli = (await one(`select value from game.config where key = 'SorotanGaram'`)).value;
  assert(garamAsli && garamAsli.length >= 16, 'garam terpasang acak');
  await H.sql(`update game.config set value = 'garam-lain' where key = 'SorotanGaram'`);
  const seq2 = [];
  for (let d = r0 * n; d < (r0 + 1) * n; d++) seq2.push(await kota(d));
  assert(JSON.stringify(seq2) !== JSON.stringify(seq.slice(0, n)), 'garam lain -> jadwal lain');
  await H.sql(`update game.config set value = $1 where key = 'SorotanGaram'`, [garamAsli]);

  // ---- parameter harian ----
  const bs = new Set(), pcts = [];
  for (let d = r0 * n; d < (r0 + 4) * n; d++) {
    const b = Number((await one('select game.sorotan_batch($1) b', [d])).b);
    assert(b >= 1.5 && b <= 2.0 && Math.abs(b * 10 - Math.round(b * 10)) < 1e-9, 'batch 1,5-2,0 kelipatan 0,1: ' + b);
    bs.add(b);
    const mp = (await one('select game.sorotan_harga_map($1) m', [d])).m;
    const ks = Object.keys(mp);
    assert(ks.length >= 2 && ks.length <= 4, 'jumlah komoditas 2-4: ' + ks.length);
    const ada = new Set((await H.sql(`select commodity_id from game.market where city_id = $1`, [await kota(d)])).map(r => r.commodity_id));
    ks.forEach(k => { assert(ada.has(k), 'komoditas ada di pasar kota: ' + k); assert(mp[k] >= 5 && mp[k] <= 25, 'persen 5-25: ' + mp[k]); pcts.push(mp[k]); });
  }
  assert(bs.size >= 3, 'pengali batch bervariasi: ' + [...bs]);
  assert(Math.min(...pcts) <= 10 && Math.max(...pcts) >= 20, 'persen bervariasi');

  // ---- slot terpisah: tidak menyentuh city_events; event acak tetap jalan dan harga berlipat ----
  const u = await H.user('pelautuji');
  await u.call('api_createCharacter', ['Kapten Uji', 'merchant']);
  const hariIni = (await one('select game.game_day() d')).d;
  const X = await kota(hariIni);
  const mapIni = (await one('select game.sorotan_harga_map($1) m', [hariIni])).m;
  const komo = Object.keys(mapIni)[0], pct = mapIni[komo];
  const lain = (await H.sql(`select commodity_id from game.market where city_id = $1`, [X])).map(r => r.commodity_id).find(c => !(c in mapIni));
  const nEvent0 = Number((await one('select count(*) n from game.city_events')).n);
  const ev = async (city, comm) => (await one('select ev_mul from game.eco2_muls($1, $2, $3)', [u.id, city, comm])).ev_mul;
  await H.sql(`update game.config set value = '0' where key = 'SorotanAktif'`);
  const dasar = await ev(X, komo), dasarLain = lain && await ev(X, lain);
  assert((await kota(hariIni)) === null && (await one('select game.sorotan_harga($1, $2) p', [X, komo])).p === 0, 'saklar mati: tidak ada efek');
  await H.sql(`update game.config set value = '1' where key = 'SorotanAktif'`);
  const naik = await ev(X, komo);
  assert(Math.abs(naik / dasar - (1 + pct / 100)) < 1e-9, 'harga ' + komo + ' di ' + X + ' naik ' + pct + '%: ' + naik / dasar);
  if (lain) assert(Math.abs((await ev(X, lain)) / dasarLain - 1) < 1e-9, 'komoditas lain tidak naik');
  const Y = elig.find(c => c !== X);
  await H.sql(`update game.config set value = '0' where key = 'SorotanAktif'`);
  const dasarY = await ev(Y, komo);
  await H.sql(`update game.config set value = '1' where key = 'SorotanAktif'`);
  assert(Math.abs((await ev(Y, komo)) / dasarY - 1) < 1e-9, 'pulau lain tidak naik');

  await H.sql(`insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day) values ($1, 'storm_surge', 'Badai', 'x', 20, 0, $2)`, [X, hariIni + 3]);
  assert((await one('select game.city_event($1) e', [X])).e.priceMultiplierPercent === 20, 'event acak tetap terbaca di kota yang disorot');
  assert(Math.abs((await ev(X, komo)) / naik - 1.2) < 1e-9 || Math.abs((await ev(X, komo)) / dasar - 1.2 * (1 + pct / 100)) < 1e-9, 'harga berlipat dengan event acak');
  assert(Number((await one('select count(*) n from game.city_events')).n) === nEvent0 + 1, 'Sorotan tidak menulis city_events');

  // ---- batch premium ----
  const prem = await one(`select m.city_id, m.commodity_id, c.ref from game.market m join game.commodities c on c.id = m.commodity_id
                           where c.tier = 'premium' and m.role = 'produce' and m.city_id = 'bjorneo' and c.id = 'emas'`);
  assert(prem, 'baris produsen emas di bjorneo');
  const ref = Number(prem.ref), batch = Math.ceil(ref * 0.4), cap = ref * 1.2;
  // cari hari game yang menyorot bjorneo, lalu siklus pertama yang DIMULAI di hari itu
  let dB = hariIni; while ((await kota(dB)) !== 'bjorneo') dB++;
  const cB = Number((await one(`select ceil((game.cfg_num('WorldStartTimestamp', 0) + $1::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)
                                         / (greatest(1, game.cfg_num('MarketCycleMinutes', 60)) * 60000))::bigint c`, [dB])).c);
  const mult = Number((await one('select game.sorotan_batch($1) b', [dB])).b);
  const tagsOn = (await one(`select game.mkt_cycle_tags('bjorneo', $1) t`, [cB])).t;
  assert(tagsOn.sorot && Number(tagsOn.sorot[String(cB)]) === mult, 'kartu siklus membawa pengali batch');
  assert(tagsOn.wanted.length === 2 && tagsOn.surplus.length === 1, 'Kabar Pasar tetap utuh');
  const proj = async (stok, dari, ke, tags) => Number((await one(`select game.mkt_project($1, now(), $2, 'produce', 'premium', $3, 'emas', $4, $5) s`, [stok, dari, ref, tags, ke])).s);
  const sOn = await proj(0, cB - 1, cB, tagsOn);
  assert(Math.abs(sOn - Math.min(cap, batch * mult)) < 1e-6, 'satu siklus disorot: batch x' + mult + ' = ' + sOn);
  let cO = cB - 1, tagsOff = (await one(`select game.mkt_cycle_tags('bjorneo', $1) t`, [cO])).t;   // siklus lebih awal yang tidak disorot
  while (tagsOff.sorot && cB - cO < 80) { cO--; tagsOff = (await one(`select game.mkt_cycle_tags('bjorneo', $1) t`, [cO])).t; }
  assert(!tagsOff.sorot, 'siklus tak disorot tanpa kunci sorot');
  assert(await proj(0, cO - 1, cO, tagsOff) === batch, 'tanpa Sorotan batch normal ' + batch);
  // dua siklus terlewat, hanya siklus terakhir disorot (siklus sebelumnya hari lain)
  const s2 = await proj(0, cB - 2, cB, tagsOn);
  assert(Math.abs(s2 - Math.min(cap, batch * (1 + mult))) < 1e-6, 'dua siklus: x1 + x' + mult + ' = ' + s2);
  // batas stok tetap
  assert(await proj(cap, cB - 1, cB, tagsOn) === cap, 'stok penuh tidak melewati batas');
  assert(await proj(0, cB - 30, cB, tagsOn) <= cap + 1e-9, 'tertahan di batas stok');

  // ---- event Skitraw macet diakhiri; event normal tak tersentuh; idempoten ----
  await H.sql(`insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day) values ('skitraw', 'storm_surge', 'Gelombang Badai', 'x', 22, 0, $1)`, [hariIni + 170]);
  await H.sql(`insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day) values ('bjorneo', 'festival', 'Festival', 'x', 0, 25, $1)`, [hariIni + 4]);
  assert((await one(`select game.city_event('skitraw') e`)).e, 'Skitraw punya event macet sebelum migrasi');
  const sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0090-sorotan-pulau.sql'), 'utf8');
  await H.db.exec(sql); await H.db.exec(sql);   // ulang = aman
  assert((await one(`select game.city_event('skitraw') e`)).e === null, 'event Skitraw macet berakhir');
  assert((await one(`select game.city_event('bjorneo') e`)).e, 'event 4 hari tidak tersentuh');
  assert((await one(`select value from game.config where key = 'SorotanGaram'`)).value === garamAsli, 'garam tidak berganti saat diulang');

  // ---- tanpa jejak di API pemain: kartu pasar tidak membawa kunci sorot/berita ----
  await H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, X]);
  const pasar = await u.call('api_getMarket', [X]);
  const teks = JSON.stringify(pasar).toLowerCase();
  assert(!teks.includes('sorot'), 'respons pasar tidak memuat kata sorot');
  assert(pasar.cycle && Array.isArray(pasar.cycle.wanted), 'respons pasar utuh');
  const lg = await one(`select count(*) n from game.player_log where message ilike '%sorot%'`);
  assert(Number(lg.n) === 0, 'tidak ada log berisi sorot');

  // ---- kinerja (informasi): 33 panggilan eco2_muls ----
  const t0 = Date.now();
  for (let i = 0; i < 33; i++) await one('select * from game.eco2_muls($1, $2, $3)', [u.id, X, komo]);
  console.log('33x eco2_muls: ' + (Date.now() - t0) + ' ms (PGlite)');

  console.log('OK: Sorotan Pulau (' + n + ' pulau layak, ' + bs.size + ' pengali batch, jadwal ' + seq.slice(0, 5).join(' > ') + ' ...)');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
