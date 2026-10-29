-- =====================================================================
-- 0042 — Pasir · Batch 3: Quest 11 "Kapal yang Tak Pernah Terdampar" (Tide v41)
-- Skenario: claude/SKENARIO-Saga3-Dark.md bagian 6.5, 6.9, 9, 15.
--
-- Langkah (game.player_quests, quest_id = 'ps11'):
--   1  Surat Paman Ocid (Q10 selesai + gold >= PasirQ11Gold). Temui di Pustaka Sunda -> 'mulai11'
--   2  Paman Ocid membuka jalan ke em pe'er de pe'er (satu-satunya). Bayar biaya Jangkar -> 'bayar11'
--   3  Selam Mutiara di perairan dalam em pe'er de pe'er: roda gigi Jam Agung -> 'selam11'
--   4  Tempa Jangkar di dok kecil em pe'er de pe'er -> 'tempa11' (Pusaka Jangkar Waktu, mutu)
--   5  Jam Agung: Arus Pusaran (Celah Waktu) -> 'lompat' badai (era badai, Skitraw)
--   6  Tahun Badai Besar: tambal perahu Gala muda -> 'tambal11'
--   7  Pilihan riak gala_muda -> 'gala11' cerita|bantu
--   8  Kapal hantu: Jaring Angin -> 'kejar11' (kaca kedua retak, kembali ke em pe'er de pe'er)
--   9  Paman Ocid menjelaskan hukum 1 & 4 -> 'paham11' (hadiah gold)
--  10  Selesai
--
-- Mekanik umum (dipakai batch berikutnya):
--   * Pusaka Kapal (game.pv_pusaka): milik pemain, 3 slot, bisa dilepas/dipasang; efek lewat has_effect('px_<id>').
--   * Lompatan waktu hanya dari Jam Agung em pe'er de pe'er, butuh Jangkar Waktu terpasang (ps_lompat / ps_tarik).
--   * Retak Waktu 0..100: naik lewat ps_retak_add; turun tiap hari game di Zaman Keadilan sesuai mutu Jangkar;
--     100 = terlempar ke Zaman Keadilan + Jangkar didinginkan 1 hari nyata.
--   * Era badai/lampau/pusaran: pasar & toko tutup (ww_market_closed), tidak bisa berlayar bebas di badai/pusaran.
--
-- ⚠️ has_effect, ww_market_closed, ps_on_sail, ps_on_arrive, pasir_state, pasir_admin, api_pasir adalah SALINAN
--    versi terakhir + tambahan. Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PasirQ11Gold', '100000'),
  ('PasirJangkarBiaya', '100000'),
  ('PasirQ11Hadiah', '100000'),
  ('PasirRetakTurunSempurna', '10'),
  ('PasirRetakTurunBaik', '6'),
  ('PasirRetakTurunKasar', '3'),
  ('PasirJedaLompatHari', '1'),
  ('PasirSelamJedaMenit', '20')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Pusaka Kapal
-- ---------------------------------------------------------------------
create table if not exists game.pv_pusaka (
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  pusaka_id  text not null,
  mutu       text,
  slot       int check (slot between 1 and 3),
  got_at     timestamptz not null default now(),
  primary key (player_id, pusaka_id)
);
create unique index if not exists pv_pusaka_slot_uq on game.pv_pusaka (player_id, slot) where slot is not null;
alter table game.pv_pusaka enable row level security;

create or replace function game.ps_pusaka_katalog() returns jsonb
language sql immutable as $$
  select '[
    {"id": "jangkar",  "name": "Jangkar Waktu",                 "desc": "Menahan kapal di waktunya. Syarat melompat dari Jam Agung; mutunya menentukan laju turunnya Retak Waktu.", "src": "quest"},
    {"id": "layar_garuda", "name": "Layar Sutra Garuda",        "desc": "+10 kecepatan.", "src": "dok_garuda"},
    {"id": "lunas_ulin",   "name": "Lunas Ulin Purba",          "desc": "+60 kondisi maksimal.", "src": "lembah"},
    {"id": "kemudi_ikn",   "name": "Kemudi Perunggu IKN",       "desc": "+10% peluang kabur & menghindar.", "src": "dok_garuda"},
    {"id": "meriam_naga",  "name": "Meriam Naga Menara",        "desc": "+20 Combat saat malam.", "src": "dok_garuda"},
    {"id": "haluan_kadet", "name": "Haluan Kadet Sudyrman",     "desc": "+15% kerusakan ke perisai.", "src": "lembah"},
    {"id": "lambung_garam","name": "Lambung Berlapis Garam Sudyrman", "desc": "Kebal satu tarikan arus per pertempuran.", "src": "lembah"}
  ]'::jsonb
$$;

create or replace function game.ps_pusaka_json(p_pid uuid) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.pusaka_id, 'mutu', p.mutu, 'slot', p.slot,
      'name', coalesce(k ->> 'name', p.pusaka_id), 'desc', coalesce(k ->> 'desc', '')) order by coalesce(p.slot, 9), p.got_at), '[]'::jsonb)
  from game.pv_pusaka p
  left join lateral (select x from jsonb_array_elements(game.ps_pusaka_katalog()) x where x ->> 'id' = p.pusaka_id) kk(k) on true
  where p.player_id = p_pid
$$;

-- mutu Jangkar Waktu yang TERPASANG (null = tidak terpasang)
create or replace function game.ps_jangkar(p_pid uuid) returns text
language sql stable as $$
  select mutu from game.pv_pusaka where player_id = p_pid and pusaka_id = 'jangkar' and slot is not null
$$;

-- salinan 0004 + Pusaka terpasang ('px_<id>')
create or replace function game.has_effect(p_pid uuid, p_effect text) returns boolean
language plpgsql stable as $$
begin
  if coalesce(p_effect, '') like 'px\_%' then
    return exists (select 1 from game.pv_pusaka where player_id = p_pid and slot is not null and 'px_' || pusaka_id = p_effect);
  end if;
  return game.book_has_effect(p_pid, p_effect) or game.artifact_has_effect(p_pid, p_effect);
end $$;

-- ---------------------------------------------------------------------
-- Pasar & toko masa lalu tutup (salinan 0019 + era)
-- ---------------------------------------------------------------------
create or replace function game.ww_market_closed(p_pid uuid) returns boolean
language sql stable as $$
  select game.ww_step(p_pid) between 1 and 3 or game.pasir_era(p_pid) in ('badai', 'lampau', 'pusaran')
$$;

-- ---------------------------------------------------------------------
-- Pembantu umum
-- ---------------------------------------------------------------------
create or replace function game.ps_lokasi(p_pid uuid, p_city text) returns void
language sql as $$
  update game.player_location set city_id = p_city, destination_city_id = null, depart_at = null, arrive_at = null,
    pending_encounter = null where player_id = p_pid
$$;

create or replace function game.ps_sdata(p_pid uuid) returns jsonb
language sql stable as $$ select coalesce((select data from game.pasir_state where player_id = p_pid), '{}'::jsonb) $$;

create or replace function game.ps_sdata_set(p_pid uuid, p_data jsonb) returns void
language plpgsql as $$
begin
  perform game.pasir_ensure(p_pid);
  update game.pasir_state set data = data || coalesce(p_data, '{}'::jsonb), updated_at = now() where player_id = p_pid;
end $$;

create or replace function game.ps_barang_add(p_pid uuid, p_item text) returns void
language plpgsql as $$
declare v jsonb := coalesce(game.ps_sdata(p_pid) -> 'barang', '[]'::jsonb);
begin
  if jsonb_typeof(v) <> 'array' then v := '[]'::jsonb; end if;
  if not v ? p_item then perform game.ps_sdata_set(p_pid, jsonb_build_object('barang', v || to_jsonb(p_item))); end if;
end $$;

create or replace function game.ps_buka_add(p_pid uuid, p_city text) returns void
language plpgsql as $$
declare v jsonb := game.pasir_buka(p_pid);
begin
  if not v ? p_city then perform game.ps_sdata_set(p_pid, jsonb_build_object('buka', v || to_jsonb(p_city))); end if;
end $$;

-- ---------------------------------------------------------------------
-- Retak Waktu
-- ---------------------------------------------------------------------
create or replace function game.ps_retak_rate(p_pid uuid) returns numeric
language sql stable as $$
  select case game.ps_jangkar(p_pid)
    when 'sempurna' then game.cfg_num('PasirRetakTurunSempurna', 10)
    when 'baik' then game.cfg_num('PasirRetakTurunBaik', 6)
    when 'kasar' then game.cfg_num('PasirRetakTurunKasar', 3)
    else 2 end
$$;

-- Turun perlahan tiap hari game selama di Zaman Keadilan (dihitung saat state dibaca)
create or replace function game.ps_retak_tick(p_pid uuid) returns void
language plpgsql as $$
declare r game.pasir_state; v_now bigint := game.now_ms(); v_t bigint; v_days numeric; v_drop int;
begin
  select * into r from game.pasir_state where player_id = p_pid for update;
  if not found then return; end if;
  v_t := nullif(r.data ->> 'retak_t', '')::bigint;
  if v_t is null then
    update game.pasir_state set data = data || jsonb_build_object('retak_t', v_now) where player_id = p_pid;
    return;
  end if;
  if r.era <> 'keadilan' or r.retak <= 0 then return; end if;
  v_days := (v_now - v_t)::numeric / greatest(1, game.ww_day_ms());
  v_drop := floor(v_days * game.ps_retak_rate(p_pid))::int;
  if v_drop <= 0 then return; end if;
  update game.pasir_state set retak = greatest(0, retak - v_drop),
    data = data || jsonb_build_object('retak_t', v_t + ceil(v_drop / game.ps_retak_rate(p_pid) * game.ww_day_ms())::bigint)
   where player_id = p_pid;
end $$;

-- Tambah Retak. Mencapai 100 = terlempar ke Zaman Keadilan (em pe'er de pe'er), Jangkar didinginkan 1 hari nyata.
create or replace function game.ps_retak_add(p_pid uuid, p_n int) returns boolean
language plpgsql as $$
declare v int;
begin
  perform game.pasir_ensure(p_pid);
  update game.pasir_state set retak = least(100, greatest(0, retak + p_n)), updated_at = now()
   where player_id = p_pid returning retak into v;
  if v >= 100 and game.pasir_era(p_pid) in ('lampau', 'badai') then
    update game.pasir_state set era = 'keadilan', retak = 70,
      data = data || jsonb_build_object('jangkar_siap', game.now_ms() + 86400000, 'retak_t', game.now_ms(), 'terlempar', game.now_ms())
     where player_id = p_pid;
    perform game.ps_lokasi(p_pid, 'empeer_depeer');
    perform game.log(p_pid, 'Kaca waktu bergetar terlalu keras. Kau terlempar kembali ke Jam Agung. Jangkar Waktu butuh sehari penuh untuk dingin.');
    return true;
  end if;
  return false;
end $$;

-- ---------------------------------------------------------------------
-- Lompatan waktu (hanya dari Jam Agung em pe'er de pe'er)
-- ---------------------------------------------------------------------
-- Zaman yang bisa dipilih di ruang Jam Agung (batch berikutnya menambah 'lampau', 'pusaran')
create or replace function game.ps_zaman_opsi(p_pid uuid) returns text[]
language sql stable as $$
  select case when game.ps_step(p_pid, 'ps11') = 5 then array['badai'] else array[]::text[] end
$$;

create or replace function game.ps_zaman_kota(p_era text) returns text
language sql immutable as $$
  select case p_era when 'badai' then 'skitraw' when 'lampau' then 'ikn' when 'pusaran' then 'empeer_depeer' else 'empeer_depeer' end
$$;

create or replace function game.ps_lompat(p_pid uuid, p_era text) returns void
language plpgsql as $$
declare d jsonb := game.ps_sdata(p_pid); v_siap bigint := nullif(d ->> 'jangkar_siap', '')::bigint; v_seen jsonb;
begin
  if game.pasir_era(p_pid) <> 'keadilan' then raise exception 'Jam Agung hanya bisa diputar dari zamanmu sendiri.'; end if;
  if game.in_transit(p_pid) or game.current_city(p_pid) <> 'empeer_depeer' then raise exception 'Jam Agung ada di Pulau em pe''er de pe''er.'; end if;
  if game.ps_jangkar(p_pid) is null then raise exception 'Pasang Jangkar Waktu dulu, Kapten. Tanpa jangkar, kapalmu akan hanyut di antara zaman.'; end if;
  if v_siap is not null and game.now_ms() < v_siap then raise exception 'Jangkar Waktu masih dingin. Tunggu sebentar lagi.'; end if;
  if not (p_era = any (game.ps_zaman_opsi(p_pid))) then raise exception 'Jarum Jam Agung tidak mau menunjuk ke sana.'; end if;
  v_seen := coalesce(d -> 'zaman_seen', '[]'::jsonb);
  update game.pasir_state set era = p_era, updated_at = now(),
    data = data || jsonb_build_object('lompat_t', game.now_ms(), 'zaman_seen', case when v_seen ? p_era then v_seen else v_seen || to_jsonb(p_era) end)
      || case when v_seen ? p_era then jsonb_build_object('jangkar_siap', game.now_ms() + (game.cfg_num('PasirJedaLompatHari', 1) * game.ww_day_ms())::bigint) else '{}'::jsonb end
   where player_id = p_pid;
  perform game.ps_lokasi(p_pid, game.ps_zaman_kota(p_era));
end $$;

-- Tarik Jangkar: kembali ke Zaman Keadilan dari dermaga mana pun di masa lalu (mendarat di em pe'er de pe'er)
create or replace function game.ps_tarik(p_pid uuid) returns void
language plpgsql as $$
begin
  if game.pasir_era(p_pid) <> 'lampau' then raise exception 'Jangkar Waktu tidak bergerak.'; end if;
  if game.in_transit(p_pid) then raise exception 'Merapat dulu, Kapten.'; end if;
  update game.pasir_state set era = 'keadilan', updated_at = now(), data = data || jsonb_build_object('retak_t', game.now_ms()) where player_id = p_pid;
  perform game.ps_lokasi(p_pid, 'empeer_depeer');
end $$;

-- ---------------------------------------------------------------------
-- Pemicu Quest 11: surat Paman Ocid
-- ---------------------------------------------------------------------
create or replace function game.ps11_try_start(p_pid uuid) returns void
language plpgsql as $$
begin
  if game.ps_step(p_pid, 'ps11') > 0 or game.ps_step(p_pid, 'ps10') < 11 then return; end if;
  if coalesce((select gold from game.players where player_id = p_pid), 0) < game.cfg_num('PasirQ11Gold', 100000) then return; end if;
  perform game.ps_set(p_pid, 'ps11', 1, jsonb_build_object('surat', game.now_ms()));
  perform game.log(p_pid, 'Surat dari Paman Ocid: "Aku sudah menemukan jalan pulang ke pulauku. Temui aku di Pustaka Sunda Empire. Bawa modalmu."');
end $$;

-- ---------------------------------------------------------------------
-- Kait berlayar & tiba (salinan 0041 + Q11 & era)
-- ---------------------------------------------------------------------
create or replace function game.ps_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps10'); v_era text := game.pasir_era(p_pid);
begin
  if v_era = 'badai' then raise exception 'Malam begini tak ada yang berlayar, Kapten. Kecuali orang gila.'; end if;
  if v_era = 'pusaran' then raise exception 'Tidak ada jalan keluar dari pusaran ini selain ke depan.'; end if;
  if s = 5 and p_origin = 'empeer_depeer' then
    raise exception 'Lonceng Jam Agung berdentang sumbang di puncak bukit. Burung-burung terbang ke arah yang salah.';
  end if;
  if s = 6 then raise exception 'Jam Agung masih berdentang. Kau belum boleh pergi.'; end if;
  if s = 2 and p_dest = 'empeer_depeer' then perform game.ps_set(p_pid, 'ps10', 3, '{}'::jsonb); end if;
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
end $$;

-- Kait untuk batch berikutnya: aksi & status tambahan (diganti 0043+; null/{} = tidak ada)
create or replace function game.ps_act_more(p_pid uuid, p_act text, a jsonb) returns jsonb
language sql as $$ select null::jsonb $$;
create or replace function game.ps_state_more(p_pid uuid) returns jsonb
language sql as $$ select '{}'::jsonb $$;
create or replace function game.ps_admin_more(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language sql as $$ select false $$;

-- ---------------------------------------------------------------------
-- Aksi Quest 11 + aksi umum (Pusaka, lompat, tarik). null = bukan aksi di sini.
-- ---------------------------------------------------------------------
create or replace function game.ps_act_ext(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps11'); d jsonb := game.ps_data(p_pid, 'ps11');
  v_arg text := game.arg(a, 1); v_arg2 text := game.arg(a, 2); v_city text := game.current_city(p_pid);
  v_docked boolean := not game.in_transit(p_pid); v_cost bigint; v_score int; v_dur int; v_grade text; v_slot int; v_now bigint := game.now_ms();
  v_rest bigint; v_n int;
begin
  -- ===== umum: Pusaka =====
  if p_act = 'pasang' then
    if not v_docked then raise exception 'Merapat dulu untuk memasang Pusaka.'; end if;
    v_slot := nullif(v_arg2, '')::int;
    if v_slot is null or v_slot not between 1 and 3 then raise exception 'Slot Pusaka 1 sampai 3.'; end if;
    if not exists (select 1 from game.pv_pusaka where player_id = p_pid and pusaka_id = v_arg) then raise exception 'Pusaka itu bukan milikmu.'; end if;
    update game.pv_pusaka set slot = null where player_id = p_pid and (slot = v_slot or pusaka_id = v_arg);
    update game.pv_pusaka set slot = v_slot where player_id = p_pid and pusaka_id = v_arg;
    return jsonb_build_object('ok', true);
  elsif p_act = 'lepas' then
    if not v_docked then raise exception 'Merapat dulu untuk melepas Pusaka.'; end if;
    if game.pasir_era(p_pid) in ('badai', 'lampau', 'pusaran') and v_arg = 'jangkar' then raise exception 'Melepas Jangkar Waktu di zaman ini? Kau tidak akan pernah pulang.'; end if;
    update game.pv_pusaka set slot = null where player_id = p_pid and pusaka_id = v_arg;
    return jsonb_build_object('ok', true);

  -- ===== umum: lompatan =====
  elsif p_act = 'lompat' then
    perform game.ps_lompat(p_pid, lower(coalesce(v_arg, '')));
    if lower(v_arg) = 'badai' and s = 5 then
      perform game.ps_set(p_pid, 'ps11', 6, '{}'::jsonb);
      perform game.log(p_pid, 'Jam Agung berdetak sekali. Kapalmu jatuh ke belakang, ke malam Tahun Badai Besar.');
    end if;
    return jsonb_build_object('ok', true);
  elsif p_act = 'tarik' then
    perform game.ps_tarik(p_pid);
    return jsonb_build_object('ok', true);
  end if;

  -- ===== Quest 11 =====
  if p_act = 'mulai11' then
    if s <> 1 then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sunda_empire' then raise exception 'Paman Ocid menunggu di Pustaka Sunda Empire.'; end if;
    perform game.ps_buka_add(p_pid, 'empeer_depeer');
    perform game.ps_set(p_pid, 'ps11', 2, jsonb_build_object('mulai', v_now));
    perform game.log(p_pid, 'Paman Ocid menggambar jalur ke Pulau em pe''er de pe''er di petamu dengan arang.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'bayar11' then
    if s <> 2 then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city not in ('sunda_empire', 'empeer_depeer') then raise exception 'Paman Ocid tidak ada di sini.'; end if;
    v_cost := game.cfg_num('PasirJangkarBiaya', 100000)::bigint;
    update game.players set gold = gold - v_cost where player_id = p_pid and gold >= v_cost;
    if not found then raise exception 'Biaya jangkar % gold. Kumpulkan dulu, Kapten.', v_cost; end if;
    perform game.ps_set(p_pid, 'ps11', 3, jsonb_build_object('bayar', v_now));
    perform game.log(p_pid, 'Membayar ' || v_cost || ' gold kepada Paman Ocid untuk besi, arang, dan upah pandai besi Jangkar Waktu.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'selam11' then
    if s <> 3 then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'empeer_depeer' then raise exception 'Perairan dalam itu ada di Pulau em pe''er de pe''er.'; end if;
    v_rest := nullif(d ->> 'selamRest', '')::bigint;
    if v_rest is not null and v_now < v_rest then raise exception 'Napasmu masih pendek, Kapten. Istirahat dulu.'; end if;
    if v_arg = 'gagal' then
      perform game.ps_set(p_pid, 'ps11', 3, jsonb_build_object('selamRest', v_now + (game.cfg_num('PasirSelamJedaMenit', 20) * 60000)::bigint));
      return jsonb_build_object('ok', false);
    end if;
    if v_arg <> 'ok' then raise exception 'Hasil selam tidak dikenal.'; end if;
    perform game.ps_set(p_pid, 'ps11', 4, jsonb_build_object('roda', v_now, 'selamRest', null));
    perform game.log(p_pid, 'Roda gigi Jam Agung diangkat dari dasar laut em pe''er de pe''er.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'tempa11' then
    if s <> 4 then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'empeer_depeer' then raise exception 'Dok kecil itu ada di Pulau em pe''er de pe''er.'; end if;
    v_score := least(100, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    v_dur := coalesce(nullif(v_arg2, '')::int, 0);
    if v_dur < 8000 then raise exception 'Besi belum sempat dipanaskan, Kapten.'; end if;
    v_grade := game.lt_grade(v_score);
    if v_grade = 'retak' then
      perform game.ps_set(p_pid, 'ps11', 4, jsonb_build_object('tempaTry', v_score));
      return jsonb_build_object('ok', false, 'grade', v_grade);
    end if;
    insert into game.pv_pusaka(player_id, pusaka_id, mutu, slot) values (p_pid, 'jangkar', v_grade, null)
      on conflict (player_id, pusaka_id) do update set mutu = excluded.mutu;
    update game.pv_pusaka set slot = null where player_id = p_pid and slot = 1 and pusaka_id <> 'jangkar';
    update game.pv_pusaka set slot = 1 where player_id = p_pid and pusaka_id = 'jangkar';
    perform game.ps_set(p_pid, 'ps11', 5, jsonb_build_object('mutu', v_grade, 'tempaScore', v_score));
    perform game.log(p_pid, 'Jangkar Waktu ditempa (' || v_grade || ') dan dipasang di kapalmu.');
    return jsonb_build_object('ok', true, 'grade', v_grade);
  elsif p_act = 'tambal11' then
    if s <> 6 or game.pasir_era(p_pid) <> 'badai' then raise exception 'Aksi tidak dikenal.'; end if;
    v_score := least(100, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    v_dur := coalesce(nullif(v_arg2, '')::int, 0);
    if v_dur < 5000 then raise exception 'Papannya belum sempat dipaku, Kapten.'; end if;
    if game.lt_grade(v_score) = 'retak' then return jsonb_build_object('ok', false); end if;
    perform game.ps_set(p_pid, 'ps11', 7, jsonb_build_object('tambal', v_score));
    return jsonb_build_object('ok', true);
  elsif p_act = 'gala11' then
    if s <> 7 or game.pasir_era(p_pid) <> 'badai' or coalesce(v_arg, '') not in ('cerita', 'bantu') then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.pasir_ensure(p_pid);
    update game.pasir_state set riak = riak || jsonb_build_object('gala_muda', v_arg), updated_at = now() where player_id = p_pid;
    if v_arg = 'cerita' then perform game.ps_retak_add(p_pid, 15);
    else perform game.ps_barang_add(p_pid, 'sabun_gala'); end if;
    perform game.ps_set(p_pid, 'ps11', 8, jsonb_build_object('gala', v_arg));
    return jsonb_build_object('ok', true);
  elsif p_act = 'kejar11' then
    if s <> 8 or game.pasir_era(p_pid) <> 'badai' then raise exception 'Aksi tidak dikenal.'; end if;
    v_n := least(20, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    update game.pasir_state set kaca = greatest(kaca, 2), era = 'keadilan', updated_at = now(),
      data = data || jsonb_build_object('sorot', true, 'retak_t', v_now) where player_id = p_pid;
    perform game.ps_lokasi(p_pid, 'empeer_depeer');
    perform game.ps_set(p_pid, 'ps11', 9, jsonb_build_object('kejar', v_n));
    perform game.log(p_pid, 'Janji Putih menarik kapal hantu menjauh dari pantai Skitraw. Kaca kedua Jam Pasir retak.');
    return jsonb_build_object('ok', true);
  elsif p_act = 'paham11' then
    if s <> 9 then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'empeer_depeer' then raise exception 'Paman Ocid menunggu di ruang Jam Agung.'; end if;
    v_cost := game.cfg_num('PasirQ11Hadiah', 100000)::bigint;
    update game.players set gold = gold + v_cost where player_id = p_pid;
    perform game.ps_sdata_set(p_pid, jsonb_build_object('jangkar_siap', v_now + (game.cfg_num('PasirJedaLompatHari', 1) * game.ww_day_ms())::bigint));
    perform game.ps_set(p_pid, 'ps11', 10, '{}'::jsonb, true);
    perform game.log(p_pid, 'Paman Ocid menjual sisa roda gigi Jam Agung ke saudagar logam: ' || v_cost || ' gold untukmu.');
    return jsonb_build_object('ok', true);
  end if;
  return game.ps_act_more(p_pid, p_act, a);   -- batch berikutnya (0043+) menyambung di sini
end $$;

-- ---------------------------------------------------------------------
-- Status untuk klien (salinan 0041 + Q11, Pusaka, Retak, zaman)
-- ---------------------------------------------------------------------
create or replace function game.pasir_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare r game.pasir_state; v_gm boolean; s int; v_siap bigint;
begin
  if not game.pasir_aktif(p_pid) then return null; end if;
  perform game.ps10_try_start(p_pid);
  perform game.ps11_try_start(p_pid);
  s := game.ps_step(p_pid, 'ps10');
  if s = 3 and not game.in_transit(p_pid) then perform game.ps_on_arrive(p_pid, game.current_city(p_pid)); end if;
  perform game.ps_retak_tick(p_pid);
  select * into r from game.pasir_state where player_id = p_pid;
  v_gm := game.is_gm(p_pid);
  if not found and not v_gm then return null; end if;
  v_siap := nullif(r.data ->> 'jangkar_siap', '')::bigint;
  return jsonb_build_object(
    'era', coalesce(r.era, 'kini'),
    'tone', game.pasir_tone(coalesce(r.era, 'kini')),
    'retak', coalesce(r.retak, 0),
    'kaca', coalesce(r.kaca, 0),
    'kacaMax', game.cfg_num('PasirKaca', 7)::int,
    'riak', coalesce(r.riak, '{}'::jsonb),
    'night', game.fish_is_night(),
    'q', jsonb_build_object('10', game.ps_step(p_pid, 'ps10'), '11', game.ps_step(p_pid, 'ps11'),
      '12', game.ps_step(p_pid, 'ps12'), '13', game.ps_step(p_pid, 'ps13'), '14', game.ps_step(p_pid, 'ps14')),
    'q10', game.ps_q_json(p_pid, 'ps10'),
    'q11', game.ps_q_json(p_pid, 'ps11'),
    'pusaka', game.ps_pusaka_json(p_pid),
    'jangkarMs', case when v_siap is null then 0 else greatest(0, v_siap - game.now_ms()) end,
    'zaman', to_jsonb(game.ps_zaman_opsi(p_pid)),
    'sorot', coalesce((r.data ->> 'sorot')::boolean, false),
    'barang', coalesce(r.data -> 'barang', '[]'::jsonb),
    'q11cost', game.cfg_num('PasirJangkarBiaya', 100000)
  ) || coalesce(game.ps_state_more(p_pid), '{}'::jsonb) || case when v_gm then jsonb_build_object('gm', true,
          'eras', (select jsonb_agg(jsonb_build_object('era', e, 'tone', game.pasir_tone(e))) from unnest(game.pasir_eras()) e))
        else '{}'::jsonb end;
end $$;

-- ---------------------------------------------------------------------
-- Alat GM (salinan 0040 + pusaka, jangkar)
-- ---------------------------------------------------------------------
create or replace function game.pasir_admin(p_pid uuid, p_aksi text, p_arg text default null, p_arg2 text default null) returns jsonb
language plpgsql as $$
declare v_act text := lower(coalesce(p_aksi, 'lihat')); v_n int; r game.pasir_state; v_extra jsonb := '{}'::jsonb;
begin
  if p_pid is null then raise exception 'Pemain tidak ditemukan.'; end if;
  if v_act = 'era' then
    if not (lower(coalesce(p_arg, '')) = any (game.pasir_eras())) then
      raise exception 'Era harus salah satu: %', array_to_string(game.pasir_eras(), ', ');
    end if;
    perform game.pasir_ensure(p_pid);
    update game.pasir_state set era = lower(p_arg), updated_at = now() where player_id = p_pid;
  elsif v_act in ('retak', 'kaca') then
    v_n := nullif(trim(coalesce(p_arg, '')), '')::int;
    if v_n is null then raise exception 'Angka tidak valid.'; end if;
    perform game.pasir_ensure(p_pid);
    if v_act = 'retak' then
      update game.pasir_state set retak = least(100, greatest(0, v_n)), data = data || jsonb_build_object('retak_t', game.now_ms()), updated_at = now() where player_id = p_pid;
    else
      update game.pasir_state set kaca = least(game.cfg_num('PasirKaca', 7)::int, greatest(0, v_n)), updated_at = now() where player_id = p_pid;
    end if;
  elsif v_act = 'langkah' then
    if coalesce(p_arg, '') !~ '^ps1[0-4]$' then raise exception 'Quest harus ps10..ps14.'; end if;
    v_n := nullif(trim(coalesce(p_arg2, '')), '')::int;
    if v_n is null or v_n < 0 then raise exception 'Langkah tidak valid.'; end if;
    perform game.pasir_ensure(p_pid);
    if v_n = 0 then delete from game.player_quests where player_id = p_pid and quest_id = p_arg;
    else perform game.ps_set(p_pid, p_arg, v_n); end if;
  elsif v_act = 'pusaka' then
    if not exists (select 1 from jsonb_array_elements(game.ps_pusaka_katalog()) x where x ->> 'id' = p_arg) then raise exception 'Pusaka tidak dikenal.'; end if;
    insert into game.pv_pusaka(player_id, pusaka_id, mutu) values (p_pid, p_arg, nullif(p_arg2, ''))
      on conflict (player_id, pusaka_id) do update set mutu = coalesce(excluded.mutu, game.pv_pusaka.mutu);
  elsif v_act = 'jangkar' then
    -- jangkar siap dipakai sekarang (lewati pendinginan)
    perform game.ps_sdata_set(p_pid, jsonb_build_object('jangkar_siap', null));
  elsif v_act = 'ambil' then
    v_extra := game.pv_ambil(p_pid);
  elsif v_act = 'pulih' then
    v_extra := game.pv_pulih(p_pid);
  elsif v_act = 'reset' then
    if exists (select 1 from game.pv_snap where player_id = p_pid and restored_at is null) then
      raise exception 'Harta pemain ini masih di potret. Jalankan pulih dulu sebelum reset.';
    end if;
    delete from game.player_quests where player_id = p_pid and quest_id in ('ps10', 'ps11', 'ps12', 'ps13', 'ps14');
    delete from game.pasir_state where player_id = p_pid;
    delete from game.pv_snap where player_id = p_pid;
    delete from game.pv_pusaka where player_id = p_pid;
  elsif v_act <> 'lihat' and not game.ps_admin_more(p_pid, v_act, p_arg, p_arg2) then
    raise exception 'Aksi GM tidak dikenal.';
  end if;
  select * into r from game.pasir_state where player_id = p_pid;
  return jsonb_build_object('row', case when r.player_id is null then null else to_jsonb(r) - 'player_id' end,
    'quests', coalesce((select jsonb_object_agg(quest_id, jsonb_build_object('step', step, 'data', data, 'done', done_at is not null))
      from game.player_quests where player_id = p_pid and quest_id in ('ps10', 'ps11', 'ps12', 'ps13', 'ps14')), '{}'::jsonb),
    'pusaka', game.ps_pusaka_json(p_pid),
    'potret', (select case when ps.player_id is null then null else jsonb_build_object('taken', ps.taken_at, 'restored', ps.restored_at,
      'gold', ps.data -> 'gold', 'bank', ps.data -> 'bank', 'result', ps.result) end from game.pv_snap ps where ps.player_id = p_pid),
    'hasil', v_extra);
end $$;

-- ---------------------------------------------------------------------
-- Endpoint: api_pasir (salinan 0041 + ps_act_ext)
-- ---------------------------------------------------------------------
create or replace function public.api_pasir(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_arg text := game.arg(a, 1);
  v_me game.players; v_pid uuid; v_res jsonb; s int; d jsonb; v_city text;
begin
  v_me := game.me(v_act not in ('status'));
  v_pid := v_me.player_id;
  if coalesce(v_me.archetype, '') = '' or not game.pasir_aktif(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;

  if v_act = 'status' then
    return jsonb_build_object('pasir', game.pasir_state(v_pid));
  elsif v_act = 'gm' then
    if not game.is_gm(v_pid) then raise exception 'Aksi tidak dikenal.'; end if;
    v_res := game.pasir_admin(v_pid, game.arg(a, 1), game.arg(a, 2), game.arg(a, 3));
    return jsonb_build_object('gm', v_res, 'pasir', game.pasir_state(v_pid));
  end if;

  v_res := game.ps_act_ext(v_pid, v_act, a);
  if v_res is not null then
    return v_res || jsonb_build_object('pasir', game.pasir_state(v_pid), 'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  s := game.ps_step(v_pid, 'ps10');
  d := game.ps_data(v_pid, 'ps10');
  v_city := game.current_city(v_pid);
  if v_act = 'pesta' then
    if s <> 1 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 1, jsonb_build_object('pesta', true));
  elsif v_act = 'terima' then
    if s <> 1 or not coalesce((d ->> 'pesta')::boolean, false) then raise exception 'Aksi tidak dikenal.'; end if;
    if game.in_transit(v_pid) or v_city <> 'ikn' then raise exception 'Nyonya Z. menunggu di dermaga IKN.'; end if;
    perform game.ps_set(v_pid, 'ps10', 2, '{}'::jsonb);
    perform game.log(v_pid, 'Menerima titipan penumpang: Nyonya Z., pelukis peta, ke Pulau em pe''er de pe''er.');
  elsif v_act = 'jawab' then
    if s not in (3, 4) or coalesce(v_arg, '') not in ('pernah', 'tidak') then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.pasir_ensure(v_pid);
    update game.pasir_state set riak = riak || jsonb_build_object('jawab_malam', v_arg), updated_at = now() where player_id = v_pid;
    perform game.ps_set(v_pid, 'ps10', s, jsonb_build_object('jawab', v_arg));
  elsif v_act = 'pisah' then
    if s <> 4 or not (d ? 'jawab') then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 5, jsonb_build_object('pisah', coalesce(v_arg, '')));
  elsif v_act = 'jam' then
    if s <> 5 or game.in_transit(v_pid) or v_city <> 'empeer_depeer' then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 6, '{}'::jsonb);
  elsif v_act = 'curi' then
    if s <> 6 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.pv_ambil(v_pid, 'sunda_empire');
    update game.pasir_state set data = data || jsonb_build_object('buka', '[]'::jsonb, 'retak_t', game.now_ms()), kaca = greatest(kaca, 1), updated_at = now()
     where player_id = v_pid;
    perform game.ps_set(v_pid, 'ps10', 7, '{}'::jsonb);
  elsif v_act = 'paham' then
    if s <> 7 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 8, '{}'::jsonb);
  elsif v_act = 'catatan' then
    if s <> 8 then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(v_pid, 'ps10', 9, jsonb_build_object('bukti', '{}'::jsonb));
  elsif v_act = 'ocid' then
    if s <> 10 then raise exception 'Aksi tidak dikenal.'; end if;
    if game.in_transit(v_pid) or v_city <> 'sunda_empire' then raise exception 'Lelaki tua itu menunggu di Pustaka Sunda.'; end if;
    perform game.ps_set(v_pid, 'ps10', 11, '{}'::jsonb, true);
    perform game.log(v_pid, 'Bertemu Paman Ocid di Pustaka Sunda. Seorang penjaga jam tanpa jam, seorang kapten tanpa kisah.');
  else
    raise exception 'Aksi tidak dikenal.';
  end if;
  return jsonb_build_object('pasir', game.pasir_state(v_pid), 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_pasir');
