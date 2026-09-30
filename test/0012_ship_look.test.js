// Tampilan kapal: kustomisasi + tahap visual dari upgrade + terlihat pemain lain
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const a = await H.user('lambung'); await a.call('api_createCharacter', ['Kapten Lambung', 'pirate']);
  let s = await a.call('api_getGameState', [null]);
  assert(s.shipVisual && s.shipVisual.look.emblem === 'skull' && s.shipVisual.look.shape === 'swallow', 'bawaan pirate');
  assert(JSON.stringify(s.shipVisual.up) === JSON.stringify({ cargo: 0, speed: 0, cannons: 0, condition: 0 }), 'up awal 0');
  const r = await a.call('api_saveShipLook', [{ hull: '#1F3A5A', flag: '#2a9d8f', shape: 'long', emblem: 'star', sail: '#fbfaf5' }, '  Bintang   Timur ']);
  assert(r.visual.look.hull === '#1f3a5a' && r.visual.look.shape === 'long' && r.visual.name === 'Bintang Timur', 'simpan ' + JSON.stringify(r.visual));
  assert(r.ship.ShipName === 'Bintang Timur', 'nama kapal');
  for (const [bad, re] of [[[{ hull: 'blue' }], /Warna tidak valid/], [[{ shape: 'kotak' }], /Bentuk bendera/], [[{ emblem: 'naga' }], /Lambang/],
    [[{}, 'ab'], /3-24/], [[{}, 'x'.repeat(25)], /3-24/], [[{}, 'Kapal<b>'], /hanya boleh/]]) await H.expectError(() => a.call('api_saveShipLook', bad), re);
  await H.sql(`update game.players set gold = 999999 where player_id = $1`, [a.id]);
  for (let i = 0; i < 3; i++) await a.call('api_shipUpgrade', ['speed']);
  const st = await a.call('api_getShipState', []);
  assert(st.visual.up.speed === 3 && st.visual.look.flag === '#2a9d8f', 'up speed 3 ' + JSON.stringify(st.visual));
  // kapten lain melihat tampilan kapal lewat pulse
  const b = await H.user('pengamat'); await b.call('api_createCharacter', ['Kapten Pengamat', 'merchant']);
  await b.call('api_getGameState', [null]); await a.call('api_getGameState', [null]);
  const p = await b.call('api_mpPulse', []);
  const other = p.here.filter(x => x.n === 'Kapten Lambung')[0];
  assert(other && other.s && other.s.look.hull === '#1f3a5a' && other.s.up.speed === 3 && other.s.name === 'Bintang Timur', 'presence ' + JSON.stringify(p.here));
  const anon = await H.anon();
  await H.expectError(() => anon.call('api_saveShipLook', [{}]), /AUTH_REQUIRED|permission/);
  console.log('SHIP LOOK TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
