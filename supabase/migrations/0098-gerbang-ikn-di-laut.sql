-- =====================================================================
-- 0098 · Gerbang rantai IKN: heat 37-39 dimainkan di laut, kapal tidak sandar di IKN sebelum Juru Sita kalah
--   * langkah 37-39 tanpa syarat kota (dimainkan saat sauh ke IKN diangkat)
--   * api_setSail menolak tujuan IKN selama langkah 37-39 belum selesai
--   * kalah di gerbang mana pun = ulang dari heat 1
-- Aman diulang.
-- =====================================================================

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
    {"n":10,"q":16,"p":"laut","b":"kabut","g":"angin"},
    {"n":11,"q":16,"c":"zentul","p":"lapau","b":"daftar","cine":"mk_zentul"},
    {"n":12,"q":16,"c":"zentul","p":"sirkuit","b":"babak1","race":"pariopelan","garasi":true},
    {"n":13,"q":16,"c":"zentul","p":"garasi","b":"kencang"},
    {"n":14,"q":16,"c":"zentul","p":"pasar","b":"sukucadang","g":"manifest"},
    {"n":15,"q":16,"c":"zentul","p":"garasi","b":"katup","g":"tempa","batas":true,"jolt":true,"gold":"MkGoldQ16"},
    {"n":16,"q":17,"c":"zentul","p":"sirkuit","b":"babak1ulang","race":"pariopelan","win":true,"batas":true,"hint":3},
    {"n":17,"q":17,"c":"zentul","p":"sirkuit","b":"semifinal","race":"kapalmber","win":true,"batas":true,"kiat":3},
    {"n":18,"q":17,"c":"zentul","p":"garasi","b":"lapor"},
    {"n":19,"q":17,"c":"skitraw","p":"galangan","b":"polarantai","g":"sandi"},
    {"n":20,"q":17,"c":"bjorneo","p":"mercusuar","b":"nenekulin","teka":true,"oleh":10,"flags":{"tembus":true,"paksa":true,"aman":true}},
    {"n":21,"q":17,"p":"tembus","b":"tembus","arr":true,"zona":true},
    {"n":22,"q":17,"p":"pasar","b":"agen","g":"timbang","zonaHere":true,"flags":{"gelap":true,"paksa":false,"aman":false}},
    {"n":23,"q":17,"c":"paradiso","p":"vip","t":"malam","b":"lapor2","gold":"MkGoldQ17","tanda":"duadetik"},
    {"n":24,"q":18,"c":"marie_regal","p":"lab","t":"malam","b":"rakbatu","g":"warga"},
    {"n":25,"q":18,"c":"marie_regal","p":"istana","t":"malam","b":"marlya","pilih":["maafkan","kabarkan"]},
    {"n":26,"q":18,"c":"zentul","p":"tiba","b":"selam","g":"selam","arr":true},
    {"n":27,"q":18,"c":"zentul","p":"garasi","b":"batubaterai","penuh":true,"warlord":true},
    {"n":28,"q":18,"c":"zentul","p":"sirkuit","b":"gerbang","race":"pariopelan","targetUs":"MkGerbangUs"},
    {"n":29,"q":18,"c":"zentul","p":"sirkuit","b":"final","race":"cangcimen_final","win":true,"batas":true,"kiat":3,"juara":true},
    {"n":30,"q":18,"c":"zentul","p":"dermaga","b":"barisan","g":"susun","flags":{"paksa":true,"aman":true}},
    {"n":31,"q":18,"p":"banjir","b":"banjir1","g":"pesta","zona":true,"setor":true},
    {"n":32,"q":18,"p":"banjir","b":"banjir2","g":"jejak","zona":true,"setor":true},
    {"n":33,"q":18,"p":"banjir","b":"banjir3","g":"kas","zona":true,"setor":true,"gold":"MkGoldQ18","tanda":"banjirsutra","flags":{"paksa":false,"aman":false}},
    {"n":34,"q":19,"c":"ikn","p":"monumen","b":"hadapi","cine":"mk_benteng"},
    {"n":35,"q":19,"c":"toogood","p":"dok","b":"pengalih","setorBahan":true},
    {"n":36,"q":19,"c":"paradiso","p":"dermaga","b":"genderang","g":"genderang","ulang":true},
    {"n":37,"q":19,"p":"heat","b":"heat1","race":"patroli_kuat","win":true,"heat":true,"arr":true},
    {"n":38,"q":19,"p":"heat","b":"heat2","race":"patroli_kuat","win":true,"heat":true,"lewatiBila":"kabarkan"},
    {"n":39,"q":19,"p":"heat","b":"heat3","race":"cangcimen_final","win":true,"heat":true,"lebarBila":"maafkan","cine":"mk_rantai"},
    {"n":40,"q":19,"c":"ikn","p":"dermaga","b":"stempel","pilih":["patahkan","dewan","marlya"],"gold":"MkGoldQ19","tanda":"sagakeempat","tamat":true}
  ]'::jsonb
$$;

-- Rantai gerbang IKN: selama heat belum selesai (langkah 37-39), kapal tidak boleh sandar di IKN.
create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb;
begin
  if v_pid is not null and game.arg(a, 0) = 'ikn' and exists (
       select 1 from game.player_quests where player_id = v_pid and quest_id = 'mahkota' and step between 36 and 38) then
    raise exception 'Rantai gerbang IKN masih terpasang, Kapten. Tembus dulu tiga gerbangnya.';
  end if;
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
  v_maks int; v_hari int; v_kb text; v_cn int := 0;
begin
  if v_act = 'status' then return jsonb_build_object('mahkota', game.mk_state(v_pid)); end if;
  if v_act not in ('maju', 'balap', 'selesai', 'teka', 'pilih', 'oleh', 'coba') then raise exception 'Aksi tidak dikenal.'; end if;
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

  -- ---------------- batas percobaan per hari game (tempa Yaptob, balapan Pariopelan/KapalMber) ----------------
  v_maks := greatest(0, game.cfg_num('MkBatasHari', 2))::int;   -- 0 = tanpa batas
  v_hari := game.game_day();
  v_kb := 'cb' || v_step;
  if d ? 'batas' then
    v_cn := case when (v_data -> v_kb ->> 'h') = v_hari::text then coalesce((v_data -> v_kb ->> 'n')::int, 0) else 0 end;
  end if;

  -- ---------------- oleh-oleh Nenek Ulin (langkah 20) ----------------
  if v_act = 'oleh' then
    if not (d ? 'oleh') then raise exception 'Tidak ada yang perlu diserahkan di sini, Kapten.'; end if;
    if coalesce((v_data ->> 'olehOk')::boolean, false) then
      return jsonb_build_object('mahkota', game.mk_state(v_pid), 'oleh', true);
    end if;
    v_qty := greatest(1, game.cfg_num('MkOlehSutra', (d ->> 'oleh')::numeric))::int;
    if game.item_qty(v_pid, 'silk') < v_qty then
      raise exception 'Nenek Ulin menunggu % Sutra untuk oleh-oleh, Kapten. Palkamu baru punya %.', v_qty, game.item_qty(v_pid, 'silk');
    end if;
    perform game.adjust_inventory(v_pid, 'silk', -v_qty);
    update game.player_quests set data = data || jsonb_build_object('olehOk', true), updated_at = now()
     where player_id = v_pid and quest_id = 'mahkota';
    return jsonb_build_object('mahkota', game.mk_state(v_pid), 'oleh', true, 'qty', v_qty);
  end if;

  -- ---------------- tempa: dua percobaan per hari game ----------------
  if v_act = 'coba' then
    if not (d ? 'batas') or d ->> 'g' is distinct from 'tempa' then raise exception 'Tidak ada yang perlu ditempa di sini, Kapten.'; end if;
    if v_maks > 0 and v_cn >= v_maks then
      raise exception 'Tungku tempa sudah terlalu panas, kembalilah besok, Kapten. (Hari game berikutnya sekitar % menit lagi.)', game.minutes_to_next_day();
    end if;
    update game.player_quests set data = data || jsonb_build_object(v_kb, jsonb_build_object('h', v_hari, 'n', v_cn + 1)), updated_at = now()
     where player_id = v_pid and quest_id = 'mahkota';
    return jsonb_build_object('mahkota', game.mk_state(v_pid), 'coba', true, 'sisaHari', case when v_maks > 0 then greatest(0, v_maks - v_cn - 1) end);
  end if;

  -- ---------------- teka-teki ----------------
  if v_act = 'teka' then
    if not coalesce((d ->> 'teka')::boolean, false) then raise exception 'Tidak ada teka-teki di sini, Kapten.'; end if;
    if d ? 'oleh' and not coalesce((v_data ->> 'olehOk')::boolean, false) then
      raise exception 'Nenek Ulin belum mau bicara, Kapten. Bawakan dulu oleh-oleh untuknya.';
    end if;
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
    if d ? 'batas' and v_maks > 0 and v_cn >= v_maks then
      raise exception 'Mesin sudah terlalu panas, bisa hancur kalau dipaksa terus. Kembalilah besok, Kapten. (Hari game berikutnya sekitar % menit lagi.)', game.minutes_to_next_day();
    end if;
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
        -- gagal di gerbang mana pun = ulang dari heat 1 (langkah 37)
        update game.player_quests set step = 36, updated_at = now(),
               data = (case when v_sisa > 0 then data || jsonb_build_object('ulang', v_sisa - 1) else data end)
                      || jsonb_build_object('kalah' || v_step, v_qty)
         where player_id = v_pid and quest_id = 'mahkota';
      else
        update game.player_quests set data = data || jsonb_build_object('kalah' || v_step, v_qty), updated_at = now()
         where player_id = v_pid and quest_id = 'mahkota';
        if d ? 'batas' then
          v_cn := v_cn + 1;   -- kegagalan ke-n hari ini
          update game.player_quests set data = data || jsonb_build_object(v_kb, jsonb_build_object('h', v_hari, 'n', v_cn))
           where player_id = v_pid and quest_id = 'mahkota';
        end if;
      end if;
      return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false, 'kalah', v_qty,
        'panas', d ? 'batas' and v_maks > 0 and v_cn >= v_maks,
        'sisaHari', case when d ? 'batas' and v_maks > 0 then greatest(0, v_maks - v_cn) end,
        'menit', case when d ? 'batas' and v_maks > 0 and v_cn >= v_maks then game.minutes_to_next_day() end,
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
