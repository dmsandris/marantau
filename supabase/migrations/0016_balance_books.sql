-- =====================================================================
-- Marantau (Supabase) - 0016 KESEIMBANGAN DAGANG + PERPUSTAKAAN (Tide v13)
-- 1) Permintaan pasar: setiap unit yang DIBELI menaikkan harga beli barang itu di kota itu
--    (dibagi semua pemain, pulih perlahan). Borong besar-besaran jadi makin mahal.
-- 2) Stok menumpuk saat menjual dibuat lebih terasa (skala 80, pulih 3 jam, lantai 30%).
-- 3) Harga semua buku naik 50% + 20 buku baru di semua kota; buku Tier IV (Legenda)
--    hanya dijual di Paradiso.
-- Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Konfigurasi (hanya ditulis sekali; setelah itu bebas diubah lewat tabel game.config)
-- ---------------------------------------------------------------------
do $$
begin
  if coalesce(game.cfg_num('BalanceVersion', 0), 0) < 16 then
    perform game.cfg_set('OverstockScale', '80');
    perform game.cfg_set('OverstockHalfLifeMinutes', '180');
    perform game.cfg_set('OverstockFloorPercent', '30');
    perform game.cfg_set('DemandScale', '100');
    perform game.cfg_set('DemandHalfLifeMinutes', '150');
    perform game.cfg_set('DemandCapPercent', '100');
    perform game.cfg_set('BalanceVersion', '16');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Permintaan (sisi beli)
-- ---------------------------------------------------------------------
create table if not exists game.market_demand (
  city_id      text not null,
  commodity_id text not null,
  demand       numeric not null default 0,
  at           timestamptz not null default now(),
  primary key (city_id, commodity_id)
);
alter table game.market_demand enable row level security;

create or replace function game.eco_demand_cfg(out scale double precision, out half_life_ms double precision, out cap double precision)
language plpgsql stable as $$
begin
  scale := greatest(10, game.cfg_num('DemandScale', 100))::double precision;
  half_life_ms := (greatest(5, game.cfg_num('DemandHalfLifeMinutes', 150)) * 60000)::double precision;
  cap := (least(500, greatest(0, game.cfg_num('DemandCapPercent', 100))) / 100)::double precision;
end $$;

create or replace function game.eco_demand_now(p_city text, p_commodity text) returns double precision
language plpgsql stable as $$
declare r game.market_demand; cfg record; d double precision;
begin
  select * into r from game.market_demand where city_id = p_city and commodity_id = p_commodity;
  if not found then return 0; end if;
  select * into cfg from game.eco_demand_cfg();
  d := r.demand::double precision * power(0.5::double precision, greatest(0, extract(epoch from (now() - r.at)) * 1000)::double precision / cfg.half_life_ms);
  return case when d < 0.05 then 0 else d end;
end $$;

create or replace function game.eco_set_demand(p_city text, p_commodity text, p_d double precision) returns void
language plpgsql as $$
begin
  if p_d < 0.05 then
    delete from game.market_demand where city_id = p_city and commodity_id = p_commodity;
  else
    insert into game.market_demand(city_id, commodity_id, demand, at)
    values (p_city, p_commodity, round(p_d::numeric, 2), now())
    on conflict (city_id, commodity_id) do update set demand = excluded.demand, at = excluded.at;
  end if;
end $$;

-- Harga beli satu unit saat permintaan = d
create or replace function game.eco_buy_unit(p_normal bigint, p_d double precision, p_scale double precision, p_cap double precision) returns bigint
language sql immutable as $$
  select game.eco_round(p_normal::double precision * least(1 + p_cap, 1 + greatest(0, p_d) / p_scale))
$$;

create or replace function game.eco_buy_cost(p_normal bigint, p_d double precision, p_qty bigint, p_scale double precision, p_cap double precision) returns bigint
language sql immutable as $$
  select coalesce(sum(game.eco_buy_unit(p_normal, p_d + i, p_scale, p_cap)), 0)::bigint
  from generate_series(0, p_qty - 1) as i
$$;

-- ---------------------------------------------------------------------
-- Pasar (menggantikan versi 0002)
-- ---------------------------------------------------------------------
create or replace function public.api_getMarket(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players; pid uuid; cfg record; dcfg record; r record; pp record;
  g double precision; d double precision; sp bigint; bp bigint; items jsonb := '[]'::jsonb; space int;
begin
  v_me := game.me(false); pid := v_me.player_id;
  select * into cfg from game.eco_glut_cfg();
  select * into dcfg from game.eco_demand_cfg();
  for r in select m.commodity_id, m.base_price, c.name, c.flavor
             from game.market m left join game.commodities c on c.id = m.commodity_id
            where m.city_id = v_city order by c.sort, m.commodity_id loop
    select * into pp from game.eco_player_prices(pid, v_city, r.commodity_id);
    g := game.eco_glut_now(v_city, r.commodity_id);
    d := game.eco_demand_now(v_city, r.commodity_id);
    sp := game.eco_sell_unit(pp.sell_normal, g, cfg.scale, cfg.floor_pct);
    bp := game.eco_buy_unit(pp.buy_price, d, dcfg.scale, dcfg.cap);
    items := items || jsonb_build_array(jsonb_build_object(
      'commodityId', r.commodity_id,
      'name', coalesce(r.name, r.commodity_id),
      'flavor', coalesce(r.flavor, ''),
      'currentPrice', pp.current_price,
      'buyPrice', bp,
      'buyNormal', pp.buy_price,
      'demand', trim_scale(game.eco_round(d * 100)::numeric / 100),
      'demandScale', dcfg.scale,
      'demandCap', dcfg.cap,
      'scarcityPct', case when pp.buy_price > 0 then greatest(0, game.eco_round((bp::double precision / pp.buy_price::double precision - 1) * 100)) else 0 end,
      'sellPrice', sp,
      'sellNormal', pp.sell_normal,
      'glut', trim_scale(game.eco_round(g * 100)::numeric / 100),
      'glutScale', cfg.scale,
      'glutFloor', cfg.floor_pct,
      'overstockPct', case when pp.sell_normal > 0
          then greatest(0, game.eco_round((1 - sp::double precision / pp.sell_normal::double precision) * 100)) else 0 end,
      'ownedQty', coalesce((select i.qty from game.inventory i where i.player_id = pid and i.item_id = r.commodity_id and i.qty > 0), 0),
      'basePrice', r.base_price,
      'priceRatio', case when r.base_price > 0
          then game.eco_round(pp.current_price::double precision / r.base_price::double precision * 100) else 100 end));
  end loop;
  space := greatest(0, coalesce(game.effective_cargo(pid), 0) - game.cargo_total(pid));
  return jsonb_build_object('items', items, 'cargoSpaceRemaining', space);
end $$;
select game.expose('api_getmarket');

create or replace function public.api_buy(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; pp record; dcfg record; total bigint; cap int; cur int; g0 double precision; d0 double precision;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah beli tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  perform game.eco_require_trade_here(pid, v_city);
  -- kunci pasangan kota+komoditas (stok & permintaan dibagi semua pemain)
  perform 1 from game.market where city_id = v_city and commodity_id = v_comm for update;
  if not found then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;

  select * into pp from game.eco_player_prices(pid, v_city, v_comm);
  select * into dcfg from game.eco_demand_cfg();
  d0 := game.eco_demand_now(v_city, v_comm);
  total := game.eco_buy_cost(pp.buy_price, d0, v_qty, dcfg.scale, dcfg.cap);
  if v_me.gold < total then
    raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', total, v_me.gold;
  end if;
  cap := coalesce(game.effective_cargo(pid), 0);
  cur := game.cargo_total(pid);
  if cur + v_qty > cap then
    raise exception 'Kapasitas cargo tidak cukup. Sisa ruang: %.', cap - cur;
  end if;

  update game.players set gold = gold - total where player_id = pid;
  perform game.adjust_inventory(pid, v_comm, v_qty::int);
  g0 := game.eco_glut_now(v_city, v_comm);
  if g0 > 0 then perform game.eco_set_glut(v_city, v_comm, greatest(0, g0 - v_qty)); end if;
  perform game.eco_set_demand(v_city, v_comm, d0 + v_qty);

  perform game.log(pid, 'Bought ' || v_qty || ' unit' || case when v_qty > 1 then 's' else '' end || ' of ' ||
    game.commodity_name(v_comm) || ' for ' || total || ' gold.');
  return jsonb_build_object('totalCost', total, 'unitPrice', game.eco_round(total::double precision / v_qty),
    'newGold', v_me.gold - total,
    'nextBuyPrice', game.eco_buy_unit(pp.buy_price, d0 + v_qty, dcfg.scale, dcfg.cap));
end $$;
select game.expose('api_buy');

create or replace function public.api_sell(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; pp record; cfg record; g double precision; d double precision; revenue bigint; nxt bigint;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah jual tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  perform game.eco_require_trade_here(pid, v_city);
  perform 1 from game.market where city_id = v_city and commodity_id = v_comm for update;
  if not found then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;

  select * into pp from game.eco_player_prices(pid, v_city, v_comm);
  select * into cfg from game.eco_glut_cfg();
  g := game.eco_glut_now(v_city, v_comm);
  revenue := game.eco_sell_revenue(pp.sell_normal, g, v_qty, cfg.scale, cfg.floor_pct);

  if not exists (select 1 from game.inventory where player_id = pid and item_id = v_comm) then
    raise exception 'Kamu tidak punya cargo ini untuk dijual.';
  end if;
  perform game.adjust_inventory(pid, v_comm, (-v_qty)::int);
  perform game.eco_set_glut(v_city, v_comm, g + v_qty);
  d := game.eco_demand_now(v_city, v_comm);
  if d > 0 then perform game.eco_set_demand(v_city, v_comm, greatest(0, d - v_qty)); end if;

  update game.players set gold = gold + revenue where player_id = pid;
  perform game.log(pid, 'Sold ' || v_qty || ' unit' || case when v_qty > 1 then 's' else '' end || ' of ' ||
    game.commodity_name(v_comm) || ' for ' || revenue || ' gold.');

  nxt := game.eco_sell_unit(pp.sell_normal, g + v_qty, cfg.scale, cfg.floor_pct);
  return jsonb_build_object('totalRevenue', revenue,
    'unitPrice', game.eco_round(revenue::double precision / v_qty),
    'newGold', v_me.gold + revenue,
    'nextSellPrice', nxt,
    'overstockPct', case when pp.sell_normal > 0
      then greatest(0, game.eco_round((1 - nxt::double precision / pp.sell_normal::double precision) * 100)) else 0 end);
end $$;
select game.expose('api_sell');

-- ---------------------------------------------------------------------
-- Perpustakaan: harga +50% (nilai tetap, bukan dikali tiap deploy) + 20 buku baru
-- ---------------------------------------------------------------------
update game.book_catalog c set price = v.price
from (values
  ('bk_trading_1', 450), ('bk_negotiation_1', 450), ('bk_navigation_1', 450), ('bk_sailing_1', 450),
  ('bk_combat_1', 525), ('bk_luck_1', 600), ('bk_knowledge_1', 375),
  ('bk_trading_2', 1350), ('bk_navigation_2', 1350), ('bk_combat_2', 1425), ('bk_negotiation_2', 1350),
  ('bk_black_market', 2700), ('bk_deep_hold', 2400), ('bk_sea_lore', 3000),
  ('bk_treasure_decoder_1', 1650), ('bk_treasure_decoder_2', 3600)
) as v(book_id, price)
where c.book_id = v.book_id;

insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  -- Sunda Empire
  ('bk_su_etiquette',  'Tata Krama Balai Adat',        'I',   '{"Negotiation":6}',                    '', 480,   'sunda_empire', 20),
  ('bk_su_ledger',     'Buku Besar Saudagar Sunda',    'II',  '{"Trading":8,"Knowledge":4}',          '', 1500,  'sunda_empire', 21),
  ('bk_su_currency',   'Kurs Tujuh Pelabuhan',         'III', '{"Trading":14,"Negotiation":6}',       '', 3600,  'sunda_empire', 22),
  -- Joungjava
  ('bk_jj_harvest',    'Almanak Musim Panen',          'I',   '{"Knowledge":6,"Luck":2}',             '', 450,   'joungjava', 23),
  ('bk_jj_monsoon',    'Membaca Angin Muson',          'II',  '{"Sailing":8,"Navigation":4}',         '', 1500,  'joungjava', 24),
  ('bk_jj_stars',      'Peta Bintang Pelaut Jawa',     'III', '{"Navigation":14,"Sailing":5}',        '', 3600,  'joungjava', 25),
  -- Bjorneo
  ('bk_bj_ulin',       'Rahasia Kayu Ulin',            'I',   '{"Sailing":6}',                        '', 480,   'bjorneo', 26),
  ('bk_bj_hunter',     'Jurnal Pemburu Rimba',         'II',  '{"Combat":8,"Luck":4}',                '', 1500,  'bjorneo', 27),
  ('bk_bj_cannon',     'Seni Meriam Lela',             'III', '{"Combat":14,"Knowledge":4}',          '', 3750,  'bjorneo', 28),
  -- Skitraw
  ('bk_sk_rantau',     'Petuah Orang Rantau',          'I',   '{"Negotiation":4,"Luck":3}',           '', 480,   'skitraw', 29),
  ('bk_sk_lapau',      'Kitab Lapau & Pasar',          'II',  '{"Trading":6,"Negotiation":6}',        '', 1500,  'skitraw', 30),
  ('bk_sk_saudagar',   'Silsilah Saudagar Minang',     'III', '{"Negotiation":14,"Trading":6}',       '', 3750,  'skitraw', 31),
  -- TooGood
  ('bk_tg_dice',       'Dadu Berbobot',                'II',  '{"Luck":10}',                          '', 1650,  'toogood', 32),
  ('bk_tg_alley',      'Duel di Gang Gelap',           'II',  '{"Combat":10,"Negotiation":2}',        '', 1650,  'toogood', 33),
  -- IKN
  ('bk_ikn_archive',   'Arsip Restorasi Nusantara',    'II',  '{"Knowledge":10,"Navigation":3}',      '', 1500,  'ikn', 34),
  -- Paradiso: Tier IV (Legenda) - hanya di sini
  ('bk_pd_tides',      'Kitab Pasang Surut Abadi',     'IV',  '{"Navigation":20,"Sailing":15}',       '', 12000, 'paradiso', 40),
  ('bk_pd_gold',       'Hikayat Emas Tujuh Samudra',   'IV',  '{"Trading":20,"Negotiation":15}',      '', 13500, 'paradiso', 41),
  ('bk_pd_war',        'Strategi Laksamana Agung',     'IV',  '{"Combat":22,"Luck":8}',               '', 12000, 'paradiso', 42),
  ('bk_pd_fortune',    'Rahasia Dewi Fortuna',         'IV',  '{"Luck":20,"Knowledge":10}',           '', 10500, 'paradiso', 43),
  ('bk_pd_sage',       'Kitab Sang Bijak Paradiso',    'IV',  '{"Knowledge":25,"Trading":5,"Navigation":5}', '', 15000, 'paradiso', 44)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  price = excluded.price, source = excluded.source, sort = excluded.sort;
