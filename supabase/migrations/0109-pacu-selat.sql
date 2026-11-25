-- =====================================================================
-- 0109 · PACU SELAT (Sirkuit Selat Lurus, Zentul) · Tide v88
--   Modul tampilan window.PacuSelat (web/src/PacuSelat.html, desain Gemini, disetel Claude)
--   dengan FISIKA BILANGAN BULAT BARU. Kembaran persis fisika klien ada di sini:
--   game.ps_spesifikasi + game.ps_input + game.ps_sim. Tes 0109 membandingkan keduanya.
--
--   Terbuka untuk kapten yang sudah melewati langkah 40 Mahkota Selat (game.mk_tamat)
--   dan merapat di Zentul. Gerbang: PacuSelatOpen = 1, atau nama di FiturPenguji.
--   Selama tertutup, bangunan Sirkuit tetap membuka gelanggang lama (Trek.html).
--   Balapan cerita Saga 4 (api_mahkota, Tembus Jaring, Turnamen Obor) TIDAK tersentuh:
--   semuanya tetap memakai MTTrekSim / game.trek_run.
--
--   Isi:
--     Galangan Kapal  : 5 kelas kapal pacu (beli sekali, pakai bergantian), bayar gold.
--     Bengkel Mesin   : 10 komponen (dipasang permanen), setelan rasio gigi, reparasi mesin jebol.
--     Uji Lintasan    : solo 800 m (gratis 1x per hari game, lalu PsUjiBiaya) dan 1,4 km (PsUjiBiaya).
--     Pacu Gugur      : 400 m, 4 babak per pekan (Pariopelan -> KapalMber -> cangcimen -> Yaptob),
--                       kalah = gugur sampai Senin. Juara: GugurHadiahOli + GugurHadiahGold.
--     Adu Kapten      : rombongan 2-4 kapten, start serentak dari jam server, posisi lawan
--                       langsung lewat Realtime 'pacu:<room>' (cadangan RPC 'pos').
--                       Taruhan PsTaruhan dari tiap kapten, pemenang membawa seluruh pot.
--                       Juara mendapat MedaliAdu (game.medali, ditukar lewat api_medali) bila
--                       minimal dua catatan masuk.
--     Mesin jebol     : bila simulasi server menyatakan blok pecah, kapal pacu tidak bisa
--                       balapan sampai direparasi (PsReparasi).
--   Semua hasil dihitung server dari log ketukan [[tms, 1|0], ...].
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PacuSelatOpen', '0'),
  ('PsUjiBiaya', '500'),
  ('PsUjiGratis', '1'),
  ('PsTaruhan', '15000'),
  ('PsAduMaks', '10'),
  ('PsReparasi', '100000'),
  ('PsSetorDetik', '90'),
  ('PsUndanganDetik', '60'),
  ('PsMulaiJedaMs', '6000')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists game.ps_pemain (
  player_id   uuid primary key references game.players(player_id) on update cascade on delete cascade,
  kelas_aktif text not null default 'sekoci_standar',
  kapal       text[] not null default array['sekoci_standar'],
  parts       text[] not null default '{}',
  rasio       text not null default '800',
  jebol       boolean not null default false,
  gratis_hari int not null default -1,          -- hari game terakhir jatah gratis Uji 800 dipakai
  updated_at  timestamptz not null default now()
);
alter table game.ps_pemain enable row level security;

create table if not exists game.ps_run (
  id         text primary key,
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  mode       text not null check (mode in ('uji_800', 'uji_1400', 'pacu_gugur')),
  seed       bigint not null,
  jarak_mm   int not null,
  meriam_ms  int not null,
  kelas      text not null,
  parts      text[] not null default '{}',
  rasio      text not null default '800',
  lawan      jsonb,                               -- profil AI (Pacu Gugur)
  mulai      bigint not null,                     -- jam server saat run dibuat (tick 0)
  biaya      int not null default 0,
  status     text not null default 'jalan' check (status in ('jalan', 'selesai', 'tinggal')),
  log        jsonb,
  hasil      jsonb,
  game_day   int not null default 0,
  created_at timestamptz not null default now()
);
alter table game.ps_run enable row level security;
create index if not exists ps_run_pid on game.ps_run(player_id, created_at desc);

create table if not exists game.ps_rekor (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  jarak_mm  int not null,
  fin_ms    int not null,
  top_mm    int not null default 0,
  kelas     text not null,
  parts_n   int not null default 0,
  at        timestamptz not null default now(),
  primary key (player_id, jarak_mm)
);
alter table game.ps_rekor enable row level security;
create index if not exists ps_rekor_jarak on game.ps_rekor(jarak_mm, fin_ms);

create table if not exists game.ps_riwayat (
  id        bigserial primary key,
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  mode      text not null,
  jarak_mm  int not null,
  kelas     text not null,
  fin_ms    int,
  top_mm    int,
  ket       text,
  at        timestamptz not null default now()
);
alter table game.ps_riwayat enable row level security;
create index if not exists ps_riwayat_pid on game.ps_riwayat(player_id, id desc);

create table if not exists game.ps_gugur (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  week      int not null,
  babak     int not null default 1,
  status    text not null default 'jalan' check (status in ('jalan', 'gugur', 'juara')),
  at        timestamptz not null default now(),
  primary key (player_id, week)
);
alter table game.ps_gugur enable row level security;

create table if not exists game.ps_room (
  id        text primary key,
  tuan      uuid not null references game.players(player_id) on update cascade on delete cascade,
  status    text not null default 'lobi' check (status in ('lobi', 'jalan', 'selesai', 'batal')),
  seed      bigint,
  jarak_mm  int not null default 800000,
  meriam_ms int,
  taruhan   int not null default 0,
  mulai     bigint,                               -- jam server = tick 0 (awal hitung mundur)
  created   bigint not null,
  game_day  int not null default 0,
  hasil     jsonb
);
alter table game.ps_room enable row level security;
create index if not exists ps_room_status on game.ps_room(status, created);

create table if not exists game.ps_room_anggota (
  room_id   text not null references game.ps_room(id) on delete cascade,
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  nama      text not null default 'Kapten',
  status    text not null default 'diundang' check (status in ('diundang', 'ikut', 'tolak', 'keluar')),
  urut      int not null default 0,
  diundang  bigint not null default 0,
  kelas     text,
  parts     text[],
  rasio     text,
  bayar     int not null default 0,               -- taruhan yang sudah dipotong
  log       jsonb,
  hasil     jsonb,
  pos       jsonb,
  pos_at    bigint,
  primary key (room_id, player_id)
);
alter table game.ps_room_anggota enable row level security;
create index if not exists ps_room_anggota_pid on game.ps_room_anggota(player_id, status);

-- Jejak uang Pacu Selat (Galangan, Bengkel, Uji, taruhan & pot Adu, hadiah Gugur) untuk Panel Ops.
create table if not exists game.ps_kas (
  id        bigserial primary key,
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  delta     bigint not null,
  jenis     text not null,
  ref       text,
  gold_akhir bigint,
  at        timestamptz not null default now()
);
alter table game.ps_kas enable row level security;
create index if not exists ps_kas_pid on game.ps_kas(player_id, id desc);

-- ---------------------------------------------------------------------
-- Katalog (angka sama persis dengan CONFIG di PacuSelat.html)
-- ---------------------------------------------------------------------
create or replace function game.ps_katalog() returns jsonb
language sql immutable as $$
  select '{
    "kelas": {
      "sekoci_standar":    {"urut": 1, "nama": "Sekoci Kayu Standar",   "accel": 1000, "top": 64400, "bonus": 0,  "harga": 0},
      "pencalang_lancang": {"urut": 2, "nama": "Pencalang Lancang",     "accel": 1084, "top": 67760, "bonus": 12, "harga": 1250000},
      "kolek_kilat":       {"urut": 3, "nama": "Kolek Kilat Zentul",    "accel": 1168, "top": 70560, "bonus": 22, "harga": 2100000},
      "lancang_sultan":    {"urut": 4, "nama": "Lancang Kuning Sultan", "accel": 1264, "top": 74480, "bonus": 32, "harga": 3100000},
      "bahtera_petir":     {"urut": 5, "nama": "Bahtera Petir Selat",   "accel": 1360, "top": 78400, "bonus": 42, "harga": 4000000}
    },
    "parts": {
      "knalpot_meriam":    {"urut": 1,  "nama": "Knalpot Meriam Tembaga",  "harga": 220000,  "mm": 560,  "accel": 20},
      "filter_kuningan":   {"urut": 2,  "nama": "Filter Udara Kuningan",   "harga": 310000,  "mm": 560},
      "kopling_keramik":   {"urut": 3,  "nama": "Kopling Keramik Bahari",  "harga": 450000,  "lag": 600},
      "cvt_hidrolik":      {"urut": 4,  "nama": "CVT Hidrolik",            "harga": 620000,  "accel": 30, "lag": 700},
      "busi_iridium":      {"urut": 5,  "nama": "Busi Iridium Petir",      "harga": 800000,  "mm": 1120, "anti": 200},
      "noken_as_balap":    {"urut": 6,  "nama": "Noken As Balap",          "harga": 1050000, "mm": 1120, "rpm": 700},
      "injektor_kembar":   {"urut": 7,  "nama": "Injektor Kembar Bahari",  "harga": 1300000, "mm": 1120, "accel": 40},
      "ecu_pelaut_pintar": {"urut": 8,  "nama": "ECU Pelaut Pintar",       "harga": 1600000, "anti": 1000, "sweet": 30},
      "bore_up_blok":      {"urut": 9,  "nama": "Kit Bore Up Blok Besi",   "harga": 1950000, "mm": 2240, "accel": 60},
      "turbo_sentrifugal": {"urut": 10, "nama": "Turbo Charger Sentrifugal","harga": 2400000, "mm": 2800, "accel": 80, "rpm": 800, "bp": 350, "bd": 1300}
    },
    "rasio": {
      "400":  {"pa": 1080, "pt": 960,  "geser": -25},
      "800":  {"pa": 1000, "pt": 1000, "geser": 0},
      "1400": {"pa": 960,  "pt": 1070, "geser": 40}
    }
  }'::jsonb
$$;

-- Harga bisa diatur GM: PsHarga_<id> (gold). Kosong = harga katalog.
create or replace function game.ps_harga(p_id text) returns bigint
language sql stable as $$
  select coalesce(nullif(game.cfg('PsHarga_' || p_id), '')::bigint,
                  (game.ps_katalog() -> 'kelas' -> p_id ->> 'harga')::bigint,
                  (game.ps_katalog() -> 'parts' -> p_id ->> 'harga')::bigint,
                  case when p_id = 'reparasi_mesin' then game.cfg_num('PsReparasi', 100000)::bigint end)
$$;

create or replace function game.ps_rp(p bigint) returns text
language sql immutable as $$ select replace(to_char(coalesce(p, 0), 'FM999,999,999,999'), ',', '.') $$;

-- Urutkan & saring daftar part ke urutan katalog (urutan menentukan hasil pembulatan jeda gigi).
create or replace function game.ps_parts_rapi(p text[]) returns text[]
language sql immutable as $$
  select coalesce(array_agg(k order by (game.ps_katalog() -> 'parts' -> k ->> 'urut')::int), '{}')
    from (select distinct unnest(coalesce(p, '{}')) k) x
   where game.ps_katalog() -> 'parts' ? k
$$;

-- ---------------------------------------------------------------------
-- FISIKA (kembaran persis PacuSelat.sim)
-- ---------------------------------------------------------------------
do $$ begin
  drop type if exists game.ps_sp cascade;
  drop type if exists game.ps_st cascade;
end $$;

create type game.ps_sp as (
  kelas text, accel int, top int, maxrpm int, lag int, anti int, ge int, boostp int, boostd int,
  gf int[],      -- faktor gigi 1..5 (permil)
  gs int[],      -- awal daun hijau gigi 1..4
  ss int[],      -- awal bintang emas gigi 1..4
  est int[]      -- taksiran laju RPM gigi 1..4
);

create type game.ps_st as (
  launched boolean, jump boolean, pend boolean, reaksi int, elapsed int,
  pos bigint, v bigint, vmax bigint, z100 int, gear int, rpm int, heat bigint, wear bigint,
  batuk int, jebol boolean, lag int, cough int, bused boolean, bleft int, tahan boolean, t5 int,
  fin int, shifts text
);

create or replace function game.ps_spesifikasi(p_kelas text, p_parts text[], p_rasio text) returns game.ps_sp
language plpgsql immutable as $$
declare v_kat jsonb := game.ps_katalog(); kp jsonb; fx jsonb; r jsonb; p text;
  v_accel int; v_top int; v_rpm int := 8000; v_lag int := 220; v_anti int := 150; v_gs0 int;
  v_bp int := 1480; v_bd int := 2000; v_raw int; v_str int; g int; zmul int; base_g int; star_mul int; base_s int;
  gtop bigint; raw_acc bigint; est_acc bigint; est int; min_g int; min_s int; gw int; sw int; g_s int; s_s int;
  sp game.ps_sp;
  BASE int[] := array[300, 500, 680, 850, 1000];
  BOBOT int[] := array[1000, 850, 600, 300, 0];
  ZM int[] := array[1550, 1250, 1050, 920];
begin
  kp := coalesce(v_kat -> 'kelas' -> p_kelas, v_kat -> 'kelas' -> 'sekoci_standar');
  sp.kelas := case when v_kat -> 'kelas' ? p_kelas then p_kelas else 'sekoci_standar' end;
  v_accel := (kp ->> 'accel')::int; v_top := (kp ->> 'top')::int;
  v_gs0 := 820 - (kp ->> 'bonus')::int;
  foreach p in array coalesce(p_parts, '{}') loop
    fx := v_kat -> 'parts' -> p;
    if fx is null then continue; end if;
    if fx ? 'accel' then v_accel := v_accel + (fx ->> 'accel')::int; end if;
    if fx ? 'mm' then v_top := v_top + (fx ->> 'mm')::int; end if;
    if fx ? 'rpm' then v_rpm := v_rpm + (fx ->> 'rpm')::int; end if;
    if fx ? 'lag' then v_lag := (v_lag * (fx ->> 'lag')::int) / 1000; end if;
    if fx ? 'anti' then v_anti := least(1000, v_anti + (fx ->> 'anti')::int); end if;
    if fx ? 'sweet' then v_gs0 := greatest(460, v_gs0 - (fx ->> 'sweet')::int); end if;
    if fx ? 'bp' then v_bp := v_bp + (fx ->> 'bp')::int; end if;
    if fx ? 'bd' then v_bd := v_bd + (fx ->> 'bd')::int; end if;
  end loop;
  v_lag := greatest(40, v_lag);
  r := coalesce(v_kat -> 'rasio' -> coalesce(p_rasio, '800'), v_kat -> 'rasio' -> '800');
  v_accel := (v_accel * (r ->> 'pa')::int) / 1000;
  v_top := (v_top::bigint * (r ->> 'pt')::int / 1000)::int;
  v_raw := ((v_accel - 1000) * 58) / 1000 + (r ->> 'geser')::int;
  v_str := least(160, greatest(-20, v_raw));
  sp.gf := array[]::int[];
  for g in 1..5 loop
    sp.gf := sp.gf || (case when g = 5 then 1000 else BASE[g] + (v_str * BOBOT[g]) / 1000 end);
  end loop;
  sp.accel := v_accel; sp.top := v_top; sp.maxrpm := v_rpm; sp.lag := v_lag; sp.anti := v_anti;
  sp.ge := 930; sp.boostp := v_bp; sp.boostd := v_bd;
  sp.gs := array[]::int[]; sp.ss := array[]::int[]; sp.est := array[]::int[];
  for g in 1..4 loop
    zmul := ZM[g];
    base_g := ((930 - v_gs0) * zmul) / 1000;
    star_mul := greatest(1000, (zmul * 900) / 1000);
    base_s := (32 * star_mul) / 1000;
    gtop := greatest(11200, (v_top::bigint * sp.gf[g]) / 1000);
    raw_acc := 15960 - g * 1344;
    est_acc := greatest(4480, (raw_acc * v_accel * 880) / 1000000);
    est := greatest(180, ((est_acc * 1000) / gtop)::int);
    min_g := least(420, (est * 320) / 1000);
    min_s := least(160, (est * 125) / 1000);
    gw := greatest(base_g, min_g); sw := greatest(base_s, min_s);
    g_s := greatest(460, 930 - gw);
    s_s := greatest(g_s + 20, 930 - sw);
    sp.gs := sp.gs || g_s; sp.ss := sp.ss || s_s; sp.est := sp.est || est;
  end loop;
  return sp;
end $$;

create or replace function game.ps_meriam(p_seed bigint) returns int
language sql immutable as $$
  select 2300 + (((((abs(p_seed) % 2147483646) + 1) * 48271) % 2147483647) % 451)::int
$$;

create or replace function game.ps_torsi(p_r int) returns int
language plpgsql immutable as $$
declare T int[] := array[550, 578, 620, 668, 722, 779, 840, 905, 972, 994, 954]; r int; i int; rem int;
begin
  r := greatest(0, least(1000, p_r)); i := least(9, r / 100); rem := r - i * 100;
  return T[i + 1] + ((T[i + 2] - T[i + 1]) * rem) / 100;
end $$;

create or replace function game.ps_input(s game.ps_st, sp game.ps_sp, p_tekan int, p_t int) returns game.ps_st
language plpgsql immutable as $$
declare r int; gr int; q text; fk int;
begin
  if s.jebol or s.fin is not null then return s; end if;
  if p_tekan <> 1 then s.tahan := false; s.t5 := -1; return s; end if;
  s.tahan := true;
  if not s.launched then
    if p_t < 80 then
      if not s.jump then s.jump := true; end if;
      if p_t < 0 then s.pend := true; return s; end if;
    end if;
    s.launched := true; s.pend := false; s.reaksi := greatest(0, p_t);
    if s.jump then
      s.elapsed := s.elapsed + 500;
      s.v := (2800::bigint * sp.accel) / 1000;
    else
      s.v := (5600::bigint * sp.accel * (case when p_t < 220 then 1250 else 1000 end)) / 1000000;
    end if;
    return s;
  end if;
  if s.gear < 5 then
    if s.lag > 0 then return s; end if;
    r := s.rpm;
    gr := least(35, (sp.est[s.gear] * 25) / 1000);
    if r < sp.gs[s.gear] - gr then q := 'a';
    elsif r < sp.ss[s.gear] - gr then q := 't'; s.v := s.v + (2520::bigint * sp.accel) / 1000;
    elsif r <= sp.ge + gr then q := 's'; s.v := s.v + (5320::bigint * sp.accel) / 1000;
    else q := 'l';
    end if;
    s.shifts := s.shifts || q;
    s.gear := s.gear + 1;
    fk := case q when 's' then 350 when 't' then 650 else 1150 end;
    s.lag := (sp.lag * fk) / 1000;
    s.rpm := greatest(300, (s.rpm * 680) / 1000);
    if s.gear = 5 and not s.bused then s.t5 := p_t; end if;
    return s;
  end if;
  if s.gear = 5 and not s.bused and s.t5 < 0 then s.t5 := p_t; end if;
  return s;
end $$;

-- Satu kapal. p_ai null = manusia (log dipakai); p_ai {react, noise, sebaran, seed} = lawan AI.
create or replace function game.ps_sim(sp game.ps_sp, p_jarak int, p_meriam int, p_log jsonb, p_ai jsonb default null)
returns jsonb
language plpgsql immutable as $$
declare s game.ps_st; k int; tms int; dt int; lt int[]; lv int[]; n int := 0; cur int := 1;
  ai boolean := p_ai is not null; a_react int; a_noise int; a_seb int; a_rng bigint; a_tgt int; q_aktif boolean := false;
  pacu int; btop int; gtop bigint; thr int; r int; tq int; base bigint; acc bigint; drag bigint; dv bigint;
  rawr bigint; minr int; resist int; laju bigint;
begin
  s := row(false, false, false, null, 0, 0, 0, 0, null, 1, 0, 0, 0, 0, false, 0, 0, false, 0, false, -1, null, '')::game.ps_st;
  if not ai and p_log is not null and jsonb_typeof(p_log) = 'array' then
    select coalesce(array_agg((e ->> 0)::int order by (e ->> 0)::int, o), '{}'), coalesce(array_agg((e ->> 1)::int order by (e ->> 0)::int, o), '{}')
      into lt, lv
      from (select e, o from jsonb_array_elements(p_log) with ordinality as x(e, o) where o <= 240) y;
    n := coalesce(array_length(lt, 1), 0);
  end if;
  if ai then
    a_react := (p_ai ->> 'react')::int; a_noise := coalesce((p_ai ->> 'noise')::int, 0);
    a_seb := greatest(0, coalesce((p_ai ->> 'sebaran')::int, 0));
    a_rng := (abs(coalesce((p_ai ->> 'seed')::bigint, 1)) % 2147483646) + 1;
  end if;

  for k in 1..14400 loop
    tms := (k * 25) / 3 - p_meriam;
    while cur <= n and lt[cur] <= tms loop
      s := game.ps_input(s, sp, lv[cur], lt[cur]); cur := cur + 1;
    end loop;
    if tms < 0 then s.rpm := 240; continue; end if;
    if s.jebol or s.fin is not null then exit; end if;
    dt := (k * 25) / 3 - ((k - 1) * 25) / 3;

    if not s.launched and s.pend then
      s.launched := true; s.pend := false; s.reaksi := 0; s.elapsed := s.elapsed + 500;
      s.v := (2800::bigint * sp.accel) / 1000;
    end if;
    if not s.launched and tms >= (case when ai then a_react else 1500 end) then
      s := game.ps_input(s, sp, 1, tms); s := game.ps_input(s, sp, 0, tms);
    end if;
    s.elapsed := s.elapsed + dt;
    if not s.launched then s.rpm := 240; continue; end if;

    if s.tahan and s.t5 >= 0 and s.gear = 5 and not s.bused and tms - s.t5 >= 450 then
      s.bused := true; s.bleft := sp.boostd; s.t5 := -1;
      s.heat := s.heat + (350000::bigint * (1300 - sp.anti)) / 1300;
    end if;
    if s.lag > 0 then s.lag := greatest(0, s.lag - dt); end if;
    if s.cough > 0 then s.cough := greatest(0, s.cough - dt); end if;
    if s.bleft > 0 then s.bleft := greatest(0, s.bleft - dt); end if;

    pacu := case when ai and s.pos > (p_jarak::bigint * 600) / 1000 then 1070 else 1000 end;
    btop := case when s.bleft > 0 then 1180 else 1000 end;
    gtop := (((sp.top::bigint * sp.gf[s.gear]) / 1000) * btop * pacu) / 1000000;
    thr := case when s.lag > 0 then 100 else 1000 end;
    if s.cough > 0 then thr := (thr * 300) / 1000; end if;
    r := case when gtop > 0 then least(1000, (s.v * 1000) / gtop)::int else 0 end;
    tq := greatest(250, game.ps_torsi(r));
    base := 15960 - s.gear * 1344;
    acc := (((base * sp.accel) / 1000) * tq * thr) / 1000000;
    if s.bleft > 0 then acc := (acc * sp.boostp) / 1000; end if;
    drag := (s.v * s.v * 2159) / 1000000000;
    acc := acc - drag;
    dv := acc / 120;
    s.v := greatest(0, least(gtop, s.v + dv));
    if s.v > s.vmax then s.vmax := s.v; end if;
    if s.z100 is null and s.v >= 30240 then s.z100 := s.elapsed; end if;
    s.pos := s.pos + s.v / 120;
    rawr := case when gtop > 0 then (s.v * 1000) / gtop else 0 end;
    minr := case when s.gear = 1 then 340 else 300 end;
    s.rpm := least(1000, greatest(minr, rawr))::int;

    if ai and s.gear < 5 and s.lag <= 0 then
      if not q_aktif then
        a_rng := (a_rng * 48271) % 2147483647;
        a_tgt := sp.ss[s.gear] + a_noise + (a_rng % (2 * a_seb + 1))::int - a_seb;
        q_aktif := true;
      end if;
      if s.rpm >= a_tgt then
        s := game.ps_input(s, sp, 1, tms); s := game.ps_input(s, sp, 0, tms);
        q_aktif := false;
      end if;
    end if;
    if ai and s.gear = 5 and not s.bused and s.pos >= (p_jarak::bigint * 720) / 1000 then
      s.bused := true; s.bleft := sp.boostd; s.t5 := -1;
      s.heat := s.heat + (350000::bigint * (1300 - sp.anti)) / 1300;
    end if;

    resist := 1000 + (sp.anti * 1400) / 1000;
    if (s.gear < 5 or s.bleft > 0) and s.rpm > 950 then
      laju := case when s.rpm >= 990 then 1150000 else 500000 end;
      s.heat := s.heat + (laju * 1000) / (120 * resist);
      if s.cough > 0 or s.heat > 850000 then
        s.wear := s.wear + (case when s.cough > 0 then 420000 else 160000 end) / 120;
      end if;
    else
      s.heat := greatest(0, s.heat - 250000 / 120);
      if s.cough <= 0 then s.wear := greatest(0, s.wear - 60000 / 120); end if;
    end if;
    if s.heat >= 1000000 and sp.anti < 1000 then
      s.heat := 620000; s.cough := 750; s.batuk := s.batuk + 1; s.wear := s.wear + 360000;
      if s.wear >= 1000000 or s.batuk >= 3 then s.jebol := true; s.v := 0; s.bleft := 0; exit; end if;
    elsif s.heat >= 1000000 and sp.anti >= 1000 then
      s.heat := 840000; s.wear := s.wear + 220000 / 120;
    end if;
    if s.wear >= 1000000 then s.jebol := true; s.v := 0; s.bleft := 0; exit; end if;
    if s.pos >= p_jarak and s.fin is null then s.pos := p_jarak; s.fin := s.elapsed; exit; end if;
  end loop;

  return jsonb_build_object('fin', s.fin, 'top', s.vmax, 'z100', s.z100, 'jebol', s.jebol, 'batuk', s.batuk,
    'boost', s.bused, 'jump', s.jump, 'reaksi', s.reaksi, 'shifts', s.shifts);
end $$;

-- Log ketukan harus masuk akal.
create or replace function game.ps_log_cek(p_log jsonb) returns boolean
language plpgsql immutable as $$
declare i int; v_prev bigint := -100000; v_t bigint;
begin
  if p_log is null or jsonb_typeof(p_log) <> 'array' or jsonb_array_length(p_log) > 240 then return false; end if;
  for i in 0..jsonb_array_length(p_log) - 1 loop
    if jsonb_typeof(p_log -> i) <> 'array' or jsonb_typeof(p_log -> i -> 0) <> 'number'
       or (p_log -> i ->> 1) not in ('0', '1') or (p_log -> i ->> 0) !~ '^-?[0-9]{1,6}$' then return false; end if;
    v_t := (p_log -> i ->> 0)::bigint;
    if v_t < v_prev or v_t < -5000 or v_t > 125000 then return false; end if;
    v_prev := v_t;
  end loop;
  return true;
end $$;

-- ---------------------------------------------------------------------
-- Gerbang & data pemain
-- ---------------------------------------------------------------------
create or replace function game.ps_buka(p_pid uuid) returns boolean
language sql stable as $$
  select p_pid is not null and game.mk_tamat(p_pid)
     and (lower(coalesce(game.cfg('PacuSelatOpen'), '0')) in ('1', 'true', 'on', 'ya') or game.penguji_saja(p_pid))
$$;

create or replace function game.ps_siap(p_pid uuid) returns boolean
language sql stable as $$
  select game.ps_buka(p_pid) and not game.in_transit(p_pid) and game.current_city(p_pid) = 'zentul'
$$;

create or replace function game.ps_row(p_pid uuid) returns game.ps_pemain
language plpgsql as $$
declare r game.ps_pemain;
begin
  insert into game.ps_pemain(player_id) values (p_pid) on conflict do nothing;
  select * into r from game.ps_pemain where player_id = p_pid;
  return r;
end $$;

create or replace function game.ps_kas_catat(p_pid uuid, p_delta bigint, p_jenis text, p_ref text) returns bigint
language plpgsql as $$
declare v_g bigint;
begin
  update game.players set gold = gold + p_delta where player_id = p_pid returning gold into v_g;
  insert into game.ps_kas(player_id, delta, jenis, ref, gold_akhir) values (p_pid, p_delta, p_jenis, p_ref, v_g);
  return v_g;
end $$;

create or replace function game.ps_bayar(p_pid uuid, p_n bigint, p_jenis text, p_ref text) returns void
language plpgsql as $$
declare v_g bigint;
begin
  if coalesce(p_n, 0) <= 0 then return; end if;
  select gold into v_g from game.players where player_id = p_pid for update;
  if coalesce(v_g, 0) < p_n then
    raise exception 'Gold di tangan tidak cukup: butuh % Gold.', game.ps_rp(p_n);
  end if;
  perform game.ps_kas_catat(p_pid, -p_n, p_jenis, p_ref);
end $$;

create or replace function game.ps_nama(p_pid uuid) returns text
language sql stable as $$ select coalesce(nullif(character_name, ''), 'Kapten') from game.players where player_id = p_pid $$;

create or replace function game.ps_knot(p_mm bigint) returns int
language sql immutable as $$ select ((coalesce(p_mm, 0) + 280) / 560)::int $$;

create or replace function game.ps_kapal_label(p_kelas text, p_n int) returns text
language sql immutable as $$
  select coalesce(game.ps_katalog() -> 'kelas' -> p_kelas ->> 'nama', 'Perahu Jalur')
         || case when coalesce(p_n, 0) > 0 then ' · ' || p_n || ' Mod' else '' end
$$;

-- Lawan Pacu Gugur (angka dikalibrasi tools: pemain "biasa" kapal menengah ±40% lawan cangcimen).
create or replace function game.ps_gugur_lawan(p_babak int, p_seed bigint) returns jsonb
language sql immutable as $$
  select jsonb_build_object('id', 'lawan_' || v.id, 'kode', v.id, 'nama', v.nama, 'kapalNama', v.kapal,
           'kelas', v.kelas, 'parts', to_jsonb(v.parts), 'rasioPreset', '800',
           'aiReaksiMs', v.react + ((abs(p_seed) % 41) - 20)::int, 'aiShiftNoisePermil', v.noise,
           'aiSebaranPermil', v.seb, 'aiSeed', (abs(p_seed) * 31 + 7) % 2147483646)
    from (values
      (1, 'pariopelan', 'Pariopelan', 'Pencalang Lancang', 'pencalang_lancang', array[]::text[], 300, -60, 60),
      (2, 'kapalmber', 'KapalMber', 'Kolek Kilat Zentul', 'kolek_kilat', array['knalpot_meriam', 'busi_iridium'], 270, -30, 60),
      (3, 'cangcimen', 'cangcimen', 'Lancang Kuning Sultan', 'lancang_sultan',
         array['knalpot_meriam', 'kopling_keramik', 'busi_iridium', 'injektor_kembar', 'bore_up_blok'], 250, -10, 50),
      (4, 'yaptob', 'Yaptob', 'YusaintJolt', 'bahtera_petir',
         array['knalpot_meriam', 'filter_kuningan', 'kopling_keramik', 'cvt_hidrolik', 'busi_iridium', 'noken_as_balap',
               'injektor_kembar', 'ecu_pelaut_pintar', 'bore_up_blok', 'turbo_sentrifugal'], 230, 5, 40)
    ) as v(b, id, nama, kapal, kelas, parts, react, noise, seb)
   where v.b = p_babak
$$;

create or replace function game.ps_gugur_row(p_pid uuid) returns game.ps_gugur
language plpgsql as $$
declare r game.ps_gugur; v_w int := game.gugur_week();
begin
  insert into game.ps_gugur(player_id, week) values (p_pid, v_w) on conflict do nothing;
  select * into r from game.ps_gugur where player_id = p_pid and week = v_w;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- ROMBONGAN ADU
-- ---------------------------------------------------------------------
create or replace function game.ps_room_aktif(p_pid uuid) returns text
language sql stable as $$
  select r.id from game.ps_room r join game.ps_room_anggota m on m.room_id = r.id
   where m.player_id = p_pid and m.status = 'ikut' and r.status in ('lobi', 'jalan')
   order by r.created desc limit 1
$$;

create or replace function game.ps_adu_jml(p_pid uuid) returns int
language sql stable as $$
  select count(*)::int from game.ps_room r join game.ps_room_anggota m on m.room_id = r.id
   where m.player_id = p_pid and m.status = 'ikut' and m.bayar >= 0 and r.mulai is not null
     and r.game_day = game.game_day() and r.status in ('jalan', 'selesai')
$$;

-- Selesaikan rombongan: semua catatan masuk, atau batas setor lewat.
create or replace function game.ps_room_hitung(p_id text) returns void
language plpgsql as $$
declare r game.ps_room; m record; v_h jsonb; v_best int; v_log int := 0; v_fin int := 0; v_pot bigint := 0;
  v_win int; v_bagi bigint; v_sisa bigint; v_medali int := greatest(0, game.cfg_num('MedaliAdu', 1))::int;
  v_rank int; v_res jsonb := '{}'::jsonb; v_sp game.ps_sp; v_habis boolean; v_n int;
begin
  select * into r from game.ps_room where id = p_id for update;
  if r.id is null then return; end if;
  if r.status = 'lobi' then
    if game.now_ms() - r.created > 600000 then
      update game.ps_room set status = 'batal' where id = r.id;
    end if;
    return;
  end if;
  if r.status <> 'jalan' then return; end if;
  v_habis := game.now_ms() > r.mulai + r.meriam_ms + greatest(30, game.cfg_num('PsSetorDetik', 90))::bigint * 1000;
  if not v_habis and exists (select 1 from game.ps_room_anggota where room_id = r.id and status = 'ikut' and log is null) then
    return;
  end if;

  -- hitung tiap catatan
  for m in select * from game.ps_room_anggota where room_id = r.id and status = 'ikut' order by urut loop
    v_pot := v_pot + m.bayar;
    if m.log is not null then
      v_log := v_log + 1;
      v_sp := game.ps_spesifikasi(m.kelas, m.parts, m.rasio);
      v_h := game.ps_sim(v_sp, r.jarak_mm, r.meriam_ms, m.log, null);
      update game.ps_room_anggota set hasil = v_h where room_id = r.id and player_id = m.player_id;
      if (v_h ->> 'fin') is not null and not (v_h ->> 'jebol')::boolean then v_fin := v_fin + 1; end if;
      if (v_h ->> 'jebol')::boolean then update game.ps_pemain set jebol = true, updated_at = now() where player_id = m.player_id; end if;
    else
      update game.ps_room_anggota set hasil = jsonb_build_object('fin', null, 'jebol', false, 'dnf', true)
       where room_id = r.id and player_id = m.player_id;
    end if;
  end loop;

  if v_fin = 0 then
    -- tidak ada yang sampai Finish: taruhan kembali
    for m in select * from game.ps_room_anggota where room_id = r.id and status = 'ikut' and bayar > 0 loop
      perform game.ps_kas_catat(m.player_id, m.bayar, 'adu_kembali', r.id);
    end loop;
    update game.ps_room set status = 'selesai', hasil = jsonb_build_object('pot', 0, 'kembali', true, 'catatan', v_log) where id = r.id;
  else
    select min((hasil ->> 'fin')::int) into v_best from game.ps_room_anggota
     where room_id = r.id and status = 'ikut' and (hasil ->> 'fin') is not null and not coalesce((hasil ->> 'jebol')::boolean, false);
    select count(*) into v_win from game.ps_room_anggota
     where room_id = r.id and status = 'ikut' and (hasil ->> 'fin')::int = v_best and not coalesce((hasil ->> 'jebol')::boolean, false);
    v_bagi := v_pot / greatest(1, v_win); v_sisa := v_pot - v_bagi * v_win; v_rank := 0;
    for m in select a.*, (a.hasil ->> 'fin')::int as f from game.ps_room_anggota a
              where a.room_id = r.id and a.status = 'ikut'
              order by case when (a.hasil ->> 'fin') is null or coalesce((a.hasil ->> 'jebol')::boolean, false) then 1 else 0 end,
                       (a.hasil ->> 'fin')::int nulls last, a.urut loop
      v_rank := v_rank + 1;
      if m.f = v_best and not coalesce((m.hasil ->> 'jebol')::boolean, false) then
        if v_bagi + v_sisa > 0 then perform game.ps_kas_catat(m.player_id, v_bagi + v_sisa, 'adu_pot', r.id); end if;
        if v_log >= 2 and v_medali > 0 then
          insert into game.medali(player_id, jumlah, total) values (m.player_id, v_medali, v_medali)
            on conflict (player_id) do update set jumlah = game.medali.jumlah + v_medali, total = game.medali.total + v_medali;
        end if;
        update game.ps_room_anggota set hasil = hasil || jsonb_build_object('peringkat', 1, 'menang', true, 'dapat', v_bagi + v_sisa,
               'medali', case when v_log >= 2 then v_medali else 0 end)
         where room_id = r.id and player_id = m.player_id;
        v_sisa := 0;
      else
        update game.ps_room_anggota set hasil = hasil || jsonb_build_object('peringkat', v_rank, 'menang', false, 'dapat', 0, 'medali', 0)
         where room_id = r.id and player_id = m.player_id;
      end if;
      if m.f is not null and not coalesce((m.hasil ->> 'jebol')::boolean, false) then
        perform game.ps_rekor_catat(m.player_id, r.jarak_mm, m.f, coalesce((m.hasil ->> 'top')::int, 0), m.kelas, coalesce(array_length(m.parts, 1), 0));
      end if;
    end loop;
    update game.ps_room set status = 'selesai', hasil = jsonb_build_object('pot', v_pot, 'terbaik', v_best, 'pemenang', v_win, 'catatan', v_log) where id = r.id;
  end if;

  for m in select * from game.ps_room_anggota where room_id = r.id and status = 'ikut' loop
    insert into game.ps_riwayat(player_id, mode, jarak_mm, kelas, fin_ms, top_mm, ket)
    values (m.player_id, 'adu_kapten', r.jarak_mm, coalesce(m.kelas, 'sekoci_standar'),
            case when coalesce((m.hasil ->> 'jebol')::boolean, false) then null else (m.hasil ->> 'fin')::int end,
            (m.hasil ->> 'top')::int,
            case when coalesce((m.hasil ->> 'menang')::boolean, false) then 'Juara Adu'
                 when coalesce((m.hasil ->> 'jebol')::boolean, false) then 'Mesin jebol'
                 when m.log is null then 'Tidak menyetor'
                 when (select (hasil ->> 'kembali')::boolean from game.ps_room where id = r.id) then 'Taruhan kembali'
                 else 'Peringkat ' || coalesce(m.hasil ->> 'peringkat', '-') end);
    perform game.mp_push_inbox(m.player_id, jsonb_build_object('type', 'pacu_hasil', 'roomId', r.id));
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Rekor & papan
-- ---------------------------------------------------------------------
create or replace function game.ps_rekor_catat(p_pid uuid, p_jarak int, p_fin int, p_top int, p_kelas text, p_n int) returns void
language sql as $$
  insert into game.ps_rekor(player_id, jarak_mm, fin_ms, top_mm, kelas, parts_n) values (p_pid, p_jarak, p_fin, p_top, p_kelas, p_n)
  on conflict (player_id, jarak_mm) do update set fin_ms = excluded.fin_ms, top_mm = excluded.top_mm, kelas = excluded.kelas,
    parts_n = excluded.parts_n, at = now()
  where excluded.fin_ms < game.ps_rekor.fin_ms
$$;

create or replace function game.ps_hof(p_pid uuid, p_jarak int) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('nama', game.ps_nama(r.player_id), 'kapal', game.ps_kapal_label(r.kelas, r.parts_n),
           'waktuDetik', r.fin_ms / 1000.0, 'topKnot', game.ps_knot(r.top_mm), 'isPemain', r.player_id = p_pid)
           order by r.fin_ms, r.at), '[]'::jsonb)
    from (select * from game.ps_rekor where jarak_mm = p_jarak order by fin_ms, at limit 10) r
$$;

-- ---------------------------------------------------------------------
-- View: state lengkap untuk window.PacuSelat.update(state)
-- ---------------------------------------------------------------------
create or replace function game.ps_room_view(p_room text, p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', r.id, 'status', r.status, 'seed', r.seed, 'jarakMm', r.jarak_mm, 'waktuMeriamMs', r.meriam_ms,
    'mulaiServerMs', r.mulai, 'nowMs', game.now_ms(), 'taruhan', r.taruhan, 'tuan', r.tuan = p_pid, 'namaTuan', game.ps_nama(r.tuan),
    'hasil', r.hasil,
    'anggota', (select coalesce(jsonb_agg(jsonb_build_object('id', coalesce(game.mp_pub_of(a.player_id), 'k' || a.urut),
                  'nama', a.nama, 'status', a.status, 'kelas', coalesce(a.kelas, pp.kelas_aktif, 'sekoci_standar'),
                  'parts', to_jsonb(coalesce(a.parts, pp.parts, '{}')), 'rasioPreset', coalesce(a.rasio, pp.rasio, '800'),
                  'aku', a.player_id = p_pid, 'setor', a.log is not null, 'hasil', a.hasil) order by a.urut), '[]'::jsonb)
                  from game.ps_room_anggota a left join game.ps_pemain pp on pp.player_id = a.player_id
                 where a.room_id = r.id and a.status in ('ikut', 'diundang')
                   and (a.status = 'ikut' or game.now_ms() - a.diundang < greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000))
  ) from game.ps_room r where r.id = p_room
$$;

create or replace function game.ps_adu_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_room text := game.ps_room_aktif(p_pid); v_rb jsonb; v_kap jsonb; v_inv jsonb; v_maks int := greatest(1, game.cfg_num('PsAduMaks', 10))::int;
  v_sisa int; v_tuan boolean; v_penuh boolean; v_jml int;
begin
  v_sisa := greatest(0, v_maks - game.ps_adu_jml(p_pid));
  if v_room is not null then
    v_rb := game.ps_room_view(v_room, p_pid);
    if v_rb ->> 'status' <> 'lobi' then v_rb := null; end if;
  end if;
  v_tuan := v_rb is null or (v_rb ->> 'tuan')::boolean;
  v_jml := case when v_rb is null then 1 else jsonb_array_length(v_rb -> 'anggota') end;
  v_penuh := v_jml >= 4;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.pub, 'nama', x.nama, 'kelas', x.kelas,
           'bisaDitantang', v_tuan and not v_penuh and v_sisa > 0 and x.bebas and x.kuota and not x.jebol,
           'alasan', case when not x.bebas then 'Sedang Lomba' when not x.kuota then 'Jatah habis' when x.jebol then 'Mesin jebol'
                          when not v_tuan then 'Bukan tuan' when v_penuh then 'Rombongan penuh' when v_sisa <= 0 then 'Jatahmu habis' else null end)
           order by x.nama), '[]'::jsonb)
    into v_kap
    from (select pr.pub, pl.player_id, coalesce(nullif(pl.character_name, ''), 'Kapten') as nama,
                 coalesce(pp.kelas_aktif, 'sekoci_standar') as kelas, coalesce(pp.jebol, false) as jebol,
                 game.ps_room_aktif(pl.player_id) is null as bebas,
                 game.ps_adu_jml(pl.player_id) < v_maks as kuota
            from game.mp_presence pr join game.players pl on pl.player_id = pr.player_id
            left join game.ps_pemain pp on pp.player_id = pr.player_id
           where pr.player_id <> p_pid and game.mp_online(pr) and not pr.sea and pr.c = 'zentul'
             and game.ps_buka(pr.player_id)
             and not exists (select 1 from game.ps_room_anggota a where a.room_id = v_room and a.player_id = pr.player_id
                              and (a.status = 'ikut' or (a.status = 'diundang' and game.now_ms() - a.diundang < greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000)))
           limit 20) x;
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'dari', game.ps_nama(r.tuan),
           'sisaDetik', greatest(0, (greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000 - (game.now_ms() - a.diundang)) / 1000),
           'jumlah', (select count(*) from game.ps_room_anggota b where b.room_id = r.id and b.status = 'ikut'),
           'taruhan', r.taruhan) order by a.diundang desc), '[]'::jsonb)
    into v_inv
    from game.ps_room_anggota a join game.ps_room r on r.id = a.room_id
   where a.player_id = p_pid and a.status = 'diundang' and r.status = 'lobi'
     and game.now_ms() - a.diundang < greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000;
  return jsonb_build_object('kaptenDiZentul', v_kap, 'undanganMasuk', v_inv, 'undanganKeluar', null,
    'sisaAduHariIni', v_sisa,
    'rombongan', case when v_rb is null then null else v_rb || jsonb_build_object('maks', 4,
       'bisaMulai', (v_rb ->> 'tuan')::boolean and (select count(*) from jsonb_array_elements(v_rb -> 'anggota') e where e ->> 'status' = 'ikut') >= 2) end);
end $$;

create or replace function game.ps_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare p game.ps_pemain; pl game.players; g game.ps_gugur; v_kat jsonb := game.ps_katalog(); k text;
  v_hk jsonb := '{}'; v_hp jsonb := '{}'; v_boleh jsonb := '{}'; v_alasan jsonb := '{}'; v_h bigint;
  v_gratis boolean; v_biaya bigint; v_rp jsonb; v_riw jsonb; v_rb text; v_rbv jsonb;
begin
  p := game.ps_row(p_pid);
  select * into pl from game.players where player_id = p_pid;
  g := game.ps_gugur_row(p_pid);
  for k in select key from jsonb_each(v_kat -> 'kelas') loop
    v_h := game.ps_harga(k);
    v_hk := v_hk || jsonb_build_object(k, case when v_h = 0 then 'Standar' else game.ps_rp(v_h) || ' Gold' end);
    if not (k = any (p.kapal)) and pl.gold < v_h then
      v_boleh := v_boleh || jsonb_build_object(k, false);
      v_alasan := v_alasan || jsonb_build_object(k, 'Gold kurang ' || game.ps_rp(v_h - pl.gold));
    end if;
  end loop;
  for k in select key from jsonb_each(v_kat -> 'parts') union all select 'reparasi_mesin' loop
    v_h := game.ps_harga(k);
    v_hp := v_hp || jsonb_build_object(k, game.ps_rp(v_h) || ' Gold');
    if not (k = any (p.parts)) and pl.gold < v_h then
      v_boleh := v_boleh || jsonb_build_object(k, false);
      v_alasan := v_alasan || jsonb_build_object(k, 'Gold kurang ' || game.ps_rp(v_h - pl.gold));
    end if;
  end loop;
  v_gratis := p.gratis_hari <> game.game_day() and game.cfg_num('PsUjiGratis', 1) > 0;
  v_biaya := greatest(0, game.cfg_num('PsUjiBiaya', 500))::bigint;
  select jsonb_object_agg(j::text, (select fin_ms / 1000.0 from game.ps_rekor where player_id = p_pid and jarak_mm = j * 1000))
    into v_rp from unnest(array[400, 800, 1400]) j;
  select coalesce(jsonb_agg(jsonb_build_object(
           'mode', case h.mode when 'uji_800' then 'Uji Lintasan 800m' when 'uji_1400' then 'Uji Lintasan 1,4 km'
                     when 'pacu_gugur' then 'Pacu Gugur 400m' else 'Adu Kapten ' || (h.jarak_mm / 1000) || 'm' end,
           'kapal', game.ps_kapal_label(h.kelas, 0),
           'waktu', case when h.fin_ms is null then '—' else replace(to_char(h.fin_ms / 1000.0, 'FM990.000'), '.', ',') || ' dtk' end,
           'top', game.ps_knot(h.top_mm) || ' kt (' || ((game.ps_knot(h.top_mm) * 1852 + 500) / 1000) || ' km/h)',
           'keterangan', coalesce(h.ket, '—')) order by h.id desc), '[]'::jsonb)
    into v_riw from (select * from game.ps_riwayat where player_id = p_pid order by id desc limit 10) h;
  v_rb := game.ps_room_aktif(p_pid);
  return jsonb_build_object(
    'namaKapten', game.ps_nama(p_pid),
    'gold', pl.gold,
    'medali', jsonb_build_object('jumlah', game.medali_jml(p_pid),
       'kurs', jsonb_build_object('gigi', game.cfg_num('MedaliGigi', 25)::int, 'rantai', game.cfg_num('MedaliRantai', 35)::int,
                                  'oli', game.cfg_num('MedaliOli', 10)::int),
       'gigiTerbuka', game.wl_buka(p_pid)),
    'kelasAktif', p.kelas_aktif,
    'kapalDimiliki', to_jsonb(p.kapal),
    'partTerpasang', to_jsonb(game.ps_parts_rapi(p.parts)),
    'mesinJebol', p.jebol,
    'rasioPreset', p.rasio,
    'autoShift', false,
    'hargaKapal', v_hk, 'hargaPart', v_hp, 'bolehBeli', v_boleh, 'alasanKunci', v_alasan,
    'infoMode', jsonb_build_object(
       'uji_800', '800m · ' || case when v_gratis then 'Gratis 1×' else game.ps_rp(v_biaya) || ' Gold' end,
       'uji_1400', '1,4 km · ' || game.ps_rp(v_biaya) || ' Gold',
       'adu_kapten', 'Taruhan ' || game.ps_rp(greatest(0, game.cfg_num('PsTaruhan', 15000))::bigint) || ' Gold',
       'pacu_gugur', case when not game.gugur_buka() then 'Gelanggang tutup'
                          when g.status = 'juara' then 'Juara pekan ini'
                          when g.status = 'gugur' then 'Gugur · tunggu Senin'
                          else 'Babak ' || g.babak || '/4 · 400m' end),
    'rekorPribadi', v_rp,
    'hallOfFame', jsonb_build_object('400', game.ps_hof(p_pid, 400000), '800', game.ps_hof(p_pid, 800000), '1400', game.ps_hof(p_pid, 1400000)),
    'riwayat', v_riw,
    'siap', game.ps_siap(p_pid),
    'gugur', jsonb_build_object('babak', g.babak, 'status', g.status, 'buka', game.gugur_buka()),
    'adu', game.ps_adu_view(p_pid),
    'roomJalan', case when v_rb is not null and (select status from game.ps_room where id = v_rb) = 'jalan' then v_rb else null end
  );
end $$;

-- Bentuk balapan untuk run solo
create or replace function game.ps_run_view(r game.ps_run, p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', r.id, 'mode', r.mode,
    'judul', case r.mode when 'uji_800' then 'Uji Lintasan · 800m' when 'uji_1400' then 'Uji Lintasan · 1,4 km'
                         else 'Pacu Gugur · Babak ' || coalesce(r.lawan ->> 'babak', '1') || '/4 · melawan ' || coalesce(r.lawan ->> 'nama', '') end,
    'seed', r.seed, 'jarakMm', r.jarak_mm, 'jarakMeter', r.jarak_mm / 1000, 'waktuMeriamMs', r.meriam_ms,
    'rasioPreset', r.rasio,
    'babak', case when r.mode = 'pacu_gugur' then (r.lawan ->> 'babak')::int end,
    'totalBabak', case when r.mode = 'pacu_gugur' then 4 end,
    'peserta', jsonb_build_array(jsonb_build_object('id', 'pemain', 'nama', game.ps_nama(p_pid), 'isPemain', true,
                 'kelas', r.kelas, 'parts', to_jsonb(r.parts), 'rasioPreset', r.rasio))
               || case when r.lawan is null then '[]'::jsonb else jsonb_build_array(r.lawan - 'babak' - 'kode' - 'kapalNama') end,
    'inputLog', '[]'::jsonb)
$$;

-- ---------------------------------------------------------------------
-- API  api_pacuSelat([aksi, ...])
--   status | beli kelas | pasang part | rasio k | mulai mode | setor runId log | tinggal runId
--   ajak pub | jawab roomId ya | keluarRb roomId | mulaiRb roomId | lihatRb roomId | pos roomId posMm v gear tms
--   setorRb roomId log
-- ---------------------------------------------------------------------
create or replace function public.api_pacuSelat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := coalesce(game.arg(a, 0), 'status'); v_kat jsonb := game.ps_katalog();
  p game.ps_pemain; v_k text; v_h bigint; v_g game.ps_gugur; v_seed bigint; v_mode text; v_jarak int; v_biaya bigint := 0;
  v_lawan jsonb; v_run game.ps_run; v_rid text; v_log jsonb; v_sp game.ps_sp; v_hasil jsonb; v_ai jsonb; v_fin int; v_afin int;
  v_menang boolean; v_ket text; v_out jsonb; v_room game.ps_room; v_t uuid; v_n int; v_maks int; m record; v_taruhan bigint;
  v_tn text; v_now bigint := game.now_ms(); v_cek jsonb; v_jud text; v_sub text; v_hadiah text; v_oli int; v_gold bigint;
begin
  if v_id is null or not game.ps_buka(v_id) then
    if v_act = 'status' then return jsonb_build_object('ps', null); end if;
    raise exception 'Aksi tidak dikenal.';
  end if;
  perform game.mp_touch(v_id);
  p := game.ps_row(v_id);

  if v_act = 'status' then
    v_rid := game.ps_room_aktif(v_id);
    if v_rid is not null then perform game.ps_room_hitung(v_rid); end if;
    return jsonb_build_object('ps', game.ps_state(v_id));
  end if;

  -- ------------------------------------------------- GALANGAN & BENGKEL
  if v_act in ('beli', 'pasang', 'rasio') then
    if not game.ps_siap(v_id) then raise exception 'Merapatlah di Zentul dulu, Kapten.'; end if;
    if game.ps_room_aktif(v_id) is not null then raise exception 'Selesaikan rombongan Adu dulu.'; end if;
    select * into p from game.ps_pemain where player_id = v_id for update;
  end if;

  if v_act = 'beli' then
    v_k := game.arg(a, 1);
    if not (v_kat -> 'kelas' ? coalesce(v_k, '')) then raise exception 'Kelas kapal itu tidak ada di galangan.'; end if;
    if not (v_k = any (p.kapal)) then
      v_h := game.ps_harga(v_k);
      perform game.ps_bayar(v_id, v_h, 'galangan', v_k);
      update game.ps_pemain set kapal = array_append(kapal, v_k) where player_id = v_id;
      perform game.log(v_id, 'Galangan Zentul: membeli ' || (v_kat -> 'kelas' -> v_k ->> 'nama') || ' (' || game.ps_rp(v_h) || ' gold).');
    end if;
    update game.ps_pemain set kelas_aktif = v_k, updated_at = now() where player_id = v_id;
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id),
      'pesan', jsonb_build_object('teks', (v_kat -> 'kelas' -> v_k ->> 'nama') || ' siap di dermaga.', 'jenis', 'sukses', 'id', v_now));
  end if;

  if v_act = 'pasang' then
    v_k := game.arg(a, 1);
    if v_k = 'reparasi_mesin' then
      if not p.jebol then raise exception 'Mesinmu tidak sedang jebol.'; end if;
      v_h := game.ps_harga('reparasi_mesin');
      perform game.ps_bayar(v_id, v_h, 'reparasi', null);
      update game.ps_pemain set jebol = false, updated_at = now() where player_id = v_id;
      perform game.log(v_id, 'Bengkel Zentul: reparasi blok mesin (' || game.ps_rp(v_h) || ' gold).');
      return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id),
        'pesan', jsonb_build_object('teks', 'Blok mesin diganti. Siap berlomba lagi.', 'jenis', 'sukses', 'id', v_now));
    end if;
    if not (v_kat -> 'parts' ? coalesce(v_k, '')) then raise exception 'Komponen itu tidak ada di bengkel.'; end if;
    if v_k = any (p.parts) then raise exception 'Komponen itu sudah terpasang.'; end if;
    v_h := game.ps_harga(v_k);
    perform game.ps_bayar(v_id, v_h, 'bengkel', v_k);
    update game.ps_pemain set parts = game.ps_parts_rapi(array_append(parts, v_k)), updated_at = now() where player_id = v_id;
    perform game.log(v_id, 'Bengkel Zentul: memasang ' || (v_kat -> 'parts' -> v_k ->> 'nama') || ' (' || game.ps_rp(v_h) || ' gold).');
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id),
      'pesan', jsonb_build_object('teks', (v_kat -> 'parts' -> v_k ->> 'nama') || ' terpasang.', 'jenis', 'sukses', 'id', v_now));
  end if;

  if v_act = 'rasio' then
    v_k := game.arg(a, 1);
    if v_k not in ('400', '800', '1400') then raise exception 'Setelan rasio tidak dikenal.'; end if;
    update game.ps_pemain set rasio = v_k, updated_at = now() where player_id = v_id;
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id));
  end if;

  -- ------------------------------------------------- BALAPAN SOLO
  if v_act = 'mulai' then
    v_mode := game.arg(a, 1);
    if v_mode not in ('uji_800', 'uji_1400', 'pacu_gugur') then raise exception 'Mode itu tidak dikenal.'; end if;
    if not game.ps_siap(v_id) then raise exception 'Merapatlah di Zentul dulu, Kapten.'; end if;
    if p.jebol then raise exception 'Mesin kapalmu jebol. Perbaiki dulu di Bengkel Mesin.'; end if;
    if game.ps_room_aktif(v_id) is not null then raise exception 'Kau sedang di rombongan Adu.'; end if;
    select * into p from game.ps_pemain where player_id = v_id for update;
    -- run lama yang belum disetor dianggap ditinggal
    update game.ps_run set status = 'tinggal' where player_id = v_id and status = 'jalan';
    v_seed := 1 + floor(random() * 2000000000)::bigint;
    v_jarak := case v_mode when 'uji_800' then 800000 when 'uji_1400' then 1400000 else 400000 end;
    if v_mode = 'pacu_gugur' then
      if not game.gugur_buka() then raise exception 'Gelanggang Yaptob sedang tutup.'; end if;
      v_g := game.ps_gugur_row(v_id);
      if v_g.status = 'gugur' then raise exception 'Kau sudah gugur pekan ini. Gelanggang dibuka lagi Senin.'; end if;
      if v_g.status = 'juara' then raise exception 'Kau sudah menembus Yaptob pekan ini.'; end if;
      v_lawan := game.ps_gugur_lawan(v_g.babak, v_seed) || jsonb_build_object('babak', v_g.babak);
    else
      if v_mode = 'uji_800' and p.gratis_hari <> game.game_day() and game.cfg_num('PsUjiGratis', 1) > 0 then
        update game.ps_pemain set gratis_hari = game.game_day() where player_id = v_id;
      else
        v_biaya := greatest(0, game.cfg_num('PsUjiBiaya', 500))::bigint;
        perform game.ps_bayar(v_id, v_biaya, 'uji', v_mode);
      end if;
    end if;
    v_rid := game.mp_uid('psr');
    insert into game.ps_run(id, player_id, mode, seed, jarak_mm, meriam_ms, kelas, parts, rasio, lawan, mulai, biaya, game_day)
    values (v_rid, v_id, v_mode, v_seed, v_jarak, game.ps_meriam(v_seed), p.kelas_aktif, game.ps_parts_rapi(p.parts), p.rasio,
            v_lawan, v_now, v_biaya, game.game_day())
    returning * into v_run;
    return jsonb_build_object('ok', true, 'balapan', game.ps_run_view(v_run, v_id), 'ps', game.ps_state(v_id));
  end if;

  if v_act in ('setor', 'tinggal') then
    v_rid := game.arg(a, 1);
    select * into v_run from game.ps_run where id = v_rid and player_id = v_id for update;
    if v_run.id is null then raise exception 'Catatan balapan itu tidak ditemukan.'; end if;
    if v_run.status <> 'jalan' then
      if v_run.hasil is not null then return jsonb_build_object('ok', true, 'hasil', v_run.hasil, 'ps', game.ps_state(v_id)); end if;
      raise exception 'Balapan itu sudah ditutup.';
    end if;
    v_log := case when v_act = 'setor' then game.arg_json(a, 2) else '[]'::jsonb end;
    if not game.ps_log_cek(v_log) then raise exception 'Catatan ketukan tidak wajar.'; end if;
    v_sp := game.ps_spesifikasi(v_run.kelas, v_run.parts, v_run.rasio);
    v_hasil := game.ps_sim(v_sp, v_run.jarak_mm, v_run.meriam_ms, v_log, null);
    v_fin := (v_hasil ->> 'fin')::int;
    if v_act = 'tinggal' then v_fin := null; v_hasil := v_hasil || jsonb_build_object('fin', null, 'tinggal', true); end if;
    -- jam dinding: catatan tidak boleh tiba lebih cepat dari waktu tempuhnya
    if v_fin is not null and v_now < v_run.mulai + v_run.meriam_ms + v_fin - 2500 then
      raise exception 'Juru tulis belum melihat kapalmu sampai di garis Finish.';
    end if;
    if (v_hasil ->> 'jebol')::boolean then update game.ps_pemain set jebol = true, updated_at = now() where player_id = v_id; end if;

    v_menang := null; v_hadiah := null;
    if v_run.mode = 'pacu_gugur' then
      v_ai := jsonb_build_object('react', (v_run.lawan ->> 'aiReaksiMs')::int, 'noise', (v_run.lawan ->> 'aiShiftNoisePermil')::int,
                                 'sebaran', (v_run.lawan ->> 'aiSebaranPermil')::int, 'seed', (v_run.lawan ->> 'aiSeed')::bigint);
      v_afin := (game.ps_sim(game.ps_spesifikasi(v_run.lawan ->> 'kelas', array(select jsonb_array_elements_text(v_run.lawan -> 'parts')), '800'),
                             v_run.jarak_mm, v_run.meriam_ms, null, v_ai) ->> 'fin')::int;
      v_menang := v_fin is not null and not (v_hasil ->> 'jebol')::boolean and (v_afin is null or v_fin < v_afin);
      v_g := game.ps_gugur_row(v_id);
      if v_menang then
        if v_g.babak >= 4 then
          update game.ps_gugur set status = 'juara', at = now() where player_id = v_id and week = v_g.week;
          v_oli := greatest(0, game.cfg_num('GugurHadiahOli', 12))::int;
          v_gold := greatest(0, game.cfg_num('GugurHadiahGold', 120000))::bigint;
          if v_oli > 0 and game.cargo_free(v_id) < v_oli * coalesce((select size from game.commodities where id = 'oli_hitam'), 1) then
            v_oli := greatest(0, floor(game.cargo_free(v_id) / coalesce((select size from game.commodities where id = 'oli_hitam'), 1))::int);
          end if;
          if v_gold > 0 then perform game.ps_kas_catat(v_id, v_gold, 'gugur_juara', v_run.id); end if;
          if v_oli > 0 then perform game.adjust_inventory(v_id, 'oli_hitam', v_oli); end if;
          v_hadiah := '+' || game.ps_rp(v_gold) || ' Gold & +' || v_oli || ' Oli Hitam';
        else
          update game.ps_gugur set babak = babak + 1, at = now() where player_id = v_id and week = v_g.week;
          v_hadiah := 'Lolos ke babak ' || (v_g.babak + 1) || '/4';
        end if;
      else
        update game.ps_gugur set status = 'gugur', at = now() where player_id = v_id and week = v_g.week;
        v_hadiah := 'Gugur pekan ini. Gelanggang dibuka lagi Senin.';
      end if;
    end if;

    if v_fin is not null and not (v_hasil ->> 'jebol')::boolean then
      perform game.ps_rekor_catat(v_id, v_run.jarak_mm, v_fin, (v_hasil ->> 'top')::int, v_run.kelas, coalesce(array_length(v_run.parts, 1), 0));
    end if;
    v_ket := case when (v_hasil ->> 'jebol')::boolean then 'Mesin jebol' when v_act = 'tinggal' then 'Ditinggal'
                  when v_menang is true then case when v_run.lawan ->> 'kode' = 'yaptob' then 'Juara Gelanggang' else 'Menang' end
                  when v_menang is false then 'Gugur' else 'Tercatat' end;
    insert into game.ps_riwayat(player_id, mode, jarak_mm, kelas, fin_ms, top_mm, ket)
    values (v_id, v_run.mode, v_run.jarak_mm, v_run.kelas, case when (v_hasil ->> 'jebol')::boolean then null else v_fin end, (v_hasil ->> 'top')::int, v_ket);

    v_jud := case when (v_hasil ->> 'jebol')::boolean then 'Mesin Jebol!'
                  when v_act = 'tinggal' then 'Lintasan Ditinggal'
                  when v_menang is true then case when v_run.lawan ->> 'kode' = 'yaptob' then 'Juara Gelanggang!' else 'Menang Babak!' end
                  when v_menang is false then 'Gugur di Selat' else 'Finish!' end;
    v_sub := case when v_run.mode = 'pacu_gugur' then 'Pacu Gugur · melawan ' || coalesce(v_run.lawan ->> 'nama', '')
                  else 'Catatan resmi juru tulis Rayan Bazzy' end;
    v_out := jsonb_build_object('balapanId', v_run.id, 'judul', v_jud, 'subJudul', v_sub,
      'menang', coalesce(v_menang, v_fin is not null), 'mesinJebol', (v_hasil ->> 'jebol')::boolean,
      'waktuMs', v_fin, 'topSpeedKnot', game.ps_knot((v_hasil ->> 'top')::bigint), 'zeroToHundredMs', (v_hasil ->> 'z100')::int,
      'finishPerKapal', jsonb_build_object('pemain', v_fin) || case when v_run.lawan is null then '{}'::jsonb
                          else jsonb_build_object(v_run.lawan ->> 'id', v_afin) end,
      'keteranganHadiah', coalesce(v_hadiah, case when v_fin is null then 'Tidak sampai garis Finish.'
         when (select fin_ms from game.ps_rekor where player_id = v_id and jarak_mm = v_run.jarak_mm) = v_fin then 'Rekor pribadi baru!'
         else 'Tercatat di Papan Rekor.' end),
      'shifts', v_hasil -> 'shifts');
    update game.ps_run set status = case when v_act = 'tinggal' then 'tinggal' else 'selesai' end, log = v_log, hasil = v_out where id = v_run.id;
    return jsonb_build_object('ok', true, 'hasil', v_out, 'ps', game.ps_state(v_id));
  end if;

  -- ------------------------------------------------- ROMBONGAN ADU KAPTEN
  if v_act = 'ajak' then
    if not game.ps_siap(v_id) then raise exception 'Merapatlah di Zentul dulu, Kapten.'; end if;
    if p.jebol then raise exception 'Mesin kapalmu jebol. Perbaiki dulu di Bengkel Mesin.'; end if;
    v_maks := greatest(1, game.cfg_num('PsAduMaks', 10))::int;
    if game.ps_adu_jml(v_id) >= v_maks then raise exception 'Jatah Adu-mu hari ini sudah habis.'; end if;
    v_t := game.mp_unpub(game.arg(a, 1));
    if v_t = v_id then raise exception 'Kapten itu tidak ditemukan.'; end if;
    if not game.ps_siap(v_t) then raise exception 'Kapten itu tidak sedang merapat di Zentul.'; end if;
    if game.ps_room_aktif(v_t) is not null then raise exception 'Kapten itu sedang di rombongan lain.'; end if;
    v_rid := game.ps_room_aktif(v_id);
    if v_rid is null then
      v_rid := game.mp_uid('psb');
      insert into game.ps_room(id, tuan, created, game_day, taruhan)
      values (v_rid, v_id, v_now, game.game_day(), greatest(0, game.cfg_num('PsTaruhan', 15000))::int);
      insert into game.ps_room_anggota(room_id, player_id, nama, status, urut, diundang)
      values (v_rid, v_id, game.ps_nama(v_id), 'ikut', 1, v_now);
    end if;
    select * into v_room from game.ps_room where id = v_rid for update;
    if v_room.tuan <> v_id then raise exception 'Hanya tuan rombongan yang boleh mengajak.'; end if;
    if v_room.status <> 'lobi' then raise exception 'Rombongan sudah berangkat.'; end if;
    select count(*) into v_n from game.ps_room_anggota where room_id = v_rid
       and (status = 'ikut' or (status = 'diundang' and v_now - diundang < greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000));
    if v_n >= 4 and not exists (select 1 from game.ps_room_anggota where room_id = v_rid and player_id = v_t and status = 'diundang') then
      raise exception 'Rombongan sudah penuh (4 kapten).';
    end if;
    insert into game.ps_room_anggota(room_id, player_id, nama, status, urut, diundang)
    values (v_rid, v_t, game.ps_nama(v_t), 'diundang', 0, v_now)
    on conflict (room_id, player_id) do update set status = 'diundang', diundang = v_now
      where game.ps_room_anggota.status <> 'ikut';
    perform game.mp_push_inbox(v_t, jsonb_build_object('type', 'pacu_ajak', 'roomId', v_rid, 'from', game.ps_nama(v_id),
      'taruhan', v_room.taruhan, 'jumlah', (select count(*) from game.ps_room_anggota where room_id = v_rid and status = 'ikut')));
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id));
  end if;

  if v_act = 'jawab' then
    v_rid := game.arg(a, 1);
    select * into v_room from game.ps_room where id = v_rid for update;
    if v_room.id is null or v_room.status <> 'lobi' then raise exception 'Rombongan itu sudah tidak menunggu.'; end if;
    if not exists (select 1 from game.ps_room_anggota where room_id = v_rid and player_id = v_id and status = 'diundang'
                    and v_now - diundang < greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000) then
      raise exception 'Ajakan itu sudah kedaluwarsa.';
    end if;
    if lower(coalesce(game.arg(a, 2), 'false')) not in ('true', '1', 'ya') then
      update game.ps_room_anggota set status = 'tolak' where room_id = v_rid and player_id = v_id;
      perform game.mp_push_inbox(v_room.tuan, jsonb_build_object('type', 'pacu_tolak', 'roomId', v_rid, 'from', game.ps_nama(v_id)));
      return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id));
    end if;
    if not game.ps_siap(v_id) then raise exception 'Merapatlah di Zentul dulu, Kapten.'; end if;
    if p.jebol then raise exception 'Mesin kapalmu jebol. Perbaiki dulu di Bengkel Mesin.'; end if;
    if game.ps_room_aktif(v_id) is not null then raise exception 'Kau sudah di rombongan lain.'; end if;
    if game.ps_adu_jml(v_id) >= greatest(1, game.cfg_num('PsAduMaks', 10))::int then raise exception 'Jatah Adu-mu hari ini sudah habis.'; end if;
    select count(*) into v_n from game.ps_room_anggota where room_id = v_rid and status = 'ikut';
    if v_n >= 4 then raise exception 'Rombongan sudah penuh (4 kapten).'; end if;
    update game.ps_room_anggota set status = 'ikut', urut = v_n + 1 where room_id = v_rid and player_id = v_id;
    perform game.mp_push_inbox(v_room.tuan, jsonb_build_object('type', 'pacu_ikut', 'roomId', v_rid, 'from', game.ps_nama(v_id)));
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id));
  end if;

  if v_act = 'keluarRb' then
    v_rid := game.arg(a, 1);
    select * into v_room from game.ps_room where id = v_rid for update;
    if v_room.id is null then return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id)); end if;
    if v_room.status = 'lobi' then
      if v_room.tuan = v_id then
        update game.ps_room set status = 'batal' where id = v_rid;
        for m in select player_id from game.ps_room_anggota where room_id = v_rid and status in ('ikut', 'diundang') and player_id <> v_id loop
          perform game.mp_push_inbox(m.player_id, jsonb_build_object('type', 'pacu_bubar', 'roomId', v_rid, 'from', game.ps_nama(v_id)));
        end loop;
      else
        update game.ps_room_anggota set status = 'keluar' where room_id = v_rid and player_id = v_id;
      end if;
    end if;
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id));
  end if;

  if v_act = 'mulaiRb' then
    v_rid := game.arg(a, 1);
    select * into v_room from game.ps_room where id = v_rid for update;
    if v_room.id is null or v_room.status <> 'lobi' then raise exception 'Rombongan itu sudah tidak menunggu.'; end if;
    if v_room.tuan <> v_id then raise exception 'Hanya tuan rombongan yang memasang obor.'; end if;
    select count(*) into v_n from game.ps_room_anggota where room_id = v_rid and status = 'ikut';
    if v_n < 2 then raise exception 'Butuh minimal dua kapten di rombongan.'; end if;
    v_taruhan := v_room.taruhan;
    for m in select a.player_id, a.nama, pl.gold, pp.jebol from game.ps_room_anggota a
               join game.players pl on pl.player_id = a.player_id left join game.ps_pemain pp on pp.player_id = a.player_id
              where a.room_id = v_rid and a.status = 'ikut' loop
      if not game.ps_siap(m.player_id) then raise exception 'Kapal % sudah tidak di dermaga Zentul.', m.nama; end if;
      if coalesce(m.jebol, false) then raise exception 'Mesin kapal % sedang jebol.', m.nama; end if;
      if m.gold < v_taruhan then raise exception 'Gold % tidak cukup untuk taruhan.', m.nama; end if;
    end loop;
    v_seed := 1 + floor(random() * 2000000000)::bigint;
    update game.ps_room set status = 'jalan', seed = v_seed, meriam_ms = game.ps_meriam(v_seed),
           mulai = v_now + greatest(3000, game.cfg_num('PsMulaiJedaMs', 6000))::bigint, game_day = game.game_day()
     where id = v_rid returning * into v_room;
    for m in select a.player_id, pp.kelas_aktif, pp.parts, pp.rasio from game.ps_room_anggota a
               left join game.ps_pemain pp on pp.player_id = a.player_id
              where a.room_id = v_rid and a.status = 'ikut' loop
      perform game.ps_row(m.player_id);
      if v_taruhan > 0 then perform game.ps_bayar(m.player_id, v_taruhan, 'adu_taruhan', v_rid); end if;
      update game.ps_room_anggota set bayar = v_taruhan, kelas = coalesce(m.kelas_aktif, 'sekoci_standar'),
             parts = game.ps_parts_rapi(coalesce(m.parts, '{}')), rasio = coalesce(m.rasio, '800')
       where room_id = v_rid and player_id = m.player_id;
      perform game.mp_push_inbox(m.player_id, jsonb_build_object('type', 'pacu_mulai', 'roomId', v_rid));
    end loop;
    update game.ps_room_anggota set status = 'tolak' where room_id = v_rid and status = 'diundang';
    return jsonb_build_object('ok', true, 'room', game.ps_room_view(v_rid, v_id), 'ps', game.ps_state(v_id));
  end if;

  if v_act in ('lihatRb', 'pos', 'setorRb') then
    v_rid := game.arg(a, 1);
    if not exists (select 1 from game.ps_room_anggota where room_id = v_rid and player_id = v_id and status = 'ikut') then
      raise exception 'Kau bukan anggota rombongan itu.';
    end if;
    if v_act = 'pos' then
      update game.ps_room_anggota set pos = jsonb_build_object('p', coalesce(nullif(game.arg(a, 2), '')::bigint, 0),
             'v', coalesce(nullif(game.arg(a, 3), '')::bigint, 0), 'g', coalesce(nullif(game.arg(a, 4), '')::int, 1),
             't', coalesce(nullif(game.arg(a, 5), '')::int, 0)), pos_at = v_now
       where room_id = v_rid and player_id = v_id;
      return jsonb_build_object('ok', true, 'lawan', (select coalesce(jsonb_agg(jsonb_build_object('id', game.mp_pub_of(x.player_id),
                 'pos', x.pos, 'umur', v_now - x.pos_at, 'setor', x.log is not null)), '[]'::jsonb)
                 from game.ps_room_anggota x where x.room_id = v_rid and x.status = 'ikut' and x.player_id <> v_id and x.pos is not null),
             'status', (select status from game.ps_room where id = v_rid));
    end if;
    if v_act = 'setorRb' then
      select * into v_room from game.ps_room where id = v_rid for update;
      if v_room.status <> 'jalan' then return jsonb_build_object('ok', true, 'room', game.ps_room_view(v_rid, v_id), 'ps', game.ps_state(v_id)); end if;
      v_log := game.arg_json(a, 2);
      if not game.ps_log_cek(v_log) then raise exception 'Catatan ketukan tidak wajar.'; end if;
      select * into m from game.ps_room_anggota where room_id = v_rid and player_id = v_id;
      if m.log is null then
        v_hasil := game.ps_sim(game.ps_spesifikasi(m.kelas, m.parts, m.rasio), v_room.jarak_mm, v_room.meriam_ms, v_log, null);
        v_fin := (v_hasil ->> 'fin')::int;
        if v_fin is not null and v_now < v_room.mulai + v_room.meriam_ms + v_fin - 2500 then
          raise exception 'Juru tulis belum melihat kapalmu sampai di garis Finish.';
        end if;
        update game.ps_room_anggota set log = v_log where room_id = v_rid and player_id = v_id;
      end if;
    end if;
    perform game.ps_room_hitung(v_rid);
    return jsonb_build_object('ok', true, 'room', game.ps_room_view(v_rid, v_id), 'ps', game.ps_state(v_id));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_pacuselat');

-- ---------------------------------------------------------------------
-- Realtime: kanal privat 'pacu:<room>' untuk posisi lawan (hanya anggota rombongan yang sedang jalan)
-- ---------------------------------------------------------------------
create or replace function public.mt_rt_pacu_ok(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
begin
  if auth.uid() is null or p_topic is null or p_topic not like 'pacu:%' then return false; end if;
  return exists (select 1 from game.ps_room r join game.ps_room_anggota m on m.room_id = r.id
                  where r.id = substr(p_topic, 6) and r.status = 'jalan' and m.player_id = auth.uid() and m.status = 'ikut');
end $$;
revoke all on function public.mt_rt_pacu_ok(text) from public;
revoke all on function public.mt_rt_pacu_ok(text) from anon;
grant execute on function public.mt_rt_pacu_ok(text) to authenticated;

create or replace function public.mt_rt_can_read(p_topic text) returns boolean
language plpgsql stable security definer set search_path = game, public as $$
declare v_pub text;
begin
  if auth.uid() is null or p_topic is null then return false; end if;
  if p_topic = 'chat:global' or p_topic like 'chat:city:%' then return true; end if;
  if p_topic like 'player:%' then
    select pub into v_pub from game.mp_presence where player_id = auth.uid();
    return v_pub is not null and p_topic = 'player:' || v_pub;
  end if;
  if p_topic like 'duel:%' then return public.mt_rt_duel_ok(p_topic); end if;
  if p_topic like 'raid:%' then return public.mt_rt_raid_ok(p_topic); end if;
  if p_topic like 'pacu:%' then return public.mt_rt_pacu_ok(p_topic); end if;
  return false;
end $$;
revoke all on function public.mt_rt_can_read(text) from public;
revoke all on function public.mt_rt_can_read(text) from anon;
grant execute on function public.mt_rt_can_read(text) to authenticated;

do $$
begin
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists "marantau kirim pacu" on realtime.messages';
    execute 'create policy "marantau kirim pacu" on realtime.messages for insert to authenticated '
         || 'with check (realtime.messages.extension = ''broadcast'' and public.mt_rt_pacu_ok(realtime.topic()))';
  end if;
exception when others then
  raise warning 'Kebijakan kirim pacu tidak terpasang (relay RPC tetap jalan): %', sqlerrm;
end $$;
