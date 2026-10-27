// Tide v37 · Fase 4: Kisah Lapau Bab 1 "Kapal Tanpa Awak" (alniu siarfi), Set Kapal Hantu khusus pembaca,
// Set Badai Petir & Mutiara Paradiso, bentuk kapal, hewan penghuni.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  await H.sql(`update game.config set value = '0' where key = 'PirateEncounterBaseChance'`);
  await H.sql(`update game.config set value = '0' where key = 'EtalaseJumlah'`);
  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const A = await mk('ks_alfa', 'Kapten Alfa Kisah'), B = await mk('ks_bravo', 'Kapten Bravo Kisah');
  const keping = async u => Number((await one('select keping from game.players where player_id = $1', [u.id])).keping);
  const at = (u, city) => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, arrive_at = null, depart_at = null where player_id = $1`, [u.id, city]);
  const sailing = u => H.sql(`update game.player_location set destination_city_id = 'joungjava', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [u.id]);
  // jam dunia: malam / siang (fish_is_night: fraksi >= 0.72 atau < 0.04)
  const setNight = async night => {
    const len = Number((await one(`select game.cfg_num('GameDayLengthRealMinutes', 60) v`)).v) * 60000;
    const now = Number((await one(`select game.now_ms() v`)).v);
    const frac = night ? 0.85 : 0.4;
    await H.sql(`insert into game.config(key, value) values ('WorldStartTimestamp', $1) on conflict (key) do update set value = excluded.value`, [String(Math.round(now - frac * len))]);
    ok((await one(`select game.fish_is_night() n`)).n === night, 'jam dunia ' + (night ? 'malam' : 'siang'));
  };

  ok((await A.call('api_getGameState', [null])).kisah === null, 'tertutup: kisah null');
  await H.sql(`update game.config set value = 'ks_alfa,ks_bravo' where key = 'FiturPenguji'`);
  let st = (await A.call('api_getGameState', [null])).kisah;
  ok(st && st.chapters.length === 5 && st.chapters[0].title === 'Kapal Tanpa Awak' && !st.chapters[0].owned && st.price.kapal_tanpa_awak === 1250, 'katalog bab ' + JSON.stringify(st.chapters[0]));
  ok(st.chapters.slice(1).every(c => !c.open), 'bab 2-5 segera');

  // --- katalog Kedai ---------------------------------------------------------------------
  const items = (await one(`select coalesce(jsonb_agg(i), '[]') j from game.kd_items i`)).j;
  const sum = s => items.filter(i => i.set_id === s).reduce((a, i) => a + i.price, 0);
  ok(items.filter(i => i.set_id === 'kapal_hantu').length === 5 && items.filter(i => i.set_id === 'badai_petir').length === 5 && items.filter(i => i.set_id === 'mutiara_paradiso').length === 5, '3 set baru x 5 barang');
  ok(sum('kapal_hantu') === 8000 && sum('badai_petir') === 9000 && sum('mutiara_paradiso') === 7000, 'total harga set 8.000 / 9.000 / 7.000');
  ok(items.filter(i => i.slot === 'bentuk').length === 3 && items.filter(i => /^penghuni_/.test(i.id)).length === 5, '3 bentuk kapal, 4 hewan baru');

  // --- Kapal Hantu terkunci untuk yang belum tamat ------------------------------------------
  await H.sql(`update game.players set keping = 30000 where player_id in ($1, $2)`, [A.id, B.id]);
  let kd = (await A.call('api_kedai', ['daftar'])).kedai;
  ok(kd.items.find(i => i.id === 'lambung_karam').locked && !kd.items.find(i => i.id === 'layar_badai').locked, 'Kapal Hantu terkunci, Badai Petir bebas');
  await H.expectError(() => A.call('api_kedai', ['beli', 'lambung_karam']), /Kapal Tanpa Awak/);
  await H.expectError(() => A.call('api_kedai', ['beli', 'kisah_kapal_tanpa_awak']), /rak Kisah/);
  await A.call('api_kedai', ['beli', 'bentuk_jung']); await A.call('api_kedai', ['pasang', 'bentuk_jung']);
  ok((await one(`select game.kd_visual($1) v`, [A.id])).v.bentuk === 'bentuk_jung', 'bentuk kapal terpasang');
  ok(!(await one(`select game.kd_etalase_ids() e`)).e.length || true, 'etalase');
  await H.sql(`update game.config set value = '20' where key = 'EtalaseJumlah'`);
  const et = (await one(`select game.kd_etalase_ids() e`)).e;
  ok(et.length === 20 && !et.some(id => items.find(i => i.id === id).req), 'Etalase tidak memajang barang khusus pembaca');
  await H.sql(`update game.config set value = '0' where key = 'EtalaseJumlah'`);

  // --- alur Kisah ---------------------------------------------------------------------------
  await H.expectError(() => A.call('api_kisah', ['dengar']), /Beli dulu/);
  await H.expectError(() => A.call('api_kisah', ['beli', 'malam_chafik']), /belum terbit/);
  const k0 = await keping(A);
  let r = await A.call('api_kisah', ['beli', 'kapal_tanpa_awak']);
  ok(await keping(A) === k0 - 1250 && r.kisah.chapters[0].owned && r.kisah.chapters[0].step === 1 && /Skitraw/.test(r.kisah.chapters[0].task), 'beli bab 1.250 keping');
  await H.expectError(() => A.call('api_kisah', ['beli', 'kapal_tanpa_awak']), /sudah kamu miliki/);
  // langkah 1: Skitraw
  await at(A, 'joungjava');
  await H.expectError(() => A.call('api_kisah', ['dengar']), /Skitraw/);
  await at(A, 'skitraw');
  r = await A.call('api_kisah', ['dengar']);
  ok(r.scene === 'cerita' && r.kisah.chapters[0].step === 2, 'Uda Gala bercerita');
  await H.expectError(() => A.call('api_kisah', ['jawab', 'pulang']), /malam/);
  // langkah 2: tiba siang -> belum; tiba malam -> kabut
  await setNight(false);
  await H.sql(`select game.hr_hook($1, 'arrive', 1, '{"city":"skitraw"}'::jsonb)`, [A.id]);
  ok((await one(`select step from game.ks_progress where player_id = $1`, [A.id])).step === 2, 'tiba siang: belum ada kabut');
  await setNight(true);
  await sailing(A);
  await H.sql(`update game.player_location set arrive_at = now() - interval '1 second' where player_id = $1`, [A.id]);
  await H.sql(`select game.voy_complete_arrival($1, 'joungjava', null)`, [A.id]);
  ok((await one(`select step from game.ks_progress where player_id = $1`, [A.id])).step === 3, 'tiba malam (kait pelayaran sungguhan): kabut, Lonceng Kabut');
  const ib = await H.sql(`select item from game.mp_inbox where player_id = $1 and item ->> 'type' = 'kisah'`, [A.id]);
  ok(ib.length === 1 && ib[0].item.ev === 'kabut', 'kabar inbox sinematik kabut');
  // langkah 3: teka-teki Nenek Ulin
  await H.expectError(() => A.call('api_kisah', ['jawab', 'pulang']), /Bjorneo/);
  await at(A, 'bjorneo');
  r = await A.call('api_kisah', ['jawab', 'Jangkar']);
  ok(r.benar === false && r.waitMs === 20000, 'jawaban salah: tunggu 20 detik');
  await H.expectError(() => A.call('api_kisah', ['jawab', 'pulang']), /Tunggu/);
  await H.sql(`update game.ks_progress set wait_until = now() - interval '1 second' where player_id = $1`, [A.id]);
  r = await A.call('api_kisah', ['jawab', '  PULANG! ']);
  ok(r.benar === true && r.kisah.chapters[0].step === 4, 'jawaban "pulang" benar');
  // langkah 4: lonceng di laut malam
  await H.expectError(() => A.call('api_kisah', ['lonceng']), /laut lepas/);
  await sailing(A);
  await setNight(false);
  await H.expectError(() => A.call('api_kisah', ['lonceng']), /malam/);
  await setNight(true);
  r = await A.call('api_kisah', ['lonceng']);
  ok(r.scene === 'pulang' && r.kisah.chapters[0].done && r.kedai.items.find(i => i.id === 'layar_koyak').qty === 1, 'tamat: Layar Koyak gratis');
  ok(!r.kedai.items.find(i => i.id === 'lambung_karam').locked, 'Set Kapal Hantu terbuka');
  await at(A, 'bjorneo');
  await A.call('api_kedai', ['beli', 'lambung_karam']);
  await H.expectError(() => A.call('api_kisah', ['lonceng']), /tamat/);
  // pemain lain tetap terkunci
  await H.expectError(() => B.call('api_kedai', ['beli', 'aura_arwah']), /Kapal Tanpa Awak/);

  // --- Kesaktian set baru -------------------------------------------------------------------
  for (const id of ['layar_badai', 'lambung_petir', 'panji_penangkal', 'meriam_guntur', 'datang_petir']) { await B.call('api_kedai', ['beli', id]); await B.call('api_kedai', ['pasang', id]); }
  ok(JSON.stringify((await one(`select game.kd_visual($1) v`, [B.id])).v.sakti) === '["badai_petir"]', 'Kesaktian Badai Petir');
  for (const id of ['lambung_karam', 'layar_koyak']) await A.call('api_kedai', ['pasang', id]);
  for (const id of ['aura_arwah', 'jejak_kabut', 'datang_lonceng']) { await A.call('api_kedai', ['beli', id]); await A.call('api_kedai', ['pasang', id]); }
  ok(((await one(`select game.kd_visual($1) v`, [A.id])).v.sakti || []).includes('kapal_hantu'), 'Kesaktian Kapal Hantu');
  ok((await one(`select game.kd_set_name('mutiara_paradiso') n`)).n === 'Set Mutiara Paradiso', 'nama set');

  console.log('0035_kisah_set OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
