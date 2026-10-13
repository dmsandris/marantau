// Realtime chat: izin baca kanal siaran (chat dunia, chat pelabuhan, kanal pribadi player:<pub>)
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const a = await H.user('rt_a'); await a.call('api_createCharacter', ['Kapten A', 'merchant']);
  const b = await H.user('rt_b'); await b.call('api_createCharacter', ['Kapten B', 'pirate']);
  const pa = (await a.call('api_mpPulse', [{}])).mePub, pb = (await b.call('api_mpPulse', [{}])).mePub;
  assert(pa && pb && pa !== pb, 'pub tiap pemain');
  const check = async (uid, topic) => (await H.sql(`with s as (select set_config('request.jwt.claim.sub', $1, false)) select public.mt_rt_can_read($2) ok from s`, [uid || '', topic]))[0].ok;
  assert(await check(a.id, 'chat:global'), 'chat dunia');
  assert(await check(a.id, 'chat:city:sunda_empire'), 'chat pelabuhan');
  assert(await check(a.id, 'player:' + pa), 'kanal pribadi sendiri');
  assert(!(await check(a.id, 'player:' + pb)), 'tidak boleh mendengar kanal pribadi orang lain');
  assert(!(await check(a.id, 'lain:apa')), 'topik lain ditolak');
  assert(!(await check('', 'chat:global')), 'tanpa login ditolak');
  await H.sql(`select set_config('request.jwt.claim.sub', '', false)`);
  // Pesan chat menyiarkan ke topik yang benar
  await a.call('api_mpChat', ['global', 'Halo dunia']);
  await b.call('api_mpChat', ['city', 'Halo pelabuhan']);
  const sent = await H.sql(`select topic, event, private from realtime.sent order by id`);
  assert(sent.some(s => s.topic === 'chat:global' && s.event === 'chat' && s.private), 'siaran dunia ' + JSON.stringify(sent));
  assert(sent.some(s => /^chat:city:/.test(s.topic) && s.event === 'chat'), 'siaran pelabuhan');
  console.log('REALTIME CHAT TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
