-- =====================================================================
-- Marantau (Supabase) - 0061 BAJAK LAUT "TONY AND GANK"  (Tide v45)
-- ---------------------------------------------------------------------
-- Event bajak laut yang hanya muncul saat GM memasangnya: rute (tujuan,
-- opsional asal), jam mulai-selesai, peluang. Armada 4 kapal, HP 4.000,
-- hampir mustahil dikalahkan (celah: gudang mesiu Tangan Panjang).
-- Pilihan pemain hanya Lawan (tembak / isi meriam) atau Menyerah.
-- Kalah / menyerah: palka 100% + gold di tangan (bawaan 60%) dirampas,
-- kapal tidak tenggelam, tetap tiba di kota tujuan.
--
-- Titik kait (dibungkus, isi asli tidak disalin):
--   game.kd_enc            -> encounter Tony menggantikan bajak laut acak / pelayaran
--                             tanpa musuh (tidak pernah bos quest). Jasa Pengawal tidak terpakai.
--   public.api_resolveCombat -> bila encounter Tony, taktik diarahkan ke game.tony_act
--   game.gm_pulse          -> pengumuman mode Umum, menyerah otomatis, state 'tony'
-- Pola bungkus: fungsi asli (dibuat ulang oleh 0003/0032/0036 setiap deploy)
-- diganti nama menjadi *_inti, lalu pembungkus dibuat dengan nama asli. Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('TonyFleetHp', '4000'),
  ('TonyDmgTaken', '0.04'),
  ('TonyLevel', '8'),
  ('TonyHitPctMin', '12'),        -- balasan armada: % kondisi maksimum per ronde (min)
  ('TonyHitPctMax', '18'),        -- (maks)
  ('TonyPowderChance', '0.5'),    -- % per tembakan kena: gudang mesiu meledak = menang
  ('TonyWinGold', '25000'),
  ('TonyLoseCondPct', '10'),      -- kondisi kapal setelah kalah (% maks)
  ('TonyAutoSurrenderMin', '10'),
  ('TonyRumorLeadMin', '60')
on conflict (key) do nothing;

create table if not exists game.tony_raid (
  id               bigserial primary key,
  dest_city        text not null,
  origin_city      text,                         -- null = semua asal
  start_at         timestamptz not null,
  end_at           timestamptz not null,
  chance           int not null default 80,
  gold_pct         int not null default 60,
  kabar            text not null default 'bisik', -- diam | bisik | umum
  announce_victims boolean not null default true,
  announced        boolean not null default false,
  announce_id      bigint,
  rolls            int not null default 0,        -- pelayaran yang tiba di rute ini selama event
  hits             int not null default 0,        -- yang dikepung
  created_by       text not null default '',
  created_at       timestamptz not null default now(),
  cancelled_at     timestamptz
);
create index if not exists tony_raid_active_idx on game.tony_raid (dest_city, end_at) where cancelled_at is null;
alter table game.tony_raid enable row level security;

create table if not exists game.tony_victims (
  id          bigserial primary key,
  raid_id     bigint not null,
  player_id   uuid not null references game.players(player_id) on update cascade on delete cascade,
  at          timestamptz not null default now(),
  result      text not null,                     -- serah | kalah | auto | menang
  rounds      int not null default 0,
  gold_before bigint not null default 0,
  gold_taken  bigint not null default 0,
  cargo       jsonb not null default '[]'::jsonb,
  cargo_value bigint not null default 0
);
create index if not exists tony_victims_raid_idx on game.tony_victims (raid_id, player_id);
create index if not exists tony_victims_player_idx on game.tony_victims (player_id);
alter table game.tony_victims enable row level security;

-- ---------------------------------------------------------------------
-- Kiasan kota (gaya penulisan Marantau: jangan sebut nama kota di bisikan)
-- ---------------------------------------------------------------------
create or replace function game.tony_hint(p_city text) returns text
language sql immutable as $$
  select case p_city
    when 'toogood' then 'sarang yang dulu asapnya tak pernah padam'
    when 'joungjava' then 'tanah paling subur'
    when 'bjorneo' then 'tempat kabut tak pernah pergi'
    when 'ikn' then 'kota yang sudah runtuh'
    when 'skitraw' then 'kota rendang paling enak'
    when 'sunda_empire' then 'pelabuhan para saudagar kain'
    when 'paradiso' then 'pulau tempat orang melupakan utangnya'
    when 'marie_regal' then 'kota kaca yang dulu diam'
    else 'pelabuhan jauh di balik kabut' end
$$;

-- Kapal sasaran berdasarkan damage yang sudah masuk (Bayang Lambung -> Si Jepit -> Kantong Bolong -> Tangan Panjang)
create or replace function game.tony_target(p_max numeric, p_hp numeric) returns text
language plpgsql immutable as $$
declare dealt numeric := greatest(0, p_max - p_hp); u numeric := greatest(p_max, 1) / 5;
begin
  if dealt < u then return 'Bayang Lambung'; end if;
  if dealt < u * 2 then return 'Si Jepit'; end if;
  if dealt < u * 3 then return 'Kantong Bolong'; end if;
  return 'Tangan Panjang';
end $$;

-- Event aktif untuk rute ini (peluang tertinggi bila tumpang tindih)
create or replace function game.tony_active(p_origin text, p_dest text) returns game.tony_raid
language sql stable as $$
  select * from game.tony_raid
   where cancelled_at is null and dest_city = p_dest
     and (origin_city is null or origin_city = p_origin)
     and now() >= start_at and now() < end_at
   order by chance desc, id desc limit 1
$$;

-- ---------------------------------------------------------------------
-- Lempar peluang saat kapal tiba (dipanggil dari pembungkus kd_enc,
-- baris player_location sudah dikunci oleh resolve_arrival_if_due)
-- ---------------------------------------------------------------------
create or replace function game.tony_roll(p_pid uuid) returns jsonb
language plpgsql as $$
declare l game.player_location; r game.tony_raid; ship jsonb; ammo numeric; mhp numeric;
begin
  select * into l from game.player_location where player_id = p_pid;
  if not found or coalesce(l.destination_city_id, '') = '' then return null; end if;
  if game.spot_city(l.destination_city_id) then return null; end if;
  begin
    if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return null; end if;   -- era lampau Saga 3
  exception when others then null;
  end;
  begin
    if game.dt_spot(p_pid, l.destination_city_id) then return null; end if;           -- titik laut quest Saga 3
  exception when others then null;
  end;
  r := game.tony_active(l.city_id, l.destination_city_id);
  if r.id is null then return null; end if;
  -- pemenang event ini kebal sampai event selesai
  if exists (select 1 from game.tony_victims where raid_id = r.id and player_id = p_pid and result = 'menang') then
    return null;
  end if;
  update game.tony_raid set rolls = rolls + 1 where id = r.id;
  if random() * 100 >= r.chance then return null; end if;
  update game.tony_raid set hits = hits + 1 where id = r.id;

  ship := coalesce(game.ship_json(p_pid), '{}'::jsonb);
  ammo := game.voy_num(ship -> 'MaxCannonAmmo');
  if ammo = 0 then ammo := game.cfg_num('CombatBaseAmmo', 3); end if;
  mhp := game.cfg_num('TonyFleetHp', 4000);
  return jsonb_build_object(
    'kind', 'tony',
    'raidId', r.id,
    'goldPct', r.gold_pct,
    'enemyName', 'Armada Tony and Gank',
    'enemyLevel', game.cfg_num('TonyLevel', 8)::int,
    'enemyMaxHp', mhp,
    'enemyHp', mhp,
    'dmgTaken', game.cfg_num('TonyDmgTaken', 0.04),
    'boss', 'tony',
    'noRam', true,
    'noFlee', true,
    'noTalkMsg', 'Tony merapikan kacamatanya: "Suap? Semua gold-mu toh akan masuk bukuku."',
    'ships', jsonb_build_array(
      jsonb_build_object('name', 'Bayang Lambung', 'share', 0.2),
      jsonb_build_object('name', 'Si Jepit', 'share', 0.2),
      jsonb_build_object('name', 'Kantong Bolong', 'share', 0.2),
      jsonb_build_object('name', 'Tangan Panjang', 'share', 0.4)),
    'maxAmmo', ammo,
    'ammoRemaining', ammo,
    'round', 1,
    'fought', false,
    'rolledAt', game.iso(now()),
    'lastAt', game.now_ms());
end $$;

-- ---------------------------------------------------------------------
-- Rampas: palka 100% + gold_pct% gold di tangan. Bank/gudang/item quest aman.
-- ---------------------------------------------------------------------
create or replace function game.tony_rob(p_pid uuid, p_enc jsonb, p_result text) returns jsonb
language plpgsql as $$
declare g bigint; pct int; take bigint; v_cargo jsonb; v_val bigint; v_dest text; v_name text; r game.tony_raid;
begin
  select destination_city_id into v_dest from game.player_location where player_id = p_pid;
  select gold, coalesce(nullif(btrim(character_name), ''), username, 'Tanpa Nama') into g, v_name
    from game.players where player_id = p_pid for update;
  pct := least(90, greatest(10, coalesce((p_enc ->> 'goldPct')::int, 60)));
  take := floor(coalesce(g, 0) * pct / 100.0)::bigint;

  select coalesce(jsonb_agg(jsonb_build_object('id', i.item_id, 'name', c.name, 'qty', i.qty) order by c.sort, i.item_id), '[]'::jsonb),
         coalesce(sum(i.qty::bigint * coalesce(m.current_price, 0)), 0)
    into v_cargo, v_val
    from game.inventory i join game.commodities c on c.id = i.item_id
    left join game.market m on m.city_id = v_dest and m.commodity_id = i.item_id
   where i.player_id = p_pid and i.qty > 0;

  perform game.voy_lose_cargo(p_pid, 1.0);
  if take > 0 then update game.players set gold = gold - take where player_id = p_pid; end if;

  insert into game.tony_victims(raid_id, player_id, result, rounds, gold_before, gold_taken, cargo, cargo_value)
  values (coalesce((p_enc ->> 'raidId')::bigint, 0), p_pid, p_result,
          case when coalesce((p_enc ->> 'fought')::boolean, false) then greatest(0, coalesce((p_enc ->> 'round')::int, 1) - 1) else 0 end,
          coalesce(g, 0), take, v_cargo, v_val);

  select * into r from game.tony_raid where id = (p_enc ->> 'raidId')::bigint;
  if coalesce(r.announce_victims, true) then
    perform game.sys_chat('Kabar Laut', 'Kapten ' || v_name || ' dikepung Tony and Gank dan pulang dengan palka kosong.');
  end if;
  perform game.log(p_pid, 'Dikepung Tony and Gank: seluruh muatan dirampas dan ' || take || ' gold diambil.');
  return jsonb_build_object('gold', take, 'goldBefore', coalesce(g, 0), 'pct', pct, 'cargo', v_cargo);
end $$;

-- Menyelesaikan pelayaran: kapal dilepas dan tiba di kota tujuan
create or replace function game.tony_finish(p_pid uuid, p_msg text) returns jsonb
language plpgsql as $$
declare v_dest text;
begin
  select destination_city_id into v_dest from game.player_location where player_id = p_pid;
  return game.voy_finalize_arrival(p_pid, v_dest, p_msg);
end $$;

-- ---------------------------------------------------------------------
-- Satu aksi pemain melawan Tony: fire | reload | surrender (+ penolakan taktik lain)
-- ---------------------------------------------------------------------
create or replace function game.tony_act(p_pid uuid, p_tactic text) returns jsonb
language plpgsql as $$
declare l game.player_location; enc jsonb; stats jsonb; ship jsonb;
  lvl numeric; mhp numeric; hp numeric; ammo numeric; mammo numeric; rnd int;
  chance numeric; dmg numeric := 0; hit boolean := false; powder boolean := false;
  mx numeric; cd numeric := 0; newc numeric; lbl text; msg text; tgt text; rob jsonb; fin jsonb; win bigint; v_name text;
begin
  select * into l from game.player_location where player_id = p_pid for update;
  enc := l.pending_encounter;
  if not found or jsonb_typeof(enc) <> 'object' or coalesce(enc ->> 'kind', '') <> 'tony' then
    raise exception 'Tidak ada pertempuran yang sedang menunggu.';
  end if;
  p_tactic := lower(coalesce(p_tactic, ''));
  if p_tactic = 'flee' then raise exception 'Tony tersenyum tipis: "Kabur? Ke mana? Empat arah sudah kami tutup."'; end if;
  if p_tactic in ('bribe', 'negotiate') then raise exception '%', enc ->> 'noTalkMsg'; end if;
  if p_tactic = 'ram' then raise exception 'Menabrak empat kapal sekaligus? Lambungmu yang hancur duluan, Kapten.'; end if;

  -- Menyerah (kapan saja)
  if p_tactic in ('surrender', 'serah') then
    rob := game.tony_rob(p_pid, enc, 'serah');
    msg := case when coalesce((enc ->> 'fought')::boolean, false)
      then 'Kapten mengibarkan bendera putih. Tony mencatat: "Muatanmu: semua. Gold-mu: ' || (rob ->> 'pct') || ' dari seratus. Kami bukan binatang."'
      else 'Kapten menurunkan layar tanpa perlawanan. Tony mencatat: "Muatanmu: semua. Gold-mu: ' || (rob ->> 'pct') || ' dari seratus. Sisanya untuk ongkos pulang."' end;
    fin := game.tony_finish(p_pid, msg);
    perform game.voy_log_combat(p_pid, game.voy_num(enc -> 'enemyLevel')::int, 'surrender', 'robbed', '');
    return jsonb_build_object('ongoing', false, 'tony', true, 'success', false, 'result', 'robbed', 'how', 'serah',
      'message', msg, 'rob', rob, 'cityId', fin -> 'cityId',
      'newCondition', game.ship_json(p_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = p_pid));
  end if;

  if p_tactic not in ('fire', 'reload') then raise exception 'Taktik tidak dikenali: %', p_tactic; end if;

  stats := coalesce(game.stats_json(p_pid), '{}'::jsonb);
  ship := coalesce(game.ship_json(p_pid), '{}'::jsonb);
  if game.ship_book_effect(p_pid, 'fy_tungku') then
    ship := ship || jsonb_build_object('CannonBonusPercent', game.voy_num(ship -> 'CannonBonusPercent') + 8);
  end if;
  enc := game.voy_enc_book(p_pid, enc);
  lvl := game.voy_num(enc -> 'enemyLevel');
  mhp := game.voy_num(enc -> 'enemyMaxHp');
  hp := game.voy_num(enc -> 'enemyHp');
  ammo := game.voy_num(enc -> 'ammoRemaining');
  mammo := game.voy_num(enc -> 'maxAmmo');
  rnd := coalesce(nullif(game.voy_num(enc -> 'round'), 0), 1)::int;
  lbl := 'Ronde ' || rnd || ': ';

  if p_tactic = 'fire' then
    if ammo <= 0 then raise exception 'Meriam kosong - isi ulang dulu sebelum menembak lagi.'; end if;
    ammo := ammo - 1;
    tgt := game.tony_target(mhp, hp);
    chance := game.voy_clamp(50 + game.voy_stat_bonus(stats -> 'Combat') * 2 + game.voy_num(ship -> 'CannonBonusPercent') - lvl * 5, 10, 92);
    hit := random() * 100 < chance;
    if hit then
      dmg := greatest(1, game.voy_round(mhp * (0.18 + random() * 0.14) * coalesce(nullif(game.voy_num(enc -> 'dmgTaken'), 0), 0.04)));
      powder := random() * 100 < game.cfg_num('TonyPowderChance', 0.5);
      if powder then
        hp := 0;
        msg := lbl || 'peluru menembus buritan Tangan Panjang dan masuk ke gudang mesiu... LEDAKAN! Api menjilat layar abu-abu, armada Tony panik.';
      else
        hp := greatest(1, hp - dmg);
        msg := lbl || 'tembakan menghantam ' || tgt || ' (-' || dmg || ' HP armada).';
      end if;
    else
      msg := lbl || 'tembakan meleset ke kabut di antara ' || tgt || ' dan Kantong Bolong.';
    end if;
  else
    ammo := mammo;
    msg := lbl || 'kru mengisi ulang meriam di bawah hujan peluru.';
  end if;

  -- Menang: gudang mesiu meledak, armada mundur
  if powder then
    win := game.cfg_num('TonyWinGold', 25000)::bigint;
    update game.players set gold = gold + win where player_id = p_pid;
    select coalesce(nullif(btrim(character_name), ''), username, 'Tanpa Nama') into v_name from game.players where player_id = p_pid;
    insert into game.tony_victims(raid_id, player_id, result, rounds, gold_before, gold_taken)
    values (coalesce((enc ->> 'raidId')::bigint, 0), p_pid, 'menang', rnd, (select gold from game.players where player_id = p_pid) - win, 0);
    perform game.sys_chat('Kabar Laut', 'Kapten ' || v_name || ' meledakkan gudang mesiu Tangan Panjang! Tony and Gank mundur ke kabut.');
    begin perform game.quest_combat_won(p_pid); exception when others then null; end;
    perform game.hr_hook(p_pid, 'combat_win', 1, jsonb_build_object('level', lvl, 'tony', true));
    msg := msg || ' Tony and Gank mundur ke kabut. Dari puing yang hanyut, kru memungut ' || win || ' gold.';
    fin := game.tony_finish(p_pid, msg);
    perform game.voy_log_combat(p_pid, lvl::int, p_tactic, 'won', win || ' gold (gudang mesiu)');
    return jsonb_build_object('ongoing', false, 'tony', true, 'success', true, 'result', 'won', 'how', 'mesiu',
      'message', msg, 'gold', win, 'cityId', fin -> 'cityId',
      'newCondition', game.ship_json(p_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = p_pid));
  end if;

  -- Balasan empat kapal: pasti kena setiap ronde
  mx := game.voy_max_cond(p_pid);
  cd := game.voy_round(mx * (game.cfg_num('TonyHitPctMin', 12)
        + random() * (game.cfg_num('TonyHitPctMax', 18) - game.cfg_num('TonyHitPctMin', 12))) / 100);
  newc := game.apply_condition_delta(p_pid, -cd);
  msg := msg || ' Empat kapal membalas serentak (-' || cd || ' Condition).';

  enc := enc || jsonb_build_object('enemyHp', hp, 'ammoRemaining', ammo, 'round', rnd + 1, 'fought', true, 'lastAt', game.now_ms());

  -- Kalah: kapal tidak tenggelam, kondisi dipulihkan ke TonyLoseCondPct, dirampas
  if coalesce(newc, 0) <= 0 then
    perform game.apply_condition_delta(p_pid, mx * game.cfg_num('TonyLoseCondPct', 10) / 100);
    update game.player_location set pending_encounter = enc where player_id = p_pid;
    rob := game.tony_rob(p_pid, enc, 'kalah');
    msg := msg || ' Lambungmu tak sanggup lagi. Pengait Si Jepit menancap di pagar kapal. Tony: "Berani. Tapi berani tidak masuk pembukuan." Seluruh muatan dan ' || (rob ->> 'gold') || ' gold berpindah ke Kantong Bolong.';
    fin := game.tony_finish(p_pid, msg);
    -- kerusakan pelayaran saat merapat tidak boleh membuat kapal di bawah batas kalah
    update game.ships set condition = greatest(condition, game.voy_round(mx * game.cfg_num('TonyLoseCondPct', 10) / 100))
     where player_id = p_pid;
    perform game.voy_log_combat(p_pid, lvl::int, p_tactic, 'robbed', '');
    return jsonb_build_object('ongoing', false, 'tony', true, 'success', false, 'result', 'robbed', 'how', 'kalah',
      'message', msg, 'rob', rob, 'cityId', fin -> 'cityId',
      'newCondition', game.ship_json(p_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = p_pid));
  end if;

  update game.player_location set pending_encounter = enc where player_id = p_pid;
  perform game.voy_log_combat(p_pid, lvl::int, p_tactic, 'round', '');
  return jsonb_build_object('ongoing', true, 'tony', true, 'message', msg, 'encounter', enc,
    'hit', hit, 'damage', dmg, 'conditionDelta', -cd,
    'newCondition', game.ship_json(p_pid) -> 'Condition', 'newGold', (select gold from game.players where player_id = p_pid));
end $$;

-- Menyerah otomatis bila pertempuran Tony dibiarkan terlalu lama
create or replace function game.tony_auto(p_pid uuid) returns void
language plpgsql as $$
declare enc jsonb; rob jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if jsonb_typeof(enc) <> 'object' or coalesce(enc ->> 'kind', '') <> 'tony' then return; end if;
  if game.now_ms() - coalesce((enc ->> 'lastAt')::bigint, 0) < game.cfg_num('TonyAutoSurrenderMin', 10) * 60000 then return; end if;
  select pending_encounter into enc from game.player_location where player_id = p_pid for update;
  if jsonb_typeof(enc) <> 'object' or coalesce(enc ->> 'kind', '') <> 'tony' then return; end if;
  rob := game.tony_rob(p_pid, enc, 'auto');
  perform game.tony_finish(p_pid, 'Kapalmu terombang-ambing tanpa nakhoda di tengah kepungan. Tony tidak menunggu: seluruh muatan dan ' ||
    (rob ->> 'gold') || ' gold dibawa pergi.');
end $$;

-- ---------------------------------------------------------------------
-- State klien: bisikan lapau (bisik/umum) + kabut peta (umum). null = tidak ada.
-- Mode diam tidak pernah muncul di sini.
-- ---------------------------------------------------------------------
create or replace function game.tony_state(p_pid uuid) returns jsonb
language plpgsql as $$
declare v_rum jsonb := '[]'::jsonb; v_fog jsonb := '[]'::jsonb; r record; lead interval; h text; i int;
begin
  begin
    if coalesce(game.pasir_era(p_pid), 'kini') <> 'kini' then return null; end if;   -- masa lalu: Tony belum ada
  exception when others then null;
  end;
  lead := make_interval(mins => game.cfg_num('TonyRumorLeadMin', 60)::int);
  for r in select * from game.tony_raid
            where cancelled_at is null and kabar in ('bisik', 'umum')
              and now() >= start_at - lead and now() < end_at
            order by id loop
    h := game.tony_hint(r.dest_city);
    i := (r.id % 3)::int;
    v_rum := v_rum || jsonb_build_array(
      case i when 0 then 'Ada empat layar abu-abu terlihat dekat ' || h || '. Jangan bawa muatan mahal ke sana.'
             when 1 then 'Kalau mau ke ' || h || ' dalam waktu dekat, titipkan dulu gold-mu di bank.'
             else 'Tony sedang menghitung lagi. Katanya bukunya terbuka di perairan ' || h || '.' end);
    if r.kabar = 'umum' and now() >= r.start_at then
      v_fog := v_fog || jsonb_build_array(jsonb_build_object('city', r.dest_city, 'until', (extract(epoch from r.end_at) * 1000)::bigint));
    end if;
  end loop;
  if v_rum = '[]'::jsonb and v_fog = '[]'::jsonb then return null; end if;
  return jsonb_build_object('rumors', v_rum, 'fog', v_fog);
end $$;

-- Pengumuman otomatis mode Umum (sekali per event, saat event mulai)
create or replace function game.tony_tick() returns void
language plpgsql as $$
declare r game.tony_raid; v_city text; v_tx text; v_aid bigint;
begin
  for r in update game.tony_raid t set announced = true
             where t.id in (select id from game.tony_raid
                             where cancelled_at is null and not announced and kabar = 'umum'
                               and now() >= start_at and now() < end_at
                             for update skip locked)
           returning t.* loop
    select name into v_city from game.cities where city_id = r.dest_city;
    v_tx := '⚠ Layar abu-abu terlihat di perairan ' || coalesce(v_city, r.dest_city) || '. Hati-hati sampai pukul ' ||
      to_char(r.end_at at time zone 'Asia/Jakarta', 'HH24.MI') || ' WIB.';
    insert into game.gm_announce(by_user, tx, lvl, target_at, kind, until)
    values ('Kabar Laut', v_tx, 'warn', (extract(epoch from r.end_at) * 1000)::bigint, 'say', r.end_at)
    returning id into v_aid;
    update game.tony_raid set announce_id = v_aid where id = r.id;
    perform game.gm_broadcast('Kabar Laut', v_tx);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Pembungkus titik kait
-- ---------------------------------------------------------------------
do $$
begin
  -- kd_enc (0032) -> kd_enc_inti
  drop function if exists game.kd_enc_inti(uuid, jsonb);
  alter function game.kd_enc(uuid, jsonb) rename to kd_enc_inti;
  -- api_resolveCombat (0003) -> game.api_resolvecombat_inti
  drop function if exists game.api_resolvecombat_inti(jsonb);
  alter function public.api_resolvecombat(jsonb) rename to api_resolvecombat_inti;
  alter function public.api_resolvecombat_inti(jsonb) set schema game;
  revoke all on function game.api_resolvecombat_inti(jsonb) from public, anon, authenticated;
  -- gm_pulse (0036) -> gm_pulse_inti
  drop function if exists game.gm_pulse_inti(uuid);
  alter function game.gm_pulse(uuid) rename to gm_pulse_inti;
end $$;

-- Tony hanya menggantikan bajak laut acak / pelayaran tanpa musuh, tidak pernah bos quest
create or replace function game.kd_enc(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql as $$
declare t jsonb;
begin
  if p_enc is null or jsonb_typeof(p_enc) <> 'object' or coalesce((p_enc ->> 'randomPirate')::boolean, false) then
    t := game.tony_roll(p_pid);
    if t is not null then return t; end if;
  end if;
  return game.kd_enc_inti(p_pid, p_enc);
end $$;

create or replace function public.api_resolveCombat(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_pid uuid := game.uid(); enc jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = v_pid;
  if jsonb_typeof(enc) = 'object' and coalesce(enc ->> 'kind', '') = 'tony' then
    return game.tony_act((game.me(true)).player_id, game.arg(a, 0));
  end if;
  return game.api_resolvecombat_inti(a);
end $$;
select game.expose('api_resolvecombat');

create or replace function game.gm_pulse(p_pid uuid) returns jsonb
language plpgsql as $$
declare v jsonb := game.gm_pulse_inti(p_pid); t jsonb;
begin
  begin
    perform game.tony_tick();
    if p_pid is not null then perform game.tony_auto(p_pid); t := game.tony_state(p_pid); end if;
    if t is not null then
      v := coalesce(v, jsonb_build_object('t', game.now_ms())) || jsonb_build_object('tony', t);
    end if;
  exception when others then null;
  end;
  return v;
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT PEMAIN: api_tonyRaid([aksi]) aksi = fire | reload | serah
-- ---------------------------------------------------------------------
create or replace function public.api_tonyRaid(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true);
begin
  return game.tony_act(v_me.player_id, coalesce(game.arg(a, 0), ''));
end $$;
select game.expose('api_tonyraid');

-- ---------------------------------------------------------------------
-- ENDPOINT GM: api_gmTony([aksi, opsi])
--   'list'
--   'add'    {dest, origin?, startAt ms, endAt ms, chance, goldPct, kabar: diam|bisik|umum, siar: bool}
--   'cancel' {id}
-- ---------------------------------------------------------------------
create or replace function game.tony_list() returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'now', game.now_ms(),
    'cities', (select coalesce(jsonb_agg(jsonb_build_object('id', c.city_id, 'name', c.name, 'hidden', c.hidden) order by c.hidden, c.name), '[]'::jsonb)
                 from game.cities c where not game.spot_city(c.city_id) and c.city_id not like 'sudyrman%'),
    'raids', (select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint desc), '[]'::jsonb) from (
      select jsonb_build_object(
        'id', r.id, 'dest', r.dest_city, 'destName', (select name from game.cities where city_id = r.dest_city),
        'origin', r.origin_city, 'originName', (select name from game.cities where city_id = r.origin_city),
        'startAt', (extract(epoch from r.start_at) * 1000)::bigint, 'endAt', (extract(epoch from r.end_at) * 1000)::bigint,
        'chance', r.chance, 'goldPct', r.gold_pct, 'kabar', r.kabar, 'siar', r.announce_victims,
        'status', case when r.cancelled_at is not null then 'batal' when now() < r.start_at then 'terjadwal'
                       when now() < r.end_at then 'aktif' else 'selesai' end,
        'rolls', r.rolls, 'hits', r.hits,
        'korban', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result <> 'menang'),
        'lawan', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result = 'kalah'),
        'serah', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result in ('serah', 'auto')),
        'menang', (select count(*) from game.tony_victims v where v.raid_id = r.id and v.result = 'menang'),
        'gold', (select coalesce(sum(v.gold_taken), 0) from game.tony_victims v where v.raid_id = r.id),
        'cargoValue', (select coalesce(sum(v.cargo_value), 0) from game.tony_victims v where v.raid_id = r.id)) x
      from game.tony_raid r order by r.id desc limit 20) q)
  )
$$;

create or replace function public.api_gmTony(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), '')); o jsonb := game.arg_json(a, 1);
  v_dest text; v_origin text; v_s bigint; v_e bigint; v_now bigint := game.now_ms(); v_ch int; v_gp int; v_kb text;
  r game.tony_raid;
begin
  if not game.is_gm(v_id) then raise exception 'Perintah ini khusus GM.'; end if;
  if jsonb_typeof(o) <> 'object' then o := '{}'::jsonb; end if;

  if v_act = 'add' then
    v_dest := nullif(btrim(coalesce(o ->> 'dest', '')), '');
    v_origin := nullif(btrim(coalesce(o ->> 'origin', '')), '');
    if v_dest is null or not exists (select 1 from game.cities where city_id = v_dest) then raise exception 'Pilih kota tujuan.'; end if;
    if game.spot_city(v_dest) then raise exception 'Titik laut quest tidak bisa dijaga Tony.'; end if;
    if v_origin is not null and not exists (select 1 from game.cities where city_id = v_origin) then raise exception 'Kota asal tidak dikenal.'; end if;
    if v_origin = v_dest then raise exception 'Kota asal dan tujuan tidak boleh sama.'; end if;
    v_s := game.mp_jsnum(o ->> 'startAt', 0)::bigint;
    v_e := game.mp_jsnum(o ->> 'endAt', 0)::bigint;
    if v_s <= 0 or v_e <= 0 then raise exception 'Isi jam mulai dan jam selesai.'; end if;
    if v_e <= v_s then raise exception 'Jam selesai harus setelah jam mulai.'; end if;
    if v_e - v_s > 86400000 then raise exception 'Satu event maksimal 24 jam.'; end if;
    if v_e <= v_now then raise exception 'Jam selesai sudah lewat.'; end if;
    if v_s > v_now + 7 * 86400000 then raise exception 'Jadwal maksimal 7 hari ke depan.'; end if;
    v_ch := least(100, greatest(1, game.mp_jsnum(o ->> 'chance', 80)::int));
    v_gp := least(90, greatest(10, game.mp_jsnum(o ->> 'goldPct', 60)::int));
    v_kb := lower(coalesce(o ->> 'kabar', 'bisik'));
    if v_kb not in ('diam', 'bisik', 'umum') then v_kb := 'bisik'; end if;
    insert into game.tony_raid(dest_city, origin_city, start_at, end_at, chance, gold_pct, kabar, announce_victims, created_by)
    values (v_dest, v_origin, case when v_s <= v_now then now() else to_timestamp(v_s / 1000.0) end, to_timestamp(v_e / 1000.0), v_ch, v_gp, v_kb,
            coalesce((o ->> 'siar')::boolean, true), coalesce((select username from game.players where player_id = v_id), ''));
    perform game.tony_tick();

  elsif v_act = 'cancel' then
    select * into r from game.tony_raid where id = game.mp_jsnum(o ->> 'id', 0)::bigint for update;
    if r.id is null then raise exception 'Event tidak ditemukan.'; end if;
    if r.cancelled_at is null then
      update game.tony_raid set cancelled_at = now() where id = r.id;
      if r.announce_id is not null then update game.gm_announce set until = now() where id = r.announce_id and until > now(); end if;
    end if;

  elsif v_act <> 'list' then
    raise exception 'Perintah tidak dikenal: %', v_act;
  end if;

  return game.tony_list();
end $$;
select game.expose('api_gmtony');
