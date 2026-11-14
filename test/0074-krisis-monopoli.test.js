// 0074 Krisis Monopoli: Zona Cukai pribadi, Patroli Jaring Biru, Bayar Cukai / Runding / Tembus Jaring, Pasar Gelap.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const { D, human, SKILL } = require('./trek-sim');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const inv = async (id) => Object.fromEntries((await H.sql('select item_id, qty from game.inventory where player_id = $1 and qty > 0', [id])).map(r => [r.item_id, r.qty]));
  const loc = async (id) => one('select * from game.player_location where player_id = $1', [id]);
  const mh = async (id) => one('select * from game.mh_player where player_id = $1', [id]);
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  const taruh = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id, city]);
  const layar = async (u, from, to) => {
    await taruh(u, from);
    const r = await u.call('api_setSail', [to]);
    await H.sql(`update game.player_location set depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second' where player_id = $1`, [u.id]);
    return { sail: r, v: (await u.call('api_pollVoyage', [])).voyage };
  };
  const isi = async (u, o) => { await H.sql('delete from game.inventory where player_id = $1', [u.id]); for (const k in o) await H.sql('select game.adjust_inventory($1, $2, $3)', [u.id, k, o[k]]); };
  const cukai = (v) => !!(v && v.encounterPending && v.encounter && v.encounter.kind === 'cukai');

  const a = await H.user('mhsatu'), b = await H.user('mhdua');
  await a.call('api_createCharacter', ['Kapten Krisis', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Biasa', 'merchant']);
  for (const u of [a, b]) {
    await H.sql(`update game.players set gold = 5000000 where player_id = $1`, [u.id]);
    await H.sql(`update game.ships set cargo_capacity = 5000 where player_id = $1`, [u.id]).catch(() => { });
  }

  // ---- jadwal zona ----
  const day = (await one('select game.game_day() d')).d;
  const boleh = ['sunda_empire', 'skitraw', 'joungjava', 'bjorneo', 'paradiso', 'marie_regal'];
  const seen = new Set(); let beda = 0, prev = '';
  for (let d = day; d < day + 30; d++) {
    const z = (await one('select game.mh_zona($1) z', [d])).z;
    assert(z.length === 3 && new Set(z).size === 3 && z.every(c => boleh.includes(c)), 'zona hari ' + d + ': ' + z);
    assert(JSON.stringify(z) === JSON.stringify((await one('select game.mh_zona($1) z', [d])).z), 'jadwal tetap');
    z.forEach(c => seen.add(c)); if (JSON.stringify(z) !== prev) beda++; prev = JSON.stringify(z);
  }
  assert(seen.size === 6 && beda > 15, 'zona berotasi (' + seen.size + ' pulau, ' + beda + ' pergantian)');
  const tampak = ['sunda_empire', 'skitraw', 'joungjava', 'bjorneo'];   // pemain tes belum membuka Paradiso / Marie Regal
  const Z = (await one('select game.mh_zona($1) z', [day])).z, zona = Z.find(c => tampak.includes(c)), bukan = tampak.find(c => !Z.includes(c));
  const asal = tampak.find(c => c !== zona && c !== bukan);

  // ---- pemain tanpa Saga 4: identik ----
  const sama = async (u, kota) => (await H.sql(`select count(*)::int n from game.market m,
      lateral game.eco2_muls($1, m.city_id, m.commodity_id) w, lateral game.eco2_muls_inti($1, m.city_id, m.commodity_id) i
    where m.city_id = $2 and (w.buy_mul <> i.buy_mul or w.sell_mul <> i.sell_mul or w.ev_mul <> i.ev_mul)`, [u.id, kota]))[0].n;
  await H.sql(`update game.config set value = '100' where key = 'MhPatroliPct'`);
  for (let i = 0; i < 6; i++) {
    const { sail, v } = await layar(b, asal, zona);
    assert(!sail.zonaCukai && !cukai(v), 'pemain biasa tidak pernah dicegat patroli cukai');
    if (v.encounterPending) { await b.call('api_resolveCombat', ['flee']).catch(() => { }); await taruh(b, asal); }
  }
  assert((await sama(b, zona)) === 0 && (await sama(b, bukan)) === 0, 'pemain biasa: harga identik');
  assert((await b.call('api_getGameState', [null])).cukai == null, 'pemain biasa: tanpa state cukai');
  await H.expectError(() => b.call('api_cukai', ['bayar']), /Aksi tidak dikenal/);
  assert((await b.call('api_cukai', ['status'])).cukai === null, 'status kosong');
  assert((await mh(b.id)) === undefined, 'tanpa baris mh_player');

  // ---- krisis menyala ----
  assert((await one(`select game.admin_mh_set('mhsatu', true) r`)).r === 'OK', 'admin_mh_set');
  await taruh(a, zona);
  assert((await sama(a, zona)) === 0, 'belum berlayar: belum dipotret, harga normal');
  let st = (await a.call('api_getGameState', [null])).cukai;
  assert(st && JSON.stringify(st.zona) === JSON.stringify(Z) && st.kena === null && st.tembus === false, 'state cukai: ' + JSON.stringify(st));

  // bukan zona: tidak dicegat, harga normal
  let x = await layar(a, asal, bukan);
  assert(!x.sail.zonaCukai && !x.v.encounterPending && (await sama(a, bukan)) === 0, 'tujuan bukan zona: bebas');

  // zona: dicegat (100%), kabur/tembak/suap dikunci
  await isi(a, { sugar: 40, mutiara: 8, beras: 3 });
  await H.sql('select game.adjust_inventory($1, $2, 4)', [a.id, 'barang_quest_uji']);   // bukan komoditas: tidak pernah disita
  const tier = Object.fromEntries((await H.sql(`select id, tier from game.commodities`)).map(r => [r.id, r.tier]));
  x = await layar(a, asal, zona);
  assert(x.sail.zonaCukai === true && cukai(x.v) && x.v.encounter.noFlee && x.v.encounter.tembus === false, 'dicegat patroli');
  await H.expectError(() => a.call('api_resolveCombat', ['flee']), /Rantai biru/);
  await H.expectError(() => a.call('api_resolveCombat', ['bribe']), /Stempel biru/);
  await H.expectError(() => a.call('api_resolveCombat', ['fire']), /kapal audit/);
  await H.expectError(() => a.call('api_resolveCombat', ['ram']), /kapal audit/);
  await H.expectError(() => a.call('api_cukai', ['tembus']), /Belum ada yang tahu/);
  assert(cukai((await a.call('api_pollVoyage', [])).voyage), 'masih dicegat');
  const g0 = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  let r = await a.call('api_cukai', ['bayar']);
  let iv = await inv(a.id);
  assert(r.result === 'cukai' && r.how === 'bayar' && r.cityId === zona && iv.sugar === 30 && iv.mutiara === 6 && iv.beras === 2 && iv.barang_quest_uji === 4, 'bayar cukai 25% barang: ' + JSON.stringify(iv));
  assert(r.sita.length === 3 && Number((await one('select gold from game.players where player_id = $1', [a.id])).gold) === g0, 'gold tidak disentuh');
  assert((await loc(a.id)).city_id === zona && (await loc(a.id)).pending_encounter === null, 'merapat di zona');

  // harga zona: beli x1,5, jual x0,6, ev_mul tidak diubah
  const beda2 = await H.sql(`select w.buy_mul / i.buy_mul b, w.sell_mul / i.sell_mul s, w.ev_mul = i.ev_mul e from game.market m,
      lateral game.eco2_muls($1, m.city_id, m.commodity_id) w, lateral game.eco2_muls_inti($1, m.city_id, m.commodity_id) i where m.city_id = $2`, [a.id, zona]);
  assert(beda2.length > 20 && beda2.every(q => Math.abs(q.b - 1.5) < 1e-9 && Math.abs(q.s - 0.6) < 1e-9 && q.e), 'harga zona x1,5 / x0,6');
  assert((await sama(a, bukan)) === 0 && (await sama(b, zona)) === 0, 'kota lain & pemain lain tetap normal');
  st = (await a.call('api_cukai', ['status'])).cukai;
  assert(st.kena === zona, 'state: kena cukai di ' + zona);
  // anti-arbitrase: beli lalu jual di zona selalu rugi
  const gA = Number((await one('select gold from game.players where player_id = $1', [a.id])).gold);
  await isi(a, {});
  await a.call('api_buy', [zona, 'sugar', 5]); await a.call('api_sell', [zona, 'sugar', 5]);
  assert(Number((await one('select gold from game.players where player_id = $1', [a.id])).gold) < gA, 'beli-jual di zona rugi');

  // muatan kecil: tetap satu yang diambil; palka kosong: lolos
  await isi(a, { sugar: 1, beras: 1 });
  x = await layar(a, asal, zona); r = await a.call('api_resolveCombat', ['surrender']);
  assert(r.sita.length === 1 && r.sita[0].qty === 1, 'muatan kecil: satu unit');
  await isi(a, {});
  x = await layar(a, asal, zona); r = await a.call('api_cukai', ['bayar']);
  assert(r.sita.length === 0 && /kosong/.test(r.message), 'palka kosong');

  // runding: gagal = bayar, sukses = lolos
  await H.sql(`update game.config set value = '-1000' where key = 'MhRundingBase'`);
  await H.sql(`update game.character_stats set negotiation = 0 where player_id = $1`, [a.id]);
  let gagal = 0, lolos = 0;
  for (let i = 0; i < 12; i++) {
    await isi(a, { sugar: 40 }); x = await layar(a, asal, zona); r = await a.call('api_cukai', ['runding']);
    if (r.result === 'lolos') { lolos++; assert((await inv(a.id)).sugar === 40, 'lolos: muatan utuh'); } else { gagal++; assert(r.how === 'runding' && (await inv(a.id)).sugar === 30, 'runding gagal = bayar'); }
  }
  assert(gagal >= 5 && lolos >= 0, 'runding (peluang minimum 10%): gagal ' + gagal + ', lolos ' + lolos);
  await H.sql(`update game.config set value = '1000' where key = 'MhRundingBase'`);
  let l65 = 0; for (let i = 0; i < 12; i++) { await isi(a, { sugar: 40 }); await layar(a, asal, zona); if ((await a.call('api_resolveCombat', ['negotiate'])).result === 'lolos') l65++; }
  assert(l65 >= 3, 'runding (peluang maksimum 65%): lolos ' + l65);
  await H.sql(`update game.config set value = '25' where key = 'MhRundingBase'`);

  // ditinggal 10 menit = bayar otomatis
  await isi(a, { sugar: 40 }); x = await layar(a, asal, zona);
  await H.sql(`update game.player_location set pending_encounter = pending_encounter || jsonb_build_object('lastAt', game.now_ms() - 11 * 60000) where player_id = $1`, [a.id]);
  await a.call('api_getGameState', [null]);
  assert((await loc(a.id)).pending_encounter === null && (await loc(a.id)).city_id === zona && (await inv(a.id)).sugar === 30, 'otomatis bayar cukai');

  // misi gubernur bebas cukai (bendera mt.mh_bebas)
  const mb = await one(`select w.buy_mul = i.buy_mul ok from (select set_config('mt.mh_bebas', '1', true)) s,
     lateral game.eco2_muls($1, $2, 'sugar') w, lateral game.eco2_muls_inti($1, $2, 'sugar') i`, [a.id, zona]);
  assert(mb.ok === true, 'bendera bebas cukai');

  // ---- Tembus Jaring ----
  await H.sql(`update game.mh_player set tembus = true where player_id = $1`, [a.id]);
  const main = async (skill) => {
    const t = await a.call('api_cukai', ['tembus']);
    assert(t.ongoing && t.trek.run && t.trek.rival === 'patroli' && t.trek.ship === 'jolt' && t.trek.kind === 'tembus', 'tembus: balapan dimulai');
    await H.sql(`update game.trek_runs set created_at = now() - interval '40 seconds' where run_id = $1`, [t.trek.run]);
    const log = skill ? human('jolt', t.trek.seed, skill).log : [];
    const menang = D.replay('jolt', log).fin < D.runAi('patroli', t.trek.seed).fin;
    return { t, log, menang };
  };
  // kalah (tidak pernah mengetuk dengan benar): premium disita, lainnya 25%
  let kalah = null, menang = null;
  for (let i = 0; i < 40 && !(kalah && menang); i++) {
    await isi(a, { sugar: 40, mutiara: 8, beras: 4 }); x = await layar(a, asal, zona);
    assert(x.v.encounter.tembus === true && x.v.encounter.rival === 'patroli', 'pilihan tembus muncul');
    const g = await main(i % 2 ? SKILL.jago : null);
    await H.expectError(() => a.call('api_trek', ['selesai', g.t.trek.run, g.log]), /./);          // bukan lewat Sirkuit
    r = await a.call('api_cukai', ['selesai', g.t.trek.run, g.log]);
    assert(r.hasil.win === g.menang, 'hasil server = hitungan klien');
    iv = await inv(a.id);
    if (r.hasil.win) {
      menang = r; assert(r.result === 'tembus' && iv.sugar === 40 && iv.mutiara === 8 && iv.beras === 4 && (await sama(a, zona)) === 0, 'menang: tanpa cukai, harga normal');
      assert((await mh(a.id)).gelap_city === zona && JSON.stringify((await mh(a.id)).gelap_cargo) === '{}', 'Pasar Gelap belum resmi: tanpa bonus');
    } else {
      kalah = r; assert(r.result === 'cukai' && r.how === 'kalah' && iv.mutiara === undefined && iv.sugar === 30 && iv.beras === 3, 'kalah: premium disita + cukai: ' + JSON.stringify(iv));
      assert(tier.mutiara === 'premium' && (await sama(a, zona)) > 20, 'kalah: tetap harga zona');
    }
  }
  assert(kalah && menang, 'dua hasil tembus teruji');

  // melepas kemudi (aksi lain setelah balapan dimulai) = kalah
  await isi(a, { sugar: 40, mutiara: 8 }); x = await layar(a, asal, zona); await main(null);
  r = await a.call('api_cukai', ['bayar']);
  assert(r.how === 'kalah' && r.hasil.lepas === true && (await inv(a.id)).mutiara === undefined, 'lepas kemudi = kalah');
  // kalah tapi aman (langkah quest): tidak menyita
  await H.sql(`update game.mh_player set aman = true where player_id = $1`, [a.id]);
  await isi(a, { sugar: 40, mutiara: 8 }); x = await layar(a, asal, zona); await main(null);
  r = await a.call('api_cukai', ['runding']);
  assert(r.aman === true && r.sita.length === 0 && (await inv(a.id)).mutiara === 8, 'aman: tidak menyita');
  await H.sql(`update game.mh_player set aman = false, paksa = true where player_id = $1`, [a.id]);
  await H.sql(`update game.config set value = '0' where key = 'MhPatroliPct'`);
  x = await layar(a, asal, zona);
  assert(cukai(x.v) && x.v.encounter.rival === 'patroli_lemah' && x.v.encounter.aman === true, 'paksa: patroli lemah pasti mencegat');
  await a.call('api_cukai', ['bayar']);
  await H.sql(`update game.mh_player set paksa = false where player_id = $1`, [a.id]);
  x = await layar(a, asal, zona);
  assert(!cukai(x.v), 'peluang 0: patroli cukai tidak muncul');
  if (x.v.encounterPending) await H.sql(`update game.player_location set pending_encounter = null, city_id = $2, destination_city_id = null where player_id = $1`, [a.id, zona]);
  assert((await sama(a, zona)) > 20, 'harga zona tetap berlaku walau tidak dicegat');
  await H.sql(`update game.config set value = '100' where key = 'MhPatroliPct'`);

  // ---- Pasar Gelap ----
  await H.sql(`update game.mh_player set gelap = true where player_id = $1`, [a.id]);
  let ok = null;
  for (let i = 0; i < 30 && !ok; i++) {
    await isi(a, { sugar: 12, mutiara: 12 }); x = await layar(a, asal, zona);
    const g = await main(SKILL.jago); r = await a.call('api_cukai', ['selesai', g.t.trek.run, g.log]);
    if (r.hasil.win) ok = r;
  }
  assert(ok && ok.state.gelap && ok.state.gelap.city === zona && ok.state.gelap.sisa === 10 && ok.state.kena === null, 'Pasar Gelap terbuka: ' + JSON.stringify(ok && ok.state.gelap));
  const lot = Object.fromEntries((await H.sql(`select id, game.mkt_lot(tier)::int l from game.commodities`)).map(q => [q.id, q.l]));
  assert(ok.state.gelap.barang.mutiara === Math.min(12, 10 * lot.mutiara) && ok.state.gelap.barang.sugar === Math.min(12, 10 * lot.sugar), 'unit berhak bonus: ' + JSON.stringify(ok.state.gelap.barang));
  const mul = async (c) => one(`select w.sell_mul ws, i.sell_mul isl, w.buy_mul wb, i.buy_mul ib from game.eco2_muls($1, $2, $3) w, game.eco2_muls_inti($1, $2, $3) i`, [a.id, zona, c]);
  let q = await mul('mutiara');
  assert(q.ws > q.isl && q.ws <= q.wb - 0.01 + 1e-9 && q.wb === q.ib, 'bonus jual, selalu di bawah harga beli: ' + JSON.stringify(q));
  q = await mul('beras'); assert(q.ws === q.isl, 'barang yang tidak dibawa: tanpa bonus');
  // beli di Pasar Gelap lalu jual: barang baru tidak berhak bonus
  await a.call('api_buy', [zona, 'beras', 5]); q = await mul('beras'); assert(q.ws === q.isl, 'barang beli-di-tempat tanpa bonus');
  // kuota: tidak boleh melebihi unit berhak dalam satu jual
  const hak = ok.state.gelap.barang.mutiara;
  await H.expectError(() => a.call('api_sell', [zona, 'mutiara', hak + 1]), /Pintu belakang/);
  await H.sql(`delete from game.pd_scores`).catch(() => { });
  r = await a.call('api_sell', [zona, 'mutiara', hak]);
  assert(r.pasarGelap === true && r.cukai.gelap.sisa === 10 - hak / lot.mutiara, 'jual gelap memotong kuota: ' + JSON.stringify(r.cukai.gelap));
  if (r.cukai.gelap.sisa <= 0) {
    q = await mul('sugar'); assert(q.ws === q.isl, 'kuota habis: tanpa bonus');
    r = await a.call('api_sell', [zona, 'sugar', 10]); assert(!r.pasarGelap, 'jual biasa setelah kuota habis');
  } else {
    q = await mul('sugar'); assert(q.ws > q.isl, 'kuota tersisa: bonus lanjut');
  }
  // Smuggler: kuota +5
  await H.sql(`update game.players set archetype = 'smuggler' where player_id = $1`, [a.id]);
  assert(Number((await one('select game.mh_kuota($1) k', [a.id])).k) === 15, 'Smuggler +5 lot');
  // berlayar lagi: Pasar Gelap tertutup
  x = await layar(a, zona, bukan);
  assert((await mh(a.id)).gelap_city === null && (await mh(a.id)).zona_tuju === null && (await a.call('api_cukai', ['status'])).cukai.gelap == null, 'berlayar lagi menutup Pasar Gelap');

  // ---- urutan: Tony > Patroli ----
  const gm = await H.user('abuy'); await gm.call('api_createCharacter', ['Abuy GM', 'merchant']);
  await gm.call('api_gmTony', ['add', { dest: zona, startAt: Date.now(), endAt: Date.now() + 3600000, chance: 100, kabar: 'diam' }]);
  await isi(a, { sugar: 40 }); x = await layar(a, asal, zona);
  assert(x.v.encounter && x.v.encounter.kind === 'tony', 'Tony didahulukan dari patroli');
  await a.call('api_tonyRaid', ['serah']);
  await H.sql(`update game.tony_raid set cancelled_at = now()`);

  // ---- krisis dimatikan: kembali normal ----
  await H.sql(`select game.admin_mh_set('mhsatu', false)`);
  x = await layar(a, asal, zona);
  assert(!x.sail.zonaCukai && !cukai(x.v) && (await sama(a, zona)) === 0 && (await a.call('api_getGameState', [null])).cukai == null, 'krisis mati: normal');

  console.log('0074 krisis monopoli: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
