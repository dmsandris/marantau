-- =====================================================================
-- 0087 · DAMAGE MERIAM, LAMBUNG WARLORD 3.000+, TONY BISA DIPUKUL MUNDUR  (Tide v67)
-- ---------------------------------------------------------------------
-- 1. Damage tembakan meriam ikut upgrade Cannons:
--      pengali = 1 + MeriamDmgPerLangkah x langkah (0..20)  ->  x1 .. x2
--      pemilik Meriam Warlord: x MeriamDmgWarlord (menggantikan, bukan menambah)
--    Berlaku di tempur laut biasa (bajak laut acak / bernama, Pemburu Tedsky) dan
--    pencegatan Tony and Gank. TIDAK berlaku untuk bos quest (encounter bertanda
--    'boss'), Duel Lambung, Serbuan Bersama, dan Perburuan Tony (ketiganya memakai
--    game.mp_fighter, tidak lewat voy_resolve_round).
-- 2. Lambung Warlord: kondisi maks +20 -> +WarlordLambungBonus (1.104; Hull mentok
--    2.096 -> 3.200). Pagar: biaya reparasi dihitung dari kondisi maks lama, jadi
--    reparasi penuh tidak lebih mahal dari sebelumnya. HP Duel Lambung tidak berubah
--    (dihitung dari persen kondisi + pagar Tier V di 0078).
--    Pemilik lama: kondisi sekarang dinaikkan proporsional sekali (penanda hp87_at).
-- 3. Pencegatan Tony and Gank: HP armada <= TonyKaburPct (10%) -> Tony melarikan
--    diri. Pemain selamat, tidak dirampas, tanpa hadiah, tanpa kabar dunia, tanpa
--    catatan di tony_victims. Kenop keseimbangan khusus pencegatan: TonyCegatDmgKali.
--    Perburuan Tony (0063) tidak disentuh.
--
-- Titik kait (pola bungkus, akhiran _dm):
--   game.voy_effective_stats · game.ship_json · game.voy_resolve_round
--   game.voy_repair_quote · game.voy_effect_line · game.wl_state
--   game.tony_act dibuat ulang utuh (salinan 0061 + pengali meriam + Tony kabur).
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('MeriamDmgPerLangkah', '0.05'),   -- tambahan pengali damage tembakan per langkah Cannons
  ('MeriamDmgWarlord', '5'),         -- pengali damage tembakan pemilik Meriam Warlord
  ('WarlordLambungBonus', '1104'),   -- kondisi maks tambahan dari Lambung Warlord (dulu 20)
  ('TonyKaburPct', '10'),            -- Tony kabur bila HP armada <= sekian % (0 = tidak pernah)
  ('TonyCegatDmgKali', '2.8')        -- pengali damage meriam ke armada Tony saat pencegatan
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Pengali damage meriam
-- ---------------------------------------------------------------------
create or replace function game.meriam_dmg_langkah(p_step int) returns numeric
language sql stable as $$
  select 1 + greatest(0, game.cfg_num('MeriamDmgPerLangkah', 0.05)) * greatest(0, least(20, coalesce(p_step, 0)))
$$;

create or replace function game.meriam_dmg_kali(p_pid uuid) returns numeric
language plpgsql stable as $$
begin
  if game.wl_has(p_pid, 'cannons') then return greatest(1, game.cfg_num('MeriamDmgWarlord', 5)); end if;
  return game.meriam_dmg_langkah(game.voy_abs_step(game.voy_player_upgrades(p_pid) -> 'cannons'));
exception when others then return 1;
end $$;

-- 1,45 (dua desimal, koma)
create or replace function game.meriam_fmt(x numeric) returns text
language sql immutable as $$ select replace(trim(to_char(x, 'FM9990.00')), '.', ',') $$;

-- 5 / 5,5 (tanpa nol di belakang)
create or replace function game.meriam_fmt_pendek(x numeric) returns text
language sql immutable as $$ select replace(rtrim(to_char(x, 'FM9990.##'), '.'), '.', ',') $$;

-- Kondisi maks tambahan Lambung Warlord (pengganti +20 di 0078)
create or replace function game.wl_lambung_bonus() returns numeric
language sql stable as $$ select greatest(20, game.cfg_num('WarlordLambungBonus', 1104)) $$;

-- ---------------------------------------------------------------------
-- Stat efektif: Lambung Warlord (+20 dari 0078 diganti WarlordLambungBonus)
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.voy_effective_stats_dm(uuid);
  alter function game.voy_effective_stats(uuid) rename to voy_effective_stats_dm;
  drop function if exists game.ship_json_dm(uuid);
  alter function game.ship_json(uuid) rename to ship_json_dm;
  drop function if exists game.voy_resolve_round_dm(text, jsonb, jsonb, jsonb, bigint);
  alter function game.voy_resolve_round(text, jsonb, jsonb, jsonb, bigint) rename to voy_resolve_round_dm;
  drop function if exists game.voy_repair_quote_dm(uuid, text);
  alter function game.voy_repair_quote(uuid, text) rename to voy_repair_quote_dm;
  drop function if exists game.voy_effect_line_dm(uuid, text, int, int, numeric);
  alter function game.voy_effect_line(uuid, text, int, int, numeric) rename to voy_effect_line_dm;
  drop function if exists game.wl_state_dm(uuid);
  alter function game.wl_state(uuid) rename to wl_state_dm;
end $$;
revoke all on function game.voy_effective_stats_dm(uuid) from public, anon, authenticated;
revoke all on function game.ship_json_dm(uuid) from public, anon, authenticated;
revoke all on function game.voy_resolve_round_dm(text, jsonb, jsonb, jsonb, bigint) from public, anon, authenticated;
revoke all on function game.voy_repair_quote_dm(uuid, text) from public, anon, authenticated;
revoke all on function game.voy_effect_line_dm(uuid, text, int, int, numeric) from public, anon, authenticated;
revoke all on function game.wl_state_dm(uuid) from public, anon, authenticated;

create or replace function game.voy_effective_stats(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb;
begin
  j := game.voy_effective_stats_dm(p_pid);
  begin
    if game.wl_has(p_pid, 'condition') then
      j := j || jsonb_build_object('maxConditionBonus',
        coalesce((j ->> 'maxConditionBonus')::numeric, 0) - 20 + game.wl_lambung_bonus());
    end if;
  exception when others then null;
  end;
  return j;
end $$;

-- ship_json: CannonDmgMul (dipakai mesin ronde & klien)
create or replace function game.ship_json(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb;
begin
  j := game.ship_json_dm(p_pid);
  if j is null then return j; end if;
  return j || jsonb_build_object('CannonDmgMul', game.meriam_dmg_kali(p_pid));
end $$;

-- ---------------------------------------------------------------------
-- Mesin ronde: tembakan kena dikali pengali meriam, kecuali bos quest.
-- (dmgTaken sudah menjadi pengali damage di inti; pengali meriam ditumpangkan di sana.)
-- ---------------------------------------------------------------------
create or replace function game.voy_resolve_round(p_tactic text, enc jsonb, stats jsonb, ship jsonb, p_gold bigint) returns jsonb
language plpgsql volatile as $$
declare k numeric;
begin
  if p_tactic = 'fire' and coalesce(enc ->> 'boss', '') = '' then
    k := coalesce(nullif(game.voy_num(ship -> 'CannonDmgMul'), 0), 1);
    if k <> 1 then
      enc := enc || jsonb_build_object('dmgTaken', coalesce(nullif(game.voy_num(enc -> 'dmgTaken'), 0), 1) * k);
    end if;
  end if;
  return game.voy_resolve_round_dm(p_tactic, enc, stats, ship, p_gold);
end $$;

-- ---------------------------------------------------------------------
-- Reparasi: pagar Lambung Warlord. Biaya dihitung seolah kondisi maks masih
-- memakai bonus lama (+20), jadi reparasi penuh tidak lebih mahal dari sebelumnya.
-- ---------------------------------------------------------------------
create or replace function game.voy_repair_quote(p_pid uuid, p_city text) returns jsonb
language plpgsql stable as $$
declare q jsonb; mx numeric; lama numeric;
begin
  q := game.voy_repair_quote_dm(p_pid, p_city);
  begin
    if game.wl_has(p_pid, 'condition') then
      mx := (q ->> 'maxCondition')::numeric;
      lama := mx - (game.wl_lambung_bonus() - 20);
      if mx > 0 and lama > 0 and lama < mx then
        q := q || jsonb_build_object('cost', game.voy_round((q ->> 'cost')::numeric * lama / mx));
      end if;
    end if;
  exception when others then null;
  end;
  return q;
end $$;

-- ---------------------------------------------------------------------
-- Teks efek kartu upgrade Cannons: + damage tembakan
-- ---------------------------------------------------------------------
create or replace function game.voy_effect_line(p_pid uuid, p_group text, p_step int, p_next int, p_inc numeric) returns text
language plpgsql stable as $$
declare t text := game.voy_effect_line_dm(p_pid, p_group, p_step, p_next, p_inc);
begin
  if p_group <> 'cannons' then return t; end if;
  begin
    if game.wl_has(p_pid, 'cannons') then
      return t || ', damage tembakan &times;' || game.meriam_fmt_pendek(greatest(1, game.cfg_num('MeriamDmgWarlord', 5))) || ' (Meriam Warlord)';
    end if;
    if p_next is null then
      return t || ', damage tembakan &times;' || game.meriam_fmt(game.meriam_dmg_langkah(p_step));
    end if;
    return t || ', damage tembakan &times;' || game.meriam_fmt(game.meriam_dmg_langkah(p_step))
      || ' &rarr; &times;' || game.meriam_fmt(game.meriam_dmg_langkah(p_next));
  exception when others then return t;
  end;
end $$;

-- ---------------------------------------------------------------------
-- Garasi Warlord: teks efek tiap komponen
-- ---------------------------------------------------------------------
create or replace function game.wl_efek(p_grup text) returns text
language sql stable as $$
  select case p_grup
    when 'speed' then 'Batas waktu tempuh 25 → 20 detik'
    when 'cargo' then 'Kapasitas palka +15%'
    when 'condition' then 'Kondisi maks +' || replace(to_char(game.wl_lambung_bonus(), 'FM999G999'), ',', '.') || ', aus per layar -10%'
    else 'Damage tembakan ×' || game.meriam_fmt_pendek(greatest(1, game.cfg_num('MeriamDmgWarlord', 5))) || ', peluang menang +5%, +1 amunisi'
  end
$$;

create or replace function game.wl_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb := game.wl_state_dm(p_pid);
begin
  if j is null or jsonb_typeof(j -> 'komponen') <> 'array' then return j; end if;
  return j || jsonb_build_object('komponen',
    (select jsonb_agg(k || jsonb_build_object('efek', game.wl_efek(k ->> 'grup')) order by o)
       from jsonb_array_elements(j -> 'komponen') with ordinality x(k, o)));
exception when others then return j;
end $$;

-- ---------------------------------------------------------------------
-- Pemilik Lambung Warlord: kondisi sekarang naik proporsional, sekali saja.
--   hp87_at  penanda: baris ini sudah disesuaikan.
--   p_lama   bonus Lambung Warlord yang berlaku sebelum penyesuaian (20 = pemilik lama,
--            0 = baru dipasang).
-- ---------------------------------------------------------------------
alter table game.mk_warlord add column if not exists hp87_at timestamptz;

create or replace function game.wl_hp_sesuaikan(p_pid uuid, p_lama numeric) returns boolean
language plpgsql as $$
declare mx numeric; lama numeric; c numeric;
begin
  update game.mk_warlord set hp87_at = now() where player_id = p_pid and grup = 'condition' and hp87_at is null;
  if not found then return false; end if;
  mx := game.voy_max_cond(p_pid);
  lama := mx - (game.wl_lambung_bonus() - coalesce(p_lama, 0));
  select condition into c from game.ships where player_id = p_pid for update;
  if c is null or lama <= 0 or lama >= mx then return true; end if;
  update game.ships set condition = least(mx, game.voy_round(c * mx / lama)) where player_id = p_pid;
  return true;
end $$;

create or replace function game.wl_hp_trg() returns trigger
language plpgsql as $$
begin
  if new.grup = 'condition' then
    begin perform game.wl_hp_sesuaikan(new.player_id, 0); exception when others then null; end;
  end if;
  return null;
end $$;
drop trigger if exists wl_hp_trg on game.mk_warlord;
create trigger wl_hp_trg after insert on game.mk_warlord for each row execute function game.wl_hp_trg();

-- pemilik lama (terpasang sebelum migrasi ini): sekali
do $$
declare r record;
begin
  for r in select player_id from game.mk_warlord where grup = 'condition' and hp87_at is null loop
    perform game.wl_hp_sesuaikan(r.player_id, 20);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Tony and Gank: satu aksi pemain (salinan 0061 + pengali meriam + Tony kabur)
-- ---------------------------------------------------------------------
create or replace function game.tony_act(p_pid uuid, p_tactic text) returns jsonb
language plpgsql as $$
declare l game.player_location; enc jsonb; stats jsonb; ship jsonb;
  lvl numeric; mhp numeric; hp numeric; ammo numeric; mammo numeric; rnd int;
  chance numeric; dmg numeric := 0; hit boolean := false; powder boolean := false;
  mx numeric; cd numeric := 0; newc numeric; lbl text; msg text; tgt text; rob jsonb; fin jsonb; win bigint; v_name text;
  v_kabur numeric;
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
      -- Tide v67: damage ikut upgrade Cannons / Meriam Warlord, dikali kenop pencegatan
      dmg := greatest(1, game.voy_round(mhp * (0.18 + random() * 0.14) * coalesce(nullif(game.voy_num(enc -> 'dmgTaken'), 0), 0.04)
        * coalesce(nullif(game.voy_num(ship -> 'CannonDmgMul'), 0), 1)
        * greatest(0.01, game.cfg_num('TonyCegatDmgKali', 2.8))));
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

  -- Tide v67: armada tinggal <= TonyKaburPct% -> Tony melarikan diri sebelum sempat membalas.
  -- Pemain selamat: tidak dirampas, tanpa hadiah, tanpa kabar dunia, tanpa catatan tony_victims.
  v_kabur := game.cfg_num('TonyKaburPct', 10);
  if v_kabur > 0 and mhp > 0 and hp <= mhp * v_kabur / 100 then
    msg := msg || ' Tiga lambung abu-abu sudah miring, dan Tangan Panjang mulai kemasukan air. Tony menutup bukunya pelan-pelan: "Hari ini rugi. Rugi juga dicatat." Empat layar abu-abu berputar dan hilang ke kabut. Muatan dan gold-mu utuh.';
    fin := game.tony_finish(p_pid, msg);
    perform game.log(p_pid, 'Memukul mundur Tony and Gank: muatan dan gold utuh.');
    perform game.voy_log_combat(p_pid, lvl::int, p_tactic, 'repelled', '');
    return jsonb_build_object('ongoing', false, 'tony', true, 'success', true, 'result', 'repelled', 'how', 'kabur',
      'message', msg, 'hit', hit, 'damage', dmg, 'enemyHp', hp, 'cityId', fin -> 'cityId',
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
