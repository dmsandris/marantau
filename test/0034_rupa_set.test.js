// Tide v37 · Fase 3: Set Api Gunung & Naga Samudra (Kesaktian Set di ship_visual), Lemari Rupa,
// Etalase Pekan (diskon 25%, ganti Senin 08:00 WIB), Tak Pernah Bolong (clean streak), hadiah gold Pacu aktif.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const at = async wib => H.sql(`update game.config set value = (extract(epoch from ($1::timestamp - ((clock_timestamp() at time zone 'UTC') + interval '7 hours'))) * 1000)::bigint::text
    where key = 'HarianClockOffset'`, [wib]);
  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const A = await mk('rs_alfa', 'Kapten Alfa Rupa'), B = await mk('rs_bravo', 'Kapten Bravo Rupa');
  await H.sql(`update game.config set value = 'rs_alfa,rs_bravo' where key = 'FiturPenguji'`);
  const keping = async u => Number((await one('select keping from game.players where player_id = $1', [u.id])).keping);

  // --- config Pacu gold ---------------------------------------------------------------
  const cfg = async k => (await one(`select value from game.config where key = $1`, [k])).value;
  ok(await cfg('PacuGoldOn') === '1' && await cfg('PacuGoldJukung') === '100000' && await cfg('PacuGoldPinisi') === '250000' && await cfg('PacuGoldGaliung') === '600000', 'hadiah gold Pacu aktif 100 rb / 250 rb / 600 rb');

  // --- katalog set --------------------------------------------------------------------
  const items = (await one(`select coalesce(jsonb_agg(i order by sort), '[]') j from game.kd_items i where set_id is not null`)).j;
  const api = items.filter(i => i.set_id === 'api_gunung'), naga = items.filter(i => i.set_id === 'naga_samudra');
  ok(api.length === 5 && naga.length === 5, 'dua set, masing-masing 5 barang');
  ok(api.reduce((s, i) => s + i.price, 0) === 6000 && naga.reduce((s, i) => s + i.price, 0) === 9000, 'total harga 6.000 & 9.000 keping');
  ok(new Set(api.map(i => i.slot)).size === 5 && new Set(naga.map(i => i.slot)).size === 5, 'tiap barang set di slot berbeda');

  // --- Etalase Pekan --------------------------------------------------------------------
  await at('2026-11-02 07:59');   // Senin sebelum 08:00: masih pekan lalu
  const e0 = (await one(`select game.kd_etalase_ids() e`)).e;
  await at('2026-11-02 08:01');
  const e1 = (await one(`select game.kd_etalase_ids() e`)).e;
  await at('2026-11-08 23:00');
  const e2 = (await one(`select game.kd_etalase_ids() e`)).e;
  ok(e1.length === 3 && JSON.stringify(e1) === JSON.stringify(e2), 'etalase 3 barang, tetap sepanjang pekan ' + JSON.stringify([e1, e2]));
  ok(JSON.stringify(e0) !== JSON.stringify(e1), 'etalase berganti Senin 08:00 ' + JSON.stringify([e0, e1]));
  const ex = await one(`select id from game.kd_items where id = any($1::text[]) and not exclusive limit 1`, [e1]);
  ok(ex, 'etalase hanya barang yang dijual');
  const pr = await one(`select game.kd_price($1) p, game.kd_base_price($1) b`, [e1[0]]);
  ok(pr.p === Math.round(pr.b * 0.75), 'diskon etalase 25% ' + JSON.stringify(pr));
  const notE = await one(`select id from game.kd_items where rak = 'rupa' and not exclusive and active and not (id = any($1::text[])) limit 1`, [e1]);
  ok((await one(`select game.kd_price($1) p, game.kd_base_price($1) b`, [notE.id])).p === (await one(`select game.kd_base_price($1) b`, [notE.id])).b, 'barang lain harga normal');
  let rv = (await A.call('api_rupa', ['status'])).rupa;
  ok(rv.etalase.ids.length === 3 && rv.etalase.msLeft > 0 && rv.etalase.msLeft <= 7 * 86400000 && rv.etalase.base[e1[0]] === pr.b, 'status etalase ' + JSON.stringify(rv.etalase));
  // beli barang etalase memakai harga diskon
  await H.sql(`update game.players set keping = 50000 where player_id = $1`, [A.id]);
  const k0 = await keping(A);
  await A.call('api_kedai', ['beli', e1[0]]);
  ok(await keping(A) === k0 - pr.p, 'beli dengan harga etalase');

  // --- Set & Kesaktian Set -------------------------------------------------------------
  for (const i of api) if (i.id !== e1[0]) { try { await A.call('api_kedai', ['beli', i.id]); } catch (e) { if (!/sudah/.test(e.message)) throw e; } }
  for (const i of api.slice(0, 4)) await A.call('api_kedai', ['pasang', i.id]);
  let vis = (await one(`select game.kd_visual($1) v`, [A.id])).v;
  ok(!vis.sakti && vis.lambung === 'lambung_lava', '4 dari 5: belum sakti ' + JSON.stringify(vis));
  await A.call('api_kedai', ['pasang', api[4].id]);
  vis = (await one(`select game.kd_visual($1) v`, [A.id])).v;
  ok(JSON.stringify(vis.sakti) === '["api_gunung"]', 'lima terpasang: Kesaktian Set Api Gunung ' + JSON.stringify(vis));
  ok((await one(`select game.ship_visual($1) v`, [A.id])).v.kd.sakti[0] === 'api_gunung', 'Kesaktian ikut ship_visual (terlihat kapten lain)');
  rv = (await A.call('api_rupa', ['status'])).rupa;
  const sApi = rv.sets.find(s => s.id === 'api_gunung');
  ok(sApi && sApi.complete && Number(sApi.owned) === 5 && sApi.items.length === 5 && /Api Gunung/.test(sApi.name), 'status set ' + JSON.stringify(sApi));

  // --- Lemari Rupa ----------------------------------------------------------------------
  let r = await A.call('api_rupa', ['simpan', 1, 'Gunung Murka']);
  ok(r.rupa.lemari.length === 1 && r.rupa.lemari[0].name === 'Gunung Murka' && r.rupa.lemari[0].sakti[0] === 'api_gunung', 'laci 1 tersimpan');
  await A.call('api_kedai', ['lepas', 'lambung']); await A.call('api_kedai', ['lepas', 'layar']);
  await A.call('api_kedai', ['beli', 'haluan_naga']); await A.call('api_kedai', ['pasang', 'haluan_naga']);
  r = await A.call('api_rupa', ['simpan', 2, '']);
  ok(r.rupa.lemari[1].name === 'Susunan 2' && r.rupa.lemari[1].equipped.haluan === 'haluan_naga', 'laci 2 nama bawaan');
  r = await A.call('api_rupa', ['pakai', 1]);
  ok(r.shipVisual.kd.sakti && r.shipVisual.kd.lambung === 'lambung_lava' && !r.shipVisual.kd.haluan, 'pakai laci 1: kembali sakti, haluan naga dilepas ' + JSON.stringify(r.shipVisual.kd));
  // laci berisi barang yang tidak dimiliki -> dilewati
  await H.sql(`update game.kd_lemari set equipped = equipped || '{"aura":"aura_mutiara"}' where player_id = $1 and n = 1`, [A.id]);
  r = await A.call('api_rupa', ['pakai', 1]);
  ok(r.skip === 1 && !r.shipVisual.kd.aura, 'barang yang belum dimiliki dilewati');
  await H.expectError(() => A.call('api_rupa', ['pakai', 3]), /kosong/);
  await H.expectError(() => A.call('api_rupa', ['simpan', 4, 'x']), /tidak dikenal/);
  r = await A.call('api_rupa', ['hapus', 2]);
  ok(r.rupa.lemari.length === 1, 'hapus laci');
  ok((await B.call('api_rupa', ['status'])).rupa.lemari.length === 0, 'lemari milik masing-masing');

  // --- Tak Pernah Bolong (clean streak) -------------------------------------------------
  const tick = d => H.sql(`select game.hr_streak_tick($1, $2::date)`, [B.id, d]);
  let d = new Date('2026-12-01T00:00:00Z');
  const ds = n => new Date(d.getTime() + n * 86400000).toISOString().slice(0, 10);
  for (let i = 0; i < 10; i++) await tick(ds(i));
  let sk = await one(`select clean, clean_best, cur from game.hr_streak where player_id = $1`, [B.id]);
  ok(sk.clean === 10 && sk.clean_best === 10 && sk.cur === 10, '10 hari bersih');
  await tick(ds(11));   // bolong 1 hari -> dimaafkan Tali Tambat: streak lanjut, clean mulai lagi
  sk = await one(`select clean, clean_best, cur from game.hr_streak where player_id = $1`, [B.id]);
  ok(sk.cur === 11 && sk.clean === 1 && sk.clean_best === 10, 'Tali Tambat memutus hitungan bersih ' + JSON.stringify(sk));
  for (let i = 12; i < 42; i++) await tick(ds(i));
  sk = await one(`select clean, clean_best from game.hr_streak where player_id = $1`, [B.id]);
  ok(sk.clean === 31 && sk.clean_best === 31, '31 hari bersih');
  ok((await one(`select game.hr_streak_json($1) j`, [B.id])).j.cleanBest === 31, 'cleanBest dikirim ke klien');

  console.log('0034_rupa_set OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
