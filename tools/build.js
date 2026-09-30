// Build: web/src/Index.html (+ include) -> dist/index.html untuk GitHub Pages.
// Pemakaian: node tools/build.js
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..'), SRC = path.join(ROOT, 'web', 'src'), OUT = path.join(ROOT, 'dist');
function inc(name, depth) {
  let t = fs.readFileSync(path.join(SRC, name + '.html'), 'utf8');
  return t.replace(/<\?!=\s*include\('([^']+)'\);?\s*\?>/g, (m, n) => depth > 2 ? '' : inc(n, depth + 1));
}
let html = inc('Index', 0);
html = html.replace(/<base target="_top">\s*/i, '');
const version = Date.now().toString(36);
const head = '<title>Marantau</title>\n  <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22%3E%3Ctext y=%22.9em%22 font-size=%2290%22%3E%E2%9A%93%3C/text%3E%3C/svg%3E">\n' +
  `  <script src="vendor/supabase.js?v=${version}"></script>\n  <script src="config.js?v=${version}"></script>\n  <script src="mt-supabase.js?v=${version}"></script>\n`;
html = html.replace(/<meta charset="utf-8">/i, m => m + '\n  ' + head);
fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'vendor'), { recursive: true });
fs.writeFileSync(path.join(OUT, 'index.html'), html);
for (const f of ['config.js', 'mt-supabase.js']) fs.copyFileSync(path.join(ROOT, 'web', f), path.join(OUT, f));
fs.copyFileSync(path.join(ROOT, 'web', 'vendor', 'supabase.js'), path.join(OUT, 'vendor', 'supabase.js'));
fs.writeFileSync(path.join(OUT, '.nojekyll'), '');
console.log('dist/index.html', (html.length / 1024).toFixed(0) + ' KB');
