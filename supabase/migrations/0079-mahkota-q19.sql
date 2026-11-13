-- =====================================================================
-- 0079 · Saga 4 batch 5 — QUEST MAHKOTA langkah 34-40 (Q19 "Gerbang Rantai") + tamat
--   34 Benteng Berjalan (sinematik)      37 Heat Pertama (tiba di IKN)
--   35 Juru Sita Palsu (setor bahan)     38 Heat Kedua (dilewati bila pilihan 'kabarkan')
--   36 Genderang Armada Bebas            39 Juru Sita: lawan cangcimen, momen Yaptob
--   40 Stempel di Dermaga: pilihan, Mesin Jolt dilepas, epilog + credit
--
--   Tamat: hadiah Q19, tanda jasa, Set Kedai "Jaring Putus", Krisis Monopoli padam,
--   Trektrek-an terbuka penuh di Zentul (lawan Pariopelan, KapalMber, cangcimen, Yaptob).
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('MkGoldQ19', '300000'), ('MkPengalihOli', '20'), ('MkPengalihBesi', '20'), ('MkPengalihMesiu', '10')
on conflict (key) do nothing;

create or replace function game.mk_steps() returns jsonb
language sql immutable as $$
  select '[
    {"n":1,"q":15,"p":"kota","b":"surat"},
    {"n":2,"q":15,"c":"ikn","p":"monumen","b":"dekret","g":"pantun","krisis":true},
    {"n":3,"q":15,"c":"ikn","p":"kamp","b":"jurutulis","g":"warga"},
    {"n":4,"q":15,"c":"joungjava","p":"syahbandar","b":"antrean","g":"syahbandar"},
    {"n":5,"q":15,"c":"joungjava","p":"warung","b":"dekretsalin"},
    {"n":6,"q":15,"c":"toogood","p":"dok","b":"blackpearl","cine":"mk_pantul"},
    {"n":7,"q":15,"c":"toogood","p":"alley","t":"malam","b":"hasiolan","g":"kuli","gold":"MkGoldQ15"},
    {"n":8,"q":16,"c":"paradiso","p":"vip","t":"malam","b":"rimba","g":"dadu"},
    {"n":9,"q":16,"c":"paradiso","p":"vip","b":"peta","g":"tercecer","zentul":true},
    {"n":10,"q":16,"c":"zentul","p":"tiba","b":"kabut","g":"angin","arr":true,"cine":"mk_zentul"},
    {"n":11,"q":16,"c":"zentul","p":"lapau","b":"daftar"},
    {"n":12,"q":16,"c":"zentul","p":"sirkuit","b":"babak1","race":"pariopelan","garasi":true},
    {"n":13,"q":16,"c":"zentul","p":"garasi","b":"kencang"},
    {"n":14,"q":16,"c":"zentul","p":"pasar","b":"sukucadang","g":"manifest"},
    {"n":15,"q":16,"c":"zentul","p":"garasi","b":"katup","g":"tempa","jolt":true,"gold":"MkGoldQ16"},
    {"n":16,"q":17,"c":"zentul","p":"sirkuit","b":"babak1ulang","race":"pariopelan","win":true,"hint":3},
    {"n":17,"q":17,"c":"zentul","p":"sirkuit","b":"semifinal","race":"kapalmber","win":true,"kiat":3},
    {"n":18,"q":17,"c":"zentul","p":"garasi","b":"lapor"},
    {"n":19,"q":17,"c":"skitraw","p":"galangan","b":"polarantai","g":"sandi"},
    {"n":20,"q":17,"c":"bjorneo","p":"mercusuar","b":"nenekulin","teka":true,
      "flags":{"tembus":true,"paksa":true,"aman":true}},
    {"n":21,"q":17,"p":"tembus","b":"tembus","arr":true,"zona":true},
    {"n":22,"q":17,"p":"pasar","b":"agen","g":"timbang","zonaHere":true,
      "flags":{"gelap":true,"paksa":false,"aman":false}},
    {"n":23,"q":17,"c":"paradiso","p":"vip","t":"malam","b":"lapor2","gold":"MkGoldQ17","tanda":"duadetik"},
    {"n":24,"q":18,"c":"marie_regal","p":"lab","t":"malam","b":"rakbatu","g":"warga"},
    {"n":25,"q":18,"c":"marie_regal","p":"istana","t":"malam","b":"marlya","pilih":["maafkan","kabarkan"]},
    {"n":26,"q":18,"c":"zentul","p":"tiba","b":"selam","g":"selam","arr":true},
    {"n":27,"q":18,"c":"zentul","p":"garasi","b":"batubaterai","penuh":true,"warlord":true},
    {"n":28,"q":18,"c":"zentul","p":"sirkuit","b":"gerbang","race":"pariopelan","targetUs":"MkGerbangUs"},
    {"n":29,"q":18,"c":"zentul","p":"sirkuit","b":"final","race":"cangcimen_final","win":true,"kiat":3,"juara":true},
    {"n":30,"q":18,"c":"zentul","p":"dermaga","b":"barisan","g":"susun",
      "flags":{"paksa":true,"aman":true}},
    {"n":31,"q":18,"p":"banjir","b":"banjir1","g":"pesta","zona":true,"setor":true},
    {"n":32,"q":18,"p":"banjir","b":"banjir2","g":"jejak","zona":true,"setor":true},
    {"n":33,"q":18,"p":"banjir","b":"banjir3","g":"kas","zona":true,"setor":true,
      "gold":"MkGoldQ18","tanda":"banjirsutra","flags":{"paksa":false,"aman":false}},
    {"n":34,"q":19,"c":"ikn","p":"monumen","b":"hadapi","cine":"mk_benteng"},
    {"n":35,"q":19,"c":"toogood","p":"dok","b":"pengalih","setorBahan":true},
    {"n":36,"q":19,"c":"paradiso","p":"dermaga","b":"genderang","g":"genderang","ulang":true},
    {"n":37,"q":19,"c":"ikn","p":"heat","b":"heat1","race":"patroli_kuat","win":true,"heat":true,"arr":true},
    {"n":38,"q":19,"c":"ikn","p":"heat","b":"heat2","race":"patroli_kuat","win":true,"heat":true,
      "lewatiBila":"kabarkan"},
    {"n":39,"q":19,"c":"ikn","p":"heat","b":"heat3","race":"cangcimen_final","win":true,"heat":true,
      "lebarBila":"maafkan","cine":"mk_rantai"},
    {"n":40,"q":19,"c":"ikn","p":"dermaga","b":"stempel","pilih":["patahkan","dewan","marlya"],
      "gold":"MkGoldQ19","tanda":"sagakeempat","tamat":true}
  ]'::jsonb
$$;

-- ---------------------------------------------------------------------
-- Keadaan quest + status tamat
-- ---------------------------------------------------------------------
create or replace function game.mk_tamat(p_pid uuid) returns boolean
language sql stable as $$ select game.mk_step(p_pid) >= 40 $$;

create or replace function game.mk_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_step int; v_d jsonb; v_next jsonb;
begin
  if p_pid is null or not game.mk_eligible(p_pid) then return null; end if;
  select step, data into v_step, v_d from game.player_quests where player_id = p_pid and quest_id = 'mahkota';
  v_step := coalesce(v_step, 0); v_d := coalesce(v_d, '{}'::jsonb);
  v_next := game.mk_steps() -> v_step;
  -- heat kedua dilewati bila pemain memilih "kabarkan"
  if v_next is not null and v_next ? 'lewatiBila' and v_d ->> 'marlya' = (v_next ->> 'lewatiBila') then
    v_next := game.mk_steps() -> (v_step + 1);
  end if;
  return jsonb_build_object(
    'step', v_step, 'ada', game.mk_ada(), 'last', game.mk_last(),
    'd', v_next, 'data', v_d,
    'jolt', v_step >= 15 and v_step < 40, 'penuh', v_step >= 27 and v_step < 40,
    'garasi', v_step >= 12, 'zentul', v_step >= 9, 'warlord', v_step >= 27,
    'juara', v_step >= 29, 'tamat', v_step >= 40,
    'ulang', coalesce((v_d ->> 'ulang')::int, 0),
    'banjir', to_jsonb(game.mk_banjir(p_pid)),
    'zonaSisa', to_jsonb(array(select z from unnest(game.mh_zona(game.game_day())) z
                                where not (z = any (game.mk_banjir(p_pid))))));
exception when others then return null;
end $$;

-- ---------------------------------------------------------------------
-- Setelah tamat: Mesin Jolt pinjaman dilepas, Sirkuit terbuka penuh.
-- ---------------------------------------------------------------------
create or replace function game.trek_kapal(p_pid uuid) returns text
language sql stable as $$
  select case
    when array_length(game.wl_set(p_pid), 1) = 4 then 'warlord'
    when not game.mk_mulai(p_pid) or game.mk_tamat(p_pid) then 'jolt'
    when game.mk_step(p_pid) >= 27 then 'penuh'
    when game.mk_step(p_pid) >= 15 then 'jolt'
    else 'tanpa'
  end
$$;

create or replace function game.trek_lawan(p_pid uuid) returns text[]
language sql stable as $$
  select case
    when not game.mk_mulai(p_pid) or game.mk_tamat(p_pid) then array['pariopelan', 'kapalmber', 'cangcimen', 'yaptob']
    when game.mk_step(p_pid) >= 29 then array['pariopelan', 'kapalmber', 'cangcimen']
    when game.mk_step(p_pid) >= 17 then array['pariopelan', 'kapalmber']
    when game.mk_step(p_pid) >= 15 then array['pariopelan']
    else array[]::text[]
  end
$$;

create or replace function game.trek_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select case
    when p_pid is null then false
    when game.fitur_on(p_pid, 'TrekOpen') and lower(coalesce(game.cfg('TrekOpen'), '0')) not in ('1', 'true', 'on', 'ya') then true
    when game.in_transit(p_pid) or game.current_city(p_pid) is distinct from 'zentul' then false
    else game.fitur_on(p_pid, 'TrekOpen') or game.mk_step(p_pid) >= 15
  end
$$;

-- ---------------------------------------------------------------------
-- Set Kedai "Jaring Putus" — terbuka setelah Saga 4 tamat.
-- ---------------------------------------------------------------------
insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, req, exclusive, active, sort) values
  ('lambung_rantai', 'rupa', 'lambung', 'jaring_putus', 'Lambung Berlilit Rantai', 'legenda', 2400,
     'Potongan rantai biru yang patah masih melilit lambung, catnya mengelupas jadi karat.', null, '{"mahkota":true}', false, true, 390),
  ('layar_sutra_biru', 'rupa', 'layar', 'jaring_putus', 'Layar Banjir Sutra', 'legenda', 2400,
     'Sutra selundupan dari tiga zona, dijahit jadi satu layar yang tidak pernah kena cap.', null, '{"mahkota":true}', false, true, 391),
  ('panji_obor', 'rupa', 'panji', 'jaring_putus', 'Panji Obor Zentul', 'legenda', 2200,
     'Panji Barisan Pacu: obor kuning di atas dasar hitam berminyak.', null, '{"mahkota":true}', false, true, 392),
  ('jejak_garis_api', 'rupa', 'jejak', 'jaring_putus', 'Garis Api Selat', 'legenda', 2600,
     'Garis api tipis tertinggal di air di belakang buritan, persis jejak YusaintJolt.', null, '{"mahkota":true}', false, true, 393),
  ('datang_stempel', 'rupa', 'kedatangan', 'jaring_putus', 'Stempel Patah', 'legenda', 2600,
     'Saat merapat, sebuah stempel biru jatuh ke dermaga dan pecah jadi serpih cahaya.', null, '{"mahkota":true}', false, true, 394)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh, req = excluded.req,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

-- salinan 0057 + syarat Mahkota
create or replace function game.kd_req_ok(p_pid uuid, p_id text) returns boolean
language plpgsql stable as $$
declare r jsonb;
begin
  select i.req into r from game.kd_items i where i.id = p_id;
  if r is null then return true; end if;
  if r ? 'mahkota' then return game.mk_tamat(p_pid); end if;
  if r ? 'pasir' then
    return coalesce((select (data ->> (r ->> 'pasir'))::boolean from game.pasir_state where player_id = p_pid), false);
  end if;
  if not (r ? 'kisah') then return true; end if;
  return game.kisah_done(p_pid, r ->> 'kisah');
end $$;

do $$
begin
  drop function if exists game.kd_list_mk(uuid);
  alter function game.kd_list(uuid) rename to kd_list_mk;
end $$;
revoke all on function game.kd_list_mk(uuid) from public, anon, authenticated;

-- barang Saga 4 disembunyikan sampai tamat (atau sudah dimiliki)
create or replace function game.kd_list(p_pid uuid) returns jsonb
language plpgsql as $$
declare v jsonb; keep jsonb;
begin
  v := game.kd_list_mk(p_pid);
  if jsonb_typeof(v -> 'items') <> 'array' then return v; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into keep from jsonb_array_elements(v -> 'items') x
   where not (x -> 'req' ? 'mahkota') or coalesce((x ->> 'locked')::boolean, false) = false or coalesce((x ->> 'qty')::int, 0) > 0;
  return v || jsonb_build_object('items', keep);
end $$;

create or replace function game.kd_set_name(p_set text) returns text
language sql immutable as $$
  select case p_set when 'api_gunung' then 'Set Api Gunung' when 'naga_samudra' then 'Set Naga Samudra'
    when 'kapal_hantu' then 'Set Kapal Hantu' when 'badai_petir' then 'Set Badai Petir' when 'mutiara_paradiso' then 'Set Mutiara Paradiso'
    when 'zaman_gemilang' then 'Set Zaman Gemilang' when 'benang_merah' then 'Set Benang Merah' when 'pasir_waktu' then 'Set Pasir Waktu'
    when 'jaring_putus' then 'Set Jaring Putus' else p_set end
$$;
create or replace function game.kd_set_info(p_set text) returns text
language sql immutable as $$
  select case p_set
    when 'api_gunung' then 'Udara panas bergetar di sekitar kapal, letusan kecil sesekali dari puncak tiang, retakan makin terang saat malam.'
    when 'naga_samudra' then 'Naga air bening sesekali muncul dari laut, melingkari kapal, lalu menyelam. Saat kapal tiba, ia muncul menyambut.'
    when 'kapal_hantu' then 'Saat malam kapal menjadi tembus pandang, bayangan awak alniu siarfi berjalan di dek, dan wajah kapal itu sesekali tampak di permukaan air.'
    when 'badai_petir' then 'Awan badai kecil mengikuti di atas kapal dengan hujan tipis; petir menyambar tiang setiap beberapa detik.'
    when 'mutiara_paradiso' then 'Dua lumba-lumba melompat bergantian di samping kapal; saat tiba, kelopak bunga berjatuhan.'
    when 'zaman_gemilang' then 'Kapalmu tampak bernada sepia lembut, seperti foto dari zaman ketika lampu IKN sampai ke tengah laut.'
    when 'benang_merah' then 'Seutas benang merah terulur dari tiangmu ke cakrawala, menuju seseorang yang kau ingat.'
    when 'pasir_waktu' then 'Saat merapat, jam pasir kecil berputar di atas tiang.'
    when 'jaring_putus' then 'Serpih rantai biru melayang pelan di sekeliling kapal, lalu padam seperti bara. Saat merapat, satu stempel jatuh dan pecah.'
    else '' end
$$;

-- ---------------------------------------------------------------------
-- Berlayar = kesempatan heat baru.
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.api_setsail_q19(jsonb);
  alter function public.api_setsail(jsonb) rename to api_setsail_q19;
  alter function public.api_setsail_q19(jsonb) set schema game;
end $$;
revoke all on function game.api_setsail_q19(jsonb) from public, anon, authenticated;

create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb;
begin
  r := game.api_setsail_q19(a);
  begin
    if v_pid is not null then
      update game.player_quests set data = data - 'heatKunci'
       where player_id = v_pid and quest_id = 'mahkota' and data ? 'heatKunci';
    end if;
  exception when others then null;
  end;
  return r;
end $$;
select game.expose('api_setsail');

-- ---------------------------------------------------------------------
-- api_mahkota: heat berantai, setoran bahan pengalih, penutup saga.
-- ---------------------------------------------------------------------
create or replace function public.api_mahkota(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status');
  v_want int := game.arg_int(a, 1);
  v_res text := lower(btrim(coalesce(game.arg(a, 2), '')));
  v_step int; d jsonb; v_city text; v_gold bigint := 0; v_oli int := 0; v_id uuid; h jsonb; t jsonb;
  v_data jsonb; v_jeda numeric; k text; v_qty int; v_bayar bigint := 0; r record; v_sisa int; v_banjir jsonb;
  v_skip int := 0; v_bahan jsonb; b record; v_kurang text := '';
begin
  if v_act = 'status' then return jsonb_build_object('mahkota', game.mk_state(v_pid)); end if;
  if v_act not in ('maju', 'balap', 'selesai', 'teka', 'pilih') then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.mk_eligible(v_pid) then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  insert into game.player_quests(player_id, quest_id, step, data) values (v_pid, 'mahkota', 0, '{}'::jsonb)
  on conflict (player_id, quest_id) do nothing;
  select step, data into v_step, v_data from game.player_quests where player_id = v_pid and quest_id = 'mahkota' for update;
  v_data := coalesce(v_data, '{}'::jsonb);

  if v_step >= game.mk_ada() then raise exception 'Ceritanya berhenti di sini dulu, Kapten. Bersambung.'; end if;
  -- heat kedua dilewati bila memilih "kabarkan"
  d := game.mk_steps() -> v_step;
  if d is not null and d ? 'lewatiBila' and v_data ->> 'marlya' = (d ->> 'lewatiBila') then
    v_skip := 1; v_step := v_step + 1; d := game.mk_steps() -> v_step;
  end if;
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  v_city := game.current_city(v_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if coalesce((d ->> 'zonaHere')::boolean, false) and v_city is distinct from (v_data ->> 'zona') then
    raise exception 'Agen itu menunggu di pasar tempat kau menembus jaring, Kapten.';
  end if;
  if coalesce((d ->> 'setor')::boolean, false) then
    if coalesce((v_data ->> 'tembusOk')::int, -1) <> v_step then
      raise exception 'Jaringnya belum kau tembus, Kapten. Berlayarlah ke zona yang belum dibanjiri.';
    end if;
    if v_city is distinct from (v_data ->> 'zona') then
      raise exception 'Barisan Pacu menunggu di pasar tempat kau menembus jaring, Kapten.';
    end if;
  elsif coalesce((d ->> 'zona')::boolean, false) and v_act <> 'status' then
    raise exception 'Berlayarlah ke pulau bertanda cukai, Kapten. Jaring itu yang akan menemukanmu.';
  end if;
  if d ->> 't' = 'malam' and not game.fish_is_night() then raise exception 'Datanglah lagi saat lampu-lampu dinyalakan, Kapten.'; end if;
  -- heat: kalah tanpa sisa kesempatan = harus berlayar lagi ke IKN
  if coalesce((d ->> 'heat')::boolean, false) and v_act in ('balap', 'maju') and coalesce((v_data ->> 'heatKunci')::boolean, false) then
    raise exception 'Gerbang rantai sudah menutup, Kapten. Mundur ke laut lepas, lalu datang lagi ke IKN.';
  end if;

  -- ---------------- pilihan cerita ----------------
  if v_act = 'pilih' then
    if not (d ? 'pilih') then raise exception 'Tidak ada yang harus dipilih di sini, Kapten.'; end if;
    if not (d -> 'pilih' @> to_jsonb(v_res)) then raise exception 'Pilihan tidak dikenali.'; end if;
    k := case when coalesce((d ->> 'tamat')::boolean, false) then 'stempel' else 'marlya' end;
    v_data := v_data || jsonb_build_object(k, v_res);
    update game.player_quests set data = data || jsonb_build_object(k, v_res) where player_id = v_pid and quest_id = 'mahkota';
  elsif d ? 'pilih' and v_act = 'maju' then
    raise exception 'Keputusannya ada di tanganmu, Kapten.';
  end if;

  -- ---------------- teka-teki ----------------
  if v_act = 'teka' then
    if not coalesce((d ->> 'teka')::boolean, false) then raise exception 'Tidak ada teka-teki di sini, Kapten.'; end if;
    v_jeda := greatest(0, game.cfg_num('MkTekaJedaDetik', 20)) * 1000;
    if coalesce((v_data ->> 'tekaAt')::bigint, 0) + v_jeda > game.now_ms() then
      return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', false, 'teka', false,
        'tunggu', ceil((coalesce((v_data ->> 'tekaAt')::bigint, 0) + v_jeda - game.now_ms()) / 1000.0)::int,
        'pesan', 'Nenek Ulin menutup matanya. "Sabar, Nak. Pikir dulu, baru bicara."');
    end if;
    if not game.mk_teka_benar(v_res) then
      update game.player_quests set data = data || jsonb_build_object('tekaAt', game.now_ms(), 'tekaSalah',
        coalesce((v_data ->> 'tekaSalah')::int, 0) + 1), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota';
      return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', false, 'teka', false,
        'tunggu', ceil(v_jeda / 1000.0)::int,
        'pesan', 'Nenek Ulin menggeleng pelan. "Bukan itu, Nak. Batu itu tidak diam. Ia menyimpan sesuatu."');
    end if;
  elsif coalesce((d ->> 'teka')::boolean, false) and v_act = 'maju' then
    raise exception 'Jawab dulu teka-tekinya, Kapten.';
  end if;

  -- ---------------- balapan ----------------
  if v_act = 'balap' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    t := game.trek_mulai(v_pid, 'turnamen', d ->> 'race', game.trek_kapal(v_pid));
    return jsonb_build_object('trek', t, 'mahkota', game.mk_state(v_pid),
      'lebar', d ? 'lebarBila' and v_data ->> 'marlya' = (d ->> 'lebarBila'),
      'target', case when d ? 'targetUs' then game.cfg_num(d ->> 'targetUs', 10300000) end);
  end if;

  if v_act = 'selesai' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    begin v_id := game.arg(a, 2)::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
    h := game.trek_selesai(v_pid, v_id, case when jsonb_typeof(a) = 'array' then a -> 3 end, 'turnamen');
    if d ? 'targetUs' then
      if coalesce((h ->> 'me')::bigint, 9999999999) > game.cfg_num(d ->> 'targetUs', 10300000) then
        return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false,
          'target', game.cfg_num(d ->> 'targetUs', 10300000));
      end if;
    elsif coalesce((d ->> 'win')::boolean, false) and not coalesce((h ->> 'win')::boolean, false) then
      v_qty := coalesce((v_data ->> ('kalah' || v_step))::int, 0) + 1;
      v_sisa := coalesce((v_data ->> 'ulang')::int, 0);
      if coalesce((d ->> 'heat')::boolean, false) then
        -- kesempatan dari genderang dipakai dulu; kalau habis, harus berlayar lagi ke IKN
        if v_sisa > 0 then
          update game.player_quests set data = data || jsonb_build_object('ulang', v_sisa - 1, 'kalah' || v_step, v_qty)
           where player_id = v_pid and quest_id = 'mahkota';
        else
          update game.player_quests set data = data || jsonb_build_object('heatKunci', true, 'kalah' || v_step, v_qty)
           where player_id = v_pid and quest_id = 'mahkota';
        end if;
      else
        update game.player_quests set data = data || jsonb_build_object('kalah' || v_step, v_qty), updated_at = now()
         where player_id = v_pid and quest_id = 'mahkota';
      end if;
      return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false, 'kalah', v_qty,
        'kunci', coalesce((d ->> 'heat')::boolean, false) and v_sisa <= 0,
        'ulangSisa', greatest(0, v_sisa - case when coalesce((d ->> 'heat')::boolean, false) then 1 else 0 end));
    end if;
    v_res := 'ok';
  end if;

  -- ---------------- syarat mini game ----------------
  if v_act = 'maju' then
    if d ? 'race' then raise exception 'Turun dulu ke garis start, Kapten.'; end if;
    if d ? 'g' and v_res not in ('ok', 'menang') then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;
  end if;

  -- ---------------- setoran bahan pengalih (langkah 35) ----------------
  if coalesce((d ->> 'setorBahan')::boolean, false) and v_act = 'maju' then
    v_bahan := jsonb_build_object('oli_hitam', greatest(0, game.cfg_num('MkPengalihOli', 20))::int,
                                  'besi', greatest(0, game.cfg_num('MkPengalihBesi', 20))::int,
                                  'mesiu', greatest(0, game.cfg_num('MkPengalihMesiu', 10))::int);
    for b in select key as id, value::text::int as n from jsonb_each(v_bahan) loop
      if game.item_qty(v_pid, b.id) < b.n then
        v_kurang := v_kurang || case when v_kurang = '' then '' else ', ' end ||
          (b.n - game.item_qty(v_pid, b.id))::text || ' ' || coalesce((select name from game.commodities where id = b.id), b.id);
      end if;
    end loop;
    if v_kurang <> '' then raise exception 'Bahan pengalih masih kurang: %.', v_kurang; end if;
    for b in select key as id, value::text::int as n from jsonb_each(v_bahan) loop
      perform game.adjust_inventory(v_pid, b.id, -b.n);
    end loop;
  end if;

  -- ---------------- setoran Banjir Sutra ----------------
  if coalesce((d ->> 'setor')::boolean, false) and v_act in ('maju', 'pilih') then
    v_qty := greatest(1, game.cfg_num('MkBanjirQty', 15))::int;
    v_sisa := v_qty;
    for r in select i.item_id, i.qty from game.inventory i join game.commodities c on c.id = i.item_id
              where i.player_id = v_pid and i.qty > 0 and c.tier = 'premium' order by c.sort, i.item_id loop
      exit when v_sisa <= 0;
      v_sisa := v_sisa - least(v_sisa, r.qty);
    end loop;
    if v_sisa > 0 then
      raise exception 'Barisan Pacu butuh % unit barang premium di palkamu, Kapten. Kurang %.', v_qty, v_sisa;
    end if;
    v_sisa := v_qty;
    for r in select i.item_id, i.qty from game.inventory i join game.commodities c on c.id = i.item_id
              where i.player_id = v_pid and i.qty > 0 and c.tier = 'premium' order by c.sort, i.item_id loop
      exit when v_sisa <= 0;
      v_qty := least(v_sisa, r.qty);
      v_bayar := v_bayar + (v_qty::bigint * game.mk_harga_jual(v_pid, v_city, r.item_id));
      perform game.adjust_inventory(v_pid, r.item_id, -v_qty);
      v_sisa := v_sisa - v_qty;
    end loop;
    if v_bayar > 0 then update game.players set gold = gold + v_bayar where player_id = v_pid; end if;
    v_banjir := coalesce(v_data -> 'banjir', '[]'::jsonb);
    if not (v_banjir @> to_jsonb(v_city)) then v_banjir := v_banjir || to_jsonb(v_city); end if;
    update game.player_quests set data = (data - 'tembusOk') || jsonb_build_object('banjir', v_banjir)
     where player_id = v_pid and quest_id = 'mahkota';
  end if;

  -- ---------------- efek langkah ----------------
  if coalesce((d ->> 'krisis')::boolean, false) then
    insert into game.mh_player(player_id, krisis) values (v_pid, true)
    on conflict (player_id) do update set krisis = true, updated_at = now();
  end if;
  if jsonb_typeof(d -> 'flags') = 'object' then
    insert into game.mh_player(player_id, krisis) values (v_pid, true) on conflict (player_id) do nothing;
    for k in select jsonb_object_keys(d -> 'flags') loop
      if k = 'tembus' then update game.mh_player set tembus = (d -> 'flags' -> k)::text::boolean, updated_at = now() where player_id = v_pid;
      elsif k = 'gelap' then update game.mh_player set gelap = (d -> 'flags' -> k)::text::boolean, updated_at = now() where player_id = v_pid;
      elsif k = 'paksa' then update game.mh_player set paksa = (d -> 'flags' -> k)::text::boolean, updated_at = now() where player_id = v_pid;
      elsif k = 'aman' then update game.mh_player set aman = (d -> 'flags' -> k)::text::boolean, updated_at = now() where player_id = v_pid;
      end if;
    end loop;
  end if;
  -- genderang: satu kesempatan ulang heat
  if coalesce((d ->> 'ulang')::boolean, false) and v_res = 'menang' then
    update game.player_quests set data = data || jsonb_build_object('ulang', coalesce((v_data ->> 'ulang')::int, 0) + 1)
     where player_id = v_pid and quest_id = 'mahkota';
  end if;
  if d ->> 'g' = 'dadu' and v_res = 'menang' then
    v_oli := greatest(0, game.cfg_num('MkOliDadu', 3))::int;
    if v_oli > 0 and game.cargo_free(v_pid) >= v_oli * coalesce((select size from game.commodities where id = 'oli_hitam'), 1) then
      perform game.adjust_inventory(v_pid, 'oli_hitam', v_oli);
    else v_oli := 0;
    end if;
  end if;
  if d ? 'gold' then
    v_gold := greatest(0, game.cfg_num(d ->> 'gold', 0))::bigint;
    if v_gold > 0 then update game.players set gold = gold + v_gold where player_id = v_pid; end if;
  end if;

  -- ---------------- penutup saga ----------------
  if coalesce((d ->> 'tamat')::boolean, false) then
    update game.mh_player set krisis = false, tembus = false, gelap = false, paksa = false, aman = false,
      zona_tuju = null, gelap_city = null, gelap_cargo = '{}'::jsonb, updated_at = now() where player_id = v_pid;
    update game.player_quests set done_at = now() where player_id = v_pid and quest_id = 'mahkota';
    perform game.log(v_pid, 'Saga Keempat selesai: Jaring Rantai putus di gerbang IKN.');
  end if;

  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = (data - 'heatKunci') || jsonb_build_object('s' || (v_step + 1), game.now_ms())
   where player_id = v_pid and quest_id = 'mahkota';
  if not coalesce((d ->> 'tamat')::boolean, false) then
    perform game.log(v_pid, 'Mahkota: langkah ' || (v_step + 1) || ' selesai.');
  end if;

  return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', true, 'gold', v_gold, 'oli', v_oli,
    'bayar', v_bayar, 'tanda', d ->> 'tanda', 'tamat', coalesce((d ->> 'tamat')::boolean, false),
    'lewati', v_skip = 1, 'hasil', h, 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_mahkota');
