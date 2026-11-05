// Tide v50 · Panel GM rapi: arsip catatan Tony and Gank hanya menyembunyikan dari daftar GM,
// data event & korban tetap di server, harta Perburuan Tony tidak berubah.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const now = Date.now(), H1 = 3600000;
  const one = async (q, p) => (await H.sql(q, p || []))[0];

  const gm = await H.user('abuy'); await gm.call('api_createCharacter', ['Abuy GM', 'merchant']);
  const biasa = await H.user('kapten1'); await biasa.call('api_createCharacter', ['Kapten Satu', 'navigator']);

  // tiga event: aktif, akan dibatalkan, dan satu yang sudah selesai
  const aktif = (await gm.call('api_gmTony', ['add', { dest: 'toogood', startAt: now, endAt: now + 2 * H1, kabar: 'diam' }])).raids[0].id;
  const batal = (await gm.call('api_gmTony', ['add', { dest: 'skitraw', startAt: now, endAt: now + H1, kabar: 'diam' }])).raids[0].id;
  await gm.call('api_gmTony', ['cancel', { id: batal }]);
  const selesai = (await gm.call('api_gmTony', ['add', { dest: 'bjorneo', startAt: now, endAt: now + H1, kabar: 'diam' }])).raids[0].id;
  await H.sql(`update game.tony_raid set start_at = now() - interval '3 hours', end_at = now() - interval '1 hour' where id = $1`, [selesai]);
  // korban palsu di event selesai (untuk harta Perburuan Tony)
  await H.sql(`insert into game.tony_victims(raid_id, player_id, result, gold_before, gold_taken, cargo_value) values ($1, $2, 'serah', 10000, 6000, 1500)`, [selesai, biasa.id]);
  const harta0 = Number((await one('select game.th_harta() v')).v);
  ok(harta0 >= 7500, 'harta Tony terhitung: ' + harta0);

  let L = await gm.call('api_gmTony', ['list']);
  ok(L.raids.length === 3 && L.doneCount === 2, 'awal: 3 event, 2 selesai/batal: ' + JSON.stringify({ n: L.raids.length, d: L.doneCount }));

  // bukan GM ditolak
  await H.expectError(() => biasa.call('api_gmTonyArsip', ['hideDone']), /khusus GM/);
  // event aktif tidak bisa diarsipkan
  await H.expectError(() => gm.call('api_gmTonyArsip', ['hide', { id: aktif }]), /masih aktif/);
  await H.expectError(() => gm.call('api_gmTonyArsip', ['hapus']), /tidak dikenal/);

  // arsip satu
  L = await gm.call('api_gmTonyArsip', ['hide', { id: selesai }]);
  ok(L.raids.length === 2 && !L.raids.some(r => r.id === selesai) && L.doneCount === 1, 'satu event hilang dari daftar');
  // diulang aman
  await gm.call('api_gmTonyArsip', ['hide', { id: selesai }]);

  // bersihkan semua yang selesai
  L = await gm.call('api_gmTonyArsip', ['hideDone']);
  ok(L.raids.length === 1 && L.raids[0].id === aktif && L.raids[0].status === 'aktif' && L.doneCount === 0, 'tinggal event aktif: ' + JSON.stringify(L.raids));

  // data server utuh
  ok(Number((await one('select count(*) v from game.tony_raid')).v) === 3, 'baris event tetap ada');
  ok(Number((await one('select count(*) v from game.tony_victims where raid_id = $1', [selesai])).v) === 1, 'korban tetap ada');
  ok(Number((await one('select game.th_harta() v')).v) === harta0, 'harta Perburuan Tony tidak berubah');

  // event aktif tetap berjalan dan masih bisa dibatalkan
  L = await gm.call('api_gmTony', ['cancel', { id: aktif }]);
  ok(L.raids.length === 1 && L.raids[0].status === 'batal' && L.doneCount === 1, 'batal tetap tampil sampai dibersihkan');

  console.log('Panel GM: arsip Tony OK');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
