// 用 esbuild 把导出的 React 工程（.jsx + .css）真的编译打包，再用 react-dom/server 渲染入口组件。
// 用法：node compile_react.mjs <导出目录> <入口.jsx>     环境：LOPI_WEBDEV 指向装了 react / react-dom / esbuild 的目录
// 输出：标准输出一行 JSON {ok, errors, warnings, html, cssBytes}
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [dir, entry] = process.argv.slice(2);
const webdev = process.env.LOPI_WEBDEV;
const require = createRequire(path.join(webdev, 'package.json'));
const esbuild = require('esbuild');

const errors = [];
const warnings = [];
const out = { ok: false, errors, warnings, html: null, cssBytes: 0 };
const outfile = path.join(dir, '.lc-out/page.mjs');
// 入口再包一层，让“渲染”和页面用的是包里同一份 React（两份 React 混用时 hooks 会报错）。
const wrapper = path.join(dir, '.lc-entry.jsx');
fs.writeFileSync(
  wrapper,
  `import React from "react";\nimport { renderToString } from "react-dom/server";\nimport Page from ${JSON.stringify(`./${entry}`)};\n` +
    'export const isComponent = typeof Page === "function";\nexport const render = () => renderToString(React.createElement(Page));\n',
);
let built = false;
try {
  const r = await esbuild.build({
    entryPoints: [wrapper],
    bundle: true,
    format: 'esm',
    platform: 'node',
    outfile,
    jsx: 'automatic',
    nodePaths: [path.join(webdev, 'node_modules')],
    logLevel: 'silent',
    banner: { js: "import { createRequire as lcCreateRequire } from 'node:module'; const require = lcCreateRequire(import.meta.url);" },
  });
  r.warnings.forEach((w) => warnings.push(`${w.location ? w.location.file : entry}：打包：${w.text}`));
  built = true;
} catch (e) {
  for (const x of e.errors || [{ text: String(e) }]) errors.push(`${x.location ? `${x.location.file}:${x.location.line}` : entry}：编译：${x.text}`);
}
if (built) {
  const css = outfile.replace(/\.mjs$/, '.css');
  if (fs.existsSync(css)) out.cssBytes = fs.statSync(css).size;
  const realError = console.error;
  console.error = (...a) => warnings.push(`${entry}：运行时警告：${a.map(String).join(' ').split('\n')[0]}`);
  try {
    const mod = await import(pathToFileURL(outfile).href);
    if (!mod.isComponent) throw new Error('入口文件没有默认导出一个组件');
    out.html = mod.render();
  } catch (e) {
    errors.push(`${entry}：服务端渲染：${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  } finally {
    console.error = realError;
  }
}
out.ok = errors.length === 0;
process.stdout.write(JSON.stringify(out));
