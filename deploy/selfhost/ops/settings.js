// Pengaturan Panel Ops yang diubah dari layar (bukan dari .env): kunci Gemini, jadwal Penjaga, senyap Telegram.
// Disimpan di volume data (/data/ops-settings.json, chmod 600). Kunci API tidak pernah dikirim balik utuh ke browser.
'use strict';
const fs = require('fs');
const path = require('path');

const DEFAULTS = {
  gemini: { key: '', model: 'gemini-2.5-flash' },
  penjaga: {
    auto: true,          // pindai aturan otomatis
    intervalMenit: 60,   // jarak pindai otomatis
    jendelaJam: 24,      // rentang catatan yang dinilai
    ai: 'auto',          // auto = AI ikut menilai bila ada temuan sedang/tinggi; manual = hanya lewat tombol; off
    aiJedaJam: 6,        // jarak minimal dua penilaian AI otomatis
    samarkan: true,      // nama kapten diganti kode (K01, K02…) sebelum dikirim ke Google
    alert: 'tinggi',     // tingkat terendah yang dikirim ke Telegram: tinggi / sedang / off
  },
  telegram: { senyapSampai: 0, laporanJam: 7 },
};

function merge(base, over) {
  const out = Array.isArray(base) ? [...base] : { ...base };
  for (const [k, v] of Object.entries(over || {})) {
    if (v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object') out[k] = merge(base[k], v);
    else if (k in base) out[k] = v;
  }
  return out;
}

function create(dataDir) {
  const FILE = path.join(dataDir, 'ops-settings.json');
  let s = DEFAULTS;
  try { s = merge(DEFAULTS, JSON.parse(fs.readFileSync(FILE, 'utf8'))); } catch {}
  if (process.env.OPS_GEMINI_KEY && !s.gemini.key) s = merge(s, { gemini: { key: process.env.OPS_GEMINI_KEY } });

  function save() {
    try { fs.writeFileSync(FILE + '.tmp', JSON.stringify(s, null, 1), { mode: 0o600 }); fs.renameSync(FILE + '.tmp', FILE); }
    catch (e) { console.error('simpan pengaturan:', e.message); }
  }
  const clamp = (v, lo, hi, d) => { v = +v; return Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : d; };

  return {
    get: () => s,
    // Versi aman untuk browser: kunci hanya 4 huruf terakhir.
    publik() {
      const k = s.gemini.key;
      return { gemini: { ada: !!k, akhir: k ? k.slice(-4) : '', model: s.gemini.model }, penjaga: s.penjaga, telegram: s.telegram };
    },
    // Terima perubahan dari browser / bot. Nilai dibersihkan satu per satu.
    ubah(b = {}) {
      const g = b.gemini || {}, p = b.penjaga || {}, t = b.telegram || {};
      const n = merge(s, {});
      if (typeof g.key === 'string') n.gemini.key = g.key.replace(/\s+/g, '').slice(0, 200);
      if (g.hapus === true) n.gemini.key = '';
      if (typeof g.model === 'string' && /^[a-z0-9.\-]{3,60}$/i.test(g.model.replace(/^models\//, ''))) n.gemini.model = g.model.replace(/^models\//, '');
      if ('auto' in p) n.penjaga.auto = !!p.auto;
      if ('intervalMenit' in p) n.penjaga.intervalMenit = clamp(p.intervalMenit, 15, 1440, 60);
      if ('jendelaJam' in p) n.penjaga.jendelaJam = clamp(p.jendelaJam, 1, 168, 24);
      if (['auto', 'manual', 'off'].includes(p.ai)) n.penjaga.ai = p.ai;
      if ('aiJedaJam' in p) n.penjaga.aiJedaJam = clamp(p.aiJedaJam, 1, 48, 6);
      if ('samarkan' in p) n.penjaga.samarkan = !!p.samarkan;
      if (['tinggi', 'sedang', 'off'].includes(p.alert)) n.penjaga.alert = p.alert;
      if ('senyapSampai' in t) n.telegram.senyapSampai = Math.max(0, +t.senyapSampai || 0);
      if ('laporanJam' in t) n.telegram.laporanJam = clamp(t.laporanJam, 0, 23, 7);
      s = n; save();
      return this.publik();
    },
  };
}

module.exports = { create };
