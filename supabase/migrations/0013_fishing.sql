-- =====================================================================
-- Marantau (Supabase) - 0013 MANCING v2 (Tide v10)
-- Lempar (jarak = kedalaman) -> tunggu gigitan -> duel tegangan -> tangkap.
-- Umpan (biaya gold) & joran (upgrade) mengubah peluang; buku ikan + rekor dermaga.
-- Menimpa api_mgFishCast / api_mgFishReel dari 0005. Aman diulang.
-- =====================================================================

alter table game.mp_fish_types add column if not exists kg_min numeric not null default 0.1;
alter table game.mp_fish_types add column if not exists kg_max numeric not null default 1;
alter table game.mp_fish_types add column if not exists stam   numeric not null default 2;     -- detik "tarikan bagus" untuk mendaratkan
alter table game.mp_fish_types add column if not exists pow    numeric not null default 0.4;   -- kekuatan tarikan 0..1.2
alter table game.mp_fish_types add column if not exists agi    numeric not null default 0.4;   -- kelincahan (sering meronta, reaksi lebih singkat)
alter table game.mp_fish_types add column if not exists depth  int not null default 0;         -- 0 dekat, 1 sedang, 2 jauh/dalam
alter table game.mp_fish_types add column if not exists tod    text not null default 'any';    -- any | night
alter table game.mp_fish_types add column if not exists cities text[];                          -- null = semua pelabuhan
alter table game.mp_fish_types add column if not exists kind   text not null default 'fish';   -- fish | junk
alter table game.mp_fish_types add column if not exists hint   text not null default '';
alter table game.mp_fish_types add column if not exists sort   int not null default 0;

insert into game.mp_fish_types(id, name, v, w, zone, sp, rarity, kg_min, kg_max, stam, pow, agi, depth, tod, cities, kind, hint, sort) values
  ('sepatu',   'Sepatu Butut',       2,    5,   0.34, 0.8,  0, 0.4, 1.1,  1.4,  0.15, 0.05, 0, 'any',   null, 'junk', 'Sering tersangkut di dekat dermaga. Siapa yang membuangnya?', 1),
  ('teri',     'Ikan Teri',          18,   30,  0.3,  1.0,  1, 0.03, 0.12, 1.4, 0.22, 0.30, 0, 'any',   null, 'fish', 'Berkerumun di air dangkal dekat dermaga.', 2),
  ('baronang', 'Baronang',           45,   18,  0.25, 1.1,  2, 0.3, 1.4,  2.8,  0.40, 0.45, 0, 'any',   null, 'fish', 'Suka lumut di tiang dermaga. Lempar dekat.', 3),
  ('kembung',  'Ikan Kembung',       40,   22,  0.25, 1.2,  2, 0.2, 0.7,  2.4,  0.38, 0.50, 1, 'any',   null, 'fish', 'Berenang di kedalaman sedang, sering bergerombol.', 4),
  ('tongkol',  'Tongkol',            80,   14,  0.2,  1.45, 3, 1.0, 5.0,  4.0,  0.55, 0.60, 1, 'any',   null, 'fish', 'Perenang cepat di kedalaman sedang. Umpan udang disukai.', 5),
  ('cumi',     'Cumi-cumi',          95,   9,   0.2,  1.3,  3, 0.3, 1.8,  3.5,  0.45, 0.75, 1, 'night', null, 'fish', 'Hanya naik ke permukaan saat malam.', 6),
  ('kakap',    'Kakap Merah',        150,  9,   0.16, 1.7,  4, 2.0, 9.0,  5.0,  0.65, 0.55, 1, 'any',   null, 'fish', 'Kebanggaan nelayan. Kedalaman sedang, umpan cumi.', 7),
  ('peti',     'Peti Karam',         280,  2.2, 0.16, 1.0,  4, 6.0, 14.0, 4.0,  0.50, 0.10, 2, 'any',   null, 'junk', 'Konon banyak kapal karam di perairan dalam. Berat, tapi berisi.', 8),
  ('kerapu',   'Kerapu Macan',       240,  6,   0.13, 1.95, 5, 3.0, 16.0, 7.0,  0.80, 0.45, 2, 'any',   null, 'fish', 'Penghuni karang dalam. Lempar jauh dengan umpan bagus.', 9),
  ('lentera',  'Ikan Lentera',       300,  4,   0.13, 2.0,  5, 0.5, 2.0,  5.5,  0.60, 0.90, 2, 'night', null, 'fish', 'Sisiknya berpendar. Hanya muncul di perairan dalam saat malam.', 10),
  ('pari',     'Ikan Pari',          330,  4,   0.13, 1.8,  5, 8.0, 32.0, 8.0,  0.85, 0.35, 2, 'any',   array['bjorneo','toogood','ikn'], 'fish', 'Mengintai di dasar perairan Bjorneo, TooGood, dan IKN.', 11),
  ('tuna',     'Tuna Sirip Kuning',  450,  3,   0.1,  2.25, 6, 15.0, 70.0, 8.5, 1.00, 0.70, 2, 'any',  null, 'fish', 'Raja laut dalam. Butuh joran kuat dan kesabaran.', 12),
  ('hiu',      'Hiu Karang',         620,  1.6, 0.1,  2.4,  6, 20.0, 90.0, 9.0, 1.10, 0.80, 2, 'any',  array['toogood','bjorneo'], 'fish', 'Hanya di perairan liar TooGood dan Bjorneo. Berbahaya!', 13),
  ('dewa',     'Ikan Dewa',          1400, 0.4, 0.07, 2.7,  7, 5.0, 25.0, 11.0, 1.20, 0.95, 2, 'any',  null, 'fish', 'Legenda Nusantara. Butuh umpan terbaik dan lemparan terjauh.', 14)
on conflict (id) do update set name = excluded.name, v = excluded.v, w = excluded.w, zone = excluded.zone, sp = excluded.sp,
  rarity = excluded.rarity, kg_min = excluded.kg_min, kg_max = excluded.kg_max, stam = excluded.stam, pow = excluded.pow,
  agi = excluded.agi, depth = excluded.depth, tod = excluded.tod, cities = excluded.cities, kind = excluded.kind,
  hint = excluded.hint, sort = excluded.sort;

alter table game.mp_fish add column if not exists bait     text;
alter table game.mp_fish add column if not exists dist     numeric;
alter table game.mp_fish add column if not exists kg       numeric;
alter table game.mp_fish add column if not exists fight_ms int;
alter table game.mp_fish add column if not exists rod      int not null default 0;

create table if not exists game.mp_fish_book (
  player_id uuid not null references game.players(player_id) on delete cascade on update cascade,
  fish_id   text not null,
  n         int not null default 0,
  best_kg   numeric not null default 0,
  best_gold bigint not null default 0,
  first_at  timestamptz not null default now(),
  best_at   timestamptz not null default now(),
  primary key (player_id, fish_id)
);
create index if not exists mp_fish_book_fish_idx on game.mp_fish_book (fish_id, best_kg desc);
alter table game.mp_fish_book enable row level security;

-- Umpan: faktor peluang per rarity 0..7
create or replace function game.fish_baits() returns jsonb
language sql immutable as $$
  select '[
    {"id":"cacing","name":"Cacing","cost":0,"desc":"Gratis. Ikan kecil di air dangkal suka.","f":[1.3,1.3,1.1,0.8,0.5,0.3,0.15,0.05]},
    {"id":"udang","name":"Udang","cost":15,"desc":"Tongkol dan kakap mudah tergoda.","f":[0.7,0.9,1.2,1.5,1.3,0.9,0.5,0.2]},
    {"id":"cumi","name":"Potongan Cumi","cost":45,"desc":"Umpan ikan besar perairan dalam.","f":[0.4,0.4,0.8,1.2,1.8,1.8,1.4,0.8]},
    {"id":"kilau","name":"Umpan Kilau","cost":150,"desc":"Umpan berkilau pemikat ikan langka dan legenda.","f":[0.2,0.2,0.4,0.8,1.4,2.2,3.0,4.0]}
  ]'::jsonb
$$;

-- Joran: tenaga gulung (reel) & batas tegangan (cap)
create or replace function game.fish_rods() returns jsonb
language sql immutable as $$
  select '[
    {"tier":0,"name":"Joran Bambu","cost":0,"reel":1.0,"cap":1.0,"desc":"Joran warisan. Cukup untuk ikan kecil."},
    {"tier":1,"name":"Joran Rotan","cost":2500,"reel":1.25,"cap":1.15,"desc":"Lebih cepat menggulung, tali lebih tahan."},
    {"tier":2,"name":"Joran Baja","cost":9000,"reel":1.55,"cap":1.3,"desc":"Untuk tuna, hiu, dan Ikan Dewa."}
  ]'::jsonb
$$;

-- Malam? (porsi hari-game >= 0.72 atau < 0.04; sama dengan jam di layar)
create or replace function game.fish_is_night() returns boolean
language plpgsql stable as $$
declare start_ms bigint; len_ms numeric; f numeric;
begin
  start_ms := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  len_ms := greatest(60000, game.cfg_num('GameDayLengthRealMinutes', 60) * 60000);
  f := mod(game.now_ms() - start_ms, len_ms::bigint) / len_ms;
  return f >= 0.72 or f < 0.04;
exception when others then return false;
end $$;

create or replace function game.fish_row(p_id uuid) returns game.mp_fish
language plpgsql as $$
declare r game.mp_fish;
begin
  insert into game.mp_fish(player_id) values (p_id) on conflict do nothing;
  select * into r from game.mp_fish where player_id = p_id for update;
  return r;
end $$;

create or replace function game.fish_left(p_id uuid) returns int
language sql stable as $$
  select 20 - coalesce((select n from game.mp_daily where player_id = p_id and kind = 'fish' and game_day = game.mp_day()), 0)
$$;

-- Info panel dermaga
create or replace function public.api_mgFishInfo(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); r game.mp_fish;
begin
  r := game.fish_row(v_me.player_id);
  return jsonb_build_object('left', game.fish_left(v_me.player_id), 'max', 20, 'rod', r.rod, 'rods', game.fish_rods(),
    'baits', game.fish_baits(), 'night', game.fish_is_night(), 'cityId', game.current_city(v_me.player_id),
    'found', (select count(*) from game.mp_fish_book where player_id = v_me.player_id),
    'total', (select count(*) from game.mp_fish_types),
    'cooldownMs', greatest(0, coalesce(r.cooldown_until, 0) - game.now_ms()));
end $$;
select game.expose('api_mgfishinfo');

-- Lempar. a = [dist 0..1, baitId, perfectCast]
create or replace function public.api_mgFishCast(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_id uuid := v_me.player_id; fr game.mp_fish; v_now bigint := game.now_ms();
  v_dist numeric := least(1, greatest(0, coalesce(nullif(game.arg(a, 0), '')::numeric, 0.5)));
  v_bait text := coalesce(nullif(game.arg(a, 1), ''), 'cacing');
  v_perfect boolean := game.mp_truthy(game.arg_json(a, 2));
  b jsonb; v_cost int; v_depth int; v_night boolean := game.fish_is_night(); v_city text := game.current_city(v_id);
  v_luck numeric; v_total numeric := 0; v_r numeric; ft game.mp_fish_types; pick game.mp_fish_types; v_w numeric;
  v_wait int; v_cast text; v_kg numeric; rod jsonb; v_fight int; v_left int; v_ids text[] := '{}'; v_ws numeric[] := '{}';
begin
  if game.in_transit(v_id) then raise exception 'Mancing di dermaga saat kapal merapat.'; end if;
  fr := game.fish_row(v_id);
  if fr.cooldown_until > v_now then raise exception 'Umpan belum siap - tunggu sebentar.'; end if;
  v_left := game.fish_left(v_id);
  if v_left <= 0 then raise exception 'Ikan di dermaga sudah jinak hari ini. Coba lagi besok (hari-game berikutnya).'; end if;
  select x into b from jsonb_array_elements(game.fish_baits()) x where x ->> 'id' = v_bait;
  if b is null then raise exception 'Umpan tidak dikenal.'; end if;
  v_cost := (b ->> 'cost')::int;
  if v_cost > 0 then
    if v_me.gold < v_cost then raise exception 'Gold tidak cukup untuk umpan % (% gold).', b ->> 'name', v_cost; end if;
    update game.players set gold = gold - v_cost where player_id = v_id;
  end if;

  v_depth := case when v_dist < 0.38 then 0 when v_dist < 0.72 then 1 else 2 end;
  v_luck := game.mp_jsnum(game.stats_json(v_id) ->> 'Luck', 0);
  -- bobot: dasar x kedalaman x umpan x luck (langka) x lemparan sempurna x waktu x kota
  for ft in select * from game.mp_fish_types order by sort loop
    if ft.tod = 'night' and not v_night then continue; end if;
    if ft.cities is not null and not (v_city = any (ft.cities)) then continue; end if;
    v_w := ft.w
      * (array[1, 0.3, 0.06])[abs(ft.depth - v_depth) + 1]
      * ((b -> 'f') ->> least(7, greatest(0, ft.rarity)))::numeric
      * case when ft.rarity >= 4 then 1 + v_luck / 60 else 1 end
      * case when v_perfect and ft.rarity >= 4 then 1.2 else 1 end
      * coalesce(game.fish_quest_weight(v_id, ft.id, v_city), 1);  -- quest (mis. Peti Karam di Bjorneo, BarSaTi)
    if v_w > 0 then v_ids := v_ids || ft.id; v_ws := v_ws || v_w; v_total := v_total + v_w; end if;
  end loop;
  v_r := random()::numeric * v_total;
  for i in 1 .. coalesce(array_length(v_ids, 1), 0) loop
    v_r := v_r - v_ws[i];
    if v_r <= 0 then select * into pick from game.mp_fish_types where id = v_ids[i]; exit; end if;
  end loop;
  if pick.id is null then select * into pick from game.mp_fish_types where id = 'teri'; end if;

  -- berat: condong ke kecil (kuadrat), makin berat makin kuat
  v_kg := round((pick.kg_min + (pick.kg_max - pick.kg_min) * power(random(), 1.8))::numeric, 2);
  select x into rod from jsonb_array_elements(game.fish_rods()) x where (x ->> 'tier')::int = fr.rod;
  -- batas bawah waktu duel (anti-curang): ~40% dari waktu tercepat yang mungkin
  v_fight := floor(pick.stam / (rod ->> 'reel')::numeric * 300)::int;
  v_wait := 1800 + floor(random() * 3400)::int;
  v_cast := game.mp_uid('c');
  update game.mp_fish set cast_id = v_cast, fish = pick.id, t0 = v_now, wait_ms = v_wait, cooldown_until = v_now + 3000,
    bait = v_bait, dist = v_dist, kg = v_kg, fight_ms = v_fight
  where player_id = v_id;
  return jsonb_build_object('castId', v_cast, 'waitMs', v_wait, 'left', v_left,
    'newGold', v_me.gold - v_cost, 'baitCost', v_cost, 'depth', v_depth,
    'fight', jsonb_build_object(
      'stam', pick.stam * (0.85 + 0.3 * (v_kg - pick.kg_min) / greatest(0.01, pick.kg_max - pick.kg_min)),
      'pow', least(1.3, pick.pow * (0.9 + 0.2 * (v_kg - pick.kg_min) / greatest(0.01, pick.kg_max - pick.kg_min))),
      'agi', pick.agi,
      'size', least(1, 0.15 + ln(1 + v_kg) / ln(91)),
      'reactMs', 1150 - floor(pick.agi * 550)::int),
    -- kompatibel dengan client lama
    'fish', jsonb_build_object('zone', pick.zone, 'speed', pick.sp, 'rarity', 0));
end $$;
select game.expose('api_mgfishcast');

-- Hasil. a = [castId, result, quality]
--   result: true/'caught' | 'snap' | 'slip' | 'early' | 'late' | false
create or replace function public.api_mgFishReel(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_id uuid := v_me.player_id; v_cast text := game.arg(a, 0);
  v_res text := lower(coalesce(game.arg(a, 1), 'false'));
  v_q numeric := least(1, greatest(0, coalesce(nullif(game.arg(a, 2), '')::numeric, 0)));
  fr game.mp_fish; f game.mp_fish_types; v_now bigint := game.now_ms(); v_luck numeric; v_gold bigint; v_avg numeric;
  bk game.mp_fish_book; v_first boolean; v_record boolean; v_global boolean; v_prev_global numeric; v_caught boolean;
  v_info game.mp_presence; v_mid int; v_msg jsonb; v_qitem jsonb;
begin
  select * into fr from game.mp_fish where player_id = v_id for update;
  if fr.cast_id is null or fr.cast_id is distinct from v_cast or v_now > fr.t0 + 180000 then
    raise exception 'Umpan sudah lepas. Lempar lagi.';
  end if;
  update game.mp_fish set cast_id = null where player_id = v_id;
  select * into f from game.mp_fish_types where id = fr.fish;
  v_caught := v_res in ('true', 'caught', '1');
  -- validasi waktu: tidak boleh sebelum gigitan + durasi duel minimum, dan tidak terlalu lama
  if v_caught and (v_now < fr.t0 + fr.wait_ms + coalesce(fr.fight_ms, 0) or v_now > fr.t0 + fr.wait_ms + 150000) then
    v_caught := false; v_res := 'invalid';
  end if;
  if not v_caught then
    return jsonb_build_object('caught', false, 'reason', v_res,
      'fish', jsonb_build_object('id', f.id, 'name', f.name, 'rarity', f.rarity, 'kind', f.kind), 'kg', fr.kg);
  end if;

  insert into game.mp_daily as x (player_id, kind, game_day, n) values (v_id, 'fish', game.mp_day(), 1)
  on conflict (player_id, kind, game_day) do update set n = x.n + 1;
  v_luck := game.mp_jsnum(game.stats_json(v_id) ->> 'Luck', 0);
  v_avg := (f.kg_min + f.kg_max) / 2;
  v_gold := greatest(1, game.mp_jsround(f.v * power(greatest(fr.kg, 0.01) / v_avg, 0.6) * (1 + v_luck / 200)
    * (1 + 0.15 * v_q) * (0.95 + random()::numeric * 0.13)));
  update game.players set gold = gold + v_gold where player_id = v_id;

  select max(best_kg) into v_prev_global from game.mp_fish_book where fish_id = f.id;
  select * into bk from game.mp_fish_book where player_id = v_id and fish_id = f.id for update;
  v_first := bk.player_id is null;
  v_record := v_first or fr.kg > bk.best_kg;
  v_global := f.kind = 'fish' and (v_prev_global is null or fr.kg > v_prev_global);
  insert into game.mp_fish_book as b (player_id, fish_id, n, best_kg, best_gold) values (v_id, f.id, 1, fr.kg, v_gold)
  on conflict (player_id, fish_id) do update set n = b.n + 1,
    best_kg = greatest(b.best_kg, excluded.best_kg), best_gold = greatest(b.best_gold, excluded.best_gold),
    best_at = case when excluded.best_kg > b.best_kg then now() else b.best_at end;

  if f.v >= 240 then perform game.log(v_id, 'Memancing ' || f.name || ' ' || fr.kg || ' kg di dermaga dan menjualnya ' || v_gold || ' gold!'); end if;
  -- kabar ke kanal dunia untuk tangkapan legendaris
  if f.rarity >= 6 then
    begin
      select * into v_info from game.mp_presence where player_id = v_id;
      insert into game.mp_chat_channels as ch (channel, last_id) values ('g', 1)
      on conflict (channel) do update set last_id = ch.last_id + 1 returning last_id into v_mid;
      v_msg := jsonb_build_object('id', v_mid, 'p', 'sys', 'n', 'Syahbandar', 'a', '', 'ts', v_now, 'city', coalesce(v_info.c, ''),
        'tx', coalesce(v_me.character_name, 'Seorang kapten') || ' mendaratkan ' || f.name || ' ' || fr.kg || ' kg di dermaga ' ||
              coalesce(game.city_name(v_info.c), '') || '!' || case when v_global then ' Rekor dermaga baru!' else '' end);
      insert into game.mp_chat(channel, id, msg) values ('g', v_mid, v_msg);
      perform game.mp_rt('chat:global', 'chat', v_msg);
    exception when others then null;
    end;
  end if;

  -- Hadiah quest dari tangkapan (mis. Mahkota Karam di dalam Peti Karam)
  v_qitem := game.fish_quest_catch(v_id, f.id);

  return jsonb_build_object('caught', true, 'gold', v_gold, 'newGold', v_me.gold + v_gold, 'kg', fr.kg,
    'questItem', v_qitem,
    'fish', jsonb_build_object('id', f.id, 'name', f.name, 'rarity', f.rarity, 'kind', f.kind),
    'firstCatch', v_first, 'record', v_record and not v_first, 'globalRecord', v_global,
    'found', (select count(*) from game.mp_fish_book where player_id = v_id),
    'left', game.fish_left(v_id));
end $$;
select game.expose('api_mgfishreel');

-- Buku ikan: semua spesies + temuan pemain + pemegang rekor dermaga
create or replace function public.api_mgFishBook(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me();
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'rarity', t.rarity, 'kind', t.kind, 'depth', t.depth, 'night', t.tod = 'night',
      'cities', coalesce(to_jsonb(t.cities), 'null'::jsonb), 'hint', t.hint,
      'found', b.player_id is not null,
      'name', case when b.player_id is not null then t.name else null end,
      'n', coalesce(b.n, 0), 'bestKg', b.best_kg, 'bestGold', b.best_gold,
      'kgMax', case when b.player_id is not null then t.kg_max else null end,
      'record', (select jsonb_build_object('kg', r.best_kg, 'n', p.character_name, 'me', r.player_id = v_me.player_id)
                 from game.mp_fish_book r join game.players p on p.player_id = r.player_id
                 where r.fish_id = t.id and t.kind = 'fish' order by r.best_kg desc, r.best_at limit 1)
    ) order by t.sort)
    from game.mp_fish_types t
    left join game.mp_fish_book b on b.fish_id = t.id and b.player_id = v_me.player_id), '[]'::jsonb);
end $$;
select game.expose('api_mgfishbook');

-- Beli joran tingkat berikutnya. a = [tier]
create or replace function public.api_mgFishBuyRod(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); fr game.mp_fish; v_tier int := game.arg_int(a, 0); rod jsonb; v_cost int;
begin
  fr := game.fish_row(v_me.player_id);
  if v_tier <> fr.rod + 1 then raise exception 'Beli joran berurutan: tingkat berikutnya dulu.'; end if;
  select x into rod from jsonb_array_elements(game.fish_rods()) x where (x ->> 'tier')::int = v_tier;
  if rod is null then raise exception 'Joran tidak tersedia.'; end if;
  v_cost := (rod ->> 'cost')::int;
  if v_me.gold < v_cost then raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', v_cost, v_me.gold; end if;
  update game.players set gold = gold - v_cost where player_id = v_me.player_id;
  update game.mp_fish set rod = v_tier where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Membeli ' || (rod ->> 'name') || ' seharga ' || v_cost || ' gold.');
  return jsonb_build_object('rod', v_tier, 'newGold', v_me.gold - v_cost, 'name', rod ->> 'name');
end $$;
select game.expose('api_mgfishbuyrod');
