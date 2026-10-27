-- =====================================================================
-- Tide v37 · Fase 3: Set Rupa, Kesaktian Set, Lemari Rupa, Etalase Pekan
-- * Set Api Gunung (langka, 5 barang) & Set Naga Samudra (agung, 5 barang).
--   Lima barang satu set terpasang = Kesaktian Set (efek tampilan, tanpa kekuatan).
--   kd_visual menambah {"sakti": ["api_gunung", ...]} -> ship_visual.kd -> kapten lain.
-- * Lemari Rupa: 3 susunan rupa tersimpan (gratis), ganti sekali klik.
-- * Etalase Pekan: tiap Senin 08:00 WIB, 3 barang rupa diskon EtalaseDiskon (25%).
-- * Hadiah gold Pacu Dagang aktif (config di 0033).
-- Idempoten: aman dijalankan ulang.
-- =====================================================================

insert into game.config(key, value) values
  ('EtalaseDiskon', '0.25'), ('EtalaseJumlah', '3'), ('LemariSlot', '3')
on conflict (key) do nothing;

insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, exclusive, active, sort) values
  -- Set Api Gunung (langka) - total 6.000
  ('lambung_lava',     'rupa', 'lambung',    'api_gunung',   'Lambung Lava Retak', 'langka', 1200, 'Retakan merah menyala di sepanjang lambung, makin terang saat malam.', null, false, true, 300),
  ('layar_bara',       'rupa', 'layar',      'api_gunung',   'Layar Bara',         'langka', 1400, 'Tepi layar membara, bara kecil beterbangan ditiup angin.', null, false, true, 301),
  ('jejak_bara',       'rupa', 'jejak',      'api_gunung',   'Jejak Bara',         'langka', 1200, 'Buih di belakang kapal berubah jadi percikan api di atas air.', null, false, true, 302),
  ('meriam_letusan',   'rupa', 'meriam',     'api_gunung',   'Meriam Letusan',     'langka', 1000, 'Mulut meriam membara. Di pertempuran, peluru berubah jadi semburan lava.', null, false, true, 303),
  ('datang_asap',      'rupa', 'kedatangan', 'api_gunung',   'Asap Gunung',        'langka', 1200, 'Tiba di pelabuhan disambut kepulan asap gunung dan hujan abu.', null, false, true, 304),
  -- Set Naga Samudra (agung) - total 9.000
  ('haluan_naga',      'rupa', 'haluan',     'naga_samudra', 'Kepala Naga',        'agung', 2000, 'Patung kepala naga di haluan. Matanya menyala, napasnya kabut laut.', null, false, true, 310),
  ('lambung_sisik',    'rupa', 'lambung',    'naga_samudra', 'Sisik Naga',         'agung', 1800, 'Lambung bersisik hijau laut yang berkilau kena cahaya.', null, false, true, 311),
  ('layar_sirip',      'rupa', 'layar',      'naga_samudra', 'Layar Sirip Naga',   'agung', 1800, 'Layar bertulang seperti sirip naga, berselaput hijau laut.', null, false, true, 312),
  ('jejak_ekor',       'rupa', 'jejak',      'naga_samudra', 'Ekor Naga',          'agung', 1800, 'Ekor naga air meliuk di belakang kapal.', null, false, true, 313),
  ('aura_mutiara',     'rupa', 'aura',       'naga_samudra', 'Kabut Mutiara',      'agung', 1600, 'Butir mutiara melayang mengitari kapal dalam kabut tipis.', null, false, true, 314)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Set & Kesaktian Set
-- ---------------------------------------------------------------------
create or replace function game.kd_set_name(p_set text) returns text
language sql immutable as $$
  select case p_set when 'api_gunung' then 'Set Api Gunung' when 'naga_samudra' then 'Set Naga Samudra' else p_set end
$$;

create or replace function game.kd_set_info(p_set text) returns text
language sql immutable as $$
  select case p_set
    when 'api_gunung' then 'Udara panas bergetar di sekitar kapal, letusan kecil sesekali dari puncak tiang, retakan makin terang saat malam.'
    when 'naga_samudra' then 'Naga air bening sesekali muncul dari laut, melingkari kapal, lalu menyelam. Saat kapal tiba, ia muncul menyambut.'
    else '' end
$$;

-- set yang kelima barangnya terpasang
create or replace function game.kd_sets_complete(p_equipped jsonb) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(s.set_id order by s.set_id), '[]'::jsonb) from (
    select i.set_id from game.kd_items i
     where i.set_id is not null and i.active and i.rak = 'rupa'
     group by i.set_id
    having bool_and(coalesce(p_equipped ->> i.slot, '') = i.id)
  ) s
$$;

-- rupa kapal untuk ship_visual: loadout + Layar Emas (juara Pacu) + Kesaktian Set
create or replace function game.kd_visual(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare e jsonb; v jsonb; s jsonb;
begin
  select l.equipped into e from game.kd_loadout l where l.player_id = p_pid;
  e := coalesce(e, '{}'::jsonb);
  v := e;
  if exists (select 1 from (select results from game.pd_events where status = 'announced' order by sat desc limit 1) z
              where z.results -> 'winners' ? p_pid::text) then
    v := v || '{"emas": true}'::jsonb;
  end if;
  s := game.kd_sets_complete(e);
  if jsonb_array_length(s) > 0 then v := v || jsonb_build_object('sakti', s); end if;
  return nullif(v, '{}'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- Etalase Pekan (Senin 08:00 WIB - Senin berikutnya)
-- ---------------------------------------------------------------------
create or replace function game.kd_week_start() returns timestamp
language sql stable as $$ select date_trunc('week', game.pd_wib() - interval '8 hours') + interval '8 hours' $$;

create or replace function game.kd_etalase_ids() returns text[]
language sql stable as $$
  select coalesce(array_agg(id), '{}') from (
    select i.id from game.kd_items i
     where i.rak = 'rupa' and i.active and not i.exclusive
     order by md5(i.id || to_char(game.kd_week_start(), 'YYYY-MM-DD')) limit greatest(0, game.cfg_num('EtalaseJumlah', 3)::int)
  ) z
$$;

create or replace function game.kd_base_price(p_id text) returns int
language sql stable as $$
  select greatest(0, round(coalesce(i.price_admin, i.price) * game.cfg_num('KedaiPriceMul', 1)))::int from game.kd_items i where i.id = p_id
$$;

-- harga jual Kedai = harga dasar, dikurangi diskon Etalase bila barang sedang dipajang
create or replace function game.kd_price(p_id text) returns int
language sql stable as $$
  select case when p_id = any(game.kd_etalase_ids())
    then greatest(0, round(game.kd_base_price(p_id) * (1 - game.cfg_num('EtalaseDiskon', 0.25))))::int
    else game.kd_base_price(p_id) end
$$;

-- ---------------------------------------------------------------------
-- Lemari Rupa
-- ---------------------------------------------------------------------
create table if not exists game.kd_lemari (
  player_id uuid not null references game.players(player_id) on update cascade on delete cascade,
  n         int not null,
  name      text not null default '',
  equipped  jsonb not null default '{}'::jsonb,
  at        timestamptz not null default now(),
  primary key (player_id, n)
);
alter table game.kd_lemari enable row level security;

create or replace function game.kd_rupa_view(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare n timestamp := game.pd_wib(); ws timestamp := game.kd_week_start(); e jsonb;
begin
  select equipped into e from game.kd_loadout where player_id = p_pid;
  return jsonb_build_object(
    'etalase', jsonb_build_object('ids', to_jsonb(game.kd_etalase_ids()), 'diskon', game.cfg_num('EtalaseDiskon', 0.25),
      'msLeft', greatest(0, floor(extract(epoch from (ws + interval '7 days' - n)) * 1000))::bigint,
      'base', coalesce((select jsonb_object_agg(id, game.kd_base_price(id)) from unnest(game.kd_etalase_ids()) id), '{}'::jsonb)),
    'lemari', coalesce((select jsonb_agg(jsonb_build_object('n', l.n, 'name', l.name, 'equipped', l.equipped,
        'sakti', game.kd_sets_complete(l.equipped)) order by l.n) from game.kd_lemari l where l.player_id = p_pid), '[]'::jsonb),
    'slots', game.cfg_num('LemariSlot', 3)::int,
    'sets', coalesce((select jsonb_agg(jsonb_build_object('id', z.set_id, 'name', game.kd_set_name(z.set_id), 'info', game.kd_set_info(z.set_id),
        'items', z.items, 'owned', z.owned, 'complete', game.kd_sets_complete(coalesce(e, '{}'::jsonb)) ? z.set_id) order by z.set_id)
      from (select i.set_id, jsonb_agg(i.id order by i.sort) items, count(*) filter (where game.kd_qty(p_pid, i.id) > 0) owned
              from game.kd_items i where i.set_id is not null and i.active group by i.set_id) z), '[]'::jsonb));
end $$;

-- a = [aksi, ...]: status | simpan <n> <nama> | pakai <n> | hapus <n>
create or replace function public.api_rupa(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'status');
  v_n int := game.arg_int(a, 1); v_name text := left(btrim(coalesce(game.arg(a, 2), '')), 24); l game.kd_lemari; e jsonb; k text; v_skip int := 0;
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KedaiOpen') then raise exception 'Kedai Rantau belum dibuka.'; end if;
  insert into game.kd_loadout(player_id) values (v_pid) on conflict (player_id) do nothing;
  if v_act <> 'status' and (v_n is null or v_n < 1 or v_n > game.cfg_num('LemariSlot', 3)::int) then raise exception 'Laci lemari tidak dikenal.'; end if;

  if v_act = 'simpan' then
    select equipped into e from game.kd_loadout where player_id = v_pid;
    insert into game.kd_lemari as x (player_id, n, name, equipped) values (v_pid, v_n, coalesce(nullif(v_name, ''), 'Susunan ' || v_n), coalesce(e, '{}'::jsonb))
    on conflict (player_id, n) do update set name = coalesce(nullif(v_name, ''), x.name), equipped = excluded.equipped, at = now();
  elsif v_act = 'pakai' then
    select * into l from game.kd_lemari where player_id = v_pid and n = v_n;
    if not found then raise exception 'Laci % masih kosong.', v_n; end if;
    e := '{}'::jsonb;
    for k in select jsonb_object_keys(l.equipped) loop
      if game.kd_qty(v_pid, l.equipped ->> k) > 0 then e := e || jsonb_build_object(k, l.equipped ->> k); else v_skip := v_skip + 1; end if;
    end loop;
    update game.kd_loadout set equipped = e where player_id = v_pid;
    begin perform game.mp_touch(v_pid); exception when others then null; end;   -- kirim rupa baru ke kapten lain
  elsif v_act = 'hapus' then
    delete from game.kd_lemari where player_id = v_pid and n = v_n;
  elsif v_act <> 'status' then
    raise exception 'Aksi tidak dikenal: %', v_act;
  end if;

  return jsonb_build_object('rupa', game.kd_rupa_view(v_pid), 'kedai', game.kd_list(v_pid), 'shipVisual', game.ship_visual(v_pid), 'skip', v_skip);
end $$;
select game.expose('api_rupa');
