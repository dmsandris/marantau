// Tide v46 · Balai Kongsi & Ki Dorus: kongsi dagang 3 tier, kabar, panggil pulang, Daya Serap,
// Neraca Laut, sumbangan IKN pekanan + porsi pribadi, penahanan selama Saga 3.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const H1 = 3600000;
  let offset = 0;
  const majuJam = async (jam) => { offset += Math.round(jam * H1); await H.sql(`update game.config set value = $1 where key = 'HarianClockOffset'`, [String(offset)]); };
  const bank = async (u) => Number((await one('select bank_balance b from game.players where player_id = $1', [u.id])).b);
  const gold = async (u) => Number((await one('select gold g from game.players where player_id = $1', [u.id])).g);
  const mk = async (name, uname) => { const u = await H.user(uname); await u.call('api_createCharacter', [name, 'merchant']); return u; };
  const keRantai = async (u) => {
    await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'limatangan', 5)
                 on conflict (player_id, quest_id) do update set step = 5`, [u.id]);
    await H.sql(`update game.player_location set city_id = 'rantai_lama', destination_city_id = null, depart_at = null, arrive_at = null where player_id = $1`, [u.id]);
  };
  const setBank = async (u, b, g) => H.sql('update game.players set bank_balance = $2, gold = $3, bank_last_interest_day = game.game_day() where player_id = $1', [u.id, b, g == null ? 1000 : g]);
  const chatCount = async (re) => (await H.sql(`select msg ->> 'tx' tx from game.mp_chat where channel = 'g' and msg ->> 'n' = 'Ki Dorus'`)).filter(r => re.test(r.tx)).length;

  // ---------------------------------------------------------------- gerbang
  const A = await mk('Kapten Anggrek', 'kongsi_a');
  let s = await A.call('api_getGameState', [null]);
  ok(s.kongsi === null, 'KongsiOpen=0: state null');
  await H.expectError(() => A.call('api_kongsi', ['status']), /belum dibuka/);
  await H.sql(`update game.config set value = '1' where key = 'KongsiOpen'`);
  s = await A.call('api_getGameState', [null]);
  ok(s.kongsi === null, 'belum pernah ke Rantai Lama: state null');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'limatangan', 5)`, [A.id]);
  s = await A.call('api_getGameState', [null]);
  ok(s.kongsi && s.kongsi.here === false && s.kongsi.min === 100000 && Array.isArray(s.kongsi.active), 'state terbuka: ' + JSON.stringify(s.kongsi));
  ok(s.kongsi.kenal === false && typeof s.kongsi.musim === 'string', 'perkenalan & musim');
  await H.expectError(() => A.call('api_kongsi', ['tanam', 'agresif', 1000000]), /Rantai Lama/);

  // ---------------------------------------------------------------- tanam
  await keRantai(A); await setBank(A, 50000000, 2000);
  await H.expectError(() => A.call('api_kongsi', ['tanam', 'agresif', 50000]), /paling sedikit/);
  await H.expectError(() => A.call('api_kongsi', ['tanam', 'emas', 1000000]), /Pilih kapal/);
  await H.expectError(() => A.call('api_kongsi', ['tanam', 'agresif', 60000000]), /tidak cukup/);
  let r = await A.call('api_kongsi', ['tanam', 'agresif', 10000000]);
  ok(await bank(A) === 40000000, 'modal diambil dari bank dulu');
  ok(r.kongsi.active.length === 1 && r.kongsi.active[0].tier === 'agresif' && r.kongsi.active[0].kabar === null && !r.kongsi.active[0].canRecall, 'kapal aktif tanpa kabar');
  const raw = JSON.stringify(r);
  ok(!/outcome|kabar_good|kabarGood|turun|"good"/.test(raw), 'peluang / hasil tidak bocor ke klien');
  await H.expectError(() => A.call('api_kongsi', ['tanam', 'agresif', 1000000]), /masih di laut/);
  // tanpa batas modal atas; bila bank kurang, sisanya dari gold di tangan
  await setBank(A, 39999000, 50000);
  await A.call('api_kongsi', ['tanam', 'moderat', 40000000]);
  ok(await bank(A) === 0 && await gold(A) === 49000, 'modal besar: bank habis lalu gold di tangan');
  await setBank(A, 5000000, 1000);
  await A.call('api_kongsi', ['tanam', 'konservatif', 2000000]);
  s = await A.call('api_getGameState', [null]);
  ok(s.kongsi.active.length === 3, '3 kapal sekaligus (satu per tier)');
  await H.expectError(() => A.call('api_kongsi', ['panggil', s.kongsi.active[0].id]), /kabar/);
  const buku0 = await one('select * from game.kongsi_buku where player_id = $1', [A.id]);
  ok(Number(buku0.total_modal) === 52000000 && buku0.n === 3, 'Buku Ki Dorus mencatat modal seumur hidup');

  // ---------------------------------------------------------------- kabar & panggil pulang
  await majuJam(12.1);
  s = await A.call('api_getGameState', [null]);
  const byTier = (t) => s.kongsi.active.filter(a => a.tier === t)[0];
  ok(byTier('agresif').kabar && byTier('moderat').kabar && byTier('konservatif').kabar, 'kabar tiba di jam ke-12');
  ok(byTier('agresif').canRecall && byTier('moderat').canRecall && !byTier('konservatif').canRecall, 'panggil pulang hanya Moderat/Agresif');
  await H.expectError(() => A.call('api_kongsi', ['panggil', byTier('konservatif').id]), /tidak bisa dipanggil/);
  const b0 = await bank(A);
  r = await A.call('api_kongsi', ['panggil', byTier('agresif').id]);
  ok(await bank(A) === b0 + 7000000, 'panggil pulang: 70% modal kembali ke bank');
  ok(r.kongsi.active.length === 2, 'kapal yang dipanggil tidak lagi di laut');
  await H.expectError(() => A.call('api_kongsi', ['panggil', byTier('agresif').id]), /tidak di laut/);

  // ---------------------------------------------------------------- pulang + Daya Serap
  await H.sql(`update game.kongsi set outcome = 140 where player_id = $1 and tier = 'moderat' and status = 'laut'`, [A.id]);
  await H.sql(`update game.kongsi set outcome = 100 where player_id = $1 and tier = 'konservatif' and status = 'laut'`, [A.id]);
  ok(Number((await one(`select game.kongsi_bayar(40000000, 140) v`)).v) === 40000000 + 2000000 + 3000000 + 2000000, 'Serap: 5 jt penuh, 15 jt separuh, sisanya seperempat');
  ok(Number((await one(`select game.kongsi_bayar(10000000, 0) v`)).v) === 0, 'rugi selalu penuh');
  ok(Number((await one(`select game.kongsi_bayar(4000000, 180) v`)).v) === 7200000, 'modal kecil: untung penuh');
  const b1 = await bank(A);
  await majuJam(12);
  s = await A.call('api_getGameState', [null]);
  ok(s.kongsi.active.length === 0, 'semua kapal pulang setelah 24 jam');
  ok(await bank(A) === b1 + 47000000 + 2000000, 'hasil masuk bank: moderat (dengan Serap) + konservatif impas');
  ok(s.kongsi.laporan.length === 2 && s.kongsi.laporan.every(l => l.story && l.payout != null), 'laporan cerita menunggu dibaca');
  ok(/harganya jatuh/.test(s.kongsi.laporan.filter(l => l.tier === 'moderat')[0].story), 'laporan menyebut pasar banjir saat Serap memotong');
  ok(await chatCount(/Lonceng/) === 0, 'hasil 140% tidak diumumkan');
  r = await A.call('api_kongsi', ['lihat']);
  ok(r.kongsi.laporan.length === 0, 'laporan ditandai sudah dibaca');
  ok(r.papan.riwayat.length === 3, 'riwayat buku: 3 kongsi');

  // pengumuman: hanya kemenangan besar
  await setBank(A, 10000000, 1000);
  await A.call('api_kongsi', ['tanam', 'agresif', 2000000]);
  await A.call('api_kongsi', ['tanam', 'moderat', 5000000]);
  await H.sql(`update game.kongsi set outcome = 180 where player_id = $1 and tier = 'agresif' and status = 'laut'`, [A.id]);
  await H.sql(`update game.kongsi set outcome = 0 where player_id = $1 and tier = 'moderat' and status = 'laut'`, [A.id]);
  await majuJam(24.1);
  r = await A.call('api_kongsi', ['status']);
  ok(await chatCount(/Lonceng Rantai Lama berdentang! Lancang kongsi Kapten Kapten Anggrek pulang membawa 3\.600\.000|Lonceng Rantai Lama berdentang!.*Kapten Anggrek/) === 1, 'kemenangan besar diumumkan');
  ok(await chatCount(/tak pulang|zonk/i) === 0, 'zonk tidak diumumkan');
  ok(r.papan.lonceng.length === 2 && r.papan.lonceng.every(x => x.me) && Number(r.papan.lonceng[1].untung) === 1600000 && !r.papan.lonceng.some(x => Number(x.untung) <= 0), 'Papan Lonceng: kemenangan pekan ini, urut untung, tanpa zonk');
  const inbox = await H.sql(`select item from game.mp_inbox where player_id = $1 and item ->> 'type' = 'kongsi'`, [A.id]);
  ok(inbox.some(i => i.item.kind === 'pulang') && inbox.some(i => i.item.kind === 'kabar'), 'inbox kabar & pulang');

  // ---------------------------------------------------------------- rata-rata < 100% & Neraca Laut
  ok((await one('select game.kongsi_aman() v')).v === true, 'config bawaan aman');
  const ev = await H.sql(`select t, game.kongsi_ev(t) ev from unnest(array['konservatif','moderat','agresif']) t`);
  ok(ev.every(e => Number(e.ev) < 100), 'rata-rata tiap tier < 100: ' + JSON.stringify(ev));
  // simulasi undian murni (pemain tanpa riwayat)
  const B = await mk('Kapten Bakau', 'kongsi_b');
  for (const t of ['konservatif', 'moderat', 'agresif']) {
    const sim = await one(`select avg(o)::numeric v, max(o) mx from (select (game.kongsi_undi($1, $2)).o_outcome o from generate_series(1, 6000)) z`, [B.id, t]);
    ok(Number(sim.v) < 100, `simulasi ${t}: rata-rata ${sim.v}`);
  }
  // simulasi Daya Serap + strategi panggil pulang terbaik (JS, dari config)
  const T = JSON.parse((await one(`select value from game.config where key = 'KongsiTier'`)).value);
  const bayar = async (m, o) => Number((await one('select game.kongsi_bayar($1, $2) v', [m, o])).v);
  for (const m of [1000000, 5000000, 20000000, 100000000]) {
    for (const t of Object.keys(T)) {
      let e = 0; for (const [p, o] of T[t]) e += p / 100 * await bayar(m, o);
      ok(e / m < 1, `Serap ${t} modal ${m}: ${(e / m * 100).toFixed(1)}%`);
      // strategi terbaik: setiap kabar, pilih max(70%, nilai lanjut)
      if (t === 'konservatif') continue;
      const good = T[t].filter(x => x[1] >= 100), bad = T[t].filter(x => x[1] < 100);
      const sum = (arr, f) => arr.reduce((s2, x) => s2 + f(x), 0);
      const pg = sum(good, x => x[0]) / 100, pb = sum(bad, x => x[0]) / 100;
      const vg = sum(good, x => x[0] / 100 * x[1]) / 100, vb = sum(bad, x => x[0] / 100 * x[1]) / 100;
      const k = 0.65, pk = k * pb + (1 - k) * pg, pk2 = 1 - pk;
      const best = pk * Math.max(0.7, (k * vb + (1 - k) * vg) / pk) + pk2 * Math.max(0.7, ((1 - k) * vb + k * vg) / pk2);
      ok(best < 1, `strategi panggil pulang terbaik ${t}: ${(best * 100).toFixed(1)}%`);
    }
  }
  // config tidak aman -> Balai menolak
  const orig = (await one(`select value from game.config where key = 'KongsiTier'`)).value;
  await H.sql(`update game.config set value = '{"konservatif":[[100,110]],"moderat":[[100,90]],"agresif":[[100,90]]}' where key = 'KongsiTier'`);
  ok((await one('select game.kongsi_aman() v')).v === false, 'config rata-rata >= 100 terdeteksi');
  await setBank(A, 10000000, 1000);
  await H.expectError(() => A.call('api_kongsi', ['tanam', 'konservatif', 1000000]), /menghitung ulang/);
  await H.sql(`update game.config set value = $1 where key = 'KongsiTier'`, [orig]);
  // Neraca Laut pemain: untung besar 14 hari -> 180% tidak pernah keluar
  await H.sql(`insert into game.kongsi(player_id, tier, modal, outcome, depart_at, kabar_at, return_at, kabar_good, status, payout, settled_at, settle_week)
               values ($1, 'agresif', 5000000, 180, now(), now(), now(), true, 'pulang', 9000000, game.hr_now(), game.kongsi_week_start())`, [B.id]);
  const nr = await one(`select max(o) mx, bool_or(t) t from (select (x).o_outcome o, (x).o_turun t from (select game.kongsi_undi($1, 'agresif') x from generate_series(1, 400)) y) z`, [B.id]);
  ok(Number(nr.mx) < 180 && nr.t === true, 'Neraca Laut menurunkan hasil tinggi pemain yang sedang hoki: ' + JSON.stringify(nr));

  // ---------------------------------------------------------------- Ki Dorus menyumbang IKN (pekanan)
  const C = await mk('Kapten Cempaka', 'kongsi_c'), D = await mk('Kapten Damar', 'kongsi_d');
  await H.sql('delete from game.kongsi');
  const lalu = `game.kongsi_week_start() - interval '7 days'`;
  await H.sql(`insert into game.kongsi(player_id, tier, modal, outcome, depart_at, kabar_at, return_at, kabar_good, status, payout, settled_at, settle_week) values
     ($1, 'agresif', 10000000, 0, now(), now(), now(), false, 'pulang', 0, game.hr_now(), ${lalu}),
     ($1, 'moderat', 2000000, 75, now(), now(), now(), false, 'pulang', 1500000, game.hr_now(), ${lalu}),
     ($2, 'agresif', 5000000, 160, now(), now(), now(), true, 'pulang', 8000000, game.hr_now(), ${lalu}),
     ($3, 'moderat', 4000000, 30, now(), now(), now(), false, 'pulang', 1200000, game.hr_now(), ${lalu})`, [C.id, D.id, A.id]);
  // C rugi 10,5 jt; D untung 3 jt; A rugi 2,8 jt -> laba 10,3 jt -> donasi 2,06 jt
  await H.sql(`insert into game.gr_donations(project_id, player_id, gold, total, n) values ('ikn', $1, 2500000, 2500000, 1)`, [C.id]);
  const pool0 = Number((await one(`select total from game.gr_projects where id = 'ikn'`)).total);
  await C.call('api_mpPulse', [{}]);
  const wk = await one(`select * from game.kongsi_week order by week desc limit 1`);
  ok(Number(wk.laba) === 10300000 && Number(wk.donasi) === 2060000 && wk.pengongsi === 3, 'hitungan pekanan: ' + JSON.stringify(wk));
  ok(Number((await one(`select total from game.gr_projects where id = 'ikn'`)).total) === pool0 + 2060000, 'kolam IKN bertambah 20% laba (sekali)');
  const dc = await one(`select kongsi, total from game.gr_donations where project_id = 'ikn' and player_id = $1`, [C.id]);
  const da = await one(`select kongsi from game.gr_donations where project_id = 'ikn' and player_id = $1`, [A.id]);
  const dd = await one(`select kongsi from game.gr_donations where project_id = 'ikn' and player_id = $1`, [D.id]);
  const shareC = Math.floor(2060000 * 10500000 / 13300000), shareA = Math.floor(2060000 * 2800000 / 13300000);
  ok(Number(dc.kongsi) === shareC && Number(da.kongsi) === shareA && !dd, 'porsi dibagi ke yang rugi, sebanding ruginya');
  ok(Number(dc.total) === 2500000 + shareC, 'porsi masuk total sumbangan pribadi');
  ok(Number((await one(`select count(*)::int n from game.kd_owned where player_id = $1 and item_id = 'aura_lentera_ikn'`, [C.id])).n) === 1, 'porsi menaikkan kategori (Lentera IKN)');
  ok(await chatCount(/menyumbang 2.060.000 gold untuk Restorasi IKN atas nama 3 pengongsi/) === 1, 'pengumuman sumbangan Ki Dorus ' + JSON.stringify(await H.sql("select msg from game.mp_chat where channel='g' order by id desc limit 3")));
  await C.call('api_mpPulse', [{}]); await D.call('api_getGameState', [null]);
  ok(Number((await one(`select count(*)::int n from game.kongsi_week`)).n) === 1 && await chatCount(/menyumbang/) === 1, 'hitungan pekanan tidak dobel');
  const gv = await C.call('api_gotong', ['status']).catch(() => null);
  if (gv) ok(Number(gv.gotong.kiDorus) === 2060000 && Number(gv.gotong.me.kongsi) === shareC, 'Prasasti: baris Ki Dorus & porsi pribadi');
  else {
    const v = await one(`select game.gr_view($1, 'ikn') v`, [C.id]);
    ok(Number(v.v.kiDorus) === 2060000 && Number(v.v.me.kongsi) === shareC, 'Prasasti: baris Ki Dorus & porsi pribadi');
  }
  // pekan untung bagi pemain: tidak ada sumbangan
  await H.sql(`insert into game.kongsi(player_id, tier, modal, outcome, depart_at, kabar_at, return_at, kabar_good, status, payout, settled_at, settle_week)
               values ($1, 'agresif', 1000000, 180, now(), now(), now(), true, 'pulang', 1800000, game.hr_now(), game.kongsi_week_start() - interval '14 days')`, [D.id]);
  await D.call('api_mpPulse', [{}]);
  const wk2 = await one(`select * from game.kongsi_week where week = game.kongsi_week_start() - interval '14 days'`);
  ok(wk2 && Number(wk2.donasi) === 0 && wk2.catatan === 'laut murah hati', 'pekan rugi bagi balai: Ki Dorus tidak menyumbang');

  // ---------------------------------------------------------------- Saga 3: hasil ditahan selama harta dicuri
  await keRantai(D); await setBank(D, 5000000, 1000);
  await D.call('api_kongsi', ['tanam', 'konservatif', 1000000]);
  await H.sql(`update game.kongsi set outcome = 115 where player_id = $1 and status = 'laut'`, [D.id]);
  await H.sql(`insert into game.pv_snap(player_id, data) values ($1, '{"bank": 4000000}')`, [D.id]);
  await setBank(D, 0, 5000);   // harta dicuri
  await majuJam(24.1);
  await A.call('api_mpPulse', [{}]);
  let kd = await one(`select status, payout from game.kongsi where player_id = $1 order by id desc limit 1`, [D.id]);
  ok(kd.status === 'tahan' && Number(kd.payout) === 1150000, 'Saga 3: hasil ditahan');
  ok(await bank(D) === 0, 'Saga 3: bank pemain tidak bertambah');
  const ibD = await H.sql(`select 1 from game.mp_inbox where player_id = $1 and item ->> 'kind' = 'pulang'`, [D.id]);
  ok(ibD.length === 0, 'Saga 3: tanpa inbox laporan');
  const snapBank = (await one(`select data ->> 'bank' b from game.pv_snap where player_id = $1`, [D.id])).b;
  ok(Number(snapBank) === 4000000, 'potret tidak disentuh (hasil kongsi tidak ikut Bunga Waktu)');
  await H.sql(`update game.pv_snap set restored_at = now() where player_id = $1`, [D.id]);
  await A.call('api_mpPulse', [{}]);
  kd = await one(`select status, seen from game.kongsi where player_id = $1 order by id desc limit 1`, [D.id]);
  ok(kd.status === 'pulang' && kd.seen === false && await bank(D) === 1150000, 'setelah harta kembali: hasil dilepas ke bank & laporan muncul');

  // ---------------------------------------------------------------- lain-lain
  r = await A.call('api_kongsi', ['kenal']);
  ok(r.kongsi.kenal === true, 'perkenalan Ki Dorus tercatat');
  await H.expectError(() => A.call('api_kongsi', ['terbang']), /tidak dikenal/);
  // IKN selesai -> Ki Dorus berhenti menyumbang
  await H.sql(`update game.gr_projects set done_at = now() where id = 'ikn'`);
  await H.sql(`insert into game.kongsi(player_id, tier, modal, outcome, depart_at, kabar_at, return_at, kabar_good, status, payout, settled_at, settle_week)
               values ($1, 'agresif', 3000000, 0, now(), now(), now(), false, 'pulang', 0, game.hr_now(), game.kongsi_week_start() - interval '21 days')`, [A.id]);
  await A.call('api_mpPulse', [{}]);
  const wk3 = await one(`select * from game.kongsi_week where week = game.kongsi_week_start() - interval '21 days'`);
  ok(Number(wk3.donasi) === 0 && wk3.catatan === 'ikn selesai', 'setelah Restorasi selesai: tidak ada sumbangan');
  s = await A.call('api_getGameState', [null]);
  ok(s.kongsi.ikn === false, 'state: IKN selesai');

  console.log('0062 balai kongsi: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
