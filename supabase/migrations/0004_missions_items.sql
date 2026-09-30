-- =====================================================================
-- Marantau (Supabase) - 0004 MODUL C: MISSIONS (v8) + ITEMS + TREASURE
-- ---------------------------------------------------------------------
-- Port dari legacy-gs/MissionService.gs (Tide v8: Titipan/Pesanan,
-- muatan misi terkunci), ItemService.gs (katalog + artifact 2 slot +
-- toko peta + jual item), TreasureService.gs + TreasureData.gs.
--
-- Menimpa kontrak 0001b milik modul C:
--   game.mission_load(pid), game.mission_state(pid),
--   game.has_effect(pid, effect), game.treasure_drop(pid, enemy_level)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
-- PlayerMissions (kolom v8: type, source_city_id, loaded_qty)
create table if not exists game.player_missions (
  id                 bigserial primary key,
  player_id          uuid not null references game.players(player_id) on delete cascade,
  mission_id         text not null default gen_random_uuid()::text,
  status             text not null default 'active',     -- active | completed | abandoned
  accepted_at        int,                                 -- hari-game saat diterima (sama dengan .gs)
  city_id            text,                                -- kota pemberi misi (origin)
  commodity_id       text not null,
  qty                int not null default 0,
  deliver_to_city_id text,
  reward             bigint not null default 0,
  type               text not null default 'legacy',     -- courier | procure | legacy ('' dianggap legacy)
  source_city_id     text not null default '',
  loaded_qty         int not null default 0,              -- muatan misi TERKUNCI (bukan di game.inventory)
  created_at         timestamptz not null default now()
);
create index if not exists player_missions_player_idx on game.player_missions (player_id, status);
-- Satu misi aktif per pemain (pengganti LockService + cek getActiveMissionRow_)
create unique index if not exists player_missions_one_active_uq
  on game.player_missions (player_id) where status = 'active';

-- ItemCatalog (kolom Price/Source dari migrateFase5TreasureShop)
create table if not exists game.item_catalog (
  item_id text primary key,
  name    text not null,
  type    text not null,                 -- treasure_map | artifact
  effects jsonb not null default '{}'::jsonb,
  value   int not null default 0,
  price   int,                           -- null/0 = tidak dijual di toko (loot-only)
  source  text,                          -- cityId atau 'any'
  sort    int not null default 0
);

-- ShipEquipment: 2 slot artifact ('artifact', 'artifact_2')
create table if not exists game.ship_equipment (
  player_id uuid not null references game.players(player_id) on delete cascade,
  slot_type text not null,
  item_id   text not null,
  primary key (player_id, slot_type)
);

-- TreasureData.gs -> tabel
create table if not exists game.treasure_sites (
  id                    text primary key,
  name                  text not null,
  city_id               text not null,
  difficulty            int not null default 1,
  requires_book_keyword text not null default '',
  clue_hint             text not null default '',
  clue_full             text not null default '',
  sort                  int not null default 0
);

alter table game.player_missions enable row level security;
alter table game.item_catalog    enable row level security;
alter table game.ship_equipment  enable row level security;
alter table game.treasure_sites  enable row level security;

-- ---------------------------------------------------------------------
-- Seed: ItemCatalog (migrateFase5Exploration + migrateFase5TreasureShop)
-- ---------------------------------------------------------------------
insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('tm_sunda_reef',      'Peta Karang Terlantar',  'treasure_map', '{"siteId":"site_sunda_reef","requiresBookKeyword":"treasure_decoder_1"}',      80, 250, 'joungjava',    1),
  ('tm_joungjava_grove', 'Peta Rimba Sunyi',       'treasure_map', '{"siteId":"site_joungjava_grove","requiresBookKeyword":"treasure_decoder_1"}', 80, 250, 'skitraw',      2),
  ('tm_skitraw_docks',   'Peta Dermaga Tua',       'treasure_map', '{"siteId":"site_skitraw_docks","requiresBookKeyword":"treasure_decoder_1"}',  120, 450, 'bjorneo',      3),
  ('tm_bjorneo_cliffs',  'Peta Tebing Berkabut',   'treasure_map', '{"siteId":"site_bjorneo_cliffs","requiresBookKeyword":"treasure_decoder_1"}', 120, 450, 'toogood',      4),
  ('tm_toogood_den',     'Peta Sarang Lama',       'treasure_map', '{"siteId":"site_toogood_den","requiresBookKeyword":"treasure_decoder_2"}',    220, 800, 'ikn',          5),
  ('tm_ikn_ruins',       'Peta Reruntuhan Istana', 'treasure_map', '{"siteId":"site_ikn_ruins","requiresBookKeyword":"treasure_decoder_2"}',      220, 800, 'sunda_empire', 6),
  ('art_current_charts', 'Peta Arus Purba',        'artifact',     '{"SpecialEffect":"cargo_bonus_10"}',        1200, null, null, 7),
  ('art_smugglers_ring', 'Cincin Penyelundup',     'artifact',     '{"SpecialEffect":"black_market_discount"}', 1500, null, null, 8),
  ('art_sunken_crown',   'Mahkota Karam',          'artifact',     '{}',                                        3000, null, null, 9)
on conflict (item_id) do nothing;

insert into game.treasure_sites(id, name, city_id, difficulty, requires_book_keyword, clue_hint, clue_full, sort) values
  ('site_sunda_reef', 'Karang Terlantar', 'sunda_empire', 1, 'treasure_decoder_1',
   'Sesuatu terkubur di karang dangkal tak jauh dari pelabuhan utama Sunda Empire.',
   'Peti besi karatan terkubur sedepa di bawah pasir karang, ditandai bangkai kapal nelayan yang setengah tenggelam sejak dua musim lalu.', 1),
  ('site_joungjava_grove', 'Rimba Sunyi Joungjava', 'joungjava', 1, 'treasure_decoder_1',
   'Petani setempat bicara soal harta yang dikubur di tepi ladang, dekat pohon tua.',
   'Digali di bawah pohon beringin tunggal di tepi ladang paling utara - akarnya sengaja dibiarkan tumbuh mengelilingi peti supaya tidak dicuri.', 2),
  ('site_skitraw_docks', 'Dermaga Tua Skitraw', 'skitraw', 2, 'treasure_decoder_1',
   'Rumor pedagang: ada brankas tersembunyi di bawah dermaga tua yang sudah tidak dipakai.',
   'Brankas besi tersembunyi di bawah papan dermaga ketiga dari ujung, diikat rantai ke tiang penyangga supaya tidak hanyut saat pasang.', 3),
  ('site_bjorneo_cliffs', 'Tebing Berkabut Bjorneo', 'bjorneo', 2, 'treasure_decoder_1',
   'Penduduk lokal menghindari satu gua di tebing - katanya menyimpan sesuatu milik pelaut lama.',
   'Gua di sisi barat tebing, tersembunyi di balik air terjun kecil - peti disegel di ceruk batu paling dalam.', 4),
  ('site_toogood_den', 'Sarang Lama TooGood', 'toogood', 3, 'treasure_decoder_2',
   'Bekas markas bajak laut yang ditinggalkan - konon penuh jebakan bagi yang tidak siap.',
   'Ruang bawah tanah bekas markas bajak laut, di balik pintu palsu ruang senjata lama - dijaga jebakan mekanis tua yang butuh kehati-hatian ekstra.', 5),
  ('site_ikn_ruins', 'Reruntuhan IKN', 'ikn', 3, 'treasure_decoder_2',
   'Di antara reruntuhan ibu kota yang tumbang, ada ruang bawah tanah istana yang belum sepenuhnya dijarah.',
   'Ruang perbendaharaan istana lama, tersembunyi di bawah reruntuhan balai kota - sebagian sudah dijarah, tapi bilik terdalam masih tersegel.', 6)
on conflict (id) do nothing;

insert into game.config(key, value) values
  ('TreasureMapDropChance', '15'),
  ('TreasureDigBaseGold', '350')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Helper umum modul C
-- ---------------------------------------------------------------------
-- Math.round JS untuk angka positif
create or replace function game.js_round(x double precision) returns bigint
language sql immutable as $$ select floor(x + 0.5)::bigint $$;

-- cityName_ di .gs: nama kota, id bila tidak dikenal, '' bila kosong
create or replace function game.mission_city_name(p_city text) returns text
language sql stable as $$
  select case when coalesce(p_city, '') = '' then '' else game.city_name(p_city) end
$$;

create or replace function game.mission_type_label(p_type text) returns text
language sql immutable as $$
  select case p_type when 'courier' then 'Titipan' when 'procure' then 'Pesanan' when 'legacy' then 'Kiriman' else 'Misi' end
$$;

-- getActiveMissionRow_
create or replace function game.mission_active(p_pid uuid) returns game.player_missions
language sql stable as $$
  select * from game.player_missions where player_id = p_pid and status = 'active' order by id limit 1
$$;

create or replace function game.mission_norm_type(p_type text) returns text
language sql immutable as $$ select coalesce(nullif(p_type, ''), 'legacy') $$;

-- toClientState_
create or replace function game.mission_client_state(m game.player_missions) returns jsonb
language plpgsql stable as $$
declare v_type text;
begin
  if m.id is null then return jsonb_build_object('hasActive', false); end if;
  v_type := game.mission_norm_type(m.type);
  return jsonb_build_object(
    'hasActive', true,
    'type', v_type,
    'typeLabel', game.mission_type_label(v_type),
    'commodityId', m.commodity_id,
    'commodityName', game.commodity_name(m.commodity_id),
    'qty', m.qty,
    'loadedQty', case when v_type = 'legacy' then 0 else m.loaded_qty end,
    'originCityId', m.city_id,
    'originCityName', game.mission_city_name(m.city_id),
    'sourceCityId', coalesce(m.source_city_id, ''),
    'sourceCityName', case when coalesce(m.source_city_id, '') <> '' then game.mission_city_name(m.source_city_id) else '' end,
    'deliverToCityId', m.deliver_to_city_id,
    'deliverToCityName', game.mission_city_name(m.deliver_to_city_id),
    'reward', m.reward);
end $$;

-- ---------------------------------------------------------------------
-- KONTRAK: mission_state / mission_load
-- ---------------------------------------------------------------------
create or replace function game.mission_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
begin
  return game.mission_client_state(game.mission_active(p_pid));
end $$;

create or replace function game.mission_load(p_pid uuid) returns int
language plpgsql stable as $$
declare m game.player_missions;
begin
  m := game.mission_active(p_pid);
  if m.id is null or game.mission_norm_type(m.type) = 'legacy' then return 0; end if;
  return coalesce(m.loaded_qty, 0);
end $$;

-- freeHold_
create or replace function game.mission_free_hold(p_pid uuid) returns int
language plpgsql stable as $$
begin
  return coalesce(game.effective_cargo(p_pid), 0) - coalesce(game.cargo_total(p_pid), 0);
end $$;

-- ---------------------------------------------------------------------
-- Papan misi (deterministik per kota + hari-game)
-- ---------------------------------------------------------------------
-- MISSION_OFFER_TIERS + tiersForCity_
create or replace function game.mission_tiers(p_city text) returns jsonb
language sql immutable as $$
  select '[
    {"minReputation":0, "label":"Muatan Standar",        "qtyRange":[3,8],   "rewardPerUnitRange":[15,25]},
    {"minReputation":0, "label":"Muatan Standar",        "qtyRange":[3,8],   "rewardPerUnitRange":[15,25]},
    {"minReputation":5, "label":"Kontrak Terpercaya",    "qtyRange":[6,12],  "rewardPerUnitRange":[25,38]},
    {"minReputation":15,"label":"Kontrak Elite Gubernur","qtyRange":[10,18], "rewardPerUnitRange":[38,55]}
  ]'::jsonb
  || case when p_city = 'ikn' then '[
    {"minReputation":0, "label":"Muatan Standar", "qtyRange":[3,8], "rewardPerUnitRange":[15,25]},
    {"minReputation":0, "label":"Muatan Standar", "qtyRange":[3,8], "rewardPerUnitRange":[15,25]}
  ]'::jsonb else '[]'::jsonb end
$$;

create or replace function game.mission_reward_multiplier(p_city text) returns double precision
language plpgsql stable as $$
declare v_base double precision := case when p_city = 'ikn' then 0.6 else 1 end;
begin
  return v_base * (1 + coalesce(game.event_reward_pct(p_city), 0)::double precision / 100);
end $$;

create or replace function game.mission_board(p_pid uuid, p_city text) returns jsonb
language plpgsql stable as $$
declare
  v_rep    int := coalesce(game.reputation_for(p_pid, p_city), 0);
  v_day    int := game.game_day();
  v_tiers  jsonb := game.mission_tiers(p_city);
  v_mult   double precision := game.mission_reward_multiplier(p_city);
  v_comms  text[];
  v_others text[];
  v_sources text[];
  v_tier   jsonb;
  v_idx    int;
  v_seed   text;
  v_n      int;
  v_type   text;
  v_qlo int; v_qhi int; v_rlo int; v_rhi int;
  v_qty    int;
  v_rpu    int;
  v_comm   text;
  v_src    text;
  v_dest   text;
  v_base   double precision;
  v_offer  jsonb;
  v_offers jsonb := '[]'::jsonb;
begin
  select coalesce(array_agg(id order by sort, id), '{}') into v_comms from game.commodities;
  select coalesce(array_agg(city_id order by sort, city_id), '{}') into v_others
    from game.cities where city_id is distinct from p_city and not hidden;

  for v_idx in 0 .. jsonb_array_length(v_tiers) - 1 loop
    v_tier := v_tiers -> v_idx;
    v_seed := coalesce(p_city, '') || '|' || v_day || '|' || v_idx || '|v8';
    v_n := 0;
    v_qlo := (v_tier #>> '{qtyRange,0}')::int; v_qhi := (v_tier #>> '{qtyRange,1}')::int;
    v_rlo := (v_tier #>> '{rewardPerUnitRange,0}')::int; v_rhi := (v_tier #>> '{rewardPerUnitRange,1}')::int;

    -- typeForSlot_: slot 0 Titipan, slot 1 Pesanan, sisanya acak
    if v_idx = 0 then v_type := 'courier';
    elsif v_idx = 1 then v_type := 'procure';
    else
      v_n := v_n + 1;
      v_type := case when game.seeded(v_seed, v_n) < 0.5 then 'courier' else 'procure' end;
    end if;
    v_n := v_n + 1; v_qty := v_qlo + floor(game.seeded(v_seed, v_n) * (v_qhi - v_qlo + 1))::int;
    v_n := v_n + 1; v_rpu := v_rlo + floor(game.seeded(v_seed, v_n) * (v_rhi - v_rlo + 1))::int;
    v_n := v_n + 1;
    v_comm := case when cardinality(v_comms) > 0
      then v_comms[1 + floor(game.seeded(v_seed, v_n) * cardinality(v_comms))::int] end;

    v_offer := jsonb_build_object(
      'offerIndex', v_idx,
      'type', v_type,
      'typeLabel', game.mission_type_label(v_type),
      'label', v_tier ->> 'label',
      'minReputation', (v_tier ->> 'minReputation')::int,
      'unlocked', v_rep >= (v_tier ->> 'minReputation')::int,
      'qty', v_qty);

    if v_type = 'procure' then
      -- Pulau sumber: kota LAIN yang benar-benar menjual barang ini
      select coalesce(array_agg(o.c order by o.ord), '{}') into v_sources
        from unnest(v_others) with ordinality o(c, ord)
       where exists (select 1 from game.market m where m.city_id = o.c and m.commodity_id = v_comm and m.base_price > 0);
      if cardinality(v_sources) = 0 then
        select k.c into v_comm from unnest(v_comms) with ordinality k(c, ord)
         where exists (select 1 from game.market m where m.city_id = any (v_others) and m.commodity_id = k.c and m.base_price > 0)
         order by k.ord limit 1;
        select coalesce(array_agg(o.c order by o.ord), '{}') into v_sources
          from unnest(v_others) with ordinality o(c, ord)
         where exists (select 1 from game.market m where m.city_id = o.c and m.commodity_id = v_comm and m.base_price > 0);
      end if;
      v_n := v_n + 1;
      v_src := case when cardinality(v_sources) > 0
        then v_sources[1 + floor(game.seeded(v_seed, v_n) * cardinality(v_sources))::int] end;
      v_base := coalesce((select base_price from game.market where city_id = v_src and commodity_id = v_comm), 100);
      v_offer := v_offer || jsonb_build_object(
        'commodityId', v_comm,
        'commodityName', game.commodity_name(v_comm),
        'sourceCityId', v_src,
        'sourceCityName', case when v_src is null then '???' else game.city_name(v_src) end,
        'deliverToCityId', p_city,
        'deliverToCityName', game.mission_city_name(p_city),
        -- Imbalan = ganti modal (harga dasar di pulau sumber + 10%) + upah jerih payah
        'reward', greatest(1, game.js_round(v_qty * (v_base * 1.1 + v_rpu * 1.4 * v_mult))),
        'estCost', game.js_round(v_qty * v_base));
    else
      v_n := v_n + 1;
      v_dest := case when cardinality(v_others) > 0
        then v_others[1 + floor(game.seeded(v_seed, v_n) * cardinality(v_others))::int] end;
      select coalesce(max(base_price), 0) into v_base from game.market where commodity_id = v_comm and base_price > 0;
      if v_base = 0 then v_base := 150; end if;
      v_offer := v_offer || jsonb_build_object(
        'commodityId', v_comm,
        'commodityName', game.commodity_name(v_comm),
        'sourceCityId', null,
        'deliverToCityId', v_dest,
        'deliverToCityName', case when v_dest is null then '???' else game.city_name(v_dest) end,
        -- Upah antar: tarif tier + sedikit dari nilai barang yang dipercayakan
        'reward', greatest(1, game.js_round(v_qty * (v_rpu * 1.5 + v_base * 0.12) * v_mult)));
    end if;
    v_offers := v_offers || jsonb_build_array(v_offer);
  end loop;

  return jsonb_build_object('offers', v_offers, 'reputationHere', v_rep, 'gameDay', v_day);
end $$;

-- ---------------------------------------------------------------------
-- API: Misi
-- ---------------------------------------------------------------------
create or replace function public.api_getMissionState(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  return game.mission_state(v_me.player_id);
end $$;
select game.expose('api_getmissionstate');

create or replace function public.api_getMissionBoard(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  return game.mission_board(v_me.player_id, game.arg(a, 0));
end $$;
select game.expose('api_getmissionboard');

create or replace function public.api_acceptMission(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_city  text := game.arg(a, 0);
  v_idx   bigint := game.arg_int(a, 1);
  v_me    game.players := game.me(true);
  v_pid   uuid := v_me.player_id;
  v_board jsonb;
  v_offer jsonb;
  v_free  int;
  v_qty   int;
  v_loaded int := 0;
  v_type  text;
begin
  if (game.mission_active(v_pid)).id is not null then
    raise exception 'Kamu masih punya misi aktif - selesaikan atau batalkan dulu.';
  end if;
  if game.current_city(v_pid) is distinct from v_city then
    raise exception 'Kamu harus berada di kota ini untuk menerima misi.';
  end if;
  if game.in_transit(v_pid) then
    raise exception 'Kamu sedang berlayar.';
  end if;

  v_board := game.mission_board(v_pid, v_city);
  if v_idx is not null and v_idx >= 0 then v_offer := v_board -> 'offers' -> v_idx::int; end if;
  if v_offer is null or jsonb_typeof(v_offer) <> 'object' then
    raise exception 'Penawaran misi tidak ditemukan - papan mungkin sudah berganti hari.';
  end if;
  if not (v_offer ->> 'unlocked')::boolean then
    raise exception 'Reputasimu di kota ini belum cukup (butuh Standing %, kamu punya %).',
      v_offer ->> 'minReputation', v_board ->> 'reputationHere';
  end if;
  if coalesce(v_offer ->> 'deliverToCityId', '') = '' then
    raise exception 'Tidak ada kota tujuan untuk misi saat ini.';
  end if;
  v_type := v_offer ->> 'type';
  v_qty := (v_offer ->> 'qty')::int;
  if v_type = 'procure' and coalesce(v_offer ->> 'sourceCityId', '') = '' then
    raise exception 'Tidak ada pulau yang menjual barang pesanan ini.';
  end if;

  if v_type = 'courier' then
    v_free := game.mission_free_hold(v_pid);
    if v_free < v_qty then
      raise exception 'Palka tidak cukup untuk barang titipan (butuh % ruang, sisa %). Jual atau titip barang dulu.',
        v_qty, greatest(0, v_free);
    end if;
    v_loaded := v_qty; -- barang titipan langsung dimuat
  end if;

  insert into game.player_missions(player_id, status, accepted_at, city_id, commodity_id, qty, deliver_to_city_id,
                                   reward, type, source_city_id, loaded_qty)
  values (v_pid, 'active', game.game_day(), v_city, v_offer ->> 'commodityId', v_qty, v_offer ->> 'deliverToCityId',
          (v_offer ->> 'reward')::bigint, v_type, coalesce(v_offer ->> 'sourceCityId', ''), v_loaded);

  if v_type = 'courier' then
    perform game.log(v_pid, 'Menerima titipan ' || v_qty || ' ' || (v_offer ->> 'commodityName') || ' untuk diantar ke ' ||
      (v_offer ->> 'deliverToCityName') || ' (imbalan ' || (v_offer ->> 'reward') || ' gold). Barang titipan sudah dimuat ke kapal.');
  else
    perform game.log(v_pid, 'Menerima pesanan ' || v_qty || ' ' || (v_offer ->> 'commodityName') || ' - beli di ' ||
      (v_offer ->> 'sourceCityName') || ', antar ke ' || (v_offer ->> 'deliverToCityName') || ' (imbalan ' || (v_offer ->> 'reward') || ' gold).');
  end if;
  return game.mission_state(v_pid);
end $$;
select game.expose('api_acceptmission');

create or replace function public.api_buyForMission(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  m      game.player_missions;
  v_need int;
  v_unit bigint;
  v_total bigint;
  v_free int;
begin
  select * into m from game.player_missions where player_id = v_pid and status = 'active' order by id limit 1 for update;
  if not found then raise exception 'Tidak ada misi aktif.'; end if;
  if game.mission_norm_type(m.type) <> 'procure' then raise exception 'Misi ini bukan pesanan barang.'; end if;
  v_need := m.qty - m.loaded_qty;
  if v_need <= 0 then
    raise exception 'Barang pesanan sudah lengkap. Antar ke %.', game.mission_city_name(m.deliver_to_city_id);
  end if;
  if game.in_transit(v_pid) then raise exception 'Kamu sedang berlayar.'; end if;
  if game.current_city(v_pid) is distinct from m.source_city_id then
    raise exception 'Barang pesanan ini hanya boleh dibeli di %.', game.mission_city_name(m.source_city_id);
  end if;
  v_unit := coalesce(game.quote_buy(v_pid, m.source_city_id, m.commodity_id), 0);
  if v_unit <= 0 then raise exception 'Barang ini sedang tidak dijual di kota ini.'; end if;
  v_total := v_unit * v_need;
  if v_me.gold < v_total then
    raise exception 'Gold tidak cukup. Butuh % untuk % unit, kamu punya %.', v_total, v_need, v_me.gold;
  end if;
  v_free := game.mission_free_hold(v_pid);
  if v_free < v_need then
    raise exception 'Palka tidak cukup (butuh % ruang, sisa %).', v_need, greatest(0, v_free);
  end if;

  update game.players set gold = gold - v_total where player_id = v_pid;
  update game.player_missions set loaded_qty = m.qty where id = m.id;
  perform game.log(v_pid, 'Membeli ' || v_need || ' ' || game.commodity_name(m.commodity_id) || ' pesanan di ' ||
    game.mission_city_name(m.source_city_id) || ' seharga ' || v_total || ' gold (muatan misi, terkunci).');
  return jsonb_build_object('bought', v_need, 'unitPrice', v_unit, 'totalCost', v_total,
    'newGold', v_me.gold - v_total, 'mission', game.mission_state(v_pid));
end $$;
select game.expose('api_buyformission');

create or replace function public.api_abandonMission(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  m      game.player_missions;
  v_type text;
  v_note text := '';
begin
  select * into m from game.player_missions where player_id = v_pid and status = 'active' order by id limit 1 for update;
  if not found then raise exception 'Tidak ada misi aktif untuk dibatalkan.'; end if;
  v_type := game.mission_norm_type(m.type);

  if v_type = 'procure' and m.loaded_qty > 0 then
    -- Barang pesanan sudah dibayar sendiri - kembali jadi barang dagang biasa
    perform game.adjust_inventory(v_pid, m.commodity_id, m.loaded_qty);
    v_note := ' Barang yang sudah dibeli (' || m.loaded_qty || ') kembali ke palka biasa.';
  elsif v_type = 'courier' then
    v_note := ' Barang titipan dikembalikan ke pemiliknya.';
  end if;

  update game.player_missions
     set status = 'abandoned',
         loaded_qty = case when v_type <> 'legacy' then 0 else loaded_qty end
   where id = m.id;
  perform game.log(v_pid, 'Membatalkan misi.' || v_note);
  return jsonb_build_object('hasActive', false, 'note', btrim(v_note));
end $$;
select game.expose('api_abandonmission');

create or replace function public.api_completeMission(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me    game.players := game.me(true);
  v_pid   uuid := v_me.player_id;
  m       game.player_missions;
  v_type  text;
  v_cname text;
  v_owned int;
  v_rep   jsonb;
begin
  select * into m from game.player_missions where player_id = v_pid and status = 'active' order by id limit 1 for update;
  if not found then raise exception 'Tidak ada misi aktif.'; end if;
  v_type := game.mission_norm_type(m.type);

  if game.in_transit(v_pid) then
    raise exception 'Kamu masih berlayar - belum bisa menyerahkan misi.';
  end if;
  if game.current_city(v_pid) is distinct from m.deliver_to_city_id then
    raise exception 'Kamu belum sampai di %.', game.mission_city_name(m.deliver_to_city_id);
  end if;
  v_cname := game.commodity_name(m.commodity_id);

  if v_type = 'legacy' then
    -- Misi lama (sebelum v8): pemain membawa barangnya sendiri dari palka
    select coalesce(sum(qty), 0) into v_owned from game.inventory where player_id = v_pid and item_id = m.commodity_id;
    if v_owned < m.qty then
      raise exception 'Cargo tidak cukup - butuh % %.', m.qty, v_cname;
    end if;
    perform game.adjust_inventory(v_pid, m.commodity_id, -m.qty);
  elsif m.loaded_qty < m.qty then
    if v_type = 'procure' then
      raise exception 'Barang pesanan belum dibeli. Beli dulu di %.', game.mission_city_name(m.source_city_id);
    else
      raise exception 'Muatan titipan tidak lengkap.';
    end if;
  end if;

  v_rep := case when jsonb_typeof(v_me.reputation) = 'object' then v_me.reputation else '{}'::jsonb end;
  v_rep := v_rep || jsonb_build_object(m.deliver_to_city_id,
    coalesce(case when jsonb_typeof(v_rep -> m.deliver_to_city_id) = 'number' then (v_rep ->> m.deliver_to_city_id)::numeric end, 0) + 1);
  update game.players set gold = gold + m.reward, reputation = v_rep where player_id = v_pid;

  update game.player_missions
     set status = 'completed',
         loaded_qty = case when v_type <> 'legacy' then 0 else loaded_qty end
   where id = m.id;

  perform game.log(v_pid, 'Misi selesai di ' || game.mission_city_name(m.deliver_to_city_id) || ': ' || m.qty || ' ' || v_cname ||
    ' diserahkan, imbalan ' || m.reward || ' gold.');
  return jsonb_build_object('reward', m.reward, 'cityId', m.deliver_to_city_id, 'type', v_type);
end $$;
select game.expose('api_completemission');

-- ---------------------------------------------------------------------
-- Items: helper
-- ---------------------------------------------------------------------
create or replace function game.item(p_item text) returns game.item_catalog
language sql stable as $$ select * from game.item_catalog where item_id = p_item $$;

create or replace function game.item_qty(p_pid uuid, p_item text) returns int
language sql stable as $$
  select coalesce((select qty from game.inventory where player_id = p_pid and item_id = p_item), 0)
$$;

-- adjustItemQty_ (pesan error khusus item)
create or replace function game.item_adjust(p_pid uuid, p_item text, p_delta int) returns int
language plpgsql as $$
declare q int;
begin
  select qty into q from game.inventory where player_id = p_pid and item_id = p_item for update;
  if not found then
    if p_delta < 0 then raise exception 'Kamu tidak punya item ini.'; end if;
    insert into game.inventory(player_id, item_id, qty) values (p_pid, p_item, p_delta);
    return p_delta;
  end if;
  if q + p_delta < 0 then raise exception 'Jumlah item tidak boleh negatif.'; end if;
  update game.inventory set qty = q + p_delta where player_id = p_pid and item_id = p_item;
  return q + p_delta;
end $$;

create or replace function game.item_special_effect(p_effects jsonb) returns text
language sql immutable as $$
  select case when jsonb_typeof(p_effects) = 'object' then coalesce(p_effects ->> 'SpecialEffect', '') else '' end
$$;

create or replace function game.artifact_slots() returns text[]
language sql immutable as $$ select array['artifact', 'artifact_2'] $$;

-- getPlayerArtifactsView
create or replace function game.artifacts_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_owned jsonb; v_slots jsonb; v_filled int;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'itemId', c.item_id, 'name', c.name, 'value', c.value,
           'specialEffect', game.item_special_effect(c.effects), 'qty', i.qty) order by c.sort, c.item_id), '[]'::jsonb)
    into v_owned
    from game.inventory i join game.item_catalog c on c.item_id = i.item_id
   where i.player_id = p_pid and i.qty > 0 and c.type = 'artifact';

  select coalesce(jsonb_agg(
           case when c.item_id is null then jsonb_build_object('slotKey', s.slot, 'itemId', null)
                else jsonb_build_object('slotKey', s.slot, 'itemId', c.item_id, 'name', c.name,
                                        'specialEffect', game.item_special_effect(c.effects)) end
           order by s.ord), '[]'::jsonb)
    into v_slots
    from unnest(game.artifact_slots()) with ordinality s(slot, ord)
    left join game.ship_equipment e on e.player_id = p_pid and e.slot_type = s.slot
    left join game.item_catalog c on c.item_id = e.item_id;

  select count(*) into v_filled from game.ship_equipment
   where player_id = p_pid and slot_type = any (game.artifact_slots()) and coalesce(item_id, '') <> '';

  return jsonb_build_object('owned', v_owned, 'equippedSlots', v_slots,
    'slotsFull', v_filled >= cardinality(game.artifact_slots()));
end $$;

-- getTreasureMapShop
create or replace function game.treasure_map_shop(p_city text) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('itemId', item_id, 'name', name, 'price', price) order by sort, item_id), '[]'::jsonb)
    from game.item_catalog
   where type = 'treasure_map' and coalesce(price, 0) > 0 and (source = p_city or source = 'any')
$$;

-- ---------------------------------------------------------------------
-- KONTRAK: has_effect (buku ATAU artifact terpasang)
-- ---------------------------------------------------------------------
-- BookService.hasSpecialEffect: tabel buku milik modul A (0002). Dicek lewat
-- to_regclass + SQL dinamis supaya modul ini tetap jalan tanpa modul A.
-- Asumsi skema: game.player_books(player_id, book_id), game.book_catalog(book_id, special_effect).
create or replace function game.book_has_effect(p_pid uuid, p_effect text) returns boolean
language plpgsql stable as $$
declare v boolean := false;
begin
  if coalesce(p_effect, '') = '' then return false; end if;
  if to_regclass('game.player_books') is null or to_regclass('game.book_catalog') is null then return false; end if;
  begin
    execute 'select exists (select 1 from game.player_books pb join game.book_catalog bc on bc.book_id = pb.book_id
              where pb.player_id = $1 and bc.special_effect = $2)'
      into v using p_pid, p_effect;
  exception when others then
    v := false;
  end;
  return coalesce(v, false);
end $$;

-- ItemService.hasEquippedEffect
create or replace function game.artifact_has_effect(p_pid uuid, p_effect text) returns boolean
language sql stable as $$
  select coalesce(p_effect, '') <> '' and exists (
    select 1 from game.ship_equipment e join game.item_catalog c on c.item_id = e.item_id
     where e.player_id = p_pid and e.slot_type = any (game.artifact_slots())
       and game.item_special_effect(c.effects) = p_effect)
$$;

create or replace function game.has_effect(p_pid uuid, p_effect text) returns boolean
language plpgsql stable as $$
begin
  return game.book_has_effect(p_pid, p_effect) or game.artifact_has_effect(p_pid, p_effect);
end $$;

-- ---------------------------------------------------------------------
-- Treasure: helper
-- ---------------------------------------------------------------------
create or replace function game.treasure_site(p_site text) returns game.treasure_sites
language sql stable as $$ select * from game.treasure_sites where id = p_site $$;

-- describeMapItem_ (decode = buku saja, sama dengan TreasureService.isDecoded_)
create or replace function game.treasure_describe(p_pid uuid, it game.item_catalog, p_qty int) returns jsonb
language plpgsql stable as $$
declare s game.treasure_sites; v_dec boolean;
begin
  s := game.treasure_site(case when jsonb_typeof(it.effects) = 'object' then it.effects ->> 'siteId' end);
  if s.id is null then
    return jsonb_build_object('itemId', it.item_id, 'name', it.name, 'qty', p_qty,
      'siteId', null, 'siteName', 'Lokasi tidak dikenali', 'cityId', null, 'cityName', '',
      'difficulty', 0, 'decoded', false, 'clue', 'Peta ini rusak - lokasinya tidak bisa dibaca.');
  end if;
  v_dec := game.book_has_effect(p_pid, s.requires_book_keyword);
  return jsonb_build_object('itemId', it.item_id, 'name', it.name, 'qty', p_qty,
    'siteId', s.id, 'siteName', s.name, 'cityId', s.city_id, 'cityName', game.city_name(s.city_id),
    'difficulty', s.difficulty, 'decoded', v_dec,
    'clue', case when v_dec then s.clue_full else s.clue_hint end);
end $$;

-- getPlayerTreasureMapsView
create or replace function game.treasure_maps_view(p_pid uuid) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(game.treasure_describe(p_pid, c, i.qty) order by c.sort, c.item_id), '[]'::jsonb)
    from game.inventory i join game.item_catalog c on c.item_id = i.item_id
   where i.player_id = p_pid and i.qty > 0 and c.type = 'treasure_map'
$$;

-- ---------------------------------------------------------------------
-- KONTRAK: treasure_drop (CombatService: menang -> peluang peta harta)
-- Kembalikan { itemId, name, note } (itemId/name = bentuk lootItem di .gs;
-- note = teks yang di .gs ditambahkan ke pesan akhir combat) atau null.
-- ---------------------------------------------------------------------
create or replace function game.treasure_drop(p_pid uuid, p_enemy_level int) returns jsonb
language plpgsql as $$
declare v_chance numeric := game.cfg_num('TreasureMapDropChance', 15); it game.item_catalog;
begin
  if not (random() * 100 < v_chance) then return null; end if;
  select * into it from game.item_catalog where type = 'treasure_map' order by random() limit 1;
  if not found then return null; end if;
  perform game.item_adjust(p_pid, it.item_id, 1);
  return jsonb_build_object('itemId', it.item_id, 'name', it.name,
    'note', ' Among the wreckage, the crew salvages ' || it.name || '!');
end $$;

-- ---------------------------------------------------------------------
-- API: Items & Treasure
-- ---------------------------------------------------------------------
create or replace function public.api_getItems(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); v_pid uuid := v_me.player_id;
begin
  return jsonb_build_object(
    'artifacts', game.artifacts_view(v_pid),
    'treasureMaps', game.treasure_maps_view(v_pid),
    'shop', game.treasure_map_shop(game.current_city(v_pid)));
end $$;
select game.expose('api_getitems');

create or replace function public.api_getTreasureMapDetail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_item text := game.arg(a, 0); v_me game.players := game.me(); it game.item_catalog; v_q int;
begin
  it := game.item(v_item);
  if it.item_id is null or it.type <> 'treasure_map' then raise exception 'Item ini bukan treasure map.'; end if;
  v_q := game.item_qty(v_me.player_id, v_item);
  if v_q < 1 then raise exception 'Kamu tidak punya peta ini.'; end if;
  return game.treasure_describe(v_me.player_id, it, v_q);
end $$;
select game.expose('api_gettreasuremapdetail');

create or replace function public.api_digTreasure(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_item   text := game.arg(a, 0);
  v_me     game.players := game.me(true);
  v_pid    uuid := v_me.player_id;
  it       game.item_catalog;
  s        game.treasure_sites;
  v_dec    boolean;
  v_base   numeric := game.cfg_num('TreasureDigBaseGold', 350);
  v_mult   numeric;
  w        int[];
  v_roll   double precision;
  v_out    text;
  v_gold   bigint := 0;
  v_cond   bigint := 0;
  v_grant  boolean := false;
  v_newgold bigint := v_me.gold;
  v_art    game.item_catalog;
  v_granted jsonb := null;
  v_newcond numeric := null;
  v_msg    text;
begin
  it := game.item(v_item);
  if it.item_id is null or it.type <> 'treasure_map' then raise exception 'Item ini bukan treasure map.'; end if;
  if game.item_qty(v_pid, v_item) < 1 then raise exception 'Kamu tidak punya peta ini.'; end if;
  s := game.treasure_site(case when jsonb_typeof(it.effects) = 'object' then it.effects ->> 'siteId' end);
  if s.id is null then raise exception 'Lokasi di peta ini tidak dikenali - peta rusak.'; end if;
  if game.in_transit(v_pid) then
    raise exception 'Kamu sedang berlayar - merapat dulu sebelum menggali.';
  end if;
  if game.current_city(v_pid) is distinct from s.city_id then
    raise exception 'Peta ini menunjuk ke lokasi dekat % - berlayar ke sana dulu.', game.city_name(s.city_id);
  end if;

  -- rollDigOutcome_: bobot [big_gold, rare_item, small_gold, false_map]
  v_dec := game.book_has_effect(v_pid, s.requires_book_keyword);
  v_mult := s.difficulty;
  w := case when v_dec then array[30, 20, 40, 10] else array[12, 8, 45, 35] end;
  v_roll := random() * 100;
  if v_roll < w[1] then v_out := 'big_gold';
  elsif v_roll < w[1] + w[2] then v_out := 'rare_item';
  elsif v_roll < w[1] + w[2] + w[3] then v_out := 'small_gold';
  else v_out := 'false_map';
  end if;

  if v_out = 'big_gold' then
    v_gold := game.js_round((v_base * v_mult)::double precision * (1.6 + random() * 1.2));
  elsif v_out = 'rare_item' then
    v_gold := game.js_round((v_base * v_mult)::double precision * (0.6 + random() * 0.4));
    v_grant := true;
  elsif v_out = 'small_gold' then
    v_gold := game.js_round((v_base * v_mult)::double precision * (0.3 + random() * 0.5));
  else
    v_cond := -game.js_round((8 + random() * 10) * least(3, greatest(1, v_mult))::double precision);
  end if;

  -- Peta HABIS terpakai apapun hasilnya
  perform game.item_adjust(v_pid, v_item, -1);

  if v_gold <> 0 then
    v_newgold := greatest(0, v_me.gold + v_gold);
    update game.players set gold = v_newgold where player_id = v_pid;
  end if;

  if v_grant then
    select * into v_art from game.item_catalog where type = 'artifact' order by random() limit 1;
    if found then
      perform game.item_adjust(v_pid, v_art.item_id, 1);
      v_granted := jsonb_build_object('itemId', v_art.item_id, 'name', v_art.name);
    end if;
  end if;

  if v_cond <> 0 then
    v_newcond := game.apply_condition_delta(v_pid, v_cond);
  end if;

  -- buildDigMessage_
  v_msg := case v_out
    when 'big_gold' then 'Galian di ' || s.name || ' membuahkan hasil besar - ' || v_gold || ' gold ditemukan terkubur.'
    when 'rare_item' then case when v_granted is not null
      then 'Galian di ' || s.name || ' menemukan ' || v_gold || ' gold DAN sebuah artifact: "' || (v_granted ->> 'name') || '"!'
      else 'Galian di ' || s.name || ' menemukan ' || v_gold || ' gold.' end
    when 'small_gold' then 'Galian di ' || s.name || ' menemukan sisa harta sederhana - ' || v_gold || ' gold.'
    else 'Peta ternyata jebakan - galian di ' || s.name || ' memicu perangkap tua, kapal sedikit rusak (' ||
      v_cond || ' Condition), tidak ada harta ditemukan.' end;
  perform game.log(v_pid, v_msg);

  return jsonb_build_object(
    'outcome', v_out,
    'message', v_msg,
    'goldDelta', v_gold,
    'newGold', v_newgold,
    'grantedItem', v_granted,
    'conditionDelta', v_cond,
    'newCondition', coalesce(to_jsonb(v_newcond), game.ship_json(v_pid) -> 'Condition'));
end $$;
select game.expose('api_digtreasure');

create or replace function public.api_equipArtifact(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_item text := game.arg(a, 0);
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  it     game.item_catalog;
  v_slot text;
begin
  it := game.item(v_item);
  if it.item_id is null or it.type <> 'artifact' then raise exception 'Item ini bukan artifact yang bisa dipasang.'; end if;
  if game.item_qty(v_pid, v_item) < 1 then raise exception 'Kamu tidak punya artifact ini di cargo.'; end if;
  if exists (select 1 from game.ship_equipment where player_id = v_pid and slot_type = any (game.artifact_slots()) and item_id = v_item) then
    raise exception 'Artifact ini sudah terpasang.';
  end if;
  select s.slot into v_slot
    from unnest(game.artifact_slots()) with ordinality s(slot, ord)
   where not exists (select 1 from game.ship_equipment e where e.player_id = v_pid and e.slot_type = s.slot and coalesce(e.item_id, '') <> '')
   order by s.ord limit 1;
  if v_slot is null then raise exception 'Kedua slot equipment sudah penuh - copot salah satu dulu.'; end if;

  insert into game.ship_equipment(player_id, slot_type, item_id) values (v_pid, v_slot, v_item)
  on conflict (player_id, slot_type) do update set item_id = excluded.item_id;
  perform game.item_adjust(v_pid, v_item, -1);
  perform game.log(v_pid, 'Equipped the artifact "' || it.name || '" to the ship.');
  return game.artifacts_view(v_pid);
end $$;
select game.expose('api_equipartifact');

create or replace function public.api_unequipArtifact(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_slotkey text := nullif(game.arg(a, 0), '');
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  v_tslot text;
  v_titem text;
  it     game.item_catalog;
begin
  if not exists (select 1 from game.ship_equipment where player_id = v_pid and slot_type = any (game.artifact_slots()) and coalesce(item_id, '') <> '') then
    raise exception 'Tidak ada artifact yang terpasang.';
  end if;
  select e.slot_type, e.item_id into v_tslot, v_titem
    from unnest(game.artifact_slots()) with ordinality s(slot, ord)
    join game.ship_equipment e on e.player_id = v_pid and e.slot_type = s.slot and coalesce(e.item_id, '') <> ''
   where v_slotkey is null or s.slot = v_slotkey
   order by s.ord limit 1;
  if v_tslot is null then raise exception 'Slot itu sedang kosong.'; end if;

  delete from game.ship_equipment where player_id = v_pid and slot_type = v_tslot;
  perform game.item_adjust(v_pid, v_titem, 1);
  it := game.item(v_titem);
  perform game.log(v_pid, 'Unequipped the artifact "' || coalesce(it.name, v_titem) || '".');
  return game.artifacts_view(v_pid);
end $$;
select game.expose('api_unequipartifact');

create or replace function public.api_sellItem(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_item text := game.arg(a, 0);
  v_qty  bigint := greatest(1, coalesce(nullif(game.arg_int(a, 1), 0), 1));
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  it     game.item_catalog;
  v_gold bigint;
begin
  it := game.item(v_item);
  if it.item_id is null then raise exception 'Item tidak dikenali: %', v_item; end if;
  if exists (select 1 from game.ship_equipment where player_id = v_pid and slot_type = any (game.artifact_slots()) and item_id = v_item) then
    raise exception 'Copot dulu artifact ini sebelum dijual.';
  end if;
  if game.item_qty(v_pid, v_item) < v_qty then raise exception 'Jumlah item tidak cukup.'; end if;

  v_gold := game.js_round(coalesce(it.value, 0)::double precision * v_qty);
  perform game.item_adjust(v_pid, v_item, -v_qty::int);
  update game.players set gold = gold + v_gold where player_id = v_pid;
  perform game.log(v_pid, 'Sold ' || v_qty || 'x "' || it.name || '" for ' || v_gold || ' gold.');
  return jsonb_build_object('newGold', v_me.gold + v_gold, 'goldEarned', v_gold);
end $$;
select game.expose('api_sellitem');

create or replace function public.api_buyTreasureMap(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_item text := game.arg(a, 0);
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  it     game.item_catalog;
  v_price bigint;
begin
  it := game.item(v_item);
  if it.item_id is null or it.type <> 'treasure_map' then raise exception 'Item ini bukan treasure map.'; end if;
  if coalesce(it.price, 0) <= 0 then raise exception 'Peta ini tidak dijual di sini.'; end if;
  v_price := it.price;
  if v_me.gold < v_price then
    raise exception 'Gold tidak cukup - butuh %, kamu punya %.', v_price, v_me.gold;
  end if;
  update game.players set gold = gold - v_price where player_id = v_pid;
  perform game.item_adjust(v_pid, v_item, 1);
  perform game.log(v_pid, 'Bought "' || it.name || '" for ' || v_price || ' gold.');
  return jsonb_build_object('newGold', v_me.gold - v_price, 'itemId', v_item, 'name', it.name);
end $$;
select game.expose('api_buytreasuremap');
