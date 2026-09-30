-- =====================================================================
-- Marantau (Supabase) - 0014 MISI RAHASIA "HARTA UDA GALA" + PULAU PARADISO (Tide v11)
-- Uda Gala (Galangan Gaul-Wash, Skitraw) memberi misi sekali seumur hidup bagi kapten
-- dengan >= 20 Tanda Jasa: 3 petunjuk (Joungjava -> Bjorneo -> IKN) -> bos Mr. GAP di rute
-- ke TooGood -> Kotak Hati -> kembali ke Uda Gala -> buku (+5 Speed) & pulau Paradiso terbuka.
-- Paradiso: kondisi kapal pulih +1 tiap 5 detik selama merapat, sampai penuh.
-- Aman diulang.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Pulau Paradiso (tersembunyi sampai misi selesai)
-- ---------------------------------------------------------------------
insert into game.cities(city_id, name, type, repair_cost_rate, image_url, map_x, map_y, sort, hidden)
values ('paradiso', 'Paradiso', 'Paradise', 0.8, '', 79, 21, 7, true)
on conflict (city_id) do update set name = excluded.name, type = excluded.type, map_x = excluded.map_x,
  map_y = excluded.map_y, hidden = true;

-- Pasar Paradiso: rum murah (produksi pulau), barang mewah dibeli mahal
insert into game.market(city_id, commodity_id, base_price, current_price)
select 'paradiso', c.id, p.price, p.price
from game.commodities c
join (values ('sugar', 115), ('silk', 345), ('spices', 255), ('rum', 58), ('tools', 150), ('arms', 205)) as p(id, price) on p.id = c.id
on conflict (city_id, commodity_id) do nothing;

select game.cfg_set('CitiesVersion', '2-paradiso');

create or replace function game.city_flavor(p_type text) returns text
language sql immutable as $$
  select case p_type
    when 'TradeHub' then 'Pelabuhan sibuk tempat semua rute berpotongan - harga stabil, pilihan barang lengkap.'
    when 'Agricultural' then 'Lumbung wilayah ini - hasil bumi murah, barang mewah harus didatangkan dari luar.'
    when 'Remote' then 'Jauh dari jalur ramai - harga lebih mahal, tapi lebih sedikit persaingan pedagang.'
    when 'Capital' then 'Kota besar yang penuh sukacita - pasar paling lengkap, harga adil dan stabil untuk semua.'
    when 'Outlaw' then 'Sarang penyamun - kapal dagang menuju sini nyaris pasti dicegat bajak laut di tengah jalan. Senjata di sini selalu lebih murah dari kota manapun.'
    when 'FallenCapital' then 'Ibu kota lama yang sudah tumbang - reruntuhan megah dengan banyak yang perlu dibenahi. Papan misi paling ramai di sini, meski bayarannya seadanya.'
    when 'Paradise' then 'Surga para pelaut yang tak ada di peta mana pun - pesta, tarian, dan mata air panas. Kapal yang merapat di sini pulih dengan sendirinya.'
    else '' end
$$;

-- Buku hadiah (tidak dijual di perpustakaan mana pun: source 'quest')
insert into game.book_catalog(book_id, name, tier, stat_effects, special_effect, price, source, sort) values
  ('bk_gala_logbook', 'Catatan Pelayaran Uda Gala', 'III', '{}', 'ship_speed_5', 0, 'quest', 99)
on conflict (book_id) do update set name = excluded.name, special_effect = excluded.special_effect, source = 'quest';

-- ---------------------------------------------------------------------
-- Status misi pemain
-- ---------------------------------------------------------------------
create table if not exists game.player_quests (
  player_id  uuid not null references game.players(player_id) on delete cascade on update cascade,
  quest_id   text not null,
  step       int not null default 1,
  data       jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  done_at    timestamptz,
  primary key (player_id, quest_id)
);
alter table game.player_quests enable row level security;

-- Langkah misi Uda Gala:
--   1 temui Pak Tua Karto di Joungjava   2 jawab teka-teki nenek mercusuar di Bjorneo
--   3 selidiki arsip IKN                 4 berlayar ke TooGood, kalahkan Mr. GAP
--   5 serahkan Kotak Hati ke Uda Gala    6 selesai (Paradiso terbuka)
create or replace function game.gala_step(p_pid uuid) returns int
language sql stable as $$ select coalesce((select step from game.player_quests where player_id = p_pid and quest_id = 'gala'), 0) $$;

create or replace function game.gala_badges(p_pid uuid) returns int
language sql stable as $$ select coalesce(game.mp_badges((select meta from game.players where player_id = p_pid)), 0) $$;

create or replace function game.gala_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare q game.player_quests; v_step int; v_city text := game.current_city(p_pid); v_badges int := game.gala_badges(p_pid);
begin
  select * into q from game.player_quests where player_id = p_pid and quest_id = 'gala';
  v_step := coalesce(q.step, 0);
  return jsonb_build_object(
    'step', v_step, 'badges', v_badges, 'need', 20, 'eligible', v_badges >= 20,
    'targetCity', (array['joungjava', 'bjorneo', 'ikn', 'toogood', 'skitraw'])[v_step],
    'here', v_city,
    'hasBox', v_step = 5,
    'done', v_step >= 6,
    'wrongUntil', coalesce((q.data ->> 'wrongUntil')::bigint, 0));
end $$;

create or replace function game.city_open(p_pid uuid, p_city text) returns boolean
language sql stable as $$
  select coalesce((select not hidden from game.cities where city_id = p_city), false)
      or (p_city = 'paradiso' and game.gala_step(p_pid) >= 6)
$$;

create or replace function game.player_unlocks(p_pid uuid) returns jsonb
language sql stable as $$ select case when game.gala_step(p_pid) >= 6 then '["paradiso"]'::jsonb else '[]'::jsonb end $$;

-- Mr. GAP menunggu di rute menuju TooGood saat langkah 4
create or replace function game.quest_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql stable as $$
declare ship jsonb; ammo numeric;
begin
  if p_dest <> 'toogood' or game.gala_step(p_pid) <> 4 then return null; end if;
  ship := coalesce(game.ship_json(p_pid), '{}'::jsonb);
  ammo := coalesce(nullif(game.voy_num(ship -> 'MaxCannonAmmo'), 0), game.cfg_num('CombatBaseAmmo', 3));
  return jsonb_build_object(
    'enemyLevel', 6, 'enemyName', 'Mr. GAP', 'boss', 'gap',
    'bossTitle', 'Bajak laut paling ditakuti di Mare Nusantara',
    'rolledAt', game.iso(now()),
    'enemyMaxHp', 600, 'enemyHp', 600, 'dmgTaken', 0.6,
    'maxAmmo', ammo, 'ammoRemaining', ammo, 'round', 1);
end $$;

create or replace function game.quest_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
begin
  if game.gala_step(p_pid) <> 4 then return null; end if;
  update game.player_quests set step = 5, updated_at = now() where player_id = p_pid and quest_id = 'gala';
  perform game.log(p_pid, 'Mengalahkan Mr. GAP! Menemukan 10.000 gold dan sebuah kotak berbentuk hati.');
  return jsonb_build_object('gold', 10000,
    'message', 'Kapal hitam Mr. GAP tenggelam perlahan. Di kabinnya kru menemukan 10.000 gold dan sebuah kotak kecil berbentuk hati. Di tutupnya terukir: "Chafik is My One Piece". Bawa kotak itu pulang ke Uda Gala di Skitraw.',
    'item', jsonb_build_object('id', 'kotak_hati', 'name', 'Kotak Hati', 'text', 'Chafik is My One Piece'));
end $$;

-- Aksi misi. a = [action, arg]: status | accept | investigate [jawaban] | deliver
create or replace function public.api_galaQuest(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := coalesce(game.arg(a, 0), 'status'); v_arg text := lower(btrim(coalesce(game.arg(a, 1), '')));
  q game.player_quests; v_step int; v_city text := game.current_city(v_pid); v_now bigint := game.now_ms();
  v_story text; v_next text;
begin
  if v_act = 'status' then return jsonb_build_object('gala', game.gala_state(v_pid)); end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  select * into q from game.player_quests where player_id = v_pid and quest_id = 'gala' for update;
  v_step := coalesce(q.step, 0);

  if v_act = 'accept' then
    if v_step > 0 then raise exception 'Kamu sudah menerima misi Uda Gala.'; end if;
    if v_city <> 'skitraw' then raise exception 'Uda Gala hanya ada di Galangan Gaul-Wash, Skitraw.'; end if;
    if game.gala_badges(v_pid) < 20 then raise exception 'Uda Gala belum percaya padamu. Kumpulkan minimal 20 Tanda Jasa dulu.'; end if;
    insert into game.player_quests(player_id, quest_id, step) values (v_pid, 'gala', 1);
    perform game.log(v_pid, 'Menerima misi rahasia dari Uda Gala: mencari harta terpenting dalam hidupnya.');
    return jsonb_build_object('gala', game.gala_state(v_pid));
  end if;

  if v_act = 'investigate' then
    if v_step not between 1 and 3 then raise exception 'Tidak ada petunjuk untuk diselidiki di sini.'; end if;
    if v_city <> (array['joungjava', 'bjorneo', 'ikn'])[v_step] then raise exception 'Petunjuknya bukan di pelabuhan ini, Kapten.'; end if;
    if v_step = 2 then
      if coalesce((q.data ->> 'wrongUntil')::bigint, 0) > v_now then
        raise exception 'Nenek penjaga mercusuar masih menunggumu berpikir. Coba lagi sebentar lagi.';
      end if;
      if v_arg <> 'jangkar' then
        update game.player_quests set data = data || jsonb_build_object('wrongUntil', v_now + 20000), updated_at = now()
        where player_id = v_pid and quest_id = 'gala';
        return jsonb_build_object('wrong', true, 'gala', game.gala_state(v_pid),
          'story', 'Nenek menggeleng pelan. "Bukan itu, Nak. Pikirkan lagi baik-baik."');
      end if;
    end if;
    v_story := (array[
      'Pak Tua Karto terbatuk sambil menyeruput kopi pahitnya. "Gala? Anak Minang yang dulu berlayar dengan hati berbunga-bunga itu? Ya, ya... Malam itu kapalnya dirampok. Perampoknya membawa lari sebuah kotak kecil, dan Gala menangis seperti anak kecil. Aku cuma ingat satu hal: perampok itu berlayar ke tempat kabut tak pernah pergi dan pohon lebih tua dari kerajaan."',
      'Nenek tersenyum lebar. "Cerdas, seperti Gala waktu muda. Perampok itu melempar jangkar di sini tiga malam, mabuk dan berteriak soal kotak berbentuk hati. Lalu ia pergi ke kota yang sudah runtuh untuk menjual rahasianya. Carilah catatannya di arsip ibu kota lama."',
      'Di antara kertas lapuk Arsip Nusantara kamu menemukan buku pelabuhan dari tahun badai besar. Satu baris ditulis dengan tinta merah: "Kapal hitam milik MR. GAP. Muatan: satu kotak hati - TIDAK DIJUAL. Tujuan: TooGood." Mr. GAP... nama yang bahkan tak berani disebut Uda Gala. Berlayarlah menuju TooGood. Dia yang akan menemukanmu.'
    ])[v_step];
    v_next := (array['bjorneo', 'ikn', 'toogood'])[v_step];
    update game.player_quests set step = v_step + 1, data = data - 'wrongUntil', updated_at = now()
    where player_id = v_pid and quest_id = 'gala';
    perform game.log(v_pid, (array['Pak Tua Karto di Joungjava menunjuk ke Bjorneo.', 'Nenek penjaga mercusuar Bjorneo menunjuk ke arsip IKN.', 'Arsip IKN: Mr. GAP berlayar menuju TooGood.'])[v_step]);
    return jsonb_build_object('story', v_story, 'next', v_next, 'gala', game.gala_state(v_pid));
  end if;

  if v_act = 'deliver' then
    if v_step <> 5 then raise exception 'Kamu belum membawa apa-apa untuk Uda Gala.'; end if;
    if v_city <> 'skitraw' then raise exception 'Uda Gala menunggumu di Galangan Gaul-Wash, Skitraw.'; end if;
    update game.player_quests set step = 6, done_at = now(), updated_at = now() where player_id = v_pid and quest_id = 'gala';
    insert into game.player_books(player_id, book_id, date_acquired) values (v_pid, 'bk_gala_logbook', game.game_day())
    on conflict do nothing;
    perform game.log(v_pid, 'Menyerahkan Kotak Hati kepada Uda Gala. Mendapat "Catatan Pelayaran Uda Gala" dan rahasia pulau Paradiso!');
    return jsonb_build_object('done', true, 'gala', game.gala_state(v_pid), 'unlocks', game.player_unlocks(v_pid),
      'book', jsonb_build_object('id', 'bk_gala_logbook', 'name', 'Catatan Pelayaran Uda Gala', 'effect', '+5 Speed kapal'),
      'ship', game.ship_json(v_pid), 'cities', game.cities_json(), 'citiesVersion', game.cities_version());
  end if;

  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_galaquest');

-- ---------------------------------------------------------------------
-- Paradiso: kondisi kapal +1 tiap 5 detik selama merapat
-- ---------------------------------------------------------------------
create table if not exists game.paradiso_heal (
  player_id uuid primary key references game.players(player_id) on delete cascade on update cascade,
  at        timestamptz not null default now()
);
alter table game.paradiso_heal enable row level security;

-- Jam penyembuhan mulai saat tiba di Paradiso dan dihapus saat berangkat
create or replace function game.paradiso_loc_trg() returns trigger
language plpgsql as $$
begin
  if coalesce(new.destination_city_id, '') <> '' then
    delete from game.paradiso_heal where player_id = new.player_id;
  elsif coalesce(old.destination_city_id, '') <> '' and new.city_id = 'paradiso' then
    insert into game.paradiso_heal(player_id, at) values (new.player_id, now())
    on conflict (player_id) do update set at = now();
  end if;
  return new;
end $$;
drop trigger if exists paradiso_loc on game.player_location;
create trigger paradiso_loc after update on game.player_location for each row execute function game.paradiso_loc_trg();

create or replace function game.paradiso_tick(p_pid uuid) returns jsonb
language plpgsql as $$
declare l game.player_location; v_at timestamptz; n int; ship jsonb; eff_max numeric; cond numeric; gain numeric;
begin
  select * into l from game.player_location where player_id = p_pid;
  if not found or l.city_id <> 'paradiso' or coalesce(l.destination_city_id, '') <> '' then
    delete from game.paradiso_heal where player_id = p_pid;
    return null;
  end if;
  select at into v_at from game.paradiso_heal where player_id = p_pid for update;
  if v_at is null then
    insert into game.paradiso_heal(player_id, at) values (p_pid, now()) on conflict (player_id) do nothing;
    return jsonb_build_object('healed', 0, 'full', false, 'nextMs', 5000);
  end if;
  ship := game.ship_json(p_pid);
  eff_max := game.voy_num(ship -> 'EffectiveMaxCondition');
  cond := game.voy_num(ship -> 'Condition');
  n := floor(extract(epoch from (now() - v_at)) / 5)::int;
  if cond >= eff_max then
    update game.paradiso_heal set at = now() where player_id = p_pid;
    return jsonb_build_object('healed', 0, 'full', true, 'condition', cond, 'max', eff_max);
  end if;
  if n <= 0 then
    return jsonb_build_object('healed', 0, 'full', false, 'condition', cond, 'max', eff_max,
      'nextMs', greatest(0, 5000 - floor(extract(epoch from (now() - v_at)) * 1000)::int));
  end if;
  gain := least(n, eff_max - cond);
  update game.ships set condition = least(eff_max, condition + gain) where player_id = p_pid;
  update game.paradiso_heal set at = v_at + make_interval(secs => n * 5) where player_id = p_pid;
  return jsonb_build_object('healed', gain, 'full', cond + gain >= eff_max, 'condition', cond + gain, 'max', eff_max, 'nextMs', 5000);
end $$;

create or replace function public.api_paradisoTick(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(); t jsonb;
begin
  t := game.paradiso_tick(v_me.player_id);
  return jsonb_build_object('tick', t, 'ship', case when t is null then null else game.ship_json(v_me.player_id) end);
end $$;
select game.expose('api_paradisotick');
