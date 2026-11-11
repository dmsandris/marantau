-- =====================================================================
-- Marantau (Supabase) - 0071 QUEST RAHASIA "SURAT YANG SELALU TERTINGGAL SATU PELABUHAN" (Surat Pulang)
--                       + PERK ARCHETYPE HIDUP
-- ---------------------------------------------------------------------
-- Konsep: claude/KONSEP-Quest-Surat-Pulang.md (v1.2).
-- Side quest di luar Saga 3. Terbuka setelah Saga 2 selesai (duatangan step >= 5), saat panel Perpustakaan
-- Sowtour dibuka, dan HANYA bila tidak ada side quest lain yang sedang berjalan (game.side_quest_active, 0064).
-- Gerbang: SuratOpen (+ FiturPenguji). Rahasia: tanpa Tanda Jasa khusus, jurnal, chat dunia, atau Realtime.
-- Dibekukan selama Saga 3 aktif; perk ikut tidur selama itu (perk lahir dari kisah, Jam hanya menghapus kisah).
--
-- Langkah (game.player_quests, quest_id = 'surat'); step = langkah BERIKUTNYA yang dijalankan.
--    0 Sowtour · Pustaka     : Urut Cap (l0)        8 TooGood · Pustaka   : Daftar Sensor (manifest) -> lampiran 4
--    1 Karang Garam · Pustaka: cerita               9 Bjorneo · Pustaka   : cerita
--    2 Karang Garam (malam)  : cerita -> lampiran 1 10 Bjorneo · Pustaka   : barter 2 Rotan dari palka
--    3 FreeYork · Pustaka    : cerita -> lampiran 2 11 Joungjava · Pustaka : cerita
--    4 Otoland · Pustaka     : cerita              12 Sunda · Pustaka     : cerita
--    5 Gading · Pustaka      : cerita              13 Sunda (malam)       : Urut Cap (l13)
--    6 Gading (malam)        : Tinta Pudar -> lamp. 3   14 Sunda (malam)   : balasan surat -> 15 tamat (satu transaksi)
--    7 IKN · Pustaka         : Urut Cap (l7)
-- Aksi:
--   api_surat(['status'])
--   api_surat(['level', step])           definisi level Urut Cap / Daftar Sensor langkah itu
--   api_surat(['maju', step, hasil])     hasil: Urut Cap [id cap, tua -> muda] / Daftar Sensor [id surat] / 'ok'
--   api_surat(['jawab', 14, 'A'|'B'])    balasan surat -> varian perk (Lanjut / Matang, lihat sp_varian)
--   api_surat(['bisikan'])               Merchant: barang "Dicari!" siklus berikutnya di kota ini (Harian)
--   api_surat(['kenalan', komoditas])    Smuggler: 2 unit premium saat stok habis, dari kiriman berikutnya (Harian)
--   api_surat(['takut', true|false])     Pirate: nyalakan/matikan "Nama yang Ditakuti"
--
-- POLA PERK (sama untuk semua archetype): Pasif (selalu aktif) + Harian (1x per hari game, tidak bisa ditabung).
--   Varian Lanjut = Harian 2x. Varian Matang = Pasif tingkat 2. Semua angka = kenop game.config (Perk*).
--   Tidak menyentuh harga, untung per transaksi, jarahan gold, PvP, Pacu, bos/pemburu quest, event GM, Tony.
-- Kait (pola bungkus, nama asli -> *_perk):
--   voy_roll_encounter (Navigator Matang, Pirate Nama yang Ditakuti) · voy_complete_arrival (pesan lewat, Tambal di Laut)
--   voy_decay_for_voyage (Adventurer) · api_setSail (Jalur Pintas, Catatan Pasar) · api_resolveCombat (suap, Gertak, Rampas)
--   treasure_drop (Explorer) · fish_quest_weight + api_mgFishCast + api_mgFishReel (Firasat Karam)
--   api_mgDice + api_harian + harian_state (Gambler) · api_warehouseStore + mkt_lock + mkt_refresh (Smuggler)
--   mission_tiers + mission_board + api_completeMission (Diplomat) · api_getMarket (Merchant)
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('SuratOpen', '0'),
  ('PerkNavPasif1', '0.9'), ('PerkNavPasif2', '0.85'), ('PerkNavHarian', '0.7'),
  ('PerkPirLevel1', '2'), ('PerkPirLevel2', '3'), ('PerkPirSuap1', '0.75'), ('PerkPirSuap2', '0.6'),
  ('PerkPirRampasMin', '5'), ('PerkPirRampasMax', '10'),
  ('PerkExpPeta1', '1.5'), ('PerkExpKaram2', '1.5'),
  ('PerkGamTukar1', '1'), ('PerkGamTukar2', '2'),
  ('PerkSmuGudang1', '200'), ('PerkSmuGudang2', '400'), ('PerkSmuUpah', '15'), ('PerkSmuQty', '2'), ('PerkSmuBatasPulau', '6'),
  ('PerkDipTawar1', '1'), ('PerkDipTawar2', '2'), ('PerkDipStanding', '1'),
  ('PerkAdvAus1', '0.2'), ('PerkAdvAus2', '0.35'), ('PerkAdvTambal', '0.2')
on conflict (key) do nothing;
-- daftar side quest (aturan satu per satu, 0064)
insert into game.config(key, value) values ('SideQuestIds', 'peregrin,duneks,jtq,surat')
on conflict (key) do update set value = case
  when string_to_array(replace(game.config.value, ' ', ''), ',') @> array['surat'] then game.config.value
  else nullif(btrim(game.config.value, ', '), '') || ',surat' end;
update game.config set value = 'peregrin,duneks,jtq,surat' where key = 'SideQuestIds' and coalesce(value, '') = '';

-- pemakaian Harian per pemain per hari (hari game; 'tukar' memakai hari Pesanan Harian)
create table if not exists game.perk_harian (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  hari      int not null,
  kunci     text not null,
  n         int not null default 0,
  primary key (player_id, hari, kunci)
);
alter table game.perk_harian enable row level security;

-- Kenalan Lama (Smuggler): unit premium yang dipinjam dari kiriman siklus berikutnya
create table if not exists game.perk_pinjam (
  city_id      text not null,
  commodity_id text not null,
  cyc          bigint not null,   -- siklus pasar saat pinjaman dipotong dari stok
  qty          int not null default 0,
  primary key (city_id, commodity_id, cyc)
);
alter table game.perk_pinjam enable row level security;

-- ---------------------------------------------------------------------
-- Data langkah & level
-- p = panel (library). t = 'malam'. g = mini game. lv = kunci level. lamp = lampiran yang didapat.
-- ---------------------------------------------------------------------
create or replace function game.sp_steps() returns jsonb
language sql immutable as $$
  select '[
    {"c":"sowtour","g":"cap","lv":"l0"},
    {"c":"karang_garam"},
    {"c":"karang_garam","t":"malam","lamp":"kain"},
    {"c":"freeyork","lamp":"papan"},
    {"c":"otoland"},
    {"c":"gading_island"},
    {"c":"gading_island","t":"malam","g":"tinta","lamp":"tanah"},
    {"c":"ikn","g":"cap","lv":"l7"},
    {"c":"toogood","g":"manifest","lv":"sensor","lamp":"gambar"},
    {"c":"bjorneo"},
    {"c":"bjorneo","barter":"rotan","qty":2},
    {"c":"joungjava"},
    {"c":"sunda_empire"},
    {"c":"sunda_empire","t":"malam","g":"cap","lv":"l13"},
    {"c":"sunda_empire","t":"malam","jawab":true}
  ]'::jsonb
$$;
create or replace function game.sp_last() returns int language sql immutable as $$ select 15 $$;

-- Level. cap: stempel {id,label,shape,col,x,y,r,z,ink,day}; z = urutan cap (0 = tertua). Stempel berurutan
-- selalu bertumpang, jadi urutannya pasti satu (dibuktikan test/surat-solver.js).
-- manifest (Daftar Sensor): sama dengan dn_check_manifest (0065).
create or replace function game.sp_levels() returns jsonb
language sql immutable as $LV$ select '{"l0":{"mode":"cap","w":400,"h":250,"stamps":[{"id":"kg","label":"PENCATAT PASANG","shape":"jangkar","col":"#1a4a5a","x":49,"y":134,"r":32,"z":4,"ink":0.89,"day":null},{"id":"fy","label":"RUMAH UKIR FREEYORK","shape":"rantai","col":"#2a2a2a","x":76,"y":113,"r":31,"z":3,"ink":0.78,"day":null},{"id":"oto","label":"JURU TULIS OTOLAND","shape":"bulat","col":"#2a5a6a","x":106,"y":90,"r":28,"z":2,"ink":0.67,"day":null},{"id":"gading","label":"TOKO OBAT GADING","shape":"lampion","col":"#a02a1a","x":128,"y":61,"r":28,"z":1,"ink":0.56,"day":null},{"id":"ikn","label":"ARSIP NUSANTARA","shape":"garuda","col":"#5a4a1a","x":137,"y":103,"r":29,"z":0,"ink":0.45,"day":null},{"id":"sow","label":"ARSIP SUARA SOWTOUR","shape":"segi8","col":"#4a3a6a","x":84,"y":141,"r":32,"z":5,"ink":1,"day":null}]},"l7":{"mode":"cap","w":400,"h":250,"stamps":[{"id":"oto","label":"JURU TULIS OTOLAND","shape":"bulat","col":"#2a5a6a","x":353,"y":46,"r":30,"z":7,"ink":0.93,"day":null},{"id":"gading","label":"TOKO OBAT GADING","shape":"lampion","col":"#a02a1a","x":312,"y":58,"r":33,"z":6,"ink":0.86,"day":null},{"id":"toog","label":"PERPUSTAKAAN RAKYAT","shape":"segi8","col":"#3a2a3a","x":242,"y":64,"r":30,"z":3,"ink":0.66,"day":null},{"id":"sunda","label":"PUSTAKA SUNDA","shape":"bulat","col":"#7a2a1a","x":315,"y":151,"r":29,"z":0,"ink":0.45,"day":null},{"id":"mati","label":"MATI","shape":"kotak","col":"#9a1a14","x":270,"y":49,"r":24,"z":5,"ink":0.79,"day":null},{"id":"bjor","label":"RUMAH ARSIP BJORNEO","shape":"bulat","col":"#2a4a1a","x":264,"y":87,"r":33,"z":2,"ink":0.59,"day":null},{"id":"joung","label":"PERPUSTAKAAN RESIDEN","shape":"segi8","col":"#1e3a6a","x":306,"y":116,"r":32,"z":1,"ink":0.52,"day":null},{"id":"fy","label":"RUMAH UKIR FREEYORK","shape":"rantai","col":"#2a2a2a","x":328,"y":81,"r":28,"z":8,"ink":1,"day":null},{"id":"ikn","label":"ARSIP NUSANTARA","shape":"garuda","col":"#5a4a1a","x":242,"y":34,"r":28,"z":4,"ink":0.73,"day":null}]},"l13":{"mode":"cap","w":400,"h":250,"stamps":[{"id":"sow","label":"ARSIP SUARA SOWTOUR","shape":"segi8","col":"#4a3a6a","x":163,"y":213,"r":29,"z":11,"ink":1,"day":null},{"id":"gading","label":"TOKO OBAT GADING","shape":"lampion","col":"#a02a1a","x":180,"y":137,"r":30,"z":7,"ink":0.8,"day":23},{"id":"sunda","label":"PUSTAKA SUNDA","shape":"bulat","col":"#7a2a1a","x":101,"y":151,"r":28,"z":1,"ink":0.5,"day":1},{"id":"ikn","label":"ARSIP NUSANTARA","shape":"garuda","col":"#5a4a1a","x":135,"y":192,"r":31,"z":5,"ink":0.7,"day":null},{"id":"oto","label":"JURU TULIS OTOLAND","shape":"bulat","col":"#2a5a6a","x":211,"y":167,"r":30,"z":8,"ink":0.85,"day":null},{"id":"toog","label":"PERPUSTAKAAN RAKYAT","shape":"segi8","col":"#3a2a3a","x":86,"y":194,"r":33,"z":4,"ink":0.65,"day":null},{"id":"jempol","label":"","shape":"jempol","col":"#6a3a2a","x":131,"y":131,"r":22,"z":0,"ink":0.45,"day":null},{"id":"fy","label":"RUMAH UKIR FREEYORK","shape":"rantai","col":"#2a2a2a","x":202,"y":199,"r":29,"z":9,"ink":0.9,"day":null},{"id":"mati","label":"MATI","shape":"kotak","col":"#9a1a14","x":146,"y":163,"r":24,"z":6,"ink":0.75,"day":null},{"id":"bjor","label":"RUMAH ARSIP BJORNEO","shape":"bulat","col":"#2a4a1a","x":61,"y":158,"r":30,"z":3,"ink":0.6,"day":9},{"id":"kg","label":"PENCATAT PASANG","shape":"jangkar","col":"#1a4a5a","x":172,"y":184,"r":29,"z":10,"ink":0.95,"day":31},{"id":"joung","label":"PERPUSTAKAAN RESIDEN","shape":"segi8","col":"#1e3a6a","x":67,"y":125,"r":32,"z":2,"ink":0.55,"day":null}]},"sensor":{"mode":"manifest","theme":"sensor","numerals":true,"rows":[{"id":"r1","label":"Surat ke Skitraw, pengirim nelayan","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"r2","label":"Surat ke Bjorneo, pengirim tukang dok","qty":1,"cap":"benteng","berat":"2 lembar"},{"id":"r3","label":"Surat ke Joungjava, pengirim janda","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"r4","label":"Surat ke Sunda, pengirim kuli","qty":1,"cap":"benteng","berat":"3 lembar"},{"id":"r5","label":"Surat ke IKN, pengirim anak","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"r6","label":"Surat ke TooGood, pengirim tak bernama","qty":1,"cap":"benteng","berat":"2 lembar"},{"id":"r7","label":"Surat ke Paradiso, pengirim penari","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"r8","label":"Surat ke Skitraw, pengirim juru masak","qty":1,"cap":"benteng","berat":"2 lembar"},{"id":"r9","label":"Surat ke kapten, pengirim tak bernama","qty":1,"cap":"pustaka","berat":"1 lembar"},{"id":"r10","label":"Surat ke Bjorneo, pengirim pemanjat walet","qty":1,"cap":"benteng","berat":"1 lembar"}],"crates":[{"id":"s4","row":"r4","label":"Surat ke Sunda, pengirim kuli","qty":1,"cap":"benteng","berat":"3 lembar"},{"id":"s9","row":"r9","label":"Surat ke kapten, pengirim tak bernama","qty":2,"cap":"pustaka","berat":"1 lembar","jt":true,"note":"isi: gambar kapal. tidak berbahaya. penulis: penakut."},{"id":"s1","row":"r1","label":"Surat ke Skitraw, pengirim nelayan","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"s7","row":"r7","label":"Surat ke Paradiso, pengirim penari","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"s2","row":"r2","label":"Surat ke Bjorneo, pengirim tukang dok","qty":1,"cap":"pustaka","berat":"2 lembar","jt":true,"note":"ditahan dua musim, lalu dilepas"},{"id":"s10","row":"r10","label":"Surat ke Bjorneo, pengirim pemanjat walet","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"s5","row":"r5","label":"Surat ke IKN, pengirim anak","qty":1,"cap":"benteng","berat":"2 lembar","jt":true,"note":"lembar kedua: gambar burung perunggu"},{"id":"s3","row":"r3","label":"Surat ke Joungjava, pengirim janda","qty":1,"cap":"benteng","berat":"1 lembar"},{"id":"s8","row":"r8","label":"Surat ke Skitraw, pengirim juru masak","qty":1,"cap":"benteng","berat":"2 lembar"},{"id":"s6","row":"r6","label":"Surat ke TooGood, pengirim tak bernama","qty":1,"cap":"benteng","berat":"2 lembar"}]}}'::jsonb $LV$;

create or replace function game.sp_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'surat'), 0) $$;

-- Saga 2 selesai, gerbang SuratOpen, dan (sudah pernah dimulai, atau tidak ada side quest lain yang sedang berjalan)
create or replace function game.sp_eligible(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if p_pid is null or game.dt_step(p_pid) < 5 then return false; end if;
  if not game.fitur_on(p_pid, 'SuratOpen') then return false; end if;
  if exists (select 1 from game.player_quests where player_id = p_pid and quest_id = 'surat') then return true; end if;
  return game.side_quest_active(p_pid, 'surat') is null;
exception when others then return false;
end $$;

-- Dibekukan selama Saga 3 aktif (aturan sama dengan TheDuneks & Rekening J.T.)
create or replace function game.sp_frozen(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if not game.pasir_aktif(p_pid) then return false; end if;
  if game.ps_step(p_pid, 'ps14') >= 6 then return false; end if;
  if game.is_gm(p_pid) and not exists (select 1 from game.pasir_state where player_id = p_pid) then return false; end if;
  return true;
exception when others then return false;
end $$;

-- Archetype yang dipakai perk (kosong / tidak dikenal = adventurer)
create or replace function game.sp_arch(p_pid uuid) returns text
language sql stable as $$
  select case when a in ('merchant','navigator','pirate','explorer','gambler','smuggler','diplomat','adventurer') then a else 'adventurer' end
    from (select lower(coalesce((select archetype from game.players where player_id = p_pid), '')) a) x
$$;

-- Balasan surat -> varian. Balasan "masih / belum" = Lanjut (Harian 2x); "sudah" = Matang (Pasif tingkat 2).
-- Pirate satu-satunya yang tertukar: A = "Aku sudah berubah" (Matang), B = "Aku masih sama" (Lanjut).
create or replace function game.sp_varian(p_arch text, p_jawab text) returns text
language sql immutable as $$
  select case when p_arch = 'pirate' then case when p_jawab = 'A' then 'matang' else 'lanjut' end
              else case when p_jawab = 'A' then 'lanjut' else 'matang' end end
$$;

-- ---------------------------------------------------------------------
-- Perk: dasar
-- ---------------------------------------------------------------------
-- null = perk belum bangun / sedang tidur. {arch, varian, tingkat (Pasif 1|2), harian (1|2)}
create or replace function game.perk(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare d jsonb; v text; a text;
begin
  if p_pid is null then return null; end if;
  select data into d from game.player_quests where player_id = p_pid and quest_id = 'surat' and done_at is not null;
  if not found then return null; end if;
  if not game.fitur_on(p_pid, 'SuratOpen') or game.sp_frozen(p_pid) then return null; end if;
  a := game.sp_arch(p_pid);
  v := case when d ->> 'jawab' in ('A', 'B') then game.sp_varian(a, d ->> 'jawab') else coalesce(d ->> 'varian', 'lanjut') end;
  return jsonb_build_object('arch', a, 'varian', v, 'tingkat', case when v = 'matang' then 2 else 1 end,
    'harian', case when v = 'lanjut' then 2 else 1 end, 'takutOff', coalesce((d ->> 'takutOff')::boolean, false));
exception when others then return null;
end $$;

create or replace function game.perk_is(p_pid uuid, p_arch text) returns boolean
language sql stable as $$ select coalesce(game.perk(p_pid) ->> 'arch' = p_arch, false) $$;

-- hari Harian: hari game; 'tukar' memakai hari Pesanan Harian (reset 00:00 WIB)
create or replace function game.perk_hari(p_kunci text) returns int
language sql stable as $$
  select case when p_kunci = 'tukar' then (game.hr_today() - date '2000-01-01') else game.game_day() end
$$;

create or replace function game.perk_harian_max(p_pid uuid, p_kunci text) returns int
language plpgsql stable as $$
declare pk jsonb := game.perk(p_pid);
begin
  if pk is null then return 0; end if;
  if p_kunci = 'tukar' then
    return case when (pk ->> 'tingkat')::int >= 2 then game.cfg_num('PerkGamTukar2', 2) else game.cfg_num('PerkGamTukar1', 1) end::int;
  end if;
  return (pk ->> 'harian')::int;
end $$;

create or replace function game.perk_harian_left(p_pid uuid, p_kunci text) returns int
language sql stable as $$
  select greatest(0, game.perk_harian_max(p_pid, p_kunci) - coalesce((select n from game.perk_harian
    where player_id = p_pid and hari = game.perk_hari(p_kunci) and kunci = p_kunci), 0))
$$;

-- pakai satu jatah Harian (aman dua perangkat: baris dikunci lewat upsert bersyarat). true = berhasil.
create or replace function game.perk_harian_pakai(p_pid uuid, p_kunci text) returns boolean
language plpgsql as $$
declare v_max int := game.perk_harian_max(p_pid, p_kunci); v_h int := game.perk_hari(p_kunci); v_n int;
begin
  if v_max <= 0 then return false; end if;
  insert into game.perk_harian as x (player_id, hari, kunci, n) values (p_pid, v_h, p_kunci, 1)
  on conflict (player_id, hari, kunci) do update set n = x.n + 1 where x.n < v_max
  returning n into v_n;
  return v_n is not null;
end $$;

-- ---------------------------------------------------------------------
-- Status (kunci 'surat' di api_getGameState). null = belum terbuka. Tidak memuat angka atau hadiah.
-- 'perk' hanya ada setelah tamat.
-- ---------------------------------------------------------------------
create or replace function game.sp_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_step int; r jsonb; d jsonb; pk jsonb; v_k text;
begin
  if p_pid is null or not game.sp_eligible(p_pid) then return null; end if;
  v_step := game.sp_step(p_pid);
  select data into d from game.player_quests where player_id = p_pid and quest_id = 'surat';
  r := jsonb_build_object('step', v_step, 'done', v_step >= game.sp_last(), 'frozen', game.sp_frozen(p_pid),
    'lampiran', coalesce(d -> 'lampiran', '[]'::jsonb));
  if v_step >= game.sp_last() then
    pk := game.perk(p_pid);
    v_k := case pk ->> 'arch' when 'merchant' then 'mer' when 'navigator' then 'nav' when 'pirate' then 'pir' when 'explorer' then 'exp'
      when 'gambler' then 'gam' when 'smuggler' then 'smu' when 'diplomat' then 'dip' else 'adv' end;
    r := r || jsonb_build_object('arch', coalesce(d ->> 'arch', game.sp_arch(p_pid)), 'jawab', d ->> 'jawab',
      'perk', case when pk is null then null else pk || jsonb_build_object('kunci', v_k,
        'harianLeft', game.perk_harian_left(p_pid, v_k),
        'tukarLeft', case when pk ->> 'arch' = 'gambler' then game.perk_harian_left(p_pid, 'tukar') end,
        'nilai', game.perk_nilai(pk)) end);
  end if;
  return r;
exception when others then
  raise warning '[surat] state: %', sqlerrm;
  return null;
end $$;

-- angka yang tampil di kartu perk (milik pemain sendiri, setelah tamat)
create or replace function game.perk_nilai(pk jsonb) returns jsonb
language plpgsql stable as $$
declare t int := coalesce((pk ->> 'tingkat')::int, 1);
begin
  return case pk ->> 'arch'
    when 'navigator' then jsonb_build_object('cegat', round((1 - game.cfg_num(case when t >= 2 then 'PerkNavPasif2' else 'PerkNavPasif1' end, 0.9)) * 100),
      'pintas', round((1 - game.cfg_num('PerkNavHarian', 0.7)) * 100))
    when 'pirate' then jsonb_build_object('level', game.cfg_num(case when t >= 2 then 'PerkPirLevel2' else 'PerkPirLevel1' end, 2)::int,
      'suap', round((1 - game.cfg_num(case when t >= 2 then 'PerkPirSuap2' else 'PerkPirSuap1' end, 0.75)) * 100),
      'rampasMin', game.cfg_num('PerkPirRampasMin', 5)::int, 'rampasMax', game.cfg_num('PerkPirRampasMax', 10)::int)
    when 'explorer' then jsonb_build_object('peta', round((game.cfg_num('PerkExpPeta1', 1.5) - 1) * 100),
      'karam', case when t >= 2 then game.cfg_num('PerkExpKaram2', 1.5) end)
    when 'gambler' then jsonb_build_object('tukar', game.cfg_num(case when t >= 2 then 'PerkGamTukar2' else 'PerkGamTukar1' end, 1)::int)
    when 'smuggler' then jsonb_build_object('gudang', game.cfg_num(case when t >= 2 then 'PerkSmuGudang2' else 'PerkSmuGudang1' end, 200)::int,
      'upah', game.cfg_num('PerkSmuUpah', 15)::int, 'qty', game.cfg_num('PerkSmuQty', 2)::int)
    when 'diplomat' then jsonb_build_object('tawar', game.cfg_num(case when t >= 2 then 'PerkDipTawar2' else 'PerkDipTawar1' end, 1)::int,
      'standing', game.cfg_num('PerkDipStanding', 1)::int)
    when 'adventurer' then jsonb_build_object('aus', round(game.cfg_num(case when t >= 2 then 'PerkAdvAus2' else 'PerkAdvAus1' end, 0.2) * 100),
      'tambal', round(game.cfg_num('PerkAdvTambal', 0.2) * 100))
    else jsonb_build_object('catatan', t >= 2) end;
end $$;

-- ---------------------------------------------------------------------
-- Pemeriksa Urut Cap (server = penentu). null = benar, atau alasan singkat.
-- p_res = [id cap, dari yang tertua ke yang terbaru]
-- ---------------------------------------------------------------------
create or replace function game.sp_check_cap(p_lv jsonb, p_res jsonb) returns text
language plpgsql immutable as $$
declare v_want text[]; v_got text[];
begin
  if p_res is null or jsonb_typeof(p_res) <> 'array' then return 'Urutkan semua capnya dulu.'; end if;
  select array_agg(s ->> 'id' order by (s ->> 'z')::int) into v_want from jsonb_array_elements(p_lv -> 'stamps') s;
  select coalesce(array_agg(x order by o), '{}') into v_got from jsonb_array_elements_text(p_res) with ordinality t(x, o);
  if cardinality(v_got) <> cardinality(v_want) then return 'Urutkan semua capnya dulu.'; end if;
  if v_got is distinct from v_want then return 'Urutannya belum benar.'; end if;
  return null;
exception when others then return 'Urutannya tidak terbaca.';
end $$;

-- ---------------------------------------------------------------------
-- Aksi
-- ---------------------------------------------------------------------
create or replace function public.api_surat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res jsonb := case when jsonb_typeof(a) = 'array' then a -> 2 end;
  v_step int; d jsonb; v_err text; v_have int; v_lamp jsonb; v_jw text; v_arch text; pk jsonb;
  v_city text; v_comm text; c game.commodities; v_role text; s numeric; mu record; v_qty int; v_total bigint;
  v_cyc bigint; v_used int; v_tags jsonb; v_nm text; v_on boolean;
begin
  if v_act = 'status' then return jsonb_build_object('surat', game.sp_state(v_pid)); end if;

  -- ------------------------------------------------------------- aksi perk (setelah tamat)
  if v_act in ('bisikan', 'kenalan', 'takut') then
    pk := game.perk(v_pid);
    if pk is null then raise exception 'Aksi tidak dikenal.'; end if;
    if v_act = 'takut' then
      if pk ->> 'arch' <> 'pirate' then raise exception 'Aksi tidak dikenal.'; end if;
      v_on := lower(coalesce(game.arg(a, 1), 'true')) in ('true', '1', 'on');
      update game.player_quests set data = data || jsonb_build_object('takutOff', not v_on), updated_at = now()
       where player_id = v_pid and quest_id = 'surat';
      return jsonb_build_object('surat', game.sp_state(v_pid));
    end if;
    if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
    v_city := game.current_city(v_pid);
    if game.spot_city(v_city) then raise exception 'Tak ada siapa pun di sini, Kapten.'; end if;

    if v_act = 'bisikan' then
      if pk ->> 'arch' <> 'merchant' then raise exception 'Aksi tidak dikenal.'; end if;
      if not game.perk_harian_pakai(v_pid, 'mer') then raise exception 'Saudagar-saudagar sudah tutup mulut hari ini, Kapten. Besok lagi.'; end if;
      v_tags := game.mkt_cycle_tags(v_city, game.mkt_cycle_index() + 1);
      v_comm := v_tags -> 'wanted' ->> 0;
      return jsonb_build_object('surat', game.sp_state(v_pid), 'bisikan', jsonb_build_object(
        'city', v_city, 'cityName', game.city_name(v_city), 'commodityId', v_comm, 'name', game.commodity_name(v_comm),
        'inMs', game.mkt_cycle_ends_ms()));
    end if;

    -- kenalan (Smuggler)
    if pk ->> 'arch' <> 'smuggler' then raise exception 'Aksi tidak dikenal.'; end if;
    v_comm := game.arg(a, 1);
    perform game.eco_require_trade_here(v_pid, v_city);
    select * into c from game.commodities where id = v_comm and active;
    if not found or c.tier <> 'premium' then raise exception 'Kenalan lama hanya mengurus barang langka, Kapten.'; end if;
    select role into v_role from game.market where city_id = v_city and commodity_id = v_comm;
    if v_role is distinct from 'produce' then raise exception 'Barang itu tidak dibuat di pulau ini, Kapten.'; end if;
    s := game.mkt_lock(v_city, v_comm);
    if s is null then raise exception 'Barang itu tidak dibuat di pulau ini, Kapten.'; end if;
    if floor(s) > 0 then raise exception 'Masih ada di pasar, Kapten. Beli saja di sana.'; end if;
    v_cyc := game.mkt_cycle_index() + 1;
    v_qty := greatest(1, game.cfg_num('PerkSmuQty', 2)::int);
    select coalesce(sum(qty), 0) into v_used from game.perk_pinjam where city_id = v_city and commodity_id = v_comm and cyc = v_cyc;
    if v_used + v_qty > game.cfg_num('PerkSmuBatasPulau', 6) then raise exception 'Kiriman berikutnya sudah habis dipesan orang, Kapten.'; end if;
    if game.perk_harian_left(v_pid, 'smu') <= 0 then raise exception 'Kenalan lamamu sudah tidur, Kapten. Besok lagi.'; end if;
    select * into mu from game.eco2_muls(v_pid, v_city, v_comm);
    -- harga sekarang (stok 0, tidak bergeser) + upah kenalan
    v_total := ceil(v_qty * greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast, game.mkt_lotx(0, c.tier), v_role, c.tier) * mu.buy_mul))
      * (1 + game.cfg_num('PerkSmuUpah', 15) / 100))::bigint;
    if v_me.gold < v_total then raise exception 'Gold tidak cukup. Butuh %, kamu punya %.', v_total, v_me.gold; end if;
    if v_qty * c.size > game.cargo_free(v_pid) then raise exception 'Kapasitas cargo tidak cukup.'; end if;
    perform game.perk_harian_pakai(v_pid, 'smu');
    update game.players set gold = gold - v_total where player_id = v_pid;
    perform game.adjust_inventory(v_pid, v_comm, v_qty);
    perform game.inv_add_cost(v_pid, v_comm, v_qty, v_total);
    update game.inventory set src_city = v_city where player_id = v_pid and item_id = v_comm;
    insert into game.perk_pinjam as x (city_id, commodity_id, cyc, qty) values (v_city, v_comm, v_cyc, v_qty)
    on conflict (city_id, commodity_id, cyc) do update set qty = x.qty + excluded.qty;
    perform game.hr_hook(v_pid, 'buy', v_total, jsonb_build_object('city', v_city, 'comm', v_comm, 'qty', v_qty, 'role', v_role));
    return jsonb_build_object('surat', game.sp_state(v_pid), 'kenalan', jsonb_build_object('commodityId', v_comm, 'name', c.name, 'qty', v_qty, 'total', v_total),
      'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  -- ------------------------------------------------------------- langkah quest
  if v_act not in ('level', 'maju', 'jawab') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.sp_eligible(v_pid) or game.sp_frozen(v_pid) then raise exception 'Pustaka sedang sepi, Kapten.'; end if;

  if v_act = 'level' then
    v_step := game.sp_step(v_pid);
    if v_want is distinct from v_step or v_step >= game.sp_last() then raise exception 'Pustaka sedang sepi, Kapten.'; end if;
    d := game.sp_steps() -> v_step;
    if not (d ? 'lv') then raise exception 'Pustaka sedang sepi, Kapten.'; end if;
    return jsonb_build_object('level', game.sp_levels() -> (d ->> 'lv'));
  end if;

  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'surat', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step, data into v_step, v_lamp from game.player_quests where player_id = v_pid and quest_id = 'surat' for update;
  v_lamp := coalesce(v_lamp -> 'lampiran', '[]'::jsonb);
  if v_step >= game.sp_last() then raise exception 'Pustaka sedang sepi, Kapten.'; end if;
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.sp_steps() -> v_step;
  if game.current_city(v_pid) is distinct from (d ->> 'c') then raise exception 'Pustaka sedang sepi, Kapten.'; end if;
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;

  if v_act = 'maju' then
    if coalesce((d ->> 'jawab')::boolean, false) then raise exception 'Surat itu menunggu balasanmu, Kapten.'; end if;
    if d ->> 'g' = 'cap' then
      v_err := game.sp_check_cap(game.sp_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum benar, Kapten. %', v_err; end if;
    elsif d ->> 'g' = 'manifest' then
      v_err := game.dn_check_manifest(game.sp_levels() -> (d ->> 'lv'), v_res);
      if v_err is not null then raise exception 'Belum cocok, Kapten. Masih ada surat yang belum cocok dengan buku sitaan.'; end if;
    elsif d ? 'g' and coalesce(v_res #>> '{}', '') <> 'ok' then
      raise exception 'Belum terbaca, Kapten. Coba lagi.';
    end if;
    if d ? 'barter' then
      select coalesce(qty, 0) into v_have from game.inventory where player_id = v_pid and item_id = d ->> 'barter';
      if coalesce(v_have, 0) < (d ->> 'qty')::int then
        raise exception 'Bawa % batang % di palka, Kapten. Yang di gudang tidak bisa diikatkan.', d ->> 'qty', game.commodity_name(d ->> 'barter');
      end if;
      perform game.adjust_inventory(v_pid, d ->> 'barter', -((d ->> 'qty')::int));
    end if;
    if d ? 'lamp' and not (v_lamp ? (d ->> 'lamp')) then v_lamp := v_lamp || to_jsonb(d ->> 'lamp'); end if;
    update game.player_quests set step = v_step + 1, updated_at = now(),
      data = data || jsonb_build_object('lampiran', v_lamp, 's' || v_step, game.now_ms())
     where player_id = v_pid and quest_id = 'surat';
    return jsonb_build_object('surat', game.sp_state(v_pid));
  end if;

  -- ------------------------------------------------------------- jawab (langkah terakhir, satu transaksi)
  if not coalesce((d ->> 'jawab')::boolean, false) then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;
  v_jw := upper(btrim(coalesce(v_res #>> '{}', '')));
  if v_jw not in ('A', 'B') then raise exception 'Surat itu menunggu balasanmu, Kapten.'; end if;
  v_arch := game.sp_arch(v_pid);
  update game.player_quests set step = game.sp_last(), updated_at = now(), done_at = now(),
    data = data || jsonb_build_object('s' || v_step, game.now_ms(), 'jawab', v_jw, 'arch', v_arch,
      'varian', game.sp_varian(v_arch, v_jw))
   where player_id = v_pid and quest_id = 'surat';
  select count(*) into v_have from game.player_quests pq where pq.quest_id = 'surat' and pq.done_at is not null
     and not game.is_gm(pq.player_id);
  return jsonb_build_object('surat', game.sp_state(v_pid), 'rak', v_have);
end $$;
select game.expose('api_surat');

-- ---------------------------------------------------------------------
-- Alat uji GM (SQL Editor): select game.admin_surat('abuy', 13);  select game.admin_surat('abuy', 15, 'B');
-- Menyetel langkah (0..15). Langkah 15 = tamat dengan balasan p_jawab (bawaan A).
-- ---------------------------------------------------------------------
create or replace function game.admin_surat(p_username text, p_step int, p_jawab text default 'A') returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; s int; v_arch text; v_l jsonb := '[]'::jsonb; i int; d jsonb;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  s := greatest(0, least(game.sp_last(), coalesce(p_step, 0)));
  for i in 0 .. s - 1 loop
    d := game.sp_steps() -> i;
    if d ? 'lamp' then v_l := v_l || to_jsonb(d ->> 'lamp'); end if;
  end loop;
  v_arch := game.sp_arch(v_pid);
  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'surat', s, '{}'::jsonb)
  on conflict (player_id, quest_id) do update set step = s, updated_at = now(), done_at = null,
    data = game.player_quests.data - 'jawab' - 'varian' - 'arch';
  update game.player_quests set data = data || jsonb_build_object('lampiran', v_l),
    done_at = case when s >= game.sp_last() then now() end
   where player_id = v_pid and quest_id = 'surat';
  if s >= game.sp_last() then
    update game.player_quests set data = data || jsonb_build_object('jawab', upper(coalesce(p_jawab, 'A')), 'arch', v_arch,
      'varian', game.sp_varian(v_arch, upper(coalesce(p_jawab, 'A'))))
     where player_id = v_pid and quest_id = 'surat';
  end if;
  return game.sp_state(v_pid);
end $$;
revoke all on function game.admin_surat(text, int, text) from public;

-- GM: kosongkan jatah Harian perk hari ini (uji)
create or replace function game.admin_perk_reset(p_username text) returns int
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid; n int;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then raise exception 'Pemain % tidak ditemukan.', p_username; end if;
  delete from game.perk_harian where player_id = v_pid; get diagnostics n = row_count;
  return n;
end $$;
revoke all on function game.admin_perk_reset(text) from public;

-- =====================================================================
-- KAIT PERK (pola bungkus: fungsi asli -> *_perk, pembungkus memakai nama asli)
-- Semua migrasi diulang berurutan tiap deploy, jadi pembungkus ini selalu membungkus versi terbaru.
-- =====================================================================
do $$
begin
  drop function if exists game.voy_roll_encounter_perk(uuid, text);
  alter function game.voy_roll_encounter(uuid, text) rename to voy_roll_encounter_perk;
  drop function if exists game.voy_complete_arrival_perk(uuid, text, text);
  alter function game.voy_complete_arrival(uuid, text, text) rename to voy_complete_arrival_perk;
  drop function if exists game.voy_decay_for_voyage_perk(uuid);
  alter function game.voy_decay_for_voyage(uuid) rename to voy_decay_for_voyage_perk;
  drop function if exists game.treasure_drop_perk(uuid, int);
  alter function game.treasure_drop(uuid, int) rename to treasure_drop_perk;
  drop function if exists game.fish_quest_weight_perk(uuid, text, text);
  alter function game.fish_quest_weight(uuid, text, text) rename to fish_quest_weight_perk;
  drop function if exists game.harian_state_perk(uuid);
  alter function game.harian_state(uuid) rename to harian_state_perk;
  drop function if exists game.mkt_lock_perk(text, text);
  alter function game.mkt_lock(text, text) rename to mkt_lock_perk;
  drop function if exists game.mkt_refresh_perk(text);
  alter function game.mkt_refresh(text) rename to mkt_refresh_perk;
  drop function if exists game.mission_tiers_perk(text);
  alter function game.mission_tiers(text) rename to mission_tiers_perk;
  drop function if exists game.mission_board_perk(uuid, text);
  alter function game.mission_board(uuid, text) rename to mission_board_perk;

  -- endpoint publik -> schema game (tidak bisa dipanggil klien langsung)
  drop function if exists game.api_setsail_perk(jsonb);
  alter function public.api_setsail(jsonb) rename to api_setsail_perk;
  alter function public.api_setsail_perk(jsonb) set schema game;
  drop function if exists game.api_resolvecombat_perk(jsonb);
  alter function public.api_resolvecombat(jsonb) rename to api_resolvecombat_perk;
  alter function public.api_resolvecombat_perk(jsonb) set schema game;
  drop function if exists game.api_mgfishcast_perk(jsonb);
  alter function public.api_mgfishcast(jsonb) rename to api_mgfishcast_perk;
  alter function public.api_mgfishcast_perk(jsonb) set schema game;
  drop function if exists game.api_mgfishreel_perk(jsonb);
  alter function public.api_mgfishreel(jsonb) rename to api_mgfishreel_perk;
  alter function public.api_mgfishreel_perk(jsonb) set schema game;
  drop function if exists game.api_mgdice_perk(jsonb);
  alter function public.api_mgdice(jsonb) rename to api_mgdice_perk;
  alter function public.api_mgdice_perk(jsonb) set schema game;
  drop function if exists game.api_harian_perk(jsonb);
  alter function public.api_harian(jsonb) rename to api_harian_perk;
  alter function public.api_harian_perk(jsonb) set schema game;
  drop function if exists game.api_warehousestore_perk(jsonb);
  alter function public.api_warehousestore(jsonb) rename to api_warehousestore_perk;
  alter function public.api_warehousestore_perk(jsonb) set schema game;
  drop function if exists game.api_completemission_perk(jsonb);
  alter function public.api_completemission(jsonb) rename to api_completemission_perk;
  alter function public.api_completemission_perk(jsonb) set schema game;
  drop function if exists game.api_getmarket_perk(jsonb);
  alter function public.api_getmarket(jsonb) rename to api_getmarket_perk;
  alter function public.api_getmarket_perk(jsonb) set schema game;
end $$;
revoke all on function game.api_setsail_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_resolvecombat_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_mgfishcast_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_mgfishreel_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_mgdice_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_harian_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_warehousestore_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_completemission_perk(jsonb) from public, anon, authenticated;
revoke all on function game.api_getmarket_perk(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Navigator (Matang: peluang dicegat 0.9 -> 0.85) · Pirate (Nama yang Ditakuti)
-- Hanya bajak laut acak (randomPirate). Bos quest, Tony, pemburu quest tidak tersentuh.
-- ---------------------------------------------------------------------
create or replace function game.voy_roll_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare e jsonb := game.voy_roll_encounter_perk(p_pid, p_dest); pk jsonb; v_lv int; v_max int;
begin
  if e is null or jsonb_typeof(e) <> 'object' or not coalesce((e ->> 'randomPirate')::boolean, false) then return e; end if;
  pk := game.perk(p_pid);
  if pk is null then return e; end if;
  if pk ->> 'arch' = 'navigator' and (pk ->> 'tingkat')::int >= 2 then
    -- inti sudah memakai x0.9 (PerkNavPasif1); Matang menurunkan lagi sampai PerkNavPasif2
    if random() >= game.cfg_num('PerkNavPasif2', 0.85) / greatest(0.01, game.cfg_num('PerkNavPasif1', 0.9)) then return null; end if;
  elsif pk ->> 'arch' = 'pirate' and not coalesce((pk ->> 'takutOff')::boolean, false) then
    v_lv := coalesce((e ->> 'enemyLevel')::int, 99);
    v_max := game.cfg_num(case when (pk ->> 'tingkat')::int >= 2 then 'PerkPirLevel2' else 'PerkPirLevel1' end, 2)::int;
    if v_lv <= v_max then
      perform set_config('mt.perk_lewat', coalesce(e ->> 'enemyName', 'kapal bajak laut'), true);
      return null;
    end if;
  end if;
  return e;
end $$;

-- Pesan "lewat sudah" + Adventurer: Tambal di Laut (Harian, saat tiba, kondisi kurang >= 10%)
create or replace function game.voy_complete_arrival(p_pid uuid, p_target text, p_combat_msg text) returns jsonb
language plpgsql as $$
declare v_l text := nullif(current_setting('mt.perk_lewat', true), ''); v_msg text := p_combat_msg; r jsonb; pk jsonb;
  mx numeric; cur numeric; v_note text;
begin
  if v_l is not null then
    perform set_config('mt.perk_lewat', '', true);
    if coalesce(p_combat_msg, '') = '' then
      v_msg := 'Layar ' || v_l || ' muncul di cakrawala, mendekat, lalu melambat. "...bendera itu. Lewat sudah, lewat sudah." Mereka berbelok menjauh.';
    end if;
  end if;
  r := game.voy_complete_arrival_perk(p_pid, p_target, v_msg);
  if v_l is not null then r := r || jsonb_build_object('perkNote', 'Intimidation: bajak laut kecil memilih berbelok.'); end if;
  pk := game.perk(p_pid);
  if pk is not null and pk ->> 'arch' = 'adventurer' then
    mx := game.voy_max_cond(p_pid);
    select condition into cur from game.ships where player_id = p_pid;
    if mx > 0 and coalesce(cur, mx) <= mx * 0.9 and game.perk_harian_pakai(p_pid, 'adv') then
      perform game.apply_condition_delta(p_pid, mx * game.cfg_num('PerkAdvTambal', 0.2));
      v_note := 'Bold Sailor: kau menambal sendiri di tengah jalan. +' || round(game.cfg_num('PerkAdvTambal', 0.2) * 100) || '% kondisi.';
      r := r || jsonb_build_object('perkNote', coalesce(r ->> 'perkNote' || ' ', '') || v_note);
    end if;
  end if;
  return r;
end $$;

-- Adventurer: aus lambung per pelayaran berkurang
create or replace function game.voy_decay_for_voyage(p_pid uuid) returns numeric
language plpgsql stable as $$
declare v numeric := game.voy_decay_for_voyage_perk(p_pid); pk jsonb;
begin
  pk := game.perk(p_pid);
  if pk is not null and pk ->> 'arch' = 'adventurer' then
    v := v * (1 - game.cfg_num(case when (pk ->> 'tingkat')::int >= 2 then 'PerkAdvAus2' else 'PerkAdvAus1' end, 0.2));
  end if;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- api_setSail: Merchant Matang (Catatan Pasar kota asal) · Navigator (Jalur Pintas, a[1] = 'pintas')
-- ---------------------------------------------------------------------
create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); pk jsonb; v_from text; v_snap jsonb; r jsonb; l game.player_location; secs numeric; v_new numeric;
  v_cat jsonb; v_pintas boolean := lower(coalesce(game.arg(a, 1), '')) = 'pintas';
begin
  pk := game.perk(v_pid);
  if pk is not null and pk ->> 'arch' = 'merchant' and (pk ->> 'tingkat')::int >= 2 and not game.in_transit(v_pid) then
    v_from := game.current_city(v_pid);
    begin
      select coalesce(jsonb_agg(jsonb_build_object('c', x ->> 'commodityId', 'b', (x ->> 'buyPrice')::int, 's', (x ->> 'sellPrice')::int)), '[]'::jsonb)
        into v_snap from jsonb_array_elements(game.api_getmarket_perk(jsonb_build_array(v_from)) -> 'items') x;
    exception when others then v_snap := null;
    end;
  end if;
  r := game.api_setsail_perk(jsonb_build_array(game.arg(a, 0)));
  if v_snap is not null and jsonb_array_length(v_snap) > 0 then
    select coalesce(data -> 'catatan', '[]'::jsonb) into v_cat from game.player_quests where player_id = v_pid and quest_id = 'surat';
    v_cat := jsonb_build_array(jsonb_build_object('city', v_from, 'at', game.now_ms(), 'items', v_snap))
      || coalesce((select jsonb_agg(x) from jsonb_array_elements(v_cat) x where x ->> 'city' <> v_from), '[]'::jsonb);
    if jsonb_array_length(v_cat) > 2 then v_cat := jsonb_build_array(v_cat -> 0, v_cat -> 1); end if;
    update game.player_quests set data = data || jsonb_build_object('catatan', v_cat) where player_id = v_pid and quest_id = 'surat';
  end if;
  if v_pintas and pk is not null and pk ->> 'arch' = 'navigator' then
    select * into l from game.player_location where player_id = v_pid for update;
    secs := extract(epoch from (l.arrive_at - l.depart_at));
    v_new := greatest(25, round(secs * game.cfg_num('PerkNavHarian', 0.7)));
    if l.arrive_at is not null and v_new < secs and game.perk_harian_pakai(v_pid, 'nav') then
      update game.player_location set arrive_at = depart_at + make_interval(secs => v_new::double precision) where player_id = v_pid;
      r := r || jsonb_build_object('arriveAt', game.iso(l.depart_at + make_interval(secs => v_new::double precision)),
        'travelSeconds', v_new::int, 'travelRealMinutes', round(v_new / 60.0, 2),
        'perkNote', 'Sea Reader: kau tahu arus yang tak tertulis di peta. -' || round((1 - game.cfg_num('PerkNavHarian', 0.7)) * 100) || '%.');
    end if;
  end if;
  return r;
end $$;
select game.expose('api_setsail');

-- ---------------------------------------------------------------------
-- api_resolveCombat: Pirate (suap lebih murah, Gertak, Rampas Muatan). Hanya bajak laut acak non-bos.
-- 'gertak' = pertempuran berakhir tanpa tempur & tanpa jarahan (Harian).
-- 'rampas' = tandai pertempuran; bila MENANG, ambil 1 jenis barang biasa dari palka musuh (Harian dipakai saat itu).
-- ---------------------------------------------------------------------
create or replace function public.api_resolveCombat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_t text := game.arg(a, 0); v_pid uuid := game.uid(); enc jsonb; pk jsonb := null; ok_pir boolean := false;
  v_lvl numeric; v_cost numeric; v_disc numeric; v_top bigint := 0; v_gold bigint; r jsonb; voyage jsonb; fin jsonb; v_msg text;
  v_comm text; v_size numeric; v_q int; v_note text; v_mul numeric;
begin
  select pending_encounter into enc from game.player_location where player_id = v_pid;
  if jsonb_typeof(enc) = 'object' and coalesce(enc ->> 'kind', '') <> 'tony' and coalesce((enc ->> 'randomPirate')::boolean, false)
     and coalesce(enc ->> 'boss', '') = '' then
    pk := game.perk(v_pid);
    ok_pir := pk is not null and pk ->> 'arch' = 'pirate';
  end if;

  if v_t in ('gertak', 'rampas') then
    if not ok_pir then raise exception 'Taktik tidak dikenali: %', v_t; end if;
    perform game.me(true);
    if v_t = 'rampas' then
      if coalesce((enc ->> 'rampas')::boolean, false) then raise exception 'Kru sudah siap merampas, Kapten. Tinggal menangkan pertempurannya.'; end if;
      if game.perk_harian_left(v_pid, 'pir') <= 0 then raise exception 'Kru sudah lelah merampas hari ini, Kapten.'; end if;
      enc := enc || '{"rampas": true}'::jsonb;
      update game.player_location set pending_encounter = enc where player_id = v_pid;
      return jsonb_build_object('ongoing', true, 'message', 'Kru bersiap dengan pengait dan karung. Kalau kapal itu kalah, palkanya milik kita.',
        'encounter', enc, 'newCondition', game.ship_json(v_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = v_pid));
    end if;
    -- gertak
    if not game.perk_harian_pakai(v_pid, 'pir') then raise exception 'Gertakanmu sudah habis hari ini, Kapten.'; end if;
    voyage := game.voyage_state(v_pid);
    v_msg := 'Kau naik ke haluan dan menatap ' || coalesce(enc ->> 'enemyName', 'mereka') || '. "...bendera itu. Lewat sudah, lewat sudah." Mereka menurunkan layar dan membiarkanmu lewat.';
    perform game.quest_combat_end(v_pid, enc, 'fled');
    fin := game.voy_finalize_arrival(v_pid, voyage ->> 'destinationCityId', v_msg);
    perform game.voy_log_combat(v_pid, coalesce((enc ->> 'enemyLevel')::int, 0), 'gertak', 'fled', '');
    return jsonb_build_object('ongoing', false, 'success', true, 'result', 'fled', 'message', v_msg, 'cityId', fin -> 'cityId',
      'newCondition', game.ship_json(v_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = v_pid),
      'perkNote', 'Intimidation: Gertak.');
  end if;

  -- suap lebih murah: selisih ditalangi dulu, lalu inti memotong harga penuh (bersih = harga diskon)
  if ok_pir and v_t = 'bribe' then
    v_lvl := game.voy_num(enc -> 'enemyLevel');
    v_cost := greatest(50, game.voy_round(game.cfg_num('CombatBribeGoldPerLevel', 150) * v_lvl
      * greatest(0.25, case when game.voy_num(enc -> 'enemyMaxHp') > 0 then game.voy_num(enc -> 'enemyHp') / game.voy_num(enc -> 'enemyMaxHp') else 0 end)));
    v_mul := game.cfg_num(case when (pk ->> 'tingkat')::int >= 2 then 'PerkPirSuap2' else 'PerkPirSuap1' end, 0.75);
    v_disc := greatest(1, round(v_cost * v_mul));
    select gold into v_gold from game.players where player_id = v_pid for update;
    if v_gold < v_disc then raise exception 'Gold tidak cukup untuk menyuap (butuh % gold).', v_disc; end if;
    v_top := (v_cost - v_disc)::bigint;
    if v_top > 0 then update game.players set gold = gold + v_top where player_id = v_pid; end if;
  end if;

  r := game.api_resolvecombat_perk(a);

  if v_top > 0 then
    if r ->> 'result' = 'bribed' then
      r := r || jsonb_build_object('message', replace(r ->> 'message', v_cost::bigint || ' gold berpindah tangan', v_disc::bigint || ' gold berpindah tangan'),
        'perkNote', 'Intimidation: suapmu lebih murah.');
    else
      update game.players set gold = greatest(0, gold - v_top) where player_id = v_pid;
      r := r || jsonb_build_object('newGold', (select gold from game.players where player_id = v_pid));
    end if;
  end if;

  -- Rampas Muatan: hanya bila menang dan pertempuran ditandai
  if ok_pir and coalesce((enc ->> 'rampas')::boolean, false) and r ->> 'result' = 'won' and coalesce((r ->> 'ongoing')::boolean, false) = false then
    select c.id, c.size into v_comm, v_size from game.commodities c where c.active and c.tier <> 'premium' order by random() limit 1;
    v_q := least(game.cfg_num('PerkPirRampasMin', 5)::int + floor(random() * (game.cfg_num('PerkPirRampasMax', 10) - game.cfg_num('PerkPirRampasMin', 5) + 1))::int,
                 floor(greatest(0, game.cargo_free(v_pid)) / greatest(0.1, v_size))::int);
    if v_q > 0 and game.perk_harian_pakai(v_pid, 'pir') then
      perform game.adjust_inventory(v_pid, v_comm, v_q);
      perform game.inv_add_cost(v_pid, v_comm, v_q, v_q * (select base from game.commodities where id = v_comm));
      v_note := 'Palka mereka lebih ringan sekarang. +' || v_q || ' ' || game.commodity_name(v_comm) || '.';
    else
      v_note := 'Palkamu penuh, Kapten. Kru tidak bisa membawa rampasan apa pun.';
    end if;
    r := r || jsonb_build_object('message', (r ->> 'message') || ' ' || v_note, 'perkNote', v_note,
      'rampas', case when v_q > 0 then jsonb_build_object('commodityId', v_comm, 'qty', v_q) end);
  end if;
  return r;
end $$;
select game.expose('api_resolvecombat');

-- ---------------------------------------------------------------------
-- Explorer: peluang peta harta dari kemenangan x1.5 · Firasat Karam (Peti Karam pertama tiap hari + 1 peta)
-- ---------------------------------------------------------------------
create or replace function game.treasure_drop(p_pid uuid, p_enemy_level int) returns jsonb
language plpgsql as $$
declare r jsonb := game.treasure_drop_perk(p_pid, p_enemy_level); it game.item_catalog; v_extra numeric;
begin
  if r is not null or not game.perk_is(p_pid, 'explorer') then return r; end if;
  -- kesempatan kedua sebesar (pengali - 1) x peluang dasar -> total kira-kira peluang x pengali
  v_extra := game.cfg_num('TreasureMapDropChance', 15) * (game.cfg_num('PerkExpPeta1', 1.5) - 1);
  if not (random() * 100 < v_extra) then return null; end if;
  select * into it from game.item_catalog where type = 'treasure_map' order by random() limit 1;
  if not found then return null; end if;
  perform game.item_adjust(p_pid, it.item_id, 1);
  return jsonb_build_object('itemId', it.item_id, 'name', it.name, 'note', ' Among the wreckage, the crew salvages ' || it.name || '!');
end $$;

create or replace function game.fish_quest_weight(p_pid uuid, p_fish text, p_city text) returns numeric
language plpgsql stable as $$
declare w numeric := coalesce(game.fish_quest_weight_perk(p_pid, p_fish, p_city), 1); pk jsonb;
begin
  if p_fish <> 'peti' or w <= 0 then return w; end if;
  if current_setting('mt.perk_karam', true) = '1' then return w * 100000; end if;
  pk := game.perk(p_pid);
  if pk is not null and pk ->> 'arch' = 'explorer' and (pk ->> 'tingkat')::int >= 2 then w := w * game.cfg_num('PerkExpKaram2', 1.5); end if;
  return w;
end $$;

-- lemparan ke perairan dalam (jarak >= 0.72) saat Firasat Karam masih ada -> Peti Karam dijamin
create or replace function public.api_mgFishCast(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_dist numeric; r jsonb;
begin
  v_dist := least(1, greatest(0, coalesce(nullif(game.arg(a, 0), '')::numeric, 0.5)));
  if v_dist >= 0.72 and game.perk_is(v_pid, 'explorer') and game.perk_harian_left(v_pid, 'exp') > 0 then
    perform set_config('mt.perk_karam', '1', true);
  end if;
  r := game.api_mgfishcast_perk(a);
  perform set_config('mt.perk_karam', '0', true);
  return r;
exception when others then
  perform set_config('mt.perk_karam', '0', true);
  raise;
end $$;
select game.expose('api_mgfishcast');

create or replace function public.api_mgFishReel(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb := game.api_mgfishreel_perk(a); it game.item_catalog;
begin
  if coalesce((r ->> 'caught')::boolean, false) and r #>> '{fish,id}' = 'peti' and game.perk_is(v_pid, 'explorer')
     and game.perk_harian_pakai(v_pid, 'exp') then
    select * into it from game.item_catalog where type = 'treasure_map' order by random() limit 1;
    if found then
      perform game.item_adjust(v_pid, it.item_id, 1);
      r := r || jsonb_build_object('perkNote', 'Treasure Hunter: di dasar peti, terlipat rapi: ' || it.name || '.',
        'perkItem', jsonb_build_object('itemId', it.item_id, 'name', it.name));
    end if;
  end if;
  return r;
end $$;
select game.expose('api_mgfishreel');

-- ---------------------------------------------------------------------
-- Gambler: Taruhan Kedua (dadu lapau) · tukar Pesanan Harian tambahan
-- ---------------------------------------------------------------------
create or replace function public.api_mgDice(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb := game.api_mgdice_perk(a); v_bet bigint;
begin
  if not coalesce((r ->> 'win')::boolean, true) and game.perk_is(v_pid, 'gambler') and game.perk_harian_pakai(v_pid, 'gam') then
    v_bet := abs(coalesce((r ->> 'delta')::bigint, 0));   -- inti sudah membatasi taruhan (maks normal)
    update game.players set gold = gold + v_bet where player_id = v_pid;
    r := r || jsonb_build_object('refund', v_bet, 'newGold', (select gold from game.players where player_id = v_pid),
      'perkNote', 'High Roller: keberuntungan pemain lama. Taruhanmu kembali.');
  end if;
  return r;
end $$;
select game.expose('api_mgdice');

create or replace function public.api_harian(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r game.hr_sheets; v_used boolean := false; x jsonb;
begin
  if coalesce(game.arg(a, 0), '') = 'tukar' and game.perk_is(v_pid, 'gambler') and game.fitur_on(v_pid, 'HarianOpen') then
    r := game.hr_sheet(v_pid);
    select * into r from game.hr_sheets where player_id = v_pid and day = r.day for update;
    if found and r.reroll >= 1 + r.reroll_bonus and game.perk_harian_left(v_pid, 'tukar') > 0 then
      -- jatah biasa habis: perk membuka satu tukar lagi (dicatat di perk_harian, bukan reroll_bonus,
      -- supaya batas jasa Tukar Pesanan tetap utuh)
      update game.hr_sheets set reroll = reroll - 1 where player_id = v_pid and day = r.day;
      v_used := true;
    end if;
  end if;
  if v_used then
    x := game.api_harian_perk(a);
    perform game.perk_harian_pakai(v_pid, 'tukar');
    return x;
  end if;
  return game.api_harian_perk(a);
end $$;
select game.expose('api_harian');

create or replace function game.harian_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare o jsonb := game.harian_state_perk(p_pid); v_x int;
begin
  if o is not null and o ? 'rerollLeft' and game.perk_is(p_pid, 'gambler') then
    v_x := game.perk_harian_left(p_pid, 'tukar');
    if v_x > 0 then o := o || jsonb_build_object('rerollLeft', (o ->> 'rerollLeft')::int + v_x, 'rerollPerk', v_x); end if;
  end if;
  return o;
end $$;

-- ---------------------------------------------------------------------
-- Smuggler: titip gudang gratis (sampai batas unit per pulau) · Kenalan Lama (pinjaman kiriman berikutnya)
-- ---------------------------------------------------------------------
create or replace function public.api_warehouseStore(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_city text := game.arg(a, 0); v_qty bigint := game.arg_int(a, 2); pk jsonb;
  v_have bigint; v_free bigint; v_back numeric := 0; r jsonb;
begin
  pk := game.perk(v_pid);
  if pk is not null and pk ->> 'arch' = 'smuggler' and coalesce(v_qty, 0) > 0 then
    select coalesce(sum(qty), 0) into v_have from game.warehouse where player_id = v_pid and city_id = v_city;
    v_free := greatest(0, game.cfg_num(case when (pk ->> 'tingkat')::int >= 2 then 'PerkSmuGudang2' else 'PerkSmuGudang1' end, 200)::bigint - v_have);
    v_back := trim_scale(game.cfg_num('WarehouseFeePerUnit', 2) * least(v_qty, v_free));
    -- biaya ditalangi dulu supaya pemeriksaan gold inti tidak menolak, lalu inti memotong biaya penuh
    if v_back > 0 then update game.players set gold = gold + v_back::bigint where player_id = v_pid; end if;
  end if;
  r := game.api_warehousestore_perk(a);
  if v_back > 0 then
    r := r || jsonb_build_object('fee', greatest(0, (r ->> 'fee')::numeric - v_back), 'newGold', (select gold from game.players where player_id = v_pid),
      'perkNote', 'Underworld Connections: penjaga gudang tidak menarik biaya.');
  end if;
  return r;
end $$;
select game.expose('api_warehousestore');

-- pinjaman Kenalan Lama dipotong dari stok saat siklusnya tiba (stok tidak pernah di bawah 0)
create or replace function game.perk_pinjam_apply(p_city text, p_comm text) returns void
language plpgsql as $$
declare l record; v_cyc bigint := game.mkt_cycle_index();
begin
  for l in select * from game.perk_pinjam where city_id = p_city and (p_comm is null or commodity_id = p_comm) and cyc <= v_cyc for update skip locked loop
    update game.market set stock = greatest(0, stock - l.qty) where city_id = l.city_id and commodity_id = l.commodity_id;
    delete from game.perk_pinjam where city_id = l.city_id and commodity_id = l.commodity_id and cyc = l.cyc;
  end loop;
end $$;

create or replace function game.mkt_lock(p_city text, p_comm text) returns numeric
language plpgsql as $$
declare s numeric := game.mkt_lock_perk(p_city, p_comm);
begin
  if s is not null and exists (select 1 from game.perk_pinjam where city_id = p_city and commodity_id = p_comm and cyc <= game.mkt_cycle_index()) then
    perform game.perk_pinjam_apply(p_city, p_comm);
    select stock into s from game.market where city_id = p_city and commodity_id = p_comm;
  end if;
  return s;
end $$;

create or replace function game.mkt_refresh(p_city text) returns void
language plpgsql as $$
begin
  perform game.mkt_refresh_perk(p_city);
  if exists (select 1 from game.perk_pinjam where city_id = p_city and cyc <= game.mkt_cycle_index()) then
    perform game.perk_pinjam_apply(p_city, null);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Diplomat: tawaran misi tambahan · Surat Pengantar (Standing +1 pada misi selesai, Harian)
-- ---------------------------------------------------------------------
create or replace function game.mission_tiers(p_city text) returns jsonb
language plpgsql stable as $$
declare t jsonb := game.mission_tiers_perk(p_city); n int := coalesce(nullif(current_setting('mt.perk_tawar', true), '')::int, 0); i int;
begin
  for i in 1 .. least(4, greatest(0, n)) loop
    t := t || '[{"minReputation":0,"label":"Surat Pengantar Gubernur","qtyRange":[6,12],"rewardPerUnitRange":[25,38]}]'::jsonb;
  end loop;
  return t;
exception when others then return game.mission_tiers_perk(p_city);
end $$;

create or replace function game.mission_board(p_pid uuid, p_city text) returns jsonb
language plpgsql stable as $$
declare pk jsonb := game.perk(p_pid); n int := 0; r jsonb;
begin
  if pk is not null and pk ->> 'arch' = 'diplomat' then
    n := game.cfg_num(case when (pk ->> 'tingkat')::int >= 2 then 'PerkDipTawar2' else 'PerkDipTawar1' end, 1)::int;
  end if;
  perform set_config('mt.perk_tawar', n::text, true);
  r := game.mission_board_perk(p_pid, p_city);
  perform set_config('mt.perk_tawar', '0', true);
  return r;
end $$;

create or replace function public.api_completeMission(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb := game.api_completemission_perk(a); v_c text; v_rep jsonb; v_add numeric;
begin
  v_c := r ->> 'cityId';
  if v_c is not null and game.perk_is(v_pid, 'diplomat') and game.perk_harian_pakai(v_pid, 'dip') then
    v_add := game.cfg_num('PerkDipStanding', 1);
    select case when jsonb_typeof(reputation) = 'object' then reputation else '{}'::jsonb end into v_rep from game.players where player_id = v_pid;
    v_rep := v_rep || jsonb_build_object(v_c, coalesce(case when jsonb_typeof(v_rep -> v_c) = 'number' then (v_rep ->> v_c)::numeric end, 0) + v_add);
    update game.players set reputation = v_rep where player_id = v_pid;
    r := r || jsonb_build_object('perkNote', 'Silver Tongue: gubernur membaca surat pengantarmu. Standing +' || v_add::int || '.', 'standingBonus', v_add);
  end if;
  return r;
end $$;
select game.expose('api_completemission');

-- ---------------------------------------------------------------------
-- Merchant: Firasat Harga (arah harga tiap barang) · Matang: Catatan Pasar (2 kota terakhir)
-- arah: stok di bawah tingkat alaminya -> stok akan naik -> harga TURUN ('down'); di atasnya -> NAIK ('up').
-- ---------------------------------------------------------------------
create or replace function public.api_getMarket(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb := game.api_getmarket_perk(a); pk jsonb; v_city text := game.arg(a, 0); v_tags jsonb;
  out_items jsonb := '[]'::jsonb; x jsonb; eq numeric; s numeric; v_cat jsonb;
begin
  pk := game.perk(v_pid);
  if pk is null or pk ->> 'arch' <> 'merchant' or jsonb_typeof(r -> 'items') <> 'array' then return r; end if;
  v_tags := game.mkt_cycle_tags(v_city, game.mkt_cycle_index());
  for x in select * from jsonb_array_elements(r -> 'items') loop
    eq := game.mkt_eq(x ->> 'role', x ->> 'tier', (x ->> 'refStock')::numeric, x ->> 'commodityId', v_tags);
    s := (x #>> '{curve,s}')::numeric;
    out_items := out_items || jsonb_build_array(x || jsonb_build_object('trend',
      case when s is null then 'flat' when s < eq * 0.97 - 0.5 then 'down' when s > eq * 1.03 + 0.5 then 'up' else 'flat' end));
  end loop;
  r := r || jsonb_build_object('items', out_items, 'perkTrend', true);
  if (pk ->> 'tingkat')::int >= 2 then
    select coalesce(data -> 'catatan', '[]'::jsonb) into v_cat from game.player_quests where player_id = v_pid and quest_id = 'surat';
    r := r || jsonb_build_object('perkCatatan', (select coalesce(jsonb_agg(c || jsonb_build_object('cityName', game.city_name(c ->> 'city'))), '[]'::jsonb)
      from jsonb_array_elements(v_cat) c where c ->> 'city' <> v_city));
  end if;
  return r;
end $$;
select game.expose('api_getmarket');
