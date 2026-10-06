-- =====================================================================
-- Marantau (Supabase) - 0001b INTERFACES
-- ---------------------------------------------------------------------
-- Fungsi "kontrak" antar-modul. Di sini hanya versi PENGGANTI SEMENTARA
-- (stub) yang aman; migrasi modul pemiliknya (lihat PORTING.md) menimpa
-- dengan implementasi asli lewat CREATE OR REPLACE. Tujuannya: setiap
-- modul bisa diuji sendiri tanpa menunggu modul lain.
-- Semua ditulis plpgsql supaya referensi ke tabel modul lain baru
-- diperiksa saat dijalankan.
-- =====================================================================

-- [modul economy / 0002] ----------------------------------------------
-- Tide v21: modal rata-rata (lihat 0020)
alter table game.inventory add column if not exists cost numeric;
alter table game.warehouse add column if not exists cost numeric;

-- Ubah jumlah barang; pengurangan memotong modal secara proporsional.
create or replace function game.adjust_inventory(p_pid uuid, p_item text, p_delta int) returns int
language plpgsql as $$
declare q0 int; q int; c numeric;
begin
  insert into game.inventory(player_id, item_id, qty) values (p_pid, p_item, 0)
  on conflict (player_id, item_id) do nothing;
  select qty, cost into q0, c from game.inventory where player_id = p_pid and item_id = p_item for update;
  q := q0 + p_delta;
  if q < 0 then
    raise exception 'Jumlah cargo tidak boleh negatif.';
  end if;
  update game.inventory set qty = q,
         cost = case when q = 0 then null
                     when p_delta < 0 and c is not null and q0 > 0 then round(c * q / q0, 4)
                     else c end
   where player_id = p_pid and item_id = p_item;
  return q;
end $$;

-- Tambah modal untuk unit yang BARU SAJA masuk (dipanggil sesudah adjust_inventory +qty).
-- Unit lama yang modalnya tidak diketahui dinilai dengan harga unit pembelian ini.
create or replace function game.inv_add_cost(p_pid uuid, p_item text, p_new_qty int, p_amount numeric) returns void
language plpgsql as $$
declare q int; c numeric;
begin
  select qty, cost into q, c from game.inventory where player_id = p_pid and item_id = p_item for update;
  if q is null or p_new_qty <= 0 then return; end if;
  if c is null then c := (q - p_new_qty) * (p_amount / p_new_qty); end if;
  update game.inventory set cost = round(c + p_amount, 4) where player_id = p_pid and item_id = p_item;
end $$;

-- Modal rata-rata per unit (NULL bila tidak diketahui)
create or replace function game.inv_avg_cost(p_pid uuid, p_item text) returns numeric
language sql stable as $$
  select case when i.qty > 0 and i.cost is not null then round(i.cost / i.qty, 2) end
  from game.inventory i where i.player_id = p_pid and i.item_id = p_item
$$;

create or replace function game.cargo_total(p_pid uuid) returns int
language plpgsql stable as $$
declare n int;
begin
  select coalesce(sum(i.qty), 0) into n from game.inventory i join game.commodities c on c.id = i.item_id where i.player_id = p_pid and i.qty > 0;
  return n + coalesce(game.mission_load(p_pid), 0);
end $$;

create or replace function game.reputation_for(p_pid uuid, p_city text) returns int
language plpgsql stable as $$
declare r jsonb;
begin
  select reputation into r from game.players where player_id = p_pid;
  return coalesce((r ->> p_city)::numeric, 0)::int;
exception when others then return 0;
end $$;

create or replace function game.stats_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.character_stats;
begin
  select * into s from game.character_stats where player_id = p_pid;
  if not found then return null; end if;
  return jsonb_build_object('Trading', s.trading, 'Negotiation', s.negotiation, 'Navigation', s.navigation,
    'Sailing', s.sailing, 'Combat', s.combat, 'Luck', s.luck, 'Knowledge', s.knowledge);
end $$;

create or replace function game.quote_buy(p_pid uuid, p_city text, p_commodity text) returns int
language plpgsql stable as $$
declare p int;
begin
  select current_price into p from game.market where city_id = p_city and commodity_id = p_commodity;
  return coalesce(p, 0);
end $$;

create or replace function game.bank_state(p_pid uuid) returns jsonb
language plpgsql as $$
begin
  return jsonb_build_object('bankBalance', 0, 'debtBalance', 0, 'bankRatePercent', 0, 'debtRatePercent', 0, 'maxDebt', 0, 'migrated', true);
end $$;

-- [modul ship/voyage/combat / 0003] -------------------------------------
create or replace function game.current_city(p_pid uuid) returns text
language plpgsql stable as $$
declare c text;
begin
  select city_id into c from game.player_location where player_id = p_pid;
  return coalesce(c, 'sunda_empire');
end $$;

create or replace function game.in_transit(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  return exists (select 1 from game.player_location where player_id = p_pid and coalesce(destination_city_id, '') <> '');
end $$;

create or replace function game.effective_cargo(p_pid uuid) returns int
language plpgsql stable as $$
declare c int;
begin
  select cargo into c from game.ships where player_id = p_pid;
  return coalesce(c, 0);
end $$;

create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.ships;
begin
  select * into s from game.ships where player_id = p_pid;
  if not found then return null; end if;
  return jsonb_build_object('ShipName', s.ship_name, 'Tier', s.tier, 'Hull', s.hull, 'MaxHull', s.max_hull,
    'Cargo', s.cargo, 'Speed', s.speed, 'Combat', s.combat, 'Armor', s.armor, 'Navigation', s.navigation,
    'Condition', s.condition, 'EffectiveCargo', s.cargo, 'CargoBonus', 0, 'EffectiveMaxCondition', 100,
    'ConditionPct', round(s.condition), 'SpeedMultiplier', 1, 'CannonBonusPercent', 0, 'MaxCannonAmmo', 3);
end $$;

create or replace function game.voyage_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
begin
  return jsonb_build_object('inTransit', false);
end $$;

create or replace function game.resolve_arrival_if_due(p_pid uuid) returns jsonb
language plpgsql as $$ begin return null; end $$;

create or replace function game.apply_condition_delta(p_pid uuid, p_delta numeric) returns numeric
language plpgsql as $$
declare c numeric;
begin
  update game.ships set condition = greatest(0, least(100, condition + p_delta)) where player_id = p_pid returning condition into c;
  return c;
end $$;

create or replace function game.city_event(p_city text) returns jsonb
language plpgsql stable as $$ begin return null; end $$;

create or replace function game.event_price_pct(p_city text) returns int
language plpgsql stable as $$ begin return coalesce((game.city_event(p_city) ->> 'priceMultiplierPercent')::int, 0); end $$;

create or replace function game.event_reward_pct(p_city text) returns int
language plpgsql stable as $$ begin return coalesce((game.city_event(p_city) ->> 'rewardMultiplierPercent')::int, 0); end $$;

-- [modul missions/items / 0004] -----------------------------------------
create or replace function game.mission_load(p_pid uuid) returns int
language plpgsql stable as $$ begin return 0; end $$;

create or replace function game.mission_state(p_pid uuid) returns jsonb
language plpgsql stable as $$ begin return jsonb_build_object('hasActive', false); end $$;

-- Efek khusus dari buku (special_effect) ATAU artifact terpasang
create or replace function game.has_effect(p_pid uuid, p_effect text) returns boolean
language plpgsql stable as $$ begin return false; end $$;

-- Dipanggil combat saat menang: kembalikan info loot peta harta (atau null)
create or replace function game.treasure_drop(p_pid uuid, p_enemy_level int) returns jsonb
language plpgsql as $$ begin return null; end $$;

-- [modul multiplayer / 0005] ------------------------------------------
create or replace function game.mp_touch(p_pid uuid) returns void
language plpgsql as $$ begin return; end $$;

create or replace function game.mp_mark_sea(p_pid uuid, p_dest text) returns void
language plpgsql as $$ begin return; end $$;

-- [umum - implementasi final di sini] ---------------------------------
create or replace function game.recent_logs(p_pid uuid, p_limit int default 30) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('gameDay', l.game_day, 'timestamp', game.iso(l.ts), 'message', l.message) order by l.id desc), '[]'::jsonb)
  from (select * from game.player_log where player_id = p_pid order by id desc limit p_limit) l
$$;

create or replace function game.audio_config() returns jsonb
language sql stable as $$
  select jsonb_build_object('bgmUrl', coalesce(game.cfg('SoundBgmUrl'), ''),
    'enabledByAdmin', coalesce(lower(game.cfg('SoundEnabled')), 'true') <> 'false')
$$;

-- [misi rahasia & kota tersembunyi / 0014] ------------------------------
-- Boleh berlayar ke kota ini? (kota tersembunyi hanya bila sudah dibuka)
create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$ select coalesce((select not hidden from game.cities where city_id = p_city), false) $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$ select '[]'::jsonb $$;

create or replace function game.gala_state(p_pid uuid) returns jsonb
language sql stable as $$ select null::jsonb $$;

-- Pertemuan bos misi (null = tidak ada)
create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language sql stable as $$ select null::jsonb $$;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql stable as $$ select null::jsonb $$;

-- Penyembuhan kapal di Paradiso (null = tidak di Paradiso)
create or replace function game.paradiso_tick(p_pid uuid) returns jsonb
language sql stable as $$ select null::jsonb $$;

-- [misi Pembebasan TooGood / 0015] -------------------------------------
create or replace function game.toogood_freed(p_pid uuid) returns boolean
language sql stable as $$ select false $$;
create or replace function game.toogood_state(p_pid uuid) returns jsonb
language sql stable as $$ select null::jsonb $$;
-- Dipanggil setiap kali pemain memenangkan pertempuran biasa (bukan bos)
create or replace function game.quest_combat_won(p_pid uuid) returns void
language plpgsql as $$ begin null; end $$;
-- Kapal legenda sementara ('pearl') atau null
create or replace function game.ship_legend(p_pid uuid) returns text
language sql stable as $$ select null::text $$;
-- Pesan bila tampilan/nama kapal sedang terkunci (null = bebas)
create or replace function game.ship_locked(p_pid uuid) returns text
language sql stable as $$ select null::text $$;

-- [ekonomi v2 / 0018] ---------------------------------------------------
-- Ruang palka per unit barang (Emas 0.1, Kayu Jati 2, ...)
create or replace function game.commodity_size(p_id text) returns numeric
language sql stable as $$ select 1::numeric $$;
-- Ruang palka terpakai (sudah memperhitungkan ukuran barang) & sisa ruang
create or replace function game.cargo_used(p_pid uuid) returns numeric
language sql stable as $$ select game.cargo_total(p_pid)::numeric $$;
create or replace function game.cargo_free(p_pid uuid) returns numeric
language sql stable as $$ select coalesce(game.effective_cargo(p_pid), 0) - game.cargo_used(p_pid) $$;
-- Ambil stok dari pasar kota (misi Pesanan). Gagal bila stok tidak cukup.
create or replace function game.market_take(p_city text, p_comm text, p_qty int) returns void
language plpgsql as $$ begin null; end $$;

-- [Quest Warwerwor / 0019] ----------------------------------------------
-- Status quest untuk getGameState (boleh menulis: menangani tenggat yang lewat)
create or replace function game.ww_state(p_pid uuid) returns jsonb
language plpgsql as $$ begin return null; end $$;
-- Pasar (jual-beli barang) terkunci untuk pemain ini?
create or replace function game.ww_market_closed(p_pid uuid) returns boolean
language sql stable as $$ select false $$;
-- Gubernur yang marah menolak memberi misi (raise exception bila menolak)
create or replace function game.ww_mission_guard(p_pid uuid, p_city text) returns void
language plpgsql as $$ begin null; end $$;
-- Dipanggil setiap kali pemain berangkat berlayar
create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$ begin null; end $$;
-- Dipanggil di akhir setiap pertempuran (hasil apa pun) dengan encounter terakhir
create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$ begin null; end $$;

-- [Quest BarSaTi / 0022] ------------------------------------------------
-- Titik laut khusus quest (bukan kota): tanpa pasar/misi/gudang/bank, tidak ikut
-- perhitungan jarak waktu tempuh, tanpa event kota & bajak laut acak. Definisi final di sini.
create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city in ('titik_buta', 'pusaran'), false) $$;
-- Tolak layanan kota (gudang, bank) bila pemain sedang merapat di titik laut khusus
create or replace function game.spot_service_guard(p_pid uuid) returns void
language plpgsql as $$
begin
  if game.spot_city(game.current_city(p_pid)) then
    raise exception 'Tak ada gudang, bank, apalagi pedagang di tengah badai ini, Kapten. Hanya ombak, petir, dan baja.';
  end if;
end $$;
-- Status quest BarSaTi untuk getGameState (null = belum tersedia)
create or replace function game.bx_state(p_pid uuid) returns jsonb
language plpgsql as $$ begin return null; end $$;
-- Pengali bobot ikan saat melempar umpan (quest bisa menaikkan peluang ikan tertentu)
create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$ begin return 1; end $$;
-- Hadiah quest saat ikan tertangkap (mis. isi Peti Karam). null = tidak ada.
create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$ begin return null; end $$;
