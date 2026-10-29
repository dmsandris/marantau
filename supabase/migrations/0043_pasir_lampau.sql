-- =====================================================================
-- 0043 — Pasir · Batch 4: Zaman 40 Tahun Lalu (Tide v41)
-- Skenario: claude/SKENARIO-Saga3-Dark.md bagian 4, 6.7, 6.8, 14, 15.
--
--   * Era 'lampau' dipilih di Jam Agung setelah Quest 11 selesai (ps_zaman_opsi). Mendarat di IKN berjaya.
--   * Peta 40 Tahun Lalu = pulau awal Mare Nusantara + Benua Sudyrman (3 pelabuhan, terbuka bila data.sudyrman).
--     Kota Sudyrman bertipe 'Ps*': TIDAK ikut cities_json (rahasia); dikirim lewat key pasir.kotaLampau.
--   * Pasar, bursa, bank, gudang, misi masa lalu tutup ("Koin apa ini? Rajanya saja belum lahir.").
--   * Pelayaran masa lalu: tanpa bajak laut acak, tanpa kerusakan & kejadian, tanpa event kota.
--   * Pustaka Agung IKN (7 buku) + Dok Garuda & Galangan Lembah Seribu Layar (6 Pusaka): bayar emas ditimbang.
--     Tertutup selamanya bila data.lampau_tutup (diset Quest 14).
--   * Efek buku & Pusaka baru: ship_json, voy_max_cond, voy_repair_quote, voy_enc_book.
--
-- ⚠️ SALINAN versi terakhir + tambahan: spot_city (0030), voy_far_city (0028), cities_json (0001), city_flavor (0030),
--    city_open/player_unlocks (0040), eco_require_trade_here/ww_mission_guard/spot_service_guard (0030),
--    voy_roll_encounter/voy_complete_arrival/ship_json/voy_max_cond/voy_enc_book (0003), voy_repair_quote (0028),
--    ps_zaman_opsi (0042). Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Benua Sudyrman (hanya ada di 40 Tahun Lalu)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('sudyrman_pelabuhan', 'Pelabuhan Sudyrman',     'PsPelabuhan', 1.0, '', 38, 104, 30, true),
  ('sudyrman_akademi',   'Akademi Laut Sudyrman',  'PsAkademi',   1.0, '', 58, 112, 31, true),
  ('sudyrman_lembah',    'Lembah Seribu Layar',    'PsLembah',    0.8, '', 74, 102, 32, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;
-- 0018 menyisipkan baris pasar untuk semua kota tiap deploy: Benua Sudyrman tidak punya pasar
delete from game.market where city_id in ('sudyrman_pelabuhan', 'sudyrman_akademi', 'sudyrman_lembah');

create or replace function game.ps_kota_lampau() returns text[]
language sql immutable as $$ select array['sudyrman_pelabuhan', 'sudyrman_akademi', 'sudyrman_lembah'] $$;

-- Titik khusus (tanpa pasar/misi/bank/gudang/bajak laut acak) — salinan 0030 + Sudyrman
create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city in ('titik_buta', 'pusaran', 'rantai_lama', 'teluk_dua_tangan',
  'sudyrman_pelabuhan', 'sudyrman_akademi', 'sudyrman_lembah'), false) $$;
-- Laut jauh (tidak mengubah rentang jarak) — salinan 0028 + Sudyrman
create or replace function game.voy_far_city(p_city text) returns boolean
language sql immutable as $$ select p_city in ('gading_island', 'otoland', 'empeer_depeer', 'freeyork', 'karang_garam', 'rantai_lama', 'sowtour', 'teluk_dua_tangan',
  'sudyrman_pelabuhan', 'sudyrman_akademi', 'sudyrman_lembah') $$;

-- Daftar kota umum: kota 'Ps*' tidak pernah dikirim (salinan 0001 + saring)
create or replace function game.cities_json() returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(game.city_json(c) order by c.sort, c.city_id), '[]'::jsonb) from game.cities c where c.type not like 'Ps%'
$$;

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
    when 'PsPelabuhan' then 'Kota kopi di Benua Sudyrman. Rumah panggung berwarna, kebun kopi di bukit, dan bau kopi sangrai di setiap gang. Tak ada pasar untuk koin asing.'
    when 'PsAkademi' then 'Benteng putih di tebing selatan. Kadet berbaris, lonceng berdentang tiap jam, dan bendera akademi yang tak pernah turun.'
    when 'PsLembah' then 'Teluk dalam di antara tebing hijau. Galangan kayu raksasa, layar-layar baru dijemur seperti cucian, dan pandai kayu yang menerima emas ditimbang.'
    else '' end
$$;

-- Kota masa lalu untuk klien (hanya pemain yang sedang di 40 Tahun Lalu)
create or replace function game.ps_kota_lampau_json(p_pid uuid) returns jsonb
language sql stable as $$
  select case when game.pasir_era(p_pid) = 'lampau' and coalesce((game.ps_sdata(p_pid) ->> 'sudyrman')::boolean, false)
    then coalesce((select jsonb_agg(game.city_json(c) order by c.sort) from game.cities c where c.city_id = any (game.ps_kota_lampau())), '[]'::jsonb)
    else '[]'::jsonb end
$$;

-- ---------------------------------------------------------------------
-- Peta per era (salinan 0040 + lampau)
-- ---------------------------------------------------------------------
create or replace function game.ps_sudyrman_open(p_pid uuid) returns boolean
language sql stable as $$ select game.pasir_era(p_pid) = 'lampau' and coalesce((game.ps_sdata(p_pid) ->> 'sudyrman')::boolean, false) $$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language plpgsql stable as $$
declare v_era text := game.pasir_era(p_pid);
begin
  if v_era = 'lampau' then
    return coalesce((select not hidden from game.cities where city_id = p_city), false)
        or (p_city = any (game.ps_kota_lampau()) and game.ps_sudyrman_open(p_pid));
  end if;
  if v_era <> 'kini' then
    return coalesce((select not hidden from game.cities where city_id = p_city), false)
        or game.pasir_buka(p_pid) ? p_city;
  end if;
  return coalesce((select not hidden from game.cities where city_id = p_city), false)
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
      or (p_city = 'teluk_dua_tangan' and game.dt_step(p_pid) >= 5);
end $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_era text := game.pasir_era(p_pid);
begin
  if v_era = 'lampau' then
    return case when game.ps_sudyrman_open(p_pid) then to_jsonb(game.ps_kota_lampau()) else '[]'::jsonb end;
  end if;
  if v_era <> 'kini' then
    return coalesce((select jsonb_agg(c.city_id order by c.sort) from game.cities c
      where c.hidden and game.pasir_buka(p_pid) ? c.city_id), '[]'::jsonb);
  end if;
  return (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
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
      || (case when game.dt_step(p_pid) >= 5 then '["teluk_dua_tangan"]'::jsonb else '[]'::jsonb end);
end $$;

-- ---------------------------------------------------------------------
-- Masa lalu menolak koinmu: pasar, misi, bank, gudang (salinan 0030 + era)
-- ---------------------------------------------------------------------
create or replace function game.ps_lalu(p_pid uuid) returns boolean
language sql stable as $$ select game.pasir_era(p_pid) in ('badai', 'lampau', 'pusaran') $$;

create or replace function game.ps_koin_msg() returns text
language sql immutable as $$ select 'Koin apa ini? Rajanya saja belum lahir. Simpan baik-baik, Kapten, nanti dipajang di museum.' $$;

create or replace function game.eco_require_trade_here(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.current_city(p_pid) is distinct from p_city then
    raise exception 'Kamu harus berada di kota ini untuk berdagang.';
  end if;
  if game.in_transit(p_pid) then
    raise exception 'Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.';
  end if;
  if game.ps_lalu(p_pid) then raise exception '%', game.ps_koin_msg(); end if;
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
  if game.ps_lalu(p_pid) then raise exception 'Gubernur zaman ini tidak mengenal benderamu, Kapten. Papan misinya juga tidak.'; end if;
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
  if game.ps_lalu(p_pid) then raise exception '%', game.ps_koin_msg(); end if;
  if game.dt_spot(p_pid, game.current_city(p_pid)) then
    raise exception 'Tak ada gudang, bank, apalagi pedagang di tengah badai ini, Kapten. Hanya ombak, petir, dan baja.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Pelayaran masa lalu (salinan 0003 + era)
-- ---------------------------------------------------------------------
create or replace function game.voy_roll_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare ship jsonb; stats jsonb; v_arch text; outlaw boolean; chance numeric;
  lvl_max int; lvl_min int; lvl int; names text[]; max_hp numeric; max_ammo numeric; boss jsonb;
begin
  boss := game.quest_boss_encounter(p_pid, p_dest);
  if boss is not null then return boss; end if;
  if game.spot_city(p_dest) then return null; end if;
  if game.ps_lalu(p_pid) then return null; end if;   -- Pasir: laut masa lalu tanpa bajak laut acak
  ship := coalesce(game.ship_json(p_pid), '{}'::jsonb);
  stats := coalesce(game.stats_json(p_pid), '{}'::jsonb);
  select archetype into v_arch from game.players where player_id = p_pid;
  outlaw := p_dest = 'toogood' and not coalesce(game.toogood_freed(p_pid), false);

  chance := game.cfg_num('PirateEncounterBaseChance', 12);
  if game.voy_num(ship -> 'Condition') < game.voy_damage_threshold(p_pid) then
    chance := chance + game.cfg_num('PirateEncounterConditionPenalty', 15);
  end if;
  chance := chance - game.voy_stat_bonus(stats -> 'Luck') * 1.5;
  if v_arch = 'navigator' then chance := chance * 0.9; end if;
  chance := game.voy_clamp(chance, 1, 60);
  if outlaw then chance := 100; end if;

  if random() * 100 > chance then return null; end if;

  lvl_max := game.cfg_num('PirateEncounterLevelMax', 5)::int;
  lvl_min := case when outlaw then 2 else 1 end;
  lvl := lvl_min + floor(random() * (lvl_max - lvl_min + 1))::int;
  names := array['a lone raider sloop', 'a Bjorneo corsair brig', 'a black-sailed marauder',
    'a notorious pirate frigate', 'a feared warlord''s flagship'];
  max_hp := game.cfg_num('CombatEnemyBaseHp', 40) + lvl * game.cfg_num('CombatEnemyHpPerLevel', 25);
  max_ammo := game.voy_num(ship -> 'MaxCannonAmmo');
  if max_ammo = 0 then max_ammo := game.cfg_num('CombatBaseAmmo', 3); end if;

  return jsonb_build_object(
    'enemyLevel', lvl,
    'enemyName', case when outlaw then 'TooGood''s own ' else '' end || coalesce(names[least(lvl, 5)], names[1]),
    'rolledAt', game.iso(now()),
    'enemyMaxHp', max_hp,
    'enemyHp', max_hp,
    'maxAmmo', max_ammo,
    'ammoRemaining', max_ammo,
    'randomPirate', true,
    'round', 1);
end $$;

create or replace function game.voy_complete_arrival(p_pid uuid, p_target text, p_combat_msg text) returns jsonb
language plpgsql as $$
declare v_name text; ev jsonb; gd bigint; decay numeric; v_lalu boolean := game.ps_lalu(p_pid);
begin
  select name into v_name from game.cities where city_id = p_target;
  if v_name is null then raise exception 'Kota tujuan tidak dikenali: %', p_target; end if;

  if p_combat_msg is not null and p_combat_msg <> '' then
    ev := jsonb_build_object('message', p_combat_msg, 'goldDelta', 0);
  elsif v_lalu then
    ev := jsonb_build_object('type', 'calm', 'message', 'Laut empat puluh tahun lalu tenang dan asing. Bintang-bintangnya sedikit bergeser.', 'goldDelta', 0);
  else
    ev := game.voy_roll_voyage_event();
  end if;

  update game.player_location
     set city_id = p_target, arrived_game_day = game.game_day(), destination_city_id = null,
         depart_at = null, arrive_at = null, pending_encounter = null
   where player_id = p_pid;
  perform game.hr_hook(p_pid, 'arrive', 1, jsonb_build_object('city', p_target));

  gd := coalesce((ev ->> 'goldDelta')::bigint, 0);
  if gd <> 0 then
    update game.players set gold = greatest(0, gold + gd) where player_id = p_pid;
  end if;

  if not v_lalu then
    decay := game.voy_decay_for_voyage(p_pid);
    if decay > 0 then perform game.apply_condition_delta(p_pid, -decay); end if;
    if game.ship_book_effect(p_pid, 'gd_ramuan') and not coalesce(game.heal_city(p_pid, p_target), false) then
      perform game.apply_condition_delta(p_pid, game.voy_max_cond(p_pid) * 0.05);
    end if;
    begin
      perform game.voy_maybe_roll_city_event(p_target);
    exception when others then
      null;
    end;
  end if;

  perform game.log(p_pid, 'Made landfall at ' || v_name || '. ' || (ev ->> 'message'));
  return jsonb_build_object('cityId', p_target, 'event', ev, 'pendingCombat', false);
end $$;

-- ---------------------------------------------------------------------
-- Pustaka Agung IKN: buku (source 'ps_pustaka' & 'ps_cerita' tidak pernah cocok dengan kota mana pun)
-- ---------------------------------------------------------------------
insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_pa_angin',     'Kitab Angin Tujuh Musim',          'VII', '{"Sailing": 15}',     '',            120000, 'ps_pustaka', 701),
  ('bk_pa_bintang',   'Peta Bintang Juru Mudi Garuda',    'VII', '{"Navigation": 10}',  'pa_bintang',  150000, 'ps_pustaka', 702),
  ('bk_pa_risalah',   'Risalah Saudagar Menara',          'VII', '{"Trading": 10}',     '',            140000, 'ps_pustaka', 703),
  ('bk_pa_meriam',    'Hikayat Meriam Perunggu IKN',      'VII', '{"Combat": 15}',      '',            150000, 'ps_pustaka', 704),
  ('bk_pa_insinyur',  'Catatan Insinyur Dok Garuda',      'VII', '',                    'pa_insinyur', 130000, 'ps_pustaka', 705),
  ('bk_pa_ikan',      'Ensiklopedia Ikan Zaman Gemilang', 'VII', '{"Luck": 6}',         'pa_ikan',     100000, 'ps_pustaka', 706),
  ('bk_pa_kramat',    'Tata Krama Pelabuhan Sudyrman',    'VII', '{"Negotiation": 10}', '',            120000, 'ps_pustaka', 707),
  ('bk_ps_kadet',     'Buku Pegangan Kadet Satnislaus',   'VII', '{"Combat": 10, "Navigation": 5}', '', 0,  'ps_cerita', 711),
  ('bk_ps_surat',     'Surat-Surat Franzi',               'VII', '{"Luck": 5}',         '',            0,      'ps_cerita', 712),
  ('bk_ps_almanak',   'Almanak Lampu IKN',                'VII', '',                    'pa_almanak',  0,      'ps_cerita', 713)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  special_effect = excluded.special_effect, price = excluded.price, source = excluded.source, sort = excluded.sort;

create or replace function game.ps_book_desc(p_book text) returns text
language sql immutable as $$
  select case p_book
    when 'bk_pa_angin' then '+15 Sailing.'
    when 'bk_pa_bintang' then '+10 Navigation. Waktu tempuh -5% (batas tercepat tetap).'
    when 'bk_pa_risalah' then '+10 Trading.'
    when 'bk_pa_meriam' then '+15 Combat.'
    when 'bk_pa_insinyur' then 'Biaya reparasi kapal -10%.'
    when 'bk_pa_ikan' then '+6 Luck: ikan langka sedikit lebih sering menyambar.'
    when 'bk_pa_kramat' then '+10 Negotiation.'
    when 'bk_ps_kadet' then '+10 Combat, +5 Navigation.'
    when 'bk_ps_surat' then '+5 Luck. Bisa dibaca ulang.'
    when 'bk_ps_almanak' then 'Pelayaran malam -10% waktu tempuh.'
    else '' end
$$;

-- Beri buku + terapkan stat_effects (sama dengan api_buyBook)
create or replace function game.ps_book_grant(p_pid uuid, p_book text) returns boolean
language plpgsql as $$
declare b game.book_catalog; eff jsonb; r record; d int;
begin
  select * into b from game.book_catalog where book_id = p_book;
  if not found then raise exception 'Buku tidak dikenali.'; end if;
  if exists (select 1 from game.player_books where player_id = p_pid and book_id = p_book) then return false; end if;
  begin eff := nullif(b.stat_effects, '')::jsonb; exception when others then eff := null; end;
  if eff is null or jsonb_typeof(eff) <> 'object' then eff := '{}'::jsonb; end if;
  for r in select key, value from jsonb_each(eff) loop
    d := game.eco_round(game.eco_js_num(r.value))::int;
    case r.key
      when 'Trading' then update game.character_stats set trading = trading + d where player_id = p_pid;
      when 'Negotiation' then update game.character_stats set negotiation = negotiation + d where player_id = p_pid;
      when 'Navigation' then update game.character_stats set navigation = navigation + d where player_id = p_pid;
      when 'Sailing' then update game.character_stats set sailing = sailing + d where player_id = p_pid;
      when 'Combat' then update game.character_stats set combat = combat + d where player_id = p_pid;
      when 'Luck' then update game.character_stats set luck = luck + d where player_id = p_pid;
      when 'Knowledge' then update game.character_stats set knowledge = knowledge + d where player_id = p_pid;
      else null;
    end case;
  end loop;
  insert into game.player_books(player_id, book_id, date_acquired) values (p_pid, p_book, game.game_day());
  return true;
end $$;

-- ---------------------------------------------------------------------
-- Pusaka Kapal: katalog dengan harga & tempat jual (salinan 0042 + harga)
-- ---------------------------------------------------------------------
create or replace function game.ps_pusaka_katalog() returns jsonb
language sql immutable as $$
  select '[
    {"id": "jangkar",      "name": "Jangkar Waktu",                   "desc": "Menahan kapal di waktunya. Syarat melompat dari Jam Agung; mutunya menentukan laju turunnya Retak Waktu.", "src": "quest"},
    {"id": "layar_garuda", "name": "Layar Sutra Garuda",              "desc": "+10 kecepatan kapal.", "src": "dok_garuda", "price": 180000},
    {"id": "lunas_ulin",   "name": "Lunas Ulin Purba",                "desc": "+60 kondisi maksimal.", "src": "lembah", "price": 200000},
    {"id": "kemudi_ikn",   "name": "Kemudi Perunggu IKN",             "desc": "Kerusakan dari tembakan musuh -10%.", "src": "dok_garuda", "price": 160000},
    {"id": "meriam_naga",  "name": "Meriam Naga Menara",              "desc": "+12% peluang tembakan kena saat malam.", "src": "dok_garuda", "price": 220000},
    {"id": "haluan_kadet", "name": "Haluan Kadet Sudyrman",           "desc": "+15% kerusakan ke kapal berperisai.", "src": "lembah", "price": 190000},
    {"id": "lambung_garam","name": "Lambung Berlapis Garam Sudyrman", "desc": "Kebal satu tarikan arus pusaran per pertempuran.", "src": "lembah", "price": 170000}
  ]'::jsonb
$$;

create or replace function game.ps_toko_kota(p_src text) returns text
language sql immutable as $$ select case p_src when 'dok_garuda' then 'ikn' when 'lembah' then 'sudyrman_lembah' when 'pustaka' then 'ikn' end $$;

-- Toko masa lalu buka? (era lampau, merapat di kotanya, belum ditutup selamanya)
create or replace function game.ps_toko_buka(p_pid uuid, p_src text) returns boolean
language sql stable as $$
  select game.pasir_era(p_pid) = 'lampau' and not game.in_transit(p_pid)
     and game.current_city(p_pid) = game.ps_toko_kota(p_src)
     and not coalesce((game.ps_sdata(p_pid) ->> 'lampau_tutup')::boolean, false)
$$;

create or replace function game.ps_toko_json(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'pustaka', case when game.ps_toko_buka(p_pid, 'pustaka') then (
      select coalesce(jsonb_agg(jsonb_build_object('id', c.book_id, 'name', c.name, 'price', c.price, 'desc', game.ps_book_desc(c.book_id),
        'owned', exists (select 1 from game.player_books pb where pb.player_id = p_pid and pb.book_id = c.book_id)) order by c.sort), '[]'::jsonb)
      from game.book_catalog c where c.source = 'ps_pustaka') end,
    'dok_garuda', case when game.ps_toko_buka(p_pid, 'dok_garuda') then (
      select coalesce(jsonb_agg(x || jsonb_build_object('owned', exists (select 1 from game.pv_pusaka p where p.player_id = p_pid and p.pusaka_id = x ->> 'id'))), '[]'::jsonb)
      from jsonb_array_elements(game.ps_pusaka_katalog()) x where x ->> 'src' = 'dok_garuda') end,
    'lembah', case when game.ps_toko_buka(p_pid, 'lembah') then (
      select coalesce(jsonb_agg(x || jsonb_build_object('owned', exists (select 1 from game.pv_pusaka p where p.player_id = p_pid and p.pusaka_id = x ->> 'id'))), '[]'::jsonb)
      from jsonb_array_elements(game.ps_pusaka_katalog()) x where x ->> 'src' = 'lembah') end)
$$;

-- ---------------------------------------------------------------------
-- Efek buku & Pusaka baru
-- ---------------------------------------------------------------------
-- salinan 0003 + Layar Sutra Garuda, Peta Bintang, Almanak Lampu IKN, Meriam Naga Menara
create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.ships; e jsonb; book_bonus int; cargo_bonus numeric; eff_max numeric; cond numeric; tn int; lsum int; leg text; v_night boolean;
begin
  select * into s from game.ships where player_id = p_pid;
  if not found then return null; end if;
  leg := game.ship_legend(p_pid);
  v_night := coalesce(game.fish_is_night(), false);
  book_bonus := case when coalesce(game.has_effect(p_pid, 'cargo_bonus_10'), false) then 10 else 0 end;
  e := game.voy_effective_stats(p_pid);
  cargo_bonus := book_bonus + (e ->> 'cargoBonus')::numeric;
  eff_max := game.voy_max_cond(p_pid);
  cond := least(coalesce(s.condition, eff_max), eff_max);
  lsum := game.ship_level_sum(e -> 'upgrades');
  tn := case when leg = 'pearl' then 5 else greatest(1, least(5, floor(lsum / 4.0)))::int end;
  return jsonb_build_object(
    'ShipName', s.ship_name, 'Tier', case when leg = 'pearl' then s.tier else game.voy_roman(tn) end,
    'TierNum', tn, 'UpgradeLevelSum', lsum, 'Hull', s.hull, 'MaxHull', s.max_hull,
    'Cargo', s.cargo, 'Speed', s.speed + case when coalesce(game.has_effect(p_pid, 'ship_speed_5'), false) then 5 else 0 end
             + case when coalesce(game.has_effect(p_pid, 'regal_engine'), false) then 10 else 0 end
             + case when game.ship_book_effect(p_pid, 'px_layar_garuda') then 10 else 0 end,
    'Combat', s.combat, 'Armor', s.armor, 'Navigation', s.navigation,
    'Condition', cond, 'ConditionDecayPerSail', s.condition_decay_per_sail, 'MaxCondition', s.max_condition,
    'DamageThreshold', s.damage_threshold,
    'CargoBonus', cargo_bonus,
    'EffectiveCargo', s.cargo + cargo_bonus,
    'SpeedMultiplier', e -> 'speedMultiplier',
    'CannonBonusPercent', (e ->> 'cannonBonusPercent')::numeric
      + case when coalesce(game.has_effect(p_pid, 'satnislaus_cannon'), false) then 15 else 0 end
      + case when v_night and game.ship_book_effect(p_pid, 'px_meriam_naga') then 12 else 0 end,
    'MaxCannonAmmo', game.cfg_num('CombatBaseAmmo', 3) + (e ->> 'cannonAmmoBonus')::numeric
      + case when coalesce(game.has_effect(p_pid, 'satnislaus_cannon'), false) then 2 else 0 end,
    'TravelMul', case when coalesce(game.has_effect(p_pid, 'ivankov_nav'), false) then 0.9 else 1 end
      * case when game.ship_book_effect(p_pid, 'oto_kincir') then 0.9 else 1 end
      * case when game.ship_book_effect(p_pid, 'pa_bintang') then 0.95 else 1 end
      * case when v_night and game.ship_book_effect(p_pid, 'pa_almanak') then 0.9 else 1 end,
    'ShipUpgrades', e -> 'upgrades',
    'EffectiveMaxCondition', eff_max,
    'ConditionPct', case when eff_max > 0 then game.voy_round(cond / eff_max * 100) else 100 end,
    'DecayReductionPercent', game.voy_decay_red(p_pid),
    'Legend', leg
  );
end $$;

-- salinan 0003 + Lunas Ulin Purba
create or replace function game.voy_max_cond(p_pid uuid) returns numeric
language plpgsql stable as $$
begin
  return 100 + coalesce((game.voy_effective_stats(p_pid) ->> 'maxConditionBonus')::numeric, 0)
    + case when game.ship_book_effect(p_pid, 'regal_hull') then 50 else 0 end
    + case when game.ship_book_effect(p_pid, 'fy_ukir') then 30 else 0 end
    + case when game.ship_book_effect(p_pid, 'px_lunas_ulin') then 60 else 0 end;
end $$;

-- salinan 0028 + Catatan Insinyur Dok Garuda
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
  if game.ship_book_effect(p_pid, 'gd_ramuan') then rate := rate * 0.75; end if;
  if game.ship_book_effect(p_pid, 'pa_insinyur') then rate := rate * 0.9; end if;
  rate := rate * game.gr_repair_mul(p_city);
  cost := game.voy_round(missing * game.cfg_num('ShipRepairBaseCostPerPoint', 15) * rate);
  return jsonb_build_object('currentCondition', game.voy_round(cur), 'maxCondition', mx,
    'missing', game.voy_round(missing), 'cost', cost, 'blocked', game.lt_repair_block(p_pid, p_city));
end $$;

-- salinan 0003 + Kemudi Perunggu IKN, Haluan Kadet Sudyrman, Lambung Berlapis Garam (sekali per pertempuran)
create or replace function game.voy_enc_book(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql stable as $$
declare e jsonb := p_enc;
begin
  if e is null or jsonb_typeof(e) <> 'object' then return e; end if;
  if not coalesce((e ->> 'bljAmmo')::boolean, false) and game.ship_book_effect(p_pid, 'fy_tungku') then
    e := e || jsonb_build_object('bljAmmo', true,
      'maxAmmo', game.voy_num(e -> 'maxAmmo') + 1, 'ammoRemaining', game.voy_num(e -> 'ammoRemaining') + 1);
  end if;
  if not coalesce((e ->> 'pxKemudi')::boolean, false) and game.ship_book_effect(p_pid, 'px_kemudi_ikn') then
    e := e || jsonb_build_object('pxKemudi', true, 'enemyDmgMul', round(coalesce(nullif(game.voy_num(e -> 'enemyDmgMul'), 0), 1) * 0.9, 4));
  end if;
  if not coalesce((e ->> 'pxHaluan')::boolean, false) and coalesce((e ->> 'shield')::boolean, false) and game.ship_book_effect(p_pid, 'px_haluan_kadet') then
    e := e || jsonb_build_object('pxHaluan', true, 'shieldMul', round(coalesce(nullif(game.voy_num(e -> 'shieldMul'), 0), 0.25) * 1.15, 4));
  end if;
  if not (e ? 'pullImmune') and game.ship_book_effect(p_pid, 'px_lambung_garam') then
    e := e || jsonb_build_object('pullImmune', 1);
  end if;
  return e;
end $$;

-- ---------------------------------------------------------------------
-- Zaman yang bisa dipilih di Jam Agung (salinan 0042 + 40 Tahun Lalu)
-- ---------------------------------------------------------------------
create or replace function game.ps_zaman_opsi(p_pid uuid) returns text[]
language sql stable as $$
  select case
    when game.ps_step(p_pid, 'ps11') = 5 then array['badai']
    when game.ps_step(p_pid, 'ps11') >= 10 and not coalesce((game.ps_sdata(p_pid) ->> 'lampau_tutup')::boolean, false) then array['lampau']
    else array[]::text[] end
$$;

-- kait untuk batch berikutnya (diganti 0044+)
create or replace function game.ps_act_q12(p_pid uuid, p_act text, a jsonb) returns jsonb
language sql as $$ select null::jsonb $$;
create or replace function game.ps_state_q12(p_pid uuid) returns jsonb
language sql as $$ select '{}'::jsonb $$;
create or replace function game.ps_admin_q12(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language sql as $$ select false $$;

-- ---------------------------------------------------------------------
-- Aksi toko masa lalu (sambungan ps_act_ext)
-- ---------------------------------------------------------------------
create or replace function game.ps_act_more(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare v_arg text := game.arg(a, 1); b game.book_catalog; v_cost numeric; k jsonb;
begin
  if p_act = 'beli_buku' then
    if not game.ps_toko_buka(p_pid, 'pustaka') then raise exception 'Pustaka Agung tidak ada di sini.'; end if;
    select * into b from game.book_catalog where book_id = v_arg and source = 'ps_pustaka';
    if not found then raise exception 'Buku itu tidak ada di rak Pustaka Agung.'; end if;
    if exists (select 1 from game.player_books where player_id = p_pid and book_id = v_arg) then raise exception 'Kamu sudah punya buku ini.'; end if;
    v_cost := coalesce(b.price, 0);
    update game.players set gold = gold - v_cost where player_id = p_pid and gold >= v_cost;
    if not found then raise exception 'Emasmu kurang, Kapten. Tuan Wiradarma menimbang % gold.', game.eco_num_text(v_cost); end if;
    perform game.ps_book_grant(p_pid, v_arg);
    perform game.log(p_pid, 'Membeli "' || b.name || '" di Pustaka Agung IKN (' || game.eco_num_text(v_cost) || ' gold, emas ditimbang).');
    return jsonb_build_object('ok', true, 'book', v_arg);
  elsif p_act = 'beli_pusaka' then
    select x into k from jsonb_array_elements(game.ps_pusaka_katalog()) x where x ->> 'id' = v_arg and x ? 'price';
    if k is null then raise exception 'Pusaka itu tidak dijual.'; end if;
    if not game.ps_toko_buka(p_pid, k ->> 'src') then
      raise exception '%', case k ->> 'src' when 'dok_garuda' then 'Pusaka itu hanya ditempa di Dok Garuda, IKN.' else 'Pusaka itu hanya dibuat di Galangan Lembah Seribu Layar.' end;
    end if;
    if exists (select 1 from game.pv_pusaka where player_id = p_pid and pusaka_id = v_arg) then raise exception 'Kau sudah memilikinya.'; end if;
    v_cost := (k ->> 'price')::numeric;
    update game.players set gold = gold - v_cost where player_id = p_pid and gold >= v_cost;
    if not found then raise exception 'Emasmu kurang, Kapten. Harganya % gold.', game.eco_num_text(v_cost); end if;
    insert into game.pv_pusaka(player_id, pusaka_id) values (p_pid, v_arg);
    perform game.log(p_pid, 'Membeli Pusaka ' || (k ->> 'name') || ' (' || game.eco_num_text(v_cost) || ' gold, emas ditimbang).');
    return jsonb_build_object('ok', true, 'pusaka', v_arg);
  end if;
  return game.ps_act_q12(p_pid, p_act, a);
end $$;

create or replace function game.ps_state_more(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('kotaLampau', game.ps_kota_lampau_json(p_pid), 'toko', game.ps_toko_json(p_pid),
    'sudyrman', game.ps_sudyrman_open(p_pid)) || coalesce(game.ps_state_q12(p_pid), '{}'::jsonb)
$$;

-- Alat GM: buka Benua Sudyrman / tutup toko masa lalu (uji)
create or replace function game.ps_admin_more(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language plpgsql as $$
begin
  if p_act = 'sudyrman' then
    perform game.ps_sdata_set(p_pid, jsonb_build_object('sudyrman', coalesce(p_arg, '1') <> '0'));
    return true;
  elsif p_act = 'tutup' then
    perform game.ps_sdata_set(p_pid, jsonb_build_object('lampau_tutup', coalesce(p_arg, '1') <> '0'));
    return true;
  end if;
  return game.ps_admin_q12(p_pid, p_act, p_arg, p_arg2);
end $$;

select game.cfg_set('CitiesVersion', '9-pasir');
