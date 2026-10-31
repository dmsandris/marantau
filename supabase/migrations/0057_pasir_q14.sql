-- =====================================================================
-- 0057 — Pasir · Batch 7: Quest 14 "Pasir Terakhir", pengembalian, epilog, set Kedai Saga 3 (Tide v41)
-- Skenario: claude/SKENARIO-Saga3-Dark.md bagian 12, 13, 16.
--
-- QUEST 14 (quest_id 'ps14') — dimulai saat Quest 13 tamat dan pemain di Zaman Keadilan
--   1  Persiapan: 3 Pusaka terpasang · setor 100 Mesiu, 100 Senjata, 100 Besi ke Paman Ocid di Sunda ('setor14', boleh cicil)
--      · tempa ulang Jangkar Waktu (opsional, 'tempa14'). Siap -> Jam Agung menawarkan 'pusaran'.
--   2  Malam Pusaran, dari luar ("Kau di Kejauhan") -> 'lihat14'
--   3  Pertempuran Janji Putih, 3 fase berantai (Tirai Pasir · Gema Masa Lalu · Kaca Ketujuh), HP tersimpan antar serangan.
--      Berlayar dari mana pun di Malam Pusaran = dicegat. 'arus14' (Arus Pusaran) membuka Tirai Pasir untuk satu serangan.
--   4  Geladak yang Tenggelam -> 'lepas14': pv_pulih (harta kembali + bunga 10%), era kini, masa lalu tertutup selamanya,
--      bangun di Gaul-Wash (Skitraw). Set Kedai Pasir Waktu terbuka.
--   5  Epilog: 'nasib14' pergi|dewan (riak nasib_fz) -> 6 selesai (credit Saga Ketiga)
--
-- SET KEDAI (terbuka per pemain, tersembunyi dari katalog sampai terbuka): Zaman Gemilang (Q12), Benang Merah (Q13),
--   Pasir Waktu (Q14, legenda). req = {"pasir": "<flag>"} -> pasir_state.data.<flag>.
--
-- ⚠️ SALINAN versi terakhir + Quest 14: ps_on_sail (0053), ps_zaman_opsi (0054), voy_enc_book (0054), ps_boss_encounter (0056),
--    ps_boss_defeated & ps_combat_end (0055), kd_req_ok, kd_list & api_kedai (0032), kd_set_name & kd_set_info (0035), kd_rupa_view (0034). Aman diulang.
-- =====================================================================

insert into game.config(key, value) values
  ('PasirQ14Setor', '100'),
  ('PasirQ14Hp', '1500'),
  ('PasirQ14Kaca', '8')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Set Kedai Saga 3
-- ---------------------------------------------------------------------
insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, req, exclusive, active, sort) values
  ('lambung_pelitur', 'rupa', 'lambung', 'zaman_gemilang', 'Lambung Pelitur Madu', 'agung', 1800, 'Kayu jati berpelitur madu, mengilap seperti lantai Pustaka Agung.', null, '{"pasir":"set_gemilang"}', false, true, 360),
  ('layar_gading',    'rupa', 'layar',   'zaman_gemilang', 'Layar Sutra Gading',  'agung', 1500, 'Sutra kuning gading dari Dok Garuda; berkilau lembut saat angin sore.', null, '{"pasir":"set_gemilang"}', false, true, 361),
  ('haluan_garuda',   'rupa', 'haluan',  'zaman_gemilang', 'Haluan Garuda Perunggu', 'agung', 1700, 'Garuda perunggu yang masih baru, seperti di alun-alun IKN berjaya.', null, '{"pasir":"set_gemilang"}', false, true, 362),
  ('panji_akademi',   'rupa', 'panji',   'zaman_gemilang', 'Panji Akademi Sudyrman', 'agung', 1400, 'Panji biru-emas Akademi Laut Sudyrman, berlambang lonceng.', null, '{"pasir":"set_gemilang"}', false, true, 363),
  ('jejak_debu_emas', 'rupa', 'jejak',   'zaman_gemilang', 'Jejak Debu Emas',     'agung', 1500, 'Butir emas halus berkilau di buritan, lalu tenggelam pelan.', null, '{"pasir":"set_gemilang"}', false, true, 364),
  ('layar_surat',     'rupa', 'layar',   'benang_merah', 'Layar Bertambal Surat', 'agung', 1600, 'Layar ditambal kertas-kertas surat lama yang tintanya pudar.', null, '{"pasir":"set_benang"}', false, true, 370),
  ('panji_benang',    'rupa', 'panji',   'benang_merah', 'Benang Merah di Tiang', 'agung', 1500, 'Seutas benang merah melilit tiang utama, ujungnya berkibar.', null, '{"pasir":"set_benang"}', false, true, 371),
  ('aura_simpul',     'rupa', 'aura',    'benang_merah', 'Simpul Merah',        'agung', 1600, 'Simpul-simpul merah kecil melayang pelan di sekitar kapal.', null, '{"pasir":"set_benang"}', false, true, 372),
  ('aura_pasir',      'rupa', 'aura',    'pasir_waktu', 'Pasir Perak',          'legenda', 2400, 'Butir pasir perak berputar perlahan di sekeliling kapal, seperti jam yang tak pernah habis.', null, '{"pasir":"set_pasir"}', false, true, 380),
  ('jejak_bayang',    'rupa', 'jejak',   'pasir_waktu', 'Bayangan Sepia',       'legenda', 2400, 'Bayangan sepia kapalmu sendiri mengikuti di belakang, sedetik terlambat.', null, '{"pasir":"set_pasir"}', false, true, 381),
  ('datang_kilat',    'rupa', 'kedatangan', 'pasir_waktu', 'Kilat Waktu',       'legenda', 2600, 'Saat tiba, layar sesaat hitam-putih, lalu warna kembali.', null, '{"pasir":"set_pasir"}', false, true, 382)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh, req = excluded.req,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

-- salinan 0032 + syarat Pasir
create or replace function game.kd_req_ok(p_pid uuid, p_id text) returns boolean
language plpgsql stable as $$
declare r jsonb;
begin
  select i.req into r from game.kd_items i where i.id = p_id;
  if r is null then return true; end if;
  if r ? 'pasir' then
    return coalesce((select (data ->> (r ->> 'pasir'))::boolean from game.pasir_state where player_id = p_pid), false);
  end if;
  if not (r ? 'kisah') then return true; end if;
  return game.kisah_done(p_pid, r ->> 'kisah');
end $$;

-- salinan 0032 + barang Pasir disembunyikan sampai terbuka (atau sudah dimiliki)
create or replace function game.kd_list(p_pid uuid) returns jsonb
language plpgsql as $$
declare l game.kd_loadout; v_k bigint;
begin
  select * into l from game.kd_loadout where player_id = p_pid;
  select keping into v_k from game.players where player_id = p_pid;
  return jsonb_build_object(
    'keping', v_k, 'mul', game.cfg_num('KedaiPriceMul', 1),
    'equipped', coalesce(l.equipped, '{}'::jsonb), 'incaran', l.incaran,
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'rak', i.rak, 'slot', i.slot, 'set', i.set_id, 'name', i.name,
        'rarity', i.rarity, 'price', game.kd_price(i.id), 'info', i.info, 'tokoh', i.tokoh, 'exclusive', i.exclusive,
        'req', i.req, 'locked', not game.kd_req_ok(p_pid, i.id),
        'qty', game.kd_qty(p_pid, i.id)) order by i.sort, i.id)
      from game.kd_items i where i.active
        and (i.req is null or not (i.req ? 'pasir') or game.kd_req_ok(p_pid, i.id) or game.kd_qty(p_pid, i.id) > 0)), '[]'::jsonb),
    'buffs', coalesce((select jsonb_object_agg(kind, uses_left) from game.kd_buffs where player_id = p_pid), '{}'::jsonb),
    'tambatExtra', coalesce((select tambat_extra from game.hr_streak where player_id = p_pid), 0));
end $$;

create or replace function game.kd_set_name(p_set text) returns text
language sql immutable as $$
  select case p_set when 'api_gunung' then 'Set Api Gunung' when 'naga_samudra' then 'Set Naga Samudra'
    when 'kapal_hantu' then 'Set Kapal Hantu' when 'badai_petir' then 'Set Badai Petir' when 'mutiara_paradiso' then 'Set Mutiara Paradiso'
    when 'zaman_gemilang' then 'Set Zaman Gemilang' when 'benang_merah' then 'Set Benang Merah' when 'pasir_waktu' then 'Set Pasir Waktu' else p_set end
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
    else '' end
$$;

-- salinan 0034 + set Pasir disembunyikan sampai terbuka
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
              from game.kd_items i where i.set_id is not null and i.active
               and (i.req is null or not (i.req ? 'pasir') or game.kd_req_ok(p_pid, i.id) or game.kd_qty(p_pid, i.id) > 0) group by i.set_id) z), '[]'::jsonb));
end $$;

-- salinan 0032 + barang Pasir yang belum terbuka dianggap tidak ada
create or replace function public.api_kedai(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_act text := coalesce(game.arg(a, 0), 'daftar');
  v_id text := game.arg(a, 1); it game.kd_items; v_price int; v_city text; q jsonb; v_out jsonb := '{}'::jsonb; r game.hr_sheets;
  v_taksir jsonb; l game.kd_loadout;
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KedaiOpen') then raise exception 'Kedai Rantau belum dibuka.'; end if;
  insert into game.kd_loadout(player_id) values (v_pid) on conflict (player_id) do nothing;

  if v_act = 'daftar' then return jsonb_build_object('kedai', game.kd_list(v_pid)); end if;

  if v_act in ('beli', 'pasang', 'pakai') then
    select * into it from game.kd_items where id = v_id and active;
    if not found or (it.req ? 'pasir' and not game.kd_req_ok(v_pid, v_id) and game.kd_qty(v_pid, v_id) = 0) then raise exception 'Barang tidak ada di Kedai.'; end if;
  end if;

  if v_act = 'beli' then
    if it.exclusive then raise exception '% tidak dijual. Barang ini hanya bisa didapat sebagai hadiah.', it.name; end if;
    if it.rak = 'kisah' then raise exception 'Bab Kisah dibeli di rak Kisah.'; end if;
    if not game.kd_req_ok(v_pid, v_id) then raise exception '% hanya untuk kapten yang sudah menamatkan Kisah Lapau "%".', it.name, coalesce(it.req ->> 'kisahName', it.req ->> 'kisah'); end if;
    if it.rak = 'rupa' and game.kd_qty(v_pid, v_id) > 0 then raise exception 'Kamu sudah memiliki %.', it.name; end if;
    v_price := game.kd_price(v_id);
    perform game.keping_add(v_pid, -v_price, 'kedai', 'beli ' || v_id);
    perform game.kd_grant(v_pid, v_id, 1, 'kedai');
    perform game.log(v_pid, 'Kedai Rantau: membeli ' || it.name || ' seharga ' || to_char(v_price, 'FM999G999G999') || ' keping.');
    update game.kd_loadout set incaran = null where player_id = v_pid and incaran = v_id;
    v_out := jsonb_build_object('bought', v_id, 'name', it.name);

  elsif v_act = 'pasang' then
    if it.rak <> 'rupa' or it.slot is null then raise exception 'Barang ini tidak dipasang di kapal.'; end if;
    if game.kd_qty(v_pid, v_id) <= 0 then raise exception 'Kamu belum memiliki %.', it.name; end if;
    update game.kd_loadout set equipped = equipped || jsonb_build_object(it.slot, v_id) where player_id = v_pid;
    begin perform game.mp_touch(v_pid); exception when others then null; end;   -- kirim rupa baru ke kapten lain
    v_out := jsonb_build_object('shipVisual', game.ship_visual(v_pid));

  elsif v_act = 'lepas' then
    update game.kd_loadout set equipped = equipped - coalesce(v_id, '') where player_id = v_pid;
    begin perform game.mp_touch(v_pid); exception when others then null; end;   -- kirim rupa baru ke kapten lain
    v_out := jsonb_build_object('shipVisual', game.ship_visual(v_pid));

  elsif v_act = 'incar' then
    if coalesce(v_id, '') = '' then update game.kd_loadout set incaran = null where player_id = v_pid;
    else
      select * into it from game.kd_items where id = v_id and active and not exclusive;
      if not found then raise exception 'Barang tidak ada di Kedai.'; end if;
      update game.kd_loadout set incaran = v_id where player_id = v_pid;
    end if;

  elsif v_act = 'pakai' then
    if it.rak <> 'jasa' then raise exception 'Barang ini bukan jasa.'; end if;
    if game.kd_qty(v_pid, v_id) <= 0 then raise exception 'Kamu tidak punya %.', it.name; end if;
    if v_id = 'jasa_kupon' then
      if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan untuk reparasi.'; end if;
      v_city := game.current_city(v_pid);
      q := game.voy_repair_quote(v_pid, v_city);
      if q ->> 'blocked' is not null then raise exception '%', q ->> 'blocked'; end if;
      if (q ->> 'missing')::numeric <= 0 then raise exception 'Kapal sudah dalam kondisi penuh.'; end if;
      update game.ships set condition = (q ->> 'maxCondition')::numeric where player_id = v_pid;
      perform game.log(v_pid, 'Kupon Reparasi Uda Gala dipakai di ' || game.city_name(v_city) || '. Kapal kembali prima.');
      perform game.hr_hook(v_pid, 'repair', 0, jsonb_build_object('city', v_city, 'kupon', true));
      v_out := jsonb_build_object('ship', game.ship_json(v_pid), 'msg', 'Kapal kembali prima. Uda Gala: "Gratis untuak sanak!"');
    elsif v_id = 'jasa_jala' then
      if game.fish_left(v_pid) >= game.fish_qmax_p(v_pid) then raise exception 'Jatah mancingmu sudah penuh.'; end if;
      update game.mp_fish set q_left = null, q_t = null where player_id = v_pid;
      v_out := jsonb_build_object('msg', 'Jatah mancing kembali penuh.');
    elsif v_id = 'jasa_tukar' then
      if not game.fitur_on(v_pid, 'HarianOpen') then raise exception 'Pesanan Harian belum dibuka.'; end if;
      r := game.hr_sheet(v_pid);
      if r.reroll_bonus >= 2 then raise exception 'Tukar Pesanan tambahan hari ini sudah maksimal (2).'; end if;
      update game.hr_sheets set reroll_bonus = reroll_bonus + 1 where player_id = v_pid and day = r.day;
      v_out := jsonb_build_object('msg', 'Satu kali tukar tugas tambahan untuk hari ini.');
    elsif v_id = 'jasa_tambat' then
      insert into game.hr_streak(player_id) values (v_pid) on conflict (player_id) do nothing;
      if (select tambat_extra from game.hr_streak where player_id = v_pid) >= 3 then raise exception 'Tali Tambat Cadangan sudah 3 tersimpan.'; end if;
      update game.hr_streak set tambat_extra = tambat_extra + 1 where player_id = v_pid;
      v_out := jsonb_build_object('msg', 'Teh Euis menyimpan satu Tali Tambat untuk streakmu.');
    elsif v_id = 'jasa_taksir' then
      select coalesce(jsonb_agg(jsonb_build_object('comm', x.comm, 'name', x.name, 'qty', x.qty, 'avg', x.avg, 'best', x.best) order by x.sort), '[]'::jsonb)
        into v_taksir
        from (select i.item_id comm, c.name, i.qty, c.sort, case when i.qty > 0 and i.cost is not null then round(i.cost / i.qty) end avg,
                (select coalesce(jsonb_agg(b order by (b ->> 'price')::int desc), '[]'::jsonb) from (
                   select jsonb_build_object('city', m.city_id, 'cityName', ct.name, 'price', m.current_price) b
                     from game.market m join game.cities ct on ct.city_id = m.city_id
                    where m.commodity_id = i.item_id and m.current_price > 0 and game.city_open(v_pid, m.city_id)
                      and not coalesce(game.spot_city(m.city_id), false)
                    order by m.current_price desc limit 3) z) best
                from game.inventory i join game.commodities c on c.id = i.item_id
               where i.player_id = v_pid and i.qty > 0) x;
      if jsonb_array_length(v_taksir) = 0 then raise exception 'Palkamu kosong. Pak Tua Karto tidak bisa menaksir angin.'; end if;
      v_out := jsonb_build_object('taksir', v_taksir);
    elsif v_id in ('jasa_pengawal', 'jasa_arus') then
      if exists (select 1 from game.kd_buffs where player_id = v_pid and uses_left > 0) then
        raise exception 'Masih ada jasa yang aktif. Satu jasa dalam satu waktu.';
      end if;
      insert into game.kd_buffs(player_id, kind, uses_left) values (v_pid, case when v_id = 'jasa_arus' then 'arus' else 'pengawal' end,
        case when v_id = 'jasa_arus' then 3 else 2 end)
      on conflict (player_id, kind) do update set uses_left = excluded.uses_left, started = now();
      v_out := jsonb_build_object('msg', case when v_id = 'jasa_arus' then 'Nenek Ulin membaca arus untuk tiga pelayaranmu berikutnya.'
        else 'Dua perahu Daeng Sore akan mengawal dua pencegatan berikutnya.' end);
    else
      raise exception 'Jasa ini belum bisa dipakai.';
    end if;
    update game.kd_owned set qty = qty - 1 where player_id = v_pid and item_id = v_id;
    delete from game.kd_owned where player_id = v_pid and item_id = v_id and qty <= 0;
    perform game.log(v_pid, 'Kedai Rantau: memakai ' || it.name || '.');
    v_out := v_out || jsonb_build_object('used', v_id);
  else
    raise exception 'Aksi tidak dikenal: %', v_act;
  end if;

  return v_out || jsonb_build_object('kedai', game.kd_list(v_pid), 'harian', game.harian_state(v_pid));
end $$;

-- ---------------------------------------------------------------------
-- Pertempuran: Tirai Pasir & Kaca Ketujuh (salinan 0054 + Pasir)
-- ---------------------------------------------------------------------
create or replace function game.voy_enc_book(p_pid uuid, p_enc jsonb) returns jsonb
language plpgsql stable as $$
declare e jsonb := p_enc;
begin
  if e is null or jsonb_typeof(e) <> 'object' then return e; end if;
  if not coalesce((e ->> 'bljAmmo')::boolean, false) and game.ship_book_effect(p_pid, 'fy_tungku') then
    e := e || jsonb_build_object('bljAmmo', true,
      'maxAmmo', game.voy_num(e -> 'maxAmmo') + 1, 'ammoRemaining', game.voy_num(e -> 'ammoRemaining') + 1);
  end if;
  if not coalesce((e ->> 'pxKemudi')::boolean, false) and game.ship_book_effect(p_pid, 'px_kemudi_ikn') then
    e := e || jsonb_build_object('pxKemudi', true, 'enemyDmgMul', round(coalesce(nullif(game.voy_num(e -> 'enemyDmgMul'), 0), 1) * 0.9, 4));
  end if;
  if not coalesce((e ->> 'pxHaluan')::boolean, false) and coalesce((e ->> 'shield')::boolean, false) and game.ship_book_effect(p_pid, 'px_haluan_kadet') then
    e := e || jsonb_build_object('pxHaluan', true, 'shieldMul', round(coalesce(nullif(game.voy_num(e -> 'shieldMul'), 0), 0.25) * 1.15, 4));
  end if;
  -- Haluan Kadet Sudyrman juga mengikis perisai pasir Janji Putih
  if not coalesce((e ->> 'pxHaluan')::boolean, false) and coalesce((e ->> 'perisai')::boolean, false) and game.ship_book_effect(p_pid, 'px_haluan_kadet') then
    e := e || jsonb_build_object('pxHaluan', true, 'dmgTaken', round(coalesce(nullif(game.voy_num(e -> 'dmgTaken'), 0), 1) * 1.15, 4));
  end if;
  if not (e ? 'pullImmune') and game.ship_book_effect(p_pid, 'px_lambung_garam') then
    e := e || jsonb_build_object('pullImmune', 1);
  end if;
  -- Kaca Ketujuh: bilah waktu penuh -> pecah, Janji Putih tak tertahankan
  if game.voy_num(e -> 'kacaLimit') > 0 and not coalesce((e ->> 'kacaPecah')::boolean, false)
     and coalesce(nullif(game.voy_num(e -> 'round'), 0), 1) > game.voy_num(e -> 'kacaLimit') then
    e := e || jsonb_build_object('kacaPecah', true, 'enemyDmgMul', 40, 'bossTitle', 'Kaca ketujuh pecah! Pasir perak menelan lautan');
  end if;
  return e;
end $$;

-- ---------------------------------------------------------------------
-- Quest 14: kesiapan, fase bos
-- ---------------------------------------------------------------------
create or replace function game.ps14_pusaka_n(p_pid uuid) returns int
language sql stable as $$ select count(*)::int from game.pv_pusaka where player_id = p_pid and slot is not null $$;

create or replace function game.ps14_setor(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('mesiu', coalesce((d -> 'setor' ->> 'mesiu')::int, 0), 'arms', coalesce((d -> 'setor' ->> 'arms')::int, 0),
    'besi', coalesce((d -> 'setor' ->> 'besi')::int, 0))
  from (select game.ps_data(p_pid, 'ps14') d) z
$$;

create or replace function game.ps14_siap(p_pid uuid) returns boolean
language plpgsql stable as $$
declare s jsonb := game.ps14_setor(p_pid); n int := game.cfg_num('PasirQ14Setor', 100)::int;
begin
  return game.ps_step(p_pid, 'ps14') = 1 and game.ps14_pusaka_n(p_pid) >= 3 and game.ps_jangkar(p_pid) is not null
     and (s ->> 'mesiu')::int >= n and (s ->> 'arms')::int >= n and (s ->> 'besi')::int >= n;
end $$;

-- salinan 0054 + Malam Pusaran
create or replace function game.ps_zaman_opsi(p_pid uuid) returns text[]
language sql stable as $$
  select case
    when game.ps_step(p_pid, 'ps11') = 5 then array['badai']
    when game.ps_step(p_pid, 'ps11') >= 10 and not coalesce((game.ps_sdata(p_pid) ->> 'lampau_tutup')::boolean, false) then
      array['lampau'] || case when game.ps14_siap(p_pid) then array['pusaran'] else array[]::text[] end
    else array[]::text[] end
$$;

-- salinan 0053 + Malam Pusaran: satu-satunya jalan adalah menghadang Janji Putih
create or replace function game.ps_on_sail(p_pid uuid, p_origin text, p_dest text) returns void
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps10'); v_era text := game.pasir_era(p_pid);
begin
  if v_era = 'badai' then raise exception 'Malam begini tak ada yang berlayar, Kapten. Kecuali orang gila.'; end if;
  if v_era = 'pusaran' then
    if game.ps_step(p_pid, 'ps14') <> 3 or p_dest not in ('pusaran', 'empeer_depeer') then
      raise exception 'Tidak ada jalan keluar dari pusaran ini selain ke depan.';
    end if;
    return;
  end if;
  if s = 5 and p_origin = 'empeer_depeer' then
    raise exception 'Lonceng Jam Agung berdentang sumbang di puncak bukit. Burung-burung terbang ke arah yang salah.';
  end if;
  if s = 6 then raise exception 'Jam Agung masih berdentang. Kau belum boleh pergi.'; end if;
  if s = 2 and p_dest = 'empeer_depeer' then perform game.ps_set(p_pid, 'ps10', 3, '{}'::jsonb); end if;
end $$;

create or replace function game.ps14_enc(p_pid uuid, p_fase int, p_hp int) returns jsonb
language plpgsql as $$
declare d jsonb := game.ps_data(p_pid, 'ps14'); r jsonb := (select riak from game.pasir_state where player_id = p_pid);
  H int := game.cfg_num('PasirQ14Hp', 1500)::int; e jsonb; v_floor int; v_kaca int; v_mutu int;
begin
  e := game.ps_janji_enc(p_pid, 5);
  v_floor := case p_fase when 1 then round(H * 0.66) when 2 then round(H * 0.33) else round(H * 0.06) end;
  e := e || jsonb_build_object('q14', p_fase, 'enemyMaxHp', H, 'enemyHp', greatest(v_floor + 1, coalesce(p_hp, H)), 'hpFloor', v_floor,
    'displayLevel', 9, 'enemyLevel', 7 + p_fase, 'enemyDmgMul', 1.6 + p_fase * 0.2, 'dmgTaken', 1, 'perisai', false);
  if p_fase = 1 then
    if coalesce((d ->> 'searah')::boolean, false) then
      e := e || jsonb_build_object('bossTitle', 'Fase 1 · Tirai Pasir. Kau berlayar searah putaran pusaran: perisainya terbuka');
    else
      e := e || jsonb_build_object('bossTitle', 'Fase 1 · Tirai Pasir. Kau melawan arus: tembakanmu tertelan pasir',
        'dmgTaken', 0.25, 'perisai', true);
    end if;
  elsif p_fase = 2 then
    e := e || jsonb_build_object('bossTitle', 'Fase 2 · Gema Masa Lalu. Bayangan sepia kapal-kapal yang pernah kau tenggelamkan');
    if (r ->> 'gala_putih') = 'belot' then
      e := e || jsonb_build_object('allyDmg', 45, 'allyNote', 'Sekoci putih Uda Gala ("Kemudi Laksamana ambo yang pegang!")');
    end if;
    if (r ->> 'gala_putih') = 'peta' then
      e := e || jsonb_build_object('smoke', false);
    else
      e := e || jsonb_build_object('smoke', true, 'immuneFirst', true,
        'immuneMsg', 'tembakan pertamamu menembus bayangan sepia Mr. GAP. Itu hanya gema.');
    end if;
  else
    v_mutu := game.lt_grade_rank(game.ps_jangkar(p_pid));
    v_kaca := game.cfg_num('PasirQ14Kaca', 8)::int + greatest(0, v_mutu - 1) * 2;
    e := e || jsonb_build_object('kacaLimit', v_kaca,
      'bossTitle', 'Fase 3 · Kaca Ketujuh. Franziska memegang Jam Pasir di haluan: ' || v_kaca || ' ronde sebelum kacanya pecah');
  end if;
  return e;
end $$;

-- salinan 0056 + Quest 14
create or replace function game.ps_boss_encounter(p_pid uuid, p_dest text) returns jsonb
language plpgsql as $$
declare k jsonb := game.ps_kdata(p_pid); e jsonb; v_n int; v_tembus boolean; d jsonb;
begin
  if game.pasir_era(p_pid) = 'pusaran' and game.ps_step(p_pid, 'ps14') = 3 then
    d := game.ps_data(p_pid, 'ps14');
    e := game.ps14_enc(p_pid, coalesce((d ->> 'fase')::int, 1), (d ->> 'hp')::int);
    perform game.ps_set(p_pid, 'ps14', 3, '{"searah": false}'::jsonb);
    return e;
  end if;
  if (k -> 'susul' ->> 'state') = 'kabur' and game.ps_kejar_aktif(p_pid) then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', (k -> 'susul') || '{"state": "laut"}'::jsonb));
    if game.ps_kejar_q13(p_pid) then
      v_n := game.ps13_n(p_pid);
      e := game.ps_janji_enc(p_pid, 2 + v_n);
      v_tembus := game.lt_grade_rank(game.ps_jangkar(p_pid)) >= 2 or coalesce(game.has_effect(p_pid, 'fy_rantai'), false);
      return e || jsonb_build_object('q13', v_n + 1, 'perisai', not v_tembus,
        'bossTitle', case when v_tembus then 'Perisai pasir berputar di lambungnya, tapi Jangkar Waktumu menembusnya'
                          else 'Perisai pasir berputar di lambungnya. Tembakanmu tertelan pasir' end,
        'dmgTaken', case when v_tembus then 1 else 0.35 end);
    end if;
    return game.ps_janji_enc(p_pid, case when game.ps_step(p_pid, 'ps12') = 4 then 0 else 1 end);
  end if;
  return null;
end $$;

-- salinan 0055 + Quest 14 (fase berantai)
create or replace function game.ps_boss_defeated(p_pid uuid) returns jsonb
language plpgsql as $$
declare enc jsonb; s int; n int; f int; nxt jsonb;
begin
  select pending_encounter into enc from game.player_location where player_id = p_pid;
  if not coalesce((enc ->> 'ps')::boolean, false) or (enc ->> 'boss') <> 'ps_janji' then return null; end if;
  if enc ? 'q14' then
    f := (enc ->> 'q14')::int;
    if f < 3 then
      perform game.ps_set(p_pid, 'ps14', 3, jsonb_build_object('fase', f + 1, 'hp', (enc ->> 'enemyHp')::int));
      nxt := game.ps14_enc(p_pid, f + 1, (enc ->> 'enemyHp')::int);
      nxt := nxt || jsonb_build_object('maxAmmo', enc -> 'maxAmmo', 'ammoRemaining', enc -> 'ammoRemaining');
      return jsonb_build_object('gold', 0, 'chain', nxt,
        'message', case f when 1 then 'Tirai pasir runtuh! Franziska mengangkat payung rendanya: dari kabut muncul bayangan sepia kapal-kapal lama.'
                          else 'Bayangan-bayangan itu buyar. Franziska berdiri di haluan, mengangkat Jam Pasir. Kaca ketujuh mulai retak.' end);
    end if;
    perform game.ps_set(p_pid, 'ps14', 4, jsonb_build_object('fase', 3, 'hp', null, 'menang', game.now_ms()));
    perform game.log(p_pid, 'Janji Putih tidak tenggelam. Ia hanyut ke sisi Absolute Justice yang sedang tenggelam.');
    return jsonb_build_object('gold', 0, 'message', 'Janji Putih berhenti melawan. Ia tidak tenggelam: ia hanyut pelan ke sisi Absolute Justice yang sedang tenggelam. Merapatlah, Kapten.');
  end if;
  n := coalesce((game.ps_kdata(p_pid) ->> 'n')::int, 0) + 1;
  perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null, 'hari', game.ps_hari(), 'n', n, 'jejak', null));
  s := game.ps_step(p_pid, 'ps12');
  if s = 4 then
    perform game.ps_set(p_pid, 'ps12', 5, jsonb_build_object('surat1', true));
    perform game.log(p_pid, 'Janji Putih berbelok tajam dan menghilang di balik kabut. Sepucuk surat lama melayang jatuh ke geladakmu.');
    return jsonb_build_object('gold', 0, 'message', 'Janji Putih mundur. Franziska berseru dari haluannya: "Kau keras kepala. Slaus juga begitu, dulu." Sepucuk surat lama jatuh ke geladakmu.');
  elsif s = 5 then
    perform game.ps_set(p_pid, 'ps12', 6, jsonb_build_object('akademi', true));
    perform game.log(p_pid, 'Franziska berteriak sebelum menghilang: "Kalau kau mau tahu siapa dia, datanglah ke Akademi!"');
    return jsonb_build_object('gold', 0, 'message', 'Janji Putih mundur lagi. Sebelum hilang di balik kabut, Franziska berseru: "Kalau kau mau tahu siapa dia, Kapten, datanglah ke Akademi!"');
  end if;
  return coalesce(game.ps_boss_won_q13(p_pid), jsonb_build_object('gold', 0, 'message', 'Janji Putih mundur ke balik kabut.'));
end $$;

-- salinan 0055 + Quest 14 (HP tersimpan)
create or replace function game.ps_combat_end(p_pid uuid, p_enc jsonb, p_result text) returns void
language plpgsql as $$
begin
  if not coalesce((p_enc ->> 'ps')::boolean, false) or (p_enc ->> 'boss') <> 'ps_janji' or p_result = 'won' then return; end if;
  if p_enc ? 'q14' then
    perform game.ps_set(p_pid, 'ps14', 3, jsonb_build_object('fase', (p_enc ->> 'q14')::int, 'hp', (p_enc ->> 'enemyHp')::int,
      'kalah', coalesce((game.ps_data(p_pid, 'ps14') ->> 'kalah')::int, 0) + 1));
    return;
  end if;
  -- tutorial: ia menunggu dicegat lagi; selain itu ia lolos (coba hari ini lagi bila belum tersusul)
  if game.ps_step(p_pid, 'ps12') = 4 then
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', jsonb_build_object('state', 'kabur', 'city', 'sudyrman_pelabuhan')));
  else
    perform game.ps_kdata_set(p_pid, jsonb_build_object('susul', null));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Aksi Quest 14 (sambungan ps_act_q13; 0056)
-- ---------------------------------------------------------------------
create or replace function game.ps_act_q14(p_pid uuid, p_act text, a jsonb) returns jsonb
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps14'); d jsonb := game.ps_data(p_pid, 'ps14'); v_arg text := game.arg(a, 1); v_arg2 text := game.arg(a, 2);
  v_city text := game.current_city(p_pid); v_docked boolean := not game.in_transit(p_pid); v_era text := game.pasir_era(p_pid);
  v_n int := game.cfg_num('PasirQ14Setor', 100)::int; v_set jsonb; c text; v_have int; v_need int; v_add jsonb := '{}'::jsonb;
  v_score int; v_dur int; v_grade text; v_res jsonb;
begin
  if p_act = 'setor14' then
    if s <> 1 or v_era <> 'keadilan' then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'sunda_empire' then raise exception 'Paman Ocid menerima perbekalan di gudang arsip Sunda Empire.'; end if;
    v_set := game.ps14_setor(p_pid);
    foreach c in array array['mesiu', 'arms', 'besi'] loop
      v_need := greatest(0, v_n - (v_set ->> c)::int);
      v_have := least(v_need, game.item_qty(p_pid, c));
      if v_have > 0 then
        perform game.adjust_inventory(p_pid, c, -v_have);
        v_set := v_set || jsonb_build_object(c, (v_set ->> c)::int + v_have);
        v_add := v_add || jsonb_build_object(c, v_have);
      end if;
    end loop;
    if v_add = '{}'::jsonb then raise exception 'Palkamu tidak membawa Mesiu, Senjata, atau Besi yang masih dibutuhkan.'; end if;
    perform game.ps_set(p_pid, 'ps14', 1, jsonb_build_object('setor', v_set));
    return jsonb_build_object('ok', true, 'setor', v_set, 'add', v_add);
  elsif p_act = 'tempa14' then
    if s not in (1, 2, 3) or v_era not in ('keadilan', 'pusaran') then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked or v_city <> 'empeer_depeer' then raise exception 'Dok kecil itu ada di Pulau em pe''er de pe''er.'; end if;
    if game.lt_grade_rank(game.ps_jangkar(p_pid)) >= 3 then raise exception 'Jangkar Waktumu sudah sempurna.'; end if;
    v_score := least(100, greatest(0, coalesce(nullif(v_arg, '')::int, 0)));
    v_dur := coalesce(nullif(v_arg2, '')::int, 0);
    if v_dur < 8000 then raise exception 'Besi belum sempat dipanaskan, Kapten.'; end if;
    v_grade := game.lt_grade(v_score);
    if game.lt_grade_rank(v_grade) > game.lt_grade_rank(game.ps_jangkar(p_pid)) then
      update game.pv_pusaka set mutu = v_grade where player_id = p_pid and pusaka_id = 'jangkar';
      return jsonb_build_object('ok', true, 'grade', v_grade, 'naik', true);
    end if;
    return jsonb_build_object('ok', true, 'grade', v_grade, 'naik', false);
  elsif p_act = 'lihat14' then
    if s <> 2 or v_era <> 'pusaran' then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_buka_add(p_pid, 'pusaran');
    perform game.ps_set(p_pid, 'ps14', 3, '{"fase": 1}'::jsonb);
    return jsonb_build_object('ok', true);
  elsif p_act = 'arus14' then
    if s <> 3 or v_era <> 'pusaran' or coalesce(v_arg, '') <> 'ok' then raise exception 'Aksi tidak dikenal.'; end if;
    perform game.ps_set(p_pid, 'ps14', 3, '{"searah": true}'::jsonb);
    return jsonb_build_object('ok', true);
  elsif p_act = 'lepas14' then
    if s <> 4 then raise exception 'Aksi tidak dikenal.'; end if;
    if not v_docked then raise exception 'Merapat dulu ke sisi Absolute Justice, Kapten.'; end if;
    v_res := '{}'::jsonb;
    if exists (select 1 from game.pv_snap where player_id = p_pid and restored_at is null) then
      v_res := game.pv_pulih(p_pid);
    end if;
    update game.pasir_state set era = 'kini', updated_at = now(),
      data = (data - 'buka') || jsonb_build_object('lampau_tutup', true, 'set_pasir', true, 'pulih', v_res)
     where player_id = p_pid;
    perform game.ps_lokasi(p_pid, 'skitraw');
    perform game.ps_set(p_pid, 'ps14', 5, jsonb_build_object('bunga', coalesce((v_res ->> 'bonus')::bigint, 0)));
    perform game.log(p_pid, 'Kau terbangun di Gaul-Wash, Skitraw. Uda Gala sedang mencuci lambung kapalmu sambil bernyanyi.');
    return jsonb_build_object('ok', true, 'bunga', coalesce((v_res ->> 'bonus')::bigint, 0));
  elsif p_act = 'nasib14' then
    if s <> 5 or coalesce(v_arg, '') not in ('pergi', 'dewan') then raise exception 'Aksi tidak dikenal.'; end if;
    update game.pasir_state set riak = riak || jsonb_build_object('nasib_fz', v_arg), updated_at = now() where player_id = p_pid;
    perform game.ps_set(p_pid, 'ps14', 6, jsonb_build_object('nasib', v_arg), true);
    return jsonb_build_object('ok', true);
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------
-- Status Quest 14
-- ---------------------------------------------------------------------
create or replace function game.ps_state_q14(p_pid uuid) returns jsonb
language plpgsql as $$
declare s int := game.ps_step(p_pid, 'ps14');
begin
  if s = 0 and game.ps_step(p_pid, 'ps13') >= 7 and game.pasir_era(p_pid) = 'keadilan' then
    perform game.ps_set(p_pid, 'ps14', 1, '{}'::jsonb); s := 1;
  end if;
  if s = 1 and game.pasir_era(p_pid) = 'pusaran' then
    perform game.ps_set(p_pid, 'ps14', 2, '{}'::jsonb); s := 2;
  end if;
  if s = 0 then return '{}'::jsonb; end if;
  return jsonb_build_object('q14', game.ps_q_json(p_pid, 'ps14') || jsonb_build_object(
    'pusaka', game.ps14_pusaka_n(p_pid), 'setor', game.ps14_setor(p_pid), 'perlu', game.cfg_num('PasirQ14Setor', 100)::int,
    'jangkar', game.ps_jangkar(p_pid), 'siap', game.ps14_siap(p_pid), 'hpMax', game.cfg_num('PasirQ14Hp', 1500)::int));
end $$;

create or replace function game.ps_admin_q14(p_pid uuid, p_act text, p_arg text, p_arg2 text) returns boolean
language plpgsql as $$
begin
  if p_act = 'fase14' then
    -- lompat ke fase bos n (1..3), HP penuh fase itu
    perform game.ps_set(p_pid, 'ps14', 3, jsonb_build_object('fase', greatest(1, least(3, coalesce(nullif(p_arg, '')::int, 1))), 'hp', null));
    return true;
  end if;
  return false;
end $$;
