-- =====================================================================
-- Marantau (Supabase) - 0005 MULTIPLAYER  (Modul D)
-- ---------------------------------------------------------------------
-- Port dari legacy-gs/MultiplayerService.gs (Tide v6) + endpoint api_mp*/api_mg*.
-- CacheService/PropertiesService/sheet PlayerOrders diganti tabel:
--   game.mp_presence        kehadiran (+ id publik acak `pub`, uuid TIDAK pernah dikirim ke pemain lain)
--   game.mp_chat_channels   penghitung id pesan per kanal ('g' | 'c:<cityId>')
--   game.mp_chat            pesan chat (60 terakhir per kanal)
--   game.mp_inbox           kotak masuk per pemain (15 menit, maks 30)
--   game.mp_duels           duel kapal/dadu dengan state lengkap (escrow taruhan)
--   game.mp_pvp             rekor PvP + rating Elo
--   game.mp_orders          order Bursa antar-pemain
--   game.mp_fish_types      tabel ikan
--   game.mp_fish            umpan aktif + cooldown 5 detik per pemain
--   game.mp_daily           penghitung harian (mancing 20 / dadu 40 per hari-game)
-- Semua waktu yang dikirim ke client berupa angka ms epoch (sama seperti Date.now() di .gs).
--
-- Urutan kunci (hindari deadlock):
--   * aksi duel: advisory-lock pemain (challenge/respond) -> baris duel FOR UPDATE -> baris players (gold)
--     (fungsi duel TIDAK memanggil game.me(), hanya game.uid(), supaya tidak mengunci baris pemain lebih dulu)
--   * Bursa: baris order FOR UPDATE -> baris players (terurut player_id)
--   * hadiah: baris players terurut player_id; mancing/dadu: baris pemain sendiri
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists game.mp_presence (
  player_id    uuid primary key references game.players(player_id) on delete cascade,
  pub          text not null unique,
  n            text not null default '',
  a            text not null default '',
  f            jsonb,
  t            int not null default 1,
  b            int not null default 0,
  c            text not null default '',
  sea          boolean not null default false,
  dest         text not null default '',
  ts           timestamptz not null default now(),
  last_chat_at timestamptz
);
create index if not exists mp_presence_ts_idx on game.mp_presence (ts desc);
alter table game.mp_presence add column if not exists s jsonb;   -- tampilan kapal (game.ship_visual)

create table if not exists game.mp_chat_channels (
  channel text primary key,
  last_id int not null default 0
);

create table if not exists game.mp_chat (
  channel text not null,
  id      int not null,
  msg     jsonb not null,
  primary key (channel, id)
);

create table if not exists game.mp_inbox (
  seq       bigserial primary key,
  id        text not null unique,
  player_id uuid not null references game.players(player_id) on delete cascade,
  ts        bigint not null,
  item      jsonb not null
);
create index if not exists mp_inbox_player_idx on game.mp_inbox (player_id, ts);

create table if not exists game.mp_duels (
  id       text primary key,
  kind     text not null,                 -- 'naval' | 'dice'
  stake    bigint not null default 0,
  status   text not null,                 -- invited | active | done | declined | expired | cancelled
  city     text not null default '',
  created  bigint not null,               -- ms epoch
  ended    bigint,
  a_id     uuid not null,                 -- penantang
  b_id     uuid not null,                 -- yang ditantang
  fa       jsonb not null,                -- fighter: {pub,n,a,f,tier,maxHp,atk,luck,ammoMax}
  fb       jsonb not null,
  round    int not null default 0,
  hp_a     int, hp_b int,
  ammo_a   int, ammo_b int,
  pick_a   text, pick_b text,
  pick_ts  bigint not null default 0,
  round_ts bigint not null default 0,
  afk_a    int not null default 0,
  afk_b    int not null default 0,
  log      jsonb not null default '[]'::jsonb,
  last     jsonb,                         -- {r, pick:{a,b}, dmg:{a,b}, note:{a,b}}
  winner   text,                          -- 'a' | 'b' | 'draw'
  forfeit  text,                          -- 'a' | 'b'
  dice     jsonb                          -- {a:[..], b:[..]}
);
create index if not exists mp_duels_a_idx on game.mp_duels (a_id, status);
create index if not exists mp_duels_b_idx on game.mp_duels (b_id, status);

create table if not exists game.mp_pvp (
  player_id uuid primary key references game.players(player_id) on delete cascade,
  w int not null default 0,
  l int not null default 0,
  d int not null default 0,
  r int not null default 1000
);
create index if not exists mp_pvp_r_idx on game.mp_pvp (r desc);

create table if not exists game.mp_orders (
  order_id     text primary key,
  seller_id    uuid not null references game.players(player_id) on delete cascade,
  seller_name  text not null default '',
  city_id      text not null,
  commodity_id text not null,
  qty          int not null,
  price        int not null,
  created_at   timestamptz not null default now(),
  status       text not null default 'open'
);
create index if not exists mp_orders_city_idx on game.mp_orders (city_id, status);
create index if not exists mp_orders_seller_idx on game.mp_orders (seller_id, status);

create table if not exists game.mp_fish_types (
  id     text primary key,
  name   text not null,
  v      numeric not null,
  w      numeric not null,
  zone   numeric not null,
  sp     numeric not null,
  rarity int not null
);
insert into game.mp_fish_types(id, name, v, w, zone, sp, rarity) values
  ('sepatu',  'Sepatu Butut',       2,    6,   0.34, 0.8,  0),
  ('teri',    'Ikan Teri',          18,   34,  0.3,  1.0,  1),
  ('kembung', 'Ikan Kembung',       40,   24,  0.25, 1.2,  2),
  ('tongkol', 'Tongkol',            80,   15,  0.2,  1.45, 3),
  ('kakap',   'Kakap Merah',        150,  9,   0.16, 1.7,  4),
  ('kerapu',  'Kerapu Macan',       240,  6,   0.13, 1.95, 5),
  ('tuna',    'Tuna Sirip Kuning',  450,  3,   0.1,  2.25, 6),
  ('dewa',    'Ikan Dewa',          1400, 0.8, 0.07, 2.7,  7)
on conflict (id) do nothing;

create table if not exists game.mp_fish (
  player_id      uuid primary key references game.players(player_id) on delete cascade,
  cast_id        text,
  fish           text,
  t0             bigint,
  wait_ms        int,
  cooldown_until bigint not null default 0
);

create table if not exists game.mp_daily (
  player_id uuid not null references game.players(player_id) on delete cascade,
  kind      text not null,        -- 'fish' | 'dice'
  game_day  int not null,
  n         int not null default 0,
  primary key (player_id, kind, game_day)
);

alter table game.mp_presence enable row level security;
alter table game.mp_chat_channels enable row level security;
alter table game.mp_chat enable row level security;
alter table game.mp_inbox enable row level security;
alter table game.mp_duels enable row level security;
alter table game.mp_pvp enable row level security;
alter table game.mp_orders enable row level security;
alter table game.mp_fish_types enable row level security;
alter table game.mp_fish enable row level security;
alter table game.mp_daily enable row level security;

-- ---------------------------------------------------------------------
-- Helper kecil
-- ---------------------------------------------------------------------
-- Math.round versi JS (setengah ke atas)
create or replace function game.mp_jsround(x numeric) returns bigint
language sql immutable as $$ select floor(x + 0.5)::bigint $$;

-- Number(v) || fb   (NaN / 0 / kosong -> fb)
create or replace function game.mp_jsnum(v text, fb numeric) returns numeric
language plpgsql immutable as $$
declare n numeric;
begin
  if v is null or btrim(v) = '' then return fb; end if;
  begin n := btrim(v)::numeric; exception when others then return fb; end;
  if n = 0 then return fb; end if;
  return n;
end $$;

-- clampInt(v, lo, hi)
create or replace function game.mp_clamp(a jsonb, i int, lo bigint, hi bigint) returns bigint
language sql immutable as $$ select greatest(lo, least(hi, coalesce(game.arg_int(a, i), 0))) $$;

-- truthy ala JS untuk nilai JSON
create or replace function game.mp_truthy(v jsonb) returns boolean
language sql immutable as $$
  select case
    when v is null then false
    when jsonb_typeof(v) = 'null' then false
    when jsonb_typeof(v) = 'boolean' then v::text = 'true'
    when jsonb_typeof(v) = 'number' then (v::text)::numeric <> 0
    when jsonb_typeof(v) = 'string' then (v #>> '{}') <> ''
    else true end
$$;

create or replace function game.mp_uid(p_prefix text) returns text
language sql volatile as $$ select p_prefix || substr(replace(gen_random_uuid()::text, '-', ''), 1, 16) $$;

create or replace function game.mp_new_pub() returns text
language sql volatile as $$ select 'p' || substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 14) $$;

-- cleanText(t, max)
create or replace function game.mp_clean(p_text text, p_max int default 140) returns text
language sql immutable as $$
  select left(btrim(regexp_replace(regexp_replace(coalesce(p_text, ''), '[\x01-\x1f]', ' ', 'g'),
    '[\s   -     　﻿]+', ' ', 'g')), p_max)
$$;

-- jumlah tanda jasa dari players.meta.u
create or replace function game.mp_badges(p_meta jsonb) returns int
language plpgsql immutable as $$
declare m jsonb := p_meta; n int;
begin
  if m is null then return 0; end if;
  if jsonb_typeof(m) = 'string' then
    begin m := (m #>> '{}')::jsonb; exception when others then return 0; end;
  end if;
  if jsonb_typeof(m) <> 'object' or jsonb_typeof(m -> 'u') <> 'object' then return 0; end if;
  select count(*) into n from jsonb_object_keys(m -> 'u');
  return n;
end $$;

-- hari-game (0 bila belum di-seed), seperti day_()
create or replace function game.mp_day() returns int
language plpgsql stable as $$
begin
  return game.game_day();
exception when others then return 0;
end $$;

-- Supabase Realtime broadcast (opsional; gagal diam-diam)
create or replace function game.mp_rt(p_topic text, p_event text, p_payload jsonb) returns void
language plpgsql as $$
begin
  perform realtime.send(p_payload, p_event, p_topic, true);
exception when others then
  null;
end $$;

create or replace function game.mp_pub_of(p_pid uuid) returns text
language sql stable as $$ select pub from game.mp_presence where player_id = p_pid $$;

create or replace function game.mp_unpub(p_pub text) returns uuid
language plpgsql stable as $$
declare v uuid;
begin
  select player_id into v from game.mp_presence where pub = coalesce(p_pub, '');
  if v is null then
    raise exception 'Kapten itu sudah tidak terlihat di pelabuhan.';
  end if;
  return v;
end $$;

create or replace function game.mp_online(p game.mp_presence) returns boolean
language sql stable as $$ select p.player_id is not null and p.ts > now() - interval '2 minutes' $$;

-- ---------------------------------------------------------------------
-- PRESENCE  (kontrak 0001b: game.mp_touch, game.mp_mark_sea)
-- ---------------------------------------------------------------------
create or replace function game.mp_touch(p_pid uuid) returns void
language plpgsql as $$
declare p game.players; sh jsonb; v_sea boolean; v_dest text := ''; v_city text; v_vis jsonb;
begin
  select * into p from game.players where player_id = p_pid;
  if not found or coalesce(p.archetype, '') = '' then return; end if;
  begin sh := game.ship_json(p_pid); exception when others then sh := null; end;
  v_sea := coalesce(game.in_transit(p_pid), false);
  if v_sea then
    select coalesce(destination_city_id, '') into v_dest from game.player_location where player_id = p_pid;
  end if;
  v_city := coalesce(game.current_city(p_pid), '');
  begin v_vis := game.ship_visual(p_pid); exception when others then v_vis := null; end;
  insert into game.mp_presence as x (player_id, pub, n, a, f, t, b, c, sea, dest, ts, s)
  values (p_pid, game.mp_new_pub(), p.character_name, p.archetype, p.appearance,
          floor(game.mp_jsnum(sh ->> 'Tier', 1))::int, game.mp_badges(p.meta), v_city, v_sea, coalesce(v_dest, ''), now(), v_vis)
  on conflict (player_id) do update set
    n = excluded.n, a = excluded.a, f = excluded.f, t = excluded.t, b = excluded.b,
    c = excluded.c, sea = excluded.sea, dest = excluded.dest, ts = excluded.ts, s = excluded.s;
exception when others then
  raise warning 'presence gagal: %', sqlerrm;
end $$;

create or replace function game.mp_mark_sea(p_pid uuid, p_dest text) returns void
language plpgsql as $$
begin
  update game.mp_presence set sea = true, dest = coalesce(p_dest, ''), ts = now() where player_id = p_pid;
exception when others then
  null;
end $$;

-- Dipakai pulse/chat: pastikan baris kehadiran ada (turunkan dari data pemain bila mp_touch belum pernah
-- dipanggil) lalu segarkan lokasi & waktu. Kembalikan baris (player_id null bila pemain belum punya karakter).
create or replace function game.mp_presence_sync(p_pid uuid) returns game.mp_presence
language plpgsql as $$
declare r game.mp_presence; v_sea boolean; v_dest text := ''; v_city text;
begin
  select * into r from game.mp_presence where player_id = p_pid;
  if not found then
    perform game.mp_touch(p_pid);
  else
    v_sea := coalesce(game.in_transit(p_pid), false);
    if v_sea then
      select coalesce(destination_city_id, '') into v_dest from game.player_location where player_id = p_pid;
    end if;
    v_city := coalesce(game.current_city(p_pid), r.c);
    -- hemat tulis: hanya perbarui bila lokasi berubah atau cap waktu sudah > 15 detik
    update game.mp_presence set c = v_city, sea = v_sea, dest = coalesce(v_dest, ''), ts = now()
    where player_id = p_pid
      and (ts < now() - interval '15 seconds' or c is distinct from v_city or sea is distinct from v_sea
           or dest is distinct from coalesce(v_dest, ''));
  end if;
  select * into r from game.mp_presence where player_id = p_pid;
  return r;
end $$;

create or replace function game.mp_public_info(o game.mp_presence) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', o.pub, 'n', o.n, 'a', o.a, 'f', o.f, 't', o.t, 'b', coalesce(o.b, 0), 's', o.s,
    'sea', coalesce(o.sea, false), 'c', o.c, 'dest', coalesce(o.dest, ''))
$$;

-- ---------------------------------------------------------------------
-- INBOX
-- ---------------------------------------------------------------------
create or replace function game.mp_push_inbox(p_pid uuid, p_item jsonb) returns jsonb
language plpgsql as $$
declare v_item jsonb; v_now bigint := game.now_ms(); v_pub text;
begin
  v_item := p_item || jsonb_build_object('id', coalesce(p_item ->> 'id', game.mp_uid('n')), 'ts', v_now);
  insert into game.mp_inbox(id, player_id, ts, item) values (v_item ->> 'id', p_pid, v_now, v_item);
  delete from game.mp_inbox where player_id = p_pid and ts < v_now - 15 * 60000;
  delete from game.mp_inbox where player_id = p_pid and seq not in
    (select seq from game.mp_inbox where player_id = p_pid order by seq desc limit 30);
  v_pub := game.mp_pub_of(p_pid);
  if v_pub is not null then perform game.mp_rt('player:' || v_pub, 'inbox', v_item); end if;
  return v_item;
end $$;

-- ---------------------------------------------------------------------
-- PvP RECORD (Elo)
-- ---------------------------------------------------------------------
create or replace function game.mp_pvp_rec(p_pid uuid) returns jsonb
language sql stable as $$
  select coalesce((select jsonb_build_object('w', w, 'l', l, 'd', d, 'r', r) from game.mp_pvp where player_id = p_pid),
                  jsonb_build_object('w', 0, 'l', 0, 'd', 0, 'r', 1000))
$$;

create or replace function game.mp_pvp_update(p_win uuid, p_lose uuid, p_draw boolean) returns void
language plpgsql as $$
declare ra int; rb int; ea numeric; sa numeric;
begin
  insert into game.mp_pvp(player_id) values (p_win) on conflict do nothing;
  insert into game.mp_pvp(player_id) values (p_lose) on conflict do nothing;
  select r into ra from game.mp_pvp where player_id = p_win for update;
  select r into rb from game.mp_pvp where player_id = p_lose for update;
  ea := 1 / (1 + power(10::numeric, (rb - ra) / 400.0));
  sa := case when p_draw then 0.5 else 1 end;
  update game.mp_pvp set r = game.mp_jsround(ra + 32 * (sa - ea)),
    w = w + case when p_draw then 0 else 1 end, d = d + case when p_draw then 1 else 0 end
  where player_id = p_win;
  update game.mp_pvp set r = game.mp_jsround(rb + 32 * ((1 - sa) - (1 - ea))),
    l = l + case when p_draw then 0 else 1 end, d = d + case when p_draw then 1 else 0 end
  where player_id = p_lose;
end $$;

-- ---------------------------------------------------------------------
-- DUEL
-- ---------------------------------------------------------------------
-- fighter_(): statistik petarung dari kapal efektif (game.ship_json) & stat karakter (game.stats_json)
create or replace function game.mp_fighter(p_pid uuid) returns jsonb
language plpgsql as $$
declare p game.players; sh jsonb; st jsonb; o game.mp_presence; v_tier numeric; v_cond numeric;
begin
  select * into p from game.players where player_id = p_pid;
  if not found or coalesce(p.archetype, '') = '' then raise exception 'Kapten tidak ditemukan.'; end if;
  begin sh := game.ship_json(p_pid); exception when others then sh := null; end;
  st := coalesce(game.stats_json(p_pid), '{}'::jsonb);
  select * into o from game.mp_presence where player_id = p_pid;
  if o.pub is null then raise exception 'Kapten itu sudah tidak terlihat di pelabuhan.'; end if;
  v_tier := game.mp_jsnum(sh ->> 'Tier', 1);
  v_cond := case when sh is null then 100 else game.mp_jsnum(sh ->> 'ConditionPct', 100) end;
  return jsonb_build_object(
    'pub', o.pub, 'n', p.character_name, 'a', p.archetype, 'f', coalesce(o.f, 'null'::jsonb), 'tier', v_tier,
    's', coalesce(o.s, 'null'::jsonb),
    'maxHp', 80 + v_tier * 20 + game.mp_jsround(v_cond / 5),
    'atk', 12 + game.mp_jsnum(st ->> 'Combat', 0) * 0.18 + game.mp_jsnum(sh ->> 'Combat', 0) * 1.2
               + game.mp_jsnum(sh ->> 'CannonBonusPercent', 0) * 0.08,
    'luck', game.mp_jsnum(st ->> 'Luck', 0),
    'ammoMax', least(6, game.mp_jsnum(sh ->> 'MaxCannonAmmo', 3)));
end $$;

-- Duel "aktif" seorang pemain (pengganti kunci cache dz:<id>):
-- undangan yang ia kirim, atau duel yang sedang berjalan.
create or replace function game.mp_slot(p_pid uuid) returns text
language sql stable as $$
  select id from game.mp_duels
  where (status = 'invited' and a_id = p_pid) or (status = 'active' and (a_id = p_pid or b_id = p_pid))
  order by created desc limit 1
$$;

create or replace function game.mp_duel_save(d game.mp_duels) returns void
language plpgsql as $$
begin
  update game.mp_duels set
    kind = d.kind, stake = d.stake, status = d.status, city = d.city, created = d.created, ended = d.ended,
    fa = d.fa, fb = d.fb, round = d.round, hp_a = d.hp_a, hp_b = d.hp_b, ammo_a = d.ammo_a, ammo_b = d.ammo_b,
    pick_a = d.pick_a, pick_b = d.pick_b, pick_ts = d.pick_ts, round_ts = d.round_ts, afk_a = d.afk_a, afk_b = d.afk_b,
    log = d.log, last = d.last, winner = d.winner, forfeit = d.forfeit, dice = d.dice
  where id = d.id;
  perform game.mp_rt('player:' || (d.fa ->> 'pub'), 'duel', jsonb_build_object('duelId', d.id, 'status', d.status, 'round', d.round));
  perform game.mp_rt('player:' || (d.fb ->> 'pub'), 'duel', jsonb_build_object('duelId', d.id, 'status', d.status, 'round', d.round));
end $$;

-- hitOn_: damage yang diterima pihak bertahan (taktik td) dari penyerang (taktik ta)
create or replace function game.mp_hit(p_atk numeric, p_luck numeric, ta text, td text) returns jsonb
language plpgsql volatile as $$
declare roll numeric; base numeric; dmg numeric := 0; note text := '';
begin
  roll := 0.85 + random()::numeric * 0.3 + least(0.1, p_luck / 500.0);
  base := p_atk * roll;
  if ta = 'fire' then
    if td = 'evade' then
      if random() < 0.7 then note := 'dodge'; dmg := 0; else dmg := base; note := 'hit'; end if;
    elsif td = 'brace' then dmg := base * 0.5; note := 'braced';
    elsif td = 'reload' then dmg := base * 1.35; note := 'exposed';
    else dmg := base; note := 'hit';
    end if;
  elsif ta = 'ram' then
    if td = 'brace' then dmg := base * 0.3; note := 'braced';
    elsif td = 'evade' or td = 'reload' then dmg := base * 1.7; note := 'rammed';
    elsif td = 'fire' then dmg := base * 0.9; note := 'rammed';
    elsif td = 'ram' then dmg := base * 1.1; note := 'clash';
    end if;
  end if;
  -- hentakan: menabrak kapal yang bertahan
  if td = 'ram' and ta = 'brace' then
    dmg := dmg + p_atk * 0.9;
    if note = '' then note := 'recoil'; end if;
  end if;
  return jsonb_build_object('dmg', game.mp_jsround(dmg), 'note', note);
end $$;

-- finish_: bayar pot / kembalikan taruhan (seri), rekor PvP, log
create or replace function game.mp_finish(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare pot bigint := d.stake * 2; w uuid; l uuid; what text; msg text; nm_a text; nm_b text;
begin
  d.status := 'done'; d.ended := game.now_ms();
  if d.winner = 'draw' then
    if d.stake > 0 then
      update game.players set gold = gold + d.stake where player_id = d.a_id;
      update game.players set gold = gold + d.stake where player_id = d.b_id;
    end if;
    perform game.mp_pvp_update(d.a_id, d.b_id, true);
  else
    w := case when d.winner = 'a' then d.a_id else d.b_id end;
    l := case when d.winner = 'a' then d.b_id else d.a_id end;
    if pot > 0 then update game.players set gold = gold + pot where player_id = w; end if;
    perform game.mp_pvp_update(w, l, false);
  end if;
  nm_a := d.fa ->> 'n'; nm_b := d.fb ->> 'n';
  what := case when d.kind = 'dice' then 'duel dadu' else 'duel kapal' end;
  -- log untuk A
  msg := case when d.winner = 'draw' then 'Seri dalam ' || what || ' melawan ' || nm_b || '.'
    when d.winner = 'a' then 'Menang ' || what || ' melawan ' || nm_b || case when d.stake > 0 then ' (+' || d.stake || ' gold).' else '.' end
    else 'Kalah ' || what || ' melawan ' || nm_b || case when d.stake > 0 then ' (-' || d.stake || ' gold).' else '.' end end;
  begin perform game.log(d.a_id, msg); exception when others then null; end;
  -- log untuk B
  msg := case when d.winner = 'draw' then 'Seri dalam ' || what || ' melawan ' || nm_a || '.'
    when d.winner = 'b' then 'Menang ' || what || ' melawan ' || nm_a || case when d.stake > 0 then ' (+' || d.stake || ' gold).' else '.' end
    else 'Kalah ' || what || ' melawan ' || nm_a || case when d.stake > 0 then ' (-' || d.stake || ' gold).' else '.' end end;
  begin perform game.log(d.b_id, msg); exception when others then null; end;
  return d;
end $$;

-- resolve_: taktik rahasia serentak ala batu-gunting-kertas
create or replace function game.mp_resolve(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare res_a jsonb; res_b jsonb; entry jsonb; dead_a boolean; dead_b boolean; ra numeric; rb numeric;
  max_a numeric := (d.fa ->> 'maxHp')::numeric; max_b numeric := (d.fb ->> 'maxHp')::numeric;
begin
  res_a := game.mp_hit((d.fb ->> 'atk')::numeric, (d.fb ->> 'luck')::numeric, d.pick_b, d.pick_a);  -- diterima A
  res_b := game.mp_hit((d.fa ->> 'atk')::numeric, (d.fa ->> 'luck')::numeric, d.pick_a, d.pick_b);  -- diterima B
  if d.pick_a = 'fire' then d.ammo_a := greatest(0, d.ammo_a - 1); end if;
  if d.pick_a = 'reload' then d.ammo_a := least((d.fa ->> 'ammoMax')::numeric, d.ammo_a + 2); end if;
  if d.pick_b = 'fire' then d.ammo_b := greatest(0, d.ammo_b - 1); end if;
  if d.pick_b = 'reload' then d.ammo_b := least((d.fb ->> 'ammoMax')::numeric, d.ammo_b + 2); end if;
  d.hp_a := greatest(0, d.hp_a - (res_a ->> 'dmg')::int);
  d.hp_b := greatest(0, d.hp_b - (res_b ->> 'dmg')::int);
  entry := jsonb_build_object('r', d.round,
    'pick', jsonb_build_object('a', d.pick_a, 'b', d.pick_b),
    'dmg', jsonb_build_object('a', (res_a -> 'dmg'), 'b', (res_b -> 'dmg')),
    'note', jsonb_build_object('a', (res_a -> 'note'), 'b', (res_b -> 'note')));
  d.log := coalesce(d.log, '[]'::jsonb) || jsonb_build_array(entry);
  while jsonb_array_length(d.log) > 14 loop d.log := d.log - 0; end loop;
  d.last := entry;
  dead_a := d.hp_a <= 0; dead_b := d.hp_b <= 0;
  if dead_a or dead_b or d.round >= 12 then
    if dead_a and dead_b then d.winner := 'draw';
    elsif dead_a then d.winner := 'b';
    elsif dead_b then d.winner := 'a';
    else
      ra := d.hp_a / max_a; rb := d.hp_b / max_b;
      d.winner := case when abs(ra - rb) < 0.02 then 'draw' when ra > rb then 'a' else 'b' end;
    end if;
    return game.mp_finish(d);
  end if;
  d.round := d.round + 1; d.pick_a := null; d.pick_b := null; d.pick_ts := 0; d.round_ts := game.now_ms();
  return d;
end $$;

create or replace function game.mp_needs_tick(d game.mp_duels) returns boolean
language plpgsql stable as $$
declare t bigint := game.now_ms();
begin
  if d.id is null then return false; end if;
  if d.status = 'invited' then return t - d.created > 60000; end if;
  if d.status <> 'active' or d.kind <> 'naval' then return false; end if;
  if d.pick_a is not null or d.pick_b is not null then return t - d.pick_ts > 25000; end if;
  return t - d.round_ts > 60000;
end $$;

-- tick_: undangan kedaluwarsa; lawan diam -> otomatis 'brace'; 3x diam -> kalah (menyerah)
create or replace function game.mp_tick(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare t bigint := game.now_ms(); one boolean; gone_a boolean; gone_b boolean;
begin
  if d.status = 'invited' and t - d.created > 60000 then d.status := 'expired'; return d; end if;
  if d.status <> 'active' or d.kind <> 'naval' then return d; end if;
  one := d.pick_a is not null or d.pick_b is not null;
  if (one and t - d.pick_ts > 25000) or (not one and t - d.round_ts > 60000) then
    if d.pick_a is null then d.pick_a := 'brace'; d.afk_a := coalesce(d.afk_a, 0) + 1; end if;
    if d.pick_b is null then d.pick_b := 'brace'; d.afk_b := coalesce(d.afk_b, 0) + 1; end if;
    gone_a := d.afk_a >= 3; gone_b := d.afk_b >= 3;
    if gone_a and gone_b then d.winner := 'draw'; return game.mp_finish(d); end if;
    if gone_a then d.winner := 'b'; d.forfeit := 'a'; return game.mp_finish(d); end if;
    if gone_b then d.winner := 'a'; d.forfeit := 'b'; return game.mp_finish(d); end if;
    d := game.mp_resolve(d);
  end if;
  return d;
end $$;

-- Proses batas waktu di bawah kunci baris (baca ulang -> tidak dobel bayar)
create or replace function game.mp_duel_refresh(p_id text) returns game.mp_duels
language plpgsql as $$
declare d game.mp_duels; before text;
begin
  if p_id is null then return d; end if;
  select * into d from game.mp_duels where id = p_id;
  if not found or not game.mp_needs_tick(d) then return d; end if;
  select * into d from game.mp_duels where id = p_id for update;
  before := d.status || '|' || d.round;
  d := game.mp_tick(d);
  if d.status || '|' || d.round <> before then perform game.mp_duel_save(d); end if;
  return d;
end $$;

create or replace function game.mp_view(d game.mp_duels, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare me_a boolean := d.a_id = p_viewer; ms text; os text; you jsonb; foe jsonb; v jsonb;
  y_hp int; y_ammo int; y_pick text; f_hp int; f_ammo int; f_pick text;
begin
  ms := case when me_a then 'a' else 'b' end; os := case when me_a then 'b' else 'a' end;
  you := case when me_a then d.fa else d.fb end; foe := case when me_a then d.fb else d.fa end;
  y_hp := case when me_a then d.hp_a else d.hp_b end; f_hp := case when me_a then d.hp_b else d.hp_a end;
  y_ammo := case when me_a then d.ammo_a else d.ammo_b end; f_ammo := case when me_a then d.ammo_b else d.ammo_a end;
  y_pick := case when me_a then d.pick_a else d.pick_b end; f_pick := case when me_a then d.pick_b else d.pick_a end;
  v := jsonb_build_object(
    'id', d.id, 'kind', d.kind, 'status', d.status, 'stake', d.stake, 'round', d.round, 'maxRounds', 12,
    'created', d.created, 't', game.now_ms(),
    'you', jsonb_strip_nulls(jsonb_build_object('id', you -> 'pub', 'n', you -> 'n', 'a', you -> 'a', 'tier', you -> 'tier',
             'maxHp', you -> 'maxHp', 'hp', y_hp, 'ammo', y_ammo, 'ammoMax', you -> 'ammoMax', 'picked', y_pick is not null))
           || jsonb_build_object('f', coalesce(you -> 'f', 'null'::jsonb), 's', coalesce(you -> 's', 'null'::jsonb), 'pick', y_pick),
    'foe', jsonb_strip_nulls(jsonb_build_object('id', foe -> 'pub', 'n', foe -> 'n', 'a', foe -> 'a', 'tier', foe -> 'tier',
             'maxHp', foe -> 'maxHp', 'hp', f_hp, 'ammo', f_ammo, 'ammoMax', foe -> 'ammoMax', 'picked', f_pick is not null))
           || jsonb_build_object('f', coalesce(foe -> 'f', 'null'::jsonb), 's', coalesce(foe -> 's', 'null'::jsonb)),
    'challenger', me_a,
    'pickDeadline', case when d.pick_ts > 0 then d.pick_ts + 25000 else 0 end,
    'roundTs', d.round_ts,
    'winner', case when d.winner = 'draw' then 'draw' when d.winner is null then null when d.winner = ms then 'you' else 'foe' end,
    'forfeit', case when d.forfeit is null then null when d.forfeit = ms then 'you' else 'foe' end);
  if d.last is not null then
    v := v || jsonb_build_object('last', jsonb_build_object('r', d.last -> 'r',
      'youPick', d.last -> 'pick' -> ms, 'foePick', d.last -> 'pick' -> os,
      'youDmg', d.last -> 'dmg' -> ms, 'foeDmg', d.last -> 'dmg' -> os,
      'youNote', d.last -> 'note' -> ms, 'foeNote', d.last -> 'note' -> os));
  end if;
  if d.dice is not null then
    v := v || jsonb_build_object('dice', jsonb_build_object('you', d.dice -> ms, 'foe', d.dice -> os));
  end if;
  return v;
end $$;

create or replace function game.mp_roll3() returns jsonb
language sql volatile as $$ select jsonb_build_array(game.rand_int(1, 6), game.rand_int(1, 6), game.rand_int(1, 6)) $$;

create or replace function game.mp_sum3(x jsonb) returns int
language sql immutable as $$ select (x ->> 0)::int + (x ->> 1)::int + (x ->> 2)::int $$;

create or replace function game.mp_roll_dice(d game.mp_duels) returns game.mp_duels
language plpgsql as $$
declare tries int := 0; ra jsonb; rb jsonb;
begin
  loop
    ra := game.mp_roll3(); rb := game.mp_roll3(); tries := tries + 1;
    exit when game.mp_sum3(ra) <> game.mp_sum3(rb) or tries >= 3;
  end loop;
  d.dice := jsonb_build_object('a', ra, 'b', rb);
  d.winner := case when game.mp_sum3(ra) = game.mp_sum3(rb) then 'draw' when game.mp_sum3(ra) > game.mp_sum3(rb) then 'a' else 'b' end;
  return d;
end $$;

create or replace function game.mp_xlock(p_pid uuid) returns void
language sql as $$ select pg_advisory_xact_lock(hashtextextended('mp:' || p_pid::text, 0)) $$;

-- ---------------------------------------------------------------------
-- ENDPOINT: presence / chat / profil
-- ---------------------------------------------------------------------
create or replace function public.api_mpPulse(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_since jsonb := game.arg_json(a, 0); info game.mp_presence; p game.players;
  s_g numeric; s_c numeric; s_ib numeric; v_here jsonb; v_online int; v_list jsonb; v_inbox jsonb;
  v_duel jsonb := null; d game.mp_duels; v_slot text; ch_g jsonb; ch_c jsonb;
begin
  select * into p from game.players where player_id = v_id;
  if not found or coalesce(p.archetype, '') = '' then
    return jsonb_build_object('needState', true, 't', game.now_ms());
  end if;
  info := game.mp_presence_sync(v_id);
  if info.player_id is null then return jsonb_build_object('needState', true, 't', game.now_ms()); end if;
  if jsonb_typeof(v_since) <> 'object' then v_since := '{}'::jsonb; end if;
  s_g := game.mp_jsnum(v_since ->> 'g', 0); s_c := game.mp_jsnum(v_since ->> 'c', 0); s_ib := game.mp_jsnum(v_since ->> 'ib', 0);

  select count(*) into v_online from game.mp_presence o where o.ts > now() - interval '2 minutes';
  select coalesce(jsonb_agg(game.mp_public_info(o) order by o.n, o.pub), '[]'::jsonb) into v_here
  from game.mp_presence o
  where o.ts > now() - interval '2 minutes' and o.player_id <> v_id and not o.sea and not info.sea and o.c = info.c;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.pub, 'n', x.n, 'a', x.a, 'c', x.c, 'sea', x.sea, 'me', x.player_id = v_id)
           order by x.player_id = v_id desc, x.n, x.pub), '[]'::jsonb) into v_list
  from (select * from game.mp_presence o where o.ts > now() - interval '2 minutes'
        order by o.player_id = v_id desc, o.n, o.pub limit 40) x;

  select coalesce(jsonb_agg(i.item order by i.seq), '[]'::jsonb) into v_inbox
  from game.mp_inbox i where i.player_id = v_id and i.ts > s_ib and i.ts > game.now_ms() - 3600000;

  v_slot := game.mp_slot(v_id);
  if v_slot is not null then
    d := game.mp_duel_refresh(v_slot);
    if d.id is not null then v_duel := game.mp_view(d, v_id); end if;
  end if;

  select coalesce(jsonb_agg(m.msg order by m.id), '[]'::jsonb) into ch_g
  from (select * from game.mp_chat where channel = 'g' and id > s_g order by id desc limit 30) m;
  if info.sea then ch_c := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(m.msg order by m.id), '[]'::jsonb) into ch_c
    from (select * from game.mp_chat where channel = 'c:' || info.c and id > s_c order by id desc limit 30) m;
  end if;

  return jsonb_build_object(
    't', game.now_ms(), 'me', jsonb_build_object('c', info.c, 'sea', info.sea),
    'here', v_here, 'online', v_online, 'onlineList', v_list, 'mePub', info.pub,
    'chat', jsonb_build_object('g', ch_g, 'c', ch_c),
    'inbox', v_inbox, 'duel', v_duel);
end $$;
select game.expose('api_mppulse');

create or replace function public.api_mpChat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_channel text := game.arg(a, 0); v_tx text; info game.mp_presence;
  v_key text; v_mid int; v_msg jsonb;
begin
  select * into info from game.mp_presence where player_id = v_id;
  if not found then info := game.mp_presence_sync(v_id); end if;
  if info.player_id is null then raise exception 'Muat ulang game dulu sebelum mengobrol.'; end if;
  v_tx := game.mp_clean(game.arg(a, 1), 140);
  if v_tx = '' then raise exception 'Pesan kosong.'; end if;
  update game.mp_presence set last_chat_at = now()
  where player_id = v_id and (last_chat_at is null or last_chat_at <= now() - interval '2 seconds');
  if not found then raise exception 'Pelan-pelan, Kapten - tunggu sebentar sebelum kirim lagi.'; end if;
  v_key := case when v_channel = 'global' then 'g' else 'c:' || info.c end;
  insert into game.mp_chat_channels as ch (channel, last_id) values (v_key, 1)
  on conflict (channel) do update set last_id = ch.last_id + 1
  returning last_id into v_mid;
  v_msg := jsonb_build_object('id', v_mid, 'p', info.pub, 'n', info.n, 'a', info.a, 'tx', v_tx, 'ts', game.now_ms(), 'city', info.c);
  insert into game.mp_chat(channel, id, msg) values (v_key, v_mid, v_msg);
  delete from game.mp_chat where channel = v_key and id <= v_mid - 60;
  perform game.mp_rt(case when v_key = 'g' then 'chat:global' else 'chat:city:' || info.c end, 'chat', v_msg);
  return jsonb_build_object('msg', v_msg);
end $$;
select game.expose('api_mpchat');

create or replace function public.api_mpProfile(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me uuid := game.uid(); v_pub text := game.arg(a, 0); v_id uuid; p game.players; o game.mp_presence; sh jsonb;
begin
  v_id := game.mp_unpub(v_pub);
  select * into p from game.players where player_id = v_id;
  if not found or coalesce(p.archetype, '') = '' then raise exception 'Kapten tidak ditemukan.'; end if;
  select * into o from game.mp_presence where player_id = v_id;
  begin sh := game.ship_json(v_id); exception when others then sh := null; end;
  return jsonb_build_object(
    'id', v_pub, 'n', p.character_name, 'a', p.archetype,
    'f', coalesce(case when o.f is null or jsonb_typeof(o.f) = 'null' then null else o.f end, p.appearance, 'null'::jsonb),
    't', floor(game.mp_jsnum(sh ->> 'Tier', 1)), 'shipName', coalesce(sh ->> 'ShipName', ''),
    'online', game.mp_online(o), 'c', coalesce(o.c, ''), 'sea', coalesce(o.sea, false),
    'badges', game.mp_badges(p.meta), 'pvp', game.mp_pvp_rec(v_id));
end $$;
select game.expose('api_mpprofile');

-- ---------------------------------------------------------------------
-- ENDPOINT: duel
-- ---------------------------------------------------------------------
create or replace function public.api_mpDuelChallenge(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_target uuid; v_kind text; v_stake bigint; t game.mp_presence; me_p game.mp_presence;
  v_loc text; v_gold bigint; d game.mp_duels;
begin
  v_target := game.mp_unpub(game.arg(a, 0));
  v_kind := case when game.arg(a, 2) = 'dice' then 'dice' else 'naval' end;
  if v_target = v_id then raise exception 'Tidak bisa menantang diri sendiri.'; end if;
  v_stake := game.mp_clamp(a, 1, 0, 100000);
  perform game.mp_xlock(v_id);
  select * into t from game.mp_presence where player_id = v_target;
  if not found or not game.mp_online(t) then raise exception 'Kapten itu sedang tidak online.'; end if;
  me_p := game.mp_presence_sync(v_id);
  if me_p.player_id is null then raise exception 'Muat ulang game dulu sebelum mengobrol.'; end if;
  -- duel lama yang sudah lewat batas waktu diselesaikan dulu (pengganti TTL cache)
  perform game.mp_duel_refresh(game.mp_slot(v_id));
  if game.mp_slot(v_id) is not null then raise exception 'Kamu masih punya duel yang belum selesai.'; end if;
  perform game.mp_duel_refresh(game.mp_slot(v_target));
  if game.mp_slot(v_target) is not null then raise exception '% sedang berduel dengan kapten lain.', t.n; end if;
  v_loc := game.current_city(v_id);
  if game.in_transit(v_id) then raise exception 'Duel hanya bisa saat kapal merapat.'; end if;
  if t.sea or t.c <> v_loc then raise exception '% tidak berada di pelabuhan yang sama.', t.n; end if;
  select gold into v_gold from game.players where player_id = v_id;
  if coalesce(v_gold, 0) < v_stake then raise exception 'Gold-mu tidak cukup untuk taruhan %.', v_stake; end if;
  insert into game.mp_duels(id, kind, stake, status, city, created, a_id, b_id, fa, fb)
  values (game.mp_uid('d'), v_kind, v_stake, 'invited', v_loc, game.now_ms(), v_id, v_target,
          game.mp_fighter(v_id), game.mp_fighter(v_target))
  returning * into d;
  perform game.mp_push_inbox(v_target, jsonb_build_object('type', 'duel_invite', 'duelId', d.id, 'kind', v_kind,
    'from', d.fa ->> 'n', 'fromId', d.fa ->> 'pub', 'stake', v_stake, 'fa', d.fa ->> 'a', 'ff', d.fa -> 'f'));
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelchallenge');

create or replace function public.api_mpDuelRespond(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); v_accept boolean := game.mp_truthy(game.arg_json(a, 1));
  d game.mp_duels; v_slot text; ga bigint; gb bigint;
begin
  perform game.mp_xlock(v_id);
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or d.b_id <> v_id then raise exception 'Tantangan tidak ditemukan atau sudah kedaluwarsa.'; end if;
  if d.status <> 'invited' then return game.mp_view(d, v_id); end if;
  if game.now_ms() - d.created > 60000 then
    -- (transaksi dibatalkan oleh raise; status 'expired' tetap diterapkan oleh tick berikutnya)
    raise exception 'Tantangan sudah kedaluwarsa.';
  end if;
  if not v_accept then
    d.status := 'declined';
    perform game.mp_duel_save(d);
    perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'duel_declined', 'duelId', d.id, 'from', d.fb ->> 'n'));
    return game.mp_view(d, v_id);
  end if;
  v_slot := game.mp_slot(v_id);
  if v_slot is not null and v_slot <> d.id then
    perform game.mp_duel_refresh(v_slot);
    v_slot := game.mp_slot(v_id);
    if v_slot is not null and v_slot <> d.id then raise exception 'Selesaikan duelmu yang lain dulu.'; end if;
  end if;
  select gold into ga from game.players where player_id = d.a_id;
  select gold into gb from game.players where player_id = v_id;
  if coalesce(gb, 0) < d.stake then raise exception 'Gold-mu tidak cukup untuk taruhan %.', d.stake; end if;
  if coalesce(ga, 0) < d.stake then raise exception '% sudah tidak punya cukup gold untuk taruhan ini.', d.fa ->> 'n'; end if;
  if game.current_city(v_id) <> d.city or game.in_transit(v_id) then raise exception 'Kamu harus berada di pelabuhan yang sama.'; end if;
  -- escrow taruhan dari kedua kapten (atomik)
  if d.stake > 0 then
    update game.players set gold = gold - d.stake where player_id = d.a_id and gold >= d.stake;
    if not found then raise exception '% sudah tidak punya cukup gold untuk taruhan ini.', d.fa ->> 'n'; end if;
    update game.players set gold = gold - d.stake where player_id = v_id and gold >= d.stake;
    if not found then raise exception 'Gold-mu tidak cukup untuk taruhan %.', d.stake; end if;
  end if;
  d.status := 'active';
  if d.kind = 'dice' then
    d := game.mp_roll_dice(d);
    d := game.mp_finish(d);
  else
    d.round := 1; d.round_ts := game.now_ms();
    d.hp_a := (d.fa ->> 'maxHp')::numeric; d.hp_b := (d.fb ->> 'maxHp')::numeric;
    d.ammo_a := (d.fa ->> 'ammoMax')::numeric; d.ammo_b := (d.fb ->> 'ammoMax')::numeric;
    d.afk_a := 0; d.afk_b := 0;
  end if;
  perform game.mp_duel_save(d);
  perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'duel_start', 'duelId', d.id, 'from', d.fb ->> 'n', 'kind', d.kind));
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelrespond');

create or replace function public.api_mpDuelAct(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); v_round bigint := game.arg_int(a, 1); v_tac text := game.arg(a, 2);
  d game.mp_duels; before text; me_a boolean;
begin
  if v_tac is null or v_tac not in ('fire', 'evade', 'ram', 'brace', 'reload') then raise exception 'Taktik tidak dikenal.'; end if;
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  before := d.status || '|' || d.round;
  d := game.mp_tick(d);
  if d.status <> 'active' or d.kind <> 'naval' then
    if d.status || '|' || d.round <> before then perform game.mp_duel_save(d); end if;
    return game.mp_view(d, v_id);
  end if;
  if v_round is distinct from d.round::bigint then
    -- (versi .gs tidak menyimpan hasil tick di sini; disimpan supaya tidak ada ronde/bayaran ganda)
    if d.status || '|' || d.round <> before then perform game.mp_duel_save(d); end if;
    return game.mp_view(d, v_id);
  end if;
  me_a := d.a_id = v_id;
  if v_tac = 'fire' and coalesce(case when me_a then d.ammo_a else d.ammo_b end, 0) <= 0 then v_tac := 'brace'; end if;
  if me_a and d.pick_a is null then
    d.pick_a := v_tac; d.afk_a := 0; if d.pick_ts = 0 then d.pick_ts := game.now_ms(); end if;
  elsif not me_a and d.pick_b is null then
    d.pick_b := v_tac; d.afk_b := 0; if d.pick_ts = 0 then d.pick_ts := game.now_ms(); end if;
  end if;
  if d.pick_a is not null and d.pick_b is not null then d := game.mp_resolve(d); end if;
  perform game.mp_duel_save(d);
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelact');

create or replace function public.api_mpDuelState(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); d game.mp_duels;
begin
  select * into d from game.mp_duels where id = v_duel;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  if not game.mp_needs_tick(d) then return game.mp_view(d, v_id); end if;
  d := game.mp_duel_refresh(v_duel);
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelstate');

create or replace function public.api_mpDuelForfeit(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_duel text := game.arg(a, 0); d game.mp_duels;
begin
  select * into d from game.mp_duels where id = v_duel for update;
  if not found or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Duel tidak ditemukan.'; end if;
  if d.status = 'invited' and d.a_id = v_id then
    d.status := 'cancelled'; perform game.mp_duel_save(d); return game.mp_view(d, v_id);
  end if;
  if d.status <> 'active' then return game.mp_view(d, v_id); end if;
  d.winner := case when d.a_id = v_id then 'b' else 'a' end;
  d.forfeit := case when d.a_id = v_id then 'a' else 'b' end;
  d := game.mp_finish(d);
  perform game.mp_duel_save(d);
  return game.mp_view(d, v_id);
end $$;
select game.expose('api_mpduelforfeit');

create or replace function public.api_mpPvpBoard(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('n', coalesce(x.character_name, '?'), 'a', coalesce(x.archetype, ''),
           'w', x.w, 'l', x.l, 'd', x.d, 'r', x.r) order by x.r desc, x.w desc, x.character_name), '[]'::jsonb) into v
  from (select r.*, p.character_name, p.archetype from game.mp_pvp r left join game.players p on p.player_id = r.player_id
        order by r.r desc, r.w desc, p.character_name limit 8) x;
  return v;
end $$;
select game.expose('api_mppvpboard');

-- ---------------------------------------------------------------------
-- ENDPOINT: Bursa (order antar-pemain)
-- ---------------------------------------------------------------------
create or replace function game.mp_order_json(o game.mp_orders, p_me uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('orderId', o.order_id, 'seller', o.seller_name, 'cityId', o.city_id, 'commodityId', o.commodity_id,
    'name', game.commodity_name(o.commodity_id), 'qty', o.qty, 'price', o.price, 'createdAt', game.iso(o.created_at),
    'status', o.status, 'mine', o.seller_id = p_me)
$$;

create or replace function public.api_mpOrders(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_city text := game.current_city(v_id); v_here jsonb; v_mine jsonb;
begin
  select coalesce(jsonb_agg(game.mp_order_json(o, v_id) order by o.commodity_id, o.price, o.created_at, o.order_id), '[]'::jsonb) into v_here
  from game.mp_orders o where o.status = 'open' and o.qty > 0 and o.city_id = v_city;
  select coalesce(jsonb_agg(game.mp_order_json(o, v_id) order by o.created_at, o.order_id), '[]'::jsonb) into v_mine
  from game.mp_orders o where o.status = 'open' and o.qty > 0 and o.seller_id = v_id;
  return jsonb_build_object('cityId', v_city, 'orders', v_here, 'mine', v_mine, 'inTransit', coalesce(game.in_transit(v_id), false));
end $$;
select game.expose('api_mporders');

create or replace function public.api_mpPostOrder(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_comm text := game.arg(a, 0); v_qty bigint := game.mp_clamp(a, 1, 0, 100000); v_price bigint := game.mp_clamp(a, 2, 0, 999999);
  v_me game.players; v_city text; v_open int; v_have int; v_oid text;
begin
  if v_qty <= 0 then raise exception 'Jumlah tidak valid.'; end if;
  if v_price <= 0 then raise exception 'Harga tidak valid.'; end if;
  if not exists (select 1 from game.commodities where id = v_comm) then raise exception 'Komoditas tidak dikenal.'; end if;
  v_me := game.me(true);
  if game.in_transit(v_me.player_id) then raise exception 'Pasang order saat kapal merapat.'; end if;
  v_city := game.current_city(v_me.player_id);
  select count(*) into v_open from game.mp_orders where seller_id = v_me.player_id and status = 'open' and qty > 0;
  if v_open >= 6 then raise exception 'Maksimal 6 order aktif. Batalkan salah satu dulu.'; end if;
  select qty into v_have from game.inventory where player_id = v_me.player_id and item_id = v_comm and qty > 0;
  if v_have is null or v_have < v_qty then raise exception 'Barang di palka tidak cukup.'; end if;
  perform game.adjust_inventory(v_me.player_id, v_comm, -v_qty::int);
  v_oid := game.mp_uid('o');
  insert into game.mp_orders(order_id, seller_id, seller_name, city_id, commodity_id, qty, price, created_at, status)
  values (v_oid, v_me.player_id, v_me.character_name, v_city, v_comm, v_qty, v_price, now(), 'open');
  perform game.log(v_me.player_id, 'Memasang order Bursa: ' || v_qty || ' ' || game.commodity_name(v_comm) || ' @ ' || v_price || ' gold.');
  return jsonb_build_object('orderId', v_oid, 'ok', true);
end $$;
select game.expose('api_mppostorder');

create or replace function public.api_mpBuyOrder(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_oid text := game.arg(a, 0); v_qty bigint := game.mp_clamp(a, 1, 0, 100000);
  o game.mp_orders; v_name text; v_total bigint; buyer game.players; v_cap int; v_used int; v_left int;
begin
  if v_qty <= 0 then raise exception 'Jumlah tidak valid.'; end if;
  -- (tanpa game.me(): jangan kunci baris pemain sebelum baris order - lihat urutan kunci)
  select * into o from game.mp_orders where order_id = v_oid for update;
  if not found or o.status <> 'open' or o.qty <= 0 then raise exception 'Order sudah tidak tersedia.'; end if;
  if o.seller_id = v_id then raise exception 'Itu order milikmu sendiri.'; end if;
  if game.in_transit(v_id) or game.current_city(v_id) <> o.city_id then raise exception 'Kamu harus berada di kota order ini.'; end if;
  if v_qty > o.qty then v_qty := o.qty; end if;
  v_total := v_qty * o.price;
  perform 1 from game.players where player_id in (v_id, o.seller_id) order by player_id for update;
  select * into buyer from game.players where player_id = v_id;
  if coalesce(buyer.gold, 0) < v_total then raise exception 'Gold tidak cukup (butuh %).', v_total; end if;
  v_cap := coalesce(game.effective_cargo(v_id), 0); v_used := coalesce(game.cargo_total(v_id), 0);
  if v_used + v_qty > v_cap then raise exception 'Palka tidak cukup. Sisa ruang: %.', v_cap - v_used; end if;
  update game.players set gold = gold - v_total where player_id = v_id;
  update game.players set gold = gold + v_total where player_id = o.seller_id;   -- dikreditkan walau penjual berlayar
  perform game.adjust_inventory(v_id, o.commodity_id, v_qty::int);
  v_left := o.qty - v_qty;
  update game.mp_orders set qty = v_left, status = case when v_left <= 0 then 'filled' else status end where order_id = o.order_id;
  v_name := game.commodity_name(o.commodity_id);
  perform game.log(v_id, 'Membeli ' || v_qty || ' ' || v_name || ' dari ' || o.seller_name || ' di Bursa seharga ' || v_total || ' gold.');
  perform game.log(o.seller_id, coalesce(nullif(buyer.character_name, ''), 'Seorang kapten') || ' membeli ' || v_qty || ' ' || v_name
    || ' dari order Bursa-mu (+' || v_total || ' gold).');
  perform game.mp_push_inbox(o.seller_id, jsonb_build_object('type', 'order_filled', 'from', buyer.character_name,
    'qty', v_qty, 'name', v_name, 'gold', v_total));
  return jsonb_build_object('ok', true, 'qty', v_qty, 'total', v_total, 'newGold', buyer.gold - v_total, 'left', v_left);
end $$;
select game.expose('api_mpbuyorder');

create or replace function public.api_mpCancelOrder(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_oid text := game.arg(a, 0); o game.mp_orders; v_here boolean; v_space int := 0;
  v_where text := 'palka';
begin
  select * into o from game.mp_orders where order_id = v_oid for update;
  if not found or o.seller_id <> v_id then raise exception 'Order tidak ditemukan.'; end if;
  if o.status <> 'open' or o.qty <= 0 then raise exception 'Order sudah tidak aktif.'; end if;
  perform 1 from game.players where player_id = v_id for update;
  v_here := not coalesce(game.in_transit(v_id), false) and game.current_city(v_id) = o.city_id;
  if v_here then v_space := coalesce(game.effective_cargo(v_id), 0) - coalesce(game.cargo_total(v_id), 0); end if;
  if v_here and v_space >= o.qty then
    perform game.adjust_inventory(v_id, o.commodity_id, o.qty);
  else
    insert into game.warehouse as w (player_id, city_id, commodity_id, qty) values (v_id, o.city_id, o.commodity_id, o.qty)
    on conflict (player_id, city_id, commodity_id) do update set qty = w.qty + excluded.qty;
    v_where := 'gudang ' || o.city_id;
  end if;
  update game.mp_orders set status = 'cancelled' where order_id = o.order_id;
  perform game.log(v_id, 'Membatalkan order Bursa ' || o.qty || ' ' || game.commodity_name(o.commodity_id) || ' (dikembalikan ke ' || v_where || ').');
  return jsonb_build_object('ok', true, 'returnedTo', v_where);
end $$;
select game.expose('api_mpcancelorder');

-- ---------------------------------------------------------------------
-- ENDPOINT: hadiah gold
-- ---------------------------------------------------------------------
create or replace function public.api_mpGift(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_target uuid; v_amt bigint; me_p game.players; to_p game.players;
begin
  v_target := game.mp_unpub(game.arg(a, 0));
  v_amt := game.mp_clamp(a, 1, 0, 1000000);
  if v_amt <= 0 then raise exception 'Jumlah tidak valid.'; end if;
  if v_target = v_id then raise exception 'Tidak bisa mengirim ke diri sendiri.'; end if;
  perform 1 from game.players where player_id in (v_id, v_target) order by player_id for update;
  select * into me_p from game.players where player_id = v_id;
  select * into to_p from game.players where player_id = v_target;
  if to_p.player_id is null or coalesce(to_p.archetype, '') = '' then raise exception 'Kapten tujuan tidak ditemukan.'; end if;
  if coalesce(me_p.gold, 0) < v_amt then raise exception 'Gold tidak cukup.'; end if;
  update game.players set gold = gold - v_amt where player_id = v_id;
  update game.players set gold = gold + v_amt where player_id = v_target;
  perform game.log(v_id, 'Mengirim ' || v_amt || ' gold ke ' || to_p.character_name || '.');
  perform game.log(v_target, me_p.character_name || ' mengirimimu ' || v_amt || ' gold.');
  perform game.mp_push_inbox(v_target, jsonb_build_object('type', 'gift', 'from', me_p.character_name, 'gold', v_amt));
  return jsonb_build_object('ok', true, 'newGold', me_p.gold - v_amt);
end $$;
select game.expose('api_mpgift');

-- ---------------------------------------------------------------------
-- ENDPOINT: mini game mancing
-- ---------------------------------------------------------------------
create or replace function public.api_mgFishCast(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_id uuid := v_me.player_id; fr game.mp_fish; v_n int; v_luck numeric; v_boost numeric;
  v_total numeric; v_r numeric; ft record; pick game.mp_fish_types; v_wait int; v_cast text; v_now bigint := game.now_ms();
begin
  if game.in_transit(v_id) then raise exception 'Mancing di dermaga saat kapal merapat.'; end if;
  insert into game.mp_fish(player_id) values (v_id) on conflict do nothing;
  select * into fr from game.mp_fish where player_id = v_id for update;
  if fr.cooldown_until > v_now then raise exception 'Umpan belum siap - tunggu sebentar.'; end if;
  select coalesce((select n from game.mp_daily where player_id = v_id and kind = 'fish' and game_day = game.mp_day()), 0) into v_n;
  if v_n >= 20 then raise exception 'Ikan di dermaga sudah jinak hari ini. Coba lagi besok (hari-game berikutnya).'; end if;
  v_luck := game.mp_jsnum(game.stats_json(v_id) ->> 'Luck', 0);
  v_boost := 1 + v_luck / 60;
  select sum(w * case when rarity >= 4 then v_boost else 1 end) into v_total from game.mp_fish_types;
  v_r := random()::numeric * v_total;
  select * into pick from game.mp_fish_types where rarity = 1;
  for ft in select * from game.mp_fish_types order by rarity loop
    v_r := v_r - ft.w * case when ft.rarity >= 4 then v_boost else 1 end;
    if v_r <= 0 then select * into pick from game.mp_fish_types where id = ft.id; exit; end if;
  end loop;
  v_wait := 1500 + floor(random() * 3500)::int;
  v_cast := game.mp_uid('c');
  update game.mp_fish set cast_id = v_cast, fish = pick.id, t0 = v_now, wait_ms = v_wait, cooldown_until = v_now + 5000
  where player_id = v_id;
  return jsonb_build_object('castId', v_cast, 'waitMs', v_wait,
    'fish', jsonb_build_object('id', pick.id, 'name', pick.name, 'zone', pick.zone, 'speed', pick.sp, 'rarity', pick.rarity),
    'left', 20 - v_n);
end $$;
select game.expose('api_mgfishcast');

create or replace function public.api_mgFishReel(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_id uuid := v_me.player_id; v_cast text := game.arg(a, 0);
  v_hit boolean := game.mp_truthy(game.arg_json(a, 1)); fr game.mp_fish; f game.mp_fish_types; v_now bigint := game.now_ms();
  v_luck numeric; v_gold bigint;
begin
  select * into fr from game.mp_fish where player_id = v_id for update;
  if fr.cast_id is null or fr.cast_id is distinct from v_cast or v_now > fr.t0 + 180000 then
    raise exception 'Umpan sudah lepas. Lempar lagi.';
  end if;
  update game.mp_fish set cast_id = null where player_id = v_id;
  select * into f from game.mp_fish_types where id = fr.fish;
  if not v_hit or v_now > fr.t0 + fr.wait_ms + 9000 then
    return jsonb_build_object('caught', false, 'fish', jsonb_build_object('id', f.id, 'name', f.name));
  end if;
  insert into game.mp_daily as x (player_id, kind, game_day, n) values (v_id, 'fish', game.mp_day(), 1)
  on conflict (player_id, kind, game_day) do update set n = x.n + 1;
  v_luck := game.mp_jsnum(game.stats_json(v_id) ->> 'Luck', 0);
  v_gold := game.mp_jsround(f.v * (1 + v_luck / 200) * (0.9 + random()::numeric * 0.25));
  update game.players set gold = gold + v_gold where player_id = v_id;
  if f.v >= 240 then perform game.log(v_id, 'Memancing ' || f.name || ' di dermaga dan menjualnya ' || v_gold || ' gold!'); end if;
  return jsonb_build_object('caught', true, 'fish', jsonb_build_object('id', f.id, 'name', f.name, 'rarity', f.rarity),
    'gold', v_gold, 'newGold', v_me.gold + v_gold);
end $$;
select game.expose('api_mgfishreel');

-- ---------------------------------------------------------------------
-- ENDPOINT: dadu besar/kecil
-- ---------------------------------------------------------------------
create or replace function public.api_mgDice(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_bet bigint := game.mp_clamp(a, 0, 0, 5000); v_side text := game.arg(a, 1); v_me game.players; v_n int;
  d jsonb; v_sum int; v_triple boolean; v_res text; v_win boolean; v_new bigint; v_day int;
begin
  perform game.uid();
  if v_bet < 10 then raise exception 'Taruhan minimal 10 gold.'; end if;
  if v_side is null or v_side not in ('besar', 'kecil') then raise exception 'Pilih Besar atau Kecil.'; end if;
  v_me := game.me(true);
  v_day := game.mp_day();
  select coalesce((select n from game.mp_daily where player_id = v_me.player_id and kind = 'dice' and game_day = v_day), 0) into v_n;
  if v_n >= 40 then raise exception 'Bandar lapau sudah tutup meja untukmu hari ini.'; end if;
  if v_me.gold < v_bet then raise exception 'Gold tidak cukup untuk taruhan itu.'; end if;
  d := game.mp_roll3();
  v_sum := game.mp_sum3(d);
  v_triple := (d ->> 0) = (d ->> 1) and (d ->> 1) = (d ->> 2);
  v_res := case when v_sum >= 11 then 'besar' else 'kecil' end;
  v_win := not v_triple and v_res = v_side;
  v_new := v_me.gold + case when v_win then v_bet else -v_bet end;
  update game.players set gold = v_new where player_id = v_me.player_id;
  insert into game.mp_daily as x (player_id, kind, game_day, n) values (v_me.player_id, 'dice', v_day, 1)
  on conflict (player_id, kind, game_day) do update set n = x.n + 1;
  return jsonb_build_object('dice', d, 'sum', v_sum, 'triple', v_triple, 'side', v_res, 'win', v_win,
    'delta', case when v_win then v_bet else -v_bet end, 'newGold', v_new, 'left', 39 - v_n);
end $$;
select game.expose('api_mgdice');
