-- =====================================================================
-- Marantau (Supabase) - 0030 SAGA 2 · QUEST 9 "TEMPAT DUA TANGAN BERJABAT" (penutup Saga 2, Tide v34)
-- Skenario: dokumen project claude/SKENARIO-Quest9-Serbuan-Bersama.md (v1.1)
--
-- Prasyarat : Quest 8 "Lima Tangan" selesai (lt_step 10) + 3 hari game sejak penutupnya.
-- Langkah (game.player_quests, quest_id = 'duatangan'):
--   1  Prolog "Hari Ketiga" selesai (pelabuhan mana pun) -> boleh masuk Papan Armada di Kota Sowtour
--   3  Serbuan Bersama dimenangkan (diisi saat serbuan selesai) -> Kartu Hasil -> penutup pribadi
--   4  Nasib Tedsky dipilih ('fate' ikn | dewan)
--   5  Selesai ('tutup': hadiah, kapal di TooGood) = VETERAN
--
-- SERBUAN BERSAMA (2-4 kapten online + Black Pearl NPC melawan Sayap Patah), mesin Duel Lambung diperluas:
--   game.mp_raids           baris armada (lobi -> bertempur -> selesai)
--   game.mp_raid_members    anggota (pub, veteran, siap, setoran Perbekalan Armada, statistik)
--   game.mp_raid_rt/_rtev   relay Pertarungan Terakhir (posisi kapal & kejadian)
--   Lobi    : Papan Armada di Sowtour. Siap = setor 50 Mesiu + 100 Beras (veteran tidak). Maks 2 veteran,
--             minimal 1 pemain baru, minimal 2 kapal. 4 siap -> berangkat otomatis 30 dtk.
--   Giliran : 15 dtk, semua kapten mengunci perintah; server mensimulasikan 3 dtk untuk semua kapal,
--             Black Pearl (Hasiolan & zafachmie) dan Sayap Patah. Kapal kapten yang putus koneksi diam.
--   Fase    : 1 Perisai Rantai (100->70%), 2 Arus Pusaran (70->50%), sinematik Tangan yang Dipaksa,
--             3 Murka (50->30%, Seruan), Pertarungan Terakhir realtime 75 dtk (<=30%). Bos dihitung server.
--   Kalah   : armada bubar, HP bos reset (serbuan berikutnya baris baru). Kapal lecet, tetap di Sowtour.
--   Veteran : 100.000 gold per serbuan menang, maks 1x per hari game.
-- Pelabuhan Rantai Lama menjadi pelabuhan tetap (pasar & reparasi) untuk pemain yang menyerahkan Tedsky
-- ke Dewan Dua Tangan. Waktu simulasi memakai game.dt_now() (bisa digeser tes lewat config DtClockOffset).
-- Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Konstanta (klien SerbuanBersama.html memakai angka yang sama)
-- ---------------------------------------------------------------------
create or replace function game.dt_k(p_key text) returns float8
language sql immutable as $$
  select case p_key
    when 'plan_ms'     then 15000   -- waktu memberi perintah per giliran
    when 'anim_ms'     then 3400    -- animasi 3 detik + jeda
    when 'start_ms'    then 9000    -- sinematik Teluk Dua Tangan sebelum giliran pertama
    when 'cine_ms'     then 12000   -- jeda tambahan untuk sinematik di tengah serbuan
    when 'final_ms'    then 75000   -- Pertarungan Terakhir realtime
    when 'final_lead'  then 4000    -- jeda sebelum Pertarungan Terakhir dimulai
    when 'max_rounds'  then 60      -- batas aman: lewat ini langsung Pertarungan Terakhir
    when 'ready_ms'    then 300000  -- 5 menit untuk menekan Siap
    when 'auto_ms'     then 30000   -- hitung mundur berangkat otomatis (4 kapal siap)
    when 'off_ms'      then 12000   -- tidak terdengar selama ini = putus koneksi (kapal diam)
    when 'abandon_ms'  then 600000  -- semua kapten hilang 10 menit = serbuan gagal
    when 'card_ms'     then 60000   -- Kartu Hasil
    -- bos
    when 'boss_hull'   then 1000
    when 'boss_shield' then 260
    when 'boss_dmg'    then 8       -- damage dasar satu salvo bos ke satu kapal (x tf kapal)
    when 'boss_range'  then 520
    when 'boss_sp'     then 0.72
    when 'boss_tm'     then 0.95
    when 'boss_r'      then 78      -- jari-jari tabrakan Sayap Patah
    when 'fin_dmg'     then 10      -- salvo bos di Pertarungan Terakhir
    when 'fin_fire_ms' then 3000
    -- Black Pearl
    when 'pearl_sh'    then 10      -- zafachmie ke perisai per giliran
    when 'pearl_hull'  then 6       -- ke lambung per giliran (x2 di fase 3)
    when 'pearl_fin'   then 6       -- per 4 dtk di Pertarungan Terakhir
    -- arena
    when 'stone_x'     then 1100
    when 'stone_y'     then 750
    when 'stone_r'     then 120     -- batu + karang di sekelilingnya (tidak bisa ditabrak)
    when 'lane_r'      then 560     -- jari-jari tengah jalur aman Arus Pusaran
    when 'ally_dmg'    then 4       -- per sekutu per 5 dtk di Pertarungan Terakhir
    when 'reload_rt'   then 3000    -- isi ulang realtime (ms, x rm kapal)
    when 'boss_arc'    then 0.85    -- busur salvo ke Sayap Patah (rad dari lambung samping)
    when 'boss_maxr'   then 520     -- jangkauan salvo ke Sayap Patah
    when 'boss_hitmul' then 1.3     -- sasaran besar: lebih mudah kena
    when 'reload_mul'  then 0.5     -- isi ulang giliran (x lb_reload): awak armada bergiliran
    when 'pull_dmg'    then 4       -- terseret Arus Pusaran
    when 'murka_mul'   then 1.6     -- salvo bos di fase Murka
    when 'second_mul'  then 0.35    -- salvo kedua bos ke kapal terdekat berikutnya
    else 0 end
$$;

insert into game.config(key, value) values ('DtClockOffset', '0') on conflict (key) do nothing;

-- jam serbuan (ms). Tes menggeser DtClockOffset untuk memajukan waktu.
create or replace function game.dt_now() returns bigint
language sql stable as $$ select game.now_ms() + coalesce(game.cfg_num('DtClockOffset', 0), 0)::bigint $$;

create or replace function game.dt_reward() returns bigint language sql immutable as $$ select 750000::bigint $$;
create or replace function game.dt_vet_reward() returns bigint language sql immutable as $$ select 100000::bigint $$;
create or replace function game.dt_mesiu() returns int language sql immutable as $$ select 50 $$;
create or replace function game.dt_beras() returns int language sql immutable as $$ select 100 $$;

create or replace function game.dt_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'duatangan'), 0) $$;

create or replace function game.dt_data(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce((select data from game.player_quests where player_id = p_pid and quest_id = 'duatangan'), '{}'::jsonb) $$;

create or replace function game.dt_vet(p_pid uuid) returns boolean
language sql stable as $$ select game.dt_step(p_pid) >= 5 $$;

-- ms (jam nyata) saat prolog boleh muncul: 3 hari game setelah penutup Quest 8
create or replace function game.dt_open_at(p_pid uuid) returns bigint
language sql stable as $$
  select (extract(epoch from coalesce(q.done_at, q.updated_at)) * 1000)::bigint + 3 * game.lt_len_ms()
    from game.player_quests q where q.player_id = p_pid and q.quest_id = 'limatangan' and q.step >= 10
$$;

create or replace function game.dt_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = greatest(step, p_step), data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 5 and done_at is null then now() else done_at end
   where player_id = p_pid and quest_id = 'duatangan'
$$;

-- Rantai Lama menjadi pelabuhan tetap untuk pemain yang menyerahkan Tedsky ke Dewan Dua Tangan
create or replace function game.dt_rantai_open(p_pid uuid) returns boolean
language sql stable as $$ select coalesce(game.dt_data(p_pid) ->> 'fate' = 'dewan', false) $$;

-- titik khusus quest untuk pemain ini (Rantai Lama bisa sudah jadi pelabuhan)
create or replace function game.dt_spot(p_pid uuid, p_city text) returns boolean
language sql stable as $$ select game.spot_city(p_city) and not (p_city = 'rantai_lama' and game.dt_rantai_open(p_pid)) $$;

-- ---------------------------------------------------------------------
-- Item, buku, artefak
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('art_jabat_tangan', 'Jabat Tangan Perak-Emas', 'artifact',
   '{"SpecialEffect": "jabat_tangan", "desc": "Dua tangan kecil, satu perak satu emas, saling menggenggam. Hadiah Dewan Dua Tangan. +10% harga jual di Kota Sowtour, Kepulauan Karang Garam, dan Joungjava saat terpasang."}',
   30000, null, 'quest', 21)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_peta_dua_tangan', 'Peta Dua Tangan', 'V', '{"Navigation":15}', 'dua_tangan_peta', 0, 'quest', 101)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  special_effect = excluded.special_effect, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Teluk Dua Tangan: tempat di peta setelah Quest 9 (tanpa pasar)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('teluk_dua_tangan', 'Teluk Dua Tangan', 'DuaTangan', 1.0, '', 204, 68, 18, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;

select game.cfg_set('CitiesVersion', '8-duatangan');

create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city in ('titik_buta', 'pusaran', 'rantai_lama', 'teluk_dua_tangan'), false) $$;

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
    when 'DuaTangan' then 'Dua karang raksasa berbentuk telapak tangan, dan di tengah pusaran yang kini tenang: Jantung Jalur, batu bercetak dua tangan yang menyala emas dan perak. Tak ada dermaga, tak ada pasar - hanya cahaya.'
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
      or (p_city = 'teluk_dua_tangan' and game.dt_step(p_pid) >= 5)
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
      || (case when game.dt_step(p_pid) >= 5 then '["teluk_dua_tangan"]'::jsonb else '[]'::jsonb end)
$$;

-- ---------------------------------------------------------------------
-- Pelabuhan Rantai Lama (pemain yang memilih Dewan): pasar, misi, bank, gudang, reparasi
-- ---------------------------------------------------------------------
create or replace function game.dt_market_role(p_comm text) returns text
language sql immutable as $$
  select case when p_comm in ('besi', 'tools', 'senjata') then 'produce'
              when p_comm in ('beras', 'kayu_jati', 'kain') then 'consume' else 'neutral' end
$$;

insert into game.market(city_id, commodity_id, base_price, current_price, role)
select 'rantai_lama', co.id, co.base, co.base, game.dt_market_role(co.id)
  from game.commodities co where co.active
on conflict (city_id, commodity_id) do update set base_price = excluded.base_price, role = excluded.role;

create or replace function game.eco_require_trade_here(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.current_city(p_pid) is distinct from p_city then
    raise exception 'Kamu harus berada di kota ini untuk berdagang.';
  end if;
  if game.in_transit(p_pid) then
    raise exception 'Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.';
  end if;
  if game.dt_spot(p_pid, p_city) then
    if p_city = 'rantai_lama' then raise exception 'Tak ada pedagang di kota hantu ini, Kapten. Hanya tiang pasung dan angin.'; end if;
    raise exception 'Tak ada pedagang di tengah pusaran, Kapten. Yang ada hanya ombak, petir, dan meriam.';
  end if;
  if game.ww_market_closed(p_pid) then
    raise exception 'Toko tutup. Kami diminta diam oleh Pemerintah.';
  end if;
  if p_city = 'marie_regal' and game.ww_step(p_pid) < 12 then
    raise exception 'AKSES DITOLAK. Seluruh toko Marie Regal tertutup bagi tamu.';
  end if;
end $$;

create or replace function game.ww_mission_guard(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.dt_spot(p_pid, p_city) then
    raise exception 'Tak ada gubernur, apalagi papan misi, di tengah badai ini.';
  end if;
  if game.ww_angry(p_pid, p_city) then
    raise exception 'Gubernur menolak bekerja sama denganmu. "Kau menjual pulau kami, Kapten."';
  end if;
end $$;

create or replace function game.spot_service_guard(p_pid uuid) returns void
language plpgsql as $$
begin
  if game.dt_spot(p_pid, game.current_city(p_pid)) then
    raise exception 'Tak ada gudang, bank, apalagi pedagang di tengah badai ini, Kapten. Hanya ombak, petir, dan baja.';
  end if;
end $$;

create or replace function game.lt_repair_block(p_pid uuid, p_city text) returns text
language sql stable as $$
  select case
    when p_city = 'rantai_lama' and not game.dt_rantai_open(p_pid) then 'Tak ada galangan di kota hantu ini, Kapten. Hanya tiang pasung dan angin.'
    when p_city = 'teluk_dua_tangan' then 'Tak ada galangan di teluk ini, Kapten. Hanya cahaya.'
    when p_city = 'sowtour' and game.lt_step(p_pid) between 1 and 6 then 'Galangan Sowtour tutup. Warga bersembunyi di balik kain hitam; tak ada yang berani bekerja di bawah mata burung itu.'
    else null end
$$;

-- ---------------------------------------------------------------------
-- Hadiah: Peta Dua Tangan (waktu tempuh -20% di rute pulau Saga 2) & Jabat Tangan (+10% harga jual)
-- ---------------------------------------------------------------------
-- Tide v35: penyesuaian per rute menerima kapal yang sudah dihitung (lihat lt_route_ship di 0028);
-- isi penyesuaian identik dengan versi sebelumnya.
create or replace function game.lt_ship_for_route(p_pid uuid, p_origin text, p_dest text) returns jsonb
language sql stable as $$
  select game.lt_route_ship(p_pid, p_origin, p_dest, game.ship_json(p_pid))
$$;
create or replace function game.lt_route_ship(p_pid uuid, p_origin text, p_dest text, p_sh jsonb) returns jsonb
language plpgsql stable as $$
declare sh jsonb := coalesce(p_sh, '{}'::jsonb); tm float8;
begin
  if game.lt_east_route(p_pid, p_origin, p_dest) then sh := sh || '{"LegendEast": true}'::jsonb; end if;
  if (game.voy_far_city(p_origin) or game.voy_far_city(p_dest)) and coalesce(game.ship_legend(p_pid), '') <> 'pearl'
     and coalesce(game.book_has_effect(p_pid, 'dua_tangan_peta'), false) then
    tm := coalesce(nullif(game.voy_num(sh -> 'TravelMul'), 0), 1);
    sh := sh || jsonb_build_object('TravelMul', round((tm * 0.8)::numeric, 4));
  end if;
  return sh;
end $$;

create or replace function game.eco2_muls(p_pid uuid, p_city text, p_comm text, out buy_mul double precision, out sell_mul double precision,
  out ev_mul double precision)
language plpgsql stable as $$
declare s game.character_stats; trading double precision := 0; nego double precision := 0; rep double precision;
  sp double precision; ev int := 0; kb double precision; ks double precision;
begin
  select * into s from game.character_stats where player_id = p_pid;
  if found then trading := game.eco_stat_bonus(s.trading); nego := game.eco_stat_bonus(s.negotiation); end if;
  rep := game.eco_rep_bonus(p_pid, p_city);
  kb := least(0.8, greatest(0, (trading + game.eco_black_market_extra(p_pid) + rep) / 25));
  ks := least(0.8, greatest(0, (nego + rep) / 25));
  sp := coalesce((select spread from game.commodities where id = p_comm), 0.15)::double precision;
  buy_mul := 1 + sp / 2 * (1 - kb);
  sell_mul := 1 - sp / 2 * (1 - ks);
  -- Tide v34: Jabat Tangan Perak-Emas (artefak terpasang) +10% harga jual di tiga kota, tetap di bawah harga beli
  if p_city in ('sowtour', 'karang_garam', 'joungjava') and coalesce(game.artifact_has_effect(p_pid, 'jabat_tangan'), false) then
    sell_mul := least(buy_mul - 0.01, sell_mul * 1.10);
  end if;
  begin ev := coalesce(game.event_price_pct(p_city), 0); exception when others then ev := 0; end;
  ev_mul := (1 + ev::double precision / 100) * (1 - game.eco_arms_discount(p_city, p_comm) / 100);
  -- Saga 2 (0023): krisis pasar per pemain saat kompas dunia rusak
  ev_mul := ev_mul * coalesce(game.quest_price_mul(p_pid, p_city, p_comm), 1);
end $$;

-- ---------------------------------------------------------------------
-- Tabel serbuan
-- ---------------------------------------------------------------------
create table if not exists game.mp_raids (
  id        text primary key,
  status    text not null default 'lobby',   -- lobby | active | done | cancelled
  leader    uuid,
  created   bigint not null default 0,
  depart_at bigint,                          -- hitung mundur berangkat otomatis
  started   bigint,
  ended     bigint,
  st        jsonb,                           -- {w, boss, pearl, ships:{pub:{..}}, order:[pub]}
  ord       jsonb not null default '{}'::jsonb,  -- perintah giliran ini {pub: order} (rahasia)
  ev        jsonb,                           -- hasil giliran terakhir (animasi)
  phase     text,                            -- plan | final
  round     int not null default 0,
  round_ts  bigint,
  final_ts  bigint,
  result    text,                            -- win | loss
  stats     jsonb not null default '{}'::jsonb,
  log       jsonb not null default '[]'::jsonb,
  card      jsonb
);
create index if not exists mp_raids_status_idx on game.mp_raids (status);

create table if not exists game.mp_raid_members (
  raid_id   text not null references game.mp_raids(id) on delete cascade,
  player_id uuid not null references game.players(player_id) on delete cascade on update cascade,
  pub       text not null,
  n         text not null default '',
  vet       boolean not null default false,
  ready     boolean not null default false,
  joined_ms bigint not null default 0,
  seen_ms   bigint not null default 0,
  supply    jsonb,                           -- setoran Perbekalan Armada {mesiu, beras}
  fighter   jsonb,
  state     text not null default 'in',      -- in | fled | sunk
  card_seen boolean not null default false,
  primary key (raid_id, player_id)
);
create index if not exists mp_raid_members_pid_idx on game.mp_raid_members (player_id);

create table if not exists game.mp_raid_rt (
  raid_id text not null,
  pub     text not null,
  st      jsonb,
  ts      bigint not null default 0,
  primary key (raid_id, pub)
);
create table if not exists game.mp_raid_rtev (
  seq     bigserial primary key,
  raid_id text not null,
  ev      jsonb not null,
  ts      bigint not null
);
create index if not exists mp_raid_rtev_idx on game.mp_raid_rtev (raid_id, seq);
alter table game.mp_raids enable row level security;
alter table game.mp_raid_members enable row level security;
alter table game.mp_raid_rt enable row level security;
alter table game.mp_raid_rtev enable row level security;

-- armada aktif (lobi / bertempur) milik pemain
create or replace function game.dt_raid_of(p_pid uuid) returns text
language sql stable as $$
  select r.id from game.mp_raid_members m join game.mp_raids r on r.id = m.raid_id
   where m.player_id = p_pid and r.status in ('lobby', 'active') and m.state <> 'fled'
   order by r.created desc limit 1
$$;

-- ---------------------------------------------------------------------
-- Bekal Tempur dari Quest 8 (menempel pada kapal pemiliknya)
-- ---------------------------------------------------------------------
create or replace function game.dt_hook_mul(p_grade text) returns float8
language sql immutable as $$ select case p_grade when 'sempurna' then 1.8 when 'baik' then 1.4 else 1.0 end $$;

create or replace function game.dt_lane(p_beads int, p_hasiolan text) returns float8
language sql immutable as $$
  select least(210, (case when coalesce(p_beads, 0) >= 5 then 160 when coalesce(p_beads, 0) >= 2 then 110 else 70 end)
       + case when p_hasiolan = 'percaya' then (case when coalesce(p_beads, 0) >= 5 then 50 when coalesce(p_beads, 0) >= 2 then 50 else 40 end) else 0 end)::float8
$$;

create or replace function game.dt_bekal(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare d jsonb := game.lt_data(p_pid); g text := coalesce(d ->> 'hookGrade', 'kasar'); b int := coalesce((d ->> 'beads')::int, 0);
  h text := d ->> 'hasiolan';
begin
  if g = 'retak' then g := 'kasar'; end if;
  return jsonb_build_object('hook', g, 'hookMul', game.dt_hook_mul(g), 'beads', b, 'hasiolan', h,
    'lane', game.dt_lane(b, h), 'immune', h = 'ambil', 'cry', coalesce((d ->> 'jejakOk')::boolean, false),
    'allies', game.lt_allies((d ->> 'drumBest')::int));
end $$;

-- ---------------------------------------------------------------------
-- Syarat
-- ---------------------------------------------------------------------
create or replace function game.dt_join_block(p_pid uuid) returns text
language plpgsql as $$
declare v_slot text;
begin
  if game.lt_step(p_pid) < 10 then return 'Hanya kapten yang sudah menjemput Lima Tangan yang mendengar genderang ini.'; end if;
  if game.dt_step(p_pid) < 1 then return 'Surat Teh Euis belum sampai padamu, Kapten.'; end if;
  if game.dt_step(p_pid) between 3 and 4 then return 'Sayap Patah sudah kandas, Kapten. Teluk Dua Tangan menunggu tanganmu di batu.'; end if;
  if game.in_transit(p_pid) then return 'Merapat dulu di Kota Sowtour, Kapten.'; end if;
  if game.current_city(p_pid) is distinct from 'sowtour' then return 'Papan Armada ada di dermaga Kota Sowtour.'; end if;
  v_slot := game.mp_slot(p_pid);
  if v_slot is not null then
    perform game.mp_duel_refresh(v_slot);
    if game.mp_slot(p_pid) is not null then return 'Selesaikan duelmu dulu.'; end if;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Status pribadi (kunci 'duatangan' di api_getGameState)
-- ---------------------------------------------------------------------
create or replace function game.dt_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_step int; d jsonb; ltd jsonb; v_open bigint; v_raid text; v_lobbies int; v_online int; v_now bigint := game.dt_now();
begin
  if game.lt_step(p_pid) < 10 then return null; end if;
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'duatangan';
  v_step := coalesce(q.step, 0);
  d := coalesce(q.data, '{}'::jsonb);
  ltd := game.lt_data(p_pid);
  v_open := game.dt_open_at(p_pid);
  v_raid := game.dt_raid_of(p_pid);
  select count(*) into v_lobbies from game.mp_raids where status = 'lobby';
  select count(*) into v_online from game.mp_presence o
   where game.mp_online(o) and o.player_id <> p_pid and game.lt_step(o.player_id) >= 10 and game.dt_step(o.player_id) >= 1;
  return jsonb_build_object(
    'step', v_step, 'done', v_step >= 5, 'veteran', v_step >= 5,
    'openAt', v_open, 'ready', v_step > 0 or (v_open is not null and game.now_ms() >= v_open),
    'raidId', v_raid, 'lobbies', v_lobbies, 'online', v_online,
    'bekal', game.dt_bekal(p_pid),
    'mesiu', game.item_qty(p_pid, 'mesiu'), 'beras', game.item_qty(p_pid, 'beras'),
    'needMesiu', game.dt_mesiu(), 'needBeras', game.dt_beras(),
    'arrived', coalesce((d ->> 'arrived')::boolean, false), 'euisSupply', coalesce((d ->> 'euisSupply')::boolean, false),
    'raidWon', d ->> 'raidWon', 'petrik', coalesce((d ->> 'petrik')::boolean, false),
    'fleet', coalesce(d -> 'fleet', '[]'::jsonb), 'fate', d ->> 'fate', 'credits', coalesce((d ->> 'credits')::boolean, false),
    'vetWins', coalesce((d ->> 'vetWins')::int, 0), 'vetPaidDay', (d ->> 'vetDay')::int, 'gameDay', game.game_day(),
    'tries', coalesce((d ->> 'tries')::int, 0), 'firstHand', coalesce((d ->> 'firstHand')::int, 0),
    'fullFleet', coalesce((d ->> 'fullFleet')::boolean, false), 'duo', coalesce((d ->> 'duo')::boolean, false),
    'history', coalesce(d -> 'history', '[]'::jsonb),
    'reward', (d ->> 'reward')::bigint,
    -- pilihan lama (cerita pribadi)
    'truth', game.ts_truth(p_pid), 'tempa', game.ts_data(p_pid) ->> 'tempa',
    'upayy', game.ts_data(p_pid) ->> 'upayy_answer', 'garlyena', game.ts_data(p_pid) ->> 'garlyena',
    'cocoAdvice', ltd ->> 'cocoAdvice', 'hasiolan', ltd ->> 'hasiolan', 'hookGrade', ltd ->> 'hookGrade',
    'kuas', game.item_qty(p_pid, 'qi_kuas_tedsky') > 0,
    'now', v_now);
end $$;

-- ---------------------------------------------------------------------
-- Larangan berlayar selama lobi / serbuan (dipanggil quest_on_sail baris pertama lewat mp_sail_guard)
-- ---------------------------------------------------------------------
create or replace function game.mp_sail_guard(p_pid uuid) returns void
language plpgsql as $$
declare v_slot text; d game.mp_duels; v_raid text; v_st text;
begin
  v_slot := game.mp_slot(p_pid);
  if v_slot is not null then
    d := game.mp_duel_refresh(v_slot);
    if d.status = 'invited' then raise exception 'Batalkan dulu tantangan duelmu sebelum berlayar.'; end if;
    if d.status = 'active' then raise exception 'Selesaikan duelmu dulu sebelum berlayar.'; end if;
  end if;
  v_raid := game.dt_raid_of(p_pid);
  if v_raid is not null then
    select status into v_st from game.mp_raids where id = v_raid;
    if v_st = 'lobby' then raise exception 'Kau masih tercatat di Papan Armada. Keluar dari armada dulu sebelum berlayar.'; end if;
    if v_st = 'active' then raise exception 'Armadamu sedang menyerbu Teluk Dua Tangan.'; end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Geometri & AI
-- ---------------------------------------------------------------------
-- kemudi menuju titik (tx,ty) dari (x,y,h)
create or replace function game.dt_steer(x float8, y float8, h float8, tx float8, ty float8) returns int
language plpgsql immutable as $$
declare rel float8 := game.lb_ang(atan2(tx - x, -(ty - y)) - h);
begin
  if abs(rel) < 0.12 then return 0; end if;
  return case when rel > 0 then (case when rel > 0.55 then 2 else 1 end) else (case when rel < -0.55 then -2 else -1 end) end;
end $$;

-- AI Sayap Patah: mengejar sasaran sampai jarak salvo, lalu memutar lambung; menjauhi batu
create or replace function game.dt_boss_rud(bx float8, by_ float8, bh float8, tx float8, ty float8) returns int
language plpgsql immutable as $$
declare d float8; rel float8; sx float8 := game.dt_k('stone_x'); sy float8 := game.dt_k('stone_y'); ds float8; away float8;
begin
  ds := sqrt(power(bx - sx, 2) + power(by_ - sy, 2));
  if ds < game.dt_k('stone_r') + 170 then
    away := game.lb_ang(atan2(bx - sx, -(by_ - sy)) - bh);
    return case when away > 0 then 2 else -2 end;
  end if;
  if bx < 260 or bx > 1940 or by_ < 240 or by_ > 1260 then return game.dt_steer(bx, by_, bh, sx, sy); end if;
  d := sqrt(power(tx - bx, 2) + power(ty - by_, 2));
  rel := game.lb_ang(atan2(tx - bx, -(ty - by_)) - bh);
  if d > 380 then return game.dt_steer(bx, by_, bh, tx, ty); end if;
  -- dekat: putar sampai sasaran di samping (+-90 derajat)
  if abs(rel) < pi() / 2 - 0.25 then return case when rel > 0 then -1 else 1 end; end if;
  if abs(rel) > pi() / 2 + 0.25 then return case when rel > 0 then 1 else -1 end; end if;
  return 0;
end $$;

-- titik tujuan berputar searah jarum jam di sekeliling (cx,cy) berjari-jari rr
create or replace function game.dt_orbit_rud(x float8, y float8, h float8, cx float8, cy float8, rr float8) returns int
language plpgsql immutable as $$
declare th float8 := atan2(y - cy, x - cx) + 0.55;
begin
  return game.dt_steer(x, y, h, cx + cos(th) * rr, cy + sin(th) * rr);
end $$;

-- salvo bos ke satu kapal: damage lambung
create or replace function game.dt_boss_hit(d float8, tf float8, mul float8) returns float8
language sql volatile as $$
  select case when d > game.dt_k('boss_range') then 0
    else game.dt_k('boss_dmg') * greatest(0.3, least(1.0, 1.15 - d / 520)) * tf * mul * (0.85 + random() * 0.3) end
$$;

-- salvo ke Sayap Patah: sasaran raksasa -> busur lebih lebar, jangkauan lebih jauh, lebih mudah kena
create or replace function game.dt_volley_boss(fx float8, fy float8, fh float8, tx float8, ty float8, side int, ammo text,
  crew float8, dm float8, hm float8)
returns jsonb language plpgsql volatile as $$
declare rel float8; off float8; q float8 := 0; d float8; maxr float8; p float8; hits jsonb := '[]'::jsonb; k int; hit boolean;
  dh float8 := 0; ds float8 := 0; dc float8 := 0; cl float8; arc float8 := game.dt_k('boss_arc');
begin
  d := sqrt(power(tx - fx, 2) + power(ty - fy, 2));
  rel := game.lb_ang(atan2(tx - fx, -(ty - fy)) - fh);
  off := abs(game.lb_ang(rel - side * pi() / 2));
  if off <= arc then q := 1 - off / arc * 0.5; end if;
  maxr := case when ammo = 'grape' then 340 else game.dt_k('boss_maxr') end;
  p := greatest(0, least(0.95, (1.08 - d / (maxr * 1.08)) * hm * game.dt_k('boss_hitmul'))) * (0.75 + 0.25 * crew / 100);
  cl := greatest(0, least(1, (340 - d) / 220));
  for k in 1..5 loop
    hit := q > 0 and d <= maxr and random() < p * q;
    hits := hits || to_jsonb(hit);
    if hit then
      if ammo = 'ball' then dh := dh + (3.4 + random() * 1.2) * dm; dc := dc + 0.6;
      elsif ammo = 'chain' then ds := ds + (5.5 + random() * 2) * dm; dh := dh + 0.6;
      else dc := dc + (5 + random() * 2) * (0.35 + 0.65 * cl) * dm; dh := dh + 0.8;
      end if;
    end if;
  end loop;
  return jsonb_build_object('hits', hits, 'd', round(d::numeric, 1), 'q', round(q::numeric, 3),
    'hull', round(dh::numeric, 2), 'sail', round(ds::numeric, 2), 'crew', round(dc::numeric, 2));
end $$;

create or replace function game.dt_dist(ax float8, ay float8, bx float8, by_ float8) returns float8
language sql immutable as $$ select sqrt(power(bx - ax, 2) + power(by_ - ay, 2)) $$;

-- ---------------------------------------------------------------------
-- Statistik per kapten
-- ---------------------------------------------------------------------
create or replace function game.dt_stat_add(p_stats jsonb, p_pub text, p_key text, p_v float8) returns jsonb
language sql immutable as $$
  select coalesce(p_stats, '{}'::jsonb) || jsonb_build_object(p_pub,
    coalesce(p_stats -> p_pub, '{}'::jsonb) || jsonb_build_object(p_key, round((coalesce((p_stats -> p_pub ->> p_key)::float8, 0) + p_v)::numeric, 2)))
$$;

-- ---------------------------------------------------------------------
-- Simulasi satu giliran untuk semua kapal (60 langkah x 0,05 dtk)
-- ---------------------------------------------------------------------
create or replace function game.dt_resolve(r game.mp_raids, p_base bigint) returns game.mp_raids
language plpgsql as $$
declare
  s jsonb := r.st; w float8 := (r.st ->> 'w')::float8; sh jsonb; o jsonb;
  pubs text[]; n int; i int; j int; k int; t float8 := 0; dt float8 := 0.05; fired boolean := false;
  x float8[]; y float8[]; h float8[]; v float8[]; hull float8[]; sail float8[]; crew float8[]; rlL float8[]; rlR float8[];
  rud int[]; sl int[]; am text[]; fl boolean[]; fr boolean[]; cr boolean[]; on_ boolean[];
  sp float8[]; tm float8[]; hm float8[]; rm float8[]; dm float8[]; tf float8[]; lane float8[]; hookm float8[];
  alive boolean[]; reef float8[]; outc int[]; tr jsonb[]; ramcd float8[];
  B jsonb := r.st -> 'boss'; P jsonb := r.st -> 'pearl';
  bx float8; by_ float8; bh float8; bv float8; bhull float8; bmax float8; bsh float8; bphase int; brud int := 0; bsl int := 1; stun boolean := false;
  px float8; py float8; ph float8; pv float8; prud int; ptr jsonb := '[]'::jsonb; btr jsonb := '[]'::jsonb;
  sx float8 := game.dt_k('stone_x'); sy float8 := game.dt_k('stone_y'); sr float8 := game.dt_k('stone_r'); lr float8 := game.dt_k('lane_r');
  br float8 := game.dt_k('boss_r');
  rr_ float8; th float8; dd float8; bb float8; push float8; rv float8; hw float8; mul float8;
  tgt int; tgt2 int; best float8; vol jsonb; raw float8; shd float8; hd float8; dmg float8;
  shots jsonb := '[]'::jsonb; evs jsonb := '[]'::jsonb; stats jsonb := coalesce(r.stats, '{}'::jsonb);
  cry_by text; dmg_mul float8 := 1; d_sh float8 := 0; d_hull float8 := 0; v_cine text; v_any boolean;
  r_ float8[]; t_now bigint := game.dt_now(); v_auto jsonb := '{}'::jsonb; v_side int;
begin
  pubs := array(select jsonb_array_elements_text(s -> 'order'));
  n := coalesce(array_length(pubs, 1), 0);
  bx := (B ->> 'x')::float8; by_ := (B ->> 'y')::float8; bh := (B ->> 'h')::float8; bv := (B ->> 'v')::float8;
  bhull := (B ->> 'hull')::float8; bmax := (B ->> 'max')::float8; bsh := (B ->> 'shield')::float8; bphase := (B ->> 'phase')::int;
  px := (P ->> 'x')::float8; py := (P ->> 'y')::float8; ph := (P ->> 'h')::float8; pv := (P ->> 'v')::float8;

  for i in 1..n loop
    sh := s -> 'ships' -> pubs[i];
    on_[i] := coalesce((sh ->> 'on')::boolean, true);
    alive[i] := coalesce((sh ->> 'alive')::boolean, true) and not coalesce((sh ->> 'fled')::boolean, false);
    o := r.ord -> pubs[i];
    if o is null then
      -- putus koneksi: kapal diam (layar setengah, kemudi lurus). Online tapi terlambat: lanjut haluan, tidak menembak.
      o := case when on_[i] then game.lb_auto(sh) else jsonb_build_object('rud', 0, 'sails', 0, 'fl', false, 'fr', false, 'ammo', coalesce(sh ->> 'ammo', 'ball'), 'auto', true) end;
      v_auto := v_auto || jsonb_build_object(pubs[i], case when on_[i] then 'late' else 'off' end);
    end if;
    x[i] := (sh ->> 'x')::float8; y[i] := (sh ->> 'y')::float8; h[i] := (sh ->> 'h')::float8; v[i] := (sh ->> 'v')::float8;
    hull[i] := (sh ->> 'hull')::float8; sail[i] := (sh ->> 'sail')::float8; crew[i] := (sh ->> 'crew')::float8;
    rlL[i] := coalesce((sh ->> 'rlL')::float8, 0); rlR[i] := coalesce((sh ->> 'rlR')::float8, 0);
    rud[i] := coalesce((o ->> 'rud')::int, 0); sl[i] := coalesce((o ->> 'sails')::int, 1); am[i] := coalesce(o ->> 'ammo', 'ball');
    fl[i] := coalesce((o ->> 'fl')::boolean, false); fr[i] := coalesce((o ->> 'fr')::boolean, false);
    cr[i] := coalesce((o ->> 'cry')::boolean, false);
    sp[i] := coalesce((sh ->> 'sp')::float8, 1); tm[i] := coalesce((sh ->> 'tm')::float8, 1); hm[i] := coalesce((sh ->> 'hm')::float8, 1);
    rm[i] := coalesce((sh ->> 'rm')::float8, 1); dm[i] := coalesce((sh ->> 'dm')::float8, 1); tf[i] := coalesce((sh ->> 'tf')::float8, 1);
    lane[i] := coalesce((sh ->> 'lane')::float8, 70); hookm[i] := coalesce((sh ->> 'hookMul')::float8, 1);
    reef[i] := 0; outc[i] := 0; ramcd[i] := 0; tr[i] := '[]'::jsonb;
    if not alive[i] then rud[i] := 0; sl[i] := 0; fl[i] := false; fr[i] := false; cr[i] := false; v[i] := 0; end if;
  end loop;

  -- Seruan (fase 3): kapten pertama yang berseru membungkam Sayap Patah satu giliran
  if bphase = 3 then
    for i in 1..n loop
      if cr[i] and alive[i] then
        if cry_by is null and coalesce((s -> 'ships' -> pubs[i] ->> 'cry')::boolean, false) then
          cry_by := pubs[i]; stun := true; dmg_mul := 1.5;
          s := jsonb_set(s, array['ships', pubs[i], 'cry'], 'false'::jsonb);
          stats := game.dt_stat_add(stats, pubs[i], 'cry', 1);
          evs := evs || jsonb_build_array(jsonb_build_object('k', 'cry', 'by', pubs[i], 'n', s -> 'ships' -> pubs[i] ->> 'n'));
        end if;
        fl[i] := false; fr[i] := false;   -- Seruan menggantikan tembakan giliran ini
      end if;
    end loop;
  end if;

  -- AI bos: sasaran = kapal terdekat (fase 2: paling dekat dengan batu)
  tgt := null; best := 1e9;
  for i in 1..n loop
    if alive[i] then
      dd := case when bphase = 2 then game.dt_dist(x[i], y[i], sx, sy) else game.dt_dist(x[i], y[i], bx, by_) end;
      if dd < best then best := dd; tgt := i; end if;
    end if;
  end loop;
  if stun then brud := 0; bsl := 0;
  elsif tgt is not null then brud := game.dt_boss_rud(bx, by_, bh, x[tgt], y[tgt]);
  end if;
  -- Black Pearl: memutari bos (fase 2: jalur paling aman di sekeliling batu)
  prud := case when bphase = 2 then game.dt_orbit_rud(px, py, ph, sx, sy, lr) else game.dt_orbit_rud(px, py, ph, bx, by_, 300) end;

  for k in 1..60 loop
    for i in 1..n loop
      if alive[i] then
        r_ := game.lb_step(x[i], y[i], h[i], v[i], rud[i], sl[i], sail[i], dt, w, sp[i], tm[i]);
        x[i] := r_[1]; y[i] := r_[2]; h[i] := r_[3]; v[i] := r_[4];
        if r_[5] = 1 and reef[i] <= 0 then hull[i] := greatest(0, hull[i] - 2.5 * tf[i]); reef[i] := 1.2; end if;
        reef[i] := reef[i] - dt;
        -- arus teluk: searah jarum jam, pelan; di Arus Pusaran kencang di luar jalur aman
        rr_ := game.dt_dist(x[i], y[i], sx, sy); th := atan2(y[i] - sy, x[i] - sx);
        x[i] := x[i] - sin(th) * 5 * dt; y[i] := y[i] + cos(th) * 5 * dt;
        if bphase = 2 then
          hw := lane[i] + case when game.dt_dist(x[i], y[i], px, py) < 170 then 40 else 0 end;
          if abs(rr_ - lr) > hw then
            outc[i] := outc[i] + 1;
            x[i] := x[i] + (-sin(th) * 26 + cos(th) * sign(rr_ - lr) * 12) * dt;
            y[i] := y[i] + (cos(th) * 26 + sin(th) * sign(rr_ - lr) * 12) * dt;
          end if;
        end if;
        -- batu tidak bisa ditabrak
        rr_ := game.dt_dist(x[i], y[i], sx, sy);
        if rr_ < sr + 30 then
          th := atan2(y[i] - sy, x[i] - sx);
          x[i] := sx + cos(th) * (sr + 30); y[i] := sy + sin(th) * (sr + 30); v[i] := v[i] * 0.5;
        end if;
        x[i] := greatest(60, least(2140, x[i])); y[i] := greatest(60, least(1440, y[i]));
      end if;
      rlL[i] := greatest(0, rlL[i] - dt); rlR[i] := greatest(0, rlR[i] - dt); ramcd[i] := ramcd[i] - dt;
    end loop;
    r_ := game.lb_step(bx, by_, bh, bv, brud, bsl, 100, dt, w, game.dt_k('boss_sp'), game.dt_k('boss_tm'));
    bx := r_[1]; by_ := r_[2]; bh := r_[3]; bv := r_[4];
    if stun then bv := bv * 0.9; end if;
    rr_ := game.dt_dist(bx, by_, sx, sy);
    if rr_ < sr + br then th := atan2(by_ - sy, bx - sx); bx := sx + cos(th) * (sr + br); by_ := sy + sin(th) * (sr + br); bv := bv * 0.5; end if;
    r_ := game.lb_step(px, py, ph, pv, prud, 1, 100, dt, w, 0.9, 1.1);
    px := r_[1]; py := r_[2]; ph := r_[3]; pv := r_[4];
    rr_ := game.dt_dist(px, py, sx, sy);
    if rr_ < sr + 30 then th := atan2(py - sy, px - sx); px := sx + cos(th) * (sr + 30); py := sy + sin(th) * (sr + 30); end if;
    t := t + dt;

    if not fired and t >= 1.0 - 1e-9 then
      fired := true;
      -- kapten menembak Sayap Patah
      for i in 1..n loop
        for j in 1..2 loop
          v_side := case when j = 1 then -1 else 1 end;
          if alive[i] and ((j = 1 and fl[i] and rlL[i] <= 0) or (j = 2 and fr[i] and rlR[i] <= 0)) then
            vol := game.dt_volley_boss(x[i], y[i], h[i], bx, by_, v_side, am[i], crew[i], dm[i], hm[i]);
            if j = 1 then rlL[i] := game.lb_reload(crew[i]) * rm[i] * game.dt_k('reload_mul'); else rlR[i] := game.lb_reload(crew[i]) * rm[i] * game.dt_k('reload_mul'); end if;
            raw := (vol ->> 'hull')::float8 + (vol ->> 'sail')::float8 * 0.6 + (vol ->> 'crew')::float8 * 0.4;
            shd := 0; hd := 0;
            if bsh > 0 then
              shd := ((vol ->> 'hull')::float8 + (vol ->> 'sail')::float8) * hookm[i] * case when am[i] = 'chain' then 2 else 1 end * dmg_mul;
              hd := raw * 0.25 * dmg_mul;
            else
              hd := raw * dmg_mul;
            end if;
            d_sh := d_sh + shd; d_hull := d_hull + hd;
            if shd > 0 then stats := game.dt_stat_add(stats, pubs[i], 'shield', shd); end if;
            if hd > 0 then stats := game.dt_stat_add(stats, pubs[i], 'hull', hd); end if;
            if shd > 0 and not coalesce((s -> 'ships' -> pubs[i] ->> 'hookSeen')::boolean, false) then
              s := jsonb_set(s, array['ships', pubs[i], 'hookSeen'], 'true'::jsonb);
              evs := evs || jsonb_build_array(jsonb_build_object('k', 'hook', 'by', pubs[i], 'g', s -> 'ships' -> pubs[i] ->> 'hook'));
            end if;
            shots := shots || jsonb_build_array(vol || jsonb_build_object('by', pubs[i], 'side', v_side, 'ammo', am[i],
              'fx', round(x[i]::numeric, 1), 'fy', round(y[i]::numeric, 1), 'fh', round(h[i]::numeric, 3),
              'tx', round(bx::numeric, 1), 'ty', round(by_::numeric, 1), 'sh', round(shd::numeric, 2), 'dmg', round(hd::numeric, 2)));
          end if;
        end loop;
      end loop;
      -- Black Pearl: zafachmie di meriam (fase 3: dua kali)
      if bsh > 0 then
        d_sh := d_sh + game.dt_k('pearl_sh') * (0.8 + random() * 0.4);
      else
        d_hull := d_hull + game.dt_k('pearl_hull') * (case when bphase = 3 then 2 else 1 end) * (0.8 + random() * 0.4) * dmg_mul;
      end if;
      shots := shots || jsonb_build_array(jsonb_build_object('by', 'pearl', 'fx', round(px::numeric, 1), 'fy', round(py::numeric, 1),
        'tx', round(bx::numeric, 1), 'ty', round(by_::numeric, 1), 'n', case when bphase = 3 then 2 else 1 end));
      -- Sayap Patah menembak (dibungkam Seruan = diam)
      if not stun then
        mul := case when bphase = 3 then game.dt_k('murka_mul') else 1 end;
        for i in 1..n loop
          if alive[i] then
            dd := game.dt_dist(x[i], y[i], bx, by_);
            dmg := 0;
            if bphase = 3 then dmg := game.dt_boss_hit(dd, tf[i], mul);          -- murka: semua kapal dalam jangkauan
            elsif i = tgt then dmg := game.dt_boss_hit(dd, tf[i], mul);
            end if;
            if dmg > 0 then
              hull[i] := greatest(0, hull[i] - dmg); crew[i] := greatest(0, crew[i] - dmg * 0.12); sail[i] := greatest(0, sail[i] - dmg * 0.2);
              stats := game.dt_stat_add(stats, pubs[i], 'taken', dmg);
              shots := shots || jsonb_build_array(jsonb_build_object('by', 'boss', 'to', pubs[i], 'fx', round(bx::numeric, 1), 'fy', round(by_::numeric, 1),
                'tx', round(x[i]::numeric, 1), 'ty', round(y[i]::numeric, 1), 'dmg', round(dmg::numeric, 2)));
            end if;
          end if;
        end loop;
        -- salvo kedua (fase 1-2): kapal terdekat berikutnya kena setengah
        if bphase < 3 then
          tgt2 := null; best := 1e9;
          for i in 1..n loop
            if alive[i] and i is distinct from tgt then
              dd := game.dt_dist(x[i], y[i], bx, by_);
              if dd < best then best := dd; tgt2 := i; end if;
            end if;
          end loop;
          if tgt2 is not null then
            dmg := game.dt_boss_hit(best, tf[tgt2], game.dt_k('second_mul'));
            if dmg > 0 then
              hull[tgt2] := greatest(0, hull[tgt2] - dmg); crew[tgt2] := greatest(0, crew[tgt2] - dmg * 0.12);
              stats := game.dt_stat_add(stats, pubs[tgt2], 'taken', dmg);
              shots := shots || jsonb_build_array(jsonb_build_object('by', 'boss', 'to', pubs[tgt2], 'fx', round(bx::numeric, 1), 'fy', round(by_::numeric, 1),
                'tx', round(x[tgt2]::numeric, 1), 'ty', round(y[tgt2]::numeric, 1), 'dmg', round(dmg::numeric, 2)));
            end if;
          end if;
        end if;
      end if;
      -- damage ke bos diterapkan bersama
      if bsh > 0 then
        bsh := greatest(0, bsh - d_sh);
        bhull := greatest(bmax * 0.70 + 1, bhull - d_hull);
      else
        bhull := greatest(0, bhull - d_hull);
      end if;
    end if;

    -- tabrakan: kapal vs Sayap Patah, kapal vs kapal
    for i in 1..n loop
      if alive[i] then
        dd := game.dt_dist(x[i], y[i], bx, by_);
        if dd < br then
          bb := atan2(x[i] - bx, -(y[i] - by_)); push := br - dd + 1;
          x[i] := x[i] + sin(bb) * push; y[i] := y[i] - cos(bb) * push;
          if ramcd[i] <= 0 then
            rv := v[i] + bv * 0.5;
            hull[i] := greatest(0, hull[i] - (2 + rv * 0.06) * tf[i]);
            v[i] := v[i] * 0.4; ramcd[i] := 1.0;
            evs := evs || jsonb_build_array(jsonb_build_object('k', 'ram', 'by', pubs[i]));
          end if;
        end if;
        for j in (i + 1)..n loop
          if alive[j] then
            dd := game.dt_dist(x[i], y[i], x[j], y[j]);
            if dd < 58 then
              bb := atan2(x[j] - x[i], -(y[j] - y[i])); push := (58 - dd) / 2 + 1;
              x[i] := x[i] - sin(bb) * push; y[i] := y[i] + cos(bb) * push; x[j] := x[j] + sin(bb) * push; y[j] := y[j] - cos(bb) * push;
            end if;
          end if;
        end loop;
      end if;
    end loop;

    if k % 5 = 0 then
      for i in 1..n loop tr[i] := tr[i] || jsonb_build_array(jsonb_build_array(round(x[i]::numeric, 1), round(y[i]::numeric, 1), round(h[i]::numeric, 3))); end loop;
      btr := btr || jsonb_build_array(jsonb_build_array(round(bx::numeric, 1), round(by_::numeric, 1), round(bh::numeric, 3)));
      ptr := ptr || jsonb_build_array(jsonb_build_array(round(px::numeric, 1), round(py::numeric, 1), round(ph::numeric, 3)));
    end if;
  end loop;

  -- Arus Pusaran: keluar jalur aman = terseret, lambung menghantam karang
  if bphase = 2 then
    for i in 1..n loop
      if alive[i] and outc[i] >= 20 then
        if coalesce((s -> 'ships' -> pubs[i] ->> 'immune')::boolean, false) then
          s := jsonb_set(s, array['ships', pubs[i], 'immune'], 'false'::jsonb);
          evs := evs || jsonb_build_array(jsonb_build_object('k', 'immune', 'by', pubs[i]));
        else
          hull[i] := greatest(0, hull[i] - game.dt_k('pull_dmg') * tf[i]); crew[i] := greatest(0, crew[i] - 2);
          stats := game.dt_stat_add(stats, pubs[i], 'taken', game.dt_k('pull_dmg') * tf[i]);
          evs := evs || jsonb_build_array(jsonb_build_object('k', 'pulled', 'by', pubs[i]));
        end if;
      end if;
    end loop;
  end if;

  -- kapal karam
  for i in 1..n loop
    if alive[i] and (hull[i] <= 0 or crew[i] <= 0) then
      alive[i] := false;
      evs := evs || jsonb_build_array(jsonb_build_object('k', 'sunk', 'by', pubs[i]));
      update game.mp_raid_members set state = 'sunk' where raid_id = r.id and pub = pubs[i] and state = 'in';
    end if;
  end loop;

  -- pergantian fase
  if bphase = 1 and bsh <= 0 then
    bphase := 2; bhull := least(bhull, bmax * 0.70); v_cine := 'rantai';
    evs := evs || jsonb_build_array(jsonb_build_object('k', 'phase', 'p', 2));
  end if;
  if bphase = 2 and bhull <= bmax * 0.50 then
    bphase := 3; v_cine := 'paksa';
    evs := evs || jsonb_build_array(jsonb_build_object('k', 'phase', 'p', 3));
    s := s || '{"paksa": true}'::jsonb;
  end if;

  for i in 1..n loop
    s := jsonb_set(s, array['ships', pubs[i]], (s -> 'ships' -> pubs[i]) || jsonb_build_object(
      'x', x[i], 'y', y[i], 'h', h[i], 'v', v[i], 'hull', hull[i], 'sail', sail[i], 'crew', crew[i], 'rlL', rlL[i], 'rlR', rlR[i],
      'rud', rud[i], 'sails', sl[i], 'ammo', am[i], 'alive', alive[i]));
  end loop;
  s := s || jsonb_build_object('w', game.lb_ang(w + (random() - 0.5) * 0.4),
    'boss', B || jsonb_build_object('x', bx, 'y', by_, 'h', bh, 'v', bv, 'hull', bhull, 'shield', bsh, 'phase', bphase, 'stun', stun),
    'pearl', P || jsonb_build_object('x', px, 'y', py, 'h', ph, 'v', pv));

  r.ev := jsonb_build_object('r', r.round, 'start', r.st, 'ord', r.ord, 'auto', v_auto, 'shots', shots, 'evs', evs,
    'tracks', (select jsonb_object_agg(pubs[q], tr[q]) from generate_series(1, n) q), 'boss', btr, 'pearl', ptr,
    'cine', v_cine, 'cry', cry_by, 'dHull', round(d_hull::numeric, 1), 'dShield', round(d_sh::numeric, 1));
  r.st := s; r.stats := stats; r.ord := '{}'::jsonb;
  r.log := r.log || jsonb_build_array(jsonb_build_object('r', r.round, 'boss', round(bhull::numeric), 'sh', round(bsh::numeric), 'p', bphase));
  while jsonb_array_length(r.log) > 80 loop r.log := r.log - 0; end loop;

  -- semua kapal karam / mundur = kalah
  v_any := false;
  for i in 1..n loop if alive[i] then v_any := true; end if; end loop;
  if not v_any then return game.dt_finish(r, 'loss'); end if;

  -- Pertarungan Terakhir
  if (bphase = 3 and bhull <= bmax * 0.30) or r.round >= game.dt_k('max_rounds') then
    r := game.dt_final_start(r, greatest(p_base, t_now) + game.dt_k('anim_ms')::bigint + case when v_cine is not null then game.dt_k('cine_ms')::bigint else 0 end);
    return r;
  end if;
  r.round := r.round + 1;
  r.round_ts := p_base + game.dt_k('anim_ms')::bigint + case when v_cine is not null then game.dt_k('cine_ms')::bigint else 0 end;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Pertarungan Terakhir (realtime, bos dihitung server)
-- ---------------------------------------------------------------------
create or replace function game.dt_final_start(r game.mp_raids, p_at bigint) returns game.mp_raids
language plpgsql as $$
declare pb text; sh jsonb;
begin
  r.phase := 'final';
  r.final_ts := p_at + game.dt_k('final_lead')::bigint;
  r.round_ts := r.final_ts;
  r.ev := coalesce(r.ev, '{}'::jsonb) || jsonb_build_object('final', true);
  r.st := r.st || jsonb_build_object('fb', jsonb_build_object('t', r.final_ts, 'rud', 0, 'fireAt', r.final_ts + 1500,
    'pearlAt', r.final_ts + 2000, 'allyAt', r.final_ts + 3000, 'aiAt', r.final_ts, 'tgt', null));
  delete from game.mp_raid_rt where raid_id = r.id;
  delete from game.mp_raid_rtev where raid_id = r.id;
  for pb, sh in select key, value from jsonb_each(r.st -> 'ships') loop
    insert into game.mp_raid_rt(raid_id, pub, st, ts) values (r.id, pb,
      jsonb_build_object('x', sh -> 'x', 'y', sh -> 'y', 'h', sh -> 'h', 'v', sh -> 'v', 'sails', 1), r.final_ts)
    on conflict (raid_id, pub) do update set st = excluded.st, ts = excluded.ts;
  end loop;
  return r;
end $$;

create or replace function game.dt_rtev(p_raid text, p_ev jsonb, p_ts bigint) returns void
language sql as $$ insert into game.mp_raid_rtev(raid_id, ev, ts) values (p_raid, p_ev, p_ts) $$;

-- damage ke bos di Pertarungan Terakhir (dengan pencatatan)
create or replace function game.dt_boss_dmg(r game.mp_raids, p_pub text, p_dmg float8, p_key text) returns game.mp_raids
language plpgsql as $$
declare bh float8;
begin
  if p_dmg <= 0 then return r; end if;
  bh := greatest(0, (r.st -> 'boss' ->> 'hull')::float8 - p_dmg);
  r.st := jsonb_set(r.st, '{boss,hull}', to_jsonb(bh));
  if p_pub is not null then r.stats := game.dt_stat_add(r.stats, p_pub, p_key, p_dmg); end if;
  return r;
end $$;

-- majukan bos sampai p_now (langkah 0,05 dtk), salvo bos, sekutu, Black Pearl
create or replace function game.dt_final_tick(r game.mp_raids, p_now bigint) returns game.mp_raids
language plpgsql as $$
declare
  fb jsonb := r.st -> 'fb'; B jsonb := r.st -> 'boss'; w float8 := (r.st ->> 'w')::float8;
  t bigint; steps int; k int; rr float8[]; bx float8; by_ float8; bh float8; bv float8; brud int;
  pubs text[]; n int; i int; xs float8[]; ys float8[]; al boolean[]; seen bigint[]; tfs float8[]; als int[];
  best float8; tgt int; best2 float8; tgt2 int; dd float8; dmg float8; v_end bigint := r.final_ts + game.dt_k('final_ms')::bigint; sh jsonb; rt game.mp_raid_rt;
  v_any boolean; th float8; sx float8 := game.dt_k('stone_x'); sy float8 := game.dt_k('stone_y'); sr float8 := game.dt_k('stone_r');
  fire_at bigint; pearl_at bigint; ally_at bigint; ai_at bigint; hl float8;
begin
  if r.status <> 'active' or r.phase <> 'final' then return r; end if;
  t := greatest(coalesce((fb ->> 't')::bigint, r.final_ts), r.final_ts);
  p_now := least(p_now, v_end);
  if p_now <= t then
    if game.dt_now() > v_end then return game.dt_finish(r, 'loss'); end if;
    return r;
  end if;
  pubs := array(select jsonb_array_elements_text(r.st -> 'order'));
  n := coalesce(array_length(pubs, 1), 0);
  for i in 1..n loop
    sh := r.st -> 'ships' -> pubs[i];
    select * into rt from game.mp_raid_rt where raid_id = r.id and pub = pubs[i];
    xs[i] := coalesce((rt.st ->> 'x')::float8, (sh ->> 'x')::float8); ys[i] := coalesce((rt.st ->> 'y')::float8, (sh ->> 'y')::float8);
    seen[i] := coalesce(rt.ts, 0);
    al[i] := coalesce((sh ->> 'alive')::boolean, true) and not coalesce((sh ->> 'fled')::boolean, false);
    tfs[i] := coalesce((sh ->> 'tf')::float8, 1); als[i] := coalesce((sh ->> 'allies')::int, 0);
  end loop;
  bx := (B ->> 'x')::float8; by_ := (B ->> 'y')::float8; bh := (B ->> 'h')::float8; bv := (B ->> 'v')::float8;
  brud := coalesce((fb ->> 'rud')::int, 0);
  fire_at := (fb ->> 'fireAt')::bigint; pearl_at := (fb ->> 'pearlAt')::bigint; ally_at := (fb ->> 'allyAt')::bigint; ai_at := (fb ->> 'aiAt')::bigint;
  steps := floor((p_now - t) / 50.0);
  if steps > 240 then t := p_now - 240 * 50; steps := 240; end if;
  for k in 1..steps loop
    t := t + 50;
    if t >= ai_at then
      tgt := null; best := 1e9;
      for i in 1..n loop
        if al[i] then dd := game.dt_dist(xs[i], ys[i], bx, by_); if dd < best then best := dd; tgt := i; end if; end if;
      end loop;
      brud := case when tgt is null then 0 else game.dt_boss_rud(bx, by_, bh, xs[tgt], ys[tgt]) end;
      ai_at := t + 1000;
    end if;
    rr := game.lb_step(bx, by_, bh, bv, brud, 1, 100, 0.05, w, game.dt_k('boss_sp'), game.dt_k('boss_tm'));
    bx := rr[1]; by_ := rr[2]; bh := rr[3]; bv := rr[4];
    dd := game.dt_dist(bx, by_, sx, sy);
    if dd < sr + game.dt_k('boss_r') then th := atan2(by_ - sy, bx - sx); bx := sx + cos(th) * (sr + game.dt_k('boss_r')); by_ := sy + sin(th) * (sr + game.dt_k('boss_r')); bv := bv * 0.5; end if;
    -- salvo bos: kapal terdekat penuh, terdekat kedua setengah
    if t >= fire_at then
      fire_at := t + game.dt_k('fin_fire_ms')::bigint;
      tgt := null; tgt2 := null; best := 1e9; best2 := 1e9;
      for i in 1..n loop
        if al[i] then
          dd := game.dt_dist(xs[i], ys[i], bx, by_);
          if dd < best then best2 := best; tgt2 := tgt; best := dd; tgt := i;
          elsif dd < best2 then best2 := dd; tgt2 := i; end if;
        end if;
      end loop;
      for i in 1..n loop
        if al[i] and (i = tgt or i = tgt2) then
          dd := game.dt_dist(xs[i], ys[i], bx, by_);
          if dd <= game.dt_k('boss_range') then
            dmg := game.dt_k('fin_dmg') * greatest(0.3, least(1.0, 1.15 - dd / 520)) * tfs[i] * (0.85 + random() * 0.3) * case when i = tgt then 1 else game.dt_k('second_mul') end;
            hl := greatest(0, (r.st -> 'ships' -> pubs[i] ->> 'hull')::float8 - dmg);
            r.st := jsonb_set(r.st, array['ships', pubs[i], 'hull'], to_jsonb(hl));
            r.st := jsonb_set(r.st, array['ships', pubs[i], 'crew'], to_jsonb(greatest(0, (r.st -> 'ships' -> pubs[i] ->> 'crew')::float8 - dmg * 0.1)));
            r.stats := game.dt_stat_add(r.stats, pubs[i], 'taken', dmg);
            perform game.dt_rtev(r.id, jsonb_build_object('k', 'bs', 'to', pubs[i], 'dmg', round(dmg::numeric, 1), 'hull', round(hl::numeric, 1),
              'fx', round(bx::numeric), 'fy', round(by_::numeric), 'tx', round(xs[i]::numeric), 'ty', round(ys[i]::numeric), 't', t), t);
            if hl <= 0 then
              al[i] := false;
              r.st := jsonb_set(r.st, array['ships', pubs[i], 'alive'], 'false'::jsonb);
              update game.mp_raid_members set state = 'sunk' where raid_id = r.id and pub = pubs[i] and state = 'in';
              perform game.dt_rtev(r.id, jsonb_build_object('k', 'sunk', 'by', pubs[i], 't', t), t);
            end if;
          end if;
        end if;
      end loop;
    end if;
    -- sekutu Tari Genderang (menempel pada kapal pembawanya; kapal putus koneksi tidak memanggil sekutu)
    if t >= ally_at then
      ally_at := t + 5000;
      for i in 1..n loop
        if al[i] and als[i] > 0 and t - seen[i] < 6000 then
          dmg := game.dt_k('ally_dmg') * als[i] * (0.8 + random() * 0.4);
          r := game.dt_boss_dmg(r, pubs[i], dmg, 'ally');
          perform game.dt_rtev(r.id, jsonb_build_object('k', 'al', 'by', pubs[i], 'n', als[i], 'dmg', round(dmg::numeric, 1), 't', t), t);
        end if;
      end loop;
    end if;
    -- Black Pearl
    if t >= pearl_at then
      pearl_at := t + 4000;
      dmg := game.dt_k('pearl_fin') * (0.8 + random() * 0.4);
      r := game.dt_boss_dmg(r, null, dmg, null);
      perform game.dt_rtev(r.id, jsonb_build_object('k', 'pf', 'dmg', round(dmg::numeric, 1), 'tx', round(bx::numeric), 'ty', round(by_::numeric), 't', t), t);
    end if;
    exit when (r.st -> 'boss' ->> 'hull')::float8 <= 0;
  end loop;
  r.st := jsonb_set(r.st, '{boss}', (r.st -> 'boss') || jsonb_build_object('x', bx, 'y', by_, 'h', bh, 'v', bv));
  r.st := jsonb_set(r.st, '{fb}', fb || jsonb_build_object('t', t, 'rud', brud, 'fireAt', fire_at, 'pearlAt', pearl_at, 'allyAt', ally_at, 'aiAt', ai_at));
  if (r.st -> 'boss' ->> 'hull')::float8 <= 0 then return game.dt_finish(r, 'win'); end if;
  v_any := false;
  for i in 1..n loop if al[i] then v_any := true; end if; end loop;
  if not v_any then return game.dt_finish(r, 'loss'); end if;
  if game.dt_now() > v_end then return game.dt_finish(r, 'loss'); end if;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Selesai: kondisi kapal, hadiah veteran, langkah quest, Kartu Hasil
-- ---------------------------------------------------------------------
create or replace function game.dt_finish(r game.mp_raids, p_result text) returns game.mp_raids
language plpgsql as $$
declare m game.mp_raid_members; sh jsonb; frac float8; cond numeric; best_pub text; best_sc float8 := -1; sc float8; st jsonb;
  v_rows jsonb := '[]'::jsonb; v_fleet jsonb := '[]'::jsonb; v_n int; v_day int := game.game_day(); v_paid boolean; v_card jsonb;
  d jsonb; v_hist jsonb; v_petrik text := r.st ->> 'petrik'; v_dur bigint;
begin
  r.status := 'done'; r.result := p_result; r.ended := game.dt_now(); r.phase := coalesce(r.phase, 'plan');
  v_dur := r.ended - coalesce(r.started, r.created);
  select count(*) into v_n from game.mp_raid_members where raid_id = r.id;
  -- Tangan Pertama
  for m in select * from game.mp_raid_members where raid_id = r.id order by joined_ms loop
    st := coalesce(r.stats -> m.pub, '{}'::jsonb);
    sc := coalesce((st ->> 'hull')::float8, 0) + coalesce((st ->> 'ally')::float8, 0) + coalesce((st ->> 'board')::float8, 0)
        + coalesce((st ->> 'shield')::float8, 0) * 1.5 + coalesce((st ->> 'boards')::float8, 0) * 25;
    if sc > best_sc then best_sc := sc; best_pub := m.pub; end if;
    v_fleet := v_fleet || jsonb_build_array(jsonb_build_object('n', m.n, 'pub', m.pub,
      'ship', coalesce(m.fighter ->> 'shipName', ''), 'visual', coalesce(m.fighter -> 's', 'null'::jsonb)));
  end loop;
  for m in select * from game.mp_raid_members where raid_id = r.id order by joined_ms loop
    sh := r.st -> 'ships' -> m.pub;
    st := coalesce(r.stats -> m.pub, '{}'::jsonb);
    -- kapal lecet, tidak tenggelam: kondisi turun sebanding lambung yang hilang
    if sh is not null then
      frac := greatest(0, least(1, (sh ->> 'hull')::float8 / greatest(1, (sh ->> 'hull0')::float8)));
      select condition into cond from game.ships where player_id = m.player_id;
      update game.ships set condition = greatest(5, round(coalesce(cond, 100) * (0.35 + 0.65 * frac)))
       where player_id = m.player_id and condition > greatest(5, round(coalesce(cond, 100) * (0.35 + 0.65 * frac)));
    end if;
    v_paid := false;
    if p_result = 'win' and m.state <> 'fled' then
      if m.vet then
        d := game.dt_data(m.player_id);
        if (d ->> 'vetDay')::int is distinct from v_day then
          update game.players set gold = gold + game.dt_vet_reward() where player_id = m.player_id;
          v_paid := true;
          perform game.dt_set(m.player_id, 5, jsonb_build_object('vetDay', v_day));
        end if;
        perform game.dt_set(m.player_id, 5, jsonb_build_object('vetWins', coalesce((game.dt_data(m.player_id) ->> 'vetWins')::int, 0) + 1));
        perform game.log(m.player_id, 'Serbuan Bersama: Sayap Patah tenggelam sekali lagi. Tangan Penolong' || case when v_paid then ' (+' || game.dt_vet_reward() || ' gold).' else ' (hadiah hari ini sudah diterima).' end);
      else
        perform game.dt_set(m.player_id, 3, jsonb_build_object('raidWon', r.id, 'petrik', v_petrik = m.pub, 'fleet', v_fleet,
          'firstHand', case when best_pub = m.pub then 1 else 0 end, 'fullFleet', v_n >= 4, 'duo', v_n = 2));
        perform game.log(m.player_id, 'Serbuan Bersama: Sayap Patah kandas di karang telapak tangan. Teluk Dua Tangan menunggu tanganmu.');
      end if;
    elsif m.state = 'fled' then
      perform game.log(m.player_id, 'Kau mundur dari Teluk Dua Tangan. Kapalmu kembali ke Kota Sowtour.');
    else
      perform game.log(m.player_id, 'Serbuan Bersama gagal. Sayap Patah memanggil sisa rantainya dan mundur ke balik batu. Armada bubar di Kota Sowtour.');
    end if;
    if not m.vet then
      perform game.dt_set(m.player_id, 1, jsonb_build_object('tries', coalesce((game.dt_data(m.player_id) ->> 'tries')::int, 0) + 1));
    end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('pub', m.pub, 'n', m.n, 'vet', m.vet, 'state', m.state,
      'hull', round(coalesce((st ->> 'hull')::float8, 0) + coalesce((st ->> 'ally')::float8, 0) + coalesce((st ->> 'board')::float8, 0)),
      'shield', round(coalesce((st ->> 'shield')::float8, 0)), 'cry', coalesce((st ->> 'cry')::numeric::int, 0),
      'boards', coalesce((st ->> 'boards')::numeric::int, 0), 'taken', round(coalesce((st ->> 'taken')::float8, 0)),
      'endHull', round(coalesce((sh ->> 'hull')::float8, 0)), 'hull0', round(coalesce((sh ->> 'hull0')::float8, 0)),
      'paid', case when v_paid then game.dt_vet_reward() else 0 end, 'ship', coalesce(m.fighter ->> 'shipName', ''),
      'tier', m.fighter -> 'tier', 'a', m.fighter -> 'a', 'f', coalesce(m.fighter -> 'f', 'null'::jsonb)));
  end loop;
  v_card := jsonb_build_object('id', r.id, 'result', p_result, 'ships', v_n, 'rounds', r.round, 'durMs', v_dur,
    'first', case when p_result = 'win' then best_pub end, 'petrik', v_petrik, 'rows', v_rows, 'at', r.ended, 'day', v_day,
    'boss', round((r.st -> 'boss' ->> 'hull')::numeric), 'bossMax', round((r.st -> 'boss' ->> 'max')::numeric));
  r.card := v_card;
  -- Riwayat Serbuan di jurnal (5 terakhir)
  for m in select * from game.mp_raid_members where raid_id = r.id loop
    v_hist := coalesce(game.dt_data(m.player_id) -> 'history', '[]'::jsonb) || jsonb_build_array(v_card);
    while jsonb_array_length(v_hist) > 5 loop v_hist := v_hist - 0; end loop;
    update game.player_quests set data = data || jsonb_build_object('history', v_hist) where player_id = m.player_id and quest_id = 'duatangan';
    perform game.mp_rt('player:' || m.pub, 'raid', jsonb_build_object('raidId', r.id, 'status', 'done', 'result', p_result));
  end loop;
  delete from game.mp_raid_rt where raid_id = r.id;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Simpan & tick
-- ---------------------------------------------------------------------
create or replace function game.dt_save(r game.mp_raids) returns void
language plpgsql as $$
begin
  update game.mp_raids set status = r.status, leader = r.leader, depart_at = r.depart_at, started = r.started, ended = r.ended,
    st = r.st, ord = r.ord, ev = r.ev, phase = r.phase, round = r.round, round_ts = r.round_ts, final_ts = r.final_ts,
    result = r.result, stats = r.stats, log = r.log, card = r.card
   where id = r.id;
end $$;

create or replace function game.dt_notify(r game.mp_raids, p_kind text) returns void
language plpgsql as $$
declare m record;
begin
  for m in select pub from game.mp_raid_members where raid_id = r.id and state = 'in' loop
    perform game.mp_rt('player:' || m.pub, 'raid', jsonb_build_object('raidId', r.id, 'status', r.status, 'round', r.round, 'kind', p_kind));
  end loop;
end $$;

-- kembalikan setoran Perbekalan Armada (keluar / bubar sebelum Angkat Sauh)
create or replace function game.dt_refund(p_raid text, p_pid uuid) returns void
language plpgsql as $$
declare m game.mp_raid_members;
begin
  select * into m from game.mp_raid_members where raid_id = p_raid and player_id = p_pid;
  if not found or m.supply is null then return; end if;
  perform game.adjust_inventory(p_pid, 'mesiu', coalesce((m.supply ->> 'mesiu')::int, 0));
  perform game.adjust_inventory(p_pid, 'beras', coalesce((m.supply ->> 'beras')::int, 0));
  update game.mp_raid_members set supply = null, ready = false where raid_id = p_raid and player_id = p_pid;
end $$;

-- keluar dari lobi (pembuka pindah ke kapten berikutnya; kosong = armada batal)
create or replace function game.dt_lobby_leave(r game.mp_raids, p_pid uuid) returns game.mp_raids
language plpgsql as $$
declare v_next uuid;
begin
  perform game.dt_refund(r.id, p_pid);
  delete from game.mp_raid_members where raid_id = r.id and player_id = p_pid;
  r.depart_at := null;
  if r.leader = p_pid then
    select player_id into v_next from game.mp_raid_members where raid_id = r.id order by joined_ms limit 1;
    r.leader := v_next;
  end if;
  if not exists (select 1 from game.mp_raid_members where raid_id = r.id) then r.status := 'cancelled'; r.ended := game.dt_now(); end if;
  return r;
end $$;

-- Angkat Sauh
create or replace function game.dt_depart(r game.mp_raids) returns game.mp_raids
language plpgsql as $$
declare m game.mp_raid_members; f jsonb; bk jsonb; s jsonb; ships jsonb := '{}'::jsonb; ord jsonb := '[]'::jsonb; i int := 0; n int;
  sx float8 := game.dt_k('stone_x'); x0 float8; v_now bigint := game.dt_now();
begin
  -- yang belum siap ditinggal di dermaga
  for m in select * from game.mp_raid_members where raid_id = r.id and not ready loop
    perform game.dt_refund(r.id, m.player_id);
    delete from game.mp_raid_members where raid_id = r.id and player_id = m.player_id;
  end loop;
  select count(*) into n from game.mp_raid_members where raid_id = r.id;
  if n < 2 then raise exception 'Butuh minimal dua kapten yang siap.'; end if;
  if not exists (select 1 from game.mp_raid_members where raid_id = r.id and not vet) then
    raise exception 'Armada butuh setidaknya satu kapten yang belum pernah melihat akhirnya.';
  end if;
  for m in select * from game.mp_raid_members where raid_id = r.id order by joined_ms loop
    i := i + 1;
    begin f := game.mp_fighter(m.player_id); exception when others then f := m.fighter; end;
    bk := game.dt_bekal(m.player_id);
    x0 := sx - (n - 1) * 110 + (i - 1) * 220;
    s := game.lb_ship0(f, x0, 1290, 0) || jsonb_build_object('pub', m.pub, 'n', m.n, 'vet', m.vet, 'hull0', (game.lb_power(f) ->> 'hull0')::float8,
      'hook', bk ->> 'hook', 'hookMul', bk -> 'hookMul', 'lane', bk -> 'lane', 'beads', bk -> 'beads', 'hasiolan', bk -> 'hasiolan',
      'immune', bk -> 'immune', 'cry', bk -> 'cry', 'cryHas', bk -> 'cry', 'allies', bk -> 'allies',
      'alive', true, 'fled', false, 'on', true, 'shipName', coalesce(f ->> 'shipName', ''), 'tier', f -> 'tier');
    ships := ships || jsonb_build_object(m.pub, s);
    ord := ord || to_jsonb(m.pub);
    update game.mp_raid_members set fighter = f, seen_ms = greatest(seen_ms, v_now), supply = case when vet then null else supply end
     where raid_id = r.id and player_id = m.player_id;
    if not m.vet and not coalesce((game.dt_data(m.player_id) ->> 'euisSupply')::boolean, false) then
      perform game.dt_set(m.player_id, 1, '{"euisSupply": true}'::jsonb);
    end if;
  end loop;
  r.st := jsonb_build_object('w', random() * 2 * pi() - pi(), 'ships', ships, 'order', ord,
    'boss', jsonb_build_object('x', sx, 'y', 330, 'h', pi() / 2, 'v', 18, 'hull', game.dt_k('boss_hull'), 'max', game.dt_k('boss_hull'),
      'shield', game.dt_k('boss_shield'), 'shMax', game.dt_k('boss_shield'), 'phase', 1, 'stun', false),
    'pearl', jsonb_build_object('x', sx + 560, 'y', 750, 'h', pi(), 'v', 22));
  r.status := 'active'; r.phase := 'plan'; r.round := 1; r.started := v_now; r.depart_at := null;
  r.round_ts := v_now + game.dt_k('start_ms')::bigint; r.ord := '{}'::jsonb; r.stats := '{}'::jsonb; r.ev := null;
  return r;
end $$;

create or replace function game.dt_tick(r game.mp_raids) returns game.mp_raids
language plpgsql as $$
declare t bigint := game.dt_now(); m game.mp_raid_members; n int; v_base bigint; i int; v_on jsonb; v_all boolean; pb text; o game.mp_presence;
begin
  if r.status = 'lobby' then
    for m in select * from game.mp_raid_members where raid_id = r.id loop
      select * into o from game.mp_presence where player_id = m.player_id;
      if (not m.ready and t - m.joined_ms > game.dt_k('ready_ms')) or not game.mp_online(o)
         or game.current_city(m.player_id) is distinct from 'sowtour' or game.in_transit(m.player_id) then
        r := game.dt_lobby_leave(r, m.player_id);
        exit when r.status <> 'lobby';
      end if;
    end loop;
    if r.status <> 'lobby' then return r; end if;
    select count(*), bool_and(ready) into n, v_all from game.mp_raid_members where raid_id = r.id;
    if n >= 4 and v_all then
      if r.depart_at is null then r.depart_at := t + game.dt_k('auto_ms')::bigint;
      elsif t >= r.depart_at then
        begin r := game.dt_depart(r); exception when others then r.depart_at := null; end;
      end if;
    else
      r.depart_at := null;
    end if;
    return r;
  end if;
  if r.status <> 'active' then return r; end if;
  -- semua kapten hilang lama = gagal
  if (select max(seen_ms) from game.mp_raid_members where raid_id = r.id and state = 'in') < t - game.dt_k('abandon_ms') then
    return game.dt_finish(r, 'loss');
  end if;
  if r.phase = 'final' then return game.dt_final_tick(r, t); end if;
  for i in 1..40 loop
    exit when r.status <> 'active' or r.phase <> 'plan' or t <= r.round_ts + game.dt_k('plan_ms');
    v_base := r.round_ts + game.dt_k('plan_ms')::bigint;
    r := game.dt_mark_online(r);
    r := game.dt_resolve(r, v_base);
  end loop;
  return r;
end $$;

-- tandai kapal putus koneksi (kapal diam)
create or replace function game.dt_mark_online(r game.mp_raids) returns game.mp_raids
language plpgsql as $$
declare m game.mp_raid_members; t bigint := game.dt_now();
begin
  for m in select * from game.mp_raid_members where raid_id = r.id loop
    if r.st -> 'ships' -> m.pub is not null then
      r.st := jsonb_set(r.st, array['ships', m.pub, 'on'], to_jsonb(t - m.seen_ms <= game.dt_k('off_ms')));
    end if;
  end loop;
  return r;
end $$;

-- semua kapten online yang masih bertempur sudah mengunci perintah?
create or replace function game.dt_all_locked(r game.mp_raids) returns boolean
language plpgsql stable as $$
declare m game.mp_raid_members; t bigint := game.dt_now();
begin
  for m in select * from game.mp_raid_members where raid_id = r.id and state = 'in' loop
    if t - m.seen_ms <= game.dt_k('off_ms') and coalesce((r.st -> 'ships' -> m.pub ->> 'alive')::boolean, false)
       and r.ord -> m.pub is null then return false; end if;
  end loop;
  return true;
end $$;

-- ---------------------------------------------------------------------
-- Tampilan
-- ---------------------------------------------------------------------
create or replace function game.dt_member_json(m game.mp_raid_members, r game.mp_raids) returns jsonb
language plpgsql stable as $$
declare bk jsonb := game.dt_bekal(m.player_id); o game.mp_presence; f jsonb := m.fighter; cond numeric;
begin
  select * into o from game.mp_presence where player_id = m.player_id;
  return jsonb_build_object('pub', m.pub, 'n', m.n, 'vet', m.vet, 'ready', m.ready, 'lead', r.leader = m.player_id,
    'state', m.state, 'joined', m.joined_ms, 'readyBy', m.joined_ms + game.dt_k('ready_ms')::bigint,
    'online', game.mp_online(o) and (r.status <> 'active' or game.dt_now() - m.seen_ms <= game.dt_k('off_ms')),
    'a', f -> 'a', 'f', coalesce(f -> 'f', 'null'::jsonb), 's', coalesce(f -> 's', 'null'::jsonb),
    'ship', coalesce(f ->> 'shipName', ''), 'tier', f -> 'tier', 'cond', f -> 'cond',
    'hook', bk ->> 'hook', 'beads', bk -> 'beads', 'cry', bk -> 'cry', 'allies', bk -> 'allies', 'hasiolan', bk -> 'hasiolan');
end $$;

create or replace function game.dt_view(r game.mp_raids, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare me game.mp_raid_members; mem jsonb; locked jsonb := '{}'::jsonb; pb text; v_st jsonb := r.st; v_ev jsonb := r.ev;
begin
  select * into me from game.mp_raid_members where raid_id = r.id and player_id = p_viewer;
  select coalesce(jsonb_agg(game.dt_member_json(m, r) order by m.joined_ms), '[]'::jsonb) into mem
    from game.mp_raid_members m where m.raid_id = r.id;
  if v_st is not null and v_st -> 'ships' is not null then
    for pb in select key from jsonb_each(v_st -> 'ships') loop
      locked := locked || jsonb_build_object(pb, r.ord -> pb is not null);
      -- kondisi meriam kapten lain dirahasiakan
      if pb is distinct from me.pub then v_st := jsonb_set(v_st, array['ships', pb], (v_st -> 'ships' -> pb) - 'rlL' - 'rlR'); end if;
    end loop;
    v_st := v_st - 'fb';
  end if;
  return jsonb_build_object(
    'id', r.id, 'status', r.status, 'me', me.pub, 'mine', me.player_id is not null, 'vet', me.vet, 'myState', me.state,
    'leader', (select pub from game.mp_raid_members where raid_id = r.id and player_id = r.leader),
    'members', mem, 'departAt', r.depart_at, 't', game.dt_now(),
    'phase', r.phase, 'round', r.round, 'maxRounds', game.dt_k('max_rounds'),
    'planStart', r.round_ts, 'planDeadline', case when r.round_ts is null then null else r.round_ts + game.dt_k('plan_ms')::bigint end,
    'finalTs', r.final_ts, 'finalEnd', case when r.final_ts is null then null else r.final_ts + game.dt_k('final_ms')::bigint end,
    'st', v_st, 'ev', v_ev, 'locked', locked, 'myOrd', case when me.pub is null then null else r.ord -> me.pub end,
    'result', r.result, 'stats', r.stats, 'card', r.card, 'log', r.log,
    'k', jsonb_build_object('planMs', game.dt_k('plan_ms'), 'animMs', game.dt_k('anim_ms'), 'finalMs', game.dt_k('final_ms'),
      'laneR', game.dt_k('lane_r'), 'stoneX', game.dt_k('stone_x'), 'stoneY', game.dt_k('stone_y'), 'stoneR', game.dt_k('stone_r'),
      'bossR', game.dt_k('boss_r'), 'reloadRt', game.dt_k('reload_rt'), 'readyMs', game.dt_k('ready_ms'),
      'mesiu', game.dt_mesiu(), 'beras', game.dt_beras()));
end $$;

create or replace function game.dt_board_json(p_pid uuid) returns jsonb
language plpgsql as $$
declare r game.mp_raids; out jsonb := '[]'::jsonb; v_id text;
begin
  for v_id in select id from game.mp_raids where status = 'lobby' order by created loop
    select * into r from game.mp_raids where id = v_id for update;
    r := game.dt_tick(r); perform game.dt_save(r);
    if r.status = 'lobby' then
      out := out || jsonb_build_array(jsonb_build_object('id', r.id, 'created', r.created, 'departAt', r.depart_at,
        'leader', (select n from game.mp_raid_members where raid_id = r.id and player_id = r.leader),
        'members', (select coalesce(jsonb_agg(game.dt_member_json(m, r) order by m.joined_ms), '[]'::jsonb) from game.mp_raid_members m where m.raid_id = r.id)));
    end if;
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT serbuan: a = [aksi, ...]
--   board | open | join <id> | leave | ready <bool> | depart | view | act <round> <order> | flee | card
--   rt <state> <events> <since>   (Pertarungan Terakhir)
-- ---------------------------------------------------------------------
create or replace function public.api_dtRaid(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'view');
  v_raid text; r game.mp_raids; v_block text; o game.mp_presence; v_n int; v_vets int; m game.mp_raid_members; v_ord jsonb;
  v_round bigint; v_ready boolean; v_mes int; v_ber int; v_now bigint := game.dt_now(); v_msg jsonb; v_mid int; v_cry boolean;
  v_rst jsonb; v_evs jsonb; v_since bigint; e jsonb; sh jsonb; vol jsonb; v_side int; v_key text; v_last bigint; v_dmg float8;
  v_bx float8; v_by float8; v_x float8; v_y float8; v_h float8; v_cnt int := 0; v_sc int; v_out jsonb; v_ev jsonb; v_max bigint;
  v_ships jsonb; pb text; rt game.mp_raid_rt; v_reload float8; q record;
begin
  o := game.mp_presence_sync(v_pid);
  if o.player_id is null then raise exception 'Muat ulang game dulu, Kapten.'; end if;

  if v_act = 'board' then
    return jsonb_build_object('board', game.dt_board_json(v_pid), 'raidId', game.dt_raid_of(v_pid),
      'block', game.dt_join_block(v_pid), 'duatangan', game.dt_state(v_pid));
  end if;

  if v_act in ('open', 'join') then
    perform game.mp_xlock(v_pid);
    v_block := game.dt_join_block(v_pid);
    if v_block is not null then raise exception '%', v_block; end if;
    if game.dt_raid_of(v_pid) is not null then raise exception 'Kau sudah tercatat di sebuah armada.'; end if;
    if v_act = 'open' then
      v_raid := game.mp_uid('r');
      insert into game.mp_raids(id, status, leader, created) values (v_raid, 'lobby', v_pid, v_now);
    else
      v_raid := game.arg(a, 1);
      select * into r from game.mp_raids where id = v_raid for update;
      if not found or r.status <> 'lobby' then raise exception 'Armada itu sudah berangkat atau bubar.'; end if;
      r := game.dt_tick(r); perform game.dt_save(r);
      if r.status <> 'lobby' then raise exception 'Armada itu sudah berangkat atau bubar.'; end if;
      select count(*), count(*) filter (where vet) into v_n, v_vets from game.mp_raid_members where raid_id = v_raid;
      if v_n >= 4 then raise exception 'Armada sudah penuh (4/4).'; end if;
      if game.dt_vet(v_pid) and v_vets >= 2 then raise exception 'Armada ini sudah membawa dua veteran.'; end if;
    end if;
    insert into game.mp_raid_members(raid_id, player_id, pub, n, vet, joined_ms, seen_ms, fighter)
    values (v_raid, v_pid, o.pub, v_me.character_name, game.dt_vet(v_pid), v_now, v_now, game.mp_fighter(v_pid));
    select * into r from game.mp_raids where id = v_raid;
    select count(*) into v_n from game.mp_raid_members where raid_id = v_raid;
    -- pengumuman di kanal dunia
    begin
      insert into game.mp_chat_channels as ch (channel, last_id) values ('g', 1)
      on conflict (channel) do update set last_id = ch.last_id + 1 returning last_id into v_mid;
      v_msg := jsonb_build_object('id', v_mid, 'p', 'sys', 'n', 'Om Baayu', 'a', '', 'ts', game.now_ms(), 'city', 'sowtour', 'raid', v_raid,
        'tx', 'Kapten ' || v_me.character_name || case when v_act = 'open' then ' menabuh genderang' else ' menjawab genderang' end
              || ' di Sowtour (' || v_n || '/4). Teluk Dua Tangan menunggu.');
      insert into game.mp_chat(channel, id, msg) values ('g', v_mid, v_msg);
      delete from game.mp_chat where channel = 'g' and id <= v_mid - 60;
      perform game.mp_rt('chat:global', 'chat', v_msg);
    exception when others then null;
    end;
    -- notifikasi ke kapten yang memenuhi syarat dan online (sekali per armada)
    if v_act = 'open' then
      for q in select p.player_id from game.mp_presence p
                where p.player_id <> v_pid and game.mp_online(p) and game.lt_step(p.player_id) >= 10 and game.dt_step(p.player_id) >= 1 loop
        perform game.mp_push_inbox(q.player_id, jsonb_build_object('type', 'raid_open', 'raidId', v_raid, 'from', v_me.character_name));
      end loop;
    end if;
    perform game.dt_notify(r, 'lobby');
    return jsonb_build_object('raid', game.dt_view(r, v_pid), 'duatangan', game.dt_state(v_pid));
  end if;

  -- id armada eksplisit: view/card [aksi, id], act [act, round, order, id], rt [rt, state, events, since, id]
  v_raid := nullif(game.arg(a, case when v_act in ('view', 'card') then 1 when v_act = 'act' then 3 when v_act = 'rt' then 4 else 99 end), '');
  v_raid := coalesce(v_raid, game.dt_raid_of(v_pid));
  if v_raid is null then
    if v_act in ('view', 'card') then return jsonb_build_object('raid', null, 'duatangan', game.dt_state(v_pid)); end if;
    raise exception 'Kau tidak sedang di armada mana pun.';
  end if;
  select * into r from game.mp_raids where id = v_raid for update;
  if not found then raise exception 'Armada tidak ditemukan.'; end if;
  select * into m from game.mp_raid_members where raid_id = v_raid and player_id = v_pid;
  if not found and v_act <> 'view' then raise exception 'Kau bukan anggota armada itu.'; end if;
  if found then update game.mp_raid_members set seen_ms = v_now where raid_id = v_raid and player_id = v_pid; end if;

  if v_act = 'leave' then
    if r.status = 'lobby' then
      r := game.dt_lobby_leave(r, v_pid);
      perform game.dt_save(r); perform game.dt_notify(r, 'lobby');
      return jsonb_build_object('raid', null, 'left', true, 'duatangan', game.dt_state(v_pid));
    end if;
    v_act := 'flee';
  end if;

  if v_act = 'ready' then
    if r.status <> 'lobby' then raise exception 'Armada sudah berangkat.'; end if;
    v_ready := game.mp_truthy(game.arg_json(a, 1));
    if v_ready and not m.ready then
      if not m.vet then
        v_mes := game.item_qty(v_pid, 'mesiu'); v_ber := game.item_qty(v_pid, 'beras');
        if v_mes < game.dt_mesiu() or v_ber < game.dt_beras() then
          raise exception '%', 'Perbekalan Armada kurang: ' || concat_ws(', ',
            case when v_mes < game.dt_mesiu() then 'kurang ' || (game.dt_mesiu() - v_mes) || ' Mesiu' end,
            case when v_ber < game.dt_beras() then 'kurang ' || (game.dt_beras() - v_ber) || ' Beras' end) || '.';
        end if;
        perform game.adjust_inventory(v_pid, 'mesiu', -game.dt_mesiu());
        perform game.adjust_inventory(v_pid, 'beras', -game.dt_beras());
        update game.mp_raid_members set ready = true, supply = jsonb_build_object('mesiu', game.dt_mesiu(), 'beras', game.dt_beras())
         where raid_id = v_raid and player_id = v_pid;
      else
        update game.mp_raid_members set ready = true where raid_id = v_raid and player_id = v_pid;
      end if;
    elsif not v_ready and m.ready then
      perform game.dt_refund(v_raid, v_pid);
      update game.mp_raid_members set ready = false where raid_id = v_raid and player_id = v_pid;
    end if;
    r := game.dt_tick(r); perform game.dt_save(r); perform game.dt_notify(r, 'lobby');
    return jsonb_build_object('raid', game.dt_view(r, v_pid), 'duatangan', game.dt_state(v_pid));
  end if;

  if v_act = 'depart' then
    if r.status <> 'lobby' then return jsonb_build_object('raid', game.dt_view(r, v_pid)); end if;
    if r.leader <> v_pid then raise exception 'Hanya pembuka armada yang boleh mengangkat sauh.'; end if;
    select count(*) into v_n from game.mp_raid_members where raid_id = v_raid and ready;
    if v_n < 2 then raise exception 'Butuh minimal dua kapten yang siap.'; end if;
    r := game.dt_depart(r);
    perform game.dt_save(r); perform game.dt_notify(r, 'depart');
    for q in select player_id from game.mp_raid_members where raid_id = v_raid and player_id <> v_pid loop
      perform game.mp_push_inbox(q.player_id, jsonb_build_object('type', 'raid_start', 'raidId', v_raid, 'from', v_me.character_name));
    end loop;
    return jsonb_build_object('raid', game.dt_view(r, v_pid), 'duatangan', game.dt_state(v_pid));
  end if;

  if v_act = 'flee' then
    if r.status = 'active' and m.state = 'in' then
      update game.mp_raid_members set state = 'fled' where raid_id = v_raid and player_id = v_pid;
      r.st := jsonb_set(r.st, array['ships', m.pub, 'fled'], 'true'::jsonb);
      r.st := jsonb_set(r.st, array['ships', m.pub, 'alive'], 'false'::jsonb);
      r.ord := r.ord - m.pub;
      if not exists (select 1 from game.mp_raid_members where raid_id = v_raid and state = 'in') then
        r := game.dt_finish(r, 'loss');
      elsif r.phase = 'plan' and game.dt_all_locked(r) then
        r := game.dt_mark_online(r); r := game.dt_resolve(r, greatest(v_now, r.round_ts));
      end if;
      perform game.dt_save(r); perform game.dt_notify(r, 'flee');
    end if;
    return jsonb_build_object('raid', game.dt_view(r, v_pid), 'duatangan', game.dt_state(v_pid));
  end if;

  if v_act = 'act' then
    v_round := game.arg_int(a, 1);
    v_ord := game.lb_order(game.arg_json(a, 2));
    v_cry := game.mp_truthy(game.arg_json(a, 2) -> 'cry');
    r := game.dt_tick(r);
    if r.status = 'active' and r.phase = 'plan' and v_round is not distinct from r.round::bigint and m.state = 'in'
       and coalesce((r.st -> 'ships' -> m.pub ->> 'alive')::boolean, false) and r.ord -> m.pub is null then
      r.ord := r.ord || jsonb_build_object(m.pub, v_ord || jsonb_build_object('cry', v_cry));
      if game.dt_all_locked(r) then
        r := game.dt_mark_online(r);
        r := game.dt_resolve(r, greatest(v_now, r.round_ts));
      end if;
    end if;
    perform game.dt_save(r); perform game.dt_notify(r, 'turn');
    return jsonb_build_object('raid', game.dt_view(r, v_pid));
  end if;

  if v_act = 'rt' then
    if r.status <> 'active' or r.phase <> 'final' then
      r := game.dt_tick(r); perform game.dt_save(r);
      return jsonb_build_object('status', r.status, 'phase', r.phase, 't', v_now, 'result', r.result);
    end if;
    v_rst := game.arg_json(a, 1); v_evs := game.arg_json(a, 2); v_since := coalesce(game.arg_int(a, 3), 0);
    sh := r.st -> 'ships' -> m.pub;
    if m.state = 'in' and coalesce((sh ->> 'alive')::boolean, false) and v_now >= r.final_ts then
      -- posisi kapal sendiri (dilaporkan klien, dijepit ke arena)
      if v_rst is not null and jsonb_typeof(v_rst) = 'object' and length(v_rst::text) < 400 then
        begin
          v_x := greatest(60, least(2140, (v_rst ->> 'x')::float8)); v_y := greatest(60, least(1440, (v_rst ->> 'y')::float8));
          v_h := game.lb_ang(coalesce((v_rst ->> 'h')::float8, 0));
          insert into game.mp_raid_rt(raid_id, pub, st, ts) values (v_raid, m.pub,
            jsonb_build_object('x', v_x, 'y', v_y, 'h', v_h, 'v', coalesce((v_rst ->> 'v')::float8, 0), 'sails', coalesce((v_rst ->> 'sails')::int, 1),
              'ammo', coalesce(v_rst ->> 'ammo', 'ball')), v_now)
          on conflict (raid_id, pub) do update set st = excluded.st, ts = excluded.ts;
        exception when others then null;
        end;
      end if;
      -- bos dimajukan dulu, lalu tembakan kapten dihitung server
      r := game.dt_final_tick(r, v_now);
      if r.status = 'active' and v_evs is not null and jsonb_typeof(v_evs) = 'array' then
        select * into rt from game.mp_raid_rt where raid_id = v_raid and pub = m.pub;
        v_x := (rt.st ->> 'x')::float8; v_y := (rt.st ->> 'y')::float8; v_h := (rt.st ->> 'h')::float8;
        v_bx := (r.st -> 'boss' ->> 'x')::float8; v_by := (r.st -> 'boss' ->> 'y')::float8;
        for e in select value from jsonb_array_elements(v_evs) loop
          v_cnt := v_cnt + 1; exit when v_cnt > 6;
          if e ->> 'k' = 'f' then
            v_side := case when (e ->> 's')::int < 0 then -1 else 1 end;
            v_key := case when v_side < 0 then 'fL' else 'fR' end;
            v_last := coalesce((r.st -> 'ships' -> m.pub ->> v_key)::bigint, 0);
            v_reload := game.dt_k('reload_rt') * coalesce((sh ->> 'rm')::float8, 1);
            if v_now - v_last >= v_reload - 250 then
              vol := game.dt_volley_boss(v_x, v_y, v_h, v_bx, v_by, v_side,
                case when e ->> 'a' in ('ball', 'chain', 'grape') then e ->> 'a' else 'ball' end,
                (r.st -> 'ships' -> m.pub ->> 'crew')::float8, (sh ->> 'dm')::float8, (sh ->> 'hm')::float8);
              v_dmg := (vol ->> 'hull')::float8 + (vol ->> 'sail')::float8 * 0.6 + (vol ->> 'crew')::float8 * 0.4;
              r.st := jsonb_set(r.st, array['ships', m.pub, v_key], to_jsonb(v_now));
              r := game.dt_boss_dmg(r, m.pub, v_dmg, 'hull');
              perform game.dt_rtev(v_raid, jsonb_build_object('k', 'f', 'by', m.pub, 's', v_side, 'a', e ->> 'a', 'hits', vol -> 'hits',
                'dmg', round(v_dmg::numeric, 1), 'fx', round(v_x::numeric), 'fy', round(v_y::numeric), 'fh', round(v_h::numeric, 3),
                'tx', round(v_bx::numeric), 'ty', round(v_by::numeric), 't', v_now), v_now);
            end if;
          elsif e ->> 'k' = 'b' then
            -- Serbu Geladak: lambung harus menyentuh Sayap Patah
            v_last := coalesce((r.st -> 'ships' -> m.pub ->> 'bAt')::bigint, 0);
            v_sc := greatest(0, least(3, coalesce((e ->> 'sc')::int, 0)));
            if v_now - v_last >= 8000 and game.dt_dist(v_x, v_y, v_bx, v_by) < game.dt_k('boss_r') + 45 then
              r.st := jsonb_set(r.st, array['ships', m.pub, 'bAt'], to_jsonb(v_now));
              if v_sc >= 2 then
                v_dmg := (r.st -> 'boss' ->> 'max')::float8 * 0.025 * v_sc * (1 + coalesce((sh ->> 'bm')::float8, 0) / 200);
                r := game.dt_boss_dmg(r, m.pub, v_dmg, 'board');
                r.stats := game.dt_stat_add(r.stats, m.pub, 'boards', 1);
                if r.st ->> 'petrik' is null then r.st := r.st || jsonb_build_object('petrik', m.pub); end if;
              end if;
              perform game.dt_rtev(v_raid, jsonb_build_object('k', 'b', 'by', m.pub, 'sc', v_sc, 'ok', v_sc >= 2,
                'dmg', case when v_sc >= 2 then round(v_dmg::numeric, 1) else 0 end, 'petrik', r.st ->> 'petrik' = m.pub, 't', v_now), v_now);
            end if;
          end if;
        end loop;
        if (r.st -> 'boss' ->> 'hull')::float8 <= 0 then r := game.dt_finish(r, 'win'); end if;
      end if;
    else
      r := game.dt_final_tick(r, v_now);
    end if;
    perform game.dt_save(r);
    if r.status <> 'active' then perform game.dt_notify(r, 'done'); end if;
    -- kapal lain + kejadian
    v_ships := '{}'::jsonb;
    if r.st -> 'ships' is not null then
      for pb, sh in select key, value from jsonb_each(r.st -> 'ships') loop
        select * into rt from game.mp_raid_rt where raid_id = v_raid and pub = pb;
        v_ships := v_ships || jsonb_build_object(pb, coalesce(rt.st, '{}'::jsonb) || jsonb_build_object('ts', rt.ts, 'hull', round((sh ->> 'hull')::numeric, 1),
          'crew', round((sh ->> 'crew')::numeric, 1), 'alive', sh -> 'alive', 'fled', sh -> 'fled', 'on', coalesce(rt.ts, 0) > r.final_ts and v_now - coalesce(rt.ts, 0) < 5000));
      end loop;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('seq', x.seq, 'ev', x.ev) order by x.seq), '[]'::jsonb), max(x.seq) into v_ev, v_max
      from (select * from game.mp_raid_rtev where raid_id = v_raid and seq > v_since order by seq limit 60) x;
    return jsonb_build_object('status', r.status, 'phase', r.phase, 'result', r.result, 't', v_now, 'finalTs', r.final_ts,
      'finalEnd', r.final_ts + game.dt_k('final_ms')::bigint,
      'boss', jsonb_build_object('x', round((r.st -> 'boss' ->> 'x')::numeric, 1), 'y', round((r.st -> 'boss' ->> 'y')::numeric, 1),
        'h', round((r.st -> 'boss' ->> 'h')::numeric, 3), 'v', round((r.st -> 'boss' ->> 'v')::numeric, 2),
        'hull', round((r.st -> 'boss' ->> 'hull')::numeric, 1), 'max', r.st -> 'boss' -> 'max'),
      'ships', v_ships, 'ev', v_ev, 'seq', coalesce(v_max, v_since), 'petrik', r.st ->> 'petrik');
  end if;

  if v_act = 'card' then
    if m.player_id is not null then update game.mp_raid_members set card_seen = true where raid_id = v_raid and player_id = v_pid; end if;
    return jsonb_build_object('raid', game.dt_view(r, v_pid), 'duatangan', game.dt_state(v_pid));
  end if;

  -- view (tick)
  r := game.dt_tick(r);
  perform game.dt_save(r);
  return jsonb_build_object('raid', game.dt_view(r, v_pid), 'duatangan', game.dt_state(v_pid));
end $$;
select game.expose('api_dtraid');

-- ---------------------------------------------------------------------
-- ENDPOINT cerita: a = [aksi, arg]
--   status | prolog | tiba | fate <ikn|dewan> | tutup | credits
-- ---------------------------------------------------------------------
create or replace function game.dt_payload(p_pid uuid) returns jsonb
language sql as $$
  select jsonb_build_object('duatangan', game.dt_state(p_pid), 'unlocks', game.player_unlocks(p_pid),
    'cities', game.cities_json(), 'citiesVersion', game.cities_version())
$$;

create or replace function public.api_duaTangan(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  st jsonb; v_step int; d jsonb; v_slot text; v_eq boolean := false; v_new boolean := false; v_rows int;
begin
  st := game.dt_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('duatangan', st); end if;
  if st is null then raise exception 'Dua jarum kompasmu belum sejajar, Kapten.'; end if;
  v_step := game.dt_step(v_pid);
  d := game.dt_data(v_pid);

  if v_act = 'prolog' then
    if v_step > 0 then return jsonb_build_object('duatangan', st); end if;
    if not coalesce((st ->> 'ready')::boolean, false) then raise exception 'Belum tiga hari, Kapten. coco epan meminta waktu.'; end if;
    if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
    insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'duatangan', 1, '{}')
    on conflict (player_id, quest_id) do update set step = 1, data = '{}', started_at = now(), updated_at = now();
    perform game.log(v_pid, 'Seekor pelikan perak membawa surat Teh Euis. Dua jarum kompasmu sejajar, menunjuk ke satu teluk. Black Pearl menunggu di Kota Sowtour.');
    return jsonb_build_object('duatangan', game.dt_state(v_pid));
  end if;
  if v_step < 1 then raise exception 'Surat Teh Euis belum sampai padamu, Kapten.'; end if;

  if v_act = 'tiba' then
    if game.current_city(v_pid) is distinct from 'sowtour' then raise exception 'Black Pearl berlabuh di Kota Sowtour.'; end if;
    perform game.dt_set(v_pid, 1, '{"arrived": true}'::jsonb);
    return jsonb_build_object('duatangan', game.dt_state(v_pid));
  end if;

  if v_act = 'fate' then
    if v_step <> 3 then raise exception 'Belum waktunya, Kapten.'; end if;
    if v_arg not in ('ikn', 'dewan') then raise exception 'Pilihan tidak dikenal.'; end if;
    perform game.dt_set(v_pid, 4, jsonb_build_object('fate', v_arg));
    perform game.log(v_pid, case when v_arg = 'ikn'
      then 'Jendral Tedsky dipulangkan ke IKN. Ia kembali mengecat patung Garuda, dan kali ini menyelesaikannya.'
      else 'Jendral Tedsky diserahkan kepada Dewan Dua Tangan: membangun ulang Pelabuhan Rantai Lama menjadi pelabuhan bebas.' end);
    return game.dt_payload(v_pid);
  end if;

  if v_act = 'tutup' then
    if v_step >= 5 then return game.dt_payload(v_pid); end if;
    if v_step <> 4 then raise exception 'Belum waktunya, Kapten.'; end if;
    update game.players set gold = gold + game.dt_reward() where player_id = v_pid;
    -- Peta Dua Tangan (+15 Navigation, waktu tempuh pulau Saga 2 -20%)
    insert into game.player_books(player_id, book_id, date_acquired) values (v_pid, 'bk_peta_dua_tangan', game.game_day())
    on conflict do nothing;
    get diagnostics v_rows = row_count;
    v_new := v_rows > 0;
    if v_new then update game.character_stats set navigation = navigation + 15 where player_id = v_pid; end if;
    -- Jabat Tangan Perak-Emas (dipasang bila ada slot artefak kosong)
    if game.item_qty(v_pid, 'art_jabat_tangan') < 1
       and not exists (select 1 from game.ship_equipment where player_id = v_pid and item_id = 'art_jabat_tangan') then
      perform game.item_adjust(v_pid, 'art_jabat_tangan', 1);
      select s.slot into v_slot from unnest(game.artifact_slots()) with ordinality s(slot, ord)
       where not exists (select 1 from game.ship_equipment e where e.player_id = v_pid and e.slot_type = s.slot and coalesce(e.item_id, '') <> '')
       order by s.ord limit 1;
      if v_slot is not null then
        insert into game.ship_equipment(player_id, slot_type, item_id) values (v_pid, v_slot, 'art_jabat_tangan')
        on conflict (player_id, slot_type) do update set item_id = excluded.item_id;
        perform game.item_adjust(v_pid, 'art_jabat_tangan', -1);
        v_eq := true;
      end if;
    end if;
    -- kenang-kenangan dari coco
    if game.item_qty(v_pid, 'qi_topi_coco') < 1 then perform game.item_adjust(v_pid, 'qi_topi_coco', 1); end if;
    if game.item_qty(v_pid, 'qi_kalung_karang') < 1 then perform game.item_adjust(v_pid, 'qi_kalung_karang', 1); end if;
    perform game.dt_set(v_pid, 5, jsonb_build_object('reward', game.dt_reward()));
    update game.player_location set city_id = 'toogood', destination_city_id = null, depart_at = null, arrive_at = null,
        pending_encounter = null, arrived_game_day = game.game_day()
     where player_id = v_pid;
    perform game.log(v_pid, 'Dua tangan berjabat di atas Jantung Jalur. Batu menyala emas dan perak. +' || game.dt_reward() || ' gold, Peta Dua Tangan, Jabat Tangan Perak-Emas. Saga Kedua selesai.');
    return game.dt_payload(v_pid) || jsonb_build_object('paid', game.dt_reward(), 'cityId', 'toogood', 'newBook', v_new, 'equipped', v_eq,
      'newGold', (select gold from game.players where player_id = v_pid), 'ship', game.ship_json(v_pid), 'shipVisual', game.ship_visual(v_pid));
  end if;

  if v_act = 'credits' then
    if v_step < 5 then raise exception 'Belum waktunya, Kapten.'; end if;
    perform game.dt_set(v_pid, 5, '{"credits": true}'::jsonb);
    return jsonb_build_object('duatangan', game.dt_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_duatangan');

-- ---------------------------------------------------------------------
-- Realtime: kanal "raid:<id>" untuk anggota armada aktif
-- ---------------------------------------------------------------------
create or replace function public.mt_rt_raid_ok(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
begin
  if auth.uid() is null or p_topic is null or p_topic not like 'raid:%' then return false; end if;
  return exists (select 1 from game.mp_raids r join game.mp_raid_members m on m.raid_id = r.id
                  where r.id = substr(p_topic, 6) and r.status = 'active' and m.player_id = auth.uid());
end $$;
revoke all on function public.mt_rt_raid_ok(text) from public;
revoke all on function public.mt_rt_raid_ok(text) from anon;
grant execute on function public.mt_rt_raid_ok(text) to authenticated;

create or replace function public.mt_rt_can_read(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
declare v_pub text;
begin
  if auth.uid() is null or p_topic is null then return false; end if;
  if p_topic = 'chat:global' or p_topic like 'chat:city:%' then return true; end if;
  if p_topic like 'player:%' then
    select pub into v_pub from game.mp_presence where player_id = auth.uid();
    return v_pub is not null and p_topic = 'player:' || v_pub;
  end if;
  if p_topic like 'duel:%' then return public.mt_rt_duel_ok(p_topic); end if;
  if p_topic like 'raid:%' then return public.mt_rt_raid_ok(p_topic); end if;
  return false;
end $$;
revoke all on function public.mt_rt_can_read(text) from public;
revoke all on function public.mt_rt_can_read(text) from anon;
grant execute on function public.mt_rt_can_read(text) to authenticated;

do $$
begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists "marantau kirim serbuan" on realtime.messages';
    execute 'create policy "marantau kirim serbuan" on realtime.messages for insert to authenticated '
         || 'with check (realtime.messages.extension = ''broadcast'' and public.mt_rt_raid_ok(realtime.topic()))';
  end if;
exception when others then
  raise warning 'Kebijakan kirim serbuan tidak terpasang (relay RPC tetap jalan): %', sqlerrm;
end $$;
