-- =====================================================================
-- 0105 · S5 fondasi (Saga 5, Fase 0)
--
-- Isi:
--   1. Gerbang fitur S5aOpen / S5bOpen / S5cOpen (+ FiturPenguji), kenop dasar.
--   2. game.s5_state: dunia pemain ('mare' | 'seberang'), hari penyeberangan terakhir, tiket titian.
--   3. Aturan titian: 1 penyeberangan per hari kalender game, pergi & pulang tidak boleh di hari yang sama
--      (pengecualian satu langkah pulang terakhir dipanggil dengan p_bebas = true).
--   4. Pagar dunia seberang di mt_pre_request: hanya endpoint dalam daftar izin yang dilayani.
--   5. Presence tersamar (tanpa kota/tujuan), tugas harian tidak dihitung, pencegatan Mare
--      (bajak laut acak, Tony, Navy, Cukai) tidak pernah muncul di pelayaran seberang.
--   6. Kerangka sesi mini game baru (pola Trektrek-an): game.mg_session, api_mg_start, api_mg_finish.
--      Jenis mini game (listen/wave/spear) didaftarkan di migrasi berikutnya lewat fungsi
--      game.mg_<kind>_build / game.mg_<kind>_judge; hook izin/biaya/efek: s5_mg_izin, s5_mg_mulai, s5_mg_efek.
--
-- Nama kota dunia seberang selalu berawalan 's5_' (game.s5_city).
-- Pembungkus (akhiran _s5): mt_pre_request -> game.mt_pre_request_s5, hr_hook, kd_enc, voy_roll_encounter.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('S5aOpen', '0'), ('S5bOpen', '0'), ('S5cOpen', '0'),
  ('S5TiketOli', '10'),           -- biaya titian Mare -> seberang (tiket berlaku sampai berhasil menyeberang hari itu)
  ('S5MgJedaMs', '2000'),         -- jarak minimal antar api_mg_start
  ('S5MgPerJam', '30')            -- batas sesi mini game per jam per pemain
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1. Gerbang & status dunia
-- ---------------------------------------------------------------------
create table if not exists game.s5_state (
  player_id  uuid primary key references game.players(player_id) on update cascade on delete cascade,
  dunia      text not null default 'mare',
  cross_day  int,                       -- hari game penyeberangan terakhir (pergi atau pulang)
  cross_n    int not null default 0,
  tiket_day  int,                       -- hari game tiket titian dibayar (belum terpakai)
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
do $$ begin
  alter table game.s5_state add constraint s5_state_dunia_chk check (dunia in ('mare', 'seberang'));
exception when duplicate_object then null; end $$;
alter table game.s5_state enable row level security;
revoke all on game.s5_state from public, anon, authenticated;

create or replace function game.s5_on(p_pid uuid) returns boolean
language sql stable as $$ select game.fitur_on(p_pid, 'S5aOpen') $$;

create or replace function game.s5_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city, '') like 's5\_%' $$;

-- Dipanggil di setiap permintaan (pre-request, presence, harian): satu baris lewat primary key.
create or replace function game.s5_di_seberang(p_pid uuid) returns boolean
language sql stable as $$
  select p_pid is not null and exists (select 1 from game.s5_state where player_id = p_pid and dunia = 'seberang')
$$;

create or replace function game.s5_dunia(p_pid uuid) returns text
language sql stable as $$
  select coalesce((select dunia from game.s5_state where player_id = p_pid), 'mare')
$$;

create or replace function game.s5_row(p_pid uuid) returns game.s5_state
language plpgsql as $$
declare r game.s5_state;
begin
  insert into game.s5_state(player_id) values (p_pid) on conflict (player_id) do nothing;
  select * into r from game.s5_state where player_id = p_pid for update;
  return r;
end $$;

-- 1 penyeberangan per hari kalender game (kapan saja); pergi & pulang tidak boleh di hari yang sama.
-- p_bebas = true untuk satu pengecualian cerita (pulang terakhir).
create or replace function game.s5_bisa_seberang(p_pid uuid, p_bebas boolean default false) returns jsonb
language plpgsql stable as $$
declare v_last int; v_day int := game.game_day();
begin
  select cross_day into v_last from game.s5_state where player_id = p_pid;
  if p_bebas or v_last is null or v_last < v_day then
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object('ok', false, 'alasan', 'hari', 'menit', game.minutes_to_next_day(),
    'pesan', 'Titian sudah dilewati hari ini. Titian terbuka lagi di hari berikutnya (± ' ||
             game.s5_menit_label(game.minutes_to_next_day()) || ').');
end $$;

create or replace function game.s5_menit_label(p_menit int) returns text
language sql immutable as $$
  select case when coalesce(p_menit, 0) >= 60
              then (p_menit / 60) || ' jam' || case when p_menit % 60 > 0 then ' ' || (p_menit % 60) || ' menit' else '' end
              else greatest(1, coalesce(p_menit, 0)) || ' menit' end
$$;

-- Catat penyeberangan yang BERHASIL (pergi atau pulang). Tiket titian habis terpakai.
create or replace function game.s5_catat_seberang(p_pid uuid, p_ke text) returns void
language plpgsql as $$
begin
  if p_ke not in ('mare', 'seberang') then raise exception 'Tujuan titian tidak dikenal.'; end if;
  perform game.s5_row(p_pid);
  update game.s5_state set dunia = p_ke, cross_day = game.game_day(), cross_n = cross_n + 1,
    tiket_day = case when p_ke = 'seberang' then null else tiket_day end, updated_at = now()
  where player_id = p_pid;
end $$;

-- Tiket titian (K6): dibayar sekali saat mulai, berlaku sampai berhasil menyeberang di hari yang sama.
create or replace function game.s5_tiket_berlaku(p_pid uuid) returns boolean
language sql stable as $$
  select coalesce((select tiket_day = game.game_day() from game.s5_state where player_id = p_pid), false)
$$;

-- ---------------------------------------------------------------------
-- 2. Pagar dunia seberang (pre-request PostgREST)
-- ---------------------------------------------------------------------
-- Daftar IZIN: endpoint baru di masa depan otomatis tertutup di seberang.
create or replace function game.s5_rpc_izin(p_fn text) returns boolean
language sql immutable as $$
  select lower(coalesce(p_fn, '')) = any (array[
    -- koneksi, akun, status
    'api_ping', 'api_gmstatus', 'api_authwhoami', 'api_pwstatus', 'api_pwchanged', 'api_gettitlescreenconfig',
    'api_getgamestate', 'api_getcitybundle', 'api_getcities', 'api_getcharacterstats', 'api_savemeta', 'api_seenmark',
    'api_saveappearance',
    -- palka & artefak (lihat saja / pasang)
    'api_getcargo', 'api_getcargostate', 'api_getitems', 'api_equipartifact', 'api_unequipartifact',
    -- kapal & galangan (Dwarfsmith)
    'api_getshipstate', 'api_getshipupgrades', 'api_shipupgrade', 'api_repairship', 'api_getrepairquote', 'api_saveshiplook',
    -- berlayar
    'api_getsailoptions', 'api_getsailingbackgroundurl', 'api_setsail', 'api_pollvoyage',
    -- sosial (tanpa duel, hadiah, bursa)
    'api_mppulse', 'api_mpchat', 'api_mppm', 'api_mpprofile', 'api_getleaderboard',
    -- GM
    'api_gmcommand', 'api_gmkirim', 'api_gmpassword',
    -- Saga 5
    'api_mg_start', 'api_mg_finish', 'api_s5'
  ])
$$;

do $$
begin
  if to_regprocedure('game.mt_pre_request_s5()') is not null then drop function game.mt_pre_request_s5(); end if;
  alter function public.mt_pre_request() rename to mt_pre_request_s5;
  alter function public.mt_pre_request_s5() set schema game;
end $$;
revoke all on function game.mt_pre_request_s5() from public, anon, authenticated;

create or replace function public.mt_pre_request() returns void
language plpgsql security definer set search_path = game, public as $$
declare v_path text; v_fn text; v_tolak boolean := false;
begin
  perform game.mt_pre_request_s5();   -- pemeliharaan, pindah server, ganti sandi, Pasir
  begin
    if auth.uid() is null then return; end if;
    v_path := lower(coalesce(current_setting('request.path', true), ''));
    v_fn := substring(v_path from 'rpc/([a-z0-9_]+)$');
    if v_fn is null then return; end if;
    if game.s5_rpc_izin(v_fn) then return; end if;
    v_tolak := game.s5_di_seberang(auth.uid());
  exception when others then
    return;   -- gagal-terbuka: gerbang ini tidak boleh mematikan game
  end;
  if v_tolak then raise exception 'Tak ada yang melayani itu di seberang titian, Kapten.'; end if;
end $$;
revoke all on function public.mt_pre_request() from public;
grant execute on function public.mt_pre_request() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. Presence tersamar: pemain di seberang tampil "berlayar jauh" (tanpa kota, tanpa tujuan)
-- ---------------------------------------------------------------------
create or replace function game.s5_presence_tg() returns trigger
language plpgsql as $$
begin
  begin
    if game.s5_di_seberang(new.player_id) then
      new.c := ''; new.sea := true; new.dest := '';
    end if;
  exception when others then null;
  end;
  return new;
end $$;
drop trigger if exists s5_presence on game.mp_presence;
create trigger s5_presence before insert or update on game.mp_presence
  for each row execute function game.s5_presence_tg();

-- ---------------------------------------------------------------------
-- 4. Pembungkus: tugas harian, pencegatan
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.hr_hook_s5(uuid, text, numeric, jsonb);
  alter function game.hr_hook(uuid, text, numeric, jsonb) rename to hr_hook_s5;
  drop function if exists game.kd_enc_s5(uuid, jsonb);
  alter function game.kd_enc(uuid, jsonb) rename to kd_enc_s5;
  drop function if exists game.voy_roll_encounter_s5(uuid, text);
  alter function game.voy_roll_encounter(uuid, text) rename to voy_roll_encounter_s5;
end $$;

-- K9: kegiatan di seberang tidak dihitung tugas harian
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
begin
  begin
    if game.s5_di_seberang(p_pid) then return; end if;
  exception when others then null;
  end;
  perform game.hr_hook_s5(p_pid, p_kind, p_amount, p_ctx);
end $$;

-- Pelayaran di seberang: tidak ada bajak laut acak (dilempar di sini, sebelum Ragam Lawan)
create or replace function game.voy_roll_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql as $$
begin
  if game.s5_city(p_dest) or game.s5_di_seberang(p_pid) then return null; end if;
  return game.voy_roll_encounter_s5(p_pid, p_dest);
end $$;

-- Pembungkus terluar kd_enc: di seberang hanya pencegatan milik S5 (penanda 's5') yang lolos.
-- Rantai dalam (Tony, Navy, Cukai, Kedai) TIDAK dipanggil sama sekali, supaya tidak ada efek samping (hitungan Tony).
create or replace function game.kd_enc(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql as $$
declare l game.player_location;
begin
  select * into l from game.player_location where player_id = p_pid;
  if game.s5_city(l.destination_city_id) or game.s5_di_seberang(p_pid) then
    if jsonb_typeof(p_enc) = 'object' and p_enc ? 's5' then return p_enc; end if;
    return null;
  end if;
  return game.kd_enc_s5(p_pid, p_enc);
end $$;

-- ---------------------------------------------------------------------
-- 5. Kerangka sesi mini game (Dengar Tanah, Susur Ombak, Tombak Laut)
-- ---------------------------------------------------------------------
create table if not exists game.mg_session (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references game.players(player_id) on update cascade on delete cascade,
  kind        text not null,
  context     text not null,
  preset      text not null,
  step_ref    int,
  params      jsonb not null default '{}'::jsonb,
  assist_pct  int not null default 0,
  issued_at   timestamptz not null default now(),
  issued_ms   bigint not null default 0,
  expires_at  timestamptz not null,
  status      text not null default 'open',
  result      jsonb,
  efek        jsonb,
  finished_at timestamptz
);
do $$ begin
  alter table game.mg_session add constraint mg_session_status_chk check (status in ('open', 'won', 'lost', 'expired'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table game.mg_session add constraint mg_session_ctx_chk check (context in ('quest', 'crossing', 'encounter', 'trial'));
exception when duplicate_object then null; end $$;
create unique index if not exists mg_session_satu_open on game.mg_session(player_id) where status = 'open';
create index if not exists mg_session_pemain on game.mg_session(player_id, issued_at desc);
alter table game.mg_session enable row level security;
revoke all on game.mg_session from public, anon, authenticated;

create table if not exists game.mg_streak (
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  kind       text not null,
  context    text not null,
  preset     text not null,
  kalah      int not null default 0,
  primary key (player_id, kind, context, preset)
);
alter table game.mg_streak enable row level security;
revoke all on game.mg_streak from public, anon, authenticated;

-- Hook bawaan (didefinisikan ulang oleh migrasi fase berikutnya).
-- Izin: null = boleh; teks = alasan ditolak.
create or replace function game.s5_mg_izin(p_pid uuid, p_kind text, p_ctx text, p_preset text, p_step int) returns text
language plpgsql stable as $$
begin
  if p_kind = 'uji' and game.is_gm(p_pid) then return null; end if;   -- jenis uji kerangka, hanya GM
  return 'Belum ada yang menunggu di sini, Kapten.';
end $$;
-- Biaya/persiapan saat sesi dibuka (mis. tiket titian). Mengembalikan info untuk klien.
create or replace function game.s5_mg_mulai(p_pid uuid, p_s game.mg_session) returns jsonb
language plpgsql as $$ begin return '{}'::jsonb; end $$;
-- Akibat hasil (maju langkah, tiba di seberang, kerusakan, bounty). Dipanggil SEKALI per sesi.
create or replace function game.s5_mg_efek(p_pid uuid, p_s game.mg_session, p_won boolean) returns jsonb
language plpgsql as $$ begin return '{}'::jsonb; end $$;

-- Jenis 'uji' (GM saja): memeriksa kerangka tanpa konten. Log {n}: menang bila n = target.
create or replace function game.mg_uji_build(p_pid uuid, p_ctx text, p_preset text, p_assist int) returns jsonb
language sql volatile as $$ select jsonb_build_object('max_ms', 5000, 'min_total_ms', 0, 'target', game.rand_int(1, 9), 'assist', p_assist) $$;
create or replace function game.mg_uji_judge(p_params jsonb, p_log jsonb, p_elapsed bigint) returns jsonb
language plpgsql stable as $$
begin
  if coalesce(jsonb_typeof(p_log), '') <> 'object' or coalesce(jsonb_typeof(p_log -> 'n'), '') <> 'number' then raise exception 'Catatan permainan tidak sah.'; end if;
  return jsonb_build_object('won', (p_log ->> 'n')::int = (p_params ->> 'target')::int, 'n', (p_log ->> 'n')::int);
end $$;

-- Tingkat bantuan otomatis dari kekalahan berturut-turut (sama untuk semua jenis: 0 / 15 / 30 persen)
create or replace function game.mg_assist(p_kalah int) returns int
language sql immutable as $$ select case when p_kalah >= 4 then 30 when p_kalah >= 2 then 15 else 0 end $$;

create or replace function public.api_mg_start(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid();
  v_kind text := lower(coalesce(game.arg(a, 0), ''));
  v_ctx text := lower(coalesce(game.arg(a, 1), ''));
  v_preset text := lower(coalesce(game.arg(a, 2), ''));
  v_step int := nullif(coalesce(game.arg(a, 3), ''), '')::int;
  v_why text; v_kalah int; v_assist int; v_params jsonb; v_max bigint; s game.mg_session; v_info jsonb;
  v_last timestamptz; v_n int;
begin
  if v_pid is null or not game.s5_on(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  if v_kind !~ '^[a-z]{2,12}$' or v_preset !~ '^[a-z0-9_]{1,32}$'
     or v_ctx not in ('quest', 'crossing', 'encounter', 'trial')
     or to_regprocedure('game.mg_' || v_kind || '_build(uuid,text,text,integer)') is null
     or to_regprocedure('game.mg_' || v_kind || '_judge(jsonb,jsonb,bigint)') is null then
    raise exception 'Aksi tidak dikenal.';
  end if;
  perform 1 from game.players where player_id = v_pid for update;

  -- batas laju
  select max(issued_at), count(*) filter (where issued_at > now() - interval '1 hour')
    into v_last, v_n from game.mg_session where player_id = v_pid and issued_at > now() - interval '1 hour';
  if v_last is not null and v_last > now() - make_interval(secs => game.cfg_num('S5MgJedaMs', 2000) / 1000.0) then
    raise exception 'Pelan-pelan, Kapten. Tarik napas dulu.';
  end if;
  if coalesce(v_n, 0) >= game.cfg_num('S5MgPerJam', 30) then
    raise exception 'Awakmu kelelahan, Kapten. Istirahat sebentar sebelum mencoba lagi.';
  end if;

  v_why := game.s5_mg_izin(v_pid, v_kind, v_ctx, v_preset, v_step);
  if v_why is not null then raise exception '%', v_why; end if;

  -- satu sesi terbuka per pemain: sesi lama gugur
  update game.mg_session set status = 'expired', finished_at = now() where player_id = v_pid and status = 'open';

  select kalah into v_kalah from game.mg_streak where player_id = v_pid and kind = v_kind and context = v_ctx and preset = v_preset;
  v_assist := game.mg_assist(coalesce(v_kalah, 0));
  execute format('select game.%I($1, $2, $3, $4)', 'mg_' || v_kind || '_build') into v_params using v_pid, v_ctx, v_preset, v_assist;
  v_max := coalesce((v_params ->> 'max_ms')::bigint, 60000);

  insert into game.mg_session(player_id, kind, context, preset, step_ref, params, assist_pct, issued_ms, expires_at)
  values (v_pid, v_kind, v_ctx, v_preset, v_step, v_params, v_assist, game.now_ms(), now() + make_interval(secs => v_max / 1000.0 + 120))
  returning * into s;
  v_info := coalesce(game.s5_mg_mulai(v_pid, s), '{}'::jsonb);

  return jsonb_build_object('session_id', s.id, 'params', s.params, 'info', v_info);
end $$;
select game.expose('api_mg_start');

create or replace function public.api_mg_finish(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_sid uuid; v_log jsonb := game.arg_json(a, 1);
  s game.mg_session; v_elapsed bigint; v_res jsonb; v_won boolean; v_efek jsonb; v_min bigint;
begin
  if v_pid is null or not game.s5_on(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  begin v_sid := game.arg(a, 0)::uuid; exception when others then raise exception 'Sesi tidak dikenal.'; end;
  select * into s from game.mg_session where id = v_sid and player_id = v_pid for update;
  if not found then raise exception 'Sesi tidak dikenal.'; end if;

  -- idempoten: hasil yang sama untuk panggilan ulang
  if s.status <> 'open' then
    return jsonb_build_object('status', s.status, 'result', s.result, 'efek', s.efek, 'replay', true);
  end if;
  if now() > s.expires_at + interval '5 seconds' then
    update game.mg_session set status = 'expired', finished_at = now() where id = s.id;
    return jsonb_build_object('status', 'expired', 'pesan', 'Kesempatan berlalu. Coba lagi, tanpa kerugian.');
  end if;

  v_elapsed := game.now_ms() - s.issued_ms;
  v_min := coalesce((s.params ->> 'min_total_ms')::bigint, 0);
  if v_elapsed < v_min - 3000 then raise exception 'Catatan permainan tidak sah.'; end if;

  execute format('select game.%I($1, $2, $3)', 'mg_' || s.kind || '_judge') into v_res using s.params, coalesce(v_log, 'null'::jsonb), v_elapsed;
  v_won := coalesce((v_res ->> 'won')::boolean, false);

  update game.mg_session set status = case when v_won then 'won' else 'lost' end, result = v_res, finished_at = now()
  where id = s.id returning * into s;

  insert into game.mg_streak(player_id, kind, context, preset, kalah) values (v_pid, s.kind, s.context, s.preset, case when v_won then 0 else 1 end)
  on conflict (player_id, kind, context, preset) do update set kalah = case when v_won then 0 else game.mg_streak.kalah + 1 end;

  v_efek := coalesce(game.s5_mg_efek(v_pid, s, v_won), '{}'::jsonb);
  update game.mg_session set efek = v_efek where id = s.id;

  return jsonb_build_object('status', s.status, 'result', v_res, 'efek', v_efek);
end $$;
select game.expose('api_mg_finish');

-- ---------------------------------------------------------------------
-- 6. api_s5 — titik masuk S5. Fase 0: alat uji GM saja (pemain lain: "Aksi tidak dikenal.").
--    Fase berikutnya mendefinisikan ulang fungsi ini (aksi quest) dan tetap membawa aksi gm_*.
-- ---------------------------------------------------------------------
create or replace function game.s5_gm_status(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'dunia', game.s5_dunia(p_pid),
    'hari', game.game_day(),
    'crossDay', (select cross_day from game.s5_state where player_id = p_pid),
    'bisa', game.s5_bisa_seberang(p_pid),
    'gerbang', jsonb_build_object('a', game.cfg('S5aOpen'), 'b', game.cfg('S5bOpen'), 'c', game.cfg('S5cOpen')),
    'penguji', coalesce(game.cfg('FiturPenguji'), ''))
$$;

create or replace function game.s5_gm_act(p_pid uuid, a jsonb) returns jsonb
language plpgsql as $$
declare v_act text := lower(coalesce(game.arg(a, 0), '')); v_ke text := lower(coalesce(game.arg(a, 1), ''));
begin
  if not game.is_gm(p_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  if v_act = 'gm_dunia' then
    -- Uji pagar: hanya menandai dunia GM sendiri. Kapal tidak dipindahkan, hari titian tidak dicatat.
    if v_ke not in ('mare', 'seberang') then raise exception 'Pilih mare atau seberang.'; end if;
    perform game.s5_row(p_pid);
    update game.s5_state set dunia = v_ke, updated_at = now() where player_id = p_pid;
    perform game.mp_touch(p_pid);
  elsif v_act = 'gm_reset_hari' then
    update game.s5_state set cross_day = null, tiket_day = null, updated_at = now() where player_id = p_pid;
  elsif v_act <> 'gm_status' then
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object('ok', true, 'gm', game.s5_gm_status(p_pid));
end $$;

create or replace function public.api_s5(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), ''));
begin
  if v_pid is null then raise exception 'Aksi tidak dikenal.'; end if;
  if v_act like 'gm\_%' then return game.s5_gm_act(v_pid, a); end if;
  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_s5');
