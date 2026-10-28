-- =====================================================================
-- 0039 — Pasir · Batch 0: fondasi (Tide v41)
-- Rencana: claude/PLAN-Coding-Saga3-Dark.md (project docs). Nama sengaja netral.
--
--   * Gerbang: config PasirOpen (0 = tertutup) atau FiturPenguji, lalu
--       (bendera dunia 'saga3' + Quest 9 selesai)  ATAU  akun GM (untuk uji).
--   * game.pasir_state : lapisan zaman per pemain (era, retak, kaca, riak, data).
--   * Quest ps10..ps14 memakai game.player_quests seperti quest lama.
--   * Key 'pasir' di api_getGameState HANYA dikirim bila pemain sudah punya baris
--     pasir_state (atau GM). Pemain lain tidak menerima key itu sama sekali.
--   * Endpoint api_pasir('status' | 'gm', ...). Aksi yang tidak berhak = "Aksi tidak dikenal."
--   * Alat GM: game.admin_pasir(username, aksi, arg) (SQL Editor) dan api_pasir('gm', aksi, arg).
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PasirOpen', '0'),
  ('PasirKaca', '7')
on conflict (key) do nothing;

create table if not exists game.pasir_state (
  player_id  uuid primary key references game.players(player_id) on update cascade on delete cascade,
  era        text not null default 'kini',
  retak      int  not null default 0,          -- Retak Waktu 0..100
  kaca       int  not null default 0,          -- kaca Jam Pasir yang sudah retak (0..PasirKaca)
  riak       jsonb not null default '{}'::jsonb, -- pilihan sebab-akibat pemain
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table game.pasir_state enable row level security;

-- ---------------------------------------------------------------------
-- Aturan dasar
-- ---------------------------------------------------------------------
create or replace function game.pasir_eras() returns text[]
language sql immutable as $$ select array['kini', 'keadilan', 'badai', 'lampau', 'pusaran'] $$;

-- Nada warna klien untuk tiap era (klien hanya mengenal nama nada, bukan nama era)
create or replace function game.pasir_tone(p_era text) returns text
language sql immutable as $$
  select case p_era when 'keadilan' then 'dingin' when 'badai' then 'sepia' when 'lampau' then 'emas'
    when 'pusaran' then 'kedip' else 'kini' end
$$;

create or replace function game.pasir_aktif(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if p_pid is null or not game.fitur_on(p_pid, 'PasirOpen') then return false; end if;
  if game.is_gm(p_pid) then return true; end if;
  return game.world_flag('saga3') and game.dt_step(p_pid) >= 5;
exception when others then return false;
end $$;

create or replace function game.pasir_era(p_pid uuid) returns text
language plpgsql stable as $$
declare v text;
begin
  if not game.pasir_aktif(p_pid) then return 'kini'; end if;
  select era into v from game.pasir_state where player_id = p_pid;
  return coalesce(v, 'kini');
exception when others then return 'kini';
end $$;

-- Langkah & data quest Pasir (ps10..ps14)
create or replace function game.ps_step(p_pid uuid, p_q text) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = p_q), 0) $$;

create or replace function game.ps_data(p_pid uuid, p_q text) returns jsonb
language sql stable as $$ select coalesce((select data from game.player_quests where player_id = p_pid and quest_id = p_q), '{}'::jsonb) $$;

create or replace function game.ps_set(p_pid uuid, p_q text, p_step int, p_data jsonb default '{}'::jsonb, p_done boolean default false) returns void
language plpgsql as $$
begin
  insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, p_q, p_step, coalesce(p_data, '{}'::jsonb))
  on conflict (player_id, quest_id) do update
    set step = excluded.step, data = game.player_quests.data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
        done_at = case when p_done and game.player_quests.done_at is null then now() else game.player_quests.done_at end;
end $$;

-- Pastikan baris lapisan zaman ada (dipanggil saat Saga dimulai / oleh alat GM)
create or replace function game.pasir_ensure(p_pid uuid) returns game.pasir_state
language plpgsql as $$
declare r game.pasir_state;
begin
  insert into game.pasir_state(player_id) values (p_pid) on conflict (player_id) do nothing;
  select * into r from game.pasir_state where player_id = p_pid;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Status untuk klien (key 'pasir'). null = key tidak dikirim.
-- ---------------------------------------------------------------------
create or replace function game.pasir_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare r game.pasir_state; v_gm boolean;
begin
  if not game.pasir_aktif(p_pid) then return null; end if;
  select * into r from game.pasir_state where player_id = p_pid;
  v_gm := game.is_gm(p_pid);
  if not found and not v_gm then return null; end if;
  return jsonb_build_object(
    'era', coalesce(r.era, 'kini'),
    'tone', game.pasir_tone(coalesce(r.era, 'kini')),
    'retak', coalesce(r.retak, 0),
    'kaca', coalesce(r.kaca, 0),
    'kacaMax', game.cfg_num('PasirKaca', 7)::int,
    'q', jsonb_build_object('10', game.ps_step(p_pid, 'ps10'), '11', game.ps_step(p_pid, 'ps11'),
      '12', game.ps_step(p_pid, 'ps12'), '13', game.ps_step(p_pid, 'ps13'), '14', game.ps_step(p_pid, 'ps14'))
  ) || case when v_gm then jsonb_build_object('gm', true,
          'eras', (select jsonb_agg(jsonb_build_object('era', e, 'tone', game.pasir_tone(e))) from unnest(game.pasir_eras()) e))
        else '{}'::jsonb end;
end $$;

-- ---------------------------------------------------------------------
-- Alat uji GM
--   era <kini|keadilan|badai|lampau|pusaran>   set lapisan zaman
--   retak <0..100>                             set Retak Waktu
--   kaca <0..7>                                set kaca retak
--   langkah <ps10..ps14> <n>                   set langkah quest
--   reset                                      hapus semua data Pasir pemain ini
--   lihat                                      lihat isi mentah
-- ---------------------------------------------------------------------
create or replace function game.pasir_admin(p_pid uuid, p_aksi text, p_arg text default null, p_arg2 text default null) returns jsonb
language plpgsql as $$
declare v_act text := lower(coalesce(p_aksi, 'lihat')); v_n int; r game.pasir_state;
begin
  if p_pid is null then raise exception 'Pemain tidak ditemukan.'; end if;
  if v_act = 'era' then
    if not (lower(coalesce(p_arg, '')) = any (game.pasir_eras())) then
      raise exception 'Era harus salah satu: %', array_to_string(game.pasir_eras(), ', ');
    end if;
    perform game.pasir_ensure(p_pid);
    update game.pasir_state set era = lower(p_arg), updated_at = now() where player_id = p_pid;
  elsif v_act in ('retak', 'kaca') then
    v_n := nullif(trim(coalesce(p_arg, '')), '')::int;
    if v_n is null then raise exception 'Angka tidak valid.'; end if;
    perform game.pasir_ensure(p_pid);
    if v_act = 'retak' then
      update game.pasir_state set retak = least(100, greatest(0, v_n)), updated_at = now() where player_id = p_pid;
    else
      update game.pasir_state set kaca = least(game.cfg_num('PasirKaca', 7)::int, greatest(0, v_n)), updated_at = now() where player_id = p_pid;
    end if;
  elsif v_act = 'langkah' then
    if coalesce(p_arg, '') !~ '^ps1[0-4]$' then raise exception 'Quest harus ps10..ps14.'; end if;
    v_n := nullif(trim(coalesce(p_arg2, '')), '')::int;
    if v_n is null or v_n < 0 then raise exception 'Langkah tidak valid.'; end if;
    perform game.pasir_ensure(p_pid);
    if v_n = 0 then delete from game.player_quests where player_id = p_pid and quest_id = p_arg;
    else perform game.ps_set(p_pid, p_arg, v_n); end if;
  elsif v_act = 'reset' then
    delete from game.player_quests where player_id = p_pid and quest_id in ('ps10', 'ps11', 'ps12', 'ps13', 'ps14');
    delete from game.pasir_state where player_id = p_pid;
  elsif v_act <> 'lihat' then
    raise exception 'Aksi GM tidak dikenal.';
  end if;
  select * into r from game.pasir_state where player_id = p_pid;
  return jsonb_build_object('row', case when r.player_id is null then null else to_jsonb(r) - 'player_id' end,
    'quests', coalesce((select jsonb_object_agg(quest_id, jsonb_build_object('step', step, 'data', data, 'done', done_at is not null))
      from game.player_quests where player_id = p_pid and quest_id in ('ps10', 'ps11', 'ps12', 'ps13', 'ps14')), '{}'::jsonb));
end $$;

-- Dipakai dari Supabase SQL Editor: select game.admin_pasir('abuy', 'era', 'lampau');
create or replace function game.admin_pasir(p_username text, p_aksi text, p_arg text default null, p_arg2 text default null) returns jsonb
language plpgsql as $$
declare v_pid uuid;
begin
  select player_id into v_pid from game.players where lower(username) = lower(trim(p_username));
  if v_pid is null then raise exception 'Username % tidak ditemukan.', p_username; end if;
  return game.pasir_admin(v_pid, p_aksi, p_arg, p_arg2);
end $$;

-- ---------------------------------------------------------------------
-- Endpoint: api_pasir(aksi, ...)
--   'status'                  -> {pasir}
--   'gm', aksi, arg, arg2     -> alat uji (khusus GM)
-- ---------------------------------------------------------------------
create or replace function public.api_pasir(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_me game.players; v_pid uuid; v_res jsonb;
begin
  v_me := game.me(v_act = 'gm');
  v_pid := v_me.player_id;
  if coalesce(v_me.archetype, '') = '' or not game.pasir_aktif(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;

  if v_act = 'status' then
    return jsonb_build_object('pasir', game.pasir_state(v_pid));
  elsif v_act = 'gm' then
    if not game.is_gm(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
    v_res := game.pasir_admin(v_pid, game.arg(a, 1), game.arg(a, 2), game.arg(a, 3));
    return jsonb_build_object('gm', v_res, 'pasir', game.pasir_state(v_pid));
  end if;
  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_pasir');
