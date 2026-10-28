// Tide v41 · Pasir Batch 1 — potret harta: ambil (kosongkan) & pulih (kembali + bunga 10%), peta per era,
// penjaga Pacu Dagang & Serbuan Bersama, kerahasiaan potret.
const ok = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p || []))[0];
  const cfg = (k, v) => H.sql('update game.config set value = $2 where key = $1', [k, v]);
  await cfg('PasirOpen', '1');
  await H.sql(`insert into game.world_flags(key) values ('saga3') on conflict do nothing`);

  const P = await H.user('pv_kaya');
  await P.call('api_createCharacter', ['Kapten Kaya', 'merchant']);
  const pid = P.id;
  // Veteran: Q9 selesai + Paradiso & pulau Saga 2 terbuka
  await H.sql(`insert into game.player_quests(player_id, quest_id, step) values ($1,'duatangan',5),($1,'gala',6),($1,'tigasilang',9)`, [pid]);

  // --- Harta lengkap ---
  await H.sql(`update game.players set gold = 1000000, bank_balance = 500000, bank_last_interest_day = 3, debt_balance = 20000,
      ship_upgrades = '{"speed":{"level":2,"tier":3,"accumulated":0},"cargo":{"level":1,"tier":2,"accumulated":40}}'::jsonb,
      ship_look = '{"hull":"#123456"}'::jsonb, keping = 777 where player_id = $1`, [pid]);
  await H.sql(`update game.ships set ship_name = 'Elang Laut', tier = 'IV', cargo = 120, condition = 77 where player_id = $1`, [pid]);
  await H.sql(`insert into game.ship_equipment(player_id, slot_type, item_id) values ($1, 'artifact', 'art_current_charts')`, [pid]);
  await H.sql(`insert into game.inventory(player_id, item_id, qty, cost) values ($1,'sugar',10,1000),($1,'art_smugglers_ring',1,null)`, [pid]);
  await H.sql(`insert into game.warehouse(player_id, city_id, commodity_id, qty, cost) values ($1,'joungjava','beras',50,2500)`, [pid]);
  await H.sql(`insert into game.player_books(player_id, book_id, date_acquired) values ($1,'bk_gala_logbook',2)`, [pid]);
  await H.sql(`update game.character_stats set combat = combat + 30, navigation = navigation + 20 where player_id = $1`, [pid]);
  const stats0 = await one('select * from game.character_stats where player_id = $1', [pid]);
  await H.sql(`insert into game.player_missions(player_id, status, accepted_at, city_id, commodity_id, qty, deliver_to_city_id, reward, type, loaded_qty)
               values ($1,'active',1,'sunda_empire','garam',20,'skitraw',900,'courier',20)`, [pid]);
  await H.sql(`insert into game.mp_orders(order_id, seller_id, city_id, commodity_id, qty, price) values ('ord1',$1,'sunda_empire','kopi',7,500)`, [pid]);
  await H.sql(`insert into game.kd_owned(player_id, item_id) values ($1,'layar_parang')`, [pid]);
  await H.sql(`insert into game.kd_loadout(player_id, equipped) values ($1,'{"layar":"layar_parang"}') on conflict (player_id) do update set equipped = excluded.equipped`, [pid]);
  await H.sql(`update game.player_location set city_id = 'empeer_depeer' where player_id = $1`, [pid]);

  let s = await P.call('api_getGameState', []);
  ok(s.unlocks.includes('paradiso') && s.unlocks.includes('empeer_depeer'), 'sebelum: pulau terbuka');
  ok(!('pasir' in s), 'sebelum masuk: tanpa key pasir');

  // --- Penjaga ---
  await H.sql(`update game.player_location set destination_city_id = 'skitraw', depart_at = now(), arrive_at = now() + interval '1 hour' where player_id = $1`, [pid]);
  await H.expectError(() => H.sql(`select game.admin_pasir('pv_kaya','ambil')`), /sedang berlayar/);
  await H.sql(`update game.player_location set destination_city_id = null, depart_at = null, arrive_at = null where player_id = $1`, [pid]);

  // --- AMBIL ---
  await H.sql(`select game.admin_pasir('pv_kaya','ambil')`);
  await H.expectError(() => H.sql(`select game.admin_pasir('pv_kaya','ambil')`), /masih tersimpan/);
  await H.expectError(() => H.sql(`select game.admin_pasir('pv_kaya','reset')`), /pulih dulu/);

  const p1 = await one('select * from game.players where player_id = $1', [pid]);
  ok(Number(p1.gold) === 5000 && Number(p1.bank_balance) === 0 && Number(p1.debt_balance) === 0, 'gold 5000, bank & utang 0');
  ok(JSON.stringify(p1.ship_upgrades) === '{}' && p1.ship_look === null, 'upgrade & tampilan kapal polos');
  ok(Number(p1.keping) === 777, 'Keping Rantau tetap');
  const sh = await one('select * from game.ships where player_id = $1', [pid]);
  ok(sh.ship_name === 'The Wandering Gull' && sh.tier === 'I' && sh.cargo === 30, 'Wandering Gull Tier I palka 30');
  ok(Number((await one('select count(*) n from game.inventory where player_id = $1', [pid])).n) === 0, 'palka kosong');
  ok(Number((await one('select count(*) n from game.warehouse where player_id = $1', [pid])).n) === 0, 'gudang kosong');
  ok(Number((await one('select count(*) n from game.player_books where player_id = $1', [pid])).n) === 0, 'buku hilang');
  ok(Number((await one('select count(*) n from game.ship_equipment where player_id = $1', [pid])).n) === 0, 'artifact terpasang hilang');
  const st1 = await one('select * from game.character_stats where player_id = $1', [pid]);
  const base = (await one(`select game.pv_base_stats('merchant') b`)).b;
  ok(st1.combat === base.combat && st1.navigation === base.navigation && st1.trading === base.trading, 'stat kembali ke dasar archetype');
  ok((await one(`select status from game.player_missions where player_id = $1`, [pid])).status === 'abandoned', 'misi aktif dibatalkan');
  ok((await one(`select status from game.mp_orders where order_id = 'ord1'`)).status === 'cancelled', 'order Bursa ditarik');
  ok(JSON.stringify((await one('select equipped from game.kd_loadout where player_id = $1', [pid])).equipped) === '{}', 'rupa Kedai dilepas');
  ok(Number((await one(`select count(*) n from game.kd_owned where player_id = $1`, [pid])).n) === 1, 'rupa Kedai tetap dimiliki');
  ok((await one('select city_id from game.player_location where player_id = $1', [pid])).city_id === 'sunda_empire', 'pindah ke Sunda Empire');

  // Peta kembali seperti awal
  s = await P.call('api_getGameState', []);
  ok(s.pasir && s.pasir.era === 'keadilan' && s.pasir.tone === 'dingin', 'era keadilan, nada dingin');
  ok(Array.isArray(s.unlocks) && s.unlocks.length === 0, 'unlocks kosong: ' + JSON.stringify(s.unlocks));
  ok((await one(`select game.city_open($1,'paradiso') o`, [pid])).o === false, 'Paradiso tertutup');
  ok((await one(`select game.city_open($1,'empeer_depeer') o`, [pid])).o === false, 'em pe\'er de pe\'er tertutup');
  ok((await one(`select game.city_open($1,'skitraw') o`, [pid])).o === true, 'pulau awal tetap terbuka');
  await H.sql(`update game.pasir_state set data = data || '{"buka":["empeer_depeer"]}' where player_id = $1`, [pid]);
  s = await P.call('api_getGameState', []);
  ok(JSON.stringify(s.unlocks) === '["empeer_depeer"]', 'hanya pulau yang dibuka Pasir: ' + JSON.stringify(s.unlocks));
  ok((await one(`select game.city_open($1,'empeer_depeer') o`, [pid])).o === true, 'em pe\'er de pe\'er dibuka Pasir');
  ok((await one(`select game.city_open($1,'paradiso') o`, [pid])).o === false, 'Paradiso tetap tertutup');

  // Kerahasiaan: angka potret tidak muncul di jawaban mana pun untuk pemain
  const dump = JSON.stringify(s) + JSON.stringify(await P.call('api_pasir', ['status'])) +
    JSON.stringify(await P.call('api_getCargo', [])) + JSON.stringify(await P.call('api_getCityBundle', []));
  ok(!/1000000|500000|Elang Laut|potret|pv_snap|"snap/.test(dump), 'tidak ada jejak potret di jawaban klien');
  ok(!/"gm"/.test(JSON.stringify(s.pasir)), 'pemain biasa tanpa alat GM');

  // Serbuan Bersama & Pacu Dagang tertutup
  ok(/Tak ada yang mengenal benderamu/.test((await one('select game.dt_join_block($1) b', [pid])).b), 'Serbuan Bersama tertutup');
  await cfg('PacuOpen', '1');
  const fnSrc = (await one(`select prosrc from pg_proc where proname = 'hr_hook'`)).prosrc;
  ok(/pasir_era\(p_pid\) = 'kini'/.test(fnSrc), 'hr_hook menahan skor Pacu selama era bukan kini');

  // --- Selama Pasir: dapat harta baru ---
  await H.sql(`update game.players set gold = 8000, bank_balance = 1000 where player_id = $1`, [pid]);
  await H.sql(`insert into game.inventory(player_id, item_id, qty, cost) values ($1,'sugar',5,600)`, [pid]);
  await H.sql(`insert into game.player_books(player_id, book_id, date_acquired) values ($1,'bk_baru_uji',9)`, [pid]);
  await H.sql(`update game.character_stats set combat = combat + 5 where player_id = $1`, [pid]);
  await H.sql(`update game.players set ship_upgrades = '{"speed":{"level":1,"tier":4,"accumulated":0},"condition":{"level":1,"tier":1,"accumulated":0}}' where player_id = $1`, [pid]);
  await H.sql(`insert into game.ship_equipment(player_id, slot_type, item_id) values ($1,'artifact','art_sunken_crown')`, [pid]);

  // --- PULIH ---
  const r = (await one(`select game.admin_pasir('pv_kaya','pulih') r`)).r;
  ok(r.hasil.bonus === 150000, 'bunga 10% dari gold + bank potret = 150.000: ' + r.hasil.bonus);
  const p2 = await one('select * from game.players where player_id = $1', [pid]);
  ok(Number(p2.gold) === 1000000 + 8000 + 150000, 'gold = potret + gold Pasir + bunga: ' + p2.gold);
  ok(Number(p2.bank_balance) === 501000 && Number(p2.debt_balance) === 20000, 'bank & utang kembali');
  ok(p2.ship_upgrades.speed.level === 2 && p2.ship_upgrades.speed.tier === 3, 'upgrade speed potret (lebih tinggi) menang');
  ok(p2.ship_upgrades.cargo.tier === 2 && p2.ship_upgrades.condition.tier === 1, 'upgrade digabung');
  ok(p2.ship_look && p2.ship_look.hull === '#123456', 'tampilan kapal kembali');
  const sh2 = await one('select * from game.ships where player_id = $1', [pid]);
  ok(sh2.ship_name === 'Elang Laut' && sh2.tier === 'IV' && sh2.cargo === 120 && Number(sh2.condition) === 77, 'baris kapal asli kembali');
  const eq = await H.sql('select slot_type, item_id from game.ship_equipment where player_id = $1 order by slot_type', [pid]);
  ok(eq.length === 1 && eq[0].item_id === 'art_current_charts', 'artifact potret terpasang lagi');
  const inv = await H.sql('select item_id, qty, cost from game.inventory where player_id = $1 order by item_id', [pid]);
  const g = Object.fromEntries(inv.map(x => [x.item_id, x]));
  ok(g.sugar && g.sugar.qty === 15 && Number(g.sugar.cost) === 1600, 'gula dijumlahkan dengan modal: ' + JSON.stringify(g.sugar));
  ok(g.garam && g.garam.qty === 20, 'muatan misi kembali ke palka');
  ok(g.kopi && g.kopi.qty === 7, 'barang order Bursa kembali ke palka');
  ok(g.art_smugglers_ring && g.art_smugglers_ring.qty === 1, 'item palka kembali');
  ok(g.art_sunken_crown && g.art_sunken_crown.qty === 1, 'artifact Pasir yang bentrok slot masuk palka');
  ok(Number((await one(`select qty from game.warehouse where player_id = $1 and city_id = 'joungjava'`, [pid])).qty) === 50, 'gudang kembali');
  ok(Number((await one('select count(*) n from game.player_books where player_id = $1', [pid])).n) === 2, 'buku lama + buku Pasir');
  const st2 = await one('select * from game.character_stats where player_id = $1', [pid]);
  ok(st2.combat === stats0.combat + 5 && st2.navigation === stats0.navigation && st2.trading === stats0.trading, 'stat potret + kenaikan Pasir');
  ok((await one('select equipped from game.kd_loadout where player_id = $1', [pid])).equipped.layar === 'layar_parang', 'rupa Kedai terpasang lagi');
  s = await P.call('api_getGameState', []);
  ok(s.pasir.era === 'kini' && s.unlocks.includes('paradiso') && s.unlocks.includes('empeer_depeer'), 'era kini, peta lama kembali');
  ok(!(await one('select game.dt_join_block($1) b', [pid])).b || !/Tak ada yang mengenal/.test((await one('select game.dt_join_block($1) b', [pid])).b), 'Serbuan terbuka lagi');
  await H.expectError(() => H.sql(`select game.admin_pasir('pv_kaya','pulih')`), /Tidak ada potret/);

  // Reset aman setelah pulih
  await H.sql(`select game.admin_pasir('pv_kaya','reset')`);
  ok(Number((await one('select count(*) n from game.pv_snap where player_id = $1', [pid])).n) === 0, 'reset menghapus potret yang sudah pulih');

  // --- Pemain miskin & berutang ---
  const M = await H.user('pv_miskin');
  await M.call('api_createCharacter', ['Kapten Miskin', 'pirate']);
  await H.sql(`update game.players set gold = 0, debt_balance = 90000 where player_id = $1`, [M.id]);
  await H.sql(`select game.admin_pasir('pv_miskin','ambil')`);
  let pm = await one('select gold, debt_balance from game.players where player_id = $1', [M.id]);
  ok(Number(pm.gold) === 5000 && Number(pm.debt_balance) === 0, 'miskin: 5000 gold, utang ditahan di potret');
  await H.sql(`update game.players set gold = 2000, debt_balance = 1000 where player_id = $1`, [M.id]);
  const rm = (await one(`select game.admin_pasir('pv_miskin','pulih') r`)).r;
  pm = await one('select gold, debt_balance from game.players where player_id = $1', [M.id]);
  ok(rm.hasil.bonus === 0 && Number(pm.gold) === 2000 && Number(pm.debt_balance) === 91000, 'miskin: tanpa bunga, utang kembali + utang Pasir');

  // Duel aktif menolak
  const D = await H.user('pv_duel');
  await D.call('api_createCharacter', ['Kapten Duel', 'merchant']);
  await H.sql(`create or replace function game.mp_sail_guard_uji(p uuid) returns void language plpgsql as $$ begin raise exception 'Selesaikan duelmu dulu sebelum berlayar.'; end $$`);
  const src = (await one(`select prosrc from pg_proc where proname = 'pv_ambil'`)).prosrc;
  ok(/mp_sail_guard/.test(src), 'ambil memanggil penjaga duel/armada');

  console.log('0040 pasir potret: semua lulus');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
