-- =====================================================================
-- 0084 · Zentul kembali jadi rahasia Saga 4
--   Masalah: gerbang global `TrekOpen` dipakai sebagai syarat `zentul_open`
--   dan `trek_boleh`, padahal `game.fitur_on` mengembalikan true untuk SEMUA
--   pemain begitu kuncinya '1'. Akibatnya menyalakan TrekOpen membuka Zentul
--   dan Sirkuit untuk seluruh server, bukan hanya peserta Saga 4.
--
--   Sesudah migrasi ini:
--     * Zentul hanya terlihat pemain yang sudah sampai langkah 9 quest Mahkota
--       (artinya Saga 3 tamat dulu), atau penguji yang namanya ada di FiturPenguji.
--     * Sirkuit Selat Lurus (latihan/harian/Adu) hanya untuk yang sudah
--       MENAMATKAN Saga 4 dan merapat di Zentul. Balapan yang jadi bagian cerita
--       tetap lewat api_mahkota dan tidak tersentuh aturan ini.
--     * `TrekOpen` tidak lagi punya kuasa apa pun. Gerbang baru `TrekTutup`
--       ('1' = tutup paksa) disediakan sebagai sakelar darurat untuk Sirkuit.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('TrekTutup', '0') on conflict (key) do nothing;

-- Hanya nama yang terdaftar di FiturPenguji. Kunci global tidak berpengaruh.
create or replace function game.penguji_saja(p_pid uuid) returns boolean
language plpgsql stable as $$
declare v_list text := lower(replace(coalesce(game.cfg('FiturPenguji'), ''), ' ', '')); v_u text;
begin
  if v_list = '' or p_pid is null then return false; end if;
  select lower(coalesce(username, '')) into v_u from game.players where player_id = p_pid;
  return coalesce(v_u, '') <> '' and v_u = any (string_to_array(v_list, ','));
end $$;

-- Zentul: rahasia sampai Surat Tercecer (langkah 9).
create or replace function game.zentul_open(p_pid uuid) returns boolean
language sql stable as $$ select game.penguji_saja(p_pid) or game.mk_step(p_pid) >= 9 $$;

-- Sirkuit: hanya setelah Saga 4 tamat, dan kapal merapat di Zentul.
create or replace function game.trek_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select case
    when p_pid is null then false
    when lower(coalesce(game.cfg('TrekTutup'), '0')) in ('1', 'true', 'on', 'ya') then false
    when game.penguji_saja(p_pid) then true
    when game.in_transit(p_pid) or game.current_city(p_pid) is distinct from 'zentul' then false
    else game.mk_tamat(p_pid)
  end
$$;
