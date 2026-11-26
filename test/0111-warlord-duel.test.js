// 0111 Meriam Warlord berlaku di Duel Lambung: fighter membawa penanda, lb_power mengalikan dm.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };
(async () => {
  const H = await require('./harness').create();
  const one = async (q, p) => (await H.sql(q, p))[0];
  const a = await H.user('wdkapten'), b = await H.user('wdbiasa');
  await a.call('api_createCharacter', ['Duel Panglima', 'merchant']);
  await b.call('api_createCharacter', ['Duel Biasa', 'merchant']);
  for (const [u, pub] of [[a, 'pa'], [b, 'pb']])
    await H.sql(`insert into game.mp_presence(player_id, pub, f, s) values ($1, $2, '{}'::jsonb, '{}'::jsonb) on conflict (player_id) do update set pub = $2`, [u.id, pub]);
  const fighter = async (u) => (await one('select game.mp_fighter($1) f', [u.id])).f;
  const power = async (f) => (await one('select game.lb_power($1::jsonb) p', [JSON.stringify(f)])).p;

  const fb0 = await fighter(b);
  assert(fb0.wlCannons === undefined, 'pemain biasa tanpa penanda');
  const base = Number((await power(fb0)).dm);

  // Meriam Warlord
  await H.sql(`insert into game.mk_warlord(player_id, grup) values ($1, 'cannons')`, [a.id]);
  const fa = await fighter(a);
  assert(fa.wlCannons === true, 'fighter pemilik Meriam Warlord membawa wlCannons');
  const fSama = Object.assign({}, fa); // statistik sama persis, hanya penanda yang dibedakan
  const tanpa = Number((await power(Object.assign({}, fa, { wlCannons: false }))).dm);
  const dengan = Number((await power(fa)).dm);
  assert(Math.abs(dengan - tanpa * 5) < 0.01, 'dm x5 untuk pemilik Meriam Warlord: ' + tanpa + ' -> ' + dengan);
  assert(Math.abs(Number((await power(fb0)).dm) - base) < 1e-9, 'pemain lain tidak berubah');

  assert(Number((await power(fa)).src.wl) === 5, 'src.wl menandai pengali untuk tampilan');

  // kenop keseimbangan
  await H.sql(`update game.config set value = '2' where key = 'DuelMeriamWarlordKali'`);
  const dua = Number((await power(fa)).dm);
  assert(Math.abs(dua - tanpa * 2) < 0.01, 'kenop DuelMeriamWarlordKali=2: ' + dua);
  await H.sql(`update game.config set value = '5' where key = 'DuelMeriamWarlordKali'`);

  // masuk ke keadaan duel (lb_ship0) dan ke tantangan sungguhan
  const s0 = await one(`select game.lb_ship0($1::jsonb, 0, 0, 0) s`, [JSON.stringify(fa)]);
  assert(Math.abs(Number(s0.s.dm) - dengan) < 0.01, 'lb_ship0 membawa dm Warlord');

  // HP duel tetap pagar Tier V (0078) dan damage tembakan nyata lebih besar
  assert(Number(fa.maxHp) === Number(fb0.maxHp) || fa.tier >= 5, 'HP duel tidak naik karena Warlord');
  let sumA = 0, sumB = 0; const N = 400;
  for (let i = 0; i < N; i++) {
    sumA += Number((await one(`select (game.lb_volley(0,0,0, 100,0, 1, 'ball', 100, $1, 1, 2.5)->>'hull')::float8 h`, [dengan])).h);
    sumB += Number((await one(`select (game.lb_volley(0,0,0, 100,0, 1, 'ball', 100, $1, 1, 2.5)->>'hull')::float8 h`, [tanpa])).h);
  }
  assert(sumB > 0 && sumA / sumB > 3.5 && sumA / sumB < 6.5, 'salvo nyata ~x5: ' + (sumA / sumB).toFixed(2));

  console.log('0111 warlord duel: semua lulus');
})().catch((e) => { console.error(e); process.exit(1); });
