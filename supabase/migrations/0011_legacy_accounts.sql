-- =====================================================================
-- Marantau (Supabase) - 0011 LEGACY ACCOUNTS
-- Kapten dari versi Google Sheets diimpor dengan id sementara (placeholder).
-- Saat pemain lama pertama kali Masuk dengan username + password lamanya:
--   1) api_legacyCheck  (tanpa login) cek hash password lama,
--   2) client membuat akun Supabase Auth dengan username/password yang sama,
--   3) api_legacyClaim  (sudah login) memindahkan seluruh data kapten ke akun baru.
-- DATA pemain TIDAK ada di repo ini (repo publik); data diimpor lewat file SQL privat.
-- =====================================================================

-- Semua FK ke game.players ikut berubah saat player_id diganti (klaim akun)
do $$
declare r record;
begin
  for r in
    select c.conname, c.conrelid::regclass as tbl, pg_get_constraintdef(c.oid) as def
    from pg_constraint c
    where c.contype = 'f' and c.confrelid = 'game.players'::regclass and c.confupdtype <> 'c'
  loop
    execute format('alter table %s drop constraint %I, add constraint %I %s on update cascade',
      r.tbl, r.conname, r.conname, r.def);
  end loop;
end $$;

create table if not exists game.legacy_accounts (
  username   text primary key,              -- huruf kecil, sama dengan username lama
  pass_hash  text not null,                 -- SHA-256 bergaram 250 putaran (AuthService.gs)
  salt       text not null,
  player_id  uuid not null,                 -- id sementara di game.players sampai diklaim
  legacy_id  text not null,                 -- id lama (email / acc:username)
  failed     int not null default 0,
  claimed_at timestamptz,
  claimed_by uuid,
  imported_at timestamptz not null default now()
);
alter table game.legacy_accounts enable row level security;

-- Sama persis dengan hash_() di AuthService.gs
create or replace function game.legacy_hash(p_password text, p_salt text) returns text
language plpgsql immutable as $$
declare h text := p_salt || '|' || p_password;
begin
  for i in 1 .. 250 loop
    h := encode(sha256(convert_to(h || '|' || p_salt, 'UTF8')), 'hex');
  end loop;
  return h;
end $$;

-- Cek password lama (belum diklaim). Terkunci sementara setelah 10x salah.
create or replace function public.api_legacyCheck(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  u text := lower(btrim(coalesce(game.arg(a, 0), '')));
  p text := coalesce(game.arg(a, 1), '');
  r game.legacy_accounts;
begin
  select * into r from game.legacy_accounts where username = u and claimed_at is null for update;
  if not found then return jsonb_build_object('ok', false); end if;
  if r.failed >= 10 then
    raise exception 'Terlalu banyak percobaan gagal. Hubungi admin game.';
  end if;
  if game.legacy_hash(p, r.salt) <> r.pass_hash then
    update game.legacy_accounts set failed = failed + 1 where username = u;
    return jsonb_build_object('ok', false);
  end if;
  update game.legacy_accounts set failed = 0 where username = u;
  return jsonb_build_object('ok', true);
end $$;
select game.expose('api_legacycheck', true);

-- Pindahkan kapten lama ke akun Supabase yang sedang login (username harus sama).
create or replace function public.api_legacyClaim(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_uid uuid := game.uid();
  u text := game.auth_username();
  p text := coalesce(game.arg(a, 0), '');
  r game.legacy_accounts;
  v_cur game.players;
  v_name text;
begin
  select * into r from game.legacy_accounts where username = u for update;
  if not found then raise exception 'Tidak ada kapten lama untuk akun ini.'; end if;
  if r.claimed_at is not null then
    if r.claimed_by = v_uid then return jsonb_build_object('ok', true, 'already', true); end if;
    raise exception 'Kapten lama ini sudah diklaim akun lain.';
  end if;
  if game.legacy_hash(p, r.salt) <> r.pass_hash then raise exception 'Password lama salah.'; end if;

  select * into v_cur from game.players where player_id = v_uid;
  if found then
    if v_cur.archetype <> '' then raise exception 'Akun ini sudah punya kapten. Kapten lama tidak bisa digabung.'; end if;
    delete from game.players where player_id = v_uid;   -- baris kosong otomatis dari login
  end if;

  update game.players set player_id = v_uid, username = u, last_active = now()
  where player_id = r.player_id
  returning character_name into v_name;
  if v_name is null then raise exception 'Data kapten lama tidak ditemukan. Hubungi admin game.'; end if;

  update game.legacy_accounts set claimed_at = now(), claimed_by = v_uid, player_id = v_uid where username = u;
  perform game.log(v_uid, 'Akun dipindahkan dari versi lama. Selamat datang kembali, ' || v_name || '!');
  return jsonb_build_object('ok', true, 'name', v_name);
end $$;
select game.expose('api_legacyclaim');

-- game.me(): sama seperti 0001, tapi tidak bentrok bila username masih dipegang kapten lama
-- yang belum diklaim (baris baru dibuat tanpa username; klaim nanti mengisinya).
create or replace function game.me(p_lock boolean default false) returns game.players
language plpgsql as $$
declare u uuid; r game.players; v_name text;
begin
  u := game.uid();
  if p_lock then
    select * into r from game.players where player_id = u for update;
  else
    select * into r from game.players where player_id = u;
  end if;
  if not found then
    v_name := nullif(game.auth_username(), '');
    if v_name is not null and exists (select 1 from game.players where username = v_name) then v_name := null; end if;
    insert into game.players(player_id, username) values (u, v_name)
    on conflict (player_id) do nothing;
    select * into r from game.players where player_id = u for update;
  elsif r.last_active < now() - interval '1 minute' then
    update game.players set last_active = now() where player_id = u;
  end if;
  return r;
end $$;
