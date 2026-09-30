// Tes Modul D - Multiplayer (port dari /home/claude/gasemu/test_mp.js + test_timeout.js)
const assert = require('assert');

(async () => {
  const H = await require('./harness').create({ only: f => /^(0001|0005)/.test(f) });
  const ids = [];

  async function mkPlayer(username, name, arch, gold, city, opts = {}) {
    const u = await H.user(username);
    await H.sql(`insert into game.players(player_id, username, character_name, archetype, gold, appearance, meta)
                 values ($1, $2, $3, $4, $5, $6::jsonb, $7::jsonb)`,
      [u.id, username, name, arch, gold, opts.appearance ? JSON.stringify(opts.appearance) : null, opts.meta ? JSON.stringify(opts.meta) : null]);
    await H.sql('insert into game.character_stats(player_id, combat, luck) values ($1, $2, $3)', [u.id, opts.combat || 35, opts.luck || 15]);
    await H.sql('insert into game.ships(player_id) values ($1)', [u.id]);
    await H.sql('insert into game.player_location(player_id, city_id) values ($1, $2)', [u.id, city]);
    ids.push(u.id);
    return u;
  }
  // panggil API + pastikan tidak ada uuid pemain di jawaban
  async function call(c, name, ...args) {
    const r = await c.call(name, args);
    const s = JSON.stringify(r);
    for (const id of ids) assert(!s.includes(id), `uuid bocor di ${name}: ${s}`);
    return r;
  }
  const err = (fn, re) => H.expectError(fn, re);
  const goldOf = async u => Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  const invOf = async (u, item) => Number(((await H.sql('select qty from game.inventory where player_id = $1 and item_id = $2', [u.id, item]))[0] || { qty: 0 }).qty);

  const A = await mkPlayer('alice', 'Alice', 'merchant', 5000, 'sunda_empire', { appearance: { fem: 1, skin: 2 }, meta: { u: { first: 1, trade: 1 } } });
  const B = await mkPlayer('bob_99', 'Bob', 'pirate', 5000, 'sunda_empire');
  const C = await mkPlayer('cara', 'Cara', 'navigator', 3000, 'joungjava');

  // ---- auth
  const anon = await H.anon();
  await err(() => anon.call('api_mpPulse', [{}]), /AUTH_REQUIRED/);
  const nobody = await H.user('nobody');
  let r = await nobody.call('api_mpPulse', [{}]); assert(r.needState && r.t > 0, JSON.stringify(r));

  // ---- presence (pulse tanpa mp_touch -> diturunkan otomatis)
  let pa = await call(A, 'api_mpPulse', {});
  assert(pa.mePub && /^p[0-9a-f]{14}$/.test(pa.mePub), pa.mePub);
  assert.strictEqual(pa.here.length, 0, 'bob belum hadir');
  assert.deepStrictEqual(pa.me, { c: 'sunda_empire', sea: false });
  // kontrak mp_touch
  await H.sql('select game.mp_touch($1)', [B.id]);
  await H.sql('select game.mp_touch($1)', [C.id]);
  let pres = (await H.sql('select * from game.mp_presence where player_id = $1', [A.id]))[0];
  assert.strictEqual(pres.n, 'Alice'); assert.strictEqual(pres.b, 2); assert.deepStrictEqual(pres.f, { fem: 1, skin: 2 }); assert.strictEqual(pres.t, 1);
  pa = await call(A, 'api_mpPulse', {});
  assert(pa.here.length === 1 && pa.here[0].n === 'Bob', JSON.stringify(pa.here));
  assert.deepStrictEqual(Object.keys(pa.here[0]).sort(), ['a', 'b', 'c', 'dest', 'f', 'id', 'n', 's', 'sea', 't']);
  assert.strictEqual(pa.online, 3);
  assert(pa.onlineList.length === 3 && pa.onlineList[0].me === true && pa.onlineList[0].id === pa.mePub);
  const bobPub = pa.here[0].id;
  // mp_mark_sea
  await H.sql(`select game.mp_mark_sea($1, 'skitraw')`, [C.id]);
  pres = (await H.sql('select sea, dest from game.mp_presence where player_id = $1', [C.id]))[0];
  assert(pres.sea === true && pres.dest === 'skitraw');
  // Cara sedang berlayar
  await H.sql(`update game.player_location set destination_city_id = 'skitraw' where player_id = $1`, [C.id]);
  let pc = await call(C, 'api_mpPulse', {});
  assert(pc.me.sea === true && pc.here.length === 0 && pc.chat.c.length === 0);
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [C.id]);
  pc = await call(C, 'api_mpPulse', {});
  assert(pc.me.sea === false && pc.me.c === 'joungjava' && pc.here.length === 0);
  const caraPub = pc.mePub;

  // ---- chat
  await call(A, 'api_mpChat', 'city', 'Halo Bob!');
  await call(B, 'api_mpChat', 'global', 'Salam semua');
  let pb = await call(B, 'api_mpPulse', {});
  assert(pb.chat.c.length === 1 && pb.chat.g.length === 1, JSON.stringify(pb.chat));
  assert.strictEqual(pb.chat.c[0].tx, 'Halo Bob!'); assert.strictEqual(pb.chat.c[0].p, pa.mePub); assert.strictEqual(pb.chat.c[0].city, 'sunda_empire');
  assert(pb.chat.g[0].id === 1 && pb.chat.g[0].ts > 0 && pb.chat.g[0].n === 'Bob' && pb.chat.g[0].a === 'pirate');
  pc = await call(C, 'api_mpPulse', {});
  assert(pc.chat.c.length === 0 && pc.chat.g.length === 1, 'kanal kota terpisah');
  const alicePub = pb.here[0].id; assert.strictEqual(alicePub, pa.mePub);
  // since
  pb = await call(B, 'api_mpPulse', { g: 1, c: 1, ib: 0 }); assert(pb.chat.g.length === 0 && pb.chat.c.length === 0);
  // rate limit, pembersihan teks, pesan kosong
  await err(() => A.call('api_mpChat', ['city', 'lagi']), /Pelan-pelan, Kapten/);
  await H.sql('update game.mp_presence set last_chat_at = null');
  await err(() => A.call('api_mpChat', ['city', ' \n\t ']), /^Pesan kosong\.$/);
  let cm = await call(A, 'api_mpChat', 'city', '  Halo\u0007\n\n   dunia  ');
  assert.strictEqual(cm.msg.tx, 'Halo dunia'); assert.strictEqual(cm.msg.id, 2);
  await H.sql('update game.mp_presence set last_chat_at = null');
  cm = await call(A, 'api_mpChat', 'city', 'x'.repeat(200)); assert.strictEqual(cm.msg.tx.length, 140);
  // simpan 60 terakhir per kanal
  for (let i = 0; i < 65; i++) { await H.sql('update game.mp_presence set last_chat_at = null'); await call(B, 'api_mpChat', 'global', 'pesan ' + i); }
  const cnt = await H.sql(`select count(*)::int n, min(id) lo, max(id) hi from game.mp_chat where channel = 'g'`);
  assert(cnt[0].n === 60 && cnt[0].hi === 66 && cnt[0].lo === 7, JSON.stringify(cnt));
  pb = await call(B, 'api_mpPulse', {});
  assert(pb.chat.g.length === 30 && pb.chat.g[29].id === 66 && pb.chat.g[0].id === 37);
  await H.sql('update game.mp_presence set last_chat_at = null');
  // realtime broadcast
  const rt = await H.sql('select topic, event from realtime.sent');
  assert(rt.some(x => x.topic === 'chat:global' && x.event === 'chat') && rt.some(x => x.topic === 'chat:city:sunda_empire'));

  // ---- profil
  let prof = await call(A, 'api_mpProfile', bobPub);
  assert(prof.n === 'Bob' && prof.online === true && prof.id === bobPub && prof.a === 'pirate' && prof.c === 'sunda_empire');
  assert(prof.shipName === 'The Wandering Gull' && prof.t === 1 && prof.sea === false);
  assert.deepStrictEqual(prof.pvp, { w: 0, l: 0, d: 0, r: 1000 });
  prof = await call(B, 'api_mpProfile', alicePub); assert(prof.badges === 2 && prof.f.fem === 1);
  await err(() => A.call('api_mpProfile', ['pzzzz']), /Kapten itu sudah tidak terlihat di pelabuhan\./);
  console.log('presence/chat/profile ok,', pb.online, 'online');

  // ---- duel kapal dengan taruhan
  const ga0 = await goldOf(A), gb0 = await goldOf(B);
  await err(() => A.call('api_mpDuelChallenge', [alicePub, 0, 'naval']), /Tidak bisa menantang diri sendiri/);
  await err(() => A.call('api_mpDuelChallenge', [caraPub, 0, 'naval']), /^Cara tidak berada di pelabuhan yang sama\.$/);
  await err(() => A.call('api_mpDuelChallenge', [bobPub, 99999, 'naval']), /Gold-mu tidak cukup untuk taruhan 99999\./);
  let d = await call(A, 'api_mpDuelChallenge', bobPub, 500, 'naval');
  assert(d.status === 'invited' && d.challenger === true && d.maxRounds === 12 && d.you.id === alicePub && d.foe.id === bobPub, JSON.stringify(d));
  assert(!('hp' in d.you) && d.you.pick === null && d.winner === null && d.forfeit === null && d.pickDeadline === 0);
  await err(() => A.call('api_mpDuelChallenge', [bobPub, 0, 'naval']), /Kamu masih punya duel yang belum selesai\./);
  await err(() => C.call('api_mpDuelRespond', [d.id, true]), /Tantangan tidak ditemukan atau sudah kedaluwarsa\./);
  pb = await call(B, 'api_mpPulse', {});
  const inv = pb.inbox.filter(x => x.type === 'duel_invite')[0];
  assert(inv && inv.stake === 500 && inv.from === 'Alice' && inv.fromId === alicePub && inv.kind === 'naval' && inv.fa === 'merchant' && inv.ff.fem === 1 && inv.id && inv.ts > 0, JSON.stringify(inv));
  assert(pb.duel === null, 'target belum terikat duel sebelum menerima');
  pa = await call(A, 'api_mpPulse', {}); assert(pa.duel && pa.duel.status === 'invited' && pa.duel.challenger);
  d = await call(B, 'api_mpDuelRespond', inv.duelId, true);
  assert(d.status === 'active' && d.round === 1 && d.you.hp === d.you.maxHp && d.you.ammo === 3 && d.challenger === false, JSON.stringify(d));
  assert.strictEqual(d.you.maxHp, 80 + 20 + 20);
  assert(await goldOf(A) === ga0 - 500 && await goldOf(B) === gb0 - 500, 'escrow');
  pa = await call(A, 'api_mpPulse', {});
  assert(pa.inbox.some(x => x.type === 'duel_start' && x.from === 'Bob') && pa.duel.status === 'active');
  await err(() => A.call('api_mpDuelAct', [d.id, 1, 'dance']), /Taktik tidak dikenal\./);
  await err(() => C.call('api_mpDuelAct', [d.id, 1, 'fire']), /Duel tidak ditemukan\./);
  await err(() => C.call('api_mpDuelState', [d.id]), /Duel tidak ditemukan\./);
  await err(() => C.call('api_mpDuelChallenge', [bobPub, 0, 'naval']), /Kapten itu sedang tidak online|Bob sedang berduel/);
  const T = ['fire', 'evade', 'ram', 'brace', 'reload'];
  let guard = 0, last;
  while (d.status === 'active' && guard++ < 40) {
    const rd = d.round;
    const va = await call(A, 'api_mpDuelAct', d.id, rd, T[(rd * 7) % 5]);
    assert(va.you.picked && va.status === 'active' && va.pickDeadline > 0);
    const vbpre = await call(B, 'api_mpDuelState', d.id); assert(vbpre.foe.picked === true && !('pick' in vbpre.foe));
    d = await call(B, 'api_mpDuelAct', d.id, rd, T[(rd * 3 + 1) % 5]);
    last = d.last;
    assert(last && last.r === rd && typeof last.youDmg === 'number' && typeof last.foeNote === 'string');
  }
  assert(d.status === 'done', 'duel belum selesai');
  assert(['you', 'foe', 'draw'].includes(d.winner));
  const ga1 = await goldOf(A), gb1 = await goldOf(B);
  assert.strictEqual(ga1 + gb1, ga0 + gb0, 'gold conservation');
  if (d.winner === 'you') assert.strictEqual(gb1, gb0 + 500);
  if (d.winner === 'foe') assert.strictEqual(ga1, ga0 + 500);
  if (d.winner === 'draw') assert(ga1 === ga0 && gb1 === gb0);
  console.log('naval duel ok: winner(B)=', d.winner, 'rounds', d.round, 'hp', d.you.hp, d.foe.hp, 'last', JSON.stringify(last));
  pa = await call(A, 'api_mpPulse', {}); assert(!pa.duel || pa.duel.status === 'done');
  const logs = await H.sql('select message from game.player_log where player_id = $1', [A.id]);
  assert(logs.some(l => /duel kapal melawan Bob/.test(l.message)), JSON.stringify(logs));

  // ---- duel dadu
  d = await call(B, 'api_mpDuelChallenge', alicePub, 100, 'dice');
  pa = await call(A, 'api_mpPulse', {});
  const inv2 = pa.inbox.filter(x => x.type === 'duel_invite' && x.kind === 'dice')[0];
  d = await call(A, 'api_mpDuelRespond', inv2.duelId, true);
  assert(d.status === 'done' && d.dice && d.dice.you.length === 3 && d.dice.foe.length === 3, JSON.stringify(d));
  const sy = d.dice.you.reduce((x, y) => x + y), sf = d.dice.foe.reduce((x, y) => x + y);
  assert.strictEqual(d.winner, sy === sf ? 'draw' : (sy > sf ? 'you' : 'foe'));
  assert.strictEqual(await goldOf(A) + await goldOf(B), ga0 + gb0);
  console.log('dice duel ok', JSON.stringify(d.dice), d.winner);

  // ---- tolak
  d = await call(A, 'api_mpDuelChallenge', bobPub, 0, 'naval');
  d = await call(B, 'api_mpDuelRespond', d.id, false); assert.strictEqual(d.status, 'declined');
  pa = await call(A, 'api_mpPulse', {}); assert(pa.inbox.some(x => x.type === 'duel_declined' && x.from === 'Bob') && !pa.duel);
  // batalkan undangan sendiri
  d = await call(A, 'api_mpDuelChallenge', bobPub, 0, 'naval');
  d = await call(A, 'api_mpDuelForfeit', d.id); assert.strictEqual(d.status, 'cancelled');
  // menyerah di tengah duel
  d = await call(A, 'api_mpDuelChallenge', bobPub, 50, 'naval'); d = await call(B, 'api_mpDuelRespond', d.id, true);
  d = await call(A, 'api_mpDuelForfeit', d.id); assert(d.status === 'done' && d.winner === 'foe' && d.forfeit === 'you', JSON.stringify(d));
  assert.strictEqual(await goldOf(A) + await goldOf(B), ga0 + gb0);
  d = await call(A, 'api_mpDuelForfeit', d.id); assert.strictEqual(d.status, 'done');  // idempoten
  console.log('decline/forfeit ok');

  // ---- amunisi habis -> tembak jadi bertahan
  d = await call(A, 'api_mpDuelChallenge', bobPub, 0, 'naval'); d = await call(B, 'api_mpDuelRespond', d.id, true);
  for (let i = 0; i < 3; i++) { await call(A, 'api_mpDuelAct', d.id, d.round, 'fire'); d = await call(B, 'api_mpDuelAct', d.id, d.round, 'brace'); }
  let va = await call(A, 'api_mpDuelAct', d.id, d.round, 'fire');
  assert(va.you.ammo === 0 && va.you.pick === 'brace', JSON.stringify(va.you));
  va = await call(A, 'api_mpDuelAct', d.id, d.round - 1, 'fire'); assert.strictEqual(va.you.pick, 'brace'); // ronde lama diabaikan
  d = await call(B, 'api_mpDuelForfeit', d.id); assert(d.winner === 'foe' && d.forfeit === 'you');
  // 12 ronde maksimal -> seri, taruhan kembali
  const gA12 = await goldOf(A), gB12 = await goldOf(B);
  d = await call(A, 'api_mpDuelChallenge', bobPub, 100, 'naval'); d = await call(B, 'api_mpDuelRespond', d.id, true);
  while (d.status === 'active') { await call(A, 'api_mpDuelAct', d.id, d.round, 'brace'); d = await call(B, 'api_mpDuelAct', d.id, d.round, 'brace'); }
  assert(d.status === 'done' && d.round === 12 && d.winner === 'draw' && d.last.youDmg === 0, JSON.stringify(d));
  assert(await goldOf(A) === gA12 && await goldOf(B) === gB12, 'seri mengembalikan taruhan');
  console.log('ammo / max rounds ok');

  // ---- timeout (port test_timeout.js): lawan diam -> brace otomatis, 3x -> kalah
  let tot = await goldOf(A) + await goldOf(B);
  d = await call(A, 'api_mpDuelChallenge', bobPub, 200, 'naval'); d = await call(B, 'api_mpDuelRespond', d.id, true);
  assert.strictEqual(await goldOf(A) + await goldOf(B), tot - 400);
  for (let i = 0; i < 3; i++) {
    const v1 = await call(A, 'api_mpDuelAct', d.id, d.round, 'fire');
    d = await call(A, 'api_mpDuelState', d.id);
    assert.strictEqual(d.round, v1.round, 'belum lewat batas 25 detik');
    await H.sql('update game.mp_duels set pick_ts = pick_ts - 26000 where id = $1', [d.id]);
    d = await call(A, 'api_mpDuelState', d.id);
    console.log('  round', d.round, d.status, 'foe afk brace ->', d.last && d.last.foePick);
    if (i < 2) assert(d.status === 'active' && d.last.foePick === 'brace' && d.round === i + 2);
  }
  assert(d.status === 'done' && d.winner === 'you' && d.forfeit === 'foe', JSON.stringify(d));
  assert.strictEqual(await goldOf(A) + await goldOf(B), tot);
  const gAafk = await goldOf(A);
  // tidak dobel bayar
  await H.sql('update game.mp_duels set pick_ts = pick_ts - 99000, round_ts = round_ts - 99000 where id = $1', [d.id]);
  await call(A, 'api_mpDuelState', d.id); await call(B, 'api_mpDuelState', d.id); await call(A, 'api_mpPulse', {});
  assert.strictEqual(await goldOf(A), gAafk, 'tidak ada bayaran ganda');
  let db = await call(B, 'api_mpDuelState', d.id); assert(db.winner === 'foe' && db.forfeit === 'you');
  // keduanya diam 60 detik x3 -> seri, taruhan kembali (tick juga lewat pulse)
  tot = await goldOf(A) + await goldOf(B); const gAb = await goldOf(A);
  d = await call(A, 'api_mpDuelChallenge', bobPub, 300, 'naval'); d = await call(B, 'api_mpDuelRespond', d.id, true);
  for (let i = 0; i < 3; i++) {
    await H.sql('update game.mp_duels set round_ts = round_ts - 61000 where id = $1', [d.id]);
    const pr = await call(i === 1 ? B : A, 'api_mpPulse', {});
    d = pr.duel;
    if (i < 2) assert(d.status === 'active' && d.round === i + 2 && d.last.youPick === 'brace' && d.last.foePick === 'brace', JSON.stringify(d));
  }
  assert(d.status === 'done' && d.winner === 'draw' && d.forfeit === null, JSON.stringify(d));
  assert(await goldOf(A) === gAb && await goldOf(A) + await goldOf(B) === tot);
  // undangan kedaluwarsa 60 detik
  d = await call(A, 'api_mpDuelChallenge', bobPub, 0, 'naval');
  await H.sql('update game.mp_duels set created = created - 61000 where id = $1', [d.id]);
  await err(() => B.call('api_mpDuelRespond', [d.id, true]), /Tantangan sudah kedaluwarsa\./);
  d = await call(A, 'api_mpDuelState', d.id); assert.strictEqual(d.status, 'expired');
  d = await call(A, 'api_mpDuelChallenge', bobPub, 0, 'dice'); console.log('re-challenge after expiry ok', d.status);
  // undangan basi tidak memblokir tantangan baru
  await H.sql('update game.mp_duels set created = created - 61000 where id = $1', [d.id]);
  d = await call(A, 'api_mpDuelChallenge', bobPub, 0, 'naval'); assert.strictEqual(d.status, 'invited');
  await call(A, 'api_mpDuelForfeit', d.id);
  // offline (> 2 menit) tidak bisa ditantang
  await H.sql(`update game.mp_presence set ts = now() - interval '3 minutes' where player_id = $1`, [B.id]);
  await err(() => A.call('api_mpDuelChallenge', [bobPub, 0, 'naval']), /Kapten itu sedang tidak online\./);
  pa = await call(A, 'api_mpPulse', {}); assert(pa.here.length === 0 && pa.online === 2);
  prof = await call(A, 'api_mpProfile', bobPub); assert.strictEqual(prof.online, false);
  await call(B, 'api_mpPulse', {});
  pa = await call(A, 'api_mpPulse', {}); assert.strictEqual(pa.here.length, 1);
  const rtd = await H.sql(`select count(*)::int n from realtime.sent where topic = $1 and event = 'duel'`, ['player:' + bobPub]);
  const rti = await H.sql(`select count(*)::int n from realtime.sent where topic = $1 and event = 'inbox'`, ['player:' + bobPub]);
  assert(rtd[0].n > 0 && rti[0].n > 0);
  console.log('timeouts ok');

  // ---- bursa
  await H.sql(`insert into game.inventory(player_id, item_id, qty) values ($1, 'sugar', 10)`, [A.id]);
  await err(() => A.call('api_mpPostOrder', ['sugar', 0, 99]), /^Jumlah tidak valid\.$/);
  await err(() => A.call('api_mpPostOrder', ['sugar', 5, 0]), /^Harga tidak valid\.$/);
  await err(() => A.call('api_mpPostOrder', ['gold_bars', 5, 9]), /^Komoditas tidak dikenal\.$/);
  await err(() => A.call('api_mpPostOrder', ['sugar', 11, 9]), /^Barang di palka tidak cukup\.$/);
  let o = await call(A, 'api_mpPostOrder', 'sugar', 8, 99); assert(o.ok && o.orderId);
  assert.strictEqual(await invOf(A, 'sugar'), 2);
  let ol = await call(B, 'api_mpOrders');
  assert(ol.orders.length === 1 && !ol.orders[0].mine && ol.orders[0].seller === 'Alice' && ol.orders[0].name === 'Sugar' && ol.cityId === 'sunda_empire' && ol.inTransit === false, JSON.stringify(ol));
  assert(!('sellerId' in ol.orders[0]) && ol.orders[0].createdAt.endsWith('Z') && ol.orders[0].status === 'open');
  let olA = await call(A, 'api_mpOrders'); assert(olA.mine.length === 1 && olA.mine[0].mine === true && olA.orders[0].mine === true);
  let olC = await call(C, 'api_mpOrders'); assert(olC.orders.length === 0 && olC.cityId === 'joungjava');
  const gA = await goldOf(A), gB = await goldOf(B);
  let br = await call(B, 'api_mpBuyOrder', ol.orders[0].orderId, 5);
  assert(br.ok && br.qty === 5 && br.total === 495 && br.left === 3 && br.newGold === gB - 495, JSON.stringify(br));
  assert(await goldOf(A) === gA + 495 && await goldOf(B) === gB - 495 && await invOf(B, 'sugar') === 5);
  await err(() => A.call('api_mpBuyOrder', [ol.orders[0].orderId, 1]), /milikmu/);
  await err(() => C.call('api_mpBuyOrder', [ol.orders[0].orderId, 1]), /^Kamu harus berada di kota order ini\.$/);
  await err(() => B.call('api_mpBuyOrder', [ol.orders[0].orderId, 0]), /^Jumlah tidak valid\.$/);
  await H.sql('update game.ships set cargo = 5 where player_id = $1', [B.id]);
  await err(() => B.call('api_mpBuyOrder', [ol.orders[0].orderId, 1]), /^Palka tidak cukup\. Sisa ruang: 0\.$/);
  await H.sql('update game.ships set cargo = 30 where player_id = $1', [B.id]);
  await H.sql('update game.players set gold = 10 where player_id = $1', [B.id]);
  await err(() => B.call('api_mpBuyOrder', [ol.orders[0].orderId, 3]), /^Gold tidak cukup \(butuh 297\)\.$/);
  await H.sql('update game.players set gold = $2 where player_id = $1', [B.id, gB - 495]);
  pa = await call(A, 'api_mpPulse', {});
  const fil = pa.inbox.filter(x => x.type === 'order_filled')[0];
  assert(fil && fil.from === 'Bob' && fil.qty === 5 && fil.name === 'Sugar' && fil.gold === 495);
  await err(() => B.call('api_mpCancelOrder', [ol.orders[0].orderId]), /^Order tidak ditemukan\.$/);
  let cr = await call(A, 'api_mpCancelOrder', ol.orders[0].orderId); assert(cr.ok && cr.returnedTo === 'palka');
  assert.strictEqual(await invOf(A, 'sugar'), 5);
  await err(() => A.call('api_mpCancelOrder', [ol.orders[0].orderId]), /^Order sudah tidak aktif\.$/);
  await err(() => B.call('api_mpBuyOrder', [ol.orders[0].orderId, 1]), /^Order sudah tidak tersedia\.$/);
  ol = await call(B, 'api_mpOrders'); assert(ol.orders.length === 0);
  // maksimal 6 order aktif
  await H.sql(`update game.inventory set qty = 10 where player_id = $1 and item_id = 'sugar'`, [A.id]);
  const oids = [];
  for (let i = 0; i < 6; i++) oids.push((await call(A, 'api_mpPostOrder', 'sugar', 1, 50 + i)).orderId);
  await err(() => A.call('api_mpPostOrder', ['sugar', 1, 50]), /^Maksimal 6 order aktif\. Batalkan salah satu dulu\.$/);
  ol = await call(B, 'api_mpOrders'); assert(ol.orders.length === 6 && ol.orders[0].price === 50 && ol.orders[5].price === 55);
  // beli habis -> filled
  br = await call(B, 'api_mpBuyOrder', oids[0], 99); assert(br.qty === 1 && br.left === 0 && br.total === 50);
  assert.strictEqual((await H.sql('select status from game.mp_orders where order_id = $1', [oids[0]]))[0].status, 'filled');
  // penjual sedang berlayar tetap dikreditkan
  await H.sql(`update game.player_location set destination_city_id = 'joungjava' where player_id = $1`, [A.id]);
  const gAsea = await goldOf(A);
  br = await call(B, 'api_mpBuyOrder', oids[1], 1); assert.strictEqual(await goldOf(A), gAsea + 51);
  await err(() => A.call('api_mpPostOrder', ['sugar', 1, 50]), /^Pasang order saat kapal merapat\.$/);
  olA = await call(A, 'api_mpOrders'); assert(olA.inTransit === true && olA.mine.length === 4);
  // batal saat tidak di kota -> gudang
  cr = await call(A, 'api_mpCancelOrder', oids[2]); assert.strictEqual(cr.returnedTo, 'gudang sunda_empire');
  const wh = await H.sql(`select qty from game.warehouse where player_id = $1 and city_id = 'sunda_empire' and commodity_id = 'sugar'`, [A.id]);
  assert.strictEqual(wh[0].qty, 1);
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [A.id]);
  // di kota tapi palka penuh -> gudang
  await H.sql('update game.ships set cargo = 4 where player_id = $1', [A.id]);
  cr = await call(A, 'api_mpCancelOrder', oids[3]); assert.strictEqual(cr.returnedTo, 'gudang sunda_empire');
  await H.sql('update game.ships set cargo = 30 where player_id = $1', [A.id]);
  cr = await call(A, 'api_mpCancelOrder', oids[4]); assert.strictEqual(cr.returnedTo, 'palka');
  console.log('bursa ok, inbox A:', pa.inbox.map(x => x.type).join(','));

  // ---- hadiah
  const g1 = await goldOf(B), gA2 = await goldOf(A);
  const gr = await call(A, 'api_mpGift', bobPub, 123); assert(gr.ok && gr.newGold === gA2 - 123);
  assert(await goldOf(B) === g1 + 123 && await goldOf(A) === gA2 - 123);
  pb = await call(B, 'api_mpPulse', {}); assert(pb.inbox.some(x => x.type === 'gift' && x.gold === 123 && x.from === 'Alice'));
  await err(() => A.call('api_mpGift', [alicePub, 5]), /^Tidak bisa mengirim ke diri sendiri\.$/);
  await err(() => A.call('api_mpGift', [bobPub, 0]), /^Jumlah tidak valid\.$/);
  await err(() => A.call('api_mpGift', [bobPub, 999999]), /^Gold tidak cukup\.$/);
  await err(() => A.call('api_mpGift', ['nope', 5]), /sudah tidak terlihat/);
  // inbox since
  const lastIb = pb.inbox[pb.inbox.length - 1].ts;
  pb = await call(B, 'api_mpPulse', { ib: lastIb }); assert.strictEqual(pb.inbox.length, 0);
  console.log('gift ok');

  // ---- mini game: mancing (dasar; uji lengkap di 0013_fishing.test.js)
  const c = await call(A, 'api_mgFishCast');
  assert(c.castId && c.waitMs >= 1500 && c.waitMs <= 5200 && c.left === 20, JSON.stringify(c));
  await err(() => A.call('api_mgFishCast', []), /^Umpan belum siap - tunggu sebentar\.$/);
  await err(() => A.call('api_mgFishReel', ['salah', true]), /^Umpan sudah lepas\. Lempar lagi\.$/);
  await H.sql(`update game.mp_daily set n = 20 where player_id = $1 and kind = 'fish'`, [A.id]);
  await H.sql(`insert into game.mp_daily(player_id, kind, game_day, n) select $1, 'fish', game.mp_day(), 20 where not exists (select 1 from game.mp_daily where player_id = $1 and kind = 'fish')`, [A.id]);
  await H.sql('update game.mp_fish set cooldown_until = 0');
  await err(() => A.call('api_mgFishCast', []), /^Ikan di dermaga sudah jinak hari ini\. Coba lagi besok \(hari-game berikutnya\)\.$/);
  await H.sql(`update game.player_location set destination_city_id = 'joungjava' where player_id = $1`, [B.id]);
  await err(() => B.call('api_mgFishCast', []), /^Mancing di dermaga saat kapal merapat\.$/);
  await H.sql(`update game.player_location set destination_city_id = null where player_id = $1`, [B.id]);

  // ---- mini game: dadu besar/kecil
  const gD = await goldOf(A);
  const dd = await call(A, 'api_mgDice', 50, 'besar');
  assert(dd.dice.length === 3 && dd.sum === dd.dice[0] + dd.dice[1] + dd.dice[2] && dd.left === 39);
  assert.strictEqual(dd.side, dd.sum >= 11 ? 'besar' : 'kecil');
  assert.strictEqual(dd.triple, dd.dice[0] === dd.dice[1] && dd.dice[1] === dd.dice[2]);
  assert.strictEqual(dd.win, !dd.triple && dd.side === 'besar');
  assert(dd.delta === (dd.win ? 50 : -50) && dd.newGold === gD + dd.delta && await goldOf(A) === dd.newGold);
  await err(() => A.call('api_mgDice', [5, 'besar']), /^Taruhan minimal 10 gold\.$/);
  await err(() => A.call('api_mgDice', [50, 'tengah']), /^Pilih Besar atau Kecil\.$/);
  const big = await call(A, 'api_mgDice', 999999, 'kecil'); assert(Math.abs(big.delta) === 5000 && big.left === 38);
  await H.sql('update game.players set gold = 20 where player_id = $1', [C.id]);
  await err(() => C.call('api_mgDice', [30, 'kecil']), /^Gold tidak cukup untuk taruhan itu\.$/);
  await H.sql(`update game.mp_daily set n = 40 where player_id = $1 and kind = 'dice'`, [A.id]);
  await err(() => A.call('api_mgDice', [50, 'besar']), /^Bandar lapau sudah tutup meja untukmu hari ini\.$/);
  // 3 kembar selalu kalah: paksa lewat random seed tidak mungkin -> uji logika dengan banyak lemparan
  await H.sql('update game.players set gold = 1000000 where player_id = $1', [C.id]);
  let sawTriple = false;
  for (let i = 0; i < 38; i++) { const x = await call(C, 'api_mgDice', 10, 'besar'); if (x.triple) { sawTriple = true; assert(!x.win && x.delta === -10); } }
  console.log('minigames ok: dice', dd.dice, dd.win, 'triple seen', sawTriple);

  // ---- papan PvP
  const board = await call(A, 'api_mpPvpBoard');
  assert(board.length === 2 && board[0].r >= board[1].r && board.every(x => ['n', 'a', 'w', 'l', 'd', 'r'].every(k => k in x)), JSON.stringify(board));
  const recs = await H.sql('select sum(w)::int w, sum(l)::int l, sum(d)::int d, sum(r)::int r from game.mp_pvp');
  assert.strictEqual(recs[0].w, recs[0].l);
  prof = await call(B, 'api_mpProfile', alicePub); assert(prof.pvp.w + prof.pvp.l + prof.pvp.d >= 7, JSON.stringify(prof.pvp));
  console.log('pvp board', JSON.stringify(board));

  // ---- migrasi idempoten
  await H.db.exec(require('fs').readFileSync(require('path').join(__dirname, '..', 'supabase', 'migrations', '0005_multiplayer.sql'), 'utf8'));
  assert.strictEqual((await H.sql('select count(*)::int n from game.mp_fish_types'))[0].n, 8);

  console.log('\nMULTIPLAYER TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
