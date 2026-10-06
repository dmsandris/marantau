-- =====================================================================
-- Marantau (Supabase) - 0018 EKONOMI v2 (Tide v16)
-- * 28 barang dalam 6 kelompok, tiap kelompok punya barang Premium.
-- * Stok pasar TERBATAS per kota x barang. Harga lahir dari stok:
--     mid = base x clamp(((R + k) / (stok + k)) ^ e, 0.35, 3)      k = 0.4 R
--   beli/jual per unit menggeser stok -> harga bergerak unit demi unit.
-- * Stok kembali ke tingkat alaminya (E) secara halus: tau ~26 menit
--   (kota produsen terisi ulang, kota konsumen menghabiskan kelebihan).
-- * Siklus pasar tiap 60 menit nyata: 2 barang "Dicari!" (E x0.4) dan
--   1 barang "Panen Raya" (E x1.8) per kota - rute terbaik berganti.
-- * Barang Premium di kota produsennya: kiriman kecil tiap siklus (bukan drift).
-- * Ukuran palka per barang (Emas 0.1 ... Kayu Jati 2).
-- * "Spices" lama dikonversi menjadi Lada.
-- Semua angka bisa diatur lewat game.config. Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Katalog barang
-- ---------------------------------------------------------------------
insert into game.commodities(id, name, flavor, sort, grp, tier, base, size, spread, elast, ref, active) values
  ('beras',        'Beras',        'Makanan pokok setiap pelabuhan. Murah, berat, selalu dicari.',              1, 'pangan',    'common',  20,   1,    0.12, 0.55, 100, true),
  ('ikan_asin',    'Ikan Asin',    'Bekal pelaut sejati - tahan berbulan-bulan di palka.',                     2, 'pangan',    'common',  35,   1,    0.12, 0.55, 100, true),
  ('garam',        'Garam',        'Emas putih dari tambak pantai.',                                          3, 'pangan',    'common',  60,   1,    0.12, 0.55, 100, true),
  ('sugar',        'Gula',         'Manis, berat, dan selalu dicari dapur istana.',                           4, 'pangan',    'common',  100,  1,    0.12, 0.55, 100, true),
  ('sarang_walet', 'Sarang Walet', 'Dipanen dari gua-gua tebing. Para bangsawan rela membayar mahal.',         5, 'pangan',    'premium', 4500, 0.25, 0.225, 0.6,  10,  true),
  ('tuak',         'Tuak',         'Nira manis yang difermentasi - minuman rakyat pesisir.',                  6, 'minuman',   'common',  40,   1,    0.12, 0.55, 100, true),
  ('rum',          'Arak',         'Bahan bakar kru sekaligus mata uang tidak resmi pelabuhan.',              7, 'minuman',   'common',  90,   1,    0.12, 0.55, 100, true),
  ('kopi',         'Kopi',         'Biji kopi dari dataran tinggi, harum sampai ke ujung dermaga.',           8, 'minuman',   'mid',     180,  0.5,  0.15, 0.65, 45,  true),
  ('jackdaniels',  'JackDaniels',  'Wiski impor dalam botol persegi - kebanggaan meja para kapten.',          9, 'minuman',   'premium', 1400, 0.25, 0.225, 0.6,  10,  true),
  ('jhonnywalker', 'JhonnyWalker', 'Wiski impor paling bergengsi di Mare Nusantara.',                         10, 'minuman',   'premium', 3250, 0.25, 0.225, 0.6,  10,  true),
  ('kayu_manis',   'Kayu Manis',   'Kulit kayu harum dari bukit-bukit Minang.',                               11, 'rempah',    'mid',     220,  0.5,  0.15, 0.65, 45,  true),
  ('lada',         'Lada',         'Raja rempah - butiran pedas yang membuat pedagang jauh rela berlayar.',   12, 'rempah',    'mid',     240,  0.5,  0.15, 0.65, 45,  true),
  ('cengkeh',      'Cengkeh',      'Bunga kering yang dulu diperebutkan bangsa-bangsa.',                       13, 'rempah',    'mid',     300,  0.5,  0.15, 0.65, 45,  true),
  ('pala',         'Pala',         'Biji pala dan fulinya - harum, langka, berharga.',                         14, 'rempah',    'mid',     340,  0.5,  0.15, 0.65, 45,  true),
  ('gaharu',       'Gaharu',       'Kayu resin yang wanginya dibakar di istana dan kuil.',                     15, 'rempah',    'premium', 5500, 0.25, 0.225, 0.6,  10,  true),
  ('rotan',        'Rotan',        'Batang lentur dari hutan rimba, bahan anyaman dan tali kapal.',            16, 'bahan',     'common',  45,   1.5,  0.12, 0.55, 100, true),
  ('kayu_jati',    'Kayu Jati',    'Kayu terbaik untuk lambung kapal dan rumah bangsawan.',                    17, 'bahan',     'common',  80,   2,    0.12, 0.55, 100, true),
  ('besi',         'Besi',         'Batangan besi untuk paku, jangkar, dan meriam.',                           18, 'bahan',     'mid',     150,  2,    0.15, 0.65, 45,  true),
  ('kayu_cendana', 'Kayu Cendana', 'Kayu wangi dari timur yang harumnya bertahan puluhan tahun.',              19, 'bahan',     'premium', 3800, 1,    0.225, 0.6,  10,  true),
  ('tools',        'Perkakas',     'Tidak glamor, tapi setiap pemukiman baru membutuhkannya.',                20, 'kerajinan', 'mid',     160,  1,    0.15, 0.65, 45,  true),
  ('batik',        'Kain Batik',   'Kain bercorak tulis tangan - setiap motif punya cerita.',                  21, 'kerajinan', 'mid',     160,  0.5,  0.15, 0.65, 45,  true),
  ('porselen',     'Porselen',     'Piring dan guci halus yang dibawa jung dari utara.',                       22, 'kerajinan', 'mid',     260,  1,    0.15, 0.65, 45,  true),
  ('keris',        'Keris Pusaka', 'Ditempa empu dengan pamor berlapis - setiap bilah konon bertuah.',         23, 'kerajinan', 'premium', 7000, 0.25, 0.225, 0.6,  10,  true),
  ('mesiu',        'Mesiu',        'Bubuk hitam pengisi meriam. Jauhkan dari api!',                            24, 'mewah',     'mid',     220,  1,    0.15, 0.65, 45,  true),
  ('silk',         'Sutra',        'Halus seperti bisikan, mahal seperti janji bangsawan.',                    25, 'mewah',     'mid',     290,  0.5,  0.15, 0.65, 45,  true),
  ('arms',         'Senjata',      'Diperlukan untuk melindungi diri - atau merampas milik orang lain.',      26, 'mewah',     'mid',     320,  1,    0.15, 0.65, 45,  true),
  ('mutiara',      'Mutiara',      'Butir bulat berkilau dari laguna terdalam.',                                27, 'mewah',     'premium', 4500, 0.1,  0.225, 0.6,  10,  true),
  ('emas',         'Emas',         'Batangan emas murni. Kecil, berat, dan bernilai sebuah kapal.',            28, 'mewah',     'premium', 9000, 0.1,  0.225, 0.6,  10,  true)
on conflict (id) do update set name = excluded.name, flavor = excluded.flavor, sort = excluded.sort, grp = excluded.grp,
  tier = excluded.tier, base = excluded.base, size = excluded.size, spread = excluded.spread, elast = excluded.elast,
  ref = excluded.ref, active = true;

-- "Spices" lama -> Lada (palka, gudang, misi aktif, order Bursa)
do $$
begin
  if exists (select 1 from game.commodities where id = 'spices') then
    insert into game.inventory(player_id, item_id, qty)
      select player_id, 'lada', qty from game.inventory where item_id = 'spices' and qty > 0
    on conflict (player_id, item_id) do update set qty = game.inventory.qty + excluded.qty;
    delete from game.inventory where item_id = 'spices';
    insert into game.warehouse(player_id, city_id, commodity_id, qty)
      select player_id, city_id, 'lada', qty from game.warehouse where commodity_id = 'spices' and qty > 0
    on conflict (player_id, city_id, commodity_id) do update set qty = game.warehouse.qty + excluded.qty;
    delete from game.warehouse where commodity_id = 'spices';
    update game.player_missions set commodity_id = 'lada' where commodity_id = 'spices';
    update game.mp_orders set commodity_id = 'lada' where commodity_id = 'spices';
    delete from game.market where commodity_id = 'spices';
    update game.commodities set active = false, name = 'Rempah (lama)' where id = 'spices';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Peran kota per barang: produce (murah, stok banyak) / consume (dicari, mahal) / neutral
-- ---------------------------------------------------------------------
create or replace function game.mkt_roles() returns jsonb
language sql immutable as $$
  select '{
    "sunda_empire": {"produce": ["garam","jackdaniels","jhonnywalker","tools","batik","porselen","silk"],
                     "consume": ["sugar","kopi","kayu_manis","lada","cengkeh","pala","rotan","kayu_jati","gaharu","kayu_cendana","mutiara","emas"]},
    "joungjava":    {"produce": ["beras","sugar","kopi","kayu_jati","batik","keris"],
                     "consume": ["garam","cengkeh","besi","tools"]},
    "bjorneo":      {"produce": ["lada","pala","rotan","tuak","sarang_walet","gaharu","emas"],
                     "consume": ["beras","ikan_asin","garam","tools","batik","mesiu","arms"]},
    "skitraw":      {"produce": ["ikan_asin","garam","rum","kayu_manis"],
                     "consume": ["sugar","kopi","lada","silk","porselen","rotan","sarang_walet","jhonnywalker","keris","kayu_cendana","mutiara","emas","arms"]},
    "toogood":      {"produce": ["rum","mesiu","arms"],
                     "consume": ["beras","tuak","besi","jackdaniels","keris"]},
    "ikn":          {"produce": ["besi"],
                     "consume": ["beras","ikan_asin","rum","kayu_manis","pala","kayu_jati","tools","mesiu","arms"]},
    "paradiso":     {"produce": ["tuak","cengkeh","kayu_cendana","mutiara"],
                     "consume": ["rum","silk","porselen","batik","sarang_walet","jackdaniels","jhonnywalker","gaharu","emas"]}
  }'::jsonb
$$;

-- Semua kota memperdagangkan semua barang aktif (stok berbeda-beda)
insert into game.market(city_id, commodity_id, base_price, current_price, role)
select ci.city_id, co.id, co.base, co.base,
  case when game.mkt_roles() -> ci.city_id -> 'produce' ? co.id then 'produce'
       when game.mkt_roles() -> ci.city_id -> 'consume' ? co.id then 'consume' else 'neutral' end
from game.cities ci cross join game.commodities co
where co.active
on conflict (city_id, commodity_id) do update set base_price = excluded.base_price, role = excluded.role;

-- Konfigurasi bawaan (cfg_num memakai nilai default bila belum ada di game.config)
--   MarketTauMinutes 26 | MarketCycleMinutes 60 | MarketProduceFactor 1.5 | MarketConsumeFactor 0.65
--   PremiumProduceMul 0.8 | PremiumConsumeMul 1.25 (pengali harga barang premium menurut peran kota)
--   MarketWantedMult 0.4 | MarketSurplusMult 1.8 | MarketPriceFloor 0.35 | MarketPriceCeil 3
--   PremiumBatchFrac 0.4 | PremiumCapFrac 1.2

-- ---------------------------------------------------------------------
-- Ukuran palka & ruang terpakai
-- ---------------------------------------------------------------------
create or replace function game.commodity_size(p_id text) returns numeric
language sql stable as $$ select coalesce((select size from game.commodities where id = p_id), 1) $$;

create or replace function game.cargo_used(p_pid uuid) returns numeric
language sql stable as $$
  select coalesce((select sum(i.qty * c.size) from game.inventory i join game.commodities c on c.id = i.item_id
                    where i.player_id = p_pid and i.qty > 0), 0)
       + coalesce((select sum(m.loaded_qty * coalesce(c.size, 1)) from game.player_missions m
                    left join game.commodities c on c.id = m.commodity_id
                    where m.player_id = p_pid and m.status = 'active' and coalesce(m.type, '') in ('courier', 'procure')), 0)
$$;

create or replace function game.cargo_free(p_pid uuid) returns numeric
language sql stable as $$ select coalesce(game.effective_cargo(p_pid), 0) - game.cargo_used(p_pid) $$;

-- ---------------------------------------------------------------------
-- Mesin stok
-- ---------------------------------------------------------------------
create or replace function game.mkt_cycle_index() returns bigint
language sql stable as $$ select floor(game.now_ms() / (greatest(1, game.cfg_num('MarketCycleMinutes', 60)) * 60000))::bigint $$;

create or replace function game.mkt_cycle_ends_ms() returns bigint
language sql stable as $$
  select ((game.mkt_cycle_index() + 1) * greatest(1, game.cfg_num('MarketCycleMinutes', 60)) * 60000)::bigint - game.now_ms()
$$;

-- Kabar Pasar siklus ini: {"wanted": [2 barang], "surplus": [1 barang]} - deterministik per kota & siklus
create or replace function game.mkt_cycle_tags(p_city text, p_cyc bigint) returns jsonb
language sql stable as $$
  with g as (
    select c.id, row_number() over (order by md5(p_city || ':' || p_cyc || ':' || c.id)) rn
    from game.commodities c
    where c.active and c.tier <> 'premium'
  )
  select jsonb_build_object(
    'wanted', coalesce((select jsonb_agg(id order by rn) from g where rn <= 2), '[]'::jsonb),
    'surplus', coalesce((select jsonb_agg(id) from g where rn = 3), '[]'::jsonb))
$$;

-- Tingkat stok alami (E)
create or replace function game.mkt_eq(p_role text, p_tier text, p_ref numeric, p_id text, p_tags jsonb) returns numeric
language sql stable as $$
  select case
    when p_tier = 'premium' then
      case p_role when 'produce' then p_ref * game.cfg_num('PremiumCapFrac', 1.2) else 0 end
    else
      p_ref * case p_role when 'produce' then game.cfg_num('MarketProduceFactor', 1.5)
                          when 'consume' then game.cfg_num('MarketConsumeFactor', 0.65) else 1 end
            * case when p_tags -> 'wanted' ? p_id then game.cfg_num('MarketWantedMult', 0.4)
                   when p_tags -> 'surplus' ? p_id then game.cfg_num('MarketSurplusMult', 1.8) else 1 end
  end
$$;

-- Stok terproyeksi sekarang (tanpa menulis)
create or replace function game.mkt_project(p_stock numeric, p_at timestamptz, p_cyc bigint, p_role text, p_tier text,
  p_ref numeric, p_id text, p_tags jsonb, p_cyc_now bigint) returns numeric
language plpgsql stable as $$
declare eq numeric := game.mkt_eq(p_role, p_tier, p_ref, p_id, p_tags); dt double precision; tau double precision; s numeric;
  cap numeric; batch numeric;
begin
  if p_stock is null then return eq; end if;
  -- barang premium di kota non-produsen: tidak tumbuh lagi, hanya dikonsumsi pelan
  dt := greatest(0, extract(epoch from (now() - p_at)) / 60.0);
  tau := greatest(1, game.cfg_num('MarketTauMinutes', 26));
  if p_tier = 'premium' and p_role = 'produce' then
    cap := eq;
    batch := ceil(p_ref * game.cfg_num('PremiumBatchFrac', 0.4));
    s := p_stock;
    if s > cap then s := cap + (s - cap) * exp(-dt / tau)::numeric; end if;   -- kelebihan diserap pelan
    if p_cyc is not null and p_cyc_now > p_cyc then s := least(greatest(s, 0) + batch * (p_cyc_now - p_cyc), greatest(s, cap)); end if;
    return round(greatest(0, s), 3);
  end if;
  return round(greatest(0, eq + (p_stock - eq) * exp(-dt / tau)::numeric), 3);
end $$;

-- Harga tengah satu unit pada tingkat stok s
create or replace function game.mkt_mid(p_base numeric, p_ref numeric, p_elast numeric, p_stock numeric) returns double precision
language sql immutable as $$
  select p_base::double precision * least(3, greatest(0.35,
    power(((p_ref * 1.4)::double precision) / (greatest(0, p_stock) + p_ref * 0.4)::double precision, p_elast::double precision)))
$$;

-- Barang premium: pengali harga menurut peran kota + "stok bayangan" di kota non-produsen
-- (kota konsumen tetap membeli dengan harga wajar walau stoknya kosong).
create or replace function game.mkt_role_mul(p_role text, p_tier text) returns double precision
language sql stable as $$
  select case when p_tier <> 'premium' then 1
    when p_role = 'produce' then game.cfg_num('PremiumProduceMul', 0.8)
    when p_role = 'consume' then game.cfg_num('PremiumConsumeMul', 1.25) else 1 end::double precision
$$;
create or replace function game.mkt_phantom(p_role text, p_tier text, p_ref numeric) returns numeric
language sql immutable as $$
  select case when p_tier <> 'premium' or p_role = 'produce' then 0 when p_role = 'consume' then p_ref * 0.6 else p_ref end
$$;
-- Harga tengah satu unit untuk baris pasar (peran & tier diperhitungkan)
create or replace function game.mkt_mid2(p_base numeric, p_ref numeric, p_elast numeric, p_stock numeric, p_role text, p_tier text)
returns double precision language sql stable as $$
  select game.mkt_mid(p_base, p_ref, p_elast, p_stock + game.mkt_phantom(p_role, p_tier, p_ref)) * game.mkt_role_mul(p_role, p_tier)
$$;

-- Perbarui stok satu kota (dipanggil saat pasar dibuka)
create or replace function game.mkt_refresh(p_city text) returns void
language plpgsql as $$
declare v_cyc bigint := game.mkt_cycle_index(); v_tags jsonb := game.mkt_cycle_tags(p_city, game.mkt_cycle_index());
begin
  update game.market m
     set stock = game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, v_tags, v_cyc),
         at = now(), cyc = v_cyc,
         current_price = greatest(1, round(game.mkt_mid2(c.base, c.ref, c.elast,
           game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, v_tags, v_cyc), m.role, c.tier)))::int
    from game.commodities c
   where c.id = m.commodity_id and m.city_id = p_city and c.active;
end $$;

-- Kunci & perbarui satu baris pasar, kembalikan stok sekarang
create or replace function game.mkt_lock(p_city text, p_comm text) returns numeric
language plpgsql as $$
declare m game.market; c game.commodities; v_cyc bigint := game.mkt_cycle_index(); s numeric;
begin
  select * into m from game.market where city_id = p_city and commodity_id = p_comm for update;
  if not found then return null; end if;
  select * into c from game.commodities where id = p_comm;
  if not found or not c.active then return null; end if;
  s := game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, game.mkt_cycle_tags(p_city, v_cyc), v_cyc);
  update game.market set stock = s, at = now(), cyc = v_cyc where city_id = p_city and commodity_id = p_comm;
  return s;
end $$;

-- Pengali harga khusus pemain (Tide v23): skill MEMPERSEMPIT selisih beli/jual.
--   setengah selisih h = spread/2. Pemula membeli di mid*(1+h) dan menjual di mid*(1-h).
--   Trading (+ buku Smuggler) & Reputasi memangkas sisi beli; Negotiation & Reputasi memangkas sisi jual.
--   Tiap 1% bonus lama = 4% potongan selisih (Trading 100 = 10% -> 40%), total per sisi maks 80%.
--   Harga beli selalu > harga jual -> beli lalu jual lagi di kota yang sama selalu rugi (tanpa batas 97%),
--   dan makin tinggi skill makin untung (tidak bisa terbalik).
-- Senjata murah di TooGood = harga lokal 20% lebih murah (lewat ev_mul), bukan diskon pribadi.
create or replace function game.eco2_muls(p_pid uuid, p_city text, p_comm text, out buy_mul double precision, out sell_mul double precision,
  out ev_mul double precision)
language plpgsql stable as $$
declare s game.character_stats; trading double precision := 0; nego double precision := 0; rep double precision;
  sp double precision; ev int := 0; kb double precision; ks double precision;
begin
  select * into s from game.character_stats where player_id = p_pid;
  if found then trading := game.eco_stat_bonus(s.trading); nego := game.eco_stat_bonus(s.negotiation); end if;
  rep := game.eco_rep_bonus(p_pid, p_city);
  kb := least(0.8, greatest(0, (trading + game.eco_black_market_extra(p_pid) + rep) / 25));
  ks := least(0.8, greatest(0, (nego + rep) / 25));
  sp := coalesce((select spread from game.commodities where id = p_comm), 0.15)::double precision;
  buy_mul := 1 + sp / 2 * (1 - kb);
  sell_mul := 1 - sp / 2 * (1 - ks);
  begin ev := coalesce(game.event_price_pct(p_city), 0); exception when others then ev := 0; end;
  ev_mul := (1 + ev::double precision / 100) * (1 - game.eco_arms_discount(p_city, p_comm) / 100);
end $$;

create or replace function game.eco2_buy_cost(p_base numeric, p_ref numeric, p_elast numeric, p_stock numeric, p_qty bigint, p_mul double precision,
  p_role text, p_tier text)
returns bigint language sql stable as $$
  select coalesce(sum(greatest(1, round(game.mkt_mid2(p_base, p_ref, p_elast, p_stock - i - 0.5, p_role, p_tier) * p_mul))), 0)::bigint
  from generate_series(0, p_qty - 1) i
$$;

create or replace function game.eco2_sell_value(p_base numeric, p_ref numeric, p_elast numeric, p_stock numeric, p_qty bigint, p_mul double precision,
  p_role text, p_tier text)
returns bigint language sql stable as $$
  select coalesce(sum(greatest(1, round(game.mkt_mid2(p_base, p_ref, p_elast, p_stock + i + 0.5, p_role, p_tier) * p_mul))), 0)::bigint
  from generate_series(0, p_qty - 1) i
$$;

-- Harga beli unit pertama (kontrak lama; dipakai misi Pesanan) - tanpa menulis
create or replace function game.quote_buy(p_pid uuid, p_city text, p_commodity text) returns int
language plpgsql stable as $$
declare m game.market; c game.commodities; mu record; s numeric; cyc bigint := game.mkt_cycle_index();
begin
  select * into m from game.market where city_id = p_city and commodity_id = p_commodity;
  if not found then return 0; end if;
  select * into c from game.commodities where id = p_commodity and active;
  if not found then return 0; end if;
  s := game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, game.mkt_cycle_tags(p_city, cyc), cyc);
  select * into mu from game.eco2_muls(p_pid, p_city, p_commodity);
  return greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast, s - 0.5, m.role, c.tier) * mu.buy_mul))::int;
end $$;

-- Misi Pesanan mengambil stok sungguhan
create or replace function game.market_take(p_city text, p_comm text, p_qty int) returns void
language plpgsql as $$
declare s numeric;
begin
  s := game.mkt_lock(p_city, p_comm);
  if s is null then raise exception 'Barang ini tidak dijual di kota ini.'; end if;
  if floor(s) < p_qty then raise exception 'Stok % di pasar tinggal % unit - tunggu pasar terisi lagi.', game.commodity_name(p_comm), floor(s); end if;
  update game.market set stock = stock - p_qty where city_id = p_city and commodity_id = p_comm;
end $$;

-- ---------------------------------------------------------------------
-- Endpoint pasar
-- ---------------------------------------------------------------------
create or replace function public.api_getMarket(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_me game.players; pid uuid; r record; mu record; items jsonb := '[]'::jsonb;
  cyc bigint; tags jsonb; base_ev double precision; bp bigint; sp bigint;
begin
  v_me := game.me(false); pid := v_me.player_id;
  if not exists (select 1 from game.cities where city_id = v_city) then raise exception 'Kota tidak dikenal.'; end if;
  perform game.mkt_refresh(v_city);
  cyc := game.mkt_cycle_index(); tags := game.mkt_cycle_tags(v_city, cyc);
  for r in select m.commodity_id, m.role, m.stock, c.* from game.market m join game.commodities c on c.id = m.commodity_id
            where m.city_id = v_city and c.active order by c.sort, c.id loop
    select * into mu from game.eco2_muls(pid, v_city, r.commodity_id);
    base_ev := r.base * mu.ev_mul;
    -- harga unit berikutnya: beli di titik stok s-0.5, jual di s+0.5 (pulang-pergi selalu kena selisih)
    bp := greatest(1, round(game.mkt_mid2(base_ev::numeric, r.ref, r.elast, r.stock - 0.5, r.role, r.tier) * mu.buy_mul));
    sp := greatest(1, round(game.mkt_mid2(base_ev::numeric, r.ref, r.elast, r.stock + 0.5, r.role, r.tier) * mu.sell_mul));
    items := items || jsonb_build_array(jsonb_build_object(
      'commodityId', r.commodity_id, 'name', r.name, 'flavor', r.flavor,
      'group', r.grp, 'tier', r.tier, 'size', r.size, 'role', r.role,
      'tag', case when tags -> 'wanted' ? r.commodity_id then 'wanted' when tags -> 'surplus' ? r.commodity_id then 'surplus' end,
      'stock', floor(r.stock)::int, 'refStock', r.ref,
      'buyPrice', bp, 'sellPrice', sp,
      'basePrice', r.base,
      'priceRatio', game.eco_round(game.mkt_mid2(base_ev::numeric, r.ref, r.elast, r.stock, r.role, r.tier) / r.base * 100),
      'curve', jsonb_build_object('base', round((base_ev * game.mkt_role_mul(r.role, r.tier))::numeric, 3), 'ref', r.ref, 'e', r.elast,
                                  'ph', game.mkt_phantom(r.role, r.tier, r.ref),
                                  'buyMul', round(mu.buy_mul::numeric, 5), 'sellMul', round(mu.sell_mul::numeric, 5), 's', round(r.stock::numeric, 3)),
      'ownedQty', coalesce((select i.qty from game.inventory i where i.player_id = pid and i.item_id = r.commodity_id and i.qty > 0), 0),
      'avgCost', game.inv_avg_cost(pid, r.commodity_id)));
  end loop;
  return jsonb_build_object('items', items, 'closed', game.ww_market_closed(pid),
    'cargoSpaceRemaining', trim_scale(greatest(0, game.cargo_free(pid))),
    'cargoUsed', trim_scale(game.cargo_used(pid)), 'cargoCapacity', coalesce(game.effective_cargo(pid), 0),
    'cycle', jsonb_build_object('index', cyc, 'endsInMs', game.mkt_cycle_ends_ms(),
      'wanted', tags -> 'wanted', 'surplus', tags -> 'surplus'));
end $$;
select game.expose('api_getmarket');

create or replace function public.api_buy(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; c game.commodities; mu record; s numeric; total bigint; need numeric; free numeric; v_role text;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah beli tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  perform game.eco_require_trade_here(pid, v_city);
  select * into c from game.commodities where id = v_comm and active;
  if not found then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;
  s := game.mkt_lock(v_city, v_comm);
  if s is null then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;
  if floor(s) < v_qty then
    raise exception 'Stok % di pasar ini tinggal % unit.', c.name, floor(s);
  end if;
  select * into mu from game.eco2_muls(pid, v_city, v_comm);
  select role into v_role from game.market where city_id = v_city and commodity_id = v_comm;
  total := game.eco2_buy_cost((c.base * mu.ev_mul)::numeric, c.ref, c.elast, s, v_qty, mu.buy_mul, v_role, c.tier);
  if v_me.gold < total then
    raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', total, v_me.gold;
  end if;
  need := v_qty * c.size; free := game.cargo_free(pid);
  if need > free then
    raise exception 'Kapasitas cargo tidak cukup. Butuh % ruang, sisa %.', trim_scale(need), trim_scale(greatest(0, free));
  end if;

  update game.players set gold = gold - total where player_id = pid;
  perform game.adjust_inventory(pid, v_comm, v_qty::int);
  perform game.inv_add_cost(pid, v_comm, v_qty::int, total);
  update game.market set stock = stock - v_qty where city_id = v_city and commodity_id = v_comm;

  perform game.log(pid, 'Bought ' || v_qty || ' unit' || case when v_qty > 1 then 's' else '' end || ' of ' ||
    c.name || ' for ' || total || ' gold.');
  return jsonb_build_object('totalCost', total, 'unitPrice', game.eco_round(total::double precision / v_qty),
    'newGold', v_me.gold - total, 'stockLeft', floor(s - v_qty), 'avgCost', game.inv_avg_cost(pid, v_comm),
    'nextBuyPrice', greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast, s - v_qty - 0.5, v_role, c.tier) * mu.buy_mul)));
end $$;
select game.expose('api_buy');

create or replace function public.api_sell(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_me game.players; pid uuid; c game.commodities; mu record; s numeric; revenue bigint; have int; v_role text; v_avg numeric;
begin
  if v_qty is null or v_qty <= 0 then raise exception 'Jumlah jual tidak valid.'; end if;
  v_me := game.me(true); pid := v_me.player_id;
  perform game.eco_require_trade_here(pid, v_city);
  select * into c from game.commodities where id = v_comm;
  if not found then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;
  select qty into have from game.inventory where player_id = pid and item_id = v_comm;
  if have is null then raise exception 'Kamu tidak punya cargo ini untuk dijual.'; end if;
  if have < v_qty then raise exception 'Barang di palka tidak cukup (punya %).', have; end if;
  s := game.mkt_lock(v_city, v_comm);
  if s is null then raise exception 'Komoditas tidak tersedia di kota ini.'; end if;
  select * into mu from game.eco2_muls(pid, v_city, v_comm);
  select role into v_role from game.market where city_id = v_city and commodity_id = v_comm;
  revenue := game.eco2_sell_value((c.base * mu.ev_mul)::numeric, c.ref, c.elast, s, v_qty, mu.sell_mul, v_role, c.tier);
  v_avg := game.inv_avg_cost(pid, v_comm);

  perform game.adjust_inventory(pid, v_comm, (-v_qty)::int);
  update game.market set stock = stock + v_qty where city_id = v_city and commodity_id = v_comm;
  update game.players set gold = gold + revenue where player_id = pid;
  perform game.log(pid, 'Sold ' || v_qty || ' unit' || case when v_qty > 1 then 's' else '' end || ' of ' ||
    c.name || ' for ' || revenue || ' gold.');
  return jsonb_build_object('totalRevenue', revenue,
    'costBasis', case when v_avg is not null then round(v_avg * v_qty) end,
    'profit', case when v_avg is not null then revenue - round(v_avg * v_qty) end,
    'unitPrice', game.eco_round(revenue::double precision / v_qty),
    'newGold', v_me.gold + revenue,
    'nextSellPrice', greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast, s + v_qty + 0.5, v_role, c.tier) * mu.sell_mul)));
end $$;
select game.expose('api_sell');
