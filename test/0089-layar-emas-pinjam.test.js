// 0089 Tide v70: Layar Emas Juara = barang pinjaman (bisa dilepas/dipasang selama masa pinjam),
// kedaluwarsa otomatis di Upacara berikutnya + Ruang Ganti Kedai (api_kedaiSusun).
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const at = async wib => H.sql(`update game.config set value = (extract(epoch from ($1::timestamp - ((clock_timestamp() at time zone 'UTC') + interval '7 hours'))) * 1000)::bigint::text
    where key = 'HarianClockOffset'`, [wib]);
  const mk = async (u, name) => { const c = await H.user(u); await c.call('api_createCharacter', [name, 'merchant']); return c; };
  const A = await mk('le_alfa', 'Kapten Alfa Emas'), B = await mk('le_bravo', 'Kapten Bravo Emas');
  await H.sql(`update game.config set value = 'le_alfa,le_bravo' where key = 'FiturPenguji'`);
  await H.sql(`update game.config set value = '1' where key in ('PacuOpen', 'KedaiOpen')`);
  await H.sql(`update game.config set value = '0' where key = 'PacuGoldOn'`);
  const sell = (u, profit) => H.sql(`select game.hr_hook($1, 'sell', $2, $3::jsonb)`,
    [u.id, 1000 + profit, JSON.stringify({ city: 'joungjava', comm: 'batik', grp: 'kerajinan', qty: 10, avg: 100, base: 100 })]);
  const vis = async u => (await one('select game.kd_visual($1) v', [u.id])).v;
  const lo = async u => one('select equipped, prev_layar from game.kd_loadout where player_id = $1', [u.id]);
  const qty = async (u, id) => Number((await one('select game.kd_qty($1, $2) q', [u.id, id])).q);
  const st = async u => (await u.call('api_getGameState', [null])).pacu;

  // A punya layar kawung terpasang sebelum menang
  await H.sql(`select game.kd_grant($1, 'layar_kawung', 1, 'uji'), game.kd_grant($1, 'panji_walet', 1, 'uji')`, [A.id]);
  await A.call('api_kedai', ['pasang', 'layar_kawung']);
  ok((await vis(A)).layar === 'layar_kawung', 'awal: layar kawung');

  // --- Pacu: A juara 1 Jukung ------------------------------------------------------------
  await at('2026-10-31 10:00');
  await st(A);
  await sell(A, 9000); await sell(B, 100);
  await at('2026-11-02 08:05');
  const s = await st(B);
  ok(s.last && s.last.id === 'PD-2026-10-31' && s.last.results.gol['1'].list[0].name === 'Kapten Alfa Emas', 'A juara 1');

  // dipinjamkan + dipasang otomatis, layar lama dicatat
  ok(await qty(A, 'layar_emas_pekan') === 1, 'A meminjam Layar Emas Juara');
  let l = await lo(A);
  ok(l.equipped.layar === 'layar_emas_pekan' && l.prev_layar === 'layar_kawung', 'dipasang otomatis, layar lama dicatat ' + JSON.stringify(l));
  let v = await vis(A);
  ok(v.layar === 'layar_emas_pekan' && v.emas === true, 'rupa: layar emas (+ penanda emas untuk klien lama) ' + JSON.stringify(v));
  ok(!(await vis(B)), 'B tanpa rupa');
  const until = (await one(`select until from game.kd_owned where player_id = $1 and item_id = 'layar_emas_pekan'`, [A.id])).until;
  ok(new Date(until).toISOString() === '2026-11-09T01:00:00.000Z', 'masa pinjam sampai Senin 9 Nov 08:00 WIB: ' + new Date(until).toISOString());

  // daftar Kedai: hanya peminjam yang melihat barang ini, dengan sisa waktu
  let kd = (await A.call('api_kedai', ['daftar'])).kedai;
  const it = kd.items.find(x => x.id === 'layar_emas_pekan');
  ok(it && it.qty === 1 && it.pinjam && Math.abs(it.msLeft - (6 * 86400000 + 23 * 3600000 + 55 * 60000)) < 120000, 'kartu pinjaman + sisa waktu ' + JSON.stringify(it && [it.qty, it.msLeft]));
  ok(!(await B.call('api_kedai', ['daftar'])).kedai.items.some(x => x.id === 'layar_emas_pekan'), 'B tidak melihat kartu pinjaman');
  await H.expectError(() => B.call('api_kedai', ['pasang', 'layar_emas_pekan']), /belum memiliki/);
  await H.expectError(() => B.call('api_kedai', ['beli', 'layar_emas_pekan']), /tidak dijual/);

  // --- bisa dilepas & dipasang lagi (inti bug Dede) ---------------------------------------
  await A.call('api_kedai', ['lepas', 'layar']);
  v = await vis(A);
  ok(!v || (!v.layar && !v.emas), 'dilepas: tanpa layar & tanpa emas ' + JSON.stringify(v));
  await A.call('api_kedai', ['pasang', 'layar_kawung']);
  ok((await vis(A)).layar === 'layar_kawung' && !(await vis(A)).emas, 'ganti ke kawung: emas tidak menimpa');
  await A.call('api_kedai', ['pasang', 'layar_emas_pekan']);
  ok((await vis(A)).layar === 'layar_emas_pekan' && (await vis(A)).emas, 'dipasang lagi');
  const pr = await one('select s from game.mp_presence where player_id = $1', [A.id]);
  ok(pr && pr.s && pr.s.kd && pr.s.kd.layar === 'layar_emas_pekan', 'presence ikut (kapten lain melihat)');

  // --- Ruang Ganti: banyak slot sekaligus -------------------------------------------------
  let r = await A.call('api_kedaiSusun', [{ layar: 'layar_kawung', panji: 'panji_walet', haluan: 'haluan_naga', ngawur: 'x' }]);
  ok(r.changed === 2 && r.skip.includes('haluan_naga') && r.skip.includes('ngawur'), 'susun: 2 berubah, barang tak dimiliki & slot salah dilewati ' + JSON.stringify([r.changed, r.skip]));
  ok(r.shipVisual.kd.layar === 'layar_kawung' && r.shipVisual.kd.panji === 'panji_walet' && r.kedai && r.rupa, 'susun mengembalikan rupa + daftar');
  r = await A.call('api_kedaiSusun', [{ panji: null, layar: 'layar_emas_pekan' }]);
  l = await lo(A);
  ok(r.changed === 2 && !l.equipped.panji && l.equipped.layar === 'layar_emas_pekan', 'susun: lepas panji + pasang emas ' + JSON.stringify(l.equipped));
  r = await A.call('api_kedaiSusun', [{ layar: 'layar_emas_pekan' }]);
  ok(r.changed === 0, 'tanpa perubahan = 0');
  r = await B.call('api_kedaiSusun', [{ layar: 'layar_emas_pekan' }]);
  ok(r.changed === 0 && r.skip.includes('layar_emas_pekan'), 'B tidak bisa memasang pinjaman A');
  await H.expectError(() => A.call('api_kedaiSusun', ['bukan objek']), /tidak valid/);

  // --- juara lagi: diperpanjang, bukan ganda ----------------------------------------------
  await H.sql(`select game.pd_emas_grant($1, '2026-11-16 01:00:00+00'::timestamptz)`, [A.id]);
  const n = await one(`select count(*)::int n, max(until) u from game.kd_owned where player_id = $1 and item_id = 'layar_emas_pekan'`, [A.id]);
  ok(n.n === 1 && new Date(n.u).toISOString() === '2026-11-16T01:00:00.000Z', 'perpanjang');
  await H.sql(`update game.kd_owned set until = '2026-11-09 01:00:00+00' where player_id = $1 and item_id = 'layar_emas_pekan'`, [A.id]);

  // --- lewat masa: tidak dimiliki, rupa kembali ke layar lama ----------------------------
  await at('2026-11-09 08:01');
  ok(await qty(A, 'layar_emas_pekan') === 0, 'lewat masa: kd_qty 0');
  v = await vis(A);
  ok(v && v.layar === 'layar_kawung' && !v.emas, 'lewat masa sebelum Upacara diproses: tampil layar lama ' + JSON.stringify(v));
  kd = (await A.call('api_kedai', ['daftar'])).kedai;
  ok(!kd.items.some(x => x.id === 'layar_emas_pekan') && kd.equipped.layar === 'layar_kawung', 'daftar Kedai: kartu hilang, terpasang = layar lama');
  await H.expectError(() => A.call('api_kedai', ['pasang', 'layar_emas_pekan']), /belum memiliki/);
  // Upacara pekan 7 Nov (tanpa juara) membersihkan baris & loadout
  await st(B);
  l = await lo(A);
  ok(l.equipped.layar === 'layar_kawung' && l.prev_layar === null, 'Upacara: loadout kembali ke kawung ' + JSON.stringify(l));
  ok(!(await one(`select 1 x from game.kd_owned where player_id = $1 and item_id = 'layar_emas_pekan'`, [A.id])), 'baris pinjaman dihapus');

  // layar lama sudah tidak dimiliki -> slot layar kosong (bukan barang hantu)
  await H.sql(`select game.pd_emas_grant($1, '2026-11-09 02:00:00+00'::timestamptz)`, [B.id]);
  await H.sql(`update game.kd_loadout set prev_layar = 'layar_songket' where player_id = $1`, [B.id]);
  await at('2026-11-09 09:30');
  v = await vis(B);
  ok(!v || !v.layar, 'prev tidak dimiliki -> tanpa layar ' + JSON.stringify(v));
  await H.sql('select game.pd_emas_cleanup()');
  ok(!(await lo(B)).equipped.layar, 'cleanup: slot layar kosong');

  // Layar Emas permanen tetap barang biasa milik tetap
  await H.sql(`select game.kd_grant($1, 'layar_emas', 1, 'pacu')`, [A.id]);
  await A.call('api_kedai', ['pasang', 'layar_emas']);
  ok((await vis(A)).layar === 'layar_emas' && !(await vis(A)).emas && await qty(A, 'layar_emas') === 1, 'Layar Emas permanen tidak terpengaruh');

  console.log('0089 layar emas pinjam: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
