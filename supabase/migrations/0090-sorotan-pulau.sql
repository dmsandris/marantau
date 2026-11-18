-- =====================================================================
-- 0090 · Tide v71 — Sorotan Pulau (hanya server, tanpa UI, tanpa berita)
--
--   * Tiap HARI GAME satu pulau "disorot". Efeknya hanya terasa lewat pasar:
--       - batch premium pulau itu x1,5 s/d x2,0 (kelipatan 0,1, tetap bergaris batas stok);
--       - harga beli DAN jual 2-4 komoditas pulau itu naik 5-25%.
--     Tidak ada lencana, banner, pesan, log, atau kolom baru di API. Pemain menemukannya sendiri.
--   * Slot TERPISAH dari event acak: tidak menyentuh game.city_events dan game.city_event(),
--     jadi event acak (1 per kota) dan Sorotan tidak saling memblokir; efek harga keduanya berlipat.
--   * Pulau dipilih deterministik dari nomor hari + garam rahasia (config SorotanGaram, acak
--     saat pertama dipasang, tidak ada di repo): putaran adil (semua pulau berdagang kena sekali
--     per putaran) dan tidak pernah dua hari berturut-turut di pulau yang sama.
--     Pulau layak = punya baris pasar dan bukan titik laut quest (spot_city).
--   * Tanpa tabel & tanpa pekerjaan terjadwal: semuanya fungsi murni dari jam dunia.
--   * Saklar: game.config SorotanAktif = 0 mematikan semuanya seketika.
--   * Pemilik/GM bisa mengintip jadwal lewat game.sorotan_jadwal() (hanya jalur SQL/connector;
--     schema game tidak terbuka untuk pemain).
--   * Sekali jalan: event Skitraw yang macet (Gelombang Badai +22% s/d hari 849) diakhiri.
--
-- Catatan teknis:
--   - Batch dibawa lewat "kartu siklus" (mkt_cycle_tags -> kunci 'sorot' berisi pengali 4 siklus
--     terakhir), jadi semua pemanggil mkt_project yang ada tidak perlu diubah. Siklus pasar
--     60 menit tidak sejajar dengan hari game (180 menit): siklus dihitung ke hari game tempat
--     siklus itu DIMULAI.
--   - Harga lewat eco2_muls_inti (ev_mul), jadi ikut ke beli, jual, Hak Lot, dan tampilan pasar.
-- Aman diulang (idempoten).
-- =====================================================================

insert into game.config(key, value) values
  ('SorotanAktif', '1'),
  ('SorotanBatchMin', '1.5'), ('SorotanBatchMax', '2'),
  ('SorotanHargaMin', '5'), ('SorotanHargaMax', '25'),
  ('SorotanKomMin', '2'), ('SorotanKomMax', '4'),
  ('SorotanGaram', md5(random()::text || clock_timestamp()::text))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1) Akhiri event Skitraw yang macet (berlaku sekali; syarat kedaluwarsa jauh di atas durasi normal)
-- ---------------------------------------------------------------------
do $$
begin
  if game.cfg('WorldStartTimestamp') is null then return; end if;   -- basis kosong (tes awal)
  update game.city_events
     set expires_game_day = game.game_day() - 1
   where city_id = 'skitraw' and event_type = 'storm_surge'
     and expires_game_day > game.game_day() + greatest(10, game.cfg_num('WorldEventMaxDurationDays', 5)::int * 2);
end $$;

-- ---------------------------------------------------------------------
-- 2) Jadwal Sorotan (fungsi murni)
-- ---------------------------------------------------------------------

-- Angka acak deterministik 0 <= u < 1 dari (garam, hari, label)
create or replace function game.sorotan_u(p_day int, p_tag text) returns numeric
language sql stable as $$
  select ('x' || substr(md5(coalesce(game.cfg('SorotanGaram'), 'garam') || '|' || p_day::text || '|' || p_tag), 1, 8))::bit(32)::bigint / 4294967296.0
$$;

-- Pulau yang disorot pada hari game p_day (null bila dimatikan).
-- Putaran n hari (n = jumlah pulau layak): tiap putaran mengocok urutan pulau dengan garam;
-- bila pulau pertama putaran ini sama dengan terakhir putaran lalu, dua pulau pertama ditukar.
create or replace function game.sorotan_kota(p_day int) returns text
language plpgsql stable as $$
declare ids text[]; n int; r int; k int; a text[]; b text[]; g text;
begin
  if coalesce(game.cfg_num('SorotanAktif', 1), 1) = 0 then return null; end if;
  select array_agg(c.city_id order by c.city_id) into ids
    from game.cities c
   where exists (select 1 from game.market m where m.city_id = c.city_id)
     and not game.spot_city(c.city_id);
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then return null; end if;
  g := coalesce(game.cfg('SorotanGaram'), 'garam');
  r := floor(p_day::numeric / n)::int;
  k := p_day - r * n;
  a := array(select x from unnest(ids) x order by md5(g || ':' || r::text || ':' || x), x);
  if k <= 1 and n >= 3 then
    b := array(select x from unnest(ids) x order by md5(g || ':' || (r - 1)::text || ':' || x), x);
    if a[1] = b[n] then a := array[a[2], a[1]] || a[3:n]; end if;
  end if;
  return a[k + 1];
end $$;

-- Pengali batch premium hari itu (SorotanBatchMin..Max, kelipatan 0,1)
create or replace function game.sorotan_batch(p_day int) returns numeric
language plpgsql stable as $$
declare lo numeric := game.cfg_num('SorotanBatchMin', 1.5); hi numeric; n int;
begin
  hi := greatest(lo, game.cfg_num('SorotanBatchMax', 2));
  n := floor((hi - lo) * 10)::int + 1;
  return round(lo + floor(game.sorotan_u(p_day, 'batch') * n) / 10.0, 1);
end $$;

-- Komoditas yang harganya naik hari itu: {"komoditas": persen}
create or replace function game.sorotan_harga_map(p_day int) returns jsonb
language plpgsql stable as $$
declare v_city text := game.sorotan_kota(p_day); nmin int; nmax int; cnt int; lo int; hi int; res jsonb;
begin
  if v_city is null then return '{}'::jsonb; end if;
  nmin := greatest(1, game.cfg_num('SorotanKomMin', 2)::int);
  nmax := greatest(nmin, game.cfg_num('SorotanKomMax', 4)::int);
  cnt := nmin + floor(game.sorotan_u(p_day, 'kn') * (nmax - nmin + 1))::int;
  lo := greatest(0, game.cfg_num('SorotanHargaMin', 5)::int);
  hi := greatest(lo, game.cfg_num('SorotanHargaMax', 25)::int);
  select coalesce(jsonb_object_agg(q.id, q.pct), '{}'::jsonb) into res
    from (select m.commodity_id as id,
                 lo + floor(game.sorotan_u(p_day, 'h:' || m.commodity_id) * (hi - lo + 1))::int as pct
            from game.market m join game.commodities c on c.id = m.commodity_id and c.active
           where m.city_id = v_city
           order by game.sorotan_u(p_day, 'r:' || m.commodity_id), m.commodity_id
           limit cnt) q;
  return res;
end $$;

-- Persen kenaikan harga komoditas p_comm di kota p_city SEKARANG (0 bila tidak disorot)
create or replace function game.sorotan_harga(p_city text, p_comm text) returns int
language plpgsql stable as $$
declare d int;
begin
  d := game.game_day();
  if game.sorotan_kota(d) is distinct from p_city then return 0; end if;
  return coalesce((game.sorotan_harga_map(d) ->> p_comm)::int, 0);
end $$;

-- Pengali batch per siklus untuk 4 siklus terakhir sampai p_cyc: {"<siklus>": pengali}; null bila tidak ada
create or replace function game.sorotan_batch_peta(p_city text, p_cyc bigint) returns jsonb
language plpgsql stable as $$
declare cyc_ms numeric; day_ms numeric; start_ms numeric; i int; c bigint; d int;
  last_d int; last_m numeric; res jsonb := '{}'::jsonb;
begin
  if p_city is null or coalesce(game.cfg_num('SorotanAktif', 1), 1) = 0 then return null; end if;
  cyc_ms := greatest(1, game.cfg_num('MarketCycleMinutes', 60)) * 60000;
  day_ms := game.cfg_num('GameDayLengthRealMinutes', 60) * 60000;
  start_ms := game.cfg_num('WorldStartTimestamp', 0);
  if day_ms <= 0 or start_ms = 0 then return null; end if;
  for i in 0..3 loop
    c := p_cyc - i;
    d := floor((c * cyc_ms - start_ms) / day_ms)::int;
    if last_d is distinct from d then
      last_d := d;
      last_m := case when game.sorotan_kota(d) = p_city then game.sorotan_batch(d) end;
    end if;
    if last_m is not null then res := res || jsonb_build_object(c::text, last_m); end if;
  end loop;
  return case when res = '{}'::jsonb then null else res end;
end $$;

-- Intip jadwal (GM/pemilik, lewat SQL): hari game, awal hari (waktu nyata), pulau, pengali batch, harga naik
create or replace function game.sorotan_jadwal(p_dari int default null, p_n int default 12)
returns table (hari_game int, mulai timestamptz, kota text, batch_mul numeric, harga jsonb)
language sql stable as $$
  select d,
         to_timestamp((game.cfg_num('WorldStartTimestamp', 0) + d::numeric * game.cfg_num('GameDayLengthRealMinutes', 60) * 60000) / 1000.0),
         game.sorotan_kota(d), game.sorotan_batch(d), game.sorotan_harga_map(d)
    from generate_series(coalesce(p_dari, game.game_day()), coalesce(p_dari, game.game_day()) + greatest(1, least(60, p_n)) - 1) d
$$;

-- ---------------------------------------------------------------------
-- 3) Kait pasar
-- ---------------------------------------------------------------------

-- Kabar Pasar siklus ini + (bila pulau ini disorot) pengali batch 4 siklus terakhir di kunci 'sorot'
create or replace function game.mkt_cycle_tags(p_city text, p_cyc bigint) returns jsonb
language sql stable as $$
  with g as (
    select c.id, row_number() over (order by md5(p_city || ':' || p_cyc || ':' || c.id)) rn
    from game.commodities c
    where c.active and c.tier <> 'premium'
  ), s as (select game.sorotan_batch_peta(p_city, p_cyc) as peta)
  select jsonb_build_object(
    'wanted', coalesce((select jsonb_agg(id order by rn) from g where rn <= 2), '[]'::jsonb),
    'surplus', coalesce((select jsonb_agg(id) from g where rn = 3), '[]'::jsonb))
    || coalesce((select jsonb_build_object('sorot', peta) from s where peta is not null), '{}'::jsonb)
$$;

-- Stok terproyeksi: batch premium tiap siklus dikalikan pengali Sorotan siklus itu
create or replace function game.mkt_project(p_stock numeric, p_at timestamptz, p_cyc bigint, p_role text, p_tier text,
  p_ref numeric, p_id text, p_tags jsonb, p_cyc_now bigint) returns numeric
language plpgsql stable as $$
declare eq numeric := game.mkt_eq(p_role, p_tier, p_ref, p_id, p_tags); dt double precision; tau double precision; s numeric;
  cap numeric; batch numeric; n bigint; ekstra numeric := 0; i int;
begin
  if p_stock is null then return eq; end if;
  -- barang premium di kota non-produsen: tidak tumbuh lagi, hanya dikonsumsi pelan
  dt := greatest(0, extract(epoch from (now() - p_at)) / 60.0);
  -- Tide v57: pangkat dibatasi 60. exp() Postgres melempar "underflow" bila pangkatnya < ~-708
  -- (baris pasar tak tersentuh ±13 hari). e^-60 sudah ±1e-26, jadi hasil setelah dibulatkan tetap sama.
  tau := greatest(1, game.cfg_num('MarketTauMinutes', 26));
  if p_tier = 'premium' and p_role = 'produce' then
    cap := eq;
    batch := ceil(p_ref * game.cfg_num('PremiumBatchFrac', 0.4));
    s := p_stock;
    if s > cap then s := cap + (s - cap) * exp(-least(dt / tau, 60))::numeric; end if;   -- kelebihan diserap pelan
    if p_cyc is not null and p_cyc_now > p_cyc then
      n := p_cyc_now - p_cyc;
      -- Sorotan Pulau: siklus yang disorot (4 terakhir) dihitung x pengali; siklus lebih lama x1 (stok sudah penuh)
      for i in 0..(least(n, 4)::int - 1) loop
        ekstra := ekstra + coalesce((p_tags -> 'sorot' ->> ((p_cyc_now - i)::text))::numeric, 1) - 1;
      end loop;
      s := least(greatest(s, 0) + batch * (n + ekstra), greatest(s, cap));
    end if;
    return round(greatest(0, s), 3);
  end if;
  return round(greatest(0, eq + (p_stock - eq) * exp(-least(dt / tau, 60))::numeric), 3);
end $$;

-- Harga: ev_mul ditambah kenaikan Sorotan (beli DAN jual). Salinan eco2_muls_inti + satu blok.
create or replace function game.eco2_muls_inti(p_pid uuid, p_city text, p_comm text, out buy_mul double precision, out sell_mul double precision,
  out ev_mul double precision)
language plpgsql stable as $$
declare s game.character_stats; trading double precision := 0; nego double precision := 0; rep double precision; sp double precision;
  ev int := 0; kb double precision; ks double precision; sorot int := 0;
begin
  select * into s from game.character_stats where player_id = p_pid;
  if found then trading := game.eco_stat_bonus(s.trading); nego := game.eco_stat_bonus(s.negotiation); end if;
  rep := game.eco_rep_bonus(p_pid, p_city);
  kb := least(0.8, greatest(0, (trading + game.eco_black_market_extra(p_pid) + rep) / 25));
  ks := least(0.8, greatest(0, (nego + rep) / 25));
  sp := coalesce((select spread from game.commodities where id = p_comm), 0.15)::double precision;
  buy_mul := 1 + sp / 2 * (1 - kb);
  sell_mul := 1 - sp / 2 * (1 - ks);
  -- Tide v34: Jabat Tangan Perak-Emas (artefak terpasang) +10% harga jual di tiga kota, tetap di bawah harga beli
  if p_city in ('sowtour', 'karang_garam', 'joungjava') and coalesce(game.artifact_has_effect(p_pid, 'jabat_tangan'), false) then
    sell_mul := least(buy_mul - 0.01, sell_mul * 1.10);
  end if;
  begin ev := coalesce(game.event_price_pct(p_city), 0); exception when others then ev := 0; end;
  ev_mul := (1 + ev::double precision / 100) * (1 - game.eco_arms_discount(p_city, p_comm) / 100);
  -- Saga 2 (0023): krisis pasar per pemain saat kompas dunia rusak
  ev_mul := ev_mul * coalesce(game.quest_price_mul(p_pid, p_city, p_comm), 1);
  -- Tide v71: Sorotan Pulau (slot terpisah dari event kota di atas; berlipat dengannya)
  begin sorot := coalesce(game.sorotan_harga(p_city, p_comm), 0); exception when others then sorot := 0; end;
  if sorot <> 0 then ev_mul := ev_mul * (1 + sorot::double precision / 100); end if;
end $$;
