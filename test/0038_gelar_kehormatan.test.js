// Tide v40: Gelar Kehormatan Pulau (Fase 1) — tangga gelar, Hak Lot, Papan Kehormatan.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const setRep = (pid, rep) => H.sql('update game.players set reputation = $1::jsonb where player_id = $2', [JSON.stringify(rep), pid]);
  const state = async (P) => (await P.call('api_getGameState', [])).honor;

  const A = await H.user('kh_ana');
  await A.call('api_createCharacter', ['Kapten Ana', 'merchant']);

  // --- Konfigurasi & tangga ---
  let h = await state(A);
  ok(h && Array.isArray(h.tiers) && h.tiers.length === 6, 'state honor ada, 6 tingkat');
  ok(h.tiers.map(t => t.min).join(',') === '0,5,15,35,60,100', 'ambang 0/5/15/35/60/100');
  ok(h.tiers.map(t => t.name).join('|') === 'Tamu|Kenalan|Sahabat Kota|Warga Kehormatan|Anak Nagari|Pelindung Pulau', 'nama gelar');
  ok(h.tiers.map(t => t.lots).join(',') === '0,0,0,3,6,10', 'jatah 3/6/10 lot');
  ok(!h.cities.some(c => c.id === 'paradiso' || c.id === 'marie_regal'), 'pulau tersembunyi tidak tampil sebelum terbuka');
  ok(!h.cities.some(c => c.id === 'gading_island' || c.id === 'otoland'), 'pulau Saga 2 tidak ikut');
  ok(h.here && h.here.id === 'sunda_empire' && h.here.tier === 0 && h.here.tierName === 'Tamu', 'Tamu di Sunda');

  await setRep(A.id, { sunda_empire: 34, joungjava: 5 });
  h = await state(A);
  ok(h.here.tier === 2 && h.here.tierName === 'Sahabat Kota' && h.here.next === 35 && h.here.nextName === 'Warga Kehormatan', 'Standing 34 = Sahabat Kota, berikutnya 35');
  ok(h.here.lotMax === 0 && h.here.goods.length === 0, 'belum ada Hak Lot di bawah 35');
  ok(h.unseen.length === 3, 'naik gelar tercatat (Kenalan+Sahabat Sunda, Kenalan Joungjava): ' + JSON.stringify(h.unseen));
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 1]), /Warga Kehormatan \(Standing 35\)/);

  await setRep(A.id, { sunda_empire: 35, joungjava: 5 });
  h = await state(A);
  ok(h.here.tier === 3 && h.here.lotMax === 3 && h.here.lotUsed === 0, 'Standing 35 = Warga Kehormatan, 3 lot');
  ok(h.unseen.length === 4 && h.unseen[3].tierName === 'Warga Kehormatan', 'gelar baru belum dilihat');
  h = (await A.call('api_kehormatan', ['lihat', 'gelar'])).honor;
  ok(h.unseen.length === 0, 'lihat gelar mengosongkan daftar');
  ok(h.top && h.top.city === 'sunda_empire' && h.top.tierName === 'Warga Kehormatan', 'gelar tertinggi');

  // --- Hak Lot ---
  const goods = h.here.goods;
  ok(goods.some(g => g.commodityId === 'garam' && g.lot === 10) && goods.some(g => g.commodityId === 'jackdaniels' && g.lot === 1), 'barang hasil Sunda: garam (lot 10), JackDaniels (lot 1)');
  ok(!goods.some(g => g.commodityId === 'sugar'), 'gula bukan hasil Sunda');
  const garam = goods.find(g => g.commodityId === 'garam');
  await H.sql('update game.players set gold = 1000000 where player_id = $1', [A.id]);
  const stock0 = Number((await one(`select stock from game.market where city_id = 'sunda_empire' and commodity_id = 'garam'`)).stock);
  let r = await A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 2]);
  ok(r.units === 20 && r.totalCost === garam.unitPrice * 20, 'beli 2 lot garam = 20 unit dengan harga keseimbangan');
  ok(r.newGold === 1000000 - r.totalCost, 'gold berkurang');
  ok(r.ownedQty === 20 && r.honor.here.lotUsed === 2, 'garam masuk palka, jatah terpakai 2');
  const stock1 = Number((await one(`select stock from game.market where city_id = 'sunda_empire' and commodity_id = 'garam'`)).stock);
  ok(stock1 === stock0, 'stok pasar tidak berubah');
  ok(Number(r.avgCost) === garam.unitPrice, 'modal rata-rata tercatat');
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 2]), /tinggal 1 lot/);
  r = await A.call('api_kehormatan', ['lot', 'sunda_empire', 'jackdaniels', 1]);
  ok(r.units === 1 && r.honor.here.lotUsed === 3, 'jatah boleh dicampur antar barang');
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 1]), /tinggal 0 lot/);
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'sugar', 1]), /hanya untuk barang hasil pulau ini/);
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'joungjava', 'beras', 1]), /harus berada di kota ini/);
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 0]), /tidak valid/);

  // Harga lot tidak ikut naik walau pasar diborong
  await H.sql(`update game.market set stock = 0, at = now() where city_id = 'sunda_empire' and commodity_id = 'garam'`);
  h = await state(A);
  ok(h.here.goods.find(g => g.commodityId === 'garam').unitPrice === garam.unitPrice, 'harga Hak Lot tetap walau stok pasar habis');

  // Reset 00:00 WIB
  await H.sql('delete from game.inventory where player_id = $1', [A.id]);
  await H.sql(`update game.config set value = '86400000' where key = 'HarianClockOffset'`);
  h = await state(A);
  ok(h.here.lotUsed === 0, 'jatah kembali penuh setelah reset WIB');
  r = await A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 1]);
  ok(r.honor.here.lotUsed === 1, 'hari baru: jatah baru');
  await H.sql(`update game.config set value = '0' where key = 'HarianClockOffset'`);

  // Gold & palka
  await H.sql('update game.players set gold = 5 where player_id = $1', [A.id]);
  await H.sql(`update game.config set value = '172800000' where key = 'HarianClockOffset'`);
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 1]), /Gold tidak cukup/);
  await H.sql('update game.players set gold = 100000000 where player_id = $1', [A.id]);
  await setRep(A.id, { sunda_empire: 100, joungjava: 5 });
  h = await state(A);
  ok(h.here.tierName === 'Pelindung Pulau' && h.here.lotMax === 10 && h.here.next === null, 'Pelindung Pulau: 10 lot, tidak ada gelar berikutnya');
  await H.expectError(() => A.call('api_kehormatan', ['lot', 'sunda_empire', 'garam', 10]), /Kapasitas cargo tidak cukup/);
  await H.sql(`update game.config set value = '0' where key = 'HarianClockOffset'`);

  // --- Papan Kehormatan ---
  const mk = async (u, name, rep) => { const P = await H.user(u); await P.call('api_createCharacter', [name, 'navigator']); await setRep(P.id, { bjorneo: rep }); return P; };
  const B = await mk('kh_budi', 'Kapten Budi', 20);
  const C = await mk('kh_citra', 'Kapten Citra', 30);
  const D = await mk('kh_dodo', 'Kapten Dodo', 10);
  const G = await mk('abuy', 'Kapten GM', 99);
  await H.sql(`update game.honor_rep set at = now() - interval '1 hour' where player_id = $1`, [C.id]);
  const E = await mk('kh_eko', 'Kapten Eko', 30);
  let b = (await B.call('api_kehormatan', ['papan', 'bjorneo'])).board;
  ok(b.rows.length === 3, 'papan 3 baris: ' + JSON.stringify(b.rows.map(x => x.name)));
  ok(b.rows[0].name === 'Kapten Citra' && b.rows[1].name === 'Kapten Eko' && b.rows[2].name === 'Kapten Budi', 'urut Standing, seri = lebih dulu mencapai');
  ok(!b.rows.some(x => x.name === 'Kapten GM'), 'akun GM tidak ikut');
  ok(!b.rows.some(x => x.name === 'Kapten Dodo'), 'Standing di bawah 15 tidak ikut');
  ok(b.rows[2].me === true && b.me.rank === 3, 'baris milik sendiri ditandai');
  ok(b.rows.every(x => !('username' in x)) && JSON.stringify(b).indexOf('kh_') < 0, 'papan memakai character_name, bukan username');
  ok(b.rows[0].tierName === 'Sahabat Kota', 'gelar tampil di papan');

  // Dodo naik ke 40 -> Budi tergeser
  await H.sql('delete from realtime.sent');
  await setRep(D.id, { bjorneo: 40 });
  b = (await D.call('api_kehormatan', ['papan', 'bjorneo'])).board;
  ok(b.rows[0].name === 'Kapten Dodo' && !b.rows.some(x => x.name === 'Kapten Budi'), 'Dodo naik, Budi keluar');
  let hb = await state(B);
  ok(hb.notes.length === 1 && hb.notes[0].kind === 'geser' && hb.notes[0].city === 'bjorneo' && hb.notes[0].data.by === 'Kapten Dodo', 'Budi mendapat catatan tergeser');
  const ib = await H.sql(`select item from game.mp_inbox where player_id = $1`, [B.id]);
  ok(ib.some(x => x.item.type === 'honor_geser' && x.item.cityName === 'Bjorneo'), 'notifikasi langsung ke kotak masuk');
  ok((await state(C)).notes.length === 0, 'yang tidak tergeser tidak mendapat catatan');
  hb = (await B.call('api_kehormatan', ['lihat', 'catatan'])).honor;
  ok(hb.notes.length === 0, 'catatan ditandai sudah dibaca');
  // Bjorneo tidak terlihat untuk Budi? (bjorneo bukan pulau tersembunyi -> boleh)
  await H.expectError(() => B.call('api_kehormatan', ['papan', 'gading_island']), /tidak punya Papan/);
  await H.expectError(() => B.call('api_kehormatan', ['papan', 'paradiso']), /tidak dikenal/);

  // Kartu kapten lain
  const pubC = (await one('select game.mp_pub_of($1) p', [C.id])).p;
  const kg = (await B.call('api_kehormatan', ['kapten', pubC])).gelar;
  ok(kg.top && kg.top.cityName === 'Bjorneo' && kg.top.tierName === 'Sahabat Kota', 'gelar tertinggi kapten lain');

  // Tidak ada Tanda Jasa / ACH dari fitur ini
  const meta = await one('select meta from game.players where player_id = $1', [A.id]);
  ok(JSON.stringify(meta.meta || {}).indexOf('honor') < 0 && JSON.stringify(meta.meta || {}).indexOf('kehormatan') < 0, 'tidak menyentuh meta Tanda Jasa');

  // Reset karakter: cermin & gelar ikut hilang
  await setRep(C.id, {});
  ok(Number((await one('select count(*) n from game.honor_rep where player_id = $1', [C.id])).n) === 0, 'reset reputasi: cermin dihapus');
  ok(Number((await one('select count(*) n from game.honor_tier where player_id = $1', [C.id])).n) === 0, 'reset reputasi: gelar dihapus');

  // Isi awal saat rilis: gelar lama tidak dirayakan
  await H.db.exec('delete from game.honor_rep; delete from game.honor_tier;');
  await H.db.exec(require('fs').readFileSync(require('path').join(__dirname, '..', 'supabase', 'migrations', '0038_gelar_kehormatan.sql'), 'utf8'));
  ok(Number((await one(`select count(*) n from game.honor_rep where player_id = $1 and city_id = 'sunda_empire' and rep = 100`, [A.id])).n) === 1, 'isi awal cermin dari reputasi');
  h = await state(A);
  ok(h.unseen.length === 0, 'gelar hasil isi awal tidak memunculkan perayaan');
  ok(Number((await one(`select count(*) n from game.honor_tier where player_id = $1 and city_id = 'sunda_empire'`, [A.id])).n) === 5, 'isi awal: 5 gelar Sunda tercatat');

  // Gerbang fitur
  await H.sql(`update game.config set value = '0' where key = 'KehormatanOpen'`);
  ok((await state(A)) === null, 'fitur ditutup: state null');
  await H.expectError(() => A.call('api_kehormatan', ['status']), /belum dibuka/);
  await H.sql(`update game.config set value = '1' where key = 'KehormatanOpen'`);

  console.log('0038 gelar kehormatan: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
