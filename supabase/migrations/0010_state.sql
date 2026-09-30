-- =====================================================================
-- Marantau (Supabase) - 0010 STATE
-- Endpoint gabungan: api_getGameState, api_pollVoyage, api_getCityBundle
-- (sama dengan versi Code.gs). Dijalankan setelah semua modul.
-- =====================================================================

create or replace function public.api_getGameState(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me();
  v_pid uuid := v_me.player_id;
  v_city text; v_city_json jsonb; v_ver text; r jsonb;
begin
  if v_me.archetype = '' then
    return jsonb_build_object('needsCharacter', true, 'username', coalesce(v_me.username, game.auth_username()));
  end if;

  -- Selesaikan kedatangan yang sudah waktunya dulu (sama seperti versi .gs)
  perform game.resolve_arrival_if_due(v_pid);
  select * into v_me from game.players where player_id = v_pid;

  v_city := game.current_city(v_pid);
  v_city_json := game.city(v_city);
  if v_city_json is null then v_city := 'sunda_empire'; v_city_json := game.city(v_city); end if;
  v_ver := game.cities_version();

  r := jsonb_build_object(
    'player', game.player_json(v_me),
    'stats', game.stats_json(v_pid),
    'ship', game.ship_json(v_pid),
    'shipVisual', game.ship_visual(v_pid),
    'city', v_city_json,
    'citiesVersion', v_ver,
    'voyage', game.voyage_state(v_pid),
    'bank', game.bank_state(v_pid),
    'mission', game.mission_state(v_pid),
    'reputationHere', game.reputation_for(v_pid, v_city),
    'cityEvent', game.city_event(v_city),
    'gameDay', game.game_day(),
    'minutesUntilNextGameDay', game.minutes_to_next_day(),
    'dayLengthMinutes', game.cfg_num('GameDayLengthRealMinutes', 60),
    'audio', game.audio_config(),
    'logs', game.recent_logs(v_pid, 30),
    'appearance', v_me.appearance,
    'meta', v_me.meta,
    'username', coalesce(v_me.username, '')
  );

  -- Kirim daftar kota sekalian kalau cache client belum versi terbaru
  if jsonb_typeof(a) = 'array' and jsonb_array_length(a) > 0
     and (jsonb_typeof(a -> 0) = 'null' or a ->> 0 is distinct from v_ver) then
    r := r || jsonb_build_object('cities', game.cities_json());
  end if;

  begin
    perform game.mp_touch(v_pid);
  exception when others then null;
  end;
  return r;
end $$;
select game.expose('api_getgamestate');

create or replace function public.api_pollVoyage(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  perform game.resolve_arrival_if_due(v_me.player_id);
  return jsonb_build_object('voyage', game.voyage_state(v_me.player_id));
end $$;
select game.expose('api_pollvoyage');

-- Satu panggilan untuk semua data panel kota (tiap bagian aman sendiri-sendiri)
create or replace function public.api_getCityBundle(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me();
  v_here text := game.current_city(v_me.player_id);
  v_city text := coalesce(nullif(game.arg(a, 0), ''), v_here);
  v_transit boolean := game.in_transit(v_me.player_id);
  o jsonb := jsonb_build_object('cityId', v_city);
  v jsonb; k text; fn text;
  parts text[][];
begin
  parts := array[
    array['cargoState', 'api_getcargostate', v_city],
    array['upgrades', 'api_getshipupgrades', ''],
    array['items', 'api_getitems', '']
  ];
  if not v_transit then
    parts := parts || array[
      array['market', 'api_getmarket', v_city],
      array['library', 'api_getlibrary', ''],
      array['missionBoard', 'api_getmissionboard', v_city],
      array['sailOptions', 'api_getsailoptions', ''],
      array['repairQuote', 'api_getrepairquote', v_city]
    ];
  end if;
  for i in 1 .. array_length(parts, 1) loop
    k := parts[i][1]; fn := parts[i][2];
    begin
      execute format('select public.%I($1)', fn) into v
        using case when parts[i][3] = '' then '[]'::jsonb else jsonb_build_array(parts[i][3]) end;
      if k = 'upgrades' then v := jsonb_build_object('affordable', v -> 'affordable'); end if;
      o := o || jsonb_build_object(k, v);
    exception when others then
      o := o || jsonb_build_object(k, null, k || 'Error', sqlerrm);
    end;
  end loop;
  return o;
end $$;
select game.expose('api_getcitybundle');

-- Siapa aku? (dipakai client saat boot)
create or replace function public.api_authWhoAmI(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players;
begin
  if auth.uid() is null then return jsonb_build_object('loggedIn', false, 'mode', 'account'); end if;
  v_me := game.me();
  return jsonb_build_object('loggedIn', true, 'username', coalesce(v_me.username, ''), 'viaGoogle', false,
    'hasCharacter', v_me.archetype <> '', 'name', v_me.character_name);
end $$;
select game.expose('api_authwhoami', true);

-- Cek ketersediaan username sebelum daftar (boleh tanpa login)
create or replace function public.api_usernameAvailable(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare u text := lower(btrim(coalesce(game.arg(a, 0), '')));
begin
  if u !~ '^[a-z0-9_]{3,16}$' then
    raise exception 'Username 3-16 karakter: huruf kecil, angka, atau garis bawah (_).';
  end if;
  return jsonb_build_object('available', not exists (select 1 from game.players where username = u)
    and not exists (select 1 from auth.users where lower(email) = u || '@marantau.game'));
end $$;
select game.expose('api_usernameavailable', true);
