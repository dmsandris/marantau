-- =====================================================================
-- 0077 · Saga 4 batch 4b — QUEST MAHKOTA langkah 24-33 (Q18 "Mahkota yang Ditawarkan Lagi")
--   24 Robot yang tidak bisa bohong   29 Final Turnamen Obor lawan cangcimen (wajib menang)
--   25 Kunci Ratu (+ pilihan marlya)  30 Barisan Pacu
--   26 Pelampung yang tenggelam       31-33 Tiga Banjir Sutra (tembus + setor 15 premium + mini game)
--   27 Jolt Penuh + Cetak Biru Warlord
--   28 Gerbang bambu (< 10,30 detik)
-- Aman diulang. Menimpa game.mk_steps dari 0076.
-- =====================================================================

insert into game.config(key, value) values
  ('MkGoldQ18', '150000'), ('MkBanjirQty', '15'), ('MkGerbangUs', '10300000')
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
      "gold":"MkGoldQ18","tanda":"banjirsutra","flags":{"paksa":false,"aman":false}}
  ]'::jsonb
$$;

-- Mesin Jolt Tahap 2 "Jolt Penuh" setelah langkah 27.
create or replace function game.trek_kapal(p_pid uuid) returns text
language sql stable as $$
  select case
    when not game.mk_mulai(p_pid) then 'jolt'
    when game.mk_step(p_pid) >= 27 then 'penuh'
    when game.mk_step(p_pid) >= 15 then 'jolt'
    else 'tanpa'
  end
$$;

create or replace function game.trek_lawan(p_pid uuid) returns text[]
language sql stable as $$
  select case
    when not game.mk_mulai(p_pid) then array['pariopelan', 'kapalmber', 'cangcimen', 'yaptob']
    when game.mk_step(p_pid) >= 29 then array['pariopelan', 'kapalmber', 'cangcimen']
    when game.mk_step(p_pid) >= 17 then array['pariopelan', 'kapalmber']
    when game.mk_step(p_pid) >= 15 then array['pariopelan']
    else array[]::text[]
  end
$$;

-- Zona yang sudah dibanjiri (langkah 31-33)
create or replace function game.mk_banjir(p_pid uuid) returns text[]
language sql stable as $$
  select coalesce(array(select jsonb_array_elements_text(
    coalesce((select data -> 'banjir' from game.player_quests where player_id = p_pid and quest_id = 'mahkota'), '[]'::jsonb))), '{}'::text[])
$$;

create or replace function game.mk_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_step int; v_d jsonb;
begin
  if p_pid is null or not game.mk_eligible(p_pid) then return null; end if;
  select step, data into v_step, v_d from game.player_quests where player_id = p_pid and quest_id = 'mahkota';
  v_step := coalesce(v_step, 0);
  return jsonb_build_object(
    'step', v_step, 'ada', game.mk_ada(), 'last', game.mk_last(),
    'd', game.mk_steps() -> v_step,
    'data', coalesce(v_d, '{}'::jsonb),
    'jolt', v_step >= 15, 'penuh', v_step >= 27, 'garasi', v_step >= 12, 'zentul', v_step >= 9,
    'warlord', v_step >= 27, 'juara', v_step >= 29,
    'banjir', to_jsonb(game.mk_banjir(p_pid)),
    'zonaSisa', to_jsonb(array(select z from unnest(game.mh_zona(game.game_day())) z
                                where not (z = any (game.mk_banjir(p_pid))))));
exception when others then return null;
end $$;

-- Harga jual "pasar normal" untuk setoran Banjir (tanpa pengali cukai / pasar gelap).
create or replace function game.mk_harga_jual(p_pid uuid, p_city text, p_comm text) returns int
language plpgsql stable as $$
declare m game.market; c game.commodities; mu record; s numeric; cyc bigint := game.mkt_cycle_index();
begin
  select * into m from game.market where city_id = p_city and commodity_id = p_comm;
  select * into c from game.commodities where id = p_comm and active;
  if c.id is null then return 0; end if;
  select * into mu from game.eco2_muls_inti(p_pid, p_city, p_comm);
  if m.city_id is null then
    return greatest(1, round(c.base * mu.ev_mul * mu.sell_mul))::int;
  end if;
  s := game.mkt_project(m.stock, m.at, m.cyc, m.role, c.tier, c.ref, c.id, game.mkt_cycle_tags(p_city, cyc), cyc);
  return greatest(1, round(game.mkt_mid2((c.base * mu.ev_mul)::numeric, c.ref, c.elast,
    game.mkt_lotx(s + 0.5, c.tier), m.role, c.tier) * mu.sell_mul))::int;
end $$;

-- ---------------------------------------------------------------------
-- Hasil Tembus Jaring: langkah 21 (maju) dan langkah 31-33 (menandai zona siap disetori)
-- ---------------------------------------------------------------------
create or replace function game.mh_cukai_act(p_pid uuid, p_tactic text, p_run text default null, p_log jsonb default null) returns jsonb
language plpgsql as $$
declare r jsonb; v_step int; d jsonb;
begin
  r := game.mh_cukai_act_mk(p_pid, p_tactic, p_run, p_log);
  begin
    if coalesce((r ->> 'success')::boolean, false) and r ->> 'result' = 'tembus' then
      v_step := game.mk_step(p_pid);
      d := game.mk_steps() -> v_step;
      if d is not null and coalesce((d ->> 'zona')::boolean, false) then
        if coalesce((d ->> 'setor')::boolean, false) then
          -- Banjir: tembus hanya membuka setoran di kota itu; langkah selesai di pasar
          update game.player_quests
             set data = data || jsonb_build_object('tembusOk', v_step, 'zona', r ->> 'cityId'), updated_at = now()
           where player_id = p_pid and quest_id = 'mahkota';
        else
          update game.player_quests
             set step = v_step + 1, updated_at = now(),
                 data = data || jsonb_build_object('s' || (v_step + 1), game.now_ms(), 'zona', r ->> 'cityId')
           where player_id = p_pid and quest_id = 'mahkota';
          perform game.log(p_pid, 'Mahkota: langkah ' || (v_step + 1) || ' selesai.');
        end if;
        r := r || jsonb_build_object('mahkota', game.mk_state(p_pid));
      end if;
    end if;
  exception when others then null;
  end;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- api_mahkota: tambahan 'pilih' (langkah 25) + setoran Banjir + gerbang bambu.
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
  if v_want is null or v_want <> v_step then raise exception 'Ceritanya sudah bergeser, Kapten. Dengarkan lagi.'; end if;

  d := game.mk_steps() -> v_step;
  v_city := game.current_city(v_pid);
  if d ? 'c' and v_city is distinct from (d ->> 'c') then raise exception 'Tidak ada yang perlu dibicarakan di sini, Kapten.'; end if;
  if coalesce((d ->> 'zonaHere')::boolean, false) and v_city is distinct from (v_data ->> 'zona') then
    raise exception 'Agen itu menunggu di pasar tempat kau menembus jaring, Kapten.';
  end if;
  -- langkah Banjir: tembus dulu, baru setoran di kota itu
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

  -- ---------------- pilihan cerita (langkah 25) ----------------
  if v_act = 'pilih' then
    if not (d ? 'pilih') then raise exception 'Tidak ada yang harus dipilih di sini, Kapten.'; end if;
    if not (d -> 'pilih' @> to_jsonb(v_res)) then raise exception 'Pilihan tidak dikenali.'; end if;
    v_data := v_data || jsonb_build_object('marlya', v_res);
    update game.player_quests set data = data || jsonb_build_object('marlya', v_res) where player_id = v_pid and quest_id = 'mahkota';
  elsif d ? 'pilih' and v_act = 'maju' then
    raise exception 'Jawab dulu tawaran Ratu, Kapten.';
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
      'target', case when d ? 'targetUs' then game.cfg_num(d ->> 'targetUs', 10300000) end);
  end if;

  if v_act = 'selesai' then
    if not (d ? 'race') then raise exception 'Tidak ada balapan di langkah ini, Kapten.'; end if;
    begin v_id := game.arg(a, 2)::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
    h := game.trek_selesai(v_pid, v_id, case when jsonb_typeof(a) = 'array' then a -> 3 end, 'turnamen');
    -- gerbang bambu: lawan waktu, bukan lawan kapal
    if d ? 'targetUs' then
      if coalesce((h ->> 'me')::bigint, 9999999999) > game.cfg_num(d ->> 'targetUs', 10300000) then
        return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false,
          'target', game.cfg_num(d ->> 'targetUs', 10300000));
      end if;
    elsif coalesce((d ->> 'win')::boolean, false) and not coalesce((h ->> 'win')::boolean, false) then
      update game.player_quests set data = data || jsonb_build_object('kalah' || v_step,
        coalesce((v_data ->> ('kalah' || v_step))::int, 0) + 1), updated_at = now()
       where player_id = v_pid and quest_id = 'mahkota';
      return jsonb_build_object('hasil', h, 'mahkota', game.mk_state(v_pid), 'maju', false,
        'kalah', coalesce((v_data ->> ('kalah' || v_step))::int, 0) + 1);
    end if;
    v_res := 'ok';
  end if;

  -- ---------------- syarat mini game ----------------
  if v_act = 'maju' then
    if d ? 'race' then raise exception 'Turun dulu ke garis start, Kapten.'; end if;
    if d ? 'g' and v_res not in ('ok', 'menang') then raise exception 'Belum berhasil, Kapten. Coba lagi.'; end if;
  end if;

  -- ---------------- setoran Banjir Sutra ----------------
  if coalesce((d ->> 'setor')::boolean, false) and v_act in ('maju', 'pilih') then
    v_qty := greatest(1, game.cfg_num('MkBanjirQty', 15))::int;
    v_sisa := v_qty;
    for r in select i.item_id, i.qty, c.base from game.inventory i join game.commodities c on c.id = i.item_id
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

  update game.player_quests set step = v_step + 1, updated_at = now(),
    data = data || jsonb_build_object('s' || (v_step + 1), game.now_ms())
   where player_id = v_pid and quest_id = 'mahkota';
  perform game.log(v_pid, 'Mahkota: langkah ' || (v_step + 1) || ' selesai.');

  return jsonb_build_object('mahkota', game.mk_state(v_pid), 'maju', true, 'gold', v_gold, 'oli', v_oli,
    'bayar', v_bayar, 'tanda', d ->> 'tanda', 'hasil', h, 'newGold', (select gold from game.players where player_id = v_pid));
end $$;
select game.expose('api_mahkota');
