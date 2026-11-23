-- =====================================================================
-- Marantau - 0096 BATAS HARIAN PETA HARTA  (perbaikan exploit galian massal)
-- ---------------------------------------------------------------------
-- Masalah: beli Peta Sarang Lama (800 gold) -> gali -> jual artifact bernilai rata-rata > harga peta,
-- tanpa batas harian. Diotomatisasi puluhan ribu kali sehari (+27 jt gold bersih satu akun).
--
-- Aturan baru (hari = tanggal WIB, reset 00:00 WIB):
--   1. Beli peta maks TreasureBuyPerDay (5) per pemain per hari. Peta dari drop tidak dihitung.
--   2. Galian per LOKASI: setelah TreasureDigFreePerSite (30) galian hari ini di lokasi itu,
--      galian berikutnya tidak lagi memberi hadiah: pemain justru KEHILANGAN gold (upah penggali,
--      sebesar kisaran "sisa harta sederhana", tidak bisa membuat gold < 0). Tanpa artifact, tanpa
--      kerusakan kapal. Peta tetap habis terpakai. Hasil 'terkuras' tidak menambah tantangan harian 'dig'.
--
-- api_buyTreasureMap & api_digTreasure di sini menggantikan versi 0004 (migrasi diulang berurutan).
-- Aman diulang. Angka bisa diubah lewat game.config tanpa deploy.
-- =====================================================================

create table if not exists game.treasure_daily (
  player_id uuid not null,
  hari      date not null,
  beli      int  not null default 0,
  gali      jsonb not null default '{}'::jsonb,     -- { site_id: jumlah galian hari ini }
  primary key (player_id, hari)
);
alter table game.treasure_daily enable row level security;

insert into game.config(key, value) values
  ('TreasureBuyPerDay', '5'),
  ('TreasureDigFreePerSite', '30')
on conflict (key) do nothing;

create or replace function game.treasure_hari() returns date
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

-- ---------------------------------------------------------------------
-- Beli peta: maks N per hari (slot diambil atomik di satu pernyataan)
-- ---------------------------------------------------------------------
create or replace function public.api_buyTreasureMap(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_item text := game.arg(a, 0);
  v_me   game.players := game.me(true);
  v_pid  uuid := v_me.player_id;
  it     game.item_catalog;
  v_price bigint;
  v_cap  int := greatest(0, game.cfg_num('TreasureBuyPerDay', 5))::int;
  v_got  int;
begin
  it := game.item(v_item);
  if it.item_id is null or it.type <> 'treasure_map' then raise exception 'Item ini bukan treasure map.'; end if;
  if coalesce(it.price, 0) <= 0 then raise exception 'Peta ini tidak dijual di sini.'; end if;
  v_price := it.price;
  if v_me.gold < v_price then
    raise exception 'Gold tidak cukup - butuh %, kamu punya %.', v_price, v_me.gold;
  end if;
  if v_cap <= 0 then
    raise exception 'Pedagang peta sedang tidak berjualan, Kapten.';
  end if;
  insert into game.treasure_daily as t (player_id, hari, beli) values (v_pid, game.treasure_hari(), 1)
  on conflict (player_id, hari) do update set beli = t.beli + 1 where t.beli < v_cap
  returning t.beli into v_got;
  if v_got is null then
    raise exception 'Pedagang peta hanya melayani % peta per hari, Kapten. Datang lagi besok (reset 00:00 WIB).', v_cap;
  end if;
  update game.players set gold = gold - v_price where player_id = v_pid;
  perform game.item_adjust(v_pid, v_item, 1);
  perform game.log(v_pid, 'Bought "' || it.name || '" for ' || v_price || ' gold.');
  return jsonb_build_object('newGold', v_me.gold - v_price, 'itemId', v_item, 'name', it.name);
end $$;
select game.expose('api_buytreasuremap');

-- ---------------------------------------------------------------------
-- Gali: setelah N galian per lokasi per hari, hasilnya minus
-- ---------------------------------------------------------------------
create or replace function public.api_digTreasure(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_item   text := game.arg(a, 0);
  v_me     game.players := game.me(true);
  v_pid    uuid := v_me.player_id;
  it       game.item_catalog;
  s        game.treasure_sites;
  v_dec    boolean;
  v_base   numeric := game.cfg_num('TreasureDigBaseGold', 350);
  v_free   int := greatest(0, game.cfg_num('TreasureDigFreePerSite', 30))::int;
  v_n      int;
  v_mult   numeric;
  w        int[];
  v_roll   double precision;
  v_out    text;
  v_gold   bigint := 0;
  v_cond   bigint := 0;
  v_grant  boolean := false;
  v_newgold bigint := v_me.gold;
  v_art    game.item_catalog;
  v_granted jsonb := null;
  v_newcond numeric := null;
  v_msg    text;
begin
  it := game.item(v_item);
  if it.item_id is null or it.type <> 'treasure_map' then raise exception 'Item ini bukan treasure map.'; end if;
  if game.item_qty(v_pid, v_item) < 1 then raise exception 'Kamu tidak punya peta ini.'; end if;
  s := game.treasure_site(case when jsonb_typeof(it.effects) = 'object' then it.effects ->> 'siteId' end);
  if s.id is null then raise exception 'Lokasi di peta ini tidak dikenali - peta rusak.'; end if;
  if game.in_transit(v_pid) then
    raise exception 'Kamu sedang berlayar - merapat dulu sebelum menggali.';
  end if;
  if game.current_city(v_pid) is distinct from s.city_id then
    raise exception 'Peta ini menunjuk ke lokasi dekat % - berlayar ke sana dulu.', game.city_name(s.city_id);
  end if;

  -- hitung galian hari ini di lokasi ini (atomik)
  insert into game.treasure_daily as t (player_id, hari, gali) values (v_pid, game.treasure_hari(), jsonb_build_object(s.id, 1))
  on conflict (player_id, hari) do update
    set gali = jsonb_set(t.gali, array[s.id], to_jsonb(coalesce((t.gali ->> s.id)::int, 0) + 1))
  returning (t.gali ->> s.id)::int into v_n;

  v_mult := s.difficulty;
  if v_n > v_free then
    -- lokasi terkuras: hadiah jadi minus (upah penggali), tanpa artifact & tanpa kerusakan kapal
    v_out := 'terkuras';
    v_gold := -game.js_round((v_base * v_mult)::double precision * (0.3 + random() * 0.5));
  else
    -- rollDigOutcome_: bobot [big_gold, rare_item, small_gold, false_map]
    v_dec := game.book_has_effect(v_pid, s.requires_book_keyword);
    w := case when v_dec then array[30, 20, 40, 10] else array[12, 8, 45, 35] end;
    v_roll := random() * 100;
    if v_roll < w[1] then v_out := 'big_gold';
    elsif v_roll < w[1] + w[2] then v_out := 'rare_item';
    elsif v_roll < w[1] + w[2] + w[3] then v_out := 'small_gold';
    else v_out := 'false_map';
    end if;

    if v_out = 'big_gold' then
      v_gold := game.js_round((v_base * v_mult)::double precision * (1.6 + random() * 1.2));
    elsif v_out = 'rare_item' then
      v_gold := game.js_round((v_base * v_mult)::double precision * (0.6 + random() * 0.4));
      v_grant := true;
    elsif v_out = 'small_gold' then
      v_gold := game.js_round((v_base * v_mult)::double precision * (0.3 + random() * 0.5));
    else
      v_cond := -game.js_round((8 + random() * 10) * least(3, greatest(1, v_mult))::double precision);
    end if;
  end if;

  -- Peta HABIS terpakai apapun hasilnya
  perform game.item_adjust(v_pid, v_item, -1);
  if v_out <> 'terkuras' then
    perform game.hr_hook(v_pid, 'dig', 1, jsonb_build_object('outcome', v_out));   -- v37
  end if;

  if v_gold <> 0 then
    v_newgold := greatest(0, v_me.gold + v_gold);
    v_gold := v_newgold - v_me.gold;                     -- potongan nyata (gold tidak bisa < 0)
    update game.players set gold = v_newgold where player_id = v_pid;
  end if;

  if v_grant then
    select * into v_art from game.item_catalog where type = 'artifact' and coalesce(source, '') <> 'quest' order by random() limit 1;
    if found then
      perform game.item_adjust(v_pid, v_art.item_id, 1);
      v_granted := jsonb_build_object('itemId', v_art.item_id, 'name', v_art.name);
    end if;
  end if;

  if v_cond <> 0 then
    v_newcond := game.apply_condition_delta(v_pid, v_cond);
  end if;

  -- buildDigMessage_
  v_msg := case v_out
    when 'big_gold' then 'Galian di ' || s.name || ' membuahkan hasil besar - ' || v_gold || ' gold ditemukan terkubur.'
    when 'rare_item' then case when v_granted is not null
      then 'Galian di ' || s.name || ' menemukan ' || v_gold || ' gold DAN sebuah artifact: "' || (v_granted ->> 'name') || '"!'
      else 'Galian di ' || s.name || ' menemukan ' || v_gold || ' gold.' end
    when 'small_gold' then 'Galian di ' || s.name || ' menemukan sisa harta sederhana - ' || v_gold || ' gold.'
    when 'terkuras' then 'Galian di ' || s.name || ' sudah terlalu sering hari ini (lebih dari ' || v_free ||
      ' kali). Tanahnya tinggal sisa; penggali sewaan menagih ' || (-v_gold) || ' gold dan tidak ada harta ditemukan.'
    else 'Peta ternyata jebakan - galian di ' || s.name || ' memicu perangkap tua, kapal sedikit rusak (' ||
      v_cond || ' Condition), tidak ada harta ditemukan.' end;
  perform game.log(v_pid, v_msg);

  return jsonb_build_object(
    'outcome', v_out,
    'message', v_msg,
    'goldDelta', v_gold,
    'newGold', v_newgold,
    'grantedItem', v_granted,
    'conditionDelta', v_cond,
    'newCondition', coalesce(to_jsonb(v_newcond), game.ship_json(v_pid) -> 'Condition'));
end $$;
select game.expose('api_digtreasure');
