// Tide v72: riwayat chat Syahbandar pindah dari Dunia ke Dermaga; chat Dunia lain tidak tersentuh
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
const fs = require('fs'), path = require('path');
(async () => {
  const H = await require('./harness').create();
  const a = await H.user('dm_a'); await a.call('api_createCharacter', ['Kapten A', 'merchant']);
  await H.sql(`insert into game.mp_chat_channels(channel, last_id) values ('g', 12) on conflict (channel) do update set last_id = 12`);
  await H.sql(`insert into game.mp_chat(channel, id, msg) values
    ('g', 10, '{"id":10,"p":"sys","n":"Syahbandar","a":"","ts":1,"city":"","tx":"lama satu"}'),
    ('g', 11, '{"id":11,"p":"sys","n":"Syahbandar","a":"","ts":2,"city":"","tx":"lama dua"}'),
    ('g', 12, '{"id":12,"p":"sys","n":"Kabar Laut","a":"","ts":3,"city":"","tx":"tetap di dunia"}')`);
  const sql = fs.readFileSync(path.join(__dirname, '..', 'supabase', 'migrations', '0091-dermaga-syahbandar.sql'), 'utf8');
  await H.db.exec(sql); await H.db.exec(sql);   // aman diulang
  const g = await H.sql(`select msg ->> 'tx' tx from game.mp_chat where channel = 'g' order by id`);
  assert(g.length === 1 && g[0].tx === 'tetap di dunia', 'Dunia: hanya pesan lain tersisa ' + JSON.stringify(g));
  const news = await a.call('api_mgFishNews', []);
  assert(news.length === 2 && news[0].tx === 'lama satu' && news[1].tx === 'lama dua' && news[0].id < news[1].id, 'Dermaga memuat riwayat berurutan ' + JSON.stringify(news));
  const anon = await H.anon();
  await H.expectError(() => anon.call('api_mgFishNews', []), /AUTH_REQUIRED|permission/);
  console.log('DERMAGA SYAHBANDAR TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
