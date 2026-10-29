-- =====================================================================
-- 0055 — Pasir · Batch 5: mesin pengejaran Franziska + Quest 12 "Kota yang Lampunya Sampai ke Laut" (Tide v41)
-- Skenario: claude/SKENARIO-Saga3-Dark.md bagian 6.3, 6.4, 10.
--
-- MESIN PENGEJARAN (dipakai juga Quest 13)
--   * Jadwal deterministik: slot = floor((now - WorldStart) / PasirSinggahMenit); pelabuhan slot = hash(pemain, slot)
--     dari kolam pelabuhan era itu, tidak pernah sama dengan slot sebelumnya. Lokasinya tidak pernah dikirim ke klien.
--   * Petunjuk: gosip (pelabuhan slot sebelumnya), Olah Jejak di pelabuhan yang baru ia tinggalkan (3 kemungkinan),
--     Manifes Syahbandar (coret satu kemungkinan, sekali per slot), Papan Deduksi di klien.
--   * Tersusul = merapat saat ia singgah (sekali per hari WIB): Mata Pesta -> ia kabur ke kapalnya ->
--     pelayaran berikutnya dicegat Janji Putih (bos, softSink, hpFloor). Menang = Franziska mundur (surat/kabar).
--
-- QUEST 12 (quest_id 'ps12')
--   1  Lompatan pertama ke 40 Tahun Lalu: IKN berjaya -> 'mulai12'
--   2  Tedsky muda di Menara Lampu: Mercusuar -> 'tedsky12' padam|jaga (riak tedsky_lampu; Almanak Lampu IKN)
--   3  Jejak pertama di dermaga IKN: Olah Jejak -> 'jejak12' (Benua Sudyrman muncul)
--   4  Pelabuhan Sudyrman (tutorial, selalu tersusul): Mata Pesta -> Janji Putih -> Surat Franzi #1
--      coco muda: 'kopi12' (Kopi Pahit Sudyrman) · Miss Nansy: 'nansy12' (riak nansy_buku)
--   5  Pengejaran di pulau-pulau lampau (mesin penuh) · Mas Karto 'karto12' · Ulin muda 'ulin12'. Tersusul -> langkah 6
--   6  Akademi Laut Sudyrman: Syahbandar (surat izin) -> 'akademi12' (kaca ketiga, hadiah)
--   7  Selesai
--
-- ⚠️ SALINAN versi terakhir + Pasir: ps_on_arrive (0053), quest_boss_encounter (0052), quest_boss_defeated (0028),
--    quest_combat_end (0028). Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PasirSinggahMenit', '45'),
  ('PasirKopiHarga', '500'),
  ('PasirQ12Hadiah', '120000')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Waktu & jadwal
-- ---------------------------------------------------------------------
create or replace function game.ps_slot_ms() returns bigint
language sql stable as $$ select greatest(60000, (game.cfg_num('PasirSinggahMenit', 45) * 60000)::bigint) $$;

create or replace function game.ps_slot(p_ms bigint default null) returns bigint
language sql stable as $$
  select floor((coalesce(p_ms, game.now_ms()) - game.cfg_num('WorldStartTimestamp', 0)::bigint)::numeric / game.ps_slot_ms())::bigint
$$;

create or replace function game.ps_hari() returns text
language sql stable as $$ select to_char((now() at time zone 'Asia/Jakarta')::date, 'YYYY-MM-DD') $$;

-- Kolam pelabuhan Franziska per era (Quest 13 menambah Zaman Keadilan)
create or replace function game.ps_fz_pool(p_pid uuid) returns text[]
language plpgsql stable as $$
begin
  if game.pasir_era(p_pid) = 'lampau' then
    return array['sunda_empire', 'joungjava', 'bjorneo', 'skitraw', 'toogood', 'ikn']
      || case when game.ps_sudyrman_open(p_pid) then game.ps_kota_lampau() else array[]::text[] end;
  end if;
  return array[]::text[];
end $$;

create or replace function game.ps_fz_raw(p_pid uuid, p_slot bigint, p_pool text[]) returns int
language sql immutable as $$
  select (abs(hashtext(p_pid::text || ':fz:' || p_slot)) % greatest(1, cardinality(p_pool)))
$$;

-- Pelabuhan tempat Franziska singgah pada slot itu (null = tidak sedang dikejar)
create or replace function game.ps_fz_port(p_pid uuid, p_slot bigint) returns text
language plpgsql stable as $$
declare pool text[] := game.ps_fz_pool(p_pid); n int := cardinality(pool); i int; j int; t int; d jsonb;
begin
  if n = 0 then return null; end if;
  d := game.ps_data(p_pid, 'ps12');
  if game.ps_step(p_pid, 'ps12') = 4 then return 'sudyrman_pelabuhan'; end if;   -- tutorial: selalu di Pelabuhan Sudyrman
  -- tak pernah dua slot berturut-turut di pelabuhan yang sama: hitung maju dari 8 slot sebelumnya
  j := game.ps_fz_raw(p_pid, p_slot - 8, pool);
  for t in reverse 7..0 loop
    i := game.ps_fz_raw(p_pid, p_slot - t, pool);
    if i = j then i := (i + 1) % n; end if;
    j := i;
  end loop;
  return pool[i + 1];
end $$;

-- Pengejaran aktif? (Quest 13 menambah langkahnya sendiri lewat ps_kejar_q13)
create or replace function game.ps_kejar_q13(p_pid uuid) returns boolean
language sql stable as $$ select false $$;
create or replace function game.ps_kejar_aktif(p_pid uuid) returns boolean
language sql stable as $$
  select (game.pasir_era(p_pid) = 'lampau' and game.ps_step(p_pid, 'ps12') in (4, 5)) or game.ps_kejar_q13(p_pid)
$$;

create or replace function game.ps_kdata(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce(game.ps_sdata(p_pid) -> 'kejar', '{}'::jsonb) $$;
create or replace function game.ps_kdata_set(p_pid uuid, p_patch jsonb) returns void
language plpgsql as $$
begin
  perform game.ps_sdata_set(p_pid, jsonb_build_object('kejar', game.ps_kdata(p_pid) || coalesce(p_patch, '{}'::jsonb)));
end $$;

create or replace function game.ps_susul_ok(p_pid uuid) returns boolean
language sql stable as $$ select coalesce(game.ps_kdata(p_pid) ->> 'hari', '') <> game.ps_hari() $$;

-- ---------------------------------------------------------------------
-- Kedatangan (salinan 0053 + pengejaran)
-- ---------------------------------------------------------------------
create or replace function game.ps_on_arrive_q13(p_pid uuid, p_city text) returns void
language plpgsql as $$ begin null; end $$;

create or replace function game.ps_kejar_on_arrive(p_pid uuid, p_city text) returns void
language plpgsql as $$
declare k jsonb; v_slot bigint := game.ps_slot();
begin
  if not game.ps_kejar_aktif(p_pid) then return; end if;
  k := game.ps_kdata(p_pid);
  -- Ia sempat kabur dari pelabuhan sebelumnya tapi kau tidak mengejarnya: lupakan
  if (k -> 'susul' ->> 'state') = 'ada' and (k -> 'susul' ->> 'city') is distinct from p_city then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null));
  end if;
  if game.ps_susul_ok(p_pid) and p_city = game.ps_fz_port(p_pid, v_slot)
     and coalesce(k -> 'susul' ->> 'state', '') not in ('kabur', 'laut') then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', jsonb_build_object('state', 'ada', 'city', p_city, 'slot', v_slot)));
  end if;
end $$;

create or replace function game.ps_on_arrive(p_pid uuid, p_city text) returns void
language plpgsql as $$
declare s int; d jsonb; b jsonb; n int; v_pay bigint;
begin
  perform game.ps10_try_start(p_pid);
  perform game.ps11_try_start(p_pid);
  s := game.ps_step(p_pid, 'ps10');
  if s = 3 then
    if p_city = 'empeer_depeer' then
      v_pay := game.cfg_num('PasirQ10Bayar', 20000)::bigint;
      update game.players set gold = gold + v_pay where player_id = p_pid;
      perform game.ps_set(p_pid, 'ps10', 4, jsonb_build_object('bayar', v_pay));
      perform game.log(p_pid, 'Nyonya Z. tiba di Pulau em pe''er de pe''er dan membayar ' || v_pay || ' gold.');
    else
      perform game.ps_set(p_pid, 'ps10', 2, '{}'::jsonb);
    end if;
  elsif s = 9 then
    d := game.ps_data(p_pid, 'ps10');
    b := coalesce(d -> 'bukti', '{}'::jsonb);
    select count(*) into n from jsonb_object_keys(b) k where k in ('skitraw', 'toogood', 'ikn');
    if n >= 2 and not (b ? 'laut') then b := b || jsonb_build_object('laut', game.now_ms()); end if;
    if p_city in ('skitraw', 'toogood', 'ikn') and not (b ? p_city) then b := b || jsonb_build_object(p_city, game.now_ms()); end if;
    perform game.ps_set(p_pid, 'ps10', 9, jsonb_build_object('bukti', b));
    if (b ? 'skitraw') and (b ? 'toogood') and (b ? 'ikn') and (b ? 'laut') then
      perform game.ps_set(p_pid, 'ps10', 10, '{}'::jsonb);
    end if;
  end if;
  perform game.ps_kejar_on_arrive(p_pid, p_city);
  perform game.ps_on_arrive_q13(p_pid, p_city);
end $$;

-- ---------------------------------------------------------------------
-- Janji Putih: pencegatan, kemenangan, mundur
-- ---------------------------------------------------------------------
create or replace function game.ps_janji_enc(p_pid uuid, p_kuat int) returns jsonb
language plpgsql as $$
declare ammo numeric := game.ww_ammo(p_pid); hp int := 260 + p_kuat * 90;
begin
  return jsonb_build_object('ps', true, 'boss', 'ps_janji', 'rolledAt', game.iso(now()), 'round', 1,
    'enemyName', 'Janji Putih', 'bossTitle', 'Franziska berdiri di haluan, payung renda di tangan',
    'displayLevel', 3 + p_kuat, 'enemyLevel', 2 + p_kuat, 'enemyMaxHp', hp, 'enemyHp', hp, 'hpFloor', round(hp * 0.45),
    'enemyDmgMul', 1.1 + p_kuat * 0.15, 'maxAmmo', ammo, 'ammoRemaining', ammo,
    'softSink', true, 'noRam', true,
    'noRamMsg', 'Menabrak Janji Putih? Lambungnya licin seperti tulang; kapalmu yang akan pecah.',
    'noTalkMsg', 'Franziska tidak menjawab. Payung rendanya menunjuk ke laut lepas.');
end $$;

create or replace function game.ps_boss_q13(p_pid uuid, p_dest text) returns jsonb
language sql as $$ select null::jsonb $$;
create or replace function game.ps_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql as $$
declare k jsonb := game.ps_kdata(p_pid);
begin
  if (k -> 'susul' ->> 'state') = 'kabur' and game.ps_kejar_aktif(p_pid) then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', (k -> 'susul') || '{"state": "laut"}'::jsonb));
    return game.ps_janji_enc(p_pid, case when game.ps_step(p_pid, 'ps12') = 4 then 0 else 1 end);
  end if;
  return game.ps_boss_q13(p_pid, p_dest);
end $$;

create or replace function game.ps_boss_won_q13(p_pid uuid) returns jsonb
language sql as $$ select null::jsonb $$;
create or replace function game.ps_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; s int; n int;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if not coalesce((enc ->> 'ps')::boolean, false) or (enc ->> 'boss') <> 'ps_janji' then return null; end if;
  n := coalesce((game.ps_kdata(p_pid) ->> 'n')::int, 0) + 1;
  perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null, 'hari', game.ps_hari(), 'n', n, 'jejak', null));
  s := game.ps_step(p_pid, 'ps12');
  if s = 4 then
    perform game.ps_set(p_pid, 'ps12', 5, jsonb_build_object('surat1', true));
    perform game.log(p_pid, 'Janji Putih berbelok tajam dan menghilang di balik kabut. Sepucuk surat lama melayang jatuh ke geladakmu.');
    return jsonb_build_object('gold', 0, 'message', 'Janji Putih mundur. Franziska berseru dari haluannya: "Kau keras kepala. Slaus juga begitu, dulu." Sepucuk surat lama jatuh ke geladakmu.');
  elsif s = 5 then
    perform game.ps_set(p_pid, 'ps12', 6, jsonb_build_object('akademi', true));
    perform game.log(p_pid, 'Franziska berteriak sebelum menghilang: "Kalau kau mau tahu siapa dia, datanglah ke Akademi!"');
    return jsonb_build_object('gold', 0, 'message', 'Janji Putih mundur lagi. Sebelum hilang di balik kabut, Franziska berseru: "Kalau kau mau tahu siapa dia, Kapten, datanglah ke Akademi!"');
  end if;
  return coalesce(game.ps_boss_won_q13(p_pid), jsonb_build_object('gold', 0, 'message', 'Janji Putih mundur ke balik kabut.'));
end $$;

create or replace function game.ps_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  if not coalesce((p_enc ->> 'ps')::boolean, false) or (p_enc ->> 'boss') <> 'ps_janji' or p_result = 'won' then return; end if;
  -- tutorial: ia menunggu dicegat lagi; selain itu ia lolos (coba hari ini lagi bila belum tersusul)
  if game.ps_step(p_pid, 'ps12') = 4 then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', jsonb_build_object('state', 'kabur', 'city', 'sudyrman_pelabuhan')));
  else
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null));
  end if;
end $$;

-- salinan 0052 + Pasir lebih dulu
create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql as $$
declare r jsonb := game.ps_boss_encounter(p_pid, p_dest);
begin
  if r is not null then return r; end if;
  if not game.ps_kini(p_pid) then return null; end if;
  return coalesce(game.gala_boss_encounter(p_pid, p_dest), game.tg_hunter_encounter(p_pid, p_dest),
                  game.ww_encounter(p_pid, p_dest), game.bx_encounter(p_pid, p_dest),
                  game.ts_hunter_encounter(p_pid, p_dest), game.lt_encounter(p_pid, p_dest));
end $$;

-- salinan 0028 + Pasir lebih dulu
create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language sql as $$
  select coalesce(game.ps_boss_defeated(p_pid), game.gala_boss_defeated(p_pid), game.ww_boss_defeated(p_pid), game.bx_boss_defeated(p_pid),
                  game.ts_boss_defeated(p_pid), game.lt_boss_defeated(p_pid))
$$;

create or replace function game.quest_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  perform game.ps_combat_end(p_pid, p_enc, p_result);
  perform game.ww_combat_end(p_pid, p_enc, p_result);
  perform game.bx_combat_end(p_pid, p_enc, p_result);
  perform game.lt_combat_end(p_pid, p_enc, p_result);
end $$;

-- ---------------------------------------------------------------------
-- Olah Jejak & Manifes
-- ---------------------------------------------------------------------
-- tiga kemungkinan tujuan: satu benar, dua dari kolam (bukan pelabuhan ini)
create or replace function game.ps_jejak_kand(p_pid uuid, p_benar text, p_here text, p_slot bigint) returns jsonb
language sql stable as $$
  select jsonb_agg(c order by md5(p_pid::text || p_slot || c)) from (
    select p_benar c
    union all
    (select x from unnest(game.ps_fz_pool(p_pid)) x where x <> p_benar and x <> p_here order by md5(p_pid::text || ':' || p_slot || x) limit 2)
  ) z
$$;

-- ---------------------------------------------------------------------
-- Aksi Quest 12 + pengejaran (sambungan ps_act_ext; 0054)
-- ---------------------------------------------------------------------
create or replace function game.ps_act_q13(p_pid uuid, p_act text, a jsonb) returns jsonb
language sql as $$ select null::jsonb $$;

create or replace function game.ps_act_q12(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps12'); d jsonb := game.ps_data(p_pid, 'ps12'); v_arg text := game.arg(a, 1);
  v_city text := game.current_city(p_pid); v_docked boolean := not game.in_transit(p_pid); v_era text := game.pasir_era(p_pid);
  k jsonb := game.ps_kdata(p_pid); v_slot bigint := game.ps_slot(); v_cost bigint; v_prev text; v_j jsonb; v_c text;
begin
  -- ===== pengejaran (umum) =====
  if p_act = 'jejak' then
    if not game.ps_kejar_aktif(p_pid) or not v_docked then raise exception 'Tak ada jejak untuk dibaca di sini.'; end if;
    v_prev := game.ps_fz_port(p_pid, v_slot - 1);
    if v_city is distinct from v_prev or v_city = game.ps_fz_port(p_pid, v_slot) then raise exception 'Tak ada jejak segar di dermaga ini.'; end if;
    if (k -> 'jejak' ->> 'slot')::bigint = v_slot and k -> 'jejak' ->> 'from' = v_city and not coalesce((k -> 'jejak' ->> 'tutorial')::boolean, false) then return jsonb_build_object('ok', true); end if;
    perform game.ps_kdata_set(p_pid, jsonb_build_object('jejak', jsonb_build_object('slot', v_slot, 'from', v_city, 'coret', '[]'::jsonb,
      'kand', game.ps_jejak_kand(p_pid, game.ps_fz_port(p_pid, v_slot), v_city, v_slot))));
    return jsonb_build_object('ok', true);
  elsif p_act = 'manifes' then
    if v_era <> 'lampau' or not v_docked then raise exception 'Manifes Syahbandar hanya ada di pelabuhan zaman itu.'; end if;
    v_j := k -> 'jejak';
    if v_j is null or jsonb_typeof(v_j) <> 'object' or (v_j ->> 'slot')::bigint <> v_slot then raise exception 'Belum ada kemungkinan untuk dicocokkan dengan manifes.'; end if;
    if coalesce((v_j ->> 'manifes')::boolean, false) then raise exception 'Syahbandar sudah menunjukkan manifesnya hari ini.'; end if;
    select x into v_c from jsonb_array_elements_text(v_j -> 'kand') x
     where x <> game.ps_fz_port(p_pid, v_slot) and not coalesce(v_j -> 'coret', '[]'::jsonb) ? x order by x limit 1;
    perform game.ps_kdata_set(p_pid, jsonb_build_object('jejak', v_j || jsonb_build_object('manifes', true,
      'coret', coalesce(v_j -> 'coret', '[]'::jsonb) || case when v_c is null then '[]'::jsonb else to_jsonb(v_c) end)));
    return jsonb_build_object('ok', true, 'coret', v_c);
  elsif p_act = 'pesta_fz' then
    if (k -> 'susul' ->> 'state') is distinct from 'ada' or not v_docked or v_city is distinct from (k -> 'susul' ->> 'city') then raise exception 'Perempuan bergaun putih itu tidak ada di sini.'; end if;
    if s <> 4 and (k -> 'susul' ->> 'slot')::bigint <> v_slot then
      perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null));
      raise exception 'Terlambat. Jejaknya sudah dingin; ia baru saja berlayar.';
    end if;
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', (k -> 'susul') || '{"state": "kabur"}'::jsonb));
    perform game.log(p_pid, 'Franziska terlihat di keramaian, lalu berlari ke kapalnya. Janji Putih membentangkan layar.');
    return jsonb_build_object('ok', true);
  end if;

  -- ===== Quest 12 =====
  if p_act = 'mulai12' then
    if s <> 1 or v_era <> 'lampau' then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(p_pid, 'ps12', 2, '{}'::jsonb);
    return jsonb_build_object('ok', true);
  elsif p_act = 'tedsky12' then
    if s <> 2 or v_era <> 'lampau' or coalesce(v_arg, '') not in ('padam', 'jaga') then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'ikn' then raise exception 'Menara Lampu ada di IKN.'; end if;
    update game.pasir_state set riak = riak || jsonb_build_object('tedsky_lampu', v_arg), updated_at = now() where player_id = p_pid;
    if v_arg = 'padam' then perform game.ps_retak_add(p_pid, 20); end if;
    perform game.ps_book_grant(p_pid, 'bk_ps_almanak');
    perform game.ps_set(p_pid, 'ps12', 3, jsonb_build_object('tedsky', v_arg));
    perform game.log(p_pid, 'Tedsky muda memberimu Almanak Lampu IKN: catatan jam-jam laut paling gelap.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'jejak12' then
    if s <> 3 or v_era <> 'lampau' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'ikn' then raise exception 'Jejaknya ada di dermaga IKN.'; end if;
    perform game.ps_sdata_set(p_pid, jsonb_build_object('sudyrman', true));
    perform game.ps_kdata_set(p_pid, jsonb_build_object('jejak', jsonb_build_object('slot', v_slot, 'from', 'ikn', 'coret', '[]'::jsonb, 'tutorial', true,
      'kand', '["joungjava", "sudyrman_pelabuhan", "bjorneo"]'::jsonb), 'susul', null));
    perform game.ps_set(p_pid, 'ps12', 4, '{}'::jsonb);
    perform game.log(p_pid, 'Jejak pertama: tiga kemungkinan. Salah satunya pelabuhan di benua yang tak pernah ada di petamu.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'kopi12' then
    if s < 4 or s > 6 or v_era <> 'lampau' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sudyrman_pelabuhan' then raise exception 'Kedai kopi itu ada di Pelabuhan Sudyrman.'; end if;
    if game.ps_sdata(p_pid) -> 'barang' ? 'kopi_pahit' then raise exception 'Kau sudah membawa sekantong Kopi Pahit Sudyrman.'; end if;
    v_cost := game.cfg_num('PasirKopiHarga', 500)::bigint;
    update game.players set gold = gold - v_cost where player_id = p_pid and gold >= v_cost;
    if not found then raise exception 'Emasmu kurang, Kapten.'; end if;
    perform game.ps_barang_add(p_pid, 'kopi_pahit');
    return jsonb_build_object('ok', true);
  elsif p_act = 'nansy12' then
    if s < 4 or s > 6 or v_era <> 'lampau' or coalesce(v_arg, '') <> 'ok' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sudyrman_pelabuhan' then raise exception 'Miss Nansy memancing di karang Pelabuhan Sudyrman.'; end if;
    update game.pasir_state set riak = riak || '{"nansy_buku": true}'::jsonb, updated_at = now() where player_id = p_pid;
    perform game.log(p_pid, 'Miss Nansy menulis namamu di buku pancingnya.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'karto12' then
    if s < 5 or s > 6 or v_era <> 'lampau' or coalesce(v_arg, '') not in ('beri', 'tidak') then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'joungjava' then raise exception 'Mas Karto ada di warung pantai Joungjava.'; end if;
    if (select riak from game.pasir_state where player_id = p_pid) ? 'karto_kopi' then raise exception 'Mas Karto sudah pulang.'; end if;
    if v_arg = 'beri' then
      if not (game.ps_sdata(p_pid) -> 'barang' ? 'kopi_pahit') then raise exception 'Kau tidak membawa Kopi Pahit Sudyrman.'; end if;
      update game.pasir_state set data = jsonb_set(data, '{barang}', coalesce((select jsonb_agg(x) from jsonb_array_elements(data -> 'barang') x where x <> '"kopi_pahit"'), '[]'::jsonb)) where player_id = p_pid;
    end if;
    update game.pasir_state set riak = riak || jsonb_build_object('karto_kopi', v_arg), updated_at = now() where player_id = p_pid;
    return jsonb_build_object('ok', true);
  elsif p_act = 'ulin12' then
    if s < 5 or s > 6 or v_era <> 'lampau' or coalesce(v_arg, '') not in ('beri', 'tidak') then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'bjorneo' then raise exception 'Ulin muda ada di mercusuar Bjorneo.'; end if;
    if (select riak from game.pasir_state where player_id = p_pid) ? 'ulin_teka' then raise exception 'Ulin muda sudah punya teka-tekinya.'; end if;
    update game.pasir_state set riak = riak || jsonb_build_object('ulin_teka', v_arg), updated_at = now() where player_id = p_pid;
    if v_arg = 'beri' then perform game.ps_retak_add(p_pid, 5); end if;
    return jsonb_build_object('ok', true);
  elsif p_act = 'akademi12' then
    if s <> 6 or v_era <> 'lampau' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sudyrman_akademi' then raise exception 'Gerbang Akademi ada di Akademi Laut Sudyrman.'; end if;
    v_cost := game.cfg_num('PasirQ12Hadiah', 120000)::bigint;
    update game.players set gold = gold + v_cost where player_id = p_pid;
    update game.pasir_state set kaca = greatest(kaca, 3), updated_at = now() where player_id = p_pid;
    perform game.ps_sdata_set(p_pid, jsonb_build_object('set_gemilang', true));
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null, 'jejak', null));
    perform game.ps_set(p_pid, 'ps12', 7, '{}'::jsonb, true);
    perform game.log(p_pid, 'Laksamana Tua Brandt membayar ' || v_cost || ' gold untuk perbekalan yang "diantar dengan sangat rapi". Kaca ketiga retak.');
    return jsonb_build_object('ok', true);
  end if;
  return game.ps_act_q13(p_pid, p_act, a);
end $$;

-- ---------------------------------------------------------------------
-- Status untuk klien (sambungan ps_state_more; 0054)
-- ---------------------------------------------------------------------
create or replace function game.ps_state_q13(p_pid uuid) returns jsonb
language sql as $$ select '{}'::jsonb $$;

create or replace function game.ps_kejar_json(p_pid uuid) returns jsonb
language plpgsql as $$
declare k jsonb; v_slot bigint := game.ps_slot(); v_city text := game.current_city(p_pid); v_docked boolean := not game.in_transit(p_pid);
  v_prev text; v_now text; v_j jsonb;
begin
  if not game.ps_kejar_aktif(p_pid) then return null; end if;
  k := game.ps_kdata(p_pid);
  v_prev := game.ps_fz_port(p_pid, v_slot - 1);
  v_now := game.ps_fz_port(p_pid, v_slot);
  v_j := k -> 'jejak';
  return jsonb_build_object(
    'gosip', case when game.ps_susul_ok(p_pid) then game.city_name(v_prev) end,
    'besok', not game.ps_susul_ok(p_pid),
    'baruPergi', v_docked and v_city = v_prev and v_city <> v_now,
    'susul', k -> 'susul' ->> 'state',
    'susulKota', k -> 'susul' ->> 'city',
    'jejak', case when jsonb_typeof(v_j) = 'object' then jsonb_build_object('kand', v_j -> 'kand', 'coret', coalesce(v_j -> 'coret', '[]'::jsonb),
        'from', v_j ->> 'from', 'segar', case when coalesce((v_j ->> 'tutorial')::boolean, false) then coalesce((k ->> 'n')::int, 0) = 0 else (v_j ->> 'slot')::bigint = v_slot end,
        'manifes', coalesce((v_j ->> 'manifes')::boolean, false)) end,
    'n', coalesce((k ->> 'n')::int, 0));
end $$;

-- salinan 0054 (kini volatile: Quest 12 dimulai saat status dibaca)
create or replace function game.ps_state_more(p_pid uuid) returns jsonb
language sql as $$
  select jsonb_build_object('kotaLampau', game.ps_kota_lampau_json(p_pid), 'toko', game.ps_toko_json(p_pid),
    'sudyrman', game.ps_sudyrman_open(p_pid)) || coalesce(game.ps_state_q12(p_pid), '{}'::jsonb)
$$;

create or replace function game.ps_state_q12(p_pid uuid) returns jsonb
language plpgsql as $$
begin
  -- Quest 12 dimulai pada lompatan pertama ke 40 Tahun Lalu
  if game.pasir_era(p_pid) = 'lampau' and game.ps_step(p_pid, 'ps12') = 0 and game.ps_step(p_pid, 'ps11') >= 10 then
    perform game.ps_set(p_pid, 'ps12', 1, '{}'::jsonb);
  end if;
  return jsonb_build_object('q12', game.ps_q_json(p_pid, 'ps12'), 'kejar', game.ps_kejar_json(p_pid))
    || case when game.is_gm(p_pid) and game.ps_kejar_aktif(p_pid) then jsonb_build_object('fzGm', game.ps_fz_port(p_pid, game.ps_slot())) else '{}'::jsonb end
    || coalesce(game.ps_state_q13(p_pid), '{}'::jsonb);
end $$;

-- GM: pindahkan Franziska ke slot berikutnya (geser jam dunia tidak perlu) / reset batas harian
create or replace function game.ps_admin_q13(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language sql as $$ select false $$;
create or replace function game.ps_admin_q12(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language plpgsql as $$
begin
  if p_act = 'harian' then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('hari', null));
    return true;
  end if;
  return game.ps_admin_q13(p_pid, p_act, p_arg, p_arg2);
end $$;
