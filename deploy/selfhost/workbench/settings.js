// Pengaturan Workbench yang diubah dari layar: profil AI (banyak), peran -> profil, GitHub, batas, override agent.
// Disimpan di volume data (/data/wb-settings.json, chmod 600). Kunci API tidak pernah dikirim balik utuh ke browser.
'use strict';
const fs = require('fs');
const path = require('path');

const PROVIDERS = ['anthropic', 'gemini', 'openai'];
// Peran = fungsi kerja. Tiap agent punya satu peran bawaan; tiap peran dipetakan ke satu profil AI.
const ROLES = [
  { id: 'orkestrator', label: 'Orkestrator', hint: 'Manager: menyusun rencana, mereview hasil tim, menulis laporan akhir.' },
  { id: 'coder', label: 'Coder', hint: 'Backend (SQL) dan Frontend (HTML/JS).' },
  { id: 'cerita', label: 'Cerita', hint: 'Lore, quest, dokumentasi: tulisan panjang yang rapi.' },
  { id: 'desain', label: 'Desain', hint: 'Spesifikasi tampilan, UX, aset teks.' },
  { id: 'gambar', label: 'Gambar', hint: 'Pembuat gambar (alat "image"). Harus model yang bisa membuat gambar.' },
  { id: 'analis', label: 'Analis', hint: 'Ekonomi, QA, DevOps, Live-Ops: membaca data lalu menyimpulkan.' },
];

const DEFAULTS = {
  profiles: [], // { id, label, provider, baseUrl, model, key }
  roles: { orkestrator: '', coder: '', cerita: '', desain: '', gambar: '', analis: '' },
  github: { repo: 'dmsandris/marantau', base: 'main', token: '' }, // token = tulis PR (Contents + Pull requests)
  limits: { panggilanPerTugas: 60, maksToken: 6000, revisi: 2, langkahAlat: 6, jedaRencana: true, prDraft: true },
  agents: {}, // override per agent: { aktif, profil, persona }
};

function merge(base, over) {
  const out = Array.isArray(base) ? [...base] : { ...base };
  for (const [k, v] of Object.entries(over || {})) {
    if (v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object' && !Array.isArray(base[k])) out[k] = merge(base[k], v);
    else if (k in base) out[k] = v;
  }
  return out;
}
const clamp = (v, lo, hi, d) => { v = +v; return Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.round(v))) : d; };
const slug = s => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 32);

// Penyedia berformat OpenAI (chat/completions). Isi Base URL otomatis; kunci dan model tetap dari pemilik.
const PRESETS = [
  { id: 'openrouter', label: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1', contoh: 'anthropic/claude-sonnet-4.5' },
  { id: 'groq', label: 'Groq', baseUrl: 'https://api.groq.com/openai/v1', contoh: 'llama-3.3-70b-versatile' },
  { id: 'cloudflare', label: 'Cloudflare Workers AI', baseUrl: 'https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/v1', contoh: '@cf/meta/llama-3.3-70b-instruct-fp8-fast', butuhAkun: true },
  { id: 'together', label: 'Together AI', baseUrl: 'https://api.together.xyz/v1', contoh: 'meta-llama/Llama-3.3-70B-Instruct-Turbo' },
  { id: 'mistral', label: 'Mistral', baseUrl: 'https://api.mistral.ai/v1', contoh: 'mistral-large-latest' },
  { id: 'deepseek', label: 'DeepSeek', baseUrl: 'https://api.deepseek.com', contoh: 'deepseek-chat' },
  { id: 'xai', label: 'xAI (Grok)', baseUrl: 'https://api.x.ai/v1', contoh: 'grok-4' },
  { id: 'fireworks', label: 'Fireworks AI', baseUrl: 'https://api.fireworks.ai/inference/v1', contoh: 'accounts/fireworks/models/llama-v3p3-70b-instruct' },
  { id: 'cerebras', label: 'Cerebras', baseUrl: 'https://api.cerebras.ai/v1', contoh: 'llama-3.3-70b' },
];

function create(dataDir, env = process.env) {
  const FILE = path.join(dataDir, 'wb-settings.json');
  let s = merge(DEFAULTS, {});
  try { s = { ...s, ...JSON.parse(fs.readFileSync(FILE, 'utf8')) }; s.limits = merge(DEFAULTS.limits, s.limits); s.roles = merge(DEFAULTS.roles, s.roles); s.github = merge(DEFAULTS.github, s.github); } catch {}
  if (env.WB_GH_TOKEN && !s.github.token) s.github.token = env.WB_GH_TOKEN;
  if (env.WB_GH_REPO) s.github.repo = env.WB_GH_REPO;

  function save() {
    try { fs.mkdirSync(dataDir, { recursive: true }); fs.writeFileSync(FILE + '.tmp', JSON.stringify(s, null, 1), { mode: 0o600 }); fs.renameSync(FILE + '.tmp', FILE); }
    catch (e) { console.error('simpan pengaturan:', e.message); }
  }
  const tail = k => (k ? k.slice(-4) : '');

  const api = {
    get: () => s,
    profile: id => s.profiles.find(p => p.id === id) || null,
    // Profil untuk satu peran. Peran kosong -> pakai orkestrator -> profil pertama.
    forRole(role) {
      let id = s.roles[role];
      if (!id && role !== 'gambar') id = s.roles.orkestrator || (s.profiles[0] && s.profiles[0].id);
      return id ? api.profile(id) : null;
    },
    publik() {
      return {
        providers: PROVIDERS, presets: PRESETS, roleList: ROLES, roles: s.roles, limits: s.limits,
        profiles: s.profiles.map(p => ({ id: p.id, label: p.label, provider: p.provider, baseUrl: p.baseUrl || '', model: p.model, ada: !!p.key, akhir: tail(p.key) })),
        github: { repo: s.github.repo, base: s.github.base, ada: !!s.github.token, akhir: tail(s.github.token) },
        agents: s.agents,
      };
    },
    // Terima perubahan dari browser. Nilai dibersihkan satu per satu.
    ubah(b = {}) {
      const n = merge(s, {});
      n.profiles = s.profiles.map(p => ({ ...p }));
      if (Array.isArray(b.profiles)) {
        const out = [];
        for (const p of b.profiles.slice(0, 12)) {
          if (!p || typeof p !== 'object') continue;
          const id = slug(p.id || p.label);
          if (!id) continue;
          const old = s.profiles.find(x => x.id === id);
          const provider = PROVIDERS.includes(p.provider) ? p.provider : 'anthropic';
          let baseUrl = String(p.baseUrl || '').trim().replace(/\/+$/, '');
          if (baseUrl && !/^https:\/\/[a-z0-9.\-]+(:\d+)?(\/[\w.\-\/]*)?$/i.test(baseUrl)) baseUrl = '';
          const model = String(p.model || '').trim().replace(/^models\//, '');
          if (model && !/^[a-z0-9@][a-z0-9._:@\-\/]{1,120}$/i.test(model)) continue;
          let key = old ? old.key : '';
          if (typeof p.key === 'string' && p.key.trim()) key = p.key.replace(/\s+/g, '').slice(0, 300);
          if (p.hapusKunci === true) key = '';
          out.push({ id, label: String(p.label || id).slice(0, 40), provider, baseUrl, model, key });
        }
        n.profiles = out;
        const ids = new Set(out.map(p => p.id));
        for (const r of Object.keys(n.roles)) if (n.roles[r] && !ids.has(n.roles[r])) n.roles[r] = '';
      }
      if (b.roles && typeof b.roles === 'object') {
        const ids = new Set(n.profiles.map(p => p.id));
        for (const r of ROLES) if (r.id in b.roles) n.roles[r.id] = ids.has(b.roles[r.id]) ? b.roles[r.id] : '';
      }
      const g = b.github || {};
      if (typeof g.repo === 'string' && /^[\w.\-]+\/[\w.\-]+$/.test(g.repo.trim())) n.github.repo = g.repo.trim();
      if (typeof g.base === 'string' && /^[\w.\-\/]{1,60}$/.test(g.base.trim())) n.github.base = g.base.trim();
      if (typeof g.token === 'string' && g.token.trim()) n.github.token = g.token.replace(/\s+/g, '').slice(0, 300);
      if (g.hapusToken === true) n.github.token = '';
      const l = b.limits || {};
      if ('panggilanPerTugas' in l) n.limits.panggilanPerTugas = clamp(l.panggilanPerTugas, 5, 200, 60);
      if ('maksToken' in l) n.limits.maksToken = clamp(l.maksToken, 500, 16000, 6000);
      if ('revisi' in l) n.limits.revisi = clamp(l.revisi, 0, 4, 2);
      if ('langkahAlat' in l) n.limits.langkahAlat = clamp(l.langkahAlat, 0, 12, 6);
      if ('jedaRencana' in l) n.limits.jedaRencana = !!l.jedaRencana;
      if ('prDraft' in l) n.limits.prDraft = !!l.prDraft;
      if (b.agents && typeof b.agents === 'object') {
        const ids = new Set(n.profiles.map(p => p.id));
        for (const [id, o] of Object.entries(b.agents)) {
          if (!/^[a-z0-9-]{2,24}$/.test(id) || !o || typeof o !== 'object') continue;
          const cur = { ...(n.agents[id] || {}) };
          if ('aktif' in o) cur.aktif = !!o.aktif;
          if ('profil' in o) cur.profil = ids.has(o.profil) ? o.profil : '';
          if (typeof o.persona === 'string') cur.persona = o.persona.slice(0, 20000);
          n.agents[id] = cur;
        }
      }
      s = n; save();
      return api.publik();
    },
  };
  return api;
}

module.exports = { create, ROLES, PROVIDERS, PRESETS };
