-- =====================================================================
-- Marantau (Supabase) - 0063 PERBURUAN TONY  (Tide v47)
-- Konsep: dokumen project claude/KONSEP-Perburuan-Tony.md (v1.1)
--
-- Setiap hari Rabu (WIB, tidak pernah diberitahukan), Ratu Marlya membuka Papan Armada di titik laut
-- KABUT ABU-ABU. Kabut Abu-abu hanya tampil di peta selama lobi terbuka (Rabu sampai Tony kabur).
-- Armada 2-4 kapten (minimal 20 Tanda Jasa, setor 10 Mesiu per percobaan) menyerbu armada Tony and Gank
-- memakai mesin Serbuan Bersama Quest 9 (tabel mp_raids dengan kind = 'tony').
--   Fase 1 Karung Pelindung (perisai Kantong Bolong, lambung tidak turun di bawah 70%)
--   Fase 2 Kabut (Bayang Lambung: peluang kena semua kapten turun)          -> sampai 55%
--   Fase 3 Pengait (Si Jepit: satu kapal tertambat 1 giliran: kemudi lurus, layar setengah) -> sampai 40%
--   Fase 4 Murka Tony (salvo ke semua kapal dalam jangkauan x1,6)           -> sampai 30%
--   Pertarungan Terakhir realtime 75 dtk: HP <= 10% -> Tony KABUR (menang). Waktu habis -> kalah.
-- Tony kabur meninggalkan 50% harta periode (gold dirampas + nilai muatan sejak terakhir kabur):
-- 70% sesuai porsi damage, 30% rata, untuk kapten armada pemenang. 50% sisanya hilang dari ekonomi.
-- Setelah kabur: lobi ditutup sampai Rabu berikutnya, harta dihitung dari 0.
-- Kalah: kapal lecet (tidak tenggelam, tidak dirampas), Tony pulih penuh untuk lobi berikutnya.
--
-- Kait (pola bungkus *_inti seperti 0061, isi asli tidak disalin):
--   game.spot_city, game.city_flavor, game.city_open, game.player_unlocks, game.quest_arrival_redirect
-- Stub di 0001b: th_sail_guard (dipanggil mp_sail_guard 0030), th_state (key 'tonyHunt' di 0010).
-- Uji / GM: config TonyHuntForce = on | off | '' (kosong = ikut hari Rabu). Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('TonyHuntForce', ''),
  ('TonyHuntDay', '3'),            -- ISO: Senin 1 ... Rabu 3 ... Minggu 7 (WIB)
  ('TonyHuntMesiu', '10')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Konstanta (selain yang di sini, ikut game.dt_k Quest 9)
-- ---------------------------------------------------------------------
create or replace function game.th_k(p_key text) returns float8
language sql immutable as $$
  select case p_key
    when 'boss_hull'   then 1100
    when 'boss_shield' then 200
    when 'boss_dmg'    then 6
    when 'fin_dmg'     then 8
    when 'murka_mul'   then 1.5
    when 'second_mul'  then 0.2
    when 'smoke_mul'   then 0.75   -- fase Kabut: peluang kena semua kapten
    when 'hook_dmg'    then 3      -- kapal yang tertambat pengait
    when 'p2_end'      then 0.55
    when 'p3_end'      then 0.40
    when 'final_at'    then 0.30
    when 'flee_at'     then 0.10   -- Tony kabur
    else game.dt_k(p_key) end
$$;

-- kekuatan armada Tony menyesuaikan jumlah kapal penyerbu (tanpa NPC sekutu, armada kecil tetap punya peluang)
create or replace function game.th_scale(p_n int) returns float8
language sql immutable as $$ select case when p_n <= 2 then 0.64 when p_n = 3 then 0.84 else 0.98 end::float8 $$;

create or replace function game.th_mesiu() returns int
language sql stable as $$ select greatest(0, game.cfg_num('TonyHuntMesiu', 10))::int $$;

-- ---------------------------------------------------------------------
-- Data perburuan
-- ---------------------------------------------------------------------
create table if not exists game.tony_hunts (
  id        bigserial primary key,
  hunt_day  date not null,              -- tanggal Rabu (WIB)
  raid_id   text,
  harta     bigint not null default 0,  -- harta periode saat Tony kabur
  pool      bigint not null default 0,  -- 50% yang ditinggalkan
  paid      bigint not null default 0,  -- yang benar-benar dibagikan (setelah pembulatan)
  shares    jsonb not null default '[]'::jsonb,   -- [{pid, n, dmg, gold}]
  kabur_at  timestamptz not null default now()
);
create index if not exists tony_hunts_day_idx on game.tony_hunts (hunt_day);
alter table game.tony_hunts enable row level security;

create or replace function game.th_now() returns bigint language sql stable as $$ select game.dt_now() $$;

-- tanggal & hari (WIB) dari jam serbuan
create or replace function game.th_day() returns date
language sql stable as $$ select (to_timestamp(game.th_now() / 1000.0) at time zone 'Asia/Jakarta')::date $$;

create or replace function game.th_rabu() returns boolean
language plpgsql stable as $$
declare f text := lower(coalesce(game.cfg('TonyHuntForce'), ''));
begin
  if f in ('on', '1', 'ya') then return true; end if;
  if f in ('off', '0', 'tidak') then return false; end if;
  return extract(isodow from (to_timestamp(game.th_now() / 1000.0) at time zone 'Asia/Jakarta'))::int = game.cfg_num('TonyHuntDay', 3)::int;
end $$;

-- lobi Marlya terbuka: hari Rabu dan Tony belum kabur hari ini
create or replace function game.th_open() returns boolean
language sql stable as $$ select game.th_rabu() and not exists (select 1 from game.tony_hunts where hunt_day = game.th_day()) $$;

create or replace function game.th_last_kabur() returns timestamptz
language sql stable as $$ select max(kabur_at) from game.tony_hunts $$;

-- harta Tony periode berjalan (sejak terakhir kabur)
create or replace function game.th_harta() returns bigint
language sql stable as $$
  select coalesce(sum(v.gold_taken + v.cargo_value), 0)::bigint from game.tony_victims v
   where v.result <> 'menang' and v.at > coalesce(game.th_last_kabur(), '-infinity'::timestamptz)
$$;

create or replace function game.th_eligible(p_pid uuid) returns boolean
language sql stable as $$ select game.gala_badges(p_pid) >= 20 $$;

create or replace function game.th_raid_of(p_pid uuid) returns text
language sql stable as $$
  select r.id from game.mp_raid_members m join game.mp_raids r on r.id = m.raid_id
   where m.player_id = p_pid and r.status in ('lobby', 'active') and m.state <> 'fled' and r.kind = 'tony'
   order by r.created desc limit 1
$$;

-- ---------------------------------------------------------------------
-- Titik laut Kabut Abu-abu
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('kabut_abu', 'Kabut Abu-abu', 'KabutAbu', 1.0, '', 36, 38, 19, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;
select game.cfg_set('CitiesVersion', '10-kabut-abu');

do $$
begin
  drop function if exists game.spot_city_inti(text);
  alter function game.spot_city(text) rename to spot_city_inti;
  drop function if exists game.city_flavor_inti(text);
  alter function game.city_flavor(text) rename to city_flavor_inti;
  drop function if exists game.city_open_inti(uuid, text);
  alter function game.city_open(uuid, text) rename to city_open_inti;
  drop function if exists game.player_unlocks_inti(uuid);
  alter function game.player_unlocks(uuid) rename to player_unlocks_inti;
  drop function if exists game.quest_arrival_redirect_inti(uuid, text, text);
  alter function game.quest_arrival_redirect(uuid, text, text) rename to quest_arrival_redirect_inti;
end $$;

create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select p_city = 'kabut_abu' or game.spot_city_inti(p_city) $$;

create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case when p_type = 'KabutAbu'
    then 'Kabut abu-abu yang tak pernah tersibak di tengah laut. Tak ada dermaga, tak ada pasar. Hanya pelikan mesin Ratu Marlya yang bertengger di pelampung, menjaga Papan Armada.'
    else game.city_flavor_inti(p_type) end
$$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language plpgsql stable as $$
begin
  if p_city = 'kabut_abu' then
    return coalesce(game.pasir_era(p_pid), 'kini') = 'kini' and game.th_open();
  end if;
  return game.city_open_inti(p_pid, p_city);
end $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare u jsonb := game.player_unlocks_inti(p_pid);
begin
  if coalesce(game.pasir_era(p_pid), 'kini') = 'kini' and game.th_open() then
    u := coalesce(u, '[]'::jsonb) || '["kabut_abu"]'::jsonb;
  end if;
  return u;
end $$;

-- kapal yang menuju Kabut Abu-abu saat lobi sudah ditutup: berbalik ke pelabuhan asal
create or replace function game.quest_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
begin
  if p_dest = 'kabut_abu' and not game.city_open(p_pid, 'kabut_abu') and p_origin is distinct from 'kabut_abu' then
    return jsonb_build_object('city', p_origin,
      'message', 'Kabut Abu-abu menebal dan menutup jalannya. Pelikan Marlya sudah terbang pulang. Kapalmu berbalik ke pelabuhan asal.');
  end if;
  return game.quest_arrival_redirect_inti(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Syarat bergabung
-- ---------------------------------------------------------------------
create or replace function game.th_join_block(p_pid uuid) returns text
language plpgsql as $$
declare v_slot text;
begin
  if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return 'Laut ini belum mengenal Tony, Kapten.'; end if;
  if not game.th_open() then return 'Pelikan Marlya sudah terbang pulang. Papan Armada tertutup.'; end if;
  if not game.th_eligible(p_pid) then return 'Pelikan Marlya memiringkan kepala: laut ini belum mengenal namamu.'; end if;
  if game.in_transit(p_pid) then return 'Merapat dulu di Kabut Abu-abu, Kapten.'; end if;
  if game.current_city(p_pid) is distinct from 'kabut_abu' then return 'Papan Armada Marlya ada di Kabut Abu-abu.'; end if;
  if game.dt_raid_of(p_pid) is not null then return 'Kau masih tercatat di armada Teluk Dua Tangan.'; end if;
  v_slot := game.mp_slot(p_pid);
  if v_slot is not null then
    perform game.mp_duel_refresh(v_slot);
    if game.mp_slot(p_pid) is not null then return 'Selesaikan duelmu dulu.'; end if;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Status untuk klien (key 'tonyHunt'). Tidak memuat jadwal, rumus, atau hadiah.
-- ---------------------------------------------------------------------
create or replace function game.th_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_open boolean; v_raid text; v_lob int; v_on int; v_kabur boolean;
begin
  if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return null; end if;
  v_open := game.th_open();
  v_raid := game.th_raid_of(p_pid);
  v_kabur := exists (select 1 from game.tony_hunts where hunt_day = game.th_day()) and game.th_rabu();
  if v_open then
    select count(*) into v_lob from game.mp_raids where status = 'lobby' and kind = 'tony';
    select count(*) into v_on from game.mp_presence o where game.mp_online(o) and o.player_id <> p_pid and game.th_eligible(o.player_id);
  end if;
  return jsonb_build_object('open', v_open, 'harta', game.th_harta(), 'kabur', v_kabur,
    'eligible', game.th_eligible(p_pid), 'raidId', v_raid, 'lobbies', coalesce(v_lob, 0), 'online', coalesce(v_on, 0),
    'mesiu', game.item_qty(p_pid, 'mesiu'), 'needMesiu', game.th_mesiu());
end $$;

-- ---------------------------------------------------------------------
-- Larangan berlayar selama lobi / serbuan (dipanggil mp_sail_guard)
-- ---------------------------------------------------------------------
create or replace function game.th_sail_guard(p_pid uuid) returns void
language plpgsql as $$
declare v_raid text; r game.mp_raids; v_n int; m game.mp_raid_members; o game.mp_presence; t bigint := game.th_now();
begin
  v_raid := game.th_raid_of(p_pid);
  if v_raid is null then return; end if;
  select * into r from game.mp_raids where id = v_raid for update;
  if r.status = 'lobby' then
    for m in select * from game.mp_raid_members where raid_id = r.id and player_id <> p_pid loop
      select * into o from game.mp_presence where player_id = m.player_id;
      if (not m.ready and t - m.joined_ms > game.th_k('ready_ms')) or not game.mp_online(o)
         or game.current_city(m.player_id) is distinct from 'kabut_abu' or game.in_transit(m.player_id) then
        r := game.dt_lobby_leave(r, m.player_id);
      end if;
    end loop;
    perform game.dt_save(r);
    if r.status = 'lobby' then
      select count(*) into v_n from game.mp_raid_members where raid_id = r.id;
      if v_n > 1 then raise exception 'Kau masih tercatat di Papan Armada Marlya. Keluar dari armada dulu sebelum berlayar.'; end if;
      r := game.dt_lobby_leave(r, p_pid); perform game.dt_save(r);
    end if;
  elsif r.status = 'active' then
    raise exception 'Armadamu sedang menyerbu Tony and Gank.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Pertempuran
-- ---------------------------------------------------------------------
create or replace function game.th_boss_hit(d float8, tf float8, mul float8) returns float8
language sql volatile as $$
  select case when d > game.th_k('boss_range') then 0
    else game.th_k('boss_dmg') * greatest(0.3, least(1.0, 1.15 - d / 520)) * tf * mul * (0.85 + random() * 0.3) end
$$;

-- satu giliran (60 langkah x 0,05 dtk). Turunan dt_resolve tanpa Black Pearl / Seruan / bekal Quest 8.
create or replace function game.th_resolve(r game.mp_raids, p_base bigint) returns game.mp_raids
language plpgsql as $$
declare
  s jsonb := r.st; w float8 := (r.st ->> 'w')::float8; sh jsonb; o jsonb;
  pubs text[]; n int; i int; j int; k int; t float8 := 0; dt float8 := 0.05; fired boolean := false;
  x float8[]; y float8[]; h float8[]; v float8[]; hull float8[]; sail float8[]; crew float8[]; rlL float8[]; rlR float8[];
  rud int[]; sl int[]; am text[]; fl boolean[]; fr boolean[]; on_ boolean[]; hooked boolean[];
  sp float8[]; tm float8[]; hm float8[]; rm float8[]; dm float8[]; tf float8[];
  alive boolean[]; reef float8[]; tr jsonb[]; ramcd float8[];
  B jsonb := r.st -> 'boss';
  bx float8; by_ float8; bh float8; bv float8; bhull float8; bmax float8; bsh float8; bphase int; brud int := 0;
  btr jsonb := '[]'::jsonb;
  sx float8 := game.th_k('stone_x'); sy float8 := game.th_k('stone_y'); sr float8 := game.th_k('stone_r'); br float8 := game.th_k('boss_r');
  rr_ float8; th float8; dd float8; bb float8; push float8; rv float8; mul float8; hmul float8;
  tgt int; tgt2 int; best float8; vol jsonb; raw float8; shd float8; hd float8; dmg float8;
  shots jsonb := '[]'::jsonb; evs jsonb := '[]'::jsonb; stats jsonb := coalesce(r.stats, '{}'::jsonb);
  d_sh float8 := 0; d_hull float8 := 0; v_any boolean; r_ float8[]; t_now bigint := game.th_now(); v_auto jsonb := '{}'::jsonb; v_side int;
  v_hook int; v_last_hook text := s ->> 'lastHook';
begin
  pubs := array(select jsonb_array_elements_text(s -> 'order'));
  n := coalesce(array_length(pubs, 1), 0);
  bx := (B ->> 'x')::float8; by_ := (B ->> 'y')::float8; bh := (B ->> 'h')::float8; bv := (B ->> 'v')::float8;
  bhull := (B ->> 'hull')::float8; bmax := (B ->> 'max')::float8; bsh := (B ->> 'shield')::float8; bphase := (B ->> 'phase')::int;
  hmul := case when bphase = 2 then game.th_k('smoke_mul') else 1 end;

  for i in 1..n loop
    sh := s -> 'ships' -> pubs[i];
    on_[i] := coalesce((sh ->> 'on')::boolean, true);
    alive[i] := coalesce((sh ->> 'alive')::boolean, true) and not coalesce((sh ->> 'fled')::boolean, false);
    hooked[i] := coalesce((sh ->> 'hooked')::boolean, false);
    o := r.ord -> pubs[i];
    if o is null then
      o := case when on_[i] then game.lb_auto(sh) else jsonb_build_object('rud', 0, 'sails', 0, 'fl', false, 'fr', false, 'ammo', coalesce(sh ->> 'ammo', 'ball'), 'auto', true) end;
      v_auto := v_auto || jsonb_build_object(pubs[i], case when on_[i] then 'late' else 'off' end);
    end if;
    x[i] := (sh ->> 'x')::float8; y[i] := (sh ->> 'y')::float8; h[i] := (sh ->> 'h')::float8; v[i] := (sh ->> 'v')::float8;
    hull[i] := (sh ->> 'hull')::float8; sail[i] := (sh ->> 'sail')::float8; crew[i] := (sh ->> 'crew')::float8;
    rlL[i] := coalesce((sh ->> 'rlL')::float8, 0); rlR[i] := coalesce((sh ->> 'rlR')::float8, 0);
    rud[i] := coalesce((o ->> 'rud')::int, 0); sl[i] := coalesce((o ->> 'sails')::int, 1); am[i] := coalesce(o ->> 'ammo', 'ball');
    fl[i] := coalesce((o ->> 'fl')::boolean, false); fr[i] := coalesce((o ->> 'fr')::boolean, false);
    sp[i] := coalesce((sh ->> 'sp')::float8, 1); tm[i] := coalesce((sh ->> 'tm')::float8, 1); hm[i] := coalesce((sh ->> 'hm')::float8, 1);
    rm[i] := coalesce((sh ->> 'rm')::float8, 1); dm[i] := coalesce((sh ->> 'dm')::float8, 1); tf[i] := coalesce((sh ->> 'tf')::float8, 1);
    reef[i] := 0; ramcd[i] := 0; tr[i] := '[]'::jsonb;
    -- tertambat pengait Si Jepit: kemudi terkunci lurus & layar setengah giliran ini (meriam tetap bisa ditembakkan)
    if hooked[i] and alive[i] then rud[i] := 0; sl[i] := 0; end if;
    if not alive[i] then rud[i] := 0; sl[i] := 0; fl[i] := false; fr[i] := false; v[i] := 0; end if;
  end loop;

  -- AI: kejar kapal terdekat
  tgt := null; best := 1e9;
  for i in 1..n loop
    if alive[i] then
      dd := game.dt_dist(x[i], y[i], bx, by_);
      if dd < best then best := dd; tgt := i; end if;
    end if;
  end loop;
  if tgt is not null then brud := game.dt_boss_rud(bx, by_, bh, x[tgt], y[tgt]); end if;

  for k in 1..60 loop
    for i in 1..n loop
      if alive[i] then
        r_ := game.lb_step(x[i], y[i], h[i], v[i], rud[i], sl[i], sail[i], dt, w, sp[i], tm[i]);
        x[i] := r_[1]; y[i] := r_[2]; h[i] := r_[3]; v[i] := r_[4];
        if r_[5] = 1 and reef[i] <= 0 then hull[i] := greatest(0, hull[i] - 2.5 * tf[i]); reef[i] := 1.2; end if;
        reef[i] := reef[i] - dt;
        rr_ := game.dt_dist(x[i], y[i], sx, sy);
        if rr_ < sr + 30 then
          th := atan2(y[i] - sy, x[i] - sx);
          x[i] := sx + cos(th) * (sr + 30); y[i] := sy + sin(th) * (sr + 30); v[i] := v[i] * 0.5;
        end if;
        x[i] := greatest(60, least(2140, x[i])); y[i] := greatest(60, least(1440, y[i]));
      end if;
      rlL[i] := greatest(0, rlL[i] - dt); rlR[i] := greatest(0, rlR[i] - dt); ramcd[i] := ramcd[i] - dt;
    end loop;
    r_ := game.lb_step(bx, by_, bh, bv, brud, 1, 100, dt, w, game.th_k('boss_sp'), game.th_k('boss_tm'));
    bx := r_[1]; by_ := r_[2]; bh := r_[3]; bv := r_[4];
    rr_ := game.dt_dist(bx, by_, sx, sy);
    if rr_ < sr + br then th := atan2(by_ - sy, bx - sx); bx := sx + cos(th) * (sr + br); by_ := sy + sin(th) * (sr + br); bv := bv * 0.5; end if;
    t := t + dt;

    if not fired and t >= 1.0 - 1e-9 then
      fired := true;
      for i in 1..n loop
        for j in 1..2 loop
          v_side := case when j = 1 then -1 else 1 end;
          if alive[i] and ((j = 1 and fl[i] and rlL[i] <= 0) or (j = 2 and fr[i] and rlR[i] <= 0)) then
            vol := game.dt_volley_boss(x[i], y[i], h[i], bx, by_, v_side, am[i], crew[i], dm[i], hm[i] * hmul);
            if j = 1 then rlL[i] := game.lb_reload(crew[i]) * rm[i] * game.th_k('reload_mul'); else rlR[i] := game.lb_reload(crew[i]) * rm[i] * game.th_k('reload_mul'); end if;
            raw := (vol ->> 'hull')::float8 + (vol ->> 'sail')::float8 * 0.6 + (vol ->> 'crew')::float8 * 0.4;
            shd := 0; hd := 0;
            if bsh > 0 then
              shd := ((vol ->> 'hull')::float8 + (vol ->> 'sail')::float8) * case when am[i] = 'chain' then 2 else 1 end;
              hd := raw * 0.25;
            else
              hd := raw;
            end if;
            d_sh := d_sh + shd; d_hull := d_hull + hd;
            if shd > 0 then stats := game.dt_stat_add(stats, pubs[i], 'shield', shd); end if;
            if hd > 0 then stats := game.dt_stat_add(stats, pubs[i], 'hull', hd); end if;
            shots := shots || jsonb_build_array(vol || jsonb_build_object('by', pubs[i], 'side', v_side, 'ammo', am[i],
              'fx', round(x[i]::numeric, 1), 'fy', round(y[i]::numeric, 1), 'fh', round(h[i]::numeric, 3),
              'tx', round(bx::numeric, 1), 'ty', round(by_::numeric, 1), 'sh', round(shd::numeric, 2), 'dmg', round(hd::numeric, 2)));
          end if;
        end loop;
      end loop;
      -- armada Tony menembak
      mul := case when bphase = 4 then game.th_k('murka_mul') else 1 end;
      for i in 1..n loop
        if alive[i] then
          dd := game.dt_dist(x[i], y[i], bx, by_);
          dmg := 0;
          if bphase = 4 then dmg := game.th_boss_hit(dd, tf[i], mul);
          elsif i = tgt then dmg := game.th_boss_hit(dd, tf[i], mul);
          end if;
          if hooked[i] then dmg := dmg + game.th_k('hook_dmg') * tf[i]; end if;
          if dmg > 0 then
            hull[i] := greatest(0, hull[i] - dmg); crew[i] := greatest(0, crew[i] - dmg * 0.12); sail[i] := greatest(0, sail[i] - dmg * 0.2);
            stats := game.dt_stat_add(stats, pubs[i], 'taken', dmg);
            shots := shots || jsonb_build_array(jsonb_build_object('by', 'boss', 'to', pubs[i], 'fx', round(bx::numeric, 1), 'fy', round(by_::numeric, 1),
              'tx', round(x[i]::numeric, 1), 'ty', round(y[i]::numeric, 1), 'dmg', round(dmg::numeric, 2)));
          end if;
        end if;
      end loop;
      if bphase < 4 then
        tgt2 := null; best := 1e9;
        for i in 1..n loop
          if alive[i] and i is distinct from tgt then
            dd := game.dt_dist(x[i], y[i], bx, by_);
            if dd < best then best := dd; tgt2 := i; end if;
          end if;
        end loop;
        if tgt2 is not null then
          dmg := game.th_boss_hit(best, tf[tgt2], game.th_k('second_mul'));
          if dmg > 0 then
            hull[tgt2] := greatest(0, hull[tgt2] - dmg); crew[tgt2] := greatest(0, crew[tgt2] - dmg * 0.12);
            stats := game.dt_stat_add(stats, pubs[tgt2], 'taken', dmg);
            shots := shots || jsonb_build_array(jsonb_build_object('by', 'boss', 'to', pubs[tgt2], 'fx', round(bx::numeric, 1), 'fy', round(by_::numeric, 1),
              'tx', round(x[tgt2]::numeric, 1), 'ty', round(y[tgt2]::numeric, 1), 'dmg', round(dmg::numeric, 2)));
          end if;
        end if;
      end if;
      if bsh > 0 then
        bsh := greatest(0, bsh - d_sh);
        bhull := greatest(bmax * 0.70 + 1, bhull - d_hull);
      else
        bhull := greatest(0, bhull - d_hull);
      end if;
    end if;

    for i in 1..n loop
      if alive[i] then
        dd := game.dt_dist(x[i], y[i], bx, by_);
        if dd < br then
          bb := atan2(x[i] - bx, -(y[i] - by_)); push := br - dd + 1;
          x[i] := x[i] + sin(bb) * push; y[i] := y[i] - cos(bb) * push;
          if ramcd[i] <= 0 then
            rv := v[i] + bv * 0.5;
            hull[i] := greatest(0, hull[i] - (2 + rv * 0.06) * tf[i]);
            v[i] := v[i] * 0.4; ramcd[i] := 1.0;
            evs := evs || jsonb_build_array(jsonb_build_object('k', 'ram', 'by', pubs[i]));
          end if;
        end if;
        for j in (i + 1)..n loop
          if alive[j] then
            dd := game.dt_dist(x[i], y[i], x[j], y[j]);
            if dd < 58 then
              bb := atan2(x[j] - x[i], -(y[j] - y[i])); push := (58 - dd) / 2 + 1;
              x[i] := x[i] - sin(bb) * push; y[i] := y[i] + cos(bb) * push; x[j] := x[j] + sin(bb) * push; y[j] := y[j] - cos(bb) * push;
            end if;
          end if;
        end loop;
      end if;
    end loop;

    if k % 5 = 0 then
      for i in 1..n loop tr[i] := tr[i] || jsonb_build_array(jsonb_build_array(round(x[i]::numeric, 1), round(y[i]::numeric, 1), round(h[i]::numeric, 3))); end loop;
      btr := btr || jsonb_build_array(jsonb_build_array(round(bx::numeric, 1), round(by_::numeric, 1), round(bh::numeric, 3)));
    end if;
  end loop;

  for i in 1..n loop
    if alive[i] and (hull[i] <= 0 or crew[i] <= 0) then
      alive[i] := false;
      evs := evs || jsonb_build_array(jsonb_build_object('k', 'sunk', 'by', pubs[i]));
      update game.mp_raid_members set state = 'sunk' where raid_id = r.id and pub = pubs[i] and state = 'in';
    end if;
    hooked[i] := false;
  end loop;

  -- pergantian fase
  if bphase = 1 and bsh <= 0 then
    bphase := 2; bhull := least(bhull, bmax * 0.70);
    evs := evs || jsonb_build_array(jsonb_build_object('k', 'phase', 'p', 2));
  end if;
  if bphase = 2 and bhull <= bmax * game.th_k('p2_end') then
    bphase := 3; evs := evs || jsonb_build_array(jsonb_build_object('k', 'phase', 'p', 3));
  end if;
  if bphase = 3 and bhull <= bmax * game.th_k('p3_end') then
    bphase := 4; evs := evs || jsonb_build_array(jsonb_build_object('k', 'phase', 'p', 4));
  end if;

  -- fase Pengait: Si Jepit menambatkan kapal terdekat (bukan yang sama dua kali berturut-turut) untuk giliran berikut
  if bphase = 3 then
    v_hook := null; best := 1e9;
    for i in 1..n loop
      if alive[i] and pubs[i] is distinct from v_last_hook then
        dd := game.dt_dist(x[i], y[i], bx, by_);
        if dd < best then best := dd; v_hook := i; end if;
      end if;
    end loop;
    if v_hook is null then
      for i in 1..n loop if alive[i] then v_hook := i; end if; end loop;
    end if;
    if v_hook is not null and best < 700 then
      hooked[v_hook] := true; v_last_hook := pubs[v_hook];
      evs := evs || jsonb_build_array(jsonb_build_object('k', 'hooked', 'by', pubs[v_hook]));
    end if;
  end if;

  for i in 1..n loop
    s := jsonb_set(s, array['ships', pubs[i]], (s -> 'ships' -> pubs[i]) || jsonb_build_object(
      'x', x[i], 'y', y[i], 'h', h[i], 'v', v[i], 'hull', hull[i], 'sail', sail[i], 'crew', crew[i], 'rlL', rlL[i], 'rlR', rlR[i],
      'rud', rud[i], 'sails', sl[i], 'ammo', am[i], 'alive', alive[i], 'hooked', hooked[i]));
  end loop;
  s := s || jsonb_build_object('w', game.lb_ang(w + (random() - 0.5) * 0.4), 'lastHook', v_last_hook,
    'boss', B || jsonb_build_object('x', bx, 'y', by_, 'h', bh, 'v', bv, 'hull', bhull, 'shield', bsh, 'phase', bphase, 'stun', false));

  r.ev := jsonb_build_object('r', r.round, 'start', r.st, 'ord', r.ord, 'auto', v_auto, 'shots', shots, 'evs', evs,
    'tracks', (select jsonb_object_agg(pubs[q], tr[q]) from generate_series(1, n) q), 'boss', btr, 'pearl', null,
    'cine', null, 'dHull', round(d_hull::numeric, 1), 'dShield', round(d_sh::numeric, 1));
  r.st := s; r.stats := stats; r.ord := '{}'::jsonb;
  r.log := r.log || jsonb_build_array(jsonb_build_object('r', r.round, 'boss', round(bhull::numeric), 'sh', round(bsh::numeric), 'p', bphase));
  while jsonb_array_length(r.log) > 80 loop r.log := r.log - 0; end loop;

  v_any := false;
  for i in 1..n loop if alive[i] then v_any := true; end if; end loop;
  if not v_any then return game.th_finish(r, 'loss'); end if;

  if (bphase = 4 and bhull <= bmax * game.th_k('final_at')) or r.round >= game.th_k('max_rounds') then
    return game.dt_final_start(r, greatest(p_base, t_now) + game.th_k('anim_ms')::bigint);
  end if;
  r.round := r.round + 1;
  r.round_ts := p_base + game.th_k('anim_ms')::bigint;
  return r;
end $$;

-- Pertarungan Terakhir: majukan Tangan Panjang, salvo armada (tanpa Black Pearl / sekutu)
create or replace function game.th_final_tick(r game.mp_raids, p_now bigint) returns game.mp_raids
language plpgsql as $$
declare
  fb jsonb := r.st -> 'fb'; B jsonb := r.st -> 'boss'; w float8 := (r.st ->> 'w')::float8;
  t bigint; steps int; k int; rr float8[]; bx float8; by_ float8; bh float8; bv float8; brud int;
  pubs text[]; n int; i int; xs float8[]; ys float8[]; al boolean[]; tfs float8[];
  best float8; tgt int; best2 float8; tgt2 int; dd float8; dmg float8; v_end bigint := r.final_ts + game.th_k('final_ms')::bigint; sh jsonb; rt game.mp_raid_rt;
  v_any boolean; th float8; sx float8 := game.th_k('stone_x'); sy float8 := game.th_k('stone_y'); sr float8 := game.th_k('stone_r');
  fire_at bigint; ai_at bigint; hl float8; v_flee float8 := (B ->> 'max')::float8 * game.th_k('flee_at');
begin
  if r.status <> 'active' or r.phase <> 'final' then return r; end if;
  t := greatest(coalesce((fb ->> 't')::bigint, r.final_ts), r.final_ts);
  p_now := least(p_now, v_end);
  if p_now <= t then
    if game.th_now() > v_end then return game.th_finish(r, 'loss'); end if;
    return r;
  end if;
  pubs := array(select jsonb_array_elements_text(r.st -> 'order'));
  n := coalesce(array_length(pubs, 1), 0);
  for i in 1..n loop
    sh := r.st -> 'ships' -> pubs[i];
    select * into rt from game.mp_raid_rt where raid_id = r.id and pub = pubs[i];
    xs[i] := coalesce((rt.st ->> 'x')::float8, (sh ->> 'x')::float8); ys[i] := coalesce((rt.st ->> 'y')::float8, (sh ->> 'y')::float8);
    al[i] := coalesce((sh ->> 'alive')::boolean, true) and not coalesce((sh ->> 'fled')::boolean, false);
    tfs[i] := coalesce((sh ->> 'tf')::float8, 1);
  end loop;
  bx := (B ->> 'x')::float8; by_ := (B ->> 'y')::float8; bh := (B ->> 'h')::float8; bv := (B ->> 'v')::float8;
  brud := coalesce((fb ->> 'rud')::int, 0);
  fire_at := (fb ->> 'fireAt')::bigint; ai_at := (fb ->> 'aiAt')::bigint;
  steps := floor((p_now - t) / 50.0);
  if steps > 240 then t := p_now - 240 * 50; steps := 240; end if;
  for k in 1..steps loop
    t := t + 50;
    if t >= ai_at then
      tgt := null; best := 1e9;
      for i in 1..n loop
        if al[i] then dd := game.dt_dist(xs[i], ys[i], bx, by_); if dd < best then best := dd; tgt := i; end if; end if;
      end loop;
      brud := case when tgt is null then 0 else game.dt_boss_rud(bx, by_, bh, xs[tgt], ys[tgt]) end;
      ai_at := t + 1000;
    end if;
    rr := game.lb_step(bx, by_, bh, bv, brud, 1, 100, 0.05, w, game.th_k('boss_sp'), game.th_k('boss_tm'));
    bx := rr[1]; by_ := rr[2]; bh := rr[3]; bv := rr[4];
    dd := game.dt_dist(bx, by_, sx, sy);
    if dd < sr + game.th_k('boss_r') then th := atan2(by_ - sy, bx - sx); bx := sx + cos(th) * (sr + game.th_k('boss_r')); by_ := sy + sin(th) * (sr + game.th_k('boss_r')); bv := bv * 0.5; end if;
    if t >= fire_at then
      fire_at := t + game.th_k('fin_fire_ms')::bigint;
      tgt := null; tgt2 := null; best := 1e9; best2 := 1e9;
      for i in 1..n loop
        if al[i] then
          dd := game.dt_dist(xs[i], ys[i], bx, by_);
          if dd < best then best2 := best; tgt2 := tgt; best := dd; tgt := i;
          elsif dd < best2 then best2 := dd; tgt2 := i; end if;
        end if;
      end loop;
      for i in 1..n loop
        if al[i] and (i = tgt or i = tgt2) then
          dd := game.dt_dist(xs[i], ys[i], bx, by_);
          if dd <= game.th_k('boss_range') then
            dmg := game.th_k('fin_dmg') * greatest(0.3, least(1.0, 1.15 - dd / 520)) * tfs[i] * (0.85 + random() * 0.3) * case when i = tgt then 1 else game.th_k('second_mul') end;
            hl := greatest(0, (r.st -> 'ships' -> pubs[i] ->> 'hull')::float8 - dmg);
            r.st := jsonb_set(r.st, array['ships', pubs[i], 'hull'], to_jsonb(hl));
            r.st := jsonb_set(r.st, array['ships', pubs[i], 'crew'], to_jsonb(greatest(0, (r.st -> 'ships' -> pubs[i] ->> 'crew')::float8 - dmg * 0.1)));
            r.stats := game.dt_stat_add(r.stats, pubs[i], 'taken', dmg);
            perform game.dt_rtev(r.id, jsonb_build_object('k', 'bs', 'to', pubs[i], 'dmg', round(dmg::numeric, 1), 'hull', round(hl::numeric, 1),
              'fx', round(bx::numeric), 'fy', round(by_::numeric), 'tx', round(xs[i]::numeric), 'ty', round(ys[i]::numeric), 't', t), t);
            if hl <= 0 then
              al[i] := false;
              r.st := jsonb_set(r.st, array['ships', pubs[i], 'alive'], 'false'::jsonb);
              update game.mp_raid_members set state = 'sunk' where raid_id = r.id and pub = pubs[i] and state = 'in';
              perform game.dt_rtev(r.id, jsonb_build_object('k', 'sunk', 'by', pubs[i], 't', t), t);
            end if;
          end if;
        end if;
      end loop;
    end if;
    exit when (r.st -> 'boss' ->> 'hull')::float8 <= v_flee;
  end loop;
  r.st := jsonb_set(r.st, '{boss}', (r.st -> 'boss') || jsonb_build_object('x', bx, 'y', by_, 'h', bh, 'v', bv));
  r.st := jsonb_set(r.st, '{fb}', fb || jsonb_build_object('t', t, 'rud', brud, 'fireAt', fire_at, 'aiAt', ai_at));
  if (r.st -> 'boss' ->> 'hull')::float8 <= v_flee then return game.th_finish(r, 'win'); end if;
  v_any := false;
  for i in 1..n loop if al[i] then v_any := true; end if; end loop;
  if not v_any then return game.th_finish(r, 'loss'); end if;
  if game.th_now() > v_end then return game.th_finish(r, 'loss'); end if;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Tony kabur: bagi jarahan (70% porsi damage, 30% rata), tutup lobi, harta kembali 0
-- ---------------------------------------------------------------------
create or replace function game.th_payout(r game.mp_raids) returns jsonb
language plpgsql as $$
declare v_harta bigint := game.th_harta(); v_pool bigint; a70 bigint; a30 bigint; v_n int; v_tot float8 := 0;
  m game.mp_raid_members; st jsonb; dmg float8; g bigint; v_paid bigint := 0; v_shares jsonb := '[]'::jsonb; v_map jsonb := '{}'::jsonb;
begin
  v_pool := floor(v_harta * 0.5)::bigint;
  a70 := floor(v_pool * 0.7)::bigint;
  a30 := floor(v_pool * 0.3)::bigint;
  select count(*) into v_n from game.mp_raid_members where raid_id = r.id and state <> 'fled';
  for m in select * from game.mp_raid_members where raid_id = r.id and state <> 'fled' loop
    st := coalesce(r.stats -> m.pub, '{}'::jsonb);
    v_tot := v_tot + coalesce((st ->> 'hull')::float8, 0) + coalesce((st ->> 'shield')::float8, 0) + coalesce((st ->> 'board')::float8, 0);
  end loop;
  for m in select * from game.mp_raid_members where raid_id = r.id and state <> 'fled' order by joined_ms loop
    st := coalesce(r.stats -> m.pub, '{}'::jsonb);
    dmg := coalesce((st ->> 'hull')::float8, 0) + coalesce((st ->> 'shield')::float8, 0) + coalesce((st ->> 'board')::float8, 0);
    g := case when v_tot > 0 then floor(a70 * dmg / v_tot)::bigint else floor(a70::float8 / greatest(1, v_n))::bigint end
       + floor(a30::float8 / greatest(1, v_n))::bigint;
    if g > 0 then update game.players set gold = gold + g where player_id = m.player_id; end if;
    v_paid := v_paid + g;
    v_shares := v_shares || jsonb_build_array(jsonb_build_object('pid', m.player_id, 'n', m.n, 'dmg', round(dmg::numeric, 1), 'gold', g));
    v_map := v_map || jsonb_build_object(m.pub, g);
    perform game.log(m.player_id, case when g > 0
      then 'Tony and Gank kabur ke dalam kabut. Dari peti-peti jarahan yang tertinggal, kau mengangkut ' || g || ' gold.'
      else 'Tony and Gank kabur ke dalam kabut. Peti-petinya kosong pekan ini.' end);
  end loop;
  insert into game.tony_hunts(hunt_day, raid_id, harta, pool, paid, shares, kabur_at)
  values (game.th_day(), r.id, v_harta, v_pool, v_paid, v_shares, now());
  return jsonb_build_object('harta', v_harta, 'pool', v_pool, 'paid', v_paid, 'by', v_map);
end $$;

-- lobi lain ditutup; serbuan lain yang masih berjalan berakhir (Tony sudah kabur lewat jalur lain)
create or replace function game.th_close_others(p_except text) returns void
language plpgsql as $$
declare v_id text; r game.mp_raids; m game.mp_raid_members;
begin
  for v_id in select id from game.mp_raids where kind = 'tony' and status in ('lobby', 'active') and id is distinct from p_except loop
    select * into r from game.mp_raids where id = v_id for update;
    if r.status = 'lobby' then
      for m in select * from game.mp_raid_members where raid_id = r.id loop
        perform game.dt_refund(r.id, m.player_id);
        perform game.mp_rt('player:' || m.pub, 'raid', jsonb_build_object('raidId', r.id, 'status', 'cancelled'));
      end loop;
      r.status := 'cancelled'; r.ended := game.th_now(); perform game.dt_save(r);
    elsif r.status = 'active' then
      r.st := r.st || '{"other": true}'::jsonb;
      r := game.th_finish(r, 'loss'); perform game.dt_save(r);
    end if;
  end loop;
end $$;

create or replace function game.th_finish(r game.mp_raids, p_result text) returns game.mp_raids
language plpgsql as $$
declare m game.mp_raid_members; sh jsonb; frac float8; cond numeric; st jsonb; v_rows jsonb := '[]'::jsonb; v_n int; v_dur bigint;
  v_pay jsonb; v_names text; v_other boolean := coalesce((r.st ->> 'other')::boolean, false);
begin
  -- Tony sudah kabur lewat armada lain sebelum armada ini menang: tidak ada jarahan ganda
  if p_result = 'win' and exists (select 1 from game.tony_hunts where hunt_day = game.th_day()) then
    p_result := 'loss'; v_other := true;
  end if;
  r.status := 'done'; r.result := p_result; r.ended := game.th_now(); r.phase := coalesce(r.phase, 'plan');
  v_dur := r.ended - coalesce(r.started, r.created);
  select count(*) into v_n from game.mp_raid_members where raid_id = r.id;
  if p_result = 'win' then v_pay := game.th_payout(r); end if;
  for m in select * from game.mp_raid_members where raid_id = r.id order by joined_ms loop
    sh := r.st -> 'ships' -> m.pub;
    st := coalesce(r.stats -> m.pub, '{}'::jsonb);
    if sh is not null then
      frac := greatest(0, least(1, (sh ->> 'hull')::float8 / greatest(1, (sh ->> 'hull0')::float8)));
      select condition into cond from game.ships where player_id = m.player_id;
      update game.ships set condition = greatest(5, round(coalesce(cond, 100) * (0.35 + 0.65 * frac)))
       where player_id = m.player_id and condition > greatest(5, round(coalesce(cond, 100) * (0.35 + 0.65 * frac)));
    end if;
    if p_result <> 'win' then
      perform game.log(m.player_id, case
        when v_other then 'Tony and Gank sudah kabur lewat jalur lain. Armadamu kembali ke Kabut Abu-abu.'
        when m.state = 'fled' then 'Kau mundur dari kepungan Tony and Gank.'
        else 'Serbuan gagal. Tony tertawa dari geladak Tangan Panjang dan menghilang ke kabut. Kapalnya akan pulih sebelum armada berikutnya datang.' end);
    end if;
    v_rows := v_rows || jsonb_build_array(jsonb_build_object('pub', m.pub, 'n', m.n, 'vet', false, 'state', m.state,
      'hull', round(coalesce((st ->> 'hull')::float8, 0) + coalesce((st ->> 'board')::float8, 0)),
      'shield', round(coalesce((st ->> 'shield')::float8, 0)), 'cry', 0,
      'boards', coalesce((st ->> 'boards')::numeric::int, 0), 'taken', round(coalesce((st ->> 'taken')::float8, 0)),
      'endHull', round(coalesce((sh ->> 'hull')::float8, 0)), 'hull0', round(coalesce((sh ->> 'hull0')::float8, 0)),
      'paid', 0, 'loot', coalesce((v_pay -> 'by' ->> m.pub)::bigint, 0), 'ship', coalesce(m.fighter ->> 'shipName', ''),
      'tier', m.fighter -> 'tier', 'a', m.fighter -> 'a', 'f', coalesce(m.fighter -> 'f', 'null'::jsonb)));
    perform game.mp_rt('player:' || m.pub, 'raid', jsonb_build_object('raidId', r.id, 'status', 'done', 'result', p_result));
  end loop;
  r.card := jsonb_build_object('id', r.id, 'kind', 'tony', 'result', p_result, 'ships', v_n, 'rounds', r.round, 'durMs', v_dur,
    'rows', v_rows, 'at', r.ended, 'other', v_other, 'empty', p_result = 'win' and coalesce((v_pay ->> 'paid')::bigint, 0) = 0,
    'boss', round((r.st -> 'boss' ->> 'hull')::numeric), 'bossMax', round((r.st -> 'boss' ->> 'max')::numeric));
  delete from game.mp_raid_rt where raid_id = r.id;
  if p_result = 'win' then
    select string_agg('Kapten ' || n, ', ' order by joined_ms) into v_names from game.mp_raid_members where raid_id = r.id and state <> 'fled';
    perform game.sys_chat('Kabar Laut', 'Tony and Gank kabur ke dalam kabut setelah digempur ' || coalesce(v_names, 'para kapten') || '! Peti-peti jarahan tertinggal di laut.');
    perform game.dt_save(r);
    perform game.th_close_others(r.id);
  end if;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Lobi & giliran
-- ---------------------------------------------------------------------
create or replace function game.th_depart(r game.mp_raids) returns game.mp_raids
language plpgsql as $$
declare m game.mp_raid_members; f jsonb; s jsonb; ships jsonb := '{}'::jsonb; ord jsonb := '[]'::jsonb; i int := 0; n int;
  sx float8 := game.th_k('stone_x'); x0 float8; v_now bigint := game.th_now();
begin
  if not game.th_open() then raise exception 'Pelikan Marlya sudah terbang pulang. Papan Armada tertutup.'; end if;
  for m in select * from game.mp_raid_members where raid_id = r.id and not ready loop
    perform game.dt_refund(r.id, m.player_id);
    delete from game.mp_raid_members where raid_id = r.id and player_id = m.player_id;
  end loop;
  select count(*) into n from game.mp_raid_members where raid_id = r.id;
  if n < 2 then raise exception 'Butuh minimal dua kapten yang siap.'; end if;
  for m in select * from game.mp_raid_members where raid_id = r.id order by joined_ms loop
    i := i + 1;
    begin f := game.mp_fighter(m.player_id); exception when others then f := m.fighter; end;
    x0 := sx - (n - 1) * 110 + (i - 1) * 220;
    s := game.lb_ship0(f, x0, 1290, 0) || jsonb_build_object('pub', m.pub, 'n', m.n, 'vet', false, 'hull0', (game.lb_power(f) ->> 'hull0')::float8,
      'alive', true, 'fled', false, 'on', true, 'hooked', false, 'shipName', coalesce(f ->> 'shipName', ''), 'tier', f -> 'tier');
    ships := ships || jsonb_build_object(m.pub, s);
    ord := ord || to_jsonb(m.pub);
    update game.mp_raid_members set fighter = f, seen_ms = greatest(seen_ms, v_now) where raid_id = r.id and player_id = m.player_id;
  end loop;
  r.st := jsonb_build_object('w', random() * 2 * pi() - pi(), 'ships', ships, 'order', ord,
    'boss', jsonb_build_object('x', sx, 'y', 330, 'h', pi() / 2, 'v', 18,
      'hull', round(game.th_k('boss_hull') * game.th_scale(n)), 'max', round(game.th_k('boss_hull') * game.th_scale(n)),
      'shield', round(game.th_k('boss_shield') * game.th_scale(n)), 'shMax', round(game.th_k('boss_shield') * game.th_scale(n)), 'phase', 1, 'stun', false));
  r.status := 'active'; r.phase := 'plan'; r.round := 1; r.started := v_now; r.depart_at := null;
  r.round_ts := v_now + game.th_k('start_ms')::bigint; r.ord := '{}'::jsonb; r.stats := '{}'::jsonb; r.ev := null;
  return r;
end $$;

create or replace function game.th_tick(r game.mp_raids) returns game.mp_raids
language plpgsql as $$
declare t bigint := game.th_now(); m game.mp_raid_members; n int; v_base bigint; i int; v_all boolean; o game.mp_presence;
begin
  if r.status = 'lobby' then
    if not game.th_open() then
      for m in select * from game.mp_raid_members where raid_id = r.id loop perform game.dt_refund(r.id, m.player_id); end loop;
      r.status := 'cancelled'; r.ended := t; return r;
    end if;
    for m in select * from game.mp_raid_members where raid_id = r.id loop
      select * into o from game.mp_presence where player_id = m.player_id;
      if (not m.ready and t - m.joined_ms > game.th_k('ready_ms')) or not game.mp_online(o)
         or game.current_city(m.player_id) is distinct from 'kabut_abu' or game.in_transit(m.player_id) then
        r := game.dt_lobby_leave(r, m.player_id);
        exit when r.status <> 'lobby';
      end if;
    end loop;
    if r.status <> 'lobby' then return r; end if;
    select count(*), bool_and(ready) into n, v_all from game.mp_raid_members where raid_id = r.id;
    if n >= 4 and v_all then
      if r.depart_at is null then r.depart_at := t + game.th_k('auto_ms')::bigint;
      elsif t >= r.depart_at then
        begin r := game.th_depart(r); exception when others then r.depart_at := null; end;
      end if;
    else
      r.depart_at := null;
    end if;
    return r;
  end if;
  if r.status <> 'active' then return r; end if;
  if (select max(seen_ms) from game.mp_raid_members where raid_id = r.id and state = 'in') < t - game.th_k('abandon_ms') then
    return game.th_finish(r, 'loss');
  end if;
  if r.phase = 'final' then return game.th_final_tick(r, t); end if;
  for i in 1..40 loop
    exit when r.status <> 'active' or r.phase <> 'plan' or t <= r.round_ts + game.th_k('plan_ms');
    v_base := r.round_ts + game.th_k('plan_ms')::bigint;
    r := game.dt_mark_online(r);
    r := game.th_resolve(r, v_base);
  end loop;
  return r;
end $$;

create or replace function game.th_view(r game.mp_raids, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb := game.dt_view(r, p_viewer);
begin
  return v || jsonb_build_object('kind', 'tony', 'vet', false,
    'k', (v -> 'k') || jsonb_build_object('mesiu', game.th_mesiu(), 'beras', 0, 'fleeAt', game.th_k('flee_at'),
      'p2', game.th_k('p2_end'), 'p3', game.th_k('p3_end'), 'finalAt', game.th_k('final_at')));
end $$;

create or replace function game.th_board_json(p_pid uuid) returns jsonb
language plpgsql as $$
declare r game.mp_raids; out jsonb := '[]'::jsonb; v_id text;
begin
  for v_id in select id from game.mp_raids where status = 'lobby' and kind = 'tony' order by created loop
    select * into r from game.mp_raids where id = v_id for update;
    r := game.th_tick(r); perform game.dt_save(r);
    if r.status = 'lobby' then
      out := out || jsonb_build_array(jsonb_build_object('id', r.id, 'created', r.created, 'departAt', r.depart_at,
        'leader', (select n from game.mp_raid_members where raid_id = r.id and player_id = r.leader),
        'members', (select coalesce(jsonb_agg(game.dt_member_json(m, r) order by m.joined_ms), '[]'::jsonb) from game.mp_raid_members m where m.raid_id = r.id)));
    end if;
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT: api_tonyHunt(a) a = [aksi, ...]
--   board | open | join <id> | leave | ready <bool> | depart | view [id] | act <round> <order> [id] | flee | card [id]
--   rt <state> <events> <since> [id]   (Pertarungan Terakhir)
-- ---------------------------------------------------------------------
create or replace function public.api_tonyHunt(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'view');
  v_raid text; r game.mp_raids; v_block text; o game.mp_presence; v_n int; m game.mp_raid_members; v_ord jsonb;
  v_round bigint; v_ready boolean; v_mes int; v_now bigint := game.th_now();
  v_rst jsonb; v_evs jsonb; v_since bigint; e jsonb; sh jsonb; vol jsonb; v_side int; v_key text; v_last bigint; v_dmg float8;
  v_bx float8; v_by float8; v_x float8; v_y float8; v_h float8; v_cnt int := 0; v_sc int; v_ev jsonb; v_max bigint;
  v_ships jsonb; pb text; rt game.mp_raid_rt; v_reload float8; q record; v_flee float8;
begin
  o := game.mp_presence_sync(v_pid);
  if o.player_id is null then raise exception 'Muat ulang game dulu, Kapten.'; end if;

  if v_act = 'board' then
    return jsonb_build_object('board', game.th_board_json(v_pid), 'raidId', game.th_raid_of(v_pid),
      'block', game.th_join_block(v_pid), 'tonyHunt', game.th_state(v_pid));
  end if;

  if v_act in ('open', 'join') then
    perform game.mp_xlock(v_pid);
    v_block := game.th_join_block(v_pid);
    if v_block is not null then raise exception '%', v_block; end if;
    if game.th_raid_of(v_pid) is not null then raise exception 'Kau sudah tercatat di sebuah armada.'; end if;
    if v_act = 'open' then
      v_raid := game.mp_uid('t');
      insert into game.mp_raids(id, status, leader, created, kind) values (v_raid, 'lobby', v_pid, v_now, 'tony');
    else
      v_raid := game.arg(a, 1);
      select * into r from game.mp_raids where id = v_raid and kind = 'tony' for update;
      if not found or r.status <> 'lobby' then raise exception 'Armada itu sudah berangkat atau bubar.'; end if;
      r := game.th_tick(r); perform game.dt_save(r);
      if r.status <> 'lobby' then raise exception 'Armada itu sudah berangkat atau bubar.'; end if;
      select count(*) into v_n from game.mp_raid_members where raid_id = v_raid;
      if v_n >= 4 then raise exception 'Armada sudah penuh (4/4).'; end if;
    end if;
    insert into game.mp_raid_members(raid_id, player_id, pub, n, vet, joined_ms, seen_ms, fighter)
    values (v_raid, v_pid, o.pub, v_me.character_name, false, v_now, v_now, game.mp_fighter(v_pid));
    select * into r from game.mp_raids where id = v_raid;
    select count(*) into v_n from game.mp_raid_members where raid_id = v_raid;
    perform game.sys_chat('Pelikan Marlya', 'Kapten ' || v_me.character_name || ' menulis namanya di Papan Armada Marlya (' || v_n || '/4).', 'kabut_abu');
    if v_act = 'open' then
      for q in select p.player_id from game.mp_presence p
                where p.player_id <> v_pid and game.mp_online(p) and game.th_eligible(p.player_id) loop
        perform game.mp_push_inbox(q.player_id, jsonb_build_object('type', 'th_open', 'raidId', v_raid, 'from', v_me.character_name));
      end loop;
    end if;
    perform game.dt_notify(r, 'lobby');
    return jsonb_build_object('raid', game.th_view(r, v_pid), 'tonyHunt', game.th_state(v_pid));
  end if;

  v_raid := nullif(game.arg(a, case when v_act in ('view', 'card') then 1 when v_act = 'act' then 3 when v_act = 'rt' then 4 else 99 end), '');
  v_raid := coalesce(v_raid, game.th_raid_of(v_pid));
  if v_raid is null then
    if v_act in ('view', 'card') then return jsonb_build_object('raid', null, 'tonyHunt', game.th_state(v_pid)); end if;
    raise exception 'Kau tidak sedang di armada mana pun.';
  end if;
  select * into r from game.mp_raids where id = v_raid and kind = 'tony' for update;
  if not found then raise exception 'Armada tidak ditemukan.'; end if;
  select * into m from game.mp_raid_members where raid_id = v_raid and player_id = v_pid;
  if not found and v_act <> 'view' then raise exception 'Kau bukan anggota armada itu.'; end if;
  if found then update game.mp_raid_members set seen_ms = v_now where raid_id = v_raid and player_id = v_pid; end if;

  if v_act = 'leave' then
    if r.status = 'lobby' then
      r := game.dt_lobby_leave(r, v_pid);
      perform game.dt_save(r); perform game.dt_notify(r, 'lobby');
      return jsonb_build_object('raid', null, 'left', true, 'tonyHunt', game.th_state(v_pid));
    end if;
    v_act := 'flee';
  end if;

  if v_act = 'ready' then
    if r.status <> 'lobby' then raise exception 'Armada sudah berangkat.'; end if;
    v_ready := game.mp_truthy(game.arg_json(a, 1));
    if v_ready and not m.ready then
      v_mes := game.item_qty(v_pid, 'mesiu');
      if v_mes < game.th_mesiu() then raise exception 'Perbekalan kurang: kurang % Mesiu.', game.th_mesiu() - v_mes; end if;
      perform game.adjust_inventory(v_pid, 'mesiu', -game.th_mesiu());
      update game.mp_raid_members set ready = true, supply = jsonb_build_object('mesiu', game.th_mesiu(), 'beras', 0)
       where raid_id = v_raid and player_id = v_pid;
    elsif not v_ready and m.ready then
      perform game.dt_refund(v_raid, v_pid);
      update game.mp_raid_members set ready = false where raid_id = v_raid and player_id = v_pid;
    end if;
    r := game.th_tick(r); perform game.dt_save(r); perform game.dt_notify(r, 'lobby');
    return jsonb_build_object('raid', game.th_view(r, v_pid), 'tonyHunt', game.th_state(v_pid));
  end if;

  if v_act = 'depart' then
    if r.status <> 'lobby' then return jsonb_build_object('raid', game.th_view(r, v_pid)); end if;
    if r.leader <> v_pid then raise exception 'Hanya pembuka armada yang boleh mengangkat sauh.'; end if;
    select count(*) into v_n from game.mp_raid_members where raid_id = v_raid and ready;
    if v_n < 2 then raise exception 'Butuh minimal dua kapten yang siap.'; end if;
    r := game.th_depart(r);
    perform game.dt_save(r); perform game.dt_notify(r, 'depart');
    for q in select player_id from game.mp_raid_members where raid_id = v_raid and player_id <> v_pid loop
      perform game.mp_push_inbox(q.player_id, jsonb_build_object('type', 'th_start', 'raidId', v_raid, 'from', v_me.character_name));
    end loop;
    return jsonb_build_object('raid', game.th_view(r, v_pid), 'tonyHunt', game.th_state(v_pid));
  end if;

  if v_act = 'flee' then
    if r.status = 'active' and m.state = 'in' then
      update game.mp_raid_members set state = 'fled' where raid_id = v_raid and player_id = v_pid;
      r.st := jsonb_set(r.st, array['ships', m.pub, 'fled'], 'true'::jsonb);
      r.st := jsonb_set(r.st, array['ships', m.pub, 'alive'], 'false'::jsonb);
      r.ord := r.ord - m.pub;
      if not exists (select 1 from game.mp_raid_members where raid_id = v_raid and state = 'in') then
        r := game.th_finish(r, 'loss');
      elsif r.phase = 'plan' and game.dt_all_locked(r) then
        r := game.dt_mark_online(r); r := game.th_resolve(r, greatest(v_now, r.round_ts));
      end if;
      perform game.dt_save(r); perform game.dt_notify(r, 'flee');
    end if;
    return jsonb_build_object('raid', game.th_view(r, v_pid), 'tonyHunt', game.th_state(v_pid));
  end if;

  if v_act = 'act' then
    v_round := game.arg_int(a, 1);
    v_ord := game.lb_order(game.arg_json(a, 2));
    r := game.th_tick(r);
    if r.status = 'active' and r.phase = 'plan' and v_round is not distinct from r.round::bigint and m.state = 'in'
       and coalesce((r.st -> 'ships' -> m.pub ->> 'alive')::boolean, false) and r.ord -> m.pub is null then
      r.ord := r.ord || jsonb_build_object(m.pub, v_ord);
      if game.dt_all_locked(r) then
        r := game.dt_mark_online(r);
        r := game.th_resolve(r, greatest(v_now, r.round_ts));
      end if;
    end if;
    perform game.dt_save(r); perform game.dt_notify(r, 'turn');
    return jsonb_build_object('raid', game.th_view(r, v_pid));
  end if;

  if v_act = 'rt' then
    if r.status <> 'active' or r.phase <> 'final' then
      r := game.th_tick(r); perform game.dt_save(r);
      return jsonb_build_object('status', r.status, 'phase', r.phase, 't', v_now, 'result', r.result);
    end if;
    v_rst := game.arg_json(a, 1); v_evs := game.arg_json(a, 2); v_since := coalesce(game.arg_int(a, 3), 0);
    sh := r.st -> 'ships' -> m.pub;
    v_flee := (r.st -> 'boss' ->> 'max')::float8 * game.th_k('flee_at');
    if m.state = 'in' and coalesce((sh ->> 'alive')::boolean, false) and v_now >= r.final_ts then
      if v_rst is not null and jsonb_typeof(v_rst) = 'object' and length(v_rst::text) < 400 then
        begin
          v_x := greatest(60, least(2140, (v_rst ->> 'x')::float8)); v_y := greatest(60, least(1440, (v_rst ->> 'y')::float8));
          v_h := game.lb_ang(coalesce((v_rst ->> 'h')::float8, 0));
          insert into game.mp_raid_rt(raid_id, pub, st, ts) values (v_raid, m.pub,
            jsonb_build_object('x', v_x, 'y', v_y, 'h', v_h, 'v', coalesce((v_rst ->> 'v')::float8, 0), 'sails', coalesce((v_rst ->> 'sails')::int, 1),
              'ammo', coalesce(v_rst ->> 'ammo', 'ball')), v_now)
          on conflict (raid_id, pub) do update set st = excluded.st, ts = excluded.ts;
        exception when others then null;
        end;
      end if;
      r := game.th_final_tick(r, v_now);
      if r.status = 'active' and v_evs is not null and jsonb_typeof(v_evs) = 'array' then
        select * into rt from game.mp_raid_rt where raid_id = v_raid and pub = m.pub;
        v_x := (rt.st ->> 'x')::float8; v_y := (rt.st ->> 'y')::float8; v_h := (rt.st ->> 'h')::float8;
        v_bx := (r.st -> 'boss' ->> 'x')::float8; v_by := (r.st -> 'boss' ->> 'y')::float8;
        for e in select value from jsonb_array_elements(v_evs) loop
          v_cnt := v_cnt + 1; exit when v_cnt > 6;
          if e ->> 'k' = 'f' then
            v_side := case when (e ->> 's')::int < 0 then -1 else 1 end;
            v_key := case when v_side < 0 then 'fL' else 'fR' end;
            v_last := coalesce((r.st -> 'ships' -> m.pub ->> v_key)::bigint, 0);
            v_reload := game.th_k('reload_rt') * coalesce((sh ->> 'rm')::float8, 1);
            if v_now - v_last >= v_reload - 250 then
              vol := game.dt_volley_boss(v_x, v_y, v_h, v_bx, v_by, v_side,
                case when e ->> 'a' in ('ball', 'chain', 'grape') then e ->> 'a' else 'ball' end,
                (r.st -> 'ships' -> m.pub ->> 'crew')::float8, (sh ->> 'dm')::float8, (sh ->> 'hm')::float8);
              v_dmg := (vol ->> 'hull')::float8 + (vol ->> 'sail')::float8 * 0.6 + (vol ->> 'crew')::float8 * 0.4;
              r.st := jsonb_set(r.st, array['ships', m.pub, v_key], to_jsonb(v_now));
              r := game.dt_boss_dmg(r, m.pub, v_dmg, 'hull');
              perform game.dt_rtev(v_raid, jsonb_build_object('k', 'f', 'by', m.pub, 's', v_side, 'a', e ->> 'a', 'hits', vol -> 'hits',
                'dmg', round(v_dmg::numeric, 1), 'fx', round(v_x::numeric), 'fy', round(v_y::numeric), 'fh', round(v_h::numeric, 3),
                'tx', round(v_bx::numeric), 'ty', round(v_by::numeric), 't', v_now), v_now);
            end if;
          elsif e ->> 'k' = 'b' then
            v_last := coalesce((r.st -> 'ships' -> m.pub ->> 'bAt')::bigint, 0);
            v_sc := greatest(0, least(3, coalesce((e ->> 'sc')::int, 0)));
            if v_now - v_last >= 8000 and game.dt_dist(v_x, v_y, v_bx, v_by) < game.th_k('boss_r') + 45 then
              r.st := jsonb_set(r.st, array['ships', m.pub, 'bAt'], to_jsonb(v_now));
              if v_sc >= 2 then
                v_dmg := (r.st -> 'boss' ->> 'max')::float8 * 0.025 * v_sc * (1 + coalesce((sh ->> 'bm')::float8, 0) / 200);
                r := game.dt_boss_dmg(r, m.pub, v_dmg, 'board');
                r.stats := game.dt_stat_add(r.stats, m.pub, 'boards', 1);
              end if;
              perform game.dt_rtev(v_raid, jsonb_build_object('k', 'b', 'by', m.pub, 'sc', v_sc, 'ok', v_sc >= 2,
                'dmg', case when v_sc >= 2 then round(v_dmg::numeric, 1) else 0 end, 't', v_now), v_now);
            end if;
          end if;
        end loop;
        if (r.st -> 'boss' ->> 'hull')::float8 <= v_flee then r := game.th_finish(r, 'win'); end if;
      end if;
    else
      r := game.th_final_tick(r, v_now);
    end if;
    perform game.dt_save(r);
    if r.status <> 'active' then perform game.dt_notify(r, 'done'); end if;
    v_ships := '{}'::jsonb;
    if r.st -> 'ships' is not null then
      for pb, sh in select key, value from jsonb_each(r.st -> 'ships') loop
        select * into rt from game.mp_raid_rt where raid_id = v_raid and pub = pb;
        v_ships := v_ships || jsonb_build_object(pb, coalesce(rt.st, '{}'::jsonb) || jsonb_build_object('ts', rt.ts, 'hull', round((sh ->> 'hull')::numeric, 1),
          'crew', round((sh ->> 'crew')::numeric, 1), 'alive', sh -> 'alive', 'fled', sh -> 'fled', 'on', coalesce(rt.ts, 0) > r.final_ts and v_now - coalesce(rt.ts, 0) < 5000));
      end loop;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('seq', x.seq, 'ev', x.ev) order by x.seq), '[]'::jsonb), max(x.seq) into v_ev, v_max
      from (select * from game.mp_raid_rtev where raid_id = v_raid and seq > v_since order by seq limit 60) x;
    return jsonb_build_object('status', r.status, 'phase', r.phase, 'result', r.result, 't', v_now, 'finalTs', r.final_ts,
      'finalEnd', r.final_ts + game.th_k('final_ms')::bigint,
      'boss', jsonb_build_object('x', round((r.st -> 'boss' ->> 'x')::numeric, 1), 'y', round((r.st -> 'boss' ->> 'y')::numeric, 1),
        'h', round((r.st -> 'boss' ->> 'h')::numeric, 3), 'v', round((r.st -> 'boss' ->> 'v')::numeric, 2),
        'hull', round((r.st -> 'boss' ->> 'hull')::numeric, 1), 'max', r.st -> 'boss' -> 'max'),
      'ships', v_ships, 'ev', v_ev, 'seq', coalesce(v_max, v_since));
  end if;

  if v_act = 'card' then
    if m.player_id is not null then update game.mp_raid_members set card_seen = true where raid_id = v_raid and player_id = v_pid; end if;
    return jsonb_build_object('raid', game.th_view(r, v_pid), 'tonyHunt', game.th_state(v_pid));
  end if;

  r := game.th_tick(r);
  perform game.dt_save(r);
  return jsonb_build_object('raid', game.th_view(r, v_pid), 'tonyHunt', game.th_state(v_pid));
end $$;
select game.expose('api_tonyhunt');
