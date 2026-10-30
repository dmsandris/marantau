-- =====================================================================
-- Marantau (Supabase) - 0060 JEJAK PERANTAU (Tide v44 · onboarding pemain baru)
-- Konsep: claude/KONSEP-Onboarding-Pemain-Baru.md (v2).
--
-- * Hanya untuk karakter yang dibuat SETELAH migrasi ini pertama kali di-deploy
--   (config PerantauStartAt, diisi sekali; deploy ulang tidak menggesernya).
--   Pemain lama & akun pindahan (legacy) tidak mendapat apa pun: state = null.
-- * Hari Pertama bersama Syahbandar Sunda (7 langkah) + Catatan Perantau (12 tugas).
--   Hadiah dicicil per langkah/tugas, total 70.000 gold, diklaim sekali.
-- * Kabar Pelabuhan saat Tanda Jasa mencapai 20 (sekali), plus satu pengingat.
-- Status disimpan di game.player_quests (quest_id 'perantau'):
--   data = { eligible, intro, skipped, c: {id: true}, earned, news, newsDay, remind, done }
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('PerantauStartAt', game.now_ms()::text) on conflict (key) do nothing;
insert into game.config(key, value) values ('PerantauTotal', '70000') on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Katalog hadiah (urutan = urutan tampil). kind: step (Hari Pertama) | task (Catatan Perantau)
-- ---------------------------------------------------------------------
create or replace function game.pr_catalog() returns jsonb
language sql immutable as $$
  select '[
    {"id":"s1","kind":"step","reward":500},
    {"id":"s2","kind":"step","reward":500},
    {"id":"s3","kind":"step","reward":1000},
    {"id":"s4","kind":"step","reward":500},
    {"id":"s5","kind":"step","reward":1500},
    {"id":"s6","kind":"step","reward":2000},
    {"id":"s7","kind":"step","reward":4000},
    {"id":"lapau_5","kind":"task","reward":2000},
    {"id":"talk_10","kind":"task","reward":2000},
    {"id":"chat_1","kind":"task","reward":2000},
    {"id":"repair_1","kind":"task","reward":2000},
    {"id":"book_1","kind":"task","reward":4000},
    {"id":"full_hold","kind":"task","reward":4000},
    {"id":"night_sail","kind":"task","reward":4000},
    {"id":"fish_10","kind":"task","reward":4000},
    {"id":"mission_1","kind":"task","reward":9000},
    {"id":"upgrade_1","kind":"task","reward":9000},
    {"id":"first_battle","kind":"task","reward":9000},
    {"id":"gold_10k","kind":"task","reward":9000}
  ]'::jsonb
$$;

create or replace function game.pr_reward(p_id text) returns int
language sql immutable as $$
  select (e ->> 'reward')::int from jsonb_array_elements(game.pr_catalog()) e where e ->> 'id' = p_id
$$;

-- meta pemain (Tanda Jasa) -> objek; meta lama kadang tersimpan sebagai string JSON
create or replace function game.pr_meta(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare m jsonb;
begin
  select meta into m from game.players where player_id = p_pid;
  if m is null then return '{}'::jsonb; end if;
  if jsonb_typeof(m) = 'string' then
    begin m := (m #>> '{}')::jsonb; exception when others then return '{}'::jsonb; end;
  end if;
  if jsonb_typeof(m) <> 'object' then return '{}'::jsonb; end if;
  return m;
end $$;

create or replace function game.pr_has_ach(p_pid uuid, p_id text) returns boolean
language plpgsql stable as $$
declare m jsonb := game.pr_meta(p_pid);
begin
  return coalesce(jsonb_typeof(m -> 'u') = 'object' and (m -> 'u') ? p_id, false);
end $$;

-- ---------------------------------------------------------------------
-- Kelayakan: karakter dibuat sesudah PerantauStartAt, bukan akun pindahan
-- ---------------------------------------------------------------------
create or replace function game.pr_eligible_calc(p_pid uuid) returns boolean
language plpgsql stable as $$
declare v_start numeric := game.cfg_num('PerantauStartAt', 0); p game.players; t timestamptz;
begin
  if v_start is null or v_start <= 0 then return false; end if;
  select * into p from game.players where player_id = p_pid;
  if not found or coalesce(p.archetype, '') = '' then return false; end if;
  begin
    if exists (select 1 from game.legacy_accounts where player_id = p_pid or claimed_by = p_pid) then return false; end if;
  exception when undefined_table then null;
  end;
  -- waktu karakter lahir = catatan log pertama "Began your journey"; cadangan: waktu akun dibuat
  select min(ts) into t from game.player_log where player_id = p_pid and message like 'Began your journey%';
  t := coalesce(t, p.created_at);
  return t >= to_timestamp(v_start / 1000.0);
end $$;

create or replace function game.pr_row(p_pid uuid) returns game.player_quests
language plpgsql as $$
declare q game.player_quests;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'perantau';
  if found then return q; end if;
  if coalesce((select archetype from game.players where player_id = p_pid), '') = '' then return null; end if;
  insert into game.player_quests(player_id, quest_id, step, data)
  values (p_pid, 'perantau', 0, jsonb_build_object('eligible', game.pr_eligible_calc(p_pid), 'c', '{}'::jsonb, 'earned', 0))
  on conflict (player_id, quest_id) do nothing;
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'perantau';
  return q;
end $$;

-- ---------------------------------------------------------------------
-- Pemeriksaan sisi server per langkah/tugas
-- ---------------------------------------------------------------------
create or replace function game.pr_check(p_pid uuid, p_id text) returns boolean
language plpgsql stable as $$
begin
  case p_id
    when 's1', 's2', 's4' then return true;
    when 's3' then
      return exists (select 1 from game.player_log where player_id = p_pid and message like 'Bought %')
          or exists (select 1 from game.inventory where player_id = p_pid and qty > 0);
    when 's5' then
      return game.in_transit(p_pid)
          or exists (select 1 from game.player_log where player_id = p_pid and message like 'Set sail %');
    when 's6' then
      return exists (select 1 from game.player_log where player_id = p_pid and message like 'Sold %');
    when 's7' then
      return exists (select 1 from game.player_missions where player_id = p_pid);
    when 'book_1' then
      return exists (select 1 from game.player_books where player_id = p_pid) or game.pr_has_ach(p_pid, p_id);
    when 'mission_1' then
      return exists (select 1 from game.player_missions where player_id = p_pid and status = 'completed') or game.pr_has_ach(p_pid, p_id);
    when 'gold_10k' then
      return coalesce((select gold from game.players where player_id = p_pid), 0) >= 10000 or game.pr_has_ach(p_pid, p_id);
    when 'first_battle' then
      return exists (select 1 from game.combat_log where player_id = p_pid) or game.pr_has_ach(p_pid, p_id);
    else
      if game.pr_reward(p_id) is null then return false; end if;
      return game.pr_has_ach(p_pid, p_id);
  end case;
end $$;

-- ---------------------------------------------------------------------
-- State untuk klien (null = bukan pemain baru)
-- ---------------------------------------------------------------------
create or replace function game.perantau_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; d jsonb; v_gala int := 0;
begin
  q := game.pr_row(p_pid);
  if q is null then return null; end if;
  d := q.data;
  if not coalesce((d ->> 'eligible')::boolean, false) then return null; end if;
  begin v_gala := game.gala_step(p_pid); exception when others then v_gala := 0; end;
  return jsonb_build_object(
    'intro', coalesce((d ->> 'intro')::boolean, false),
    'skipped', coalesce((d ->> 'skipped')::boolean, false),
    'claimed', coalesce(d -> 'c', '{}'::jsonb),
    'earned', coalesce((d ->> 'earned')::int, 0),
    'total', game.cfg_num('PerantauTotal', 70000),
    'catalog', game.pr_catalog(),
    'done', coalesce((d ->> 'done')::boolean, false),
    'news', coalesce((d ->> 'news')::boolean, false),
    'newsDay', coalesce((d ->> 'newsDay')::int, 0),
    'remind', coalesce((d ->> 'remind')::boolean, false),
    'badges', game.gala_badges(p_pid),
    'galaStep', v_gala,
    'gameDay', game.game_day());
end $$;

-- ---------------------------------------------------------------------
-- Aksi. a = [aksi, arg]: status | intro | skip | claim <id> | done | news | remind
-- ---------------------------------------------------------------------
create or replace function public.api_perantau(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := btrim(coalesce(game.arg(a, 1), ''));
  q game.player_quests; d jsonb; v_rew int; v_earned int; v_total int; v_gold bigint;
begin
  if v_act = 'status' then return jsonb_build_object('perantau', game.perantau_state(v_pid)); end if;
  q := game.pr_row(v_pid);
  if q is null or not coalesce((q.data ->> 'eligible')::boolean, false) then
    raise exception 'Jejak Perantau hanya untuk kapten baru.';
  end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'perantau' for update;
  d := q.data;

  if v_act = 'intro' then
    d := d || jsonb_build_object('intro', true);
  elsif v_act = 'skip' then
    d := d || jsonb_build_object('skipped', true, 'intro', true);
  elsif v_act = 'done' then
    d := d || jsonb_build_object('done', true);
  elsif v_act = 'claim' then
    v_rew := game.pr_reward(v_arg);
    if v_rew is null then raise exception 'Tugas tidak dikenal.'; end if;
    if coalesce(d -> 'c', '{}'::jsonb) ? v_arg then raise exception 'Hadiah tugas ini sudah diterima.'; end if;
    if not coalesce(game.pr_check(v_pid, v_arg), false) then raise exception 'Tugas ini belum selesai, Tuan Kapten.'; end if;
    v_earned := coalesce((d ->> 'earned')::int, 0);
    v_total := game.cfg_num('PerantauTotal', 70000)::int;
    v_rew := greatest(0, least(v_rew, v_total - v_earned));
    d := jsonb_set(d, '{c}', coalesce(d -> 'c', '{}'::jsonb) || jsonb_build_object(v_arg, true))
         || jsonb_build_object('earned', v_earned + v_rew);
    if v_rew > 0 then
      update game.players set gold = gold + v_rew where player_id = v_pid returning gold into v_gold;
      perform game.log(v_pid, 'Jejak Perantau: menerima ' || v_rew || ' gold dari Syahbandar Sunda.');
    end if;
  elsif v_act = 'news' then
    if game.gala_badges(v_pid) < 20 then raise exception 'Belum ada kabar, Tuan Kapten.'; end if;
    if not coalesce((d ->> 'news')::boolean, false) then
      d := d || jsonb_build_object('news', true, 'newsDay', game.game_day());
    end if;
  elsif v_act = 'remind' then
    d := d || jsonb_build_object('remind', true);
  else
    raise exception 'Aksi tidak dikenal.';
  end if;

  update game.player_quests set data = d, updated_at = now(),
    step = (select count(*) from jsonb_object_keys(coalesce(d -> 'c', '{}'::jsonb)))::int
   where player_id = v_pid and quest_id = 'perantau';
  return jsonb_build_object('perantau', game.perantau_state(v_pid), 'reward', coalesce(v_rew, 0),
    'newGold', coalesce(v_gold, (select gold from game.players where player_id = v_pid)));
end $$;
select game.expose('api_perantau');

-- ---------------------------------------------------------------------
-- Saran barang & rute untuk Hari Pertama: barang produksi kota ini (bukan premium) yang
-- paling untung dijual di kota terdekat yang membutuhkannya. Harga dihitung saat ini.
-- ---------------------------------------------------------------------
create or replace function game.pr_unit_price(p_pid uuid, p_city text, p_comm text, p_buy boolean) returns int
language plpgsql stable as $$
declare m game.market; c game.commodities; mu record; s numeric; cyc bigint := game.mkt_cycle_index();
begin
  select * into m from game.market where city_id = p_city and commodity_id = p_comm;
  if not found then return null; end if;
  select * into c from game.commodities where id = p_comm and active;
  if not found then return null; end if;
  s := game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, game.mkt_cycle_tags(p_city, cyc), cyc);
  select * into mu from game.eco2_muls(p_pid, p_city, p_comm);
  return greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast,
    game.mkt_lotx(s + case when p_buy then -0.5 else 0.5 end, c.tier), m.role, c.tier)
    * case when p_buy then mu.buy_mul else mu.sell_mul end))::int;
end $$;

create or replace function game.perantau_suggest(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_here text := game.current_city(p_pid); h game.cities; r record; best jsonb := null; best_score numeric := -1;
  bp int; sp int; v_gold bigint; v_free numeric; v_qty int; score numeric; dist numeric;
begin
  select * into h from game.cities where city_id = v_here;
  if not found then return null; end if;
  select gold into v_gold from game.players where player_id = p_pid;
  v_free := greatest(0, game.cargo_free(p_pid));
  for r in
    select m.commodity_id, c.name, c.size, c.tier, ci.city_id as dest, ci.name as dest_name, ci.map_x, ci.map_y,
           game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, game.mkt_cycle_tags(v_here, game.mkt_cycle_index()), game.mkt_cycle_index()) as stock
      from game.market m
      join game.commodities c on c.id = m.commodity_id and c.active and c.tier <> 'premium'
      join game.market md on md.commodity_id = m.commodity_id and md.role = 'consume'
      join game.cities ci on ci.city_id = md.city_id
     where m.city_id = v_here and m.role = 'produce'
       and ci.city_id <> v_here and not coalesce(ci.hidden, false) and ci.type <> 'Outlaw'
       and not game.voy_far_city(ci.city_id)
  loop
    if r.stock < 5 then continue; end if;
    bp := game.pr_unit_price(p_pid, v_here, r.commodity_id, true);
    sp := game.pr_unit_price(p_pid, r.dest, r.commodity_id, false);
    if bp is null or sp is null or sp <= bp then continue; end if;
    v_qty := least(floor(r.stock)::int, floor(v_gold * 0.5 / bp)::int, floor(v_free / greatest(r.size, 0.01))::int, 20);
    if v_qty < 1 then continue; end if;
    dist := sqrt(power(r.map_x - h.map_x, 2) + power(r.map_y - h.map_y, 2));
    score := (sp - bp)::numeric * v_qty / (1 + dist / 25);
    if score > best_score then
      best_score := score;
      best := jsonb_build_object('item', r.commodity_id, 'itemName', r.name, 'qty', v_qty, 'buyPrice', bp,
        'dest', r.dest, 'destName', r.dest_name, 'sellPrice', sp, 'profit', (sp - bp) * v_qty, 'from', v_here);
    end if;
  end loop;
  return best;
end $$;

create or replace function public.api_perantauSuggest(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); begin
  if game.perantau_state(v_me.player_id) is null then return jsonb_build_object('suggest', null); end if;
  return jsonb_build_object('suggest', game.perantau_suggest(v_me.player_id));
end $$;
select game.expose('api_perantausuggest');

-- ---------------------------------------------------------------------
-- Buat Kapten (langkah 1): cek nama kapten sudah dipakai atau belum, sebelum lanjut
-- ---------------------------------------------------------------------
create or replace function public.api_captainNameFree(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); v_name text := game.eco_trim(coalesce(game.arg(a, 0), ''));
begin
  if v_name = '' then return jsonb_build_object('free', false, 'reason', 'Nama kapten tidak boleh kosong.'); end if;
  if char_length(v_name) > 40 then return jsonb_build_object('free', false, 'reason', 'Nama kapten terlalu panjang.'); end if;
  if exists (select 1 from game.players where player_id <> v_me.player_id and lower(game.eco_trim(character_name)) = lower(v_name)) then
    return jsonb_build_object('free', false, 'reason', 'Nama kapten "' || v_name || '" sudah dipakai pemain lain.');
  end if;
  return jsonb_build_object('free', true);
end $$;
select game.expose('api_captainnamefree');
