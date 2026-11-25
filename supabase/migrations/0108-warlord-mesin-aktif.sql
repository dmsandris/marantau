-- =====================================================================
-- 0108 · Perbaikan: efek Mesin Jolt Warlord tidak terasa di pelayaran
--   Masalah: 0078 menurunkan SpeedMultiplier 0,24 -> 0,20, tetapi
--   voy_travel_seconds (0028) mengunci pengali di lantai 0,24 dan
--   TravelFastestSeconds (25 dtk). Hasilnya waktu tempuh pemilik Mesin Jolt
--   Warlord tetap sama persis dengan kapal Level V Tier IV biasa.
--   Perbaikan: bila kapal punya Mesin Jolt Warlord, waktu tempuh dikali
--   WarlordFastestSeconds / TravelFastestSeconds (20/25 = -20%), sehingga
--   pulau terdekat 25 -> 20 detik dan rute lain ikut lebih cepat sebanding.
--   Black Pearl (15 dtk) tidak disentuh. Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('WarlordFastestSeconds', '20')
on conflict (key) do nothing;

do $$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'game' and p.proname = 'voy_travel_seconds_wm') then
    alter function game.voy_travel_seconds(double precision, jsonb) rename to voy_travel_seconds_wm;
  end if;
end $$;
revoke all on function game.voy_travel_seconds_wm(double precision, jsonb) from public, anon, authenticated;

create or replace function game.voy_travel_seconds(p_distance double precision, p_ship jsonb) returns int
language plpgsql stable as $$
declare t int; lo numeric; fast numeric; wl numeric;
begin
  t := game.voy_travel_seconds_wm(p_distance, p_ship);
  if coalesce(p_ship ->> 'Legend', '') = 'pearl' and not coalesce((p_ship ->> 'LegendEast')::boolean, false) then
    return t;
  end if;
  if not coalesce(jsonb_typeof(p_ship -> 'Warlord') = 'array' and (p_ship -> 'Warlord') ? 'speed', false) then
    return t;
  end if;
  lo := greatest(10, game.cfg_num('TravelMinSeconds', 120));
  fast := least(lo, greatest(5, game.cfg_num('TravelFastestSeconds', 25)));
  wl := least(fast, greatest(5, game.cfg_num('WarlordFastestSeconds', 20)));
  return greatest(1, round(t * wl / fast))::int;
end $$;
