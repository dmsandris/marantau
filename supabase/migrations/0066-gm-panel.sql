-- =====================================================================
-- Marantau (Supabase) - 0066 PANEL GM RAPI  (Tide v50)
-- ---------------------------------------------------------------------
-- Arsip catatan Tony and Gank di daftar Panel GM.
-- "Hapus" di panel HANYA menyembunyikan baris dari daftar GM (gm_hidden_at).
-- Data event (game.tony_raid) dan korban (game.tony_victims) TIDAK dihapus,
-- jadi harta Tony untuk Perburuan Tony (game.th_harta) tidak berubah.
-- Hanya event berstatus selesai / batal yang boleh diarsipkan.
--
--   api_gmTonyArsip(['hide', {id}])   arsipkan satu event
--   api_gmTonyArsip(['hideDone'])     arsipkan semua event selesai / batal
-- Keduanya mengembalikan game.tony_list() seperti api_gmTony.
-- Aman diulang.
-- =====================================================================

alter table game.tony_raid add column if not exists gm_hidden_at timestamptz;

-- event yang sudah tidak berjalan (selesai atau dibatalkan)
create or replace function game.tony_raid_done(r game.tony_raid) returns boolean
language sql stable as $$ select r.cancelled_at is not null or now() >= r.end_at $$;

-- Daftar GM: sama dengan 0061, tetapi baris yang diarsipkan disembunyikan
create or replace function game.tony_list() returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'now', game.now_ms(),
    'cities', (select coalesce(jsonb_agg(jsonb_build_object('id', c.city_id, 'name', c.name, 'hidden', c.hidden) order by c.hidden, c.name), '[]'::jsonb)
                 from game.cities c where not game.spot_city(c.city_id) and c.city_id not like 'sudyrman%'),
    'raids', (select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint desc), '[]'::jsonb) from (
      select jsonb_build_object(
        'id', r.id, 'dest', r.dest_city, 'destName', (select name from game.cities where city_id = r.dest_city),
        'origin', r.origin_city, 'originName', (select name from game.cities where city_id = r.origin_city),
        'startAt', (extract(epoch from r.start_at) * 1000)::bigint, 'endAt', (extract(epoch from r.end_at) * 1000)::bigint,
        'chance', r.chance, 'goldPct', r.gold_pct, 'kabar', r.kabar, 'siar', r.announce_victims,
        'status', case when r.cancelled_at is not null then 'batal' when now() < r.start_at then 'terjadwal'
                       when now() < r.end_at then 'aktif' else 'selesai' end,
        'rolls', r.rolls, 'hits', r.hits,
        'korban', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result <> 'menang'),
        'lawan', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result = 'kalah'),
        'serah', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result in ('serah', 'auto')),
        'menang', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result = 'menang'),
        'gold', (select coalesce(sum(v.gold_taken), 0) from game.tony_victims v where v.raid_id = r.id),
        'cargoValue', (select coalesce(sum(v.cargo_value), 0) from game.tony_victims v where v.raid_id = r.id)) x
      from game.tony_raid r where r.gm_hidden_at is null order by r.id desc limit 20) q),
    'doneCount', (select count(*) from game.tony_raid r where r.gm_hidden_at is null and game.tony_raid_done(r))
  )
$$;

create or replace function public.api_gmTonyArsip(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), '')); o jsonb := game.arg_json(a, 1);
  r game.tony_raid;
begin
  if not game.is_gm(v_id) then raise exception 'Perintah ini khusus GM.'; end if;
  if jsonb_typeof(o) <> 'object' then o := '{}'::jsonb; end if;

  if v_act = 'hide' then
    select * into r from game.tony_raid where id = game.mp_jsnum(o ->> 'id', 0)::bigint for update;
    if r.id is null then raise exception 'Event tidak ditemukan.'; end if;
    if not game.tony_raid_done(r) then raise exception 'Event yang masih aktif / terjadwal tidak bisa dihapus dari daftar. Batalkan dulu.'; end if;
    update game.tony_raid set gm_hidden_at = now() where id = r.id and gm_hidden_at is null;

  elsif v_act = 'hidedone' then
    update game.tony_raid t set gm_hidden_at = now()
     where t.gm_hidden_at is null and game.tony_raid_done(t);

  else
    raise exception 'Perintah tidak dikenal: %', v_act;
  end if;

  return game.tony_list();
end $$;
select game.expose('api_gmtonyarsip');
