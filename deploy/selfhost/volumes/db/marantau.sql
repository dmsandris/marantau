-- Marantau: setelan role yang di Supabase cloud sudah bawaan, tapi tidak ikut pg_dump.
-- Hanya jalan sekali saat data Postgres masih kosong (docker-entrypoint-initdb.d).
-- Untuk server yang sudah jalan, workflow vps-deploy menjalankan ulang file ini (aman diulang).

alter role authenticated set statement_timeout = '8s';
alter role anon set statement_timeout = '3s';
alter role authenticator set statement_timeout = '8s';
alter role authenticator set lock_timeout = '8s';

create extension if not exists pg_stat_statements with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;

-- Role hanya-baca untuk connector Claude marantau-ops (1.6). Sandi diatur oleh vps-deploy.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'mt_ops_ro') then
    create role mt_ops_ro login nosuperuser nocreatedb nocreaterole inherit;
  end if;
end $$;
-- Sengaja TANPA pg_read_all_data: schema auth (hash sandi, token) tidak boleh terbaca.
alter role mt_ops_ro inherit;
grant pg_read_all_stats to mt_ops_ro with inherit true;
grant usage on schema extensions to mt_ops_ro;
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'game') then
    execute 'grant usage on schema game to mt_ops_ro';
    execute 'grant select on all tables in schema game to mt_ops_ro';
  end if;
end $$;
alter role mt_ops_ro set statement_timeout = '5s';
alter role mt_ops_ro set default_transaction_read_only = on;
