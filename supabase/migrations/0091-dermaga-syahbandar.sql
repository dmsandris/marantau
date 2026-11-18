-- Tide v72: chat Syahbandar (kabar tangkapan ikan) pindah dari tab Dunia ke menu Dermaga.
-- Kanal 'd' di game.mp_chat. Tanpa siaran Realtime dan tanpa lencana. Aman diulang.

-- Riwayat lama: pindahkan pesan Syahbandar dari kanal dunia ('g') ke kanal 'd' (nomor urut baru, urutan tetap)
do $$
declare r record; v_mid int;
begin
  for r in select channel, id, msg from game.mp_chat
           where channel = 'g' and msg ->> 'p' = 'sys' and msg ->> 'n' = 'Syahbandar' order by id loop
    insert into game.mp_chat_channels as ch (channel, last_id) values ('d', 1)
    on conflict (channel) do update set last_id = ch.last_id + 1 returning last_id into v_mid;
    insert into game.mp_chat(channel, id, msg) values ('d', v_mid, jsonb_set(r.msg, '{id}', to_jsonb(v_mid)));
    delete from game.mp_chat where channel = r.channel and id = r.id;
  end loop;
  delete from game.mp_chat where channel = 'd' and id <= (select last_id from game.mp_chat_channels where channel = 'd') - 60;
end $$;

-- Dibaca menu Dermaga: 30 pesan terakhir, terlama dulu
create or replace function public.api_mgFishNews(a jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare v_id uuid := game.uid();
begin
  if v_id is null then raise exception 'AUTH_REQUIRED'; end if;
  return coalesce((select jsonb_agg(m.msg order by m.id)
    from (select * from game.mp_chat where channel = 'd' order by id desc limit 30) m), '[]'::jsonb);
end $$;
select game.expose('api_mgfishnews');
