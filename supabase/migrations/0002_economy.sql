-- =====================================================================
-- Marantau (Supabase) - 0002 ECONOMY (Modul A)
-- ---------------------------------------------------------------------
-- Port dari: CharacterService.gs, ArchetypeData.gs, MarketService.gs
-- (v8 overstock + quoteBuy), CargoService.gs, WarehouseService.gs,
-- BankService.gs, BookService.gs (+ seed BookCatalog dari SetupSheets.gs),
-- AppearanceStore_ / MetaStore_ + endpoint api_* terkait di Code.gs.
--
-- Kontrak 0001b yang ditimpa di sini (signature TIDAK berubah):
--   game.cargo_total, game.reputation_for, game.stats_json,
--   game.quote_buy, game.bank_state   (game.adjust_inventory dibiarkan)
--
-- Tambahan untuk modul lain:
--   game.book_catalog / game.player_books   (tabel buku)
--   game.book_effects(pid) text[], game.book_has_effect(pid, eff) boolean
--   game.archetypes, game.archetype_json(id)
--   Hook hapus karakter: fungsi game.<apa saja>_on_character_delete(uuid)
--   dipanggil otomatis oleh api_deleteCharacter (lihat di bawah).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper kecil peniru semantik JavaScript
-- ---------------------------------------------------------------------
-- Math.round (setengah ke atas)
create or replace function game.eco_round(x double precision) returns bigint
language sql immutable as $$ select floor(x + 0.5)::bigint $$;

-- String.prototype.trim()
create or replace function game.eco_trim(s text) returns text
language sql immutable as $$ select regexp_replace(coalesce(s, ''), '^[\s ﻿]+|[\s ﻿]+$', '', 'g') $$;

-- Number(v) || 0   (NaN/tidak valid -> 0)
create or replace function game.eco_js_num(v jsonb) returns numeric
language plpgsql immutable as $$
declare s text;
begin
  if v is null then return 0; end if;
  case jsonb_typeof(v)
    when 'number' then return (v #>> '{}')::numeric;
    when 'boolean' then return case when v = 'true'::jsonb then 1 else 0 end;
    when 'string' then
      s := game.eco_trim(v #>> '{}');
      if s = '' then return 0; end if;
      begin
        return s::numeric;
      exception when others then return 0;
      end;
    else return 0;
  end case;
end $$;

-- Truthiness JavaScript untuk nilai JSON
create or replace function game.eco_js_truthy(v jsonb) returns boolean
language sql immutable as $$
  select case
    when v is null then false
    when jsonb_typeof(v) = 'null' then false
    when jsonb_typeof(v) = 'boolean' then v = 'true'::jsonb
    when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric <> 0
    when jsonb_typeof(v) = 'string' then (v #>> '{}') <> ''
    else true end
$$;

-- String(v)
create or replace function game.eco_js_string(v jsonb) returns text
language sql immutable as $$
  select case
    when v is null then 'undefined'
    when jsonb_typeof(v) = 'string' then v #>> '{}'
    when jsonb_typeof(v) = 'object' then '[object Object]'
    else v::text end
$$;

-- Angka -> teks seperti JS (tanpa nol di belakang koma)
create or replace function game.eco_num_text(n numeric) returns text
language sql immutable as $$ select trim_scale(n)::text $$;

-- ---------------------------------------------------------------------
-- ARCHETYPES (ArchetypeData.gs)
-- ---------------------------------------------------------------------
create table if not exists game.archetypes (
  id                        text primary key,
  name                      text not null,
  tagline                   text not null default '',
  bio                       text not null default '',
  bonuses                   jsonb not null default '{}'::jsonb,
  perk_name                 text not null default '',
  perk_desc                 text not null default '',
  starting_reputation_bonus int,
  sort                      int not null default 0
);
alter table game.archetypes enable row level security;

insert into game.archetypes(id, name, tagline, bio, bonuses, perk_name, perk_desc, starting_reputation_bonus, sort) values
  ('merchant', 'The Merchant', 'Naluri dagang sejak lahir.',
   'Lahir di keluarga pedagang kain di Sunda Empire, kamu belajar menawar sebelum belajar berenang. Buku besar dan neraca timbangan lebih akrab di tanganmu daripada pedang.',
   '{"Trading":15}', 'Market Sense', 'Setiap masuk kota baru, melihat 1 barang dengan perubahan harga terbesar.', null, 1),
  ('navigator', 'The Navigator', 'Mengenal laut lebih baik dari daratan.',
   'Dari kecil kamu dibesarkan di atas geladak, membaca bintang dan arus lebih fasih daripada membaca peta darat. Kapten mana pun akan berebut punya juru mudi sepertimu.',
   '{"Navigation":15}', 'Sea Reader', '-10% peluang terkena sea event berbahaya.', null, 2),
  ('pirate', 'The Pirate', 'Dulunya bukan orang baik-baik.',
   'Bendera hitam pernah jadi rumahmu sebelum kamu memutuskan berhenti - atau begitu ceritanya. Reputasi lama masih mengikuti, dan tidak semua orang percaya kamu sudah berubah.',
   '{"Combat":15}', 'Intimidation', 'Pirate encounter membuka opsi negosiasi khusus.', null, 3),
  ('explorer', 'The Explorer', 'Mengejar peta, bukan gold.',
   'Gold cuma bahan bakar untuk mendanai pelayaran berikutnya. Yang kamu kejar adalah pulau yang belum ada di peta manapun, dan legenda yang belum ada yang membuktikan benar.',
   '{"Luck":10,"Navigation":10}', 'Treasure Hunter', 'Akurasi treasure clue lebih tinggi.', null, 4),
  ('gambler', 'The Gambler', 'Semua atau tidak sama sekali.',
   'Kapal ini sendiri dimenangkan lewat taruhan kartu di pelabuhan yang lebih baik dilupakan. Hidup aman itu membosankan - kamu lebih suka taruhan besar dengan risiko yang sepadan.',
   '{"Luck":10}', 'High Roller', 'Reward event langka +30%, tapi event negatif juga +20%.', null, 5),
  ('smuggler', 'The Smuggler', 'Kenal orang-orang yang tepat.',
   'Ada pintu belakang di setiap pelabuhan yang kamu tahu caranya masuk, dan orang-orang di sana lebih percaya kamu daripada percaya pejabat kota. Untung besar datang dengan risiko yang sepadan.',
   '{"Negotiation":10}', 'Underworld Connections', 'Black Market lebih murah, tapi reputasi dari misi walikota -20%.', null, 6),
  ('diplomat', 'The Diplomat', 'Kata-kata adalah senjata terbaik.',
   'Dibesarkan di lingkaran istana sebelum memilih laut lepas, kamu tahu persis bagaimana bicara dengan gubernur dan bangsawan. Pintu yang tertutup untuk orang lain, terbuka untukmu.',
   '{"Negotiation":10}', 'Silver Tongue', 'Peluang negosiasi saat combat lebih tinggi.', 5, 7),
  ('adventurer', 'The Adventurer', 'Generalist yang siap segalanya.',
   'Kamu belum tahu jadi apa nanti - pedagang, pemburu harta, atau legenda laut - dan itu justru yang membuatmu berangkat. Serba bisa, tidak istimewa di satu hal, tapi tidak lemah di manapun.',
   '{"Sailing":10,"Combat":5}', 'Bold Sailor', '-10% waktu perjalanan di rute berisiko (aktif setelah Ship System, Fase 3).', null, 8)
on conflict (id) do update set
  name = excluded.name, tagline = excluded.tagline, bio = excluded.bio, bonuses = excluded.bonuses,
  perk_name = excluded.perk_name, perk_desc = excluded.perk_desc,
  starting_reputation_bonus = excluded.starting_reputation_bonus, sort = excluded.sort;

-- Objek archetype lengkap (bentuk ARCHETYPES[i] di .gs) atau null
create or replace function game.archetype_json(p_id text) returns jsonb
language sql stable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', a.id, 'name', a.name, 'tagline', a.tagline, 'bio', a.bio, 'bonuses', a.bonuses,
    'perkName', a.perk_name, 'perkDesc', a.perk_desc,
    'startingReputationBonus', a.starting_reputation_bonus))
  from game.archetypes a where a.id = p_id
$$;

create or replace function public.api_getArchetypes(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', x.id, 'name', x.name, 'tagline', x.tagline, 'bio', x.bio, 'bonuses', x.bonuses,
      'perkName', x.perk_name, 'perkDesc', x.perk_desc) order by x.sort, x.id)
    from game.archetypes x), '[]'::jsonb);
end $$;
select game.expose('api_getarchetypes', true);

-- ---------------------------------------------------------------------
-- BOOKS (BookService.gs + seedBookCatalog / migrateFase5Exploration)
-- ---------------------------------------------------------------------
create table if not exists game.book_catalog (
  book_id        text primary key,
  name           text not null,
  tier           text not null default 'I',
  stat_effects   text not null default '',     -- JSON string, sama seperti kolom sheet
  special_effect text not null default '',
  price          numeric not null default 0,
  source         text not null default 'any',  -- CityId atau 'any'
  sort           int not null default 0
);
alter table game.book_catalog enable row level security;

create table if not exists game.player_books (
  player_id     uuid not null references game.players(player_id) on delete cascade,
  book_id       text not null,
  date_acquired int,
  primary key (player_id, book_id)
);
alter table game.player_books enable row level security;

insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_trading_1', 'Basic Bookkeeping', 'I', '{"Trading":5}', '', 300, 'sunda_empire', 1),
  ('bk_negotiation_1', 'Street Haggling', 'I', '{"Negotiation":5}', '', 300, 'sunda_empire', 2),
  ('bk_navigation_1', 'Coastal Charts', 'I', '{"Navigation":5}', '', 300, 'joungjava', 3),
  ('bk_sailing_1', 'Knot & Rigging', 'I', '{"Sailing":5}', '', 300, 'joungjava', 4),
  ('bk_combat_1', 'Brawler''s Primer', 'I', '{"Combat":5}', '', 350, 'bjorneo', 5),
  ('bk_luck_1', 'Sailor''s Superstitions', 'I', '{"Luck":5}', '', 400, 'any', 6),
  ('bk_knowledge_1', 'Common Almanac', 'I', '{"Knowledge":8}', '', 250, 'any', 7),
  ('bk_trading_2', 'The Merchant''s Codex', 'II', '{"Trading":10,"Negotiation":3}', '', 900, 'sunda_empire', 8),
  ('bk_navigation_2', 'Deep Sea Charts', 'II', '{"Navigation":10,"Sailing":3}', '', 900, 'joungjava', 9),
  ('bk_combat_2', 'Blade & Broadside', 'II', '{"Combat":10,"Luck":2}', '', 950, 'bjorneo', 10),
  ('bk_negotiation_2', 'Diplomat''s Handbook', 'II', '{"Negotiation":10,"Knowledge":3}', '', 900, 'sunda_empire', 11),
  ('bk_black_market', 'Smuggler''s Codebook', 'III', '{"Negotiation":5}', 'black_market_discount', 1800, 'bjorneo', 12),
  ('bk_deep_hold', 'Shipwright''s Secrets', 'III', '{"Sailing":5}', 'cargo_bonus_10', 1600, 'joungjava', 13),
  ('bk_sea_lore', 'Chronicle of the Drowned Kings', 'III', '{"Knowledge":15,"Luck":5}', '', 2000, 'any', 14),
  ('bk_treasure_decoder_1', 'Kompendium Pemburu Harta', 'II', '{"Knowledge":5}', 'treasure_decoder_1', 1100, 'any', 15),
  ('bk_treasure_decoder_2', 'Kitab Terlarang Sang Perompak', 'III', '{"Knowledge":8,"Luck":3}', 'treasure_decoder_2', 2400, 'toogood', 16)
on conflict (book_id) do nothing;

-- Baris katalog -> objek JSON (kolom sheet BookCatalog)
create or replace function game.book_json(b game.book_catalog) returns jsonb
language sql immutable as $$
  select jsonb_build_object('BookId', b.book_id, 'Name', b.name, 'Tier', b.tier,
    'StatEffects', b.stat_effects, 'SpecialEffect', b.special_effect,
    'Price', trim_scale(b.price), 'Source', b.source)
$$;

-- BookService.getActiveSpecialEffects / hasSpecialEffect
create or replace function game.book_effects(p_pid uuid) returns text[]
language plpgsql stable as $$
begin
  return coalesce((select array_agg(c.special_effect order by c.sort, c.book_id)
    from game.player_books pb join game.book_catalog c on c.book_id = pb.book_id
    where pb.player_id = p_pid and c.special_effect <> ''), array[]::text[]);
end $$;

create or replace function game.book_has_effect(p_pid uuid, p_effect text) returns boolean
language plpgsql stable as $$
begin
  return exists (select 1 from game.player_books pb join game.book_catalog c on c.book_id = pb.book_id
    where pb.player_id = p_pid and c.special_effect = p_effect);
end $$;

-- ---------------------------------------------------------------------
-- KONTRAK: stats / reputasi / cargo
-- ---------------------------------------------------------------------
create or replace function game.stats_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.character_stats;
begin
  select * into s from game.character_stats where player_id = p_pid;
  if not found then return null; end if;
  return jsonb_build_object('Trading', s.trading, 'Negotiation', s.negotiation, 'Navigation', s.navigation,
    'Sailing', s.sailing, 'Combat', s.combat, 'Luck', s.luck, 'Knowledge', s.knowledge);
end $$;

-- MissionService.getReputationForCity: reputation[cityId] || 0
create or replace function game.reputation_for(p_pid uuid, p_city text) returns int
language plpgsql stable as $$
declare r jsonb;
begin
  select reputation into r from game.players where player_id = p_pid;
  if r is null or jsonb_typeof(r) <> 'object' then return 0; end if;
  return game.eco_round(game.eco_js_num(r -> p_city))::int;
exception when others then return 0;
end $$;

-- CargoService.getTotalCargoQty: komoditas di palka + muatan misi terkunci
create or replace function game.cargo_total(p_pid uuid) returns int
language plpgsql stable as $$
declare n int; m int;
begin
  select coalesce(sum(i.qty), 0) into n from game.inventory i join game.commodities c on c.id = i.item_id
   where i.player_id = p_pid and i.qty > 0;
  begin
    m := coalesce(game.mission_load(p_pid), 0);
  exception when others then m := 0;
  end;
  return n + m;
end $$;

-- CargoService.getCargo: HANYA komoditas (item/artifact tidak ikut)
create or replace function game.cargo_json(p_pid uuid) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('commodityId', i.item_id, 'name', c.name, 'qty', i.qty, 'size', c.size)
    order by c.sort, c.id), '[]'::jsonb)
  from game.inventory i join game.commodities c on c.id = i.item_id
  where i.player_id = p_pid and i.qty > 0
$$;

-- WarehouseService.getWarehouseContents
create or replace function game.warehouse_json(p_pid uuid, p_city text) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('commodityId', w.commodity_id,
      'name', coalesce(c.name, w.commodity_id), 'qty', w.qty, 'size', coalesce(c.size, 1)) order by c.sort nulls last, w.commodity_id), '[]'::jsonb)
  from game.warehouse w left join game.commodities c on c.id = w.commodity_id
  where w.player_id = p_pid and w.city_id = p_city and w.qty > 0
$$;

-- ---------------------------------------------------------------------
-- MARKET (MarketService.gs v8)
-- ---------------------------------------------------------------------
-- statToBonusPercent
create or replace function game.eco_stat_bonus(p_stat numeric) returns double precision
language sql immutable as $$ select least(coalesce(p_stat, 0), 100)::double precision / 10 $$;

-- getReputationBonusPercent_
create or replace function game.eco_rep_bonus(p_pid uuid, p_city text) returns double precision
language plpgsql stable as $$
declare r jsonb; rep double precision;
begin
  select reputation into r from game.players where player_id = p_pid;
  if r is null or jsonb_typeof(r) <> 'object' then rep := 0;
  else rep := game.eco_js_num(r -> p_city)::double precision;
  end if;
  return least(rep * game.cfg_num('ReputationMarketBonusPerPoint', 0.05)::double precision,
               game.cfg_num('ReputationMarketBonusCap', 10)::double precision);
end $$;

-- Buku "Smuggler's Codebook" ATAU artifact terpasang -> +5% diskon beli
create or replace function game.eco_black_market_extra(p_pid uuid) returns double precision
language plpgsql stable as $$
declare has boolean := false;
begin
  begin
    has := coalesce(game.has_effect(p_pid, 'black_market_discount'), false);
  exception when others then has := false;
  end;
  if not has then has := game.book_has_effect(p_pid, 'black_market_discount'); end if;
  return case when has then 5 else 0 end;
end $$;

-- TooGood: Arms selalu -20%
create or replace function game.eco_arms_discount(p_city text, p_commodity text) returns double precision
language sql immutable as $$ select case when p_city = 'toogood' and p_commodity = 'arms' then 20 else 0 end::double precision $$;

-- computePrices_ : sellPrice di-clamp <= buyPrice
create or replace function game.eco_prices(p_current bigint, p_buy_disc double precision, p_nego double precision,
  out buy_price bigint, out sell_price bigint)
language plpgsql immutable as $$
begin
  buy_price := game.eco_round(p_current::double precision * (1 - p_buy_disc / 100));
  sell_price := least(game.eco_round(p_current::double precision * (1 + p_nego / 100)), buy_price);
end $$;

-- CurrentPrice setelah event kota
create or replace function game.eco_current_price(p_city text, p_raw int) returns bigint
language plpgsql stable as $$
declare ev int := 0;
begin
  begin
    ev := coalesce(game.event_price_pct(p_city), 0);
  exception when others then ev := 0;
  end;
  return game.eco_round(p_raw::double precision * (1 + ev::double precision / 100));
end $$;

-- Overstock config
create or replace function game.eco_glut_cfg(out scale double precision, out half_life_ms double precision, out floor_pct double precision)
language plpgsql stable as $$
begin
  scale := greatest(10, game.cfg_num('OverstockScale', 120))::double precision;
  half_life_ms := (greatest(5, game.cfg_num('OverstockHalfLifeMinutes', 120)) * 60000)::double precision;
  floor_pct := (least(95, greatest(5, game.cfg_num('OverstockFloorPercent', 35))) / 100)::double precision;
end $$;

-- glutNow_ : glut yang sudah diluruhkan ke waktu sekarang
create or replace function game.eco_glut_now(p_city text, p_commodity text) returns double precision
language plpgsql stable as $$
declare r game.market_glut; cfg record; dt double precision; g double precision;
begin
  select * into r from game.market_glut where city_id = p_city and commodity_id = p_commodity;
  if not found then return 0; end if;
  select * into cfg from game.eco_glut_cfg();
  dt := greatest(0, extract(epoch from (now() - r.at)) * 1000)::double precision;
  g := r.glut::double precision * power(0.5::double precision, dt / cfg.half_life_ms);
  return case when g < 0.05 then 0 else g end;
end $$;

-- setGlut_
create or replace function game.eco_set_glut(p_city text, p_commodity text, p_g double precision) returns void
language plpgsql as $$
declare cfg record;
begin
  select * into cfg from game.eco_glut_cfg();
  if p_g < 0.05 then
    delete from game.market_glut where city_id = p_city and commodity_id = p_commodity;
  else
    insert into game.market_glut(city_id, commodity_id, glut, at)
    values (p_city, p_commodity, trim_scale(round((p_g * 100)::numeric) / 100), now())
    on conflict (city_id, commodity_id) do update set glut = excluded.glut, at = excluded.at;
  end if;
  -- buang entri yang sudah pulih
  delete from game.market_glut
   where glut::double precision * power(0.5::double precision,
           greatest(0, extract(epoch from (now() - at)) * 1000)::double precision / cfg.half_life_ms) < 0.05;
end $$;

-- sellUnitAt_
create or replace function game.eco_sell_unit(p_normal bigint, p_g double precision, p_scale double precision, p_floor double precision) returns bigint
language sql immutable as $$
  select greatest(game.eco_round(p_normal::double precision * p_floor),
                  game.eco_round(p_normal::double precision / (1 + p_g / p_scale)))
$$;

-- sellRevenue_
create or replace function game.eco_sell_revenue(p_normal bigint, p_g double precision, p_qty bigint, p_scale double precision, p_floor double precision) returns bigint
language sql immutable as $$
  select coalesce(sum(game.eco_sell_unit(p_normal, p_g + i, p_scale, p_floor)), 0)::bigint
  from generate_series(0, p_qty - 1) as i
$$;

-- KONTRAK: MarketService.quoteBuy (0 = tidak dijual)
create or replace function game.quote_buy(p_pid uuid, p_city text, p_commodity text) returns int
language plpgsql stable as $$
declare raw int; cp bigint; s game.character_stats; trading double precision := 0; disc double precision; pr record;
begin
  select current_price into raw from game.market where city_id = p_city and commodity_id = p_commodity;
  if not found then return 0; end if;
  cp := game.eco_current_price(p_city, raw);
  select * into s from game.character_stats where player_id = p_pid;
  if found then trading := game.eco_stat_bonus(s.trading); end if;
  disc := (trading + game.eco_black_market_extra(p_pid)) + game.eco_rep_bonus(p_pid, p_city) + game.eco_arms_discount(p_city, p_commodity);
  select * into pr from game.eco_prices(cp, disc, 0);
  return pr.buy_price::int;
end $$;

-- Harga final beli/jual-normal untuk pemain (dipakai getMarket / buy / sell)
create or replace function game.eco_player_prices(p_pid uuid, p_city text, p_commodity text,
  out current_price bigint, out buy_price bigint, out sell_normal bigint)
language plpgsql stable as $$
declare raw int; s game.character_stats; trading double precision := 0; nego double precision := 0;
  rep double precision; disc double precision; pr record;
begin
  select m.current_price into raw from game.market m where m.city_id = p_city and m.commodity_id = p_commodity;
  if not found then current_price := null; return; end if;
  current_price := game.eco_current_price(p_city, raw);
  select * into s from game.character_stats where player_id = p_pid;
  if found then
    trading := game.eco_stat_bonus(s.trading);
    nego := game.eco_stat_bonus(s.negotiation);
  end if;
  rep := game.eco_rep_bonus(p_pid, p_city);
  disc := (trading + game.eco_black_market_extra(p_pid)) + rep + game.eco_arms_discount(p_city, p_commodity);
  select * into pr from game.eco_prices(current_price, disc, nego + rep);
  buy_price := pr.buy_price;
  sell_normal := pr.sell_price;
end $$;

create or replace function public.api_getMarket(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players; pid uuid; cfg record; r record; pp record;
  g double precision; sp bigint; items jsonb := '[]'::jsonb; space int;
begin
  v_me := game.me(false); pid := v_me.player_id;
  select * into cfg from game.eco_glut_cfg();
  for r in select m.commodity_id, m.base_price, c.name, c.flavor
             from game.market m left join game.commodities c on c.id = m.commodity_id
            where m.city_id = v_city order by c.sort, m.commodity_id loop
    select * into pp from game.eco_player_prices(pid, v_city, r.commodity_id);
    g := game.eco_glut_now(v_city, r.commodity_id);
    sp := game.eco_sell_unit(pp.sell_normal, g, cfg.scale, cfg.floor_pct);
    items := items || jsonb_build_array(jsonb_build_object(
      'commodityId', r.commodity_id,
      'name', coalesce(r.name, r.commodity_id),
      'flavor', coalesce(r.flavor, ''),
      'currentPrice', pp.current_price,
      'buyPrice', pp.buy_price,
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

-- Pemeriksaan umum sebelum berdagang di kota
create or replace function game.eco_require_trade_here(p_pid uuid, p_city text) returns void
language plpgsql as $$
begin
  if game.current_city(p_pid) is distinct from p_city then
    raise exception 'Kamu harus berada di kota ini untuk berdagang.';
  end if;
  if game.in_transit(p_pid) then
    raise exception 'Kamu sedang berlayar - tidak bisa berdagang sampai kapal merapat.';
  end if;
  if game.ww_market_closed(p_pid) then
    raise exception 'Toko tutup. Kami diminta diam oleh Pemerintah.';
  end if;
end $$;

create or replace function public.api_buy(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; pp record; total bigint; cap int; cur int; g0 double precision;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah beli tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  perform game.eco_require_trade_here(pid, v_city);
  -- kunci pasangan kota+komoditas (stok menumpuk dibagi semua pemain)
  perform 1 from game.market where city_id = v_city and commodity_id = v_comm for update;
  if not found then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;

  select * into pp from game.eco_player_prices(pid, v_city, v_comm);
  total := pp.buy_price * v_qty;
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

  perform game.log(pid, 'Bought ' || v_qty || ' unit' || case when v_qty > 1 then 's' else '' end || ' of ' ||
    game.commodity_name(v_comm) || ' for ' || total || ' gold.');
  return jsonb_build_object('totalCost', total, 'unitPrice', pp.buy_price, 'newGold', v_me.gold - total);
end $$;
select game.expose('api_buy');

create or replace function public.api_sell(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; pp record; cfg record; g double precision; revenue bigint; nxt bigint;
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

  -- CargoService.adjustQty: baris belum ada -> pesan khusus
  if not exists (select 1 from game.inventory where player_id = pid and item_id = v_comm) then
    raise exception 'Kamu tidak punya cargo ini untuk dijual.';
  end if;
  perform game.adjust_inventory(pid, v_comm, (-v_qty)::int);
  perform game.eco_set_glut(v_city, v_comm, g + v_qty);

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
-- CARGO
-- ---------------------------------------------------------------------
create or replace function public.api_getCargo(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(false);
begin
  return game.cargo_json(v_me.player_id);
end $$;
select game.expose('api_getcargo');

create or replace function public.api_getCargoState(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players := game.me(false);
begin
  return jsonb_build_object(
    'cargo', game.cargo_json(v_me.player_id),
    'warehouse', game.warehouse_json(v_me.player_id, v_city),
    'missionLoad', coalesce(game.mission_load(v_me.player_id), 0),
    'used', game.cargo_used(v_me.player_id),
    'capacity', coalesce(game.effective_cargo(v_me.player_id), 0));
end $$;
select game.expose('api_getcargostate');

-- ---------------------------------------------------------------------
-- WAREHOUSE
-- ---------------------------------------------------------------------
create or replace function public.api_getWarehouse(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players := game.me(false);
begin
  return game.warehouse_json(v_me.player_id, v_city);
end $$;
select game.expose('api_getwarehouse');

create or replace function public.api_warehouseStore(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; fee numeric; owned int; v_share numeric;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  if game.current_city(pid) is distinct from v_city then
    raise exception 'Kamu harus berada di kota ini untuk titip barang.';
  end if;
  if game.in_transit(pid) then raise exception 'Kamu sedang berlayar.'; end if;
  perform game.spot_service_guard(pid);

  fee := trim_scale(game.cfg_num('WarehouseFeePerUnit', 2) * v_qty);
  if v_me.gold < fee then
    raise exception 'Gold tidak cukup untuk biaya titip (% gold).', game.eco_num_text(fee);
  end if;

  select i.qty into owned from game.inventory i join game.commodities c on c.id = i.item_id
   where i.player_id = pid and i.item_id = v_comm and i.qty > 0;
  if owned is null or owned < v_qty then raise exception 'Cargo tidak cukup untuk dititipkan.'; end if;

  -- modal ikut pindah ke gudang (Tide v21)
  select case when i.cost is not null and i.qty > 0 then i.cost * v_qty / i.qty end into v_share
    from game.inventory i where i.player_id = pid and i.item_id = v_comm;
  perform game.adjust_inventory(pid, v_comm, (-v_qty)::int);
  insert into game.warehouse(player_id, city_id, commodity_id, qty, cost) values (pid, v_city, v_comm, v_qty, v_share)
  on conflict (player_id, city_id, commodity_id) do update set qty = game.warehouse.qty + excluded.qty,
    cost = case when game.warehouse.qty = 0 then excluded.cost
                when game.warehouse.cost is null or excluded.cost is null then null
                else game.warehouse.cost + excluded.cost end;

  update game.players set gold = gold - fee where player_id = pid;
  perform game.log(pid, 'Stored ' || v_qty || ' ' || game.commodity_name(v_comm) ||
    ' at the warehouse (fee: ' || game.eco_num_text(fee) || ' gold).');
  return jsonb_build_object('fee', fee, 'newGold', trim_scale(v_me.gold - fee));
end $$;
select game.expose('api_warehousestore');

create or replace function public.api_warehouseWithdraw(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; stored int; wcost numeric; v_share numeric;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  if game.current_city(pid) is distinct from v_city then
    raise exception 'Kamu harus berada di kota ini untuk ambil barang dari gudang.';
  end if;
  perform game.spot_service_guard(pid);
  if game.cargo_used(pid) + v_qty * game.commodity_size(v_comm) > coalesce(game.effective_cargo(pid), 0) then
    raise exception 'Kapasitas cargo tidak cukup untuk mengambil semua ini.';
  end if;

  select qty, cost into stored, wcost from game.warehouse
   where player_id = pid and city_id = v_city and commodity_id = v_comm for update;
  if stored is null or stored < v_qty then raise exception 'Jumlah di gudang tidak cukup.'; end if;
  v_share := case when wcost is not null and stored > 0 then wcost * v_qty / stored end;

  update game.warehouse set qty = qty - v_qty,
         cost = case when qty - v_qty <= 0 then null when cost is null then null else cost - v_share end
   where player_id = pid and city_id = v_city and commodity_id = v_comm;
  perform game.adjust_inventory(pid, v_comm, v_qty::int);
  if v_share is not null then perform game.inv_add_cost(pid, v_comm, v_qty::int, v_share); end if;
  perform game.log(pid, 'Retrieved ' || v_qty || ' ' || game.commodity_name(v_comm) || ' from the warehouse.');
  return jsonb_build_object('ok', true);
end $$;
select game.expose('api_warehousewithdraw');

-- ---------------------------------------------------------------------
-- BANK & MONEYLENDER (BankService.gs) - bunga majemuk lazy per hari-game
-- ---------------------------------------------------------------------
create or replace function game.bank_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare p game.players; day int; bank_rate numeric; debt_rate numeric;
  bank_last int; debt_last int; bank_days int; debt_days int;
  bank_bal double precision; debt_bal double precision;
begin
  select * into p from game.players where player_id = p_pid;
  if not found then raise exception 'Player % tidak ditemukan.', p_pid; end if;
  day := game.game_day();
  bank_rate := game.cfg_num('BankInterestRatePercent', 0.5);
  debt_rate := game.cfg_num('DebtInterestRatePercent', 2);

  bank_bal := coalesce(p.bank_balance, 0);
  debt_bal := coalesce(p.debt_balance, 0);
  bank_last := coalesce(p.bank_last_interest_day, day);
  debt_last := coalesce(p.debt_last_interest_day, day);
  bank_days := greatest(0, day - bank_last);
  debt_days := greatest(0, day - debt_last);

  if bank_days > 0 and bank_bal > 0 then
    bank_bal := game.eco_round(bank_bal * power(1 + bank_rate::double precision / 100, bank_days));
  end if;
  if debt_days > 0 and debt_bal > 0 then
    debt_bal := game.eco_round(debt_bal * power(1 + debt_rate::double precision / 100, debt_days));
  end if;

  -- Tulis balik (juga menginisialisasi hari accrual yang masih kosong)
  if bank_days > 0 or debt_days > 0 or p.bank_last_interest_day is null or p.debt_last_interest_day is null then
    update game.players set
      bank_balance = game.eco_round(bank_bal),
      debt_balance = game.eco_round(debt_bal),
      bank_last_interest_day = case when bank_days > 0 or bank_last_interest_day is null then day else bank_last_interest_day end,
      debt_last_interest_day = case when debt_days > 0 or debt_last_interest_day is null then day else debt_last_interest_day end
    where player_id = p_pid;
  end if;

  return jsonb_build_object(
    'bankBalance', game.eco_round(bank_bal),
    'debtBalance', game.eco_round(debt_bal),
    'bankRatePercent', trim_scale(bank_rate),
    'debtRatePercent', trim_scale(debt_rate),
    'maxDebt', trim_scale(game.cfg_num('MaxDebtAmount', 5000)),
    'migrated', true);
end $$;

create or replace function public.api_getBankState(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true);
begin
  return game.bank_state(v_me.player_id);
end $$;
select game.expose('api_getbankstate');

create or replace function public.api_bankDeposit(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah setor tidak valid.'; end if;
  v_me := game.me(true);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  if v_me.gold < v_amt then raise exception 'Gold tidak cukup.'; end if;
  update game.players set bank_balance = (st ->> 'bankBalance')::bigint + v_amt, gold = gold - v_amt
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Deposited ' || v_amt || ' gold at the Bank.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold - v_amt);
end $$;
select game.expose('api_bankdeposit');

create or replace function public.api_bankWithdraw(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah tarik tidak valid.'; end if;
  v_me := game.me(true);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  if (st ->> 'bankBalance')::bigint < v_amt then raise exception 'Saldo Bank tidak cukup.'; end if;
  update game.players set bank_balance = (st ->> 'bankBalance')::bigint - v_amt, gold = gold + v_amt
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Withdrew ' || v_amt || ' gold from the Bank.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold + v_amt);
end $$;
select game.expose('api_bankwithdraw');

create or replace function public.api_bankBorrow(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah pinjam tidak valid.'; end if;
  v_me := game.me(true);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  if (st ->> 'debtBalance')::numeric + v_amt > (st ->> 'maxDebt')::numeric then
    raise exception 'Melebihi batas pinjaman Moneylender (maksimum utang % gold).', st ->> 'maxDebt';
  end if;
  update game.players set debt_balance = (st ->> 'debtBalance')::bigint + v_amt, gold = gold + v_amt
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Borrowed ' || v_amt || ' gold from the Moneylender.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold + v_amt);
end $$;
select game.expose('api_bankborrow');

create or replace function public.api_bankRepay(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_amt bigint := game.arg_int(a, 0); v_me game.players; st jsonb; pay bigint;
begin
  if v_amt is null or v_amt <= 0 then raise exception 'Jumlah bayar tidak valid.'; end if;
  v_me := game.me(true);
  perform game.spot_service_guard(v_me.player_id);
  st := game.bank_state(v_me.player_id);
  pay := least(v_amt, (st ->> 'debtBalance')::bigint, v_me.gold);
  if pay <= 0 then raise exception 'Tidak ada yang bisa dibayar (cek gold atau utangmu).'; end if;
  update game.players set debt_balance = (st ->> 'debtBalance')::bigint - pay, gold = gold - pay
   where player_id = v_me.player_id;
  perform game.log(v_me.player_id, 'Repaid ' || pay || ' gold to the Moneylender.');
  return game.bank_state(v_me.player_id) || jsonb_build_object('newGold', v_me.gold - pay);
end $$;
select game.expose('api_bankrepay');

-- ---------------------------------------------------------------------
-- LIBRARY / BOOKS
-- ---------------------------------------------------------------------
create or replace function public.api_getLibrary(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(false); v_city text;
begin
  v_city := game.current_city(v_me.player_id);
  return jsonb_build_object(
    'owned', coalesce((select jsonb_agg(game.book_json(c) order by c.sort, c.book_id) from game.book_catalog c
       where exists (select 1 from game.player_books pb where pb.player_id = v_me.player_id and pb.book_id = c.book_id)), '[]'::jsonb),
    'available', coalesce((select jsonb_agg(game.book_json(c) order by c.sort, c.book_id) from game.book_catalog c
       where not exists (select 1 from game.player_books pb where pb.player_id = v_me.player_id and pb.book_id = c.book_id)
         and (c.source = 'any' or c.source = v_city)), '[]'::jsonb));
end $$;
select game.expose('api_getlibrary');

create or replace function public.api_buyBook(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_book text := game.arg(a, 0); v_me game.players; pid uuid; b game.book_catalog; v_city text;
  price numeric; eff jsonb; r record; d int;
begin
  v_me := game.me(true); pid := v_me.player_id;
  select * into b from game.book_catalog where book_id = v_book;
  if not found then raise exception 'Buku tidak dikenali: %', coalesce(v_book, 'undefined'); end if;
  v_city := game.current_city(pid);
  if b.source <> 'any' and b.source is distinct from v_city then
    raise exception 'Buku ini tidak dijual di kota ini.';
  end if;
  if game.in_transit(pid) then
    raise exception 'Kamu sedang berlayar - tidak bisa mengunjungi Library sampai kapal merapat.';
  end if;
  if exists (select 1 from game.player_books where player_id = pid and book_id = v_book) then
    raise exception 'Kamu sudah punya buku ini.';
  end if;
  price := coalesce(b.price, 0);
  if v_me.gold < price then
    raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', game.eco_num_text(price), v_me.gold;
  end if;

  -- parseStatEffects_
  begin
    eff := nullif(b.stat_effects, '')::jsonb;
  exception when others then eff := null;
  end;
  if eff is null or jsonb_typeof(eff) <> 'object' then eff := '{}'::jsonb; end if;

  -- applyStatEffects_
  perform 1 from game.character_stats where player_id = pid for update;
  if not found then raise exception 'CharacterStats untuk pemain ini tidak ditemukan.'; end if;
  for r in select key, value from jsonb_each(eff) loop
    d := game.eco_round(game.eco_js_num(r.value))::int;
    case r.key
      when 'Trading' then update game.character_stats set trading = trading + d where player_id = pid;
      when 'Negotiation' then update game.character_stats set negotiation = negotiation + d where player_id = pid;
      when 'Navigation' then update game.character_stats set navigation = navigation + d where player_id = pid;
      when 'Sailing' then update game.character_stats set sailing = sailing + d where player_id = pid;
      when 'Combat' then update game.character_stats set combat = combat + d where player_id = pid;
      when 'Luck' then update game.character_stats set luck = luck + d where player_id = pid;
      when 'Knowledge' then update game.character_stats set knowledge = knowledge + d where player_id = pid;
      else null;
    end case;
  end loop;

  insert into game.player_books(player_id, book_id, date_acquired) values (pid, v_book, game.game_day());
  update game.players set gold = gold - price where player_id = pid;
  perform game.log(pid, 'Purchased "' || b.name || '" for ' || game.eco_num_text(price) || ' gold.');
  return jsonb_build_object('newGold', trim_scale(v_me.gold - price), 'book', game.book_json(b));
end $$;
select game.expose('api_buybook');

create or replace function public.api_getCharacterStats(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(false);
begin
  return jsonb_build_object('stats', game.stats_json(v_me.player_id));
end $$;
select game.expose('api_getcharacterstats');

-- ---------------------------------------------------------------------
-- APPEARANCE (AppearanceStore_) & META (MetaStore_)
-- ---------------------------------------------------------------------
create or replace function game.appearance_pick(v jsonb, allowed text[], dflt text) returns text
language sql immutable as $$
  select case when jsonb_typeof(v) = 'string' and (v #>> '{}') = any (allowed) then v #>> '{}' else dflt end
$$;

-- Penampilan kapten v2 (Tide v14) - lihat docs/FACE_V2_SPEC.md
create or replace function game.appearance_clean(p jsonb) returns jsonb
language plpgsql immutable as $$
declare a jsonb := p; fem int; head text;
begin
  if a is null or jsonb_typeof(a) <> 'object' then a := '{}'::jsonb; end if;
  fem := case when game.eco_js_truthy(a -> 'fem') then 1 else 0 end;
  head := case when a ->> 'head' = 'hood' then 'tudung' when a ->> 'head' = 'headband' then 'ikat' else a ->> 'head' end;
  return jsonb_build_object(
    'fem', fem,
    'skin', greatest(0, least(7, floor(game.eco_js_num(a -> 'skin'))))::int,
    'hair', greatest(0, least(9, floor(game.eco_js_num(a -> 'hair'))))::int,
    'hairStyle', greatest(0, least(13, floor(game.eco_js_num(a -> 'hairStyle'))))::int,
    'facial', case when fem = 1 then 0 else greatest(0, least(9, floor(game.eco_js_num(a -> 'facial'))))::int end,
    'eyes', greatest(0, least(4, floor(game.eco_js_num(a -> 'eyes'))))::int,
    'iris', greatest(0, least(5, floor(game.eco_js_num(a -> 'iris'))))::int,
    'brows', greatest(0, least(3, floor(game.eco_js_num(a -> 'brows'))))::int,
    'head', game.appearance_pick(to_jsonb(head), array['arch', 'none', 'hijab', 'peci', 'blangkon', 'bandana', 'tricorne', 'kapten', 'bicorne',
      'plumed', 'udeng', 'iket', 'caping', 'serban', 'beret', 'kupluk', 'brim', 'bowler', 'ikat', 'tudung'], 'arch'),
    'outfit', game.appearance_pick(a -> 'outfit', array['arch', 'jas_kapten', 'mantel', 'rompi', 'kemeja', 'beskap', 'kebaya', 'koko', 'kulit',
      'seragam', 'pelaut', 'jubah'], 'arch'),
    'cloth', greatest(0, least(9, floor(game.eco_js_num(a -> 'cloth'))))::int,
    'eye', game.appearance_pick(a -> 'eye', array['arch', 'none', 'patch', 'monocle', 'glasses', 'halfmoon'], 'arch'),
    'ear', game.appearance_pick(a -> 'ear', array['arch', 'none', 'hoop', 'hoop2', 'pearl', 'stud'], 'arch'),
    'neck', game.appearance_pick(a -> 'neck', array['arch', 'none', 'scarf', 'chain', 'pearls', 'medallion', 'jabot', 'tooth', 'masker'], 'arch'),
    'mark', game.appearance_pick(a -> 'mark', array['none', 'scar_cheek', 'scar_eye', 'tattoo', 'freckles', 'mole', 'warpaint'], 'none'),
    'item', game.appearance_pick(a -> 'item', array['arch', 'none', 'pipe', 'parrot', 'spyglass', 'sword'], 'arch'),
    'seed', greatest(0, least(999999, floor(game.eco_js_num(a -> 'seed'))))::int);
end $$;

create or replace function public.api_saveAppearance(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); c jsonb;
begin
  c := game.appearance_clean(game.arg_json(a, 0));
  update game.players set appearance = c where player_id = v_me.player_id;
  return c;
end $$;
select game.expose('api_saveappearance');

-- MetaStore_.clean
create or replace function game.meta_clean(p jsonb) returns jsonb
language plpgsql immutable as $$
declare m jsonb := p; ou jsonb := '{}'::jsonb; oc jsonb := '{}'::jsonb; ov jsonb := '[]'::jsonb;
  r record; n int; s text;
begin
  if m is null or jsonb_typeof(m) <> 'object' then m := '{}'::jsonb; end if;
  if jsonb_typeof(m -> 'u') = 'object' then
    n := 0;
    for r in select key, value from jsonb_each(m -> 'u') loop
      n := n + 1; exit when n > 80;
      if r.key ~ '^[a-z0-9_]{1,24}$' then
        ou := ou || jsonb_build_object(r.key, greatest(0, floor(game.eco_js_num(r.value))));
      end if;
    end loop;
  end if;
  if jsonb_typeof(m -> 'c') = 'object' then
    n := 0;
    for r in select key, value from jsonb_each(m -> 'c') loop
      n := n + 1; exit when n > 40;
      if r.key ~ '^[a-z0-9_]{1,24}$' then
        oc := oc || jsonb_build_object(r.key, greatest(0, least(1000000000000, floor(game.eco_js_num(r.value)))));
      end if;
    end loop;
  end if;
  if jsonb_typeof(m -> 'v') = 'array' then
    for r in select value from jsonb_array_elements(m -> 'v') with ordinality as t(value, ord) where ord <= 60 order by ord loop
      s := left(game.eco_js_string(r.value), 40);
      if s <> '' and not (ov @> jsonb_build_array(s)) then ov := ov || jsonb_build_array(s); end if;
    end loop;
  end if;
  return jsonb_build_object('u', ou, 'c', oc, 'v', ov);
end $$;

-- MetaStore_.merge (union / max)
create or replace function game.meta_merge(p_old jsonb, p_new jsonb) returns jsonb
language plpgsql immutable as $$
declare o jsonb := game.meta_clean(p_old); n jsonb := game.meta_clean(p_new);
  ou jsonb; oc jsonb; ov jsonb; r record; oldv numeric; newv numeric;
begin
  ou := o -> 'u'; oc := o -> 'c'; ov := o -> 'v';
  for r in select key, value from jsonb_each(n -> 'u') loop
    newv := (r.value #>> '{}')::numeric;
    oldv := (ou ->> r.key)::numeric;
    if oldv is null or oldv = 0 or (newv <> 0 and newv < oldv) then
      ou := ou || jsonb_build_object(r.key,
        case when newv <> 0 then newv when oldv is not null and oldv <> 0 then oldv else 1 end);
    end if;
  end loop;
  for r in select key, value from jsonb_each(n -> 'c') loop
    oc := oc || jsonb_build_object(r.key, greatest(coalesce((oc ->> r.key)::numeric, 0), (r.value #>> '{}')::numeric));
  end loop;
  for r in select value from jsonb_array_elements(n -> 'v') with ordinality as t(value, ord) order by ord loop
    if not (ov @> jsonb_build_array(r.value)) then ov := ov || jsonb_build_array(r.value); end if;
  end loop;
  return jsonb_build_object('u', ou, 'c', oc, 'v', ov);
end $$;

-- Panjang JSON.stringify (jsonb::text menambah spasi setelah ':' dan ',')
create or replace function game.eco_meta_json_len(m jsonb) returns int
language sql immutable as $$
  select length(m::text)
    - (3 + (select count(*) from jsonb_object_keys(m -> 'u'))::int + (select count(*) from jsonb_object_keys(m -> 'c'))::int)
    - (2 + greatest((select count(*) from jsonb_object_keys(m -> 'u'))::int - 1, 0)
         + greatest((select count(*) from jsonb_object_keys(m -> 'c'))::int - 1, 0)
         + greatest(jsonb_array_length(m -> 'v') - 1, 0))
$$;

create or replace function public.api_saveMeta(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); merged jsonb;
begin
  merged := game.meta_merge(v_me.meta, game.arg_json(a, 0));
  if game.eco_meta_json_len(merged) > 8000 then raise exception 'Data Tanda Jasa terlalu besar.'; end if;
  update game.players set meta = merged where player_id = v_me.player_id;
  return merged;
end $$;
select game.expose('api_savemeta');

-- ---------------------------------------------------------------------
-- LEADERBOARD
-- ---------------------------------------------------------------------
create or replace function public.api_getLeaderboard(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'characterName', t.character_name, 'archetype', t.archetype, 'gold', t.gold,
      'appearance', coalesce(t.appearance, 'null'::jsonb),
      'badges', case when t.meta is not null and jsonb_typeof(t.meta -> 'u') = 'object'
                     then (select count(*) from jsonb_object_keys(t.meta -> 'u'))::int else 0 end)
      order by t.gold desc, t.created_at, t.player_id)
    from (select * from game.players where character_name <> ''
           order by gold desc, created_at, player_id limit 5) t), '[]'::jsonb);
end $$;
select game.expose('api_getleaderboard');

-- ---------------------------------------------------------------------
-- CHARACTER (CharacterService.gs)
-- ---------------------------------------------------------------------
-- getFullCharacterState
create or replace function game.full_character_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare p game.players; ar game.archetypes;
begin
  select * into p from game.players where player_id = p_pid;
  select * into ar from game.archetypes where id = p.archetype;
  return jsonb_build_object(
    'player', game.player_json(p),
    'stats', game.stats_json(p_pid),
    'archetype', case when ar.id is null then null
      else jsonb_build_object('name', ar.name, 'perkName', ar.perk_name, 'perkDesc', ar.perk_desc) end);
end $$;

-- archetype.name.replace('The ', '') (hanya kemunculan pertama)
create or replace function game.eco_replace_first_the(s text) returns text
language sql immutable as $$
  select case when strpos(s, 'The ') > 0
    then substr(s, 1, strpos(s, 'The ') - 1) || substr(s, strpos(s, 'The ') + 4) else s end
$$;

create or replace function public.api_createCharacter(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_raw text := game.arg(a, 0); v_arch text := game.arg(a, 1); v_app jsonb := game.arg_json(a, 2);
  v_me game.players; pid uuid; ar game.archetypes; v_name text; v_wanted text; rep jsonb := '{}'::jsonb;
  st record;
begin
  v_me := game.me(true); pid := v_me.player_id;

  -- Tide v6: nama kapten unik (case-insensitive)
  v_wanted := lower(game.eco_trim(coalesce(v_raw, '')));
  if v_wanted <> '' and exists (select 1 from game.players
       where player_id <> pid and lower(game.eco_trim(character_name)) = v_wanted) then
    raise exception 'Nama kapten "%" sudah dipakai pemain lain.', v_raw;
  end if;

  select * into ar from game.archetypes where id = v_arch;
  if not found then raise exception 'Archetype tidak dikenali: %', coalesce(v_arch, 'undefined'); end if;

  v_name := game.eco_trim(coalesce(v_raw, ''));
  if v_name = '' then raise exception 'Nama karakter tidak boleh kosong.'; end if;
  if char_length(v_name) > 40 then raise exception 'Nama karakter terlalu panjang (maks 40 karakter).'; end if;
  if v_me.archetype <> '' then raise exception 'Karakter untuk akun ini sudah pernah dibuat.'; end if;

  -- writeCharacterStats: BASE_STATS + bonus archetype
  select 35 + coalesce((ar.bonuses ->> 'Trading')::int, 0) as trading,
         35 + coalesce((ar.bonuses ->> 'Negotiation')::int, 0) as negotiation,
         35 + coalesce((ar.bonuses ->> 'Navigation')::int, 0) as navigation,
         35 + coalesce((ar.bonuses ->> 'Sailing')::int, 0) as sailing,
         35 + coalesce((ar.bonuses ->> 'Combat')::int, 0) as combat,
         15 + coalesce((ar.bonuses ->> 'Luck')::int, 0) as luck,
          5 + coalesce((ar.bonuses ->> 'Knowledge')::int, 0) as knowledge
    into st;
  insert into game.character_stats(player_id, trading, negotiation, navigation, sailing, combat, luck, knowledge)
  values (pid, st.trading, st.negotiation, st.navigation, st.sailing, st.combat, st.luck, st.knowledge)
  on conflict (player_id) do update set trading = excluded.trading, negotiation = excluded.negotiation,
    navigation = excluded.navigation, sailing = excluded.sailing, combat = excluded.combat,
    luck = excluded.luck, knowledge = excluded.knowledge;

  -- writeStarterShip (nilai default tabel = kapal starter)
  delete from game.ships where player_id = pid;
  insert into game.ships(player_id) values (pid);

  -- writeStartingLocation
  delete from game.player_location where player_id = pid;
  insert into game.player_location(player_id, city_id, arrived_game_day) values (pid, 'sunda_empire', game.game_day());

  if coalesce(ar.starting_reputation_bonus, 0) <> 0 then
    rep := jsonb_build_object('sunda_empire', ar.starting_reputation_bonus);
  end if;

  begin
    update game.players set character_name = v_name, archetype = ar.id, gold = 5000, reputation = rep
     where player_id = pid;
  exception when unique_violation then
    raise exception 'Nama kapten "%" sudah dipakai pemain lain.', v_raw;
  end;

  perform game.log(pid, 'Began your journey as ' || v_name || ', ' || game.eco_replace_first_the(ar.name) || ', in Sunda Empire.');

  -- Tide v3: wajah kapten (opsional)
  if game.eco_js_truthy(v_app) then
    update game.players set appearance = game.appearance_clean(v_app) where player_id = pid;
  end if;

  return game.full_character_state(pid);
end $$;

select game.expose('api_createcharacter');

-- Hapus baris pemain di tabel game.<tbl> bila tabel & kolom player_id ada
create or replace function game.eco_delete_player_rows(p_table text, p_pid uuid) returns void
language plpgsql as $$
begin
  if to_regclass('game.' || p_table) is not null and exists (
       select 1 from pg_attribute where attrelid = to_regclass('game.' || p_table)
          and attname = 'player_id' and not attisdropped) then
    execute format('delete from game.%I where player_id = $1', p_table) using p_pid;
  end if;
end $$;

create or replace function public.api_deleteCharacter(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players; pid uuid; t text; f record;
begin
  v_me := game.me(true); pid := v_me.player_id;
  if v_me.archetype = '' then raise exception 'Belum ada karakter untuk dihapus.'; end if;

  -- DELETABLE_PLAYER_SHEETS (+ warehouse) - tabel modul lain dicek dulu keberadaannya
  foreach t in array array['character_stats', 'ships', 'ship_equipment', 'player_location', 'inventory',
      'player_books', 'player_missions', 'combat_log', 'player_log', 'warehouse',
      'player_artifacts', 'player_equipment', 'artifact_slots'] loop
    perform game.eco_delete_player_rows(t, pid);
  end loop;

  -- Hook modul lain: game.<nama>_on_character_delete(uuid)
  for f in select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'game' and p.proname like '%\_on\_character\_delete' and p.pronargs = 1
            order by p.proname loop
    execute format('select game.%I($1)', f.proname) using pid;
  end loop;

  update game.players set character_name = '', archetype = '', gold = 0, reputation = '{}'::jsonb,
    ship_upgrades = '{}'::jsonb, meta = null,
    bank_balance = 0, bank_last_interest_day = null, debt_balance = 0, debt_last_interest_day = null
   where player_id = pid;
  return jsonb_build_object('success', true);
end $$;
select game.expose('api_deletecharacter');
