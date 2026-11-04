-- =====================================================================
-- Marantau (Supabase) - 0062 BALAI KONGSI & KI DORUS  (Tide v46)
-- ---------------------------------------------------------------------
-- Konsep: claude/KONSEP-Balai-Kongsi-Ki-Dorus.md (v3).
-- Pemain menanam gold di kapal kongsi (Balai Kongsi, Pelabuhan Rantai Lama).
-- 24 jam nyata kemudian kapal pulang dengan hasil 0%-180% dari modal.
-- Rata-rata SEMUA tier < 100% -> sink gold, tidak pernah pencetak gold.
--
--   * Hasil diundi di server SAAT BERANGKAT, tidak pernah dikirim ke klien sebelum pulang.
--   * Kabar dari Laut di tengah pelayaran (65% benar, 35% menipu).
--   * Panggil Pulang (Moderat/Agresif, setelah kabar): modal kembali 70%.
--   * Daya Serap Laut: untung dari modal besar dipotong (rugi selalu penuh).
--   * Neraca Laut pemain (14 hari) & server (7 hari): hasil tinggi diturunkan.
--   * Pengumuman chat dunia hanya untuk kemenangan besar.
--   * Senin 08:00 WIB: Ki Dorus menyumbang 20% laba Balai Kongsi sepekan ke Restorasi IKN
--     (tanpa batas). Sumbangan itu dibagi ke sumbangan pribadi kapten yang rugi pekan itu.
--   * Saga 3: kongsi yang pulang selama harta dicuri ditahan ('tahan'), dilepas ke bank
--     setelah potret harta dikembalikan (bukan bagian potret, tidak ikut Bunga Waktu).
--
-- Peluang & aturan rahasia: tidak pernah ada di state klien.
-- Penyelesaian tanpa cron: game.kongsi_tick() dipanggil dari denyut (gm_pulse) & getGameState.
-- Pembungkus: gm_pulse (0061) -> gm_pulse_kongsi, gr_view (0032) -> gr_view_inti. Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('KongsiOpen', '0'),
  ('KongsiModalMin', '100000'),
  ('KongsiDurMenit', '1440'),
  ('KongsiKabarMenit', '720'),
  ('KongsiKabarBenar', '65'),
  ('KongsiPanggilPct', '70'),
  ('KongsiSerap', '5000000:1,20000000:0.5,inf:0.25'),
  ('KongsiNeracaHari', '14'),
  ('KongsiNeracaPct', '15'),
  ('KongsiNeracaMin', '1000000'),
  ('KongsiNeracaServer', '95'),
  ('KongsiIknPersen', '0.2'),
  ('KongsiUmumkanPct', '160'),
  ('KongsiUmumkanMin', '1000000'),
  ('KongsiSimpanHari', '120'),
  -- [peluang %, hasil %] per tier. Rata-rata wajib < 100 (dicek saat deploy & saat menanam).
  ('KongsiTier', '{"konservatif":[[20,80],[40,92],[30,100],[10,115]],"moderat":[[15,30],[30,75],[30,100],[15,120],[10,140]],"agresif":[[45,0],[25,120],[20,160],[10,180]]}')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Tabel
-- ---------------------------------------------------------------------
create table if not exists game.kongsi (
  id          bigserial primary key,
  player_id   uuid not null references game.players(player_id) on update cascade on delete cascade,
  tier        text not null,                 -- konservatif | moderat | agresif
  modal       bigint not null,
  outcome     int not null,                  -- % hasil (rahasia sampai pulang)
  turun       boolean not null default false,-- diturunkan Neraca Laut
  tujuan      text not null default '',
  musim       text not null default '',
  depart_at   timestamptz not null,
  kabar_at    timestamptz not null,
  return_at   timestamptz not null,
  kabar_good  boolean not null,              -- kabar yang akan diterima (bisa menipu)
  kabar_tx    text,                          -- terisi saat kabar tiba
  status      text not null default 'laut',  -- laut | pulang | panggil | tahan
  payout      bigint,
  story       text,
  settled_at  timestamptz,
  settle_week timestamp,                     -- awal pekan WIB (Senin 08:00) saat diselesaikan
  seen        boolean not null default false -- laporan sudah dibaca
);
create index if not exists kongsi_laut_idx on game.kongsi (return_at) where status = 'laut';
create index if not exists kongsi_kabar_idx on game.kongsi (kabar_at) where status = 'laut' and kabar_tx is null;
create index if not exists kongsi_player_idx on game.kongsi (player_id, id desc);
create index if not exists kongsi_week_idx on game.kongsi (settle_week) where settle_week is not null;
alter table game.kongsi enable row level security;

-- Ringkasan seumur hidup (Buku Ki Dorus) — tetap ada walau baris lama dihapus
create table if not exists game.kongsi_buku (
  player_id  uuid primary key references game.players(player_id) on update cascade on delete cascade,
  total_modal bigint not null default 0,
  total_bayar bigint not null default 0,
  n          int not null default 0,
  kenal      boolean not null default false  -- perkenalan Ki Dorus sudah dibaca
);
alter table game.kongsi_buku enable row level security;

create table if not exists game.kongsi_week (
  week       timestamp primary key,          -- awal pekan WIB (Senin 08:00)
  modal      bigint not null default 0,
  bayar      bigint not null default 0,
  laba       bigint not null default 0,
  donasi     bigint not null default 0,
  pengongsi  int not null default 0,
  catatan    text not null default '',
  done_at    timestamptz not null default now()
);
alter table game.kongsi_week enable row level security;

alter table game.gr_donations add column if not exists kongsi bigint not null default 0;  -- porsi dari rugi kongsi

-- ---------------------------------------------------------------------
-- Aturan angka
-- ---------------------------------------------------------------------
create or replace function game.kongsi_tiers() returns jsonb
language plpgsql stable as $$
declare v jsonb;
begin
  begin v := game.cfg('KongsiTier')::jsonb; exception when others then v := null; end;
  if v is null or jsonb_typeof(v) <> 'object' then
    v := '{"konservatif":[[20,80],[40,92],[30,100],[10,115]],"moderat":[[15,30],[30,75],[30,100],[15,120],[10,140]],"agresif":[[45,0],[25,120],[20,160],[10,180]]}'::jsonb;
  end if;
  return v;
end $$;

-- rata-rata hasil (%) satu tier tanpa Serap/Neraca
create or replace function game.kongsi_ev(p_tier text) returns numeric
language sql stable as $$
  select coalesce(sum((e ->> 0)::numeric * (e ->> 1)::numeric) / nullif(sum((e ->> 0)::numeric), 0), 999)
    from jsonb_array_elements(game.kongsi_tiers() -> p_tier) e
$$;

-- Penjaga: semua tier harus < 100%, strategi Panggil Pulang terbaik juga < 100%
create or replace function game.kongsi_aman() returns boolean
language plpgsql stable as $$
declare t text; pb numeric := game.cfg_num('KongsiKabarBenar', 65) / 100; rc numeric := game.cfg_num('KongsiPanggilPct', 70);
  pg numeric; pl numeric; sg numeric; sl numeric; bk numeric; gk numeric; tot numeric;
begin
  for t in select jsonb_object_keys(game.kongsi_tiers()) loop
    if game.kongsi_ev(t) >= 100 then return false; end if;
    select coalesce(sum(case when (e ->> 1)::numeric >= 100 then (e ->> 0)::numeric end), 0),
           coalesce(sum(case when (e ->> 1)::numeric < 100 then (e ->> 0)::numeric end), 0),
           coalesce(sum(case when (e ->> 1)::numeric >= 100 then (e ->> 0)::numeric * (e ->> 1)::numeric end), 0),
           coalesce(sum(case when (e ->> 1)::numeric < 100 then (e ->> 0)::numeric * (e ->> 1)::numeric end), 0),
           sum((e ->> 0)::numeric)
      into pg, pl, sg, sl, tot from jsonb_array_elements(game.kongsi_tiers() -> t) e;
    if t = 'konservatif' or tot is null or tot = 0 then continue; end if;
    -- kabar buruk: pb dari hasil rugi + (1-pb) dari hasil untung; strategi terbaik pilih max(rc, nilai lanjut)
    bk := pb * pl + (1 - pb) * pg; gk := tot - bk;
    if (bk * greatest(rc, case when bk > 0 then (pb * sl + (1 - pb) * sg) / bk else 0 end)
       + gk * greatest(rc, case when gk > 0 then ((1 - pb) * sl + pb * sg) / gk else 0 end)) / tot >= 100 then return false; end if;
  end loop;
  return true;
end $$;

do $$ begin
  if not game.kongsi_aman() then raise exception 'KongsiTier tidak aman: rata-rata hasil kongsi >= 100%%.'; end if;
end $$;

-- Daya Serap Laut: hasil akhir untuk modal & outcome
create or replace function game.kongsi_bayar(p_modal bigint, p_outcome int) returns bigint
language plpgsql stable as $$
declare raw text := coalesce(nullif(trim(game.cfg('KongsiSerap')), ''), '5000000:1,20000000:0.5,inf:0.25');
  part text; lim numeric; f numeric; lo numeric := 0; hi numeric; prof numeric := 0; pct numeric := p_outcome::numeric / 100 - 1;
begin
  if p_outcome <= 100 then return floor(p_modal * p_outcome::numeric / 100)::bigint; end if;
  foreach part in array string_to_array(raw, ',') loop
    begin
      hi := case when lower(trim(split_part(part, ':', 1))) = 'inf' then null else trim(split_part(part, ':', 1))::numeric end;
      f := trim(split_part(part, ':', 2))::numeric;
    exception when others then continue;
    end;
    if p_modal > lo then prof := prof + (coalesce(least(p_modal, hi), p_modal) - lo) * pct * f; end if;
    exit when hi is null or p_modal <= hi;
    lo := hi;
  end loop;
  return p_modal + floor(prof)::bigint;
end $$;

create or replace function game.kongsi_week_start() returns timestamp
language sql stable as $$ select date_trunc('week', game.pd_wib() - interval '8 hours') + interval '8 hours' $$;

create or replace function game.kongsi_musim() returns text
language sql stable as $$
  select (array['Musim Angin Barat', 'Musim Mutiara', 'Musim Badai', 'Musim Pancaroba'])[(extract(month from game.pd_wib())::int % 4) + 1]
$$;

create or replace function game.kongsi_nama_tier(p_tier text) returns text
language sql immutable as $$ select case p_tier when 'konservatif' then 'Konservatif' when 'moderat' then 'Moderat' when 'agresif' then 'Agresif' else p_tier end $$;

create or replace function game.kongsi_kapal(p_tier text) returns text
language sql immutable as $$ select case p_tier when 'konservatif' then 'Jung' when 'moderat' then 'Pinisi' else 'Lancang' end $$;

create or replace function game.kongsi_tujuan(p_tier text) returns text
language sql volatile as $$
  select case p_tier
    when 'konservatif' then (array['Otoland', 'FreeYork'])[1 + floor(random() * 2)::int]
    when 'moderat' then (array['Gading Island', 'em pe''er de pe''er'])[1 + floor(random() * 2)::int]
    else (array['Kepulauan Karang Garam', 'perairan di balik Sowtour'])[1 + floor(random() * 2)::int] end
$$;

-- ---------------------------------------------------------------------
-- Cerita (server, supaya laporan & pengumuman selalu sama)
-- ---------------------------------------------------------------------
create or replace function game.kongsi_kabar(p_good boolean, p_tier text, p_tujuan text) returns text
language plpgsql volatile as $$
declare k text := game.kongsi_kapal(p_tier); a text[];
begin
  if p_good then a := array[
    'Pelaut ' || p_tujuan || ' melihat ' || lower(k) || ' kongsimu dekat karang. Layarnya utuh, lambungnya dalam. Muatannya berat.',
    'Pelikan pembawa surat bilang ' || lower(k) || ' kongsi sudah merapat di ' || p_tujuan || '. Saudagar di sana tersenyum.',
    'Angin timur bertiup lurus sejak semalam. Kata nelayan, kapal-kapal yang ke ' || p_tujuan || ' berlayar seperti dikejar rezeki.',
    'Seorang awak kongsi menitip pesan lewat kapal ikan: "Pasar ' || p_tujuan || ' sedang lapar barang kita."'];
  else a := array[
    'Badai mengamuk di jalur ke ' || p_tujuan || ' semalam. Belum ada kabar dari kapal kongsi.',
    'Sepotong tali kongsi terdampar di pantai. Bisa jadi milik kapal lain. Bisa jadi bukan.',
    'Kabarnya harga di ' || p_tujuan || ' sedang jatuh. Saudagar di sana menawar sambil tertawa.',
    'Kapal patroli melihat ' || lower(k) || ' kongsi berlayar miring ke timur. Entah karena muatan, entah karena bocor.'];
  end if;
  return a[1 + floor(random() * array_length(a, 1))::int];
end $$;

create or replace function game.kongsi_cerita(p_tier text, p_outcome int, p_tujuan text, p_serap boolean) returns text
language plpgsql volatile as $$
declare k text := game.kongsi_kapal(p_tier); a text[]; t text;
begin
  if p_outcome <= 0 then a := array[
    k || ' tak pernah kembali. Hanya sepotong layar yang terdampar di Karang Garam. Ama Kerang menyimpannya untukmu.',
    'Kabut menelan ' || lower(k) || ' kongsi di dekat ' || p_tujuan || '. Lonceng Rantai Lama tidak berbunyi untuknya.',
    'Bajak laut menunggu di selat sempit. ' || k || ' kongsi tenggelam bersama seluruh muatannya.'];
  elsif p_outcome < 60 then a := array[
    'Separuh palka tersapu badai di dekat ' || p_tujuan || '. Yang tersisa dijual murah.',
    'Muatan basah kena hujan tiga hari berturut-turut. Saudagar ' || p_tujuan || ' hanya mau membayar sebagian.',
    'Awak kongsi terpaksa membuang muatan supaya kapal tidak karam. Yang pulang hanya sedikit.'];
  elsif p_outcome < 100 then a := array[
    'Beras basah kena tempias. Dijual murah di ' || p_tujuan || '.',
    'Harga di ' || p_tujuan || ' sedang turun saat kapal merapat. Pulang dengan sedikit kurang dari modal.',
    'Pelayaran lancar, tapi pajak pelabuhan ' || p_tujuan || ' memakan sebagian keuntungan.'];
  elsif p_outcome = 100 then a := array[
    'Impas. Laut sedang tak ramah, tak juga kejam.',
    k || ' kongsi pulang utuh dari ' || p_tujuan || '. Modalmu kembali, tidak lebih, tidak kurang.'];
  elsif p_outcome < 150 then a := array[
    'Muatan habis di ' || p_tujuan || ' sebelum kapal sempat merapat.',
    'Saudagar ' || p_tujuan || ' memborong muatan kongsi. Untung yang rapi.',
    'Angin bersahabat sepanjang jalan. ' || k || ' pulang lebih cepat dan lebih berat.'];
  else a := array[
    'Mutiara sebesar telur merpati dari ' || p_tujuan || '! Ki Dorus sampai lupa menulis selama satu tarikan napas.',
    'Cendana tua dari ' || p_tujuan || '! Harganya gila. Lonceng Rantai Lama berdentang panjang.',
    k || ' kongsi pulang sarat muatan. Di dermaga orang berdesak ingin melihat isi palkanya.'];
  end if;
  t := a[1 + floor(random() * array_length(a, 1))::int];
  if p_serap then t := t || ' Tapi muatan sebesar itu membanjiri pasar di sana; harganya jatuh, untungnya tak sebesar yang dibayangkan.'; end if;
  return t;
end $$;

-- ---------------------------------------------------------------------
-- Undian (saat berangkat) + Neraca Laut
-- ---------------------------------------------------------------------
create or replace function game.kongsi_turun(p_tier text, p_outcome int) returns int
language sql stable as $$
  select case when p_outcome <= 100 then p_outcome else
    coalesce((select max((e ->> 1)::int) from jsonb_array_elements(game.kongsi_tiers() -> p_tier) e
               where (e ->> 1)::int >= 100 and (e ->> 1)::int < p_outcome), 100) end
$$;

create or replace function game.kongsi_undi(p_pid uuid, p_tier text, out o_outcome int, out o_turun boolean)
language plpgsql volatile as $$
declare r numeric; acc numeric := 0; e jsonb; tot numeric; v_top int;
  n_modal numeric; n_bayar numeric; s_modal numeric; s_bayar numeric;
begin
  o_turun := false;
  select sum((x ->> 0)::numeric), max((x ->> 1)::int) into tot, v_top from jsonb_array_elements(game.kongsi_tiers() -> p_tier) x;
  r := random() * tot;
  for e in select * from jsonb_array_elements(game.kongsi_tiers() -> p_tier) loop
    acc := acc + (e ->> 0)::numeric;
    if r < acc then o_outcome := (e ->> 1)::int; exit; end if;
  end loop;
  if o_outcome is null then o_outcome := 100; end if;
  if o_outcome <= 100 then return; end if;
  -- Neraca Laut pemain: untung bersih 14 hari > pct modal & > min -> hasil tinggi turun satu tingkat
  select coalesce(sum(modal), 0), coalesce(sum(payout), 0) into n_modal, n_bayar from game.kongsi
   where player_id = p_pid and status in ('pulang', 'panggil', 'tahan')
     and settled_at > game.hr_now() - make_interval(days => game.cfg_num('KongsiNeracaHari', 14)::int);
  if n_bayar - n_modal > greatest(n_modal * game.cfg_num('KongsiNeracaPct', 15) / 100, game.cfg_num('KongsiNeracaMin', 1000000)) then
    o_outcome := game.kongsi_turun(p_tier, o_outcome); o_turun := true; return;
  end if;
  -- Neraca Laut server: bayar 7 hari > 95% modal -> hasil teratas tier dibagi dua peluangnya
  select coalesce(sum(modal), 0), coalesce(sum(payout), 0) into s_modal, s_bayar from game.kongsi
   where status in ('pulang', 'panggil', 'tahan') and settled_at > game.hr_now() - interval '7 days';
  if s_modal > 0 and s_bayar > s_modal * game.cfg_num('KongsiNeracaServer', 95) / 100 and o_outcome = v_top and random() < 0.5 then
    o_outcome := game.kongsi_turun(p_tier, o_outcome); o_turun := true;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Restorasi IKN: tambah kolam & porsi pribadi. Logika tahap & kategori ada di 0032
-- (game.gr_pool_add, game.gr_grant_kategori), dipakai bersama api_gotong & TheDuneks.
-- ---------------------------------------------------------------------
create or replace function game.kongsi_gr_pool(p_val bigint) returns void
language plpgsql as $$
begin
  perform game.gr_pool_add(p_val, 'Ki Dorus, Balai Kongsi', null);
end $$;

-- Porsi pribadi (dari rugi kongsi): masuk total sumbangan & kategori, tanpa gold/keping
create or replace function game.kongsi_gr_credit(p_pid uuid, p_val bigint) returns void
language plpgsql as $$
declare d game.gr_donations;
begin
  if p_val <= 0 then return; end if;
  insert into game.gr_donations as x (project_id, player_id, kongsi, total, n, last_at)
  values ('ikn', p_pid, p_val, p_val, 0, now())
  on conflict (project_id, player_id) do update set kongsi = x.kongsi + excluded.kongsi, total = x.total + excluded.total, last_at = now()
  returning * into d;
  perform game.gr_grant_kategori(p_pid, d.total);
end $$;

-- ---------------------------------------------------------------------
-- Penyelesaian
-- ---------------------------------------------------------------------
create or replace function game.kongsi_tahan(p_pid uuid) returns boolean
language sql stable as $$
  select exists (select 1 from game.pv_snap where player_id = p_pid and restored_at is null)
$$;

create or replace function game.kongsi_kredit(p_pid uuid, p_val bigint) returns void
language plpgsql as $$
begin
  if p_val <= 0 then return; end if;
  perform game.bank_state(p_pid);   -- bunga tertunda dihitung dulu
  update game.players set bank_balance = coalesce(bank_balance, 0) + p_val where player_id = p_pid;
end $$;

create or replace function game.kongsi_settle(p_id bigint) returns void
language plpgsql as $$
declare k game.kongsi; v_pay bigint; v_name text; v_hold boolean;
begin
  select * into k from game.kongsi where id = p_id and status = 'laut' for update skip locked;
  if not found then return; end if;
  v_pay := game.kongsi_bayar(k.modal, k.outcome);
  v_hold := game.kongsi_tahan(k.player_id);
  update game.kongsi set status = case when v_hold then 'tahan' else 'pulang' end, payout = v_pay, settled_at = game.hr_now(),
    settle_week = game.kongsi_week_start(),
    story = game.kongsi_cerita(k.tier, k.outcome, k.tujuan, k.outcome > 100 and v_pay < floor(k.modal * k.outcome::numeric / 100)),
    kabar_tx = coalesce(kabar_tx, game.kongsi_kabar(kabar_good, tier, tujuan)),
    seen = false
   where id = p_id;
  update game.kongsi_buku set total_bayar = total_bayar + v_pay where player_id = k.player_id;
  if v_hold then return; end if;   -- Saga 3: ditahan diam-diam sampai harta kembali
  perform game.kongsi_kredit(k.player_id, v_pay);
  perform game.log(k.player_id, 'Kapal kongsi ' || game.kongsi_nama_tier(k.tier) || ' pulang dari ' || k.tujuan || ': modal '
    || to_char(k.modal, 'FM999G999G999G999') || ', kembali ' || to_char(v_pay, 'FM999G999G999G999') || ' gold ke Bank.');
  perform game.mp_push_inbox(k.player_id, jsonb_build_object('type', 'kongsi', 'kind', 'pulang', 'tier', k.tier, 'modal', k.modal, 'payout', v_pay));
  if k.outcome >= game.cfg_num('KongsiUmumkanPct', 160) and k.modal >= game.cfg_num('KongsiUmumkanMin', 1000000) then
    select coalesce(nullif(character_name, ''), 'Seorang kapten') into v_name from game.players where player_id = k.player_id;
    perform game.sys_chat('Ki Dorus', 'Lonceng Rantai Lama berdentang! ' || game.kongsi_kapal(k.tier) || ' kongsi Kapten ' || v_name
      || ' pulang membawa ' || to_char(v_pay, 'FM999G999G999G999') || ' gold.');
  end if;
end $$;

-- Hitungan pekanan + sumbangan Ki Dorus (aman diulang: satu baris kongsi_week per pekan)
create or replace function game.kongsi_weekly() returns void
language plpgsql as $$
declare w timestamp; v_modal bigint; v_bayar bigint; v_laba bigint; v_don bigint := 0; v_n int; v_done boolean;
  v_loss bigint; r record; v_share bigint; v_given bigint := 0; v_cat text := '';
begin
  for w in select distinct settle_week from game.kongsi
            where settle_week is not null and settle_week < game.kongsi_week_start()
              and settle_week not in (select week from game.kongsi_week) order by 1 loop
    begin
      insert into game.kongsi_week(week) values (w);
    exception when unique_violation then continue;
    end;
    select coalesce(sum(modal), 0), coalesce(sum(payout), 0), count(distinct player_id) into v_modal, v_bayar, v_n
      from game.kongsi where settle_week = w and status in ('pulang', 'panggil', 'tahan');
    v_laba := v_modal - v_bayar;
    select done_at is not null into v_done from game.gr_projects where id = 'ikn';
    v_don := 0; v_given := 0;
    if v_laba > 0 and not coalesce(v_done, true) then
      v_don := floor(v_laba * game.cfg_num('KongsiIknPersen', 0.2))::bigint;
    end if;
    if v_don > 0 then
      -- porsi pribadi: dibagi ke kapten yang rugi bersih pekan itu, sebanding ruginya
      select coalesce(sum(l), 0) into v_loss from (
        select greatest(0, sum(modal) - sum(payout)) l from game.kongsi where settle_week = w and status in ('pulang', 'panggil', 'tahan') group by player_id) z;
      for r in select player_id, sum(modal) - sum(payout) l from game.kongsi where settle_week = w and status in ('pulang', 'panggil', 'tahan')
                group by player_id having sum(modal) - sum(payout) > 0 loop
        v_share := floor(v_don::numeric * r.l / greatest(v_loss, 1))::bigint;
        if v_share > 0 then
          perform game.kongsi_gr_credit(r.player_id, v_share);
          v_given := v_given + v_share;
          if game.pasir_era(r.player_id) = 'kini' then
            perform game.mp_push_inbox(r.player_id, jsonb_build_object('type', 'kongsi', 'kind', 'ikn', 'share', v_share));
          end if;
        end if;
      end loop;
      perform game.kongsi_gr_pool(v_don);
      perform game.sys_chat('Ki Dorus', 'Ki Dorus menyumbang ' || to_char(v_don, 'FM999G999G999G999') || ' gold untuk Restorasi IKN atas nama '
        || v_n || ' pengongsi Balai Kongsi. "Utang lama. Dicatat."', 'ikn');
      v_cat := 'disumbangkan';
    elsif coalesce(v_done, false) then
      v_cat := 'ikn selesai';
    else
      v_cat := 'laut murah hati';
      if v_n > 0 then perform game.sys_chat('Ki Dorus', 'Pekan ini laut lebih murah hati pada Tuan-Tuan Kapten. Garuda bisa menunggu.'); end if;
    end if;
    update game.kongsi_week set modal = v_modal, bayar = v_bayar, laba = v_laba, donasi = v_don, pengongsi = v_n, catatan = v_cat, done_at = now() where week = w;
  end loop;
end $$;

-- Dipanggil dari denyut & getGameState. Murah: indeks parsial, batas baris per panggilan.
create or replace function game.kongsi_tick() returns void
language plpgsql as $$
declare k record; v_now timestamptz := game.hr_now();
begin
  -- Kabar dari Laut
  for k in select id, player_id, kabar_good, tier, tujuan from game.kongsi
            where status = 'laut' and kabar_tx is null and kabar_at <= v_now order by kabar_at limit 50 for update skip locked loop
    update game.kongsi set kabar_tx = game.kongsi_kabar(k.kabar_good, k.tier, k.tujuan) where id = k.id;
    if not game.kongsi_tahan(k.player_id) and game.pasir_era(k.player_id) = 'kini' then
      perform game.mp_push_inbox(k.player_id, jsonb_build_object('type', 'kongsi', 'kind', 'kabar', 'tier', k.tier));
    end if;
  end loop;
  -- Kapal pulang
  for k in select id from game.kongsi where status = 'laut' and return_at <= v_now order by return_at limit 50 loop
    perform game.kongsi_settle(k.id);
  end loop;
  -- Saga 3: lepaskan hasil yang ditahan begitu harta pemain kembali
  for k in select id, player_id, payout from game.kongsi where status = 'tahan' order by id limit 50 for update skip locked loop
    if not game.kongsi_tahan(k.player_id) then
      update game.kongsi set status = 'pulang', seen = false where id = k.id;
      perform game.kongsi_kredit(k.player_id, k.payout);
      perform game.log(k.player_id, 'Ki Dorus mengirim hasil kapal kongsi yang lama tertahan: ' || to_char(k.payout, 'FM999G999G999G999') || ' gold ke Bank.');
    end if;
  end loop;
  perform game.kongsi_weekly();
  -- rapikan baris lama (ringkasan tetap di kongsi_buku & kongsi_week)
  delete from game.kongsi where status in ('pulang', 'panggil') and settled_at < v_now - make_interval(days => game.cfg_num('KongsiSimpanHari', 120)::int)
    and settle_week in (select week from game.kongsi_week);
exception when others then raise warning '[kongsi] tick: %', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- State klien (TANPA peluang, outcome, atau kabar_good)
-- ---------------------------------------------------------------------
create or replace function game.kongsi_kenal_rantai(p_pid uuid) returns boolean
language sql stable as $$ select game.lt_step(p_pid) >= 5 $$;

create or replace function game.kongsi_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare b game.kongsi_buku; v_now timestamptz; v_ws timestamp;
begin
  if p_pid is null or not game.fitur_on(p_pid, 'KongsiOpen') then return null; end if;
  if not game.kongsi_kenal_rantai(p_pid) then return null; end if;
  if game.pasir_era(p_pid) <> 'kini' then return null; end if;
  perform game.kongsi_tick();
  v_now := game.hr_now(); v_ws := game.kongsi_week_start();
  select * into b from game.kongsi_buku where player_id = p_pid;
  return jsonb_build_object(
    'here', game.current_city(p_pid) = 'rantai_lama' and not game.in_transit(p_pid),
    'now', (extract(epoch from v_now) * 1000)::bigint,
    'min', game.cfg_num('KongsiModalMin', 100000)::bigint,
    'musim', game.kongsi_musim(),
    'recallPct', game.cfg_num('KongsiPanggilPct', 70),
    'kenal', coalesce(b.kenal, false),
    'ikn', (select done_at is null from game.gr_projects where id = 'ikn'),
    'buku', jsonb_build_object('modal', coalesce(b.total_modal, 0), 'bayar', coalesce(b.total_bayar, 0), 'n', coalesce(b.n, 0)),
    'active', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tier', k.tier, 'modal', k.modal, 'tujuan', k.tujuan,
        'departMs', (extract(epoch from k.depart_at) * 1000)::bigint, 'kabarMs', (extract(epoch from k.kabar_at) * 1000)::bigint,
        'returnMs', (extract(epoch from k.return_at) * 1000)::bigint, 'kabar', k.kabar_tx,
        'canRecall', k.kabar_tx is not null and k.tier <> 'konservatif') order by k.depart_at)
      from game.kongsi k where k.player_id = p_pid and k.status = 'laut'), '[]'::jsonb),
    'laporan', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'tier', k.tier, 'modal', k.modal, 'payout', k.payout, 'tujuan', k.tujuan,
        'recalled', k.status = 'panggil', 'story', k.story, 'atMs', (extract(epoch from k.settled_at) * 1000)::bigint) order by k.settled_at desc)
      from game.kongsi k where k.player_id = p_pid and k.status in ('pulang', 'panggil') and not k.seen), '[]'::jsonb)
  );
end $$;

-- Papan Lonceng (kemenangan terbesar pekan ini) & riwayat 10 terakhir
create or replace function game.kongsi_papan(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'lonceng', coalesce((select jsonb_agg(x order by (x ->> 'untung')::bigint desc) from (
        select jsonb_build_object('name', coalesce(nullif(p.character_name, ''), 'Kapten'), 'tier', k.tier, 'payout', k.payout, 'untung', k.payout - k.modal,
          'me', k.player_id = p_pid) x
          from game.kongsi k join game.players p on p.player_id = k.player_id
         where k.status = 'pulang' and k.settle_week = game.kongsi_week_start() and k.payout > k.modal
         order by k.payout - k.modal desc limit 5) z), '[]'::jsonb),
    'riwayat', coalesce((select jsonb_agg(jsonb_build_object('tier', k.tier, 'modal', k.modal, 'payout', k.payout, 'tujuan', k.tujuan,
        'recalled', k.status = 'panggil', 'story', k.story, 'atMs', (extract(epoch from k.settled_at) * 1000)::bigint) order by k.settled_at desc)
      from (select * from game.kongsi where player_id = p_pid and status in ('pulang', 'panggil') order by settled_at desc limit 10) k), '[]'::jsonb),
    'kiDorus', coalesce((select sum(donasi) from game.kongsi_week), 0)
  )
$$;

-- ---------------------------------------------------------------------
-- ENDPOINT: api_kongsi([aksi, ...])
--   status | tanam(tier, modal) | panggil(id) | lihat | kenal
-- ---------------------------------------------------------------------
create or replace function public.api_kongsi(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'status');
  v_tier text; v_modal bigint; v_bank bigint; v_from_bank bigint; v_from_gold bigint; v_out int; v_turun boolean; v_good boolean;
  v_now timestamptz; v_id bigint; k game.kongsi; v_pay bigint; bk jsonb;
begin
  if coalesce(v_me.archetype, '') = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KongsiOpen') or not game.kongsi_kenal_rantai(v_pid) then raise exception 'Balai Kongsi belum dibuka.'; end if;
  if game.pasir_era(v_pid) <> 'kini' then raise exception 'Tak ada kapal kongsi di zaman ini, Kapten.'; end if;

  if v_act = 'kenal' then
    insert into game.kongsi_buku(player_id, kenal) values (v_pid, true) on conflict (player_id) do update set kenal = true;
  elsif v_act = 'lihat' then
    update game.kongsi set seen = true where player_id = v_pid and status in ('pulang', 'panggil') and not seen;
  elsif v_act = 'tanam' then
    v_tier := lower(coalesce(game.arg(a, 1), ''));
    v_modal := coalesce(game.arg_int(a, 2), 0);
    if v_tier not in ('konservatif', 'moderat', 'agresif') then raise exception 'Pilih kapal kongsi dulu, Tuan Kapten.'; end if;
    if game.in_transit(v_pid) or game.current_city(v_pid) is distinct from 'rantai_lama' then
      raise exception 'Kongsi hanya dicatat di Balai Kongsi, Pelabuhan Rantai Lama.';
    end if;
    if not game.kongsi_aman() then raise exception 'Balai Kongsi sedang menghitung ulang buku besarnya. Datang lagi nanti, Tuan Kapten.'; end if;
    if v_modal < game.cfg_num('KongsiModalMin', 100000) then
      raise exception 'Modal kongsi paling sedikit % gold, Tuan Kapten.', to_char(game.cfg_num('KongsiModalMin', 100000), 'FM999G999G999');
    end if;
    if exists (select 1 from game.kongsi where player_id = v_pid and tier = v_tier and status = 'laut') then
      raise exception 'Kapal % Tuan Kapten masih di laut. Satu kapal per jenis, Tuan Kapten. Dicatat.', game.kongsi_kapal(v_tier);
    end if;
    bk := game.bank_state(v_pid);
    v_bank := (bk ->> 'bankBalance')::bigint;
    select gold into v_me.gold from game.players where player_id = v_pid for update;
    if v_modal > v_bank + v_me.gold then raise exception 'Gold di Bank dan di tangan tidak cukup untuk modal itu.'; end if;
    v_from_bank := least(v_bank, v_modal); v_from_gold := v_modal - v_from_bank;
    update game.players set bank_balance = bank_balance - v_from_bank, gold = gold - v_from_gold where player_id = v_pid;
    select * into v_out, v_turun from game.kongsi_undi(v_pid, v_tier);
    v_good := case when random() * 100 < game.cfg_num('KongsiKabarBenar', 65) then v_out >= 100 else v_out < 100 end;
    v_now := game.hr_now();
    insert into game.kongsi(player_id, tier, modal, outcome, turun, tujuan, musim, depart_at, kabar_at, return_at, kabar_good)
    values (v_pid, v_tier, v_modal, v_out, v_turun, game.kongsi_tujuan(v_tier), game.kongsi_musim(), v_now,
      v_now + make_interval(mins => game.cfg_num('KongsiKabarMenit', 720)::int),
      v_now + make_interval(mins => game.cfg_num('KongsiDurMenit', 1440)::int), v_good)
    returning id into v_id;
    insert into game.kongsi_buku(player_id, total_modal, n) values (v_pid, v_modal, 1)
    on conflict (player_id) do update set total_modal = game.kongsi_buku.total_modal + v_modal, n = game.kongsi_buku.n + 1;
    perform game.log(v_pid, 'Menanam ' || to_char(v_modal, 'FM999G999G999G999') || ' gold di kapal kongsi ' || game.kongsi_nama_tier(v_tier) || ' (Balai Kongsi, Rantai Lama).');
  elsif v_act = 'panggil' then
    v_id := game.arg_int(a, 1);
    select * into k from game.kongsi where id = v_id and player_id = v_pid for update;
    if not found or k.status <> 'laut' then raise exception 'Kapal itu sudah tidak di laut, Tuan Kapten.'; end if;
    if k.tier = 'konservatif' then raise exception 'Jung beras tidak bisa dipanggil pulang, Tuan Kapten. Ia berlayar pelan, tapi pasti.'; end if;
    if k.kabar_tx is null then raise exception 'Belum ada kabar dari laut. Tunggu kabarnya dulu, Tuan Kapten.'; end if;
    v_pay := floor(k.modal * game.cfg_num('KongsiPanggilPct', 70) / 100)::bigint;
    update game.kongsi set status = 'panggil', payout = v_pay, settled_at = game.hr_now(), settle_week = game.kongsi_week_start(), seen = true,
      story = 'Dipanggil pulang setelah kabar dari laut. Ki Dorus: "Dicatat. Tuan Kapten memilih percaya pada angin. Kadang angin benar."'
     where id = v_id;
    update game.kongsi_buku set total_bayar = total_bayar + v_pay where player_id = v_pid;
    perform game.kongsi_kredit(v_pid, v_pay);
    perform game.log(v_pid, 'Memanggil pulang kapal kongsi ' || game.kongsi_nama_tier(k.tier) || ': ' || to_char(v_pay, 'FM999G999G999G999') || ' gold kembali ke Bank.');
  elsif v_act <> 'status' then
    raise exception 'Aksi tidak dikenal: %', v_act;
  end if;

  perform game.kongsi_tick();
  return jsonb_build_object('kongsi', game.kongsi_state(v_pid), 'papan', game.kongsi_papan(v_pid),
    'bank', game.bank_state(v_pid), 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_kongsi');

-- ---------------------------------------------------------------------
-- Pembungkus: denyut (penyelesaian tanpa cron) & Prasasti Restorasi (baris Ki Dorus)
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.gm_pulse_kongsi(uuid);
  alter function game.gm_pulse(uuid) rename to gm_pulse_kongsi;
  drop function if exists game.gr_view_inti(uuid, text);
  alter function game.gr_view(uuid, text) rename to gr_view_inti;
end $$;

create or replace function game.gm_pulse(p_pid uuid) returns jsonb
language plpgsql as $$
begin
  perform game.kongsi_tick();
  return game.gm_pulse_kongsi(p_pid);
end $$;

create or replace function game.gr_view(p_pid uuid, p_project text) returns jsonb
language plpgsql stable as $$
declare v jsonb := game.gr_view_inti(p_pid, p_project); v_kd bigint;
begin
  if p_project <> 'ikn' or v is null then return v; end if;
  select coalesce(sum(donasi), 0) into v_kd from game.kongsi_week;
  v := v || jsonb_build_object('kiDorus', v_kd);
  if jsonb_typeof(v -> 'me') = 'object' then
    v := jsonb_set(v, '{me,kongsi}', to_jsonb(coalesce((select kongsi from game.gr_donations where project_id = 'ikn' and player_id = p_pid), 0)));
  end if;
  return v;
end $$;
