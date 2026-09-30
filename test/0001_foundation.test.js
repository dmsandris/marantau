const assert = require('assert');
(async () => {
  const H = await require('./harness').create();
  const a = await H.anon();
  const c = await a.call('api_getCities', []);
  assert.strictEqual(c.cities.length, 6); assert(c.cities[0].CityId && c.cities[0].TypeFlavor);
  const p = await a.call('api_ping', []); assert(p.ok);
  const day = await H.sql('select game.game_day() d, game.minutes_to_next_day() m'); console.log('day', day[0]);
  const s = await H.sql("select game.seeded('abc', 1) x, game.seeded('abc', 2) y"); console.log(s[0]);
  const u = await H.user('nina');
  const me = await H.sql(`select set_config('request.jwt.claim.sub', $1, false), set_config('request.jwt.claim.email', $2, false)`, [u.id, u.email]);
  const r = await H.sql('select (game.me()).username');
  assert.strictEqual(r[0].username, 'nina');
  console.log('FOUNDATION OK');
})().catch(e => { console.error(e); process.exit(1); });
