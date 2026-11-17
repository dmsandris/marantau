-- Dijalankan sebagai supabase_admin SETELAH migrasi di VM (tools/vps/migrate-vps.sh). Aman diulang.
-- Di cloud, role postgres boleh melakukan dua hal di bawah; di self-host belum tentu
-- (migrasi menangkap errornya sebagai WARNING). Di sini dipastikan dengan superuser.

-- 1) Gerbang pemeliharaan PostgREST (0036)
do $$
begin
  if to_regprocedure('public.mt_pre_request()') is not null then
    alter role authenticator set pgrst.db_pre_request = 'public.mt_pre_request';
  end if;
end $$;

-- 2) Kebijakan Realtime (0023b, 0026, 0030) - hanya bila fungsinya ada
do $$
begin
  if to_regclass('realtime.messages') is null then return; end if;
  if to_regprocedure('public.mt_rt_can_read(text)') is not null then
    drop policy if exists "marantau baca siaran" on realtime.messages;
    create policy "marantau baca siaran" on realtime.messages for select to authenticated
      using (realtime.messages.extension = 'broadcast' and public.mt_rt_can_read(realtime.topic()));
  end if;
  if to_regprocedure('public.mt_rt_duel_ok(text)') is not null then
    drop policy if exists "marantau kirim duel" on realtime.messages;
    create policy "marantau kirim duel" on realtime.messages for insert to authenticated
      with check (realtime.messages.extension = 'broadcast' and public.mt_rt_duel_ok(realtime.topic()));
  end if;
  if to_regprocedure('public.mt_rt_raid_ok(text)') is not null then
    drop policy if exists "marantau kirim serbuan" on realtime.messages;
    create policy "marantau kirim serbuan" on realtime.messages for insert to authenticated
      with check (realtime.messages.extension = 'broadcast' and public.mt_rt_raid_ok(realtime.topic()));
  end if;
end $$;

-- 3) Role hanya-baca connector/Panel Ops ikut membaca tabel game yang baru dibuat
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'mt_ops_ro') and to_regnamespace('game') is not null then
    grant usage on schema game to mt_ops_ro;
    grant select on all tables in schema game to mt_ops_ro;
  end if;
end $$;

select pg_notify('pgrst', 'reload config');
select pg_notify('pgrst', 'reload schema');

select 'Kebijakan Realtime: ' || count(*) from pg_policies where schemaname = 'realtime' and tablename = 'messages';
select 'pre-request: ' || coalesce((select array_to_string(setconfig, ',') from pg_db_role_setting s
  join pg_roles r on r.oid = s.setrole where r.rolname = 'authenticator'), '-');
