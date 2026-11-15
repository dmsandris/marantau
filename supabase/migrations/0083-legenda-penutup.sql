-- =====================================================================
-- 0083 · Buku Pancing Legenda: 8 halaman terakhir (Tide v61 "Halaman Terakhir")
--
-- Membuka #13, #15–#21 sehingga ke-21 legenda bisa ditangkap:
--   #13 Ikan Kabut Tanpa Mata  Kabut Abu-abu · kapan saja · Kompas Dua Jarum di palka
--   #15 Ikan Rantai            Rantai Lama · malam · umpan Besi · dilepas
--   #16 Lumba Gema             Kota Sowtour · siang · setelah tiga menara menyala (Quest 8)
--   #17 Gurita Arsip           Kota Sowtour · malam · umpan Sutra
--   #18 Kakap Dua Tangan       Teluk Dua Tangan · fajar · dua joran (kapten lain <= 5 menit,
--                              atau "bayangan" kapten yang memancing di teluk <= 24 jam)
--   #19 Hiu Kumis Hitam        IKN · saat Gelombang Badai · umpan Mesiu · kapal Tier V ·
--                              setelah Saga 4 tamat · TIDAK diumumkan di kanal Dunia
--   #20 Matahari Penari        HANYA di 40 Tahun Lalu (Saga 3): ikan karang yang ditarik
--                              bersama Miss Nansy muda di Pelabuhan Sudyrman (Q12 'nansy12').
--                              Rahasia Saga 3: kartu tampil "???" bagi yang belum ke Sudyrman.
--   #21 Ikan Terakhir Miss Nansy  Gading Island · fajar · Joran Kecil Miss Nansy ·
--                              setelah #1–#19 tercatat (#20 tidak wajib) · pasti naik
-- Hadiah buku: 14 = buku "Catatan Fajar" (+5 Luck, legenda ×1,25) · 20 = artefak
-- "Topi Pantai" (tali ×1,15) · 21/21 = adegan Stumpy + 300.000 gold (sekali).
-- Hadiah 14/20 ditahan selama Saga 3 berjalan (harta sedang dicuri), lalu diberikan saat
-- buku dibuka lagi setelah tamat.
--
-- 0025 menulis ulang baris legenda tiap deploy (l_available = false), jadi diperbarui lagi di sini.
-- Kait memakai pola bungkus: fish_quest_weight -> *_lg, fish_quest_catch -> *_lg,
-- api_mgFishCast -> game.api_mgfishcast_lg, api_pasir (nansy12) -> game.api_pasir_lg.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Baris legenda
-- ---------------------------------------------------------------------
update game.mp_fish_types set l_available = true, cities = array['kabut_abu'], l_place = 'Kabut Abu-abu', l_time = 'any'
 where id = 'ikan_kabut';
update game.mp_fish_types set l_available = true, cities = array['rantai_lama'], l_place = 'Pelabuhan Rantai Lama'
 where id = 'ikan_rantai';
update game.mp_fish_types set l_available = true, cities = array['sowtour'], l_place = 'Kota Sowtour'
 where id in ('lumba_gema', 'gurita_arsip');
update game.mp_fish_types set l_available = true, cities = array['teluk_dua_tangan'], l_place = 'Teluk Dua Tangan'
 where id = 'kakap_dua_tangan';
-- rarity 5: pengumuman Syahbandar di api_mgFishReel hanya untuk rarity >= 6 (klien tetap menampilkan "Legenda")
update game.mp_fish_types set l_available = true, cities = array['ikn'], l_place = 'IKN', l_time = 'any',
  l_event = 'storm_surge', l_bait = 'mesiu', rarity = 5
 where id = 'hiu_kumis_hitam';
update game.mp_fish_types set l_available = true, cities = array['sudyrman_pelabuhan'], l_place = 'Pelabuhan Sudyrman',
  l_time = 'fajar', l_bait = null, l_region = 'lampau', v = 0
 where id = 'matahari_penari';
-- tarikan lembut: tidak pernah meronta keras
update game.mp_fish_types set l_available = true, cities = array['gading_island'], l_place = 'Gading Island', l_time = 'fajar',
  l_bait = null, stam = 6, pow = 0.35, agi = 0.15
 where id = 'ikan_terakhir';

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
-- lemparan terakhir per pemain di tempat yang butuh "dua joran"
create table if not exists game.lg_cast (
  player_id uuid primary key references game.players(player_id) on delete cascade on update cascade,
  city      text not null,
  at_ms     bigint not null
);
alter table game.lg_cast enable row level security;
revoke all on game.lg_cast from public;

-- penutup buku (adegan Stumpy) sudah diterima
create table if not exists game.lg_tutup (
  player_id uuid primary key references game.players(player_id) on delete cascade on update cascade,
  at        timestamptz not null default now()
);
alter table game.lg_tutup enable row level security;
revoke all on game.lg_tutup from public;

-- ---------------------------------------------------------------------
-- Buku & artefak hadiah
-- ---------------------------------------------------------------------
insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_catatan_fajar', 'Catatan Fajar', 'V', '{"Luck":5}', 'catatan_fajar', 0, 'quest', 102)
on conflict (book_id) do update set name = excluded.name, tier = excluded.tier, stat_effects = excluded.stat_effects,
  special_effect = excluded.special_effect, price = excluded.price, source = excluded.source, sort = excluded.sort;

insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('art_topi_pantai', 'Topi Pantai', 'artifact',
   '{"SpecialEffect": "topi_pantai", "desc": "Topi pantai lebar milik Miss Nansy, pitanya sudah pudar. Saat terpasang, tali pancing lebih kuat menahan tarikan (×1,15)."}',
   30000, null, 'quest', 22)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Pembantu
-- ---------------------------------------------------------------------
create or replace function game.lg_n(p_pid uuid) returns int
language sql stable as $$ select count(*)::int from game.legend_catch where player_id = p_pid $$;

-- Saga 3 sedang berjalan untuk pemain ini (harta sedang "dicuri")
create or replace function game.lg_saga3_jalan(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if not exists (select 1 from game.pasir_state where player_id = p_pid) then return false; end if;
  if not game.pasir_aktif(p_pid) then return false; end if;
  return game.ps_step(p_pid, 'ps14') < 6;
exception when others then return false;
end $$;

-- Pemain pernah melihat Pelabuhan Sudyrman (boleh tahu halaman #20)
create or replace function game.lg_tahu_lampau(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  return game.ps_step(p_pid, 'ps12') >= 4 or game.ps_step(p_pid, 'ps13') >= 1 or game.ps_step(p_pid, 'ps14') >= 1;
exception when others then return false;
end $$;

create or replace function game.lg_riak_nansy(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  return coalesce((select riak ? 'nansy_buku' from game.pasir_state where player_id = p_pid), false);
exception when others then return false;
end $$;

-- #18: kapten lain (punya buku) yang melempar di teluk dalam p_ms terakhir
create or replace function game.lg_pasangan(p_pid uuid, p_city text, p_ms bigint) returns uuid
language sql stable as $$
  select c.player_id from game.lg_cast c
   where c.city = p_city and c.player_id <> p_pid and c.at_ms >= game.now_ms() - p_ms and game.lg_unlocked(c.player_id)
   order by c.at_ms desc limit 1
$$;

-- Syarat khusus per legenda (selain kota/waktu/event/umpan dari 0025)
create or replace function game.lg_extra_ok(p_pid uuid, p_fish text, p_city text) returns boolean
language plpgsql stable as $$
begin
  return case p_fish
    when 'ikan_kabut'       then game.item_qty(p_pid, 'qi_kompas_dua_jarum') > 0
    when 'lumba_gema'       then game.lt_step(p_pid) >= 7
    when 'kakap_dua_tangan' then game.lg_pasangan(p_pid, p_city, 86400000) is not null
    when 'hiu_kumis_hitam'  then game.mk_tamat(p_pid) and game.ship_tier_num(p_pid) >= 5
    -- #20 hanya lewat Pancing Fajar bersama Miss Nansy (Quest 12), tidak dari lemparan biasa
    when 'matahari_penari'  then false
    when 'ikan_terakhir'    then game.item_qty(p_pid, 'qi_joran_nansy') > 0
      and (select count(*) from game.legend_catch where player_id = p_pid
            and fish_id not in ('matahari_penari', 'ikan_terakhir')) >= 19
    else true end;
exception when others then return false;
end $$;

-- Label syarat khusus untuk buku (samar, gaya catatan Nansy)
create or replace function game.lg_extra_label(p_fish text) returns text
language sql immutable as $$
  select case p_fish
    when 'ikan_kabut'       then 'Kompas Dua Jarum di palka'
    when 'lumba_gema'       then 'Setelah menara-menara menyala'
    when 'kakap_dua_tangan' then 'Dua joran'
    when 'hiu_kumis_hitam'  then 'Kapal Tier V · hanya bagi yang pernah memutus rantai'
    when 'ikan_terakhir'    then 'Joran Kecil Miss Nansy · setelah 19 halaman lain'
    else null end
$$;

create or replace function game.lg_ready(p_pid uuid, f game.mp_fish_types, p_city text) returns boolean
language plpgsql stable as $$
begin
  if f.book <> 'legenda' or not f.l_available then return false; end if;
  if not (f.cities is null or p_city = any (f.cities)) then return false; end if;
  if not game.lg_unlocked(p_pid) then return false; end if;
  if not game.lg_time_ok(f.l_time) then return false; end if;
  if f.l_event is not null and coalesce(game.city_event(p_city) ->> 'eventType', '') <> f.l_event then return false; end if;
  if f.l_bait is not null and game.item_qty(p_pid, f.l_bait) < 1 then return false; end if;
  return game.lg_extra_ok(p_pid, f.id, p_city);
end $$;

-- Hadiah 14 & 20 (idempoten). Ditahan selama Saga 3 berjalan.
create or replace function game.lg_milestone(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_n int := game.lg_n(p_pid); v_out jsonb := '[]'::jsonb; v_rows int; v_slot text;
begin
  if game.lg_saga3_jalan(p_pid) then return v_out; end if;
  if v_n >= 14 then
    insert into game.player_books(player_id, book_id, date_acquired) values (p_pid, 'bk_catatan_fajar', game.game_day())
    on conflict do nothing;
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      update game.character_stats set luck = luck + 5 where player_id = p_pid;
      perform game.log(p_pid, 'Buku Pancing Legenda: 14 halaman. felyx menyelipkan buku tipis "Catatan Fajar" ke dalamnya (+5 Luck).');
      v_out := v_out || jsonb_build_array(jsonb_build_object('kind', 'book', 'id', 'bk_catatan_fajar', 'name', 'Catatan Fajar',
        'effect', '+5 Luck, ikan legenda sedikit lebih sering naik'));
    end if;
  end if;
  if v_n >= 20 and game.item_qty(p_pid, 'art_topi_pantai') < 1
     and not exists (select 1 from game.ship_equipment where player_id = p_pid and item_id = 'art_topi_pantai')
     and not exists (select 1 from game.player_log where player_id = p_pid and message like 'Buku Pancing Legenda: 20 halaman.%') then
    perform game.item_adjust(p_pid, 'art_topi_pantai', 1);
    select s.slot into v_slot from unnest(game.artifact_slots()) with ordinality s(slot, ord)
     where not exists (select 1 from game.ship_equipment e where e.player_id = p_pid and e.slot_type = s.slot and coalesce(e.item_id, '') <> '')
     order by s.ord limit 1;
    if v_slot is not null then
      insert into game.ship_equipment(player_id, slot_type, item_id) values (p_pid, v_slot, 'art_topi_pantai')
      on conflict (player_id, slot_type) do update set item_id = excluded.item_id;
      perform game.item_adjust(p_pid, 'art_topi_pantai', -1);
    end if;
    perform game.log(p_pid, 'Buku Pancing Legenda: 20 halaman. Dari balik meja Stumpy, felyx mengulurkan topi pantai Miss Nansy.');
    v_out := v_out || jsonb_build_array(jsonb_build_object('kind', 'artifact', 'id', 'art_topi_pantai', 'name', 'Topi Pantai',
      'effect', 'Tali pancing lebih kuat menahan tarikan', 'equipped', v_slot is not null));
  end if;
  return v_out;
end $$;

-- Catat satu legenda tanpa tangkapan (penumpang dua joran, Matahari Penari)
create or replace function game.lg_record(p_pid uuid, p_fish text, p_kg numeric default 0) returns boolean
language plpgsql as $$
declare v_first boolean;
begin
  select not exists (select 1 from game.legend_catch where player_id = p_pid and fish_id = p_fish) into v_first;
  insert into game.legend_catch as c (player_id, fish_id, n, best_kg) values (p_pid, p_fish, 1, coalesce(p_kg, 0))
  on conflict (player_id, fish_id) do update set n = c.n + 1,
    best_kg = greatest(c.best_kg, excluded.best_kg), best_at = case when excluded.best_kg > c.best_kg then now() else c.best_at end;
  return v_first;
end $$;

-- ---------------------------------------------------------------------
-- Kait memancing (pola bungkus)
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.fish_quest_weight_lg(uuid, text, text);
  alter function game.fish_quest_weight(uuid, text, text) rename to fish_quest_weight_lg;
  drop function if exists game.fish_quest_catch_lg(uuid, text);
  alter function game.fish_quest_catch(uuid, text) rename to fish_quest_catch_lg;
  drop function if exists game.api_mgfishcast_lg(jsonb);
  alter function public.api_mgfishcast(jsonb) rename to api_mgfishcast_lg;
  alter function public.api_mgfishcast_lg(jsonb) set schema game;
end $$;
revoke all on function game.api_mgfishcast_lg(jsonb) from public, anon, authenticated;

create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
declare w numeric := game.fish_quest_weight_lg(p_pid, p_fish, p_city); f game.mp_fish_types;
begin
  if coalesce(w, 0) <= 0 then return w; end if;
  select * into f from game.mp_fish_types where id = p_fish;
  if not found or f.book <> 'legenda' then return w; end if;
  -- #21 pasti naik bila semua syarat lengkap
  if p_fish = 'ikan_terakhir' then return 100000; end if;
  -- #18 dua joran sungguhan (kapten lain <= 5 menit) lebih kuat dari bayangan
  if p_fish = 'kakap_dua_tangan' and game.lg_pasangan(p_pid, p_city, 300000) is not null then w := w * 2; end if;
  -- Catatan Fajar: legenda ×1,25
  if game.has_effect(p_pid, 'catatan_fajar') then w := w * 1.25; end if;
  return w;
end $$;

create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
declare r jsonb := game.fish_quest_catch_lg(p_pid, p_fish); v_city text := game.current_city(p_pid); v_mate uuid;
  v_me text; v_mate_n text; v_rw jsonb;
begin
  if r is null or not coalesce((r ->> 'legend')::boolean, false) then return r; end if;
  if p_fish = 'kakap_dua_tangan' then
    v_mate := game.lg_pasangan(p_pid, v_city, 300000);
    select character_name into v_me from game.players where player_id = p_pid;
    if v_mate is not null then
      select character_name into v_mate_n from game.players where player_id = v_mate;
      if game.lg_record(v_mate, 'kakap_dua_tangan') then
        perform game.log(v_mate, 'Buku Pancing Legenda: Kakap Dua Tangan tercatat. Joranmu ikut memegang tali saat ' || coalesce(v_me, 'kapten lain') || ' mendaratkannya.');
      end if;
      perform game.sys_chat('Syahbandar', 'Kapten ' || coalesce(v_me, '?') || ' dan Kapten ' || coalesce(v_mate_n, '?') ||
        ' berjabat di Teluk Dua Tangan. Kakap Dua Tangan naik saat fajar.', v_city);
      r := r || jsonb_build_object('mate', v_mate_n, 'message',
        'Dua joran, satu tali. Kau dan ' || coalesce(v_mate_n, 'kapten lain') || ' mengangkatnya bersama. Keduanya tercatat di Buku Pancing Legenda.');
    else
      r := r || jsonb_build_object('message',
        'Di ujung teluk, bayangan joran kapten lain masih tertancap di batu. Kakap itu naik di antara dua tali.');
    end if;
  elsif p_fish = 'ikan_kabut' then
    r := r || jsonb_build_object('message', 'Kompas di palka berdetak sekali, lalu diam. Kedua jarumnya sejajar. Ikan tanpa mata itu tenang di tanganmu.');
  elsif p_fish = 'lumba_gema' then
    r := r || jsonb_build_object('message', 'Om Baayu dari dermaga: "Menara-menara itu dulu menyala untuk kapal. Ternyata ada yang lain juga yang menunggu."');
  elsif p_fish = 'gurita_arsip' then
    r := r || jsonb_build_object('message', 'Sebelum dilepas ke ember, gurita itu menjatuhkan segulung kertas basah: "...kalau salah satu dari kita lupa, menara akan mengingatkan." Tulisan tangan yang sangat tua.');
  elsif p_fish = 'ikan_rantai' then
    r := r || jsonb_build_object('message', case when game.dt_rantai_open(p_pid)
      then 'Kau melepasnya. Di Balai Kongsi, Ki Dorus mengangkat lonceng pelelangan dan membunyikannya sekali.'
      else 'Kau melepasnya. Hanya angin di tiang-tiang pasung yang menjawab.' end);
  elsif p_fish = 'hiu_kumis_hitam' then
    r := r || jsonb_build_object('secret', true, 'message', 'Kau memotong tali sebelum ada yang melihat. Di Buku Pancing Legenda halaman ini kau tulis kecil-kecil: tercatat, tidak dibicarakan.');
  elsif p_fish = 'ikan_terakhir' then
    r := r || jsonb_build_object('message', 'Ikan kecil biasa, sisiknya pucat seperti fajar. Di halaman kosong itu, di bawah gambar perempuan bertopi pantai, muncul satu baris tulisan tangan: "Yang besar itu ceritanya."');
  end if;
  v_rw := game.lg_milestone(p_pid);
  if jsonb_array_length(v_rw) > 0 then r := r || jsonb_build_object('rewards', v_rw); end if;
  r := r || jsonb_build_object('complete', game.lg_n(p_pid) >= 21);
  return r;
end $$;

-- Lempar: catat lemparan di teluk (dua joran), lalu lempar biasa
create or replace function public.api_mgFishCast(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_city text;
begin
  if v_pid is not null and not game.in_transit(v_pid) then
    v_city := game.current_city(v_pid);
    if v_city = 'teluk_dua_tangan' and game.lg_unlocked(v_pid) then
      insert into game.lg_cast as c (player_id, city, at_ms) values (v_pid, v_city, game.now_ms())
      on conflict (player_id) do update set city = excluded.city, at_ms = excluded.at_ms;
    end if;
  end if;
  return game.api_mgfishcast_lg(a);
end $$;
select game.expose('api_mgfishcast');

-- ---------------------------------------------------------------------
-- #20 Matahari Penari: Pancing Fajar bersama Miss Nansy (Quest 12, aksi 'nansy12')
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.api_pasir_lg(jsonb);
  alter function public.api_pasir(jsonb) rename to api_pasir_lg;
  alter function public.api_pasir_lg(jsonb) set schema game;
end $$;
revoke all on function game.api_pasir_lg(jsonb) from public, anon, authenticated;

create or replace function public.api_pasir(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb; v_had boolean;
begin
  v_had := v_pid is not null and game.lg_riak_nansy(v_pid);
  r := game.api_pasir_lg(a);
  if v_pid is not null and coalesce(game.arg(a, 0), '') = 'nansy12' and not v_had and game.lg_riak_nansy(v_pid) then
    if game.lg_record(v_pid, 'matahari_penari', round((0.5 + random() * 1.5)::numeric, 2)) then
      perform game.log(v_pid, 'Buku Pancing Legenda: Matahari Penari tercatat (' || game.lg_n(v_pid) || '/21). Miss Nansy muda menuliskannya untukmu.');
    end if;
    if jsonb_typeof(r) = 'object' then
      r := r || jsonb_build_object('legend', jsonb_build_object('no', 20, 'name', 'Matahari Penari', 'count', game.lg_n(v_pid)));
    end if;
  end if;
  return r;
end $$;
select game.expose('api_pasir');

-- Pemain yang sudah memancing bersama Nansy sebelum halaman ini ada
insert into game.legend_catch(player_id, fish_id, n, best_kg)
select s.player_id, 'matahari_penari', 1, 1.2
  from game.pasir_state s
 where s.riak ? 'nansy_buku'
on conflict (player_id, fish_id) do nothing;

-- ---------------------------------------------------------------------
-- API: Buku Pancing Legenda (+ rahasia Saga 3, label syarat, hadiah, penutup)
-- a = []         -> isi buku (juga memberi hadiah 14/20 yang tertunda)
-- a = ['stumpy'] -> adegan penutup di Stumpy (21/21, di Gading Island, sekali)
-- ---------------------------------------------------------------------
create or replace function public.api_legendBook(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); v_pid uuid := v_me.player_id; v_city text := game.current_city(v_pid);
  v_act text := coalesce(game.arg(a, 0), ''); v_rw jsonb; v_tahu boolean; v_n int; v_gold bigint;
begin
  if not game.lg_unlocked(v_pid) then raise exception 'Buku Pancing Legenda belum ada di tanganmu, Kapten.'; end if;
  v_n := game.lg_n(v_pid);

  if v_act = 'stumpy' then
    if v_n < 21 then raise exception 'Masih ada halaman yang kosong, Kapten.'; end if;
    if v_city <> 'gading_island' or game.in_transit(v_pid) then raise exception 'Bawa bukunya ke Kedai Stumpy di Gading Island.'; end if;
    if game.lg_saga3_jalan(v_pid) then raise exception 'Kedai Stumpy sedang tutup, Kapten.'; end if;
    insert into game.lg_tutup(player_id) values (v_pid) on conflict do nothing;
    if not found then raise exception 'Buku itu sudah selesai, Kapten.'; end if;
    v_gold := game.cfg_num('LegendaTutupGold', 300000)::bigint;
    update game.players set gold = gold + v_gold where player_id = v_pid;
    perform game.log(v_pid, 'Di Kedai Stumpy, coco epan menulis di halaman terakhir Buku Pancing Legenda: "Selesai. Terima kasih, Kapten. — E." (+' || v_gold || ' gold)');
    perform game.sys_chat('Syahbandar', 'Kapten ' || coalesce(v_me.character_name, '?') || ' menyelesaikan Buku Pancing Legenda Miss Nansy. 21 halaman.', v_city);
    return jsonb_build_object('ok', true, 'gold', v_gold, 'newGold', v_me.gold + v_gold);
  end if;

  v_rw := game.lg_milestone(v_pid);
  v_tahu := game.lg_tahu_lampau(v_pid);
  return jsonb_build_object(
    'found', v_n,
    'total', (select count(*) from game.mp_fish_types where book = 'legenda'),
    'cityId', v_city,
    'rewards', v_rw,
    'complete', v_n >= 21,
    'closed', exists (select 1 from game.lg_tutup where player_id = v_pid),
    'atStumpy', v_city = 'gading_island' and not game.in_transit(v_pid),
    'entries', coalesce((select jsonb_agg(
      case when t.id = 'matahari_penari' and c.player_id is null and not v_tahu then
        -- Rahasia Saga 3: tanpa tempat, waktu, atau wilayah
        jsonb_build_object('no', t.legend_no, 'id', t.id, 'rarity', t.rarity, 'region', 'moramora', 'place', '???',
          'time', '???', 'event', null, 'bait', null, 'baitId', null, 'release', false, 'available', true,
          'hint', t.hint, 'here', false, 'ready', false, 'found', false, 'name', null, 'n', 0, 'bestKg', null,
          'secret', true, 'lockLabel', 'Halaman ini belum ditulis')
      else jsonb_build_object(
        'no', t.legend_no, 'id', t.id, 'rarity', t.rarity, 'region', t.l_region, 'place', t.l_place,
        'time', game.lg_time_label(t.l_time), 'event', t.l_event,
        'bait', case when t.l_bait is null then null else game.commodity_name(t.l_bait) end, 'baitId', t.l_bait,
        'release', t.l_release, 'available', t.l_available, 'hint', t.hint,
        'req', case when t.id = 'matahari_penari' then 'Bersama Miss Nansy' else game.lg_extra_label(t.id) end,
        'here', t.l_available and (t.cities is null or v_city = any (t.cities)),
        'ready', game.lg_ready(v_pid, t, v_city),
        'found', c.player_id is not null,
        'name', case when c.player_id is not null then t.name else null end,
        'n', coalesce(c.n, 0), 'bestKg', c.best_kg,
        'lockLabel', case
          when t.id = 'matahari_penari' and c.player_id is null
               and game.ps_step(v_pid, 'ps12') between 4 and 6 then 'Ikut Miss Nansy memancing saat fajar'
          when t.id = 'matahari_penari' and c.player_id is null then 'Fajar itu sudah lewat'
          else null end,
        'secret', t.id = 'hiu_kumis_hitam' and c.player_id is not null)
      end order by t.legend_no)
      from game.mp_fish_types t
      left join game.legend_catch c on c.fish_id = t.id and c.player_id = v_pid
     where t.book = 'legenda'), '[]'::jsonb));
end $$;
select game.expose('api_legendbook');

-- Info dermaga: + Topi Pantai
do $$
begin
  drop function if exists game.api_mgfishinfo_lg(jsonb);
  alter function public.api_mgfishinfo(jsonb) rename to api_mgfishinfo_lg;
  alter function public.api_mgfishinfo_lg(jsonb) set schema game;
end $$;
revoke all on function game.api_mgfishinfo_lg(jsonb) from public, anon, authenticated;

create or replace function public.api_mgFishInfo(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid();
begin
  return game.api_mgfishinfo_lg(a) || jsonb_build_object('topiPantai', game.has_effect(v_pid, 'topi_pantai'));
end $$;
select game.expose('api_mgfishinfo');

insert into game.config(key, value) values ('LegendaTutupGold', '300000') on conflict (key) do nothing;
