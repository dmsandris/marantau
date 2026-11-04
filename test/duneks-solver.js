// Pemeriksa & solver Tata Gudang (mode susun) untuk tes 0065.
// Aturan harus sama dengan game.dn_check_susun (0065-duneks.sql) dan GudangGames.html.
// Koordinat: y = 0 baris bawah, x = w-1 kolom dekat pintu. Putaran r: (x,y) -> (y,-x), lalu digeser ke 0.
function rot(shape, r) {
  let c = shape.map(p => [p[0], p[1]]);
  for (let i = 0; i < ((r % 4) + 4) % 4; i++) c = c.map(([x, y]) => [y, -x]);
  const mx = Math.min(...c.map(p => p[0])), my = Math.min(...c.map(p => p[1]));
  return c.map(([x, y]) => [x - mx, y - my]);
}
function key(c) { return c.map(p => p.join(',')).sort().join(';'); }
function rots(shape) {
  const seen = {}, out = [];
  for (let r = 0; r < 4; r++) { const c = rot(shape, r), k = key(c); if (!seen[k]) { seen[k] = 1; out.push({ r, c }); } }
  return out;
}

/** Periksa susunan lengkap. place: { id: {x, y, r} } -> { ok, why } */
function check(L, place) {
  const W = L.w, H = L.h, R = L.rules || [], grid = {}, items = {};
  for (const it of L.items) items[it.id] = it;
  const tag = (id, t) => (items[id].tags || []).indexOf(t) >= 0;
  for (const it of L.items) {
    const p = place[it.id]; if (!p) return { ok: false, why: 'belum' };
    let near = false;
    for (const [dx, dy] of rot(it.shape, p.r || 0)) {
      const x = p.x + dx, y = p.y + dy;
      if (x < 0 || y < 0 || x >= W || y >= H) return { ok: false, why: 'luar' };
      if (grid[x + ',' + y]) return { ok: false, why: 'tumpang' };
      grid[x + ',' + y] = it.id;
      if (x === W - 1) near = true;
    }
    if (R.includes('besok') && tag(it.id, 'besok') && !near) return { ok: false, why: 'besok' };
  }
  for (const k in grid) {
    const [x, y] = k.split(',').map(Number), id = grid[k], below = grid[x + ',' + (y - 1)], above = grid[x + ',' + (y + 1)];
    if (R.includes('berat') && tag(id, 'berat') && y > 0) return { ok: false, why: 'berat' };
    if (y > 0 && !below) return { ok: false, why: 'melayang' };
    if (R.includes('basah') && tag(id, 'basah') && below && below !== id && tag(below, 'kain')) return { ok: false, why: 'basah' };
    if (R.includes('rapuh') && tag(id, 'rapuh') && above && above !== id) return { ok: false, why: 'rapuh' };
  }
  return { ok: true };
}

/** Solver scan (bawah-kiri ke atas-kanan). Item identik dikelompokkan. -> { count, first, nodes } */
function solve(L, limit) {
  limit = limit || 1;
  const W = L.w, H = L.h, R = L.rules || [];
  const total = L.items.reduce((s, it) => s + it.shape.length, 0);
  let holes = W * H - total;
  const groups = {};
  for (const it of L.items) {
    const k = (it.k || '') + '|' + JSON.stringify(it.shape) + '|' + (it.tags || []).join();
    (groups[k] = groups[k] || { it, ids: [] }).ids.push(it.id);
  }
  const G = Object.values(groups).map(g => ({
    tags: g.it.tags || [], left: g.ids.length, ids: g.ids,
    opts: rots(g.it.shape).map(({ r, c }) => { const s = c.slice().sort((a, b) => a[1] - b[1] || a[0] - b[0]); return { r, c, ax: s[0][0], ay: s[0][1] }; })
  }));
  const grid = new Array(W * H).fill(null); // null = belum, 0 = lubang, {g,id} = peti
  const place = {}; let count = 0, first = null, nodes = 0;
  const has = (g, t) => g.tags.indexOf(t) >= 0;
  function rec(pos) {
    if (count >= limit || nodes > 5e7) return;
    while (pos < W * H && grid[pos] !== null) pos++;
    if (pos === W * H) {
      if (G.every(g => g.left === 0) && check(L, place).ok) { count++; if (!first) first = JSON.parse(JSON.stringify(place)); }
      return;
    }
    nodes++;
    const x = pos % W, y = Math.floor(pos / W);
    for (const g of G) {
      if (!g.left) continue;
      for (const o of g.opts) {
        const ox = x - o.ax, oy = y - o.ay; let ok = true;
        for (const [dx, dy] of o.c) { const X = ox + dx, Y = oy + dy; if (X < 0 || X >= W || Y < 0 || Y >= H || grid[Y * W + X] !== null) { ok = false; break; } }
        if (!ok) continue;
        if (R.includes('berat') && has(g, 'berat') && o.c.some(([, dy]) => oy + dy > 0)) continue;
        if (R.includes('besok') && has(g, 'besok') && !o.c.some(([dx]) => ox + dx === W - 1)) continue;
        let bad = false;
        for (const [dx, dy] of o.c) {
          const X = ox + dx, Y = oy + dy; if (Y === 0) continue;
          if (o.c.some(([ex, ey]) => ex === dx && ey === dy - 1)) continue;
          const b = grid[(Y - 1) * W + X];
          if (b === 0) { bad = true; break; }
          if (b && b.g && R.includes('rapuh') && has(b.g, 'rapuh')) { bad = true; break; }
          if (b && b.g && R.includes('basah') && has(g, 'basah') && has(b.g, 'kain')) { bad = true; break; }
        }
        if (bad) continue;
        const id = g.ids[g.ids.length - g.left], cell = { g, id };
        for (const [dx, dy] of o.c) grid[(oy + dy) * W + ox + dx] = cell;
        g.left--; place[id] = { x: ox, y: oy, r: o.r };
        rec(pos + 1);
        g.left++; delete place[id];
        for (const [dx, dy] of o.c) grid[(oy + dy) * W + ox + dx] = null;
        if (count >= limit) return;
      }
    }
    if (holes > 0) { holes--; grid[pos] = 0; rec(pos + 1); grid[pos] = null; holes++; }
  }
  rec(0);
  return { count, first, nodes };
}

module.exports = { rot, rots, check, solve };
