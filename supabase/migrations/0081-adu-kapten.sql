-- =====================================================================
-- 0081 · Saga 4 batch 6b — ADU KAPTEN (balapan antar pemain di Sirkuit Zentul)
--   Dua kapten yang sudah menamatkan Mahkota dan sama-sama merapat di Zentul
--   boleh saling menantang. Tanpa taruhan. Server menyimulasi ulang kedua
--   catatan dengan benih yang sama, jadi yang menang adalah yang benar-benar cepat.
--   Maksimal 3 adu per pasangan per hari game. Yang tidak menyetor catatan
--   dalam 90 detik dianggap kalah; bila keduanya diam, adu dibatalkan.
-- Aman diulang.
-- =====================================================================

insert into game.config(key, value) values ('TrekAduOpen', '1'), ('TrekAduMaks', '3') on conflict (key) do nothing;

create table if not exists game.trek_duels (
  id        text primary key,
  status    text not null default 'invited',   -- invited|active|done|declined|expired|cancelled
  city      text not null default 'zentul',
  a_id      uuid not null references game.players(player_id) on update cascade on delete cascade,
  b_id      uuid not null references game.players(player_id) on update cascade on delete cascade,
  a_nama    text, b_nama text,
  a_ship    text, b_ship text,
  seed      bigint not null,
  created   bigint not null,
  started   bigint,
  log_a     jsonb, log_b jsonb,
  us_a      bigint, us_b bigint,
  menang    text,                               -- 'a'|'b'|'seri'|null
  game_day  int not null default 0
);
alter table game.trek_duels enable row level security;
create index if not exists trek_duels_a on game.trek_duels(a_id, created desc);
create index if not exists trek_duels_b on game.trek_duels(b_id, created desc);

create or replace function game.trek_adu_boleh(p_pid uuid) returns boolean
language sql stable as $$
  select coalesce(game.cfg_num('TrekAduOpen', 1), 0) > 0 and game.mk_tamat(p_pid)
$$;

create or replace function game.trek_adu_siap(p_pid uuid) returns boolean
language sql stable as $$
  select game.trek_adu_boleh(p_pid) and not game.in_transit(p_pid) and game.current_city(p_pid) = 'zentul'
$$;

-- Catatan balapan harus masuk akal (bentuk sama seperti Sirkuit).
create or replace function game.trek_log_cek(p_log jsonb) returns boolean
language plpgsql immutable as $$
declare i int; v_prev bigint := -100000; v_t bigint;
begin
  if p_log is null or jsonb_typeof(p_log) <> 'array' or jsonb_array_length(p_log) > 240 then return false; end if;
  for i in 0..jsonb_array_length(p_log) - 1 loop
    if jsonb_typeof(p_log -> i) <> 'array' or jsonb_typeof(p_log -> i -> 0) <> 'number' or (p_log -> i ->> 1) not in ('0', '1')
       or (p_log -> i ->> 0) !~ '^-?[0-9]{1,6}$' then return false; end if;
    v_t := (p_log -> i ->> 0)::bigint;
    if v_t < v_prev or v_t < -20000 or v_t > 40000 then return false; end if;
    v_prev := v_t;
  end loop;
  return true;
end $$;

create or replace function game.trek_adu_slot(p_pid uuid) returns text
language sql stable as $$
  select id from game.trek_duels
   where status in ('invited', 'active') and (a_id = p_pid or b_id = p_pid)
   order by created desc limit 1
$$;

create or replace function game.trek_adu_jml(p_a uuid, p_b uuid) returns int
language sql stable as $$
  select coalesce(count(*), 0)::int from game.trek_duels
   where game_day = game.game_day() and status in ('active', 'done')
     and ((a_id = p_a and b_id = p_b) or (a_id = p_b and b_id = p_a))
$$;

create or replace function game.trek_adu_view(d game.trek_duels, p_me uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'id', d.id, 'status', d.status, 'seed', d.seed, 'kota', d.city,
    'aku', case when d.a_id = p_me then 'a' else 'b' end,
    'kapalku', case when d.a_id = p_me then d.a_ship else d.b_ship end,
    'kapalLawan', case when d.a_id = p_me then d.b_ship else d.a_ship end,
    'lawan', case when d.a_id = p_me then d.b_nama else d.a_nama end,
    'lawanId', game.mp_pub_of(case when d.a_id = p_me then d.b_id else d.a_id end),
    'mulai', d.started, 'dibuat', d.created,
    'rekorLawan', (select b.log from game.trek_best b where b.player_id = case when d.a_id = p_me then d.b_id else d.a_id end
                    and b.ship = case when d.a_id = p_me then d.b_ship else d.a_ship end),
    'usKu', case when d.a_id = p_me then d.us_a else d.us_b end,
    'usLawan', case when d.a_id = p_me then d.us_b else d.us_a end,
    'logKu', case when d.a_id = p_me then d.log_a is not null else d.log_b is not null end,
    'logLawan', case when d.a_id = p_me then d.log_b is not null else d.log_a is not null end,
    'menang', case when d.menang is null then null when d.menang = 'seri' then 'seri'
                   when (d.menang = 'a') = (d.a_id = p_me) then 'aku' else 'lawan' end)
$$;

-- Hitung hasil bila kedua catatan masuk, atau waktu setor habis.
create or replace function game.trek_adu_hitung(p_id text) returns game.trek_duels
language plpgsql as $$
declare d game.trek_duels; va jsonb; vb jsonb; fa bigint; fb bigint; v_habis boolean;
begin
  select * into d from game.trek_duels where id = p_id for update;
  if d.id is null then return d; end if;
  if d.status = 'invited' and game.now_ms() - d.created > 60000 then
    update game.trek_duels set status = 'expired' where id = d.id returning * into d;
    return d;
  end if;
  if d.status <> 'active' then return d; end if;
  v_habis := game.now_ms() - coalesce(d.started, d.created) > 90000;
  if not v_habis and (d.log_a is null or d.log_b is null) then return d; end if;
  if v_habis and d.log_a is null and d.log_b is null then
    update game.trek_duels set status = 'cancelled' where id = d.id returning * into d;
    return d;
  end if;
  if d.log_a is not null then
    va := game.trek_run(game.trek_ships() -> d.a_ship, d.log_a, null, d.seed); fa := (va ->> 'fin')::bigint;
  end if;
  if d.log_b is not null then
    vb := game.trek_run(game.trek_ships() -> d.b_ship, d.log_b, null, d.seed); fb := (vb ->> 'fin')::bigint;
  end if;
  update game.trek_duels set status = 'done', us_a = fa, us_b = fb,
      menang = case when fa is null and fb is null then 'seri'
                    when fb is null then 'a' when fa is null then 'b'
                    when fa < fb then 'a' when fb < fa then 'b' else 'seri' end
    where id = d.id returning * into d;
  perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'trek_adu_hasil', 'duelId', d.id));
  perform game.mp_push_inbox(d.b_id, jsonb_build_object('type', 'trek_adu_hasil', 'duelId', d.id));
  return d;
end $$;

-- Papan Adu: kemenangan tujuh hari game terakhir.
create or replace function game.trek_adu_papan() returns jsonb
language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('nama', nama, 'menang', n) order by n desc, nama), '[]'::jsonb)
  from (select coalesce(nullif(p.character_name, ''), 'Kapten') as nama, count(*) as n
          from game.trek_duels d
          join game.players p on p.player_id = case when d.menang = 'a' then d.a_id else d.b_id end
         where d.status = 'done' and d.menang in ('a', 'b') and d.game_day > game.game_day() - 7
         group by 1 order by n desc limit 10) s
$$;

create or replace function game.trek_adu_lobi(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v_list jsonb; v_slot text; d game.trek_duels;
begin
  if not game.trek_adu_boleh(p_pid) then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', game.mp_pub_of(x.player_id), 'nama', x.nama,
      'sisa', greatest(0, game.cfg_num('TrekAduMaks', 3)::int - game.trek_adu_jml(p_pid, x.player_id))) order by x.nama), '[]'::jsonb)
    into v_list
    from (select pr.player_id, coalesce(nullif(pl.character_name, ''), 'Kapten') as nama
            from game.mp_presence pr join game.players pl on pl.player_id = pr.player_id
           where pr.player_id <> p_pid and game.mp_online(pr) and not pr.sea and pr.c = 'zentul'
             and game.trek_adu_boleh(pr.player_id) limit 20) x;
  v_slot := game.trek_adu_slot(p_pid);
  if v_slot is not null then select * into d from game.trek_duels where id = v_slot; end if;
  return jsonb_build_object('siap', game.trek_adu_siap(p_pid), 'kapten', v_list,
    'papan', game.trek_adu_papan(), 'maks', game.cfg_num('TrekAduMaks', 3)::int,
    'duel', case when d.id is null then null else game.trek_adu_view(d, p_pid) end);
end $$;

-- ---------------------------------------------------------------------
-- API  ['lobi'] | ['tantang', pub] | ['jawab', id, true|false] | ['log', id, log] | ['lihat', id] | ['batal', id]
-- ---------------------------------------------------------------------
create or replace function public.api_trekDuel(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid(); v_act text := coalesce(game.arg(a, 0), 'lobi'); v_duel text; v_target uuid;
  d game.trek_duels; t game.mp_presence; v_nama text; v_tn text;
begin
  if not game.trek_adu_boleh(v_id) then raise exception 'Adu Kapten baru terbuka bagi yang sudah menamatkan Mahkota Selat.'; end if;
  perform game.mp_touch(v_id);

  if v_act = 'lobi' then
    perform game.trek_adu_hitung(game.trek_adu_slot(v_id));
    return jsonb_build_object('adu', game.trek_adu_lobi(v_id));
  end if;

  if v_act = 'tantang' then
    v_target := game.mp_unpub(game.arg(a, 1));
    if v_target is null or v_target = v_id then raise exception 'Kapten itu tidak ditemukan.'; end if;
    perform game.mp_xlock(v_id);
    if not game.trek_adu_siap(v_id) then raise exception 'Kau harus merapat di Zentul untuk menantang.'; end if;
    if not game.trek_adu_siap(v_target) then raise exception 'Kapten itu tidak sedang merapat di Zentul.'; end if;
    select * into t from game.mp_presence where player_id = v_target;
    if not found or not game.mp_online(t) then raise exception 'Kapten itu sedang tidak online.'; end if;
    perform game.trek_adu_hitung(game.trek_adu_slot(v_id));
    if game.trek_adu_slot(v_id) is not null then raise exception 'Kau masih punya adu yang belum selesai.'; end if;
    perform game.trek_adu_hitung(game.trek_adu_slot(v_target));
    if game.trek_adu_slot(v_target) is not null then raise exception 'Kapten itu sedang beradu dengan yang lain.'; end if;
    if game.trek_adu_jml(v_id, v_target) >= game.cfg_num('TrekAduMaks', 3)::int then
      raise exception 'Kalian sudah beradu % kali hari ini. Cari lawan lain dulu.', game.cfg_num('TrekAduMaks', 3)::int;
    end if;
    select coalesce(nullif(character_name, ''), 'Kapten') into v_nama from game.players where player_id = v_id;
    select coalesce(nullif(character_name, ''), 'Kapten') into v_tn from game.players where player_id = v_target;
    insert into game.trek_duels(id, status, city, a_id, b_id, a_nama, b_nama, a_ship, b_ship, seed, created, game_day)
      values (game.mp_uid('t'), 'invited', 'zentul', v_id, v_target, v_nama, v_tn,
              game.trek_kapal(v_id), game.trek_kapal(v_target),
              floor(random() * 2000000000)::bigint + 1, game.now_ms(), game.game_day())
      returning * into d;
    perform game.mp_push_inbox(v_target, jsonb_build_object('type', 'trek_adu_invite', 'duelId', d.id, 'from', v_nama, 'fromId', game.mp_pub_of(v_id)));
    return jsonb_build_object('duel', game.trek_adu_view(d, v_id));
  end if;

  v_duel := game.arg(a, 1);
  select * into d from game.trek_duels where id = v_duel for update;
  if d.id is null or (d.a_id <> v_id and d.b_id <> v_id) then raise exception 'Adu itu tidak ditemukan.'; end if;

  if v_act = 'jawab' then
    if d.b_id <> v_id then raise exception 'Hanya yang ditantang yang bisa menjawab.'; end if;
    if d.status <> 'invited' then return jsonb_build_object('duel', game.trek_adu_view(d, v_id)); end if;
    if game.now_ms() - d.created > 60000 then
      update game.trek_duels set status = 'expired' where id = d.id returning * into d;
      raise exception 'Tantangan sudah kedaluwarsa.';
    end if;
    if not game.mp_truthy(game.arg_json(a, 2)) then
      update game.trek_duels set status = 'declined' where id = d.id returning * into d;
      perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'trek_adu_tolak', 'duelId', d.id, 'from', d.b_nama));
      return jsonb_build_object('duel', game.trek_adu_view(d, v_id));
    end if;
    if not game.trek_adu_siap(v_id) then raise exception 'Kau harus merapat di Zentul untuk beradu.'; end if;
    update game.trek_duels set status = 'active', started = game.now_ms() where id = d.id returning * into d;
    perform game.mp_push_inbox(d.a_id, jsonb_build_object('type', 'trek_adu_mulai', 'duelId', d.id, 'from', d.b_nama));
    perform game.mp_rt('trek:' || d.id, 'mulai', jsonb_build_object('duelId', d.id, 'seed', d.seed));
    return jsonb_build_object('duel', game.trek_adu_view(d, v_id));
  end if;

  if v_act = 'log' then
    if d.status <> 'active' then
      d := game.trek_adu_hitung(d.id);
      return jsonb_build_object('duel', game.trek_adu_view(d, v_id));
    end if;
    if not game.trek_log_cek(game.arg_json(a, 2)) then raise exception 'Catatan balapan tidak terbaca.'; end if;
    if d.a_id = v_id then
      if d.log_a is null then update game.trek_duels set log_a = game.arg_json(a, 2) where id = d.id; end if;
    else
      if d.log_b is null then update game.trek_duels set log_b = game.arg_json(a, 2) where id = d.id; end if;
    end if;
    d := game.trek_adu_hitung(d.id);
    return jsonb_build_object('duel', game.trek_adu_view(d, v_id));
  end if;

  if v_act = 'batal' then
    if d.status in ('invited', 'active') then
      update game.trek_duels set status = 'cancelled' where id = d.id returning * into d;
      perform game.mp_push_inbox(case when d.a_id = v_id then d.b_id else d.a_id end,
        jsonb_build_object('type', 'trek_adu_batal', 'duelId', d.id));
    end if;
    return jsonb_build_object('duel', game.trek_adu_view(d, v_id));
  end if;

  d := game.trek_adu_hitung(d.id);
  return jsonb_build_object('duel', game.trek_adu_view(d, v_id), 'adu', game.trek_adu_lobi(v_id));
end $$;
select game.expose('api_trekduel');

-- Status Sirkuit ikut membawa ringkasan Adu Kapten.
do $$
begin
  drop function if exists game.trek_state_adu(uuid);
  alter function game.trek_state(uuid) rename to trek_state_adu;
end $$;
create or replace function game.trek_state(p_pid uuid) returns jsonb
language plpgsql stable as $$
declare v jsonb;
begin
  v := game.trek_state_adu(p_pid);
  if v is null then return null; end if;
  return v || jsonb_build_object('adu', game.trek_adu_lobi(p_pid));
end $$;
