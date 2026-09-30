// Penampilan kapten v2: field baru tersimpan, nilai liar dibersihkan, data lama tetap valid.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const u = await H.user('gaya'); 
  const face = { fem: 0, skin: 7, hair: 9, hairStyle: 13, facial: 7, eyes: 4, iris: 3, brows: 3, head: 'plumed', outfit: 'jas_kapten', cloth: 5,
    eye: 'patch', ear: 'hoop2', neck: 'medallion', mark: 'scar_eye', item: 'parrot', seed: 1234, junk: '<script>' };
  await u.call('api_createCharacter', ['Kapten Gaya', 'pirate', face]);
  let ap = (await H.sql('select appearance from game.players where player_id = $1', [u.id]))[0].appearance;
  for (const k of Object.keys(face)) if (k !== 'junk') assert(ap[k] === face[k], 'tersimpan ' + k + ': ' + JSON.stringify(ap[k]));
  assert(!('junk' in ap), 'field asing dibuang');
  await u.call('api_saveAppearance', [{ fem: 1, skin: 99, hair: -3, hairStyle: 40, facial: 5, head: 'topi-aneh', outfit: 'bikini', eye: 'laser', item: 'naga', mark: 'freckles', iris: 9 }]);
  ap = (await H.sql('select appearance from game.players where player_id = $1', [u.id]))[0].appearance;
  assert(ap.skin === 7 && ap.hair === 0 && ap.hairStyle === 13 && ap.facial === 0 && ap.head === 'arch' && ap.outfit === 'arch' && ap.eye === 'arch' && ap.item === 'arch' && ap.mark === 'freckles' && ap.iris === 5, 'dibersihkan ' + JSON.stringify(ap));
  await u.call('api_saveAppearance', [{ fem: 0, skin: 2, hair: 1, hairStyle: 3, facial: 2, head: 'hood', eyes: 1, seed: 7 }]);
  ap = (await H.sql('select appearance from game.players where player_id = $1', [u.id]))[0].appearance;
  assert(ap.head === 'tudung' && ap.outfit === 'arch' && ap.mark === 'none' && ap.hairStyle === 3, 'data v1 tetap valid ' + JSON.stringify(ap));
  console.log('APPEARANCE V2 TESTS PASSED');
})().catch(e => { console.error(e); process.exit(1); });
