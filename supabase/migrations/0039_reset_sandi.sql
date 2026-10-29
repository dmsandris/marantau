-- =====================================================================
-- Marantau (Supabase) - 0039 RESET SANDI OLEH GM  (Tide v43)
-- ---------------------------------------------------------------------
-- Pemain lupa sandi -> lapor ke GM -> GM cocokkan data kapten di panel ->
-- GM tekan Reset -> server membuat SANDI SEMENTARA (tampil sekali ke GM).
--   * Sandi di Supabase Auth diganti (bcrypt), semua sesi lama dikeluarkan.
--   * Kapten lama (Google Sheets) yang belum diklaim: hash sandi lama yang diganti.
--   * Akun ditandai "wajib ganti sandi": SEMUA endpoint ditolak (MT_PWCHANGE)
--     sampai pemain memasang sandi baru sendiri. Tanda baru dicabut bila
--     server melihat hash sandi di Auth benar-benar berubah.
--   * Sandi sementara TIDAK disimpan di mana pun. Tiap reset & ganti tercatat.
-- Endpoint:
--   api_gmPassword([aksi, username])   aksi: lookup | reset | log      (khusus GM)
--   api_pwStatus([])                   {must: bool}                      (pemain login)
--   api_pwChanged([])                  cabut tanda setelah sandi diganti (pemain login)
-- Aman diulang.
-- =====================================================================

create table if not exists game.pw_must_change (
  username      text primary key,          -- huruf kecil (bagian depan email @marantau.game)
  set_at        timestamptz not null default now(),
  set_by        text not null default '',
  hash_at_reset text                       -- hash Auth saat reset; null = belum ada akun Auth (kapten lama)
);
alter table game.pw_must_change enable row level security;

create table if not exists game.pw_reset_log (
  id        bigserial primary key,
  at        timestamptz not null default now(),
  by_user   text not null default '',
  username  text not null,
  kind      text not null                  -- reset | reset_legacy | changed
);
create index if not exists pw_reset_log_at_idx on game.pw_reset_log (at desc);
alter table game.pw_reset_log enable row level security;

-- ---------------------------------------------------------------------
-- pgcrypto ada di schema "extensions" (Supabase); cari dinamis supaya tes lokal juga jalan
-- ---------------------------------------------------------------------
create or replace function game.pw_crypto_schema() returns text
language plpgsql stable as $$
declare s text;
begin
  select n.nspname into s from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.proname = 'gen_salt' order by (n.nspname = 'extensions') desc limit 1;
  if s is null then raise exception 'pgcrypto belum terpasang di database.'; end if;
  return s;
end $$;

create or replace function game.pw_bcrypt(p_pass text) returns text
language plpgsql volatile as $$
declare s text := game.pw_crypto_schema(); h text;
begin
  execute format('select %I.crypt($1, %I.gen_salt(''bf'', 10))', s, s) into h using p_pass;
  return h;
end $$;

-- Sandi sementara: kata-laut + 4 angka, mis. "pasir-4821" (acak kriptografis)
create or replace function game.pw_temp() returns text
language plpgsql volatile as $$
declare s text := game.pw_crypto_schema(); b bytea;
  w text[] := array['pasir','ombak','karang','layar','jangkar','camar','pelikan','dermaga','teluk','kompas',
                    'tiram','buritan','haluan','pinisi','jukung','galiung','pala','cengkeh','mutiara','lentera'];
begin
  execute format('select %I.gen_random_bytes(4)', s) into b;
  return w[1 + (get_byte(b, 0) % array_length(w, 1))] || '-' ||
         lpad(((get_byte(b, 1) * 65536 + get_byte(b, 2) * 256 + get_byte(b, 3)) % 10000)::text, 4, '0');
end $$;

-- Akun Auth dari username
create or replace function game.pw_auth_id(p_user text) returns uuid
language sql stable as $$
  select id from auth.users where lower(email) = lower(p_user) || '@marantau.game' limit 1
$$;

-- ---------------------------------------------------------------------
-- ENDPOINT GM
-- ---------------------------------------------------------------------
create or replace function public.api_gmPassword(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_gm uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), ''));
  v_u text := lower(btrim(coalesce(game.arg(a, 1), ''))); v_auth uuid; v_pid uuid;
  v_leg game.legacy_accounts; v_p game.players; v_card jsonb; v_tmp text; v_hash text; v_by text;
begin
  if not game.is_gm(v_gm) then raise exception 'Perintah ini khusus GM.'; end if;
  v_by := coalesce((select username from game.players where player_id = v_gm), '');

  if v_act = 'log' then
    return jsonb_build_object('ok', true, 'log', coalesce((
      select jsonb_agg(jsonb_build_object('at', (extract(epoch from x.at) * 1000)::bigint, 'by', x.by_user, 'u', x.username, 'k', x.kind) order by x.id desc)
      from (select * from game.pw_reset_log order by id desc limit 15) x), '[]'::jsonb),
      'pending', coalesce((select jsonb_agg(username order by set_at desc) from game.pw_must_change), '[]'::jsonb));
  end if;

  if v_act not in ('lookup', 'reset') then raise exception 'Perintah tidak dikenal: %', v_act; end if;
  if v_u !~ '^[a-z0-9_]{3,16}$' then raise exception 'Username tidak valid.'; end if;

  v_auth := game.pw_auth_id(v_u);
  select * into v_leg from game.legacy_accounts where username = v_u and claimed_at is null;
  v_pid := coalesce(v_auth, case when v_leg.username is not null then v_leg.player_id end);
  if v_pid is null then raise exception 'Username "%" tidak ditemukan.', v_u; end if;
  select * into v_p from game.players where player_id = v_pid;

  if v_act = 'lookup' then
    v_card := jsonb_build_object(
      'username', v_u,
      'legacy', v_auth is null,
      'name', nullif(coalesce(v_p.character_name, ''), ''),
      'arch', nullif(coalesce(v_p.archetype, ''), ''),
      'ship', (select ship_name from game.ships where player_id = v_pid),
      'city', (select coalesce(c.name, l.city_id) from game.player_location l left join game.cities c on c.city_id = l.city_id where l.player_id = v_pid),
      'gold', coalesce(v_p.gold, 0), 'bank', coalesce(v_p.bank_balance, 0),
      'created', (extract(epoch from v_p.created_at) * 1000)::bigint,
      'last', (extract(epoch from v_p.last_active) * 1000)::bigint,
      'gm', game.is_gm(v_pid),
      'pending', exists (select 1 from game.pw_must_change where username = v_u),
      'resets', (select count(*) from game.pw_reset_log where username = v_u and kind like 'reset%'));
    return jsonb_build_object('ok', true, 'card', v_card);
  end if;

  -- reset
  if v_pid = v_gm then raise exception 'Sandimu sendiri diganti lewat Pengaturan > Akun.'; end if;
  v_tmp := game.pw_temp();
  if v_auth is not null then
    v_hash := game.pw_bcrypt(v_tmp);
    update auth.users set encrypted_password = v_hash, updated_at = now() where id = v_auth;
    -- keluarkan semua sesi lama (token login yang tersimpan di HP/laptop lain)
    begin
      if to_regclass('auth.refresh_tokens') is not null then
        execute 'delete from auth.refresh_tokens where user_id = $1' using v_auth::text;
      end if;
      if to_regclass('auth.sessions') is not null then
        execute 'delete from auth.sessions where user_id = $1' using v_auth;
      end if;
    exception when others then
      raise warning 'Sesi lama % tidak terhapus: %', v_u, sqlerrm;
    end;
  else
    update game.legacy_accounts set pass_hash = game.legacy_hash(v_tmp, salt), failed = 0 where username = v_u;
  end if;
  insert into game.pw_must_change(username, set_at, set_by, hash_at_reset) values (v_u, now(), v_by, v_hash)
  on conflict (username) do update set set_at = now(), set_by = excluded.set_by, hash_at_reset = excluded.hash_at_reset;
  insert into game.pw_reset_log(by_user, username, kind) values (v_by, v_u, case when v_auth is null then 'reset_legacy' else 'reset' end);
  if v_p.player_id is not null then
    perform game.log(v_p.player_id, 'Sandi akunmu direset oleh GM. Pasang sandi baru saat masuk.');
  end if;
  return jsonb_build_object('ok', true, 'username', v_u, 'temp', v_tmp);
end $$;
select game.expose('api_gmpassword');

-- ---------------------------------------------------------------------
-- ENDPOINT PEMAIN
-- ---------------------------------------------------------------------
create or replace function public.api_pwStatus(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_u text := game.auth_username(); r game.pw_must_change;
begin
  select * into r from game.pw_must_change where username = v_u for update;
  if not found then return jsonb_build_object('must', false); end if;
  -- kapten lama: akun Auth baru dibuat dengan sandi sementara -> catat hash-nya sebagai pembanding
  if r.hash_at_reset is null then
    update game.pw_must_change set hash_at_reset = (select encrypted_password from auth.users where id = v_id)
    where username = v_u;
  end if;
  return jsonb_build_object('must', true);
end $$;
select game.expose('api_pwstatus');

create or replace function public.api_pwChanged(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_u text := game.auth_username(); r game.pw_must_change; v_now text;
begin
  select * into r from game.pw_must_change where username = v_u for update;
  if not found then return jsonb_build_object('ok', true, 'must', false); end if;
  select encrypted_password into v_now from auth.users where id = v_id;
  if r.hash_at_reset is not null and coalesce(v_now, '') = r.hash_at_reset then
    raise exception 'Sandi belum berganti. Pasang sandi baru dulu, Kapten.';
  end if;
  delete from game.pw_must_change where username = v_u;
  insert into game.pw_reset_log(by_user, username, kind) values (v_u, v_u, 'changed');
  return jsonb_build_object('ok', true, 'must', false);
end $$;
select game.expose('api_pwchanged');

-- ---------------------------------------------------------------------
-- Gerbang server (menggantikan versi 0036): pemeliharaan + wajib ganti sandi
-- ---------------------------------------------------------------------
create or replace function public.mt_pre_request() returns void
language plpgsql security definer set search_path = game, public as $$
declare v_block text; v_path text; v_info jsonb; v_u text;
begin
  begin
    v_path := lower(coalesce(current_setting('request.path', true), ''));
    if game.maint_active() then
      if v_path ~ 'rpc/(api_ping|api_gmstatus)$' then return; end if;
      if not game.is_gm(auth.uid()) then v_info := game.maint_info(); v_block := 'maint'; end if;
    end if;
    if v_block is null and auth.uid() is not null then
      v_u := lower(split_part(coalesce(auth.email(), ''), '@', 1));
      if v_u <> '' and exists (select 1 from game.pw_must_change where username = v_u)
         and v_path !~ 'rpc/(api_ping|api_gmstatus|api_pwstatus|api_pwchanged|api_authwhoami|api_legacyclaim|api_legacycheck)$' then
        v_block := 'pw';
      end if;
    end if;
  exception when others then
    return;   -- gagal-terbuka: jangan pernah mematikan game karena gerbang ini error
  end;
  if v_block = 'maint' then
    raise sqlstate 'PGRST' using
      message = json_build_object('code', 'MT_MAINT', 'message', 'Maintenis dulu ya gaes, kembali sebentar lagi.',
                                  'details', coalesce(v_info, '{}'::jsonb)::text)::text,
      detail = json_build_object('status', 503, 'status_text', 'Maintenance')::text;
  elsif v_block = 'pw' then
    raise sqlstate 'PGRST' using
      message = json_build_object('code', 'MT_PWCHANGE', 'message', 'Pasang sandi baru dulu, Kapten.', 'details', '{}')::text,
      detail = json_build_object('status', 403, 'status_text', 'Password change required')::text;
  end if;
end $$;
revoke all on function public.mt_pre_request() from public;
grant execute on function public.mt_pre_request() to anon, authenticated;
