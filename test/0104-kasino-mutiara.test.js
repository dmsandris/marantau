// Tide v84 · Kasino Mutiara (0104): aturan akses, taruhan, money trace, batas menang harian, Blackjack, GM, Edge.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const num = v => Number(v);
  let nn = 0; const nonce = () => 'tes-' + (++nn) + '-' + Math.random().toString(36).slice(2, 8);

  await H.sql(`select game.cfg_set('GmUsernames', 'ks_gm'), game.cfg_set('KasinoJedaMs', '0')`);
  const G = await H.user('ks_gm'); await G.call('api_createCharacter', ['Bandar GM', 'merchant']);
  const A = await H.user('ks_ana'); await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);
  const B = await H.user('ks_budi'); await B.call('api_createCharacter', ['Kapten Budi', 'merchant']);
  const toParadiso = async (u) => H.sql(`update game.player_location set city_id = 'paradiso', destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [u.id]);
  const setMoney = async (u, gold, bank, debt) => H.sql(`update game.players set gold = $2, bank_balance = $3, debt_balance = $4 where player_id = $1`, [u.id, gold, bank, debt]);
  const money = async (u) => one(`select gold::bigint g, bank_balance::bigint b from game.players where player_id = $1`, [u.id]);
  await toParadiso(A); await toParadiso(B);
  await setMoney(A, 1000000, 32000000, 0); await setMoney(B, 1000000, 0, 0);

  // ---------- Gerbang ----------
  let st = (await A.call('api_kasino', ['status'])).kasino;
  ok(st.open === false && st.why === 'tutup', 'KasinoOpen bawaan 0 -> tutup');
  let gs = await A.call('api_getGameState', []);
  ok(gs.kasino == null, 'getGameState: kunci kasino null saat tutup');
  await H.expectError(() => A.call('api_kasino', ['dadu', 1000, nonce()]), /masih tertutup/);
  // Mode penguji: hanya akun di FiturPenguji
  await H.sql(`select game.cfg_set('FiturPenguji', 'ks_ana')`);
  ok((await A.call('api_kasino', ['status'])).kasino.open === true, 'penguji: Ana bisa masuk');
  ok((await B.call('api_kasino', ['status'])).kasino.open === false, 'penguji: Budi belum');
  await H.sql(`select game.cfg_set('FiturPenguji', ''), game.cfg_set('KasinoOpen', '1')`);
  gs = await A.call('api_getGameState', []);
  ok(gs.kasino && gs.kasino.on === true && Object.keys(gs.kasino).length === 1, 'getGameState: hanya penanda {on:true}');

  // Kota lain / berlayar / utang
  await H.sql(`update game.player_location set city_id = 'sunda_empire' where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_kasino', ['dadu', 1000, nonce()]), /hanya ada di Paradiso/);
  await toParadiso(A);
  await H.sql(`update game.player_location set pending_encounter = '{"kind":"pirate","level":3}'::jsonb where player_id = $1`, [A.id]);
  await H.expectError(() => A.call('api_kasino', ['dadu', 1000, nonce()]), /PelicanSystem/);
  await toParadiso(A);
  await setMoney(A, 1000000, 32000000, 150000);
  st = (await A.call('api_kasino', ['status'])).kasino;
  ok(st.open === false && st.why === 'utang', 'utang Moneylender -> pintu terkunci');
  await H.expectError(() => A.call('api_kasino', ['slot', 1000, nonce()]), /utang Moneylender/);
  await setMoney(A, 1000000, 32000000, 0);

  // ---------- Taruhan ----------
  for (const b of [99, 100001, 0, -5]) await H.expectError(() => A.call('api_kasino', ['dadu', b, nonce()]), /Taruhan harus antara 100 dan 100\.000/);
  for (const b of [100, 500, 1000, 2500, 5000, 100000, 777]) {
    const before = await money(A);
    const r = await A.call('api_kasino', ['dadu', b, nonce()]);
    const after = await money(A);
    ok(r.round.bet === b && num(after.g) === num(before.g) - b + r.round.payout, 'dadu ' + b + ': gold = sebelum - taruhan + bayaran');
    ok(num(after.b) === num(before.b), 'dadu ' + b + ': saldo bank tidak tersentuh');
    ok(['menang', 'kalah', 'seri'].includes(r.round.result.hasil), 'hasil dadu');
    const d = r.round.result, ps = d.p[0] + d.p[1], ds = d.d[0] + d.d[1];
    ok((d.hasil === 'menang') === (ps > ds) && (d.hasil === 'seri') === (ps === ds), 'mata dadu sesuai hasil');
    ok(r.round.payout === (d.hasil === 'menang' ? 2 * b : d.hasil === 'seri' ? b : 0), 'bayaran dadu 1:1 / seri kembali');
  }
  await setMoney(A, 500, 32000000, 0);
  await H.expectError(() => A.call('api_kasino', ['dadu', 1000, nonce()]), /Gold di tangan tidak cukup/);
  await setMoney(A, 1000000, 32000000, 0);

  // Nonce ganda: hasil sama, gold tidak dipotong dua kali
  const n1 = nonce(), g0 = num((await money(A)).g);
  const r1 = await A.call('api_kasino', ['slot', 2500, n1]);
  const r2 = await A.call('api_kasino', ['slot', 2500, n1]);
  ok(r2.replay === true && r2.round.id === r1.round.id && JSON.stringify(r2.round.result) === JSON.stringify(r1.round.result), 'nonce ganda -> hasil sama');
  ok(num((await money(A)).g) === g0 - 2500 + r1.round.payout, 'nonce ganda tidak memotong dua kali');

  // Jeda antar ronde
  await H.sql(`select game.cfg_set('KasinoJedaMs', '60000')`);
  await H.expectError(() => A.call('api_kasino', ['dadu', 100, nonce()]), /merapikan meja/);
  await H.sql(`select game.cfg_set('KasinoJedaMs', '0')`);

  // Edge tidak bocor ke pemain
  const blob = JSON.stringify(await A.call('api_kasino', ['status'])) + JSON.stringify(r1) + JSON.stringify((await A.call('api_getGameState', [])).kasino);
  ok(!/edge|menangHarian|2500000|kuota/i.test(blob), 'tidak ada Edge / angka kuota di respons pemain');

  // ---------- Roulette ----------
  await H.expectError(() => A.call('api_kasino', ['roulette', [{ t: 'num', n: 0, a: 1000 }], nonce()]), /Kantong mutiara milik bandar/);
  await H.expectError(() => A.call('api_kasino', ['roulette', [{ t: 'num', n: 37, a: 1000 }], nonce()]), /1 sampai 36/);
  await H.expectError(() => A.call('api_kasino', ['roulette', [{ t: 'red', a: 60000 }, { t: 'black', a: 50000 }], nonce()]), /Taruhan harus antara/);
  await H.expectError(() => A.call('api_kasino', ['roulette', [{ t: 'red', a: 50 }], nonce()]), /minimal 100/);
  await H.expectError(() => A.call('api_kasino', ['roulette', [], nonce()]), /Pasang chip/);
  for (let i = 0; i < 12; i++) {
    const bets = [{ t: 'red', a: 1000 }, { t: 'num', n: 7, a: 500 }, { t: 'd3', a: 300 }];
    const r = await A.call('api_kasino', ['roulette', bets, nonce()]);
    const n = r.round.result.n, red = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36].includes(n);
    const exp = (n !== 0 && red ? 2000 : 0) + (n === 7 ? 18000 : 0) + (n >= 25 ? 900 : 0);
    ok(n >= 0 && n <= 36 && r.round.bet === 1800 && r.round.payout === exp, 'roulette: bayaran ' + n + ' = ' + exp);
  }
  // Edge 0 -> kantong mutiara tidak pernah muncul
  ok((await one(`select count(*)::int c from game.kasino_round where game_type = 'roulette' and (state_json ->> 'n')::int = 0`)).c === 0, 'edge 0: bola tidak jatuh di 0');

  // ---------- Slot (analitik) ----------
  const ex = await one(`
    with s(sym, w) as (values ('pearl', 2), ('anchor', 2), ('compass', 3), ('tankard', 7), ('shell', 7))
    select sum(a.w * b.w * c.w * game.ks_slot_mult(a.sym, b.sym, c.sym))::numeric / 9261 as rtp, game.ks_slot_r0() as r0,
           (select count(*) from s) n from s a, s b, s c`);
  ok(Math.abs(num(ex.rtp) - num(ex.r0)) < 1e-9 && Math.abs(num(ex.r0) - 1.101825) < 1e-5, 'slot: RTP dasar enumerasi = ks_slot_r0 = 1,1018');
  for (const e of [-0.10, -0.05, 0, 0.05, 0.10]) {
    const k = Math.max(0, 1 - (1 - e) / num(ex.r0));
    const rtp = (1 - k) * num(ex.r0);
    ok(Math.abs(rtp - (1 - e)) < 1e-9, 'slot: RTP efektif = 1 - Edge (' + e + ')');
  }
  for (let i = 0; i < 10; i++) {
    const r = await A.call('api_kasino', ['slot', 1000, nonce()]);
    const [a, b, c] = r.round.result.reels;
    const m = (await one(`select game.ks_slot_mult($1, $2, $3) m`, [a, b, c])).m;
    ok(m === r.round.result.mult && r.round.payout === 1000 * m && m <= 50, 'slot: bayaran sesuai tabel');
  }

  // ---------- Money trace ----------
  const dsum = await one(`select (select net from game.kasino_daily where player_id = $1 and ks_day = game.ks_day()) d,
      (select sum(net_delta) from game.kasino_round where player_id = $1 and status <> 'active') r`, [A.id]);
  ok(num(dsum.d) === num(dsum.r), 'ringkasan harian = jumlah ronde');
  const bad = await one(`select count(*)::int c from game.kasino_round where status = 'settled'
      and (gold_after <> gold_before - bet_amount + payout_amount or net_delta <> payout_amount - bet_amount)`);
  ok(bad.c === 0, 'money trace: gold_before - bet + payout = gold_after untuk semua ronde instan');

  // ---------- Blackjack ----------
  let g1 = num((await money(A)).g), bj = null, guard = 0;
  do { bj = (await A.call('api_kasino', ['bj', 1000, nonce()])).round; guard++; } while (!bj.active && guard < 30);
  ok(bj.active === true, 'bj: ronde aktif');
  ok(bj.d.length === 1 && bj.p.length === 2 && bj.canDouble === true, 'bj: kartu tertutup bandar tidak dikirim');
  const raw = JSON.stringify(await A.call('api_kasino', ['status']));
  ok(!/shoe/.test(raw), 'bj: sepatu tidak pernah dikirim');
  await H.expectError(() => A.call('api_kasino', ['dadu', 100, nonce()]), /Selesaikan dulu ronde Blackjack/);
  const an = nonce();
  let s1 = (await A.call('api_kasino', ['bjact', bj.id, 'hit', an])).round;
  const s1b = (await A.call('api_kasino', ['bjact', bj.id, 'hit', an])).round;
  ok(JSON.stringify(s1b.p) === JSON.stringify(s1.p), 'bj: aksi dengan nonce sama tidak menarik kartu dua kali');
  if (s1.active) s1 = (await A.call('api_kasino', ['bjact', bj.id, 'stand', nonce()])).round;
  ok(s1.active === false && s1.d.length >= 2 && ['menang', 'kalah', 'seri', 'bust', 'blackjack'].includes(s1.hasil), 'bj: selesai, kartu bandar terbuka');
  const rowBj = await one(`select * from game.kasino_round where id = $1`, [bj.id]);
  ok(rowBj.status === 'settled' && !('shoe' in rowBj.state_json), 'bj: sepatu dibuang setelah selesai');
  ok(num(rowBj.gold_after) === num((await money(A)).g), 'bj: gold_after = gold sekarang');
  ok(num(rowBj.payout_amount) === (s1.hasil === 'menang' ? 2000 : s1.hasil === 'seri' ? 1000 : 0), 'bj: bayaran 1:1');
  // skor konsisten
  const sc = async (cards) => (await one(`select game.ks_bj_score($1::int[]) s`, [cards])).s;
  ok(await sc(s1.p) === s1.ps && await sc(s1.d) === s1.ds, 'bj: skor sesuai kartu');
  ok(await sc([0, 12]) === 21 && await sc([0, 0, 0]) === 13 && await sc([9, 10, 11]) === 30, 'bj: hitung As & kartu gambar');

  // Double
  guard = 0; do { bj = (await A.call('api_kasino', ['bj', 1000, nonce()])).round; guard++; } while (!bj.active && guard < 30);
  const gD = num((await money(A)).g);
  const dd = (await A.call('api_kasino', ['bjact', bj.id, 'double', nonce()])).round;
  ok(dd.active === false && dd.bet === 2000 && dd.p.length === 3 && dd.double === true, 'bj: double = taruhan 2×, satu kartu, selesai');
  ok(num((await money(A)).g) === gD - 1000 + dd.payout, 'bj: double memotong taruhan tambahan');

  // Kedaluwarsa 120 dtk -> stand otomatis
  guard = 0; do { bj = (await A.call('api_kasino', ['bj', 1000, nonce()])).round; guard++; } while (!bj.active && guard < 30);
  await H.sql(`update game.kasino_round set created_at = now() - interval '5 minutes' where id = $1`, [bj.id]);
  st = (await A.call('api_kasino', ['status'])).kasino;
  ok(st.bj === null && (await one(`select status from game.kasino_round where id = $1`, [bj.id])).status === 'expired', 'bj: kedaluwarsa -> stand otomatis');

  // Berlayar -> ronde aktif diselesaikan otomatis
  guard = 0; do { bj = (await A.call('api_kasino', ['bj', 1000, nonce()])).round; guard++; } while (!bj.active && guard < 30);
  const dest = (await one(`select city_id from game.cities where city_id <> 'paradiso' and not coalesce(hidden, false) order by city_id limit 1`)).city_id;
  await A.call('api_setSail', [dest]);
  ok((await one(`select status from game.kasino_round where id = $1`, [bj.id])).status === 'expired', 'bj: berlayar -> ronde diselesaikan');
  await toParadiso(A);

  // ---------- Batas menang harian (hari nyata) ----------
  await H.sql(`select game.cfg_set('KasinoMenangHarian', '1000')`);
  await setMoney(B, 1000000, 0, 0);
  await H.sql(`select game.ks_daily_add($1, game.ks_day(), false, 900, 100)`, [B.id]);
  let capped = null;
  for (let i = 0; i < 200 && !capped; i++) {
    const before = num((await one(`select game.ks_net_today($1) n`, [B.id])).n);
    const r = await B.call('api_kasino', ['dadu', 1000, nonce()]);
    if (r.round.capped) { capped = r; ok(r.round.payout === 1000 + (1000 - before) && r.round.payout < 2000, 'kuota: bayaran = taruhan + sisa kuota'); }
  }
  ok(capped && capped.round.capped === true, 'kuota: bayaran dipotong ke sisa kuota');
  ok((await one(`select game.ks_net_today($1) n`, [B.id])).n == 1000, 'kuota: menang bersih hari ini tepat di batas');
  st = (await B.call('api_kasino', ['status'])).kasino;
  ok(st.open === false && st.why === 'penuh', 'kuota: meja tutup untuk Budi');
  await H.expectError(() => B.call('api_kasino', ['slot', 100, nonce()]), /menutup semua meja/);
  const C = await H.user('ks_cici'); await C.call('api_createCharacter', ['Kapten Cici', 'merchant']); await toParadiso(C);
  ok((await C.call('api_kasino', ['status'])).kasino.open === true, 'kuota per kapten: kapten lain tetap bisa main');
  await H.sql(`select game.cfg_set('HarianClockOffset', $1)`, [String(86400000)]);
  ok((await B.call('api_kasino', ['status'])).kasino.open === true, 'kuota: hari nyata berikutnya meja buka lagi');
  await H.sql(`select game.cfg_set('HarianClockOffset', '0'), game.cfg_set('KasinoMenangHarian', '2500000')`);
  // Tanpa batas kalah
  await setMoney(B, 3000, 0, 0);
  for (let i = 0; i < 40; i++) { const g = num((await money(B)).g); if (g < 100) break; await B.call('api_kasino', ['dadu', Math.min(g, 1000), nonce()]); }
  ok(num((await money(B)).g) >= 0, 'tanpa batas kalah: bisa main sampai gold habis');

  // ---------- Meja ditutup ----------
  await H.sql(`select game.cfg_set('KasinoOpenSlot', '0')`);
  await H.expectError(() => A.call('api_kasino', ['slot', 100, nonce()]), /Meja ini sedang ditutup/);
  ok((await A.call('api_kasino', ['status'])).kasino.tables.slot === false, 'status meja slot tutup');
  await H.sql(`select game.cfg_set('KasinoOpenSlot', '1')`);

  // ---------- GM ----------
  await H.expectError(() => A.call('api_gmKasino', ['status']), /khusus GM/);
  await H.expectError(() => G.call('api_gmKasino', ['edge', 'dadu', 11, 'uji']), /antara -10% dan \+10%/);
  await H.expectError(() => G.call('api_gmKasino', ['edge', 'dadu', 5, '']), /catatan/);
  await H.expectError(() => G.call('api_gmKasino', ['edge', 'poker', 5, 'uji']), /tidak dikenal/);
  let gm = await G.call('api_gmKasino', ['edge', 'dadu', 5, 'Sink gold pekan ini']);
  ok(num(gm.edges.dadu) === 5 && gm.audit.length === 1 && num(gm.audit[0].old) === 0 && num(gm.audit[0].new) === 5 && gm.audit[0].gm === 'ks_gm', 'GM: edge tersimpan + audit');
  ok(gm.stats.dadu && gm.stats.dadu.rounds > 0 && gm.top.length > 0, 'GM: statistik & papan menang');
  gm = await G.call('api_gmKasino', ['gate', 'roulette', false]);
  ok(gm.tables.roulette === false, 'GM: tutup meja');
  await G.call('api_gmKasino', ['gate', 'roulette', true]);
  ok(!/edge/i.test(JSON.stringify(await A.call('api_kasino', ['status']))), 'edge GM tetap tidak bocor');

  // ---------- Edge (Monte Carlo, benih tetap) ----------
  await H.sql(`select setseed(0.4242)`);
  const mc = async (game, edge, n) => {
    await H.sql(`select game.cfg_set('KasinoEdge' || game.ks_key($1), $2)`, [game, String(edge)]);
    await H.sql(`update game.players set gold = 1e12 where player_id = $1`, [A.id]);
    await H.sql(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.jwt.claim.email', $2, false)`, [A.id, A.email]);
    const fn = game === 'dadu' ? `game.ks_play_dadu(1000, 'mc-' || $2 || '-' || $3 || '-' || i)`
      : game === 'slot' ? `game.ks_play_slot(1000, 'mc-' || $2 || '-' || $3 || '-' || i)`
      : `game.ks_play_roulette('[{"t":"red","a":1000}]'::jsonb, 'mc-' || $2 || '-' || $3 || '-' || i)`;
    const r = await one(`with x as (select (${fn}) o from generate_series(1, $1::int) i)
      select sum((o ->> 'payout')::numeric) / sum((o ->> 'bet')::numeric) rtp from x`, [n, game, String(edge)]);
    return num(r.rtp);
  };
  for (const g of ['dadu', 'roulette']) {
    const lo = await mc(g, 0.05, 6000), mid = await mc(g, 0, 6000), hi = await mc(g, -0.05, 6000);
    console.log('  MC', g, 'RTP e+5%', lo.toFixed(4), 'e0', mid.toFixed(4), 'e-5%', hi.toFixed(4));
    ok(Math.abs(lo - 0.95) < 0.045 && Math.abs(mid - 1) < 0.045 && Math.abs(hi - 1.05) < 0.045 && lo < mid && mid < hi, g + ': RTP mengikuti Edge');
  }
  const sl = await mc('slot', 0.10, 6000);
  console.log('  MC slot RTP e+10%', sl.toFixed(4));
  ok(Math.abs(sl - 0.90) < 0.15, 'slot: RTP mendekati 1 - Edge');
  // Roulette edge +10%: kantong 0 muncul
  ok((await one(`select count(*)::int c from game.kasino_round where game_type = 'roulette' and (state_json ->> 'n')::int = 0`)).c > 0, 'edge > 0: kantong mutiara muncul');
  // Kalibrasi Blackjack monoton & di dalam rentang
  const k = async (e) => num((await one(`select game.ks_bj_k($1) k`, [e])).k);
  const kk = [await k(-0.1), await k(-0.05), await k(0), await k(0.05), await k(0.1)];
  ok(kk[0] < kk[1] && kk[1] < kk[2] && kk[2] < kk[3] && kk[3] < kk[4] && kk[0] > -2 && kk[4] < 0.8, 'bj: kalibrasi Edge -> k monoton: ' + kk.join(', '));
  ok(Math.abs(await k(0.01)) < 0.01, 'bj: Edge +1% ≈ aturan dasar (k 0)');

  // ---------- Panel Ops: query kasino, aliran dana, Penjaga (hanya SELECT) ----------
  const KAS = require('../deploy/selfhost/ops/kasino'), ALIRAN = require('../deploy/selfhost/ops/aliran'), PJ = require('../deploy/selfhost/ops/penjaga');
  for (const [k, q] of Object.entries(KAS.Q)) {
    const prm = k === 'feed' ? [null, '%Ana%', 'dadu', 'settled'] : (/\$1/.test(q) ? [null] : []);
    const rows = await H.sql(q, prm);
    ok(Array.isArray(rows), 'ops kasino.' + k + ' jalan');
    if (k === 'feed') ok(rows.length > 0 && rows.every(r => r.meja === 'Duel Dadu' && !/shoe/.test(r.detail)), 'ops feed tersaring & tanpa sepatu');
    if (k === 'ringkas') ok(rows[0].ronde > 0, 'ops ringkas ada ronde');
  }
  const kat = await H.sql(ALIRAN.Q.kategori, [null]);
  ok(kat.some(r => r.kel === 'Kasino'), 'aliran dana memuat kategori Kasino');
  const kap = await H.sql(ALIRAN.Q.kapten, [null]);
  const ana = kap.find(r => r.username === 'ks_ana');
  const anaNet = num((await one(`select sum(net_delta) s from game.kasino_round where player_id = $1 and status <> 'active'`, [A.id])).s);
  ok(ana && Math.abs(num(ana.kasino_bersih) - anaNet) < 1, 'aliran dana: kasino_bersih = jumlah selisih ronde');
  ok(Array.isArray(await H.sql(PJ.Q.kasino, [24])), 'penjaga: query kasino jalan');

  console.log('0104 kasino mutiara: semua lulus');
  process.exit(0);
})().catch((e) => { console.error('GAGAL:', e && e.message || e); process.exit(1); });
