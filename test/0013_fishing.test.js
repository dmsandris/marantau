// Mancing v2: lempar (jarak/umpan), anti-curang durasi duel, hasil, buku ikan, rekor, joran.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const A = await H.user('pancing_a'); await A.call('api_createCharacter', ['Kapten Kail', 'explorer']);
  const B = await H.user('pancing_b'); await B.call('api_createCharacter', ['Kapten Jala', 'merchant']);
  const gold = async u => Number((await H.sql('select gold from game.players where player_id = $1', [u.id]))[0].gold);
  const ready = async () => { await H.sql('update game.mp_fish set cooldown_until = 0'); };
  const pass = async u => H.sql('update game.mp_fish set t0 = t0 - 60000 where player_id = $1', [u.id]);

  const info = await A.call('api_mgFishInfo', []);
  assert(info.left === 20 && info.rod === 0 && info.baits.length === 4 && info.rods.length === 3 && info.total === 14 && info.found === 0, JSON.stringify(info));

  // umpan berbayar memotong gold; nama ikan TIDAK dikirim saat melempar
  let g0 = await gold(A);
  const c = await A.call('api_mgFishCast', [0.9, 'kilau', true]);
  assert(c.baitCost === 150 && c.newGold === g0 - 150 && await gold(A) === g0 - 150, 'biaya umpan');
  assert(!c.fish.name && !c.fish.id && c.fight.stam > 0 && c.fight.pow > 0 && c.fight.size > 0 && c.fight.reactMs > 0 && c.depth === 2, 'nama tersembunyi ' + JSON.stringify(c));
  // tarik terlalu cepat (sebelum gigitan + durasi duel minimum) = tidak sah
  const early = await A.call('api_mgFishReel', [c.castId, 'caught', 1]);
  assert(early.caught === false && early.reason === 'invalid' && early.fish.name, 'anti-curang ' + JSON.stringify(early));
  await H.expectError(() => A.call('api_mgFishReel', [c.castId, 'caught', 1]), /Umpan sudah lepas/);

  // tangkapan sah
  await ready(); g0 = await gold(A);
  const c2 = await A.call('api_mgFishCast', [0.1, 'cacing', false]);
  assert(c2.baitCost === 0 && c2.depth === 0, 'cacing gratis');
  await pass(A);
  const r = await A.call('api_mgFishReel', [c2.castId, 'caught', 0.9]);
  assert(r.caught && r.gold >= 1 && r.kg > 0 && r.fish.name && r.firstCatch === true && r.found === 1 && r.left === 19, JSON.stringify(r));
  assert(await gold(A) === g0 + r.gold && r.newGold === g0 + r.gold, 'gold bertambah');

  // lepas: alasan dikembalikan + ikan diungkap (penasaran)
  await ready();
  const c3 = await A.call('api_mgFishCast', [0.5, 'udang', false]);
  const lost = await A.call('api_mgFishReel', [c3.castId, 'snap', 0]);
  assert(lost.caught === false && lost.reason === 'snap' && lost.fish.name && lost.kg > 0, 'lepas ' + JSON.stringify(lost));

  // buku ikan + rekor dermaga
  const book = await A.call('api_mgFishBook', []);
  assert(book.length === 14, 'buku 14');
  const got = book.filter(b => b.found);
  assert(got.length === 1 && got[0].name === r.fish.name && got[0].n === 1 && Number(got[0].bestKg) === Number(r.kg), 'buku isi ' + JSON.stringify(got));
  assert(book.filter(b => !b.found).every(b => b.name === null && b.hint), 'spesies belum ditemukan disembunyikan');
  // B menangkap spesies yang sama lebih berat -> rekor dermaga pindah
  await H.sql(`insert into game.mp_fish(player_id) values ($1) on conflict do nothing`, [B.id]);
  const cb = await B.call('api_mgFishCast', [0.1, 'cacing', false]);
  await H.sql(`update game.mp_fish set fish = $2, kg = 999, t0 = t0 - 60000 where player_id = $1`, [B.id, r.fish.id]);
  const rb = await B.call('api_mgFishReel', [cb.castId, 'caught', 0]);
  assert(rb.caught && rb.fish.id === r.fish.id && (rb.globalRecord === (r.fish.id !== 'sepatu')), 'rekor global ' + JSON.stringify(rb));
  if (r.fish.id !== 'sepatu') {
    const bk2 = (await A.call('api_mgFishBook', [])).filter(b => b.id === r.fish.id)[0];
    assert(bk2.record && bk2.record.n === 'Kapten Jala' && bk2.record.me === false, 'pemegang rekor ' + JSON.stringify(bk2));
  }

  // jarak memengaruhi kedalaman: lemparan dekat tidak pernah memberi ikan dalam (tuna/hiu/dewa jarang sekali)
  const near = {}, far = {};
  await H.sql('update game.players set gold = 1000000 where player_id = $1', [A.id]);
  for (let i = 0; i < 120; i++) {
    await ready(); await H.sql('delete from game.mp_daily where player_id = $1', [A.id]);
    await A.call('api_mgFishCast', [0.05, 'cacing', false]); const f = (await H.sql('select fish from game.mp_fish where player_id = $1', [A.id]))[0].fish; near[f] = (near[f] || 0) + 1;
    await ready();
    await A.call('api_mgFishCast', [0.98, 'kilau', true]); const g = (await H.sql('select fish from game.mp_fish where player_id = $1', [A.id]))[0].fish; far[g] = (far[g] || 0) + 1;
  }
  const deepNear = (near.tuna || 0) + (near.dewa || 0) + (near.kerapu || 0);
  const smallFar = (far.teri || 0) + (far.sepatu || 0);
  assert(deepNear <= 3 && smallFar <= 3 && (near.teri || 0) > 20, 'distribusi dekat ' + JSON.stringify(near) + ' jauh ' + JSON.stringify(far));
  // spesies kota: pari/hiu tidak muncul di Sunda Empire
  assert(!near.pari && !far.pari && !far.hiu, 'spesies khusus kota');

  // umpan tidak dikenal & gold kurang
  await ready();
  await H.expectError(() => A.call('api_mgFishCast', [0.5, 'dinamit', false]), /Umpan tidak dikenal/);
  await H.sql('update game.players set gold = 10 where player_id = $1', [B.id]); await H.sql('update game.mp_fish set cooldown_until = 0');
  await H.expectError(() => B.call('api_mgFishCast', [0.5, 'kilau', false]), /Gold tidak cukup untuk umpan/);

  // joran: berurutan, bayar, memperpendek durasi minimum
  await H.expectError(() => A.call('api_mgFishBuyRod', [2]), /berurutan/);
  g0 = await gold(A);
  const rod = await A.call('api_mgFishBuyRod', [1]);
  assert(rod.rod === 1 && await gold(A) === g0 - 2500, 'beli joran');
  assert((await A.call('api_mgFishInfo', [])).rod === 1, 'joran tersimpan');
  await H.expectError(() => B.call('api_mgFishBuyRod', [1]), /Gold tidak cukup/);

  // tangkapan legendaris diumumkan di kanal dunia
  await ready(); await H.sql('delete from game.mp_daily where player_id = $1', [A.id]);
  await A.call('api_getGameState', [null]);
  const cl = await A.call('api_mgFishCast', [0.95, 'kilau', false]);
  await H.sql(`update game.mp_fish set fish = 'dewa', kg = 12.5, t0 = t0 - 60000 where player_id = $1`, [A.id]);
  const rl = await A.call('api_mgFishReel', [cl.castId, 'caught', 0.5]);
  assert(rl.caught && rl.fish.rarity === 7, 'dewa');
  const chat = await H.sql(`select msg from game.mp_chat where channel = 'g' order by id desc limit 1`);
  assert(chat.length && chat[0].msg.p === 'sys' && /Ikan Dewa 12.5 kg/.test(chat[0].msg.tx), 'chat dunia ' + JSON.stringify(chat));
  const anon = await H.anon();
  await H.expectError(() => anon.call('api_mgFishBook', []), /AUTH_REQUIRED|permission/);
  console.log('FISHING TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
