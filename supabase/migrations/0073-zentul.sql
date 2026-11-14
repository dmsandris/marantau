-- =====================================================================
-- 0073 — Zentul (Saga 4, batch 2a): atol rongsok di kanan atas peta, Laut Jauh.
--   Konsep: claude/KONSEP-Saga4-Monopoli-dan-Mahkota.md bagian 3.
--   * Kota 'zentul' (tersembunyi; terbuka per pemain lewat game.zentul_open).
--   * Barang baru PREMIUM 'oli_hitam': hanya bisa dibeli di Zentul (aturan premium 0018), tidak dipakai papan misi.
--   * Tanpa bank (bank_guard) — "Zentul tidak percaya bank".
--   * Sirkuit Selat Lurus (0072): Trektrek-an hanya saat kapal merapat di Zentul.
--   * game.zentul_open(): sementara = gerbang TrekOpen / FiturPenguji. Batch quest Mahkota menimpanya
--     (terbuka sejak langkah "Peta yang Disobek" dan seterusnya).
--   Mengait fungsi inti dengan pola *_inti (lihat ARSITEKTUR 4.2). Aman diulang.
-- =====================================================================

insert into game.commodities(id, name, flavor, sort, grp, tier, base, size, spread, elast, ref, active) values
  ('oli_hitam', 'Oli Hitam', 'Minyak pekat sulingan Zentul. Mesin meminumnya, obor menyukainya, dan tak ada pulau lain yang tahu cara membuatnya.', 44, 'bahan', 'premium', 2200, 1, 0.225, 0.6, 12, true)
on conflict (id) do update set name = excluded.name, flavor = excluded.flavor, sort = excluded.sort, grp = excluded.grp,
  tier = excluded.tier, base = excluded.base, size = excluded.size, spread = excluded.spread, elast = excluded.elast,
  ref = excluded.ref, active = true;

insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden) values
  ('zentul', 'Zentul', 'Zentul', 0.8, '', 185, 12, 40, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, repair_cost_rate = excluded.repair_cost_rate,
  map_x = excluded.map_x, map_y = excluded.map_y, sort = excluded.sort, hidden = true;
select game.cfg_set('CitiesVersion', '11-zentul');

-- Peran pasar Zentul & Oli Hitam. Ditulis ulang SETIAP deploy (0018 menyisipkan ulang peran bawaan lebih dulu).
create or replace function game.zt_market_role(p_city text, p_comm text) returns text
language sql immutable as $$
  select case
    when p_comm = 'oli_hitam' then
      case when p_city = 'zentul' then 'produce'
           when p_city in ('freeyork', 'marie_regal', 'skitraw') then 'consume'
           else 'neutral' end
    when p_city = 'zentul' then
      case when p_comm in ('besi', 'mesiu', 'tools') then 'produce'
           when p_comm in ('beras', 'ikan_asin', 'rum', 'kopi', 'kayu_jati') then 'consume'
           else 'neutral' end
    else null end
$$;

insert into game.market(city_id, commodity_id, base_price, current_price, role)
select ci.city_id, co.id, co.base, co.base, coalesce(game.zt_market_role(ci.city_id, co.id), 'neutral')
  from game.cities ci cross join game.commodities co
 where co.active and not game.spot_city(ci.city_id)
   and (ci.city_id = 'zentul' or co.id = 'oli_hitam')
on conflict (city_id, commodity_id) do update set base_price = excluded.base_price, role = excluded.role;

-- ---------------------------------------------------------------------
-- Siapa yang sudah menemukan Zentul. Ditimpa batch quest Mahkota.
-- ---------------------------------------------------------------------
create or replace function game.zentul_open(p_pid uuid) returns boolean
language sql stable as $$ select game.fitur_on(p_pid, 'TrekOpen') $$;

do $$
begin
  drop function if exists game.voy_far_city_inti(text);
  alter function game.voy_far_city(text) rename to voy_far_city_inti;
  drop function if exists game.city_flavor_inti_zt(text);
  alter function game.city_flavor(text) rename to city_flavor_inti_zt;
  drop function if exists game.city_open_inti_zt(uuid, text);
  alter function game.city_open(uuid, text) rename to city_open_inti_zt;
  drop function if exists game.player_unlocks_inti_zt(uuid);
  alter function game.player_unlocks(uuid) rename to player_unlocks_inti_zt;
end $$;

create or replace function game.voy_far_city(p_city text) returns boolean
language sql immutable as $$ select coalesce(p_city = 'zentul', false) or game.voy_far_city_inti(p_city) $$;

create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case when p_type = 'Zentul'
    then 'Atol yang dibangun dari lambung perahu rongsok. Obor dan pelita menyala siang malam, mesin meraung dari setiap bengkel, dan laut di sekelilingnya berbau oli. Di sini tak ada bank; orang Zentul hanya percaya pada yang bisa lari.'
    else game.city_flavor_inti_zt(p_type) end
$$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language plpgsql stable as $$
begin
  if p_city = 'zentul' then
    return coalesce(game.pasir_era(p_pid), 'kini') = 'kini' and game.zentul_open(p_pid);
  end if;
  return game.city_open_inti_zt(p_pid, p_city);
end $$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare u jsonb := game.player_unlocks_inti_zt(p_pid);
begin
  if coalesce(game.pasir_era(p_pid), 'kini') = 'kini' and game.zentul_open(p_pid) then
    u := coalesce(u, '[]'::jsonb) || '["zentul"]'::jsonb;
  end if;
  return u;
end $$;

-- ---------------------------------------------------------------------
-- Trektrek-an hanya di Sirkuit Selat Lurus: kapal harus merapat di Zentul.
-- (Selama TrekOpen masih '0', penguji boleh membuka dari mana saja lewat #trek.)
-- ---------------------------------------------------------------------
create or replace function game.trek_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select game.fitur_on(p_pid, 'TrekOpen')
     and ((game.current_city(p_pid) = 'zentul' and not game.in_transit(p_pid))
          or lower(coalesce(game.cfg('TrekOpen'), '0')) not in ('1', 'true', 'on', 'ya'))
$$;

-- ---------------------------------------------------------------------
-- Zentul tidak punya bank maupun rentenir.
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.bank_land_guard_inti(uuid);
  alter function game.bank_land_guard(uuid) rename to bank_land_guard_inti;
end $$;

create or replace function game.bank_land_guard(p_pid uuid) returns void
language plpgsql as $$
begin
  perform game.bank_land_guard_inti(p_pid);
  if game.current_city(p_pid) = 'zentul' then
    raise exception 'Zentul tidak punya bank, Kapten. Orang sini menyimpan emasnya di bawah mesin.';
  end if;
end $$;
