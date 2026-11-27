-- =====================================================================
-- 0114 · PACU SELAT — KATEGORI JARAK, TARUHAN & MEDALI ADU KAPTEN
--   Tuan rombongan memilih kategori 400 m / 800 m / 1,4 km (saat mengajak, atau
--   lewat aksi 'jarakRb' selagi rombongan masih di lobi).
--   Taruhan masuk lomba (tiap kapten) dan Medali dasar Juara 1 (2 kapten):
--        400 m = 10.000 Gold, 2 Medali
--        800 m = 15.000 Gold, 3 Medali
--        1,4 km = 20.000 Gold, 5 Medali
--   Juara 1 membawa seluruh pot taruhan (= taruhan x jumlah kapten; untung bersih
--   taruhan x (kapten - 1)) dan Medali dasar x (kapten - 1): 2 kapten x1, 3 x2, 4 x3.
--   Contoh: 1,4 km dengan 4 kapten -> pot 80.000 (untung 60.000 Gold) + 15 Medali.
--   Hanya Juara 1 yang menerima. Medali baru diberikan bila minimal dua catatan
--   masuk (menang WO hanya mendapat pot). Seri: pot dan Medali dibagi rata.
--   Tanpa catatan sama sekali: taruhan dikembalikan.
--   Angka bisa diubah GM lewat game.config: PsAduTaruhan{400,800,1400}, PsAduMedali{400,800,1400}.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PsAduTaruhan400', '10000'), ('PsAduTaruhan800', '15000'), ('PsAduTaruhan1400', '20000'),
  ('PsAduMedali400', '2'),      ('PsAduMedali800', '3'),      ('PsAduMedali1400', '5')
on conflict (key) do nothing;

create or replace function game.ps_adu_kat(p_jarak_mm int) returns text
language sql immutable as $$ select case when p_jarak_mm <= 400000 then '400' when p_jarak_mm >= 1400000 then '1400' else '800' end $$;

create or replace function game.ps_adu_taruhan(p_jarak_mm int) returns int
language sql stable as $$
  select greatest(0, game.cfg_num('PsAduTaruhan' || game.ps_adu_kat(p_jarak_mm),
           case game.ps_adu_kat(p_jarak_mm) when '400' then 10000 when '800' then 15000 else 20000 end))::int
$$;

-- hg = untung bersih Gold Juara 1, hr = Medali Juara 1, untuk jarak & jumlah kapten tertentu
create or replace function game.ps_adu_hadiah(p_jarak_mm int, p_kapten int, out hg bigint, out hr int)
language sql stable as $$
  select game.ps_adu_taruhan(p_jarak_mm)::bigint * pg,
         (greatest(0, game.cfg_num('PsAduMedali' || game.ps_adu_kat(p_jarak_mm),
            case game.ps_adu_kat(p_jarak_mm) when '400' then 2 when '800' then 3 else 5 end)))::int * pg
    from (select greatest(1, least(4, coalesce(p_kapten, 2)) - 1)::int as pg) x
$$;

create or replace function game.ps_adu_hadiah_tabel() returns jsonb
language sql stable as $$
  select jsonb_object_agg(k, jsonb_build_object('taruhan', game.ps_adu_taruhan(k::int * 1000),
                                                 'medali', (select hr from game.ps_adu_hadiah(k::int * 1000, 2))))
    from unnest(array['400', '800', '1400']) k
$$;

create or replace function game.ps_room_hitung(p_id text) returns void
language plpgsql as $$
declare r game.ps_room; m record; v_h jsonb; v_best int; v_log int := 0; v_fin int := 0; v_pot bigint := 0;
  v_win int; v_bagi bigint; v_sisa bigint; v_gold_h bigint := 0; v_medali_h int := 0; v_br int; v_sr int; v_ikut int;
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

  -- Medali Juara 1 (sesuai jarak dan jumlah kapten yang bersaing) hanya bila minimal dua catatan masuk.
  select count(*) into v_ikut from game.ps_room_anggota where room_id = r.id and status = 'ikut';
  select hg, hr into v_gold_h, v_medali_h from game.ps_adu_hadiah(r.jarak_mm, v_ikut);

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
    if v_log < 2 then v_medali_h := 0; end if;
    v_bagi := v_pot / greatest(1, v_win); v_sisa := v_pot - v_bagi * v_win;
    v_br := v_medali_h / greatest(1, v_win); v_sr := v_medali_h - v_br * v_win; v_rank := 0;
    for m in select a.*, (a.hasil ->> 'fin')::int as f from game.ps_room_anggota a
              where a.room_id = r.id and a.status = 'ikut'
              order by case when (a.hasil ->> 'fin') is null or coalesce((a.hasil ->> 'jebol')::boolean, false) then 1 else 0 end,
                       (a.hasil ->> 'fin')::int nulls last, a.urut loop
      v_rank := v_rank + 1;
      if m.f = v_best and not coalesce((m.hasil ->> 'jebol')::boolean, false) then
        if v_bagi + v_sisa > 0 then perform game.ps_kas_catat(m.player_id, v_bagi + v_sisa, 'adu_pot', r.id); end if;
        if v_br + v_sr > 0 then
          insert into game.medali(player_id, jumlah, total) values (m.player_id, v_br + v_sr, v_br + v_sr)
            on conflict (player_id) do update set jumlah = game.medali.jumlah + (v_br + v_sr), total = game.medali.total + (v_br + v_sr);
        end if;
        update game.ps_room_anggota set hasil = hasil || jsonb_build_object('peringkat', 1, 'menang', true, 'dapat', v_bagi + v_sisa,
               'medali', v_br + v_sr)
         where room_id = r.id and player_id = m.player_id;
        v_sisa := 0; v_sr := 0;
      else
        update game.ps_room_anggota set hasil = hasil || jsonb_build_object('peringkat', v_rank, 'menang', false, 'dapat', 0, 'medali', 0)
         where room_id = r.id and player_id = m.player_id;
      end if;
      if m.f is not null and not coalesce((m.hasil ->> 'jebol')::boolean, false) then
        perform game.ps_rekor_catat(m.player_id, r.jarak_mm, m.f, coalesce((m.hasil ->> 'top')::int, 0), m.kelas, coalesce(array_length(m.parts, 1), 0));
      end if;
    end loop;
    update game.ps_room set status = 'selesai', hasil = jsonb_build_object('pot', v_pot, 'terbaik', v_best, 'pemenang', v_win, 'catatan', v_log,
                                                                         'hadiahMedali', v_medali_h, 'kapten', v_ikut) where id = r.id;
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
           'taruhan', r.taruhan, 'jarakMm', r.jarak_mm) order by a.diundang desc), '[]'::jsonb)
    into v_inv
    from game.ps_room_anggota a join game.ps_room r on r.id = a.room_id
   where a.player_id = p_pid and a.status = 'diundang' and r.status = 'lobi'
     and game.now_ms() - a.diundang < greatest(10, game.cfg_num('PsUndanganDetik', 60))::bigint * 1000;
  return jsonb_build_object('kaptenDiZentul', v_kap, 'undanganMasuk', v_inv, 'undanganKeluar', null,
    'sisaAduHariIni', v_sisa, 'hadiah', game.ps_adu_hadiah_tabel(),
    'rombongan', case when v_rb is null then null else v_rb || jsonb_build_object('maks', 4,
       'bisaMulai', (v_rb ->> 'tuan')::boolean and (select count(*) from jsonb_array_elements(v_rb -> 'anggota') e where e ->> 'status' = 'ikut') >= 2) end);
end $$;

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
    v_jarak := case coalesce(game.arg(a, 2), '800') when '400' then 400000 when '1400' then 1400000 when '800' then 800000
                 else null end;
    if v_jarak is null then raise exception 'Kategori jarak tidak dikenal.'; end if;
    if v_rid is null then
      v_rid := game.mp_uid('psb');
      insert into game.ps_room(id, tuan, created, game_day, taruhan, jarak_mm)
      values (v_rid, v_id, v_now, game.game_day(), game.ps_adu_taruhan(v_jarak), v_jarak);
      insert into game.ps_room_anggota(room_id, player_id, nama, status, urut, diundang)
      values (v_rid, v_id, game.ps_nama(v_id), 'ikut', 1, v_now);
    end if;
    select * into v_room from game.ps_room where id = v_rid for update;
    if v_room.tuan <> v_id then raise exception 'Hanya tuan rombongan yang boleh mengajak.'; end if;
    if v_room.status <> 'lobi' then raise exception 'Rombongan sudah berangkat.'; end if;
    if game.arg(a, 2) is not null and v_room.jarak_mm <> v_jarak then
      update game.ps_room set jarak_mm = v_jarak, taruhan = game.ps_adu_taruhan(v_jarak) where id = v_rid returning * into v_room;
    end if;
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
      'taruhan', v_room.taruhan, 'jarakMm', v_room.jarak_mm,
      'jumlah', (select count(*) from game.ps_room_anggota where room_id = v_rid and status = 'ikut')));
    return jsonb_build_object('ok', true, 'ps', game.ps_state(v_id));
  end if;

  -- Tuan mengganti kategori jarak selagi rombongan masih di lobi: ['jarakRb', roomId, '400'|'800'|'1400']
  if v_act = 'jarakRb' then
    v_rid := game.arg(a, 1);
    v_jarak := case game.arg(a, 2) when '400' then 400000 when '1400' then 1400000 when '800' then 800000 else null end;
    if v_jarak is null then raise exception 'Kategori jarak tidak dikenal.'; end if;
    select * into v_room from game.ps_room where id = v_rid for update;
    if v_room.id is null or v_room.status <> 'lobi' then raise exception 'Rombongan itu sudah tidak menunggu.'; end if;
    if v_room.tuan <> v_id then raise exception 'Hanya tuan rombongan yang boleh memilih jarak.'; end if;
    update game.ps_room set jarak_mm = v_jarak, taruhan = game.ps_adu_taruhan(v_jarak) where id = v_rid;
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
