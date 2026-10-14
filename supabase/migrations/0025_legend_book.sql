-- =====================================================================
-- Marantau (Supabase) - 0025 BUKU PANCING LEGENDA (Saga 2)
-- Buku memancing kedua, terpisah dari Buku Ikan (14 ikan, syarat Quest 2 tidak berubah).
-- Terbuka setelah pemain menerima Buku Pancing Legenda dari felyx (Quest 6, langkah >= 6).
-- 21 entri sesuai skenario. 10 bisa ditangkap sekarang (8 Mare Nusantara + 2 Gading Island);
-- 11 lainnya terkunci sampai pulau/laut Quest 7-8 dibuat (available = false).
--
-- Syarat tiap legenda (semua harus terpenuhi agar ikan bisa naik ke kail):
--   kota (mp_fish_types.cities), waktu (l_time: fajar|pagi|siang|sore|malam|any),
--   event kota (l_event, mis. 'festival'), umpan dagang di palka (l_bait; 1 unit dipakai saat tertangkap).
--   l_release = ikan dicatat lalu dilepas (tanpa gold).
-- Peluang: umpan dermaga berkilau + lemparan jauh paling baik (rarity 7), lihat 0013.
-- Aman diulang.
-- =====================================================================

alter table game.mp_fish_types add column if not exists legend_no  int;
alter table game.mp_fish_types add column if not exists l_time     text not null default 'any';
alter table game.mp_fish_types add column if not exists l_event    text;
alter table game.mp_fish_types add column if not exists l_bait     text;
alter table game.mp_fish_types add column if not exists l_release  boolean not null default false;
alter table game.mp_fish_types add column if not exists l_region   text;
alter table game.mp_fish_types add column if not exists l_place    text;
alter table game.mp_fish_types add column if not exists l_available boolean not null default true;

-- Catatan tangkapan legenda per pemain
create table if not exists game.legend_catch (
  player_id uuid not null references game.players(player_id) on delete cascade on update cascade,
  fish_id   text not null,
  n         int not null default 0,
  best_kg   numeric not null default 0,
  first_at  timestamptz not null default now(),
  best_at   timestamptz not null default now(),
  primary key (player_id, fish_id)
);
alter table game.legend_catch enable row level security;
revoke all on game.legend_catch from public;

-- ---------------------------------------------------------------------
-- Katalog 21 legenda (book = 'legenda'). v = nilai gold dasar (0 untuk yang dilepas).
-- Kolom tarikan: kg_min, kg_max, stam, pow, agi, depth (2 = laut dalam).
-- ---------------------------------------------------------------------
insert into game.mp_fish_types(id, name, v, w, zone, sp, rarity, kg_min, kg_max, stam, pow, agi, depth, tod, cities, kind, hint, sort, book,
  legend_no, l_time, l_event, l_bait, l_release, l_region, l_place, l_available) values
  -- Mare Nusantara
  ('hiu_garuda',     'Hiu Garuda Perunggu', 1200, 1, 0.07, 2.6, 7, 30, 110, 11.0, 1.15, 0.7, 2, 'any', array['ikn'], 'fish',
   'Ia berenang di bawah burung yang tak pernah terbang.', 101, 'legenda', 1, 'siang', null, 'besi', false, 'nusantara', 'IKN', true),
  ('belut_gunung',   'Belut Gunung Api',     900, 1, 0.08, 2.4, 7, 6, 24, 9.0, 0.95, 1.0, 2, 'any', array['bjorneo'], 'fish',
   'Ia hanya keluar saat gunung batuk dan tuak menghangat.', 102, 'legenda', 2, 'malam', null, 'tuak', false, 'nusantara', 'Bjorneo', true),
  ('pari_batik',     'Pari Batik',           950, 1, 0.08, 2.2, 7, 18, 60, 9.5, 1.0, 0.5, 2, 'any', array['sunda_empire'], 'fish',
   'Punggungnya ditenun ombak.', 103, 'legenda', 3, 'sore', null, 'garam', false, 'nusantara', 'Sunda Empire', true),
  ('kakap_rendang',  'Kakap Rendang',        850, 1, 0.08, 2.3, 7, 8, 30, 9.0, 0.95, 0.75, 2, 'any', array['skitraw'], 'fish',
   'Ikan paling lapar di laut. Pantas, lihat saja kotanya.', 104, 'legenda', 4, 'siang', null, 'kayu_manis', false, 'nusantara', 'Skitraw', true),
  ('tongkol_kopi',   'Tongkol Kopi Pahit',   900, 1, 0.08, 2.6, 7, 10, 40, 9.5, 1.0, 0.8, 2, 'any', array['joungjava'], 'fish',
   'Ia menunggu lelaki tua itu menghabiskan cangkirnya.', 105, 'legenda', 5, 'pagi', null, 'kopi', false, 'nusantara', 'Joungjava', true),
  ('kakap_asap',     'Kakap Asap',             0, 1, 0.08, 2.3, 7, 8, 28, 9.0, 0.95, 0.75, 2, 'any', array['toogood'], 'fish',
   'Dulu ia hitam karena asap. Sekarang ia hitam karena memang begitu warnanya.', 106, 'legenda', 6, 'malam', null, 'rum', true, 'nusantara', 'TooGood', true),
  ('penyu_mutiara',  'Penyu Mutiara Tua',      0, 1, 0.07, 1.6, 7, 60, 180, 12.0, 1.1, 0.3, 2, 'any', array['paradiso'], 'fish',
   'Jangan pernah membawanya pulang. Ia lebih tua dari semua pulau.', 107, 'legenda', 7, 'malam', null, 'mutiara', true, 'nusantara', 'Paradiso', true),
  ('ubur_kaca',      'Ubur Kaca',            700, 1, 0.1, 1.4, 7, 2, 9, 7.0, 0.6, 1.1, 1, 'any', array['marie_regal'], 'fish',
   'Ia menyala saat kota bicara.', 108, 'legenda', 8, 'malam', null, null, false, 'nusantara', 'Marie Regal', true),
  -- Pulau & laut baru
  ('kerapu_fajar',   'Kerapu Fajar',        1100, 1, 0.08, 2.5, 7, 4, 18, 9.0, 1.0, 0.85, 2, 'any', array['gading_island'], 'fish',
   'Ia muncul tepat saat lonceng klenteng pertama berbunyi.', 99, 'legenda', 9, 'fajar', null, null, false, 'baru', 'Gading Island', true),
  ('koi_lampion',    'Koi Lampion',         1000, 1, 0.09, 2.0, 7, 3, 14, 8.0, 0.85, 0.9, 1, 'any', array['gading_island'], 'fish',
   'Ia ikut berenang di bawah lampion. Ia juga suka pesta.', 110, 'legenda', 10, 'malam', 'festival', 'silk', false, 'baru', 'Gading Island', true),
  ('tiram_otoland',  'Tiram Otoland',          0, 1, 0.1, 1, 7, 1, 3, 6, 0.5, 0.2, 1, 'any', array['otoland'], 'fish',
   'Rumahku. Ia tumbuh di garam yang dijemur kincir. Ibu bilang ia lebih tua dariku.', 111, 'legenda', 11, 'siang', null, 'garam', false, 'baru', 'Otoland', false),
  ('marlin_garam',   'Marlin Garam',           0, 1, 0.07, 3, 7, 60, 200, 12, 1.2, 0.9, 2, 'any', array['karang_garam'], 'fish',
   'Ia hanya melompat saat langit marah.', 112, 'legenda', 12, 'siang', null, 'garam', false, 'baru', 'Kepulauan Karang Garam', false),
  ('ikan_kabut',     'Ikan Kabut Tanpa Mata',  0, 1, 0.08, 2, 7, 5, 20, 9, 0.9, 0.8, 2, 'any', array['laut_kabut'], 'fish',
   'Ia tidak melihat. Ia mengikuti jarum.', 113, 'legenda', 13, 'any', null, null, false, 'baru', 'Laut Belum Dipetakan', false),
  ('paus_bisu',      'Bayang Paus Bisu',       0, 1, 0.05, 1, 7, 900, 3000, 14, 1.2, 0.2, 2, 'any', array['seribu_tangga'], 'fish',
   'Di bawah tangga-tangga itu ada yang menyanyi pelan, seperti jam yang berhenti.', 114, 'legenda', 14, 'malam', null, null, true, 'baru', 'Pulau Seribu Tangga', false),
  -- Benua Moramora
  ('ikan_rantai',    'Ikan Rantai',            0, 1, 0.08, 2, 7, 6, 22, 9, 0.9, 0.7, 2, 'any', array['rantai_lama'], 'fish',
   'Sisiknya berbentuk mata rantai. Lepaskan. Ia juga pernah terikat.', 115, 'legenda', 15, 'malam', null, 'besi', true, 'moramora', 'Pelabuhan Rantai Lama', false),
  ('lumba_gema',     'Lumba Gema',             0, 1, 0.07, 2.4, 7, 60, 150, 11, 1, 0.9, 2, 'any', array['menara_suara'], 'fish',
   'Ia menjawab cahaya dengan nyanyian.', 116, 'legenda', 16, 'siang', null, null, false, 'moramora', 'Kota Menara Suara', false),
  ('gurita_arsip',   'Gurita Arsip',           0, 1, 0.08, 1.8, 7, 10, 40, 10, 1, 1, 2, 'any', array['menara_suara'], 'fish',
   'Delapan lengannya menyimpan delapan rahasia. Ia hanya menukarnya dengan kain halus.', 117, 'legenda', 17, 'malam', null, 'silk', false, 'moramora', 'Kota Menara Suara', false),
  ('kakap_dua_tangan','Kakap Dua Tangan',      0, 1, 0.08, 2.2, 7, 10, 36, 9.5, 1, 0.8, 2, 'any', array['teluk_dua_tangan'], 'fish',
   'Ia hanya datang kalau ada dua joran.', 118, 'legenda', 18, 'fajar', null, null, false, 'moramora', 'Teluk Dua Tangan', false),
  ('hiu_kumis_hitam','Hiu Kumis Hitam',        0, 1, 0.06, 3, 7, 120, 400, 14, 1.3, 1, 2, 'any', array['benua_dalam'], 'fish',
   'Kalau kau melihatnya, pulanglah. Kalau kau menangkapnya, jangan bilang siapa-siapa.', 119, 'legenda', 19, 'any', null, 'mesiu', false, 'moramora', 'Perairan dalam Benua', false),
  ('matahari_penari','Matahari Penari',        0, 1, 0.1, 2.6, 7, 0.5, 2, 6, 0.6, 1.2, 0, 'any', array['di_mana_pun'], 'fish',
   'Ikan kecil yang menari. Kata orang, ia anak Legenda Trust.', 120, 'legenda', 20, 'fajar', null, 'batik', false, 'moramora', 'Di mana pun', false),
  ('ikan_terakhir',  'Ikan Terakhir Maudy',    0, 1, 0.06, 2, 7, 5, 20, 10, 1, 0.8, 2, 'any', array['gading_island'], 'fish',
   '(Halaman ini kosong. Hanya ada gambar seorang perempuan bertopi pantai memegang joran.)', 121, 'legenda', 21, 'fajar', null, null, false, 'moramora', 'Gading Island', false)
on conflict (id) do update set name = excluded.name, v = excluded.v, w = excluded.w, zone = excluded.zone, sp = excluded.sp,
  rarity = excluded.rarity, kg_min = excluded.kg_min, kg_max = excluded.kg_max, stam = excluded.stam, pow = excluded.pow,
  agi = excluded.agi, depth = excluded.depth, tod = excluded.tod, cities = excluded.cities, kind = excluded.kind,
  hint = excluded.hint, sort = excluded.sort, book = excluded.book, legend_no = excluded.legend_no, l_time = excluded.l_time,
  l_event = excluded.l_event, l_bait = excluded.l_bait, l_release = excluded.l_release, l_region = excluded.l_region,
  l_place = excluded.l_place, l_available = excluded.l_available;

-- ---------------------------------------------------------------------
-- Waktu & syarat
-- ---------------------------------------------------------------------
create or replace function game.lg_day_frac() returns numeric
language plpgsql stable as $$
declare start_ms bigint; len_ms numeric;
begin
  start_ms := game.cfg_num('WorldStartTimestamp', 0)::bigint;
  len_ms := greatest(60000, game.cfg_num('GameDayLengthRealMinutes', 60) * 60000);
  return mod(game.now_ms() - start_ms, len_ms::bigint) / len_ms;
exception when others then return 0.3;
end $$;

-- fajar 0.93..0.12 (sama dengan cb_is_dawn) | pagi 0.07..0.25 | siang 0.25..0.55 | sore 0.55..0.72 | malam 0.72..0.04
create or replace function game.lg_time_ok(p_time text) returns boolean
language plpgsql stable as $$
declare f numeric := game.lg_day_frac();
begin
  return case coalesce(p_time, 'any')
    when 'any' then true
    when 'fajar' then f >= 0.93 or f < 0.12
    when 'pagi' then f >= 0.07 and f < 0.25
    when 'siang' then f >= 0.25 and f < 0.55
    when 'sore' then f >= 0.55 and f < 0.72
    when 'malam' then f >= 0.72 or f < 0.04
    else false end;
end $$;

create or replace function game.lg_time_label(p_time text) returns text
language sql immutable as $$
  select case coalesce(p_time, 'any') when 'fajar' then 'Fajar' when 'pagi' then 'Pagi' when 'siang' then 'Siang'
    when 'sore' then 'Sore' when 'malam' then 'Malam' else 'Kapan saja' end
$$;

-- Buku terbuka: sudah menerima Buku Pancing Legenda dari felyx
create or replace function game.lg_unlocked(p_pid uuid) returns boolean
language sql stable as $$
  select game.item_qty(p_pid, 'qi_buku_pancing_maudy') > 0 or game.cb_step(p_pid) >= 6
$$;

-- Semua syarat legenda terpenuhi untuk pemain di kota ini?
create or replace function game.lg_ready(p_pid uuid, f game.mp_fish_types, p_city text) returns boolean
language plpgsql stable as $$
begin
  if f.book <> 'legenda' or not f.l_available then return false; end if;
  if not (f.cities is null or p_city = any (f.cities)) then return false; end if;
  if not game.lg_unlocked(p_pid) then return false; end if;
  if not game.lg_time_ok(f.l_time) then return false; end if;
  if f.l_event is not null and coalesce(game.city_event(p_city) ->> 'eventType', '') <> f.l_event then return false; end if;
  if f.l_bait is not null and game.item_qty(p_pid, f.l_bait) < 1 then return false; end if;
  return true;
end $$;

-- ---------------------------------------------------------------------
-- Kait memancing (menggantikan versi 0024): legenda, Quest 6, lalu Peti Karam Bjorneo (0022)
-- ---------------------------------------------------------------------
create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
declare f game.mp_fish_types;
begin
  select * into f from game.mp_fish_types where id = p_fish;
  if found and f.book = 'legenda' then
    -- Quest 6: halaman bertanda bintang - fajar di Gading, peluang tinggi
    if p_fish = 'kerapu_fajar' and game.cb_step(p_pid) = 6 then
      return case when p_city = 'gading_island' and game.cb_is_dawn() then 40 else 0 end;
    end if;
    return case when game.lg_ready(p_pid, f, p_city) then 4 else 0 end;
  end if;
  return game.bx_fish_quest_weight(p_pid, p_fish, p_city);
end $$;

create or replace function game.fish_quest_catch(p_pid uuid, p_fish text) returns jsonb
language plpgsql as $$
declare f game.mp_fish_types; v_kg numeric; v_city text := game.current_city(p_pid); v_n int; v_first boolean;
begin
  select * into f from game.mp_fish_types where id = p_fish;
  if not found or f.book <> 'legenda' then return game.bx_fish_quest_catch(p_pid, p_fish); end if;
  -- legenda dicatat di Buku Pancing Legenda, bukan di Buku Ikan
  select best_kg into v_kg from game.mp_fish_book where player_id = p_pid and fish_id = p_fish;
  delete from game.mp_fish_book where player_id = p_pid and fish_id = p_fish;
  select not exists (select 1 from game.legend_catch where player_id = p_pid and fish_id = p_fish) into v_first;
  insert into game.legend_catch as c (player_id, fish_id, n, best_kg) values (p_pid, p_fish, 1, coalesce(v_kg, 0))
  on conflict (player_id, fish_id) do update set n = c.n + 1,
    best_kg = greatest(c.best_kg, excluded.best_kg), best_at = case when excluded.best_kg > c.best_kg then now() else c.best_at end;
  -- umpan dagang dipakai 1 unit
  if f.l_bait is not null and game.item_qty(p_pid, f.l_bait) > 0 then perform game.adjust_inventory(p_pid, f.l_bait, -1); end if;
  select count(*) into v_n from game.legend_catch where player_id = p_pid;
  -- Quest 6: entri bertanda bintang
  if p_fish = 'kerapu_fajar' and game.cb_step(p_pid) = 6 and v_city = 'gading_island' then
    update game.player_quests set step = 7, data = data || jsonb_build_object('legend', true, 'legendKg', v_kg), updated_at = now()
     where player_id = p_pid and quest_id = 'cocoepan';
    perform game.log(p_pid, 'Kerapu Fajar tertangkap saat fajar di Gading Island. Halaman pertama Buku Pancing Legenda kini terisi.');
    return jsonb_build_object('legend', true, 'no', f.legend_no, 'name', f.name, 'release', false, 'first', true, 'count', v_n,
      'itemId', 'qi_buku_pancing_maudy', 'quest', 'cocoepan',
      'message', 'Sisiknya berkilau keemasan seperti langit sebelum matahari. Di Buku Pancing Legenda, entri pertama bertanda bintang kini bisa dicoret.');
  end if;
  if v_first then
    perform game.log(p_pid, 'Buku Pancing Legenda: ' || f.name || ' tercatat (' || v_n || '/21)' || case when f.l_release then ', lalu dilepas kembali ke laut.' else '.' end);
  end if;
  return jsonb_build_object('legend', true, 'no', f.legend_no, 'name', f.name, 'release', f.l_release, 'first', v_first, 'count', v_n,
    'message', case when f.l_release then 'Kau mencatatnya di Buku Pancing Legenda, lalu melepasnya kembali ke laut.'
      else 'Tercatat di Buku Pancing Legenda.' end);
end $$;

-- Pemain yang sudah menangkap ikan Quest 6 sebelum buku ini ada: catat di buku
insert into game.legend_catch(player_id, fish_id, n, best_kg)
select q.player_id, 'kerapu_fajar', 1, coalesce((q.data ->> 'legendKg')::numeric, 0)
  from game.player_quests q
 where q.quest_id = 'cocoepan' and q.step >= 7
on conflict (player_id, fish_id) do nothing;

-- ---------------------------------------------------------------------
-- API: Buku Pancing Legenda & info dermaga
-- ---------------------------------------------------------------------
create or replace function public.api_legendBook(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); v_pid uuid := v_me.player_id; v_city text := game.current_city(v_pid);
begin
  if not game.lg_unlocked(v_pid) then raise exception 'Buku Pancing Legenda belum ada di tanganmu, Kapten.'; end if;
  return jsonb_build_object(
    'found', (select count(*) from game.legend_catch where player_id = v_pid),
    'total', (select count(*) from game.mp_fish_types where book = 'legenda'),
    'cityId', v_city,
    'entries', coalesce((select jsonb_agg(jsonb_build_object(
        'no', t.legend_no, 'id', t.id, 'rarity', t.rarity, 'region', t.l_region, 'place', t.l_place,
        'time', game.lg_time_label(t.l_time), 'event', t.l_event,
        'bait', case when t.l_bait is null then null else game.commodity_name(t.l_bait) end, 'baitId', t.l_bait,
        'release', t.l_release, 'available', t.l_available, 'hint', t.hint,
        'here', t.l_available and (t.cities is null or v_city = any (t.cities)),
        'ready', game.lg_ready(v_pid, t, v_city),
        'found', c.player_id is not null,
        'name', case when c.player_id is not null then t.name else null end,
        'n', coalesce(c.n, 0), 'bestKg', c.best_kg
      ) order by t.legend_no)
      from game.mp_fish_types t
      left join game.legend_catch c on c.fish_id = t.id and c.player_id = v_pid
     where t.book = 'legenda'), '[]'::jsonb));
end $$;
select game.expose('api_legendbook');

-- Info dermaga (sama dengan 0024 + status Buku Pancing Legenda)
create or replace function public.api_mgFishInfo(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); r game.mp_fish;
begin
  r := game.fish_row(v_me.player_id);
  return jsonb_build_object('left', game.fish_left(v_me.player_id), 'max', game.fish_qmax(),
    'nextMs', game.fish_next_ms(v_me.player_id), 'regenMs', game.fish_qsec(), 'rod', r.rod, 'rods', game.fish_rods(),
    'baits', game.fish_baits(), 'night', game.fish_is_night(), 'cityId', game.current_city(v_me.player_id),
    'dawn', game.cb_is_dawn(),
    'found', (select count(*) from game.mp_fish_book b join game.mp_fish_types t on t.id = b.fish_id where b.player_id = v_me.player_id and t.book = 'ikan'),
    'total', (select count(*) from game.mp_fish_types where book = 'ikan'),
    'legendUnlocked', game.lg_unlocked(v_me.player_id),
    'legendFound', (select count(*) from game.legend_catch where player_id = v_me.player_id),
    'legendTotal', (select count(*) from game.mp_fish_types where book = 'legenda'),
    'cooldownMs', greatest(0, coalesce(r.cooldown_until, 0) - game.now_ms()));
end $$;
select game.expose('api_mgfishinfo');
