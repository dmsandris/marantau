-- =====================================================================
-- Marantau (Supabase) - 0019 QUEST "WARWERWOR" (Tide v18)
-- Terbuka setelah TooGood merdeka. Seekor pelikan besar membawa surat dari "Pemerintah
-- Moramora" saat pemain berlayar dari TooGood. Pulau Marie Regal - ibu kota mesin di luar
-- zaman - muncul di peta bagi yang menerimanya.
--
-- Langkah (game.player_quests, quest_id = 'warwerwor'):
--   0  belum menerima (data.armed = surat sudah dikirim; data.tornAt = surat disobek)
--   1  Babak 1  surat diterima; pasar terkunci; berlayar ke Marie Regal
--   2  Babak 2  sudah menghadap Ratu Marie; antar 3 Surat Damai ke gubernur
--   3  Babak 3  Surat Damai ternyata akta penyerahan; cari jalan saat malam di Marie Regal
--   4  Babak 4  Marlya asli dibebaskan dari rantai; pasar terbuka; studio dwi dibobol
--   5  Babak 5  menyelidiki pembobolan (tuduh Teh Euis / selidiki)
--   6           kebenaran: Ms. alyfindi; kumpulkan sekutu (3 gubernur + Skitraw)
--   7  Fase 1   Pecah Blokade: 8 drone, lalu kapal komando alyfindi
--   8  Fase 2   Logistik Perang ke TooGood
--   9  Fase 3   Serbuan Marie Regal (Kapal Induk HENING sampai separuh HP)
--  10           Pengkhianatan Hasiolan (duel)
--  11           Serbuan terakhir
--  12           selesai: Marie Regal merdeka
-- Tenggat: WarwerworDeadlineDays hari game (bawaan 60) dari surat diterima sampai Babak 4.
-- Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Pulau Marie Regal (tersembunyi)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden)
values ('marie_regal', 'Marie Regal', 'Regal', 1.5, '', 88, 50, 8, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, map_x = excluded.map_x,
  map_y = excluded.map_y, hidden = true;

insert into game.market(city_id, commodity_id, base_price, current_price, role)
select 'marie_regal', co.id, co.base, co.base, 'neutral' from game.commodities co where co.active
on conflict (city_id, commodity_id) do nothing;

select game.cfg_set('CitiesVersion', '3-marie-regal');

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
    else '' end
$$;

-- Toko teknologi Marie Regal (dijual di "perpustakaan" pulau ini setelah merdeka)
insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_mr_engine',  'Mesin Uap Marlya',          'V', '{}',                                'regal_engine', 60000, 'marie_regal', 50),
  ('bk_mr_hull',    'Lambung Baja Regal',        'V', '{}',                                'regal_hull',   50000, 'marie_regal', 51),
  ('bk_mr_plasma',  'Kitab Meriam Plasma',       'V', '{"Combat":25}',                     '',             30000, 'marie_regal', 52),
  ('bk_mr_quantum', 'Kompas Kuantum',            'V', '{"Navigation":25,"Sailing":15}',    '',             30000, 'marie_regal', 53),
  ('bk_mr_speech',  'Arsip Pidato M.A.R.I.E.',   'V', '{"Negotiation":25,"Knowledge":10}', '',             25000, 'marie_regal', 54)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  special_effect = excluded.special_effect, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Konstanta
-- ---------------------------------------------------------------------
create or replace function game.ww_govs() returns text[]
language sql immutable as $$ select array['sunda_empire', 'joungjava', 'bjorneo', 'skitraw', 'paradiso'] $$;

-- Potongan kertas yang diselipkan warga (dibaca berurutan)
create or replace function game.ww_scraps() returns jsonb
language sql immutable as $$
  select '[["sunda_empire","Toko kami"],["joungjava","tidak tutup."],["bjorneo","Toko kami"],["skitraw","tutup"],["paradiso","untukmu."]]'::jsonb
$$;

create or replace function game.ww_supply_need() returns jsonb
language sql immutable as $$ select '{"mesiu": 40, "arms": 25, "besi": 20}'::jsonb $$;

create or replace function game.ww_drones_need() returns int language sql immutable as $$ select 8 $$;
create or replace function game.ww_induk_max() returns int language sql immutable as $$ select 3000 $$;
create or replace function game.ww_reward() returns bigint language sql immutable as $$ select 250000::bigint $$;

create or replace function game.ww_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'warwerwor'), 0) $$;

create or replace function game.ww_day_ms() returns bigint
language sql stable as $$ select (game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint $$;

create or replace function game.ww_market_closed(p_pid uuid) returns boolean
language sql stable as $$ select game.ww_step(p_pid) between 1 and 3 $$;

-- Kota yang tertipu menandatangani Surat Damai dan belum dipulihkan kepercayaannya
create or replace function game.ww_angry(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select q.step between 3 and 6
      and coalesce(q.data -> 'signed', '[]'::jsonb) ? p_city
      and not coalesce(q.data -> 'restored', '[]'::jsonb) ? p_city
    from game.player_quests q where q.player_id = p_pid and q.quest_id = 'warwerwor'), false)
$$;

create or replace function game.ww_mission_guard(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.ww_angry(p_pid, p_city) then
    raise exception 'Gubernur menolak bekerja sama denganmu. "Kau menjual pulau kami, Kapten."';
  end if;
end $$;

-- Pulau tersembunyi: Paradiso (misi Uda Gala) dan Marie Regal (surat diterima)
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
      or (p_city = 'marie_regal' and game.ww_step(p_pid) >= 1)
$$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$
  select (case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end)
      || (case when game.ww_step(p_pid) >= 1 then '["marie_regal"]'::jsonb else '[]'::jsonb end)
$$;

-- Surat datang pertama kali saat berangkat dari TooGood yang sudah merdeka
create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  if p_origin <> 'toogood' or not coalesce(game.toogood_freed(p_pid), false) then return; end if;
  insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, 'warwerwor', 0, '{"armed": true}')
  on conflict (player_id, quest_id) do update set data = game.player_quests.data || '{"armed": true}', updated_at = now()
    where game.player_quests.step = 0 and not coalesce((game.player_quests.data ->> 'armed')::boolean, false);
end $$;

-- Tenggat lewat (sebelum Babak 4 selesai): surat hangus, pasar terbuka, pelikan datang lagi 24 jam lagi
create or replace function game.ww_expire(p_pid uuid) returns boolean
language plpgsql as $$
declare q game.player_quests;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'warwerwor';
  if not found or q.step not between 1 and 3 then return false; end if;
  if game.now_ms() <= coalesce((q.data ->> 'deadline')::bigint, game.now_ms() + 1) then return false; end if;
  update game.player_quests
     set step = 0,
         data = jsonb_build_object('armed', true, 'tornAt', game.now_ms(),
                  'tears', coalesce((q.data ->> 'tears')::int, 0), 'expired', coalesce((q.data ->> 'expired')::int, 0) + 1),
         updated_at = now()
   where player_id = p_pid and quest_id = 'warwerwor';
  perform game.log(p_pid, 'Surat Pemerintah Moramora hangus dimakan waktu. Pasar kembali buka - dan langit terasa terlalu sunyi.');
  return true;
end $$;

create or replace function game.ww_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_step int; v_now bigint := game.now_ms(); v_cd bigint; v_dl bigint; v_ready boolean; v_exp boolean;
begin
  v_exp := game.ww_expire(p_pid);
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'warwerwor';
  if not found and not coalesce(game.toogood_freed(p_pid), false) then return null; end if;
  v_step := coalesce(q.step, 0);
  v_cd := (game.cfg_num('WarwerworLetterCooldownHours', 24) * 3600000)::bigint;
  v_ready := v_step = 0 and coalesce((q.data ->> 'armed')::boolean, false)
             and v_now >= coalesce((q.data ->> 'tornAt')::bigint, 0) + case when q.data ? 'tornAt' then v_cd else 0 end;
  v_dl := (q.data ->> 'deadline')::bigint;
  return jsonb_build_object(
    'step', v_step,
    'letter', v_ready,
    'letterInMs', case when v_step = 0 and q.data ? 'tornAt' then greatest(0, (q.data ->> 'tornAt')::bigint + v_cd - v_now) end,
    'tears', coalesce((q.data ->> 'tears')::int, 0),
    'expired', coalesce((q.data ->> 'expired')::int, 0),
    'justExpired', v_exp,
    'deadlineMs', case when v_step between 1 and 3 then v_dl end,
    'daysLeft', case when v_step between 1 and 3 and v_dl is not null then round(greatest(0, v_dl - v_now)::numeric / game.ww_day_ms(), 1) end,
    'marketClosed', v_step between 1 and 3,
    'signed', coalesce(q.data -> 'signed', '[]'::jsonb),
    'restored', coalesce(q.data -> 'restored', '[]'::jsonb),
    'skitraw', coalesce((q.data ->> 'skitraw')::boolean, false),
    'accused', coalesce((q.data ->> 'accused')::boolean, false),
    'apologized', coalesce((q.data ->> 'apologized')::boolean, false),
    'scraps', coalesce(q.data -> 'scraps', '[]'::jsonb),
    'drones', coalesce((q.data ->> 'drones')::int, 0),
    'dronesNeed', game.ww_drones_need(),
    'supplies', coalesce(q.data -> 'supplies', '{}'::jsonb),
    'suppliesNeed', game.ww_supply_need(),
    'indukHp', coalesce((q.data ->> 'indukHp')::int, game.ww_induk_max()),
    'indukMax', game.ww_induk_max(),
    'night', game.fish_is_night(),
    'done', v_step >= 12);
end $$;

-- ---------------------------------------------------------------------
-- Pertempuran perang
-- ---------------------------------------------------------------------
create or replace function game.ww_ammo(p_pid uuid) returns numeric
language sql stable as $$
  select coalesce(nullif(game.voy_num(coalesce(game.ship_json(p_pid), '{}'::jsonb) -> 'MaxCannonAmmo'), 0), game.cfg_num('CombatBaseAmmo', 3))
$$;

create or replace function game.ww_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare q game.player_quests; v_step int; ammo numeric; hp numeric; mx numeric := game.ww_induk_max();
  codes text[] := array['M-01 "Mata"', 'M-02 "Telinga"', 'M-03 "Lidah"', 'M-04 "Bisik"', 'M-05 "Senyap"', 'M-06 "Sunyi"', 'M-07 "Bungkam"', 'M-08 "Hening"'];
  n int; allies numeric;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'warwerwor';
  if not found then return null; end if;
  v_step := q.step;
  if v_step not in (7, 9, 10, 11) then return null; end if;
  ammo := game.ww_ammo(p_pid);
  -- sekutu: 3 gubernur yang dipulihkan + Skitraw + Black Pearl
  allies := 8 * jsonb_array_length(coalesce(q.data -> 'restored', '[]'::jsonb)) + 14;

  if v_step = 7 then
    n := coalesce((q.data ->> 'drones')::int, 0);
    if n < game.ww_drones_need() then
      return jsonb_build_object('enemyLevel', 5, 'enemyName', 'Drone Pemburu ' || codes[least(n + 1, 8)],
        'boss', 'drone', 'bossTitle', 'Armada Blokade Moramora', 'ww', true,
        'droneNo', n + 1, 'dronesNeed', game.ww_drones_need(),
        'rolledAt', game.iso(now()), 'enemyMaxHp', 200, 'enemyHp', 200, 'dmgTaken', 0.9,
        'maxAmmo', ammo, 'ammoRemaining', ammo, 'round', 1,
        'noRam', true, 'noRamMsg', 'Drone itu melayang di atas air - tak ada lambung untuk ditabrak.',
        'noTalkMsg', 'Lampu mata drone berkedip merah: "PERMINTAAN DITOLAK. MOHON TIDAK BERBICARA."', 'softSink', true);
    end if;
    return jsonb_build_object('enemyLevel', 7, 'enemyName', 'Ms. alyfindi', 'boss', 'alyfindi',
      'bossTitle', 'Laksamana Armada Blokade - kapal "Kanvas Hitam"', 'ww', true,
      'rolledAt', game.iso(now()), 'enemyMaxHp', 900, 'enemyHp', 900, 'dmgTaken', 0.5,
      'maxAmmo', ammo, 'ammoRemaining', ammo, 'round', 1,
      'noRam', true, 'noTalkMsg', 'alyfindi tertawa: "Bicara? Aku sudah selesai bicara sejak dwi pergi."',
      'softSink', true, 'retreatOk', true, 'retreat', true,
      'retreatMsg', 'Kau memutar haluan menembus kabut drone - alyfindi membiarkanmu pergi. "Lari saja. Kanvasku masih panjang."');
  end if;

  if p_dest <> 'marie_regal' then return null; end if;

  if v_step = 10 then
    return jsonb_build_object('enemyLevel', 7, 'enemyName', 'Hasiolan', 'boss', 'hasiolan',
      'bossTitle', 'Pengkhianat Skitraw - "Rangkiang Merah"', 'ww', true,
      'rolledAt', game.iso(now()), 'enemyMaxHp', 1100, 'enemyHp', 1100, 'dmgTaken', 0.45,
      'maxAmmo', ammo, 'ammoRemaining', ammo, 'round', 1,
      'allyDmg', 22, 'allyNote', 'Kapal Uda Gala',
      'noRam', true, 'noTalkMsg', 'Hasiolan meludah ke laut: "Tak ada lagi yang perlu dibicarakan. Hari ini namaku yang disebut!"',
      'softSink', true, 'retreatOk', true, 'retreat', true,
      'retreatMsg', 'Uda Gala menghadang Rangkiang Merah dengan lambung kapalnya sendiri - kau sempat mundur. "Pergi, Kapten! Ambo tahan dia!"');
  end if;

  hp := least(mx, greatest(1, coalesce((q.data ->> 'indukHp')::numeric, mx)));
  return jsonb_build_object('enemyLevel', 8, 'enemyName', 'Kapal Induk HENING', 'boss', 'induk',
    'bossTitle', case when v_step = 9 then 'Benteng terapung M.A.R.I.E.' else 'Benteng terapung M.A.R.I.E. - perisai runtuh' end,
    'ww', true, 'final', v_step = 11,
    'rolledAt', game.iso(now()), 'enemyMaxHp', mx, 'enemyHp', hp,
    'dmgTaken', case when v_step = 9 then 0.08 else 0.1 end,
    'hpFloor', case when v_step = 9 then mx / 2 else null end,
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'round', 1,
    'allyDmg', case when v_step = 9 then allies + 12 else allies + 8 end,
    'allyNote', case when v_step = 9 then 'Armada lima pulau & Black Pearl' else 'Armada sekutu, Uda Gala & Black Pearl' end,
    'noRam', true, 'noRamMsg', 'Menabrak benteng baja sebesar pulau? Kru-mu menatapmu seolah kau sudah gila.',
    'noTalkMsg', 'Suara Ratu Marie bergema dari seratus pengeras suara: "Diam adalah bentuk kerja sama tertinggi, Kapten."',
    'softSink', true, 'retreatOk', true, 'retreat', true,
    'retreatMsg', 'Black Pearl menembakkan tirai asap - armada mundur teratur, siap kembali setelah diperbaiki.');
end $$;

create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language sql as $$
  select coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest), game.ww_encounter(p_pid, p_dest))
$$;

-- Simpan HP Kapal Induk di akhir setiap pertempuran (mundur / karam)
create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  if coalesce(p_enc ->> 'boss', '') <> 'induk' or p_result = 'won' then return; end if;
  update game.player_quests set data = data || jsonb_build_object('indukHp', greatest(1, round(game.voy_num(p_enc -> 'enemyHp')))), updated_at = now()
   where player_id = p_pid and quest_id = 'warwerwor' and step in (9, 11);
end $$;

create or replace function game.ww_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; v_boss text; q game.player_quests; n int;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  v_boss := coalesce(enc ->> 'boss', '');
  if not coalesce((enc ->> 'ww')::boolean, false) then return null; end if;
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'warwerwor' for update;
  if not found then return null; end if;

  if v_boss = 'drone' and q.step = 7 then
    n := coalesce((q.data ->> 'drones')::int, 0) + 1;
    update game.player_quests set data = data || jsonb_build_object('drones', n), updated_at = now()
     where player_id = p_pid and quest_id = 'warwerwor';
    perform game.log(p_pid, 'Drone blokade Moramora jatuh ke laut (' || n || '/' || game.ww_drones_need() || ').');
    return jsonb_build_object('gold', 600, 'event', 'drone', 'drones', n, 'need', game.ww_drones_need(),
      'message', case when n >= game.ww_drones_need()
        then 'Drone terakhir menukik ke laut dengan desis panjang. Langit mendadak sunyi... lalu di cakrawala, sebuah kapal berlayar kanvas hitam muncul dari kabut.'
        else 'Drone itu kehilangan cahaya matanya dan jatuh ke laut. Kru memunguti suku cadangnya (+600 gold). Masih ada yang lain di luar sana.' end);
  end if;

  if v_boss = 'alyfindi' and q.step = 7 then
    update game.player_quests set step = 8, data = data || '{"supplies": {}}', updated_at = now()
     where player_id = p_pid and quest_id = 'warwerwor';
    perform game.log(p_pid, 'Kapal "Kanvas Hitam" tenggelam. Ms. alyfindi ditangkap - blokade Moramora pecah!');
    return jsonb_build_object('gold', 15000, 'event', 'alyfindi',
      'message', 'Tiang utama Kanvas Hitam patah dan kapal itu miring perlahan. Kru-mu menarik Ms. alyfindi dari air - basah, diam, dan untuk pertama kalinya tidak tersenyum. Blokade Moramora pecah. Di kabinnya kalian menemukan 15.000 gold dan lukisan-lukisan dwi yang belum sempat dikirim.');
  end if;

  if v_boss = 'induk' and q.step = 9 then
    update game.player_quests set step = 10, data = data || jsonb_build_object('indukHp', game.ww_induk_max() / 2), updated_at = now()
     where player_id = p_pid and quest_id = 'warwerwor';
    perform game.log(p_pid, 'Kapal Induk HENING terluka parah - lalu Hasiolan membalikkan meriamnya ke arah aliansi!');
    return jsonb_build_object('gold', 0, 'event', 'betrayal',
      'message', 'Lapisan baja Kapal Induk retak dan api menjalar di geladaknya. Sorak-sorai armada baru saja pecah... ketika meriam-meriam Skitraw berputar perlahan - ke arah kalian.');
  end if;

  if v_boss = 'hasiolan' and q.step = 10 then
    update game.player_quests set step = 11, updated_at = now() where player_id = p_pid and quest_id = 'warwerwor';
    perform game.log(p_pid, 'Rangkiang Merah tenggelam. Hasiolan ditangkap, dan perisai Kapal Induk ikut padam.');
    return jsonb_build_object('gold', 0, 'event', 'hasiolan',
      'message', 'Rangkiang Merah terbelah dua. Uda Gala sendiri yang menarik Hasiolan dari air, tanpa sepatah kata. Jauh di depan, kubah cahaya yang melindungi Kapal Induk berkedip... lalu padam.');
  end if;

  if v_boss = 'induk' and q.step = 11 then
    update game.player_quests set step = 12, done_at = now(), data = data || '{"indukHp": 0}', updated_at = now()
     where player_id = p_pid and quest_id = 'warwerwor';
    perform game.log(p_pid, 'KAPAL INDUK HENING TUMBANG. M.A.R.I.E. dimatikan, Marlya kembali bertakhta - Marie Regal merdeka! Hadiah ' || game.ww_reward() || ' gold.');
    return jsonb_build_object('gold', game.ww_reward(), 'event', 'finale', 'arrive', true,
      'message', 'Inti Kapal Induk meledak dalam cahaya putih yang menyilaukan. Satu per satu, lampu-lampu Marie Regal padam... dan dari kegelapan itu terdengar suara yang selama ini dibungkam: genderang.');
  end if;
  return null;
end $$;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$ select coalesce(game.gala_boss_defeated(p_pid), game.ww_boss_defeated(p_pid)) $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg]
--   status | tear | accept | scrap | audience | peace | marlya | studio [accuse|investigate]
--   kiosk | restore | skitraw | supply | apologize
-- ---------------------------------------------------------------------
create or replace function game.ww_check_war(p_pid uuid) returns boolean
language plpgsql as $$
declare q game.player_quests; v_all boolean;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'warwerwor';
  if q.step <> 6 or not coalesce((q.data ->> 'skitraw')::boolean, false) then return false; end if;
  select bool_and(coalesce(q.data -> 'restored', '[]'::jsonb) ? c) into v_all
    from jsonb_array_elements_text(coalesce(q.data -> 'signed', '[]'::jsonb)) c;
  if not coalesce(v_all, false) then return false; end if;
  update game.player_quests set step = 7, data = data || '{"drones": 0}', updated_at = now()
   where player_id = p_pid and quest_id = 'warwerwor';
  perform game.log(p_pid, 'Genderang ditabuh di TooGood. Armada lima pulau berkumpul - PERANG GENDERANG dimulai!');
  return true;
end $$;

create or replace function public.api_warwerwor(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb; v_list jsonb; v_piece text;
  k text; v_need int; v_have int; v_give int; v_sup jsonb; v_moved jsonb := '{}'::jsonb; v_done boolean; v_war boolean;
begin
  perform game.ww_expire(v_pid);
  if v_act = 'status' then return jsonb_build_object('warwerwor', game.ww_state(v_pid)); end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'warwerwor' for update;
  v_step := coalesce(q.step, 0);
  st := game.ww_state(v_pid);

  -- Surat (boleh dibaca di tengah laut)
  if v_act in ('tear', 'accept') then
    if v_step <> 0 or not coalesce((st ->> 'letter')::boolean, false) then raise exception 'Tidak ada surat untukmu.'; end if;
    if v_act = 'tear' then
      update game.player_quests set data = data || jsonb_build_object('tornAt', game.now_ms(), 'tears', coalesce((q.data ->> 'tears')::int, 0) + 1), updated_at = now()
       where player_id = v_pid and quest_id = 'warwerwor';
      perform game.log(v_pid, 'Menyobek surat Pemerintah Moramora dan membuangnya ke laut. Pelikan itu terbang tanpa suara.');
      return jsonb_build_object('torn', true, 'warwerwor', game.ww_state(v_pid));
    end if;
    update game.player_quests
       set step = 1, started_at = now(), updated_at = now(),
           data = jsonb_build_object('armed', true, 'tears', coalesce((q.data ->> 'tears')::int, 0), 'expired', coalesce((q.data ->> 'expired')::int, 0),
                    'deadline', game.now_ms() + (game.cfg_num('WarwerworDeadlineDays', 60) * game.ww_day_ms())::bigint, 'scraps', '[]'::jsonb)
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Menempelkan cap jempol di segel perak surat Pemerintah Moramora. Sebuah pulau yang tak pernah ada di peta muncul: Marie Regal.');
    return jsonb_build_object('accepted', true, 'warwerwor', game.ww_state(v_pid), 'unlocks', game.player_unlocks(v_pid),
      'cities', game.cities_json(), 'citiesVersion', game.cities_version());
  end if;

  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  -- Babak 1: potongan kertas dari warga yang gelisah
  if v_act = 'scrap' then
    if v_step not between 1 and 3 then raise exception 'Tak ada yang menyelipkan apa pun padamu.'; end if;
    select e ->> 1 into v_piece from jsonb_array_elements(game.ww_scraps()) e where e ->> 0 = v_city;
    if v_piece is null then raise exception 'Warga di sini terlalu takut untuk mendekat.'; end if;
    v_list := coalesce(q.data -> 'scraps', '[]'::jsonb);
    if not v_list ? v_city then
      v_list := v_list || to_jsonb(v_city);
      update game.player_quests set data = data || jsonb_build_object('scraps', v_list), updated_at = now()
       where player_id = v_pid and quest_id = 'warwerwor';
    end if;
    return jsonb_build_object('piece', v_piece, 'warwerwor', game.ww_state(v_pid));
  end if;

  -- Babak 2: menghadap Ratu Marie
  if v_act = 'audience' then
    if v_step <> 1 then raise exception 'Istana Hening tidak menerima tamu saat ini.'; end if;
    if v_city <> 'marie_regal' then raise exception 'Istana Hening hanya ada di Marie Regal.'; end if;
    update game.player_quests set step = 2, data = data || '{"signed": []}', updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Menghadap Ratu Marie di Istana Hening. Menerima tiga Surat Damai bersegel perak.');
    return jsonb_build_object('warwerwor', game.ww_state(v_pid));
  end if;

  -- Babak 3: mengantar Surat Damai
  if v_act = 'peace' then
    if v_step <> 2 then raise exception 'Kamu tidak membawa Surat Damai.'; end if;
    if not (v_city = any (game.ww_govs())) then raise exception 'Tak ada gubernur yang bisa menandatangani di pelabuhan ini.'; end if;
    v_list := coalesce(q.data -> 'signed', '[]'::jsonb);
    if v_list ? v_city then raise exception 'Gubernur di sini sudah menandatangani.'; end if;
    v_list := v_list || to_jsonb(v_city);
    update game.player_quests set data = data || jsonb_build_object('signed', v_list),
        step = case when jsonb_array_length(v_list) >= 3 then 3 else 2 end, updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Gubernur ' || game.city_name(v_city) || ' menandatangani Surat Damai (' || jsonb_array_length(v_list) || '/3).');
    if jsonb_array_length(v_list) >= 3 then
      perform game.log(v_pid, 'Fajar. Drone-drone perak turun di tiga pelabuhan. Surat Damai itu ternyata akta penyerahan pulau.');
    end if;
    return jsonb_build_object('signed', v_city, 'count', jsonb_array_length(v_list), 'betrayed', jsonb_array_length(v_list) >= 3,
      'warwerwor', game.ww_state(v_pid));
  end if;

  -- Babak 4: menyusuri saluran di bawah Marie Regal saat malam
  if v_act = 'marlya' then
    if v_step <> 3 then raise exception 'Pelikan itu tidak menunggumu.'; end if;
    if v_city <> 'marie_regal' then raise exception 'Bukan di sini.'; end if;
    if not game.fish_is_night() then raise exception 'Lampu-lampu kota masih menyala. Robot penjaga berdiri di setiap sudut.'; end if;
    update game.player_quests set step = 4, data = (data - 'deadline') || '{"freedAt": true}', updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Di bawah Marie Regal: Marlya yang asli, dirantai pada mesinnya sendiri. Kontrak Diam dipatahkan - pasar kembali buka.');
    return jsonb_build_object('warwerwor', game.ww_state(v_pid));
  end if;

  -- Babak 5: studio dwi dibobol
  if v_act = 'studio' then
    if v_step <> 4 then raise exception 'Tidak ada yang aneh di sini.'; end if;
    if v_city <> 'toogood' then raise exception 'Studio dwi ada di TooGood.'; end if;
    if v_arg not in ('accuse', 'investigate') then raise exception 'Putuskan dulu, Kapten.'; end if;
    update game.player_quests set step = 5, data = data || jsonb_build_object('accused', v_arg = 'accuse'), updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, case when v_arg = 'accuse'
      then 'Menuduh Teh Euis membobol studio dwi. Ia ditahan di Benteng Kapten, menangis tanpa suara.'
      else 'Menolak menuduh siapa pun. Ada yang ganjil dengan surat "pengakuan" itu.' end);
    return jsonb_build_object('warwerwor', game.ww_state(v_pid));
  end if;

  if v_act = 'kiosk' then
    if v_step <> 5 then raise exception 'Kios itu tutup.'; end if;
    if v_city <> 'toogood' then raise exception 'Bukan di sini.'; end if;
    if not game.fish_is_night() then raise exception 'Siang hari kios peta itu ramai dan tak ada yang ganjil.'; end if;
    update game.player_quests set step = 6, data = data || '{"restored": [], "skitraw": false}', updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Pelikan mesin di jendela kios peta. Ms. alyfindi - dialah yang mencuri lukisan dwi dan memfitnah Teh Euis. Ia kabur ke Marie Regal.');
    return jsonb_build_object('warwerwor', game.ww_state(v_pid));
  end if;

  if v_act = 'apologize' then
    if v_step < 6 or not coalesce((q.data ->> 'accused')::boolean, false) or coalesce((q.data ->> 'apologized')::boolean, false) then
      raise exception 'Tidak ada yang perlu dimaafkan.';
    end if;
    if v_city <> 'toogood' then raise exception 'Teh Euis ada di TooGood.'; end if;
    update game.player_quests set data = data || '{"apologized": true}', updated_at = now() where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Meminta maaf kepada Teh Euis. Dibalas satu cubitan di lengan - dan senyum.');
    return jsonb_build_object('warwerwor', game.ww_state(v_pid));
  end if;

  -- Mengumpulkan sekutu
  if v_act = 'restore' then
    if v_step <> 6 then raise exception 'Belum waktunya.'; end if;
    if not coalesce(q.data -> 'signed', '[]'::jsonb) ? v_city then raise exception 'Gubernur di sini tidak pernah tertipu olehmu.'; end if;
    v_list := coalesce(q.data -> 'restored', '[]'::jsonb);
    if v_list ? v_city then raise exception 'Gubernur di sini sudah berdiri di pihakmu.'; end if;
    v_list := v_list || to_jsonb(v_city);
    update game.player_quests set data = data || jsonb_build_object('restored', v_list), updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Gubernur ' || game.city_name(v_city) || ' membaca Catatan Marlya dan mengirim armadanya ke TooGood.');
    v_war := game.ww_check_war(v_pid);
    return jsonb_build_object('restored', v_city, 'war', v_war, 'warwerwor', game.ww_state(v_pid));
  end if;

  if v_act = 'skitraw' then
    if v_step <> 6 then raise exception 'Belum waktunya.'; end if;
    if v_city <> 'skitraw' then raise exception 'Uda Gala ada di Skitraw.'; end if;
    if coalesce((q.data ->> 'skitraw')::boolean, false) then raise exception 'Armada Skitraw sudah berlayar ke TooGood.'; end if;
    update game.player_quests set data = data || '{"skitraw": true}', updated_at = now() where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Uda Gala dan Hasiolan memimpin armada Skitraw bergabung dengan aliansi.');
    v_war := game.ww_check_war(v_pid);
    return jsonb_build_object('skitraw', true, 'war', v_war, 'warwerwor', game.ww_state(v_pid));
  end if;

  -- Fase 2: logistik perang ke TooGood (boleh dicicil)
  if v_act = 'supply' then
    if v_step <> 8 then raise exception 'Gudang perang belum membutuhkan apa-apa.'; end if;
    if v_city <> 'toogood' then raise exception 'Gudang perang aliansi ada di TooGood.'; end if;
    v_sup := coalesce(q.data -> 'supplies', '{}'::jsonb);
    for k, v_need in select key, value::int from jsonb_each_text(game.ww_supply_need()) loop
      v_have := coalesce((v_sup ->> k)::int, 0);
      select coalesce(sum(qty), 0)::int into v_give from game.inventory where player_id = v_pid and item_id = k;
      v_give := least(v_give, greatest(0, v_need - v_have));
      if v_give > 0 then
        perform game.adjust_inventory(v_pid, k, -v_give);
        v_sup := v_sup || jsonb_build_object(k, v_have + v_give);
        v_moved := v_moved || jsonb_build_object(k, v_give);
      end if;
    end loop;
    if v_moved = '{}'::jsonb then raise exception 'Palkamu tidak membawa Mesiu, Senjata, atau Besi yang masih dibutuhkan.'; end if;
    select bool_and(coalesce((v_sup ->> key)::int, 0) >= value::int) into v_done from jsonb_each_text(game.ww_supply_need());
    update game.player_quests set data = data || jsonb_build_object('supplies', v_sup)
           || case when v_done then jsonb_build_object('indukHp', game.ww_induk_max()) else '{}'::jsonb end,
        step = case when v_done then 9 else 8 end, updated_at = now()
     where player_id = v_pid and quest_id = 'warwerwor';
    perform game.log(v_pid, 'Menyerahkan perbekalan perang ke gudang aliansi di TooGood.' ||
      case when v_done then ' Gudang penuh - armada siap menyerbu Marie Regal!' else '' end);
    return jsonb_build_object('moved', v_moved, 'ready', v_done, 'warwerwor', game.ww_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_warwerwor');

-- Pasar Marie Regal baru buka setelah pulau itu merdeka
create or replace function game.eco_require_trade_here(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.current_city(p_pid) is distinct from p_city then
    raise exception 'Kamu harus berada di kota ini untuk berdagang.';
  end if;
  if game.in_transit(p_pid) then
    raise exception 'Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.';
  end if;
  if game.ww_market_closed(p_pid) then
    raise exception 'Toko tutup. Kami diminta diam oleh Pemerintah.';
  end if;
  if p_city = 'marie_regal' and game.ww_step(p_pid) < 12 then
    raise exception 'AKSES DITOLAK. Seluruh toko Marie Regal tertutup bagi tamu.';
  end if;
end $$;
