// 0101 Pesan Pribadi: kirim ke offline, daftar, utas & tanda baca, pulse 'pm', GM, jeda, 7 hari.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const a = await H.user('pm_a'), b = await H.user('pm_b'), c = await H.user('pm_c'), gm = await H.user('abuy');
  await a.call('api_createCharacter', ['Kapten Alif', 'merchant']);
  await b.call('api_createCharacter', ['Kapten Bima', 'pirate']);
  await c.call('api_createCharacter', ['Kapten Citra', 'explorer']);
  await gm.call('api_createCharacter', ['Syahbandar', 'diplomat']);
  for (const u of [a, b, c, gm]) await u.call('api_mpPulse', []);
  const pub = async (u) => (await one(`select game.mp_pub_of($1) p`, [u.id])).p;
  const [pa, pb, pc, pg] = [await pub(a), await pub(b), await pub(c), await pub(gm)];
  const jeda = (u) => H.sql(`update game.mp_presence set last_chat_at = now() - interval '5 seconds' where player_id = $1`, [u.id]);

  // pulse pertama (since.pm = 0): hanya jumlah + top, tanpa isi
  let pu = (await b.call('api_mpPulse', [{}])).pm;
  assert(pu && pu.unread === 0 && pu.top === 0 && pu.baru.length === 0, 'pulse awal kosong: ' + JSON.stringify(pu));

  // kirim ke B (B dianggap offline: tidak ada pulse lagi)
  let r = await a.call('api_mpPm', ['kirim', pb, '  Halo   Bima, mau dagang kopi?  ']);
  assert(r.msg && r.msg.mine === true && r.msg.tx === 'Halo Bima, mau dagang kopi?', 'pesan dibersihkan: ' + JSON.stringify(r.msg));
  assert(r.who.n === 'Kapten Bima', 'who tujuan');
  const sent = await H.sql(`select topic, event from realtime.sent where event = 'pm'`);
  assert(sent.length === 1 && sent[0].topic === 'player:' + pb, 'bel realtime ke kanal pribadi B');

  // jeda 2 detik (berbagi dengan chat)
  await H.expectError(() => a.call('api_mpPm', ['kirim', pb, 'lagi']), /Pelan-pelan/);
  await jeda(a);
  await a.call('api_mpChat', ['global', 'halo dunia']);
  await H.expectError(() => a.call('api_mpPm', ['kirim', pb, 'lagi']), /Pelan-pelan/);
  await jeda(a);
  await a.call('api_mpPm', ['kirim', pb, 'x'.repeat(200)]);
  const panjang = await one(`select length(tx) n from game.mp_pm order by id desc limit 1`);
  assert(Number(panjang.n) === 140, 'dipotong 140');

  // penolakan
  await jeda(a);
  await H.expectError(() => a.call('api_mpPm', ['kirim', pg, 'hai GM']), /^Kapten tidak ditemukan\.$/);
  await H.expectError(() => a.call('api_mpPm', ['kirim', pa, 'diri']), /diri sendiri/);
  await H.expectError(() => a.call('api_mpPm', ['kirim', 'palsu', 'x']), /^Kapten tidak ditemukan\.$/);
  await H.expectError(() => a.call('api_mpPm', ['kirim', pb, '   ']), /Pesan kosong/);
  await H.expectError(() => gm.call('api_mpPm', ['kirim', pb, 'dari GM']), /^Aksi tidak dikenal\.$/);
  await H.expectError(() => gm.call('api_mpPm', ['daftar']), /^Aksi tidak dikenal\.$/);
  await H.expectError(() => a.call('api_mpPm', ['entah']), /^Aksi tidak dikenal\.$/);

  // C kirim ke B juga
  await c.call('api_mpPm', ['kirim', pb, 'Bima, ada Tony di selat!']);

  // B "login": pulse awal -> unread 3, top = id terakhir, tanpa isi
  pu = (await b.call('api_mpPulse', [{}])).pm;
  assert(pu.unread === 3 && pu.top > 0 && pu.baru.length === 0, 'login: 3 belum dibaca: ' + JSON.stringify(pu));
  const top0 = pu.top;

  // daftar: 2 percakapan, terbaru (C) di atas
  let d = await b.call('api_mpPm', ['daftar']);
  assert(d.list.length === 2 && d.unread === 3, 'daftar 2 percakapan');
  assert(d.list[0].who.id === pc && d.list[0].unread === 1 && d.list[0].last.mine === false, 'C di atas');
  assert(d.list[1].who.id === pa && d.list[1].unread === 2 && d.list[1].who.n === 'Kapten Alif', 'A kedua');
  assert(!JSON.stringify(d).includes(a.id), 'uuid tidak bocor');

  // utas A: urut lama -> baru, ditandai dibaca
  let u = await b.call('api_mpPm', ['utas', pa]);
  assert(u.msgs.length === 2 && u.msgs[0].tx.startsWith('Halo') && u.msgs[1].tx.length === 140 && u.who.n === 'Kapten Alif' && u.who.gm === false, 'utas A');
  assert(u.unread === 1, 'sisa unread 1 (dari C)');
  // A melihat pesannya sudah dibaca
  let ua = await a.call('api_mpPm', ['utas', pb]);
  assert(ua.msgs.every(m => m.mine && m.read), 'A lihat tanda dibaca');

  // pesan baru saat B online -> pulse membawa isi
  await jeda(a);
  await a.call('api_mpPm', ['kirim', pb, 'Jadi?']);
  pu = (await b.call('api_mpPulse', [{ pm: top0 }])).pm;
  assert(pu.baru.length === 1 && pu.baru[0].tx === 'Jadi?' && pu.baru[0].from.id === pa && pu.unread === 2, 'pulse bawa pesan baru: ' + JSON.stringify(pu));
  // pesan keluar sendiri tidak masuk 'baru'
  await jeda(b);
  await b.call('api_mpPm', ['kirim', pa, 'Siap, ke Joungjava!']);
  pu = (await b.call('api_mpPulse', [{ pm: pu.top }])).pm;
  assert(pu.baru.length === 0, 'pesan sendiri tidak muncul sebagai baru');
  // baca
  r = await b.call('api_mpPm', ['baca', pc]);
  assert(r.unread === 1, 'baca C -> sisa 1');

  // GM: pulse tanpa pm, profil membawa gm
  assert(!('pm' in (await gm.call('api_mpPulse', [{}]))), 'GM tanpa pm');
  assert((await a.call('api_mpProfile', [pg])).gm === true, 'profil GM: gm true');
  assert((await a.call('api_mpProfile', [pb])).gm === false, 'profil biasa: gm false');

  // 7 hari: pesan lama tidak tampil & terhapus saat ada kiriman
  await H.sql(`update game.mp_pm set ts = ts - 8 * 86400000 where from_id = $1`, [c.id]);
  d = await b.call('api_mpPm', ['daftar']);
  assert(d.list.length === 1 && d.list[0].who.id === pa, 'percakapan > 7 hari hilang dari daftar');
  await jeda(a);
  await a.call('api_mpPm', ['kirim', pb, 'pemicu bersih']);
  assert(Number((await one(`select count(*) n from game.mp_pm where from_id = $1`, [c.id])).n) === 0, 'pesan > 7 hari terhapus');

  // utas paging 50
  for (let i = 0; i < 60; i++) await H.sql(`insert into game.mp_pm(pair, from_id, to_id, tx, ts) values (game.pm_pair($1,$2), $1, $2, $3, game.now_ms())`, [a.id, b.id, 'm' + i]);
  u = await b.call('api_mpPm', ['utas', pa]);
  assert(u.msgs.length === 50 && u.more === true && u.msgs[49].tx === 'm59', 'utas 50 terakhir + more');
  const u2 = await b.call('api_mpPm', ['utas', pa, u.msgs[0].id]);
  assert(u2.msgs.length > 0 && u2.msgs[u2.msgs.length - 1].id < u.msgs[0].id, 'halaman sebelumnya');

  console.log('OK 0101-pesan-pribadi');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
