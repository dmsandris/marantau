-- =====================================================================
-- 0101 Pesan Pribadi (PM) antar kapten · Tide v82
-- Konsep: claude/KONSEP-Pesan-Pribadi.md
--   - Kirim dari kartu kapten / tab Pesan, ke kapten mana saja (online/offline, beda pulau, berlayar).
--   - Disimpan 7 hari (PmSimpanHari). Pesan ke kapten offline muncul saat dia login.
--   - Akun GM tidak bisa di-PM dan tidak mengirim PM.
--   - Jeda 2 detik, berbagi jeda dengan chat (mp_presence.last_chat_at). Tanpa batas harian.
--   - Pengantaran: realtime.send ke kanal pribadi player:<pub> (event 'pm') sebagai "bel",
--     isi diambil lewat api_mpPulse (kunci 'pm'), jadi dedup & urutan tetap dari server.
--   - Panel Ops (tab Iluminaty) membaca game.mp_pm lewat role mt_ops_ro (grant dari fixups-vps.sql).
-- Aman diulang.
-- =====================================================================

create table if not exists game.mp_pm (
  id      bigserial primary key,
  pair    text not null,                -- '<uuid kecil>|<uuid besar>' = satu percakapan
  from_id uuid not null references game.players(player_id) on delete cascade on update cascade,
  to_id   uuid not null references game.players(player_id) on delete cascade on update cascade,
  tx      text not null,
  ts      bigint not null,              -- game.now_ms()
  read_at bigint
);
create index if not exists mp_pm_pair_idx on game.mp_pm (pair, id);
create index if not exists mp_pm_to_idx on game.mp_pm (to_id, id);
create index if not exists mp_pm_unread_idx on game.mp_pm (to_id) where read_at is null;
create index if not exists mp_pm_ts_idx on game.mp_pm (ts);
alter table game.mp_pm enable row level security;

insert into game.config(key, value) values ('PmSimpanHari', '7') on conflict (key) do nothing;

create or replace function game.pm_pair(a uuid, b uuid) returns text
language sql immutable as $$ select least(a::text, b::text) || '|' || greatest(a::text, b::text) $$;

create or replace function game.pm_cutoff() returns bigint
language sql stable as $$ select game.now_ms() - (greatest(1, game.cfg_num('PmSimpanHari', 7)) * 86400000)::bigint $$;

-- Tujuan PM dari pub -> player_id. Pub palsu / GM / tanpa karakter -> 'Kapten tidak ditemukan.'
create or replace function game.pm_target(p_pub text) returns uuid
language plpgsql stable as $$
declare v uuid;
begin
  select o.player_id into v from game.mp_presence o join game.players p on p.player_id = o.player_id
  where o.pub = coalesce(p_pub, '') and coalesce(p.archetype, '') <> '';
  if v is null or game.is_gm(v) then raise exception 'Kapten tidak ditemukan.'; end if;
  return v;
end $$;

-- Ringkasan lawan bicara (pub, nama, archetype, wajah) untuk daftar & utas
create or replace function game.pm_who(p_pid uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', o.pub, 'n', p.character_name, 'a', p.archetype,
    'f', coalesce(case when o.f is null or jsonb_typeof(o.f) = 'null' then null else o.f end, p.appearance, 'null'::jsonb))
  from game.players p left join game.mp_presence o on o.player_id = p.player_id
  where p.player_id = p_pid
$$;

create or replace function game.pm_msg(m game.mp_pm, p_me uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', m.id, 'mine', m.from_id = p_me, 'tx', m.tx, 'ts', m.ts,
    'read', m.read_at is not null)
$$;

-- Bagian 'pm' untuk api_mpPulse.
--   since = 0 (baru dimuat): hanya jumlah belum dibaca + id teratas, tanpa isi.
--   since > 0: pesan MASUK baru (id > since), maks 20, plus jumlah belum dibaca.
create or replace function game.pm_pulse(p_me uuid, p_since bigint) returns jsonb
language plpgsql stable as $$
declare v_unread int; v_top bigint; v_new jsonb := '[]'::jsonb; v_cut bigint := game.pm_cutoff();
begin
  select count(*) into v_unread from game.mp_pm where to_id = p_me and read_at is null and ts > v_cut;
  select coalesce(max(id), 0) into v_top from game.mp_pm where to_id = p_me;
  if coalesce(p_since, 0) > 0 and v_top > p_since then
    select coalesce(jsonb_agg(x.j order by x.id), '[]'::jsonb) into v_new from (
      select m.id, game.pm_msg(m, p_me) || jsonb_build_object('from', game.pm_who(m.from_id)) j
      from game.mp_pm m where m.to_id = p_me and m.id > p_since and m.ts > v_cut
      order by m.id desc limit 20) x;
  end if;
  return jsonb_build_object('unread', v_unread, 'top', v_top, 'baru', v_new);
end $$;

-- ---------------------------------------------------------------------
-- ENDPOINT api_mpPm
--   ['kirim', pubTujuan, teks]        -> {msg}
--   ['daftar']                        -> {list:[{who, last, unread}], unread}
--   ['utas', pubLawan, sebelumId?]    -> {who, msgs[], more} (pesan masuk ditandai dibaca)
--   ['baca', pubLawan]                -> {unread}
-- ---------------------------------------------------------------------
create or replace function public.api_mpPm(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_me uuid := game.uid(); v_act text := lower(coalesce(game.arg(a, 0), '')); v_to uuid; v_tx text;
  v_pair text; m game.mp_pm; v_list jsonb; v_msgs jsonb; v_before bigint; v_more boolean; v_cut bigint := game.pm_cutoff();
  v_pub_to text; v_unread int; v_now bigint := game.now_ms();
begin
  if v_me is null or not exists (select 1 from game.players where player_id = v_me and coalesce(archetype, '') <> '') then
    raise exception 'Muat ulang game dulu.';
  end if;
  if game.is_gm(v_me) then raise exception 'Aksi tidak dikenal.'; end if;

  if v_act = 'kirim' then
    v_to := game.pm_target(game.arg(a, 1));
    if v_to = v_me then raise exception 'Tidak bisa mengirim pesan ke diri sendiri.'; end if;
    v_tx := game.mp_clean(game.arg(a, 2), 140);
    if v_tx = '' then raise exception 'Pesan kosong.'; end if;
    if not exists (select 1 from game.mp_presence where player_id = v_me) then perform game.mp_presence_sync(v_me); end if;
    update game.mp_presence set last_chat_at = now()
    where player_id = v_me and (last_chat_at is null or last_chat_at <= now() - interval '2 seconds');
    if not found then raise exception 'Pelan-pelan, Kapten - tunggu sebentar sebelum kirim lagi.'; end if;
    insert into game.mp_pm(pair, from_id, to_id, tx, ts) values (game.pm_pair(v_me, v_to), v_me, v_to, v_tx, v_now)
      returning * into m;
    delete from game.mp_pm where ts < v_cut;             -- pembersihan 7 hari (index ts, murah)
    v_pub_to := game.mp_pub_of(v_to);
    if v_pub_to is not null then perform game.mp_rt('player:' || v_pub_to, 'pm', jsonb_build_object('id', m.id)); end if;
    return jsonb_build_object('msg', game.pm_msg(m, v_me), 'who', game.pm_who(v_to));

  elsif v_act = 'daftar' then
    select coalesce(jsonb_agg(x.j order by x.id desc), '[]'::jsonb) into v_list from (
      select l.id, jsonb_build_object(
          'who', game.pm_who(case when l.from_id = v_me then l.to_id else l.from_id end),
          'last', game.pm_msg(l, v_me),
          'unread', (select count(*) from game.mp_pm u where u.pair = l.pair and u.to_id = v_me and u.read_at is null and u.ts > v_cut)) j
      from (select distinct on (pair) * from game.mp_pm
            where (from_id = v_me or to_id = v_me) and ts > v_cut
            order by pair, id desc) l
      order by l.id desc limit 40) x;
    select count(*) into v_unread from game.mp_pm where to_id = v_me and read_at is null and ts > v_cut;
    return jsonb_build_object('list', v_list, 'unread', v_unread);

  elsif v_act = 'utas' or v_act = 'baca' then
    begin v_to := game.pm_target(game.arg(a, 1));
    exception when others then
      -- lawan yang kini jadi GM / hilang: tetap boleh dibaca lewat pub bila pernah bercakap
      select o.player_id into v_to from game.mp_presence o where o.pub = coalesce(game.arg(a, 1), '');
      if v_to is null then raise exception 'Kapten tidak ditemukan.'; end if;
    end;
    v_pair := game.pm_pair(v_me, v_to);
    update game.mp_pm set read_at = v_now where pair = v_pair and to_id = v_me and read_at is null;
    select count(*) into v_unread from game.mp_pm where to_id = v_me and read_at is null and ts > v_cut;
    if v_act = 'baca' then return jsonb_build_object('unread', v_unread); end if;
    v_before := nullif(game.mp_jsnum(game.arg(a, 2), 0), 0)::bigint;
    select coalesce(jsonb_agg(game.pm_msg(x, v_me) order by x.id), '[]'::jsonb) into v_msgs from (
      select * from game.mp_pm where pair = v_pair and ts > v_cut and (v_before is null or id < v_before)
      order by id desc limit 50) x;
    v_more := jsonb_array_length(v_msgs) = 50 and exists (select 1 from game.mp_pm where pair = v_pair and ts > v_cut
      and id < ((v_msgs -> 0 ->> 'id')::bigint));
    return jsonb_build_object('who', game.pm_who(v_to) || jsonb_build_object('gm', game.is_gm(v_to)),
      'msgs', v_msgs, 'more', v_more, 'unread', v_unread);
  end if;
  raise exception 'Aksi tidak dikenal.';
end $$;
select game.expose('api_mppm');

-- ---------------------------------------------------------------------
-- api_mpPulse membawa 'pm' (since.pm dari klien). Pola bungkus: versi lama -> game.api_mppulse_pm
-- ---------------------------------------------------------------------
do $$
begin
  drop function if exists game.api_mppulse_pm(jsonb);
  alter function public.api_mppulse(jsonb) rename to api_mppulse_pm;
  alter function public.api_mppulse_pm(jsonb) set schema game;
end $$;
revoke all on function game.api_mppulse_pm(jsonb) from public, anon, authenticated;

create or replace function public.api_mpPulse(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare r jsonb; v_me uuid; v_since jsonb := game.arg_json(a, 0);
begin
  r := game.api_mppulse_pm(a);
  if r ? 'needState' then return r; end if;
  v_me := game.uid();
  if game.is_gm(v_me) then return r; end if;
  begin
    if jsonb_typeof(v_since) <> 'object' then v_since := '{}'::jsonb; end if;
    r := r || jsonb_build_object('pm', game.pm_pulse(v_me, game.mp_jsnum(v_since ->> 'pm', 0)::bigint));
  exception when others then null;
  end;
  return r;
end $$;
select game.expose('api_mppulse');

-- api_mpProfile membawa 'gm' supaya klien menyembunyikan bagian Kirim Pesan
do $$
begin
  drop function if exists game.api_mpprofile_pm(jsonb);
  alter function public.api_mpprofile(jsonb) rename to api_mpprofile_pm;
  alter function public.api_mpprofile_pm(jsonb) set schema game;
end $$;
revoke all on function game.api_mpprofile_pm(jsonb) from public, anon, authenticated;

create or replace function public.api_mpProfile(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare r jsonb;
begin
  r := game.api_mpprofile_pm(a);
  return r || jsonb_build_object('gm', game.is_gm(game.mp_unpub(game.arg(a, 0))));
end $$;
select game.expose('api_mpprofile');
