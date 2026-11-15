-- =====================================================================
-- 0085 · Trektrek-an jadi arena antar pemain; lawan AI pindah ke event mingguan
--   * Sirkuit Zentul di luar event = HANYA Adu Kapten (PvP). Tidak ada lagi
--     balapan latihan melawan Pariopelan dkk, dan hadiah harian dicabut.
--   * Lawan AI muncul sebagai "Pacu Gugur" Yaptob: babak gugur sekali per
--     pekan kalender (Senin–Minggu). Pariopelan → KapalMber → cangcimen → Yaptob.
--     Kalah = gugur sampai pekan depan. Hadiah hanya untuk yang menembus Yaptob.
--   * Balapan yang jadi bagian cerita tetap lewat api_mahkota, tidak tersentuh.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('GugurTutup', '0'), ('GugurHadiahOli', '12'), ('GugurHadiahGold', '120000')
on conflict (key) do nothing;

create table if not exists game.gugur_run (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  week      int  not null,
  babak     int  not null default 1,
  status    text not null default 'jalan',   -- jalan | gugur | juara
  menang    int  not null default 0,
  us_total  bigint not null default 0,
  oli       int  not null default 0,
  gold      bigint not null default 0,
  at        timestamptz not null default now(),
  primary key (player_id, week)
);
alter table game.gugur_run enable row level security;

-- Pekan kalender, mulai Senin (epoch 1 Jan 1970 = Kamis).
create or replace function game.gugur_week() returns int
language sql stable as $$ select floor((extract(epoch from now()) + 3 * 86400) / 604800)::int $$;

create or replace function game.gugur_buka() returns boolean
language sql stable as $$ select lower(coalesce(game.cfg('GugurTutup'), '0')) not in ('1', 'true', 'on', 'ya') $$;

create or replace function game.gugur_lawan(p_babak int) returns text
language sql immutable as $$
  select case p_babak when 1 then 'pariopelan' when 2 then 'kapalmber' when 3 then 'cangcimen' when 4 then 'yaptob' else null end
$$;

create or replace function game.gugur_babak_akhir() returns int language sql immutable as $$ select 4 $$;

create or replace function game.gugur_kapal(p_pid uuid) returns text
language sql stable as $$
  -- Yaptob memasang Mesin Jolt Penuh untuk peserta gelanggang; Warlord dipakai apa adanya.
  select case when array_length(game.wl_set(p_pid), 1) = 4 then 'warlord' else 'penuh' end
$$;

create or replace function game.gugur_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select p_pid is not null and game.gugur_buka() and game.mk_tamat(p_pid)
     and not game.in_transit(p_pid) and game.current_city(p_pid) = 'zentul'
$$;

create or replace function game.gugur_papan() returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('nama', nama, 'us', us_total, 'menang', menang) order by us_total), '[]'::jsonb)
  from (select coalesce(nullif(p.character_name, ''), 'Kapten') as nama, r.us_total, r.menang
          from game.gugur_run r join game.players p using (player_id)
         where r.week = game.gugur_week() and r.status = 'juara'
         order by r.us_total limit 10) s
$$;

create or replace function game.gugur_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare r game.gugur_run; v_babak int; v_status text;
begin
  if p_pid is null or not game.mk_tamat(p_pid) then return null; end if;
  select * into r from game.gugur_run where player_id = p_pid and week = game.gugur_week();
  v_babak := coalesce(r.babak, 1); v_status := coalesce(r.status, 'jalan');
  return jsonb_build_object(
    'buka', game.gugur_buka(), 'siap', game.gugur_boleh(p_pid), 'minggu', game.gugur_week(),
    'babak', v_babak, 'akhir', game.gugur_babak_akhir(), 'status', v_status,
    'lawan', case when v_status = 'jalan' then game.gugur_lawan(v_babak) else null end,
    'menang', coalesce(r.menang, 0), 'usTotal', coalesce(r.us_total, 0),
    'kapal', game.gugur_kapal(p_pid), 'papan', game.gugur_papan(),
    'hadiah', jsonb_build_object('oli', greatest(0, round(game.cfg_num('GugurHadiahOli', 12)))::int,
                                 'gold', greatest(0, round(game.cfg_num('GugurHadiahGold', 120000)))::bigint),
    'didapat', case when v_status = 'juara' then jsonb_build_object('oli', coalesce(r.oli, 0), 'gold', coalesce(r.gold, 0)) else null end);
end $$;

-- ---------------------------------------------------------------------
-- API  ['status'] | ['mulai'] | ['selesai', run, log]
-- ---------------------------------------------------------------------
create or replace function public.api_gugur(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := coalesce(game.arg(a, 0), 'status');
  r game.gugur_run; v_w int := game.gugur_week(); v_h jsonb; v_oli int; v_gold bigint; v_muat int; v_bayar jsonb;
begin
  if v_id is null or not game.mk_tamat(v_id) then raise exception 'Gelanggang Yaptob hanya untuk yang sudah menamatkan Mahkota Selat.'; end if;
  if v_act = 'status' then return jsonb_build_object('gugur', game.gugur_state(v_id)); end if;
  if v_act not in ('mulai', 'selesai') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.gugur_boleh(v_id) then raise exception 'Gelanggang hanya buka di Zentul, Kapten. Merapat dulu.'; end if;

  insert into game.gugur_run(player_id, week) values (v_id, v_w) on conflict (player_id, week) do nothing;
  select * into r from game.gugur_run where player_id = v_id and week = v_w for update;

  if v_act = 'mulai' then
    if r.status = 'gugur' then raise exception 'Kau sudah gugur pekan ini, Kapten. Obor menyala lagi Senin depan.'; end if;
    if r.status = 'juara' then raise exception 'Kau sudah menembus Yaptob pekan ini. Simpan tenagamu.'; end if;
    return jsonb_build_object('run', game.trek_mulai(v_id, 'gugur', game.gugur_lawan(r.babak), game.gugur_kapal(v_id)),
      'gugur', game.gugur_state(v_id));
  end if;

  v_h := game.trek_selesai(v_id, (game.arg(a, 1))::uuid, game.arg_json(a, 2), 'gugur');
  if coalesce((v_h ->> 'win')::boolean, false) then
    if r.babak >= game.gugur_babak_akhir() then
      v_oli := greatest(0, round(game.cfg_num('GugurHadiahOli', 12)))::int;
      v_gold := greatest(0, round(game.cfg_num('GugurHadiahGold', 120000)))::bigint;
      v_muat := coalesce((select size from game.commodities where id = 'oli_hitam'), 1);
      if v_oli > 0 and game.cargo_free(v_id) < v_oli * v_muat then v_oli := greatest(0, floor(game.cargo_free(v_id) / v_muat)::int); end if;
      update game.gugur_run set status = 'juara', menang = menang + 1, us_total = us_total + coalesce((v_h ->> 'me')::bigint, 0),
             oli = v_oli, gold = v_gold, at = now()
       where player_id = v_id and week = v_w;
      if v_oli > 0 then perform game.adjust_inventory(v_id, 'oli_hitam', v_oli); end if;
      if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = v_id; end if;
      v_bayar := jsonb_build_object('oli', v_oli, 'gold', v_gold);
    else
      update game.gugur_run set babak = babak + 1, menang = menang + 1,
             us_total = us_total + coalesce((v_h ->> 'me')::bigint, 0), at = now()
       where player_id = v_id and week = v_w;
    end if;
  else
    update game.gugur_run set status = 'gugur', at = now() where player_id = v_id and week = v_w;
  end if;
  return jsonb_build_object('hasil', v_h, 'gugur', game.gugur_state(v_id), 'hadiah', v_bayar);
end $$;
select game.expose('api_gugur');

-- ---------------------------------------------------------------------
-- Hadiah harian Sirkuit dicabut; Sirkuit solo lawan AI ditutup.
-- ---------------------------------------------------------------------
create or replace function game.trek_hadiah(p_pid uuid, p_rival text) returns jsonb
language sql stable as $$ select null::jsonb $$;

create or replace function game.trek_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select case
    when p_pid is null then false
    when lower(coalesce(game.cfg('TrekTutup'), '0')) in ('1', 'true', 'on', 'ya') then false
    else game.penguji_saja(p_pid)
  end
$$;

-- Papan Sirkuit: tanpa hadiah harian, ditambah ringkasan gelanggang mingguan.
do $$
begin
  drop function if exists game.trek_state_gg(uuid);
  alter function game.trek_state(uuid) rename to trek_state_gg;
end $$;
create or replace function game.trek_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb;
begin
  v := game.trek_state_gg(p_pid);
  if v is null then return null; end if;
  return (v - 'harian') || jsonb_build_object('gugur', game.gugur_state(p_pid));
end $$;

-- Kemenangan lawan Yaptob kini hanya mungkin lewat Pacu Gugur.
create or replace function game.trek_kalahkan(p_pid uuid, p_rival text) returns boolean
language sql stable as $$
  select exists (select 1 from game.trek_runs where player_id = p_pid and done and win
                   and kind in ('sirkuit', 'gugur') and rival = p_rival)
$$;
