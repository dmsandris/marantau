// GM Kirim Gold & Keping (perluasan 0073): tanpa batas jumlah, langsung masuk, tercatat, notif pemain.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];

  const gm = await H.user('abuy'); await gm.call('api_createCharacter', ['Abuy GM', 'merchant']);
  const p1 = await H.user('kapten1'); await p1.call('api_createCharacter', ['Kapten Satu', 'navigator']);
  const pl = async (u) => await one(`select gold::text gold, keping::text keping from game.players where player_id = $1`, [u.id]);
  const inbox = async (u) => (await H.sql(`select item from game.mp_inbox where player_id = $1 and item->>'type' = 'gm_kirim' order by seq`, [u.id])).map(r => r.item);

  // non-GM ditolak
  await H.expectError(() => p1.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'gold', qty: 100 }]), /khusus GM/);
  // ke akun GM ditolak, jenis aneh ditolak, jumlah tidak valid ditolak
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'abuy', jenis: 'gold', qty: 100 }]), /akun GM/);
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'rupa', qty: 1 }]), /tidak dikenal/);
  for (const q of [0, -5, 'abc', null]) await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'gold', qty: q }]), /minimal 1/);

  // kartu memuat gold & keping
  const C = (await gm.call('api_gmKirim', ['cek', 'kapten1'])).card;
  ok(C.gold !== undefined && C.keping !== undefined, 'kartu gold & keping');

  // gold: tanpa batas (jauh di atas batas barang 500)
  const g0 = BigInt((await pl(p1)).gold);
  let R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'gold', qty: 25000000, note: 'hadiah event' }]);
  ok(R.ok === true, 'kirim gold');
  ok(BigInt((await pl(p1)).gold) === g0 + 25000000n, 'gold bertambah 25 jt');
  ok(R.log[0].jenis === 'gold' && Number(R.log[0].qty) === 25000000 && R.log[0].note === 'hadiah event' && R.log[0].name === 'gold', 'log gold: ' + JSON.stringify(R.log[0]));
  let ib = await inbox(p1);
  ok(ib.length === 1 && ib[0].jenis === 'gold' && Number(ib[0].qty) === 25000000, 'inbox gold');
  const bank = await one(`select bank_balance::text b from game.players where player_id = $1`, [p1.id]);
  ok(BigInt(bank.b) === 0n, 'bank tidak tersentuh');

  // keping: tanpa batas, tercatat di keping_log sumber 'gm'
  const k0 = BigInt((await pl(p1)).keping);
  R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'keping', qty: 123456 }]);
  ok(R.ok === true && BigInt((await pl(p1)).keping) === k0 + 123456n, 'keping bertambah');
  const kl = await one(`select delta::text d, sumber, catatan from game.keping_log where player_id = $1 order by id desc limit 1`, [p1.id]);
  ok(kl.d === '123456' && kl.sumber === 'gm' && /kiriman GM abuy/.test(kl.catatan), 'keping_log: ' + JSON.stringify(kl));
  ok((await inbox(p1)).length === 2, 'inbox keping');

  // saat berlayar tetap masuk
  await H.sql(`update game.player_location set destination_city_id = 'toogood', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [p1.id]);
  R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'gold', qty: 1 }]);
  ok(R.ok === true && R.card.sea === true, 'gold masuk saat berlayar');

  // batas teknis bigint
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'gold', qty: '99999999999999999999' }]), /terlalu besar/);

  // barang tetap jalan (tanpa jenis = barang)
  const it = await one(`select id from game.commodities where active and size = 1 order by sort limit 1`);
  R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: it.id, qty: 3 }]);
  ok(R.ok === true && R.log[0].jenis === 'barang' && Number(R.log[0].qty) === 3, 'barang tetap: ' + JSON.stringify(R.log[0]));
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', jenis: 'barang', item: it.id, qty: 501 }]), /1 sampai 500/);

  console.log('GM Kirim Gold & Keping OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
