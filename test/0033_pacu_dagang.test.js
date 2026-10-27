// Tide v37 · Fase 2: Pacu Dagang - jadwal WIB, skor dari jual, pengali unggulan, kabar salip, Papan Ditutup,
// pengumuman Senin 08:00 (juara per golongan, kategori, Target Pribadi, rekor), coret juri, audit, Layar Emas, API.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  // set jam WIB (naive) lewat HarianClockOffset
  const at = async wib => H.sql(`update game.config set value = (extract(epoch from ($1::timestamp - ((clock_timestamp() at time zone 'UTC') + interval '7 hours'))) * 1000)::bigint::text
    where key = 'HarianClockOffset'`, [wib]);
  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const A = await mk('pd_a', 'Kapten Alfa'), B = await mk('pd_b', 'Kapten Bravo'), C = await mk('pd_c', 'Kapten Charlie'), D = await mk('pd_d', 'Kapten Delta');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6), ($1, 'barsati', 16)`, [C.id]);   // Galiung
  const keping = async u => Number((await one('select keping from game.players where player_id = $1', [u.id])).keping);
  const gold = async u => Number((await one('select gold from game.players where player_id = $1', [u.id])).gold);
  // jual: modal 10 x 100 = 1000, untung = revenue - 1000
  const sell = (u, profit, extra) => H.sql(`select game.hr_hook($1, 'sell', $2, $3::jsonb)`,
    [u.id, 1000 + profit, JSON.stringify(Object.assign({ city: 'joungjava', comm: 'batik', grp: 'kerajinan', qty: 10, avg: 100, base: 100 }, extra || {}))]);
  const score = async (u, ev) => { const r = await one(`select score from game.pd_scores where event_id = $2 and player_id = $1`, [u.id, ev]); return r ? Number(r.score) : null; };
  const st = async u => (await u.call('api_getGameState', [null])).pacu;
  await H.sql(`update game.config set value = '1' where key = 'PacuMataMinJual'`);
  await H.sql(`update game.config set value = '0' where key = 'PacuGoldOn'`);   // pekan 1 = Pekan Uji

  // --- gerbang -----------------------------------------------------------------------
  await at('2026-10-30 19:00');
  ok((await st(A)) === null, 'Pacu tertutup: state null');
  await H.expectError(() => A.call('api_pacu', ['papan']), /belum dibuka/);
  await H.sql(`update game.config set value = '1' where key = 'PacuOpen'`);

  // --- jadwal ----------------------------------------------------------------------------
  let s = await st(A);
  ok(s.event.id === 'PD-2026-10-31' && s.event.status === 'planned' && s.event.theme === null, 'Jumat 19:00: planned, unggulan rahasia ' + JSON.stringify(s.event));
  ok(Math.abs(s.event.ms.reveal - 3600000) < 5000 && Math.abs(s.event.ms.announce - (2 * 86400000 + 13 * 3600000)) < 5000, 'hitung mundur jadwal');
  await sell(A, 9000);
  ok(await score(A, 'PD-2026-10-31') === null, 'jual sebelum Sabtu tidak dihitung');
  await at('2026-10-30 20:30');
  s = await st(A);
  ok(s.event.status === 'revealed' && s.event.theme === 'rempah' && s.event.themeName === 'Rempah', 'Jumat 20:30: bocoran Rempah');
  let chat = await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`);
  ok(/Bocoran Pacu Dagang/.test(chat.msg.tx) && chat.msg.n === 'coco epan', 'kabar bocoran di chat dunia');
  await st(B);
  ok(Number((await one(`select count(*)::int n from game.mp_chat where msg ->> 'tx' like 'Bocoran Pacu%'`)).n) === 1, 'bocoran hanya sekali');

  // --- Sabtu: skor ---------------------------------------------------------------------
  await at('2026-10-31 10:00');
  await st(A);
  ok(/Buku besar dibuka/.test((await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`)).msg.tx), 'kabar pembukaan');
  await sell(A, 10000);
  ok(await score(A, 'PD-2026-10-31') === 10000, 'skor = untung pacu');
  await sell(A, 10000, { grp: 'rempah', city: 'bjorneo' });
  ok(await score(A, 'PD-2026-10-31') === 25000, 'unggulan x1,5');
  await sell(A, 1000, { avg: null, base: 200 });   // barang tanpa modal: modal 10 x 120 = 1200 -> untung 800
  ok(await score(A, 'PD-2026-10-31') === 25800, 'lantai modal untuk barang tanpa catatan modal');
  await sell(B, 30000);
  let ib = await H.sql(`select item from game.mp_inbox where player_id = $1 and item ->> 'type' = 'pacu_salip'`, [A.id]);
  ok(ib.length === 1 && ib[0].item.from === 'Kapten Bravo', 'kabar disalip ke Alfa');
  const lead = await H.sql(`select msg ->> 'tx' tx from game.mp_chat where msg ->> 'tx' like '%merebut kursi pertama%'`);
  ok(lead.length === 1 && /^Kapten Alfa merebut kursi pertama Jukung/.test(lead[0].tx), 'kabar pemimpin pertama; salip Bravo tertahan jeda 3 jam ' + JSON.stringify(lead));
  await sell(A, 40000, { city: 'skitraw' });   // A 65800, lewati target Emas (40000)
  ib = await H.sql(`select item from game.mp_inbox where player_id = $1 and item ->> 'type' = 'pacu_tier' order by seq`, [A.id]);
  ok(ib.length && ib[ib.length - 1].item.tier === 3, 'kabar Target Emas');
  ok(Number((await one(`select count(*)::int n from game.mp_chat where msg ->> 'tx' like '%merebut kursi pertama%'`)).n) === 1, 'kabar pemimpin dibatasi 3 jam');
  await sell(D, 5000);
  await sell(C, 200000);
  await sell(B, -2000);
  ok(await score(B, 'PD-2026-10-31') === 28000, 'rugi mengurangi skor');
  s = await st(B);
  ok(s.me.rank === 2 && s.me.golName === 'Jukung' && s.me.tier === 2 && s.me.peserta === 3, 'peringkat & tier Bravo ' + JSON.stringify(s.me));
  let pb = await A.call('api_pacu', ['papan']);
  ok(pb.board.gol['1'].rows.length === 3 && pb.board.gol['1'].rows[0].name === 'Kapten Alfa' && pb.board.gol['3'].rows[0].name === 'Kapten Charlie', 'papan per golongan');
  ok(pb.board.cats.jelajah[0].name === 'Kapten Alfa' && pb.board.cats.jelajah[0].v === 3, 'papan Penjelajah');
  // golongan dikunci walau naik di tengah pacu
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1, 'gala', 6)`, [D.id]);
  await sell(D, 100);
  ok((await one(`select gol from game.pd_scores where player_id = $1`, [D.id])).gol === 1, 'golongan terkunci');

  // --- Papan Ditutup ---------------------------------------------------------------------
  await at('2026-11-01 17:30'); await st(A);
  ok(/Satu jam lagi/.test((await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`)).msg.tx), 'peringatan sejam sebelum tutup');
  await at('2026-11-01 18:30'); await st(A);
  ok(/Buku besar ditutup/.test((await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`)).msg.tx), 'kabar Papan Ditutup');
  pb = await B.call('api_pacu', ['papan']);
  ok(pb.board.closed && pb.board.gol['1'].rows.length === 0 && pb.board.gol['1'].me.rank === null && Number(pb.board.gol['1'].me.score) === 28000 && !pb.board.cats,
    'Papan Ditutup: hanya skor sendiri ' + JSON.stringify(pb.board.gol['1']));
  ok((await st(B)).me.rank === null, 'peringkat disembunyikan di state');
  await sell(B, 5000);   // masih dihitung, tanpa kabar salip
  ok(await score(B, 'PD-2026-10-31') === 33000, 'jual saat Papan Ditutup tetap dihitung');
  await at('2026-11-02 00:30');
  await sell(B, 99999);
  ok(await score(B, 'PD-2026-10-31') === 33000, 'jual setelah Minggu 23:59 tidak dihitung');
  s = await st(A);
  ok(s.event.status === 'judging' && s.event.id === 'PD-2026-10-31', 'Senin 00:30: juri menghitung');

  // coret juri & audit
  ok(/dicoret/.test((await one(`select game.admin_pacu_coret('PD-2026-10-31', 'pd_d', 'uji') r`)).r), 'coret juri');
  const aud = await H.sql(`select * from game.pd_audit where event_id = 'PD-2026-10-31' order by score desc`);
  ok(aud.length === 4 && aud.some(x => x.banned) && aud[0].tanda.includes('akun < 7 hari'), 'audit ' + JSON.stringify(aud.map(x => [x.username, x.tanda])));

  // --- Senin 08:00: pengumuman -------------------------------------------------------------
  const k0 = { A: await keping(A), B: await keping(B), C: await keping(C), D: await keping(D) }, g0 = await gold(A);
  await at('2026-11-02 08:05');
  s = await st(B);
  ok(s.event.id === 'PD-2026-11-07' && s.last && s.last.id === 'PD-2026-10-31', 'pekan baru, pekan lalu diumumkan');
  const res = s.last.results;
  ok(res.gol['1'].list.length === 1 && res.gol['1'].list[0].name === 'Kapten Alfa', 'Jukung: 2 lolos Perunggu (Delta dicoret) -> hanya juara 1 ' + JSON.stringify(res.gol['1']));
  ok(res.gol['3'].list[0].name === 'Kapten Charlie', 'Juara Galiung');
  ok(res.jelajah && res.jelajah.name === 'Kapten Alfa' && !res.lompat && res.mata, 'kategori (Lompatan butuh rekor)');
  // Alfa: tier 3 (20+40+80) + juara 200 + Penjelajah 150 (+ Mata bila margin terbaik)
  const kA = await keping(A) - k0.A, mataA = res.mata.name === 'Kapten Alfa' ? 150 : 0;
  ok(kA === 140 + 200 + 150 + mataA, 'keping Alfa ' + kA);
  ok(await keping(B) - k0.B === 60 + (res.mata.name === 'Kapten Bravo' ? 150 : 0), 'keping Bravo (Perak, bukan juara 2 karena < 3 lolos)');
  ok(await keping(D) === k0.D, 'Delta dicoret: tanpa hadiah');
  ok(await gold(A) === g0, 'Pekan Uji: tanpa gold');
  ok(Number((await one(`select count(*)::int n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'pacu_hasil'`, [A.id])).n) === 1, 'kabar hasil');
  ok(/Juara pekan ini - Jukung: Kapten Alfa/.test((await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`)).msg.tx), 'pengumuman chat');
  const rec = await one(`select * from game.pd_record where player_id = $1`, [A.id]);
  ok(rec.n_ikut === 1 && rec.juara1 === 1 && rec.n_emas === 1 && JSON.stringify(rec.last3) === '[65800]', 'rekor Alfa ' + JSON.stringify(rec));
  ok((await one(`select game.kd_visual($1) v`, [A.id])).v.emas === true && !(await one(`select game.kd_visual($1) v`, [B.id])).v, 'Layar Emas sepekan untuk juara 1');
  // dua panggilan bersamaan tidak mengumumkan dua kali
  await st(A); await st(C);
  ok(Number((await one(`select count(*)::int n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'pacu_hasil'`, [A.id])).n) === 1, 'pengumuman hanya sekali');
  const pr = (await A.call('api_pacu', ['prasasti'])).prasasti;
  ok(pr.length === 1 && pr[0].juara['1'].name === 'Kapten Alfa' && !pr[0].juara['1'].pid, 'prasasti');
  ok((await A.call('api_pacu', ['hasil'])).hasil.event === 'PD-2026-10-31', 'api hasil');

  // --- pekan kedua: target dari rekor, gold aktif, Layar Emas permanen ----------------------
  s = await st(A);
  ok(JSON.stringify(s.me.targets) === JSON.stringify([39480, 65800, 98700]), 'target dari rekor ' + JSON.stringify(s.me.targets));
  await H.sql(`update game.config set value = '1' where key = 'PacuGoldOn'`);
  await H.sql(`update game.pd_record set juara1 = 2 where player_id = $1`, [A.id]);
  await at('2026-11-07 12:00');
  ok((await st(A)).event.theme === 'mewah', 'unggulan berputar');
  const E = await mk('pd_e', 'Kapten Echo');   // Delta sudah naik ke Pinisi
  await sell(A, 70000); await sell(B, 20000); await sell(E, 20000); await sell(C, 160000);
  await at('2026-11-09 09:00');
  const g1 = await gold(A);
  s = await st(A);
  ok(s.last.id === 'PD-2026-11-07' && s.last.results.gol['1'].list.length === 3, 'Jukung 3 lolos: juara 1-3');
  ok(await gold(A) === g1 + 100000, 'gold juara Jukung ' + (await gold(A) - g1));
  ok(s.last.results.lompat && s.last.results.lompat.name, 'Lompatan Terjauh ada setelah rekor');
  ok(Number((await one(`select game.kd_qty($1, 'layar_emas') q`, [A.id])).q) === 1, 'Layar Emas permanen setelah juara 1 tiga kali');
  ok(s.stats.juara1 === 3 && s.stats.ikut === 2, 'statistik untuk Tanda Jasa');

  // pekan tanpa peserta tetap diumumkan dengan rapi
  await at('2026-11-17 09:00');
  s = await st(A);
  ok(s.event.id === 'PD-2026-11-21' && s.last.id === 'PD-2026-11-14' && s.last.results.peserta === 0, 'pekan kosong diumumkan');
  console.log('0033_pacu_dagang OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
