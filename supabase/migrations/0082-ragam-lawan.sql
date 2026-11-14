-- =====================================================================
-- Tide v60 — Ragam Bajak Laut Biasa (+ Fatrabbit)
-- Rancangan: claude/KONSEP-Ragam-Bajak-Laut-Biasa.md
--
-- Sebelum ini semua bajak laut acak identik: yang berbeda hanya HP dan
-- nama, dipilih murni dari level. Mesin tempur sudah mendukung sembilan
-- flag taktik, tapi tidak satu pun dipakai.
--
-- Migrasi ini TIDAK mengubah mesin tempur. Ia hanya memilih tokoh dan
-- memasang flag yang sudah didukung (plus empat kunci aditif di 0003,
-- yang semuanya coalesce-guarded: tanpa kunci = perilaku lama).
--
-- Peluang dicegat TIDAK berubah (tetap PirateEncounterBaseChance).
-- Jarahan TIDAK dinaikkan. Hukuman kalah TIDAK diperberat.
--
-- Gerbang: RagamLawanOpen (+ FiturPenguji). Mati = perilaku lama persis.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('RagamLawanOpen', '0'),
  ('RagamFatOdds',   '12'),              -- Fatrabbit: 1 dari N pencegatan
  ('RagamSalt',      'ganti-saya-di-config')   -- garam rahasia; JANGAN dibiarkan bawaan
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tokoh
-- ---------------------------------------------------------------------
create table if not exists game.ragam_types (
  id      text primary key,
  nama    text not null,
  lv_min  int  not null default 1,
  lv_max  int  not null default 5,
  hp_mul  numeric not null default 1,
  flags   jsonb not null default '{}'::jsonb,   -- flag mesin; hpFloorPct diubah ke hpFloor absolut saat dipasang
  greet   text,                                  -- satu baris saat muncul (dipakai klien)
  pemula  boolean not null default false,        -- boleh muncul untuk pemain < 20 Tanda Jasa
  malam   boolean not null default false,        -- hanya malam
  langka  boolean not null default false,        -- tidak masuk undian biasa (Fatrabbit)
  sort    int not null default 0
);
alter table game.ragam_types enable row level security;

insert into game.ragam_types(id, nama, lv_min, lv_max, hp_mul, flags, greet, pemula, malam, langka, sort) values
  ('bon_krieq', 'Bon Krieq', 1, 2, 0.7,
   '{"dmgTaken": 1.4, "enemyDmgMul": 1.2}'::jsonb,
   'Jangan tersinggung, Kapten! Ini bukan soal kau. Ini soal aku belum makan.',
   true, false, false, 10),

  ('buddy_clown', 'Buddy The Clown', 2, 3, 1,
   '{}'::jsonb,
   'Kakakku melukis supaya kiamat tidak datang. Aku merampok supaya datangnya cepat. Kami tetap sayang, kok.',
   true, false, false, 20),

  ('slimrabbit', 'SlimRabbit', 3, 4, 1.4,
   '{"dmgTaken": 0.45, "noRam": true,
     "noRamMsg": "SlimRabbit menepuk pelat lambungnya. \"Besi Bjorneo, Kapten. Tabrak saja kalau haluanmu sedang ingin pensiun.\""}'::jsonb,
   'Lambungku berpelat, Kapten. Dompetku tidak. Mari kita bicara angka.',
   false, false, false, 30),

  ('cipengwolf', 'Dokter CipengWolf', 3, 5, 1,
   '{"enemyDmgMul": 1.6, "immuneFirst": true}'::jsonb,
   'Tenang. Ini akan cepat. Saya sudah sering melakukannya.',
   false, false, false, 40),

  ('zuma', 'Bartholomew Zuma', 2, 3, 1,
   '{"immuneFirst": true, "noLoot": true,
     "wonMsg": "Kapalnya miring, lalu diam. Palkanya kosong - tidak ada satu peti pun. Ia memang hanya menginginkan tanda hormat."}'::jsonb,
   'Kami tidak ingin kapalmu, Kapten. Hanya sedikit tanda hormat.',
   true, false, false, 50),

  ('hantu_kabut', 'Hantu Kabut', 4, 5, 1,
   '{"dmgTaken": 0.7, "noLoot": true, "hpFloorPct": 30,
     "wonMsg": "Siluet itu memudar ke dalam kabut tanpa suara, tanpa meninggalkan puing, tanpa meninggalkan apa pun."}'::jsonb,
   null,
   false, true, false, 60),

  ('fatrabbit', 'Fatrabbit dan Telinga Angin', 3, 5, 1.2,
   '{"dmgTaken": 0.5, "enemyDmgMul": 0.8, "immuneFirst": true, "hpFloorPct": 25,
     "softSink": true,
     "noTalk": true,
     "noTalkMsg": "Fatrabbit menggeleng sambil tersenyum. \"Simpan koinmu. Yang kuambil tidak bisa dibeli kembali.\"",
     "noLoot": true,
     "wonMsg": "Telinga Angin berbelok menjauh. \"Baik. Baik! Ambil panjiku. Tapi ingat, kau menang karena aku sedang baik hati.\"",
     "softSinkMsg": "\"Muatanmu tidak kusentuh, Kapten - hitung sendiri kalau tidak percaya.\" Fatrabbit mengikatkan sepasang panji telinga di tiang utamamu. \"Panji ini kupinjamkan. Pakai yang rajin, biar semua pelabuhan tahu.\""}'::jsonb,
   'Tenang, Kapten. Aku tidak butuh gold-mu. Aku cuma mau ceritanya.',
   false, false, true, 70)
on conflict (id) do update set
  nama = excluded.nama, lv_min = excluded.lv_min, lv_max = excluded.lv_max, hp_mul = excluded.hp_mul,
  flags = excluded.flags, greet = excluded.greet, pemula = excluded.pemula, malam = excluded.malam,
  langka = excluded.langka, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Catatan Fatrabbit (Panji Kelinci + hitungan Kartu Kapten)
-- ---------------------------------------------------------------------
create table if not exists game.fr_mark (
  player_id uuid primary key references game.players(player_id) on delete cascade on update cascade,
  n         int not null default 0,        -- berapa kali dilucuti (tidak pernah turun)
  mark_at   timestamptz,                   -- panji terakhir dipasang; null = tidak memakai panji
  met_at    timestamptz,                   -- terakhir bertemu (batas 1x per hari nyata)
  won       boolean not null default false -- pernah mengalahkannya
);
alter table game.fr_mark enable row level security;

-- ---------------------------------------------------------------------
-- Pemilih tokoh: deterministik dari rute + siklus dunia + pemain + garam
-- (bukan random(); audit ekonomi temuan 11 - jadwal jangan bisa dihitung dari repo)
-- ---------------------------------------------------------------------
create or replace function game.ragam_hash(p_salt text, p_pid uuid, p_dest text, p_bucket bigint, p_tag text)
returns numeric language sql immutable as $$
  select ('x' || substr(md5(p_salt || '|' || p_pid::text || '|' || coalesce(p_dest, '') || '|'
                         || p_bucket::text || '|' || p_tag), 1, 8))::bit(32)::bigint / 4294967296.0
$$;

-- Fatrabbit hanya boleh sekali per hari nyata (WIB)
create or replace function game.ragam_fat_ok(p_pid uuid) returns boolean
language sql stable as $$
  select coalesce((select (m.met_at at time zone 'Asia/Jakarta')::date
                     < (now() at time zone 'Asia/Jakarta')::date
                  from game.fr_mark m where m.player_id = p_pid), true)
$$;

create or replace function game.ragam_pick(p_pid uuid, p_dest text, p_lvl int) returns text
language plpgsql stable as $$
declare v_salt text; v_bucket bigint; v_night boolean; v_newbie boolean; v_ids text[]; v_u numeric; v_n int;
begin
  v_salt   := coalesce(game.cfg('RagamSalt'), 'marantau');
  v_bucket := game.mkt_cycle_index();
  v_night  := coalesce(game.fish_is_night(), false);
  v_newbie := not coalesce(game.gala_badges(p_pid) >= 20, false);

  -- Fatrabbit: langka, sekali per hari nyata, hanya untuk >= 20 Tanda Jasa
  if not v_newbie and game.ragam_fat_ok(p_pid)
     and game.ragam_hash(v_salt, p_pid, p_dest, v_bucket, 'fat')
         < 1.0 / greatest(2, game.cfg_num('RagamFatOdds', 12)) then
    return 'fatrabbit';
  end if;

  select array_agg(id order by sort, id) into v_ids from game.ragam_types
   where not langka and p_lvl between lv_min and lv_max
     and (not malam or v_night) and (not v_newbie or pemula);
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n = 0 then return null; end if;
  v_u := game.ragam_hash(v_salt, p_pid, p_dest, v_bucket, 'tipe');
  return v_ids[1 + least(v_n - 1, floor(v_u * v_n)::int)];
end $$;

-- ---------------------------------------------------------------------
-- Pasang tokoh ke pencegatan acak (membungkus versi terakhir)
-- ---------------------------------------------------------------------
do $$ begin
  drop function if exists game.voy_roll_encounter_ragam(uuid, text);
  alter function game.voy_roll_encounter(uuid, text) rename to voy_roll_encounter_ragam;
end $$;

create or replace function game.voy_roll_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql volatile as $$
declare e jsonb; t game.ragam_types; v_id text; mhp numeric; v_fl jsonb;
begin
  -- dadu inti dikocok SEKALI, di luar penangan galat
  e := game.voy_roll_encounter_ragam(p_pid, p_dest);
  if e is null or jsonb_typeof(e) <> 'object' then return e; end if;
  -- hanya bajak laut acak: bos quest, Tony, dan pencegatan quest tidak disentuh
  if not coalesce((e ->> 'randomPirate')::boolean, false) then return e; end if;

  -- gagal-terbuka: kalau pemilihan tokoh error, pencegatan inti tetap jalan apa adanya
  begin
    if not game.fitur_on(p_pid, 'RagamLawanOpen') then return e; end if;

    v_id := game.ragam_pick(p_pid, p_dest, coalesce((e ->> 'enemyLevel')::int, 1));
    if v_id is null then return e; end if;
    select * into t from game.ragam_types where id = v_id;
    if not found then return e; end if;

    mhp  := greatest(1, round(game.voy_num(e -> 'enemyMaxHp') * coalesce(t.hp_mul, 1)));
    v_fl := coalesce(t.flags, '{}'::jsonb);
    if v_fl ? 'hpFloorPct' then
      v_fl := (v_fl - 'hpFloorPct')
              || jsonb_build_object('hpFloor', round(mhp * (v_fl ->> 'hpFloorPct')::numeric / 100));
    end if;

    e := e || v_fl || jsonb_build_object(
           'type', t.id, 'enemyName', t.nama, 'enemyMaxHp', mhp, 'enemyHp', mhp)
         || case when t.greet is null then '{}'::jsonb else jsonb_build_object('greet', t.greet) end;

    if t.id = 'fatrabbit' then
      insert into game.fr_mark as m (player_id, met_at) values (p_pid, now())
        on conflict (player_id) do update set met_at = now();
    end if;
  exception when others then
    raise warning '[ragam] pemilihan tokoh gagal: %', sqlerrm;
  end;
  return e;
end $$;

-- ---------------------------------------------------------------------
-- Hasil melawan Fatrabbit (dipanggil di akhir SETIAP pertempuran)
-- ---------------------------------------------------------------------
create or replace function game.fr_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  if p_enc is null or jsonb_typeof(p_enc) <> 'object'
     or coalesce(p_enc ->> 'type', '') <> 'fatrabbit' then return; end if;
  if p_result = 'sunk' then
    -- softSink: gold & muatan utuh. Yang hilang hanya harga diri.
    insert into game.fr_mark as m (player_id, n, mark_at) values (p_pid, 1, now())
      on conflict (player_id) do update set n = m.n + 1, mark_at = now();
  elsif p_result = 'won' then
    insert into game.fr_mark as m (player_id, won, mark_at) values (p_pid, true, null)
      on conflict (player_id) do update set won = true, mark_at = null;
    begin
      perform game.kd_grant(p_pid, 'panji_telinga_angin', 1, 'fatrabbit');
    exception when others then null; end;
  end if;
exception when others then null;   -- jangan pernah menggagalkan pertempuran karena fitur ini
end $$;

-- Salinan daftar terakhir (0055) + penangan Fatrabbit
create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  perform game.ps_combat_end(p_pid, p_enc, p_result);
  perform game.ww_combat_end(p_pid, p_enc, p_result);
  perform game.bx_combat_end(p_pid, p_enc, p_result);
  perform game.lt_combat_end(p_pid, p_enc, p_result);
  perform game.fr_combat_end(p_pid, p_enc, p_result);
end $$;

-- ---------------------------------------------------------------------
-- Panji Telinga Angin: hadiah mengalahkan Fatrabbit, tidak dijual
-- ---------------------------------------------------------------------
insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, price_admin, info, tokoh, req, exclusive, active, sort)
values ('panji_telinga_angin', 'rupa', 'panji', null, 'Panji Telinga Angin', 'legenda', 0, null,
        'Sepasang panji telinga milik Fatrabbit sendiri. Tidak dijual, tidak bisa ditukar keping - hanya untuk kapten yang pernah mengalahkannya.',
        'Fatrabbit', null, true, true, 196)
on conflict (id) do update set
  rak = excluded.rak, slot = excluded.slot, name = excluded.name, rarity = excluded.rarity,
  price = excluded.price, info = excluded.info, tokoh = excluded.tokoh,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Panji Kelinci: penanda SEMENTARA, pola yang sama dengan kd.emas (0034).
--   * tidak pernah ditulis ke kd_loadout -> rupa yang dibeli pemain tidak tersentuh
--   * diturunkan saat dibaca -> kedaluwarsa otomatis, tanpa cron, tanpa baris basi
--   * Kesaktian Set dihitung fungsi dalam dari rupa MILIK pemain, bukan dari penanda ini
--   * berisi cap waktu kedaluwarsa (bukan boolean) supaya potret presence yang basi
--     memperbaiki dirinya sendiri di sisi penonton
-- ---------------------------------------------------------------------
do $$ begin
  drop function if exists game.kd_visual_ragam(uuid);
  alter function game.kd_visual(uuid) rename to kd_visual_ragam;
end $$;

create or replace function game.kd_visual(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb := game.kd_visual_ragam(p_pid); v_at timestamptz; v_until bigint;
begin
  select mark_at into v_at from game.fr_mark where player_id = p_pid;
  if v_at is null then return v; end if;
  v_until := (extract(epoch from v_at) * 1000
              + game.cfg_num('GameDayLengthRealMinutes', 180) * 60000)::bigint;
  if v_until <= game.now_ms() then return v; end if;
  return coalesce(v, '{}'::jsonb) || jsonb_build_object('kelinci', v_until);
exception when others then return v;
end $$;

-- Status untuk klien: hitungan Kartu Kapten + panji aktif
create or replace function game.fr_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare m game.fr_mark; v_until bigint;
begin
  select * into m from game.fr_mark where player_id = p_pid;
  if not found then return null; end if;
  v_until := case when m.mark_at is null then null else
    (extract(epoch from m.mark_at) * 1000 + game.cfg_num('GameDayLengthRealMinutes', 180) * 60000)::bigint end;
  return jsonb_build_object('n', m.n, 'won', m.won,
    'panjiUntil', case when coalesce(v_until, 0) > game.now_ms() then v_until end);
end $$;
