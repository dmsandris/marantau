-- =====================================================================
-- 0068 — Pasir: pengejaran Franziska yang tidak menggantung (Tide v53)
-- Dasar: claude/AUDIT-Saga3-Gantung-2026-11-06.md, claude/KONSEP-Pengganti-Olah-Jejak.md
--
-- 1. Batas penyusulan: 1x per HARI GAME (dulu per hari WIB).
-- 2. Olah Jejak di pengejaran penuh diganti 4 permainan bergiliran (tidak pernah sama dengan yang terakhir):
--      warga   Tanya Warga        tiga saksi, satu berbohong (dinilai server)
--      buntuti Buntuti Keramaian  nilai dari klien
--      surat   Surat Tercecer     nilai dari klien
--      kuli    Tawar Kuli         tiga pilihan dialog (dinilai server); Kopi Pahit Sudyrman = sempurna
--    Hasil: sempurna 2 kemungkinan · lulus 3 · gagal boleh ulang 1x, gagal lagi = samar 4 kemungkinan.
--    Olah Jejak lama tetap untuk tutorial (jejak12).
-- 3. Kabar saat tiba: kemungkinan yang salah dicoret otomatis ("kosong"), jejak basi ("dingin"),
--    zaman salah di Quest 13 ("zaman").
-- 4. Status: petunjuk zaman bila pengejaran Q12 berlangsung di zaman lain.
--
-- ⚠️ SALINAN versi terakhir: ps_hari (0055), ps_kejar_on_arrive (0055), ps_kejar_json (0055), ps_state_q12 (0055),
--    ps_act_more (0054): aksi 'jejak' kini ditangani ps_act_kejar sebelum ps_act_q12. Aman diulang.
-- =====================================================================

-- 1. Hari game
create or replace function game.ps_hari() returns text
language sql stable as $$ select 'g' || game.game_day() $$;

-- ---------------------------------------------------------------------
-- Sifat pelabuhan untuk kesaksian
-- ---------------------------------------------------------------------
create or replace function game.ps_kota_sifat(p_city text) returns jsonb
language sql immutable as $$
  select case p_city
    when 'sunda_empire' then '{"wil": "Mare Nusantara", "ciri": "istana dan pustaka besar"}'
    when 'joungjava' then '{"wil": "Mare Nusantara", "ciri": "warung pantai berkopi manis"}'
    when 'bjorneo' then '{"wil": "Mare Nusantara", "ciri": "hutan ulin dan mercusuar"}'
    when 'skitraw' then '{"wil": "Mare Nusantara", "ciri": "kampung nelayan kecil"}'
    when 'toogood' then '{"wil": "Mare Nusantara", "ciri": "pelabuhan bata yang sepi"}'
    when 'ikn' then '{"wil": "Mare Nusantara", "ciri": "menara lampu dan trem"}'
    when 'sudyrman_pelabuhan' then '{"wil": "Benua Sudyrman", "ciri": "kedai kopi pahit"}'
    when 'sudyrman_akademi' then '{"wil": "Benua Sudyrman", "ciri": "lonceng akademi"}'
    when 'sudyrman_lembah' then '{"wil": "Benua Sudyrman", "ciri": "galangan seribu layar"}'
    else '{"wil": "Mare Nusantara", "ciri": "pelabuhan"}' end::jsonb
$$;

-- Surat Tercecer: kalimat kiasan untuk tujuan (nama kota tidak pernah dikirim)
create or replace function game.ps_kiasan(p_city text) returns text
language sql immutable as $$
  select case p_city
    when 'sunda_empire' then 'ke istana yang menyimpan lebih banyak buku daripada prajurit'
    when 'joungjava' then 'ke warung pantai yang kopinya terlalu manis untuk lidahmu'
    when 'bjorneo' then 'ke pohon-pohon yang lebih tua dari kita berdua'
    when 'skitraw' then 'ke kampung nelayan kecil yang jalanya selalu dijemur'
    when 'toogood' then 'ke pelabuhan bata yang terlalu sepi untuk ditinggali'
    when 'ikn' then 'ke tempat lampunya sampai ke laut'
    when 'sudyrman_pelabuhan' then 'ke tempat kau dulu menolak membayar kopi pahit'
    when 'sudyrman_akademi' then 'ke bawah lonceng yang dulu membangunkan kita setiap subuh'
    when 'sudyrman_lembah' then 'ke lembah tempat seribu layar dijahit'
    else 'ke pelabuhan yang belum pernah kau datangi' end
$$;

create or replace function game.ps_arah(p_from text, p_to text) returns text
language sql stable as $$
  select case when abs(b.map_y - a.map_y) >= abs(b.map_x - a.map_x)
              then case when b.map_y > a.map_y then 'selatan' else 'utara' end
              else case when b.map_x > a.map_x then 'timur' else 'barat' end end
  from game.cities a, game.cities b where a.city_id = p_from and b.city_id = p_to
$$;

create or replace function game.ps_jarak(p_from text, p_to text) returns numeric
language sql stable as $$
  select sqrt(power(b.map_x - a.map_x, 2) + power(b.map_y - a.map_y, 2)) from game.cities a, game.cities b where a.city_id = p_from and b.city_id = p_to
$$;

create or replace function game.ps_hash(p text) returns int
language sql immutable as $$ select ('x' || substr(md5(p), 1, 7))::bit(28)::int $$;

-- ---------------------------------------------------------------------
-- Permainan jejak yang ditugaskan
-- ---------------------------------------------------------------------
create or replace function game.ps_jejak_game(p_pid uuid, p_slot bigint, p_city text) returns text
language plpgsql stable as $$
declare v_last text := game.ps_kdata(p_pid) ->> 'lastGame'; v text[];
begin
  v := array(select g from unnest(array['warga', 'buntuti', 'surat', 'kuli']) g where g is distinct from v_last);
  return v[1 + game.ps_hash(p_pid::text || ':' || p_slot || ':' || p_city) % cardinality(v)];
end $$;

-- percobaan ke berapa di pelabuhan & slot ini (0 = pertama)
create or replace function game.ps_jejak_coba(p_pid uuid, p_slot bigint, p_city text) returns int
language sql stable as $$
  select case when (c ->> 'slot')::bigint = p_slot and c ->> 'city' = p_city then coalesce((c ->> 'n')::int, 0) else 0 end
  from (select game.ps_kdata(p_pid) -> 'coba' c) z
$$;

-- Tanya Warga: soal (bohong = indeks saksi pembohong; tidak pernah dikirim ke klien)
create or replace function game.ps_warga_soal(p_pid uuid, p_slot bigint, p_city text, p_coba int) returns jsonb
language plpgsql stable as $$
declare v_t text := game.ps_fz_port(p_pid, p_slot); v_arah text; v_lain text; v_sf jsonb; v_jauh boolean; v_n int;
  h int := game.ps_hash(p_pid::text || ':' || p_slot || ':' || p_city || ':' || p_coba); v_fakta text; v_s jsonb; v_out jsonb := '[]'::jsonb;
  v_peran jsonb := '[["Kuli dermaga","Bang Odon"],["Penjual ikan","Mak Ipah"],["Anak kecil","Ucok"],["Juru tambat","Pak Darto"],["Tukang perahu","Wak Leman"],["Penjual kue","Ceu Imas"],["Nelayan tua","Datuk Basa"],["Pengamen","Si Gondrong"]]'::jsonb;
  i int; v_bohong int; v_order int[];
begin
  if v_t is null then return null; end if;
  v_arah := coalesce(game.ps_arah(p_city, v_t), 'selatan');
  v_sf := game.ps_kota_sifat(v_t);
  v_jauh := coalesce(game.ps_jarak(p_city, v_t), 0) > 30;
  v_n := coalesce((game.ps_kdata(p_pid) ->> 'n')::int, 0);
  v_lain := (array['utara', 'selatan', 'timur', 'barat'])[1 + (h % 3 + array_position(array['utara', 'selatan', 'timur', 'barat'], v_arah)) % 4];
  if v_lain = v_arah then v_lain := case v_arah when 'utara' then 'selatan' when 'selatan' then 'utara' when 'timur' then 'barat' else 'timur' end; end if;
  -- fakta pasti: terang di penyusulan awal, kiasan sesudahnya
  if v_n <= 1 then
    v_fakta := 'Kau melihat sendiri dari dermaga: kapal putih itu berlayar ke arah <b>' || v_arah || '</b>.';
  else
    v_fakta := case v_arah
      when 'utara' then 'Kata syahbandar, bintang kutub tepat di depan haluannya saat ia berangkat.'
      when 'selatan' then 'Kata syahbandar, bintang kutub tepat di belakang buritannya saat ia berangkat.'
      when 'timur' then 'Kata syahbandar, ia berangkat menyongsong matahari terbit.'
      else 'Kata syahbandar, ia berangkat mengejar matahari terbenam.' end;
  end if;
  v_s := jsonb_build_array(
    'Kapalnya menuju ' || (v_sf ->> 'wil') || '. Aku kenal layarnya, layar itu sering lewat sana.',
    case when v_jauh then 'Ia membeli bekal banyak sekali. Pelayarannya pasti jauh.' else 'Ia hanya membeli sebungkus kue. Katanya tidak lama di laut.' end,
    case when v_n <= 1 then 'Aku lihat sendiri, kapalnya berbelok ke ' || v_lain || '!'
         else 'Ia bertanya padaku jalan tercepat ke ' || v_lain || '. Pasti ke sanalah ia pergi.' end);
  -- urutan saksi diacak
  v_order := case h % 6 when 0 then array[0,1,2] when 1 then array[0,2,1] when 2 then array[1,0,2] when 3 then array[1,2,0] when 4 then array[2,0,1] else array[2,1,0] end;
  for i in 1..3 loop
    v_out := v_out || jsonb_build_array(jsonb_build_object('peran', v_peran -> ((h / 7 + i * 3) % 8) ->> 0, 'nama', v_peran -> ((h / 7 + i * 3) % 8) ->> 1,
      'seed', 'warga' || ((h / 7 + i * 3) % 8), 'kata', v_s ->> v_order[i]));
    if v_order[i] = 2 then v_bohong := i - 1; end if;
  end loop;
  return jsonb_build_object('fakta', v_fakta, 'saksi', v_out, 'bohong', v_bohong);
end $$;

-- Tawar Kuli: watak & nilai jawaban
create or replace function game.ps_kuli_watak(p_pid uuid, p_slot bigint, p_city text, p_coba int) returns text
language sql immutable as $$
  select (array['pemalu', 'pekerja', 'kopi', 'cerita'])[1 + game.ps_hash(p_pid::text || ':kuli:' || p_slot || ':' || p_city || ':' || p_coba) % 4]
$$;
create or replace function game.ps_kuli_nilai(p_watak text, p_r int, p_o text) returns int
language sql immutable as $$
  select coalesce(('{
    "pemalu":  {"1": {"sopan": 2, "akrab": 0, "langsung": -1}, "2": {"kopi": 1, "cerita": 0, "bantu": 2}, "3": {"halus": 2, "langsung": -1, "pancing": 1}},
    "pekerja": {"1": {"sopan": 0, "akrab": 1, "langsung": 2},  "2": {"kopi": 0, "cerita": -1, "bantu": 2}, "3": {"halus": 0, "langsung": 2, "pancing": 0}},
    "kopi":    {"1": {"sopan": 1, "akrab": 1, "langsung": 0},  "2": {"kopi": 2, "cerita": 0, "bantu": 0}, "3": {"halus": 1, "langsung": 1, "pancing": 1}},
    "cerita":  {"1": {"sopan": 1, "akrab": 2, "langsung": -1}, "2": {"kopi": 1, "cerita": 2, "bantu": 0}, "3": {"halus": 1, "langsung": 0, "pancing": 2}}
  }'::jsonb -> p_watak -> p_r::text ->> p_o)::int, -1)
$$;

create or replace function game.ps_barang_del(p_pid uuid, p_item text) returns void
language plpgsql as $$
begin
  update game.pasir_state set data = jsonb_set(data, '{barang}',
    coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(data -> 'barang', '[]'::jsonb)) x where x <> to_jsonb(p_item)), '[]'::jsonb)),
    updated_at = now() where player_id = p_pid;
end $$;

create or replace function game.ps_jejak_kand_n(p_pid uuid, p_benar text, p_here text, p_slot bigint, p_n int) returns jsonb
language sql stable as $$
  select jsonb_agg(c order by md5(p_pid::text || p_slot || c)) from (
    select p_benar c
    union all
    (select x from unnest(game.ps_fz_pool(p_pid)) x where x <> p_benar and x <> p_here order by md5(p_pid::text || ':' || p_slot || x) limit greatest(1, p_n - 1))
  ) z
$$;

-- ---------------------------------------------------------------------
-- Aksi 'jejak' baru (dipanggil sebelum ps_act_more)
-- ---------------------------------------------------------------------
create or replace function game.ps_act_kejar(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare k jsonb := game.ps_kdata(p_pid); v_slot bigint := game.ps_slot(); v_city text := game.current_city(p_pid);
  v_game text; v_arg text := game.arg(a, 1); v_arg2 text := game.arg(a, 2); v_coba int; v_grade text; v_soal jsonb;
  v_w text; v_sum int := 0; v_opts text[]; i int; v_kopi boolean := false; v_n int; v_kand jsonb;
begin
  if p_act <> 'jejak' then return null; end if;
  if not game.ps_kejar_aktif(p_pid) or game.in_transit(p_pid) then raise exception 'Tak ada jejak untuk dibaca di sini.'; end if;
  if v_city is distinct from game.ps_fz_port(p_pid, v_slot - 1) or v_city = game.ps_fz_port(p_pid, v_slot) then raise exception 'Tak ada jejak segar di dermaga ini.'; end if;
  if (k -> 'jejak' ->> 'slot')::bigint = v_slot and k -> 'jejak' ->> 'from' = v_city and not coalesce((k -> 'jejak' ->> 'tutorial')::boolean, false) then
    return jsonb_build_object('ok', true, 'grade', k -> 'jejak' ->> 'grade', 'sudah', true);
  end if;
  v_game := game.ps_jejak_game(p_pid, v_slot, v_city);
  if coalesce(v_arg, '') <> v_game then raise exception 'Jejak di dermaga ini dibaca dengan cara lain.'; end if;
  v_coba := game.ps_jejak_coba(p_pid, v_slot, v_city);
  if v_game = 'warga' then
    v_soal := game.ps_warga_soal(p_pid, v_slot, v_city, v_coba);
    v_grade := case when nullif(v_arg2, '')::int = (v_soal ->> 'bohong')::int then case when v_coba = 0 then 'sempurna' else 'lulus' end else 'gagal' end;
  elsif v_game = 'kuli' then
    v_w := game.ps_kuli_watak(p_pid, v_slot, v_city, v_coba);
    v_opts := string_to_array(coalesce(v_arg2, ''), ',');
    if cardinality(v_opts) <> 3 then raise exception 'Jawabanmu belum lengkap.'; end if;
    if v_opts[2] = 'kopipahit' then
      if not coalesce(game.ps_sdata(p_pid) -> 'barang' ? 'kopi_pahit', false) then raise exception 'Kau tidak membawa Kopi Pahit Sudyrman.'; end if;
      perform game.ps_barang_del(p_pid, 'kopi_pahit');
      v_kopi := true; v_grade := 'sempurna';
    else
      for i in 1..3 loop v_sum := v_sum + game.ps_kuli_nilai(v_w, i, v_opts[i]); end loop;
      v_grade := case when v_sum >= 5 then 'sempurna' when v_sum >= 3 then 'lulus' else 'gagal' end;
    end if;
  else
    if coalesce(v_arg2, '') not in ('sempurna', 'lulus', 'gagal') then raise exception 'Hasil tidak dikenal.'; end if;
    v_grade := v_arg2;
  end if;
  if v_grade = 'gagal' then
    if v_coba = 0 then
      perform game.ps_kdata_set(p_pid, jsonb_build_object('coba', jsonb_build_object('slot', v_slot, 'city', v_city, 'n', 1)));
      return jsonb_build_object('ok', false, 'ulang', true, 'game', v_game);
    end if;
    v_grade := 'samar';
  end if;
  v_n := case v_grade when 'sempurna' then 2 when 'lulus' then 3 else 4 end;
  v_kand := game.ps_jejak_kand_n(p_pid, game.ps_fz_port(p_pid, v_slot), v_city, v_slot, v_n);
  perform game.ps_kdata_set(p_pid, jsonb_build_object('lastGame', v_game, 'coba', null,
    'jejak', jsonb_build_object('slot', v_slot, 'from', v_city, 'coret', '[]'::jsonb, 'kand', v_kand, 'grade', v_grade, 'game', v_game)));
  return jsonb_build_object('ok', true, 'grade', v_grade, 'kand', v_kand, 'kopi', v_kopi, 'watak', v_w);
end $$;

-- ---------------------------------------------------------------------
-- Kedatangan (salinan 0055 + kabar tiba)
-- ---------------------------------------------------------------------
create or replace function game.ps_kejar_on_arrive(p_pid uuid, p_city text) returns void
language plpgsql as $$
declare k jsonb; v_slot bigint := game.ps_slot(); v_port text; v_j jsonb; v_t jsonb; v_q13 jsonb;
begin
  if not game.ps_kejar_aktif(p_pid) then return; end if;
  k := game.ps_kdata(p_pid);
  v_port := game.ps_fz_port(p_pid, v_slot);
  v_j := k -> 'jejak';
  if (k -> 'susul' ->> 'state') = 'ada' and (k -> 'susul' ->> 'city') is distinct from p_city then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null));
  end if;
  if game.ps_susul_ok(p_pid) and p_city = v_port and coalesce(k -> 'susul' ->> 'state', '') not in ('kabur', 'laut') then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', jsonb_build_object('state', 'ada', 'city', p_city, 'slot', v_slot)));
    return;
  end if;
  -- Quest 13: tujuan benar, zaman salah
  if game.ps_kejar_q13(p_pid) then
    v_q13 := game.ps13_tuju(game.ps13_n(p_pid));
    if p_city = (v_q13 ->> 'kota') and game.pasir_era(p_pid) <> (v_q13 ->> 'era') then
      v_t := jsonb_build_object('kota', p_city, 'hasil', 'zaman', 'era', v_q13 ->> 'era');
    end if;
  elsif jsonb_typeof(v_j) = 'object' and coalesce(v_j -> 'kand', '[]'::jsonb) ? p_city and not coalesce((v_j ->> 'tutorial')::boolean, false) then
    if (v_j ->> 'slot')::bigint = v_slot then
      if p_city is distinct from v_port and not coalesce(v_j -> 'coret', '[]'::jsonb) ? p_city then
        perform game.ps_kdata_set(p_pid, jsonb_build_object('jejak', v_j || jsonb_build_object('coret', coalesce(v_j -> 'coret', '[]'::jsonb) || to_jsonb(p_city))));
      end if;
      v_t := jsonb_build_object('kota', p_city, 'hasil', 'kosong');
    else
      v_t := jsonb_build_object('kota', p_city, 'hasil', 'dingin');
    end if;
  end if;
  if v_t is not null then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('tiba', v_t || jsonb_build_object('t', game.now_ms(), 'nama', game.city_name(p_city))));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Status pengejaran (salinan 0055 + permainan jejak, kabar tiba)
-- ---------------------------------------------------------------------
create or replace function game.ps_kejar_json(p_pid uuid) returns jsonb
language plpgsql as $$
declare k jsonb; v_slot bigint := game.ps_slot(); v_city text := game.current_city(p_pid); v_docked boolean := not game.in_transit(p_pid);
  v_prev text; v_now text; v_j jsonb; v_baru boolean; v_game text; v_coba int; v_main jsonb; v_soal jsonb; v_done boolean;
begin
  if not game.ps_kejar_aktif(p_pid) then return null; end if;
  k := game.ps_kdata(p_pid);
  v_prev := game.ps_fz_port(p_pid, v_slot - 1);
  v_now := game.ps_fz_port(p_pid, v_slot);
  v_j := k -> 'jejak';
  v_baru := v_docked and v_city = v_prev and v_city <> v_now and not game.ps_kejar_q13(p_pid);
  v_done := coalesce(jsonb_typeof(v_j), '') = 'object' and (v_j ->> 'slot')::bigint = v_slot and v_j ->> 'from' = v_city and not coalesce((v_j ->> 'tutorial')::boolean, false);
  if v_baru and not coalesce(v_done, false) then
    v_game := game.ps_jejak_game(p_pid, v_slot, v_city);
    v_coba := game.ps_jejak_coba(p_pid, v_slot, v_city);
    v_main := jsonb_build_object('game', v_game, 'coba', v_coba);
    if v_game = 'warga' then
      v_soal := game.ps_warga_soal(p_pid, v_slot, v_city, v_coba);
      v_main := v_main || jsonb_build_object('fakta', v_soal -> 'fakta', 'saksi', v_soal -> 'saksi');
    elsif v_game = 'kuli' then
      v_main := v_main || jsonb_build_object('watak', game.ps_kuli_watak(p_pid, v_slot, v_city, v_coba));
    elsif v_game = 'surat' then
      v_main := v_main || jsonb_build_object('kiasan', game.ps_kiasan(v_now), 'potong', least(9, 6 + coalesce((k ->> 'n')::int, 0)));
    end if;
  end if;
  return jsonb_build_object(
    'gosip', case when game.ps_susul_ok(p_pid) and v_prev is not null then game.city_name(v_prev) end,
    'besok', not game.ps_susul_ok(p_pid),
    'baruPergi', v_baru,
    'main', v_main,
    'susul', k -> 'susul' ->> 'state',
    'susulKota', k -> 'susul' ->> 'city',
    'tiba', k -> 'tiba',
    'surat', coalesce((k ->> 'suratN')::int, 0),
    'jejak', case when jsonb_typeof(v_j) = 'object' then jsonb_build_object('kand', v_j -> 'kand', 'coret', coalesce(v_j -> 'coret', '[]'::jsonb),
        'from', v_j ->> 'from', 'grade', v_j ->> 'grade', 'game', v_j ->> 'game',
        'segar', case when coalesce((v_j ->> 'tutorial')::boolean, false) then coalesce((k ->> 'n')::int, 0) = 0 else (v_j ->> 'slot')::bigint = v_slot end,
        'manifes', coalesce((v_j ->> 'manifes')::boolean, false)) end,
    'n', coalesce((k ->> 'n')::int, 0));
end $$;

-- Surat Tercecer: hitung surat yang sudah utuh (untuk Papan Benang)
create or replace function game.ps_surat_tambah(p_pid uuid) returns void
language plpgsql as $$
begin
  perform game.ps_kdata_set(p_pid, jsonb_build_object('suratN', coalesce((game.ps_kdata(p_pid) ->> 'suratN')::int, 0) + 1));
end $$;

create or replace function game.ps_act_kejar2(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare r jsonb;
begin
  r := game.ps_act_kejar(p_pid, p_act, a);
  if r is not null and coalesce((r ->> 'ok')::boolean, false) and game.arg(a, 1) = 'surat' and not coalesce((r ->> 'sudah')::boolean, false) then
    perform game.ps_surat_tambah(p_pid);
  end if;
  return r;
end $$;
-- salinan 0054 + 'jejak' baru
create or replace function game.ps_act_more(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare v_arg text := game.arg(a, 1); b game.book_catalog; v_cost numeric; k jsonb;
begin
  -- v53: pengejaran (jejak) diperiksa lebih dulu
  if p_act = 'jejak' then return game.ps_act_kejar2(p_pid, p_act, a); end if;
  if p_act = 'beli_buku' then
    if not game.ps_toko_buka(p_pid, 'pustaka') then raise exception 'Pustaka Agung tidak ada di sini.'; end if;
    select * into b from game.book_catalog where book_id = v_arg and source = 'ps_pustaka';
    if not found then raise exception 'Buku itu tidak ada di rak Pustaka Agung.'; end if;
    if exists (select 1 from game.player_books where player_id = p_pid and book_id = v_arg) then raise exception 'Kamu sudah punya buku ini.'; end if;
    v_cost := coalesce(b.price, 0);
    update game.players set gold = gold - v_cost where player_id = p_pid and gold >= v_cost;
    if not found then raise exception 'Emasmu kurang, Kapten. Tuan Wiradarma menimbang % gold.', game.eco_num_text(v_cost); end if;
    perform game.ps_book_grant(p_pid, v_arg);
    perform game.log(p_pid, 'Membeli "' || b.name || '" di Pustaka Agung IKN (' || game.eco_num_text(v_cost) || ' gold, emas ditimbang).');
    return jsonb_build_object('ok', true, 'book', v_arg);
  elsif p_act = 'beli_pusaka' then
    select x into k from jsonb_array_elements(game.ps_pusaka_katalog()) x where x ->> 'id' = v_arg and x ? 'price';
    if k is null then raise exception 'Pusaka itu tidak dijual.'; end if;
    if not game.ps_toko_buka(p_pid, k ->> 'src') then
      raise exception '%', case k ->> 'src' when 'dok_garuda' then 'Pusaka itu hanya ditempa di Dok Garuda, IKN.' else 'Pusaka itu hanya dibuat di Galangan Lembah Seribu Layar.' end;
    end if;
    if exists (select 1 from game.pv_pusaka where player_id = p_pid and pusaka_id = v_arg) then raise exception 'Kau sudah memilikinya.'; end if;
    v_cost := (k ->> 'price')::numeric;
    update game.players set gold = gold - v_cost where player_id = p_pid and gold >= v_cost;
    if not found then raise exception 'Emasmu kurang, Kapten. Harganya % gold.', game.eco_num_text(v_cost); end if;
    insert into game.pv_pusaka(player_id, pusaka_id) values (p_pid, v_arg);
    perform game.log(p_pid, 'Membeli Pusaka ' || (k ->> 'name') || ' (' || game.eco_num_text(v_cost) || ' gold, emas ditimbang).');
    return jsonb_build_object('ok', true, 'pusaka', v_arg);
  end if;
  return game.ps_act_q12(p_pid, p_act, a);
end $$;

-- ---------------------------------------------------------------------
-- Status Quest 12 (salinan 0055 + petunjuk zaman & jeda Jangkar)
-- ---------------------------------------------------------------------
create or replace function game.ps_state_q12(p_pid uuid) returns jsonb
language plpgsql as $$
declare s int;
begin
  if game.pasir_era(p_pid) = 'lampau' and game.ps_step(p_pid, 'ps12') = 0 and game.ps_step(p_pid, 'ps11') >= 10 then
    perform game.ps_set(p_pid, 'ps12', 1, '{}'::jsonb);
  end if;
  s := game.ps_step(p_pid, 'ps12');
  return jsonb_build_object('q12', game.ps_q_json(p_pid, 'ps12'), 'kejar', game.ps_kejar_json(p_pid),
      'kejarZaman', case when s between 1 and 6 and game.pasir_era(p_pid) <> 'lampau' then 'lampau' end)
    || case when game.is_gm(p_pid) and game.ps_kejar_aktif(p_pid) then jsonb_build_object('fzGm', game.ps_fz_port(p_pid, game.ps_slot())) else '{}'::jsonb end
    || coalesce(game.ps_state_q13(p_pid), '{}'::jsonb);
end $$;


-- ---------------------------------------------------------------------
-- Quest 13 langkah 1: daftar pulau yang sudah terhitung (salinan 0056 + repPulau)
-- ---------------------------------------------------------------------
create or replace function game.ps_state_q13(p_pid uuid) returns jsonb
language plpgsql as $$
declare s int; d jsonb; v jsonb; v_rep int := 0; v_pulau jsonb := '[]'::jsonb;
begin
  s := game.ps_step(p_pid, 'ps13');
  -- dimulai saat kembali ke Zaman Keadilan setelah Quest 12
  if s = 0 and game.ps_step(p_pid, 'ps12') >= 7 and game.pasir_era(p_pid) = 'keadilan' then
    perform game.ps_set(p_pid, 'ps13', 1, jsonb_build_object('mulai_t', game.now_ms()));
    s := 1;
  end if;
  if s = 0 then return coalesce(game.ps_state_q14(p_pid), '{}'::jsonb); end if;
  d := game.ps_data(p_pid, 'ps13');
  if s = 1 then
    select count(distinct m.city_id) into v_rep from game.player_missions m
     where m.player_id = p_pid and m.status = 'completed' and m.city_id = any (game.ps_pulau_awal())
       and m.created_at >= to_timestamp(coalesce((d ->> 'mulai_t')::bigint, 0) / 1000.0);
    select coalesce(jsonb_agg(distinct game.city_name(m.city_id)), '[]'::jsonb) into v_pulau from game.player_missions m
     where m.player_id = p_pid and m.status = 'completed' and m.city_id = any (game.ps_pulau_awal())
       and m.created_at >= to_timestamp(coalesce((d ->> 'mulai_t')::bigint, 0) / 1000.0);
  end if;
  if game.ps_kejar_q13(p_pid) then
    v := game.ps13_tuju(game.ps13_n(p_pid));
    v := v || jsonb_build_object('nama', game.city_name(v ->> 'kota'), 'susulOk', game.ps_susul_ok(p_pid));
  end if;
  return jsonb_build_object('q13', game.ps_q_json(p_pid, 'ps13') || jsonb_build_object('rep', v_rep, 'repPulau', v_pulau,
      'repPerlu', game.cfg_num('PasirQ13Reputasi', 3)::int, 'palsuBesok', coalesce(d ->> 'palsu_hari', '') = game.ps_hari(),
      'beras', game.cfg_num('PasirQ13Beras', 100)::int), 'tuju13', v)
    || coalesce(game.ps_state_q14(p_pid), '{}'::jsonb);
end $$;
