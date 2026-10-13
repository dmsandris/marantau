-- =====================================================================
-- Marantau (Supabase) - 0023 SAGA 2 · QUEST 5 "KOMPAS YANG BERPUTAR"
-- Terbuka 5 hari game setelah Quest 4 (Tiga Tanda Silang) selesai DAN saldo bank >= 1.000.000.
-- Badai menyapu kapal ke TooGood; kompas berputar (3 pelayaran tersesat ke pulau acak, yang
-- ke-4 lewat mini-game Jaring Angin selalu tiba di Marie Regal); Marlya meminta Tedsky dijemput
-- dari IKN (jaminan 50.000); Tedsky memperbaiki kutub di Istana Hening lalu menghilang - puff.
--
-- Langkah (game.player_quests, quest_id = 'kompas'):
--   0  belum mulai (ready = sudah 5 hari game sejak Q4 + saldo bank cukup)
--   1  Babak 1  badai - pelayaran yang sedang berjalan dibelokkan ke TooGood (saat tiba)
--   2           terdampar di TooGood: juru mudi, gosip, Adu Gasing dwi (gasing won|lost)
--   3  Babak 2  tersesat: 3 pelayaran dibelokkan ke pulau acak (data.lost),
--               pelayaran ke-4 butuh Jaring Angin (wind) lalu selalu tiba di Marie Regal
--   4  Babak 3  Istana Hening - Marlya (marlya)
--   5  Babak 4  IKN - jaminan 50.000 (bail)
--   6           Tedsky bertanya kabar dunia (answer jujur|bohong)
--   7  Babak 5  Istana Hening - Tari Genderang & perbaikan kutub (repair)
--   8           selesai: Tedsky menghilang, Kompas Tedsky, 150.000 gold
-- Krisis pasar per pemain: langkah 2-7 penuh, lalu mereda dalam 3 hari game.
-- Aman diulang.
-- =====================================================================

insert into game.item_catalog(item_id, name, type, effects, value, price, source, sort) values
  ('qi_kompas_tedsky', 'Kompas Tedsky', 'quest',
   '{"cargoSize": 0, "desc": "Kompas tua berlapis kuningan yang tertinggal di lantai Istana Hening. Jarumnya tidak pernah menunjuk utara. Ia selalu menunjuk ke satu arah yang sama."}',
   0, null, 'quest', 92)
on conflict (item_id) do update set name = excluded.name, type = excluded.type, effects = excluded.effects,
  value = excluded.value, price = excluded.price, source = excluded.source, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Konstanta & helper
-- ---------------------------------------------------------------------
create or replace function game.kp_bank_need() returns bigint language sql immutable as $$ select 1000000::bigint $$;
create or replace function game.kp_bail() returns bigint language sql immutable as $$ select 50000::bigint $$;
create or replace function game.kp_reward() returns bigint language sql immutable as $$ select 150000::bigint $$;
create or replace function game.kp_lost_need() returns int language sql immutable as $$ select 3 $$;
create or replace function game.kp_wait_days() returns numeric language sql immutable as $$ select 5::numeric $$;
create or replace function game.kp_crisis_days() returns numeric language sql immutable as $$ select 3::numeric $$;

create or replace function game.kp_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'kompas'), 0) $$;

-- Kapan Quest 4 selesai (ms) - null bila belum
create or replace function game.kp_q4_done_ms(p_pid uuid) returns bigint
language sql stable as $$
  select (extract(epoch from coalesce(done_at, updated_at, now())) * 1000)::bigint
    from game.player_quests where player_id = p_pid and quest_id = 'barsati' and step >= 16
$$;

create or replace function game.kp_day_ms() returns bigint
language sql stable as $$ select (game.cfg_num('GameDayLengthRealMinutes', 60) * 60000)::bigint $$;

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------
create or replace function game.kp_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_q4 bigint := game.kp_q4_done_ms(p_pid); v_step int; v_due bigint; v_bank bigint;
  v_time boolean; v_bank_ok boolean;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'kompas';
  if not found and v_q4 is null then return null; end if;
  v_step := coalesce(q.step, 0);
  v_due := coalesce(v_q4, 0) + (game.kp_wait_days() * game.kp_day_ms())::bigint;
  select coalesce(bank_balance, 0) into v_bank from game.players where player_id = p_pid;
  v_time := v_q4 is not null and game.now_ms() >= v_due;
  v_bank_ok := v_bank >= game.kp_bank_need();
  return jsonb_build_object(
    'step', v_step,
    'eligible', v_q4 is not null,
    'timeOk', v_time,
    'readyInMs', case when v_step = 0 then greatest(0, v_due - game.now_ms()) end,
    'bankOk', v_bank_ok,
    'bankNeed', game.kp_bank_need(),
    'ready', v_step = 0 and v_time and v_bank_ok,
    'lost', coalesce((q.data ->> 'lost')::int, 0),
    'wind', coalesce((q.data ->> 'wind')::boolean, false),
    'windDue', v_step = 3 and coalesce((q.data ->> 'lost')::int, 0) >= game.kp_lost_need(),
    'chosen', q.data ->> 'chosen',
    'redirect', q.data -> 'redirect',
    'gasing', q.data ->> 'gasing',
    'truth', q.data ->> 'truth',
    'bail', game.kp_bail(),
    'bailPaid', coalesce((q.data ->> 'bailPaid')::boolean, false),
    'reward', game.kp_reward(),
    'crisis', game.kp_crisis_level(p_pid),
    'compass', game.item_qty(p_pid, 'qi_kompas_tedsky') > 0,
    'night', game.fish_is_night(),
    'done', v_step >= 8);
end $$;

-- ---------------------------------------------------------------------
-- Krisis pasar per pemain (0..1): penuh selama kompas rusak, mereda 3 hari game setelah selesai
-- ---------------------------------------------------------------------
create or replace function game.kp_crisis_level(p_pid uuid) returns double precision
language plpgsql stable as $$
declare q game.player_quests; v_left double precision;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'kompas';
  if not found or q.step < 2 then return 0; end if;
  if q.step < 8 then return 1; end if;
  v_left := 1 - (game.now_ms() - extract(epoch from coalesce(q.done_at, q.updated_at)) * 1000)::double precision
              / (game.kp_crisis_days() * game.kp_day_ms())::double precision;
  return greatest(0, least(1, v_left));
end $$;

-- Barang impor (bukan produksi kota) naik, barang lokal menumpuk dan turun
create or replace function game.quest_price_mul(p_pid uuid, p_city text, p_comm text) returns double precision
language plpgsql stable as $$
declare lvl double precision; v_role text;
begin
  lvl := game.kp_crisis_level(p_pid);
  if lvl <= 0 then return 1; end if;
  select role into v_role from game.market where city_id = p_city and commodity_id = p_comm;
  return 1 + lvl * case coalesce(v_role, 'neutral')
    when 'produce' then -0.15
    when 'consume' then 0.25
    else 0.15 end;
end $$;

-- ---------------------------------------------------------------------
-- Berangkat berlayar: pemicu badai & gerbang Jaring Angin
-- ---------------------------------------------------------------------
create or replace function game.kp_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
declare st jsonb; q game.player_quests;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'kompas' for update;
  if not found or q.step = 0 then
    st := game.kp_state(p_pid);
    if st is null or not coalesce((st ->> 'ready')::boolean, false) then return; end if;
    insert into game.player_quests(player_id, quest_id, step, data)
    values (p_pid, 'kompas', 1, jsonb_build_object('chosen', p_dest, 'lost', 0))
    on conflict (player_id, quest_id) do update set step = 1, data = excluded.data, started_at = now(), updated_at = now();
    perform game.log(p_pid, 'Langit menghitam di tengah pelayaran. Ombak naik setinggi tiang - kapal terguncang hebat.');
    return;
  end if;
  if q.step = 3 then
    if coalesce((q.data ->> 'lost')::int, 0) >= game.kp_lost_need() and not coalesce((q.data ->> 'wind')::boolean, false) then
      raise exception 'Badai magnet menghadang di mulut pelabuhan. Layar harus menjaring angin dulu, Kapten. [JARING_ANGIN]';
    end if;
    update game.player_quests set data = data || jsonb_build_object('chosen', p_dest), updated_at = now()
     where player_id = p_pid and quest_id = 'kompas';
  end if;
end $$;

create or replace function game.quest_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
begin
  perform game.ww_on_sail(p_pid, p_origin, p_dest);
  perform game.bx_on_sail(p_pid, p_origin, p_dest);
  perform game.kp_on_sail(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Tiba: badai ke TooGood, kompas berputar ke pulau acak, angin ke Marie Regal
-- ---------------------------------------------------------------------
create or replace function game.kp_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
declare q game.player_quests; v_lost int; v_to text; rd jsonb; v_name text;
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'kompas' for update;
  if not found then return null; end if;

  if q.step = 1 then
    rd := jsonb_build_object('city', 'toogood', 'kind', 'storm', 'from', p_dest, 'quiet', true, 'at', game.now_ms(),
      'message', 'Badai besar menyapu kapalmu jauh dari jalur. Saat laut akhirnya tenang, haluanmu tersangkut di dermaga yang berasap: TooGood.');
    update game.player_quests set step = 2, data = data || jsonb_build_object('redirect', rd), updated_at = now()
     where player_id = p_pid and quest_id = 'kompas';
    perform game.log(p_pid, 'Badai besar menyapu kapal sampai terdampar di TooGood. Juru mudi melapor: kompas hanya berputar-putar.');
    return rd;
  end if;

  if q.step = 3 then
    v_lost := coalesce((q.data ->> 'lost')::int, 0);
    if v_lost >= game.kp_lost_need() then
      if not coalesce((q.data ->> 'wind')::boolean, false) then return null; end if;
      rd := jsonb_build_object('city', 'marie_regal', 'kind', 'wind', 'from', p_dest, 'quiet', true, 'at', game.now_ms(),
        'message', 'Layar menjaring angin badai magnet, dan angin memilihkan jalan. Menara kaca berkilau di cakrawala: Marie Regal.');
      update game.player_quests set step = 4, data = data || jsonb_build_object('redirect', rd, 'wind', false), updated_at = now()
       where player_id = p_pid and quest_id = 'kompas';
      perform game.log(p_pid, 'Angin memilihkan jalan - kapal merapat di Marie Regal. Seekor pelikan menunggu di dermaga.');
      return rd;
    end if;
    -- Pulau acak: bukan tujuan, bukan pulau asal, bukan TooGood/Marie Regal, bukan titik laut quest
    select c.city_id into v_to from game.cities c
     where c.city_id not in (coalesce(p_dest, ''), coalesce(p_origin, ''), 'toogood', 'marie_regal')
       and not game.spot_city(c.city_id) and game.city_open(p_pid, c.city_id)
     order by random() limit 1;
    if v_to is null then
      select c.city_id into v_to from game.cities c
       where c.city_id <> coalesce(p_dest, '') and not game.spot_city(c.city_id) and game.city_open(p_pid, c.city_id)
       order by random() limit 1;
    end if;
    if v_to is null then return null; end if;
    select name into v_name from game.cities where city_id = v_to;
    rd := jsonb_build_object('city', v_to, 'kind', 'lost', 'n', v_lost + 1, 'from', p_dest, 'quiet', false, 'at', game.now_ms(),
      'message', 'Jarum kompas berputar... kapal merapat di ' || v_name || '.');
    update game.player_quests set data = data || jsonb_build_object('redirect', rd, 'lost', v_lost + 1), updated_at = now()
     where player_id = p_pid and quest_id = 'kompas';
    perform game.log(p_pid, 'Jarum kompas berputar... kapal merapat di ' || v_name || '.');
    return rd;
  end if;
  return null;
end $$;

create or replace function game.quest_arrival_redirect(p_pid uuid, p_origin text, p_dest text) returns jsonb
language plpgsql as $$
begin
  return game.kp_arrival_redirect(p_pid, p_origin, p_dest);
end $$;

-- ---------------------------------------------------------------------
-- Aksi quest. a = [action, arg]
--   status | gasing [won|lost] | wind [perfect|ok] | marlya | bail | answer [jujur|bohong] | repair [skor]
-- ---------------------------------------------------------------------
create or replace function game.kp_set(p_pid uuid, p_step int, p_data jsonb) returns void
language sql as $$
  update game.player_quests set step = p_step, data = data || coalesce(p_data, '{}'::jsonb), updated_at = now(),
    done_at = case when p_step >= 8 then now() else done_at end
   where player_id = p_pid and quest_id = 'kompas'
$$;

create or replace function public.api_kompas(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); st jsonb;
begin
  st := game.kp_state(v_pid);
  if v_act = 'status' then return jsonb_build_object('kompas', st); end if;
  if st is null then raise exception 'Kompasmu masih menunjuk utara, Kapten.'; end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'kompas' for update;
  v_step := coalesce(q.step, 0);
  if v_step = 0 then raise exception 'Kompasmu masih menunjuk utara, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;

  -- Babak 1: TooGood - Adu Gasing dengan dwi
  if v_act = 'gasing' then
    if v_step <> 2 then raise exception 'dwi sedang sibuk dengan kanvasnya.'; end if;
    if v_city <> 'toogood' then raise exception 'dwi de''clown menunggu di Black''s Alley, TooGood.'; end if;
    if v_arg not in ('won', 'lost') then raise exception 'Hasil adu gasing tidak dikenal.'; end if;
    perform game.kp_set(v_pid, 3, jsonb_build_object('gasing', v_arg, 'lost', 0));
    if v_arg = 'won' then update game.players set gold = gold + 2000 where player_id = v_pid; end if;
    perform game.log(v_pid, 'Adu gasing melawan dwi de''clown di Black''s Alley: ' ||
      case when v_arg = 'won' then 'menang (+2.000 gold).' else 'kalah.' end ||
      ' dwi: "Kalau jarum tak tahu utara, biar laut yang memilihkan."');
    return jsonb_build_object('kompas', game.kp_state(v_pid), 'gold', case when v_arg = 'won' then 2000 else 0 end,
      'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  -- Babak 2: Jaring Angin sebelum pelayaran ke-4
  if v_act = 'wind' then
    if v_step <> 3 or coalesce((q.data ->> 'lost')::int, 0) < game.kp_lost_need() then
      raise exception 'Angin masih bertiup biasa.';
    end if;
    if v_arg not in ('perfect', 'ok') then raise exception 'Hasil Jaring Angin tidak dikenal.'; end if;
    perform game.kp_set(v_pid, 3, jsonb_build_object('wind', true, 'windPerfect', v_arg = 'perfect'));
    perform game.log(v_pid, 'Layar berhasil menjaring angin badai magnet. Ke mana pun haluanmu, angin yang akan memilih.');
    return jsonb_build_object('kompas', game.kp_state(v_pid));
  end if;

  -- Babak 3: Marlya di Istana Hening
  if v_act = 'marlya' then
    if v_step <> 4 then raise exception 'Marlya sedang menelusuri arsip.'; end if;
    if v_city <> 'marie_regal' then raise exception 'Marlya menunggu di Istana Hening, Marie Regal.'; end if;
    perform game.kp_set(v_pid, 5, null);
    perform game.log(v_pid, 'Marlya: mekanisme pemicu buatan J.T. merusak kutub bumi. "Ia sedang mengecat burung perunggu itu. Bawa ia kemari."');
    return jsonb_build_object('kompas', game.kp_state(v_pid));
  end if;

  -- Babak 4: IKN - jaminan & kabar dunia
  if v_act = 'bail' then
    if v_step <> 5 then raise exception 'Petugas IKN tidak menagih apa pun darimu.'; end if;
    if v_city <> 'ikn' then raise exception 'Tedsky sedang mengecat patung Garuda di IKN.'; end if;
    if v_me.gold < game.kp_bail() then
      raise exception 'Petugas IKN menggeleng. "Jaminan 50.000 gold, Kapten. Terpidana ini tidak murah."';
    end if;
    update game.players set gold = gold - game.kp_bail() where player_id = v_pid;
    perform game.kp_set(v_pid, 6, jsonb_build_object('bailPaid', true));
    perform game.log(v_pid, 'Membayar jaminan 50.000 gold. Jendral Tedsky meletakkan kuasnya.');
    return jsonb_build_object('kompas', game.kp_state(v_pid), 'paid', game.kp_bail(), 'newGold', v_me.gold - game.kp_bail());
  end if;

  if v_act = 'answer' then
    if v_step <> 6 then raise exception 'Tedsky tidak sedang bertanya apa pun.'; end if;
    if v_city <> 'ikn' then raise exception 'Tedsky menunggu di IKN.'; end if;
    if v_arg not in ('jujur', 'bohong') then raise exception 'Jawab dulu, Kapten: jujur atau bohong.'; end if;
    perform game.kp_set(v_pid, 7, jsonb_build_object('truth', v_arg));
    perform game.log(v_pid, case when v_arg = 'jujur'
      then 'Menceritakan kabar dunia apa adanya kepada Tedsky - termasuk siapa a''dik sebenarnya. Tedsky diam lama.'
      else 'Berbohong kepada Tedsky: "Dunia tenang." Tedsky tertawa pelan.' end || ' Tedsky naik ke kapalmu.');
    return jsonb_build_object('kompas', game.kp_state(v_pid), 'truth', v_arg);
  end if;

  -- Babak 5: perbaikan kutub & puff
  if v_act = 'repair' then
    if v_step <> 7 then raise exception 'Belum ada yang bisa memperbaiki kutub.'; end if;
    if v_city <> 'marie_regal' then raise exception 'Bawa Tedsky ke ruang kontrol Istana Hening, Marie Regal.'; end if;
    perform game.kp_set(v_pid, 8, jsonb_build_object('drumScore', nullif(v_arg, '')));
    update game.players set gold = gold + game.kp_reward() where player_id = v_pid;
    if game.item_qty(v_pid, 'qi_kompas_tedsky') < 1 then perform game.item_adjust(v_pid, 'qi_kompas_tedsky', 1); end if;
    perform game.log(v_pid, 'Kutub bumi pulih - kompas di seluruh dunia berhenti berputar. Jendral Tedsky berlari ke arah cahaya dan menghilang. Yang tertinggal hanya sebuah kompas tua.');
    perform game.log(v_pid, 'Pemerintah Moramora menghadiahkan 150.000 gold. Jaminan 50.000 gold di IKN hangus.');
    return jsonb_build_object('kompas', game.kp_state(v_pid),
      'rewards', jsonb_build_object('gold', game.kp_reward(),
        'item', jsonb_build_object('itemId', 'qi_kompas_tedsky', 'name', 'Kompas Tedsky')),
      'newGold', (select gold from game.players where player_id = v_pid));
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_kompas');
