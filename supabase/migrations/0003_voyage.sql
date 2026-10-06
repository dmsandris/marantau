-- =====================================================================
-- Marantau (Supabase) - 0003 VOYAGE (Modul B)
-- ---------------------------------------------------------------------
-- Port dari: ShipService.gs, ShipUpgradeService.gs, LocationService.gs,
-- CombatService.gs, WorldEventService.gs + endpoint Code.gs:
--   api_getShipState, api_getShipUpgrades, api_shipUpgrade,
--   api_getRepairQuote, api_repairShip, api_getSailOptions, api_setSail,
--   api_resolveCombat
-- Menimpa kontrak 0001b milik modul B: game.current_city, game.in_transit,
-- game.effective_cargo, game.ship_json, game.voyage_state,
-- game.resolve_arrival_if_due, game.apply_condition_delta, game.city_event.
-- Helper internal modul ini berawalan game.voy_.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabel: CombatLog (sheet lama: PlayerId, Timestamp, EnemyLevel, Action, Result, Loot)
-- ---------------------------------------------------------------------
create table if not exists game.combat_log (
  id          bigserial primary key,
  player_id   uuid not null references game.players(player_id) on delete cascade,
  ts          timestamptz not null default now(),
  enemy_level int,
  action      text,
  result      text,
  loot        text not null default ''
);
create index if not exists combat_log_player_idx on game.combat_log (player_id, id desc);
alter table game.combat_log enable row level security;

-- ---------------------------------------------------------------------
-- Helper umum
-- ---------------------------------------------------------------------
-- Math.round versi JS (setengah dibulatkan ke atas, juga untuk negatif)
create or replace function game.voy_round(x numeric) returns numeric
language sql immutable as $$ select floor(x + 0.5) $$;
create or replace function game.voy_round(x double precision) returns numeric
language sql immutable as $$ select floor(x + 0.5)::numeric $$;

create or replace function game.voy_clamp(x numeric, lo numeric, hi numeric) returns numeric
language sql immutable as $$ select least(hi, greatest(lo, x)) $$;

-- Number(v) || 0 versi JS untuk nilai jsonb
create or replace function game.voy_num(v jsonb) returns numeric
language plpgsql immutable as $$
begin
  if v is null then return 0; end if;
  case jsonb_typeof(v)
    when 'number' then return (v #>> '{}')::numeric;
    when 'string' then
      if btrim(v #>> '{}') = '' then return 0; end if;
      begin return (v #>> '{}')::numeric; exception when others then return 0; end;
    when 'boolean' then return case when (v #>> '{}')::boolean then 1 else 0 end;
    else return 0;
  end case;
end $$;

-- statBonus_: min(stat, 100) / 10
create or replace function game.voy_stat_bonus(v jsonb) returns numeric
language sql immutable as $$ select least(game.voy_num(v), 100) / 10.0 $$;

-- ---------------------------------------------------------------------
-- ShipUpgradeService: katalog, level/tier, stat efektif
-- ---------------------------------------------------------------------
create or replace function game.voy_catalogs() returns jsonb
language sql immutable as $$
  select '{
    "speed": [
      {"tier": 1, "cost": 1500,  "speedMultiplier": 0.80, "label": "+20% lebih cepat"},
      {"tier": 2, "cost": 3500,  "speedMultiplier": 0.65, "label": "+35% lebih cepat"},
      {"tier": 3, "cost": 7000,  "speedMultiplier": 0.50, "label": "+50% lebih cepat"},
      {"tier": 4, "cost": 12000, "speedMultiplier": 0.40, "label": "+60% lebih cepat"}
    ],
    "cargo": [
      {"tier": 1, "cost": 1000, "cargoBonus": 5,  "label": "+5 kapasitas"},
      {"tier": 2, "cost": 2500, "cargoBonus": 15, "label": "+15 kapasitas"},
      {"tier": 3, "cost": 5000, "cargoBonus": 30, "label": "+30 kapasitas"},
      {"tier": 4, "cost": 9000, "cargoBonus": 50, "label": "+50 kapasitas"}
    ],
    "condition": [
      {"tier": 1, "cost": 2000,  "maxConditionBonus": 10, "decayReductionPercent": 0,  "label": "+10 max, tanpa kurangi decay"},
      {"tier": 2, "cost": 4000,  "maxConditionBonus": 20, "decayReductionPercent": 5,  "label": "+20 max, -5% decay"},
      {"tier": 3, "cost": 7500,  "maxConditionBonus": 30, "decayReductionPercent": 10, "label": "+30 max, -10% decay"},
      {"tier": 4, "cost": 13000, "maxConditionBonus": 45, "decayReductionPercent": 20, "label": "+45 max, -20% decay"}
    ],
    "cannons": [
      {"tier": 1, "cost": 1200,  "combatBonusPercent": 5,  "ammoBonus": 1, "label": "+5% peluang menang, +1 amunisi meriam"},
      {"tier": 2, "cost": 3000,  "combatBonusPercent": 10, "ammoBonus": 2, "label": "+10% peluang menang, +2 amunisi meriam"},
      {"tier": 3, "cost": 6000,  "combatBonusPercent": 15, "ammoBonus": 3, "label": "+15% peluang menang, +3 amunisi meriam"},
      {"tier": 4, "cost": 11000, "combatBonusPercent": 20, "ammoBonus": 4, "label": "+20% peluang menang, +4 amunisi meriam"}
    ]
  }'::jsonb
$$;

create or replace function game.voy_groups() returns text[]
language sql immutable as $$ select array['speed', 'cargo', 'condition', 'cannons'] $$;

-- SHIP_ACCUMULATING_FIELDS
create or replace function game.voy_accum_field(p_group text) returns text
language sql immutable as $$
  select case p_group when 'cargo' then 'cargoBonus' when 'condition' then 'maxConditionBonus' else null end
$$;

-- SHIP_LEVEL_MULT (index 1-based)
create or replace function game.voy_level_mult(p_level int) returns numeric
language sql immutable as $$
  select (array[1, 2, 3.5, 5, 7.5]::numeric[])[greatest(1, least(5, p_level))]
$$;

create or replace function game.voy_roman(n int) returns text
language sql immutable as $$
  select coalesce((array['I', 'II', 'III', 'IV', 'V'])[n], n::text)
$$;

-- romanNumeral_ (tier 0-4)
create or replace function game.voy_tier_roman(n int) returns text
language sql immutable as $$
  select case n when 0 then '0' when 1 then 'I' when 2 then 'II' when 3 then 'III' when 4 then 'IV' else n::text end
$$;

-- formatLevelTierLabel_
create or replace function game.voy_level_tier_label(p_level int, p_tier int) returns text
language sql immutable as $$
  select 'Level ' || coalesce((array['I', 'II', 'III', 'IV', 'V'])[p_level], 'undefined') || ' &middot; Tier ' || game.voy_tier_roman(p_tier)
$$;

-- normalizeGroupState_
create or replace function game.voy_normalize_group(p_group text, p_raw jsonb) returns jsonb
language plpgsql immutable as $$
declare
  v_level numeric; v_tier numeric; v_acc numeric; v_field text; v_old int; v_entry jsonb;
begin
  if p_raw is not null and jsonb_typeof(p_raw) = 'object' then
    v_tier := game.voy_num(p_raw -> 'tier');
    v_level := game.voy_num(p_raw -> 'level');
    if v_level = 0 then v_level := case when v_tier > 0 then 1 else 0 end; end if;
    v_acc := game.voy_num(p_raw -> 'accumulated');
    return jsonb_build_object('level', v_level, 'tier', v_tier, 'accumulated', v_acc);
  end if;
  -- Format lama: angka polos = tier di Level I
  v_old := coalesce(floor(game.voy_num(p_raw))::int, 0);
  v_acc := 0;
  v_field := game.voy_accum_field(p_group);
  if v_field is not null and v_old between 1 and 4 then
    v_entry := game.voy_catalogs() -> p_group -> (v_old - 1);
    v_acc := game.voy_num(v_entry -> v_field);
  end if;
  return jsonb_build_object('level', case when v_old > 0 then 1 else 0 end, 'tier', v_old, 'accumulated', v_acc);
end $$;

-- ShipUpgradeService.getPlayerUpgrades
create or replace function game.voy_player_upgrades(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare raw jsonb; g text; out jsonb := '{}'::jsonb;
begin
  select ship_upgrades into raw from game.players where player_id = p_pid;
  if raw is null or jsonb_typeof(raw) <> 'object' then raw := '{}'::jsonb; end if;
  foreach g in array game.voy_groups() loop
    out := out || jsonb_build_object(g, game.voy_normalize_group(g, raw -> g));
  end loop;
  return out;
end $$;

create or replace function game.voy_abs_step(p_state jsonb) returns int
language sql immutable as $$
  select case when game.voy_num(p_state -> 'level') < 1 or game.voy_num(p_state -> 'tier') < 1 then 0
    else ((game.voy_num(p_state -> 'level') - 1) * 4 + game.voy_num(p_state -> 'tier'))::int end
$$;

create or replace function game.voy_speed_mult_for_step(s int) returns numeric
language sql immutable as $$
  -- Tide v22: tiap langkah (1..20) selalu mempercepat; 0.24 (= 25 dtk pulau terdekat) baru di Level V Tier IV.
  select case when s <= 0 then 1 when s <= 4 then (array[0.80, 0.65, 0.50, 0.40]::numeric[])[s]
    else greatest(0.24, 0.40 - 0.01 * (s - 4)) end
$$;

create or replace function game.voy_decay_red_for_step(s int) returns numeric
language sql immutable as $$
  select case when s <= 0 then 0 when s <= 4 then (array[0, 5, 10, 20]::numeric[])[s]
    else least(50, 20 + 2 * (s - 4)) end
$$;

create or replace function game.voy_combat_bonus_for_step(s int) returns numeric
language sql immutable as $$
  select case when s <= 0 then 0 when s <= 4 then (array[5, 10, 15, 20]::numeric[])[s]
    else least(60, 20 + 2 * (s - 4)) end
$$;

create or replace function game.voy_ammo_bonus_for_step(s int) returns numeric
language sql immutable as $$
  select case when s <= 0 then 0 when s <= 4 then (array[1, 2, 3, 4]::numeric[])[s]
    else 4 + floor((s - 4) / 2.0) end
$$;

-- ShipUpgradeService.getEffectiveShipStats
create or replace function game.voy_effective_stats(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare u jsonb;
begin
  u := game.voy_player_upgrades(p_pid);
  return jsonb_build_object(
    'upgrades', u,
    'speedMultiplier', game.voy_speed_mult_for_step(game.voy_abs_step(u -> 'speed')),
    'cargoBonus', game.voy_num(u -> 'cargo' -> 'accumulated'),
    'maxConditionBonus', game.voy_num(u -> 'condition' -> 'accumulated'),
    'decayReductionPercent', game.voy_decay_red_for_step(game.voy_abs_step(u -> 'condition')),
    'cannonBonusPercent', game.voy_combat_bonus_for_step(game.voy_abs_step(u -> 'cannons')),
    'cannonAmmoBonus', game.voy_ammo_bonus_for_step(game.voy_abs_step(u -> 'cannons'))
  );
end $$;

-- nextPurchaseSlot_
create or replace function game.voy_next_slot(p_state jsonb) returns jsonb
language plpgsql immutable as $$
declare lv int := coalesce(game.voy_num(p_state -> 'level'), 0)::int; tr int := coalesce(game.voy_num(p_state -> 'tier'), 0)::int;
  nt int; nl int;
begin
  if lv = 0 then return jsonb_build_object('maxed', false, 'nextLevel', 1, 'nextTier', 1); end if;
  if lv >= 5 and tr >= 4 then return jsonb_build_object('maxed', true); end if;
  nt := tr + 1; nl := lv;
  if nt > 4 then nt := 1; nl := lv + 1; end if;
  return jsonb_build_object('maxed', false, 'nextLevel', nl, 'nextTier', nt);
end $$;

-- Tide v22: Tier kapal = rata-rata Level keempat grup upgrade (dibulatkan ke bawah, 1..5).
-- Black Pearl (kapal legenda) selalu Tier V.
create or replace function game.ship_level_sum(p_up jsonb) returns int
language sql immutable as $$
  select coalesce(game.voy_num(p_up -> 'speed' -> 'level'), 0)::int + coalesce(game.voy_num(p_up -> 'cargo' -> 'level'), 0)::int
       + coalesce(game.voy_num(p_up -> 'condition' -> 'level'), 0)::int + coalesce(game.voy_num(p_up -> 'cannons' -> 'level'), 0)::int
$$;
create or replace function game.ship_tier_num(p_pid uuid) returns int
language sql stable as $$
  select case when game.ship_legend(p_pid) = 'pearl' then 5
    else greatest(1, least(5, floor(game.ship_level_sum(game.voy_player_upgrades(p_pid)) / 4.0)))::int end
$$;

-- ---------------------------------------------------------------------
-- ShipService.getShip  (kontrak game.ship_json)
-- ---------------------------------------------------------------------
create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.ships; e jsonb; book_bonus int; cargo_bonus numeric; eff_max numeric; cond numeric; tn int; lsum int; leg text;
begin
  select * into s from game.ships where player_id = p_pid;
  if not found then return null; end if;
  leg := game.ship_legend(p_pid);
  book_bonus := case when coalesce(game.has_effect(p_pid, 'cargo_bonus_10'), false) then 10 else 0 end;
  e := game.voy_effective_stats(p_pid);
  cargo_bonus := book_bonus + (e ->> 'cargoBonus')::numeric;
  eff_max := 100 + (e ->> 'maxConditionBonus')::numeric
    + case when coalesce(game.has_effect(p_pid, 'regal_hull'), false) then 50 else 0 end;
  cond := least(coalesce(s.condition, eff_max), eff_max);
  lsum := game.ship_level_sum(e -> 'upgrades');
  tn := case when leg = 'pearl' then 5 else greatest(1, least(5, floor(lsum / 4.0)))::int end;
  return jsonb_build_object(
    'ShipName', s.ship_name, 'Tier', case when leg = 'pearl' then s.tier else game.voy_roman(tn) end,
    'TierNum', tn, 'UpgradeLevelSum', lsum, 'Hull', s.hull, 'MaxHull', s.max_hull,
    'Cargo', s.cargo, 'Speed', s.speed + case when coalesce(game.has_effect(p_pid, 'ship_speed_5'), false) then 5 else 0 end
             + case when coalesce(game.has_effect(p_pid, 'regal_engine'), false) then 10 else 0 end,
    'Combat', s.combat, 'Armor', s.armor, 'Navigation', s.navigation,
    'Condition', cond, 'ConditionDecayPerSail', s.condition_decay_per_sail, 'MaxCondition', s.max_condition,
    'DamageThreshold', s.damage_threshold,
    'CargoBonus', cargo_bonus,
    'EffectiveCargo', s.cargo + cargo_bonus,
    'SpeedMultiplier', e -> 'speedMultiplier',
    'CannonBonusPercent', e -> 'cannonBonusPercent',
    'MaxCannonAmmo', game.cfg_num('CombatBaseAmmo', 3) + (e ->> 'cannonAmmoBonus')::numeric,
    'ShipUpgrades', e -> 'upgrades',
    'EffectiveMaxCondition', eff_max,
    'ConditionPct', case when eff_max > 0 then game.voy_round(cond / eff_max * 100) else 100 end,
    'DecayReductionPercent', e -> 'decayReductionPercent',
    'Legend', leg
  );
end $$;

create or replace function game.effective_cargo(p_pid uuid) returns int
language plpgsql stable as $$
declare c int; bonus numeric;
begin
  select cargo into c from game.ships where player_id = p_pid;
  if c is null then return 0; end if;
  bonus := case when coalesce(game.has_effect(p_pid, 'cargo_bonus_10'), false) then 10 else 0 end
    + (game.voy_effective_stats(p_pid) ->> 'cargoBonus')::numeric;
  return (c + bonus)::int;
end $$;

-- ShipUpgradeService.applyConditionDelta (clamp 0..max efektif, dibulatkan)
create or replace function game.apply_condition_delta(p_pid uuid, p_delta numeric) returns numeric
language plpgsql as $$
declare cur numeric; mx numeric; nxt numeric;
begin
  select condition into cur from game.ships where player_id = p_pid for update;
  if not found then return null; end if;
  mx := 100 + (game.voy_effective_stats(p_pid) ->> 'maxConditionBonus')::numeric;
  cur := coalesce(cur, mx);
  nxt := game.voy_round(greatest(0, least(mx, cur + coalesce(p_delta, 0))));
  update game.ships set condition = nxt where player_id = p_pid;
  return nxt;
end $$;

-- getConditionDecayForVoyage
create or replace function game.voy_decay_for_voyage(p_pid uuid) returns numeric
language plpgsql stable as $$
declare frac numeric;
begin
  select condition_decay_per_sail into frac from game.ships where player_id = p_pid;
  if not found then return 0; end if;
  frac := coalesce(frac, 0.03);
  return frac * 100 * (1 - (game.voy_effective_stats(p_pid) ->> 'decayReductionPercent')::numeric / 100);
end $$;

create or replace function game.voy_damage_threshold(p_pid uuid) returns numeric
language sql stable as $$ select coalesce((select damage_threshold from game.ships where player_id = p_pid), 45) $$;

-- getRepairQuote
create or replace function game.voy_repair_quote(p_pid uuid, p_city text) returns jsonb
language plpgsql stable as $$
declare s game.ships; mx numeric; cur numeric; missing numeric; rate numeric; cost numeric;
begin
  select * into s from game.ships where player_id = p_pid;
  if not found then raise exception 'Kapal tidak ditemukan.'; end if;
  mx := 100 + (game.voy_effective_stats(p_pid) ->> 'maxConditionBonus')::numeric;
  cur := least(coalesce(s.condition, mx), mx);
  missing := greatest(0, mx - cur);
  select repair_cost_rate into rate from game.cities where city_id = p_city;
  if rate is null or rate = 0 then rate := 1; end if;
  cost := game.voy_round(missing * game.cfg_num('ShipRepairBaseCostPerPoint', 15) * rate);
  return jsonb_build_object('currentCondition', game.voy_round(cur), 'maxCondition', mx,
    'missing', game.voy_round(missing), 'cost', cost);
end $$;

-- Tide v22: efek nyata sebuah langkah upgrade (angka sekarang -> sesudah), dari rumus yang benar-benar dipakai.
create or replace function game.voy_effect_line(p_pid uuid, p_group text, p_step int, p_next int, p_inc numeric) returns text
language plpgsql stable as $$
declare sh jsonb; r record; spd jsonb; a int; b int; c int; d int; am0 numeric; am1 numeric; base_ammo numeric;
begin
  sh := coalesce(game.ship_json(p_pid), '{}'::jsonb);
  if p_group = 'speed' then
    if sh ->> 'Legend' = 'pearl' then return 'Black Pearl selalu 15 dtk ke mana pun - upgrade Speed berlaku untuk kapalmu sendiri'; end if;
    select * into r from game.voy_dist_range();
    spd := coalesce(sh -> 'Speed', '50'::jsonb);
    a := game.voy_travel_seconds(r.dmin, jsonb_build_object('Speed', spd, 'SpeedMultiplier', game.voy_speed_mult_for_step(p_step)));
    c := game.voy_travel_seconds(r.dmax, jsonb_build_object('Speed', spd, 'SpeedMultiplier', game.voy_speed_mult_for_step(p_step)));
    if p_next is null then return 'Pulau terdekat ' || a || ' dtk, terjauh ' || c || ' dtk'; end if;
    b := game.voy_travel_seconds(r.dmin, jsonb_build_object('Speed', spd, 'SpeedMultiplier', game.voy_speed_mult_for_step(p_next)));
    d := game.voy_travel_seconds(r.dmax, jsonb_build_object('Speed', spd, 'SpeedMultiplier', game.voy_speed_mult_for_step(p_next)));
    return 'Pulau terdekat ' || a || ' &rarr; ' || b || ' dtk, terjauh ' || c || ' &rarr; ' || d || ' dtk';
  elsif p_group = 'cargo' then
    if p_next is null then return 'Kapasitas ' || coalesce(sh ->> 'EffectiveCargo', '?'); end if;
    return 'Kapasitas ' || coalesce(sh ->> 'EffectiveCargo', '?') || ' &rarr; ' || (game.voy_num(sh -> 'EffectiveCargo') + p_inc);
  elsif p_group = 'condition' then
    if p_next is null then return 'Kondisi maks ' || coalesce(sh ->> 'EffectiveMaxCondition', '?') || ', aus per layar -' || game.voy_decay_red_for_step(p_step) || '%'; end if;
    return 'Kondisi maks ' || coalesce(sh ->> 'EffectiveMaxCondition', '?') || ' &rarr; ' || (game.voy_num(sh -> 'EffectiveMaxCondition') + p_inc) ||
      ', aus per layar -' || game.voy_decay_red_for_step(p_step) || '% &rarr; -' || game.voy_decay_red_for_step(p_next) || '%';
  else
    base_ammo := game.cfg_num('CombatBaseAmmo', 3);
    am0 := base_ammo + game.voy_ammo_bonus_for_step(p_step);
    if p_next is null then return 'Peluang menang +' || game.voy_combat_bonus_for_step(p_step) || '%, amunisi ' || am0; end if;
    am1 := base_ammo + game.voy_ammo_bonus_for_step(p_next);
    return 'Peluang menang +' || game.voy_combat_bonus_for_step(p_step) || '% &rarr; +' || game.voy_combat_bonus_for_step(p_next) || '%, amunisi ' ||
      am0 || case when am1 <> am0 then ' &rarr; ' || am1 else ' (tetap)' end;
  end if;
end $$;

-- getAffordableUpgrades
create or replace function game.voy_affordable(p_pid uuid, p_gold bigint) returns jsonb
language plpgsql stable as $$
declare u jsonb; g text; st jsonb; slot jsonb; entry jsonb; mult numeric; cost numeric; out jsonb := '{}'::jsonb;
  lv int; tr int; nl int; nt int; fld text; inc numeric; stp int;
begin
  u := game.voy_player_upgrades(p_pid);
  foreach g in array game.voy_groups() loop
    st := u -> g;
    lv := game.voy_num(st -> 'level')::int; tr := game.voy_num(st -> 'tier')::int;
    stp := game.voy_abs_step(st);
    slot := game.voy_next_slot(st);
    if (slot ->> 'maxed')::boolean then
      out := out || jsonb_build_object(g, jsonb_build_object('maxed', true, 'currentLevel', st -> 'level',
        'currentTier', st -> 'tier', 'currentLabel', game.voy_level_tier_label(lv, tr),
        'effect', game.voy_effect_line(p_pid, g, stp, null, 0)));
      continue;
    end if;
    nl := (slot ->> 'nextLevel')::int; nt := (slot ->> 'nextTier')::int;
    entry := game.voy_catalogs() -> g -> (nt - 1);
    mult := game.voy_level_mult(nl);
    cost := game.voy_round((entry ->> 'cost')::numeric * mult);
    fld := game.voy_accum_field(g);
    inc := case when fld is not null then game.voy_round((entry ->> fld)::numeric * mult) else 0 end;
    out := out || jsonb_build_object(g, jsonb_build_object(
      'maxed', false,
      'currentLevel', st -> 'level',
      'currentTier', st -> 'tier',
      'currentLabel', case when tr > 0 then game.voy_level_tier_label(lv, tr) else 'Belum di-upgrade' end,
      'nextLevel', nl,
      'nextTier', nt,
      'nextLabel', game.voy_level_tier_label(nl, nt),
      'cost', cost,
      'label', (entry ->> 'label') || case when nl > 1 then ' (skala Level ' || game.voy_roman(nl) || ')' else '' end,
      'effect', game.voy_effect_line(p_pid, g, stp, (nl - 1) * 4 + nt, inc),
      'affordable', p_gold >= cost));
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- WorldEventService
-- ---------------------------------------------------------------------
create or replace function game.city_event(p_city text) returns jsonb
language plpgsql stable as $$
declare e game.city_events;
begin
  select * into e from game.city_events
   where city_id = p_city and expires_game_day >= game.game_day()
   order by id asc limit 1;
  if not found then return null; end if;
  return jsonb_build_object('cityId', e.city_id, 'eventType', e.event_type, 'label', e.label,
    'message', e.message, 'priceMultiplierPercent', coalesce(e.price_pct, 0),
    'rewardMultiplierPercent', coalesce(e.reward_pct, 0), 'expiresGameDay', e.expires_game_day);
end $$;

-- maybeRollCityEvent_
create or replace function game.voy_maybe_roll_city_event(p_city text) returns void
language plpgsql as $$
declare chance numeric; roll numeric; t text; lbl text; msg text; price int := 0; reward int := 0;
  min_d int; max_d int; dur int;
begin
  if game.city_event(p_city) is not null then return; end if;
  chance := game.cfg_num('WorldEventRollChancePercent', 10);
  if random() * 100 >= chance then return; end if;
  -- WORLD_EVENT_TYPES: 4 jenis, bobot masing-masing 25 (total 100)
  roll := random() * 100;
  if roll <= 25 then
    t := 'storm_surge'; lbl := 'Gelombang Badai';
    msg := 'Badai musiman mengganggu jalur pasokan - harga di pasar melonjak sementara.';
    price := 15 + floor(random() * 11);
  elsif roll <= 50 then
    t := 'harvest_bounty'; lbl := 'Panen Melimpah';
    msg := 'Panen melimpah membanjiri pasar - harga turun sementara, saat yang tepat untuk berbelanja.';
    price := -(15 + floor(random() * 11));
  elsif roll <= 75 then
    t := 'festival'; lbl := 'Festival Kota';
    msg := 'Kota sedang berpesta - gubernur murah hati memberi upah lebih besar untuk misi.';
    reward := 20 + floor(random() * 21);
  else
    t := 'unrest'; lbl := 'Kerusuhan Kecil';
    msg := 'Kerusuhan kecil melanda kota - aktivitas dagang & misi lesu untuk sementara.';
    reward := -(15 + floor(random() * 16));
  end if;
  min_d := game.cfg_num('WorldEventMinDurationDays', 2)::int;
  max_d := game.cfg_num('WorldEventMaxDurationDays', 5)::int;
  dur := min_d + floor(random() * (max_d - min_d + 1))::int;
  insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day)
  values (p_city, t, lbl, msg, price, reward, game.game_day() + dur);
end $$;

-- ---------------------------------------------------------------------
-- LocationService
-- ---------------------------------------------------------------------
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

create or replace function game.voy_map_distance(a text, b text) returns double precision
language sql stable as $$
  select sqrt(power((ca.map_x - cb.map_x)::double precision, 2) + power((ca.map_y - cb.map_y)::double precision, 2))
  from game.cities ca, game.cities cb where ca.city_id = a and cb.city_id = b
$$;

-- computeTravelMinutes_
create or replace function game.voy_travel_minutes(p_distance double precision, p_ship jsonb) returns int
language plpgsql stable as $$
declare mpu double precision; min_t double precision; base_speed double precision; spd double precision;
  factor double precision; base_min double precision; mult double precision;
begin
  mpu := game.cfg_num('TravelMinutesPerDistanceUnit', 0.25);
  min_t := game.cfg_num('MinTravelMinutes', 5);
  base_speed := game.cfg_num('BaselineShipSpeed', 50);
  spd := game.voy_num(p_ship -> 'Speed');
  if spd = 0 then spd := base_speed; end if;
  factor := least(2.5, greatest(0.5, spd / nullif(base_speed, 0)));
  base_min := (p_distance * mpu) / factor;
  mult := game.voy_num(p_ship -> 'SpeedMultiplier');
  if mult = 0 then mult := 1; end if;
  return greatest(min_t, floor(base_min * mult + 0.5))::int;
end $$;

-- Lama perjalanan dalam DETIK (lihat voy_travel_seconds di bawah).
create or replace function game.voy_dist_range(out dmin double precision, out dmax double precision)
language sql stable as $$
  select min(game.voy_map_distance(a.city_id, b.city_id)), max(game.voy_map_distance(a.city_id, b.city_id))
  from game.cities a join game.cities b on a.city_id < b.city_id
$$;

create or replace function game.voy_travel_seconds(p_distance double precision, p_ship jsonb) returns int
language plpgsql stable as $$
-- Tide v20: kapal standar 120 dtk (pulau terdekat) .. 240 dtk (terjauh).
-- Upgrade Speed / stat Speed memangkas SELURUH waktu tempuh secara bertahap sampai
-- batas tercepat 25 dtk untuk pulau terdekat (pengali layar 0.24 = upgrade tertinggi).
-- Black Pearl (kapal legenda TooGood): 15 dtk ke mana pun.
-- Atur lewat game.config: TravelMinSeconds, TravelMaxSeconds, TravelFastestSeconds, TravelLegendSeconds.
declare lo double precision; hi double precision; r record; frac double precision; base_t double precision;
  base_speed double precision; spd double precision; mult double precision; eff double precision;
  fast double precision; floor_mult constant double precision := 0.24; f double precision;
begin
  if coalesce(p_ship ->> 'Legend', '') = 'pearl' then
    return greatest(5, game.cfg_num('TravelLegendSeconds', 15))::int;
  end if;
  lo := greatest(10, game.cfg_num('TravelMinSeconds', 120));
  hi := greatest(lo, game.cfg_num('TravelMaxSeconds', 240));
  fast := least(lo, greatest(5, game.cfg_num('TravelFastestSeconds', 25)));
  select * into r from game.voy_dist_range();
  frac := case when r.dmax > r.dmin then least(1, greatest(0, (p_distance - r.dmin) / (r.dmax - r.dmin))) else 0 end;
  base_t := lo + (hi - lo) * frac;
  base_speed := greatest(1, game.cfg_num('BaselineShipSpeed', 50));
  spd := coalesce(nullif(game.voy_num(p_ship -> 'Speed'), 0), base_speed);
  mult := coalesce(nullif(game.voy_num(p_ship -> 'SpeedMultiplier'), 0), 1);
  -- Tide v22: stat Speed memperkecil jarak ke batas tercepat (bukan mengalikan), jadi
  -- setiap upgrade Speed tetap terasa sampai Level V Tier IV; batas 25 dtk hanya di upgrade tertinggi.
  mult := least(1, greatest(floor_mult, mult));
  eff := least(1, greatest(floor_mult, floor_mult + (mult - floor_mult) * base_speed / spd));
  -- eff 1 -> waktu penuh; eff 0.24 -> fast/lo (25/120)
  f := fast / lo + (1 - fast / lo) * (eff - floor_mult) / (1 - floor_mult);
  return greatest(1, round(base_t * f))::int;
end $$;

-- getVoyageState
create or replace function game.voyage_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare l game.player_location; total_ms numeric; prog numeric;
begin
  select * into l from game.player_location where player_id = p_pid;
  if not found or coalesce(l.destination_city_id, '') = '' then
    return jsonb_build_object('inTransit', false);
  end if;
  total_ms := greatest(1, extract(epoch from (l.arrive_at - l.depart_at)) * 1000);
  prog := least(1, greatest(0, extract(epoch from (now() - l.depart_at)) * 1000 / total_ms));
  return jsonb_build_object(
    'inTransit', true,
    'originCityId', l.city_id,
    'destinationCityId', l.destination_city_id,
    'departAt', game.iso(l.depart_at),
    'arriveAt', game.iso(l.arrive_at),
    'progress', prog::double precision,
    'etaSeconds', greatest(0, game.voy_round(extract(epoch from (l.arrive_at - now()))::numeric)),
    'encounterPending', l.pending_encounter is not null and jsonb_typeof(l.pending_encounter) = 'object',
    'encounter', case when jsonb_typeof(l.pending_encounter) = 'object' then l.pending_encounter else null end
  );
end $$;

-- rollVoyageEvent_
create or replace function game.voy_roll_voyage_event() returns jsonb
language plpgsql volatile as $$
declare roll double precision := random(); amt int;
begin
  if roll < 0.65 then
    return jsonb_build_object('type', 'calm', 'message', 'Laut tenang sepanjang perjalanan.', 'goldDelta', 0);
  elsif roll < 0.85 then
    amt := 10 + floor(random() * 40)::int;
    return jsonb_build_object('type', 'tailwind',
      'message', 'Angin buritan bersahabat - kru sempat memancing di sela pelayaran dan menjual hasilnya (+' || amt || ' gold).',
      'goldDelta', amt);
  else
    amt := 10 + floor(random() * 30)::int;
    return jsonb_build_object('type', 'storm',
      'message', 'Diterjang badai kecil - sedikit kerusakan ringan pada kapal (-' || amt || ' gold untuk perbaikan darurat).',
      'goldDelta', -amt);
  end if;
end $$;

-- completeArrival_ (dipanggil dengan baris player_location sudah terkunci)
create or replace function game.voy_complete_arrival(p_pid uuid, p_target text, p_combat_msg text) returns jsonb
language plpgsql as $$
declare v_name text; ev jsonb; gd bigint; decay numeric;
begin
  select name into v_name from game.cities where city_id = p_target;
  if v_name is null then raise exception 'Kota tujuan tidak dikenali: %', p_target; end if;

  if p_combat_msg is not null and p_combat_msg <> '' then
    ev := jsonb_build_object('message', p_combat_msg, 'goldDelta', 0);
  else
    ev := game.voy_roll_voyage_event();
  end if;

  update game.player_location
     set city_id = p_target, arrived_game_day = game.game_day(), destination_city_id = null,
         depart_at = null, arrive_at = null, pending_encounter = null
   where player_id = p_pid;

  gd := coalesce((ev ->> 'goldDelta')::bigint, 0);
  if gd <> 0 then
    update game.players set gold = greatest(0, gold + gd) where player_id = p_pid;
  end if;

  decay := game.voy_decay_for_voyage(p_pid);
  if decay > 0 then perform game.apply_condition_delta(p_pid, -decay); end if;

  begin
    perform game.voy_maybe_roll_city_event(p_target);
  exception when others then
    null; -- event dunia tidak boleh menggagalkan penyelesaian voyage
  end;

  perform game.log(p_pid, 'Made landfall at ' || v_name || '. ' || (ev ->> 'message'));
  return jsonb_build_object('cityId', p_target, 'event', ev, 'pendingCombat', false);
end $$;

-- CombatService.rollEncounterForArrival
create or replace function game.voy_roll_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare ship jsonb; stats jsonb; v_arch text; outlaw boolean; chance numeric;
  lvl_max int; lvl_min int; lvl int; names text[]; max_hp numeric; max_ammo numeric; boss jsonb;
begin
  -- Misi rahasia: bos menunggu di rute tertentu (lihat 0014)
  boss := game.quest_boss_encounter(p_pid, p_dest);
  if boss is not null then return boss; end if;
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
    'round', 1);
end $$;

-- LocationService.resolveArrivalIfDue (aman dari proses ganda: baris lokasi dikunci & dicek ulang)
create or replace function game.resolve_arrival_if_due(p_pid uuid) returns jsonb
language plpgsql as $$
declare l game.player_location; enc jsonb;
begin
  select * into l from game.player_location where player_id = p_pid;
  if not found or coalesce(l.destination_city_id, '') = '' then return null; end if;
  if jsonb_typeof(l.pending_encounter) = 'object' then
    return jsonb_build_object('cityId', null, 'event', null, 'pendingCombat', true, 'encounter', l.pending_encounter);
  end if;
  if now() < l.arrive_at then return null; end if;

  -- Kunci & baca ulang (pengganti LockService)
  select * into l from game.player_location where player_id = p_pid for update;
  if not found or coalesce(l.destination_city_id, '') = '' then return null; end if;
  if jsonb_typeof(l.pending_encounter) = 'object' then
    return jsonb_build_object('cityId', null, 'event', null, 'pendingCombat', true, 'encounter', l.pending_encounter);
  end if;
  if now() < l.arrive_at then return null; end if;

  enc := game.voy_roll_encounter(p_pid, l.destination_city_id);
  if enc is not null then
    update game.player_location set pending_encounter = enc where player_id = p_pid;
    perform game.log(p_pid, 'Sails spotted on the horizon - a pirate vessel closes in!');
    return jsonb_build_object('cityId', null, 'event', null, 'pendingCombat', true, 'encounter', enc);
  end if;

  return game.voy_complete_arrival(p_pid, l.destination_city_id, null);
end $$;

-- LocationService.finalizeArrival
create or replace function game.voy_finalize_arrival(p_pid uuid, p_target text, p_msg text) returns jsonb
language plpgsql as $$
declare l game.player_location;
begin
  select * into l from game.player_location where player_id = p_pid for update;
  if not found or coalesce(l.destination_city_id, '') = '' then
    raise exception 'Tidak ada voyage aktif untuk diselesaikan.';
  end if;
  return game.voy_complete_arrival(p_pid, p_target, p_msg);
end $$;

create or replace function game.voy_log_combat(p_pid uuid, p_level int, p_action text, p_result text, p_loot text) returns void
language sql as $$
  insert into game.combat_log(player_id, enemy_level, action, result, loot) values (p_pid, p_level, p_action, p_result, coalesce(p_loot, ''))
$$;

-- ---------------------------------------------------------------------
-- CombatService.resolveRound_ (murni kalkulasi, tidak mengubah tabel)
-- ---------------------------------------------------------------------
create or replace function game.voy_resolve_round(p_tactic text, enc jsonb, stats jsonb, ship jsonb, p_gold bigint) returns jsonb
language plpgsql volatile as $$
declare
  loot_pl numeric := game.cfg_num('CombatLootGoldPerLevel', 200);
  bribe_pl numeric := game.cfg_num('CombatBribeGoldPerLevel', 150);
  lvl numeric := game.voy_num(enc -> 'enemyLevel');
  max_hp numeric := game.voy_num(enc -> 'enemyMaxHp');
  hp numeric := game.voy_num(enc -> 'enemyHp');
  hp_pct numeric;
  ename text := coalesce(enc ->> 'enemyName', '');
  lbl text := 'Ronde ' || coalesce(enc ->> 'round', '1') || ': ';
  chance numeric; dmg numeric := 0; cd numeric := 0; msg text; cost numeric; toll numeric; big numeric; spd_bonus numeric;
begin
  hp_pct := case when max_hp > 0 then hp / max_hp else 0 end;

  if p_tactic = 'fire' then
    if game.voy_num(enc -> 'ammoRemaining') <= 0 then
      return jsonb_build_object('invalidAction', true, 'message', 'Meriam kosong - reload dulu sebelum menembak lagi.');
    end if;
    chance := 50 + game.voy_stat_bonus(stats -> 'Combat') * 2 + game.voy_num(ship -> 'CannonBonusPercent') - lvl * 5;
    chance := game.voy_clamp(chance, 10, 92);
    if random() * 100 < chance then
      dmg := game.voy_round(max_hp * (0.18 + random() * 0.14) * coalesce(nullif(game.voy_num(enc -> 'dmgTaken'), 0), 1));
      msg := lbl || 'tembakan meriam menghantam ' || ename || ' telak (-' || dmg || ' HP musuh).';
    else
      msg := lbl || 'tembakan meriam meleset dari ' || ename || '.';
    end if;
    if dmg < hp and random() < 0.55 then
      cd := -(4 + floor(random() * 6) + lvl);
      msg := msg || ' Balasan tembakan mereka merobek lambung kapal (' || cd || ' Condition).';
    end if;
    return jsonb_build_object('message', msg, 'enemyDamage', dmg, 'conditionDelta', cd, 'ammoDelta', -1);
  end if;

  if p_tactic = 'reload' then
    msg := lbl || 'kru buru-buru mengisi ulang meriam.';
    if random() < 0.75 then
      cd := -(6 + floor(random() * 8) + lvl);
      msg := msg || ' Sementara sibuk mengisi ulang, tembakan musuh menghantam kapal (' || cd || ' Condition).';
    else
      msg := msg || ' Untungnya musuh meleset kali ini.';
    end if;
    return jsonb_build_object('message', msg, 'reloadToMax', true, 'conditionDelta', cd);
  end if;

  if p_tactic = 'flee' then
    spd_bonus := (1 - coalesce(nullif(game.voy_num(ship -> 'SpeedMultiplier'), 0), 1)) * 100;
    chance := 45 + game.voy_stat_bonus(stats -> 'Sailing') * 2 + spd_bonus - lvl * 7;
    chance := game.voy_clamp(chance, 5, 95);
    if random() * 100 < chance then
      return jsonb_build_object('ends', true, 'endResult', 'fled',
        'message', lbl || 'manuver tajam & angin bersahabat membawa kapal lolos dari ' || ename || '.');
    end if;
    cd := -(5 + floor(random() * 7));
    return jsonb_build_object('conditionDelta', cd,
      'message', lbl || 'upaya kabur gagal - ' || ename || ' mengejar dan sempat menembak (' || cd || ' Condition).');
  end if;

  if p_tactic = 'bribe' then
    cost := greatest(50, game.voy_round(bribe_pl * lvl * greatest(0.25, hp_pct)));
    if p_gold < cost then
      return jsonb_build_object('insufficientGold', true, 'message', 'Gold tidak cukup untuk menyuap (butuh ' || cost || ' gold).');
    end if;
    return jsonb_build_object('ends', true, 'endResult', 'bribed', 'goldDelta', -cost,
      'message', lbl || cost || ' gold berpindah tangan, dan ' || ename || ' membiarkan kapal lewat tanpa perlawanan lebih lanjut.');
  end if;

  if p_tactic = 'negotiate' then
    chance := 40 + game.voy_stat_bonus(stats -> 'Negotiation') * 2.5 - lvl * 6;
    chance := game.voy_clamp(chance, 5, 90);
    if random() * 100 < chance then
      return jsonb_build_object('ends', true, 'endResult', 'negotiated',
        'message', lbl || 'parley tegang di atas air berakhir damai - ' || ename || ' membiarkan kapal berlalu.');
    end if;
    toll := least(game.voy_round(loot_pl * lvl * 0.3), p_gold);
    return jsonb_build_object('goldDelta', -toll,
      'message', lbl || 'parley belum membuahkan hasil - membayar upeti kecil ' || toll || ' gold sekadar menahan mereka sebentar.');
  end if;

  if p_tactic = 'ram' then
    chance := 35 + game.voy_num(ship -> 'Armor') / 3 + game.voy_stat_bonus(stats -> 'Combat') - lvl * 10;
    chance := game.voy_clamp(chance, 5, 90);
    if random() * 100 < chance then
      big := game.voy_round(loot_pl * lvl * 1.5);
      return jsonb_build_object('ends', true, 'endResult', 'won', 'goldDelta', big, 'lootNote', big || ' gold (ram)',
        'message', lbl || 'manuver menabrak nekat menghancurkan lambung ' || ename ||
          ' seketika - kru menjarah ' || big || ' gold dari puing sebelum tenggelam.');
    end if;
    cd := -(22 + floor(random() * 14));
    return jsonb_build_object('ends', true, 'endResult', 'lost', 'conditionDelta', cd,
      'message', lbl || 'tabrakan nekat gagal total - benturan yang seharusnya untuk musuh malah dirasakan kapal sendiri.');
  end if;

  raise exception 'Taktik tidak dikenali: %', p_tactic;
end $$;

-- Kehilangan cargo (komoditas saja) sebesar persen, dibulatkan ke atas per baris
create or replace function game.voy_lose_cargo(p_pid uuid, p_pct numeric) returns void
language plpgsql as $$
declare r record; lost int;
begin
  for r in select i.item_id, i.qty from game.inventory i join game.commodities c on c.id = i.item_id
            where i.player_id = p_pid and i.qty > 0 order by c.sort, i.item_id loop
    lost := ceil(r.qty * p_pct)::int;
    if lost > 0 then perform game.adjust_inventory(p_pid, r.item_id, -least(lost, r.qty)); end if;
  end loop;
end $$;

-- =====================================================================
-- ENDPOINT
-- =====================================================================

-- api_getShipState()
create or replace function public.api_getShipState(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  return jsonb_build_object('ship', game.ship_json(v_me.player_id), 'visual', game.ship_visual(v_me.player_id));
end $$;
select game.expose('api_getshipstate');

-- api_getShipUpgrades()
create or replace function public.api_getShipUpgrades(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  return jsonb_build_object(
    'current', game.voy_player_upgrades(v_me.player_id),
    'affordable', game.voy_affordable(v_me.player_id, v_me.gold),
    'allCatalogs', game.voy_catalogs());
end $$;
select game.expose('api_getshipupgrades');

-- api_shipUpgrade(group)
create or replace function public.api_shipUpgrade(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_group text := game.arg(a, 0);
  v_me game.players;
  u jsonb; st jsonb; slot jsonb; entry jsonb; mult numeric; cost bigint; field text; acc numeric;
  nl int; nt int; lt text;
begin
  if v_group is null or not (v_group = any (game.voy_groups())) then
    raise exception 'Grup upgrade tidak dikenali: %', coalesce(v_group, 'undefined');
  end if;
  v_me := game.me(true);
  u := game.voy_player_upgrades(v_me.player_id);
  st := u -> v_group;
  slot := game.voy_next_slot(st);
  if (slot ->> 'maxed')::boolean then
    raise exception 'Grup ini sudah Level V Tier IV (Legendary) - sudah maksimum mutlak.';
  end if;
  nl := (slot ->> 'nextLevel')::int; nt := (slot ->> 'nextTier')::int;
  entry := game.voy_catalogs() -> v_group -> (nt - 1);
  mult := game.voy_level_mult(nl);
  cost := game.voy_round((entry ->> 'cost')::numeric * mult)::bigint;

  if v_me.gold < cost then
    raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', cost, v_me.gold;
  end if;

  field := game.voy_accum_field(v_group);
  acc := game.voy_num(st -> 'accumulated');
  if field is not null then acc := acc + game.voy_round((entry ->> field)::numeric * mult); end if;

  u := jsonb_set(u, array[v_group], jsonb_build_object('level', nl, 'tier', nt, 'accumulated', acc));
  update game.players set ship_upgrades = u, gold = v_me.gold - cost where player_id = v_me.player_id;

  lt := game.voy_level_tier_label(nl, nt);
  perform game.log(v_me.player_id, 'Upgraded ship ' || v_group || ' to ' || replace(lt, '&middot;', '-') ||
    ' (' || (entry ->> 'label') || ') for ' || cost || ' gold.');

  return jsonb_build_object('success', true, 'group', v_group, 'newLevel', nl, 'newTier', nt,
    'newLevelTierLabel', lt, 'goldSpent', cost, 'effect', entry ->> 'label', 'newGold', v_me.gold - cost);
end $$;
select game.expose('api_shipupgrade');

-- api_getRepairQuote(cityId)
create or replace function public.api_getRepairQuote(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players := game.me();
begin
  return game.voy_repair_quote(v_me.player_id, v_city);
end $$;
select game.expose('api_getrepairquote');

-- api_repairShip(cityId)
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

-- api_getSailOptions()
create or replace function public.api_getSailOptions(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); l game.player_location; ship jsonb; out jsonb;
begin
  select * into l from game.player_location where player_id = v_me.player_id;
  if not found then raise exception 'Data lokasi pemain tidak ditemukan.'; end if;
  if not exists (select 1 from game.cities where city_id = l.city_id) then
    raise exception 'Kota asal tidak dikenali: %', l.city_id;
  end if;
  ship := coalesce(game.ship_json(v_me.player_id), '{}'::jsonb);
  select coalesce(jsonb_agg(jsonb_build_object(
      'cityId', c.city_id,
      'name', c.name,
      'distance', round((floor(d.dist * 10 + 0.5) / 10)::numeric, 1),
      'etaSeconds', game.voy_travel_seconds(d.dist, ship),
      'etaMinutes', round(game.voy_travel_seconds(d.dist, ship) / 60.0, 2),
      'eventLabel', ev ->> 'label',
      'eventType', ev ->> 'eventType') order by c.sort, c.city_id), '[]'::jsonb)
    into out
    from game.cities c
    cross join lateral (select game.voy_map_distance(l.city_id, c.city_id) as dist) d
    cross join lateral (select game.city_event(c.city_id) as ev) e
   where c.city_id <> l.city_id and game.city_open(v_me.player_id, c.city_id);
  return out;
end $$;
select game.expose('api_getsailoptions');

-- api_setSail(cityId)
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
  -- Selesaikan dulu voyage lama kalau sudah waktunya tiba
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
  secs := game.voy_travel_seconds(dist, coalesce(game.ship_json(v_me.player_id), '{}'::jsonb));
  t_depart := now();
  t_arrive := t_depart + make_interval(secs => secs);

  update game.player_location set destination_city_id = v_dest, depart_at = t_depart, arrive_at = t_arrive
   where player_id = v_me.player_id;

  perform game.log(v_me.player_id, 'Set sail from ' || v_origin_name || ' toward ' || v_dest_name || '.');

  begin
    perform game.mp_mark_sea(v_me.player_id, v_dest);
  exception when others then
    null; -- sama seperti try/catch di Code.gs
  end;
  perform game.quest_on_sail(v_me.player_id, l.city_id, v_dest);

  return jsonb_build_object('originCityId', l.city_id, 'destinationCityId', v_dest,
    'departAt', game.iso(t_depart), 'arriveAt', game.iso(t_arrive), 'travelSeconds', secs, 'travelRealMinutes', round(secs / 60.0, 2));
end $$;
select game.expose('api_setsail');

-- api_resolveCombat(tactic)
create or replace function public.api_resolveCombat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_tactic text := game.arg(a, 0);
  v_me game.players;
  pid uuid;
  l game.player_location;
  voyage jsonb; enc jsonb; stats jsonb; ship jsonb; r jsonb;
  new_cond numeric; hp numeric; ammo numeric; max_ammo numeric; lvl int;
  sinking boolean; defeated boolean; ends boolean; ended boolean;
  final_msg text; final_result text; target text; loot numeric; gold_now bigint; penalty bigint; eff_max numeric;
  drop_res jsonb; drop_note text := ''; loot_item jsonb := null; drop_name text; fin jsonb;
  is_boss boolean := false; boss_res jsonb := null; ad numeric; v_floor numeric;
begin
  if v_tactic is null or not (v_tactic = any (array['fire', 'reload', 'flee', 'bribe', 'negotiate', 'ram'])) then
    raise exception 'Taktik tidak dikenali: %', coalesce(v_tactic, 'undefined');
  end if;

  v_me := game.me(true);
  pid := v_me.player_id;
  select * into l from game.player_location where player_id = pid for update;
  voyage := game.voyage_state(pid);
  if not coalesce((voyage ->> 'inTransit')::boolean, false) or not coalesce((voyage ->> 'encounterPending')::boolean, false) then
    raise exception 'Tidak ada pertempuran yang sedang menunggu.';
  end if;

  enc := voyage -> 'encounter';
  stats := coalesce(game.stats_json(pid), '{}'::jsonb);
  ship := coalesce(game.ship_json(pid), '{}'::jsonb);
  lvl := game.voy_num(enc -> 'enemyLevel')::int;
  is_boss := coalesce(enc ->> 'boss', '') <> '';
  if is_boss and v_tactic in ('bribe', 'negotiate') then
    if enc ? 'noTalkMsg' then raise exception '%', enc ->> 'noTalkMsg'; end if;
    raise exception '% tertawa: "Suap? Runding? Aku tak butuh gold-mu!" - bos ini tidak bisa disuap atau diajak berunding.', enc ->> 'enemyName';
  end if;
  if v_tactic = 'ram' and coalesce((enc ->> 'noRam')::boolean, false) then
    raise exception '%', coalesce(enc ->> 'noRamMsg', 'Kapal sebesar itu tak mungkin ditabrak - lambungmu yang akan hancur duluan.');
  end if;

  -- Tide v18: mundur selalu berhasil bila armada sekutu menutupi (pertempuran perang)
  if v_tactic = 'flee' and coalesce((enc ->> 'retreatOk')::boolean, false) then
    r := jsonb_build_object('ends', true, 'endResult', 'fled',
      'message', 'Ronde ' || coalesce(enc ->> 'round', '1') || ': ' || coalesce(enc ->> 'retreatMsg', 'Armada sekutu menutupi manuvermu - kapal mundur dari pertempuran dengan selamat.'));
  else
    r := game.voy_resolve_round(v_tactic, enc, stats, ship, v_me.gold);
  end if;
  -- Tembakan armada sekutu tiap ronde yang belum berakhir
  if game.voy_num(enc -> 'allyDmg') > 0 and not coalesce((r ->> 'ends')::boolean, false)
     and not coalesce((r ->> 'insufficientGold')::boolean, false) and not coalesce((r ->> 'invalidAction')::boolean, false) then
    ad := game.voy_round(game.voy_num(enc -> 'allyDmg') * (0.8 + random() * 0.4));
    r := r || jsonb_build_object('enemyDamage', game.voy_num(r -> 'enemyDamage') + ad, 'allyDamage', ad,
      'message', (r ->> 'message') || ' ' || coalesce(enc ->> 'allyNote', 'Armada sekutu') || ' menghujani musuh (-' || ad || ' HP).');
  end if;

  -- Gold tidak cukup / meriam kosong: ronde tidak dikonsumsi
  if coalesce((r ->> 'insufficientGold')::boolean, false) or coalesce((r ->> 'invalidAction')::boolean, false) then
    raise exception '%', r ->> 'message';
  end if;

  if game.voy_num(r -> 'goldDelta') <> 0 then
    update game.players set gold = greatest(0, v_me.gold + game.voy_num(r -> 'goldDelta')::bigint) where player_id = pid;
  end if;

  new_cond := game.voy_num(ship -> 'Condition');
  if game.voy_num(r -> 'conditionDelta') <> 0 then
    new_cond := game.apply_condition_delta(pid, game.voy_num(r -> 'conditionDelta'));
  end if;

  hp := game.voy_num(enc -> 'enemyHp');
  if game.voy_num(r -> 'enemyDamage') <> 0 then
    hp := greatest(0, hp - game.voy_num(r -> 'enemyDamage'));
    enc := jsonb_set(enc, '{enemyHp}', to_jsonb(hp));
  end if;
  max_ammo := game.voy_num(enc -> 'maxAmmo');
  if coalesce((r ->> 'reloadToMax')::boolean, false) then
    enc := jsonb_set(enc, '{ammoRemaining}', to_jsonb(max_ammo));
  elsif game.voy_num(r -> 'ammoDelta') <> 0 then
    ammo := greatest(0, least(max_ammo, game.voy_num(enc -> 'ammoRemaining') + game.voy_num(r -> 'ammoDelta')));
    enc := jsonb_set(enc, '{ammoRemaining}', to_jsonb(ammo));
  end if;

  ends := coalesce((r ->> 'ends')::boolean, false);
  sinking := new_cond <= 0;
  v_floor := case when enc ? 'hpFloor' then game.voy_num(enc -> 'hpFloor') else 0 end;
  if v_floor > 0 and hp <= v_floor then hp := v_floor; enc := jsonb_set(enc, '{enemyHp}', to_jsonb(hp)); end if;
  defeated := not ends and hp <= v_floor;
  ended := ends or sinking or defeated;

  if not ended then
    enc := jsonb_set(enc, '{round}', to_jsonb(coalesce(nullif(game.voy_num(enc -> 'round'), 0), 1) + 1));
    update game.player_location set pending_encounter = enc where player_id = pid;
    perform game.voy_log_combat(pid, lvl, v_tactic, 'round', '');
    return jsonb_build_object('ongoing', true, 'message', r ->> 'message', 'encounter', enc,
      'newCondition', game.ship_json(pid) -> 'Condition',
      'newGold', (select gold from game.players where player_id = pid));
  end if;

  -- Pertempuran berakhir
  final_msg := r ->> 'message';
  final_result := coalesce(r ->> 'endResult', 'unknown');
  target := voyage ->> 'destinationCityId';

  if defeated then
    loot := case when is_boss then 0 else game.voy_round(game.cfg_num('CombatLootGoldPerLevel', 200) * lvl * (0.9 + random() * 0.3)) end;
    update game.players set gold = gold + loot::bigint where player_id = pid;
    final_msg := (r ->> 'message') || ' Tembakan itu ternyata mematikan - ' || (enc ->> 'enemyName') ||
      ' tenggelam dan kru menjarah ' || loot || ' gold dari puing kapal sebelum berlayar lagi.';
    final_result := 'won';
  end if;

  if sinking and coalesce((enc ->> 'softSink')::boolean, false) then
    -- Pertempuran perang: kapal ditarik mundur armada sekutu tanpa kehilangan muatan/gold
    eff_max := game.voy_num(game.ship_json(pid) -> 'EffectiveMaxCondition');
    perform game.apply_condition_delta(pid, eff_max * 0.25);
    target := voyage ->> 'originCityId';
    final_msg := coalesce(r ->> 'message', '') || ' Lambung kapalmu jebol di bawah gempuran ' || (enc ->> 'enemyName') ||
      '! Armada sekutu menarikmu keluar dari medan tempur - kapal selamat, tapi harus diperbaiki sebelum kembali bertempur.';
    final_result := 'sunk';
  elsif sinking then
    eff_max := game.voy_num(game.ship_json(pid) -> 'EffectiveMaxCondition');
    perform game.apply_condition_delta(pid, eff_max * 0.25);
    select gold into gold_now from game.players where player_id = pid;
    penalty := game.voy_round(gold_now * 0.15)::bigint;
    if penalty > 0 then update game.players set gold = gold_now - penalty where player_id = pid; end if;
    perform game.voy_lose_cargo(pid, 0.5);
    target := voyage ->> 'originCityId';
    final_msg := 'The ship went down under ' || (enc ->> 'enemyName') || '''s assault after ' || coalesce(enc ->> 'round', '1') ||
      ' rounds of fighting! A passing fisherman pulled the crew from the wreckage and towed you back, ' ||
      'but half the cargo and ' || penalty || ' gold were lost to the sea.';
    final_result := 'sunk';
  end if;

  -- Bos misi dikalahkan: hadiah khusus (menggantikan jarahan biasa & peta harta)
  if final_result = 'won' and is_boss then
    boss_res := game.quest_boss_defeated(pid);
    loot := coalesce(game.voy_num(boss_res -> 'gold'), 0) - greatest(0, game.voy_num(r -> 'goldDelta'));
    if loot <> 0 then update game.players set gold = gold + loot::bigint where player_id = pid; end if;
    final_msg := (r ->> 'message') || ' ' || coalesce(boss_res ->> 'message', '');
  -- Menang: peluang peta harta (peluang + pemberian item ditangani kontrak game.treasure_drop)
  elsif final_result = 'won' then
    perform game.quest_combat_won(pid);
    drop_res := game.treasure_drop(pid, lvl);
    if drop_res is not null and jsonb_typeof(drop_res) = 'object' then
      drop_name := coalesce(drop_res ->> 'name', drop_res ->> 'Name');
      drop_note := ' Among the wreckage, the crew salvages ' || coalesce(drop_name, 'a weathered map') || '!';
      final_msg := final_msg || drop_note;
      if drop_name is not null then
        loot_item := jsonb_build_object('itemId', coalesce(drop_res ->> 'itemId', drop_res ->> 'ItemId', drop_res ->> 'item_id', drop_res ->> 'id'),
          'name', drop_name);
      end if;
    end if;
  end if;

  -- Pertempuran perang: kapal kembali ke pelabuhan asal kecuali kemenangan terakhir
  if coalesce((enc ->> 'retreat')::boolean, false) and not coalesce((boss_res ->> 'arrive')::boolean, false) then
    target := voyage ->> 'originCityId';
  end if;
  perform game.quest_combat_end(pid, enc, final_result);
  fin := game.voy_finalize_arrival(pid, target, final_msg);
  perform game.voy_log_combat(pid, lvl, v_tactic, final_result, coalesce(r ->> 'lootNote', '') || drop_note);

  return jsonb_build_object(
    'ongoing', false,
    'success', final_result in ('won', 'fled', 'bribed', 'negotiated'),
    'result', final_result,
    'message', final_msg,
    'cityId', fin -> 'cityId',
    'newCondition', game.ship_json(pid) -> 'Condition',
    'newGold', (select gold from game.players where player_id = pid),
    'lootItem', loot_item,
    'boss', case when is_boss then enc ->> 'boss' else null end,
    'questItem', boss_res -> 'item',
    'questEvent', boss_res -> 'event');
end $$;
select game.expose('api_resolvecombat');


-- =====================================================================
-- TAMPILAN KAPAL: kustomisasi pemain + tahap visual dari upgrade
-- =====================================================================
alter table game.players add column if not exists ship_look jsonb;

-- Tampilan bawaan per arketipe (supaya kapal sudah beda walau belum dikustom)
create or replace function game.ship_default_look(p_arch text) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'hull', '#6b4226', 'trim', '#d4a84c', 'sail', '#f3e9d2',
    'flag', coalesce(jsonb_build_object('merchant', '#c9922f', 'navigator', '#2f7fa3', 'pirate', '#111111', 'explorer', '#3f8c3f',
      'gambler', '#8e3d8a', 'smuggler', '#4a4540', 'diplomat', '#f4ecd8', 'adventurer', '#4ea3c9') ->> p_arch, '#9b2d20'),
    'emblemColor', case when p_arch = 'diplomat' then '#9b2d20' else '#f3e9d2' end,
    'shape', case p_arch when 'pirate' then 'swallow' when 'navigator' then 'pennant' when 'gambler' then 'flame' else 'rect' end,
    'emblem', coalesce(jsonb_build_object('merchant', 'crest', 'navigator', 'star', 'pirate', 'skull', 'explorer', 'compass',
      'gambler', 'diamond', 'smuggler', 'crescent', 'diplomat', 'crest', 'adventurer', 'anchor') ->> p_arch, 'crest'))
$$;

-- { look, up:{speed,cargo,condition,cannons} (langkah 0..20), name }
create or replace function game.ship_visual(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare p game.players; u jsonb; v_name text;
begin
  select * into p from game.players where player_id = p_pid;
  if not found then return null; end if;
  u := game.voy_player_upgrades(p_pid);
  select ship_name into v_name from game.ships where player_id = p_pid;
  return jsonb_build_object(
    'look', game.ship_default_look(p.archetype) || coalesce(p.ship_look, '{}'::jsonb),
    'up', jsonb_build_object('speed', game.voy_abs_step(u -> 'speed'), 'cargo', game.voy_abs_step(u -> 'cargo'),
      'condition', game.voy_abs_step(u -> 'condition'), 'cannons', game.voy_abs_step(u -> 'cannons')),
    'name', coalesce(v_name, 'The Wandering Gull'),
    'legend', game.ship_legend(p_pid));
end $$;

-- Simpan tampilan kapal (gratis) + nama kapal. a = [look, shipName]
create or replace function public.api_saveShipLook(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true);
  v_in jsonb := coalesce(game.arg_json(a, 0), '{}'::jsonb);
  v_name text := btrim(regexp_replace(coalesce(game.arg(a, 1), ''), '\s+', ' ', 'g'));
  v_out jsonb := '{}'::jsonb; k text; v text;
begin
  if v_me.archetype = '' then raise exception 'Buat kapten dulu.'; end if;
  if game.ship_locked(v_me.player_id) is not null then raise exception '%', game.ship_locked(v_me.player_id); end if;
  if jsonb_typeof(v_in) <> 'object' then raise exception 'Data tampilan kapal tidak valid.'; end if;
  foreach k in array array['hull', 'trim', 'sail', 'flag', 'emblemColor'] loop
    v := lower(coalesce(v_in ->> k, ''));
    if v <> '' then
      if v !~ '^#[0-9a-f]{6}$' then raise exception 'Warna tidak valid: %', k; end if;
      v_out := v_out || jsonb_build_object(k, v);
    end if;
  end loop;
  v := coalesce(v_in ->> 'shape', '');
  if v <> '' then
    if v <> all (array['rect', 'swallow', 'pennant', 'long', 'flame']) then raise exception 'Bentuk bendera tidak dikenal.'; end if;
    v_out := v_out || jsonb_build_object('shape', v);
  end if;
  v := coalesce(v_in ->> 'emblem', '');
  if v <> '' then
    if v <> all (array['none', 'crest', 'star', 'anchor', 'skull', 'cross', 'crescent', 'diamond', 'compass']) then
      raise exception 'Lambang bendera tidak dikenal.';
    end if;
    v_out := v_out || jsonb_build_object('emblem', v);
  end if;
  if v_name <> '' then
    if char_length(v_name) < 3 or char_length(v_name) > 24 then raise exception 'Nama kapal 3-24 karakter.'; end if;
    if v_name !~ '^[[:alnum:] .''&-]+$' then raise exception 'Nama kapal hanya boleh huruf, angka, spasi, dan tanda . '' & -'; end if;
    update game.ships set ship_name = v_name where player_id = v_me.player_id;
  end if;
  update game.players set ship_look = v_out where player_id = v_me.player_id;
  begin perform game.mp_touch(v_me.player_id); exception when others then null; end;
  return jsonb_build_object('visual', game.ship_visual(v_me.player_id), 'ship', game.ship_json(v_me.player_id));
end $$;
select game.expose('api_saveshiplook');
