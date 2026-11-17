// Build: web/src/Index.html (+ include) -> dist/index.html untuk GitHub Pages.
// Pemakaian: node tools/build.js
// Versi uji (Fase 2, server Biznet): MT_OUT=dist-uji MT_API_URL=https://api.marantau.web.id MT_API_KEY=<anon> node tools/build.js
//   -> config.js diganti alamat & kunci server uji + pita "VERSI UJI" di layar.
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..'), SRC = path.join(ROOT, 'web', 'src');
const OUT = path.join(ROOT, process.env.MT_OUT || 'dist');
const UJI = !!process.env.MT_API_URL;
if (UJI && !process.env.MT_API_KEY) { console.error('MT_API_KEY wajib diisi bersama MT_API_URL'); process.exit(1); }
function inc(name, depth) {
  let t = fs.readFileSync(path.join(SRC, name + '.html'), 'utf8');
  return t.replace(/<\?!=\s*include\('([^']+)'\);?\s*\?>/g, (m, n) => depth > 2 ? '' : inc(n, depth + 1));
}
let html = inc('Index', 0);
html = html.replace(/<base target="_top">\s*/i, '');
const version = Date.now().toString(36);
const head = '<title>Marantau</title>\n  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22%3E%3Ctext y=%22.9em%22 font-size=%2290%22%3E%E2%9A%93%3C/text%3E%3C/svg%3E">\n' +
  `  <script>window.MT_BUILD = '${version}';</script>\n` +
  `  <script src="vendor/supabase.js?v=${version}"></script>\n  <script src="config.js?v=${version}"></script>\n  <script src="mt-supabase.js?v=${version}"></script>\n`;
html = html.replace(/<meta charset="utf-8">/i, m => m + '\n  ' + head);
fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'vendor'), { recursive: true });
fs.writeFileSync(path.join(OUT, 'index.html'), html);
for (const f of ['config.js', 'mt-supabase.js']) fs.copyFileSync(path.join(ROOT, 'web', f), path.join(OUT, f));
if (UJI) {
  fs.writeFileSync(path.join(OUT, 'config.js'), '// Versi UJI - server Biznet (salinan data, ditimpa tiap malam).\n' +
    'window.MT_CONFIG = ' + JSON.stringify({ supabaseUrl: process.env.MT_API_URL.replace(/\/+$/, ''),
      supabaseKey: process.env.MT_API_KEY, emailDomain: 'marantau.game', uji: true }, null, 2) + ';\n' +
    "document.addEventListener('DOMContentLoaded', function () { var d = document.createElement('div');" +
    " d.textContent = 'VERSI UJI \u00b7 server Biznet \u00b7 data salinan, ditimpa tiap malam';" +
    " d.style.cssText = 'position:fixed;top:0;left:50%;transform:translateX(-50%);z-index:2147483647;background:#b3261e;color:#fff;" +
    "font:600 11px/1 system-ui,sans-serif;padding:4px 10px;border-radius:0 0 6px 6px;pointer-events:none;opacity:.85';" +
    " document.body.appendChild(d); });\n");
  html = html.replace('<title>Marantau</title>', '<title>Marantau (UJI)</title>\n  <meta name="robots" content="noindex,nofollow">');
  fs.writeFileSync(path.join(OUT, 'index.html'), html);
  // Fase 2.5: halaman uji kecepatan server lama vs baru (butuh alamat cloud juga).
  fs.copyFileSync(path.join(ROOT, 'web', 'uji', 'kecepatan.html'), path.join(OUT, 'kecepatan.html'));
  fs.writeFileSync(path.join(OUT, 'cloud-config.js'),
    fs.readFileSync(path.join(ROOT, 'web', 'config.js'), 'utf8').replace('window.MT_CONFIG =', 'window.MT_CONFIG_CLOUD ='));
}
fs.copyFileSync(path.join(ROOT, 'web', 'vendor', 'supabase.js'), path.join(OUT, 'vendor', 'supabase.js'));
fs.writeFileSync(path.join(OUT, '.nojekyll'), '');
// Tide v38: klien membandingkan MT_BUILD miliknya dengan file ini -> tahu ada versi baru
fs.writeFileSync(path.join(OUT, 'version.json'), JSON.stringify({ v: version, at: new Date().toISOString() }));
console.log(path.relative(ROOT, OUT) + '/index.html' + (UJI ? ' (UJI)' : ''), (html.length / 1024).toFixed(0) + ' KB');
