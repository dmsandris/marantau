-- =====================================================================
-- 0089 · Tide v70 — Layar Emas Juara jadi barang pinjaman + Ruang Ganti Kedai
--
--   * Juara 1 Pacu Dagang tidak lagi "ditempeli" emas oleh kd_visual (dulu tidak bisa
--     dilepas dan menimpa layar lain). Sekarang ia MENERIMA barang `layar_emas_pekan`
--     di kd_owned dengan masa pinjam sampai Upacara berikutnya (Senin 08:00 WIB).
--   * Saat diterima, barang otomatis dipasang SEKALI (layar lama dicatat di prev_layar).
--     Sesudah itu sama seperti rupa lain: Lepas, Pasang lagi, simpan di Lemari.
--   * Lewat masa pinjam: kd_qty = 0 (dianggap tidak dimiliki), kd_visual tidak lagi
--     menampilkannya dan memakai layar lama (bila masih dimiliki). Upacara berikutnya
--     membersihkan barisnya dan mengembalikan layar lama ke loadout.
--   * Juara lagi: masa pinjam diperpanjang, bukan barang ganda.
--   * Layar Emas PERMANEN (3x juara 1, `layar_emas`) tidak berubah.
--   * api_kedaiSusun: Ruang Ganti Kedai menyimpan banyak slot sekaligus (satu panggilan).
-- Aman diulang.
-- =====================================================================

insert into game.kd_items(id, rak, slot, set_id, name, rarity, price, info, tokoh, req, exclusive, active, sort) values
  ('layar_emas_pekan', 'rupa', 'layar', null, 'Layar Emas Juara', 'legenda', 0,
   'Pinjaman kehormatan untuk juara 1 Pacu Dagang, berlaku sampai Upacara berikutnya. Boleh dilepas dan dipasang lagi selama masa pinjam.',
   'coco epan', null, true, true, 191)
on conflict (id) do update set rak = excluded.rak, slot = excluded.slot, set_id = excluded.set_id, name = excluded.name,
  rarity = excluded.rarity, price = excluded.price, info = excluded.info, tokoh = excluded.tokoh, req = excluded.req,
  exclusive = excluded.exclusive, active = excluded.active, sort = excluded.sort;

alter table game.kd_owned add column if not exists until timestamptz;          -- null = milik tetap
alter table game.kd_loadout add column if not exists prev_layar text;           -- layar sebelum Layar Emas Juara dipasang otomatis

-- barang pinjaman yang lewat masa = tidak dimiliki
create or replace function game.kd_qty(p_pid uuid, p_id text) returns int
language sql stable as $$
  select coalesce((select qty from game.kd_owned where player_id = p_pid and item_id = p_id
                    and (until is null or until > game.hr_now())), 0)
$$;

-- Senin 08:00 WIB sesudah Pacu p_sat, sebagai timestamptz
create or replace function game.pd_announce_at(p_sat date) returns timestamptz
language sql stable as $$ select (game.pd_t(p_sat, 'announce') - interval '7 hours') at time zone 'UTC' $$;

-- beri / perpanjang Layar Emas Juara dan pasang otomatis
create or replace function game.pd_emas_grant(p_pid uuid, p_until timestamptz) returns void
language plpgsql as $$
declare l game.kd_loadout;
begin
  insert into game.kd_owned as o (player_id, item_id, qty, source, until) values (p_pid, 'layar_emas_pekan', 1, 'pacu', p_until)
  on conflict (player_id, item_id) do update set qty = 1, until = greatest(coalesce(o.until, excluded.until), excluded.until), acquired = now();
  insert into game.kd_loadout(player_id) values (p_pid) on conflict (player_id) do nothing;
  select * into l from game.kd_loadout where player_id = p_pid;
  if coalesce(l.equipped ->> 'layar', '') <> 'layar_emas_pekan' then
    update game.kd_loadout set prev_layar = nullif(l.equipped ->> 'layar', ''),
      equipped = equipped || '{"layar": "layar_emas_pekan"}'::jsonb where player_id = p_pid;
  end if;
  begin perform game.mp_touch(p_pid); exception when others then null; end;
end $$;

-- bersihkan pinjaman yang lewat masa: kembalikan layar lama bila masih dimiliki
create or replace function game.pd_emas_cleanup() returns void
language plpgsql as $$
declare r record;
begin
  for r in select o.player_id, l.equipped, l.prev_layar from game.kd_owned o left join game.kd_loadout l on l.player_id = o.player_id
            where o.item_id = 'layar_emas_pekan' and o.until is not null and o.until <= game.hr_now() loop
    if coalesce(r.equipped ->> 'layar', '') = 'layar_emas_pekan' then
      update game.kd_loadout set equipped = case when r.prev_layar is not null and game.kd_qty(r.player_id, r.prev_layar) > 0
                                                 then equipped || jsonb_build_object('layar', r.prev_layar) else equipped - 'layar' end,
                                 prev_layar = null where player_id = r.player_id;
    else
      update game.kd_loadout set prev_layar = null where player_id = r.player_id;
    end if;
    delete from game.kd_owned where player_id = r.player_id and item_id = 'layar_emas_pekan';
    begin perform game.mp_touch(r.player_id); exception when others then null; end;
  end loop;
  -- Lemari: laci yang menyimpan Layar Emas Juara tidak perlu diubah (barang tak dimiliki dilewati saat Pakai)
end $$;

-- ---------------------------------------------------------------------
-- Upacara: bersihkan pinjaman lama -> umumkan (fungsi lama) -> pinjamkan ke juara 1 baru
-- ---------------------------------------------------------------------
do $$ begin
  drop function if exists game.pd_finalize_emas(date);
  alter function game.pd_finalize(date) rename to pd_finalize_emas;
end $$;
revoke all on function game.pd_finalize_emas(date) from public, anon, authenticated;

create or replace function game.pd_finalize(p_sat date) returns void
language plpgsql as $$
declare w jsonb; v text;
begin
  perform game.pd_emas_cleanup();
  perform game.pd_finalize_emas(p_sat);
  select results -> 'winners' into w from game.pd_events where id = game.pd_id(p_sat) and status = 'announced';
  if jsonb_typeof(w) = 'array' then
    for v in select jsonb_array_elements_text(w) loop
      perform game.pd_emas_grant(v::uuid, game.pd_announce_at(p_sat + 7));
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Rupa kapal: emas tidak lagi ditempel. Layar Emas Juara = rupa slot layar biasa.
--   `emas: true` tetap ikut SELAMA barang itu terpasang, supaya klien lama (belum muat
--   ulang) tetap menggambar layar emas. Pinjaman lewat masa -> layar lama / tanpa layar.
-- ---------------------------------------------------------------------
do $$ begin
  drop function if exists game.kd_visual_emas(uuid);
  alter function game.kd_visual(uuid) rename to kd_visual_emas;
end $$;
revoke all on function game.kd_visual_emas(uuid) from public, anon, authenticated;

create or replace function game.kd_visual(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb := coalesce(game.kd_visual_emas(p_pid), '{}'::jsonb) - 'emas'; v_prev text;
begin
  if v ->> 'layar' = 'layar_emas_pekan' then
    if game.kd_qty(p_pid, 'layar_emas_pekan') > 0 then
      v := v || '{"emas": true}'::jsonb;
    else
      select prev_layar into v_prev from game.kd_loadout where player_id = p_pid;
      v := case when v_prev is not null and game.kd_qty(p_pid, v_prev) > 0 then v || jsonb_build_object('layar', v_prev) else v - 'layar' end;
    end if;
  end if;
  return nullif(v, '{}'::jsonb);
end $$;

-- data lama: juara 1 Pacu terakhir yang masih berjalan masa "emas sepekan"-nya dapat pinjaman
do $$
declare e game.pd_events; v text;
begin
  select * into e from game.pd_events where status = 'announced' order by sat desc limit 1;
  if found and game.pd_announce_at(e.sat + 7) > game.hr_now() and jsonb_typeof(e.results -> 'winners') = 'array' then
    for v in select jsonb_array_elements_text(e.results -> 'winners') loop
      if exists (select 1 from game.players where player_id = v::uuid)
         and not exists (select 1 from game.kd_owned where player_id = v::uuid and item_id = 'layar_emas_pekan') then
        perform game.pd_emas_grant(v::uuid, game.pd_announce_at(e.sat + 7));
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Daftar Kedai: Layar Emas Juara hanya tampil bagi peminjam aktif, dengan sisa waktu
-- ---------------------------------------------------------------------
do $$ begin
  drop function if exists game.kd_list_emas(uuid);
  alter function game.kd_list(uuid) rename to kd_list_emas;
end $$;
revoke all on function game.kd_list_emas(uuid) from public, anon, authenticated;

create or replace function game.kd_list(p_pid uuid) returns jsonb
language plpgsql as $$
declare v jsonb := game.kd_list_emas(p_pid); keep jsonb; v_until timestamptz;
begin
  if jsonb_typeof(v -> 'items') <> 'array' then return v; end if;
  select until into v_until from game.kd_owned where player_id = p_pid and item_id = 'layar_emas_pekan' and until > game.hr_now();
  select coalesce(jsonb_agg(case when x ->> 'id' = 'layar_emas_pekan'
           then x || jsonb_build_object('msLeft', greatest(0, floor(extract(epoch from (v_until - game.hr_now())) * 1000))::bigint, 'pinjam', true)
           else x end), '[]'::jsonb) into keep
    from jsonb_array_elements(v -> 'items') x
   where x ->> 'id' <> 'layar_emas_pekan' or v_until is not null;
  -- loadout yang masih menunjuk pinjaman kedaluwarsa: tampilkan seperti yang dilihat kapten lain
  if (v -> 'equipped' ->> 'layar') = 'layar_emas_pekan' and v_until is null then
    v := jsonb_set(v, '{equipped}', coalesce((select (game.kd_visual(p_pid) - 'emas' - 'sakti' - 'kelinci')), '{}'::jsonb));
  end if;
  return v || jsonb_build_object('items', keep);
end $$;

-- ---------------------------------------------------------------------
-- Ruang Ganti: simpan banyak slot sekaligus. a[0] = {slot: id | null}
--   * id kosong/null = lepas slot itu
--   * barang yang tidak dimiliki / slot salah dilewati dan dilaporkan di `skip`
-- ---------------------------------------------------------------------
create or replace function public.api_kedaiSusun(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me game.players := game.me(true); v_pid uuid := v_me.player_id; v_set jsonb := game.arg_json(a, 0);
  k text; v_id text; it game.kd_items; e jsonb; v_skip jsonb := '[]'::jsonb; n int := 0;
  slots text[] := array['bentuk', 'layar', 'lambung', 'haluan', 'panji', 'aura', 'lambang', 'jejak', 'meriam', 'kedatangan', 'penghuni'];
begin
  if v_me.archetype = '' then raise exception 'Buat karakter dulu.'; end if;
  if not game.fitur_on(v_pid, 'KedaiOpen') then raise exception 'Kedai Rantau belum dibuka.'; end if;
  if jsonb_typeof(v_set) <> 'object' then raise exception 'Susunan rupa tidak valid.'; end if;
  if (select count(*) from jsonb_object_keys(v_set)) > 20 then raise exception 'Susunan rupa terlalu banyak.'; end if;
  insert into game.kd_loadout(player_id) values (v_pid) on conflict (player_id) do nothing;
  select equipped into e from game.kd_loadout where player_id = v_pid for update;
  for k in select jsonb_object_keys(v_set) loop
    if not (k = any(slots)) then v_skip := v_skip || to_jsonb(k); continue; end if;
    v_id := nullif(v_set ->> k, '');
    if v_id is null then
      if e ? k then e := e - k; n := n + 1; end if;
      continue;
    end if;
    select * into it from game.kd_items where id = v_id and active and rak = 'rupa';
    if not found or it.slot is distinct from k or game.kd_qty(v_pid, v_id) <= 0 then v_skip := v_skip || to_jsonb(v_id); continue; end if;
    if e ->> k is distinct from v_id then e := e || jsonb_build_object(k, v_id); n := n + 1; end if;
  end loop;
  if n > 0 then
    update game.kd_loadout set equipped = e where player_id = v_pid;
    begin perform game.mp_touch(v_pid); exception when others then null; end;
  end if;
  return jsonb_build_object('changed', n, 'skip', v_skip, 'kedai', game.kd_list(v_pid), 'rupa', game.kd_rupa_view(v_pid),
    'shipVisual', game.ship_visual(v_pid));
end $$;
select game.expose('api_kedaisusun');
