-- =====================================================================
-- Marantau (Supabase) - 0036 GM & MODE PEMELIHARAAN  (Tide v38)
-- ---------------------------------------------------------------------
-- 1) Pengumuman GM: tampil di layar semua pemain (banner / modal darurat),
--    opsional dengan hitung mundur ke jam tertentu, dan tercatat di chat Dunia.
-- 2) Mode Pemeliharaan: saat aktif, SEMUA endpoint ditolak untuk pemain biasa
--    (layar "Maintenis dulu ya gaes"), kecuali akun GM yang tetap bisa main & menguji.
--    Bisa langsung ON, atau dijadwalkan ke jam tertentu (aktif otomatis).
-- GM = username di config GmUsernames (dipisah koma). Bawaan: abuy.
--
-- Penegakan di server: fungsi pre-request PostgREST (public.mt_pre_request)
-- dijalankan sebelum SETIAP panggilan API. Selama tidak pemeliharaan ia hanya
-- membaca 2 baris config. Kalau ada error tak terduga di dalamnya -> permintaan
-- DILOLOSKAN (gagal-terbuka), jadi fitur ini tidak bisa membuat game mati.
--
-- Aman diulang: status pemeliharaan & pengumuman TIDAK direset oleh deploy.
-- =====================================================================

insert into game.config(key, value) values
  ('GmUsernames', 'abuy'),
  ('MaintenanceMode', 'off'),        -- on | off
  ('MaintenanceStartAt', '0'),       -- ms epoch; > 0 = terjadwal, aktif otomatis saat tiba
  ('MaintenanceEndAt', '0'),         -- ms epoch; perkiraan selesai (hanya untuk tampilan)
  ('MaintenanceMessage', '')
on conflict (key) do nothing;

create table if not exists game.gm_announce (
  id         bigserial primary key,
  created_at timestamptz not null default now(),
  by_user    text not null default '',
  tx         text not null,
  lvl        text not null default 'info',     -- info | warn | urgent
  target_at  bigint,                           -- ms epoch untuk hitung mundur (opsional)
  kind       text not null default 'say',      -- say | maint
  until      timestamptz not null
);
create index if not exists gm_announce_until_idx on game.gm_announce (until desc);
alter table game.gm_announce enable row level security;

-- ---------------------------------------------------------------------
-- Siapa GM
-- ---------------------------------------------------------------------
create or replace function game.is_gm(p_pid uuid) returns boolean
language plpgsql stable as $$
declare v_list text := lower(replace(coalesce(game.cfg('GmUsernames'), ''), ' ', '')); v_u text;
begin
  if p_pid is null or v_list = '' then return false; end if;
  select lower(coalesce(username, '')) into v_u from game.players where player_id = p_pid;
  return coalesce(v_u, '') <> '' and v_u = any (string_to_array(v_list, ','));
end $$;

-- ---------------------------------------------------------------------
-- Status pemeliharaan
-- ---------------------------------------------------------------------
create or replace function game.maint_active() returns boolean
language plpgsql stable as $$
declare v_start bigint;
begin
  if lower(coalesce(game.cfg('MaintenanceMode'), 'off')) in ('on', '1', 'true', 'ya') then return true; end if;
  v_start := game.cfg_num('MaintenanceStartAt', 0)::bigint;
  return v_start > 0 and game.now_ms() >= v_start;
end $$;

-- null = tidak aktif & tidak terjadwal
create or replace function game.maint_info() returns jsonb
language plpgsql stable as $$
declare v_on boolean := game.maint_active(); v_start bigint := game.cfg_num('MaintenanceStartAt', 0)::bigint;
  v_end bigint := game.cfg_num('MaintenanceEndAt', 0)::bigint;
begin
  if not v_on and v_start <= 0 then return null; end if;
  return jsonb_build_object(
    'on', v_on,
    'startAt', case when v_start > 0 then v_start end,
    'endAt', case when v_end > 0 then v_end end,
    'tx', nullif(coalesce(game.cfg('MaintenanceMessage'), ''), ''),
    't', game.now_ms());
end $$;

-- ---------------------------------------------------------------------
-- Pengumuman aktif + status (dipakai pulse, api_gmStatus)
-- ---------------------------------------------------------------------
create or replace function game.gm_announce_list() returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tx', x.tx, 'lvl', x.lvl, 'at', x.target_at, 'kind', x.kind,
           'ts', (extract(epoch from x.created_at) * 1000)::bigint, 'until', (extract(epoch from x.until) * 1000)::bigint)
         order by x.id), '[]'::jsonb)
  from (select * from game.gm_announce where until > now() order by id desc limit 5) x
$$;

create or replace function game.gm_pulse(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_m jsonb; v_a jsonb; v_gm boolean;
begin
  v_m := game.maint_info();
  v_a := game.gm_announce_list();
  v_gm := game.is_gm(p_pid);
  if v_m is null and v_a = '[]'::jsonb and not v_gm then return null; end if;
  return jsonb_strip_nulls(jsonb_build_object('m', v_m, 'a', case when v_a <> '[]'::jsonb then v_a end,
    'gm', case when v_gm then true end, 't', game.now_ms()));
exception when others then
  return null;   -- denyut multiplayer tidak boleh gagal karena fitur ini
end $$;

-- Publik (boleh tanpa login): layar judul & layar pemeliharaan menanyakan status di sini.
create or replace function public.api_gmStatus(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return coalesce(game.gm_pulse(auth.uid()), jsonb_build_object('t', game.now_ms()));
end $$;
select game.expose('api_gmstatus', true);

-- ---------------------------------------------------------------------
-- Kirim ke semua layar: chat Dunia (label GM) + "bel" Realtime
-- ---------------------------------------------------------------------
create or replace function game.gm_broadcast(p_name text, p_text text) returns void
language plpgsql as $$
declare v_mid int; v_msg jsonb;
begin
  if coalesce(p_text, '') <> '' then
    insert into game.mp_chat_channels as ch (channel, last_id) values ('g', 1)
    on conflict (channel) do update set last_id = ch.last_id + 1 returning last_id into v_mid;
    v_msg := jsonb_build_object('id', v_mid, 'p', 'gm', 'n', p_name, 'a', '', 'ts', game.now_ms(), 'city', '', 'tx', p_text, 'gm', true);
    insert into game.mp_chat(channel, id, msg) values ('g', v_mid, v_msg);
    delete from game.mp_chat where channel = 'g' and id <= v_mid - 60;
    perform game.mp_rt('chat:global', 'chat', v_msg);
  end if;
  perform game.mp_rt('chat:global', 'gm', jsonb_build_object('t', game.now_ms()));
exception when others then null;
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT GM
--   api_gmCommand([aksi, teks, opsi])
--     'say'       teks, opsi {lvl: info|warn|urgent, at: ms hitung mundur, min: lama tampil (menit)}
--     'maint_on'  teks, opsi {endAt: ms perkiraan selesai}
--     'maint_at'  teks, opsi {startAt: ms mulai, endAt: ms perkiraan selesai}
--     'maint_off' teks (opsional, ucapan buka kembali)
--     'clear'     hapus semua pengumuman yang masih tampil
--     'status'    lihat status
-- ---------------------------------------------------------------------
create or replace function public.api_gmCommand(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), '')); v_tx text;
  v_opt jsonb := game.arg_json(a, 2); v_lvl text; v_at bigint; v_min numeric; v_until timestamptz;
  v_start bigint; v_end bigint; v_now bigint := game.now_ms(); v_name text; v_row game.gm_announce;
begin
  if not game.is_gm(v_id) then raise exception 'Perintah ini khusus GM.'; end if;
  if jsonb_typeof(v_opt) <> 'object' then v_opt := '{}'::jsonb; end if;
  v_tx := game.mp_clean(game.arg(a, 1), 240);
  v_name := 'GM ' || coalesce((select username from game.players where player_id = v_id), '');
  v_at := nullif(game.mp_jsnum(v_opt ->> 'at', 0), 0)::bigint;
  v_start := nullif(game.mp_jsnum(v_opt ->> 'startAt', 0), 0)::bigint;
  v_end := nullif(game.mp_jsnum(v_opt ->> 'endAt', 0), 0)::bigint;

  if v_act = 'say' then
    if v_tx = '' then raise exception 'Pesan GM kosong.'; end if;
    v_lvl := lower(coalesce(v_opt ->> 'lvl', 'info'));
    if v_lvl not in ('info', 'warn', 'urgent') then v_lvl := 'info'; end if;
    if v_at is not null and (v_at < v_now - 60000 or v_at > v_now + 2 * 86400000) then
      raise exception 'Jam hitung mundur harus dalam 48 jam ke depan.';
    end if;
    v_min := least(greatest(game.mp_jsnum(v_opt ->> 'min', 10), 1), 1440);
    v_until := case when v_at is not null then to_timestamp((v_at + 60000) / 1000.0)
                    else now() + make_interval(mins => v_min::int) end;
    insert into game.gm_announce(by_user, tx, lvl, target_at, kind, until)
    values (v_name, v_tx, v_lvl, v_at, 'say', v_until) returning * into v_row;
    perform game.gm_broadcast(v_name, v_tx);

  elsif v_act = 'maint_on' then
    if v_end is not null and v_end <= v_now then v_end := null; end if;
    perform game.cfg_set('MaintenanceMode', 'on');
    perform game.cfg_set('MaintenanceStartAt', '0');
    perform game.cfg_set('MaintenanceEndAt', coalesce(v_end, 0)::text);
    perform game.cfg_set('MaintenanceMessage', v_tx);
    update game.gm_announce set until = now() where kind = 'maint' and until > now();
    perform game.gm_broadcast(v_name, 'Pelabuhan ditutup sementara untuk pemeliharaan.' ||
      case when v_tx <> '' then ' ' || v_tx else '' end);

  elsif v_act = 'maint_at' then
    if v_start is null or v_start <= v_now + 30000 then raise exception 'Jam mulai pemeliharaan harus di masa depan.'; end if;
    if v_start > v_now + 2 * 86400000 then raise exception 'Jadwal pemeliharaan maksimal 48 jam ke depan.'; end if;
    if v_end is not null and v_end <= v_start then v_end := null; end if;
    perform game.cfg_set('MaintenanceMode', 'off');
    perform game.cfg_set('MaintenanceStartAt', v_start::text);
    perform game.cfg_set('MaintenanceEndAt', coalesce(v_end, 0)::text);
    perform game.cfg_set('MaintenanceMessage', v_tx);
    update game.gm_announce set until = now() where kind = 'maint' and until > now();
    insert into game.gm_announce(by_user, tx, lvl, target_at, kind, until)
    values (v_name, case when v_tx <> '' then v_tx else 'Server akan berbenah sebentar. Simpan dulu daganganmu, Kapten!' end,
            'warn', v_start, 'maint', to_timestamp(v_start / 1000.0))
    returning * into v_row;
    perform game.gm_broadcast(v_name, v_row.tx);

  elsif v_act = 'maint_off' then
    perform game.cfg_set('MaintenanceMode', 'off');
    perform game.cfg_set('MaintenanceStartAt', '0');
    perform game.cfg_set('MaintenanceEndAt', '0');
    perform game.cfg_set('MaintenanceMessage', '');
    update game.gm_announce set until = now() where kind = 'maint' and until > now();
    perform game.gm_broadcast(v_name, case when v_tx <> '' then v_tx else 'Pelabuhan dibuka kembali. Selamat berlayar, Kapten!' end);

  elsif v_act = 'clear' then
    update game.gm_announce set until = now() where until > now();
    perform game.gm_broadcast(v_name, '');

  elsif v_act <> 'status' then
    raise exception 'Perintah GM tidak dikenal: %', v_act;
  end if;

  return jsonb_build_object('ok', true, 'status', game.gm_pulse(v_id));
end $$;
select game.expose('api_gmcommand');

-- ---------------------------------------------------------------------
-- Gerbang server: dijalankan PostgREST sebelum setiap permintaan API
-- ---------------------------------------------------------------------
create or replace function public.mt_pre_request() returns void
language plpgsql security definer set search_path = game, public as $$
declare v_block boolean := false; v_path text; v_info jsonb;
begin
  begin
    if not game.maint_active() then return; end if;
    v_path := lower(coalesce(current_setting('request.path', true), ''));
    -- tetap boleh: cek koneksi & cek status pemeliharaan
    if v_path ~ 'rpc/(api_ping|api_gmstatus)$' then return; end if;
    if game.is_gm(auth.uid()) then return; end if;
    v_info := game.maint_info();
    v_block := true;
  exception when others then
    return;   -- gagal-terbuka: jangan pernah mematikan game karena gerbang ini error
  end;
  if v_block then
    raise sqlstate 'PGRST' using
      message = json_build_object('code', 'MT_MAINT', 'message', 'Maintenis dulu ya gaes, kembali sebentar lagi.',
                                  'details', coalesce(v_info, '{}'::jsonb)::text)::text,
      detail = json_build_object('status', 503, 'status_text', 'Maintenance')::text;
  end if;
end $$;
revoke all on function public.mt_pre_request() from public;
grant execute on function public.mt_pre_request() to anon, authenticated;

-- Daftarkan ke PostgREST (Supabase). Di tes lokal role authenticator tidak ada -> dilewati.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'alter role authenticator set pgrst.db_pre_request = ''public.mt_pre_request''';
    perform pg_notify('pgrst', 'reload config');
  end if;
exception when others then
  raise warning 'Gerbang pemeliharaan (pre-request) tidak terpasang: %', sqlerrm;
end $$;
