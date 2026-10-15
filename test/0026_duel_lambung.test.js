// Duel Lambung (PvP): fase taktis dihitung server, taruhan diselesaikan saat Pertarungan Terakhir,
// laporan akhir realtime, relay cadangan, duel ditinggal, larangan berlayar, perbaikan audit.
const assert = require('assert');
(async () => {
  const H = await require('./harness').create();
  const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
  const mk = async (u, n) => { const c = await H.user(u); await c.call('api_createCharacter', [n, 'pirate']); await H.sql('update game.players set gold = 20000 where player_id = $1', [c.id]); return c; };
  const A = await mk('lb_alfa', 'Alfa'), B = await mk('lb_bravo', 'Bravo');
  const pubOf = async c => (await c.call('api_mpPulse', [{}])).mePub;
  const pa = await pubOf(A), pb = await pubOf(B);
  const gold = async c => Number((await H.sql('select gold from game.players where player_id = $1', [c.id]))[0].gold);
  const row = async id => (await H.sql('select * from game.mp_duels where id = $1', [id]))[0];
  const age = (id, ms) => H.sql(`update game.mp_duels set created = created - $2, round_ts = round_ts - $2, final_ts = final_ts - $2 where id = $1`, [id, ms]);
  const ready = id => H.sql(`update game.mp_duels set round_ts = (extract(epoch from clock_timestamp()) * 1000)::bigint - 10 where id = $1`, [id]);
  const ORD = (o) => Object.assign({ rud: 0, sails: 1, fl: false, fr: false, ammo: 'ball' }, o || {});
  const total0 = (await gold(A)) + (await gold(B));

  // --- tantangan 'naval' dari klien lama kini menjadi duel lambung -------------
  let d = await A.call('api_mpDuelChallenge', [pb, 1000, 'naval']);
  ok(d.kind === 'lambung' && d.status === 'invited', 'tantangan lambung ' + JSON.stringify(d.kind));
  d = await B.call('api_mpDuelRespond', [d.id, true]);
  ok(d.status === 'active' && d.lb && d.lb.phase === 'plan' && d.lb.me === 'b' && d.round === 1, 'duel aktif ' + JSON.stringify(d.lb && d.lb.phase));
  ok(d.lb.st.a.hull === 100 && d.lb.st.b.hull === 100 && typeof d.lb.st.w === 'number', 'kapal awal');
  ok(d.lb.st.a.rlL === undefined && d.lb.st.b.rlL === 0, 'meriam lawan dirahasiakan, meriam sendiri terlihat');
  ok(d.lb.pw && d.lb.pw.you.dm > 0 && d.lb.pw.foe.sp > 0 && d.lb.pw.you.src.Combat != null, 'kekuatan kedua kapten terkirim');
  ok((await gold(A)) === 19000 && (await gold(B)) === 19000, 'taruhan dipegang server');
  const id = d.id;
  await ready(id);

  // --- perintah rahasia ---------------------------------------------------------
  let va = await A.call('api_mpDuelAct', [id, 1, ORD({ rud: 1, fr: true })]);
  ok(va.lb.locked && !va.lb.foeLocked && va.lb.myOrd.rud === 1, 'A terkunci');
  let vb = await B.call('api_mpDuelState', [id]);
  ok(vb.lb.foeLocked && vb.lb.myOrd === null && !JSON.stringify(vb).includes('"fr":true'), 'perintah A tidak bocor ke B');
  await H.expectError(() => B.call('api_mpDuelAct', [id, 1, 'fire']), /Perintah tidak valid/);
  vb = await B.call('api_mpDuelAct', [id, 1, ORD({ rud: -2, sails: 0, fl: true, ammo: 'chain' })]);
  ok(vb.round === 2 && vb.lb.ev && vb.lb.ev.r === 1, 'giliran 1 dihitung ' + JSON.stringify(vb.lb.ev && vb.lb.ev.r));
  const ev = vb.lb.ev;
  ok(ev.oa.rud === 1 && ev.ob.rud === -2 && ev.ob.ammo === 'chain', 'perintah kedua kapal terungkap setelah giliran');
  const s1 = vb.lb.st;
  ok(Math.abs(s1.a.x - 836) > 20 && Math.abs(s1.b.x - 1364) > 20, 'kapal berlayar');
  ok(s1.a.rud === 1 && s1.b.sails === 0, 'perintah tersimpan di kapal');
  console.log('giliran 1:', ev.shots.length, 'salvo, jarak', ev.shots.map(x => x.d), 'a', s1.a.x.toFixed(1), s1.a.y.toFixed(1), 'b', s1.b.x.toFixed(1), s1.b.y.toFixed(1));

  // --- determinisme fisika: simulasi JS (sama dengan klien) cocok dengan server ---
  const TAU = Math.PI * 2, ang = a => a - TAU * Math.floor((a + Math.PI) / TAU);
  const wf = (h, w) => { const a = Math.abs(ang(h - (w + Math.PI))); if (a < 0.62) return 0.12 + a * 0.12; if (a < 1.75) return 0.25 + 0.75 * Math.sin((a - 0.62) / (1.75 - 0.62) * Math.PI / 2); return 1.0 - (a - 1.75) / (Math.PI - 1.75) * 0.22; };
  function step(s, rud, sails, dt, w) {
    const tr = 0.2 * (sails === 1 ? 0.85 : 1) * (0.55 + 0.45 * Math.min(1, s.v / 30)) * (s.tm || 1);
    s.h = ang(s.h + rud * tr * dt);
    const ts = 62 * wf(s.h, w) * (sails === 1 ? 1 : 0.55) * (0.3 + 0.7 * s.sail / 100) * (s.sp || 1);
    s.v = s.v + (ts - s.v) * (1 - Math.exp(-dt * 0.9));
    s.x += Math.sin(s.h) * s.v * dt; s.y -= Math.cos(s.h) * s.v * dt;
  }
  const st0 = (await row(id)).ev.start, ja = Object.assign({}, st0.a), jb = Object.assign({}, st0.b);
  for (let i = 0; i < 60; i++) { step(ja, ev.oa.rud, ev.oa.sails, 0.05, st0.w); step(jb, ev.ob.rud, ev.ob.sails, 0.05, st0.w); }
  ok(Math.abs(ja.x - s1.a.x) < 0.01 && Math.abs(jb.y - s1.b.y) < 0.01, 'JS = server ' + ja.x + ' vs ' + s1.a.x);

  // --- jalankan beberapa giliran sampai Pertarungan Terakhir ---------------------
  // dorong cepat: lambung dibuat sekarat lewat data, lalu satu giliran
  await H.sql(`update game.mp_duels set st = jsonb_set(jsonb_set(st, '{a,hull}', '38'), '{b,hull}', '36') where id = $1`, [id]);
  await H.sql(`update game.mp_duels set st = jsonb_set(st, '{a,crew}', '90') where id = $1`, [id]);
  await ready(id);
  await A.call('api_mpDuelAct', [id, 2, ORD()]);
  vb = await B.call('api_mpDuelAct', [id, 2, ORD()]);
  ok(vb.lb.phase === 'final' && vb.status === 'active' && vb.lb.finalTs > 0, 'masuk Pertarungan Terakhir ' + vb.lb.phase);
  const r1 = await row(id);
  ok(r1.stake_done === true && ['a', 'b', 'draw'].includes(r1.st.stakeWin), 'taruhan diselesaikan');
  const gA = await gold(A), gB = await gold(B);
  ok(gA + gB === total0, 'gold kekal setelah taruhan ' + (gA + gB) + ' vs ' + total0);
  ok(r1.st.stakeWin === 'a' ? gA === 21000 : r1.st.stakeWin === 'b' ? gB === 21000 : gA === 20000, 'pemenang taruhan dibayar ' + r1.st.stakeWin + ' ' + gA + '/' + gB);
  ok(vb.lb.stakeWin === (r1.st.stakeWin === 'b' ? 'you' : r1.st.stakeWin === 'a' ? 'foe' : 'draw'), 'stakeWin dipetakan ke sudut pandang');
  await H.expectError(() => A.call('api_mpDuelChallenge', [pb, 0, 'naval']), /belum selesai/);

  // --- relay cadangan ---------------------------------------------------------------
  let rt = await A.call('api_mpDuelRt', [id, { x: 1, y: 2 }, [{ k: 'shot', id: 's1', dmg: { hull: 3 } }], 0]);
  ok(rt.phase === 'final' && rt.foe === null, 'relay A');
  rt = await B.call('api_mpDuelRt', [id, { x: 9, y: 9 }, [], 0]);
  ok(rt.foe && rt.foe.x === 1 && rt.ev.length === 1 && rt.ev[0].ev.id === 's1', 'B menerima posisi & event A ' + JSON.stringify(rt));
  const seq = rt.seq;
  rt = await B.call('api_mpDuelRt', [id, null, [], seq]);
  ok(rt.ev.length === 0, 'event tidak terulang');

  // --- laporan akhir: lambung tidak bisa naik, kapal tenggelam = kalah ---------------
  let f = await A.call('api_mpDuelFinal', [id, 99, 80, false]);
  ok(f.status === 'active' && f.lb.reported && !f.lb.foeReported, 'A melapor, menunggu B');
  ok((await row(id)).fin.a.hull === 38, 'lambung dipotong ke batas awal Pertarungan Terakhir');
  f = await B.call('api_mpDuelFinal', [id, 0, 50, true]);
  ok(f.status === 'done' && f.winner === 'foe', 'B tenggelam -> A menang ' + JSON.stringify(f.winner));
  ok((await gold(A)) + (await gold(B)) === total0, 'pertarungan terakhir tidak memindahkan gold');
  let rec = await H.sql('select w, l from game.mp_pvp where player_id = $1', [A.id]);
  ok(rec[0].w === 1, 'rekor menang tercatat');
  ok((await H.sql('select count(*)::int n from game.mp_duel_rtev where duel_id = $1', [id]))[0].n === 0, 'relay dibersihkan');

  // --- duel ditinggal 6 jam: selesai sekaligus (audit #2) ----------------------------
  d = await A.call('api_mpDuelChallenge', [pb, 500, 'naval']); d = await B.call('api_mpDuelRespond', [d.id, true]);
  const g2 = (await gold(A)) + (await gold(B));
  await age(d.id, 6 * 3600 * 1000);
  const x = await A.call('api_mpDuelChallenge', [pb, 0, 'naval']);
  ok(x.status === 'invited', 'langsung bisa menantang lagi setelah duel lama ditinggal');
  const old = await row(d.id);
  ok(old.status === 'done' && old.winner === 'draw', 'duel lama seri ' + old.status + ' ' + old.winner);
  ok((await gold(A)) + (await gold(B)) === g2 + 1000, 'taruhan duel ditinggal dikembalikan');
  await A.call('api_mpDuelForfeit', [x.id]);

  // --- satu kapten diam: kalah setelah 3 giliran tanpa perintah --------------------------
  d = await A.call('api_mpDuelChallenge', [pb, 0, 'naval']); d = await B.call('api_mpDuelRespond', [d.id, true]);
  for (let i = 0; i < 3; i++) {
    await ready(d.id);
    const cur = await A.call('api_mpDuelState', [d.id]);
    if (cur.status !== 'active') break;
    await A.call('api_mpDuelAct', [d.id, cur.round, ORD()]);
    await H.sql(`update game.mp_duels set round_ts = round_ts - 16000 where id = $1`, [d.id]);
    await A.call('api_mpDuelState', [d.id]);
  }
  const afk = await A.call('api_mpDuelState', [d.id]);
  ok(afk.status === 'done' && afk.winner === 'you' && afk.forfeit === 'foe', 'B diam 3 giliran -> A menang ' + JSON.stringify([afk.status, afk.winner, afk.forfeit]));

  // --- tidak bisa berlayar saat duel (audit #3) -------------------------------------------
  d = await A.call('api_mpDuelChallenge', [pb, 0, 'naval']);
  const opts = await A.call('api_getSailOptions', []);
  const dest = (opts.options || opts.routes || opts)[0]; const destId = dest.cityId || dest.CityId || dest.id;
  await H.expectError(() => A.call('api_setSail', [destId]), /Batalkan dulu tantangan duelmu/);
  d = await B.call('api_mpDuelRespond', [d.id, true]);
  await H.expectError(() => B.call('api_setSail', [destId]), /Selesaikan duelmu dulu/);
  await A.call('api_mpDuelForfeit', [d.id]);
  // penantang pergi sebelum diterima
  d = await A.call('api_mpDuelChallenge', [pb, 0, 'naval']);
  await H.sql(`update game.player_location set destination_city_id = $2 where player_id = $1`, [A.id, destId]);
  await H.expectError(() => B.call('api_mpDuelRespond', [d.id, true]), /sudah meninggalkan pelabuhan/);
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [A.id]);
  await A.call('api_mpDuelForfeit', [d.id]);

  // --- kondisi kapal 0% (audit #4) ---------------------------------------------------------
  await H.sql('update game.ships set condition = 0 where player_id = $1', [A.id]);
  const fz = (await H.sql('select game.mp_fighter($1) f', [A.id]))[0].f;
  ok(fz.maxHp === 100, 'kapal 0% tanpa bonus kondisi ' + fz.maxHp);
  await H.sql('update game.ships set condition = 100 where player_id = $1', [A.id]);

  // --- duel dadu tetap seperti biasa ----------------------------------------------------------
  d = await B.call('api_mpDuelChallenge', [pa, 100, 'dice']); d = await A.call('api_mpDuelRespond', [d.id, true]);
  ok(d.kind === 'dice' && d.status === 'done' && d.dice, 'duel dadu');

  // --- Pertarungan Terakhir kedaluwarsa tanpa laporan B -> A menang -------------------------
  d = await A.call('api_mpDuelChallenge', [pb, 0, 'naval']); d = await B.call('api_mpDuelRespond', [d.id, true]);
  for (let r = d.round; r <= 7; r++) { await ready(d.id); await A.call('api_mpDuelAct', [d.id, r, ORD()]); vb = await B.call('api_mpDuelAct', [d.id, r, ORD()]); }
  ok(vb.lb.phase === 'final' && vb.round === 7, 'giliran ke-7 -> Pertarungan Terakhir ' + vb.round);
  await A.call('api_mpDuelFinal', [d.id, 50, 50, false]);
  await age(d.id, 340000);
  const tf = await A.call('api_mpDuelState', [d.id]);
  ok(tf.status === 'done' && tf.winner === 'you', 'B tidak melapor -> A menang ' + JSON.stringify([tf.status, tf.winner]));

  // --- keahlian & kapal berpengaruh -------------------------------------------------------------
  const pw = async f => (await H.sql('select game.lb_power($1::jsonb) p', [JSON.stringify(f)]))[0].p;
  const lo = await pw({ tier: 1, cond: 100, stx: { Combat: 35, Luck: 15, Navigation: 35, Sailing: 35, Knowledge: 5, Negotiation: 35 }, ups: {} });
  const hi = await pw({ tier: 4, cond: 100, cannonPct: 52, stx: { Combat: 82, Luck: 73, Navigation: 141, Sailing: 91, Knowledge: 92, Negotiation: 84 }, ups: { speed: 1, cannons: 1, condition: 0.8 } });
  ok(hi.dm > lo.dm + 0.3 && hi.tf < lo.tf - 0.25 && hi.sp > lo.sp + 0.15 && hi.tm > lo.tm + 0.15 && hi.hm > lo.hm && hi.rm < lo.rm - 0.2 && hi.bm > lo.bm,
     'kapten & kapal kuat terasa ' + JSON.stringify([lo, hi].map(x => [x.dm, x.tf, x.sp, x.tm, x.hm, x.rm, x.bm])));
  const dmg = await pw({ tier: 1, cond: 20, stx: {}, ups: {} });
  ok(dmg.hull0 === 68, 'kapal rusak masuk duel tidak utuh ' + dmg.hull0);
  // waktu habis: darah tertinggi menang
  d = await A.call('api_mpDuelChallenge', [pb, 0, 'naval']); d = await B.call('api_mpDuelRespond', [d.id, true]);
  for (let r = 1; r <= 7; r++) { await ready(d.id); await A.call('api_mpDuelAct', [d.id, r, ORD()]); vb = await B.call('api_mpDuelAct', [d.id, r, ORD()]); }
  await A.call('api_mpDuelFinal', [d.id, 30, 90, false]);
  const hb = await B.call('api_mpDuelFinal', [d.id, 50, 10, false]);
  ok(hb.status === 'done' && hb.winner === 'you', 'lambung tertinggi menang walau awak lebih sedikit ' + JSON.stringify([hb.status, hb.winner]));

  console.log('DUEL LAMBUNG TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('ERROR:', e); process.exit(1); });
