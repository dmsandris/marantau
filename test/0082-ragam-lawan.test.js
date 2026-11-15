// Tide v60 (Ragam Bajak Laut Biasa + Fatrabbit)
// Fokus tes:
//   1. Empat kunci aditif di 0003 (noTalk, noLoot, wonMsg, softSinkMsg) -- TANPA kunci itu,
//      mekanik pertempuran harus sama dengan perilaku lama: kalah = gold -15% & muatan -50%.
//   2. Pemilih tokoh: gerbang, batas pemula, Hantu Kabut hanya malam, Fatrabbit 1x/hari.
//   3. Fatrabbit: kalah TIDAK mengurangi gold/muatan, dan Panji Kelinci tidak merusak
//      rupa Kedai yang dibeli pemain.
const assert = (c, m) => { if (!c) { console.error('GAGAL:', m); process.exit(1); } };

(async () => {
  const H = await require('./harness').create();

  // matikan fitur sampingan yang bisa memberi gold saat menang/kalah (Pesanan Harian dsb.)
  await H.sql(`insert into game.config(key, value) values ('HarianOpen','0'),('PacuOpen','0'),('KehormatanOpen','0'),('GotongOpen','0')
               on conflict (key) do update set value = excluded.value`);

  const BASE = { enemyLevel: 2, enemyName: 'uji', enemyMaxHp: 60, enemyHp: 60,
                 maxAmmo: 99, ammoRemaining: 99, round: 1, randomPirate: true };

  const pasang = (u, extra) => H.sql(
    `update game.player_location set city_id = 'sunda_empire', destination_city_id = 'joungjava',
       depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second',
       pending_encounter = $2::jsonb where player_id = $1`,
    [u.id, JSON.stringify(Object.assign({}, BASE, extra || {}))]);

  const gold = async (u) => (await H.sql(`select gold::float8 g from game.players where player_id = $1`, [u.id]))[0].g;
  const muatan = async (u) => (await H.sql(`select coalesce(sum(qty),0)::float8 q from game.inventory where player_id = $1`, [u.id]))[0].q;
  const beriMuatan = (u, q) => H.sql(`insert into game.inventory(player_id, item_id, qty, cost) values ($1,'beras',$2,$3)
    on conflict (player_id, item_id) do update set qty = $2, cost = $3`, [u.id, q, q * 20]);
  const kondisi = (u, c) => H.sql(`update game.ships set condition = $2 where player_id = $1`, [u.id, c]);
  const badges = (u, n) => H.sql(`update game.players set meta = $2::jsonb where player_id = $1`,
    [u.id, JSON.stringify({ u: Object.fromEntries(Array.from({ length: n }, (_, i) => ['a' + i, 1])) })]);

  // bertempur sampai selesai (maks 60 ronde)
  const sampaiHabis = async (u) => {
    for (let i = 0; i < 60; i++) {
      const r = await u.call('api_resolveCombat', ['fire']);
      if (!r.ongoing) return r;
    }
    throw new Error('pertempuran tidak pernah berakhir');
  };

  const mk = async (nama, arch) => {
    const u = await H.user(nama);
    await u.call('api_createCharacter', ['Kapten ' + nama, arch || 'merchant']);
    await H.sql(`update game.players set gold = 100000 where player_id = $1`, [u.id]);
    return u;
  };

  // =====================================================================
  // 1. PERILAKU LAMA TETAP: tanpa kunci baru, kalah = gold -15% & muatan -50%
  // =====================================================================
  {
    const u = await mk('lama');
    await beriMuatan(u, 100); await kondisi(u, 1);
    await pasang(u, { dmgTaken: 0.01 });            // musuh tahan: pemain pasti kalah
    const g0 = await gold(u);
    const r = await sampaiHabis(u);
    assert(r.result === 'sunk', 'tanpa softSink: kapal tenggelam (dapat ' + r.result + ')');
    const g1 = await gold(u);
    assert(Math.abs(g1 - Math.round(g0 * 0.85)) <= 2, 'gold dipotong 15%: ' + g0 + ' -> ' + g1);
    assert((await muatan(u)) === 50, 'muatan dipotong 50%: sisa ' + (await muatan(u)));
    assert(/tenggelam di bawah gempuran/.test(r.message), 'pesan kekalahan Bahasa Indonesia');
  }

  // pesan bos TIDAK berubah (tanpa noTalkMsg)
  {
    const u = await mk('bos');
    await pasang(u, { boss: 'ujibos' });
    await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /bos ini tidak bisa disuap atau diajak berunding/);
    await H.expectError(() => u.call('api_resolveCombat', ['negotiate']), /bos ini tidak bisa disuap atau diajak berunding/);
  }

  // =====================================================================
  // 2. KUNCI ADITIF
  // =====================================================================
  // noTalk: tolak suap & runding tanpa flag boss
  {
    const u = await mk('notalk');
    await pasang(u, { noTalk: true, noTalkMsg: 'Simpan koinmu.' });
    await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /Simpan koinmu/);
    await H.expectError(() => u.call('api_resolveCombat', ['negotiate']), /Simpan koinmu/);
    // tanpa noTalkMsg: pesan umum, dan TIDAK menyebut "bos"
    await pasang(u, { noTalk: true });
    const msg = await H.expectError(() => u.call('api_resolveCombat', ['bribe']), /tidak bisa disuap atau diajak berunding/);
    assert(!/bos ini/.test(msg), 'musuh non-bos tidak disebut "bos ini"');
  }

  // suap tetap berfungsi kalau noTalk tidak ada (perilaku lama)
  {
    const u = await mk('suap');
    await pasang(u, {});
    const r = await u.call('api_resolveCombat', ['bribe']);
    assert(r.result === 'bribed', 'tanpa noTalk, suap tetap bisa (dapat ' + r.result + ')');
  }

  // noLoot + wonMsg: menang tanpa jarahan gold, pakai teks sendiri
  {
    const u = await mk('noloot');
    await kondisi(u, 100);
    await pasang(u, { enemyHp: 1, enemyMaxHp: 60, noLoot: true, wonMsg: 'Palkanya kosong.' });
    const g0 = await gold(u);
    const r = await sampaiHabis(u);
    assert(r.result === 'won', 'menang (dapat ' + r.result + ')');
    assert((await gold(u)) === g0, 'noLoot: gold tidak bertambah (' + g0 + ' -> ' + (await gold(u)) + ')');
    assert(/Palkanya kosong\./.test(r.message), 'wonMsg dipakai');
    assert(!/kru menjarah/.test(r.message), 'teks jarahan bawaan tidak muncul');
  }

  // tanpa noLoot: jarahan tetap masuk (perilaku lama)
  {
    const u = await mk('loot');
    await kondisi(u, 100);
    await pasang(u, { enemyHp: 1, enemyMaxHp: 60 });
    const g0 = await gold(u);
    const r = await sampaiHabis(u);
    assert(r.result === 'won' && (await gold(u)) > g0, 'tanpa noLoot: jarahan tetap diberikan');
    assert(/kru menjarah/.test(r.message), 'teks jarahan bawaan muncul');
  }

  // softSinkMsg: teks sendiri, dan teks armada sekutu tidak muncul
  {
    const u = await mk('softmsg');
    await beriMuatan(u, 100); await kondisi(u, 1);
    await pasang(u, { dmgTaken: 0.01, softSink: true, softSinkMsg: 'Panji ini kupinjamkan.' });
    const g0 = await gold(u);
    const r = await sampaiHabis(u);
    assert(r.result === 'sunk', 'softSink tetap menghasilkan result sunk');
    assert(/Panji ini kupinjamkan\./.test(r.message), 'softSinkMsg dipakai');
    assert(!/Armada sekutu/.test(r.message), 'teks armada sekutu tidak muncul');
    assert((await gold(u)) === g0, 'softSink: gold utuh');
    assert((await muatan(u)) === 100, 'softSink: muatan utuh');
  }

  // softSink tanpa pesan sendiri: teks bawaan TIDAK berubah
  {
    const u = await mk('softbawaan');
    await kondisi(u, 1);
    await pasang(u, { dmgTaken: 0.01, softSink: true });
    const r = await sampaiHabis(u);
    assert(/Armada sekutu menarikmu keluar dari medan tempur/.test(r.message), 'teks softSink bawaan tetap sama');
  }

  // =====================================================================
  // 3. PEMILIH TOKOH
  // =====================================================================
  {
    const u = await mk('pemula');          // 0 Tanda Jasa
    const v = await mk('veteran'); await badges(v, 25);

    // gerbang mati -> encounter tidak punya kunci 'type'
    await H.sql(`update game.config set value = '0' where key = 'RagamLawanOpen'`);
    let e = (await H.sql(`select game.voy_roll_encounter($1, 'joungjava') e`, [v.id]))[0].e;
    assert(e === null || !('type' in e), 'gerbang mati: tidak ada kunci type');

    await H.sql(`insert into game.config(key,value) values ('RagamLawanOpen','1') on conflict (key) do update set value='1'`);

    const siang = !(await H.sql(`select game.fish_is_night() n`))[0].n;
    const dipilih = new Set();
    for (const kota of ['joungjava', 'bjorneo', 'skitraw', 'ikn', 'toogood', 'paradiso']) {
      for (let lv = 1; lv <= 5; lv++) {
        const p = (await H.sql(`select game.ragam_pick($1,$2,$3) p`, [v.id, kota, lv]))[0].p;
        if (p) dipilih.add(p);
        const q = (await H.sql(`select game.ragam_pick($1,$2,$3) p`, [u.id, kota, lv]))[0].p;
        if (q) {
          const row = (await H.sql(`select pemula from game.ragam_types where id = $1`, [q]))[0];
          assert(row.pemula, 'pemula hanya dapat tokoh pemula, dapat: ' + q);
          assert(q !== 'fatrabbit', 'pemain < 20 TJ tidak pernah bertemu Fatrabbit');
        }
      }
    }
    if (siang) assert(!dipilih.has('hantu_kabut'), 'Hantu Kabut tidak muncul siang');
    assert(dipilih.size >= 2, 'ada ragam tokoh yang terpilih (dapat ' + dipilih.size + ')');

    // Fatrabbit sekali per hari nyata
    await H.sql(`insert into game.fr_mark(player_id, met_at) values ($1, now())
                 on conflict (player_id) do update set met_at = now()`, [v.id]);
    assert((await H.sql(`select game.ragam_fat_ok($1) o`, [v.id]))[0].o === false, 'sudah bertemu hari ini -> tidak boleh lagi');
    await H.sql(`update game.fr_mark set met_at = now() - interval '2 days' where player_id = $1`, [v.id]);
    assert((await H.sql(`select game.ragam_fat_ok($1) o`, [v.id]))[0].o === true, 'hari berganti -> boleh lagi');
  }

  // =====================================================================
  // 4. FATRABBIT & PANJI KELINCI
  // =====================================================================
  {
    const u = await mk('fatlawan'); await badges(u, 25);
    // paksa Fatrabbit: sisakan hanya dia di tabel tokoh, peluang 1 dari 2
    await H.sql(`delete from game.ragam_types where id <> 'fatrabbit'`);
    await H.sql(`update game.ragam_types set langka = false where id = 'fatrabbit'`);
    await H.sql(`update game.config set value = '2' where key = 'RagamFatOdds'`);
    await H.sql(`delete from game.fr_mark where player_id = $1`, [u.id]);

    // rupa Kedai yang DIBELI pemain: harus tetap utuh sebelum & sesudah panji
    await H.sql(`insert into game.kd_owned(player_id, item_id, qty, source) values ($1,'panji_telinga_angin',1,'uji')
                 on conflict (player_id, item_id) do nothing`, [u.id]);
    await H.sql(`insert into game.kd_loadout(player_id, equipped) values ($1, '{"panji":"panji_telinga_angin"}'::jsonb)
                 on conflict (player_id) do update set equipped = '{"panji":"panji_telinga_angin"}'::jsonb`, [u.id]);
    const sebelum = (await H.sql(`select equipped from game.kd_loadout where player_id = $1`, [u.id]))[0].equipped;

    // Pemilihan tokoh DETERMINISTIK per (pemain, rute, siklus pasar): mengulang roll dengan
    // input yang sama selalu memberi hasil yang sama. Jadi garamnya yang digeser sampai
    // Fatrabbit terpilih -- ini setup tes, bukan mengandalkan kebetulan.
    let e = null;
    for (let i = 0; i < 80 && !e; i++) {
      await H.sql(`update game.config set value = $1 where key = 'RagamSalt'`, ['uji-' + i]);
      if ((await H.sql(`select game.ragam_pick($1,'joungjava',4) p`, [u.id]))[0].p !== 'fatrabbit') continue;
      const r = (await H.sql(`select game.voy_roll_encounter($1, 'joungjava') e`, [u.id]))[0].e;
      if (r && r.type === 'fatrabbit') e = r;
    }
    assert(e, 'Fatrabbit bisa terpilih');
    assert(e.noTalk === true && e.softSink === true && e.noLoot === true, 'flag Fatrabbit terpasang');
    assert(typeof e.hpFloor === 'number' && e.hpFloor > 0, 'hpFloorPct diubah ke hpFloor absolut: ' + e.hpFloor);
    assert(!('hpFloorPct' in e), 'hpFloorPct tidak ikut dikirim');
    assert(e.randomPirate === true, 'penanda randomPirate dipertahankan (dipakai 2 buku)');
    assert(typeof e.softSinkMsg === 'string' && typeof e.greet === 'string', 'teks Fatrabbit terbawa');

    // KALAH: gold & muatan utuh, panji terpasang
    await beriMuatan(u, 100); await kondisi(u, 1);
    await H.sql(`update game.player_location set city_id='sunda_empire', destination_city_id='joungjava',
      depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second',
      pending_encounter = $2::jsonb where player_id = $1`,
      [u.id, JSON.stringify(Object.assign({}, e, { dmgTaken: 0.01, maxAmmo: 99, ammoRemaining: 99 }))]);
    const g0 = await gold(u);
    const r = await sampaiHabis(u);
    assert(r.result === 'sunk', 'kalah dari Fatrabbit (dapat ' + r.result + ')');
    assert((await gold(u)) === g0, 'Fatrabbit tidak mengambil gold');
    assert((await muatan(u)) === 100, 'Fatrabbit tidak mengambil muatan');

    const m = (await H.sql(`select n, mark_at is not null ada from game.fr_mark where player_id = $1`, [u.id]))[0];
    assert(m.n === 1 && m.ada, 'tercatat: n=1 dan panji dipasang');

    const vis = (await H.sql(`select game.kd_visual($1) v`, [u.id]))[0].v;
    const now = (await H.sql(`select game.now_ms()::float8 t`))[0].t;
    assert(vis && typeof vis.kelinci === 'number', 'kd.kelinci ada dan berupa angka');
    assert(vis.kelinci > now, 'kd.kelinci berisi cap waktu kedaluwarsa di masa depan');
    assert(vis.panji === 'panji_telinga_angin', 'panji milik pemain TIDAK tergantikan');
    const sesudah = (await H.sql(`select equipped from game.kd_loadout where player_id = $1`, [u.id]))[0].equipped;
    assert(JSON.stringify(sesudah) === JSON.stringify(sebelum), 'kd_loadout tidak pernah ditulis fitur ini');

    // kedaluwarsa: panji hilang sendiri, tanpa pembersihan
    await H.sql(`update game.fr_mark set mark_at = now() - interval '4 hours' where player_id = $1`, [u.id]);
    const vis2 = (await H.sql(`select game.kd_visual($1) v`, [u.id]))[0].v;
    assert(!vis2 || !('kelinci' in vis2), 'setelah 1 hari game, kd.kelinci hilang sendiri');
    assert(vis2.panji === 'panji_telinga_angin', 'rupa pemain tetap utuh setelah panji habis');
    assert((await H.sql(`select n from game.fr_mark where player_id = $1`, [u.id]))[0].n === 1, 'hitungan tidak ikut hilang');

    // MENANG: panji dilepas, Panji Telinga Angin diberikan
    const w = await mk('fatmenang'); await badges(w, 25);
    await H.sql(`insert into game.fr_mark(player_id, n, mark_at) values ($1, 3, now())
                 on conflict (player_id) do update set n = 3, mark_at = now()`, [w.id]);
    await kondisi(w, 100);
    await H.sql(`update game.player_location set city_id='sunda_empire', destination_city_id='joungjava',
      depart_at = now() - interval '2 minutes', arrive_at = now() - interval '1 second',
      pending_encounter = $2::jsonb where player_id = $1`,
      [w.id, JSON.stringify(Object.assign({}, e, { enemyHp: 1, hpFloor: 0, maxAmmo: 99, ammoRemaining: 99 }))]);
    const rw = await sampaiHabis(w);
    assert(rw.result === 'won', 'menang lawan Fatrabbit (dapat ' + rw.result + ')');
    const mw = (await H.sql(`select n, won, mark_at from game.fr_mark where player_id = $1`, [w.id]))[0];
    assert(mw.won === true, 'tercatat pernah menang');
    assert(mw.mark_at === null, 'panji dilepas saat menang');
    assert(mw.n === 3, 'hitungan dilucuti tidak pernah turun');
    const punya = await H.sql(`select 1 from game.kd_owned where player_id = $1 and item_id = 'panji_telinga_angin'`, [w.id]);
    assert(punya.length === 1, 'Panji Telinga Angin diberikan');
    const visw = (await H.sql(`select game.kd_visual($1) v`, [w.id]))[0].v;
    assert(!visw || !('kelinci' in visw), 'panji kelinci hilang setelah menang');
  }

  console.log('0082 ragam lawan: semua lulus.');
})().catch((e) => { console.error(e); process.exit(1); });
