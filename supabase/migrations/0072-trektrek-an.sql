-- =====================================================================
-- 0072 — Trektrek-an (Saga 4, batch 1): mini game adu lurus 402 m.
--   Konsep: claude/KONSEP-Saga4-Monopoli-dan-Mahkota.md bagian 5.
--   * game.trek_run()  : simulasi BILANGAN BULAT, kembaran persis web/src/TrekSim.html (MTTrekSim).
--                        Setiap perubahan angka WAJIB dilakukan di dua tempat; tes 0072 membandingkannya.
--   * api_trek         : status · mulai · selesai. Klien hanya mengirim LOG KETUKAN; menang/kalah dihitung di sini.
--   * Gerbang TrekOpen ('0' bawaan; penguji lewat FiturPenguji). Batch berikutnya (quest Mahkota)
--     menimpa game.trek_boleh() dan game.trek_kapal() sesuai langkah quest / Warlord.
--   Batch 1 tidak memberi hadiah apa pun dan tidak menyentuh ekonomi.
-- Aman diulang (idempoten).
-- =====================================================================

insert into game.config(key, value) values ('TrekOpen', '0') on conflict (key) do nothing;

create table if not exists game.trek_runs (
  run_id     uuid primary key default gen_random_uuid(),
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  kind       text not null default 'sirkuit',
  rival      text not null,
  ship       text not null,
  seed       bigint not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  done       boolean not null default false,
  me_us      bigint,
  op_us      bigint,
  win        boolean,
  log        jsonb
);
create index if not exists trek_runs_player_idx on game.trek_runs (player_id, created_at desc);

create table if not exists game.trek_best (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  ship      text not null,
  best_us   bigint not null,
  log       jsonb not null,
  at        timestamptz not null default now(),
  primary key (player_id, ship)
);
create index if not exists trek_best_us_idx on game.trek_best (best_us);

-- ---------------------------------------------------------------------
-- Tetapan (sama dengan MTTrekSim.SHIPS / RIVALS). Permil kecuali react/rsd (ms).
-- ---------------------------------------------------------------------
create or replace function game.trek_ships() returns jsonb language sql immutable as $$ select '{
  "tanpa":   {"name": "Kapal Sendiri", "zone": 55,  "top": 900,  "acc": 900,  "heat": 750},
  "jolt":    {"name": "Mesin Jolt",    "zone": 95,  "top": 1000, "acc": 1000, "heat": 1000},
  "penuh":   {"name": "Jolt Penuh",    "zone": 125, "top": 1060, "acc": 1050, "heat": 1300},
  "warlord": {"name": "Warlord",       "zone": 125, "top": 1060, "acc": 1050, "heat": 1300},
  "yusaint": {"name": "YusaintJolt",   "zone": 150, "top": 1130, "acc": 1100, "heat": 1600}
}'::jsonb $$;

create or replace function game.trek_rivals() returns jsonb language sql immutable as $$ select '{
  "pariopelan":      {"name": "Pariopelan", "ship": "jolt",    "react": 280, "rsd": 90, "aim": -20, "sd": 34, "boost": 0},
  "kapalmber":       {"name": "KapalMber",  "ship": "jolt",    "react": 260, "rsd": 50, "aim": -22, "sd": 22, "boost": 1},
  "cangcimen_final": {"name": "cangcimen",  "ship": "warlord", "react": 250, "rsd": 55, "aim": -21, "sd": 21, "boost": 1},
  "cangcimen":       {"name": "cangcimen",  "ship": "warlord", "react": 240, "rsd": 50, "aim": -18, "sd": 18, "boost": 1},
  "yaptob":          {"name": "Yaptob",     "ship": "yusaint", "react": 250, "rsd": 40, "aim": -30, "sd": 16, "boost": 1},
  "patroli_lemah":   {"name": "Patroli Jaring", "ship": "jolt", "react": 340, "rsd": 90, "aim": -34, "sd": 48, "boost": 0},
  "patroli":         {"name": "Patroli Jaring", "ship": "jolt", "react": 290, "rsd": 70, "aim": -28, "sd": 40, "boost": 1},
  "patroli_kuat":    {"name": "Patroli Jaring", "ship": "penuh", "react": 290, "rsd": 70, "aim": -28, "sd": 40, "boost": 1}
}'::jsonb $$;

create or replace function game.trek_green_ms(p_seed bigint) returns int language sql immutable as $$
  select (2400 + (((abs(p_seed + 101) % 2147483646) + 1) * 48271 % 2147483647) % 900)::int $$;

-- ---------------------------------------------------------------------
-- Simulasi. p_log = [[tms, 1|0], ...] (1 tekan, 0 lepas), urut waktu. Bila p_ai diisi, log diabaikan
-- dan kapal dikemudikan lawan (deterministik dari p_seed).
-- Hasil: {fin (mikrodetik, null bila tak finis), shifts: ['sempurna'|'tepat'|'awal'|'telat'], reaction, jump, boost}
-- ---------------------------------------------------------------------
create or replace function game.trek_run(p_ship jsonb, p_log jsonb, p_ai jsonb, p_seed bigint) returns jsonb
language plpgsql immutable as $$
declare
  c_top constant bigint[] := array[16000, 27000, 38000, 49000, 61000];
  c_acc constant bigint[] := array[15500, 11000, 8200, 6400, 5000];
  c_tq  constant bigint[] := array[520, 544, 584, 634, 690, 752, 820, 892, 968, 992, 944];
  c_zmul constant bigint[] := array[160, 115, 85, 70];
  c_len constant bigint := 48240000;
  z_zone bigint := (p_ship ->> 'zone')::bigint; z_top bigint := (p_ship ->> 'top')::bigint;
  z_acc bigint := (p_ship ->> 'acc')::bigint; z_heat bigint := (p_ship ->> 'heat')::bigint;
  tops bigint[] := '{}'; accs bigint[] := '{}';
  heat_hi bigint; heat_lo bigint; heat_boost bigint;
  x bigint := 0; v bigint := 0; gear int := 1; rpm bigint := 0; heat bigint := 0;
  launched boolean := false; launchat bigint := 0; reaction bigint; jump boolean := false;
  lastdown bigint; hold bigint; boostleft int := 0; boostused boolean := false;
  shiftleft int := 0; coughleft int := 0; fin bigint; shifts jsonb := '[]'::jsonb;
  ln int := coalesce(jsonb_array_length(p_log), 0); li int := 0;
  lt bigint[] := '{}'; ld int[] := '{}';
  it bigint[]; idn int[]; n int; j int; pass int; t bigint; ql text; zlo bigint;
  k int; tms bigint; top bigint; thr bigint; r bigint; r2 bigint; a bigint; net bigint; fl bigint; i int; nx bigint;
  ai boolean := p_ai is not null; ai_s bigint; ai_react bigint; ai_target bigint; ai_rel boolean;
  ai_aim bigint; ai_sd bigint; ai_boost boolean;
begin
  for i in 1..5 loop tops := tops || (c_top[i] * z_top / 1000); accs := accs || (c_acc[i] * z_acc / 1000); end loop;
  heat_hi := 1250000000 / (120 * z_heat); heat_lo := 550000000 / (120 * z_heat); heat_boost := 380000000 / z_heat;
  if ai then
    ai_s := ((abs(p_seed) % 2147483646) + 1) * 48271 % 2147483647;
    ai_react := greatest(120, (p_ai ->> 'react')::bigint + ai_s % (2 * (p_ai ->> 'rsd')::bigint + 1) - (p_ai ->> 'rsd')::bigint);
    ai_aim := (p_ai ->> 'aim')::bigint; ai_sd := (p_ai ->> 'sd')::bigint; ai_boost := (p_ai ->> 'boost')::int = 1;
  else
    for i in 0..ln - 1 loop lt := lt || (p_log -> i ->> 0)::bigint; ld := ld || (p_log -> i ->> 1)::int; end loop;
  end if;

  for k in 1..3600 loop
    exit when fin is not null;
    tms := (k * 25) / 3;
    it := '{}'; idn := '{}'; ai_rel := false;
    if not ai then
      while li < ln and lt[li + 1] * 3 <= k * 25 loop it := it || lt[li + 1]; idn := idn || ld[li + 1]; li := li + 1; end loop;
    elsif not launched then
      if tms >= ai_react then it := array[tms, tms]; idn := array[1, 0]; end if;
    elsif gear < 5 then
      if ai_target is null then ai_s := ai_s * 48271 % 2147483647; ai_target := 930 + ai_aim + ai_s % (2 * ai_sd + 1) - ai_sd; end if;
      if shiftleft <= 0 and tms - launchat >= 250 and rpm >= ai_target then it := array[tms]; idn := array[1]; ai_target := null; ai_rel := true; end if;
    end if;

    -- pass 1: masukan tick ini; pass 2: lepas otomatis di 1,6 detik bila belum berangkat
    for pass in 1..2 loop
      if pass = 2 then
        exit when launched or k * 25 < 4800;
        it := array[1600, 1600]; idn := array[1, 0];
      end if;
      n := coalesce(array_length(it, 1), 0);
      for j in 1..n loop
        t := it[j];
        if idn[j] = 0 then hold := null;
        elsif lastdown is not null and t - lastdown < 80 then null;
        else
          lastdown := t;
          if not launched then
            if t < 0 then jump := true;
            else
              if t < 80 then jump := true; end if;
              launched := true; launchat := case when jump then greatest(t, 500) else t end; reaction := t;
            end if;
          elsif t - launchat < 250 then null;
          elsif gear < 5 then
            if shiftleft <= 0 then
              zlo := 930 - (z_zone * c_zmul[gear]) / 100;
              if rpm < zlo then ql := 'awal'; shiftleft := 22;
              elsif rpm < 930 - 28 then ql := 'tepat'; shiftleft := 8; v := v + 400;
              elsif rpm <= 930 + 12 then ql := 'sempurna'; shiftleft := 5; v := v + 900;
              else ql := 'telat'; shiftleft := 19; end if;
              shifts := shifts || to_jsonb(ql);
              gear := gear + 1;
              if gear = 5 and not boostused then hold := t; end if;
            end if;
          elsif not boostused then hold := t;
          end if;
        end if;
      end loop;
      if pass = 1 and ai_rel and not (ai_boost and gear = 5) then hold := null; end if;
    end loop;

    continue when not launched or k * 25 < launchat * 3;

    top := tops[gear];
    if boostleft > 0 then top := top * 109 / 100; end if;
    if hold is not null and not boostused and k * 25 - hold * 3 >= 1350 then
      boostused := true; boostleft := 204; heat := heat + heat_boost; hold := null;
    end if;
    thr := 1000;
    if shiftleft > 0 then thr := 0; shiftleft := shiftleft - 1; end if;
    if coughleft > 0 then if thr > 300 then thr := 300; end if; coughleft := coughleft - 1; end if;
    r := v * 1000 / top;
    if gear = 1 then fl := 320 + least(1000, tms * 2) / 10; if r < fl then r := fl; end if; end if;
    a := 0;
    if r < 1000 then
      if r <= 0 then a := c_tq[1]; else i := (r / 100)::int; a := c_tq[i + 1] + (c_tq[i + 2] - c_tq[i + 1]) * (r - i * 100) / 100; end if;
      a := (accs[gear] * a / 1000) * thr / 1000;
    end if;
    if boostleft > 0 then a := a * 155 / 100; boostleft := boostleft - 1; end if;
    net := a - v * v * 6 / 10000000;
    if net >= 0 then v := v + net / 120; else v := v - (-net) / 120; end if;
    if v < 0 then v := 0; end if;
    if v > top then v := top - (case when r >= 1000 then top * 40 / 1000 else 0 end); end if;
    r2 := v * 1000 / top; if r2 < r then r2 := r; end if; if r2 > 1000 then r2 := 1000; end if;
    rpm := r2;
    if r2 > 960 then heat := heat + (case when r2 >= 999 then heat_hi else heat_lo end);
    else heat := heat - 1833; if heat < 0 then heat := 0; end if; end if;
    if heat >= 1000000 then heat := 550000; coughleft := 90; end if;
    nx := x + v;
    if nx >= c_len and x < c_len then fin := ((k - 1)::bigint * 1000000 + (c_len - x) * 1000000 / v) / 120; end if;
    x := nx;
  end loop;

  return jsonb_build_object('fin', fin, 'shifts', shifts, 'reaction', reaction, 'jump', jump, 'boost', boostused);
end $$;

-- ---------------------------------------------------------------------
-- Siapa boleh main & dengan kapal apa. Batch quest Mahkota menimpa dua fungsi ini.
-- ---------------------------------------------------------------------
create or replace function game.trek_boleh(p_pid uuid) returns boolean
language sql stable as $$ select game.fitur_on(p_pid, 'TrekOpen') $$;

create or replace function game.trek_kapal(p_pid uuid) returns text
language sql stable as $$ select 'jolt'::text $$;

create or replace function game.trek_lawan(p_pid uuid) returns text[]
language sql stable as $$ select array['pariopelan', 'kapalmber', 'cangcimen', 'yaptob'] $$;

create or replace function game.trek_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_ship text; v_best jsonb; v_papan jsonb; v_menang jsonb;
begin
  if p_pid is null or not game.trek_boleh(p_pid) then return null; end if;
  v_ship := game.trek_kapal(p_pid);
  select jsonb_build_object('us', best_us, 'log', log) into v_best from game.trek_best where player_id = p_pid and ship = v_ship;
  select coalesce(jsonb_agg(jsonb_build_object('nama', nama, 'us', best_us, 'kapal', kapal, 'aku', aku) order by best_us), '[]'::jsonb) into v_papan
    from (select coalesce(nullif(p.character_name, ''), 'Kapten') as nama, b.best_us, game.trek_ships() -> b.ship ->> 'name' as kapal, b.player_id = p_pid as aku
            from game.trek_best b join game.players p on p.player_id = b.player_id order by b.best_us limit 10) s;
  select coalesce(jsonb_object_agg(rival, n), '{}'::jsonb) into v_menang
    from (select rival, count(*) as n from game.trek_runs where player_id = p_pid and done and win and kind = 'sirkuit' group by rival) w;
  return jsonb_build_object('ship', v_ship, 'lawan', to_jsonb(game.trek_lawan(p_pid)), 'best', v_best, 'papan', v_papan, 'menang', v_menang);
end $$;

-- ---------------------------------------------------------------------
-- API
--   ['status']
--   ['mulai', rival]            -> {run, seed, rival, ship}
--   ['selesai', run, log]       -> {hasil: {...}, trek: state}
-- ---------------------------------------------------------------------
-- Mesin bersama (Sirkuit, Tembus Jaring, turnamen, heat quest): mulai & catat satu balapan.
create or replace function game.trek_mulai(p_pid uuid, p_kind text, p_rival text, p_ship text) returns jsonb
language plpgsql as $$
declare v_seed bigint; v_id uuid;
begin
  if game.trek_rivals() -> p_rival is null or game.trek_ships() -> p_ship is null then raise exception 'Lawan itu belum turun ke selat.'; end if;
  delete from game.trek_runs where player_id = p_pid and (not done or created_at < now() - interval '14 days');
  v_seed := floor(random() * 2000000000)::bigint + 1;
  insert into game.trek_runs(player_id, kind, rival, ship, seed, expires_at)
    values (p_pid, p_kind, p_rival, p_ship, v_seed, now() + interval '10 minutes') returning run_id into v_id;
  return jsonb_build_object('run', v_id, 'seed', v_seed, 'rival', p_rival, 'ship', p_ship, 'kind', p_kind);
end $$;

-- Mengembalikan {win, me, op, shifts, reaction, jump, boost, best, rec, rival, kind}. Salah jenis / basi / curang = exception.
create or replace function game.trek_selesai(p_pid uuid, p_id uuid, p_log jsonb, p_kind text) returns jsonb
language plpgsql as $$
declare v_run game.trek_runs; me jsonb; op jsonb; i int; v_prev bigint; v_t bigint; v_el numeric; v_fin bigint; v_win boolean;
  v_best bigint; v_rec boolean := false;
begin
  select * into v_run from game.trek_runs where run_id = p_id and player_id = p_pid for update;
  if v_run.run_id is null or v_run.kind is distinct from p_kind then raise exception 'Balapan tidak ditemukan.'; end if;
  if v_run.done then raise exception 'Balapan ini sudah dicatat.'; end if;
  if v_run.expires_at < now() then
    delete from game.trek_runs where run_id = p_id;
    raise exception 'Obor garis start sudah padam. Mulai lagi, Kapten.';
  end if;
  if p_log is null or jsonb_typeof(p_log) <> 'array' or jsonb_array_length(p_log) > 240 then raise exception 'Catatan balapan tidak terbaca.'; end if;
  v_prev := -100000;
  for i in 0..jsonb_array_length(p_log) - 1 loop
    if jsonb_typeof(p_log -> i) <> 'array' or jsonb_typeof(p_log -> i -> 0) <> 'number' or (p_log -> i ->> 1) not in ('0', '1')
       or (p_log -> i ->> 0) !~ '^-?[0-9]{1,6}$' then raise exception 'Catatan balapan tidak terbaca.'; end if;
    v_t := (p_log -> i ->> 0)::bigint;
    if v_t < v_prev or v_t < -20000 or v_t > 40000 then raise exception 'Catatan balapan tidak terbaca.'; end if;
    v_prev := v_t;
  end loop;

  me := game.trek_run(game.trek_ships() -> v_run.ship, p_log, null, v_run.seed);
  op := game.trek_run(game.trek_ships() -> (game.trek_rivals() -> v_run.rival ->> 'ship'), null, game.trek_rivals() -> v_run.rival, v_run.seed);
  v_fin := (me ->> 'fin')::bigint;
  -- jam dinding: balapan tidak mungkin selesai lebih cepat dari lampu + waktu tempuhnya sendiri
  v_el := extract(epoch from (now() - v_run.created_at)) * 1000;
  if v_fin is not null and v_el < game.trek_green_ms(v_run.seed) + v_fin / 1000 - 1500 then raise exception 'Catatan balapan tidak wajar.'; end if;
  v_win := v_fin is not null and v_fin < (op ->> 'fin')::bigint;

  update game.trek_runs set done = true, me_us = v_fin, op_us = (op ->> 'fin')::bigint, win = v_win, log = p_log where run_id = p_id;
  if v_fin is not null then
    select best_us into v_best from game.trek_best where player_id = p_pid and ship = v_run.ship;
    if v_best is null or v_fin < v_best then
      v_rec := v_best is not null;
      insert into game.trek_best(player_id, ship, best_us, log) values (p_pid, v_run.ship, v_fin, p_log)
        on conflict (player_id, ship) do update set best_us = excluded.best_us, log = excluded.log, at = now();
      v_best := v_fin;
    end if;
  end if;
  return jsonb_build_object('win', v_win, 'me', v_fin, 'op', (op ->> 'fin')::bigint, 'shifts', me -> 'shifts',
    'reaction', me -> 'reaction', 'jump', me -> 'jump', 'boost', me -> 'boost', 'best', v_best, 'rec', v_rec,
    'rival', v_run.rival, 'kind', v_run.kind);
end $$;

create or replace function public.api_trek(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_rival text; v_id uuid; v_h jsonb;
begin
  if v_pid is null or not game.trek_boleh(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  if v_act = 'status' then return jsonb_build_object('trek', game.trek_state(v_pid)); end if;

  if v_act = 'mulai' then
    v_rival := lower(coalesce(game.arg(a, 1), ''));
    if not (v_rival = any (game.trek_lawan(v_pid))) then raise exception 'Lawan itu belum turun ke selat.'; end if;
    return game.trek_mulai(v_pid, 'sirkuit', v_rival, game.trek_kapal(v_pid));
  end if;

  if v_act = 'selesai' then
    begin v_id := game.arg(a, 1)::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
    v_h := game.trek_selesai(v_pid, v_id, case when jsonb_typeof(a) = 'array' then a -> 2 end, 'sirkuit');
    return jsonb_build_object('hasil', v_h, 'trek', game.trek_state(v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_trek');
