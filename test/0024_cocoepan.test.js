// Saga 2 · Quest 6 "Bunga yang Tak Pernah Layu": pemicu (2 hari game setelah Quest 5 + bank 1 juta)
// -> pinjaman ke Coco Epan (ditahan 10 hari game) -> Peti Bantuan IKN -> Mata Syahbandar ->
// bunga melati -> Gading Island (terbuka) -> Stumpy -> makam -> ikan legenda -> mural ->
// pelunasan 2x -> adu gasing -> surat ke Marlya.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('cocoepan1'); await u.call('api_createCharacter', ['Pembawa Bunga', 'merchant']);
  const pid = u.id;
  const go = c => H.sql(`update game.player_location set city_id = $2, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = $1`, [pid, c]);
  const city = async () => (await H.sql('select city_id from game.player_location where player_id = $1', [pid]))[0].city_id;
  const cb = a => u.call('api_cocoepan', a);
  const st = async () => (await u.call('api_cocoepan', ['status'])).cocoepan;
  const gold = async () => Number((await H.sql('select gold from game.players where player_id = $1', [pid]))[0].gold);
  const bank = async () => Number((await H.sql('select bank_balance from game.players where player_id = $1', [pid]))[0].bank_balance);
  const item = async id => Number((await H.sql('select game.item_qty($1, $2) q', [pid, id]))[0].q);
  const dayAgo = async n => H.sql(`update game.player_quests set data = data || jsonb_build_object('loanDay', game.game_day() - $2::int) where player_id = $1 and quest_id = 'cocoepan'`, [pid, n]);

  // --- Prasyarat ------------------------------------------------------------
  assert((await st()) === null, 'tersembunyi sebelum Quest 5 selesai');
  await H.sql(`insert into game.player_quests(player_id, quest_id, step, done_at) values
    ($1, 'gala', 6, now()), ($1, 'toogood', 10, now()), ($1, 'warwerwor', 12, now()), ($1, 'barsati', 16, now()),
    ($1, 'kompas', 8, now() - (2.2 * game.cfg_num('GameDayLengthRealMinutes', 60) || ' minutes')::interval)`, [pid]);
  let s = await st();
  assert(s && s.step === 0 && s.eligible && s.timeOk === true, 'siap setelah 2 hari game ' + JSON.stringify(s));
  assert(s.bankNeed === 1000000 && s.bankOk === false, 'bank belum cukup');
  await H.sql('update game.players set gold = 0 where player_id = $1', [pid]);
  await H.sql('update game.players set bank_balance = 500000 where player_id = $1', [pid]);
  await go('joungjava');
  await H.expectError(() => cb(['talk']), /bankmu lebih berat/);
  assert((await st()).step === 0, 'quest tidak lanjut bila bank kurang');

  // --- Babak 1: Javasche Bank ----------------------------------------------
  await H.sql('update game.players set bank_balance = 2000000 where player_id = $1', [pid]);
  await go('skitraw');
  await H.expectError(() => cb(['talk']), /Pak Tua Karto menunggu di Joungjava/);
  await go('joungjava');
  s = await cb(['talk']); assert(s.cocoepan.step === 1, 'Babak 1 dimulai');
  await H.expectError(() => cb(['loan', '500000']), /minimal 1.000.000/);
  await H.expectError(() => cb(['loan', '3000000']), /Saldo Bank tidak cukup/);
  s = await cb(['decline']); assert(s.cocoepan.declined === true && s.cocoepan.step === 1, 'tolak: quest tetap bisa kembali');
  s = await cb(['loan', '1500000']);
  assert(s.cocoepan.step === 2 && s.cocoepan.loan === 1500000 && s.cocoepan.repay === 3000000, 'pinjaman 1,5 juta -> 2x (3 juta)');
  assert((await bank()) === 500000, 'saldo bank berkurang sebesar pinjaman');
  assert((await item('qi_peti_bantuan')) === 1 && s.cocoepan.hasCrate, 'Peti Bantuan diterima');

  // --- Babak 2: Peti Bantuan & Mata Syahbandar -----------------------------
  await H.expectError(() => cb(['deliver']), /Kamp Pemulung ada di IKN/);
  await go('ikn');
  s = await cb(['deliver']); assert(s.cocoepan.step === 3 && (await item('qi_peti_bantuan')) === 0, 'Peti dibagikan di IKN');
  await go('joungjava');
  await H.expectError(() => cb(['flower']), /belum punya bunga/);
  s = await cb(['syahbandar', 'ok']); assert(s.cocoepan.syah === true && s.cocoepan.step === 3, 'Mata Syahbandar selesai');

  // --- Babak 3: bunga & Gading Island ---------------------------------------
  s = await cb(['flower']); assert(s.cocoepan.step === 4 && s.cocoepan.hasFlower, 'bunga melati diberikan');
  assert((await H.sql(`select game.city_open($1, 'gading_island') o`, [pid]))[0].o === true, 'Gading Island terbuka setelah bunga');
  assert((await H.sql(`select game.city_open($1, 'pusaran') o`, [pid]))[0].o === false, 'pulau lain tetap tertutup');

  await H.expectError(() => cb(['stumpy']), /Stumpy ada di Gading Island/);
  await go('gading_island');
  s = await cb(['stumpy']); assert(s.cocoepan.step === 5, 'felyx di Stumpy');
  s = await cb(['grave']); // bunga melati dibawa dari Joungjava
  assert(s.cocoepan.step === 6 && s.cocoepan.bookGiven && s.cocoepan.hasFlower === false, 'makam & buku pancing');
  assert((await item('qi_buku_pancing_maudy')) === 1, 'Buku Pancing Legenda diterima');
  await H.expectError(() => cb(['mural']), /belum terbuka/);
  // ikan legenda: lewat kait memancing (fish_quest_catch), bukan aksi manual
  await H.sql(`select game.fish_quest_catch($1, 'legenda_gading')`, [pid]);
  s = await st(); assert(s.step === 7 && s.legend === true, 'ikan legenda tertangkap lewat kait memancing');
  const w = Number((await H.sql(`select game.fish_quest_weight($1, 'legenda_gading', 'gading_island') w`, [pid]))[0].w);
  assert(w !== 1, 'bobot ikan legenda sudah lewat langkah 6');
  const gs = await u.call('api_getGameState', [null]);
  assert(gs.cocoepan && gs.cocoepan.step === 7, 'status Quest 6 ikut di getGameState');
  s = await cb(['mural']); assert(s.cocoepan.step === 8 && s.cocoepan.mural === true, 'mural Sandi Pelikan selesai');

  // --- Babak 4 pasar kopi ---------------------------------------------------
  const kopi = await H.sql(`select count(*) n from game.market where commodity_id like 'kopi_%' and city_id = 'gading_island'`);
  assert(Number(kopi[0].n) === 3, 'tiga kopi dijual di Gading Island');
  const pusaranPasar = await H.sql(`select count(*) n from game.market where city_id = 'pusaran'`);
  assert(Number(pusaranPasar[0].n) === 0, 'kota spot tanpa pasar kopi');

  // --- Babak 5: pelunasan hari ke-10 ---------------------------------------
  await go('joungjava');
  await H.expectError(() => cb(['return']), /Belum waktunya/);
  await dayAgo(10);
  const g0 = await gold();
  s = await cb(['return']);
  assert(s.cocoepan.step === 9 && s.cocoepan.done === false, 'pelunasan');
  assert((await gold()) === g0 + 3000000, 'pengembalian 2x diterima sebagai gold');
  await H.expectError(() => cb(['surat']), /belum disegel|belum/);
  s = await cb(['gasing', 'won']); assert(s.cocoepan.step === 10 && s.cocoepan.gasing === 'won', 'adu gasing dimenangkan');

  // --- Epilog ---------------------------------------------------------------
  await H.expectError(() => cb(['surat']), /Marlya membaca surat/);
  await go('marie_regal');
  s = await cb(['surat']); assert(s.cocoepan.done === true && s.cocoepan.step === 12, 'Quest 6 selesai');
  console.log('COCOEPAN TESTS PASSED');
  process.exit(0);
})().catch(e => { console.error('ERROR:', e); process.exit(1); });
