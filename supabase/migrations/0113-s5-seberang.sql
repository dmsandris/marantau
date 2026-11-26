-- =====================================================================
-- 0113 · S5 Fase B: dunia seberang + titian + Bagian II (langkah 20-28, Q25 di langkah 20, Q26 di langkah 28)
--
--   Kota netral s5_t0 (kaki titian), s5_p1..p6 (pulau), s5_t1..t3 (titik laut). Tipe 'S5*':
--     tidak ikut cities_json (rahasia), tidak punya pasar, dikirim lewat key s5.kota hanya ke pemain yang berhak.
--   Peta seberang: koordinat 2000 + x/20 (x, y = koordinat S5Peta 1600 x 1000), terpisah total dari Mare.
--   Titian (Susur Ombak, ctx 'crossing'): dari Bjorneo, 1 penyeberangan per hari kalender game (K3),
--     Mesin Jolt Warlord terpasang, tiket 10 Oli dipotong saat mulai kecuali penyeberangan pertama (K6).
--     Pertama: tiba di kaki titian (langkah 21). Berikutnya: langsung merapat di s5_p1.
--   Pulang: dari s5_p1 (Dermaga), gratis, tanpa mini game, 1 per hari kalender game, selalu tiba di Bjorneo.
--   Pencegatan cerita (langkah 22, 26): s5_state.data.cegat; kapal ditahan di detik kedatangan sampai lolos (Lari).
--   Dwarfsmith (reparasi 3x) hanya di s5_p1, s5_p5, s5_p6.
--   Gerbang langkah 20+ : S5bOpen (FiturPenguji) atau mode uji GM.
--   Pembungkus (rename _s5b): city_open, player_unlocks, spot_city, quest_arrival_redirect, voy_repair_quote,
--     s5_mg_izin, s5_mg_mulai, s5_mg_efek, api_setsail.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('S5TekaJedaDetik', '20') on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- 1. Kota seberang
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('s5_t0', 'Kaki Titian',     'S5Titian',  1.0, '', 2007.5, 2023.5, 90, true),
  ('s5_p1', 'Himinbujang',     'S5Gerbang', 3.0, '', 2012.5, 2031,   91, true),
  ('s5_p2', 'Jotunjumbo',      'S5Raksasa', 1.0, '', 2023.5, 2015,   92, true),
  ('s5_p3', 'Kabutheim',       'S5Kabut',   1.0, '', 2066.75, 2016.5, 93, true),
  ('s5_p4', 'Folkbarakk',      'S5Barak',   1.0, '', 2065,   2031.25, 94, true),
  ('s5_p5', 'Valhalalo',       'S5Aula',    3.0, '', 2053.75, 2008.25, 95, true),
  ('s5_p6', 'Glamorheim',      'S5Rune',    3.0, '', 2023.5, 2040.75, 96, true),
  ('s5_t1', 'Akar Yggdrasil',  'S5Akar',    1.0, '', 2045.25, 2035,   97, true),
  ('s5_t2', 'Garis Selatan',   'S5Selatan', 1.0, '', 2057,   2040.75, 98, true),
  ('s5_t3', 'Palung',          'S5Palung',  1.0, '', 2064.5, 2045.75, 99, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;
-- 0018 menyisipkan baris pasar untuk semua kota tiap deploy: dunia seberang tidak punya pasar (B4)
delete from game.market where city_id like 's5\_%';

create or replace function game.s5_dwarf(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city in ('s5_p1', 's5_p5', 's5_p6'), false) $$;

-- Daftar kota umum: tipe 'Ps*' (Pasir) dan 'S5*' tidak pernah dikirim
create or replace function game.cities_json() returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(game.city_json(c) order by c.sort, c.city_id), '[]'::jsonb) from game.cities c
  where c.type not like 'Ps%' and c.type not like 'S5%'
$$;

do $$
begin
  drop function if exists game.city_open_s5b(uuid, text);
  alter function game.city_open(uuid, text) rename to city_open_s5b;
  drop function if exists game.player_unlocks_s5b(uuid);
  alter function game.player_unlocks(uuid) rename to player_unlocks_s5b;
  drop function if exists game.spot_city_s5b(text);
  alter function game.spot_city(text) rename to spot_city_s5b;
  drop function if exists game.quest_arrival_redirect_s5b(uuid, text, text);
  alter function game.quest_arrival_redirect(uuid, text, text) rename to quest_arrival_redirect_s5b;
  drop function if exists game.voy_repair_quote_s5b(uuid, text);
  alter function game.voy_repair_quote(uuid, text) rename to voy_repair_quote_s5b;
  drop function if exists game.s5_mg_izin_s5b(uuid, text, text, text, int);
  alter function game.s5_mg_izin(uuid, text, text, text, int) rename to s5_mg_izin_s5b;
  drop function if exists game.s5_mg_mulai_s5b(uuid, game.mg_session);
  alter function game.s5_mg_mulai(uuid, game.mg_session) rename to s5_mg_mulai_s5b;
  drop function if exists game.s5_mg_efek_s5b(uuid, game.mg_session, boolean);
  alter function game.s5_mg_efek(uuid, game.mg_session, boolean) rename to s5_mg_efek_s5b;
  drop function if exists game.api_setsail_s5b(jsonb);
  alter function public.api_setsail(jsonb) rename to api_setsail_s5b;
  alter function public.api_setsail_s5b(jsonb) set schema game;
end $$;
revoke all on function game.api_setsail_s5b(jsonb) from public, anon, authenticated;

create or replace function game.spot_city(p_city text) returns boolean
language sql immutable as $$ select game.s5_city(p_city) or game.spot_city_s5b(p_city) $$;

-- ---------------------------------------------------------------------
-- 2. Langkah 1-28
--   w 'seberang' = hanya di dunia seberang · gb = gerbang Bagian II · auto = diselesaikan server (mini game)
--   dest/cegat = pencegatan cerita di pelayaran ke dest · jawab = teka-teki dinilai server · item = item quest
-- ---------------------------------------------------------------------
create or replace function game.s5_steps() returns jsonb
language sql immutable as $$
  select '[
    {"n":1, "q":23, "p":"tavern", "b":"bisikan"},
    {"n":2, "q":23, "c":"toogood", "p":"tavern", "b":"dwi", "g":"jejak"},
    {"n":3, "q":23, "c":"bjorneo", "p":"tavern", "b":"getaran", "mg":"cari_lereng"},
    {"n":4, "q":23, "c":"bjorneo", "p":"tavern", "b":"opung", "g":"pantun"},
    {"n":5, "q":23, "c":"joungjava", "p":"market", "b":"etalase", "g":"manifest"},
    {"n":6, "q":23, "c":"joungjava", "p":"market", "b":"tepi", "gold":"S5GoldQ23"},
    {"n":7, "q":24, "c":"bjorneo", "p":"ship", "b":"selam", "g":"selam"},
    {"n":8, "q":24, "c":"bjorneo", "p":"ship", "b":"lambung"},
    {"n":9, "q":24, "c":"bjorneo", "p":"tavern", "b":"cap", "g":"pelikan"},
    {"n":10,"q":24, "c":"karang_garam", "p":"tavern", "b":"lunas", "g":"angin"},
    {"n":11,"q":24, "c":"karang_garam", "p":"tavern", "b":"tetua", "g":"warga"},
    {"n":12,"q":24, "c":"joungjava", "p":"market", "b":"kebenaran", "pilih":["luruskan","biarkan"], "gold":"S5GoldQ24"},
    {"n":13,"q":25, "c":"otoland", "p":"tavern", "b":"kincir", "g":"jejak"},
    {"n":14,"q":25, "c":"otoland", "p":"tavern", "b":"basahi", "g":"tercecer"},
    {"n":15,"q":25, "c":"sowtour", "p":"tavern", "b":"cermin", "g":"sandi", "t":"malam"},
    {"n":16,"q":25, "c":"sowtour", "p":"tavern", "b":"syarat"},
    {"n":17,"q":25, "c":"zentul", "p":"garasi", "b":"lambung", "warlord":true},
    {"n":18,"q":25, "c":"bjorneo", "p":"tavern", "b":"serpihan", "g":"manifest"},
    {"n":19,"q":25, "c":"bjorneo", "p":"tavern", "b":"airterjun", "mg":"lagu_tidur", "t":"malam"},
    {"n":20,"q":25, "c":"bjorneo", "p":"merapi", "b":"cahaya", "t":"malam", "gold":"S5GoldQ25", "gb":true},
    {"n":21,"q":26, "c":"bjorneo", "p":"merapi", "b":"titian", "auto":"crossing", "gb":true},
    {"n":22,"q":26, "c":"s5_t0", "p":"laut", "dest":"s5_p1", "cegat":"valkyrie", "auto":"encounter", "w":"seberang", "gb":true},
    {"n":23,"q":26, "c":"s5_p1", "p":"dermaga", "b":"penjaga", "g":"pantun", "w":"seberang", "gb":true},
    {"n":24,"q":26, "c":"s5_p1", "p":"dermaga", "b":"dengar", "item":"segel_penjaga", "w":"seberang", "gb":true},
    {"n":25,"q":26, "c":"s5_p1", "p":"aula", "b":"kabar", "g":"warga", "w":"seberang", "gb":true},
    {"n":26,"q":26, "p":"laut", "dest":"s5_p2", "cegat":"ular_muda", "auto":"encounter", "w":"seberang", "gb":true},
    {"n":27,"q":26, "c":"s5_p2", "p":"balai", "b":"segel", "jawab":"janji", "w":"seberang", "gb":true},
    {"n":28,"q":26, "c":"s5_p2", "p":"balai", "b":"papan", "gold":"S5GoldQ26", "w":"seberang", "gb":true}
  ]'::jsonb
$$;

create or replace function game.s5_gerbang_b(p_pid uuid) returns boolean
language sql stable as $$ select game.fitur_on(p_pid, 'S5bOpen') or game.s5_uji(p_pid) $$;

-- Pulau & titik yang terbuka (urut kemunculan cerita). Kaki titian bukan tujuan layar.
create or replace function game.s5_buka(p_pid uuid) returns text[]
language plpgsql stable as $$
declare s int := game.s5_step(p_pid); r text[] := array[]::text[];
begin
  if not game.s5_gerbang_b(p_pid) then return r; end if;
  if s >= 21 then r := array_append(r, 's5_p1'); end if;
  if s >= 24 then r := array_append(r, 's5_p2'); end if;
  return r;
end $$;

-- Titian terbuka: Bagian I tuntas sampai "melangkah ke cahaya" (langkah 20)
create or replace function game.s5_titian(p_pid uuid) returns boolean
language sql stable as $$ select game.s5_eligible(p_pid) and game.s5_gerbang_b(p_pid) and game.s5_step(p_pid) >= 20 $$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language plpgsql stable as $$
begin
  if game.s5_city(p_city) then
    return game.s5_di_seberang(p_pid) and p_city = any (game.s5_buka(p_pid));
  end if;
  if game.s5_di_seberang(p_pid) then return false; end if;   -- dari seberang tak ada jalan laut ke Mare
  return game.city_open_s5b(p_pid, p_city);
end $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language plpgsql stable as $$
begin
  if game.s5_di_seberang(p_pid) then return to_jsonb(game.s5_buka(p_pid)); end if;
  return game.player_unlocks_s5b(p_pid);
end $$;

-- Dwarfsmith hanya di tiga pulau; pulau seberang lain tidak punya galangan
create or replace function game.voy_repair_quote(p_pid uuid, p_city text) returns jsonb
language plpgsql stable as $$
begin
  if game.s5_city(p_city) and not game.s5_dwarf(p_city) then
    raise exception 'Tak ada Dwarfsmith di pulau ini, Kapten.';
  end if;
  return game.voy_repair_quote_s5b(p_pid, p_city);
end $$;

-- ---------------------------------------------------------------------
-- 3. Status titian untuk klien
-- ---------------------------------------------------------------------
create or replace function game.s5_pertama(p_pid uuid) returns boolean
language sql stable as $$ select not coalesce((select (data ->> 'tiba')::boolean from game.s5_state where player_id = p_pid), false) $$;

create or replace function game.s5_titian_info(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_oli int := greatest(0, game.cfg_num('S5TiketOli', 10))::int; v_first boolean := game.s5_pertama(p_pid);
begin
  return jsonb_build_object(
    'buka', game.s5_titian(p_pid),
    'pertama', v_first,
    'preset', case when v_first then 'pelangi' else 'pelangi_ulang' end,
    'hari', game.s5_bisa_seberang(p_pid),
    'warlord', game.wl_has(p_pid, 'speed'),
    'oli', case when v_first then 0 else v_oli end,
    'punyaOli', game.item_qty(p_pid, 'oli_hitam'),
    'tiket', game.s5_tiket_berlaku(p_pid));
exception when others then return jsonb_build_object('buka', false);
end $$;

-- ---------------------------------------------------------------------
-- 4. Pencegatan cerita
-- ---------------------------------------------------------------------
create or replace function game.s5_sdata(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce((select data from game.s5_state where player_id = p_pid), '{}'::jsonb) $$;

create or replace function game.s5_sdata_set(p_pid uuid, p_set jsonb, p_hapus text[] default array[]::text[]) returns void
language plpgsql as $$
begin
  perform game.s5_row(p_pid);
  update game.s5_state set data = (data - p_hapus) || coalesce(p_set, '{}'::jsonb), updated_at = now() where player_id = p_pid;
end $$;

create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_dest text := game.arg(a, 0); r jsonb; d jsonb; l game.player_location; v_at bigint;
begin
  r := game.api_setsail_s5b(a);
  if v_pid is null or not game.s5_di_seberang(v_pid) then return r; end if;
  begin
    perform game.s5_sdata_set(v_pid, null, array['cegat']);
    d := game.s5_steps() -> game.s5_step(v_pid);
    if d ? 'cegat' and d ->> 'dest' = v_dest then
      select * into l from game.player_location where player_id = v_pid;
      v_at := (extract(epoch from l.depart_at) * 1000)::bigint
            + greatest(3000, least(8000, ((extract(epoch from (l.arrive_at - l.depart_at)) * 1000)::bigint * 4) / 10));
      perform game.s5_sdata_set(v_pid, jsonb_build_object('cegat', jsonb_build_object(
        'n', (d ->> 'n')::int, 'dest', v_dest, 'preset', d ->> 'cegat', 'at', v_at, 'asal', l.city_id)));
      -- pelayaran sependek apa pun tetap memberi ruang untuk pencegatan
      update game.player_location set arrive_at = greatest(arrive_at, depart_at + interval '14 seconds') where player_id = v_pid;
    end if;
  exception when others then null;
  end;
  return r;
end $$;
select game.expose('api_setsail');

-- Kapal ditahan di detik kedatangan sampai pencegatan dilewati
create or replace function game.quest_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
declare c jsonb;
begin
  if game.s5_city(p_dest) then
    c := game.s5_sdata(p_pid) -> 'cegat';
    if jsonb_typeof(c) = 'object' and c ->> 'dest' = p_dest then return jsonb_build_object('hold', true, 's5', true); end if;
    return null;
  end if;
  return game.quest_arrival_redirect_s5b(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- 5. Mini game: izin, biaya, akibat (titian & pencegatan)
-- ---------------------------------------------------------------------
create or replace function game.s5_mg_izin(p_pid uuid, p_kind text, p_ctx text, p_preset text, p_step int) returns text
language plpgsql stable as $$
declare t jsonb; c jsonb; l game.player_location;
begin
  if p_kind = 'wave' and p_ctx = 'crossing' then
    if not game.s5_titian(p_pid) then return 'Belum ada yang menunggu di sini, Kapten.'; end if;
    if game.s5_di_seberang(p_pid) then return 'Kau sudah di seberang, Kapten.'; end if;
    if game.in_transit(p_pid) then return 'Merapat dulu di pelabuhan, Kapten.'; end if;
    if game.current_city(p_pid) is distinct from 'bjorneo' then return 'Titian hanya bisa dicapai dari kawah Bjorneo, Kapten.'; end if;
    t := game.s5_titian_info(p_pid);
    if p_preset <> (t ->> 'preset') then return 'Titian berubah, Kapten. Coba lagi.'; end if;
    if not coalesce((t -> 'hari' ->> 'ok')::boolean, false) then return t -> 'hari' ->> 'pesan'; end if;
    if not coalesce((t ->> 'warlord')::boolean, false) then return 'Titian hanya menerima lambung yang lurus. Pasang Mesin Jolt Warlord dulu, Kapten.'; end if;
    if not coalesce((t ->> 'tiket')::boolean, false) and (t ->> 'punyaOli')::int < (t ->> 'oli')::int then
      return 'Titian itu haus, Kapten. Butuh ' || (t ->> 'oli') || ' Oli Hitam di palka (ada ' || (t ->> 'punyaOli') || ').';
    end if;
    return null;
  end if;
  if p_kind = 'wave' and p_ctx = 'encounter' then
    c := game.s5_sdata(p_pid) -> 'cegat';
    select * into l from game.player_location where player_id = p_pid;
    if jsonb_typeof(c) <> 'object' or not game.s5_di_seberang(p_pid) or coalesce(l.destination_city_id, '') <> c ->> 'dest'
       or c ->> 'preset' <> p_preset or p_step is distinct from (c ->> 'n')::int then
      return 'Laut sudah tenang, Kapten.';
    end if;
    if game.now_ms() < (c ->> 'at')::bigint then return 'Belum ada apa-apa di cakrawala, Kapten.'; end if;
    return null;
  end if;
  return game.s5_mg_izin_s5b(p_pid, p_kind, p_ctx, p_preset, p_step);
end $$;

create or replace function game.s5_mg_mulai(p_pid uuid, p_s game.mg_session) returns jsonb
language plpgsql as $$
declare v_oli int;
begin
  if p_s.kind = 'wave' and p_s.context = 'crossing' then
    if game.s5_pertama(p_pid) or game.s5_tiket_berlaku(p_pid) then return jsonb_build_object('tiket', game.s5_tiket_berlaku(p_pid), 'oli', 0); end if;
    v_oli := greatest(0, game.cfg_num('S5TiketOli', 10))::int;
    if v_oli > 0 then perform game.item_adjust(p_pid, 'oli_hitam', -v_oli); end if;
    perform game.s5_row(p_pid);
    update game.s5_state set tiket_day = game.game_day(), updated_at = now() where player_id = p_pid;
    perform game.log(p_pid, 'Titian meminta ' || v_oli || ' Oli Hitam.');
    return jsonb_build_object('tiket', true, 'oli', v_oli);
  end if;
  return game.s5_mg_mulai_s5b(p_pid, p_s);
end $$;

-- Pindahkan kapal ke dunia lain (tanpa pelayaran)
create or replace function game.s5_pindah(p_pid uuid, p_ke text, p_city text) returns void
language plpgsql as $$
begin
  perform game.s5_catat_seberang(p_pid, p_ke);
  update game.player_location set city_id = p_city, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null
   where player_id = p_pid;
  perform game.s5_sdata_set(p_pid, null, array['cegat']);
  begin perform game.mp_touch(p_pid); exception when others then null; end;
end $$;

create or replace function game.s5_mg_efek(p_pid uuid, p_s game.mg_session, p_won boolean) returns jsonb
language plpgsql as $$
declare v_first boolean; v_kota text; c jsonb; g jsonb;
begin
  if p_s.kind = 'wave' and p_s.context = 'crossing' then
    if not p_won then return jsonb_build_object('ulang', true); end if;
    v_first := game.s5_pertama(p_pid);
    v_kota := case when v_first then 's5_t0' else 's5_p1' end;
    perform game.s5_pindah(p_pid, 'seberang', v_kota);
    perform game.s5_sdata_set(p_pid, '{"tiba":true}'::jsonb);
    if game.s5_step(p_pid) = 20 then g := game.s5_tuntas(p_pid, 21, '{}'::jsonb); end if;
    perform game.log(p_pid, 'Kapalmu menyeberangi titian tujuh warna.');
    return jsonb_build_object('tiba', v_kota, 'pertama', v_first, 'langkah', g);
  end if;
  if p_s.kind = 'wave' and p_s.context = 'encounter' then
    if not p_won then return jsonb_build_object('ulang', true); end if;
    c := game.s5_sdata(p_pid) -> 'cegat';
    perform game.s5_sdata_set(p_pid, null, array['cegat']);
    if jsonb_typeof(c) = 'object' and game.s5_step(p_pid) + 1 = (c ->> 'n')::int then
      g := game.s5_tuntas(p_pid, (c ->> 'n')::int, jsonb_build_object('mg' || (c ->> 'n'), p_s.id::text));
    end if;
    return jsonb_build_object('lolos', true, 'langkah', g);
  end if;
  return game.s5_mg_efek_s5b(p_pid, p_s, p_won);
end $$;

-- ---------------------------------------------------------------------
-- 6. Menyelesaikan satu langkah (dipakai aksi pemain dan akibat mini game)
-- ---------------------------------------------------------------------
create or replace function game.s5_tuntas(p_pid uuid, p_n int, p_tambah jsonb) returns jsonb
language plpgsql as $$
declare v_step int; v_data jsonb; d jsonb; v_gold bigint := 0;
begin
  select step, data into v_step, v_data from game.player_quests where player_id = p_pid and quest_id = 's5' for update;
  if v_step is null or v_step + 1 <> p_n then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  d := game.s5_steps() -> v_step;
  if d ? 'gold' then
    v_gold := greatest(0, game.cfg_num(d ->> 'gold', 0))::bigint;
    if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = p_pid; end if;
  end if;
  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = coalesce(v_data, '{}'::jsonb) || coalesce(p_tambah, '{}'::jsonb) || jsonb_build_object('s' || (d ->> 'n'), game.now_ms())
      || case when d ? 'item' then jsonb_build_object('item_' || (d ->> 'item'), true) else '{}'::jsonb end
   where player_id = p_pid and quest_id = 's5';
  perform game.log(p_pid, case when v_gold > 0 then 'Jejak gunung: bab ' || (d ->> 'q') || ' selesai (+' || v_gold || ' gold).'
                               else 'Jejak gunung: langkah ' || (d ->> 'n') || ' selesai.' end);
  return jsonb_build_object('n', p_n, 'gold', v_gold, 'q', (d ->> 'q')::int);
end $$;

-- ---------------------------------------------------------------------
-- 7. View & aksi pemain
-- ---------------------------------------------------------------------
create or replace function game.s5_kota_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_here text := game.current_city(p_pid); v_dest text;
begin
  if not game.s5_di_seberang(p_pid) then return '[]'::jsonb; end if;
  select destination_city_id into v_dest from game.player_location where player_id = p_pid;
  return coalesce((select jsonb_agg(game.city_json(c) || jsonb_build_object('Dwarf', game.s5_dwarf(c.city_id)) order by c.sort)
    from game.cities c where c.city_id like 's5\_%' and (c.city_id = any (game.s5_buka(p_pid)) or c.city_id = v_here or c.city_id = v_dest)), '[]'::jsonb);
end $$;

create or replace function game.s5_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v int; d jsonb; v_seb boolean; sd jsonb;
begin
  if not game.s5_eligible(p_pid) then return null; end if;
  select step, data into v, d from game.player_quests where player_id = p_pid and quest_id = 's5';
  v := coalesce(v, 0); d := coalesce(d, '{}'::jsonb);
  v_seb := game.s5_di_seberang(p_pid); sd := game.s5_sdata(p_pid);
  -- Bagian II terkunci gerbangnya: langkah 20+ tidak dikirim
  return jsonb_build_object(
    'step', v, 'ada', case when game.s5_gerbang_b(p_pid) then game.s5_ada() else 19 end,
    'd', case when v >= 19 and not game.s5_gerbang_b(p_pid) then null else game.s5_steps() -> v end, 'data', d,
    'dunia', game.s5_dunia(p_pid),
    'warlord', case when coalesce((game.s5_steps() -> v ->> 'warlord')::boolean, false) then game.s5_warlord(p_pid) end,
    'gerbangB', game.s5_gerbang_b(p_pid),
    'titian', case when game.s5_titian(p_pid) then game.s5_titian_info(p_pid) end,
    'kota', case when v_seb then game.s5_kota_json(p_pid) end,
    'buka', case when v_seb then to_jsonb(game.s5_buka(p_pid)) end,
    'fase', case when v >= 28 then 3 else 2 end,
    'cegat', case when v_seb then sd -> 'cegat' end,
    'tekaSampai', d -> 'tekaSampai',
    'nowMs', game.now_ms());
exception when others then return null;
end $$;

create or replace function game.s5_act(p_pid uuid, a jsonb) returns jsonb
language plpgsql as $$
declare
  v_act text := lower(coalesce(game.arg(a, 0), 'status'));
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; v_data jsonb; d jsonb; v_city text; g jsonb; v_seb boolean; c jsonb; l game.player_location; v_tambah jsonb := '{}'::jsonb;
  v_bisa jsonb;
begin
  if v_act = 'status' then return jsonb_build_object('s5', game.s5_view(p_pid)); end if;
  if not game.s5_eligible(p_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  v_seb := game.s5_di_seberang(p_pid);

  -- Pulang ke Mare: dari Dermaga pulau gerbang, gratis, 1 penyeberangan per hari kalender game (K3)
  if v_act = 'pulang' then
    if not v_seb then raise exception 'Kau sudah di Mare, Kapten.'; end if;
    if game.in_transit(p_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
    if game.current_city(p_pid) is distinct from 's5_p1' then raise exception 'Pintu pulang hanya dibuka penjaga di pulau gerbang, Kapten.'; end if;
    v_bisa := game.s5_bisa_seberang(p_pid);
    if not coalesce((v_bisa ->> 'ok')::boolean, false) then raise exception '%', v_bisa ->> 'pesan'; end if;
    perform game.s5_pindah(p_pid, 'mare', 'bjorneo');
    perform game.log(p_pid, 'Titian membawamu pulang ke kawah Bjorneo.');
    return jsonb_build_object('s5', game.s5_view(p_pid), 'pulang', true);
  end if;

  -- Mundur dari pencegatan: kapal kembali ke pelabuhan asal, pencegatan menunggu pelayaran berikutnya
  if v_act = 'mundur' then
    c := game.s5_sdata(p_pid) -> 'cegat';
    select * into l from game.player_location where player_id = p_pid for update;
    if not v_seb or jsonb_typeof(c) <> 'object' or coalesce(l.destination_city_id, '') <> c ->> 'dest' then
      raise exception 'Tidak ada yang mengejarmu, Kapten.';
    end if;
    update game.player_location set destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = p_pid;
    perform game.s5_sdata_set(p_pid, null, array['cegat']);
    return jsonb_build_object('s5', game.s5_view(p_pid), 'mundur', true);
  end if;

  if v_act not in ('maju', 'pilih') then raise exception 'Aksi tidak dikenal.'; end if;
  if game.in_transit(p_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, 's5', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step, data into v_step, v_data from game.player_quests where player_id = p_pid and quest_id = 's5' for update;
  v_data := coalesce(v_data, '{}'::jsonb);

  if v_step >= game.s5_ada() then raise exception 'Bersambung, Kapten. Laut ini belum selesai bercerita.'; end if;
  d := game.s5_steps() -> v_step;
  if coalesce((d ->> 'gb')::boolean, false) and not game.s5_gerbang_b(p_pid) then raise exception 'Bersambung, Kapten. Gunung itu tidak akan lari.'; end if;
  if v_want is null or v_want <> (d ->> 'n')::int then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  if d ? 'auto' then raise exception 'Ceritanya menunggu di tempat lain, Kapten.'; end if;
  if (coalesce(d ->> 'w', 'mare') = 'seberang') <> v_seb then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  v_city := game.current_city(p_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if d ->> 't' = 'malam' and not game.s5_malam() then raise exception 'Datanglah lagi saat lampu dinyalakan, Kapten.'; end if;

  if d ? 'pilih' then
    if v_act <> 'pilih' then raise exception 'Keputusannya ada di tanganmu, Kapten.'; end if;
    if not (d -> 'pilih' @> to_jsonb(v_res)) then raise exception 'Pilihan tidak dikenali.'; end if;
    v_tambah := jsonb_build_object('kabar_buku', v_res);
  elsif v_act = 'pilih' then
    raise exception 'Tidak ada yang harus dipilih di sini, Kapten.';
  end if;

  if d ? 'mg' and not (v_data ? ('mg' || (d ->> 'n'))) then raise exception 'Tanah belum menjawab, Kapten. Dengarkan lagi.'; end if;
  if d ? 'g' and v_res <> 'ok' then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;
  if coalesce((d ->> 'warlord')::boolean, false) and not game.wl_has(p_pid, 'speed') then
    raise exception 'Lambungmu belum lurus, Kapten. Mesin Jolt Warlord belum terpasang.';
  end if;
  if d ? 'jawab' then
    if (v_data ->> 'tekaSampai') is not null and game.now_ms() < (v_data ->> 'tekaSampai')::bigint then
      raise exception 'Ia memejamkan mata. Tunggu sebentar, Kapten.';
    end if;
    if regexp_replace(v_res, '[^a-z]', '', 'g') <> (d ->> 'jawab') then
      update game.player_quests set data = data || jsonb_build_object('tekaSampai', game.now_ms() + greatest(0, game.cfg_num('S5TekaJedaDetik', 20))::bigint * 1000)
       where player_id = p_pid and quest_id = 's5';
      return jsonb_build_object('s5', game.s5_view(p_pid), 'salah', true);
    end if;
  end if;

  g := game.s5_tuntas(p_pid, v_step + 1, v_tambah);
  return jsonb_build_object('s5', game.s5_view(p_pid), 'maju', true, 'gold', (g ->> 'gold')::bigint, 'q', (g ->> 'q')::int,
    'newGold', (select gold from game.players where player_id = p_pid));
end $$;
revoke all on function game.s5_act(uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 8. Alat uji GM (superset 0107)
--   gm_dunia mare|seberang : pindah dunia SEKALIGUS lokasi (Bjorneo / pulau gerbang)
--   gm_ke <kota s5>        : pindah ke pulau seberang mana pun (uji)
-- ---------------------------------------------------------------------
create or replace function game.s5_gm_act(p_pid uuid, a jsonb) returns jsonb
language plpgsql as $$
declare v_act text := lower(coalesce(game.arg(a, 0), '')); v_ke text := lower(coalesce(game.arg(a, 1), '')); v_n int;
begin
  if not game.is_gm(p_pid) then raise exception 'Aksi tidak dikenal.'; end if;
  perform game.s5_row(p_pid);
  if v_act = 'gm_dunia' then
    if v_ke not in ('mare', 'seberang') then raise exception 'Pilih mare atau seberang.'; end if;
    update game.s5_state set dunia = v_ke, data = data - 'cegat', updated_at = now() where player_id = p_pid;
    update game.player_location set city_id = case when v_ke = 'mare' then 'bjorneo' else 's5_p1' end,
      destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = p_pid;
    perform game.mp_touch(p_pid);
  elsif v_act = 'gm_ke' then
    if not exists (select 1 from game.cities where city_id = v_ke and city_id like 's5\_%') then raise exception 'Kota seberang tidak dikenal.'; end if;
    update game.s5_state set dunia = 'seberang', data = data - 'cegat', updated_at = now() where player_id = p_pid;
    update game.player_location set city_id = v_ke, destination_city_id = null, depart_at = null, arrive_at = null, pending_encounter = null where player_id = p_pid;
  elsif v_act = 'gm_reset_hari' then
    update game.s5_state set cross_day = null, tiket_day = null, updated_at = now() where player_id = p_pid;
  elsif v_act = 'gm_uji' then
    update game.s5_state set data = data || jsonb_build_object('uji', v_ke in ('1', 'true', 'on')), updated_at = now() where player_id = p_pid;
  elsif v_act = 'gm_pertama' then   -- ulangi titian pertama (kaki titian, preset pelangi)
    update game.s5_state set data = data - 'tiba', updated_at = now() where player_id = p_pid;
  elsif v_act = 'gm_langkah' then
    v_n := nullif(v_ke, '')::int;
    if v_n is null or v_n < 1 or v_n > game.s5_ada() + 1 then raise exception 'Langkah 1 sampai %.', game.s5_ada() + 1; end if;
    insert into game.player_quests(player_id, quest_id, step, data) values (p_pid, 's5', v_n - 1, '{}'::jsonb)
    on conflict (player_id, quest_id) do update set step = v_n - 1, updated_at = now(),
      data = (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from jsonb_each(game.player_quests.data) where key not like 'mg%' and key <> 'tekaSampai');
    update game.s5_state set data = data - 'cegat', updated_at = now() where player_id = p_pid;
    perform game.log(p_pid, '[GM] Uji jejak gunung: lompat ke langkah ' || v_n || '.');
  elsif v_act <> 'gm_status' then
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object('ok', true, 'gm', game.s5_gm_status(p_pid), 's5', game.s5_view(p_pid));
end $$;

create or replace function game.admin_s5(p_username text, p_langkah int) returns jsonb
language plpgsql as $$
declare v_pid uuid;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain tidak ditemukan.'; end if;
  if p_langkah < 1 or p_langkah > game.s5_ada() + 1 then raise exception 'Langkah 1 sampai %.', game.s5_ada() + 1; end if;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 's5', p_langkah - 1, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = p_langkah - 1, updated_at = now();
  return game.s5_view(v_pid);
end $$;
revoke all on function game.admin_s5(text, int) from public, anon, authenticated;
