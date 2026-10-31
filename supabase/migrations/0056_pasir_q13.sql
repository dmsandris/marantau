-- =====================================================================
-- 0056 — Pasir · Batch 6: Quest 13 "Laksamana yang Tak Pernah Tenggelam" (Tide v41)
-- Skenario: claude/SKENARIO-Saga3-Dark.md bagian 11.
--
-- QUEST 13 (quest_id 'ps13') — dimulai saat Quest 12 tamat dan pemain kembali ke Zaman Keadilan
--   1  Undangan Pesta Keadilan: 'undangan13' (misi gubernur selesai di 3 pulau awal sejak quest dimulai)
--      atau 'palsu13' ok|gagal (Mata Syahbandar di IKN; gagal = diusir, coba lagi besok)
--   2  Pesta Keadilan di IKN: Mata Pesta -> Laksamana Agung Satnislaus -> balkon -> 'pesta13' (Surat Franzi #2)
--   3  Uda Gala berseragam putih di Skitraw: 'gala13' (bertemu, Chafik) -> 'gasing13' (Adu Gasing)
--      -> 'galapilih13' sabun|cerita (riak gala_putih belot|peta; barang peta_armada)
--   4  Pengejaran lintas zaman, 3 penyusulan berurutan (maks. 1 per hari WIB), memakai mesin 0055:
--        a. Lembah Seribu Layar (40 Tahun Lalu)  · Jaring Angin      -> Surat #3, kaca 4
--        b. Bjorneo (Zaman Keadilan)             · Olah Jejak         -> Surat #4, kaca 5
--        c. Akademi Laut Sudyrman (40 Tahun Lalu)· Mata Pesta malam   -> Surat #5, kaca 6
--      Janji Putih makin kuat; perisai pasir (damage x0.35) kecuali Jangkar Waktu mutu Baik+ atau efek fy_rantai.
--   5  Arsip Akademi (twist tujuh kaca): 'arsip13' di Akademi Laut Sudyrman (40 Tahun Lalu)
--   6  Malam Pasang Besar: 'pasang13' evakuasi|tonton di Pelabuhan Sudyrman (40 Tahun Lalu)
--      evakuasi: 3x 'angkut13' (100 Beras dari palka) lalu merapat di pulau Mare Nusantara lampau; Retak +10 per pelayaran
--      'tebing13' di tebing Akademi -> selesai (180.000 gold, riak sudyrman, set Kedai Benang Merah terbuka)
--   7  Selesai
--
-- ⚠️ SALINAN versi 0055 + Quest 13: ps_fz_port, ps_kejar_q13, ps_on_arrive_q13, ps_boss_encounter, ps_boss_won_q13,
--    ps_act_q13, ps_state_q13, ps_admin_q13. Kait Quest 14: ps_act_q14, ps_state_q14. Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PasirQ13Hadiah', '180000'),
  ('PasirQ13Beras', '100'),
  ('PasirQ13Reputasi', '3')
on conflict (key) do nothing;

create or replace function game.ps_pulau_awal() returns text[]
language sql immutable as $$ select array['sunda_empire', 'joungjava', 'bjorneo', 'skitraw', 'toogood', 'ikn'] $$;

-- Tujuan penyusulan Quest 13 ke-n (0..2)
create or replace function game.ps13_tuju(p_n int) returns jsonb
language sql immutable as $$
  select case p_n
    when 0 then '{"kota": "sudyrman_lembah", "era": "lampau", "game": "angin"}'::jsonb
    when 1 then '{"kota": "bjorneo", "era": "keadilan", "game": "jejak"}'::jsonb
    when 2 then '{"kota": "sudyrman_akademi", "era": "lampau", "game": "pesta"}'::jsonb
  end
$$;
create or replace function game.ps13_n(p_pid uuid) returns int
language sql stable as $$ select coalesce((game.ps_data(p_pid, 'ps13') ->> 'n')::int, 0) $$;

-- ---------------------------------------------------------------------
-- Mesin pengejaran: Quest 13 memakai tujuan tetap per penyusulan
-- ---------------------------------------------------------------------
create or replace function game.ps_kejar_q13(p_pid uuid) returns boolean
language sql stable as $$ select game.ps_step(p_pid, 'ps13') = 4 and game.ps13_n(p_pid) < 3 $$;

-- salinan 0055 + Quest 13 lebih dulu
create or replace function game.ps_fz_port(p_pid uuid, p_slot bigint) returns text
language plpgsql stable as $$
declare pool text[]; n int; i int; j int; t int; v jsonb;
begin
  if game.ps_kejar_q13(p_pid) then
    v := game.ps13_tuju(game.ps13_n(p_pid));
    return case when game.pasir_era(p_pid) = (v ->> 'era') then v ->> 'kota' end;
  end if;
  pool := game.ps_fz_pool(p_pid); n := cardinality(pool);
  if n = 0 then return null; end if;
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

-- salinan 0055 + Quest 13 (Janji Putih makin kuat, perisai pasir)
create or replace function game.ps_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql as $$
declare k jsonb := game.ps_kdata(p_pid); e jsonb; v_n int; v_tembus boolean;
begin
  if (k -> 'susul' ->> 'state') = 'kabur' and game.ps_kejar_aktif(p_pid) then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', (k -> 'susul') || '{"state": "laut"}'::jsonb));
    if game.ps_kejar_q13(p_pid) then
      v_n := game.ps13_n(p_pid);
      e := game.ps_janji_enc(p_pid, 2 + v_n);
      v_tembus := game.lt_grade_rank(game.ps_jangkar(p_pid)) >= 2 or coalesce(game.has_effect(p_pid, 'fy_rantai'), false);
      return e || jsonb_build_object('q13', v_n + 1, 'perisai', not v_tembus,
        'bossTitle', case when v_tembus then 'Perisai pasir berputar di lambungnya, tapi Jangkar Waktumu menembusnya'
                          else 'Perisai pasir berputar di lambungnya. Tembakanmu tertelan pasir' end,
        'dmgTaken', case when v_tembus then 1 else 0.35 end);
    end if;
    return game.ps_janji_enc(p_pid, case when game.ps_step(p_pid, 'ps12') = 4 then 0 else 1 end);
  end if;
  return null;
end $$;

create or replace function game.ps_boss_won_q13(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_n int; v_surat int;
begin
  if not game.ps_kejar_q13(p_pid) then return null; end if;
  v_n := game.ps13_n(p_pid) + 1;
  v_surat := v_n + 2;
  update game.pasir_state set kaca = greatest(kaca, 3 + v_n), updated_at = now() where player_id = p_pid;
  perform game.ps_set(p_pid, 'ps13', case when v_n >= 3 then 5 else 4 end,
    jsonb_build_object('n', v_n, 'surat' || v_surat, true));
  perform game.log(p_pid, 'Janji Putih menembus pusaran pasir ke zaman lain. Kaca ke-' || (3 + v_n) || ' retak. Sepucuk surat lama tertinggal di geladakmu.');
  return jsonb_build_object('gold', 0, 'message',
    case v_n when 1 then 'Janji Putih menembus pusaran pasir dan lenyap ke zaman lain. Kaca keempat retak. Sepucuk surat lama tertinggal di geladakmu.'
             when 2 then 'Janji Putih lenyap lagi ke zaman lain. Kaca kelima retak. Surat lain melayang jatuh dari layarnya.'
             else 'Janji Putih menghilang. Kaca keenam retak. Di Papan Benang, tinggal satu kaca. Surat terakhir tertinggal: tulisan seorang kadet perempuan.' end);
end $$;

-- ---------------------------------------------------------------------
-- Kedatangan: evakuasi Malam Pasang Besar
-- ---------------------------------------------------------------------
create or replace function game.ps_on_arrive_q13(p_pid uuid, p_city text) returns void
language plpgsql as $$
declare d jsonb; v_e int;
begin
  if game.ps_step(p_pid, 'ps13') <> 6 or game.pasir_era(p_pid) <> 'lampau' then return; end if;
  d := game.ps_data(p_pid, 'ps13');
  if coalesce((d ->> 'muat')::boolean, false) and p_city = any (game.ps_pulau_awal()) then
    v_e := coalesce((d ->> 'evak')::int, 0) + 1;
    perform game.ps_set(p_pid, 'ps13', 6, jsonb_build_object('muat', false, 'evak', v_e));
    perform game.log(p_pid, 'Warga Pelabuhan Sudyrman turun di ' || game.city_name(p_city) || '. Pelayaran evakuasi ke-' || v_e || ' dari 3.');
    perform game.ps_retak_add(p_pid, 10);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Aksi Quest 13 (sambungan ps_act_q12; 0055)
-- ---------------------------------------------------------------------
create or replace function game.ps_act_q14(p_pid uuid, p_act text, a jsonb) returns jsonb
language sql as $$ select null::jsonb $$;

create or replace function game.ps_act_q13(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps13'); d jsonb := game.ps_data(p_pid, 'ps13'); v_arg text := game.arg(a, 1);
  v_city text := game.current_city(p_pid); v_docked boolean := not game.in_transit(p_pid); v_era text := game.pasir_era(p_pid);
  v_n int; v_beras int := game.cfg_num('PasirQ13Beras', 100)::int; v_gold bigint;
begin
  if p_act = 'undangan13' then
    if s <> 1 then raise exception 'Aksi tidak dikenal.'; end if;
    select count(distinct m.city_id) into v_n from game.player_missions m
     where m.player_id = p_pid and m.status = 'completed' and m.city_id = any (game.ps_pulau_awal())
       and m.created_at >= to_timestamp(coalesce((d ->> 'mulai_t')::bigint, 0) / 1000.0);
    if v_n < game.cfg_num('PasirQ13Reputasi', 3)::int then
      raise exception 'Namamu belum cukup dikenal. Selesaikan misi gubernur di % pulau lagi.', game.cfg_num('PasirQ13Reputasi', 3)::int - v_n;
    end if;
    perform game.ps_set(p_pid, 'ps13', 2, '{"undangan": "reputasi"}'::jsonb);
    perform game.log(p_pid, 'Undangan Pesta Keadilan tiba, bersegel lilin putih: "Untuk kapten yang dikenal di tiga pulau."');
    return jsonb_build_object('ok', true);
  elsif p_act = 'palsu13' then
    if s <> 1 or v_era <> 'keadilan' or coalesce(v_arg, '') not in ('ok', 'gagal') then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'ikn' then raise exception 'Kantor Syahbandar yang mencetak undangan ada di IKN.'; end if;
    if coalesce(d ->> 'palsu_hari', '') = game.ps_hari() then raise exception 'Syahbandar IKN masih mengingat wajahmu. Coba lagi besok.'; end if;
    if v_arg = 'gagal' then
      perform game.ps_set(p_pid, 'ps13', 1, jsonb_build_object('palsu_hari', game.ps_hari()));
      return jsonb_build_object('ok', false);
    end if;
    perform game.ps_set(p_pid, 'ps13', 2, '{"undangan": "palsu"}'::jsonb);
    perform game.log(p_pid, 'Sehelai undangan Pesta Keadilan, cap Syahbandar IKN-nya nyaris sempurna.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'pesta13' then
    if s <> 2 or v_era <> 'keadilan' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'ikn' then raise exception 'Pesta Keadilan diadakan di IKN.'; end if;
    perform game.ps_set(p_pid, 'ps13', 3, '{"surat2": true}'::jsonb);
    perform game.log(p_pid, 'Pesta Keadilan: Laksamana Agung Satnislaus tidak mengenali perempuan bergaun putih itu. Ia kabur lewat balkon. Sepucuk surat tertinggal.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'gala13' then
    if s <> 3 or v_era <> 'keadilan' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'skitraw' then raise exception 'Uda Gala turun ke darat di Skitraw.'; end if;
    perform game.ps_set(p_pid, 'ps13', 3, '{"temu": true}'::jsonb);
    return jsonb_build_object('ok', true);
  elsif p_act = 'gasing13' then
    if s <> 3 or not coalesce((d ->> 'temu')::boolean, false) or coalesce(v_arg, '') <> 'ok' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'skitraw' then raise exception 'Uda Gala ada di Skitraw.'; end if;
    perform game.ps_set(p_pid, 'ps13', 3, '{"gasing": true}'::jsonb);
    return jsonb_build_object('ok', true);
  elsif p_act = 'galapilih13' then
    if s <> 3 or not coalesce((d ->> 'gasing')::boolean, false) or coalesce(v_arg, '') not in ('sabun', 'cerita') then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'skitraw' then raise exception 'Uda Gala ada di Skitraw.'; end if;
    if v_arg = 'sabun' then
      if not coalesce(game.ps_sdata(p_pid) -> 'barang' ? 'sabun_gala', false) then raise exception 'Kau tidak membawa Sabun Kelapa Buatan Gala Muda.'; end if;
      update game.pasir_state set data = jsonb_set(data, '{barang}', coalesce((select jsonb_agg(x) from jsonb_array_elements(data -> 'barang') x where x <> '"sabun_gala"'), '[]'::jsonb)) where player_id = p_pid;
      update game.pasir_state set riak = riak || '{"gala_putih": "belot"}'::jsonb, updated_at = now() where player_id = p_pid;
      perform game.log(p_pid, 'Uda Gala mencium sabun kelapa itu lama sekali. "Ini resep ambo waktu muda." Ia melepas lencana Armada Putih.');
    else
      perform game.ps_barang_add(p_pid, 'peta_armada');
      update game.pasir_state set riak = riak || '{"gala_putih": "peta"}'::jsonb, updated_at = now() where player_id = p_pid;
      perform game.log(p_pid, 'Uda Gala tidak percaya ceritamu tentang Gaul-Wash, tapi ia menyelipkan Peta Rute Armada Putih ke tanganmu.');
    end if;
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null, 'jejak', null, 'hari', null));
    perform game.ps_set(p_pid, 'ps13', 4, jsonb_build_object('gala', v_arg, 'n', 0));
    return jsonb_build_object('ok', true);
  elsif p_act = 'arsip13' then
    if s <> 5 or v_era <> 'lampau' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sudyrman_akademi' then raise exception 'Arsip itu ada di Akademi Laut Sudyrman.'; end if;
    perform game.ps_book_grant(p_pid, 'bk_ps_kadet');
    perform game.ps_set(p_pid, 'ps13', 6, '{"arsip": true}'::jsonb);
    perform game.log(p_pid, 'Tujuh kaca, tujuh percobaan. Ia tidak pernah mencoba berhenti.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'pasang13' then
    if s <> 6 or v_era <> 'lampau' or coalesce(v_arg, '') not in ('evakuasi', 'tonton') or d ? 'pasang' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sudyrman_pelabuhan' then raise exception 'Malam Pasang Besar dimulai di Pelabuhan Sudyrman.'; end if;
    perform game.ps_set(p_pid, 'ps13', 6, jsonb_build_object('pasang', v_arg, 'evak', 0, 'muat', false));
    return jsonb_build_object('ok', true);
  elsif p_act = 'angkut13' then
    if s <> 6 or v_era <> 'lampau' or (d ->> 'pasang') is distinct from 'evakuasi' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sudyrman_pelabuhan' then raise exception 'Warga menunggu di dermaga Pelabuhan Sudyrman.'; end if;
    if coalesce((d ->> 'muat')::boolean, false) then raise exception 'Kapalmu sudah penuh warga. Antar mereka dulu ke pulau Mare Nusantara.'; end if;
    if coalesce((d ->> 'evak')::int, 0) >= 3 then raise exception 'Semua warga sudah diantar.'; end if;
    if game.item_qty(p_pid, 'beras') < v_beras then raise exception 'Bawa % Beras di palka untuk bekal warga di laut.', v_beras; end if;
    perform game.adjust_inventory(p_pid, 'beras', -v_beras);
    perform game.ps_set(p_pid, 'ps13', 6, '{"muat": true}'::jsonb);
    perform game.log(p_pid, 'Warga Pelabuhan Sudyrman naik ke kapalmu membawa buntelan. ' || v_beras || ' Beras dibagikan di geladak.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'tebing13' then
    if s <> 6 or v_era <> 'lampau' then raise exception 'Aksi tidak dikenal.'; end if;
    if not (coalesce(d ->> 'pasang', '') = 'tonton' or (coalesce(d ->> 'pasang', '') = 'evakuasi' and coalesce((d ->> 'evak')::int, 0) >= 3)) then
      raise exception 'Malam Pasang Besar belum tiba.';
    end if;
    if not v_docked or v_city <> 'sudyrman_akademi' then raise exception 'Tebing itu ada di Akademi Laut Sudyrman.'; end if;
    v_gold := game.cfg_num('PasirQ13Hadiah', 180000)::bigint;
    update game.players set gold = gold + v_gold where player_id = p_pid;
    update game.pasir_state set riak = riak || jsonb_build_object('sudyrman', d ->> 'pasang'), updated_at = now() where player_id = p_pid;
    perform game.ps_sdata_set(p_pid, jsonb_build_object('set_benang', true));
    perform game.ps_book_grant(p_pid, 'bk_ps_surat');
    perform game.ps_set(p_pid, 'ps13', 7, '{}'::jsonb, true);
    perform game.log(p_pid, 'Benua Sudyrman tenggelam. Rampasan Janji Putih dari tiga penyusulan: ' || v_gold || ' gold. Kaca ketujuh menunggu.');
    return jsonb_build_object('ok', true, 'gold', v_gold);
  end if;
  return game.ps_act_q14(p_pid, p_act, a);
end $$;

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------
create or replace function game.ps_state_q14(p_pid uuid) returns jsonb
language sql as $$ select '{}'::jsonb $$;

create or replace function game.ps_state_q13(p_pid uuid) returns jsonb
language plpgsql as $$
declare s int; d jsonb; v jsonb; v_rep int := 0;
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
  end if;
  if game.ps_kejar_q13(p_pid) then
    v := game.ps13_tuju(game.ps13_n(p_pid));
    v := v || jsonb_build_object('nama', game.city_name(v ->> 'kota'), 'susulOk', game.ps_susul_ok(p_pid));
  end if;
  return jsonb_build_object('q13', game.ps_q_json(p_pid, 'ps13') || jsonb_build_object('rep', v_rep,
      'repPerlu', game.cfg_num('PasirQ13Reputasi', 3)::int, 'palsuBesok', coalesce(d ->> 'palsu_hari', '') = game.ps_hari(),
      'beras', game.cfg_num('PasirQ13Beras', 100)::int), 'tuju13', v)
    || coalesce(game.ps_state_q14(p_pid), '{}'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- GM
-- ---------------------------------------------------------------------
create or replace function game.ps_admin_q14(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language sql as $$ select false $$;
create or replace function game.ps_admin_q13(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language plpgsql as $$
begin
  if p_act = 'susul13' then
    -- lompat ke penyusulan ke-n (0..2) Quest 13
    perform game.ps_set(p_pid, 'ps13', 4, jsonb_build_object('n', greatest(0, least(2, coalesce(nullif(p_arg, '')::int, 0)))));
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null, 'hari', null));
    return true;
  end if;
  return game.ps_admin_q14(p_pid, p_act, p_arg, p_arg2);
end $$;
