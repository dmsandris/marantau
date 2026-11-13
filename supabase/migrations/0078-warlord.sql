-- =====================================================================
-- 0078 · Saga 4 — WARLORD: tahap terakhir kapal pemain (TierNum 6)
--   Dibuka di Garasi Yaptob, Zentul, setelah langkah 27 (Cetak Biru Warlord).
--   Empat komponen terpisah; tiap grup harus sudah mentok (Level V Tier IV = langkah 20).
--     Mesin Jolt Warlord (speed)   : batas waktu tempuh 25 -> 20 detik (Black Pearl tetap 15)
--     Palka Warlord (cargo)        : kapasitas +15%
--     Lambung Warlord (condition)  : kondisi maks +20%, aus -10%
--     Meriam Warlord (cannons)     : +5% peluang menang, +1 amunisi
--   Harga: gold + Oli Hitam + satu bahan khusus per komponen.
--   Gigi Jaring & Rantai Biru jatuh dari menang Tembus Jaring / Sirkuit (batas simpan).
--   Pagar: HP Duel Lambung tetap dihitung Tier V. Tidak wajib untuk menamatkan quest.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('WarlordGold', '2500000'), ('WarlordOli', '10'), ('WarlordBahan', '6'), ('WarlordDropMax', '12')
on conflict (key) do nothing;

insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_mk_gigi',   'Gigi Jaring', 'quest', '{"cargoSize": 1, "desc": "Potongan mata rantai Jaring Biru yang patah saat kau menembusnya. Masih dingin."}', 0, null, 'quest', 160),
  ('qi_mk_rantai', 'Rantai Biru', 'quest', '{"cargoSize": 1, "desc": "Seuntai rantai biru yang ditarik dari dasar Selat Lurus. Catnya tidak mau hilang."}', 0, null, 'quest', 161)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects, sort = excluded.sort;

create table if not exists game.mk_warlord (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  grup      text not null,
  at        timestamptz not null default now(),
  primary key (player_id, grup)
);
alter table game.mk_warlord enable row level security;

create or replace function game.wl_set(p_pid uuid) returns text[]
language sql stable as $$ select coalesce(array(select grup from game.mk_warlord where player_id = p_pid order by grup), '{}'::text[]) $$;

create or replace function game.wl_has(p_pid uuid, p_grup text) returns boolean
language sql stable as $$ select exists (select 1 from game.mk_warlord where player_id = p_pid and grup = p_grup) $$;

create or replace function game.wl_buka(p_pid uuid) returns boolean
language sql stable as $$ select game.mk_step(p_pid) >= 27 $$;

create or replace function game.wl_bahan(p_grup text) returns text
language sql immutable as $$
  select case p_grup when 'speed' then 'qi_mk_gigi' when 'condition' then 'qi_mk_rantai'
                     when 'cargo' then 'besi' else 'mesiu' end
$$;

create or replace function game.wl_nama(p_grup text) returns text
language sql immutable as $$
  select case p_grup when 'speed' then 'Mesin Jolt Warlord' when 'cargo' then 'Palka Warlord'
                     when 'condition' then 'Lambung Warlord' else 'Meriam Warlord' end
$$;

-- Grup sudah mentok (Level V Tier IV)?
create or replace function game.wl_siap(p_pid uuid, p_grup text) returns boolean
language sql stable as $$ select game.voy_abs_step(game.voy_player_upgrades(p_pid) -> p_grup) >= 20 $$;

create or replace function game.wl_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare g text; out jsonb := '[]'::jsonb; v_bahan text; v_gold bigint; v_oli int; v_n int;
begin
  if p_pid is null or not game.wl_buka(p_pid) then return null; end if;
  v_gold := greatest(0, game.cfg_num('WarlordGold', 2500000))::bigint;
  v_oli := greatest(0, game.cfg_num('WarlordOli', 10))::int;
  v_n := greatest(0, game.cfg_num('WarlordBahan', 6))::int;
  foreach g in array array['speed', 'cargo', 'condition', 'cannons'] loop
    v_bahan := game.wl_bahan(g);
    out := out || jsonb_build_array(jsonb_build_object(
      'grup', g, 'nama', game.wl_nama(g), 'punya', game.wl_has(p_pid, g), 'siap', game.wl_siap(p_pid, g),
      'gold', v_gold, 'oli', v_oli, 'bahanId', v_bahan, 'bahanN', v_n,
      'bahanNama', coalesce((select name from game.commodities where id = v_bahan), (select name from game.item_catalog where item_id = v_bahan)),
      'punyaOli', game.item_qty(p_pid, 'oli_hitam'), 'punyaBahan', game.item_qty(p_pid, v_bahan)));
  end loop;
  return jsonb_build_object('buka', true, 'komponen', out, 'set', to_jsonb(game.wl_set(p_pid)),
    'penuh', array_length(game.wl_set(p_pid), 1) = 4);
exception when others then return null;
end $$;

-- ---------------------------------------------------------------------
-- Efek
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.voy_effective_stats_wl(uuid);
  alter function game.voy_effective_stats(uuid) rename to voy_effective_stats_wl;
  drop function if exists game.ship_json_wl(uuid);
  alter function game.ship_json(uuid) rename to ship_json_wl;
end $$;
revoke all on function game.voy_effective_stats_wl(uuid) from public, anon, authenticated;
revoke all on function game.ship_json_wl(uuid) from public, anon, authenticated;

create or replace function game.voy_effective_stats(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb; w text[]; v_cargo numeric;
begin
  j := game.voy_effective_stats_wl(p_pid);
  begin
    w := game.wl_set(p_pid);
    if array_length(w, 1) is null then return j; end if;
    if 'speed' = any (w) then j := j || jsonb_build_object('speedMultiplier', least(0.20, (j ->> 'speedMultiplier')::numeric)); end if;
    if 'cargo' = any (w) then
      select cargo into v_cargo from game.ships where player_id = p_pid;
      j := j || jsonb_build_object('cargoBonus', coalesce((j ->> 'cargoBonus')::numeric, 0) + round(coalesce(v_cargo, 0) * 0.15));
    end if;
    if 'condition' = any (w) then
      j := j || jsonb_build_object('maxConditionBonus', coalesce((j ->> 'maxConditionBonus')::numeric, 0) + 20,
        'decayReductionPercent', coalesce((j ->> 'decayReductionPercent')::numeric, 0) + 10);
    end if;
    if 'cannons' = any (w) then
      j := j || jsonb_build_object('cannonBonusPercent', coalesce((j ->> 'cannonBonusPercent')::numeric, 0) + 5,
        'cannonAmmoBonus', coalesce((j ->> 'cannonAmmoBonus')::numeric, 0) + 1);
    end if;
  exception when others then null;
  end;
  return j;
end $$;

-- TierNum 6 bila keempat komponen terpasang (HP Duel tetap dihitung Tier V, lihat di bawah).
create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb; w text[];
begin
  j := game.ship_json_wl(p_pid);
  if j is null then return j; end if;
  begin
    w := game.wl_set(p_pid);
    if array_length(w, 1) is not null then
      j := j || jsonb_build_object('Warlord', to_jsonb(w));
      if array_length(w, 1) = 4 and coalesce(j ->> 'Legend', '') <> 'pearl' then
        j := j || jsonb_build_object('TierNum', 6, 'Tier', 'VI');
      end if;
    end if;
  exception when others then null;
  end;
  return j;
end $$;

-- Duel Lambung: HP dihitung maksimal Tier V.
do $$
begin
  drop function if exists game.mp_fighter_wl(uuid);
  alter function game.mp_fighter(uuid) rename to mp_fighter_wl;
end $$;
create or replace function game.mp_fighter(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb; t int;
begin
  j := game.mp_fighter_wl(p_pid);
  if j is null then return j; end if;
  t := coalesce((j ->> 'tier')::int, 1);
  if t > 5 then
    j := j || jsonb_build_object('maxHp', coalesce((j ->> 'maxHp')::int, 0) - (t - 5) * 20);
  end if;
  return j;
end $$;

-- ---------------------------------------------------------------------
-- Bahan: Gigi Jaring (menang Tembus Jaring) & Rantai Biru (menang di Sirkuit)
-- ---------------------------------------------------------------------
create or replace function game.wl_drop(p_pid uuid, p_item text) returns int
language plpgsql as $$
declare v_max int := greatest(0, game.cfg_num('WarlordDropMax', 12))::int;
begin
  if not game.wl_buka(p_pid) then return 0; end if;
  if game.item_qty(p_pid, p_item) >= v_max then return 0; end if;
  if game.cargo_free(p_pid) < 1 then return 0; end if;
  perform game.item_adjust(p_pid, p_item, 1);
  return 1;
exception when others then return 0;
end $$;

do $$
begin
  drop function if exists game.trek_selesai_wl(uuid, uuid, jsonb, text);
  alter function game.trek_selesai(uuid, uuid, jsonb, text) rename to trek_selesai_wl;
end $$;
create or replace function game.trek_selesai(p_pid uuid, p_id uuid, p_log jsonb, p_kind text) returns jsonb
language plpgsql as $$
declare r jsonb; v_drop int := 0;
begin
  r := game.trek_selesai_wl(p_pid, p_id, p_log, p_kind);
  begin
    if coalesce((r ->> 'win')::boolean, false) then
      if p_kind = 'tembus' then v_drop := game.wl_drop(p_pid, 'qi_mk_gigi');
      elsif p_kind = 'sirkuit' then v_drop := game.wl_drop(p_pid, 'qi_mk_rantai');
      end if;
      if v_drop > 0 then
        r := r || jsonb_build_object('bahan', case when p_kind = 'tembus' then 'Gigi Jaring' else 'Rantai Biru' end);
      end if;
    end if;
  exception when others then null;
  end;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- api_warlord(['status'] | ['bangun', grup])
-- ---------------------------------------------------------------------
create or replace function public.api_warlord(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := lower(coalesce(game.arg(a, 0), 'status'));
  v_grup text := lower(coalesce(game.arg(a, 1), ''));
  v_gold bigint; v_oli int; v_n int; v_bahan text;
begin
  if v_act = 'status' then return jsonb_build_object('warlord', game.wl_state(v_pid)); end if;
  if v_act <> 'bangun' then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.wl_buka(v_pid) then raise exception 'Garasi itu masih terkunci, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  if game.current_city(v_pid) is distinct from 'zentul' then raise exception 'Hanya Yaptob yang bisa memasangnya, Kapten. Di Zentul.'; end if;
  if v_grup not in ('speed', 'cargo', 'condition', 'cannons') then raise exception 'Komponen tidak dikenali.'; end if;
  if game.wl_has(v_pid, v_grup) then raise exception '% sudah terpasang, Kapten.', game.wl_nama(v_grup); end if;
  if not game.wl_siap(v_pid, v_grup) then
    raise exception 'Grup itu belum mentok, Kapten. Yaptob cuma mau memasang di atas yang sudah terbaik (Level V Tier IV).';
  end if;

  v_gold := greatest(0, game.cfg_num('WarlordGold', 2500000))::bigint;
  v_oli := greatest(0, game.cfg_num('WarlordOli', 10))::int;
  v_n := greatest(0, game.cfg_num('WarlordBahan', 6))::int;
  v_bahan := game.wl_bahan(v_grup);
  if v_me.gold < v_gold then raise exception 'Butuh % gold, Kapten.', v_gold; end if;
  if game.item_qty(v_pid, 'oli_hitam') < v_oli then raise exception 'Butuh % Oli Hitam di palkamu, Kapten.', v_oli; end if;
  if game.item_qty(v_pid, v_bahan) < v_n then
    raise exception 'Butuh % %, Kapten.', v_n,
      coalesce((select name from game.commodities where id = v_bahan), (select name from game.item_catalog where item_id = v_bahan));
  end if;

  update game.players set gold = gold - v_gold where player_id = v_pid;
  perform game.item_adjust(v_pid, 'oli_hitam', -v_oli);
  perform game.item_adjust(v_pid, v_bahan, -v_n);
  insert into game.mk_warlord(player_id, grup) values (v_pid, v_grup) on conflict do nothing;
  perform game.log(v_pid, 'Warlord: ' || game.wl_nama(v_grup) || ' terpasang.');

  return jsonb_build_object('warlord', game.wl_state(v_pid), 'grup', v_grup, 'nama', game.wl_nama(v_grup),
    'newGold', (select gold from game.players where player_id = v_pid), 'ship', game.ship_json(v_pid));
end $$;
select game.expose('api_warlord');

-- Trektrek-an: lambung Warlord (lengkap) seasyik Jolt Penuh walau mesin pinjaman sudah dilepas.
create or replace function game.trek_kapal(p_pid uuid) returns text
language sql stable as $$
  select case
    when array_length(game.wl_set(p_pid), 1) = 4 then 'warlord'
    when not game.mk_mulai(p_pid) then 'jolt'
    when game.mk_step(p_pid) >= 27 then 'penuh'
    when game.mk_step(p_pid) >= 15 then 'jolt'
    else 'tanpa'
  end
$$;
