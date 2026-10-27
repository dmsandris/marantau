-- =====================================================================
-- Tide v37 · Fase 4: Kisah Lapau Bab 1 "Kapal Tanpa Awak" (kapal hantu alniu siarfi),
-- Set Kapal Hantu (khusus pembaca), Set Badai Petir, Set Mutiara Paradiso,
-- Bentuk Kapal (slot 'bentuk'), hewan penghuni baru.
-- Kisah: beli bab (keping) -> 1 dengar Uda Gala di Lapau Skitraw -> 2 tiba di pelabuhan
-- saat malam (kabut, alniu siarfi muncul, Lonceng Kabut) -> 3 teka-teki Nenek Ulin di
-- Bjorneo ("pulang") -> 4 bunyikan lonceng saat berlayar malam -> tamat: Layar Koyak,
-- Set Kapal Hantu terbuka di Kedai.
-- Idempoten.
-- =====================================================================

insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, req, exclusive, active, sort) values
  -- Kisah Lapau
  ('kisah_kapal_tanpa_awak', 'kisah', null, null, 'Kapal Tanpa Awak', 'agung', 1250,
     'Uda Gala bercerita tentang kapal pertama yang dicuci Gaul-Wash: kapal tanpa awak bernama alniu siarfi.', 'Uda Gala', null, false, true, 400),
  -- Set Kapal Hantu (agung, khusus pembaca Bab 1)
  ('lambung_karam',   'rupa', 'lambung',    'kapal_hantu', 'Lambung Karam',  'agung', 1800, 'Lambung pucat tembus pandang, teritip dan lumut yang berpendar hijau.', null, '{"kisah":"kapal_tanpa_awak","kisahName":"Kapal Tanpa Awak"}', false, true, 320),
  ('layar_koyak',     'rupa', 'layar',      'kapal_hantu', 'Layar Koyak',    'agung', 1400, 'Layar compang-camping; cahaya hijau pucat merembes dari setiap sobekan.', null, '{"kisah":"kapal_tanpa_awak","kisahName":"Kapal Tanpa Awak"}', false, true, 321),
  ('aura_arwah',      'rupa', 'aura',       'kapal_hantu', 'Lentera Arwah',  'agung', 1600, 'Lentera hijau-biru melayang di sekeliling dek, berkedip pelan.', null, '{"kisah":"kapal_tanpa_awak","kisahName":"Kapal Tanpa Awak"}', false, true, 322),
  ('jejak_kabut',     'rupa', 'jejak',      'kapal_hantu', 'Jejak Kabut',    'agung', 1600, 'Kabut dingin bergulung di belakang kapal.', null, '{"kisah":"kapal_tanpa_awak","kisahName":"Kapal Tanpa Awak"}', false, true, 323),
  ('datang_lonceng',  'rupa', 'kedatangan', 'kapal_hantu', 'Lonceng Kabut',  'agung', 1600, 'Kapalmu muncul perlahan dari dalam kabut, diiringi bunyi lonceng.', null, '{"kisah":"kapal_tanpa_awak","kisahName":"Kapal Tanpa Awak"}', false, true, 324),
  -- Set Badai Petir (agung)
  ('layar_badai',     'rupa', 'layar',      'badai_petir', 'Layar Awan Badai', 'agung', 1800, 'Layar kelabu bermotif awan badai; kilat merambat di permukaannya.', null, null, false, true, 330),
  ('lambung_petir',   'rupa', 'lambung',    'badai_petir', 'Lambung Besi Petir', 'agung', 1800, 'Lambung baja biru berpaku keling; percikan listrik meloncat di sela pelat.', null, null, false, true, 331),
  ('panji_penangkal', 'rupa', 'panji',      'badai_petir', 'Tiang Penangkal', 'agung', 1600, 'Penangkal petir di puncak tiang, berdesis dan memercik.', null, null, false, true, 332),
  ('meriam_guntur',   'rupa', 'meriam',     'badai_petir', 'Meriam Guntur',   'agung', 1800, 'Mulut meriam berkilat. Di pertempuran, tembakan berubah jadi sambaran petir.', null, null, false, true, 333),
  ('datang_petir',    'rupa', 'kedatangan', 'badai_petir', 'Petir Menyambar', 'agung', 2000, 'Saat tiba, petir menyambar laut di samping kapalmu, disusul guntur.', null, null, false, true, 334),
  -- Set Mutiara Paradiso (langka)
  ('lambung_mutiara', 'rupa', 'lambung',    'mutiara_paradiso', 'Lambung Kerang Mutiara', 'langka', 1500, 'Lambung berkilau pelangi seperti bagian dalam kerang mutiara.', null, null, false, true, 340),
  ('layar_senja',     'rupa', 'layar',      'mutiara_paradiso', 'Layar Sutra Senja', 'langka', 1500, 'Sutra bergradasi jingga-merah muda yang berkibar lembut.', null, null, false, true, 341),
  ('haluan_penyu',    'rupa', 'haluan',     'mutiara_paradiso', 'Haluan Penyu', 'langka', 1400, 'Patung penyu laut di haluan; siripnya mengayuh pelan.', null, null, false, true, 342),
  ('jejak_kamboja',   'rupa', 'jejak',      'mutiara_paradiso', 'Jejak Kamboja', 'langka', 1300, 'Kelopak kamboja putih-kuning hanyut di belakang kapal.', null, null, false, true, 343),
  ('aura_gelembung',  'rupa', 'aura',       'mutiara_paradiso', 'Gelembung Pantai', 'langka', 1300, 'Gelembung pelangi dan kunang-kunang melayang di sekitar kapal.', null, null, false, true, 344),
  -- Bentuk kapal (legenda)
  ('bentuk_lancang',  'rupa', 'bentuk', null, 'Lancang Kuning', 'legenda', 4000, 'Kapal kerajaan Melayu: lambung kuning-emas, haluan melengkung berukir, layar tanja, payung kuning di buritan.', null, null, false, true, 350),
  ('bentuk_kora',     'rupa', 'bentuk', null, 'Kora-kora',      'legenda', 3500, 'Perahu perang Maluku: ramping, berkatir, haluan-buritan menjulang, deretan pendayung, panji bulu.', null, null, false, true, 351),
  ('bentuk_jung',     'rupa', 'bentuk', null, 'Jung Jawa',      'legenda', 4500, 'Kapal raksasa empat tiang berlayar bilah, buritan bertingkat, mata naga di haluan.', null, null, false, true, 352),
  -- Hewan penghuni
  ('penghuni_beo',    'rupa', 'penghuni', null, 'Burung Beo',          'biasa', 1200, 'Bertengger di cucur haluan, sesekali terbang memutari tiang. Saat tiba: "Untung!"', null, null, false, true, 160),
  ('penghuni_monyet', 'rupa', 'penghuni', null, 'Monyet Ekor Panjang', 'biasa', 1200, 'Memanjat tali-temali dan bergelantungan di palang layar.', null, null, false, true, 161),
  ('penghuni_ayam',   'rupa', 'penghuni', null, 'Ayam Jago',           'biasa', 1000, 'Mondar-mandir di dek dan berkokok saat fajar.', null, null, false, true, 162),
  ('penghuni_anjing', 'rupa', 'penghuni', null, 'Anjing Kintamani',    'biasa', 1300, 'Rebahan di dek, ekornya bergoyang. Saat merapat ia melompat ke dermaga.', null, null, false, true, 163)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh, req = excluded.req,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

create or replace function game.kd_set_name(p_set text) returns text
language sql immutable as $$
  select case p_set when 'api_gunung' then 'Set Api Gunung' when 'naga_samudra' then 'Set Naga Samudra'
    when 'kapal_hantu' then 'Set Kapal Hantu' when 'badai_petir' then 'Set Badai Petir' when 'mutiara_paradiso' then 'Set Mutiara Paradiso' else p_set end
$$;
create or replace function game.kd_set_info(p_set text) returns text
language sql immutable as $$
  select case p_set
    when 'api_gunung' then 'Udara panas bergetar di sekitar kapal, letusan kecil sesekali dari puncak tiang, retakan makin terang saat malam.'
    when 'naga_samudra' then 'Naga air bening sesekali muncul dari laut, melingkari kapal, lalu menyelam. Saat kapal tiba, ia muncul menyambut.'
    when 'kapal_hantu' then 'Saat malam kapal menjadi tembus pandang, bayangan awak alniu siarfi berjalan di dek, dan wajah kapal itu sesekali tampak di permukaan air.'
    when 'badai_petir' then 'Awan badai kecil mengikuti di atas kapal dengan hujan tipis; petir menyambar tiang setiap beberapa detik.'
    when 'mutiara_paradiso' then 'Dua lumba-lumba melompat bergantian di samping kapal; saat tiba, kelopak bunga berjatuhan.'
    else '' end
$$;

-- Etalase hanya barang yang bisa dibeli semua kapten
create or replace function game.kd_etalase_ids() returns text[]
language sql stable as $$
  select coalesce(array_agg(id), '{}') from (
    select i.id from game.kd_items i
     where i.rak = 'rupa' and i.active and not i.exclusive and i.req is null
     order by md5(i.id || to_char(game.kd_week_start(), 'YYYY-MM-DD')) limit greatest(0, game.cfg_num('EtalaseJumlah', 3)::int)
  ) z
$$;

-- ---------------------------------------------------------------------
-- Kisah Lapau
-- ---------------------------------------------------------------------
create table if not exists game.ks_progress (
  player_id  uuid not null references game.players(player_id) on update cascade on delete cascade,
  kisah      text not null,
  step       int not null default 1,          -- 1 dengar, 2 kabut malam, 3 teka-teki, 4 lonceng, 5 tamat
  wait_until timestamptz,
  bought_at  timestamptz not null default now(),
  step_at    timestamptz not null default now(),
  done_at    timestamptz,
  primary key (player_id, kisah)
);
alter table game.ks_progress enable row level security;

create or replace function game.kisah_done(p_pid uuid, p_kisah text) returns boolean
language sql stable as $$ select exists (select 1 from game.ks_progress where player_id = p_pid and kisah = p_kisah and done_at is not null) $$;

-- katalog bab (bab 2-5 "Segera")
create or replace function game.ks_catalog() returns jsonb
language sql immutable as $$ select '[
  {"id":"kapal_tanpa_awak","item":"kisah_kapal_tanpa_awak","bab":1,"title":"Kapal Tanpa Awak","tokoh":"Uda Gala","open":true,
   "blurb":"Malam badai besar, hari pertama Gaul-Wash buka. Sebuah kapal tanpa awak bernama alniu siarfi merapat sendiri, loncengnya berbunyi tanpa disentuh."},
  {"id":"malam_chafik","bab":2,"title":"Malam Sebelum Chafik Lahir","tokoh":"Uda Gala","open":false,"blurb":"Uda Gala muda berlayar pulang untuk menggendong putra kecilnya."},
  {"id":"kedai_kopi","bab":3,"title":"Kedai Kopi di Pulau Sudyrman","tokoh":"coco epan","open":false,"blurb":"Masa muda coco epan sebelum menjadi bankir."},
  {"id":"surat_andry","bab":4,"title":"Surat untuk Andry","tokoh":"zafachmie","open":false,"blurb":"zafachmie menulis surat untuk Andry Ivankov. Pelikan membawa balasan yang tak bisa dibaca."},
  {"id":"tujuh_pulau","bab":5,"title":"Tujuh Pulau, Delapan Nama","tokoh":"Pustakawan","open":false,"blurb":"Teka-teki angka tujuh di Pustaka: ada pulau yang tidak pernah tercatat."}
]'::jsonb $$;

create or replace function game.ks_step_text(p_kisah text, p_step int) returns text
language sql immutable as $$
  select case when p_kisah = 'kapal_tanpa_awak' then case p_step
    when 1 then 'Datangi Lapau Bopet Bassamo di Skitraw. Uda Gala ingin bercerita.'
    when 2 then 'Berlayarlah dan merapatlah di pelabuhan mana pun saat malam. Kabut sering turun di jam-jam itu.'
    when 3 then 'Bawa Lonceng Kabut ke mercusuar Nenek Ulin di Bjorneo.'
    when 4 then 'Saat berlayar di malam hari, bunyikan Lonceng Kabut di laut lepas.'
    else 'Tamat. alniu siarfi sudah pulang.' end else '' end
$$;

create or replace function game.kisah_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_on boolean := game.fitur_on(p_pid, 'KedaiOpen');
begin
  if not v_on then return null; end if;
  return jsonb_build_object(
    'night', game.fish_is_night(),
    'city', game.current_city(p_pid), 'transit', game.in_transit(p_pid),
    'price', jsonb_build_object('kapal_tanpa_awak', game.kd_price('kisah_kapal_tanpa_awak')),
    'chapters', (select jsonb_agg(c || jsonb_build_object(
        'owned', p.player_id is not null, 'step', p.step, 'done', p.done_at is not null,
        'waitMs', case when p.wait_until > now() then floor(extract(epoch from (p.wait_until - now())) * 1000)::bigint else 0 end,
        'task', case when p.player_id is not null then game.ks_step_text(c ->> 'id', p.step) end) order by (c ->> 'bab')::int)
      from jsonb_array_elements(game.ks_catalog()) c
      left join game.ks_progress p on p.player_id = p_pid and p.kisah = c ->> 'id'));
end $$;

-- kejadian dari kait pelayaran: tiba di pelabuhan saat malam -> kabut & alniu siarfi
create or replace function game.ks_on_event(p_pid uuid, p_kind text, p_ctx jsonb) returns void
language plpgsql as $$
declare r game.ks_progress;
begin
  if p_kind <> 'arrive' then return; end if;
  select * into r from game.ks_progress where player_id = p_pid and kisah = 'kapal_tanpa_awak' and done_at is null for update;
  if not found or r.step <> 2 or not game.fish_is_night() then return; end if;
  update game.ks_progress set step = 3, step_at = now() where player_id = p_pid and kisah = 'kapal_tanpa_awak';
  perform game.log(p_pid, 'Kabut turun saat merapat. Sebuah kapal tanpa awak berlayar sejajar, lalu lenyap. Yang tertinggal hanya lonceng kecil yang mengapung: Lonceng Kabut.');
  perform game.mp_push_inbox(p_pid, jsonb_build_object('type', 'kisah', 'ev', 'kabut', 'kisah', 'kapal_tanpa_awak', 'city', p_ctx ->> 'city'));
end $$;

-- kait kejadian (salinan 0033 + Kisah Lapau)
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
begin
  if p_pid is null then return; end if;
  if game.fitur_on(p_pid, 'HarianOpen') then
    begin
      perform game.hr_event(p_pid, p_kind, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[harian] % %: %', p_kind, p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'sell' and game.fitur_on(p_pid, 'PacuOpen') then
    begin
      perform game.pd_on_sell(p_pid, p_amount, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[pacu] %: %', p_pid, sqlerrm;
    end;
  end if;
  if p_kind = 'arrive' then
    begin
      perform game.ks_on_event(p_pid, p_kind, coalesce(p_ctx, '{}'::jsonb));
    exception when others then raise warning '[kisah] %: %', p_pid, sqlerrm;
    end;
  end if;
end $$;

-- a = [aksi, ...]: status | beli <kisah> | dengar | jawab <teks> | lonceng
create or replace function public.api_kisah(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'status');
  v_arg text := game.arg(a, 1); r game.ks_progress; v_price int; v_city text; v_ans text; v_out jsonb := '{}'::jsonb; v_k text := 'kapal_tanpa_awak';
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KedaiOpen') then raise exception 'Kedai Rantau belum dibuka.'; end if;
  v_city := game.current_city(v_pid);

  if v_act = 'beli' then
    v_k := coalesce(v_arg, v_k);
    if not exists (select 1 from jsonb_array_elements(game.ks_catalog()) c where c ->> 'id' = v_k and (c ->> 'open')::boolean) then
      raise exception 'Bab ini belum terbit. Nantikan di Lapau.';
    end if;
    if exists (select 1 from game.ks_progress where player_id = v_pid and kisah = v_k) then raise exception 'Bab ini sudah kamu miliki.'; end if;
    v_price := game.kd_price('kisah_' || v_k);
    perform game.keping_add(v_pid, -v_price, 'kisah', 'bab ' || v_k);
    insert into game.ks_progress(player_id, kisah) values (v_pid, v_k);
    perform game.log(v_pid, 'Kisah Lapau: membeli bab "Kapal Tanpa Awak" seharga ' || v_price || ' keping. Uda Gala menunggumu di Lapau Skitraw.');
    v_out := jsonb_build_object('bought', v_k);
  elsif v_act in ('dengar', 'jawab', 'lonceng') then
    select * into r from game.ks_progress where player_id = v_pid and kisah = v_k for update;
    if not found then raise exception 'Beli dulu bab "Kapal Tanpa Awak" di rak Kisah, Kedai Rantau.'; end if;
    if r.done_at is not null then raise exception 'Kisah ini sudah tamat.'; end if;
    if v_act = 'dengar' then
      if r.step <> 1 then raise exception 'Uda Gala sudah selesai bercerita. %', game.ks_step_text(v_k, r.step); end if;
      if game.in_transit(v_pid) or v_city is distinct from 'skitraw' then raise exception 'Uda Gala sedang di Lapau Bopet Bassamo, Skitraw.'; end if;
      update game.ks_progress set step = 2, step_at = now() where player_id = v_pid and kisah = v_k;
      perform game.log(v_pid, 'Uda Gala menyerahkan selembar log robek kapal alniu siarfi: "Kalau kau berlayar malam dan kabut turun, jangan takut. Ia hanya ingin pulang."');
      v_out := jsonb_build_object('scene', 'cerita');
    elsif v_act = 'jawab' then
      if r.step <> 3 then raise exception '%', game.ks_step_text(v_k, r.step); end if;
      if game.in_transit(v_pid) or v_city is distinct from 'bjorneo' then raise exception 'Nenek Ulin menjaga mercusuar di Bjorneo.'; end if;
      if r.wait_until > now() then raise exception 'Nenek Ulin masih menyeruput tehnya. Tunggu % detik.', ceil(extract(epoch from (r.wait_until - now())))::int; end if;
      v_ans := lower(btrim(regexp_replace(coalesce(v_arg, ''), '[^a-zA-Z ]', '', 'g')));
      if v_ans in ('pulang', 'kepulangan', 'kembali pulang') then
        update game.ks_progress set step = 4, step_at = now(), wait_until = null where player_id = v_pid and kisah = v_k;
        perform game.log(v_pid, 'Nenek Ulin: "Pulang. Itu yang dicari setiap kapal yang hilang. Bunyikan lonceng itu di laut malam, Nak, dan biarkan ia pulang."');
        v_out := jsonb_build_object('benar', true);
      else
        update game.ks_progress set wait_until = now() + interval '20 seconds' where player_id = v_pid and kisah = v_k;
        v_out := jsonb_build_object('benar', false, 'waitMs', 20000);
      end if;
    else   -- lonceng
      if r.step <> 4 then raise exception '%', game.ks_step_text(v_k, r.step); end if;
      if not game.in_transit(v_pid) then raise exception 'Lonceng ini harus dibunyikan di laut lepas, saat berlayar.'; end if;
      if not game.fish_is_night() then raise exception 'Tunggu malam turun. alniu siarfi hanya mendengar lonceng di malam hari.'; end if;
      update game.ks_progress set step = 5, step_at = now(), done_at = now() where player_id = v_pid and kisah = v_k;
      if game.kd_qty(v_pid, 'layar_koyak') = 0 then perform game.kd_grant(v_pid, 'layar_koyak', 1, 'kisah'); end if;
      perform game.log(v_pid, 'Lonceng Kabut berdentang. Awak bayangan alniu siarfi memberi hormat, lalu kapal itu larut menjadi kabut yang meresap ke layarmu. Kisah "Kapal Tanpa Awak" tamat.');
      v_out := jsonb_build_object('scene', 'pulang', 'reward', 'layar_koyak');
    end if;
  elsif v_act <> 'status' then
    raise exception 'Aksi tidak dikenal: %', v_act;
  end if;

  return v_out || jsonb_build_object('kisah', game.kisah_state(v_pid), 'kedai', game.kd_list(v_pid),
    'keping', (select keping from game.players where player_id = v_pid));
end $$;
select game.expose('api_kisah');
