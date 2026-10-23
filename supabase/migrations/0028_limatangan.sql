-- =====================================================================
-- Marantau (Supabase) - 0028 SAGA 2 · QUEST 8 "LIMA TANGAN"
-- Prasyarat: Quest 7 (Malam Tiga Tanda Silang) selesai + saldo bank >= LimaTanganBankMin
-- (6.000.000; syarat SEMENTARA untuk uji coba DMSandris - ubah game.config ke 0 untuk membuka).
-- Pemicu: merapat di TooGood setelah penutup Quest 7 (prolog diputar klien, lalu 'prolog').
--
-- Langkah (game.player_quests, quest_id = 'limatangan'):
--   1  Babak 1  Lima Tangan (bebas urutan, kapal pemain sendiri):
--               kemudi Hasiolan (Skitraw, Balas Pantun) · peta coco epan (Joungjava, 10 kopi premium
--               + ikan pertama saat fajar) · mata dwi (Marie Regal, Mata Syahbandar laboratorium)
--               · meriam Bang Rimba (Paradiso malam, Adu Gasing; +Dadu bila Q5 bohong)
--               · Papan Ulin (Bjorneo, 3 teka-teki) · setor bahan dok di TooGood + 1 hari game
--               · (opsional) Kuas Perunggu Tedsky di IKN. 'launch' -> Black Pearl aktif.
--   2  Babak 2  Black Pearl berlayar -> 'freeyork' saat tiba di FreeYork
--   3  Babak 3  FreeYork: lunas ditambal (1 jam game), Tempa Pengait (mutu) -> 'fydone'
--   4  Babak 4  Laut Putih: Jaring Angin (kapal ditahan di mulut kabut), Ama Kerang, Marlin Garam
--               (siang/badai), Selam Mutiara (pagi), pilihan coco -> 'kgdone' (Kalung Karang)
--   5  Babak 5  Pelabuhan Rantai Lama: Sandi Pelikan (malam, 3 salah = malam berikutnya),
--               Olah Jejak (sekali jawab), surat untuk Hasiolan -> 'hasiolan'
--   6  Babak 6  Kota Sowtour: Blokade Gagak (gelombang), Om Baayu, tiga menara (satu per malam)
--   7           Mata Seribu menghadang setiap kapal yang meninggalkan Sowtour (3 fase, berantai)
--   8           zafachmie dibebaskan, Tari Genderang (sekutu Q9) -> 'sekutu'
--   9  Babak 7  Topi di Kemudi: 'tutup' -> hadiah, kapal sendiri kembali, pemain di TooGood
--  10  selesai
-- Black Pearl dipinjam langkah 2..9: ransum 10 Beras + 5 Garam (atau Ikan Asin) per pelayaran
-- Laut Timur; kurang = awak kelaparan, kapal putar balik ke asal, kondisi -30%.
-- Pasar dunia TIDAK dikacaukan. Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Konstanta & helper
-- ---------------------------------------------------------------------
insert into game.config(key, value) values ('LimaTanganBankMin', '6000000') on conflict (key) do nothing;

create or replace function game.lt_reward() returns bigint language sql immutable as $$ select 300000::bigint $$;
create or replace function game.lt_beras() returns int language sql immutable as $$ select 10 $$;
create or replace function game.lt_garam() returns int language sql immutable as $$ select 5 $$;
create or replace function game.lt_kopi_need() returns int language sql immutable as $$ select 10 $$;
create or replace function game.lt_ms_max() returns int language sql immutable as $$ select 9000 $$;

create or replace function game.lt_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'limatangan'), 0) $$;

create or replace function game.lt_data(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce((select data from game.player_quests where player_id = p_pid and quest_id = 'limatangan'), '{}'::jsonb) $$;

create or replace function game.lt_len_ms() returns bigint
language sql stable as $$ select greatest(60000, game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint $$;

-- satu "jam game" dalam milidetik nyata
-- Jam dunia (ms sejak WorldStartTimestamp): semua jeda quest memakai jam ini
create or replace function game.lt_wms() returns bigint
language sql stable as $$ select game.now_ms() - game.cfg_num('WorldStartTimestamp', 0)::bigint $$;

create or replace function game.lt_hour_ms() returns bigint
language sql stable as $$ select (game.lt_len_ms() / 24)::bigint $$;

-- Indeks malam dunia: malam (0.72..1.04 hari) mendapat satu nomor yang sama
create or replace function game.lt_night_idx() returns int
language sql stable as $$
  select floor((game.now_ms() - game.cfg_num('WorldStartTimestamp', 0)::bigint)::numeric / game.lt_len_ms() + 0.28)::int
$$;

create or replace function game.lt_bank_ok(p_pid uuid) returns boolean
language plpgsql as $$
begin
  return coalesce((game.bank_state(p_pid) ->> 'bankBalance')::numeric, 0) >= game.cfg_num('LimaTanganBankMin', 6000000);
exception when others then return false;
end $$;

-- Laut Timur: rute yang berangkat dari / menuju tempat-tempat ini
create or replace function game.lt_east_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city in ('freeyork', 'karang_garam', 'rantai_lama', 'sowtour', 'teluk_dua_tangan'), false) $$;

-- Black Pearl dipinjam selama langkah 2..9
create or replace function game.lt_pearl(p_pid uuid) returns boolean
language sql stable as $$ select game.lt_step(p_pid) between 2 and 9 $$;

create or replace function game.lt_east_route(p_pid uuid, p_origin text, p_dest text) returns boolean
language sql stable as $$ select game.lt_pearl(p_pid) and (game.lt_east_city(p_origin) or game.lt_east_city(p_dest)) $$;

-- Ransum: jumlah jatah pelayaran yang bisa dibiayai isi palka
create or replace function game.lt_ransum(p_pid uuid) returns int
language sql stable as $$
  select least(floor(game.item_qty(p_pid, 'beras') / game.lt_beras()::numeric),
               floor((game.item_qty(p_pid, 'garam') + game.item_qty(p_pid, 'ikan_asin')) / game.lt_garam()::numeric))::int
$$;

create or replace function game.lt_take_ransum(p_pid uuid) returns boolean
language plpgsql as $$
declare g int; ia int; need int := game.lt_garam();
begin
  if game.lt_ransum(p_pid) < 1 then return false; end if;
  perform game.adjust_inventory(p_pid, 'beras', -game.lt_beras());
  g := least(need, game.item_qty(p_pid, 'garam'));
  if g > 0 then perform game.adjust_inventory(p_pid, 'garam', -g); end if;
  ia := need - g;
  if ia > 0 then perform game.adjust_inventory(p_pid, 'ikan_asin', -ia); end if;
  return true;
end $$;

create or replace function game.lt_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = p_step, data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 10 then now() else done_at end
   where player_id = p_pid and quest_id = 'limatangan'
$$;

create or replace function game.lt_need_city(p_city text, p_need text, p_msg text) returns void
language plpgsql as $$ begin if p_city is distinct from p_need then raise exception '%', p_msg; end if; end $$;

-- Bahan dok di TooGood
create or replace function game.lt_dock_need() returns jsonb
language sql immutable as $$ select '{"qi_papan_ulin": 1, "kayu_jati": 20, "besi": 15, "rotan": 10, "mesiu": 20}'::jsonb $$;

create or replace function game.lt_dock_done(p_d jsonb) returns boolean
language sql immutable as $$
  select not exists (select 1 from jsonb_each_text(game.lt_dock_need()) n
                      where coalesce((p_d -> 'dock' ->> n.key)::int, 0) < n.value::int)
$$;

-- Jumlah sekutu dari skor Tari Genderang
create or replace function game.lt_allies(p_score int) returns int
language sql immutable as $$ select case when coalesce(p_score, -1) >= 85 then 3 when coalesce(p_score, -1) >= 60 then 2 when p_score is null then 0 else 1 end $$;

-- Mutu Pengait dari skor Tempa
create or replace function game.lt_grade(p_score int) returns text
language sql immutable as $$ select case when p_score >= 90 then 'sempurna' when p_score >= 70 then 'baik' when p_score >= 50 then 'kasar' else 'retak' end $$;

create or replace function game.lt_grade_rank(p_grade text) returns int
language sql immutable as $$ select case p_grade when 'sempurna' then 3 when 'baik' then 2 when 'kasar' then 1 else 0 end $$;

-- ---------------------------------------------------------------------
-- Item quest
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_papan_ulin', 'Papan Ulin Tua', 'quest',
   '{"cargoSize": 0, "desc": "Anak tangga paling bawah mercusuar Nenek Ulin, hitam legam dan berat seperti besi. \"Kapal yang tiangnya ulin tidak akan patah di laut yang belum punya nama.\""}',
   0, null, 'quest', 106),
  ('qi_kuas_tedsky', 'Kuas Perunggu Tedsky', 'quest',
   '{"cargoSize": 0, "desc": "Kuas besar berlepotan cat perunggu kering, dari anak-anak Kamp Pemulung IKN. \"Kalau ketemu Jendral, kembalikan. Bilang sayapnya belum selesai.\""}',
   0, null, 'quest', 107),
  ('qi_pengait', 'Pengait Pemecah Rantai', 'quest',
   '{"cargoSize": 0, "desc": "Pengait besi yang kau tempa sendiri di Dok Legenda FreeYork, terpasang di haluan Black Pearl. Rantai di perisai Tedsky ditempa di bengkel yang sama."}',
   0, null, 'quest', 108),
  ('qi_nasi_tassyaaa', 'Bungkusan Nasi Tassyaaa', 'quest',
   '{"cargoSize": 0, "desc": "Nasi dalam daun pisang yang masih hangat. \"Untuk Petrik. Kalau dia masih hidup.\""}',
   0, null, 'quest', 109),
  ('qi_kalung_karang', 'Kalung Karang', 'quest',
   '{"cargoSize": 0, "desc": "Hati Karang dari kima tua, dirangkai Ama Kerang dengan mutiara kecil yang kau bawa naik dengan napasmu sendiri. \"Tunjukkan pada laut kalau kau tersesat.\""}',
   0, null, 'quest', 110),
  ('qi_topi_coco', 'Topi Bowler Coco Epan', 'quest',
   '{"cargoSize": 0, "desc": "Tergantung di kemudi Black Pearl saat fajar, bersama sepucuk surat. Sekoci kapal hilang dari tempatnya."}',
   0, null, 'quest', 111)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Tiga tempat baru di Laut Timur (tersembunyi; terbuka per pemain)
--   Pelabuhan Rantai Lama = kota hantu: titik khusus quest (tanpa pasar, misi, bank, gudang)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('karang_garam', 'Kepulauan Karang Garam', 'Karang',     1.5, '', 168, 60, 15, true),
  ('rantai_lama',  'Pelabuhan Rantai Lama',  'RantaiLama', 1.0, '', 186, 88, 16, true),
  ('sowtour',      'Kota Sowtour',           'Sowtour',    2.0, '', 192, 44, 17, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;

select game.cfg_set('CitiesVersion', '7-limatangan');

create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city in ('titik_buta', 'pusaran', 'rantai_lama'), false) $$;

create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case p_type
    when 'TradeHub' then 'Pelabuhan sibuk tempat semua rute berpotongan - harga stabil, pilihan barang lengkap.'
    when 'Agricultural' then 'Lumbung wilayah ini - hasil bumi murah, barang mewah harus didatangkan dari luar.'
    when 'Remote' then 'Jauh dari jalur ramai - harga lebih mahal, tapi lebih sedikit persaingan pedagang.'
    when 'Capital' then 'Kota besar yang penuh sukacita - pasar paling lengkap, harga adil dan stabil untuk semua.'
    when 'Outlaw' then 'Sarang penyamun - kapal dagang menuju sini nyaris pasti dicegat bajak laut di tengah jalan. Senjata di sini selalu lebih murah dari kota manapun.'
    when 'FallenCapital' then 'Ibu kota lama yang sudah tumbang - reruntuhan megah dengan banyak yang perlu dibenahi. Papan misi paling ramai di sini, meski bayarannya seadanya.'
    when 'Paradise' then 'Surga para pelaut yang tak ada di peta mana pun - pesta, tarian, dan mata air panas. Kapal yang merapat di sini pulih dengan sendirinya.'
    when 'Regal' then 'Ibu kota Pemerintah Moramora. Menara kaca, lampu yang tak pernah padam, dan mesin yang bekerja tanpa suara. Tak ada satu manusia pun di dermaganya.'
    when 'BlindSpot' then 'Titik di tengah laut tak bertuan yang hanya muncul saat lampu-lampu dinyalakan. Tak ada dermaga - hanya perahu tanpa bendera yang menunggu.'
    when 'Maelstrom' then 'Pusaran air raksasa di bawah langit ungu dan petir biru. Armada Terakhir berjaga di tepinya - kapalmu dirawat di sini, tapi tak ada pasar di tengah badai.'
    when 'Gading' then 'Kepulauan di laut timur yang jauh. Lampion merah di sepanjang dermaga, asap dupa dari klenteng tua, dan pintu toko yang dibuka sebelum matahari. Porselen dan sutranya terkenal, kopinya lebih lagi.'
    when 'Kincir' then 'Pulau datar yang tak pernah sepi angin. Puluhan kincir kayu memompa ladang garam dan menjemur biji kopi. Garam, ikan asin, dan kopinya murah; kain dan perkakas selalu dicari.'
    when 'Dewan' then 'Pulau para bangsawan pengungsi. Gedung Kubah di ujung tangga panjang, karpet merah yang menipis, dan izin bersandar yang harus dicap tujuh kali. Sutra dan porselennya halus; gula, arak, dan rempah selalu kurang.'
    when 'Tempa' then 'Tanah pandai besi. Tambang batu bara di lereng, cerobong yang menyala siang-malam, dan Dok Legenda tempat Black Pearl dulu ditempa. Besi, perkakas, dan senjata murah; beras dan garam dibeli mahal.'
    when 'Karang' then 'Gugusan karang putih di balik kabut timur. Desa penyelam di atas tiang, ladang garam berkilau, dan benteng karang yang tumbuh sendiri. Garam, ikan asin, dan mutiaranya murah; beras dan kayu selalu kurang. Tak ada sawah di laut timur.'
    when 'RantaiLama' then 'Bekas pelabuhan budak di pesisir Benua Moramora. Tiang-tiang pasung berkarat, gudang tanpa pintu, lonceng pelelangan tanpa tali. Tak ada pedagang, tak ada galangan - hanya angin.'
    when 'Sowtour' then 'Kota leluhur Sang Penjaga Suara di Benua Moramora. Menara batu bercermin dan sarang pelikan di setiap puncak. Porselen dan perkakasnya halus; beras, garam, dan arak didatangkan dari jauh.'
    else '' end
$$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
      or (p_city = 'titik_buta' and game.fish_is_night() and (game.bx_step(p_pid) = 4 or game.ts_step(p_pid) = 7))
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'gading_island' and game.cb_step(p_pid) >= 4)
      or (p_city = 'otoland' and game.ts_step(p_pid) >= 3)
      or (p_city = 'empeer_depeer' and game.ts_step(p_pid) >= 4)
      or (p_city = 'freeyork' and game.ts_step(p_pid) >= 5)
      or (p_city = 'karang_garam' and game.lt_step(p_pid) >= 4)
      or (p_city = 'rantai_lama' and game.lt_step(p_pid) >= 5)
      or (p_city = 'sowtour' and game.lt_step(p_pid) >= 6)
$$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$
  select (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
      || (case when game.ww_step(p_pid) >= 1 then '["marie_regal"]'::jsonb else '[]'::jsonb end)
      || (case when game.fish_is_night() and (game.bx_step(p_pid) = 4 or game.ts_step(p_pid) = 7) then '["titik_buta"]'::jsonb else '[]'::jsonb end)
      || (case when game.bx_step(p_pid) between 7 and 15 then '["pusaran"]'::jsonb else '[]'::jsonb end)
      || (case when game.cb_step(p_pid) >= 4 then '["gading_island"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 3 then '["otoland"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 4 then '["empeer_depeer"]'::jsonb else '[]'::jsonb end)
      || (case when game.ts_step(p_pid) >= 5 then '["freeyork"]'::jsonb else '[]'::jsonb end)
      || (case when game.lt_step(p_pid) >= 4 then '["karang_garam"]'::jsonb else '[]'::jsonb end)
      || (case when game.lt_step(p_pid) >= 5 then '["rantai_lama"]'::jsonb else '[]'::jsonb end)
      || (case when game.lt_step(p_pid) >= 6 then '["sowtour"]'::jsonb else '[]'::jsonb end)
$$;

create or replace function game.voy_far_city(p_city text) returns boolean
language sql immutable as $$ select p_city in ('gading_island', 'otoland', 'empeer_depeer', 'freeyork', 'karang_garam', 'rantai_lama', 'sowtour', 'teluk_dua_tangan') $$;

-- Peran pasar dua tempat baru (Rantai Lama tanpa pasar). Ditulis ulang SETIAP deploy.
create or replace function game.lt_market_role(p_city text, p_comm text) returns text
language sql immutable as $$
  select case p_city
    when 'karang_garam' then
      case when p_comm in ('garam', 'ikan_asin', 'mutiara') then 'produce'
           when p_comm in ('beras', 'kayu_jati', 'tools') then 'consume' else 'neutral' end
    when 'sowtour' then
      case when p_comm in ('porselen', 'tools') then 'produce'
           when p_comm in ('beras', 'garam', 'rum') then 'consume' else 'neutral' end
    else null end
$$;

insert into game.market(city_id, commodity_id, base_price, current_price, role)
select ci.city_id, co.id, co.base, co.base, coalesce(game.lt_market_role(ci.city_id, co.id), 'neutral')
  from game.cities ci cross join game.commodities co
 where co.active and ci.city_id in ('karang_garam', 'sowtour')
on conflict (city_id, commodity_id) do update set base_price = excluded.base_price, role = excluded.role;

-- ---------------------------------------------------------------------
-- Black Pearl (dipinjam langkah 2..9). Kapal pemain disimpan di data quest.
-- ---------------------------------------------------------------------
create or replace function game.ship_legend(p_pid uuid) returns text
language sql stable as $$ select case when game.tg_step(p_pid) between 8 and 9 or game.lt_pearl(p_pid) then 'pearl' end $$;

create or replace function game.ship_locked(p_pid uuid) returns text
language sql stable as $$
  select case when game.tg_step(p_pid) between 8 and 9 or game.lt_pearl(p_pid)
    then 'Black Pearl adalah kapal legenda TooGood - tidak bisa dicat ulang atau diganti nama.' end
$$;

create or replace function game.lt_pearl_on(p_pid uuid) returns void
language plpgsql as $$
declare s game.ships; up jsonb;
begin
  select * into s from game.ships where player_id = p_pid for update;
  select coalesce(ship_upgrades, '{}'::jsonb) into up from game.players where player_id = p_pid;
  if jsonb_typeof(up) <> 'object' then up := '{}'::jsonb; end if;
  update game.player_quests set data = data || jsonb_build_object('own', jsonb_build_object('ship', to_jsonb(s), 'upgrades', up))
   where player_id = p_pid and quest_id = 'limatangan';
  update game.players set ship_upgrades = up || jsonb_build_object(
      'speed', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0),
      'condition', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 200),
      'cannons', jsonb_build_object('level', 5, 'tier', 4, 'accumulated', 0))
   where player_id = p_pid;
  update game.ships set ship_name = 'Black Pearl', tier = 'V', speed = s.speed + 25, combat = s.combat + 40,
      armor = s.armor + 40, navigation = s.navigation + 20, condition = 300
   where player_id = p_pid;
end $$;

create or replace function game.lt_pearl_off(p_pid uuid) returns void
language plpgsql as $$
declare own jsonb; cur jsonb; eff numeric;
begin
  select data -> 'own' into own from game.player_quests where player_id = p_pid and quest_id = 'limatangan';
  if own is null then return; end if;
  select coalesce(ship_upgrades, '{}'::jsonb) into cur from game.players where player_id = p_pid;
  update game.players set ship_upgrades = coalesce(own -> 'upgrades', '{}'::jsonb)
      || case when cur ? 'cargo' then jsonb_build_object('cargo', cur -> 'cargo') else '{}'::jsonb end
   where player_id = p_pid;
  update game.ships set ship_name = own -> 'ship' ->> 'ship_name', tier = own -> 'ship' ->> 'tier',
      speed = (own -> 'ship' ->> 'speed')::int, combat = (own -> 'ship' ->> 'combat')::int,
      armor = (own -> 'ship' ->> 'armor')::int, navigation = (own -> 'ship' ->> 'navigation')::int
   where player_id = p_pid;
  eff := game.voy_num(game.ship_json(p_pid) -> 'EffectiveMaxCondition');
  update game.ships set condition = eff where player_id = p_pid;
  update game.player_quests set data = data - 'own' where player_id = p_pid and quest_id = 'limatangan';
end $$;

-- ---------------------------------------------------------------------
-- Waktu tempuh: Black Pearl tetap 15 dtk di Mare Nusantara, tapi di Laut Timur arusnya melawan
-- (waktu tempuh normal kapal Tier V). Penanda 'LegendEast' dikirim oleh setSail/getSailOptions.
-- Isi selain penanda identik dengan 0024.
-- ---------------------------------------------------------------------
create or replace function game.voy_travel_seconds(p_distance double precision, p_ship jsonb) returns int
language plpgsql stable as $$
declare lo double precision; hi double precision; r record; frac double precision; base_t double precision;
  base_speed double precision; spd double precision; mult double precision; eff double precision;
  fast double precision; floor_mult constant double precision := 0.24; f double precision; tm double precision;
begin
  if coalesce(p_ship ->> 'Legend', '') = 'pearl' and not coalesce((p_ship ->> 'LegendEast')::boolean, false) then
    return greatest(5, game.cfg_num('TravelLegendSeconds', 15))::int;
  end if;
  lo := greatest(10, game.cfg_num('TravelMinSeconds', 120));
  hi := greatest(lo, game.cfg_num('TravelMaxSeconds', 240));
  fast := least(lo, greatest(5, game.cfg_num('TravelFastestSeconds', 25)));
  select * into r from game.voy_dist_range();
  frac := case when r.dmax > r.dmin then least(1.5, greatest(0, (p_distance - r.dmin) / (r.dmax - r.dmin))) else 0 end;
  base_t := lo + (hi - lo) * frac;
  base_speed := greatest(1, game.cfg_num('BaselineShipSpeed', 50));
  spd := coalesce(nullif(game.voy_num(p_ship -> 'Speed'), 0), base_speed);
  mult := coalesce(nullif(game.voy_num(p_ship -> 'SpeedMultiplier'), 0), 1);
  mult := least(1, greatest(floor_mult, mult));
  eff := least(1, greatest(floor_mult, floor_mult + (mult - floor_mult) * base_speed / spd));
  f := fast / lo + (1 - fast / lo) * (eff - floor_mult) / (1 - floor_mult);
  tm := coalesce(nullif(game.voy_num(p_ship -> 'TravelMul'), 0), 1);
  if tm < 1 then f := greatest(fast / lo, f * tm); end if;
  return greatest(1, round(base_t * f))::int;
end $$;

-- Tide v35: penyesuaian per rute dipisah dari ship_json supaya daftar tujuan (api_getSailOptions)
-- cukup menghitung kapal SEKALI, bukan sekali per pulau. Isi penyesuaian tidak berubah.
create or replace function game.lt_route_ship(p_pid uuid, p_origin text, p_dest text, p_sh jsonb) returns jsonb
language sql stable as $$
  select coalesce(p_sh, '{}'::jsonb)
      || case when game.lt_east_route(p_pid, p_origin, p_dest) then '{"LegendEast": true}'::jsonb else '{}'::jsonb end
$$;
create or replace function game.lt_ship_for_route(p_pid uuid, p_origin text, p_dest text) returns jsonb
language sql stable as $$
  select game.lt_route_ship(p_pid, p_origin, p_dest, game.ship_json(p_pid))
$$;

-- api_setSail (isi identik dengan 0003, kecuali kapal per rute untuk waktu tempuh)
create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_dest text := game.arg(a, 0);
  v_me game.players;
  l game.player_location;
  v_origin_name text; v_dest_name text; dist double precision; secs int; t_depart timestamptz; t_arrive timestamptz;
begin
  select name into v_dest_name from game.cities where city_id = v_dest;
  if v_dest_name is null then raise exception 'Kota tujuan tidak dikenali: %', coalesce(v_dest, 'undefined'); end if;

  v_me := game.me(true);
  if not game.city_open(v_me.player_id, v_dest) then raise exception 'Kota tujuan tidak dikenali: %', v_dest; end if;
  perform game.resolve_arrival_if_due(v_me.player_id);

  select * into l from game.player_location where player_id = v_me.player_id for update;
  if not found then raise exception 'Data lokasi pemain tidak ditemukan.'; end if;
  if jsonb_typeof(l.pending_encounter) = 'object' then
    raise exception 'Kapal sedang dicegat bajak laut - selesaikan pertempuran dulu sebelum berlayar lagi.';
  end if;
  if coalesce(l.destination_city_id, '') <> '' then raise exception 'Kamu sudah dalam perjalanan menuju kota lain.'; end if;
  if l.city_id = v_dest then raise exception 'Kamu sudah berada di kota ini.'; end if;

  select name into v_origin_name from game.cities where city_id = l.city_id;
  if v_origin_name is null then raise exception 'Kota asal tidak dikenali: %', l.city_id; end if;

  dist := game.voy_map_distance(l.city_id, v_dest);
  secs := game.voy_travel_seconds(dist, game.lt_ship_for_route(v_me.player_id, l.city_id, v_dest));
  t_depart := now();
  t_arrive := t_depart + make_interval(secs => secs);

  update game.player_location set destination_city_id = v_dest, depart_at = t_depart, arrive_at = t_arrive
   where player_id = v_me.player_id;

  perform game.log(v_me.player_id, 'Set sail from ' || v_origin_name || ' toward ' || v_dest_name || '.');

  begin
    perform game.mp_mark_sea(v_me.player_id, v_dest);
  exception when others then
    null;
  end;
  perform game.quest_on_sail(v_me.player_id, l.city_id, v_dest);

  return jsonb_build_object('originCityId', l.city_id, 'destinationCityId', v_dest,
    'departAt', game.iso(t_depart), 'arriveAt', game.iso(t_arrive), 'travelSeconds', secs, 'travelRealMinutes', round(secs / 60.0, 2),
    'ransum', case when game.lt_pearl(v_me.player_id) then game.lt_ransum(v_me.player_id) end);
end $$;
select game.expose('api_setsail');

create or replace function public.api_getSailOptions(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); l game.player_location; out jsonb; v_sh jsonb;
begin
  select * into l from game.player_location where player_id = v_me.player_id;
  if not found then raise exception 'Data lokasi pemain tidak ditemukan.'; end if;
  if not exists (select 1 from game.cities where city_id = l.city_id) then
    raise exception 'Kota asal tidak dikenali: %', l.city_id;
  end if;
  -- Tide v35: kapal dihitung sekali; penyesuaian per rute & waktu tempuh sekali per pulau
  v_sh := game.ship_json(v_me.player_id);
  select coalesce(jsonb_agg(jsonb_build_object(
      'cityId', c.city_id,
      'name', c.name,
      'distance', round((floor(d.dist * 10 + 0.5) / 10)::numeric, 1),
      'etaSeconds', t.secs,
      'etaMinutes', round(t.secs / 60.0, 2),
      'ransum', game.lt_east_route(v_me.player_id, l.city_id, c.city_id),
      'eventLabel', ev ->> 'label',
      'eventType', ev ->> 'eventType') order by c.sort, c.city_id), '[]'::jsonb)
    into out
    from game.cities c
    cross join lateral (select game.voy_map_distance(l.city_id, c.city_id) as dist) d
    cross join lateral (select game.lt_route_ship(v_me.player_id, l.city_id, c.city_id, v_sh) as ship) sh
    cross join lateral (select game.voy_travel_seconds(d.dist, sh.ship) as secs offset 0) t
    cross join lateral (select game.city_event(c.city_id) as ev) e
   where c.city_id <> l.city_id and game.city_open(v_me.player_id, c.city_id);
  return out;
end $$;
select game.expose('api_getsailoptions');

-- ---------------------------------------------------------------------
-- Reparasi: tidak ada galangan di Pelabuhan Rantai Lama; di Sowtour baru buka setelah kota bercahaya
-- (isi selain penanda 'blocked' identik dengan 0003)
-- ---------------------------------------------------------------------
create or replace function game.lt_repair_block(p_pid uuid, p_city text) returns text
language sql stable as $$
  select case
    when p_city = 'rantai_lama' then 'Tak ada galangan di kota hantu ini, Kapten. Hanya tiang pasung dan angin.'
    when p_city = 'sowtour' and game.lt_step(p_pid) between 1 and 6 then 'Galangan Sowtour tutup. Warga bersembunyi di balik kain hitam; tak ada yang berani bekerja di bawah mata burung itu.'
    else null end
$$;

create or replace function game.voy_repair_quote(p_pid uuid, p_city text) returns jsonb
language plpgsql stable as $$
declare s game.ships; mx numeric; cur numeric; missing numeric; rate numeric; cost numeric;
begin
  select * into s from game.ships where player_id = p_pid;
  if not found then raise exception 'Kapal tidak ditemukan.'; end if;
  mx := game.voy_max_cond(p_pid);
  cur := least(coalesce(s.condition, mx), mx);
  missing := greatest(0, mx - cur);
  select repair_cost_rate into rate from game.cities where city_id = p_city;
  if rate is null or rate = 0 then rate := 1; end if;
  -- Tide v33: Resep Ramuan Sinshe Tan -25% (tidak untuk Black Pearl)
  if game.ship_book_effect(p_pid, 'gd_ramuan') then rate := rate * 0.75; end if;
  cost := game.voy_round(missing * game.cfg_num('ShipRepairBaseCostPerPoint', 15) * rate);
  return jsonb_build_object('currentCondition', game.voy_round(cur), 'maxCondition', mx,
    'missing', game.voy_round(missing), 'cost', cost, 'blocked', game.lt_repair_block(p_pid, p_city));
end $$;

create or replace function public.api_repairShip(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players; q jsonb; cost bigint; mx numeric;
begin
  v_me := game.me(true);
  if (game.voyage_state(v_me.player_id) ->> 'inTransit')::boolean then
    raise exception 'Kamu sedang berlayar - reparasi hanya bisa dilakukan saat merapat di pelabuhan.';
  end if;
  if game.current_city(v_me.player_id) is distinct from v_city then
    raise exception 'Kamu harus berada di kota ini untuk reparasi.';
  end if;
  q := game.voy_repair_quote(v_me.player_id, v_city);
  if q ->> 'blocked' is not null then raise exception '%', q ->> 'blocked'; end if;
  if (q ->> 'missing')::numeric <= 0 then raise exception 'Kapal sudah dalam kondisi penuh.'; end if;
  cost := (q ->> 'cost')::bigint;
  mx := (q ->> 'maxCondition')::numeric;
  if v_me.gold < cost then
    raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', cost, v_me.gold;
  end if;
  update game.ships set condition = mx where player_id = v_me.player_id;
  update game.players set gold = v_me.gold - cost where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Repaired the ship at ' || game.city_name(v_city) ||
    ' for ' || cost || ' gold (Condition restored to ' || mx || ').');
  return jsonb_build_object('success', true, 'newCondition', mx, 'goldSpent', cost, 'newGold', v_me.gold - cost);
end $$;
select game.expose('api_repairship');

-- ---------------------------------------------------------------------
-- Status (kunci 'limatangan' di api_getGameState)
-- ---------------------------------------------------------------------
create or replace function game.lt_tower_allow(p_d jsonb) returns int
language plpgsql stable as $$
declare n int := game.lt_night_idx(); logs jsonb := coalesce(p_d -> 'towerLog', '[]'::jsonb); tonight int; prev boolean; any_before boolean; allow int := 1;
begin
  select count(*) into tonight from jsonb_array_elements(logs) e where (e ->> 'n')::int = n;
  select exists (select 1 from jsonb_array_elements(logs) e where (e ->> 'n')::int = n - 1) into prev;
  select exists (select 1 from jsonb_array_elements(logs) e where (e ->> 'n')::int < n) into any_before;
  -- katup: malam sebelumnya gagal atau terlewat (setelah mulai menyalakan) -> boleh dua cahaya malam ini
  if exists (select 1 from jsonb_array_elements(logs) e where (e ->> 'n')::int = n - 1 and not (e ->> 'ok')::boolean)
     or (any_before and not prev) then allow := 2; end if;
  return greatest(0, allow - tonight);
end $$;

create or replace function game.lt_waves(p_pid uuid) returns int
language plpgsql stable as $$
declare d jsonb := game.lt_data(p_pid); lit int := coalesce((d ->> 'lit')::int, 0); fails int := coalesce((d ->> 'towerFails')::int, 0);
begin
  if game.lt_step(p_pid) <> 6 or lit >= 3 then return 0; end if;
  return greatest(0, least(3, 3 - lit + fails));
end $$;

create or replace function game.lt_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_step int; d jsonb; v_truth text; v_now bigint := game.lt_wms(); v_frac numeric := game.lg_day_frac();
begin
  if game.ts_step(p_pid) < 12 then return null; end if;
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'limatangan';
  v_step := coalesce(q.step, 0);
  d := coalesce(q.data, '{}'::jsonb);
  v_truth := game.ts_truth(p_pid);
  return jsonb_build_object(
    'step', v_step,
    'bankOk', v_step > 0 or game.lt_bank_ok(p_pid),
    'bankNeed', game.cfg_num('LimaTanganBankMin', 6000000),
    'truth', v_truth,
    'tempa', game.ts_data(p_pid) ->> 'tempa',
    'night', game.fish_is_night(), 'dawn', game.cb_is_dawn(), 'pagi', v_frac >= 0.07 and v_frac < 0.25,
    'siang', v_frac >= 0.25 and v_frac < 0.55, 'frac', round(v_frac, 4), 'nightIdx', game.lt_night_idx(),
    'hourMs', game.lt_hour_ms(), 'now', v_now) || jsonb_build_object(
    -- Babak 1
    'hands', jsonb_build_object('kunci', v_step >= 1, 'kemudi', coalesce((d ->> 'kemudi')::boolean, false),
      'peta', coalesce((d ->> 'peta')::boolean, false), 'mata', coalesce((d ->> 'mata')::boolean, false),
      'meriam', coalesce((d ->> 'meriam')::boolean, false)),
    'dock', coalesce(d -> 'dock', '{}'::jsonb), 'dockNeed', game.lt_dock_need(),
    'dockReadyAt', (d ->> 'dockReadyAt')::bigint,
    'dockReady', (d ->> 'dockReadyAt') is not null and v_now >= (d ->> 'dockReadyAt')::bigint,
    'pantunAt', (d ->> 'pantunAt')::bigint, 'pantunPerfect', coalesce((d ->> 'pantunPerfect')::boolean, false),
    'cocoKopi', coalesce((d ->> 'cocoKopi')::int, 0), 'kopiNeed', game.lt_kopi_need(), 'cocoFish', coalesce((d ->> 'cocoFish')::boolean, false),
    'labDone', coalesce((d ->> 'mata')::boolean, false), 'titikInti', coalesce((d ->> 'titikInti')::boolean, false),
    'rimbaLoss', coalesce((d ->> 'rimbaLoss')::int, 0), 'rimbaNight', (d ->> 'rimbaNight')::int,
    'diceWins', coalesce((d ->> 'diceWins')::int, 0), 'diceLoss', coalesce((d ->> 'diceLoss')::int, 0),
    'diceDone', coalesce((d ->> 'diceDone')::boolean, false) or coalesce(v_truth, 'jujur') <> 'bohong',
    'ulinIdx', coalesce((d ->> 'ulinIdx')::int, 0), 'ulinAt', (d ->> 'ulinAt')::bigint, 'ulinWrong', coalesce(d -> 'ulinWrong', '{}'::jsonb),
    'hasUlin', game.item_qty(p_pid, 'qi_papan_ulin') > 0 or coalesce((d -> 'dock' ->> 'qi_papan_ulin')::int, 0) > 0,
    'kuas', game.item_qty(p_pid, 'qi_kuas_tedsky') > 0) || jsonb_build_object(
    -- Black Pearl & ransum
    'pearl', game.lt_pearl(p_pid), 'ransum', game.lt_ransum(p_pid), 'ransumBeras', game.lt_beras(), 'ransumGaram', game.lt_garam(),
    'beras', game.item_qty(p_pid, 'beras'), 'garam', game.item_qty(p_pid, 'garam'), 'ikanAsin', game.item_qty(p_pid, 'ikan_asin'),
    'besi', game.item_qty(p_pid, 'besi'), 'hungry', d -> 'hungry', 'hungerAt', (d ->> 'hungerAt')::bigint,
    -- Babak 3
    'lunasAt', (d ->> 'lunasAt')::bigint, 'lunasReady', (d ->> 'lunasAt') is not null and v_now >= (d ->> 'lunasAt')::bigint,
    'hookGrade', d ->> 'hookGrade', 'hookScore', (d ->> 'hookScore')::int, 'hookAt', (d ->> 'hookAt')::bigint,
    'hookDay', (d ->> 'hookDay')::int, 'gameDay', game.game_day(), 'tempaFree', not (d ? 'hookScore')) || jsonb_build_object(
    -- Babak 4
    'windDue', v_step = 4 and not coalesce((d ->> 'windDone')::boolean, false) and game.in_transit(p_pid)
               and (select destination_city_id from game.player_location where player_id = p_pid) = 'karang_garam',
    'windDone', coalesce((d ->> 'windDone')::boolean, false), 'windRetries', (d ->> 'windRetries')::int,
    'ama', coalesce((d ->> 'ama')::boolean, false), 'marlin', coalesce((d ->> 'marlin')::boolean, false),
    'diveHeart', coalesce((d ->> 'diveHeart')::boolean, false), 'beads', coalesce((d ->> 'beads')::int, 0),
    'diveRestAt', (d ->> 'diveRestAt')::bigint, 'cocoAdvice', d ->> 'cocoAdvice',
    -- Babak 5
    'sandiDone', coalesce((d ->> 'sandiDone')::boolean, false), 'sandiFails', coalesce((d ->> 'sandiFails')::int, 0),
    'sandiNight', (d ->> 'sandiNight')::int, 'sandiNights', coalesce((d ->> 'sandiNights')::int, 0),
    'jejakDone', d ? 'jejakOk', 'jejakOk', coalesce((d ->> 'jejakOk')::boolean, false),
    'hasiolan', d ->> 'hasiolan') || jsonb_build_object(
    -- Babak 6
    'baayu', coalesce((d ->> 'baayu')::boolean, false), 'lit', coalesce((d ->> 'lit')::int, 0), 'towerLog', coalesce(d -> 'towerLog', '[]'::jsonb),
    'clean', coalesce((d ->> 'clean')::int, 0), 'towerFails', coalesce((d ->> 'towerFails')::int, 0),
    'towerAllow', game.lt_tower_allow(d), 'waves', game.lt_waves(p_pid), 'blokWins', coalesce((d ->> 'blokWins')::int, 0),
    'msPhase', coalesce((d ->> 'msPhase')::int, 1), 'msHp', coalesce((d ->> 'msHp')::int, game.lt_ms_max()), 'msMax', game.lt_ms_max(),
    'msK', coalesce((d ->> 'msK')::int, 0),
    'zafa', coalesce((d ->> 'zafa')::boolean, false), 'drumBest', (d ->> 'drumBest')::int, 'drumAt', (d ->> 'drumAt')::bigint,
    'allies', game.lt_allies((d ->> 'drumBest')::int),
    'reward', (d ->> 'reward')::bigint,
    'done', v_step >= 10);
end $$;

-- ---------------------------------------------------------------------
-- Berangkat: ransum Black Pearl di Laut Timur
-- ---------------------------------------------------------------------
create or replace function game.lt_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  if not game.lt_east_route(p_pid, p_origin, p_dest) then return; end if;
  if game.lt_take_ransum(p_pid) then
    update game.player_quests set data = (data - 'hungry') || jsonb_build_object('sails', coalesce((data ->> 'sails')::int, 0) + 1), updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan';
  else
    update game.player_quests set data = data || jsonb_build_object('hungry', jsonb_build_object('from', p_origin, 'to', p_dest, 'at', game.now_ms())), updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan';
    perform game.log(p_pid, 'Black Pearl berangkat dengan palka ransum kosong. Awak saling pandang.');
  end if;
end $$;

create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  perform game.mp_sail_guard(p_pid);
  perform game.ww_on_sail(p_pid, p_origin, p_dest);
  perform game.bx_on_sail(p_pid, p_origin, p_dest);
  perform game.kp_on_sail(p_pid, p_origin, p_dest);
  perform game.ts_on_sail(p_pid, p_origin, p_dest);
  perform game.lt_on_sail(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Tiba: awak kelaparan -> putar balik; mulut kabut -> kapal ditahan sampai Jaring Angin
-- ---------------------------------------------------------------------
create or replace function game.lt_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_arrive timestamptz; eff numeric; v_name text;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'limatangan' for update;
  if not found then return null; end if;
  if jsonb_typeof(q.data -> 'hungry') = 'object' then
    eff := game.voy_num(game.ship_json(p_pid) -> 'EffectiveMaxCondition');
    perform game.apply_condition_delta(p_pid, -round(eff * 0.3));
    update game.player_quests set data = (data - 'hungry') || jsonb_build_object('hungerAt', game.now_ms(), 'hungerN', coalesce((data ->> 'hungerN')::int, 0) + 1), updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan';
    select name into v_name from game.cities where city_id = p_origin;
    perform game.log(p_pid, 'Awak kelaparan di tengah Laut Timur. Black Pearl memutar haluan sendiri dan pulang ke ' || coalesce(v_name, p_origin) || '. Lambungnya lecet di karang (-30% kondisi).');
    return jsonb_build_object('city', p_origin, 'kind', 'hunger', 'quiet', true, 'at', game.now_ms(),
      'message', 'Awak kelaparan. Di tengah laut, Black Pearl memutar haluannya sendiri, seperti kata buku log zafachmie: ia lebih sayang awaknya daripada nakhodanya. Kapal pulang ke ' || coalesce(v_name, p_origin) || ' dengan lambung lecet.');
  end if;
  if q.step = 4 and p_dest = 'karang_garam' and not coalesce((q.data ->> 'windDone')::boolean, false) then
    select arrive_at into v_arrive from game.player_location where player_id = p_pid;
    if now() < coalesce(v_arrive, now()) + interval '10 minutes' then
      return jsonb_build_object('hold', true, 'kind', 'kabut');
    end if;
    update game.player_quests set data = data || jsonb_build_object('windDone', true, 'windRetries', 0), updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan';
  end if;
  return null;
end $$;

create or replace function game.quest_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
begin
  return coalesce(game.kp_arrival_redirect(p_pid, p_origin, p_dest), game.lt_arrival_redirect(p_pid, p_origin, p_dest));
end $$;

-- ---------------------------------------------------------------------
-- Pertempuran: Blokade Gagak (menuju Sowtour) & Gagak Induk "Mata Seribu" (meninggalkan Sowtour)
-- ---------------------------------------------------------------------
create or replace function game.lt_enc(p_pid uuid, p_kind text, p_n int default 1, p_of int default 1) returns jsonb
language plpgsql volatile as $$
declare d jsonb := game.lt_data(p_pid); ammo numeric := game.ww_ammo(p_pid); base jsonb; mx int := game.lt_ms_max();
  hp numeric := least(mx, greatest(1, coalesce((d ->> 'msHp')::numeric, mx))); clean int := coalesce((d ->> 'clean')::int, 0);
  meriam boolean := coalesce((d ->> 'meriam')::boolean, false);
begin
  base := jsonb_build_object('lt', true, 'boss', p_kind, 'rolledAt', game.iso(now()), 'round', 1,
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'softSink', true, 'retreat', true, 'retreatOk', true, 'noRam', true,
    'allyDmg', case when meriam then 120 else 0 end, 'allyNote', 'Meriam Armada Bebas',
    'noRamMsg', 'Menabrak kawanan burung logam? Mereka akan menyebar lalu menyerbu layarmu.',
    'noTalkMsg', 'Tak ada yang bisa diajak bicara. Hanya klik-klik logam dan mata-mata merah.');
  if p_kind = 'gagak' then
    return base || jsonb_build_object('enemyName', 'Kawanan Gagak Mesin', 'bossTitle', 'Blokade Gagak - gelombang ' || p_n || '/' || p_of,
      'waveNo', p_n, 'waves', p_of, 'displayLevel', 7, 'enemyLevel', 5, 'enemyMaxHp', 1200, 'enemyHp', 1200,
      'dmgTaken', 0.6, 'enemyDmgMul', 2.0, 'smoke', p_n = 1,
      'retreatMsg', 'Kau memutar haluan menjauhi kota menara. Kawanan gagak tidak mengejar; mereka hanya menjaga pintunya.');
  end if;
  if p_kind = 'kawanan' then
    return base || jsonb_build_object('enemyName', 'Kawanan Pelindung', 'bossTitle', 'Gagak Induk memanggil kawanan pelindung',
      'displayLevel', 8, 'enemyLevel', 6, 'enemyMaxHp', 900, 'enemyHp', 900, 'dmgTaken', 0.3, 'enemyDmgMul', 3.4, 'smoke', true,
      'retreatMsg', 'Kau berbalik ke dermaga Sowtour. Luka di tubuh Mata Seribu tidak sembuh.');
  end if;
  base := base || jsonb_build_object('enemyName', 'Gagak Induk "Mata Seribu"', 'displayLevel', 12, 'enemyLevel', 8,
    'enemyMaxHp', mx, 'enemyHp', hp, 'dmgTaken', 0.09,
    'noRamMsg', 'Burung logam sebesar perahu itu melayang di atas tiangmu. Tak ada yang bisa ditabrak.',
    'noTalkMsg', 'Dari pengeras suara di seluruh kota terdengar suara datar: "Diam adalah bentuk kerja sama tertinggi."',
    'retreatMsg', 'Om Baayu menyalakan cermin menara ke mata burung itu - kau sempat mundur ke dermaga Sowtour. Lukanya tidak sembuh.');
  if p_kind = 'ms_a' then
    return base || jsonb_build_object('bossTitle', 'Mesin pengendali semua gagak hitam', 'hpFloor', 6000, 'enemyDmgMul', 1.9);
  elsif p_kind = 'ms_b' then
    return base || jsonb_build_object('bossTitle', 'Mesin pengendali semua gagak hitam - sayapnya retak', 'hpFloor', 4500, 'enemyDmgMul', 1.9);
  end if;
  -- murka fase 3 mengikuti menara yang menyala pada percobaan pertama (dikalibrasi lewat simulasi, Tide v32)
  return base || jsonb_build_object('bossTitle', 'Inti merah terbuka - Hening', 'final', true, 'enemyHp', least(hp, 4500), 'dmgTaken', 0.12,
    'enemyDmgMul', 2.6 * (case clean when 3 then 1.0 when 2 then 1.25 when 1 then 1.55 else 1.9 end), 'clean', clean);
end $$;

-- Urutan fase 1 Mata Seribu: segmen A -> kawanan -> segmen B -> (kawanan kedua, tanpa Titik Inti) -> fase 3
create or replace function game.lt_ms_next(p_pid uuid) returns jsonb
language plpgsql volatile as $$
declare d jsonb := game.lt_data(p_pid); ph int := coalesce((d ->> 'msPhase')::int, 1);
  hp int := coalesce((d ->> 'msHp')::int, game.lt_ms_max()); k int := coalesce((d ->> 'msK')::int, 0);
  inti boolean := coalesce((d ->> 'titikInti')::boolean, false);
begin
  if ph >= 3 then return game.lt_enc(p_pid, 'ms3'); end if;
  if hp > 6000 then return game.lt_enc(p_pid, 'ms_a'); end if;
  if k < 1 then return game.lt_enc(p_pid, 'kawanan', 1, case when inti then 1 else 2 end); end if;
  if hp > 4500 then return game.lt_enc(p_pid, 'ms_b'); end if;
  if not inti and k < 2 then return game.lt_enc(p_pid, 'kawanan', 2, 2); end if;
  return null;
end $$;

create or replace function game.lt_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare v_step int := game.lt_step(p_pid); v_origin text := game.current_city(p_pid); w int;
begin
  if v_step = 6 and p_dest = 'sowtour' then
    w := game.lt_waves(p_pid);
    if w > 0 then return game.lt_enc(p_pid, 'gagak', 1, w); end if;
  end if;
  if v_step = 7 and v_origin = 'sowtour' then return game.lt_ms_next(p_pid); end if;
  return null;
end $$;

create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language sql as $$
  select coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest),
                  game.ww_encounter(p_pid, p_dest), game.bx_encounter(p_pid, p_dest),
                  game.ts_hunter_encounter(p_pid, p_dest), game.lt_encounter(p_pid, p_dest))
$$;

create or replace function game.lt_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; v_boss text; d jsonb; n int; w int; v_gold int := 0; v_next jsonb; k int;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if not coalesce((enc ->> 'lt')::boolean, false) then return null; end if;
  v_boss := coalesce(enc ->> 'boss', '');
  d := game.lt_data(p_pid);

  if v_boss = 'gagak' then
    n := coalesce((d ->> 'blokWins')::int, 0) + 1;
    if n <= 3 then v_gold := 5000; end if;
    update game.player_quests set data = data || jsonb_build_object('blokWins', n), updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan';
    w := coalesce((enc ->> 'waves')::int, 1);
    if coalesce((enc ->> 'waveNo')::int, 1) < w then
      v_next := game.lt_enc(p_pid, 'gagak', (enc ->> 'waveNo')::int + 1, w);
      return jsonb_build_object('gold', v_gold, 'event', 'gagak', 'chain', v_next,
        'message', 'Kawanan itu pecah dan berjatuhan ke laut' || case when v_gold > 0 then ' (+5.000 gold dari puing logam)' else '' end || '. Belum sempat bernapas, gelombang berikutnya menutup langit di depan haluan!');
    end if;
    perform game.log(p_pid, 'Blokade Gagak tertembus. Menara-menara gelap Kota Sowtour terlihat di cakrawala.');
    return jsonb_build_object('gold', v_gold, 'event', 'blokade', 'arrive', true,
      'message', 'Gelombang terakhir pecah dan berjatuhan seperti hujan logam' || case when v_gold > 0 then ' (+5.000 gold)' else '' end || '. Di depan, menara-menara batu bercermin berdiri gelap. Kota Sowtour.');
  end if;

  if v_boss = 'ms_a' then
    update game.player_quests set data = data || '{"msHp": 6000}'::jsonb, updated_at = now() where player_id = p_pid and quest_id = 'limatangan';
    v_next := game.lt_ms_next(p_pid);
    return jsonb_build_object('gold', 0, 'event', 'kawanan', 'chain', v_next,
      'message', 'Sayap logam Mata Seribu retak. Ia menjerit - dan dari menara-menara gelap, kawanan pelindung menyerbu menutupi tubuhnya!');
  end if;

  if v_boss in ('kawanan', 'ms_b') then
    if v_boss = 'kawanan' then
      k := coalesce((d ->> 'msK')::int, 0) + 1;
      update game.player_quests set data = data || jsonb_build_object('msK', k), updated_at = now() where player_id = p_pid and quest_id = 'limatangan';
    else
      update game.player_quests set data = data || '{"msHp": 4500}'::jsonb, updated_at = now() where player_id = p_pid and quest_id = 'limatangan';
    end if;
    v_next := game.lt_ms_next(p_pid);
    if v_next is not null then
      return jsonb_build_object('gold', 0, 'event', case when v_boss = 'kawanan' then 'kawananDown' else 'kawanan' end, 'chain', v_next,
        'message', case when v_boss = 'kawanan' then 'Kawanan pelindung berjatuhan ke laut. Mata Seribu turun lagi, mata merahnya menyala lebih terang.'
                        else 'Mata Seribu terhuyung. Sekali lagi ia memanggil kawanan dari menara!' end);
    end if;
    -- fase 1 selesai: dada burung itu terbuka. Fase 3 menunggu pelayaran berikutnya dari Sowtour.
    update game.player_quests set data = data || '{"msPhase": 3, "msHp": 4500, "msK": 0}'::jsonb, updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan';
    perform game.log(p_pid, 'Dada Mata Seribu terbuka. Di dalamnya berdenyut inti merah. Suara datar dari seluruh kota: "DIAM ADALAH EMAS."');
    return jsonb_build_object('gold', 0, 'event', 'suara',
      'message', 'Mata Seribu terlempar ke atas menara tertinggi. Dadanya terbuka, dan di dalamnya berdenyut sebuah inti merah sebesar kepala manusia. Dari pengeras suara di seluruh kota terdengar suara datar yang pernah kau dengar di Marie Regal. Kau mundur ke dermaga untuk berbenah.');
  end if;

  if v_boss = 'ms3' then
    update game.player_quests set step = 8, data = data || '{"msHp": 0}'::jsonb, updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan' and step = 7;
    perform game.log(p_pid, 'MATA SERIBU TUMBANG. Inti merah M.A.R.I.E. retak. Semua gagak hitam di dunia jatuh ke laut dan diam. +60.000 gold.');
    return jsonb_build_object('gold', 60000, 'event', 'mataseribu',
      'message', 'Inti merah itu retak. Suaranya melambat: "...saya... akan... diam." Mata Seribu jatuh berputar ke laut di kaki menara. Di seluruh dunia, gagak-gagak hitam berjatuhan dan diam. Di puing tubuhnya kau menemukan 60.000 gold.');
  end if;
  return null;
end $$;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$
  select coalesce(game.gala_boss_defeated(p_pid), game.ww_boss_defeated(p_pid), game.bx_boss_defeated(p_pid),
                  game.ts_boss_defeated(p_pid), game.lt_boss_defeated(p_pid))
$$;

-- HP Mata Seribu tersimpan saat mundur / karam
create or replace function game.lt_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
declare v_boss text := coalesce(p_enc ->> 'boss', ''); v_hp int;
begin
  if not coalesce((p_enc ->> 'lt')::boolean, false) or p_result = 'won' then return; end if;
  if v_boss in ('ms_a', 'ms_b', 'ms3') then
    v_hp := greatest(1, round(game.voy_num(p_enc -> 'enemyHp')))::int;
    update game.player_quests set data = data || jsonb_build_object('msHp', v_hp, 'msTries', coalesce((data ->> 'msTries')::int, 0) + 1), updated_at = now()
     where player_id = p_pid and quest_id = 'limatangan' and step = 7;
  end if;
end $$;

create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  perform game.ww_combat_end(p_pid, p_enc, p_result);
  perform game.bx_combat_end(p_pid, p_enc, p_result);
  perform game.lt_combat_end(p_pid, p_enc, p_result);
end $$;

-- ---------------------------------------------------------------------
-- Memancing: Marlin Garam (siang, badai di Karang Garam) & ikan pertama coco epan (fajar, Joungjava)
-- 0025 menulis ulang baris legenda setiap deploy dengan l_available = false, jadi diperbarui lagi di sini.
-- Isi kait selain tambahan Quest 8 identik dengan 0025.
-- ---------------------------------------------------------------------
update game.mp_fish_types set l_available = true, cities = array['karang_garam'], l_place = 'Kepulauan Karang Garam'
 where id = 'marlin_garam';

create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
declare f game.mp_fish_types;
begin
  select * into f from game.mp_fish_types where id = p_fish;
  if found and f.book = 'legenda' then
    if p_fish = 'kerapu_fajar' and game.cb_step(p_pid) = 6 then
      return case when p_city = 'gading_island' and game.cb_is_dawn() then 40 else 0 end;
    end if;
    -- Quest 8: Ama Kerang meminta satu Marlin Garam untuk laut
    if p_fish = 'marlin_garam' and game.lt_step(p_pid) = 4 and coalesce((game.lt_data(p_pid) ->> 'ama')::boolean, false)
       and not coalesce((game.lt_data(p_pid) ->> 'marlin')::boolean, false) then
      return case when game.lg_ready(p_pid, f, p_city) then 40 else 0 end;
    end if;
    return case when game.lg_ready(p_pid, f, p_city) then 4 else 0 end;
  end if;
  return game.bx_fish_quest_weight(p_pid, p_fish, p_city);
end $$;

create or replace function game.lt_fish_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
declare d jsonb; v_city text := game.current_city(p_pid);
begin
  if game.lt_step(p_pid) = 1 and v_city = 'joungjava' and game.cb_is_dawn() and game.item_qty(p_pid, 'qi_joran_nansy') > 0 then
    d := game.lt_data(p_pid);
    if not coalesce((d ->> 'cocoFish')::boolean, false) and coalesce((d ->> 'cocoKopi')::int, 0) >= game.lt_kopi_need() then
      update game.player_quests set data = data || '{"cocoFish": true}'::jsonb, updated_at = now() where player_id = p_pid and quest_id = 'limatangan';
      perform game.log(p_pid, 'Ikan pertama coco epan menggelepar di ujung Joran Kecil Miss Nansy, saat fajar di dermaga Joungjava.');
      return jsonb_build_object('quest', 'limatangan', 'event', 'cocoFish',
        'message', 'Seekor ikan kecil menggelepar di ujung joran. coco epan memandanginya lama: "Kecil sekali." Ikan pertamanya.');
    end if;
  end if;
  if p_fish = 'marlin_garam' and game.lt_step(p_pid) = 4 and v_city = 'karang_garam' then
    update game.player_quests set data = data || '{"marlin": true}'::jsonb, updated_at = now() where player_id = p_pid and quest_id = 'limatangan';
    perform game.log(p_pid, 'Marlin Garam tertangkap di bawah badai siang Karang Garam. Ama Kerang melepaskannya kembali ke laut.');
  end if;
  return null;
end $$;

create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
declare f game.mp_fish_types; v_kg numeric; v_city text := game.current_city(p_pid); v_n int; v_first boolean; lt jsonb;
begin
  lt := game.lt_fish_catch(p_pid, p_fish);
  select * into f from game.mp_fish_types where id = p_fish;
  if not found or f.book <> 'legenda' then return coalesce(lt, game.bx_fish_quest_catch(p_pid, p_fish)); end if;
  select best_kg into v_kg from game.mp_fish_book where player_id = p_pid and fish_id = p_fish;
  delete from game.mp_fish_book where player_id = p_pid and fish_id = p_fish;
  select not exists (select 1 from game.legend_catch where player_id = p_pid and fish_id = p_fish) into v_first;
  insert into game.legend_catch as c (player_id, fish_id, n, best_kg) values (p_pid, p_fish, 1, coalesce(v_kg, 0))
  on conflict (player_id, fish_id) do update set n = c.n + 1,
    best_kg = greatest(c.best_kg, excluded.best_kg), best_at = case when excluded.best_kg > c.best_kg then now() else c.best_at end;
  if f.l_bait is not null and game.item_qty(p_pid, f.l_bait) > 0 then perform game.adjust_inventory(p_pid, f.l_bait, -1); end if;
  select count(*) into v_n from game.legend_catch where player_id = p_pid;
  if p_fish = 'kerapu_fajar' and game.cb_step(p_pid) = 6 and v_city = 'gading_island' then
    update game.player_quests set step = 7, data = data || jsonb_build_object('legend', true, 'legendKg', v_kg), updated_at = now()
     where player_id = p_pid and quest_id = 'cocoepan';
    perform game.log(p_pid, 'Kerapu Fajar tertangkap saat fajar di Gading Island. Halaman pertama Buku Pancing Legenda kini terisi.');
    return jsonb_build_object('legend', true, 'no', f.legend_no, 'name', f.name, 'release', false, 'first', true, 'count', v_n,
      'itemId', 'qi_buku_pancing_maudy', 'quest', 'cocoepan',
      'message', 'Sisiknya berkilau keemasan seperti langit sebelum matahari. Di Buku Pancing Legenda, entri pertama bertanda bintang kini bisa dicoret.');
  end if;
  if v_first then
    perform game.log(p_pid, 'Buku Pancing Legenda: ' || f.name || ' tercatat (' || v_n || '/21)' || case when f.l_release then ', lalu dilepas kembali ke laut.' else '.' end);
  end if;
  return jsonb_build_object('legend', true, 'no', f.legend_no, 'name', f.name, 'release', f.l_release, 'first', v_first, 'count', v_n,
    'quest', case when p_fish = 'marlin_garam' and game.lt_step(p_pid) = 4 then 'limatangan' end,
    'message', case when p_fish = 'marlin_garam' and game.lt_step(p_pid) = 4
      then 'Marlin Garam melompat di bawah hujan, sisiknya berkilau seperti garam. Ama Kerang mengangkatnya dengan dua tangan, membisikkan sesuatu, lalu melepaskannya: "Laut sudah melihatmu."'
      when f.l_release then 'Kau mencatatnya di Buku Pancing Legenda, lalu melepasnya kembali ke laut.'
      else 'Tercatat di Buku Pancing Legenda.' end);
end $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg, arg2]
-- ---------------------------------------------------------------------
create or replace function game.lt_norm(p text) returns text
language sql immutable as $$ select regexp_replace(lower(coalesce(p, '')), '[^a-z]', '', 'g') $$;

create or replace function game.lt_ulin_ok(p_idx int, p_answer text) returns boolean
language sql immutable as $$
  select case p_idx
    when 0 then game.lt_norm(p_answer) in ('lubang', 'lobang', 'galian')
    when 1 then game.lt_norm(p_answer) in ('masadepan', 'hariesok', 'besok', 'esok', 'masadepanmu')
    when 2 then game.lt_norm(p_answer) in ('ulin', 'kayuulin', 'kayubesi', 'besikayu')
    else false end
$$;

create or replace function game.lt_payload(p_pid uuid) returns jsonb
language sql as $$
  select jsonb_build_object('limatangan', game.lt_state(p_pid), 'unlocks', game.player_unlocks(p_pid),
    'cities', game.cities_json(), 'citiesVersion', game.cities_version())
$$;

create or replace function public.api_limaTangan(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  v_arg2 text := lower(btrim(coalesce(game.arg(a, 2), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb; d jsonb; v_now bigint := game.lt_wms();
  v_dock jsonb; k text; v_need int; v_have int; v_put int; v_moved jsonb := '{}'::jsonb; v_n int; v_score int; v_grade text;
  v_kopi int; c text; v_take int; dice jsonb; v_sum int; v_win boolean; v_idx int; v_wrong jsonb; v_beads int; v_total int;
  v_extra int; v_logs jsonb; v_ok boolean; v_dur int; v_lost int;
begin
  st := game.lt_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('limatangan', st); end if;
  if st is null then raise exception 'Lambung hitam itu masih tertidur, Kapten.'; end if;

  -- Jaring Angin dimainkan DI LAUT, di mulut kabut, sebelum kapal tiba di Karang Garam
  if v_act = 'wind' then
    if game.lt_step(v_pid) <> 4 or coalesce((game.lt_data(v_pid) ->> 'windDone')::boolean, false) then raise exception 'Angin di sini bertiup biasa.'; end if;
    if not game.in_transit(v_pid) then raise exception 'Kabut itu menunggu di tengah laut, Kapten. Angkat sauh dulu.'; end if;
    v_n := least(8, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    v_lost := 0;
    for i in 1 .. v_n loop exit when not game.lt_take_ransum(v_pid); v_lost := v_lost + 1; end loop;
    update game.player_quests set data = data || jsonb_build_object('windDone', true, 'windRetries', v_n, 'windLost', v_lost), updated_at = now()
     where player_id = v_pid and quest_id = 'limatangan';
    perform game.log(v_pid, 'Black Pearl menembus empat zona angin di batas kabut timur' || case when v_lost > 0 then ' (' || v_lost || ' jatah ransum terbuang saat layar robek)' else '' end || '. Pulau putih muncul dari kabut.');
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'lost', v_lost);
  end if;

  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'limatangan' for update;
  v_step := coalesce(q.step, 0);
  d := coalesce(q.data, '{}'::jsonb);

  -- PROLOG: Kapal yang Terluka
  if v_act = 'prolog' then
    if v_step > 0 then return jsonb_build_object('limatangan', st); end if;
    perform game.lt_need_city(v_city, 'toogood', 'Teh Euis menunggumu di dermaga TooGood.');
    if not game.lt_bank_ok(v_pid) then raise exception 'Belum waktunya, Kapten.'; end if;
    insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'limatangan', 1, '{"dock": {}}')
    on conflict (player_id, quest_id) do update set step = 1, data = '{"dock": {}}', started_at = now(), updated_at = now();
    perform game.log(v_pid, 'Black Pearl terbaring terluka di Dok Kering TooGood. Buku log zafachmie: "Black Pearl butuh lima tangan." Teh Euis memegang tangan pertama: kunci.');
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;
  if v_step < 1 then raise exception 'Lambung hitam itu masih tertidur, Kapten.'; end if;

  -- ============ BABAK 1: Lima Tangan ============
  if v_act = 'setor' then
    if v_step <> 1 then raise exception 'Dok Kering sudah selesai bekerja.'; end if;
    perform game.lt_need_city(v_city, 'toogood', 'Bahan perbaikan disetor ke Dok Kering TooGood.');
    v_dock := coalesce(d -> 'dock', '{}'::jsonb);
    for k, v_need in select key, value::int from jsonb_each_text(game.lt_dock_need()) loop
      v_have := coalesce((v_dock ->> k)::int, 0);
      if v_have >= v_need then continue; end if;
      v_put := least(v_need - v_have, game.item_qty(v_pid, k));
      if v_put <= 0 then continue; end if;
      if k like 'qi\_%' escape '\' then perform game.item_adjust(v_pid, k, -v_put); else perform game.adjust_inventory(v_pid, k, -v_put); end if;
      v_dock := v_dock || jsonb_build_object(k, v_have + v_put);
      v_moved := v_moved || jsonb_build_object(k, v_put);
    end loop;
    if v_moved = '{}'::jsonb then raise exception 'Palkamu tidak membawa bahan yang masih dibutuhkan tukang dok.'; end if;
    perform game.lt_set(v_pid, 1, jsonb_build_object('dock', v_dock));
    if game.lt_dock_done(jsonb_build_object('dock', v_dock)) and (d ->> 'dockReadyAt') is null then
      perform game.lt_set(v_pid, 1, jsonb_build_object('dockReadyAt', v_now + game.lt_len_ms()));
      perform game.log(v_pid, 'Bahan perbaikan Black Pearl lengkap. Tukang dok TooGood mulai bekerja: satu hari penuh.');
    end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'moved', v_moved);
  end if;

  if v_act = 'pantun' then
    if v_step <> 1 then raise exception 'Hasiolan sudah di kemudi.'; end if;
    perform game.lt_need_city(v_city, 'skitraw', 'Hasiolan menjemur kain di belakang Galangan Gaul-Wash, Skitraw.');
    if coalesce((d ->> 'kemudi')::boolean, false) then return jsonb_build_object('limatangan', st); end if;
    if (d ->> 'pantunAt') is not null and v_now < (d ->> 'pantunAt')::bigint then raise exception 'Hasiolan masih menjemur. "Kembalilah kalau lidahmu sudah diasah, Kapten."'; end if;
    if v_arg = 'ok' then
      perform game.lt_set(v_pid, 1, jsonb_build_object('kemudi', true, 'pantunPerfect', v_arg2 = 'perfect'));
      perform game.log(v_pid, 'Hasiolan mengembalikan jubah Uda Gala dan naik ke kemudi. "Ambo mau pulang dengan jubah ambo sendiri."');
    elsif v_arg = 'gagal' then
      perform game.lt_set(v_pid, 1, jsonb_build_object('pantunAt', v_now + game.lt_hour_ms()));
    else raise exception 'Hasil pantun tidak dikenal.'; end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'kopi' then
    if v_step <> 1 then raise exception 'coco epan sudah berkemas.'; end if;
    perform game.lt_need_city(v_city, 'joungjava', 'coco epan menunggumu di Javasche Bank, Joungjava.');
    v_kopi := coalesce((d ->> 'cocoKopi')::int, 0);
    if v_kopi >= game.lt_kopi_need() then return jsonb_build_object('limatangan', st); end if;
    foreach c in array array['kopi_bourbon_chiroso', 'kopi_flores_bajawa', 'kopi_sumatera_gayo'] loop
      v_take := least(game.lt_kopi_need() - v_kopi, game.item_qty(v_pid, c));
      if v_take > 0 then perform game.adjust_inventory(v_pid, c, -v_take); v_kopi := v_kopi + v_take; v_moved := v_moved || jsonb_build_object(c, v_take); end if;
    end loop;
    if v_moved = '{}'::jsonb then raise exception 'Kopi Stumpy hanya dijual di Gading Island, Kapten. Bourbon Chiroso, Flores Bajawa, atau Sumatera Gayo.'; end if;
    perform game.lt_set(v_pid, 1, jsonb_build_object('cocoKopi', v_kopi));
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'moved', v_moved);
  end if;

  if v_act = 'coco' then
    if v_step <> 1 then raise exception 'coco epan sudah di kapal.'; end if;
    perform game.lt_need_city(v_city, 'joungjava', 'coco epan menunggumu di Javasche Bank, Joungjava.');
    if coalesce((d ->> 'cocoKopi')::int, 0) < game.lt_kopi_need() then raise exception 'coco epan masih menunggu kopinya.'; end if;
    if not coalesce((d ->> 'cocoFish')::boolean, false) then raise exception 'coco epan ingin menangkap ikan pertamanya dulu, saat fajar, dengan joran kecil itu.'; end if;
    if not coalesce((d ->> 'peta')::boolean, false) then
      perform game.lt_set(v_pid, 1, '{"peta": true}'::jsonb);
      perform game.log(v_pid, 'coco epan naik ke Black Pearl. Separuh Peta Jalur Pendiri ada di kepalanya.');
    end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'lab' then
    if v_step <> 1 then raise exception 'dwi sudah di kapal.'; end if;
    perform game.lt_need_city(v_city, 'marie_regal', 'dwi de''clown ada di Laboratorium Regal, Marie Regal.');
    if coalesce((d ->> 'mata')::boolean, false) then return jsonb_build_object('limatangan', st); end if;
    v_n := greatest(0, coalesce(nullif(v_arg, '')::int, 9));
    perform game.lt_set(v_pid, 1, jsonb_build_object('mata', true, 'titikInti', v_n = 0, 'labErrors', v_n));
    perform game.log(v_pid, 'Di Laboratorium Regal: inti merah M.A.R.I.E. hilang, digantikan lukisan di atas kaca bertanda "A." dwi de''clown naik ke kapal.');
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act in ('dadu', 'gasing') then
    if v_step <> 1 then raise exception 'Meja di ruang VIP itu sudah kosong.'; end if;
    perform game.lt_need_city(v_city, 'paradiso', 'Awak Armada Bebas bersembunyi di ruang VIP Kasino Mutiara, Paradiso.');
    if not game.fish_is_night() then raise exception 'Ruang VIP Kasino Mutiara baru dibuka saat malam.'; end if;
    if coalesce((d ->> 'meriam')::boolean, false) then return jsonb_build_object('limatangan', st); end if;
  end if;

  if v_act = 'dadu' then
    if coalesce((st ->> 'diceDone')::boolean, false) then raise exception 'Bang Rimba menyingkirkan cangkir dadu. "Cukup."'; end if;
    if v_arg not in ('besar', 'kecil') then raise exception 'Pilih Besar atau Kecil.'; end if;
    dice := jsonb_build_array(1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int);
    v_sum := (dice ->> 0)::int + (dice ->> 1)::int + (dice ->> 2)::int;
    v_win := (v_sum >= 11) = (v_arg = 'besar');
    v_n := coalesce((d ->> 'diceWins')::int, 0) + case when v_win then 1 else 0 end;
    v_lost := coalesce((d ->> 'diceLoss')::int, 0) + case when v_win then 0 else 1 end;
    if v_n >= 2 then perform game.lt_set(v_pid, 1, jsonb_build_object('diceWins', v_n, 'diceLoss', v_lost, 'diceDone', true));
    elsif v_lost >= 2 then perform game.lt_set(v_pid, 1, '{"diceWins": 0, "diceLoss": 0}'::jsonb);
    else perform game.lt_set(v_pid, 1, jsonb_build_object('diceWins', v_n, 'diceLoss', v_lost)); end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'dice', dice, 'sum', v_sum, 'win', v_win, 'reset', v_n < 2 and v_lost >= 2);
  end if;

  if v_act = 'gasing' then
    if not coalesce((st ->> 'diceDone')::boolean, false) then raise exception 'Bang Rimba mengocok cangkir dadu. "Untung dulu, Kapten. Baru kepercayaan."'; end if;
    if (d ->> 'rimbaNight') is not null and (d ->> 'rimbaNight')::int >= game.lt_night_idx() then raise exception 'Bang Rimba: "Kembali besok malam. Kami tidak ke mana-mana."'; end if;
    if v_arg = 'won' then
      perform game.lt_set(v_pid, 1, '{"meriam": true}'::jsonb);
      perform game.log(v_pid, 'Gasing bergores tiga silang milik Andry berhenti lebih dulu. Bang Rimba dan dua belas awak Armada Bebas naik ke meriam Black Pearl.');
    elsif v_arg = 'lost' then
      perform game.lt_set(v_pid, 1, jsonb_build_object('rimbaLoss', coalesce((d ->> 'rimbaLoss')::int, 0) + 1, 'rimbaNight', game.lt_night_idx()));
    else raise exception 'Hasil adu gasing tidak dikenal.'; end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'ulin' then
    if v_step <> 1 then raise exception 'Mercusuar Nenek Ulin sudah kehilangan satu anak tangga.'; end if;
    perform game.lt_need_city(v_city, 'bjorneo', 'Nenek Ulin menjaga mercusuar kayu di Bjorneo.');
    v_idx := coalesce((d ->> 'ulinIdx')::int, 0);
    if v_idx >= 3 then return jsonb_build_object('limatangan', st); end if;
    if (d ->> 'ulinAt') is not null and v_now < (d ->> 'ulinAt')::bigint then raise exception 'Nenek Ulin sedang menyalakan mercusuar. "Kembali sebentar lagi, Nak."'; end if;
    if game.lt_ulin_ok(v_idx, game.arg(a, 1)) then
      v_idx := v_idx + 1;
      perform game.lt_set(v_pid, 1, jsonb_build_object('ulinIdx', v_idx));
      if v_idx >= 3 and game.item_qty(v_pid, 'qi_papan_ulin') < 1 and coalesce((d -> 'dock' ->> 'qi_papan_ulin')::int, 0) < 1 then
        perform game.item_adjust(v_pid, 'qi_papan_ulin', 1);
        perform game.log(v_pid, 'Nenek Ulin mencungkil anak tangga paling bawah mercusuarnya: Papan Ulin Tua untuk tiang Black Pearl.');
        return jsonb_build_object('limatangan', game.lt_state(v_pid), 'correct', true, 'item', jsonb_build_object('itemId', 'qi_papan_ulin', 'name', 'Papan Ulin Tua'));
      end if;
      return jsonb_build_object('limatangan', game.lt_state(v_pid), 'correct', true);
    end if;
    v_wrong := coalesce(d -> 'ulinWrong', '{}'::jsonb);
    v_wrong := v_wrong || jsonb_build_object(v_idx::text, coalesce((v_wrong ->> v_idx::text)::int, 0) + 1);
    perform game.lt_set(v_pid, 1, jsonb_build_object('ulinWrong', v_wrong, 'ulinAt', v_now + game.lt_hour_ms()));
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'correct', false);
  end if;

  if v_act = 'kuas' then
    perform game.lt_need_city(v_city, 'ikn', 'Anak-anak Kamp Pemulung ada di IKN.');
    if game.item_qty(v_pid, 'qi_kuas_tedsky') < 1 then perform game.item_adjust(v_pid, 'qi_kuas_tedsky', 1); end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'item', jsonb_build_object('itemId', 'qi_kuas_tedsky', 'name', 'Kuas Perunggu Tedsky'));
  end if;

  if v_act = 'launch' then
    if v_step <> 1 then raise exception 'Black Pearl sudah berlayar.'; end if;
    perform game.lt_need_city(v_city, 'toogood', 'Black Pearl menunggu di Dok Kering TooGood.');
    if not (coalesce((d ->> 'kemudi')::boolean, false) and coalesce((d ->> 'peta')::boolean, false)
            and coalesce((d ->> 'mata')::boolean, false) and coalesce((d ->> 'meriam')::boolean, false)) then
      raise exception 'Black Pearl butuh lima tangan, Kapten. Masih ada yang belum naik.';
    end if;
    if (d ->> 'dockReadyAt') is null or v_now < (d ->> 'dockReadyAt')::bigint then raise exception 'Tukang dok masih menambal geladak dan memasang tiang ulin.'; end if;
    perform game.lt_set(v_pid, 2, null);
    perform game.lt_pearl_on(v_pid);
    perform game.log(v_pid, 'LIMA TANGAN. Black Pearl meluncur keluar dari Dok Kering TooGood. Kau nakhodanya. Ransum: 10 Beras + 5 Garam setiap pelayaran di Laut Timur.');
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'pearl', true, 'ship', game.ship_json(v_pid), 'shipVisual', game.ship_visual(v_pid));
  end if;

  -- ============ BABAK 3: FreeYork ============
  if v_act = 'freeyork' then
    perform game.lt_need_city(v_city, 'freeyork', 'Tassyaaa menunggu di dermaga FreeYork.');
    if v_step = 2 then
      perform game.lt_set(v_pid, 3, jsonb_build_object('lunasAt', v_now + game.lt_hour_ms()));
      perform game.log(v_pid, 'Dok Legenda FreeYork menyala lagi setelah dua puluh tahun. Lunas Black Pearl ditambal di tempat ia lahir.');
    end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'tempa' then
    if v_step <> 3 then raise exception 'Tungku Dok Legenda sudah dingin.'; end if;
    perform game.lt_need_city(v_city, 'freeyork', 'Dok Legenda ada di FreeYork.');
    v_score := least(100, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    v_dur := coalesce(nullif(v_arg2, '')::int, 0);
    if v_dur < 8000 then raise exception 'Besi belum sempat dipanaskan, Kapten.'; end if;
    if (d ->> 'hookAt') is not null and v_now < (d ->> 'hookAt')::bigint then raise exception 'Tungku masih memanas. Satu jam lagi.'; end if;
    v_grade := d ->> 'hookGrade';
    if v_grade is not null and v_grade <> 'retak' then
      -- tempa ulang: 10 Besi, mulai pagi berikutnya
      if game.game_day() <= coalesce((d ->> 'hookDay')::int, 0) then raise exception 'Tempa ulang mulai besok pagi, Kapten. Tungku harus istirahat.'; end if;
      if game.item_qty(v_pid, 'besi') < 10 then raise exception 'Tempa ulang butuh 10 Besi.'; end if;
      perform game.adjust_inventory(v_pid, 'besi', -10);
    elsif d ? 'hookScore' then
      if game.item_qty(v_pid, 'besi') < 5 then raise exception 'Bawa 5 Besi lagi untuk menempa ulang.'; end if;
      perform game.adjust_inventory(v_pid, 'besi', -5);
    end if;
    v_ok := game.lt_grade(v_score) <> 'retak';
    if v_ok and game.lt_grade_rank(game.lt_grade(v_score)) >= game.lt_grade_rank(v_grade) then
      perform game.lt_set(v_pid, 3, jsonb_build_object('hookGrade', game.lt_grade(v_score), 'hookScore', v_score, 'hookDay', game.game_day(), 'hookAt', null));
      if game.item_qty(v_pid, 'qi_pengait') < 1 then perform game.item_adjust(v_pid, 'qi_pengait', 1); end if;
    elsif v_ok then
      perform game.lt_set(v_pid, 3, jsonb_build_object('hookDay', game.game_day(), 'hookTry', v_score));
    else
      perform game.lt_set(v_pid, 3, jsonb_build_object('hookScore', coalesce((d ->> 'hookScore')::int, v_score), 'hookTry', v_score,
        'hookAt', v_now + game.lt_hour_ms()) || case when v_grade is null then '{"hookGrade": "retak"}'::jsonb else '{}'::jsonb end);
    end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'grade', game.lt_grade(v_score), 'kept', game.lt_state(v_pid) ->> 'hookGrade');
  end if;

  if v_act = 'fydone' then
    if v_step <> 3 then raise exception 'Kau sudah meninggalkan FreeYork.'; end if;
    perform game.lt_need_city(v_city, 'freeyork', 'Tassyaaa ada di FreeYork.');
    if coalesce(d ->> 'hookGrade', 'retak') = 'retak' then raise exception 'Pengait pemecah rantai belum jadi.'; end if;
    if (d ->> 'lunasAt') is null or v_now < (d ->> 'lunasAt')::bigint then raise exception 'Lunas Black Pearl masih ditambal di Dok Legenda.'; end if;
    if game.item_qty(v_pid, 'qi_nasi_tassyaaa') < 1 then perform game.item_adjust(v_pid, 'qi_nasi_tassyaaa', 1); end if;
    perform game.lt_set(v_pid, 4, null);
    perform game.log(v_pid, 'Lunas Black Pearl sembuh. Tassyaaa menitipkan bungkusan nasi untuk Petrik. Kompas Dua Jarum menunjuk ke kabut di timur FreeYork.');
    return game.lt_payload(v_pid) || jsonb_build_object('item', jsonb_build_object('itemId', 'qi_nasi_tassyaaa', 'name', 'Bungkusan Nasi Tassyaaa'));
  end if;

  -- ============ BABAK 4: Laut Putih ============
  if v_act in ('ama', 'selam', 'advice', 'kgdone') then
    if v_step <> 4 then raise exception 'Ama Kerang sedang menggulung jaring.'; end if;
    perform game.lt_need_city(v_city, 'karang_garam', 'Ama Kerang ada di dermaga karang, Kepulauan Karang Garam.');
  end if;

  if v_act = 'ama' then
    if not coalesce((d ->> 'ama')::boolean, false) then perform game.lt_set(v_pid, 4, '{"ama": true}'::jsonb); end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'selam' then
    if not coalesce((d ->> 'marlin')::boolean, false) then raise exception 'Laut belum melihatmu di atas air, Kapten. Marlin Garam dulu.'; end if;
    if not coalesce((st ->> 'pagi')::boolean, false) then raise exception 'Ama Kerang: "Air jernih hanya di pagi hari."'; end if;
    if (d ->> 'diveRestAt') is not null and v_now < (d ->> 'diveRestAt')::bigint then raise exception 'Ipo: "Istirahat dulu! Napasmu masih pendek."'; end if;
    if coalesce((d ->> 'beads')::int, 0) >= 6 and coalesce((d ->> 'diveHeart')::boolean, false) then raise exception 'Kalung Karang sudah penuh, Kapten.'; end if;
    v_beads := least(8, greatest(0, coalesce(nullif(v_arg2, '')::int, 0)));
    if v_arg = 'gagal' then
      perform game.lt_set(v_pid, 4, jsonb_build_object('diveRestAt', v_now + game.lt_hour_ms() / 2, 'dives', coalesce((d ->> 'dives')::int, 0) + 1));
      return jsonb_build_object('limatangan', game.lt_state(v_pid), 'ok', false);
    end if;
    if v_arg <> 'ok' then raise exception 'Hasil selam tidak dikenal.'; end if;
    v_total := coalesce((d ->> 'beads')::int, 0) + v_beads;
    v_extra := greatest(0, v_total - 6);
    if v_extra > 0 then perform game.adjust_inventory(v_pid, 'mutiara', v_extra); end if;
    perform game.lt_set(v_pid, 4, jsonb_build_object('diveHeart', true, 'beads', least(6, v_total), 'dives', coalesce((d ->> 'dives')::int, 0) + 1,
      'perfectDive', coalesce((d ->> 'perfectDive')::boolean, false) or v_beads >= 6));
    return jsonb_build_object('limatangan', game.lt_state(v_pid), 'ok', true, 'extra', v_extra);
  end if;

  if v_act = 'advice' then
    if not coalesce((d ->> 'diveHeart')::boolean, false) then raise exception 'coco epan masih memandangi laut.'; end if;
    if v_arg not in ('bersama', 'pilihan') then raise exception 'Jawablah coco epan, Kapten.'; end if;
    perform game.lt_set(v_pid, 4, jsonb_build_object('cocoAdvice', v_arg));
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'kgdone' then
    if not (coalesce((d ->> 'ama')::boolean, false) and coalesce((d ->> 'marlin')::boolean, false) and coalesce((d ->> 'diveHeart')::boolean, false)) then
      raise exception 'Laut belum menerimamu, Kapten.';
    end if;
    if not d ? 'cocoAdvice' then raise exception 'coco epan menunggu jawabanmu di haluan.'; end if;
    if game.item_qty(v_pid, 'qi_kalung_karang') < 1 then perform game.item_adjust(v_pid, 'qi_kalung_karang', 1); end if;
    perform game.lt_set(v_pid, 5, null);
    perform game.log(v_pid, 'Ama Kerang merangkai Kalung Karang (' || coalesce((d ->> 'beads')::int, 0) || '/6 butir). Garis pantai benua menunggu di balik kabut.');
    return game.lt_payload(v_pid) || jsonb_build_object('item', jsonb_build_object('itemId', 'qi_kalung_karang', 'name', 'Kalung Karang'));
  end if;

  -- ============ BABAK 5: Kota Rantai ============
  if v_act in ('sandi', 'jejak', 'hasiolan') then
    if v_step <> 5 then raise exception 'Angin di kota rantai sudah berbicara.'; end if;
    perform game.lt_need_city(v_city, 'rantai_lama', 'Jejak Marlya ada di Pelabuhan Rantai Lama.');
  end if;

  if v_act = 'sandi' then
    if coalesce((d ->> 'sandiDone')::boolean, false) then return jsonb_build_object('limatangan', st); end if;
    if not game.fish_is_night() then raise exception 'Bulu-bulu itu hanya berpendar di bawah bulan.'; end if;
    if (d ->> 'sandiNight')::int = game.lt_night_idx() and coalesce((d ->> 'sandiFails')::int, 0) >= 3 then
      raise exception 'Angin malam sudah menerbangkan sebagian bulu. Tunggu malam berikutnya.';
    end if;
    if v_arg = 'ok' then
      perform game.lt_set(v_pid, 5, '{"sandiDone": true}'::jsonb);
      perform game.log(v_pid, 'Bulu pelikan perak di dinding gudang: "Bungkam menaranya, dan gagak akan buta. Jangan bawa raja ke teluk. - M."');
    elsif v_arg = 'gagal' then
      if (d ->> 'sandiNight')::int is distinct from game.lt_night_idx() then
        perform game.lt_set(v_pid, 5, jsonb_build_object('sandiNight', game.lt_night_idx(), 'sandiFails', 3, 'sandiNights', coalesce((d ->> 'sandiNights')::int, 0) + 1));
      else
        perform game.lt_set(v_pid, 5, jsonb_build_object('sandiFails', 3));
      end if;
    else raise exception 'Hasil sandi tidak dikenal.'; end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'jejak' then
    if d ? 'jejakOk' then raise exception 'Kau sudah menjawabnya, Kapten. Jawaban di rumah ini hanya sekali.'; end if;
    if v_arg not in ('benar', 'salah') then raise exception 'Hasil penalaran tidak dikenal.'; end if;
    perform game.lt_set(v_pid, 5, jsonb_build_object('jejakOk', v_arg = 'benar'));
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'hasiolan' then
    if not (coalesce((d ->> 'sandiDone')::boolean, false) and d ? 'jejakOk') then raise exception 'Masih ada yang harus dibaca di kota ini.'; end if;
    if v_arg not in ('percaya', 'ambil') then raise exception 'Putuskan, Kapten. Siapa yang memegang kemudi?'; end if;
    perform game.lt_set(v_pid, 6, jsonb_build_object('hasiolan', v_arg));
    perform game.log(v_pid, case when v_arg = 'percaya'
      then 'Hasiolan menyobek surat Tedsky dan membuangnya ke laut. Kemudi tetap di tangannya.'
      else 'Hasiolan menyerahkan kemudi kepadamu dan pindah ke barisan meriam tanpa bicara.' end);
    return game.lt_payload(v_pid);
  end if;

  -- ============ BABAK 6: Seribu Mata ============
  if v_act in ('baayu', 'menara') then
    if v_step <> 6 then raise exception 'Menara-menara Sowtour sudah bercahaya.'; end if;
    perform game.lt_need_city(v_city, 'sowtour', 'Om Baayu menjaga cermin di Kota Sowtour.');
  end if;

  if v_act = 'baayu' then
    if not coalesce((d ->> 'baayu')::boolean, false) then perform game.lt_set(v_pid, 6, '{"baayu": true}'::jsonb); end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'menara' then
    if not coalesce((d ->> 'baayu')::boolean, false) then raise exception 'Om Baayu belum menunjukkan tangga menaranya.'; end if;
    if not game.fish_is_night() then raise exception 'Cermin menara hanya bisa dinyalakan saat malam.'; end if;
    if game.lt_tower_allow(d) <= 0 then raise exception 'Cermin tua hanya kuat menampung satu cahaya setiap malam, Kapten. Tunggu malam berikutnya.'; end if;
    if v_arg not in ('ok', 'gagal') then raise exception 'Hasil sandi menara tidak dikenal.'; end if;
    v_n := coalesce((d ->> 'lit')::int, 0);
    v_logs := coalesce(d -> 'towerLog', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('n', game.lt_night_idx(), 'ok', v_arg = 'ok', 'tower', v_n + 1));
    if v_arg = 'ok' then
      v_n := v_n + 1;
      perform game.lt_set(v_pid, case when v_n >= 3 then 7 else 6 end, jsonb_build_object('lit', v_n, 'towerLog', v_logs,
        -- menara bersih = menyala tanpa pernah gagal (dihitung server dari towerLog, bukan dari klien)
        'clean', coalesce((d ->> 'clean')::int, 0) + case when exists (select 1 from jsonb_array_elements(coalesce(d -> 'towerLog', '[]'::jsonb)) e
                   where (e ->> 'tower')::int = v_n and not (e ->> 'ok')::boolean) then 0 else 1 end));
      perform game.log(v_pid, 'Menara ' || (array['Sapa', 'Kabar', 'Janji'])[least(3, v_n)] || ' menyala di Kota Sowtour (' || v_n || '/3).');
      if v_n >= 3 then perform game.log(v_pid, 'Seluruh Kota Sowtour bercahaya. Gagak di langit kota menjadi buta. Mata Seribu turun dari menara tertinggi: ia akan menghadang kapal yang meninggalkan kota.'); end if;
    else
      perform game.lt_set(v_pid, 6, jsonb_build_object('towerFails', coalesce((d ->> 'towerFails')::int, 0) + 1, 'towerLog', v_logs));
    end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act in ('zafa', 'genderang', 'sekutu') then
    if v_step <> 8 then raise exception 'Belum waktunya, Kapten.'; end if;
    perform game.lt_need_city(v_city, 'sowtour', 'zafachmie ada di menara tertinggi Kota Sowtour.');
  end if;

  if v_act = 'zafa' then
    if not coalesce((d ->> 'zafa')::boolean, false) then
      perform game.lt_set(v_pid, 8, '{"zafa": true}'::jsonb);
      perform game.log(v_pid, 'Teh Euis membuka rantai zafachmie dengan salah satu kunci tuanya. "Rantai TooGood. Mereka bahkan tidak repot membuat rantai baru."');
    end if;
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'genderang' then
    if not coalesce((d ->> 'zafa')::boolean, false) then raise exception 'zafachmie masih dirantai.'; end if;
    if (d ->> 'drumAt') is not null and v_now < (d ->> 'drumAt')::bigint then raise exception 'zafachmie: "Biar tanganmu istirahat dulu. Genderang ini tua."'; end if;
    v_score := least(100, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    perform game.lt_set(v_pid, 8, jsonb_build_object('drumBest', greatest(v_score, coalesce((d ->> 'drumBest')::int, 0)),
      'drumAt', case when d ? 'drumBest' or v_score < 85 then v_now + game.lt_hour_ms() else null end));
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  if v_act = 'sekutu' then
    if not d ? 'drumBest' then raise exception 'Genderang belum ditabuh.'; end if;
    perform game.lt_set(v_pid, 9, null);
    perform game.log(v_pid, 'Cahaya menara Sowtour dijawab dari cakrawala barat. Sekutu: ' || game.lt_allies((d ->> 'drumBest')::int) || '/3.');
    return jsonb_build_object('limatangan', game.lt_state(v_pid));
  end if;

  -- ============ BABAK 7: Topi di Kemudi ============
  if v_act = 'tutup' then
    if v_step <> 9 then raise exception 'Belum waktunya, Kapten.'; end if;
    perform game.lt_need_city(v_city, 'sowtour', 'Black Pearl berlabuh di Kota Sowtour.');
    if game.item_qty(v_pid, 'qi_topi_coco') < 1 then perform game.item_adjust(v_pid, 'qi_topi_coco', 1); end if;
    if game.item_qty(v_pid, 'qi_kunci_jam_agung') < 1 then perform game.item_adjust(v_pid, 'qi_kunci_jam_agung', 1); end if;
    update game.players set gold = gold + game.lt_reward() where player_id = v_pid;
    perform game.lt_set(v_pid, 10, jsonb_build_object('reward', game.lt_reward()));
    -- Hasiolan membawa Black Pearl pulang ke TooGood untuk mengisi ransum & meriam; kapalmu kembali
    perform game.lt_pearl_off(v_pid);
    update game.player_location set city_id = 'toogood', destination_city_id = null, depart_at = null, arrive_at = null,
        pending_encounter = null, arrived_game_day = game.game_day()
     where player_id = v_pid;
    perform game.log(v_pid, 'Saat fajar, sekoci Black Pearl hilang. Di kemudi tergantung topi bowler coco epan dan sepucuk surat. "Jangan ikuti saya selama tiga hari." +' || game.lt_reward() || ' gold.');
    perform game.log(v_pid, 'Hasiolan membawa Black Pearl pulang ke TooGood untuk mengisi ransum dan meriam. Kapalmu sendiri menunggu di dermaga. BERSAMBUNG.');
    return game.lt_payload(v_pid) || jsonb_build_object('paid', game.lt_reward(), 'cityId', 'toogood',
      'newGold', (select gold from game.players where player_id = v_pid), 'ship', game.ship_json(v_pid), 'shipVisual', game.ship_visual(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_limatangan');
