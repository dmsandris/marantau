-- =====================================================================
-- Marantau (Supabase) - 0032 PESANAN HARIAN, KEPING RANTAU, KEDAI RANTAU,
-- GOTONG ROYONG (Tide v37 · Fase 1). Aman diulang.
--
-- Rancangan: dokumen project "KONSEP-Pesanan-Harian-dan-Lomba-Saudagar" (v3).
--
-- * Golongan (Jukung/Pinisi/Galiung) = saga yang sedang dijalani (gala & barsati).
-- * Keping Rantau = kolom game.players.keping. BOLEH diedit langsung di Supabase
--   (Table Editor -> schema game -> players -> kolom keping); setiap perubahan,
--   termasuk edit manual, tercatat otomatis di game.keping_log lewat trigger.
--   SQL: select game.admin_keping('username', 5000, 'catatan');
--        select game.admin_keping_all(1000, 'catatan');
-- * Pesanan Harian: lembar 3 tugas per hari WIB (reset 00:00 WIB), streak 7 tokoh,
--   Tali Tambat, Peti Rantau. Kejadian masuk lewat game.hr_hook (stub di 0001b).
-- * Kedai Rantau: rak Rupa (barang Biasa Fase 1) & Jasa. Harga di game.kd_items
--   (kolom price_admin menimpa harga bawaan) dikali config KedaiPriceMul.
-- * Gotong Royong: Restorasi IKN, total 100 juta gold (keping dihitung
--   GotongKepingRate gold per keping). Satu kolam bersama: setiap kali total kumulatif
--   melewati 5/15/35/60/100 juta, kota IKN berubah untuk semua pemain. Kategori
--   penyumbang dari total pribadi: 1 (< 1 jt), 2 (1-2,5 jt), 3 (2,5-15 jt, batas per
--   kapten). Kategori 3 = Sayap Garuda (terbatas, bernomor). Selesai: kapal yang
--   merapat di IKN sembuh gratis.
-- * Mode penguji: HarianOpen / KedaiOpen / GotongOpen = '0' -> hanya username
--   di FiturPenguji (dipisah koma) yang melihat fitur. '1' = buka untuk semua.
-- =====================================================================

insert into game.config(key, value) values
  ('HarianOpen', '0'), ('KedaiOpen', '0'), ('GotongOpen', '0'), ('FiturPenguji', ''),
  ('KedaiPriceMul', '1'), ('HarianClockOffset', '0'), ('PacuFloorRatio', '0.6'),
  ('HarianGoldJukung', '1000,2500,5000'), ('HarianGoldPinisi', '5000,15000,30000'), ('HarianGoldGaliung', '20000,50000,100000'),
  ('HarianKeping', '5,10,20'), ('HarianSapuKeping', '10'), ('HarianStreakKeping', '5'), ('HarianPetiKeping', '30'),
  ('GotongKepingRate', '1000'), ('GotongKategori', '3000000,15000000'), ('GotongMaxPerKapten', '0'), ('GotongMinDonasi', '1000')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Gerbang fitur (mode penguji)
-- ---------------------------------------------------------------------
create or replace function game.fitur_on(p_pid uuid, p_key text) returns boolean
language plpgsql stable as $$
declare v_list text := lower(replace(coalesce(game.cfg('FiturPenguji'), ''), ' ', '')); v_u text;
begin
  if lower(coalesce(game.cfg(p_key), '0')) in ('1', 'true', 'on', 'ya') then return true; end if;
  if v_list = '' or p_pid is null then return false; end if;
  select lower(coalesce(username, '')) into v_u from game.players where player_id = p_pid;
  return coalesce(v_u, '') <> '' and v_u = any (string_to_array(v_list, ','));
end $$;

-- ---------------------------------------------------------------------
-- Keping Rantau
-- ---------------------------------------------------------------------
alter table game.players add column if not exists keping bigint not null default 0;
do $$ begin
  alter table game.players add constraint players_keping_nonneg check (keping >= 0);
exception when duplicate_object then null;
end $$;

create table if not exists game.keping_log (
  id        bigserial primary key,
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  ts        timestamptz not null default now(),
  delta     bigint not null,
  saldo     bigint not null,
  sumber    text not null,          -- harian | streak | peti | kedai | gotong | admin | manual (edit langsung di tabel)
  catatan   text
);
create index if not exists keping_log_player_idx on game.keping_log (player_id, ts desc);
alter table game.keping_log enable row level security;

create or replace function game.keping_trg() returns trigger
language plpgsql as $$
begin
  if new.keping is distinct from old.keping then
    insert into game.keping_log(player_id, delta, saldo, sumber, catatan)
    values (new.player_id, new.keping - old.keping, new.keping,
      coalesce(nullif(current_setting('mt.keping_src', true), ''), 'manual'),
      nullif(current_setting('mt.keping_note', true), ''));
  end if;
  return new;
end $$;
drop trigger if exists players_keping_log on game.players;
create trigger players_keping_log after update of keping on game.players
  for each row execute function game.keping_trg();

-- Satu-satunya jalur kode untuk mengubah keping. Menolak saldo negatif.
create or replace function game.keping_add(p_pid uuid, p_delta bigint, p_src text, p_note text default null) returns bigint
language plpgsql as $$
declare v bigint;
begin
  if coalesce(p_delta, 0) = 0 then return (select keping from game.players where player_id = p_pid); end if;
  perform set_config('mt.keping_src', coalesce(p_src, 'game'), true);
  perform set_config('mt.keping_note', coalesce(p_note, ''), true);
  update game.players set keping = keping + p_delta
   where player_id = p_pid and keping + p_delta >= 0
  returning keping into v;
  perform set_config('mt.keping_src', '', true);
  perform set_config('mt.keping_note', '', true);
  if v is null then raise exception 'Keping Rantau tidak cukup.'; end if;
  return v;
end $$;

-- Admin (hanya dari SQL Editor Supabase; schema game tidak terbuka untuk API)
create or replace function game.admin_keping(p_user text, p_delta bigint, p_note text default 'admin') returns text
language plpgsql as $$
declare v_pid uuid; v_name text; v_have bigint; v bigint;
begin
  select player_id, character_name, keping into v_pid, v_name, v_have from game.players
   where lower(username) = lower(trim(p_user)) or lower(character_name) = lower(trim(p_user))
   order by (lower(username) = lower(trim(p_user))) desc limit 1;
  if v_pid is null then raise exception 'Kapten "%" tidak ditemukan (pakai username atau nama kapten).', p_user; end if;
  v := game.keping_add(v_pid, greatest(p_delta, -v_have), 'admin', p_note);
  return coalesce(nullif(v_name, ''), p_user) || ': ' || v || ' keping';
end $$;

create or replace function game.admin_keping_all(p_delta bigint, p_note text default 'admin') returns int
language plpgsql as $$
declare r record; n int := 0;
begin
  for r in select player_id, keping from game.players where archetype <> '' loop
    perform game.keping_add(r.player_id, greatest(p_delta, -r.keping), 'admin', p_note);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function game.admin_keping(text, bigint, text) from public;
revoke all on function game.admin_keping_all(bigint, text) from public;

-- ---------------------------------------------------------------------
-- Golongan: 1 Jukung (Quest 1 belum tamat) · 2 Pinisi (Saga Pertama) · 3 Galiung (Saga Kedua)
-- ---------------------------------------------------------------------
create or replace function game.golongan(p_pid uuid) returns int
language sql stable as $$
  select case
    when coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'gala'), 0) < 6 then 1
    when coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'barsati'), 0) < 16 then 2
    else 3 end
$$;
create or replace function game.golongan_nama(p_gol int) returns text
language sql immutable as $$ select case p_gol when 1 then 'Jukung' when 2 then 'Pinisi' else 'Galiung' end $$;

-- ---------------------------------------------------------------------
-- Waktu WIB (UTC+7, tanpa musim panas). HarianClockOffset (ms) untuk uji.
-- ---------------------------------------------------------------------
create or replace function game.hr_now() returns timestamptz
language sql stable as $$
  select clock_timestamp() + make_interval(secs => game.cfg_num('HarianClockOffset', 0)::double precision / 1000)
$$;
create or replace function game.hr_today() returns date
language sql stable as $$ select ((game.hr_now() at time zone 'UTC') + interval '7 hours')::date $$;
-- ms sampai lembar berikutnya (00:00 WIB)
create or replace function game.hr_reset_in_ms() returns bigint
language sql stable as $$
  select greatest(0, (extract(epoch from ((((game.hr_today() + 1)::timestamp) - interval '7 hours') at time zone 'UTC') - game.hr_now()) * 1000))::bigint
$$;

-- Untung Pacu: modal per unit tidak pernah di bawah PacuFloorRatio x harga dasar (anti barang gratis/Bursa)
create or replace function game.pacu_profit(p_revenue numeric, p_qty numeric, p_avg numeric, p_base numeric) returns numeric
language sql stable as $$
  select round(coalesce(p_revenue, 0) - coalesce(p_qty, 0) * greatest(coalesce(p_avg, 0), game.cfg_num('PacuFloorRatio', 0.6) * coalesce(p_base, 0)))
$$;

-- ---------------------------------------------------------------------
-- Pesanan Harian: katalog tugas
--   t = tingkat (1 Mudah, 2 Sedang, 3 Tantangan), g = kelompok (tidak boleh dobel dalam satu lembar)
--   n = angka per golongan [Jukung, Pinisi, Galiung], goal = 'n' (hitung sampai n) atau 1 (sekali tercapai)
--   l = label ({n} diganti angka di klien), req = syarat muncul
-- ---------------------------------------------------------------------
create or replace function game.hr_catalog() returns jsonb
language sql immutable as $$ select '[
  {"c":"M1","t":1,"g":"untung","l":"Jual satu muatan dengan untung minimal {n} gold","n":[200,2000,10000],"goal":1},
  {"c":"M2","t":1,"g":"singgah","l":"Singgah di {n} pelabuhan berbeda","n":[2,2,2],"goal":"n"},
  {"c":"M3","t":1,"g":"ikan","l":"Pancing {n} ikan di dermaga","n":[3,3,3],"goal":"n"},
  {"c":"M4","t":1,"g":"misi","l":"Antar {n} Titipan gubernur","n":[1,1,1],"goal":"n"},
  {"c":"M5","t":1,"l":"Beli barang di pulau penghasilnya","n":[1,1,1],"goal":1},
  {"c":"M6","t":1,"l":"Rawat kapal di galangan","n":[1,1,1],"goal":1,"req":"repair"},
  {"c":"S1","t":2,"g":"untung","l":"Kumpulkan untung dagang {n} gold hari ini","n":[3000,30000,150000],"goal":"n"},
  {"c":"S2","t":2,"g":"misi","l":"Selesaikan {n} Pesanan gubernur","n":[1,1,1],"goal":"n"},
  {"c":"S3","t":2,"l":"Kalahkan {n} kapal bajak laut","n":[1,1,1],"goal":"n"},
  {"c":"S4","t":2,"g":"singgah","l":"Jual dengan untung di {n} pulau berbeda","n":[3,3,3],"goal":"n"},
  {"c":"S5","t":2,"l":"Jual dengan untung barang yang sedang Dicari","n":[1,1,1],"goal":1},
  {"c":"S6","t":2,"g":"ikan","l":"Pancing {n} ikan yang hanya muncul malam","n":[1,1,1],"goal":"n","req":"fishbook"},
  {"c":"T1","t":3,"g":"untung","l":"Kumpulkan untung dagang {n} gold hari ini","n":[10000,100000,500000],"goal":"n"},
  {"c":"T2","t":3,"l":"Rute panjang: jual dengan untung jauh dari tempat membelinya","n":[1,1,1],"goal":1},
  {"c":"T3","t":3,"g":"misi","l":"Selesaikan misi gubernur di {n} kota berbeda","n":[2,2,2],"goal":"n"},
  {"c":"T4","t":3,"l":"Jual dengan untung di pulau tersembunyi","n":[1,1,1],"goal":1,"req":"hidden"},
  {"c":"T5","t":3,"l":"Gali harta karun","n":[1,1,1],"goal":1,"req":"map"},
  {"c":"T6","t":3,"l":"Bertransaksi di Bursa Kapten","n":[1,1,1],"goal":1,"req":"bursa"}
]'::jsonb $$;

create or replace function game.hr_req_ok(p_pid uuid, p_req text) returns boolean
language plpgsql stable as $$
begin
  if p_req is null or p_req = '' then return true; end if;
  if p_req = 'repair' then
    return coalesce((select s.condition < game.voy_max_cond(p_pid) from game.ships s where s.player_id = p_pid), false);
  elsif p_req = 'fishbook' then
    return exists (select 1 from game.mp_fish_book where player_id = p_pid);
  elsif p_req = 'hidden' then
    return exists (select 1 from jsonb_array_elements_text(coalesce(game.player_unlocks(p_pid), '[]'::jsonb)) u
                     join game.cities c on c.city_id = u.value
                    where c.hidden and not coalesce(game.spot_city(u.value), false));
  elsif p_req = 'map' then
    return exists (select 1 from game.inventory i join game.item_catalog c on c.item_id = i.item_id
                    where i.player_id = p_pid and i.qty > 0 and c.type = 'treasure_map');
  elsif p_req = 'bursa' then
    return (select count(*) from game.players where player_id <> p_pid and archetype <> '' and last_active > now() - interval '24 hours') >= 3;
  end if;
  return true;
end $$;

create or replace function game.hr_num(p_csv text, p_idx int, p_def numeric) returns numeric
language plpgsql immutable as $$
declare a text[] := string_to_array(replace(coalesce(p_csv, ''), ' ', ''), ',');
begin
  return coalesce(nullif(a[p_idx], '')::numeric, p_def);
exception when others then return p_def;
end $$;
create or replace function game.hr_gold(p_gol int, p_tier int) returns bigint
language sql stable as $$
  select game.hr_num(game.cfg(case p_gol when 1 then 'HarianGoldJukung' when 2 then 'HarianGoldPinisi' else 'HarianGoldGaliung' end), p_tier,
    (case p_gol when 1 then array[1000, 2500, 5000] when 2 then array[5000, 15000, 30000] else array[20000, 50000, 100000] end)[p_tier])::bigint
$$;
create or replace function game.hr_kp(p_tier int) returns bigint
language sql stable as $$ select game.hr_num(game.cfg('HarianKeping'), p_tier, (array[5, 10, 20])[p_tier])::bigint $$;

-- ---------------------------------------------------------------------
-- Lembar harian
-- ---------------------------------------------------------------------
create table if not exists game.hr_sheets (
  player_id    uuid not null references game.players(player_id) on update cascade on delete cascade,
  day          date not null,
  npc          int not null,            -- 1 Senin .. 7 Minggu (tokoh pemberi pesanan)
  gol          int not null,            -- golongan saat lembar dibuat (menentukan gold)
  tasks        jsonb not null,          -- [{c,t,g,l,n,goal,p,s,x,done,gold,kp,at}]
  reroll       int not null default 0,  -- tukar yang sudah dipakai
  reroll_bonus int not null default 0,  -- tambahan dari jasa Tukar Pesanan
  swapped      jsonb not null default '[]'::jsonb,
  lunas        boolean not null default false,
  sapu         boolean not null default false,
  created      timestamptz not null default now(),
  primary key (player_id, day)
);
alter table game.hr_sheets enable row level security;

create table if not exists game.hr_streak (
  player_id    uuid primary key references game.players(player_id) on update cascade on delete cascade,
  cur          int not null default 0,
  best         int not null default 0,
  last_day     date,
  tambat_day   date,                    -- hari bolong terakhir yang dimaafkan Tali Tambat
  tambat_extra int not null default 0,  -- Tali Tambat Cadangan (jasa Kedai)
  peti_n       int not null default 0
);
alter table game.hr_streak add column if not exists clean int not null default 0;        -- hari berturut-turut tanpa Tali Tambat
alter table game.hr_streak add column if not exists clean_best int not null default 0;   -- Tanda Jasa rahasia Tak Pernah Bolong (30)
alter table game.hr_streak enable row level security;

create or replace function game.hr_pick(p_pid uuid, p_day date, p_tier int, p_gol int, p_dow int,
  p_used text[], p_groups text[], p_avoid text[], p_strict boolean default true) returns jsonb
language plpgsql as $$
declare e jsonb;
begin
  select x into e from jsonb_array_elements(game.hr_catalog()) x
   where (x ->> 't')::int = p_tier
     and not ((x ->> 'c') = any (p_used))
     and not ((x ->> 'c') = any (p_avoid))
     and (not p_strict or not (coalesce(x ->> 'g', x ->> 'c') = any (p_groups)))
     and (not p_strict or p_tier < 3 or p_dow < 6 or (x ->> 'c') in ('T1', 'T2', 'T4'))   -- akhir pekan: Tantangan selalu dagang
     and game.hr_req_ok(p_pid, x ->> 'req')
   order by md5(p_pid::text || p_day::text || (x ->> 'c')) limit 1;
  if e is null then return null; end if;
  return jsonb_build_object('c', e ->> 'c', 't', p_tier, 'g', coalesce(e ->> 'g', e ->> 'c'), 'l', e ->> 'l',
    'n', (e -> 'n') -> (p_gol - 1),
    'goal', case when e ->> 'goal' = 'n' then (e -> 'n') -> (p_gol - 1) else to_jsonb(1) end,
    'p', 0, 's', 0, 'x', '[]'::jsonb, 'done', false,
    'gold', game.hr_gold(p_gol, p_tier), 'kp', game.hr_kp(p_tier));
end $$;

create or replace function game.hr_sheet(p_pid uuid) returns game.hr_sheets
language plpgsql as $$
declare d date := game.hr_today(); r game.hr_sheets; v_prev text[]; v_gol int; v_dow int; v_tasks jsonb := '[]'::jsonb;
  v_used text[] := '{}'; v_groups text[] := '{}'; t int; e jsonb;
begin
  select * into r from game.hr_sheets where player_id = p_pid and day = d;
  if found then return r; end if;
  select coalesce(array_agg(x ->> 'c'), '{}') into v_prev
    from game.hr_sheets s, jsonb_array_elements(s.tasks) x where s.player_id = p_pid and s.day = d - 1;
  v_gol := game.golongan(p_pid);
  v_dow := extract(isodow from d)::int;
  for t in 1..3 loop
    e := game.hr_pick(p_pid, d, t, v_gol, v_dow, v_used, v_groups, v_prev);
    if e is null then e := game.hr_pick(p_pid, d, t, v_gol, v_dow, v_used, v_groups, '{}'); end if;
    if e is null then e := game.hr_pick(p_pid, d, t, v_gol, v_dow, v_used, v_groups, '{}', false); end if;
    if e is null then continue; end if;
    v_tasks := v_tasks || jsonb_build_array(e);
    v_used := v_used || (e ->> 'c');
    v_groups := v_groups || (e ->> 'g');
  end loop;
  insert into game.hr_sheets(player_id, day, npc, gol, tasks) values (p_pid, d, v_dow, v_gol, v_tasks)
  on conflict (player_id, day) do nothing;
  select * into r from game.hr_sheets where player_id = p_pid and day = d;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- Kedai: katalog & kepemilikan (dipakai Peti Rantau juga)
-- ---------------------------------------------------------------------
create table if not exists game.kd_items (
  id          text primary key,
  rak         text not null,                -- rupa | jasa
  slot        text,                         -- rupa: lambung layar haluan panji jejak aura meriam kedatangan penghuni
  set_id      text,
  name        text not null,
  rarity      text not null default 'biasa',-- biasa | langka | agung | legenda
  price       int not null default 0,       -- harga bawaan (keping)
  price_admin int,                          -- diisi admin untuk menimpa harga bawaan
  info        text,
  tokoh       text,
  req         jsonb,
  exclusive   boolean not null default false, -- tidak dijual (hadiah)
  active      boolean not null default true,
  sort        int not null default 0
);
alter table game.kd_items enable row level security;

insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, exclusive, active, sort) values
  -- Rak Rupa · Fase 1 (Biasa, pintu masuk ±2 pekan)
  ('layar_parang',  'rupa', 'layar', null, 'Layar Batik Parang', 'biasa', 750, 'Motif parang miring yang terlihat jelas saat layar terkembang.', null, false, true, 110),
  ('layar_songket', 'rupa', 'layar', null, 'Layar Songket',      'biasa', 750, 'Benang emas berpola di atas warna layar pilihanmu.', null, false, true, 111),
  ('layar_ikat',    'rupa', 'layar', null, 'Layar Tenun Ikat',   'biasa', 750, 'Pola ikat geometris berwarna tanah.', null, false, true, 112),
  ('layar_kawung',  'rupa', 'layar', null, 'Layar Kawung',       'biasa', 750, 'Motif kawung bulat bersusun.', null, false, true, 113),
  ('panji_umbul',   'rupa', 'panji', null, 'Umbul-umbul Tujuh Warna', 'biasa', 900, 'Umbul-umbul tinggi melengkung di buritan.', null, false, true, 120),
  ('panji_susun',   'rupa', 'panji', null, 'Panji Bersusun',     'biasa', 900, 'Tiga panji bertingkat di tiang utama.', null, false, true, 121),
  ('panji_walet',   'rupa', 'panji', null, 'Ekor Walet Ganda',   'biasa', 800, 'Bendera bercabang dua yang berkibar cepat.', null, false, true, 122),
  ('haluan_ikan',   'rupa', 'haluan', null, 'Haluan Ikan Terbang', 'biasa', 1000, 'Patung ikan terbang bersayap terbentang di ujung haluan.', null, false, true, 130),
  ('penghuni_kucing','rupa','penghuni', null, 'Kucing Belang',   'biasa', 1000, 'Tidur di atas peti muatan; melompat ke dermaga saat merapat.', null, false, true, 140),
  ('aura_lampion',  'rupa', 'aura', null, 'Lampion Dek',         'biasa', 1000, 'Deretan lampion menyala di malam hari, pantulannya di air.', null, false, true, 150),
  -- Rupa eksklusif (tidak dijual)
  ('panji_tujuh',   'rupa', 'panji', null, 'Panji Tujuh Tokoh',  'biasa', 0, 'Tujuh wajah tokoh Marantau di umbul-umbul. Hanya dari Peti Rantau.', null, true, true, 190),
  ('aura_lentera_ikn','rupa','aura', null, 'Lentera IKN',        'langka', 0, 'Lentera tua IKN yang menyala lagi. Untuk penyumbang Restorasi IKN kategori 2.', null, true, true, 191),
  ('lambang_garuda', 'rupa','lambang', null, 'Sayap Garuda',      'legenda', 0, 'Sayap Garuda emas membentang di atas kapal. Hanya untuk penyumbang Restorasi IKN kategori 3, bernomor, tidak akan pernah dibuat lagi.', null, true, true, 192),
  -- Rak Jasa (sementara / sekali pakai)
  ('jasa_kupon',    'jasa', null, null, 'Kupon Reparasi',       'biasa', 200, 'Reparasi penuh gratis di galangan mana pun.', 'Uda Gala', false, true, 210),
  ('jasa_jala',     'jasa', null, null, 'Jala Penuh',           'biasa', 125, 'Jatah mancing langsung penuh.', 'Pak Tua Karto', false, true, 211),
  ('jasa_tukar',    'jasa', null, null, 'Tukar Pesanan',        'biasa', 75,  'Satu kali tukar tugas tambahan hari ini (maks 2 per hari).', 'dwi de''clown', false, true, 212),
  ('jasa_tambat',   'jasa', null, null, 'Tali Tambat Cadangan', 'biasa', 250, 'Menjaga streak dari satu hari bolong tambahan (maks 3 disimpan).', 'Teh Euis', false, true, 213),
  ('jasa_taksir',   'jasa', null, null, 'Juru Taksir',          'biasa', 300, 'Sekali pakai: tiga pelabuhan dengan harga jual terbaik untuk isi palkamu.', 'Pak Tua Karto', false, true, 214),
  ('jasa_pengawal', 'jasa', null, null, 'Pengawal Daeng',       'biasa', 350, 'Dua pencegatan bajak laut berikutnya: perahu Daeng ikut menembak.', 'Daeng Sore', false, true, 215),
  ('jasa_arus',     'jasa', null, null, 'Pembaca Arus',         'biasa', 400, 'Tiga pelayaran berikutnya 15% lebih cepat.', 'Nenek Ulin', false, true, 216)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

create table if not exists game.kd_owned (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  item_id   text not null,
  qty       int not null default 1,
  acquired  timestamptz not null default now(),
  source    text,
  primary key (player_id, item_id)
);
alter table game.kd_owned enable row level security;

create table if not exists game.kd_loadout (
  player_id uuid primary key references game.players(player_id) on update cascade on delete cascade,
  equipped  jsonb not null default '{}'::jsonb,   -- {slot: item_id}
  incaran   text
);
alter table game.kd_loadout enable row level security;

create table if not exists game.kd_buffs (
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  kind       text not null,            -- pengawal | arus
  uses_left  int not null,
  started    timestamptz not null default now(),
  primary key (player_id, kind)
);
alter table game.kd_buffs enable row level security;

create or replace function game.kd_price(p_id text) returns int
language sql stable as $$
  select greatest(0, round(coalesce(i.price_admin, i.price) * game.cfg_num('KedaiPriceMul', 1)))::int from game.kd_items i where i.id = p_id
$$;
-- syarat beli (req): {"kisah": "<id bab>"} = bab Kisah Lapau sudah tamat
create or replace function game.kd_req_ok(p_pid uuid, p_id text) returns boolean
language sql stable as $$
  select coalesce((select case when i.req ? 'kisah' then game.kisah_done(p_pid, i.req ->> 'kisah') else true end from game.kd_items i where i.id = p_id), true)
$$;
create or replace function game.kd_qty(p_pid uuid, p_id text) returns int
language sql stable as $$ select coalesce((select qty from game.kd_owned where player_id = p_pid and item_id = p_id), 0) $$;
create or replace function game.kd_grant(p_pid uuid, p_id text, p_qty int, p_src text) returns void
language plpgsql as $$
declare it game.kd_items;
begin
  select * into it from game.kd_items where id = p_id;
  if not found then raise exception 'Barang Kedai tidak dikenal: %', p_id; end if;
  if it.rak = 'rupa' then
    insert into game.kd_owned(player_id, item_id, qty, source) values (p_pid, p_id, 1, p_src) on conflict (player_id, item_id) do nothing;
  else
    insert into game.kd_owned as o (player_id, item_id, qty, source) values (p_pid, p_id, greatest(1, p_qty), p_src)
    on conflict (player_id, item_id) do update set qty = o.qty + greatest(1, p_qty);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Streak & Peti Rantau
-- ---------------------------------------------------------------------
create or replace function game.hr_peti(p_pid uuid, p_n int) returns jsonb
language plpgsql as $$
declare v_roll numeric := random() * 100; v_id text; v_has boolean := game.kd_qty(p_pid, 'panji_tujuh') > 0;
begin
  if not v_has and p_n >= 8 then v_id := 'panji_tujuh';            -- dijamin pada Peti ke-8
  elsif v_roll < 35 then v_id := 'jasa_kupon';
  elsif v_roll < 60 then v_id := 'jasa_jala';
  elsif v_roll < 80 then v_id := 'jasa_arus';
  elsif v_roll < 95 then v_id := 'jasa_tambat';
  elsif not v_has then v_id := 'panji_tujuh';
  else v_id := 'jasa_kupon';
  end if;
  perform game.kd_grant(p_pid, v_id, 1, 'peti');
  return jsonb_build_object('item', v_id, 'name', (select name from game.kd_items where id = v_id));
end $$;

create or replace function game.hr_streak_tick(p_pid uuid, p_day date) returns jsonb
language plpgsql as $$
declare s game.hr_streak; v_pos int; v_kp bigint; v_peti jsonb; v_how text := 'lanjut';
begin
  insert into game.hr_streak(player_id) values (p_pid) on conflict (player_id) do nothing;
  select * into s from game.hr_streak where player_id = p_pid for update;
  if s.last_day = p_day then return null; end if;
  if s.last_day = p_day - 1 then s.cur := s.cur + 1;
  elsif s.last_day = p_day - 2 and (s.tambat_day is null or s.tambat_day < p_day - 7) then
    s.cur := s.cur + 1; s.tambat_day := p_day - 1; v_how := 'tambat';
  elsif s.last_day = p_day - 2 and s.tambat_extra > 0 then
    s.cur := s.cur + 1; s.tambat_extra := s.tambat_extra - 1; v_how := 'cadangan';
  else s.cur := 1; v_how := case when s.last_day is null then 'mulai' else 'ulang' end;
  end if;
  s.last_day := p_day;
  s.best := greatest(s.best, s.cur);
  s.clean := case when v_how = 'lanjut' then s.clean + 1 else 1 end;
  s.clean_best := greatest(s.clean_best, s.clean);
  v_pos := ((s.cur - 1) % 7) + 1;
  if v_pos = 7 then
    s.peti_n := s.peti_n + 1;
    v_kp := game.cfg_num('HarianPetiKeping', 30)::bigint;
  else
    v_kp := game.cfg_num('HarianStreakKeping', 5)::bigint;
  end if;
  update game.hr_streak set cur = s.cur, best = s.best, last_day = s.last_day, tambat_day = s.tambat_day,
    tambat_extra = s.tambat_extra, peti_n = s.peti_n, clean = s.clean, clean_best = s.clean_best where player_id = p_pid;
  if v_pos = 7 then v_peti := game.hr_peti(p_pid, s.peti_n); end if;
  perform game.keping_add(p_pid, v_kp, case when v_pos = 7 then 'peti' else 'streak' end, 'streak ' || s.cur);
  return jsonb_build_object('cur', s.cur, 'pos', v_pos, 'kp', v_kp, 'peti', v_peti, 'how', v_how, 'best', s.best);
end $$;

-- ---------------------------------------------------------------------
-- Kejadian -> kemajuan tugas
-- ---------------------------------------------------------------------
create or replace function game.hr_wanted(p_city text, p_comm text) returns boolean
language plpgsql stable as $$
begin
  return coalesce(game.mkt_cycle_tags(p_city, game.mkt_cycle_index()) -> 'wanted' ? p_comm, false);
exception when others then return false;
end $$;
create or replace function game.hr_far(p_src text, p_dst text) returns boolean
language plpgsql stable as $$
declare d double precision; mx double precision;
begin
  if p_src is null or p_dst is null or p_src = p_dst then return false; end if;
  d := game.voy_map_distance(p_src, p_dst);
  select dmax into mx from game.voy_dist_range();
  return d is not null and mx is not null and mx > 0 and d >= 0.6 * mx;
exception when others then return false;
end $$;

create or replace function game.hr_event(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
declare r game.hr_sheets; v_tasks jsonb; t jsonb; i int; c text; n numeric; goal numeric; p numeric; v_new numeric;
  v_profit numeric; v_city text; v_x jsonb; v_done jsonb := '[]'::jsonb; v_cnt int := 0; v_streak jsonb; v_sapu boolean := false;
  v_lunas boolean := false; v_changed boolean := false;
begin
  r := game.hr_sheet(p_pid);
  if r.player_id is null then return; end if;
  select * into r from game.hr_sheets where player_id = p_pid and day = r.day for update;
  v_tasks := r.tasks;
  v_city := p_ctx ->> 'city';
  if p_kind = 'sell' then
    v_profit := game.pacu_profit(p_amount, (p_ctx ->> 'qty')::numeric, (p_ctx ->> 'avg')::numeric, (p_ctx ->> 'base')::numeric);
  end if;

  for i in 0 .. jsonb_array_length(v_tasks) - 1 loop
    t := v_tasks -> i;
    if coalesce((t ->> 'done')::boolean, false) then continue; end if;
    c := t ->> 'c'; n := (t ->> 'n')::numeric; goal := (t ->> 'goal')::numeric; p := coalesce((t ->> 'p')::numeric, 0);
    v_new := null; v_x := coalesce(t -> 'x', '[]'::jsonb);
    if c = 'M1' and p_kind = 'sell' and v_profit >= n then v_new := 1;
    elsif c = 'M2' and p_kind = 'arrive' and v_city is not null and not (v_x ? v_city) then
      v_x := v_x || to_jsonb(v_city); v_new := jsonb_array_length(v_x);
    elsif c = 'M3' and p_kind = 'fish' then v_new := p + 1;
    elsif c = 'M4' and p_kind = 'mission' and p_ctx ->> 'type' = 'courier' then v_new := p + 1;
    elsif c = 'M5' and p_kind = 'buy' and p_ctx ->> 'role' = 'produce' then v_new := 1;
    elsif c = 'M6' and p_kind = 'repair' then v_new := 1;
    elsif c in ('S1', 'T1') and p_kind = 'sell' then
      t := jsonb_set(t, '{s}', to_jsonb(coalesce((t ->> 's')::numeric, 0) + v_profit));
      v_new := greatest(0, (t ->> 's')::numeric);
    elsif c = 'S2' and p_kind = 'mission' and p_ctx ->> 'type' = 'procure' then v_new := p + 1;
    elsif c = 'S3' and p_kind = 'combat_win' then v_new := p + 1;
    elsif c = 'S4' and p_kind = 'sell' and v_profit > 0 and v_city is not null and not (v_x ? v_city) then
      v_x := v_x || to_jsonb(v_city); v_new := jsonb_array_length(v_x);
    elsif c = 'S5' and p_kind = 'sell' and v_profit > 0 and game.hr_wanted(v_city, p_ctx ->> 'comm') then v_new := 1;
    elsif c = 'S6' and p_kind = 'fish' and coalesce((p_ctx ->> 'night')::boolean, false) then v_new := p + 1;
    elsif c = 'T2' and p_kind = 'sell' and v_profit > 0 and game.hr_far(p_ctx ->> 'src', v_city) then v_new := 1;
    elsif c = 'T3' and p_kind = 'mission' and v_city is not null and not (v_x ? v_city) then
      v_x := v_x || to_jsonb(v_city); v_new := jsonb_array_length(v_x);
    elsif c = 'T4' and p_kind = 'sell' and v_profit > 0 and coalesce((select hidden from game.cities where city_id = v_city), false) then v_new := 1;
    elsif c = 'T5' and p_kind = 'dig' then v_new := p + 1;
    elsif c = 'T6' and p_kind = 'bursa' then v_new := p + 1;
    end if;
    if v_new is null then continue; end if;
    v_changed := true;
    t := t || jsonb_build_object('p', least(v_new, goal), 'x', v_x);
    if v_new >= goal then
      t := t || jsonb_build_object('done', true, 'at', game.now_ms());
      update game.players set gold = gold + (t ->> 'gold')::bigint where player_id = p_pid;
      perform game.keping_add(p_pid, (t ->> 'kp')::bigint, 'harian', c);
      perform game.log(p_pid, 'Pesanan Harian selesai: ' || replace(t ->> 'l', '{n}', (t ->> 'n')) || ' (+' || (t ->> 'gold') || ' gold, +' || (t ->> 'kp') || ' keping).');
      v_done := v_done || jsonb_build_array(jsonb_build_object('c', c, 't', t -> 't', 'l', t ->> 'l', 'n', t -> 'n', 'gold', t -> 'gold', 'kp', t -> 'kp'));
    end if;
    v_tasks := jsonb_set(v_tasks, array[i::text], t);
  end loop;
  if not v_changed then return; end if;

  select count(*) into v_cnt from jsonb_array_elements(v_tasks) x where coalesce((x ->> 'done')::boolean, false);
  if v_cnt >= 2 and not r.lunas then v_lunas := true; v_streak := game.hr_streak_tick(p_pid, r.day); end if;
  if v_cnt >= 3 and not r.sapu then
    v_sapu := true;
    perform game.keping_add(p_pid, game.cfg_num('HarianSapuKeping', 10)::bigint, 'harian', 'sapu bersih');
  end if;
  update game.hr_sheets set tasks = v_tasks, lunas = lunas or v_lunas, sapu = sapu or v_sapu
   where player_id = p_pid and day = r.day;
  if jsonb_array_length(v_done) > 0 or v_lunas or v_sapu then
    perform game.mp_push_inbox(p_pid, jsonb_build_object('type', 'harian', 'done', v_done, 'lunas', v_lunas, 'sapu', v_sapu,
      'streak', v_streak, 'npc', r.npc, 'keping', (select keping from game.players where player_id = p_pid)));
  end if;
end $$;

-- Pintu kejadian dari endpoint inti: tidak pernah menggagalkan aksi (dagang tetap jalan walau Pesanan error)
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
begin
  if p_pid is null or not game.fitur_on(p_pid, 'HarianOpen') then return; end if;
  begin
    perform game.hr_event(p_pid, p_kind, p_amount, coalesce(p_ctx, '{}'::jsonb));
  exception when others then
    raise warning '[harian] % %: %', p_kind, p_pid, sqlerrm;
  end;
end $$;

-- ---------------------------------------------------------------------
-- Status untuk klien (key 'harian' di getGameState)
-- ---------------------------------------------------------------------
create or replace function game.hr_streak_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare s game.hr_streak; d date := game.hr_today(); v_alive boolean; v_today boolean; v_filled int; v_tambat boolean;
begin
  select * into s from game.hr_streak where player_id = p_pid;
  if not found then
    return jsonb_build_object('cur', 0, 'best', 0, 'alive', false, 'today', false, 'filled', 0, 'tambatReady', true, 'extra', 0, 'petiN', 0);
  end if;
  v_today := s.last_day = d;
  v_tambat := s.tambat_day is null or s.tambat_day < d - 7;   -- bolong kemarin masih bisa dimaafkan hari ini (sama dengan hr_streak_tick)
  v_alive := s.last_day >= d - 1 or (s.last_day = d - 2 and (v_tambat or s.tambat_extra > 0));
  v_filled := case when not v_alive then 0 when v_today then ((s.cur - 1) % 7) + 1 else s.cur % 7 end;
  return jsonb_build_object('cur', case when v_alive then s.cur else 0 end, 'best', s.best, 'alive', v_alive, 'today', v_today,
    'filled', v_filled, 'pending', s.last_day = d - 2 and v_alive,
    'tambatReady', s.tambat_day is null or s.tambat_day < d - 7, 'extra', s.tambat_extra, 'petiN', s.peti_n,
    'cleanBest', s.clean_best,
    'tambatDays', case when s.tambat_day is not null and s.tambat_day >= d - 7 then jsonb_build_array(s.tambat_day) else '[]'::jsonb end);
end $$;

create or replace function game.harian_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_h boolean := game.fitur_on(p_pid, 'HarianOpen'); v_k boolean := game.fitur_on(p_pid, 'KedaiOpen');
  v_g boolean := game.fitur_on(p_pid, 'GotongOpen'); r game.hr_sheets; v_gol int := game.golongan(p_pid); o jsonb; l game.kd_loadout;
begin
  if not (v_h or v_k or v_g) then return null; end if;
  select * into l from game.kd_loadout where player_id = p_pid;
  o := jsonb_build_object('open', jsonb_build_object('harian', v_h, 'kedai', v_k, 'gotong', v_g),
    'keping', (select keping from game.players where player_id = p_pid),
    'gol', v_gol, 'golName', game.golongan_nama(v_gol),
    'incaran', l.incaran, 'incaranPrice', case when l.incaran is not null then game.kd_price(l.incaran) end,
    'incaranName', (select name from game.kd_items where id = l.incaran));
  if v_h then
    r := game.hr_sheet(p_pid);
    o := o || jsonb_build_object('day', r.day, 'npc', r.npc, 'tasks', r.tasks, 'lunas', r.lunas, 'sapu', r.sapu,
      'rerollLeft', greatest(0, 1 + r.reroll_bonus - r.reroll), 'rerollBonus', r.reroll_bonus,
      'resetInMs', game.hr_reset_in_ms(), 'streak', game.hr_streak_json(p_pid),
      'sapuKp', game.cfg_num('HarianSapuKeping', 10), 'streakKp', game.cfg_num('HarianStreakKeping', 5), 'petiKp', game.cfg_num('HarianPetiKeping', 30));
  end if;
  return o;
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT Pesanan Harian: a = [aksi, ...]   status | tukar <slot 0..2>
-- ---------------------------------------------------------------------
create or replace function public.api_harian(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'status');
  r game.hr_sheets; v_slot int; t jsonb; e jsonb; v_used text[]; v_groups text[]; i int;
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if v_act = 'status' then return jsonb_build_object('harian', game.harian_state(v_pid)); end if;
  if not game.fitur_on(v_pid, 'HarianOpen') then raise exception 'Pesanan Harian belum dibuka.'; end if;

  if v_act = 'tukar' then
    v_slot := coalesce(game.arg_int(a, 1), -1);
    r := game.hr_sheet(v_pid);
    select * into r from game.hr_sheets where player_id = v_pid and day = r.day for update;
    if v_slot < 0 or v_slot >= jsonb_array_length(r.tasks) then raise exception 'Tugas tidak dikenal.'; end if;
    if r.reroll >= 1 + r.reroll_bonus then raise exception 'Jatah tukar hari ini sudah habis.'; end if;
    t := r.tasks -> v_slot;
    if coalesce((t ->> 'done')::boolean, false) or coalesce((t ->> 'p')::numeric, 0) > 0 or coalesce((t ->> 's')::numeric, 0) <> 0 then
      raise exception 'Tugas yang sudah dimulai tidak bisa ditukar.';
    end if;
    v_used := array(select x ->> 'c' from jsonb_array_elements(r.tasks) x) || array(select jsonb_array_elements_text(r.swapped));
    v_groups := array(select x ->> 'g' from jsonb_array_elements(r.tasks) with ordinality q(x, k) where k - 1 <> v_slot);
    e := game.hr_pick(v_pid, r.day, (t ->> 't')::int, r.gol, r.npc, v_used, v_groups, '{}');
    if e is null then e := game.hr_pick(v_pid, r.day, (t ->> 't')::int, r.gol, r.npc, v_used, v_groups, '{}', false); end if;
    if e is null then raise exception 'Tidak ada tugas pengganti untuk tingkat ini.'; end if;
    update game.hr_sheets set tasks = jsonb_set(tasks, array[v_slot::text], e), reroll = reroll + 1,
      swapped = swapped || to_jsonb(t ->> 'c')
     where player_id = v_pid and day = r.day;
    return jsonb_build_object('harian', game.harian_state(v_pid));
  end if;
  raise exception 'Aksi tidak dikenal: %', v_act;
end $$;
select game.expose('api_harian');

-- ---------------------------------------------------------------------
-- Jasa yang menempel ke sistem inti
-- ---------------------------------------------------------------------
create or replace function game.kd_enc(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql as $$
declare b game.kd_buffs;
begin
  if p_enc is null or jsonb_typeof(p_enc) <> 'object' or not coalesce((p_enc ->> 'randomPirate')::boolean, false) then return p_enc; end if;
  select * into b from game.kd_buffs where player_id = p_pid and kind = 'pengawal' for update;
  if not found or b.uses_left <= 0 then return p_enc; end if;
  if b.uses_left <= 1 then delete from game.kd_buffs where player_id = p_pid and kind = 'pengawal';
  else update game.kd_buffs set uses_left = uses_left - 1 where player_id = p_pid and kind = 'pengawal'; end if;
  return p_enc || jsonb_build_object('allyDmg', greatest(6, round(game.voy_num(p_enc -> 'enemyMaxHp') * 0.12)),
    'allyNote', 'Perahu Daeng Sore', 'kdGuard', true);
end $$;

create or replace function game.kd_sail_mul(p_pid uuid) returns double precision
language plpgsql as $$
declare b game.kd_buffs;
begin
  select * into b from game.kd_buffs where player_id = p_pid and kind = 'arus' for update;
  if not found or b.uses_left <= 0 then return 1; end if;
  if b.uses_left <= 1 then delete from game.kd_buffs where player_id = p_pid and kind = 'arus';
  else update game.kd_buffs set uses_left = uses_left - 1 where player_id = p_pid and kind = 'arus'; end if;
  return 0.85;
end $$;

create or replace function game.kd_visual(p_pid uuid) returns jsonb
language sql stable as $$
  select case when l.equipped is null or l.equipped = '{}'::jsonb then null else l.equipped end
    from game.kd_loadout l where l.player_id = p_pid
$$;

-- ---------------------------------------------------------------------
-- ENDPOINT Kedai Rantau: a = [aksi, ...]
--   daftar | beli <id> | pasang <id> | lepas <slot> | pakai <id> | incar <id|''>
-- ---------------------------------------------------------------------
create or replace function game.kd_list(p_pid uuid) returns jsonb
language plpgsql as $$
declare l game.kd_loadout; v_k bigint;
begin
  select * into l from game.kd_loadout where player_id = p_pid;
  select keping into v_k from game.players where player_id = p_pid;
  return jsonb_build_object(
    'keping', v_k, 'mul', game.cfg_num('KedaiPriceMul', 1),
    'equipped', coalesce(l.equipped, '{}'::jsonb), 'incaran', l.incaran,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'rak', i.rak, 'slot', i.slot, 'set', i.set_id, 'name', i.name,
        'rarity', i.rarity, 'price', game.kd_price(i.id), 'info', i.info, 'tokoh', i.tokoh, 'exclusive', i.exclusive,
        'req', i.req, 'locked', not game.kd_req_ok(p_pid, i.id),
        'qty', game.kd_qty(p_pid, i.id)) order by i.sort, i.id)
      from game.kd_items i where i.active), '[]'::jsonb),
    'buffs', coalesce((select jsonb_object_agg(kind, uses_left) from game.kd_buffs where player_id = p_pid), '{}'::jsonb),
    'tambatExtra', coalesce((select tambat_extra from game.hr_streak where player_id = p_pid), 0));
end $$;

create or replace function public.api_kedai(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'daftar');
  v_id text := game.arg(a, 1); it game.kd_items; v_price int; v_city text; q jsonb; v_out jsonb := '{}'::jsonb; r game.hr_sheets;
  v_taksir jsonb; l game.kd_loadout;
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KedaiOpen') then raise exception 'Kedai Rantau belum dibuka.'; end if;
  insert into game.kd_loadout(player_id) values (v_pid) on conflict (player_id) do nothing;

  if v_act = 'daftar' then return jsonb_build_object('kedai', game.kd_list(v_pid)); end if;

  if v_act in ('beli', 'pasang', 'pakai') then
    select * into it from game.kd_items where id = v_id and active;
    if not found then raise exception 'Barang tidak ada di Kedai.'; end if;
  end if;

  if v_act = 'beli' then
    if it.exclusive then raise exception '% tidak dijual. Barang ini hanya bisa didapat sebagai hadiah.', it.name; end if;
    if it.rak = 'kisah' then raise exception 'Bab Kisah dibeli di rak Kisah.'; end if;
    if not game.kd_req_ok(v_pid, v_id) then raise exception '% hanya untuk kapten yang sudah menamatkan Kisah Lapau "%".', it.name, coalesce(it.req ->> 'kisahName', it.req ->> 'kisah'); end if;
    if it.rak = 'rupa' and game.kd_qty(v_pid, v_id) > 0 then raise exception 'Kamu sudah memiliki %.', it.name; end if;
    v_price := game.kd_price(v_id);
    perform game.keping_add(v_pid, -v_price, 'kedai', 'beli ' || v_id);
    perform game.kd_grant(v_pid, v_id, 1, 'kedai');
    perform game.log(v_pid, 'Kedai Rantau: membeli ' || it.name || ' seharga ' || to_char(v_price, 'FM999G999G999') || ' keping.');
    update game.kd_loadout set incaran = null where player_id = v_pid and incaran = v_id;
    v_out := jsonb_build_object('bought', v_id, 'name', it.name);

  elsif v_act = 'pasang' then
    if it.rak <> 'rupa' or it.slot is null then raise exception 'Barang ini tidak dipasang di kapal.'; end if;
    if game.kd_qty(v_pid, v_id) <= 0 then raise exception 'Kamu belum memiliki %.', it.name; end if;
    update game.kd_loadout set equipped = equipped || jsonb_build_object(it.slot, v_id) where player_id = v_pid;
    begin perform game.mp_touch(v_pid); exception when others then null; end;   -- kirim rupa baru ke kapten lain
    v_out := jsonb_build_object('shipVisual', game.ship_visual(v_pid));

  elsif v_act = 'lepas' then
    update game.kd_loadout set equipped = equipped - coalesce(v_id, '') where player_id = v_pid;
    begin perform game.mp_touch(v_pid); exception when others then null; end;   -- kirim rupa baru ke kapten lain
    v_out := jsonb_build_object('shipVisual', game.ship_visual(v_pid));

  elsif v_act = 'incar' then
    if coalesce(v_id, '') = '' then update game.kd_loadout set incaran = null where player_id = v_pid;
    else
      select * into it from game.kd_items where id = v_id and active and not exclusive;
      if not found then raise exception 'Barang tidak ada di Kedai.'; end if;
      update game.kd_loadout set incaran = v_id where player_id = v_pid;
    end if;

  elsif v_act = 'pakai' then
    if it.rak <> 'jasa' then raise exception 'Barang ini bukan jasa.'; end if;
    if game.kd_qty(v_pid, v_id) <= 0 then raise exception 'Kamu tidak punya %.', it.name; end if;
    if v_id = 'jasa_kupon' then
      if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan untuk reparasi.'; end if;
      v_city := game.current_city(v_pid);
      q := game.voy_repair_quote(v_pid, v_city);
      if q ->> 'blocked' is not null then raise exception '%', q ->> 'blocked'; end if;
      if (q ->> 'missing')::numeric <= 0 then raise exception 'Kapal sudah dalam kondisi penuh.'; end if;
      update game.ships set condition = (q ->> 'maxCondition')::numeric where player_id = v_pid;
      perform game.log(v_pid, 'Kupon Reparasi Uda Gala dipakai di ' || game.city_name(v_city) || '. Kapal kembali prima.');
      perform game.hr_hook(v_pid, 'repair', 0, jsonb_build_object('city', v_city, 'kupon', true));
      v_out := jsonb_build_object('ship', game.ship_json(v_pid), 'msg', 'Kapal kembali prima. Uda Gala: "Gratis untuak sanak!"');
    elsif v_id = 'jasa_jala' then
      if game.fish_left(v_pid) >= game.fish_qmax_p(v_pid) then raise exception 'Jatah mancingmu sudah penuh.'; end if;
      update game.mp_fish set q_left = null, q_t = null where player_id = v_pid;
      v_out := jsonb_build_object('msg', 'Jatah mancing kembali penuh.');
    elsif v_id = 'jasa_tukar' then
      if not game.fitur_on(v_pid, 'HarianOpen') then raise exception 'Pesanan Harian belum dibuka.'; end if;
      r := game.hr_sheet(v_pid);
      if r.reroll_bonus >= 2 then raise exception 'Tukar Pesanan tambahan hari ini sudah maksimal (2).'; end if;
      update game.hr_sheets set reroll_bonus = reroll_bonus + 1 where player_id = v_pid and day = r.day;
      v_out := jsonb_build_object('msg', 'Satu kali tukar tugas tambahan untuk hari ini.');
    elsif v_id = 'jasa_tambat' then
      insert into game.hr_streak(player_id) values (v_pid) on conflict (player_id) do nothing;
      if (select tambat_extra from game.hr_streak where player_id = v_pid) >= 3 then raise exception 'Tali Tambat Cadangan sudah 3 tersimpan.'; end if;
      update game.hr_streak set tambat_extra = tambat_extra + 1 where player_id = v_pid;
      v_out := jsonb_build_object('msg', 'Teh Euis menyimpan satu Tali Tambat untuk streakmu.');
    elsif v_id = 'jasa_taksir' then
      select coalesce(jsonb_agg(jsonb_build_object('comm', x.comm, 'name', x.name, 'qty', x.qty, 'avg', x.avg, 'best', x.best) order by x.sort), '[]'::jsonb)
        into v_taksir
        from (select i.item_id comm, c.name, i.qty, c.sort, case when i.qty > 0 and i.cost is not null then round(i.cost / i.qty) end avg,
                (select coalesce(jsonb_agg(b order by (b ->> 'price')::int desc), '[]'::jsonb) from (
                   select jsonb_build_object('city', m.city_id, 'cityName', ct.name, 'price', m.current_price) b
                     from game.market m join game.cities ct on ct.city_id = m.city_id
                    where m.commodity_id = i.item_id and m.current_price > 0 and game.city_open(v_pid, m.city_id)
                      and not coalesce(game.spot_city(m.city_id), false)
                    order by m.current_price desc limit 3) z) best
                from game.inventory i join game.commodities c on c.id = i.item_id
               where i.player_id = v_pid and i.qty > 0) x;
      if jsonb_array_length(v_taksir) = 0 then raise exception 'Palkamu kosong. Pak Tua Karto tidak bisa menaksir angin.'; end if;
      v_out := jsonb_build_object('taksir', v_taksir);
    elsif v_id in ('jasa_pengawal', 'jasa_arus') then
      if exists (select 1 from game.kd_buffs where player_id = v_pid and uses_left > 0) then
        raise exception 'Masih ada jasa yang aktif. Satu jasa dalam satu waktu.';
      end if;
      insert into game.kd_buffs(player_id, kind, uses_left) values (v_pid, case when v_id = 'jasa_arus' then 'arus' else 'pengawal' end,
        case when v_id = 'jasa_arus' then 3 else 2 end)
      on conflict (player_id, kind) do update set uses_left = excluded.uses_left, started = now();
      v_out := jsonb_build_object('msg', case when v_id = 'jasa_arus' then 'Nenek Ulin membaca arus untuk tiga pelayaranmu berikutnya.'
        else 'Dua perahu Daeng Sore akan mengawal dua pencegatan berikutnya.' end);
    else
      raise exception 'Jasa ini belum bisa dipakai.';
    end if;
    update game.kd_owned set qty = qty - 1 where player_id = v_pid and item_id = v_id;
    delete from game.kd_owned where player_id = v_pid and item_id = v_id and qty <= 0;
    perform game.log(v_pid, 'Kedai Rantau: memakai ' || it.name || '.');
    v_out := v_out || jsonb_build_object('used', v_id);
  else
    raise exception 'Aksi tidak dikenal: %', v_act;
  end if;

  return v_out || jsonb_build_object('kedai', game.kd_list(v_pid), 'harian', game.harian_state(v_pid));
end $$;
select game.expose('api_kedai');

-- ---------------------------------------------------------------------
-- Gotong Royong: Restorasi IKN (total 100 juta gold)
-- ---------------------------------------------------------------------
create table if not exists game.gr_projects (
  id       text primary key,
  name     text not null,
  city_id  text not null,
  stages   jsonb not null,                 -- [{n, name, need}] need = kebutuhan tahap (gold)
  total    bigint not null default 0,      -- terkumpul (gold; keping x GotongKepingRate)
  stage    int not null default 0,
  stage_at jsonb not null default '{}'::jsonb,
  done_at  timestamptz
);
alter table game.gr_projects enable row level security;
insert into game.gr_projects(id, name, city_id, stages) values ('ikn', 'Restorasi IKN', 'ikn', '[
  {"n":1,"name":"Papan Baru","need":5000000,"desc":"Papan RESTORASI baru yang tidak lapuk lagi."},
  {"n":2,"name":"Garuda Bersih","need":10000000,"desc":"Lumut di monumen Garuda perunggu dibersihkan."},
  {"n":3,"name":"Dermaga Ulin","need":20000000,"desc":"Dok Karat menjadi dermaga kayu ulin. Reparasi di IKN -20%."},
  {"n":4,"name":"Lampu Jalan","need":25000000,"desc":"Lampu-lampu IKN menyala lagi di malam hari."},
  {"n":5,"name":"Menara Cahaya","need":40000000,"desc":"Lampunya terlihat sampai ke tengah laut. Festival Restorasi sepekan. Kapal yang merapat di IKN pulih perlahan, seperti di Paradiso."}
]'::jsonb)
on conflict (id) do update set name = excluded.name, city_id = excluded.city_id, stages = excluded.stages;

create table if not exists game.gr_donations (
  project_id text not null,
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  gold       bigint not null default 0,
  keping     bigint not null default 0,
  total      bigint not null default 0,
  n          int not null default 0,
  last_at    timestamptz not null default now(),
  primary key (project_id, player_id)
);
alter table game.gr_donations add column if not exists garuda_no int;   -- nomor Sayap Garuda (kategori 3), urut siapa duluan
alter table game.gr_donations enable row level security;
create index if not exists gr_donations_rank_idx on game.gr_donations (project_id, total desc);

-- tahap dari total (kumulatif)
create or replace function game.gr_stage_of(p_stages jsonb, p_total bigint) returns int
language sql immutable as $$
  select coalesce(max((e ->> 'n')::int), 0) from (
    select e, sum((e ->> 'need')::bigint) over (order by (e ->> 'n')::int) cum from jsonb_array_elements(p_stages) e
  ) z where cum <= p_total
$$;
create or replace function game.gr_stage(p_project text) returns int
language sql stable as $$ select coalesce((select stage from game.gr_projects where id = p_project), 0) $$;
create or replace function game.gr_repair_mul(p_city text) returns numeric
language sql stable as $$ select case when p_city = 'ikn' and game.gr_stage('ikn') >= 3 then 0.8 else 1 end::numeric $$;

-- kategori penyumbang dari total pribadi (0 = belum menyumbang). 1: s.d. 3 jt, 2: di atas 3 jt s.d. 15 jt, 3: di atas 15 jt
create or replace function game.gr_kategori(p_total bigint) returns int
language sql stable as $$
  select case when coalesce(p_total, 0) <= 0 then 0
    when p_total > coalesce(nullif(split_part(game.cfg('GotongKategori'), ',', 2), '')::bigint, 15000000) then 3
    when p_total > coalesce(nullif(split_part(game.cfg('GotongKategori'), ',', 1), '')::bigint, 3000000) then 2
    else 1 end
$$;

-- Restorasi selesai: IKN menjadi kota pemulih seperti Paradiso & TooGood merdeka (+1 kondisi / 5 detik saat merapat).
-- Salinan heal_city 0022 + IKN. Bila heal_city diubah di migrasi lain, ikutkan baris IKN.
create or replace function game.heal_city(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select p_city = 'paradiso' or (p_city = 'toogood' and game.toogood_freed(p_pid))
      or (p_city = 'pusaran' and game.bx_step(p_pid) between 7 and 15)
      or (p_city = 'ikn' and exists (select 1 from game.gr_projects where id = 'ikn' and done_at is not null))
$$;

-- Bendera dunia (internal, tidak dikirim ke klien). saga3 = dipicu diam-diam saat Restorasi IKN selesai.
create table if not exists game.world_flags (
  key   text primary key,
  value jsonb not null default '{}'::jsonb,
  at    timestamptz not null default now()
);
alter table game.world_flags enable row level security;
create or replace function game.world_flag(p_key text) returns boolean
language sql stable as $$ select exists (select 1 from game.world_flags where key = p_key) $$;

create or replace function game.gotong_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare g game.gr_projects;
begin
  select * into g from game.gr_projects where id = 'ikn';
  -- setelah selesai, kota IKN yang pulih (tampilan & pemulihan kapal) berlaku untuk semua kapten
  if not game.fitur_on(p_pid, 'GotongOpen') and g.done_at is null then return null; end if;
  return jsonb_build_object('ikn', jsonb_build_object('stage', g.stage, 'total', g.total, 'done', g.done_at is not null,
    'goal', (select sum((e ->> 'need')::bigint) from jsonb_array_elements(g.stages) e),
    'kat', game.gr_kategori((select total from game.gr_donations where project_id = 'ikn' and player_id = p_pid))));
end $$;

create or replace function game.sys_chat(p_name text, p_text text, p_city text default '') returns void
language plpgsql as $$
declare v_mid int; v_msg jsonb;
begin
  insert into game.mp_chat_channels as ch (channel, last_id) values ('g', 1)
  on conflict (channel) do update set last_id = ch.last_id + 1 returning last_id into v_mid;
  v_msg := jsonb_build_object('id', v_mid, 'p', 'sys', 'n', p_name, 'a', '', 'ts', game.now_ms(), 'city', coalesce(p_city, ''), 'tx', p_text);
  insert into game.mp_chat(channel, id, msg) values ('g', v_mid, v_msg);
  delete from game.mp_chat where channel = 'g' and id <= v_mid - 60;
  perform game.mp_rt('chat:global', 'chat', v_msg);
exception when others then null;
end $$;

create or replace function game.gr_view(p_pid uuid, p_project text) returns jsonb
language plpgsql stable as $$
declare g game.gr_projects; d game.gr_donations; v_rank int;
begin
  select * into g from game.gr_projects where id = p_project;
  select * into d from game.gr_donations where project_id = p_project and player_id = p_pid;
  if d.player_id is not null then
    select count(*) + 1 into v_rank from game.gr_donations where project_id = p_project and total > d.total;
  end if;
  return jsonb_build_object('id', g.id, 'name', g.name, 'city', g.city_id, 'stage', g.stage, 'total', g.total, 'stageAt', g.stage_at,
    'stages', (select jsonb_agg(e || jsonb_build_object('cum', cum) order by (e ->> 'n')::int) from (
      select e, sum((e ->> 'need')::bigint) over (order by (e ->> 'n')::int) cum from jsonb_array_elements(g.stages) e) z),
    'goal', (select sum((e ->> 'need')::bigint) from jsonb_array_elements(g.stages) e),
    'rate', game.cfg_num('GotongKepingRate', 1000), 'min', game.cfg_num('GotongMinDonasi', 1000),
    'kategori', jsonb_build_array(
      coalesce(nullif(split_part(game.cfg('GotongKategori'), ',', 1), '')::bigint, 3000000),
      coalesce(nullif(split_part(game.cfg('GotongKategori'), ',', 2), '')::bigint, 15000000)),
    'max', game.cfg_num('GotongMaxPerKapten', 0)::bigint,
    'done', g.done_at is not null,
    'garuda', (select count(*) from game.gr_donations where project_id = p_project and garuda_no is not null),
    'donors', (select count(*) from game.gr_donations where project_id = p_project),
    'me', jsonb_build_object('gold', coalesce(d.gold, 0), 'keping', coalesce(d.keping, 0), 'total', coalesce(d.total, 0), 'rank', v_rank,
      'kat', game.gr_kategori(d.total), 'garudaNo', d.garuda_no),
    'top', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(nullif(p.character_name, ''), 'Kapten'), 'total', x.total, 'kat', game.gr_kategori(x.total), 'garudaNo', x.garuda_no) order by x.total desc)
      from (select * from game.gr_donations where project_id = p_project order by total desc limit 10) x
      join game.players p on p.player_id = x.player_id), '[]'::jsonb),
    'here', game.current_city(p_pid) = g.city_id and not game.in_transit(p_pid),
    'keping', (select keping from game.players where player_id = p_pid),
    'gold', (select gold from game.players where player_id = p_pid));
end $$;

create or replace function public.api_gotong(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'status');
  v_gold bigint := greatest(0, coalesce(game.arg_int(a, 1), 0)); v_kp bigint := greatest(0, coalesce(game.arg_int(a, 2), 0));
  g game.gr_projects; v_val bigint; v_old int; v_new int; d game.gr_donations; v_rate numeric := game.cfg_num('GotongKepingRate', 1000);
  v_lentera boolean := false; v_name text; st jsonb; k int; v_max bigint := game.cfg_num('GotongMaxPerKapten', 0)::bigint;
  v_kat0 int; v_kat1 int; v_gno int; v_cum bigint;
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'GotongOpen') then raise exception 'Gotong Royong belum dibuka.'; end if;
  if v_act = 'status' then return jsonb_build_object('gotong', game.gr_view(v_pid, 'ikn')); end if;
  if v_act <> 'sumbang' then raise exception 'Aksi tidak dikenal: %', v_act; end if;

  select * into g from game.gr_projects where id = 'ikn' for update;
  if game.in_transit(v_pid) or game.current_city(v_pid) is distinct from g.city_id then
    raise exception 'Sumbangan diterima di Monumen Restorasi, IKN. Merapatlah ke sana, Kapten.';
  end if;
  v_val := v_gold + round(v_kp * v_rate)::bigint;
  if v_val < game.cfg_num('GotongMinDonasi', 1000) then raise exception 'Sumbangan minimal % gold (atau setaranya dalam keping).', game.cfg_num('GotongMinDonasi', 1000); end if;
  if g.done_at is not null then raise exception 'Restorasi IKN sudah selesai. Terima kasih, Kapten!'; end if;
  if v_gold > v_me.gold then raise exception 'Gold tidak cukup. Kamu punya %.', v_me.gold; end if;
  select * into d from game.gr_donations where project_id = 'ikn' and player_id = v_pid for update;
  if v_max > 0 and coalesce(d.total, 0) + v_val > v_max then
    raise exception 'Batas sumbangan per kapten % gold. Sisa jatahmu % gold.', to_char(v_max, 'FM999G999G999'), to_char(greatest(0, v_max - coalesce(d.total, 0)), 'FM999G999G999');
  end if;
  if v_gold > 0 then update game.players set gold = gold - v_gold where player_id = v_pid; end if;
  if v_kp > 0 then perform game.keping_add(v_pid, -v_kp, 'gotong', 'Restorasi IKN'); end if;

  insert into game.gr_donations as x (project_id, player_id, gold, keping, total, n, last_at)
  values ('ikn', v_pid, v_gold, v_kp, v_val, 1, now())
  on conflict (project_id, player_id) do update set gold = x.gold + excluded.gold, keping = x.keping + excluded.keping,
    total = x.total + excluded.total, n = x.n + 1, last_at = now();
  v_name := coalesce(nullif(v_me.character_name, ''), 'Seorang kapten');
  -- kategori penyumbang: 2 = Lentera IKN, 3 = Sayap Garuda bernomor (terbatas: hanya selama Restorasi berjalan)
  v_kat0 := game.gr_kategori(d.total); v_kat1 := game.gr_kategori(coalesce(d.total, 0) + v_val);
  if v_kat1 >= 2 and game.kd_qty(v_pid, 'aura_lentera_ikn') = 0 then
    perform game.kd_grant(v_pid, 'aura_lentera_ikn', 1, 'gotong');
    v_lentera := true;
  end if;
  if v_kat1 >= 3 and game.kd_qty(v_pid, 'lambang_garuda') = 0 then
    perform game.kd_grant(v_pid, 'lambang_garuda', 1, 'gotong');
    select coalesce(max(garuda_no), 0) + 1 into v_gno from game.gr_donations where project_id = 'ikn';
    update game.gr_donations set garuda_no = v_gno where project_id = 'ikn' and player_id = v_pid;
    perform game.sys_chat('Monumen Restorasi', 'Kapten ' || v_name || ' menjadi Penjaga Garuda #' || v_gno || '. Sayap Garuda emas kini membentang di atas kapalnya.', 'ikn');
  end if;

  v_old := g.stage;
  update game.gr_projects set total = total + v_val where id = 'ikn' returning * into g;
  v_new := greatest(v_old, game.gr_stage_of(g.stages, g.total));
  perform game.log(v_pid, 'Menyumbang ' || to_char(v_val, 'FM999G999G999G999') || ' gold' || case when v_kp > 0 then ' (termasuk ' || v_kp || ' keping)' else '' end || ' untuk Restorasi IKN.');
  if v_new > v_old then
    for k in v_old + 1 .. v_new loop
      st := (select e from jsonb_array_elements(g.stages) e where (e ->> 'n')::int = k);
      update game.gr_projects set stage = k, stage_at = stage_at || jsonb_build_object(k::text, game.now_ms()) where id = 'ikn';
      v_cum := (select sum((e ->> 'need')::bigint) from jsonb_array_elements(g.stages) e where (e ->> 'n')::int <= k);
      perform game.sys_chat('Monumen Restorasi', 'Kolam Restorasi IKN mencapai ' || to_char(v_cum / 1000000, 'FM999') || ' juta gold: ' || (st ->> 'name') || '! ' || (st ->> 'desc')
        || ' Sumbangan terakhir dari Kapten ' || v_name || '.', 'ikn');
      if k = 5 then
        update game.gr_projects set done_at = now() where id = 'ikn';
        delete from game.city_events where city_id = 'ikn' and expires_game_day >= game.game_day();
        insert into game.city_events(city_id, event_type, label, message, price_pct, reward_pct, expires_game_day)
        values ('ikn', 'festival', 'Festival Restorasi', 'Menara Cahaya IKN menyala lagi. Seluruh Mare Nusantara datang berpesta.', 0, 25,
          game.game_day() + greatest(1, ceil(7 * 24 * 60 / game.cfg_num('GameDayLengthRealMinutes', 180)))::int);
        -- pemicu Saga 3 (diam-diam: tanpa chat, inbox, atau data ke klien)
        insert into game.world_flags(key, value) values ('saga3', jsonb_build_object('trigger', 'ikn', 'by', v_pid))
        on conflict (key) do nothing;
      end if;
    end loop;
  elsif v_val >= 1000000 then
    perform game.sys_chat('Monumen Restorasi', 'Kapten ' || v_name || ' menyumbang ' || to_char(v_val, 'FM999G999G999') || ' gold untuk Restorasi IKN.', 'ikn');
  end if;

  return jsonb_build_object('gotong', game.gr_view(v_pid, 'ikn'), 'stageUp', v_new > v_old, 'stage', v_new, 'lentera', v_lentera,
    'katUp', v_kat1 > v_kat0, 'kat', v_kat1, 'garudaNo', v_gno,
    'newGold', v_me.gold - v_gold, 'harian', game.harian_state(v_pid));
end $$;
select game.expose('api_gotong');
