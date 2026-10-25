-- =====================================================================
-- Marantau (Supabase) - 0033 PACU DAGANG (Tide v37 · Fase 2). Aman diulang.
--
-- Lomba dagang akhir pekan (semua jam WIB, ikut HarianClockOffset untuk uji):
--   Jumat 20:00 bocoran Komoditas Unggulan · Sabtu 00:00 dibuka · Minggu 18:00 Papan Ditutup
--   Minggu 23:59:59 skor dikunci · Senin 00:00-08:00 jeda juri · Senin 08:00 pengumuman + hadiah.
-- Skor = Untung Pacu dari penjualan ke pasar kota (0032 game.pacu_profit), x PacuThemeMul
-- untuk kelompok barang unggulan. Tidak ada cron: game.pd_tick() memajukan semuanya saat
-- ada panggilan (getGameState / api_pacu) dari kapten yang fiturnya terbuka.
-- Gerbang: PacuOpen = '0' -> hanya FiturPenguji. Kabar chat dunia hanya bila PacuOpen = '1'.
-- Pekan Uji: PacuGoldOn = '0' -> hadiah keping saja (tanpa gold).
-- Admin (SQL Editor):
--   select * from game.pd_audit where event_id = 'PD-2026-10-31';
--   select game.admin_pacu_coret('PD-2026-10-31', 'username', 'alasan');   -- sebelum Senin 08:00
-- =====================================================================

insert into game.config(key, value) values
  ('PacuOpen', '0'), ('PacuGoldOn', '0'), ('PacuCloseBoardHours', '6'), ('PacuThemeMul', '1.5'),
  ('PacuTargetJukung', '3000,12000,40000'), ('PacuTargetPinisi', '15000,60000,200000'), ('PacuTargetGaliung', '150000,600000,2000000'),
  ('PacuTierKeping', '20,40,80'), ('PacuJuaraKeping', '200,120,80'), ('PacuKategoriKeping', '150'),
  ('PacuGoldJukung', '50000'), ('PacuGoldPinisi', '250000'), ('PacuGoldGaliung', '750000'),
  ('PacuMataMinJual', '15'), ('PacuNewsGapHours', '3')
on conflict (key) do nothing;

-- Layar Emas permanen (juara 1 tiga kali) - rupa eksklusif slot layar
insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, exclusive, active, sort) values
  ('layar_emas', 'rupa', 'layar', null, 'Layar Emas', 'legenda', 0, 'Layar berkilau emas bersulam nama golonganmu. Untuk juara 1 Pacu Dagang tiga kali.', null, true, true, 192)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, name = excluded.name, rarity = excluded.rarity,
  price = excluded.price, info = excluded.info, exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Waktu & jadwal (timestamp tanpa zona = jam WIB)
-- ---------------------------------------------------------------------
create or replace function game.pd_wib() returns timestamp
language sql stable as $$ select (game.hr_now() at time zone 'UTC') + interval '7 hours' $$;

-- Sabtu milik event yang pengumumannya (Senin 08:00) belum lewat
create or replace function game.pd_cur_sat() returns date
language plpgsql stable as $$
declare n timestamp := game.pd_wib(); d0 date; s date;
begin
  d0 := (n - interval '56 hours')::date;
  s := d0 + ((6 - extract(isodow from d0)::int + 7) % 7);
  if s + interval '56 hours' <= n then s := s + 7; end if;
  return s;
end $$;

create or replace function game.pd_id(p_sat date) returns text
language sql immutable as $$ select 'PD-' || to_char(p_sat, 'YYYY-MM-DD') $$;

create or replace function game.pd_t(p_sat date, p_what text) returns timestamp
language sql stable as $$
  select case p_what
    when 'reveal'   then p_sat::timestamp - interval '4 hours'
    when 'start'    then p_sat::timestamp
    when 'close'    then p_sat::timestamp + interval '2 days' - make_interval(hours => greatest(0, least(48, game.cfg_num('PacuCloseBoardHours', 6)::int)))
    when 'end'      then p_sat::timestamp + interval '2 days'
    when 'announce' then p_sat::timestamp + interval '56 hours'
  end
$$;

create or replace function game.pd_status(p_sat date) returns text
language sql stable as $$
  select case
    when game.pd_wib() < game.pd_t(p_sat, 'reveal') then 'planned'
    when game.pd_wib() < game.pd_t(p_sat, 'start') then 'revealed'
    when game.pd_wib() < game.pd_t(p_sat, 'end') then 'open'
    when game.pd_wib() < game.pd_t(p_sat, 'announce') then 'judging'
    else 'announced' end
$$;

create or replace function game.pd_ms(p_ts timestamp) returns bigint
language sql stable as $$ select (extract(epoch from (p_ts - game.pd_wib())) * 1000)::bigint $$;

-- Komoditas Unggulan berputar tiap pekan
create or replace function game.pd_theme(p_sat date) returns text
language sql immutable as $$
  select (array['rempah', 'mewah', 'pangan', 'kerajinan', 'minuman', 'bahan'])[((((p_sat - date '2026-10-31') / 7) % 6 + 6) % 6) + 1]
$$;
create or replace function game.pd_theme_name(p_grp text) returns text
language sql immutable as $$
  select case p_grp when 'rempah' then 'Rempah' when 'mewah' then 'Barang Mewah' when 'pangan' then 'Pangan'
    when 'kerajinan' then 'Kerajinan' when 'minuman' then 'Minuman' when 'bahan' then 'Bahan' else p_grp end
$$;

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists game.pd_events (
  id           text primary key,
  sat          date not null unique,
  theme        text not null,
  status       text not null default 'planned',   -- planned | revealed | open | judging | announced
  flags        jsonb not null default '{}'::jsonb, -- kabar chat yang sudah dikirim
  leaders      jsonb not null default '{}'::jsonb, -- {golongan: player_id} pemimpin terakhir (kabar salip)
  results      jsonb,
  announced_at timestamptz
);
alter table game.pd_events enable row level security;

create table if not exists game.pd_scores (
  event_id    text not null references game.pd_events(id) on delete cascade,
  player_id   uuid not null references game.players(player_id) on update cascade on delete cascade,
  gol         int not null,                 -- golongan dikunci pada penjualan pertama di event
  score       numeric not null default 0,   -- untung pacu x pengali unggulan
  profit      numeric not null default 0,   -- untung pacu murni
  cost        numeric not null default 0,   -- modal pacu
  revenue     numeric not null default 0,
  sells       int not null default 0,
  sells_win   int not null default 0,
  cities      jsonb not null default '[]'::jsonb,   -- pulau tempat jual untung
  reached_at  timestamptz not null default now(),   -- seri: yang lebih dulu mencapai skor menang
  tier_live   int not null default 0,
  notified_at timestamptz,
  banned      boolean not null default false,
  ban_note    text,
  primary key (event_id, player_id)
);
alter table game.pd_scores enable row level security;
create index if not exists pd_scores_rank_idx on game.pd_scores (event_id, gol, score desc);

create table if not exists game.pd_record (
  player_id  uuid primary key references game.players(player_id) on update cascade on delete cascade,
  last3      jsonb not null default '[]'::jsonb,
  n_ikut     int not null default 0,
  n_perunggu int not null default 0,
  n_emas     int not null default 0,
  juara1     int not null default 0,
  mata       int not null default 0,
  jelajah    int not null default 0,
  lompat     int not null default 0
);
alter table game.pd_record enable row level security;

create or replace function game.pd_ensure(p_sat date) returns game.pd_events
language plpgsql as $$
declare e game.pd_events;
begin
  insert into game.pd_events(id, sat, theme) values (game.pd_id(p_sat), p_sat, game.pd_theme(p_sat)) on conflict (sat) do nothing;
  select * into e from game.pd_events where sat = p_sat;
  return e;
end $$;

-- ---------------------------------------------------------------------
-- Target Pribadi: dari rekor sendiri, tidak di bawah target dasar golongan
-- ---------------------------------------------------------------------
create or replace function game.pd_base(p_gol int, p_i int) returns numeric
language sql stable as $$
  select game.hr_num(game.cfg(case p_gol when 1 then 'PacuTargetJukung' when 2 then 'PacuTargetPinisi' else 'PacuTargetGaliung' end), p_i,
    (case p_gol when 1 then array[3000, 12000, 40000] when 2 then array[15000, 60000, 200000] else array[150000, 600000, 2000000] end)[p_i])
$$;
create or replace function game.pd_avg(p_pid uuid) returns numeric
language sql stable as $$
  select avg(x::numeric) from game.pd_record r, jsonb_array_elements_text(r.last3) x where r.player_id = p_pid
$$;
create or replace function game.pd_targets(p_pid uuid, p_gol int) returns numeric[]
language plpgsql stable as $$
declare a numeric := coalesce(game.pd_avg(p_pid), 0);
begin
  return array[greatest(game.pd_base(p_gol, 1), round(a * 0.6)), greatest(game.pd_base(p_gol, 2), round(a)), greatest(game.pd_base(p_gol, 3), round(a * 1.5))];
end $$;
create or replace function game.pd_tier(p_score numeric, p_t numeric[]) returns int
language sql immutable as $$ select (p_score >= p_t[1])::int + (p_score >= p_t[2])::int + (p_score >= p_t[3])::int $$;

-- ---------------------------------------------------------------------
-- Skor dari penjualan (dipanggil game.hr_hook untuk kind 'sell')
-- ---------------------------------------------------------------------
create or replace function game.pd_on_sell(p_pid uuid, p_revenue numeric, p_ctx jsonb) returns void
language plpgsql as $$
declare s date := game.pd_cur_sat(); n timestamp := game.pd_wib(); e game.pd_events; o game.pd_scores; r game.pd_scores;
  v_profit numeric; v_cost numeric; v_pts numeric; v_city text := p_ctx ->> 'city'; v_gol int; t numeric[]; v_tier int;
  v_name text; v_rank int; v_open boolean := lower(coalesce(game.cfg('PacuOpen'), '0')) in ('1', 'true', 'on', 'ya'); q record;
begin
  if n < game.pd_t(s, 'start') or n >= game.pd_t(s, 'end') then return; end if;
  e := game.pd_ensure(s);
  v_profit := game.pacu_profit(p_revenue, (p_ctx ->> 'qty')::numeric, (p_ctx ->> 'avg')::numeric, (p_ctx ->> 'base')::numeric);
  v_cost := coalesce((p_ctx ->> 'qty')::numeric, 0) * greatest(coalesce((p_ctx ->> 'avg')::numeric, 0), game.cfg_num('PacuFloorRatio', 0.6) * coalesce((p_ctx ->> 'base')::numeric, 0));
  v_pts := round(v_profit * case when p_ctx ->> 'grp' = e.theme then game.cfg_num('PacuThemeMul', 1.5) else 1 end);
  select * into o from game.pd_scores where event_id = e.id and player_id = p_pid for update;
  v_gol := coalesce(o.gol, game.golongan(p_pid));
  insert into game.pd_scores as x (event_id, player_id, gol, score, profit, cost, revenue, sells, sells_win, cities, reached_at)
  values (e.id, p_pid, v_gol, v_pts, v_profit, v_cost, p_revenue, 1, (v_profit > 0)::int,
    case when v_profit > 0 and v_city is not null then jsonb_build_array(v_city) else '[]'::jsonb end, now())
  on conflict (event_id, player_id) do update set
    score = x.score + excluded.score, profit = x.profit + excluded.profit, cost = x.cost + excluded.cost,
    revenue = x.revenue + excluded.revenue, sells = x.sells + 1, sells_win = x.sells_win + excluded.sells_win,
    cities = case when v_profit > 0 and v_city is not null and not (x.cities ? v_city) then x.cities || to_jsonb(v_city) else x.cities end,
    reached_at = case when excluded.score <> 0 then now() else x.reached_at end
  returning * into r;

  -- Target Pribadi tercapai (kabar pribadi; keping diberikan saat pengumuman)
  t := game.pd_targets(p_pid, v_gol);
  v_tier := game.pd_tier(r.score, t);
  if v_tier > r.tier_live then
    update game.pd_scores set tier_live = v_tier where event_id = e.id and player_id = p_pid;
    perform game.mp_push_inbox(p_pid, jsonb_build_object('type', 'pacu_tier', 'tier', v_tier, 'score', r.score, 'target', t[v_tier]));
  end if;

  -- kabar salip (tidak saat Papan Ditutup)
  if n >= game.pd_t(s, 'close') or r.banned then return; end if;
  select coalesce(nullif(character_name, ''), 'Seorang kapten') into v_name from game.players where player_id = p_pid;
  if v_pts > 0 then
    for q in select x.player_id, x.score, x.reached_at from game.pd_scores x
              where x.event_id = e.id and x.gol = v_gol and not x.banned and x.player_id <> p_pid
                and x.score >= coalesce(o.score, 0) and x.score < r.score
                and (x.notified_at is null or x.notified_at < now() - interval '1 hour') loop
      select 1 + count(*) into v_rank from game.pd_scores y where y.event_id = e.id and y.gol = v_gol and not y.banned and (y.score > q.score or (y.score = q.score and y.reached_at < q.reached_at));
      if v_rank <= 4 then
        perform game.mp_push_inbox(q.player_id, jsonb_build_object('type', 'pacu_salip', 'from', v_name, 'rank', v_rank));
        update game.pd_scores set notified_at = now() where event_id = e.id and player_id = q.player_id;
      end if;
    end loop;
  end if;
  select 1 + count(*) into v_rank from game.pd_scores y where y.event_id = e.id and y.gol = v_gol and not y.banned and (y.score > r.score or (y.score = r.score and y.reached_at < r.reached_at));
  if v_rank = 1 and r.score > 0 and (e.leaders ->> v_gol::text) is distinct from p_pid::text then
    update game.pd_events set leaders = leaders || jsonb_build_object(v_gol::text, p_pid::text) where id = e.id;
    if v_open and coalesce((e.flags ->> ('news' || v_gol))::bigint, 0) < game.now_ms() - game.cfg_num('PacuNewsGapHours', 3) * 3600000 then
      update game.pd_events set flags = flags || jsonb_build_object('news' || v_gol, game.now_ms()) where id = e.id;
      perform game.sys_chat('coco epan', case when v_name ilike 'kapten %' then '' else 'Kapten ' end || v_name || ' merebut kursi pertama ' || game.golongan_nama(v_gol) || '. Buku besar mulai panas.');
    end if;
  end if;
end $$;

-- Kejadian: Pesanan Harian (0032) + Pacu Dagang. Masing-masing berpengaman.
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
begin
  if p_pid is null then return; end if;
  if game.fitur_on(p_pid, 'HarianOpen') then
    begin
      perform game.hr_event(p_pid, p_kind, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[harian] % %: %', p_kind, p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'sell' and game.fitur_on(p_pid, 'PacuOpen') then
    begin
      perform game.pd_on_sell(p_pid, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[pacu] %: %', p_pid, sqlerrm;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Pengumuman (Senin 08:00): pemenang, hadiah, rekor, prasasti
-- ---------------------------------------------------------------------
create or replace function game.pd_finalize(p_sat date) returns void
language plpgsql as $$
declare e game.pd_events; r record; v_gold boolean := lower(coalesce(game.cfg('PacuGoldOn'), '0')) in ('1', 'true', 'on', 'ya');
  v_open boolean := lower(coalesce(game.cfg('PacuOpen'), '0')) in ('1', 'true', 'on', 'ya');
  tk numeric[]; jk numeric[]; v_cat numeric := game.cfg_num('PacuKategoriKeping', 150); v_g int; v_n int; v_k int;
  v_res jsonb := '{}'::jsonb; v_gols jsonb := '{}'::jsonb; v_winners jsonb := '[]'::jsonb; v_list jsonb; v_mata jsonb; v_jelajah jsonb; v_lompat jsonb;
  v_kp bigint; v_gp bigint; v_titles jsonb; v_rank int; v_line text := ''; v_has boolean;
begin
  select * into e from game.pd_events where sat = p_sat for update;
  if not found or e.status = 'announced' then return; end if;
  tk := array[game.hr_num(game.cfg('PacuTierKeping'), 1, 20), game.hr_num(game.cfg('PacuTierKeping'), 2, 40), game.hr_num(game.cfg('PacuTierKeping'), 3, 80)];
  jk := array[game.hr_num(game.cfg('PacuJuaraKeping'), 1, 200), game.hr_num(game.cfg('PacuJuaraKeping'), 2, 120), game.hr_num(game.cfg('PacuJuaraKeping'), 3, 80)];

  -- peringkat & tier dihitung dengan rekor SEBELUM pekan ini
  create temp table if not exists pd_tmp (player_id uuid primary key, name text, gol int, score numeric, profit numeric, cost numeric,
    sells_win int, ncity int, reached_at timestamptz, tier int, avg numeric, rank int, titles jsonb, kp bigint, gp bigint) on commit drop;
  delete from pd_tmp;
  insert into pd_tmp
  select s.player_id, coalesce(nullif(p.character_name, ''), 'Kapten'), s.gol, s.score, s.profit, s.cost, s.sells_win,
         jsonb_array_length(s.cities), s.reached_at, game.pd_tier(s.score, game.pd_targets(s.player_id, s.gol)), game.pd_avg(s.player_id),
         null, '[]'::jsonb, 0, 0
    from game.pd_scores s join game.players p on p.player_id = s.player_id
   where s.event_id = e.id and not s.banned;

  -- Juara Pacu per golongan (wajib lolos Perunggu; < 3 peserta lolos = hanya juara 1)
  for v_g in 1..3 loop
    select count(*) into v_n from pd_tmp where gol = v_g and tier >= 1;
    v_k := 0; v_list := '[]'::jsonb;
    for r in select * from pd_tmp where gol = v_g and tier >= 1 order by score desc, reached_at asc limit case when v_n >= 3 then 3 else 1 end loop
      v_k := v_k + 1;
      v_gp := case when v_gold then round(game.cfg_num(case v_g when 1 then 'PacuGoldJukung' when 2 then 'PacuGoldPinisi' else 'PacuGoldGaliung' end, 0)
              * (array[1, 0.5, 0.25])[v_k])::bigint else 0 end;
      update pd_tmp set rank = v_k, kp = kp + jk[v_k], gp = gp + v_gp,
        titles = titles || to_jsonb(case v_k when 1 then 'Juara Pacu ' || game.golongan_nama(v_g) when 2 then 'Juara 2 ' || game.golongan_nama(v_g) else 'Juara 3 ' || game.golongan_nama(v_g) end)
       where player_id = r.player_id;
      v_list := v_list || jsonb_build_array(jsonb_build_object('pid', r.player_id, 'name', r.name, 'score', r.score, 'rank', v_k, 'gold', v_gp));
      if v_k = 1 then v_winners := v_winners || to_jsonb(r.player_id::text); v_line := v_line || game.golongan_nama(v_g) || ': ' || r.name || '. '; end if;
    end loop;
    v_gols := v_gols || jsonb_build_object(v_g::text, jsonb_build_object('list', v_list, 'peserta', (select count(*) from pd_tmp where gol = v_g)));
  end loop;

  -- Mata Saudagar: margin terbaik
  select jsonb_build_object('pid', player_id, 'name', name, 'ratio', round(profit / cost, 3)) into v_mata
    from pd_tmp where tier >= 1 and sells_win >= game.cfg_num('PacuMataMinJual', 15) and cost > 0
   order by profit / cost desc, reached_at limit 1;
  -- Penjelajah Pasar: pulau berbeda terbanyak
  select jsonb_build_object('pid', player_id, 'name', name, 'n', ncity) into v_jelajah
    from pd_tmp where score > 0 and ncity >= 2 order by ncity desc, score desc, reached_at limit 1;
  -- Lompatan Terjauh: skor dibanding rekor sendiri
  select jsonb_build_object('pid', player_id, 'name', name, 'ratio', round(score / avg, 2)) into v_lompat
    from pd_tmp where avg > 0 and score > 0 order by score / avg desc, reached_at limit 1;
  if v_mata is not null then update pd_tmp set kp = kp + v_cat, titles = titles || '"Mata Saudagar"'::jsonb where player_id = (v_mata ->> 'pid')::uuid; end if;
  if v_jelajah is not null then update pd_tmp set kp = kp + v_cat, titles = titles || '"Penjelajah Pasar"'::jsonb where player_id = (v_jelajah ->> 'pid')::uuid; end if;
  if v_lompat is not null then update pd_tmp set kp = kp + v_cat, titles = titles || '"Lompatan Terjauh"'::jsonb where player_id = (v_lompat ->> 'pid')::uuid; end if;
  -- keping Target Pribadi (bertumpuk)
  update pd_tmp set kp = kp + (case when tier >= 1 then tk[1] else 0 end) + (case when tier >= 2 then tk[2] else 0 end) + (case when tier >= 3 then tk[3] else 0 end);

  -- hadiah, kabar, rekor
  for r in select * from pd_tmp loop
    if r.kp > 0 then perform game.keping_add(r.player_id, r.kp, 'pacu', e.id); end if;
    if r.gp > 0 then update game.players set gold = gold + r.gp where player_id = r.player_id; end if;
    if r.kp > 0 or r.gp > 0 then
      perform game.log(r.player_id, 'Pacu Dagang ' || to_char(e.sat, 'DD-MM-YYYY') || ': skor ' || to_char(r.score, 'FM999G999G999G990')
        || ', hadiah ' || r.kp || ' keping' || case when r.gp > 0 then ' dan ' || to_char(r.gp, 'FM999G999G999') || ' gold' else '' end || '.');
    end if;
    perform game.mp_push_inbox(r.player_id, jsonb_build_object('type', 'pacu_hasil', 'event', e.id, 'score', r.score, 'tier', r.tier,
      'rank', r.rank, 'keping', r.kp, 'gold', r.gp, 'titles', r.titles));
    insert into game.pd_record(player_id) values (r.player_id) on conflict (player_id) do nothing;
    update game.pd_record set
      last3 = (select coalesce(jsonb_agg(v order by k), '[]'::jsonb) from (
                 select v, k from jsonb_array_elements(last3 || to_jsonb(r.score)) with ordinality z(v, k)
                 order by k desc limit 3) w),
      n_ikut = n_ikut + 1, n_perunggu = n_perunggu + (r.tier >= 1)::int, n_emas = n_emas + (r.tier >= 3)::int,
      juara1 = juara1 + coalesce(r.rank = 1, false)::int,
      mata = mata + coalesce(r.player_id = (v_mata ->> 'pid')::uuid, false)::int,
      jelajah = jelajah + coalesce(r.player_id = (v_jelajah ->> 'pid')::uuid, false)::int,
      lompat = lompat + coalesce(r.player_id = (v_lompat ->> 'pid')::uuid, false)::int
     where player_id = r.player_id;
    if coalesce(r.rank = 1, false) and (select juara1 from game.pd_record where player_id = r.player_id) >= 3 and game.kd_qty(r.player_id, 'layar_emas') = 0 then
      perform game.kd_grant(r.player_id, 'layar_emas', 1, 'pacu');
      perform game.mp_push_inbox(r.player_id, jsonb_build_object('type', 'pacu_layar_emas'));
    end if;
  end loop;

  select exists (select 1 from pd_tmp) into v_has;
  v_res := jsonb_build_object('event', e.id, 'sat', e.sat, 'theme', e.theme, 'themeName', game.pd_theme_name(e.theme),
    'gol', v_gols, 'mata', v_mata, 'jelajah', v_jelajah, 'lompat', v_lompat, 'winners', v_winners,
    'peserta', (select count(*) from pd_tmp), 'gold', v_gold);
  update game.pd_events set status = 'announced', results = v_res, announced_at = now() where id = e.id;
  if v_open and v_has then
    perform game.sys_chat('coco epan', 'Buku besar Pacu Dagang dibuka. Juara pekan ini - ' || coalesce(nullif(v_line, ''), 'belum ada yang lolos target. ')
      || case when v_mata is not null then 'Mata Saudagar: ' || (v_mata ->> 'name') || '. ' else '' end
      || case when v_jelajah is not null then 'Penjelajah Pasar: ' || (v_jelajah ->> 'name') || '. ' else '' end
      || case when v_lompat is not null then 'Lompatan Terjauh: ' || (v_lompat ->> 'name') || '.' else '' end);
  end if;
  drop table if exists pd_tmp;
end $$;

-- ---------------------------------------------------------------------
-- Detak: bocoran, pembukaan, peringatan, Papan Ditutup, pengumuman event lama
-- ---------------------------------------------------------------------
create or replace function game.pd_tick() returns void
language plpgsql as $$
declare s date := game.pd_cur_sat(); n timestamp := game.pd_wib(); e game.pd_events; v_open boolean := lower(coalesce(game.cfg('PacuOpen'), '0')) in ('1', 'true', 'on', 'ya');
  v_old date; v_id text;
begin
  -- pengumuman event yang sudah lewat Senin 08:00 (biasanya hanya satu)
  for v_old in select sat from game.pd_events where sat < s and status <> 'announced' order by sat loop
    perform game.pd_finalize(v_old);
  end loop;
  e := game.pd_ensure(s);
  update game.pd_events set status = game.pd_status(s) where id = e.id and status is distinct from game.pd_status(s);
  if n >= game.pd_t(s, 'reveal') and n < game.pd_t(s, 'end') then
    update game.pd_events set flags = flags || '{"reveal":true}'::jsonb where id = e.id and not (flags ? 'reveal') returning id into v_id;
    if v_id is not null and v_open and n < game.pd_t(s, 'start') then
      perform game.sys_chat('coco epan', 'Bocoran Pacu Dagang: akhir pekan ini coco epan mencari ' || lower(game.pd_theme_name(e.theme))
        || '. Untungnya dihitung x' || replace(game.cfg_num('PacuThemeMul', 1.5)::text, '.', ',') || '. Buku besar dibuka Sabtu 00:00 WIB.');
    end if;
  end if;
  v_id := null;
  if n >= game.pd_t(s, 'start') and n < game.pd_t(s, 'end') then
    update game.pd_events set flags = flags || '{"start":true}'::jsonb where id = e.id and not (flags ? 'start') returning id into v_id;
    if v_id is not null and v_open then
      perform game.sys_chat('coco epan', 'Buku besar dibuka. Berpacu, Kapten! Komoditas Unggulan: ' || game.pd_theme_name(e.theme) || '. Pengumuman Senin 08:00 WIB.');
    end if;
  end if;
  v_id := null;
  if n >= game.pd_t(s, 'close') - interval '1 hour' and n < game.pd_t(s, 'close') then
    update game.pd_events set flags = flags || '{"warn":true}'::jsonb where id = e.id and not (flags ? 'warn') returning id into v_id;
    if v_id is not null and v_open then perform game.sys_chat('coco epan', 'Satu jam lagi buku besar kututup. Setelah itu, hanya langit yang tahu.'); end if;
  end if;
  v_id := null;
  if n >= game.pd_t(s, 'close') and n < game.pd_t(s, 'end') then
    update game.pd_events set flags = flags || '{"close":true}'::jsonb where id = e.id and not (flags ? 'close') returning id into v_id;
    if v_id is not null and v_open then perform game.sys_chat('coco epan', 'Buku besar ditutup. Berdaganglah sebaik mungkin, Kapten.'); end if;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Status pribadi (key 'pacu' di getGameState)
-- ---------------------------------------------------------------------
create or replace function game.pacu_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare s date; e game.pd_events; m game.pd_scores; st text; v_gol int; t numeric[]; v_rank int; v_n int; v_last game.pd_events; lm game.pd_scores;
  rc game.pd_record;
begin
  if not game.fitur_on(p_pid, 'PacuOpen') then return null; end if;
  begin perform game.pd_tick(); exception when others then raise warning '[pacu] tick: %', sqlerrm; end;
  s := game.pd_cur_sat();
  select * into e from game.pd_events where sat = s;
  st := game.pd_status(s);
  select * into m from game.pd_scores where event_id = e.id and player_id = p_pid;
  v_gol := coalesce(m.gol, game.golongan(p_pid));
  t := game.pd_targets(p_pid, v_gol);
  if m.player_id is not null then
    select 1 + count(*) into v_rank from game.pd_scores y where y.event_id = e.id and y.gol = v_gol and not y.banned and (y.score > m.score or (y.score = m.score and y.reached_at < m.reached_at));
  end if;
  select count(*) into v_n from game.pd_scores y where y.event_id = e.id and y.gol = v_gol and not y.banned;
  select * into v_last from game.pd_events where sat < s and status = 'announced' order by sat desc limit 1;
  if v_last.id is not null then select * into lm from game.pd_scores where event_id = v_last.id and player_id = p_pid; end if;
  select * into rc from game.pd_record where player_id = p_pid;
  return jsonb_build_object(
    'event', jsonb_build_object('id', e.id, 'sat', e.sat, 'status', st,
      'theme', case when st <> 'planned' then e.theme end, 'themeName', case when st <> 'planned' then game.pd_theme_name(e.theme) end,
      'themeMul', game.cfg_num('PacuThemeMul', 1.5),
      'boardClosed', game.pd_wib() >= game.pd_t(s, 'close'),
      'ms', jsonb_build_object('reveal', game.pd_ms(game.pd_t(s, 'reveal')), 'start', game.pd_ms(game.pd_t(s, 'start')),
        'close', game.pd_ms(game.pd_t(s, 'close')), 'end', game.pd_ms(game.pd_t(s, 'end')), 'announce', game.pd_ms(game.pd_t(s, 'announce')))),
    'me', jsonb_build_object('gol', v_gol, 'golName', game.golongan_nama(v_gol), 'score', coalesce(m.score, 0), 'profit', coalesce(m.profit, 0),
      'sells', coalesce(m.sells, 0), 'sellsWin', coalesce(m.sells_win, 0), 'cities', coalesce(m.cities, '[]'::jsonb),
      'rank', case when game.pd_wib() < game.pd_t(s, 'close') then v_rank end, 'peserta', v_n,
      'targets', to_jsonb(t), 'tier', game.pd_tier(coalesce(m.score, 0), t), 'joined', m.player_id is not null, 'banned', coalesce(m.banned, false)),
    'last', case when v_last.id is null then null else jsonb_build_object('id', v_last.id, 'sat', v_last.sat, 'results', v_last.results,
      'me', case when lm.player_id is null then null else jsonb_build_object('score', lm.score, 'gol', lm.gol) end) end,
    'gold', lower(coalesce(game.cfg('PacuGoldOn'), '0')) in ('1', 'true', 'on', 'ya'),
    'stats', jsonb_build_object('ikut', coalesce(rc.n_ikut, 0), 'perunggu', coalesce(rc.n_perunggu, 0), 'emas', coalesce(rc.n_emas, 0),
      'juara1', coalesce(rc.juara1, 0), 'mata', coalesce(rc.mata, 0), 'jelajah', coalesce(rc.jelajah, 0), 'lompat', coalesce(rc.lompat, 0),
      'rekor', game.pd_avg(p_pid)));
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT: a = [aksi, ...]   papan | hasil [event_id] | prasasti
-- ---------------------------------------------------------------------
create or replace function game.pd_board(p_pid uuid) returns jsonb
language plpgsql as $$
declare s date := game.pd_cur_sat(); e game.pd_events; v_closed boolean; v_g int; v_out jsonb := '{}'::jsonb; v_rows jsonb; v_mine jsonb; cats jsonb;
begin
  select * into e from game.pd_events where sat = s;
  v_closed := game.pd_wib() >= game.pd_t(s, 'close');
  for v_g in 1..3 loop
    with ranked as (
      select x.player_id, coalesce(nullif(p.character_name, ''), 'Kapten') name, p.appearance ap, x.score, x.sells_win, jsonb_array_length(x.cities) ncity,
             rank() over (order by x.score desc, x.reached_at) rk
        from game.pd_scores x join game.players p on p.player_id = x.player_id
       where x.event_id = e.id and x.gol = v_g and not x.banned)
    select coalesce(jsonb_agg(jsonb_build_object('name', name, 'ap', ap, 'score', score, 'rank', rk, 'me', player_id = p_pid) order by rk), '[]'::jsonb)
      into v_rows from ranked where not v_closed and rk <= 5;
    with ranked as (
      select x.player_id, coalesce(nullif(p.character_name, ''), 'Kapten') name, p.appearance ap, x.score,
             rank() over (order by x.score desc, x.reached_at) rk
        from game.pd_scores x join game.players p on p.player_id = x.player_id
       where x.event_id = e.id and x.gol = v_g and not x.banned)
    select jsonb_build_object('name', name, 'ap', ap, 'score', score, 'rank', case when v_closed then null else rk end, 'me', true) into v_mine
      from ranked where player_id = p_pid;
    v_out := v_out || jsonb_build_object(v_g::text, jsonb_build_object('rows', v_rows, 'me', v_mine,
      'peserta', (select count(*) from game.pd_scores where event_id = e.id and gol = v_g and not banned)));
  end loop;
  if not v_closed then
    cats := jsonb_build_object(
      'mata', (select coalesce(jsonb_agg(z), '[]'::jsonb) from (select coalesce(nullif(p.character_name, ''), 'Kapten') name, round(x.profit / x.cost, 3) v
          from game.pd_scores x join game.players p using (player_id) where x.event_id = e.id and not x.banned and x.cost > 0 and x.sells_win >= game.cfg_num('PacuMataMinJual', 15)
          order by x.profit / x.cost desc limit 3) z),
      'jelajah', (select coalesce(jsonb_agg(z), '[]'::jsonb) from (select coalesce(nullif(p.character_name, ''), 'Kapten') name, jsonb_array_length(x.cities) v
          from game.pd_scores x join game.players p using (player_id) where x.event_id = e.id and not x.banned and x.score > 0
          order by jsonb_array_length(x.cities) desc, x.score desc limit 3) z),
      'lompat', (select coalesce(jsonb_agg(z), '[]'::jsonb) from (select coalesce(nullif(p.character_name, ''), 'Kapten') name, round(x.score / game.pd_avg(x.player_id), 2) v
          from game.pd_scores x join game.players p using (player_id) where x.event_id = e.id and not x.banned and x.score > 0 and coalesce(game.pd_avg(x.player_id), 0) > 0
          order by x.score / game.pd_avg(x.player_id) desc limit 3) z));
  end if;
  return jsonb_build_object('gol', v_out, 'cats', cats, 'closed', v_closed);
end $$;

-- buang player_id dari data publik (aman untuk null / bukan objek)
create or replace function game.pd_nopid(p jsonb) returns jsonb
language sql immutable as $$ select case when jsonb_typeof(p) = 'object' then p - 'pid' end $$;

create or replace function public.api_pacu(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'papan'); v_id text := game.arg(a, 1); e game.pd_events;
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'PacuOpen') then raise exception 'Pacu Dagang belum dibuka.'; end if;
  if v_act = 'papan' then
    return jsonb_build_object('pacu', game.pacu_state(v_pid), 'board', game.pd_board(v_pid));
  elsif v_act = 'hasil' then
    if coalesce(v_id, '') = '' then select * into e from game.pd_events where status = 'announced' order by sat desc limit 1;
    else select * into e from game.pd_events where id = v_id and status = 'announced'; end if;
    return jsonb_build_object('hasil', e.results, 'me', (select jsonb_build_object('score', score, 'gol', gol) from game.pd_scores where event_id = e.id and player_id = v_pid));
  elsif v_act = 'prasasti' then
    return jsonb_build_object('prasasti', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'sat', sat, 'themeName', game.pd_theme_name(theme),
        'juara', (select coalesce(jsonb_object_agg(k, game.pd_nopid(v -> 'list' -> 0)), '{}'::jsonb) from jsonb_each(results -> 'gol') g(k, v) where jsonb_array_length(v -> 'list') > 0),
        'mata', game.pd_nopid(results -> 'mata'), 'jelajah', game.pd_nopid(results -> 'jelajah'), 'lompat', game.pd_nopid(results -> 'lompat'), 'peserta', results -> 'peserta') order by sat desc)
      from (select * from game.pd_events where status = 'announced' order by sat desc limit 52) z), '[]'::jsonb));
  end if;
  raise exception 'Aksi tidak dikenal: %', v_act;
end $$;
select game.expose('api_pacu');

-- ---------------------------------------------------------------------
-- Layar Emas sepekan (juara 1 event terakhir) ikut rupa kapal
-- ---------------------------------------------------------------------
create or replace function game.kd_visual(p_pid uuid) returns jsonb
language sql stable as $$
  select nullif(
    coalesce((select l.equipped from game.kd_loadout l where l.player_id = p_pid), '{}'::jsonb)
    || case when exists (select 1 from (select results from game.pd_events where status = 'announced' order by sat desc limit 1) z
                          where z.results -> 'winners' ? p_pid::text) then '{"emas": true}'::jsonb else '{}'::jsonb end,
    '{}'::jsonb)
$$;

-- ---------------------------------------------------------------------
-- Jeda juri: audit & coret
-- ---------------------------------------------------------------------
create or replace view game.pd_audit as
with w as (
  select e.id event_id, e.status, ((e.sat::timestamp - interval '7 hours') at time zone 'UTC') t0, ((e.sat::timestamp + interval '2 days' - interval '7 hours') at time zone 'UTC') t1
    from game.pd_events e)
select s.event_id, p.username, p.character_name, s.gol, s.score, s.profit, s.cost,
  case when s.cost > 0 then round(s.profit / s.cost, 2) end as margin, s.sells, s.sells_win, jsonb_array_length(s.cities) pulau,
  rank() over (partition by s.event_id, s.gol order by s.score desc) peringkat,
  extract(day from now() - p.created_at)::int umur_akun_hari,
  coalesce((select sum((regexp_match(l.message, 'mengirimimu (\d+) gold'))[1]::bigint) from game.player_log l
             where l.player_id = s.player_id and l.ts between w.t0 and w.t1 and l.message like '%mengirimimu % gold.'), 0) gold_diterima,
  (select count(*) from game.player_log l where l.player_id = s.player_id and l.ts between w.t0 and w.t1 and l.message like 'Membeli % di Bursa%') beli_bursa,
  array_remove(array[
    case when s.cost > 0 and s.profit / s.cost > 3 and s.sells_win >= 5 then 'margin > 300%' end,
    case when extract(day from now() - p.created_at) < 7 then 'akun < 7 hari' end,
    case when coalesce((select sum((regexp_match(l.message, 'mengirimimu (\d+) gold'))[1]::bigint) from game.player_log l
             where l.player_id = s.player_id and l.ts between w.t0 and w.t1 and l.message like '%mengirimimu % gold.'), 0) > 100000 then 'menerima kiriman gold' end,
    case when (select count(*) from game.player_log l where l.player_id = s.player_id and l.ts between w.t0 and w.t1 and l.message like 'Membeli % di Bursa%') >= 3 then 'sering beli di Bursa' end
  ], null) tanda,
  s.banned, s.ban_note
from game.pd_scores s join game.players p on p.player_id = s.player_id join w on w.event_id = s.event_id;
revoke all on game.pd_audit from public, anon, authenticated;

create or replace function game.admin_pacu_coret(p_event text, p_user text, p_note text default 'dicoret juri') returns text
language plpgsql as $$
declare v_pid uuid; e game.pd_events;
begin
  select * into e from game.pd_events where id = p_event;
  if not found then raise exception 'Event % tidak ada.', p_event; end if;
  if e.status = 'announced' then raise exception 'Event % sudah diumumkan; coret harus sebelum Senin 08:00.', p_event; end if;
  select player_id into v_pid from game.players where lower(username) = lower(trim(p_user)) or lower(character_name) = lower(trim(p_user))
   order by (lower(username) = lower(trim(p_user))) desc limit 1;
  if v_pid is null then raise exception 'Kapten "%" tidak ditemukan.', p_user; end if;
  update game.pd_scores set banned = true, ban_note = p_note where event_id = p_event and player_id = v_pid;
  if not found then raise exception 'Kapten itu tidak ikut %.', p_event; end if;
  return p_user || ' dicoret dari ' || p_event;
end $$;
revoke all on function game.admin_pacu_coret(text, text, text) from public;
