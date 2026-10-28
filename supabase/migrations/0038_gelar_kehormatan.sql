-- =====================================================================
-- 0038 — Gelar Kehormatan Pulau · Fase 1 (Tide v40)
-- Konsep: claude/KONSEP-Gelar-Kehormatan-Pulau.md (project docs)
--
--   * Tangga gelar per pulau dari Standing (players.reputation):
--       0 Tamu · 5 Kenalan · 15 Sahabat Kota · 35 Warga Kehormatan · 60 Anak Nagari · 100 Pelindung Pulau
--   * Hak Lot: jatah beli pribadi harian (reset 00:00 WIB) untuk barang HASIL pulau itu,
--       3 / 6 / 10 lot (Warga Kehormatan / Anak Nagari / Pelindung). 1 lot = ukuran lot Ekonomi v2
--       (common 10, mid 5, premium 1 unit). Harga = harga keseimbangan, TIDAK mengurangi stok pasar.
--   * Papan Kehormatan: 3 kapten Standing tertinggi per pulau (character_name), mulai Standing 15,
--       seri = yang lebih dulu mencapai angka itu, akun GM tidak ikut. Kapten yang tergeser dari
--       papan mendapat catatan.
--   * Hanya 8 pulau Mare Nusantara. TIDAK ada Tanda Jasa dari fitur ini. Sumber Standing tidak berubah.
--
-- Sumber kebenaran Standing tetap players.reputation. Tabel honor_rep hanya cermin (diisi trigger)
-- supaya papan bisa diurutkan + mencatat KAPAN angka itu dicapai (penentu seri).
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('KehormatanOpen', '1'),
  ('HonorCities', 'sunda_empire,joungjava,bjorneo,skitraw,toogood,ikn,paradiso,marie_regal'),
  ('HonorTiers', '5:Kenalan,15:Sahabat Kota,35:Warga Kehormatan,60:Anak Nagari,100:Pelindung Pulau'),
  ('HonorLots', '3,6,10'),
  ('HonorBoardMin', '15'),
  ('HonorBoardSize', '3')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Aturan
-- ---------------------------------------------------------------------
create or replace function game.honor_cities() returns text[]
language sql stable as $$
  select coalesce(nullif(string_to_array(replace(coalesce(game.cfg('HonorCities'), ''), ' ', ''), ','), '{}'),
    array['sunda_empire','joungjava','bjorneo','skitraw','toogood','ikn','paradiso','marie_regal'])
$$;

-- [{tier, min, name}] urut naik, tier 0 = Tamu
create or replace function game.honor_tiers() returns jsonb
language plpgsql stable as $$
declare raw text := coalesce(nullif(trim(game.cfg('HonorTiers')), ''), '5:Kenalan,15:Sahabat Kota,35:Warga Kehormatan,60:Anak Nagari,100:Pelindung Pulau');
  part text; out jsonb := jsonb_build_array(jsonb_build_object('tier', 0, 'min', 0, 'name', 'Tamu')); n int := 0;
begin
  foreach part in array string_to_array(raw, ',') loop
    part := trim(part);
    if part = '' or position(':' in part) = 0 then continue; end if;
    begin
      n := n + 1;
      out := out || jsonb_build_array(jsonb_build_object('tier', n, 'min', trim(split_part(part, ':', 1))::numeric,
        'name', trim(substr(part, position(':' in part) + 1))));
    exception when others then n := n - 1;
    end;
  end loop;
  return out;
end $$;

create or replace function game.honor_tier_of(p_rep numeric) returns int
language sql stable as $$
  select coalesce(max((t ->> 'tier')::int), 0) from jsonb_array_elements(game.honor_tiers()) t
   where coalesce(p_rep, 0) >= (t ->> 'min')::numeric
$$;

create or replace function game.honor_tier_name(p_tier int) returns text
language sql stable as $$
  select coalesce((select t ->> 'name' from jsonb_array_elements(game.honor_tiers()) t where (t ->> 'tier')::int = p_tier), 'Tamu')
$$;

create or replace function game.honor_tier_min(p_tier int) returns numeric
language sql stable as $$
  select (select (t ->> 'min')::numeric from jsonb_array_elements(game.honor_tiers()) t where (t ->> 'tier')::int = p_tier)
$$;

-- Jatah Hak Lot per hari untuk tingkat gelar (tingkat 3, 4, 5 -> HonorLots[1..3])
create or replace function game.honor_lot_max(p_tier int) returns int
language plpgsql stable as $$
declare arr text[] := string_to_array(replace(coalesce(game.cfg('HonorLots'), '3,6,10'), ' ', ''), ',');
  first_tier int := 3; idx int;
begin
  idx := p_tier - first_tier + 1;
  if idx < 1 then return 0; end if;
  if idx > coalesce(array_length(arr, 1), 0) then idx := array_length(arr, 1); end if;
  if idx is null or idx < 1 then return 0; end if;
  return greatest(0, coalesce(nullif(arr[idx], '')::int, 0));
exception when others then return 0;
end $$;

-- Standing satu kota dari jsonb reputasi (angka atau teks angka; selain itu 0)
create or replace function game.honor_num(p_rep jsonb, p_city text) returns numeric
language plpgsql immutable as $$
begin
  if p_rep is null or jsonb_typeof(p_rep) <> 'object' or not (p_rep ? p_city) then return 0; end if;
  if jsonb_typeof(p_rep -> p_city) = 'number' then return (p_rep ->> p_city)::numeric; end if;
  return coalesce(nullif(p_rep ->> p_city, '')::numeric, 0);
exception when others then return 0;
end $$;

-- Pulau yang boleh dilihat pemain ini (tidak tersembunyi, atau sudah terbuka untuknya)
create or replace function game.honor_visible(p_pid uuid, p_city text, p_unlocks jsonb default null) returns boolean
language plpgsql stable as $$
declare h boolean;
begin
  select coalesce(hidden, false) into h from game.cities where city_id = p_city;
  if not found then return false; end if;
  if not h then return true; end if;
  return coalesce(coalesce(p_unlocks, game.player_unlocks(p_pid)) ? p_city, false);
exception when others then return not coalesce(h, true);
end $$;

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists game.honor_rep (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  city_id   text not null,
  rep       numeric not null,
  at        timestamptz not null default now(),       -- kapan angka ini dicapai (penentu seri papan)
  primary key (player_id, city_id)
);
create index if not exists honor_rep_board_idx on game.honor_rep (city_id, rep desc, at);

create table if not exists game.honor_tier (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  city_id   text not null,
  tier      int not null,
  at        timestamptz not null default now(),
  seen      boolean not null default false,            -- modal/toast naik gelar sudah tampil
  backfill  boolean not null default false,            -- diisi saat rilis (tidak dirayakan)
  primary key (player_id, city_id, tier)
);

create table if not exists game.honor_lot (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  city_id   text not null,
  day_wib   date not null,
  used      int not null default 0,
  primary key (player_id, city_id, day_wib)
);

create table if not exists game.honor_note (
  id        bigserial primary key,
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  kind      text not null,                             -- 'geser' = tergeser dari Papan Kehormatan
  city_id   text,
  data      jsonb not null default '{}'::jsonb,
  at        timestamptz not null default now(),
  seen      boolean not null default false
);
create index if not exists honor_note_player_idx on game.honor_note (player_id, seen, at desc);

alter table game.honor_rep enable row level security;
alter table game.honor_tier enable row level security;
alter table game.honor_lot enable row level security;
alter table game.honor_note enable row level security;

-- ---------------------------------------------------------------------
-- Papan Kehormatan
-- ---------------------------------------------------------------------
create or replace function game.honor_gm_names() returns text[]
language sql stable as $$
  select coalesce(string_to_array(lower(replace(coalesce(game.cfg('GmUsernames'), ''), ' ', '')), ','), '{}')
$$;

-- Kapten yang berhak tampil di papan kota ini, terurut (rep turun, lebih dulu mencapai = menang)
create or replace function game.honor_ranked(p_city text) returns table(player_id uuid, rep numeric, at timestamptz, rk bigint)
language sql stable as $$
  select h.player_id, h.rep, h.at, row_number() over (order by h.rep desc, h.at asc, h.player_id) as rk
    from game.honor_rep h join game.players p on p.player_id = h.player_id
   where h.city_id = p_city
     and h.rep >= game.cfg_num('HonorBoardMin', 15)
     and coalesce(p.archetype, '') <> '' and coalesce(trim(p.character_name), '') <> ''
     and not (lower(coalesce(p.username, '')) = any (game.honor_gm_names()))
$$;

create or replace function game.honor_top_ids(p_city text) returns uuid[]
language sql stable as $$
  select coalesce(array_agg(player_id order by rk), '{}') from game.honor_ranked(p_city)
   where rk <= greatest(1, game.cfg_num('HonorBoardSize', 3)::int)
$$;

create or replace function game.honor_board(p_city text, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare v_rows jsonb; v_me jsonb; n int := greatest(1, game.cfg_num('HonorBoardSize', 3)::int);
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', r.rk, 'id', game.mp_pub_of(r.player_id), 'name', p.character_name, 'arch', p.archetype,
      'ap', p.appearance, 'rep', trim_scale(r.rep), 'tier', game.honor_tier_of(r.rep),
      'tierName', game.honor_tier_name(game.honor_tier_of(r.rep)), 'me', r.player_id = p_viewer) order by r.rk), '[]'::jsonb)
    into v_rows
    from game.honor_ranked(p_city) r join game.players p on p.player_id = r.player_id
   where r.rk <= n;
  select jsonb_build_object('rank', r.rk, 'rep', trim_scale(r.rep)) into v_me
    from game.honor_ranked(p_city) r where r.player_id = p_viewer;
  return jsonb_build_object('city', p_city, 'cityName', game.city_name(p_city), 'rows', v_rows, 'me', v_me,
    'min', game.cfg_num('HonorBoardMin', 15), 'size', n);
end $$;

-- ---------------------------------------------------------------------
-- Trigger: cermin Standing -> honor_rep, catat naik gelar, beri tahu yang tergeser
-- ---------------------------------------------------------------------
create or replace function game.honor_rep_trg() returns trigger
language plpgsql as $$
declare c text; o numeric; n numeric; ot int; nt int; v_before uuid[]; v_after uuid[]; x uuid; v_note bigint;
begin
  if NEW.reputation is not distinct from OLD.reputation then return NEW; end if;
  foreach c in array game.honor_cities() loop
    o := game.honor_num(OLD.reputation, c);
    n := game.honor_num(NEW.reputation, c);
    continue when o = n;
    v_before := game.honor_top_ids(c);
    if n <= 0 then
      delete from game.honor_rep where player_id = NEW.player_id and city_id = c;
    else
      insert into game.honor_rep(player_id, city_id, rep, at) values (NEW.player_id, c, n, now())
      on conflict (player_id, city_id) do update set rep = excluded.rep, at = excluded.at;
    end if;
    ot := game.honor_tier_of(o); nt := game.honor_tier_of(n);
    if nt > ot then
      insert into game.honor_tier(player_id, city_id, tier, at)
        select NEW.player_id, c, g, now() from generate_series(greatest(ot + 1, 1), nt) g
      on conflict (player_id, city_id, tier) do nothing;
    elsif nt < ot then
      delete from game.honor_tier where player_id = NEW.player_id and city_id = c and tier > nt;
    end if;
    -- Kapten yang terdorong keluar dari papan
    begin
      v_after := game.honor_top_ids(c);
      foreach x in array v_before loop
        if x <> NEW.player_id and not (x = any (v_after)) then
          insert into game.honor_note(player_id, kind, city_id, data)
            values (x, 'geser', c, jsonb_build_object('by', NEW.character_name))
            returning id into v_note;
          delete from game.honor_note where player_id = x and id not in
            (select id from game.honor_note where player_id = x order by id desc limit 20);
          perform game.mp_push_inbox(x, jsonb_build_object('type', 'honor_geser', 'noteId', v_note, 'city', c,
            'cityName', game.city_name(c), 'by', NEW.character_name));
        end if;
      end loop;
    exception when others then
      raise warning '[kehormatan] catatan papan %: %', c, sqlerrm;
    end;
  end loop;
  return NEW;
end $$;

drop trigger if exists honor_rep_sync on game.players;
create trigger honor_rep_sync after update of reputation on game.players
  for each row execute function game.honor_rep_trg();

-- ---------------------------------------------------------------------
-- Isi awal / perbaikan cermin (setiap deploy; tidak menimpa waktu yang sudah tercatat)
-- ---------------------------------------------------------------------
insert into game.honor_rep(player_id, city_id, rep, at)
  select p.player_id, c, game.honor_num(p.reputation, c), now()
    from game.players p cross join unnest(game.honor_cities()) c
   where game.honor_num(p.reputation, c) > 0
on conflict (player_id, city_id) do nothing;

update game.honor_rep h set rep = game.honor_num(p.reputation, h.city_id)
  from game.players p
 where p.player_id = h.player_id and game.honor_num(p.reputation, h.city_id) > 0
   and h.rep <> game.honor_num(p.reputation, h.city_id);

delete from game.honor_rep h using game.players p
 where p.player_id = h.player_id and game.honor_num(p.reputation, h.city_id) <= 0;
delete from game.honor_rep where not (city_id = any (game.honor_cities()));

-- Gelar yang sudah dimiliki saat rilis: dicatat, tidak dirayakan
insert into game.honor_tier(player_id, city_id, tier, at, seen, backfill)
  select h.player_id, h.city_id, g, now(), true, true
    from game.honor_rep h cross join lateral generate_series(1, game.honor_tier_of(h.rep)) g
on conflict (player_id, city_id, tier) do nothing;

-- ---------------------------------------------------------------------
-- Hak Lot
-- ---------------------------------------------------------------------
-- Harga beli satu unit pada stok keseimbangan (tanpa Kabar Pasar), dengan skill/reputasi/event pemain
create or replace function game.honor_unit_price(p_pid uuid, p_city text, p_comm text) returns bigint
language plpgsql stable as $$
declare m game.market; c game.commodities; mu record; eq numeric;
begin
  select * into m from game.market where city_id = p_city and commodity_id = p_comm;
  if not found then return null; end if;
  select * into c from game.commodities where id = p_comm and active;
  if not found then return null; end if;
  eq := game.mkt_eq(m.role, c.tier, c.ref, c.id, '{}'::jsonb);
  select * into mu from game.eco2_muls(p_pid, p_city, p_comm);
  return greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast, eq, m.role, c.tier) * mu.buy_mul))::bigint;
end $$;

create or replace function game.honor_lot_used(p_pid uuid, p_city text) returns int
language sql stable as $$
  select coalesce((select used from game.honor_lot where player_id = p_pid and city_id = p_city and day_wib = game.hr_today()), 0)
$$;

create or replace function game.honor_lot_goods(p_pid uuid, p_city text) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'commodityId', c.id, 'name', c.name, 'tier', c.tier, 'size', c.size,
      'lot', game.mkt_lot(c.tier)::int,
      'unitPrice', game.honor_unit_price(p_pid, p_city, c.id),
      'lotPrice', game.honor_unit_price(p_pid, p_city, c.id) * game.mkt_lot(c.tier)::int) order by c.sort, c.id), '[]'::jsonb)
    from game.market m join game.commodities c on c.id = m.commodity_id
   where m.city_id = p_city and m.role = 'produce' and c.active
$$;

-- ---------------------------------------------------------------------
-- Status untuk klien (key 'honor' di getGameState)
-- ---------------------------------------------------------------------
create or replace function game.honor_city_json(p_pid uuid, p_city text, p_rep numeric) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', p_city, 'name', game.city_name(p_city), 'rep', trim_scale(coalesce(p_rep, 0)),
    'tier', game.honor_tier_of(p_rep), 'tierName', game.honor_tier_name(game.honor_tier_of(p_rep)),
    'next', game.honor_tier_min(game.honor_tier_of(p_rep) + 1),
    'nextName', case when game.honor_tier_min(game.honor_tier_of(p_rep) + 1) is not null then game.honor_tier_name(game.honor_tier_of(p_rep) + 1) end,
    'floor', game.honor_tier_min(game.honor_tier_of(p_rep)))
$$;

create or replace function game.honor_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_me game.players; c text; r numeric; v_list jsonb := '[]'::jsonb; v_here jsonb; v_city text; t int;
  v_top jsonb; v_top_t int := 0; v_top_r numeric := -1; v_pel int := 0; v_tiers jsonb; v_unl jsonb;
begin
  if p_pid is null or not game.fitur_on(p_pid, 'KehormatanOpen') then return null; end if;
  select * into v_me from game.players where player_id = p_pid;
  if not found or coalesce(v_me.archetype, '') = '' then return null; end if;
  v_city := game.current_city(p_pid);
  begin v_unl := game.player_unlocks(p_pid); exception when others then v_unl := '[]'::jsonb; end;
  foreach c in array game.honor_cities() loop
    r := game.honor_num(v_me.reputation, c);
    if r <= 0 and not game.honor_visible(p_pid, c, v_unl) then continue; end if;
    t := game.honor_tier_of(r);
    v_list := v_list || jsonb_build_array(game.honor_city_json(p_pid, c, r));
    if t = 5 then v_pel := v_pel + 1; end if;
    if t > v_top_t or (t = v_top_t and t > 0 and r > v_top_r) then
      v_top_t := t; v_top_r := r;
      v_top := jsonb_build_object('city', c, 'cityName', game.city_name(c), 'tier', t, 'tierName', game.honor_tier_name(t));
    end if;
    if c = v_city then
      v_here := game.honor_city_json(p_pid, c, r) || jsonb_build_object(
        'lotMax', game.honor_lot_max(t), 'lotUsed', game.honor_lot_used(p_pid, c),
        'goods', case when game.honor_lot_max(t) > 0 then game.honor_lot_goods(p_pid, c) else '[]'::jsonb end);
    end if;
  end loop;
  select coalesce(jsonb_agg(t2 || jsonb_build_object('lots', game.honor_lot_max((t2 ->> 'tier')::int))), '[]'::jsonb)
    into v_tiers from jsonb_array_elements(game.honor_tiers()) t2;
  return jsonb_build_object(
    'tiers', v_tiers,
    'cities', v_list,
    'here', v_here,
    'top', v_top,
    'pelindung', v_pel,
    'pelindungAll', v_pel >= array_length(game.honor_cities(), 1),
    'boardMin', game.cfg_num('HonorBoardMin', 15),
    'lotResetMs', game.hr_reset_in_ms(),
    'unseen', coalesce((select jsonb_agg(jsonb_build_object('city', ht.city_id, 'cityName', game.city_name(ht.city_id),
                 'tier', ht.tier, 'tierName', game.honor_tier_name(ht.tier)) order by ht.at, ht.tier)
               from (select * from game.honor_tier where player_id = p_pid and not seen order by at, tier limit 12) ht), '[]'::jsonb),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('id', hn.id, 'kind', hn.kind, 'city', hn.city_id,
                 'cityName', game.city_name(hn.city_id), 'data', hn.data) order by hn.id)
               from (select * from game.honor_note where player_id = p_pid and not seen order by id desc limit 10) hn), '[]'::jsonb));
end $$;

-- Gelar orang lain (kartu kapten): hanya pulau yang boleh dilihat penonton
create or replace function game.honor_public(p_pid uuid, p_viewer uuid) returns jsonb
language plpgsql stable as $$
declare v_rep jsonb; c text; r numeric; t int; v_list jsonb := '[]'::jsonb; v_top jsonb; v_top_t int := 0; v_top_r numeric := -1; v_unl jsonb;
begin
  select reputation into v_rep from game.players where player_id = p_pid;
  if not found then return null; end if;
  begin v_unl := game.player_unlocks(p_viewer); exception when others then v_unl := '[]'::jsonb; end;
  foreach c in array game.honor_cities() loop
    r := game.honor_num(v_rep, c); t := game.honor_tier_of(r);
    if t < 1 or not game.honor_visible(p_viewer, c, v_unl) then continue; end if;
    v_list := v_list || jsonb_build_array(jsonb_build_object('city', c, 'cityName', game.city_name(c), 'tier', t, 'tierName', game.honor_tier_name(t)));
    if t > v_top_t or (t = v_top_t and r > v_top_r) then
      v_top_t := t; v_top_r := r;
      v_top := jsonb_build_object('city', c, 'cityName', game.city_name(c), 'tier', t, 'tierName', game.honor_tier_name(t));
    end if;
  end loop;
  return jsonb_build_object('top', v_top, 'list', v_list);
end $$;

-- ---------------------------------------------------------------------
-- Endpoint: api_kehormatan(aksi, ...)
--   'status'                    -> {honor}
--   'papan', kota               -> {board}
--   'lot', kota, barang, n      -> beli n lot dengan Hak Lot
--   'lihat', 'gelar'|'catatan'  -> tandai sudah tampil
--   'kapten', pubId             -> gelar kapten lain
-- ---------------------------------------------------------------------
create or replace function public.api_kehormatan(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_me game.players; v_pid uuid;
  v_city text; v_comm text; v_lots bigint; c game.commodities; v_role text; r numeric; t int; v_max int; v_used int;
  v_lot int; v_units bigint; v_unit bigint; v_total bigint; v_need numeric; v_free numeric; v_day date;
begin
  if v_act = 'lot' then v_me := game.me(true); else v_me := game.me(false); end if;
  v_pid := v_me.player_id;
  if coalesce(v_me.archetype, '') = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KehormatanOpen') then raise exception 'Gelar Kehormatan belum dibuka.'; end if;

  if v_act = 'status' then
    return jsonb_build_object('honor', game.honor_state(v_pid));

  elsif v_act = 'papan' then
    v_city := coalesce(game.arg(a, 1), game.current_city(v_pid));
    if not (v_city = any (game.honor_cities())) then raise exception 'Pulau ini tidak punya Papan Kehormatan.'; end if;
    if not game.honor_visible(v_pid, v_city) then raise exception 'Pulau tidak dikenal.'; end if;
    return jsonb_build_object('board', game.honor_board(v_city, v_pid));

  elsif v_act = 'kapten' then
    return jsonb_build_object('gelar', game.honor_public(game.mp_unpub(game.arg(a, 1)), v_pid));

  elsif v_act = 'lihat' then
    if coalesce(game.arg(a, 1), 'gelar') = 'catatan' then
      update game.honor_note set seen = true where player_id = v_pid and not seen;
    else
      update game.honor_tier set seen = true where player_id = v_pid and not seen;
    end if;
    return jsonb_build_object('honor', game.honor_state(v_pid));

  elsif v_act = 'lot' then
    v_city := game.arg(a, 1); v_comm := game.arg(a, 2); v_lots := game.arg_int(a, 3);
    if v_lots is null or v_lots <= 0 or v_lots > 100 then raise exception 'Jumlah lot tidak valid.'; end if;
    if not (v_city = any (game.honor_cities())) then raise exception 'Pulau ini tidak punya Hak Lot.'; end if;
    perform game.eco_require_trade_here(v_pid, v_city);
    r := game.honor_num(v_me.reputation, v_city); t := game.honor_tier_of(r); v_max := game.honor_lot_max(t);
    if v_max <= 0 then
      raise exception 'Hak Lot terbuka mulai gelar % (Standing %) di pulau ini.',
        game.honor_tier_name(3), trim_scale(game.honor_tier_min(3));
    end if;
    select * into c from game.commodities where id = v_comm and active;
    if not found then raise exception 'Barang tidak dikenal.'; end if;
    select role into v_role from game.market where city_id = v_city and commodity_id = v_comm;
    if v_role is distinct from 'produce' then raise exception 'Hak Lot hanya untuk barang hasil pulau ini.'; end if;

    v_day := game.hr_today();
    insert into game.honor_lot(player_id, city_id, day_wib, used) values (v_pid, v_city, v_day, 0)
    on conflict (player_id, city_id, day_wib) do nothing;
    select used into v_used from game.honor_lot where player_id = v_pid and city_id = v_city and day_wib = v_day for update;
    if v_used + v_lots > v_max then
      raise exception 'Jatah Hak Lot hari ini tinggal % lot.', greatest(0, v_max - v_used);
    end if;

    v_lot := game.mkt_lot(c.tier)::int;
    v_units := v_lots * v_lot;
    v_unit := game.honor_unit_price(v_pid, v_city, v_comm);
    v_total := v_unit * v_units;
    if v_me.gold < v_total then raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', v_total, v_me.gold; end if;
    v_need := v_units * c.size; v_free := game.cargo_free(v_pid);
    if v_need > v_free then
      raise exception 'Kapasitas cargo tidak cukup. Butuh % ruang, sisa %.', trim_scale(v_need), trim_scale(greatest(0, v_free));
    end if;

    update game.players set gold = gold - v_total where player_id = v_pid;
    perform game.adjust_inventory(v_pid, v_comm, v_units::int);
    perform game.inv_add_cost(v_pid, v_comm, v_units::int, v_total);
    update game.inventory set src_city = v_city where player_id = v_pid and item_id = v_comm;
    update game.honor_lot set used = used + v_lots::int where player_id = v_pid and city_id = v_city and day_wib = v_day;
    -- stok pasar TIDAK berubah ("gudang gubernur")
    perform game.hr_hook(v_pid, 'buy', v_total, jsonb_build_object('city', v_city, 'comm', v_comm, 'qty', v_units, 'role', v_role, 'lot', true));
    perform game.log(v_pid, 'Hak Lot: ' || v_units || ' ' || c.name || ' (' || v_lots || ' lot) for ' || v_total || ' gold.');
    return jsonb_build_object('lots', v_lots, 'units', v_units, 'unitPrice', v_unit, 'totalCost', v_total,
      'newGold', v_me.gold - v_total, 'avgCost', game.inv_avg_cost(v_pid, v_comm),
      'ownedQty', coalesce((select qty from game.inventory where player_id = v_pid and item_id = v_comm), 0),
      'cargoSpaceRemaining', trim_scale(greatest(0, game.cargo_free(v_pid))), 'cargoUsed', trim_scale(game.cargo_used(v_pid)),
      'honor', game.honor_state(v_pid));
  end if;
  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_kehormatan');
