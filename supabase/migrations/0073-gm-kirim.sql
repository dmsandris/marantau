-- =====================================================================
-- Marantau (Supabase) - 0073 GM KIRIM BARANG  (Tide v58)
-- ---------------------------------------------------------------------
-- GM mengirim komoditas pasar langsung ke palka seorang pemain.
--   * Hanya komoditas pasar aktif (game.commodities.active). Item lain ditolak.
--   * Masuk palka. Ruang kurang -> seluruh kiriman gagal (tidak sebagian),
--     pemain & GM sama-sama mendapat notifikasi inbox.
--   * Langsung masuk, tanpa tombol terima. Modal 0 (hadiah), src_city tidak diisi.
--   * Tetap masuk walau kapal sedang berlayar.
--   * Tanpa tarik kembali. Semua percobaan (berhasil / gagal) dicatat.
--
--   api_gmKirim(['init'])                            daftar komoditas + 30 log terakhir + batas
--   api_gmKirim(['cek', username])                   kartu pemain + sisa palka
--   api_gmKirim(['kirim', {u, item, qty, note}])     kirim
-- Aman diulang.
-- =====================================================================

create table if not exists game.gm_kirim_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  gm_id uuid,
  gm_user text,
  player_id uuid,
  username text,
  item_id text,
  qty int,
  ok boolean not null,
  reason text,
  note text
);
create index if not exists gm_kirim_log_at on game.gm_kirim_log (id desc);

insert into game.config(key, value) values ('GmKirimMaks', '500') on conflict (key) do nothing;

create or replace function game.gmk_log_json(p_n int default 30) returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'at', (extract(epoch from x.at) * 1000)::bigint, 'by', x.gm_user, 'u', x.username,
      'item', x.item_id, 'name', (select name from game.commodities where id = x.item_id),
      'qty', x.qty, 'ok', x.ok, 'reason', x.reason, 'note', x.note) order by x.id desc), '[]'::jsonb)
  from (select * from game.gm_kirim_log order by id desc limit p_n) x
$$;

create or replace function game.gmk_card(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'username', p.username,
    'name', nullif(coalesce(p.character_name, ''), ''),
    'ship', (select ship_name from game.ships where player_id = p.player_id),
    'city', (select coalesce(c.name, l.city_id) from game.player_location l left join game.cities c on c.city_id = l.city_id where l.player_id = p.player_id),
    'sea', coalesce((select l.destination_city_id is not null from game.player_location l where l.player_id = p.player_id), false),
    'used', game.cargo_used(p.player_id),
    'capacity', coalesce(game.effective_cargo(p.player_id), 0),
    'free', game.cargo_free(p.player_id),
    'gm', game.is_gm(p.player_id))
  from game.players p where p.player_id = p_pid
$$;

create or replace function public.api_gmKirim(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_gm uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), ''));
  o jsonb; v_u text; v_pid uuid; v_by text; v_c game.commodities; v_qty int; v_note text;
  v_max int := greatest(1, game.cfg_num('GmKirimMaks', 500)::int);
  v_need numeric; v_free numeric; q0 int;
begin
  if not game.is_gm(v_gm) then raise exception 'Perintah ini khusus GM.'; end if;
  v_by := coalesce((select username from game.players where player_id = v_gm), '');

  if v_act = 'init' then
    return jsonb_build_object('ok', true, 'max', v_max, 'log', game.gmk_log_json(30),
      'items', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'tier', c.tier, 'size', c.size) order by c.sort, c.name)
                           from game.commodities c where c.active), '[]'::jsonb));
  end if;

  if v_act = 'cek' then
    v_u := lower(btrim(coalesce(game.arg(a, 1), '')));
  elsif v_act = 'kirim' then
    o := game.arg_json(a, 1);
    if jsonb_typeof(o) <> 'object' then o := '{}'::jsonb; end if;
    v_u := lower(btrim(coalesce(o ->> 'u', '')));
  else
    raise exception 'Perintah tidak dikenal: %', v_act;
  end if;

  if v_u !~ '^[a-z0-9_]{3,16}$' then raise exception 'Username tidak valid.'; end if;
  select player_id into v_pid from game.players where username = v_u;
  if v_pid is null then raise exception 'Username "%" tidak ditemukan.', v_u; end if;
  if not exists (select 1 from game.ships where player_id = v_pid) then raise exception 'Pemain "%" belum punya kapal.', v_u; end if;

  if v_act = 'cek' then
    return jsonb_build_object('ok', true, 'card', game.gmk_card(v_pid));
  end if;

  -- kirim --------------------------------------------------------------
  if game.is_gm(v_pid) then raise exception 'Tidak bisa mengirim ke akun GM.'; end if;
  select * into v_c from game.commodities where id = coalesce(o ->> 'item', '') and active;
  if v_c.id is null then raise exception 'Hanya komoditas pasar yang bisa dikirim.'; end if;
  v_qty := floor(game.mp_jsnum(o ->> 'qty', 0))::int;
  if v_qty < 1 or v_qty > v_max then raise exception 'Jumlah harus 1 sampai %.', v_max; end if;
  v_note := nullif(left(btrim(coalesce(o ->> 'note', '')), 120), '');

  perform 1 from game.players where player_id = v_pid for update;   -- antre dengan aksi pemain lain
  v_need := v_qty * coalesce(v_c.size, 1);
  v_free := game.cargo_free(v_pid);

  if v_need > v_free then
    insert into game.gm_kirim_log(gm_id, gm_user, player_id, username, item_id, qty, ok, reason, note)
      values (v_gm, v_by, v_pid, v_u, v_c.id, v_qty, false, 'palka penuh', v_note);
    perform game.mp_push_inbox(v_pid, jsonb_build_object('type', 'gm_kirim_gagal', 'qty', v_qty, 'name', v_c.name,
      'need', v_need, 'free', greatest(0, v_free)));
    perform game.mp_push_inbox(v_gm, jsonb_build_object('type', 'gm_kirim_gagal_gm', 'u', v_u, 'qty', v_qty, 'name', v_c.name,
      'need', v_need, 'free', greatest(0, v_free)));
    return jsonb_build_object('ok', false, 'reason', 'Palka ' || v_u || ' tidak cukup: perlu ' || v_need || ' ruang, sisa ' || greatest(0, v_free) || '. Tidak ada yang dikirim.',
      'card', game.gmk_card(v_pid), 'log', game.gmk_log_json(30));
  end if;

  select coalesce((select qty from game.inventory where player_id = v_pid and item_id = v_c.id), 0) into q0;
  perform game.adjust_inventory(v_pid, v_c.id, v_qty);
  -- modal 0: unit lama dengan modal diketahui tetap; bila palka kosong untuk barang ini, modal = 0.
  -- (src_city sengaja tidak diubah)
  if q0 = 0 then update game.inventory set cost = 0 where player_id = v_pid and item_id = v_c.id; end if;

  insert into game.gm_kirim_log(gm_id, gm_user, player_id, username, item_id, qty, ok, note)
    values (v_gm, v_by, v_pid, v_u, v_c.id, v_qty, true, v_note);
  perform game.log(v_pid, 'Kiriman dari Syahbandar: ' || v_qty || ' ' || v_c.name || ' masuk palka.');
  perform game.mp_push_inbox(v_pid, jsonb_build_object('type', 'gm_kirim', 'qty', v_qty, 'item', v_c.id, 'name', v_c.name, 'note', v_note));

  return jsonb_build_object('ok', true, 'card', game.gmk_card(v_pid), 'log', game.gmk_log_json(30));
end $$;
select game.expose('api_gmkirim');
