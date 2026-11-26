-- =====================================================================
-- 0112 · Syarat item Warlord per komponen  (Tide v89)
--   Gold tetap 2,5 jt per komponen. Syarat item disesuaikan per komponen:
--     Mesin Jolt  : 10 Oli Hitam + 6 Gigi Jaring                        (tetap)
--     Palka       : 15 Oli Hitam + 60 Besi + 12 Rantai Biru
--     Lambung     : 20 Oli Hitam + 30 Besi + 12 Rantai Biru
--     Meriam      : 15 Oli Hitam + 30 Mesiu + 10 Besi
--                   + Mesin Jolt Warlord dan Lambung Warlord terpasang dulu
--   Pemilik lama tidak dicabut (baris mk_warlord tetap).
--   Tidak ada perubahan lain: gold, drop bahan, dan batas simpan (WarlordDropMax = 12) tetap.
--   Rantai Biru 12 pas di batas simpan, jadi Palka dan Lambung dikerjakan satu per satu.
-- Aman diulang.
-- =====================================================================

create or replace function game.wl_syarat(p_grup text) returns jsonb
language sql stable as $$
  select case p_grup
    when 'speed' then jsonb_build_object(
      'oli', greatest(0, game.cfg_num('WarlordOli', 10))::int,
      'bahan', jsonb_build_array(jsonb_build_object('id', 'qi_mk_gigi', 'n', greatest(0, game.cfg_num('WarlordBahan', 6))::int)),
      'prasyarat', '[]'::jsonb)
    when 'cargo' then jsonb_build_object('oli', 15,
      'bahan', jsonb_build_array(jsonb_build_object('id', 'besi', 'n', 60), jsonb_build_object('id', 'qi_mk_rantai', 'n', 12)),
      'prasyarat', '[]'::jsonb)
    when 'condition' then jsonb_build_object('oli', 20,
      'bahan', jsonb_build_array(jsonb_build_object('id', 'besi', 'n', 30), jsonb_build_object('id', 'qi_mk_rantai', 'n', 12)),
      'prasyarat', '[]'::jsonb)
    else jsonb_build_object('oli', 15,
      'bahan', jsonb_build_array(jsonb_build_object('id', 'mesiu', 'n', 30), jsonb_build_object('id', 'besi', 'n', 10)),
      'prasyarat', jsonb_build_array('speed', 'condition'))
  end
$$;

create or replace function game.wl_nama_bahan(p_id text) returns text
language sql stable as $$
  select coalesce((select name from game.commodities where id = p_id), (select name from game.item_catalog where item_id = p_id), p_id)
$$;

-- ---------------------------------------------------------------------
-- Status Garasi: tiap komponen membawa daftar bahan, jumlah Oli, dan prasyarat
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.wl_state_sy(uuid);
  alter function game.wl_state(uuid) rename to wl_state_sy;
end $$;
revoke all on function game.wl_state_sy(uuid) from public, anon, authenticated;

create or replace function game.wl_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare j jsonb := game.wl_state_sy(p_pid);
begin
  if j is null or jsonb_typeof(j -> 'komponen') <> 'array' then return j; end if;
  return j || jsonb_build_object('komponen',
    (select jsonb_agg(k || game.wl_syarat_info(p_pid, k ->> 'grup') order by o)
       from jsonb_array_elements(j -> 'komponen') with ordinality x(k, o)));
exception when others then return j;
end $$;

create or replace function game.wl_syarat_info(p_pid uuid, p_grup text) returns jsonb
language plpgsql stable as $$
declare s jsonb := game.wl_syarat(p_grup); b jsonb; pr jsonb; first_b jsonb := (s -> 'bahan' -> 0);
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', x ->> 'id', 'nama', game.wl_nama_bahan(x ->> 'id'),
      'n', (x ->> 'n')::int, 'punya', game.item_qty(p_pid, x ->> 'id')) order by o), '[]'::jsonb)
    into b from jsonb_array_elements(s -> 'bahan') with ordinality t(x, o);
  select coalesce(jsonb_agg(jsonb_build_object('grup', g, 'nama', game.wl_nama(g), 'ok', game.wl_has(p_pid, g)) order by o), '[]'::jsonb)
    into pr from jsonb_array_elements_text(s -> 'prasyarat') with ordinality t(g, o);
  return jsonb_build_object(
    'oli', (s ->> 'oli')::int, 'punyaOli', game.item_qty(p_pid, 'oli_hitam'),
    'bahan', b, 'prasyarat', pr,
    'prasyaratOk', not exists (select 1 from jsonb_array_elements(pr) e where not (e ->> 'ok')::boolean),
    -- kolom lama (bahan pertama) untuk klien lama
    'bahanId', first_b ->> 'id', 'bahanN', (first_b ->> 'n')::int,
    'bahanNama', game.wl_nama_bahan(first_b ->> 'id'), 'punyaBahan', game.item_qty(p_pid, first_b ->> 'id'));
end $$;

-- ---------------------------------------------------------------------
-- api_warlord: salinan 0078 dengan syarat per komponen + prasyarat
-- ---------------------------------------------------------------------
create or replace function public.api_warlord(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare
  v_me game.players := game.me(true); v_pid uuid := v_me.player_id;
  v_act text := lower(coalesce(game.arg(a, 0), 'status'));
  v_grup text := lower(coalesce(game.arg(a, 1), ''));
  v_gold bigint; v_s jsonb; v_oli int; x jsonb; g text; v_kurang text[];
begin
  if v_act = 'status' then return jsonb_build_object('warlord', game.wl_state(v_pid)); end if;
  if v_act <> 'bangun' then raise exception 'Aksi tidak dikenal.'; end if;
  if not game.wl_buka(v_pid) then raise exception 'Garasi itu masih terkunci, Kapten.'; end if;
  if game.in_transit(v_pid) then raise exception 'Merapat dulu di pelabuhan, Kapten.'; end if;
  if game.current_city(v_pid) is distinct from 'zentul' then raise exception 'Hanya Yaptob yang bisa memasangnya, Kapten. Di Zentul.'; end if;
  if v_grup not in ('speed', 'cargo', 'condition', 'cannons') then raise exception 'Komponen tidak dikenali.'; end if;
  if game.wl_has(v_pid, v_grup) then raise exception '% sudah terpasang, Kapten.', game.wl_nama(v_grup); end if;

  v_s := game.wl_syarat(v_grup);
  -- prasyarat urutan (Meriam dipasang paling akhir)
  v_kurang := array(select game.wl_nama(p) from jsonb_array_elements_text(v_s -> 'prasyarat') p where not game.wl_has(v_pid, p));
  if array_length(v_kurang, 1) is not null then
    raise exception 'Yaptob memasang % paling akhir. Pasang dulu %, Kapten.', game.wl_nama(v_grup), array_to_string(v_kurang, ' dan ');
  end if;
  if not game.wl_siap(v_pid, v_grup) then
    raise exception 'Grup itu belum mentok, Kapten. Yaptob cuma mau memasang di atas yang sudah terbaik (Level V Tier IV).';
  end if;

  v_gold := greatest(0, game.cfg_num('WarlordGold', 2500000))::bigint;
  v_oli := (v_s ->> 'oli')::int;
  if v_me.gold < v_gold then raise exception 'Butuh % gold, Kapten.', v_gold; end if;
  if game.item_qty(v_pid, 'oli_hitam') < v_oli then raise exception 'Butuh % Oli Hitam di palkamu, Kapten.', v_oli; end if;
  for x in select * from jsonb_array_elements(v_s -> 'bahan') loop
    if game.item_qty(v_pid, x ->> 'id') < (x ->> 'n')::int then
      raise exception 'Butuh % %, Kapten.', (x ->> 'n')::int, game.wl_nama_bahan(x ->> 'id');
    end if;
  end loop;

  update game.players set gold = gold - v_gold where player_id = v_pid;
  perform game.item_adjust(v_pid, 'oli_hitam', -v_oli);
  for x in select * from jsonb_array_elements(v_s -> 'bahan') loop
    perform game.item_adjust(v_pid, x ->> 'id', -(x ->> 'n')::int);
  end loop;
  insert into game.mk_warlord(player_id, grup) values (v_pid, v_grup) on conflict do nothing;
  perform game.log(v_pid, 'Warlord: ' || game.wl_nama(v_grup) || ' terpasang.');

  return jsonb_build_object('warlord', game.wl_state(v_pid), 'grup', v_grup, 'nama', game.wl_nama(v_grup),
    'newGold', (select gold from game.players where player_id = v_pid), 'ship', game.ship_json(v_pid));
end $$;
select game.expose('api_warlord');
