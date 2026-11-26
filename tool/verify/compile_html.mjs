// 把导出的纯网页（.html + .css + .js）真的过一遍编译器：每个 .css、.js 用 esbuild 解析（语法错、不认识的写法都会报），
// 每个 .html 里引用的 .css / .js 文件必须都在。
// 用法：node compile_html.mjs <导出目录> <入口.html>     环境：LOPI_WEBDEV 指向装了 esbuild 的目录
// 输出：标准输出一行 JSON {ok, errors, warnings, html}（html＝入口网页的内容）
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const [dir, entry] = process.argv.slice(2);
const require = createRequire(path.join(process.env.LOPI_WEBDEV, 'package.json'));
const esbuild = require('esbuild');

const errors = [];
const warnings = [];
const files = fs.readdirSync(dir).filter((f) => !f.startsWith('.'));
for (const f of files) {
  const ext = path.extname(f);
  const text = fs.readFileSync(path.join(dir, f), 'utf8');
  if (ext === '.css' || ext === '.js') {
    try {
      const r = await esbuild.transform(text, { loader: ext.slice(1), logLevel: 'silent', sourcefile: f });
      r.warnings.forEach((w) => warnings.push(`${f}:${w.location ? w.location.line : 0}：${w.text}`));
    } catch (e) {
      for (const x of e.errors || [{ text: String(e) }]) errors.push(`${f}:${x.location ? x.location.line : 0}：${x.text}`);
    }
  } else if (ext === '.html') {
    if (!/^<!doctype html>/i.test(text.trimStart())) errors.push(`${f}：开头不是 <!doctype html>`);
    for (const m of text.matchAll(/(?:href|src)="([^"#:]+\.(?:css|js|html))"/g)) {
      if (!fs.existsSync(path.join(dir, m[1]))) errors.push(`${f}：引用的 ${m[1]} 不在导出的文件里`);
    }
  }
}
const html = fs.existsSync(path.join(dir, entry)) ? fs.readFileSync(path.join(dir, entry), 'utf8') : null;
if (html === null) errors.push(`入口 ${entry} 不在`);
process.stdout.write(JSON.stringify({ ok: errors.length === 0, errors, warnings, html }));
