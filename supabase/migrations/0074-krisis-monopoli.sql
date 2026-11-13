-- =====================================================================
-- 0074 · Saga 4 batch 2b — KRISIS MONOPOLI (Zona Cukai, Patroli Jaring Biru, Pasar Gelap)
--   Semua efek PRIBADI: hanya pemain dengan game.mh_player.krisis = true (diisi quest Mahkota, batch 3).
--   Stok pasar bersama tidak pernah diubah. Pemain lain: harga & pertemuan laut identik dengan sebelumnya.
--
--   * Zona Cukai   : N pulau Mare Nusantara per hari game (jadwal bergaram rahasia; TooGood & IKN tidak pernah).
--                    Dipotret saat setSail. Di zona: beli x MhCukaiBeli, jual x MhCukaiJual (lewat eco2_muls).
--   * Patroli      : pelayaran menuju zona, peluang MhPatroliPct. Urutan: bos quest > Tony > Patroli > bajak laut acak.
--                    Aksi: Bayar Cukai (barang) · Runding (gagal = bayar) · Tembus Jaring (Trektrek-an, setelah dibuka quest).
--                    Tembak / Tabrak / Kabur / Suap dikunci. Ditinggal MhCukaiAutoMin menit = Bayar Cukai.
--   * Kalah Tembus : barang premium disita + cukai untuk barang lain. Gold, barang quest, muatan misi, gudang aman.
--   * Menang Tembus: tiba tanpa cukai. Bila Pasar Gelap sudah terbuka: bonus jual untuk muatan yang dibawa saat tiba,
--                    selalu di bawah harga beli, berkuota lot per hari game. Bonus tidak dihitung Pacu Dagang / Harian.
--   * Misi gubernur (api_buyForMission) bebas cukai.
-- Kait (pola bungkus, migrasi diulang berurutan tiap deploy):
--   eco2_muls -> eco2_muls_inti · kd_enc -> kd_enc_mh · hr_hook -> hr_hook_mh · tony_auto -> tony_auto_mh
--   gm_pulse -> gm_pulse_mh · api_setSail / api_sell / api_resolveCombat / api_buyForMission -> game.*_mh
-- Aman diulang (idempoten).
-- =====================================================================

insert into game.config(key, value) values
  ('MhCukaiBeli', '1.5'), ('MhCukaiJual', '0.6'), ('MhPatroliPct', '35'), ('MhCukaiPct', '25'),
  ('MhZonaN', '3'), ('MhRundingBase', '25'), ('MhCukaiAutoMin', '10'),
  ('MhGelapBonus', '0.15'), ('MhGelapKuota', '10'), ('MhGelapKuotaSmuggler', '5'),
  ('MhGaram', md5(random()::text || clock_timestamp()::text))
on conflict (key) do nothing;

create table if not exists game.mh_player (
  player_id   uuid primary key references game.players(player_id) on update cascade on delete cascade,
  krisis      boolean not null default false,   -- Krisis Monopoli berlaku (langkah 2 sampai tamat)
  tembus      boolean not null default false,   -- pilihan Tembus Jaring sudah terbuka (langkah 21)
  gelap       boolean not null default false,   -- Pasar Gelap resmi terbuka (langkah 22)
  paksa       boolean not null default false,   -- patroli lemah pasti mencegat (langkah 21)
  aman        boolean not null default false,   -- kalah Tembus Jaring tidak menyita (langkah quest tertentu)
  zona_tuju   text,                             -- potret saat setSail: tujuan ini Zona Cukai
  zona_day    int,
  gelap_city  text,                             -- menang Tembus Jaring: kota ini bebas cukai sampai berlayar lagi
  gelap_cargo jsonb not null default '{}'::jsonb,   -- {barang: unit yang dibawa saat tiba dan masih berhak bonus}
  gelap_day   int,
  gelap_used  numeric not null default 0,       -- lot bonus terpakai pada gelap_day
  updated_at  timestamptz not null default now()
);
alter table game.mh_player enable row level security;

-- ---------------------------------------------------------------------
-- Jadwal & status
-- ---------------------------------------------------------------------
create or replace function game.mh_krisis(p_pid uuid) returns boolean
language plpgsql stable as $$
begin
  if p_pid is null or not exists (select 1 from game.mh_player where player_id = p_pid and krisis) then return false; end if;
  begin
    if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return false; end if;
  exception when others then null;
  end;
  return true;
end $$;

create or replace function game.mh_zona(p_day int) returns text[]
language sql stable as $$
  select coalesce(array(
    select c.city_id from game.cities c
     where c.city_id in ('sunda_empire', 'skitraw', 'joungjava', 'bjorneo', 'paradiso', 'marie_regal')
     order by md5(coalesce(game.cfg('MhGaram'), 'garam') || ':' || p_day || ':' || c.city_id)
     limit greatest(0, least(6, game.cfg_num('MhZonaN', 3)::int))), '{}'::text[])
$$;
revoke all on function game.mh_zona(int) from public, anon, authenticated;

create or replace function game.mh_kuota(p_pid uuid) returns numeric
language sql stable as $$
  select game.cfg_num('MhGelapKuota', 10)
       + case when (select archetype from game.players where player_id = p_pid) = 'smuggler' then game.cfg_num('MhGelapKuotaSmuggler', 5) else 0 end
$$;

-- unit barang ini yang masih berhak harga gelap (0 = tidak ada bonus)
create or replace function game.mh_gelap_unit(p_pid uuid, p_city text, p_comm text) returns int
language plpgsql stable as $$
declare m game.mh_player; v_sisa numeric; v_lot numeric; v_bawa int;
begin
  select * into m from game.mh_player where player_id = p_pid;
  if not found or not m.krisis or not m.gelap or m.gelap_city is distinct from p_city then return 0; end if;
  v_bawa := coalesce((m.gelap_cargo ->> p_comm)::int, 0);
  if v_bawa <= 0 then return 0; end if;
  v_sisa := game.mh_kuota(p_pid) - case when m.gelap_day = game.game_day() then m.gelap_used else 0 end;
  select game.mkt_lot(tier) into v_lot from game.commodities where id = p_comm;
  return greatest(0, least(v_bawa, floor(v_sisa * coalesce(v_lot, 1))::int));
end $$;

create or replace function game.mh_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare m game.mh_player; v_city text; v_kena boolean := false; v_g jsonb;
begin
  if not game.mh_krisis(p_pid) then return null; end if;
  select * into m from game.mh_player where player_id = p_pid;
  if not game.in_transit(p_pid) then v_city := game.current_city(p_pid); end if;
  v_kena := v_city is not null and m.zona_tuju = v_city and m.gelap_city is distinct from v_city;
  if m.gelap_city is not null and m.gelap_city = v_city then
    v_g := jsonb_build_object('city', m.gelap_city, 'buka', m.gelap, 'kuota', game.mh_kuota(p_pid),
      'sisa', greatest(0, game.mh_kuota(p_pid) - case when m.gelap_day = game.game_day() then m.gelap_used else 0 end),
      'barang', case when m.gelap then
        coalesce((select jsonb_object_agg(k, game.mh_gelap_unit(p_pid, v_city, k)) from jsonb_object_keys(m.gelap_cargo) k
                   where game.mh_gelap_unit(p_pid, v_city, k) > 0), '{}'::jsonb) else '{}'::jsonb end,
      'bonus', game.cfg_num('MhGelapBonus', 0.15));
  end if;
  return jsonb_build_object('zona', to_jsonb(game.mh_zona(game.game_day())), 'kena', case when v_kena then v_city end,
    'beli', game.cfg_num('MhCukaiBeli', 1.5), 'jual', game.cfg_num('MhCukaiJual', 0.6), 'pct', game.cfg_num('MhCukaiPct', 25),
    'tembus', m.tembus, 'gelapBuka', m.gelap, 'gelap', v_g, 'hari', game.game_day());
end $$;

-- ---------------------------------------------------------------------
-- Sita barang. p_mode: 'cukai' = MhCukaiPct% tiap barang · 'premium' = premium habis + cukai barang lain.
-- Hanya game.inventory (komoditas). Gold, barang quest, muatan misi (player_missions), gudang tidak disentuh.
-- ---------------------------------------------------------------------
create or replace function game.mh_seize(p_pid uuid, p_mode text) returns jsonb
language plpgsql as $$
declare r record; v_pct numeric := greatest(0, least(100, game.cfg_num('MhCukaiPct', 25))); v_take int; v_out jsonb := '[]'::jsonb; v_tot int := 0;
begin
  for r in select i.item_id, i.qty, c.name, c.tier from game.inventory i join game.commodities c on c.id = i.item_id
            where i.player_id = p_pid and i.qty > 0 order by c.sort, i.item_id loop
    v_take := case when p_mode = 'premium' and r.tier = 'premium' then r.qty else least(r.qty, round(r.qty * v_pct / 100.0)::int) end;
    if v_take > 0 then
      perform game.adjust_inventory(p_pid, r.item_id, -v_take);
      v_out := v_out || jsonb_build_array(jsonb_build_object('id', r.item_id, 'name', r.name, 'qty', v_take, 'premium', r.tier = 'premium'));
      v_tot := v_tot + v_take;
    end if;
  end loop;
  -- muatan kecil-kecil: juru sita tetap pulang membawa satu
  if v_tot = 0 and v_pct > 0 then
    select i.item_id, i.qty, c.name, c.tier into r from game.inventory i join game.commodities c on c.id = i.item_id
     where i.player_id = p_pid and i.qty > 0 order by i.qty desc, c.sort, i.item_id limit 1;
    if found then
      perform game.adjust_inventory(p_pid, r.item_id, -1);
      v_out := jsonb_build_array(jsonb_build_object('id', r.item_id, 'name', r.name, 'qty', 1, 'premium', r.tier = 'premium'));
    end if;
  end if;
  return v_out;
end $$;

-- ---------------------------------------------------------------------
-- Lempar peluang patroli saat kapal tiba (baris player_location sudah dikunci)
-- ---------------------------------------------------------------------
create or replace function game.mh_patroli_roll(p_pid uuid) returns jsonb
language plpgsql as $$
declare l game.player_location; m game.mh_player; v_ship text; v_rival text; v_n int;
begin
  if not game.mh_krisis(p_pid) then return null; end if;
  select * into l from game.player_location where player_id = p_pid;
  select * into m from game.mh_player where player_id = p_pid;
  if coalesce(l.destination_city_id, '') = '' or m.zona_tuju is distinct from l.destination_city_id then return null; end if;
  if not m.paksa and random() * 100 >= game.cfg_num('MhPatroliPct', 35) then return null; end if;
  v_ship := game.trek_kapal(p_pid);
  v_rival := case when m.paksa then 'patroli_lemah' when v_ship in ('penuh', 'warlord', 'yusaint') then 'patroli_kuat' else 'patroli' end;
  select coalesce(sum(i.qty), 0) into v_n from game.inventory i join game.commodities c on c.id = i.item_id where i.player_id = p_pid and i.qty > 0;
  return jsonb_build_object(
    'kind', 'cukai',
    'enemyName', 'Patroli Jaring Biru',
    'enemyLevel', 5, 'enemyMaxHp', 999, 'enemyHp', 999, 'maxAmmo', 0, 'ammoRemaining', 0, 'round', 1,
    'noFlee', true, 'noRam', true,
    'noFleeMsg', 'Rantai biru sudah terbentang di depan dan di belakang. Tidak ada celah untuk kabur.',
    'noTalkMsg', 'Juru sita menggeleng: "Stempel biru tidak bisa dibeli, Kapten. Hanya dibayar."',
    'pct', game.cfg_num('MhCukaiPct', 25), 'muatan', v_n,
    'tembus', m.tembus, 'rival', v_rival, 'aman', (m.aman or m.paksa), 'lemah', m.paksa,
    'rolledAt', game.iso(now()), 'lastAt', game.now_ms());
end $$;

-- ---------------------------------------------------------------------
-- Satu aksi di depan patroli: bayar | runding | tembus | selesai (run, log)
-- ---------------------------------------------------------------------
create or replace function game.mh_cukai_act(p_pid uuid, p_tactic text, p_run text default null, p_log jsonb default null) returns jsonb
language plpgsql as $$
declare l game.player_location; enc jsonb; m game.mh_player; v_dest text; v_name text; v_sita jsonb; v_msg text; fin jsonb;
  v_ch numeric; v_neg int; t jsonb; h jsonb; v_id uuid; v_how text; v_cargo jsonb;
begin
  select * into l from game.player_location where player_id = p_pid for update;
  enc := l.pending_encounter;
  if not found or jsonb_typeof(enc) <> 'object' or coalesce(enc ->> 'kind', '') <> 'cukai' then
    raise exception 'Tidak ada patroli yang sedang menghadang.';
  end if;
  v_dest := l.destination_city_id;
  select name into v_name from game.cities where city_id = v_dest;
  select * into m from game.mh_player where player_id = p_pid;
  p_tactic := lower(coalesce(p_tactic, ''));
  if p_tactic in ('surrender', 'serah') then p_tactic := 'bayar'; end if;
  if p_tactic = 'negotiate' then p_tactic := 'runding'; end if;
  if p_tactic = 'flee' then raise exception '%', enc ->> 'noFleeMsg'; end if;
  if p_tactic = 'bribe' then raise exception '%', enc ->> 'noTalkMsg'; end if;
  if p_tactic in ('fire', 'reload', 'ram') then
    raise exception 'Menembak kapal audit berarti seluruh Armada Biru memburumu sampai ke ujung peta. Krumu menahan sumbu meriam.';
  end if;

  -- Tembus Jaring sudah dimulai: hanya 'selesai' yang sah. Aksi lain = melepas kemudi = kalah.
  if enc ? 'trekRun' then
    if p_tactic = 'selesai' then
      begin v_id := p_run::uuid; exception when others then raise exception 'Balapan tidak ditemukan.'; end;
      if v_id::text <> enc ->> 'trekRun' then raise exception 'Balapan tidak ditemukan.'; end if;
      h := game.trek_selesai(p_pid, v_id, p_log, 'tembus');
    else
      h := jsonb_build_object('win', false, 'lepas', true);
    end if;
    if coalesce((h ->> 'win')::boolean, false) then
      -- MENANG: tiba tanpa cukai. Pasar Gelap mencatat muatan yang dibawa.
      select coalesce(jsonb_object_agg(i.item_id, i.qty), '{}'::jsonb) into v_cargo
        from game.inventory i join game.commodities c on c.id = i.item_id where i.player_id = p_pid and i.qty > 0;
      update game.mh_player set gelap_city = v_dest, gelap_cargo = case when gelap then v_cargo else '{}'::jsonb end, updated_at = now()
       where player_id = p_pid;
      v_msg := 'Kapalmu melesat di celah rantai yang buta dua detik. Jaring menutup di belakang buritan, terlambat. ' ||
        case when m.gelap then 'Di ' || coalesce(v_name, v_dest) || ', pintu belakang pasar sudah menunggu: tidak ada stempel, tidak ada cukai.'
             else 'Kau merapat di ' || coalesce(v_name, v_dest) || ' tanpa satu stempel pun di palka.' end;
      fin := game.voy_finalize_arrival(p_pid, v_dest, v_msg);
      perform game.log(p_pid, 'Menembus Jaring Biru menuju ' || coalesce(v_name, v_dest) || '.');
      return jsonb_build_object('ongoing', false, 'cukai', true, 'success', true, 'result', 'tembus', 'how', 'menang',
        'message', v_msg, 'hasil', h, 'cityId', fin -> 'cityId', 'state', game.mh_state(p_pid));
    end if;
    -- KALAH
    if coalesce((enc ->> 'aman')::boolean, false) then
      v_sita := '[]'::jsonb;
      v_msg := 'Rantai menutup sebelum haluanmu sampai. Patroli itu hanya mencatat nama kapalmu dan melepasmu: "Lain kali kami tidak sebaik ini."';
    else
      v_sita := game.mh_seize(p_pid, 'premium');
      v_msg := case when coalesce((h ->> 'lepas')::boolean, false) then 'Kemudi terlepas di tengah selat dan rantai menutup. ' else 'Rantai menutup sebelum haluanmu sampai. ' end ||
        'Juru sita naik ke geladak dengan buku besar: barang premium disita, sisanya kena cukai ' || (enc ->> 'pct') || ' dari seratus.';
    end if;
    fin := game.voy_finalize_arrival(p_pid, v_dest, v_msg);
    perform game.log(p_pid, 'Gagal menembus Jaring Biru menuju ' || coalesce(v_name, v_dest) || '.');
    return jsonb_build_object('ongoing', false, 'cukai', true, 'success', false, 'result', 'cukai', 'how', 'kalah',
      'message', v_msg, 'sita', v_sita, 'hasil', h, 'aman', coalesce((enc ->> 'aman')::boolean, false),
      'cityId', fin -> 'cityId', 'state', game.mh_state(p_pid));
  end if;

  if p_tactic = 'tembus' then
    if not coalesce((enc ->> 'tembus')::boolean, false) then
      raise exception 'Belum ada yang tahu cara menembus rantai itu, Kapten. Bayar, atau coba berunding.';
    end if;
    t := game.trek_mulai(p_pid, 'tembus', coalesce(enc ->> 'rival', 'patroli'), game.trek_kapal(p_pid));
    enc := enc || jsonb_build_object('trekRun', t ->> 'run', 'lastAt', game.now_ms());
    update game.player_location set pending_encounter = enc where player_id = p_pid;
    return jsonb_build_object('ongoing', true, 'cukai', true, 'trek', t, 'encounter', enc);
  end if;

  if p_tactic = 'runding' then
    select negotiation into v_neg from game.character_stats where player_id = p_pid;
    v_ch := greatest(10, least(65, game.cfg_num('MhRundingBase', 25) + (coalesce(v_neg, 35) - 35) * 0.6));
    if random() * 100 < v_ch then
      v_msg := 'Kau membentangkan surat muatan dan bicara panjang soal pasal yang tidak pernah ada. Juru sita ragu, lalu menutup bukunya: "Lewat. Sekali ini."';
      fin := game.voy_finalize_arrival(p_pid, v_dest, v_msg);
      return jsonb_build_object('ongoing', false, 'cukai', true, 'success', true, 'result', 'lolos', 'how', 'runding',
        'message', v_msg, 'cityId', fin -> 'cityId', 'state', game.mh_state(p_pid));
    end if;
    v_how := 'runding';
  elsif p_tactic = 'bayar' then
    v_how := 'bayar';
  elsif p_tactic = 'auto' then
    v_how := 'auto';
  else
    raise exception 'Taktik tidak dikenali: %', p_tactic;
  end if;

  v_sita := game.mh_seize(p_pid, 'cukai');
  v_msg := case v_how
    when 'runding' then 'Juru sita mendengarkan sampai habis, lalu mencelupkan stempelnya: "Bagus ceritanya. Cukainya tetap." '
    when 'auto' then 'Kapalmu terombang-ambing tanpa jawaban. Juru sita tidak menunggu. '
    else 'Kau menurunkan layar. ' end ||
    case when jsonb_array_length(v_sita) = 0 then 'Palkamu kosong; juru sita mendengus, menstempel udara, lalu pergi.'
         else 'Seperempat muatanmu dipindahkan ke lambung biru, peti demi peti, dan tiap peti yang tersisa dicap stempel biru.' end;
  fin := game.voy_finalize_arrival(p_pid, v_dest, v_msg);
  perform game.log(p_pid, 'Dicegat Patroli Jaring Biru menuju ' || coalesce(v_name, v_dest) || ': cukai dibayar dengan barang.');
  return jsonb_build_object('ongoing', false, 'cukai', true, 'success', false, 'result', 'cukai', 'how', v_how,
    'message', v_msg, 'sita', v_sita, 'cityId', fin -> 'cityId', 'state', game.mh_state(p_pid));
end $$;

-- Ditinggal terlalu lama di depan patroli = Bayar Cukai (atau kalah bila Tembus Jaring sudah dimulai)
create or replace function game.mh_auto(p_pid uuid) returns void
language plpgsql as $$
declare enc jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if jsonb_typeof(enc) <> 'object' or coalesce(enc ->> 'kind', '') <> 'cukai' then return; end if;
  if game.now_ms() - coalesce((enc ->> 'lastAt')::bigint, 0) < game.cfg_num('MhCukaiAutoMin', 10) * 60000 then return; end if;
  perform game.mh_cukai_act(p_pid, 'auto');
end $$;

-- GM / penguji: nyalakan Krisis Monopoli untuk satu pemain sebelum quest Mahkota ada.
create or replace function game.admin_mh_set(p_username text, p_krisis boolean, p_tembus boolean default false, p_gelap boolean default false)
returns text language plpgsql as $$
declare v_pid uuid;
begin
  select player_id into v_pid from game.players where lower(username) = lower(p_username);
  if v_pid is null then return 'Pemain tidak ditemukan.'; end if;
  insert into game.mh_player(player_id, krisis, tembus, gelap) values (v_pid, p_krisis, p_tembus, p_gelap)
    on conflict (player_id) do update set krisis = excluded.krisis, tembus = excluded.tembus, gelap = excluded.gelap,
      zona_tuju = null, gelap_city = null, gelap_cargo = '{}'::jsonb, updated_at = now();
  return 'OK';
end $$;
revoke all on function game.admin_mh_set(text, boolean, boolean, boolean) from public, anon, authenticated;

-- =====================================================================
-- KAIT
-- =====================================================================
do $$
begin
  drop function if exists game.eco2_muls_inti(uuid, text, text);
  alter function game.eco2_muls(uuid, text, text) rename to eco2_muls_inti;
  drop function if exists game.kd_enc_mh(uuid, jsonb);
  alter function game.kd_enc(uuid, jsonb) rename to kd_enc_mh;
  drop function if exists game.hr_hook_mh(uuid, text, numeric, jsonb);
  alter function game.hr_hook(uuid, text, numeric, jsonb) rename to hr_hook_mh;
  drop function if exists game.tony_auto_mh(uuid);
  alter function game.tony_auto(uuid) rename to tony_auto_mh;
  drop function if exists game.gm_pulse_mh(uuid);
  alter function game.gm_pulse(uuid) rename to gm_pulse_mh;

  drop function if exists game.api_setsail_mh(jsonb);
  alter function public.api_setsail(jsonb) rename to api_setsail_mh;
  alter function public.api_setsail_mh(jsonb) set schema game;
  drop function if exists game.api_sell_mh(jsonb);
  alter function public.api_sell(jsonb) rename to api_sell_mh;
  alter function public.api_sell_mh(jsonb) set schema game;
  drop function if exists game.api_resolvecombat_mh(jsonb);
  alter function public.api_resolvecombat(jsonb) rename to api_resolvecombat_mh;
  alter function public.api_resolvecombat_mh(jsonb) set schema game;
  drop function if exists game.api_buyformission_mh(jsonb);
  alter function public.api_buyformission(jsonb) rename to api_buyformission_mh;
  alter function public.api_buyformission_mh(jsonb) set schema game;
end $$;
revoke all on function game.api_setsail_mh(jsonb) from public, anon, authenticated;
revoke all on function game.api_sell_mh(jsonb) from public, anon, authenticated;
revoke all on function game.api_resolvecombat_mh(jsonb) from public, anon, authenticated;
revoke all on function game.api_buyformission_mh(jsonb) from public, anon, authenticated;

-- Harga: cukai di sisi beli & jual (bukan ev_mul), Pasar Gelap = bonus jual di bawah harga beli
create or replace function game.eco2_muls(p_pid uuid, p_city text, p_comm text, out buy_mul double precision, out sell_mul double precision,
  out ev_mul double precision)
language plpgsql stable as $$
declare m game.mh_player;
begin
  select i.buy_mul, i.sell_mul, i.ev_mul into buy_mul, sell_mul, ev_mul from game.eco2_muls_inti(p_pid, p_city, p_comm) i;
  if p_pid is null then return; end if;
  select * into m from game.mh_player where player_id = p_pid;
  if not found or not m.krisis then return; end if;
  if coalesce(current_setting('mt.mh_bebas', true), '') = '1' then return; end if;
  if m.gelap_city is not null and m.gelap_city = p_city then
    if game.mh_gelap_unit(p_pid, p_city, p_comm) > 0 then
      sell_mul := greatest(sell_mul, least(buy_mul - 0.01, sell_mul * (1 + game.cfg_num('MhGelapBonus', 0.15))));
    end if;
    return;
  end if;
  if m.zona_tuju is not null and m.zona_tuju = p_city and game.mh_krisis(p_pid)
     and not game.in_transit(p_pid) and game.current_city(p_pid) = p_city then
    buy_mul := buy_mul * game.cfg_num('MhCukaiBeli', 1.5);
    sell_mul := sell_mul * game.cfg_num('MhCukaiJual', 0.6);
  end if;
end $$;

-- Pertemuan laut: bos quest > Tony > Patroli > bajak laut acak
create or replace function game.kd_enc(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql as $$
declare l game.player_location; c jsonb; v_tony boolean := false;
begin
  if p_enc is null or jsonb_typeof(p_enc) <> 'object' or coalesce((p_enc ->> 'randomPirate')::boolean, false) then
    if game.mh_krisis(p_pid) then
      select * into l from game.player_location where player_id = p_pid;
      begin v_tony := (game.tony_active(l.city_id, l.destination_city_id)).id is not null; exception when others then v_tony := false; end;
      if not v_tony then
        c := game.mh_patroli_roll(p_pid);
        if c is not null then return c; end if;
      end if;
    end if;
  end if;
  return game.kd_enc_mh(p_pid, p_enc);
end $$;

-- Bonus Pasar Gelap tidak dihitung Pacu Dagang / Pesanan Harian
create or replace function game.hr_hook(p_pid uuid, p_kind text, p_amount numeric, p_ctx jsonb) returns void
language plpgsql as $$
declare v_r numeric;
begin
  if p_kind = 'sell' then
    begin v_r := nullif(current_setting('mt.mh_gelap_r', true), '')::numeric; exception when others then v_r := null; end;
    if v_r is not null and v_r > 1 then p_amount := round(p_amount / v_r); end if;
  end if;
  perform game.hr_hook_mh(p_pid, p_kind, p_amount, p_ctx);
end $$;

create or replace function game.tony_auto(p_pid uuid) returns void
language plpgsql as $$
begin
  perform game.tony_auto_mh(p_pid);
  begin perform game.mh_auto(p_pid); exception when others then null; end;
end $$;

create or replace function game.gm_pulse(p_pid uuid) returns jsonb
language plpgsql as $$
declare v jsonb := game.gm_pulse_mh(p_pid); c jsonb;
begin
  begin
    if p_pid is not null then c := game.mh_state(p_pid); end if;
    if c is not null then v := coalesce(v, jsonb_build_object('t', game.now_ms())) || jsonb_build_object('cukai', c); end if;
  exception when others then null;
  end;
  return v;
end $$;

-- setSail: potret zona tujuan, tutup Pasar Gelap kota yang ditinggalkan
create or replace function public.api_setSail(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); r jsonb; v_dest text; v_day int;
begin
  r := game.api_setsail_mh(a);
  if v_pid is not null and exists (select 1 from game.mh_player where player_id = v_pid and krisis) then
    select destination_city_id into v_dest from game.player_location where player_id = v_pid;
    v_day := game.game_day();
    update game.mh_player
       set zona_tuju = case when game.mh_krisis(v_pid) and v_dest = any (game.mh_zona(v_day)) then v_dest end,
           zona_day = v_day, gelap_city = null, gelap_cargo = '{}'::jsonb, updated_at = now()
     where player_id = v_pid;
    if exists (select 1 from game.mh_player where player_id = v_pid and zona_tuju is not null) then
      r := r || jsonb_build_object('zonaCukai', true);
    end if;
  end if;
  return r;
end $$;
select game.expose('api_setsail');

-- Jual: harga gelap hanya untuk unit yang berhak; kuota lot per hari game
create or replace function public.api_sell(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); v_city text := game.arg(a, 0); v_comm text := game.arg(a, 1); v_qty bigint := game.arg_int(a, 2);
  v_unit int := 0; r jsonb; mu record; mi record; v_lot numeric; v_day int;
begin
  if v_pid is not null and v_qty is not null and v_qty > 0 then v_unit := game.mh_gelap_unit(v_pid, v_city, v_comm); end if;
  if v_unit <= 0 then return game.api_sell_mh(a); end if;
  if v_qty > v_unit then
    raise exception 'Pintu belakang hanya sanggup menampung % unit barang ini dengan harga gelap. Jual % dulu; sisanya lewat pintu depan.', v_unit, v_unit;
  end if;
  select * into mu from game.eco2_muls(v_pid, v_city, v_comm);
  select * into mi from game.eco2_muls_inti(v_pid, v_city, v_comm);
  perform set_config('mt.mh_gelap_r', case when mi.sell_mul > 0 then (mu.sell_mul / mi.sell_mul)::text else '' end, true);
  r := game.api_sell_mh(a);
  perform set_config('mt.mh_gelap_r', '', true);
  select game.mkt_lot(tier) into v_lot from game.commodities where id = v_comm;
  v_day := game.game_day();
  update game.mh_player
     set gelap_cargo = jsonb_set(gelap_cargo, array[v_comm], to_jsonb(greatest(0, coalesce((gelap_cargo ->> v_comm)::int, 0) - v_qty::int))),
         gelap_used = case when gelap_day = v_day then gelap_used else 0 end + v_qty / coalesce(nullif(v_lot, 0), 1),
         gelap_day = v_day, updated_at = now()
   where player_id = v_pid;
  return r || jsonb_build_object('pasarGelap', true, 'cukai', game.mh_state(v_pid));
end $$;
select game.expose('api_sell');

create or replace function public.api_resolveCombat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); enc jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = v_pid;
  if jsonb_typeof(enc) = 'object' and coalesce(enc ->> 'kind', '') = 'cukai' then
    return game.mh_cukai_act((game.me(true)).player_id, game.arg(a, 0));
  end if;
  return game.api_resolvecombat_mh(a);
end $$;
select game.expose('api_resolvecombat');

-- Misi gubernur bebas cukai
create or replace function public.api_buyForMission(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare r jsonb;
begin
  perform set_config('mt.mh_bebas', '1', true);
  r := game.api_buyformission_mh(a);
  perform set_config('mt.mh_bebas', '', true);
  return r;
end $$;
select game.expose('api_buyformission');

-- ---------------------------------------------------------------------
-- ENDPOINT: api_cukai([aksi, run?, log?])  aksi = status | bayar | runding | tembus | selesai
-- ---------------------------------------------------------------------
create or replace function public.api_cukai(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_act text := lower(coalesce(game.arg(a, 0), 'status')); v_me game.players;
begin
  if v_act = 'status' then
    v_me := game.me();
    return jsonb_build_object('cukai', game.mh_state(v_me.player_id));
  end if;
  v_me := game.me(true);
  if not exists (select 1 from game.mh_player where player_id = v_me.player_id and krisis) then raise exception 'Aksi tidak dikenal.'; end if;
  if v_act not in ('bayar', 'runding', 'tembus', 'selesai') then raise exception 'Aksi tidak dikenal.'; end if;
  return game.mh_cukai_act(v_me.player_id, v_act, game.arg(a, 1), case when jsonb_typeof(a) = 'array' then a -> 2 end);
end $$;
select game.expose('api_cukai');
