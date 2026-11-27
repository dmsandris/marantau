// Gerbang AI: satu antarmuka untuk Anthropic, Gemini, dan OpenAI/kompatibel. Kunci hanya dibaca dari profil di server.
'use strict';

const URLS = {
  anthropic: (process.env.WB_ANTHROPIC_URL || 'https://api.anthropic.com').replace(/\/+$/, ''),
  gemini: (process.env.WB_GEMINI_URL || 'https://generativelanguage.googleapis.com').replace(/\/+$/, ''),
  openai: (process.env.WB_OPENAI_URL || 'https://api.openai.com/v1').replace(/\/+$/, ''),
};
const TIMEOUT_MS = +(process.env.WB_AI_TIMEOUT_MS || 150000);

function scrub(text, key) {
  let t = String(text || '');
  if (key) t = t.split(key).join('[kunci]');
  return t.replace(/(sk-[A-Za-z0-9_\-]{12,}|AIza[A-Za-z0-9_\-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})/g, '[kunci]').slice(0, 600);
}

async function post(url, headers, body, key) {
  let last;
  for (let i = 0; i < 2; i++) {
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body), signal: AbortSignal.timeout(TIMEOUT_MS) });
      const txt = await r.text();
      let j; try { j = JSON.parse(txt); } catch { j = null; }
      if (r.ok && j) return j;
      const msg = (j && (j.error && (j.error.message || j.error) || j.message)) || txt;
      last = new Error(`AI ${r.status}: ${scrub(typeof msg === 'string' ? msg : JSON.stringify(msg), key)}`);
      if (r.status !== 429 && r.status < 500) throw last;
    } catch (e) {
      if (e === last) { if (i === 1 || !/AI (429|5\d\d)/.test(e.message)) throw e; }
      else { last = new Error('AI tidak terjangkau: ' + scrub(e.message, key)); if (i === 1) throw last; }
    }
    await new Promise(r => setTimeout(r, 1500));
  }
  throw last;
}

// messages: [{role:'user'|'assistant', content:'teks'}]. Mengembalikan { text, usage:{in,out} }.
async function chat(profile, { system = '', messages = [], maxTokens = 4000 }) {
  if (!profile) throw new Error('Belum ada profil AI untuk peran ini. Atur di Pengaturan.');
  if (!profile.key) throw new Error(`Profil "${profile.label}" belum punya kunci API.`);
  const k = profile.key;
  if (profile.provider === 'anthropic') {
    const j = await post(`${URLS.anthropic}/v1/messages`, { 'x-api-key': k, 'anthropic-version': '2023-06-01' },
      { model: profile.model, max_tokens: maxTokens, system, messages: messages.map(m => ({ role: m.role, content: m.content })) }, k);
    const text = (j.content || []).filter(c => c.type === 'text').map(c => c.text).join('');
    return { text, usage: { in: (j.usage || {}).input_tokens || 0, out: (j.usage || {}).output_tokens || 0 } };
  }
  if (profile.provider === 'gemini') {
    const base = profile.baseUrl || URLS.gemini;
    const j = await post(`${base}/v1beta/models/${encodeURIComponent(profile.model)}:generateContent`, { 'x-goog-api-key': k },
      { systemInstruction: { parts: [{ text: system }] }, contents: messages.map(m => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })), generationConfig: { maxOutputTokens: maxTokens } }, k);
    const c = (j.candidates || [])[0];
    const text = c && c.content && c.content.parts ? c.content.parts.map(p => p.text || '').join('') : '';
    if (!text && c && c.finishReason) throw new Error('Gemini tidak mengembalikan teks (' + c.finishReason + ').');
    const u = j.usageMetadata || {};
    return { text, usage: { in: u.promptTokenCount || 0, out: u.candidatesTokenCount || 0 } };
  }
  // openai / kompatibel (OpenRouter, Groq, dsb. lewat baseUrl)
  const base = profile.baseUrl || URLS.openai;
  const official = /^https:\/\/api\.openai\.com/.test(base);
  const body = { model: profile.model, messages: [{ role: 'system', content: system }, ...messages.map(m => ({ role: m.role, content: m.content }))] };
  body[official ? 'max_completion_tokens' : 'max_tokens'] = maxTokens;
  const j = await post(`${base}/chat/completions`, { authorization: 'Bearer ' + k }, body, k);
  const text = ((j.choices || [])[0] || {}).message ? (j.choices[0].message.content || '') : '';
  const u = j.usage || {};
  return { text, usage: { in: u.prompt_tokens || 0, out: u.completion_tokens || 0 } };
}

// Gambar: Gemini (responseModalities IMAGE) atau OpenAI /images/generations. Mengembalikan { mime, b64 }.
async function image(profile, prompt) {
  if (!profile) throw new Error('Peran "Gambar" belum dipetakan ke profil AI.');
  if (!profile.key) throw new Error(`Profil "${profile.label}" belum punya kunci API.`);
  const k = profile.key;
  if (profile.provider === 'gemini') {
    const base = profile.baseUrl || URLS.gemini;
    const j = await post(`${base}/v1beta/models/${encodeURIComponent(profile.model)}:generateContent`, { 'x-goog-api-key': k },
      { contents: [{ role: 'user', parts: [{ text: prompt }] }], generationConfig: { responseModalities: ['TEXT', 'IMAGE'] } }, k);
    for (const p of (((j.candidates || [])[0] || {}).content || {}).parts || []) {
      const d = p.inlineData || p.inline_data;
      if (d && d.data) return { mime: d.mimeType || d.mime_type || 'image/png', b64: d.data };
    }
    throw new Error('Model tidak mengembalikan gambar. Pakai model yang mendukung keluaran gambar.');
  }
  if (profile.provider === 'openai') {
    const base = profile.baseUrl || URLS.openai;
    const j = await post(`${base}/images/generations`, { authorization: 'Bearer ' + k }, { model: profile.model, prompt, size: '1024x1024', n: 1 }, k);
    const d = (j.data || [])[0];
    if (d && d.b64_json) return { mime: 'image/png', b64: d.b64_json };
    if (d && d.url) { const r = await fetch(d.url, { signal: AbortSignal.timeout(60000) }); return { mime: r.headers.get('content-type') || 'image/png', b64: Buffer.from(await r.arrayBuffer()).toString('base64') }; }
    throw new Error('Penyedia tidak mengembalikan gambar.');
  }
  throw new Error('Penyedia Anthropic tidak membuat gambar. Petakan peran Gambar ke profil Gemini atau OpenAI.');
}

async function test(profile) {
  const t0 = Date.now();
  const r = await chat(profile, { system: 'Jawab satu kata.', messages: [{ role: 'user', content: 'Balas persis: siap' }], maxTokens: 20 });
  return { ok: true, ms: Date.now() - t0, balasan: r.text.slice(0, 60) };
}

module.exports = { chat, image, test, scrub };
