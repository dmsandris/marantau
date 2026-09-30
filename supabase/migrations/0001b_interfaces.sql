-- =====================================================================
-- Marantau (Supabase) - 0001b INTERFACES
-- ---------------------------------------------------------------------
-- Fungsi "kontrak" antar-modul. Di sini hanya versi PENGGANTI SEMENTARA
-- (stub) yang aman; migrasi modul pemiliknya (lihat PORTING.md) menimpa
-- dengan implementasi asli lewat CREATE OR REPLACE. Tujuannya: setiap
-- modul bisa diuji sendiri tanpa menunggu modul lain.
-- Semua ditulis plpgsql supaya referensi ke tabel modul lain baru
-- diperiksa saat dijalankan.
-- =====================================================================

-- [modul economy / 0002] ----------------------------------------------
create or replace function game.adjust_inventory(p_pid uuid, p_item text, p_delta int) returns int
language plpgsql as $$
declare q int;
begin
  insert into game.inventory(player_id, item_id, qty) values (p_pid, p_item, 0)
  on conflict (player_id, item_id) do nothing;
  update game.inventory set qty = qty + p_delta where player_id = p_pid and item_id = p_item returning qty into q;
  if q < 0 then
    raise exception 'Jumlah cargo tidak boleh negatif.';
  end if;
  return q;
end $$;

create or replace function game.cargo_total(p_pid uuid) returns int
language plpgsql stable as $$
declare n int;
begin
  select coalesce(sum(i.qty), 0) into n from game.inventory i join game.commodities c on c.id = i.item_id where i.player_id = p_pid and i.qty > 0;
  return n + coalesce(game.mission_load(p_pid), 0);
end $$;

create or replace function game.reputation_for(p_pid uuid, p_city text) returns int
language plpgsql stable as $$
declare r jsonb;
begin
  select reputation into r from game.players where player_id = p_pid;
  return coalesce((r ->> p_city)::numeric, 0)::int;
exception when others then return 0;
end $$;

create or replace function game.stats_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.character_stats;
begin
  select * into s from game.character_stats where player_id = p_pid;
  if not found then return null; end if;
  return jsonb_build_object('Trading', s.trading, 'Negotiation', s.negotiation, 'Navigation', s.navigation,
    'Sailing', s.sailing, 'Combat', s.combat, 'Luck', s.luck, 'Knowledge', s.knowledge);
end $$;

create or replace function game.quote_buy(p_pid uuid, p_city text, p_commodity text) returns int
language plpgsql stable as $$
declare p int;
begin
  select current_price into p from game.market where city_id = p_city and commodity_id = p_commodity;
  return coalesce(p, 0);
end $$;

create or replace function game.bank_state(p_pid uuid) returns jsonb
language plpgsql as $$
begin
  return jsonb_build_object('bankBalance', 0, 'debtBalance', 0, 'bankRatePercent', 0, 'debtRatePercent', 0, 'maxDebt', 0, 'migrated', true);
end $$;

-- [modul ship/voyage/combat / 0003] -------------------------------------
create or replace function game.current_city(p_pid uuid) returns text
language plpgsql stable as $$
declare c text;
begin
  select city_id into c from game.player_location where player_id = p_pid;
  return coalesce(c, 'sunda_empire');
end $$;

create or replace function game.in_transit(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  return exists (select 1 from game.player_location where player_id = p_pid and coalesce(destination_city_id, '') <> '');
end $$;

create or replace function game.effective_cargo(p_pid uuid) returns int
language plpgsql stable as $$
declare c int;
begin
  select cargo into c from game.ships where player_id = p_pid;
  return coalesce(c, 0);
end $$;

create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.ships;
begin
  select * into s from game.ships where player_id = p_pid;
  if not found then return null; end if;
  return jsonb_build_object('ShipName', s.ship_name, 'Tier', s.tier, 'Hull', s.hull, 'MaxHull', s.max_hull,
    'Cargo', s.cargo, 'Speed', s.speed, 'Combat', s.combat, 'Armor', s.armor, 'Navigation', s.navigation,
    'Condition', s.condition, 'EffectiveCargo', s.cargo, 'CargoBonus', 0, 'EffectiveMaxCondition', 100,
    'ConditionPct', round(s.condition), 'SpeedMultiplier', 1, 'CannonBonusPercent', 0, 'MaxCannonAmmo', 3);
end $$;

create or replace function game.voyage_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
begin
  return jsonb_build_object('inTransit', false);
end $$;

create or replace function game.resolve_arrival_if_due(p_pid uuid) returns jsonb
language plpgsql as $$ begin return null; end $$;

create or replace function game.apply_condition_delta(p_pid uuid, p_delta numeric) returns numeric
language plpgsql as $$
declare c numeric;
begin
  update game.ships set condition = greatest(0, least(100, condition + p_delta)) where player_id = p_pid returning condition into c;
  return c;
end $$;

create or replace function game.city_event(p_city text) returns jsonb
language plpgsql stable as $$ begin return null; end $$;

create or replace function game.event_price_pct(p_city text) returns int
language plpgsql stable as $$ begin return coalesce((game.city_event(p_city) ->> 'priceMultiplierPercent')::int, 0); end $$;

create or replace function game.event_reward_pct(p_city text) returns int
language plpgsql stable as $$ begin return coalesce((game.city_event(p_city) ->> 'rewardMultiplierPercent')::int, 0); end $$;

-- [modul missions/items / 0004] -----------------------------------------
create or replace function game.mission_load(p_pid uuid) returns int
language plpgsql stable as $$ begin return 0; end $$;

create or replace function game.mission_state(p_pid uuid) returns jsonb
language plpgsql stable as $$ begin return jsonb_build_object('hasActive', false); end $$;

-- Efek khusus dari buku (special_effect) ATAU artifact terpasang
create or replace function game.has_effect(p_pid uuid, p_effect text) returns boolean
language plpgsql stable as $$ begin return false; end $$;

-- Dipanggil combat saat menang: kembalikan info loot peta harta (atau null)
create or replace function game.treasure_drop(p_pid uuid, p_enemy_level int) returns jsonb
language plpgsql as $$ begin return null; end $$;

-- [modul multiplayer / 0005] ------------------------------------------
create or replace function game.mp_touch(p_pid uuid) returns void
language plpgsql as $$ begin return; end $$;

create or replace function game.mp_mark_sea(p_pid uuid, p_dest text) returns void
language plpgsql as $$ begin return; end $$;

-- [umum - implementasi final di sini] ---------------------------------
create or replace function game.recent_logs(p_pid uuid, p_limit int default 30) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('gameDay', l.game_day, 'timestamp', game.iso(l.ts), 'message', l.message) order by l.id desc), '[]'::jsonb)
  from (select * from game.player_log where player_id = p_pid order by id desc limit p_limit) l
$$;

create or replace function game.audio_config() returns jsonb
language sql stable as $$
  select jsonb_build_object('bgmUrl', coalesce(game.cfg('SoundBgmUrl'), ''),
    'enabledByAdmin', coalesce(lower(game.cfg('SoundEnabled')), 'true') <> 'false')
$$;
