// Tide v47 · Perburuan Tony: Kabut Abu-abu (hanya saat lobi Marlya terbuka, hari Rabu), lobi 2-4 kapten
// (20 Tanda Jasa, 10 Mesiu), serbuan memakai mesin Quest 9 (kind 'tony'), Tony kabur di 10% -> jarahan 50% harta
// periode (70% porsi damage, 30% rata), lobi ditutup & harta kembali 0.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const bot = require('./raidbot');
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const force = v => H.sql(`update game.config set value = $1 where key = 'TonyHuntForce'`, [v]);
  const gold = async u => Number((await one('select gold from game.players where player_id = $1', [u.pid])).gold);
  const qty = async (u, id) => Number((await one('select game.item_qty($1, $2) q', [u.pid, id])).q);

  const kapten = async (name, opt) => {
    opt = opt || {};
    const c = await H.user(name); await c.call('api_createCharacter', ['Kapten ' + name, 'pirate']);
    const pid = c.id;
    await H.sql(`update game.players set gold = 100000 where player_id = $1`, [pid]);
    await H.sql(`update game.ships set tier = 'IV', cargo = 1000, condition = 100 where player_id = $1`, [pid]);
    await H.sql(`update game.character_stats set combat = 60 where player_id = $1`, [pid]);
    if (opt.badges !== 0) await H.sql(`update game.players set meta = jsonb_build_object('u', (select jsonb_object_agg('b' || g, 1) from generate_series(1, $2::int) g)) where player_id = $1`, [pid, opt.badges || 22]);
    await H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, opt.city || 'kabut_abu']);
    await H.sql(`select game.adjust_inventory($1, 'mesiu', 40)`, [pid]);
    const pub = (await c.call('api_mpPulse', [{}])).mePub;
    return { c, pid, pub, name };
  };
  const hunt = (u, a) => u.c.call('api_tonyHunt', a);

  // --- hari Rabu (WIB) & Kabut Abu-abu ------------------------------------------------
  await force('');
  const dow = Number((await one(`select extract(isodow from (now() at time zone 'Asia/Jakarta'))::int d`)).d);
  const shiftDays = ((3 - dow) + 7) % 7;
  await H.sql(`update game.config set value = $1 where key = 'DtClockOffset'`, [String(shiftDays * 86400000)]);
  ok((await one(`select game.th_rabu() r`)).r === true, 'hari Rabu WIB terdeteksi');
  await H.sql(`update game.config set value = $1 where key = 'DtClockOffset'`, [String((shiftDays + 1) * 86400000)]);
  ok((await one(`select game.th_rabu() r`)).r === false, 'Kamis bukan hari perburuan');
  await H.sql(`update game.config set value = '0' where key = 'DtClockOffset'`);

  const A = await kapten('tha'), B = await kapten('thb'), C = await kapten('thc'), D = await kapten('thd', { city: 'skitraw' });
  const P = await kapten('thpemula', { badges: 5 });
  await force('off');
  let s = (await A.c.call('api_getGameState', [null]));
  ok(s.tonyHunt && s.tonyHunt.open === false && !(s.unlocks || []).includes('kabut_abu'), 'bukan hari Rabu: Kabut Abu-abu tersembunyi');
  ok(!JSON.stringify(s.tonyHunt).match(/rabu|wednesday|hadiah|pool/i), 'status tidak membocorkan jadwal/hadiah');
  await H.expectError(() => D.c.call('api_setSail', ['kabut_abu']), /tidak dikenali/);
  await force('on');
  s = await D.c.call('api_getGameState', [null]);
  ok(s.tonyHunt.open === true && (s.unlocks || []).includes('kabut_abu'), 'lobi Marlya terbuka: Kabut Abu-abu tampil');
  ok((await one(`select game.spot_city('kabut_abu') s`)).s === true, 'Kabut Abu-abu titik laut (tanpa pasar/bajak laut)');

  // --- harta Tony periode -------------------------------------------------------------
  await H.sql(`insert into game.tony_victims(raid_id, player_id, result, gold_taken, cargo_value) values
    (1, $1, 'serah', 600000, 400000), (1, $2, 'menang', 0, 0)`, [D.pid, A.pid]);
  ok(Number((await one(`select game.th_harta() h`)).h) === 1000000, 'harta periode = gold + muatan (tanpa hasil menang)');
  ok((await A.c.call('api_getGameState', [null])).tonyHunt.harta === 1000000, 'harta dikirim ke klien (untuk gosip Marlya)');

  // --- syarat & lobi ------------------------------------------------------------------
  await H.expectError(() => hunt(P, ['open']), /belum mengenal namamu/);
  await H.expectError(() => hunt(D, ['open']), /Kabut Abu-abu/);
  let r = (await hunt(A, ['open'])).raid;
  ok(r.status === 'lobby' && r.kind === 'tony' && r.members.length === 1, 'Papan Armada Marlya dibuka');
  const chat = await one(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`);
  ok(/Papan Armada Marlya \(1\/4\)/.test(chat.msg.tx) && chat.msg.n === 'Pelikan Marlya' && !/gold|hadiah/i.test(chat.msg.tx), 'pengumuman lobi tanpa hadiah');
  ok(Number((await one(`select count(*)::int n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'th_open'`, [B.pid])).n) === 1, 'notifikasi kapten layak');
  ok(Number((await one(`select count(*)::int n from game.mp_inbox where player_id = $1 and item ->> 'type' = 'th_open'`, [P.pid])).n) === 0, 'pemula tidak dinotifikasi');
  ok((await A.c.call('api_dtRaid', ['board'])).board.length === 0, 'lobi Tony tidak muncul di Papan Armada Quest 9');
  r = (await hunt(B, ['join', r.id])).raid;
  ok(r.members.length === 2, 'Bravo bergabung');
  await H.expectError(() => A.c.call('api_setSail', ['skitraw']), /Papan Armada Marlya/);
  const m0 = await qty(A, 'mesiu');
  await hunt(A, ['ready', true]);
  ok((await qty(A, 'mesiu')) === m0 - 10, 'setor 10 Mesiu');
  await hunt(A, ['ready', false]);
  ok((await qty(A, 'mesiu')) === m0, 'batal siap: Mesiu kembali');
  await H.sql(`select game.adjust_inventory($1, 'mesiu', -38)`, [B.pid]);
  await H.expectError(() => hunt(B, ['ready', true]), /kurang 8 Mesiu/);
  await H.sql(`select game.adjust_inventory($1, 'mesiu', 38)`, [B.pid]);
  await hunt(A, ['ready', true]); await hunt(B, ['ready', true]);
  await H.expectError(() => hunt(B, ['depart']), /pembuka armada/);

  // lobi kedua (akan ditutup saat Tony kabur, Mesiu kembali)
  await H.sql(`update game.player_location set city_id = 'kabut_abu' where player_id = $1`, [D.pid]);
  const r2 = (await hunt(C, ['open'])).raid;
  await hunt(D, ['join', r2.id]); await hunt(C, ['ready', true]);
  const cM = await qty(C, 'mesiu');

  // --- serbuan berjalan (mesin Quest 9, bot) -----------------------------------------
  r = (await hunt(A, ['depart'])).raid;
  ok(r.status === 'active' && r.st.boss.phase === 1 && r.st.boss.max === Math.round(1100 * 0.64) && r.st.boss.shield > 0 && !r.st.pearl, 'Angkat Sauh: armada Tony (2 kapal), tanpa Black Pearl');
  ok(r.k && r.k.fleeAt === 0.1, 'konstanta klien');
  await H.expectError(() => A.c.call('api_setSail', ['skitraw']), /menyerbu Tony/);
  // satu giliran: semua mengunci
  r = (await hunt(A, ['act', 1, { rud: 1, sails: 1, fl: true, fr: false, ammo: 'chain' }])).raid;
  r = (await hunt(B, ['act', 1, { rud: -1, sails: 1, fl: false, fr: true, ammo: 'ball' }])).raid;
  ok(r.round === 2 && r.ev && r.ev.r === 1 && r.ev.tracks[A.pub].length === 12 && r.ev.pearl === null, 'giliran 1 dihitung');
  // fase: paksa lambung ke ambang -> Pengait & Murka
  await H.sql(`update game.mp_raids set st = jsonb_set(jsonb_set(jsonb_set(st, '{boss,shield}', '0'), '{boss,phase}', '2'), '{boss,hull}', to_jsonb((st -> 'boss' ->> 'max')::float8 * 0.56)) where id = $1`, [r.id]);
  await H.sql(`update game.mp_raids set stats = '{}'::jsonb where id = $1`, [r.id]);
  let guard = 0, sawHook = false, sawP4 = false;
  while (guard++ < 30) {
    const v = (await hunt(A, ['view', r.id])).raid;
    if (v.status !== 'active' || v.phase !== 'plan') { r = v; break; }
    for (const u of [A, B]) {
      const vv = (await hunt(u, ['view', r.id])).raid;
      if (vv.status !== 'active' || vv.phase !== 'plan') continue;
      const me = vv.st.ships[vv.me]; if (!me || !me.alive) continue;
      r = (await hunt(u, ['act', vv.round, bot.plan(me, vv.st.boss, 1, 1, null, vv.st.w), r.id])).raid;
    }
    if (r.ev && r.ev.evs) { if (r.ev.evs.some(e => e.k === 'hooked')) sawHook = true; if (r.ev.evs.some(e => e.k === 'phase' && e.p === 4)) sawP4 = true; }
    // dorong ke Pertarungan Terakhir
    await H.sql(`update game.mp_raids set st = jsonb_set(st, '{boss,hull}', to_jsonb(greatest((st -> 'boss' ->> 'max')::float8 * 0.2, (st -> 'boss' ->> 'hull')::float8 - 40))) where id = $1 and status = 'active' and phase = 'plan'`, [r.id]);
    await H.sql(`update game.config set value = (value::bigint + 3500)::text where key = 'DtClockOffset'`);
  }
  ok(sawHook, 'fase Pengait: kapal tertambat');
  ok(sawP4, 'fase Murka Tony');
  r = (await hunt(A, ['view', r.id])).raid;
  ok(r.status === 'active' && r.phase === 'final', 'Pertarungan Terakhir dimulai di <= 30%');

  // menang di Pertarungan Terakhir: lambung Tony ke 10% -> kabur
  const gA = await gold(A), gB = await gold(B);
  await H.sql(`update game.mp_raids set stats = '{"${A.pub}": {"hull": 300}, "${B.pub}": {"hull": 100}}'::jsonb,
     st = jsonb_set(st, '{boss,hull}', to_jsonb((st -> 'boss' ->> 'max')::float8 * 0.105)) where id = $1`, [r.id]);
  await H.sql(`update game.config set value = (value::bigint + $1)::text where key = 'DtClockOffset'`, [Math.max(0, r.finalTs - r.t) + 100]);
  // satu tembakan realtime (atau serbu geladak) menurunkan lambung di bawah 10%
  let rt, tries = 0;
  do {
    const vv = (await hunt(A, ['view', r.id])).raid;
    if (vv.status !== 'active') break;
    const bx = vv.st.boss.x, by = vv.st.boss.y;
    rt = await hunt(A, ['rt', { x: bx - 80, y: by, h: 0, v: 0, sails: 1, ammo: 'ball' }, [{ k: 'b', sc: 3 }, { k: 'f', s: 1, a: 'ball' }], 0, r.id]);
    await H.sql(`update game.config set value = (value::bigint + 9000)::text where key = 'DtClockOffset'`);
  } while (rt.status === 'active' && tries++ < 6);
  r = (await hunt(A, ['view', r.id])).raid;
  ok(r.status === 'done' && r.result === 'win', 'Tony kabur di 10%: ' + JSON.stringify([r.status, r.result, r.st.boss.hull]));

  // pembagian: pool 500.000 -> 70% (350.000) porsi damage, 30% (150.000) rata
  const loot = Object.fromEntries(r.card.rows.map(x => [x.pub, x.loot]));
  const dA = Number(r.stats[A.pub].hull) + Number(r.stats[A.pub].board || 0) + Number(r.stats[A.pub].shield || 0);
  const dB = Number(r.stats[B.pub].hull) + Number(r.stats[B.pub].board || 0) + Number(r.stats[B.pub].shield || 0);
  const expA = Math.floor(350000 * dA / (dA + dB)) + 75000, expB = Math.floor(350000 * dB / (dA + dB)) + 75000;
  ok(Math.abs(loot[A.pub] - expA) <= 1 && Math.abs(loot[B.pub] - expB) <= 1, 'pembagian 70/30: ' + JSON.stringify([loot, expA, expB]));
  ok((await gold(A)) === gA + loot[A.pub] && (await gold(B)) === gB + loot[B.pub], 'gold masuk');
  ok(loot[A.pub] + loot[B.pub] <= 500000 && loot[A.pub] + loot[B.pub] >= 499998, '50% harta saja yang dibagi');
  const hrow = await one(`select * from game.tony_hunts order by id desc limit 1`);
  ok(Number(hrow.harta) === 1000000 && Number(hrow.pool) === 500000 && hrow.raid_id === r.id, 'catatan perburuan');
  const kabur = await one(`select msg from game.mp_chat where channel = 'g' and msg ->> 'tx' like 'Tony and Gank kabur%' order by id desc limit 1`);
  ok(kabur && /Kapten tha/.test(kabur.msg.tx) && !/\d{3}/.test(kabur.msg.tx), 'chat Dunia: Tony kabur, tanpa angka');

  // setelah kabur: lobi ditutup, Kabut Abu-abu hilang, harta dihitung dari 0
  ok((await one(`select game.th_open() o`)).o === false, 'lobi Marlya ditutup');
  s = await D.c.call('api_getGameState', [null]);
  ok(s.tonyHunt.open === false && s.tonyHunt.kabur === true && !(s.unlocks || []).includes('kabut_abu'), 'Kabut Abu-abu hilang dari peta');
  ok(s.tonyHunt.harta === 0, 'harta kembali 0');
  const r2v = await one(`select status from game.mp_raids where id = $1`, [r2.id]);
  ok(r2v.status === 'cancelled' && (await qty(C, 'mesiu')) === cM + 10, 'lobi lain bubar, Mesiu kembali');
  await H.expectError(() => hunt(C, ['open']), /terbang pulang/);
  await H.sql(`insert into game.tony_victims(raid_id, player_id, result, gold_taken, cargo_value, at) values (2, $1, 'kalah', 1000, 500, now() + interval '1 second')`, [D.pid]);
  ok(Number((await one(`select game.th_harta() h`)).h) === 1500, 'perampokan baru masuk periode berikutnya');

  // kapal menuju Kabut Abu-abu setelah ditutup: berbalik ke asal
  await H.sql(`update game.player_location set city_id = 'skitraw', destination_city_id = 'kabut_abu', depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second', pending_encounter = null where player_id = $1`, [D.pid]);
  await D.c.call('api_pollVoyage', []);
  ok((await one(`select city_id from game.player_location where player_id = $1`, [D.pid])).city_id === 'skitraw', 'kabut tertutup: kapal berbalik');

  // --- hari Rabu berikutnya: kalah = tidak dirampas, lobi tetap terbuka -------------
  await H.sql(`delete from game.tony_hunts`);
  for (const u of [A, B]) await H.sql(`update game.player_location set city_id = 'kabut_abu' where player_id = $1`, [u.pid]);
  r = (await hunt(A, ['open'])).raid; await hunt(B, ['join', r.id]);
  await hunt(A, ['ready', true]); await hunt(B, ['ready', true]);
  r = (await hunt(A, ['depart'])).raid;
  const gA2 = await gold(A), cargoA = Number((await one(`select coalesce(sum(qty),0)::int n from game.inventory where player_id = $1`, [A.pid])).n);
  await hunt(A, ['flee']); r = (await hunt(B, ['flee'])).raid;
  ok(r.status === 'done' && r.result === 'loss', 'semua mundur = kalah');
  ok((await gold(A)) === gA2 && Number((await one(`select coalesce(sum(qty),0)::int n from game.inventory where player_id = $1`, [A.pid])).n) === cargoA, 'kalah tidak dirampas');
  ok((await one(`select game.th_open() o`)).o === true && Number((await one(`select count(*)::int n from game.tony_hunts`)).n) === 0, 'kalah: lobi tetap terbuka, Tony tidak kabur');

  // --- satu serbuan bot penuh (mesin berjalan sampai selesai tanpa error) ------------
  for (const u of [A, B, C]) await H.sql(`update game.player_location set city_id = 'kabut_abu' where player_id = $1; update game.ships set condition = 100 where player_id = $1`, [u.pid]).catch(async () => {
    await H.sql(`update game.player_location set city_id = 'kabut_abu' where player_id = $1`, [u.pid]); await H.sql(`update game.ships set condition = 100 where player_id = $1`, [u.pid]);
  });
  r = (await hunt(A, ['open'])).raid; await hunt(B, ['join', r.id]); await hunt(C, ['join', r.id]);
  for (const u of [A, B, C]) await hunt(u, ['ready', true]);
  await hunt(A, ['depart']);
  const res = await bot.runRaid(H, [A, B, C].map(u => ({ c: u.c, pub: u.pub })), { skill: 0.9, api: 'api_tonyHunt' });
  ok(res.status === 'done' && (res.result === 'win' || res.result === 'loss') && res.card && res.card.kind === 'tony', 'serbuan bot selesai: ' + res.result);

  // --- era lampau Saga 3: tidak ada Tony ----------------------------------------------
  await H.sql(`alter function game.pasir_era(uuid) rename to pasir_era_asli`);
  await H.sql(`create function game.pasir_era(p uuid) returns text language sql as $f$ select 'lampau'::text $f$`);
  ok((await one(`select game.th_state($1) s`, [A.pid])).s === null, 'era lampau: tanpa Perburuan');
  await H.sql(`drop function game.pasir_era(uuid)`);
  await H.sql(`alter function game.pasir_era_asli(uuid) rename to pasir_era`);

  console.log('PERBURUAN TONY TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
