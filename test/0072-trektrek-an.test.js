// 0072 Trektrek-an: (1) simulasi JS (MTTrekSim) = SQL (game.trek_run), (2) alur api_trek.
// TREK_N=jumlah kasus acak per kelompok (bawaan 120; kalibrasi penuh pakai 2500+).
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const H0 = require('./harness');
const { D, human, chaos, SKILL } = require('./trek-sim');
const N = parseInt(process.env.TREK_N || '120', 10);

(async () => {
  const H = await H0.create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const SHIPS = Object.keys(D.SHIPS), RIV = Object.keys(D.RIVALS);

  // tetapan kembar
  const ships = (await one(`select game.trek_ships() j`)).j, rivals = (await one(`select game.trek_rivals() j`)).j;
  for (const k of SHIPS) for (const f of ['zone', 'top', 'acc', 'heat']) assert(ships[k][f] === D.SHIPS[k][f], `kapal ${k}.${f} sama`);
  for (const k of RIV) for (const f of ['ship', 'react', 'rsd', 'aim', 'sd', 'boost']) assert(rivals[k][f] === D.RIVALS[k][f], `lawan ${k}.${f} sama`);
  assert(Object.keys(ships).length === SHIPS.length && Object.keys(rivals).length === RIV.length, 'jumlah tetapan sama');

  const sqlRun = async (ship, log) => (await one(`select game.trek_run($1::jsonb, $2::jsonb, null, 1) j`, [JSON.stringify(D.SHIPS[ship]), JSON.stringify(log)])).j;
  const same = (js, sq, tag) => {
    assert(js.fin === sq.fin, `${tag}: fin JS ${js.fin} vs SQL ${sq.fin}`);
    assert(JSON.stringify(js.shifts.map(x => x.q)) === JSON.stringify(sq.shifts), `${tag}: nilai gigi sama`);
    assert(js.reaction === sq.reaction && js.jump === sq.jump && js.boostUsed === sq.boost, `${tag}: reaksi/curi start/semburan sama`);
  };
  // 1a. pemain tiruan (tiga tingkat) di semua kapal
  let n = 0;
  for (let i = 0; i < N; i++) {
    const ship = SHIPS[i % SHIPS.length], sk = SKILL[['pemula', 'biasa', 'jago'][i % 3]];
    const h = human(ship, 1000 + i, sk);
    assert(D.replay(ship, h.log).fin === h.fin, 'replay JS = main langsung');
    same(h, await sqlRun(ship, h.log), `manusia#${i} ${ship}`); n++;
  }
  // 1b. log sembarang: ketukan kembar, sebelum meriam, tahan lama, tidak pernah menekan
  for (let i = 0; i < N; i++) { const ship = SHIPS[i % SHIPS.length], log = chaos(i + 1); same(D.replay(ship, log), await sqlRun(ship, log), `acak#${i} ${ship} ${JSON.stringify(log)}`); n++; }
  for (const log of [[], [[0, 1]], [[79, 1], [79, 0]], [[80, 1], [80, 0]], [[-1, 1], [0, 1], [90, 1]], [[200, 1]], [[200, 1], [200, 0], [449, 1], [450, 1], [451, 1]], [[1600, 1]], [[1599, 1], [1600, 0]]])
    for (const ship of ['tanpa', 'jolt', 'yusaint']) { same(D.replay(ship, log), await sqlRun(ship, log), `tepi ${ship} ${JSON.stringify(log)}`); n++; }
  // 1c. lawan
  for (const r of RIV) for (let i = 0; i < Math.max(6, Math.floor(N / 8)); i++) {
    const seed = 1 + i * 7919 + r.length, js = D.runAi(r, seed);
    const sq = (await one(`select game.trek_run(game.trek_ships() -> $1, null, game.trek_rivals() -> $2, $3) j`, [D.RIVALS[r].ship, r, seed])).j;
    same(js, sq, `lawan ${r} seed ${seed}`); n++;
    assert((await one(`select game.trek_green_ms($1) g`, [seed])).g === D.greenMs(seed), 'waktu meriam sama');
  }
  assert(D.replay('jolt', []).fin != null, 'tanpa ketukan pun kapal berangkat sendiri & finis');

  // 2. API
  const u = await H.user('trekker');
  await u.call('api_createCharacter', ['Kapten Trek', 'merchant']);
  await H.expectError(() => u.call('api_trek', ['status']), /Aksi tidak dikenal/);
  await H.sql(`update game.config set value = 'trekker' where key = 'FiturPenguji'`);
  if (!(await H.sql(`select 1 from game.config where key = 'FiturPenguji'`)).length) await H.sql(`insert into game.config(key, value) values ('FiturPenguji', 'trekker')`);
  let st = (await u.call('api_trek', ['status'])).trek;
  assert(st && st.ship === 'jolt' && st.lawan.length === 4 && st.best === null, 'status penguji');
  const other = await H.user('orangluar'); await other.call('api_createCharacter', ['Orang Luar', 'pirate']);
  await H.expectError(() => other.call('api_trek', ['status']), /Aksi tidak dikenal/);
  await H.expectError(() => u.call('api_trek', ['mulai', 'cangcimen_final']), /belum turun/);
  await H.expectError(() => u.call('api_trek', ['mulai', 'siapa']), /belum turun/);

  const race = async (rival, mkLog, age) => {
    const r = await u.call('api_trek', ['mulai', rival]);
    assert(r.run && r.seed > 0 && r.ship === 'jolt', 'mulai memberi run & seed');
    const log = mkLog(r.seed);
    if (age) await H.sql(`update game.trek_runs set created_at = now() - ($2 || ' seconds')::interval where run_id = $1`, [r.run, String(age)]);
    return { r, log, send: () => u.call('api_trek', ['selesai', r.run, log]) };
  };
  // terlalu cepat menurut jam dinding
  let x = await race('pariopelan', (seed) => human('jolt', seed, SKILL.jago).log, 0);
  await H.expectError(x.send, /tidak wajar/);
  // wajar: hasil = hitungan JS
  x = await race('pariopelan', (seed) => human('jolt', seed, SKILL.jago).log, 30);
  let res = (await x.send());
  const meJs = D.replay('jolt', x.log), opJs = D.runAi('pariopelan', x.r.seed);
  assert(res.hasil.me === meJs.fin && res.hasil.op === opJs.fin && res.hasil.win === (meJs.fin < opJs.fin), 'hasil server = hitungan klien');
  assert(res.hasil.best === meJs.fin && res.hasil.rec === false && res.trek.best.us === meJs.fin, 'rekor pertama tersimpan');
  assert(res.trek.papan.length === 1 && res.trek.papan[0].nama === 'Kapten Trek' && res.trek.papan[0].aku === true, 'papan waktu');
  await H.expectError(x.send, /sudah dicatat/);
  // log rusak
  for (const bad of [null, 'x', [[1, 2]], [[5, 1], [4, 0]], [['a', 1]], [[1.5, 1]], [[999999, 1]], new Array(241).fill([0, 0])]) {
    x = await race('kapalmber', () => bad, 30); await H.expectError(x.send, /tidak terbaca/);
  }
  // milik orang lain / kedaluwarsa
  x = await race('yaptob', (seed) => human('jolt', seed, SKILL.biasa).log, 30);
  await H.sql(`update game.config set value = 'trekker,orangluar' where key = 'FiturPenguji'`);
  await H.expectError(() => other.call('api_trek', ['selesai', x.r.run, x.log]), /tidak ditemukan/);
  await H.sql(`update game.trek_runs set expires_at = now() - interval '1 second' where run_id = $1`, [x.r.run]);
  await H.expectError(x.send, /sudah padam/);
  // pemain jago dengan Mesin Jolt melawan Yaptob: kalah, dan tidak ada gold yang berubah
  const g0 = (await one(`select gold from game.players where player_id = $1`, [u.id])).gold;
  x = await race('yaptob', (seed) => human('jolt', seed, SKILL.jago).log, 30); res = await x.send();
  assert(res.hasil.win === false, 'Mesin Jolt tidak mengalahkan Yaptob');
  assert((await one(`select gold from game.players where player_id = $1`, [u.id])).gold === g0, 'tanpa efek ekonomi');
  assert((await H.sql(`select 1 from game.trek_runs where player_id = $1 and not done`, [u.id])).length === 0, 'tidak ada run menggantung');

  console.log(`0072 trektrek-an: ${n} simulasi JS = SQL, alur api_trek lulus.`);
})().catch((e) => { console.error(e); process.exit(1); });
