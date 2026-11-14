// Tide v58 · GM Kirim Barang: GM mengirim komoditas pasar ke palka pemain.
// Hanya komoditas aktif; palka kurang -> gagal total + notif ke pemain & GM; modal 0; tetap masuk saat berlayar.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];

  const gm = await H.user('abuy'); await gm.call('api_createCharacter', ['Abuy GM', 'merchant']);
  const p1 = await H.user('kapten1'); await p1.call('api_createCharacter', ['Kapten Satu', 'navigator']);
  const p2 = await H.user('kapten2'); await p2.call('api_createCharacter', ['Kapten Dua', 'merchant']);

  // komoditas biasa berukuran 1 untuk tes
  const it = (await one(`select id, name, size from game.commodities where active and size = 1 order by sort limit 1`));
  ok(it && it.id, 'ada komoditas aktif');
  const inbox = async (u, t) => (await H.sql(`select item from game.mp_inbox where player_id = $1 and item->>'type' = $2`, [u.id, t])).map(r => r.item);
  const inv = async (u, id) => await one(`select qty, cost, src_city from game.inventory where player_id = $1 and item_id = $2`, [u.id, id]);

  // bukan GM ditolak
  await H.expectError(() => p1.call('api_gmKirim', ['init']), /khusus GM/);
  await H.expectError(() => p1.call('api_gmKirim', ['kirim', { u: 'kapten2', item: it.id, qty: 1 }]), /khusus GM/);

  // init
  const I = await gm.call('api_gmKirim', ['init']);
  ok(I.max === 500 && I.items.length > 5 && I.items.some(x => x.id === it.id), 'init: daftar komoditas & batas');
  await H.expectError(() => gm.call('api_gmKirim', ['hapus']), /tidak dikenal/);

  // cek
  const C = await gm.call('api_gmKirim', ['cek', 'kapten1']);
  ok(C.card.name === 'Kapten Satu' && C.card.capacity > 0 && C.card.free > 0, 'cek kartu: ' + JSON.stringify(C.card));
  await H.expectError(() => gm.call('api_gmKirim', ['cek', 'tidakada']), /tidak ditemukan/);

  // validasi
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'abuy', item: it.id, qty: 1 }]), /akun GM/);
  const nonKom = await one(`select item_id from game.item_catalog limit 1`);
  if (nonKom) await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: nonKom.item_id, qty: 1 }]), /Hanya komoditas/);
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: 'gold', qty: 1 }]), /Hanya komoditas/);
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: it.id, qty: 0 }]), /1 sampai 500/);
  await H.expectError(() => gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: it.id, qty: 501 }]), /1 sampai 500/);

  // berhasil -> palka bertambah, modal 0, src_city kosong, log & inbox
  let R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: it.id, qty: 5, note: 'ganti rugi bug' }]);
  ok(R.ok === true, 'kirim berhasil');
  let row = await inv(p1, it.id);
  ok(row.qty === 5 && Number(row.cost) === 0 && row.src_city == null, 'palka +5, modal 0: ' + JSON.stringify(row));
  ok((await inbox(p1, 'gm_kirim')).length === 1, 'inbox pemain');
  ok(R.log[0].ok === true && R.log[0].u === 'kapten1' && R.log[0].note === 'ganti rugi bug', 'log berhasil');
  ok(Number((await one(`select count(*) v from game.player_log where player_id = $1 and message like 'Kiriman dari Syahbandar%'`, [p1.id])).v) === 1, 'player_log');

  // modal rata-rata turun bila sudah punya barang bermodal
  await H.sql(`update game.inventory set cost = 500 where player_id = $1 and item_id = $2`, [p1.id, it.id]);
  await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: it.id, qty: 5 }]);
  row = await inv(p1, it.id);
  ok(row.qty === 10 && Number(row.cost) === 500, 'modal total tetap 500 (rata-rata 50): ' + JSON.stringify(row));

  // palka penuh -> gagal total, notif pemain & GM
  const free = Number((await gm.call('api_gmKirim', ['cek', 'kapten2'])).card.free);
  const big = await one(`select id, size from game.commodities where active order by size desc limit 1`);
  const n = Math.min(500, Math.floor(free / Number(big.size)) + 1);
  ok(n * Number(big.size) > free, 'kiriman melebihi palka');
  R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten2', item: big.id, qty: n }]);
  ok(R.ok === false && /tidak cukup/.test(R.reason), 'gagal palka penuh: ' + JSON.stringify(R.reason));
  ok(!(await inv(p2, big.id)) || (await inv(p2, big.id)).qty === 0, 'tidak ada yang masuk');
  ok((await inbox(p2, 'gm_kirim_gagal')).length === 1, 'notif gagal ke pemain');
  ok((await inbox(gm, 'gm_kirim_gagal_gm')).length === 1, 'notif gagal ke GM');
  ok(R.log[0].ok === false && R.log[0].reason === 'palka penuh', 'log gagal');

  // pas sisa ruang -> berhasil
  const free2 = Number((await gm.call('api_gmKirim', ['cek', 'kapten2'])).card.free);
  const k = Math.min(500, Math.floor(free2));
  R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten2', item: it.id, qty: k }]);
  ok(R.ok === true && Number(R.card.free) >= 0, 'muat pas: ' + JSON.stringify(R.card));

  // tetap masuk saat berlayar
  await H.sql(`update game.player_location set destination_city_id = 'toogood', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [p1.id]);
  R = await gm.call('api_gmKirim', ['kirim', { u: 'kapten1', item: it.id, qty: 2 }]);
  ok(R.ok === true && R.card.sea === true && (await inv(p1, it.id)).qty === 12, 'masuk saat berlayar');

  console.log('GM Kirim Barang OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
