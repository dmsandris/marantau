-- =====================================================================
-- 0080 · Saga 4 batch 6a — SIRKUIT HARIAN, TANTANGAN YAPTOB, SANG PACU SELAT
--   Menang pertama melawan tiap lawan, sekali per hari game: Oli Hitam + gold.
--   Kalahkan Yaptob sekali -> rupa Kedai "Garis Api Jolt" terbuka (tidak bisa dibeli dengan cara lain).
--   10 kemenangan Sirkuit -> tanda jasa "Sang Pacu Selat" (dihitung klien dari trek_state).
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('TrekHadiahOli', '2'), ('TrekHadiahGold', '4000'), ('TrekHadiahKali', '1')
on conflict (key) do nothing;

create table if not exists game.trek_harian (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  rival     text not null,
  game_day  int  not null,
  oli       int  not null default 0,
  gold      bigint not null default 0,
  at        timestamptz not null default now(),
  primary key (player_id, rival, game_day)
);
alter table game.trek_harian enable row level security;

-- Lawan yang lebih keras memberi lebih banyak.
create or replace function game.trek_bobot(p_rival text) returns int
language sql immutable as $$
  select case p_rival when 'pariopelan' then 1 when 'kapalmber' then 2 when 'cangcimen' then 4 when 'yaptob' then 8 else 1 end
$$;

create or replace function game.trek_sudah(p_pid uuid, p_rival text) returns boolean
language sql stable as $$
  select exists (select 1 from game.trek_harian where player_id = p_pid and rival = p_rival and game_day = game.game_day())
$$;

-- Dipanggil setelah menang di Sirkuit. Mengembalikan {oli, gold} atau null.
create or replace function game.trek_hadiah(p_pid uuid, p_rival text) returns jsonb
language plpgsql as $$
declare v_b int; v_oli int; v_gold bigint; v_muat int;
begin
  if p_pid is null or game.trek_sudah(p_pid, p_rival) then return null; end if;
  v_b := game.trek_bobot(p_rival);
  v_oli := greatest(0, round(game.cfg_num('TrekHadiahOli', 2) * v_b))::int;
  v_gold := greatest(0, round(game.cfg_num('TrekHadiahGold', 4000) * v_b * greatest(0, game.cfg_num('TrekHadiahKali', 1))))::bigint;
  v_muat := coalesce((select size from game.commodities where id = 'oli_hitam'), 1);
  if v_oli > 0 and game.cargo_free(p_pid) < v_oli * v_muat then v_oli := greatest(0, floor(game.cargo_free(p_pid) / v_muat)::int); end if;
  insert into game.trek_harian(player_id, rival, game_day, oli, gold)
  values (p_pid, p_rival, game.game_day(), v_oli, v_gold)
  on conflict (player_id, rival, game_day) do nothing;
  if not found then return null; end if;
  if v_oli > 0 then perform game.adjust_inventory(p_pid, 'oli_hitam', v_oli); end if;
  if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = p_pid; end if;
  return jsonb_build_object('oli', v_oli, 'gold', v_gold, 'rival', p_rival);
end $$;

-- Pernah mengalahkan Yaptob?
create or replace function game.trek_kalahkan(p_pid uuid, p_rival text) returns boolean
language sql stable as $$
  select exists (select 1 from game.trek_runs where player_id = p_pid and done and win and kind = 'sirkuit' and rival = p_rival)
$$;

create or replace function game.trek_menang_total(p_pid uuid) returns int
language sql stable as $$
  select coalesce((select count(*) from game.trek_runs where player_id = p_pid and done and win and kind = 'sirkuit'), 0)::int
$$;

-- Rupa Kedai: hadiah Tantangan Yaptob (tidak bisa dibeli sebelum YusaintJolt dikalahkan).
insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, req, exclusive, active, sort) values
  ('jejak_garis_api_jolt', 'rupa', 'jejak', null, 'Garis Api Jolt', 'legenda', 0,
     'Jejak api tipis khas YusaintJolt tertinggal di air. Yaptob hanya memberikannya pada yang pernah mengalahkannya.',
     'Yaptob', '{"yaptob":true}', false, true, 395)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh, req = excluded.req,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

create or replace function game.kd_req_ok(p_pid uuid, p_id text) returns boolean
language plpgsql stable as $$
declare r jsonb;
begin
  select i.req into r from game.kd_items i where i.id = p_id;
  if r is null then return true; end if;
  if r ? 'yaptob' then return game.trek_kalahkan(p_pid, 'yaptob'); end if;
  if r ? 'mahkota' then return game.mk_tamat(p_pid); end if;
  if r ? 'pasir' then
    return coalesce((select (data ->> (r ->> 'pasir'))::boolean from game.pasir_state where player_id = p_pid), false);
  end if;
  if not (r ? 'kisah') then return true; end if;
  return game.kisah_done(p_pid, r ->> 'kisah');
end $$;

-- Barang Saga 4 (termasuk hadiah Yaptob) disembunyikan sampai syaratnya terpenuhi.
create or replace function game.kd_list(p_pid uuid) returns jsonb
language plpgsql as $$
declare v jsonb; keep jsonb;
begin
  v := game.kd_list_mk(p_pid);
  if jsonb_typeof(v -> 'items') <> 'array' then return v; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into keep from jsonb_array_elements(v -> 'items') x
   where not ((x -> 'req') ?| array['mahkota', 'yaptob'])
      or coalesce((x ->> 'locked')::boolean, false) = false
      or coalesce((x ->> 'qty')::int, 0) > 0;
  return v || jsonb_build_object('items', keep);
end $$;

-- ---------------------------------------------------------------------
-- Hadiah harian dibayar saat balapan Sirkuit dimenangkan.
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.trek_selesai_hr(uuid, uuid, jsonb, text);
  alter function game.trek_selesai(uuid, uuid, jsonb, text) rename to trek_selesai_hr;
end $$;
create or replace function game.trek_selesai(p_pid uuid, p_id uuid, p_log jsonb, p_kind text) returns jsonb
language plpgsql as $$
declare r jsonb; v_rival text; v_hadiah jsonb;
begin
  r := game.trek_selesai_hr(p_pid, p_id, p_log, p_kind);
  begin
    if p_kind = 'sirkuit' and coalesce((r ->> 'win')::boolean, false) then
      v_rival := r ->> 'rival';
      v_hadiah := game.trek_hadiah(p_pid, v_rival);
      if v_hadiah is not null then r := r || jsonb_build_object('harian', v_hadiah); end if;
      if v_rival = 'yaptob' then r := r || jsonb_build_object('yaptob', true); end if;
    end if;
  exception when others then null;
  end;
  return r;
end $$;

-- Papan Sirkuit: tambahkan status hadiah harian + total menang.
do $$
begin
  drop function if exists game.trek_state_hr(uuid);
  alter function game.trek_state(uuid) rename to trek_state_hr;
end $$;
create or replace function game.trek_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb; v_h jsonb; g text;
begin
  v := game.trek_state_hr(p_pid);
  if v is null then return null; end if;
  v_h := '{}'::jsonb;
  foreach g in array game.trek_lawan(p_pid) loop
    v_h := v_h || jsonb_build_object(g, jsonb_build_object(
      'sudah', game.trek_sudah(p_pid, g),
      'oli', greatest(0, round(game.cfg_num('TrekHadiahOli', 2) * game.trek_bobot(g)))::int,
      'gold', greatest(0, round(game.cfg_num('TrekHadiahGold', 4000) * game.trek_bobot(g) * greatest(0, game.cfg_num('TrekHadiahKali', 1))))::bigint));
  end loop;
  return v || jsonb_build_object('harian', v_h, 'total', game.trek_menang_total(p_pid),
    'yaptob', game.trek_kalahkan(p_pid, 'yaptob'), 'hari', game.game_day());
end $$;
