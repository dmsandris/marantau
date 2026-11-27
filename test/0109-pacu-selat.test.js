// Tide v88 · Pacu Selat (0109): fisika JS (PacuSelat.html) = SQL (game.ps_sim), Galangan, Bengkel, Uji, Pacu Gugur,
// rombongan Adu 2-4 kapten, taruhan & medali, mesin jebol, gerbang langkah 40.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const P = require('./pacu-selat-sim');
const Q = { awal: 'a', tepat: 't', sempurna: 's', telat: 'l' };

(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];

  // ================= 1. Spesifikasi JS = SQL =================
  const R = P.mk(4242);
  let nSpec = 0;
  for (const kelas of P.KELAS) for (const rasio of ['400', '800', '1400']) for (let i = 0; i < 4; i++) {
    const parts = P.PARTS.filter(() => R() < 0.5);
    const js = P.S.spesifikasi(kelas, parts, rasio);
    const sq = (await one(`select to_jsonb(game.ps_spesifikasi($1, $2::text[], $3)) s`, [kelas, parts, rasio])).s;
    ok(sq.accel === js.accelPermil && sq.top === js.topMmPerSec && sq.maxrpm === js.maxRpm && sq.lag === js.shiftLagMs &&
       sq.anti === js.antiBatukPermil && sq.boostp === js.boostPowerPermil && sq.boostd === js.boostDurMs,
       'spesifikasi ' + kelas + ' ' + rasio + ' ' + parts.join(',') + ' ' + JSON.stringify(sq) + ' vs ' + JSON.stringify(js));
    ok(JSON.stringify(sq.gf) === JSON.stringify(js.gearFactorsPermil.slice(1)), 'faktor gigi ' + kelas);
    for (let g = 1; g <= 4; g++) {
      const w = P.S.jendelaGigi(js, g);
      ok(sq.gs[g - 1] === w.greenStartPermil && sq.ss[g - 1] === w.starStartPermil && sq.est[g - 1] === w.estRpmPerSecPermil,
         'jendela gigi ' + g + ' ' + kelas + ' ' + rasio);
    }
    nSpec++;
  }
  for (const seed of [1, 2, 3003, 99991, 2000000000, 123456789]) {
    ok((await one(`select game.ps_meriam($1) m`, [seed])).m === P.S.waktuMeriam(seed), 'waktu meriam seed ' + seed);
  }

  // ================= 2. Simulasi JS = SQL (log manusia tiruan + log acak) =================
  const cases = [];
  const jarakList = [400000, 800000, 1400000];
  for (let i = 0; i < 18; i++) {
    const kelas = P.KELAS[i % 5], parts = P.PARTS.filter(() => R() < 0.45), rasio = ['400', '800', '1400'][i % 3];
    const sk = P.SKILL[['pemula', 'biasa', 'jago'][i % 3]], jarak = jarakList[i % 3], seed = 1000 + i * 7919;
    const h = P.human(kelas, parts, jarak, seed, sk, rasio);
    cases.push({ kelas, parts, rasio, jarak, seed, log: h.log });
  }
  for (let i = 0; i < 22; i++) {
    const kelas = P.KELAS[(i * 3) % 5], parts = P.PARTS.filter(() => R() < 0.4), rasio = ['800', '400', '1400'][i % 3];
    cases.push({ kelas, parts, rasio, jarak: jarakList[(i + 1) % 3], seed: 50000 + i * 31337, log: P.chaos(i * 17 + 3) });
  }
  // kasus khusus: diam saja (auto lepas 1500 ms), curi start, tahan terus, lepas tanpa tekan, ECU macet di gigi 1
  cases.push({ kelas: 'sekoci_standar', parts: [], rasio: '800', jarak: 800000, seed: 7, log: [] });
  cases.push({ kelas: 'sekoci_standar', parts: [], rasio: '800', jarak: 800000, seed: 8, log: [[-150, 1], [-90, 0]] });
  cases.push({ kelas: 'kolek_kilat', parts: [], rasio: '800', jarak: 800000, seed: 9, log: [[40, 1], [60, 0], [300, 1]] });
  cases.push({ kelas: 'lancang_sultan', parts: [], rasio: '800', jarak: 800000, seed: 10, log: [[500, 0], [700, 0]] });
  cases.push({ kelas: 'bahtera_petir', parts: P.PARTS, rasio: '800', jarak: 800000, seed: 11, log: [[200, 1], [200, 0]] });
  let nSim = 0, nFin = 0, nJebol = 0, nBoost = 0, nJump = 0;
  for (const c of cases) {
    const js = P.jsRun(c.kelas, c.parts, c.rasio, c.jarak, c.log, c.seed);
    const sq = (await one(`select game.ps_sim(game.ps_spesifikasi($1, $2::text[], $3), $4, game.ps_meriam($5), $6::jsonb, null) h`,
      [c.kelas, c.parts, c.rasio, c.jarak, c.seed, JSON.stringify(c.log)])).h;
    const jsSh = js.shifts.map(x => Q[x.kualitas]).join('');
    const same = sq.fin === js.waktuMs && Number(sq.top) === js.topSpeedMmPerSec && sq.z100 === js.zeroToHundredMs &&
      sq.jebol === js.exploded && sq.batuk === js.coughCount && sq.boost === js.boostUsed && sq.jump === js.jumpStart &&
      sq.reaksi === js.reaksiMs && sq.shifts === jsSh;
    ok(same, 'simulasi JS = SQL: ' + JSON.stringify(c) + '\n  SQL ' + JSON.stringify(sq) + '\n  JS  ' + JSON.stringify(Object.assign({}, js, { shifts: jsSh })));
    nSim++; if (js.waktuMs != null) nFin++; if (js.exploded) nJebol++; if (js.boostUsed) nBoost++; if (js.jumpStart) nJump++;
  }
  ok(nFin >= 15 && nJebol >= 2 && nBoost >= 8 && nJump >= 2, `variasi kasus cukup (finish ${nFin}, jebol ${nJebol}, semburan ${nBoost}, curi ${nJump})`);

  // Lawan AI Pacu Gugur: JS = SQL
  for (let b = 1; b <= 4; b++) for (const seed of [17, 4242, 1999999999]) {
    const lw = (await one(`select game.ps_gugur_lawan($1, $2) l`, [b, seed])).l;
    const js = P.jsAi(lw, 400000, seed);
    const sq = (await one(`select game.ps_sim(game.ps_spesifikasi($1, $2::text[], '800'), 400000, game.ps_meriam($3), null,
        jsonb_build_object('react', $4::int, 'noise', $5::int, 'sebaran', $6::int, 'seed', $7::bigint)) h`,
      [lw.kelas, lw.parts, seed, lw.aiReaksiMs, lw.aiShiftNoisePermil, lw.aiSebaranPermil, lw.aiSeed])).h;
    ok(js != null && sq.fin === js, 'lawan AI babak ' + b + ' seed ' + seed + ': SQL ' + sq.fin + ' JS ' + js);
  }

  // ================= 3. Gerbang =================
  await H.sql(`select game.cfg_set('GmUsernames', 'ps_gm')`);
  const mkCap = async (u, nama) => { const c = await H.user(u); await c.call('api_createCharacter', [nama, 'merchant']); return c; };
  const A = await mkCap('ps_ana', 'Kapten Ana'), B = await mkCap('ps_budi', 'Kapten Budi'),
        C = await mkCap('ps_cici', 'Kapten Cici'), D = await mkCap('ps_dodi', 'Kapten Dodi'), E = await mkCap('ps_eko', 'Kapten Eko');
  const all = [A, B, C, D, E];
  const toZentul = (u) => H.sql(`update game.player_location set city_id = 'zentul', destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id]);
  const gold = async (u) => Number((await one(`select gold from game.players where player_id = $1`, [u.id])).gold);
  const setGold = (u, g) => H.sql(`update game.players set gold = $2 where player_id = $1`, [u.id, g]);
  for (const u of all) { await toZentul(u); await setGold(u, 20000000); }

  ok((await A.call('api_pacuSelat', ['status'])).ps === null, 'tertutup: status ps null');
  await H.expectError(() => A.call('api_pacuSelat', ['mulai', 'uji_800']), /Aksi tidak dikenal/);
  await H.sql(`select game.cfg_set('PacuSelatOpen', '1')`);
  ok((await A.call('api_pacuSelat', ['status'])).ps === null, 'belum langkah 40: tetap tertutup');
  for (const u of all) await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'mahkota', 39) on conflict (player_id, quest_id) do update set step = 39`, [u.id]);
  ok((await A.call('api_pacuSelat', ['status'])).ps === null, 'langkah 39: tertutup');
  for (const u of all) await H.sql(`update game.player_quests set step = 41 where player_id = $1 and quest_id = 'mahkota'`, [u.id]);
  let st = (await A.call('api_pacuSelat', ['status'])).ps;
  ok(st && st.kelasAktif === 'sekoci_standar' && st.siap === true && st.kapalDimiliki.length === 1, 'langkah 41 (Bagian II): terbuka, siap di Zentul');
  ok(st.hargaKapal.pencalang_lancang === '1.250.000 Gold' && st.hargaPart.turbo_sentrifugal === '2.400.000 Gold' && st.hargaPart.reparasi_mesin === '100.000 Gold', 'label harga');
  ok(st.infoMode.uji_800 === '800m · Gratis 1×' && st.infoMode.adu_kapten === 'Taruhan 15.000 Gold' && st.infoMode.pacu_gugur === 'Babak 1/4 · 400m', 'infoMode');
  await H.sql(`select game.cfg_set('PacuSelatOpen', '0'), game.cfg_set('FiturPenguji', 'ps_ana')`);
  ok((await A.call('api_pacuSelat', ['status'])).ps !== null && (await B.call('api_pacuSelat', ['status'])).ps === null, 'penguji: hanya Ana');
  await H.sql(`select game.cfg_set('PacuSelatOpen', '1'), game.cfg_set('FiturPenguji', '')`);
  // berlayar = tidak siap
  await H.sql(`update game.player_location set city_id = 'ikn' where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_pacuSelat', ['mulai', 'uji_800']), /Merapatlah di Zentul/);
  await H.expectError(() => A.call('api_pacuSelat', ['beli', 'kolek_kilat']), /Merapatlah di Zentul/);
  await toZentul(A);

  // ================= 4. Galangan & Bengkel =================
  await setGold(A, 1000000);
  await H.expectError(() => A.call('api_pacuSelat', ['beli', 'pencalang_lancang']), /Gold di tangan tidak cukup/);
  st = (await A.call('api_pacuSelat', ['status'])).ps;
  ok(st.bolehBeli.pencalang_lancang === false && /Gold kurang 250\.000/.test(st.alasanKunci.pencalang_lancang), 'alasan kunci gold kurang');
  await setGold(A, 20000000);
  let r = await A.call('api_pacuSelat', ['beli', 'kolek_kilat']);
  ok(r.ps.kelasAktif === 'kolek_kilat' && r.ps.kapalDimiliki.includes('kolek_kilat') && await gold(A) === 17900000, 'beli Kolek Kilat 2,1 jt');
  r = await A.call('api_pacuSelat', ['beli', 'sekoci_standar']);
  ok(r.ps.kelasAktif === 'sekoci_standar' && await gold(A) === 17900000, 'pakai kapal milik sendiri gratis');
  r = await A.call('api_pacuSelat', ['beli', 'kolek_kilat']);
  ok(await gold(A) === 17900000, 'tidak membayar dua kali');
  for (const pid of ['busi_iridium', 'knalpot_meriam', 'kopling_keramik']) r = await A.call('api_pacuSelat', ['pasang', pid]);
  ok(JSON.stringify(r.ps.partTerpasang) === JSON.stringify(['knalpot_meriam', 'kopling_keramik', 'busi_iridium']), 'part disimpan urut katalog');
  ok(await gold(A) === 17900000 - 800000 - 220000 - 450000, 'harga part dipotong');
  await H.expectError(() => A.call('api_pacuSelat', ['pasang', 'busi_iridium']), /sudah terpasang/);
  await H.expectError(() => A.call('api_pacuSelat', ['pasang', 'roket']), /tidak ada di bengkel/);
  await H.expectError(() => A.call('api_pacuSelat', ['pasang', 'reparasi_mesin']), /tidak sedang jebol/);
  r = await A.call('api_pacuSelat', ['rasio', '400']);
  ok(r.ps.rasioPreset === '400', 'setel rasio');
  await H.expectError(() => A.call('api_pacuSelat', ['rasio', '999']), /rasio tidak dikenal/);
  await A.call('api_pacuSelat', ['rasio', '800']);
  const kas = await one(`select count(*)::int n, sum(delta)::bigint s from game.ps_kas where player_id = $1`, [A.id]);
  ok(kas.n === 4 && Number(kas.s) === -(2100000 + 800000 + 220000 + 450000), 'jejak uang ps_kas');

  // ================= 5. Uji Lintasan =================
  const majuJam = (id) => H.sql(`update game.ps_run set mulai = mulai - 120000 where id = $1`, [id]);
  let g0 = await gold(A);
  r = await A.call('api_pacuSelat', ['mulai', 'uji_800']);
  let b = r.balapan;
  ok(b && b.jarakMm === 800000 && b.peserta.length === 1 && b.peserta[0].kelas === 'kolek_kilat' && await gold(A) === g0, 'Uji 800 gratis pertama');
  ok(b.waktuMeriamMs === P.S.waktuMeriam(b.seed), 'meriam sama dengan klien');
  let h = P.human('kolek_kilat', b.peserta[0].parts, 800000, b.seed, P.SKILL.biasa, '800');
  await H.expectError(() => A.call('api_pacuSelat', ['setor', b.id, h.log]), /belum melihat kapalmu/);
  await majuJam(b.id);
  r = await A.call('api_pacuSelat', ['setor', b.id, h.log]);
  ok(r.hasil.waktuMs === h.s.finishWaktuMs && r.hasil.balapanId === b.id && r.hasil.judul === 'Finish!', 'setor Uji 800: waktu server = klien');
  ok(Math.abs(r.ps.rekorPribadi['800'] - h.s.finishWaktuMs / 1000) < 1e-9 && r.ps.hallOfFame['800'][0].isPemain === true, 'rekor pribadi + papan');
  ok(r.ps.riwayat[0].mode === 'Uji Lintasan 800m', 'riwayat');
  const r2 = await A.call('api_pacuSelat', ['setor', b.id, h.log]);
  ok(r2.hasil.waktuMs === r.hasil.waktuMs, 'setor ulang idempoten');
  g0 = await gold(A);
  r = await A.call('api_pacuSelat', ['mulai', 'uji_800']);
  ok(await gold(A) === g0 - 500 && r.ps.infoMode.uji_800 === '800m · 500 Gold', 'Uji 800 kedua bayar 500');
  r = await A.call('api_pacuSelat', ['mulai', 'uji_1400']);
  ok(await gold(A) === g0 - 1000 && r.balapan.jarakMm === 1400000, 'Uji 1,4 km bayar 500; run lama ditinggal');
  ok((await one(`select count(*)::int n from game.ps_run where player_id = $1 and status = 'tinggal'`, [A.id])).n === 1, 'run lama status tinggal');
  await H.expectError(() => A.call('api_pacuSelat', ['setor', b.id + 'x', []]), /tidak ditemukan/);
  await H.expectError(() => A.call('api_pacuSelat', ['setor', r.balapan.id, [[5, 1], [1, 0]]]), /tidak wajar/);

  // ================= 6. Mesin jebol =================
  r = await B.call('api_pacuSelat', ['mulai', 'uji_800']);
  await majuJam(r.balapan.id);
  r = await B.call('api_pacuSelat', ['setor', r.balapan.id, [[200, 1], [200, 0]]]);
  ok(r.hasil.mesinJebol === true && r.ps.mesinJebol === true && r.hasil.judul === 'Mesin Jebol!', 'tertahan di gigi 1 -> mesin jebol');
  await H.expectError(() => B.call('api_pacuSelat', ['mulai', 'uji_800']), /Mesin kapalmu jebol/);
  g0 = await gold(B);
  r = await B.call('api_pacuSelat', ['pasang', 'reparasi_mesin']);
  ok(r.ps.mesinJebol === false && await gold(B) === g0 - 100000, 'reparasi 100.000');

  // ================= 7. Pacu Gugur =================
  // Kapal kuat + pemain jago menembus empat babak (tes alur, bukan kalibrasi)
  await setGold(C, 40000000);
  await C.call('api_pacuSelat', ['beli', 'bahtera_petir']);
  for (const pid of P.PARTS) await C.call('api_pacuSelat', ['pasang', pid]);
  const oli0 = Number((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'), 0) q`, [C.id])).q);
  let babakMenang = 0;
  for (let bb = 1; bb <= 4; bb++) {
    r = await C.call('api_pacuSelat', ['mulai', 'pacu_gugur']);
    b = r.balapan;
    ok(b.jarakMm === 400000 && b.babak === bb && b.totalBabak === 4 && b.peserta.length === 2, 'gugur babak ' + bb);
    const lw = b.peserta[1];
    ok(lw.aiSeed != null && lw.aiReaksiMs != null, 'profil AI dikirim ke klien');
    let best = null;
    for (let t = 0; t < 30 && !best; t++) {
      const hh = P.human('bahtera_petir', P.PARTS, 400000, b.seed + t * 13, P.SKILL.jago, '800');
      const fin = P.jsRun('bahtera_petir', P.PARTS, '800', 400000, hh.log, b.seed);
      if (fin.waktuMs != null && fin.waktuMs < P.jsAi(lw, 400000, b.seed)) best = hh.log;
    }
    ok(best, 'ada log pemenang babak ' + bb);
    await majuJam(b.id);
    r = await C.call('api_pacuSelat', ['setor', b.id, best]);
    ok(r.hasil.menang === true, 'menang babak ' + bb);
    babakMenang++;
  }
  ok(babakMenang === 4 && r.ps.infoMode.pacu_gugur === 'Juara pekan ini' && r.hasil.judul === 'Juara Gelanggang!', 'juara gelanggang');
  const oli1 = Number((await one(`select coalesce((select qty from game.inventory where player_id = $1 and item_id = 'oli_hitam'), 0) q`, [C.id])).q);
  ok(oli1 > oli0, 'hadiah Oli Hitam juara');
  await H.expectError(() => C.call('api_pacuSelat', ['mulai', 'pacu_gugur']), /sudah menembus Yaptob/);
  // kalah = gugur
  r = await D.call('api_pacuSelat', ['mulai', 'pacu_gugur']);
  await majuJam(r.balapan.id);
  r = await D.call('api_pacuSelat', ['setor', r.balapan.id, []]);
  ok(r.hasil.menang === false && r.ps.gugur.status === 'gugur', 'diam di garis start -> gugur');
  ok(r.ps.mesinJebol === true, 'diam di gigi 1 juga merusak mesin');
  await D.call('api_pacuSelat', ['pasang', 'reparasi_mesin']);
  await H.expectError(() => D.call('api_pacuSelat', ['mulai', 'pacu_gugur']), /sudah gugur pekan ini/);

  // ================= 8. Rombongan Adu 2-4 kapten =================
  for (const u of all) { await H.sql(`select game.mp_touch($1)`, [u.id]); }
  await H.sql(`update game.mp_presence set c = 'zentul', sea = false, ts = now()`);
  const pub = async (u) => (await one(`select pub from game.mp_presence where player_id = $1`, [u.id])).pub;
  st = (await A.call('api_pacuSelat', ['status'])).ps;
  ok(st.adu.kaptenDiZentul.length === 4 && st.adu.kaptenDiZentul.every(k => k.bisaDitantang), 'empat kapten lain di dermaga');
  r = await A.call('api_pacuSelat', ['ajak', await pub(B)]);
  ok(r.ps.adu.rombongan && r.ps.adu.rombongan.tuan === true && r.ps.adu.rombongan.anggota.length === 2, 'rombongan dibuat, Budi diundang');
  await A.call('api_pacuSelat', ['ajak', await pub(C)]);
  await A.call('api_pacuSelat', ['ajak', await pub(D)]);
  const pE = await pub(E); await H.expectError(() => A.call('api_pacuSelat', ['ajak', pE]), /penuh/);
  ok((await one(`select count(*)::int n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'pacu_ajak'`, [B.id])).n === 1, 'undangan masuk inbox');
  st = (await B.call('api_pacuSelat', ['status'])).ps;
  const rid = st.adu.undanganMasuk[0].id;
  ok(st.adu.undanganMasuk.length === 1 && st.adu.undanganMasuk[0].dari === 'Kapten Ana', 'Budi melihat ajakan');
  await H.expectError(() => A.call('api_pacuSelat', ['mulaiRb', rid]), /minimal dua/);
  await H.expectError(() => B.call('api_pacuSelat', ['mulaiRb', rid]), /Hanya tuan/);
  for (const u of [B, C, D]) await u.call('api_pacuSelat', ['jawab', rid, true]);
  st = (await A.call('api_pacuSelat', ['status'])).ps;
  ok(st.adu.rombongan.anggota.filter(x => x.status === 'ikut').length === 4 && st.adu.rombongan.bisaMulai === true, 'empat kapten ikut');
  ok(st.adu.kaptenDiZentul.length === 1 && st.adu.kaptenDiZentul[0].bisaDitantang === false, 'rombongan penuh: Eko tidak bisa diajak');
  await H.expectError(() => B.call('api_pacuSelat', ['mulai', 'uji_800']), /rombongan Adu/);
  await setGold(D, 20000000);
  const goldAwal = {}; for (const u of [A, B, C, D]) goldAwal[u.id] = await gold(u);
  r = await A.call('api_pacuSelat', ['mulaiRb', rid]);
  const room = r.room;
  ok(room.status === 'jalan' && room.anggota.length === 4 && room.mulaiServerMs > room.nowMs && room.waktuMeriamMs === P.S.waktuMeriam(room.seed), 'obor dipasang: start serentak dari jam server');
  for (const u of [A, B, C, D]) ok(await gold(u) === goldAwal[u.id] - 15000, 'taruhan masuk 800 m = 15.000 dipotong');
  ok(room.jarakMm === 800000 && room.taruhan === 15000, 'tanpa pilihan, kategori 800 m');
  ok((await one(`select count(*)::int n from game.mp_inbox where item ->> 'type' = 'pacu_mulai'`)).n === 4, 'empat kapten dibangunkan');
  // akses kanal realtime
  await H.sql(`select set_config('request.jwt.claim.sub', $1, false)`, [B.id]);
  ok((await one(`select public.mt_rt_can_read($1) v`, ['pacu:' + rid])).v === true, 'anggota boleh membaca kanal pacu');
  await H.sql(`select set_config('request.jwt.claim.sub', $1, false)`, [E.id]);
  ok((await one(`select public.mt_rt_can_read($1) v`, ['pacu:' + rid])).v === false, 'bukan anggota ditolak');
  // posisi relay
  r = await A.call('api_pacuSelat', ['pos', rid, 12345, 30000, 2, 900]);
  r = await B.call('api_pacuSelat', ['pos', rid, 11000, 29000, 2, 900]);
  ok(r.lawan.length === 1 && r.lawan[0].pos.p === 12345, 'relay posisi lawan');
  await H.expectError(() => E.call('api_pacuSelat', ['pos', rid, 1, 1, 1, 1]), /bukan anggota/);
  // setor: urutan kecepatan C (kapal terkuat) > A > B > D (diam)
  await H.sql(`update game.ps_room set mulai = mulai - 30000 where id = $1`, [rid]);
  const mem = Object.fromEntries(room.anggota.map(x => [x.nama, x]));
  const logOf = (nama, sk) => P.human(mem[nama].kelas, mem[nama].parts, 800000, room.seed, sk, mem[nama].rasioPreset);
  const hc = logOf('Kapten Cici', P.SKILL.jago), ha = logOf('Kapten Ana', P.SKILL.biasa), hb = logOf('Kapten Budi', P.SKILL.pemula);
  await C.call('api_pacuSelat', ['setorRb', rid, hc.log]);
  r = await A.call('api_pacuSelat', ['setorRb', rid, ha.log]);
  ok(r.room.status === 'jalan', 'menunggu catatan lain');
  await B.call('api_pacuSelat', ['setorRb', rid, hb.log]);
  r = await D.call('api_pacuSelat', ['setorRb', rid, [[200, 1], [200, 0]]]);
  ok(r.room.status === 'selesai', 'semua setor -> dihitung');
  const by = Object.fromEntries(r.room.anggota.map(x => [x.nama, x.hasil]));
  ok(by['Kapten Cici'].menang === true && by['Kapten Cici'].peringkat === 1 && by['Kapten Cici'].fin === hc.s.finishWaktuMs, 'Cici juara, waktu = klien');
  ok(by['Kapten Dodi'].jebol === true && by['Kapten Dodi'].menang === false, 'Dodi jebol');
  ok(await gold(C) === goldAwal[C.id] - 15000 + 60000, '800 m, 4 kapten: pot 60.000 ke Juara 1 (untung 45.000)');
  const medali = async (u) => ((await one(`select coalesce(sum(jumlah), 0)::int q from game.medali where player_id = $1`, [u.id])).q);
  ok(await medali(C) === 9 && by['Kapten Cici'].medali === 9, '800 m, 4 kapten: 3 x3 = 9 Medali untuk Juara 1');
  for (const u of [A, B, D]) ok(await gold(u) === goldAwal[u.id] - 15000 && await medali(u) === 0, 'selain Juara 1 kehilangan taruhan, tanpa Medali');
  ok(by['Kapten Ana'].dapat === 0 && by['Kapten Ana'].medali === 0, 'hasil peringkat lain: dapat 0');
  ok((await one(`select jebol from game.ps_pemain where player_id = $1`, [D.id])).jebol === true, 'mesin Dodi jebol tersimpan');
  ok((await one(`select count(*)::int n from game.mp_inbox where item ->> 'type' = 'pacu_hasil'`)).n === 4, 'hasil dikirim ke semua');
  st = (await C.call('api_pacuSelat', ['status'])).ps;
  ok(st.adu.sisaAduHariIni === 9 && st.riwayat[0].keterangan === 'Juara Adu', 'jatah adu berkurang, riwayat juara');

  // taruhan masuk bisa diaktifkan GM; tanpa catatan -> taruhan kembali. Sekalian uji ganti kategori jarak.
  await D.call('api_pacuSelat', ['pasang', 'reparasi_mesin']);
  const pubB = await pub(B);
  await H.expectError(() => A.call('api_pacuSelat', ['ajak', pubB, '999']), /Kategori jarak/);
  await A.call('api_pacuSelat', ['ajak', await pub(B), '1400']);
  ok((await one(`select jarak_mm from game.ps_room where status = 'lobi' and tuan = $1`, [A.id])).jarak_mm === 1400000, 'rombongan dibuat dengan kategori 1,4 km');
  ok((await one(`select taruhan from game.ps_room where status = 'lobi' and tuan = $1`, [A.id])).taruhan === 20000, 'taruhan 1,4 km = 20.000');
  const rid2 = (await B.call('api_pacuSelat', ['status'])).ps.adu.undanganMasuk[0].id;
  ok((await B.call('api_pacuSelat', ['status'])).ps.adu.undanganMasuk[0].jarakMm === 1400000, 'undangan memuat kategori jarak');
  await H.expectError(() => B.call('api_pacuSelat', ['jarakRb', rid2, '400']), /Hanya tuan/);
  await H.expectError(() => A.call('api_pacuSelat', ['jarakRb', rid2, '700']), /Kategori jarak/);
  await A.call('api_pacuSelat', ['jarakRb', rid2, '400']);
  ok((await one(`select jarak_mm from game.ps_room where id = $1`, [rid2])).jarak_mm === 400000, 'tuan mengganti kategori jadi 400 m');
  ok((await one(`select taruhan from game.ps_room where id = $1`, [rid2])).taruhan === 10000, 'taruhan ikut berubah jadi 10.000');
  await B.call('api_pacuSelat', ['jawab', rid2, true]);
  const gA = await gold(A), gB = await gold(B);
  await A.call('api_pacuSelat', ['mulaiRb', rid2]);
  ok(await gold(A) === gA - 10000, 'taruhan rombongan kedua (400 m)');
  await H.sql(`update game.ps_room set mulai = mulai - 400000 where id = $1`, [rid2]);
  r = await B.call('api_pacuSelat', ['lihatRb', rid2]);
  ok(r.room.status === 'selesai' && r.room.hasil.kembali === true && await gold(A) === gA && await gold(B) === gB, 'tanpa catatan: taruhan kembali');

  // ---- hadiah per kategori & jumlah kapten (2 kapten: pengali x1) ----
  const duel = async (jarak, tuan, lawan, setorSemua) => {
    await tuan.call('api_pacuSelat', ['ajak', await pub(lawan), String(jarak)]);
    const id = (await lawan.call('api_pacuSelat', ['status'])).ps.adu.undanganMasuk[0].id;
    await lawan.call('api_pacuSelat', ['jawab', id, true]);
    r = await tuan.call('api_pacuSelat', ['mulaiRb', id]);
    const rm = r.room;
    await H.sql(`update game.ps_room set mulai = mulai - 60000 where id = $1`, [id]);
    const mm = Object.fromEntries(rm.anggota.map(x => [x.nama, x]));
    const lg = (nama, sk) => P.human(mm[nama].kelas, mm[nama].parts, jarak * 1000, rm.seed, sk, mm[nama].rasioPreset);
    return { id, rm, lg, mm };
  };
  {
    const g0 = { A: await gold(A), B: await gold(B) }, m0 = { A: await medali(A), B: await medali(B) };
    const d = await duel(1400, A, B);
    const la = d.lg('Kapten Ana', P.SKILL.jago), lb = d.lg('Kapten Budi', P.SKILL.pemula);
    ok(d.rm.jarakMm === 1400000 && d.rm.taruhan === 20000, 'kategori 1,4 km terbawa ke balapan, taruhan 20.000');
    await A.call('api_pacuSelat', ['setorRb', d.id, la.log]);
    r = await B.call('api_pacuSelat', ['setorRb', d.id, lb.log]);
    ok(r.room.status === 'selesai' && r.room.hasil.pot === 40000 && r.room.hasil.hadiahMedali === 5, '1,4 km, 2 kapten: pot 40.000 + 5 Medali');
    ok(await gold(A) === g0.A + 20000 && await medali(A) === m0.A + 5 && await gold(B) === g0.B - 20000 && await medali(B) === m0.B, 'hanya Juara 1 yang menerima: untung 20.000 + 5 Medali');
  }
  {
    const g0 = await gold(B), m0 = await medali(B);
    const d = await duel(400, B, A);
    const lb = d.lg('Kapten Budi', P.SKILL.biasa);
    await B.call('api_pacuSelat', ['setorRb', d.id, lb.log]);
    await H.sql(`update game.ps_room set mulai = mulai - 400000 where id = $1`, [d.id]);
    r = await A.call('api_pacuSelat', ['lihatRb', d.id]);
    ok(r.room.status === 'selesai' && r.room.hasil.hadiahMedali === 0 && await gold(B) === g0 + 10000 && await medali(B) === m0, 'menang WO: hanya pot (untung 10.000), tanpa Medali');
  }
  const tb = (await one(`select game.ps_adu_hadiah_tabel() t`)).t;
  ok(tb['400'].taruhan === 10000 && tb['400'].medali === 2 && tb['800'].taruhan === 15000 && tb['800'].medali === 3 && tb['1400'].taruhan === 20000 && tb['1400'].medali === 5, 'tabel dasar taruhan & Medali');
  ok((await one(`select hg, hr from game.ps_adu_hadiah(1400000, 4)`)).hr === 15 && Number((await one(`select hg from game.ps_adu_hadiah(1400000, 4)`)).hg) === 60000, '1,4 km, 4 kapten: untung 60.000 Gold + 15 Medali');
  // menolak & bubar
  await A.call('api_pacuSelat', ['ajak', await pub(E)]);
  const rid3 = (await E.call('api_pacuSelat', ['status'])).ps.adu.undanganMasuk[0].id;
  await E.call('api_pacuSelat', ['jawab', rid3, false]);
  ok((await one(`select status from game.ps_room_anggota where room_id = $1 and player_id = $2`, [rid3, E.id])).status === 'tolak', 'menolak ajakan');
  await A.call('api_pacuSelat', ['keluarRb', rid3]);
  ok((await one(`select status from game.ps_room where id = $1`, [rid3])).status === 'batal', 'tuan membubarkan rombongan');

  // ================= 9. Quest Saga 4 tetap memakai mesin lama =================
  ok((await one(`select game.trek_run(game.trek_ships() -> 'penuh', '[[250,1],[250,0]]'::jsonb, null, 5) ->> 'fin' f`)).f !== undefined, 'game.trek_run (Trektrek-an quest) masih ada');

  console.log(`OK 0109 pacu selat: ${nSpec} spesifikasi, ${nSim} simulasi JS = SQL, 12 lawan AI, alur Galangan/Bengkel/Uji/Gugur/Adu 4 kapten.`);
})().catch(e => { console.error(e); process.exit(1); });
