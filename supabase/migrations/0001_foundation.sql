-- =====================================================================
-- Marantau (Supabase) - 0001 FOUNDATION
-- ---------------------------------------------------------------------
-- Semua tabel & helper game ada di schema `game` (TIDAK diekspos ke API).
-- Satu-satunya pintu dari browser adalah fungsi public.api_*(a jsonb)
-- (SECURITY DEFINER) - nama & bentuk jawabannya sama persis dengan
-- fungsi api_* versi Apps Script, jadi client lama tetap jalan.
--
-- Konvensi fungsi API:
--   public.api_nama(a jsonb default '[]')  returns jsonb
--   argumen posisi: a->>0, a->>1, ... (sama urutannya dengan versi .gs)
--   error untuk pemain: raise exception '<pesan>'  (client menerima pesannya)
-- =====================================================================

create schema if not exists game;
revoke all on schema game from public;

-- ---------------------------------------------------------------------
-- Konfigurasi (pengganti sheet GameConfig)
-- ---------------------------------------------------------------------
create table if not exists game.config (
  key   text primary key,
  value text
);

create or replace function game.cfg(p_key text) returns text
language sql stable as $$ select value from game.config where key = p_key $$;

create or replace function game.cfg_num(p_key text, p_fallback numeric) returns numeric
language plpgsql stable as $$
declare v text;
begin
  select value into v from game.config where key = p_key;
  if v is null or btrim(v) = '' then return p_fallback; end if;
  begin
    return v::numeric;
  exception when others then
    return p_fallback;
  end;
end $$;

create or replace function game.cfg_set(p_key text, p_value text) returns void
language sql as $$
  insert into game.config(key, value) values (p_key, p_value)
  on conflict (key) do update set value = excluded.value
$$;

-- ---------------------------------------------------------------------
-- Waktu dunia: hari-game dihitung dari WorldStartTimestamp (ms epoch),
-- persis seperti TimeService.gs.
-- ---------------------------------------------------------------------
create or replace function game.now_ms() returns bigint
language sql stable as $$ select (extract(epoch from clock_timestamp()) * 1000)::bigint $$;

create or replace function game.game_day() returns int
language plpgsql stable as $$
declare start_ms bigint; len_min numeric;
begin
  start_ms := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  len_min := game.cfg_num('GameDayLengthRealMinutes', 60);
  if start_ms = 0 or len_min <= 0 then
    raise exception 'GameConfig belum di-seed (WorldStartTimestamp).';
  end if;
  return floor((game.now_ms() - start_ms) / (len_min * 60000))::int;
end $$;

create or replace function game.minutes_to_next_day() returns int
language plpgsql stable as $$
declare start_ms bigint; len_ms numeric; into_day numeric;
begin
  start_ms := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  len_ms := game.cfg_num('GameDayLengthRealMinutes', 60) * 60000;
  into_day := mod(game.now_ms() - start_ms, len_ms::bigint);
  return ceil((len_ms - into_day) / 60000)::int;
end $$;

-- ---------------------------------------------------------------------
-- Angka acak
-- ---------------------------------------------------------------------
create or replace function game.rand_int(lo int, hi int) returns int
language sql volatile as $$ select lo + floor(random() * (hi - lo + 1))::int $$;

-- Deterministik dari string (pengganti seededRandom_): nilai 0..1 untuk (seed, n)
create or replace function game.seeded(p_seed text, p_n int) returns double precision
language sql immutable as $$
  select ('x' || substr(md5(p_seed || ':' || p_n::text), 1, 8))::bit(32)::bigint / 4294967296.0
$$;

-- ---------------------------------------------------------------------
-- Data referensi
-- ---------------------------------------------------------------------
create table if not exists game.cities (
  city_id          text primary key,
  name             text not null,
  type             text not null,
  repair_cost_rate numeric not null default 1,
  image_url        text not null default '',
  map_x            numeric not null default 50,
  map_y            numeric not null default 50,
  sort             int not null default 0
);
alter table game.cities add column if not exists hidden boolean not null default false;  -- kota rahasia (dibuka lewat misi)

create table if not exists game.commodities (
  id     text primary key,
  name   text not null,
  flavor text not null default '',
  sort   int not null default 0
);

create table if not exists game.market (
  city_id       text not null references game.cities(city_id) on delete cascade,
  commodity_id  text not null references game.commodities(id) on delete cascade,
  base_price    int not null,
  current_price int not null,
  updated_at    timestamptz not null default now(),
  primary key (city_id, commodity_id)
);
-- Ekonomi v2 (0018): atribut barang & stok pasar
alter table game.commodities add column if not exists grp text not null default 'pangan';
alter table game.commodities add column if not exists tier text not null default 'common';
alter table game.commodities add column if not exists base int not null default 100;
alter table game.commodities add column if not exists size numeric not null default 1;
alter table game.commodities add column if not exists spread numeric not null default 0.08;
alter table game.commodities add column if not exists elast numeric not null default 0.6;
alter table game.commodities add column if not exists ref numeric not null default 100;
alter table game.commodities add column if not exists active boolean not null default true;
alter table game.market add column if not exists role text not null default 'neutral';
alter table game.market add column if not exists stock numeric;
alter table game.market add column if not exists at timestamptz not null default now();
alter table game.market add column if not exists cyc bigint;

-- Tide v8: stok menumpuk (dibagi semua pemain)
create table if not exists game.market_glut (
  city_id      text not null,
  commodity_id text not null,
  glut         numeric not null default 0,
  at           timestamptz not null default now(),
  primary key (city_id, commodity_id)
);

-- ---------------------------------------------------------------------
-- Pemain
-- player_id = auth.uid() dari Supabase Auth.
-- ---------------------------------------------------------------------
create table if not exists game.players (
  player_id                uuid primary key,
  username                 text unique,
  character_name           text not null default '',
  archetype                text not null default '',
  gold                     bigint not null default 0,
  reputation               jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  last_active              timestamptz not null default now(),
  bank_balance             bigint not null default 0,
  bank_last_interest_day   int,
  debt_balance             bigint not null default 0,
  debt_last_interest_day   int,
  ship_upgrades            jsonb not null default '{}'::jsonb,
  appearance               jsonb,
  meta                     jsonb,
  legacy_id                text          -- id lama dari Google Sheets (email / acc:username), untuk impor data
);
create unique index if not exists players_character_name_uq
  on game.players (lower(btrim(character_name))) where character_name <> '';

create table if not exists game.character_stats (
  player_id   uuid primary key references game.players(player_id) on delete cascade,
  trading     int not null default 35,
  negotiation int not null default 35,
  navigation  int not null default 35,
  sailing     int not null default 35,
  combat      int not null default 35,
  luck        int not null default 15,
  knowledge   int not null default 5
);

create table if not exists game.ships (
  player_id                uuid primary key references game.players(player_id) on delete cascade,
  ship_name                text not null default 'The Wandering Gull',
  tier                     text not null default 'I',
  hull                     int not null default 100,
  max_hull                 int not null default 100,
  cargo                    int not null default 30,
  speed                    int not null default 50,
  combat                   int not null default 5,
  armor                    int not null default 10,
  navigation               int not null default 20,
  condition                numeric not null default 100,
  condition_decay_per_sail numeric not null default 0.03,
  max_condition            int not null default 100,
  damage_threshold         int not null default 45
);

create table if not exists game.player_location (
  player_id           uuid primary key references game.players(player_id) on delete cascade,
  city_id             text not null default 'sunda_empire',
  arrived_game_day    int,
  destination_city_id text,
  depart_at           timestamptz,
  arrive_at           timestamptz,
  pending_encounter   jsonb
);

-- PlayerInventory: komoditas DAN item (artifact/peta harta) - sama seperti sheet lama
create table if not exists game.inventory (
  player_id uuid not null references game.players(player_id) on delete cascade,
  item_id   text not null,
  qty       int not null default 0,
  primary key (player_id, item_id)
);

create table if not exists game.warehouse (
  player_id    uuid not null references game.players(player_id) on delete cascade,
  city_id      text not null,
  commodity_id text not null,
  qty          int not null default 0,
  primary key (player_id, city_id, commodity_id)
);

create table if not exists game.player_log (
  id        bigserial primary key,
  player_id uuid not null references game.players(player_id) on delete cascade,
  game_day  int not null,
  ts        timestamptz not null default now(),
  message   text not null
);
create index if not exists player_log_player_idx on game.player_log (player_id, id desc);

create table if not exists game.city_events (
  id               bigserial primary key,
  city_id          text not null,
  event_type       text not null,
  label            text not null,
  message          text not null,
  price_pct        int not null default 0,
  reward_pct       int not null default 0,
  expires_game_day int not null
);
create index if not exists city_events_city_idx on game.city_events (city_id, expires_game_day desc);

-- ---------------------------------------------------------------------
-- Keamanan: tabel tidak bisa disentuh langsung dari browser.
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'game' loop
    execute format('alter table game.%I enable row level security', t.tablename);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Identitas & baris pemain
-- ---------------------------------------------------------------------
create or replace function game.uid() returns uuid
language plpgsql stable as $$
declare u uuid;
begin
  u := auth.uid();
  if u is null then
    raise exception 'AUTH_REQUIRED: Silakan masuk dengan akun Marantau-mu.';
  end if;
  return u;
end $$;

-- Username dari email Supabase Auth (<username>@marantau.game)
create or replace function game.auth_username() returns text
language sql stable as $$ select lower(split_part(coalesce(auth.email(), ''), '@', 1)) $$;

-- Pastikan baris pemain ada; kembalikan baris (terkunci FOR UPDATE bila p_lock)
create or replace function game.me(p_lock boolean default false) returns game.players
language plpgsql as $$
declare u uuid; r game.players;
begin
  u := game.uid();
  if p_lock then
    select * into r from game.players where player_id = u for update;
  else
    select * into r from game.players where player_id = u;
  end if;
  if not found then
    insert into game.players(player_id, username) values (u, nullif(game.auth_username(), ''))
    on conflict (player_id) do nothing;
    select * into r from game.players where player_id = u for update;
  elsif r.last_active < now() - interval '1 minute' then
    update game.players set last_active = now() where player_id = u;
  end if;
  return r;
end $$;

create or replace function game.player(p_id uuid) returns game.players
language sql stable as $$ select * from game.players where player_id = p_id $$;

create or replace function game.player_json(r game.players) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'playerId', r.player_id,
    'characterName', r.character_name,
    'archetype', r.archetype,
    'gold', r.gold,
    'reputation', r.reputation::text,
    'createdAt', to_char(r.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'lastActive', to_char(r.last_active at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'hasCharacter', r.archetype <> ''
  )
$$;

create or replace function game.add_gold(p_id uuid, p_delta bigint) returns bigint
language sql as $$
  update game.players set gold = greatest(0, gold + p_delta) where player_id = p_id returning gold
$$;

create or replace function game.log(p_id uuid, p_msg text) returns void
language sql as $$
  insert into game.player_log(player_id, game_day, message) values (p_id, game.game_day(), p_msg)
$$;

create or replace function game.iso(t timestamptz) returns text
language sql immutable as $$ select case when t is null then '' else to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end $$;

-- ---------------------------------------------------------------------
-- Kota (bentuk JSON sama dengan WorldService.getCities)
-- ---------------------------------------------------------------------
create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case p_type
    when 'TradeHub' then 'Pelabuhan sibuk tempat semua rute berpotongan - harga stabil, pilihan barang lengkap.'
    when 'Agricultural' then 'Lumbung wilayah ini - hasil bumi murah, barang mewah harus didatangkan dari luar.'
    when 'Remote' then 'Jauh dari jalur ramai - harga lebih mahal, tapi lebih sedikit persaingan pedagang.'
    when 'Capital' then 'Kota besar yang penuh sukacita - pasar paling lengkap, harga adil dan stabil untuk semua.'
    when 'Outlaw' then 'Sarang penyamun - kapal dagang menuju sini nyaris pasti dicegat bajak laut di tengah jalan. Senjata di sini selalu lebih murah dari kota manapun.'
    when 'FallenCapital' then 'Ibu kota lama yang sudah tumbang - reruntuhan megah dengan banyak yang perlu dibenahi. Papan misi paling ramai di sini, meski bayarannya seadanya.'
    else '' end
$$;

create or replace function game.city_json(c game.cities) returns jsonb
language sql stable as $$
  select case when c.city_id is null then null else jsonb_build_object(
    'CityId', c.city_id, 'Name', c.name, 'Type', c.type,
    'RepairCostRate', c.repair_cost_rate, 'MayorMissionPool', '',
    'ImageUrl', c.image_url, 'MapX', c.map_x, 'MapY', c.map_y,
    'TypeFlavor', game.city_flavor(c.type), 'Hidden', c.hidden) end
$$;

create or replace function game.city(p_id text) returns jsonb
language sql stable as $$ select game.city_json(c) from game.cities c where c.city_id = p_id $$;

create or replace function game.city_name(p_id text) returns text
language sql stable as $$ select coalesce((select name from game.cities where city_id = p_id), p_id) $$;

create or replace function game.cities_json() returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(game.city_json(c) order by c.sort, c.city_id), '[]'::jsonb) from game.cities c
$$;

create or replace function game.cities_version() returns text
language sql stable as $$ select coalesce(game.cfg('CitiesVersion'), '1') $$;

create or replace function game.commodity_name(p_id text) returns text
language sql stable as $$ select coalesce((select name from game.commodities where id = p_id), p_id) $$;

-- ---------------------------------------------------------------------
-- SEED: konfigurasi (nilai default sama dengan fallback di kode .gs)
-- ---------------------------------------------------------------------
insert into game.config(key, value) values
  ('WorldStartTimestamp', ((extract(epoch from now()) * 1000)::bigint)::text),
  ('GameDayLengthRealMinutes', '60'),
  ('CitiesVersion', '1'),
  ('TitleScreenImageUrl', ''),
  ('SailingBackgroundImageUrl', ''),
  ('SoundBgmUrl', ''),
  ('SoundEnabled', 'true'),
  ('TravelMinutesPerDistanceUnit', '0.25'),
  ('MinTravelMinutes', '5'),
  ('BaselineShipSpeed', '50'),
  ('WarehouseFeePerUnit', '2'),
  ('BankInterestRatePercent', '0.5'),
  ('DebtInterestRatePercent', '2'),
  ('MaxDebtAmount', '5000'),
  ('ReputationMarketBonusPerPoint', '0.05'),
  ('ReputationMarketBonusCap', '10'),
  ('ShipRepairBaseCostPerPoint', '15'),
  ('PirateEncounterBaseChance', '12'),
  ('PirateEncounterLevelMax', '5'),
  ('PirateEncounterConditionPenalty', '15'),
  ('CombatBaseAmmo', '3'),
  ('CombatEnemyBaseHp', '40'),
  ('CombatEnemyHpPerLevel', '25'),
  ('CombatLootGoldPerLevel', '200'),
  ('CombatBribeGoldPerLevel', '150'),
  ('TreasureMapDropChance', '15'),
  ('TreasureDigBaseGold', '350'),
  ('WorldEventRollChancePercent', '10'),
  ('WorldEventMinDurationDays', '2'),
  ('WorldEventMaxDurationDays', '5'),
  ('OverstockScale', '120'),
  ('OverstockHalfLifeMinutes', '120'),
  ('OverstockFloorPercent', '35')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- SEED: kota, komoditas, harga pasar (CommodityData.gs + migrasi kota)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, map_x, map_y, sort) values
  ('sunda_empire', 'Sunda Empire', 'TradeHub',      1.0, 25, 55, 1),
  ('joungjava',    'Joungjava',    'Agricultural',  1.2, 60, 30, 2),
  ('bjorneo',      'Bjorneo',      'Remote',        1.6, 75, 75, 3),
  ('skitraw',      'Skitraw',      'Capital',       0.9, 45, 15, 4),
  ('toogood',      'TooGood',      'Outlaw',        1.3, 15, 80, 5),
  ('ikn',          'IKN',          'FallenCapital', 1.4, 50, 62, 6)
on conflict (city_id) do nothing;

insert into game.commodities(id, name, flavor, sort) values
  ('sugar',  'Sugar',  'Manis, berat, dan selalu dicari dapur istana.', 1),
  ('silk',   'Silk',   'Halus seperti bisikan, mahal seperti janji bangsawan.', 2),
  ('spices', 'Spices', 'Aroma yang membuat pedagang jauh rela berlayar.', 3),
  ('rum',    'Rum',    'Bahan bakar kru sekaligus mata uang tidak resmi pelabuhan.', 4),
  ('tools',  'Tools',  'Tidak glamor, tapi setiap pemukiman baru membutuhkannya.', 5),
  ('arms',   'Arms',   'Diperlukan untuk melindungi diri - atau merampas milik orang lain.', 6)
on conflict (id) do nothing;

insert into game.market(city_id, commodity_id, base_price, current_price)
select v.city_id, v.commodity_id, v.price, v.price from (values
  ('sunda_empire','sugar',100),('sunda_empire','silk',250),('sunda_empire','spices',180),('sunda_empire','rum',90),('sunda_empire','tools',150),('sunda_empire','arms',300),
  ('joungjava','sugar',70),('joungjava','silk',300),('joungjava','spices',120),('joungjava','rum',60),('joungjava','tools',180),('joungjava','arms',340),
  ('bjorneo','sugar',110),('bjorneo','silk',280),('bjorneo','spices',220),('bjorneo','rum',100),('bjorneo','tools',220),('bjorneo','arms',380),
  ('skitraw','sugar',95),('skitraw','silk',280),('skitraw','spices',175),('skitraw','rum',85),('skitraw','tools',185),('skitraw','arms',340),
  ('toogood','sugar',105),('toogood','rum',70),('toogood','tools',200),('toogood','arms',160),
  ('ikn','sugar',130),('ikn','silk',320),('ikn','spices',240),('ikn','rum',115),('ikn','tools',260),('ikn','arms',400)
) as v(city_id, commodity_id, price)
on conflict (city_id, commodity_id) do nothing;

-- ---------------------------------------------------------------------
-- Pembungkus API: helper untuk mendaftarkan hak akses.
-- Setiap migrasi berikutnya memanggil game.expose('api_x', true/false)
-- (true = boleh dipanggil tanpa login).
-- ---------------------------------------------------------------------
create or replace function game.expose(p_fn text, p_public boolean default false) returns void
language plpgsql as $$
begin
  -- Supabase memberi hak eksekusi otomatis ke anon/authenticated -> cabut dulu semuanya
  execute format('revoke all on function public.%I(jsonb) from public, anon, authenticated', p_fn);
  execute format('grant execute on function public.%I(jsonb) to authenticated', p_fn);
  if p_public then
    execute format('grant execute on function public.%I(jsonb) to anon', p_fn);
  end if;
end $$;

-- Helper argumen posisi
create or replace function game.arg(a jsonb, i int) returns text
language sql immutable as $$ select case when a is null or jsonb_typeof(a) <> 'array' then null else a ->> i end $$;
create or replace function game.arg_int(a jsonb, i int) returns bigint
language plpgsql immutable as $$
declare v text := game.arg(a, i);
begin
  if v is null or btrim(v) = '' then return null; end if;
  return floor(v::numeric)::bigint;
exception when others then
  return null;
end $$;
create or replace function game.arg_json(a jsonb, i int) returns jsonb
language sql immutable as $$ select case when a is null or jsonb_typeof(a) <> 'array' then null else a -> i end $$;

-- ---------------------------------------------------------------------
-- API publik ringan (tanpa login)
-- ---------------------------------------------------------------------
create or replace function public.api_ping(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return jsonb_build_object('ok', true, 'time', game.iso(now()), 'playerId', auth.uid());
end $$;
select game.expose('api_ping', true);

create or replace function public.api_getTitleScreenConfig(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return jsonb_build_object('imageUrl', coalesce(game.cfg('TitleScreenImageUrl'), ''));
end $$;
select game.expose('api_gettitlescreenconfig', true);

create or replace function public.api_getSailingBackgroundUrl(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return jsonb_build_object('imageUrl', coalesce(game.cfg('SailingBackgroundImageUrl'), ''));
end $$;
select game.expose('api_getsailingbackgroundurl', true);

create or replace function public.api_getCities(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return jsonb_build_object('cities', game.cities_json(), 'version', game.cities_version());
end $$;
select game.expose('api_getcities', true);
