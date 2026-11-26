// 用官方编译器把导出的 Vue 3 工程真的编译一遍，再在 Node 里服务端渲染入口组件。
// 用法：node compile_vue.mjs <导出目录> <入口.vue>      环境：LOPI_WEBDEV 指向装了 vue / @vue/compiler-sfc / esbuild 的目录
// 输出：标准输出一行 JSON {ok, errors, warnings, files, html}
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [dir, entry] = process.argv.slice(2);
const webdev = process.env.LOPI_WEBDEV;
const require = createRequire(path.join(webdev, 'package.json'));
const sfc = require('@vue/compiler-sfc');
const esbuild = require('esbuild');

const errors = [];
const warnings = [];
const say = (list, file, what, e) => list.push(`${file}：${what}：${String((e && e.message) || e)}`);

function listVue(d, base = '') {
  const out = [];
  for (const name of fs.readdirSync(d)) {
    const full = path.join(d, name);
    if (fs.statSync(full).isDirectory()) out.push(...listVue(full, `${base}${name}/`));
    else if (name.endsWith('.vue')) out.push(`${base}${name}`);
  }
  return out.sort();
}

/// 一个 .vue 编译成一个 JS 模块。ssr=true 时模板编译成服务端渲染函数。
function compileOne(file, ssr, report) {
  const source = fs.readFileSync(path.join(dir, file), 'utf8');
  const id = `lc${Buffer.from(file).toString('hex').slice(0, 12)}`;
  const { descriptor, errors: parseErrors } = sfc.parse(source, { filename: file });
  if (report) parseErrors.forEach((e) => say(errors, file, '解析', e));
  if (parseErrors.length) return null;
  if (report) {
    if (!descriptor.scriptSetup) say(errors, file, '结构', '没有 <script setup>');
    if (!descriptor.template) say(errors, file, '结构', '没有 <template>');
    for (const s of descriptor.styles) {
      const r = sfc.compileStyle({ source: s.content, filename: file, id: `data-v-${id}`, scoped: s.scoped });
      r.errors.forEach((e) => say(errors, file, '样式', e));
    }
  }
  let script;
  try {
    script = sfc.compileScript(descriptor, {
      id,
      inlineTemplate: true,
      templateOptions: { ssr, ssrCssVars: [], compilerOptions: { onWarn: (w) => report && say(warnings, file, ssr ? '模板（服务端）' : '模板', w) } },
    });
  } catch (e) {
    if (report) say(errors, file, ssr ? '脚本和模板（服务端）' : '脚本和模板', e);
    return null;
  }
  if (report && !ssr && descriptor.template) {
    // 模板再单独编一次：把警告和错误都收上来（内联编译时有的只抛第一条）
    const t = sfc.compileTemplate({ source: descriptor.template.content, filename: file, id, scoped: true, compilerOptions: { bindingMetadata: script.bindings } });
    t.errors.forEach((e) => say(errors, file, '模板', e));
    t.tips.forEach((e) => say(warnings, file, '模板提示', e));
  }
  return script.content;
}

const vuePlugin = (ssr, report) => ({
  name: 'lc-vue',
  setup(build) {
    build.onLoad({ filter: /\.vue$/ }, (args) => {
      const rel = path.relative(dir, args.path).split(path.sep).join('/');
      const code = compileOne(rel, ssr, report);
      if (code == null) return { errors: [{ text: `${rel} 没编译过` }] };
      return { contents: code, loader: 'js' };
    });
  },
});

// 服务端那一份的入口再包一层，让“渲染”和页面用的是包里同一份 Vue。
const wrapper = path.join(dir, '.lc-entry.js');
fs.writeFileSync(
  wrapper,
  `import { createSSRApp } from "vue";\nimport { renderToString } from "@vue/server-renderer";\nimport Page from ${JSON.stringify(`./${entry}`)};\n` +
    'export const render = (onWarn, onError) => { const app = createSSRApp(Page); app.config.warnHandler = onWarn; app.config.errorHandler = onError; return renderToString(app); };\n',
);

async function bundle(ssr, outfile, report) {
  try {
    const r = await esbuild.build({
      entryPoints: [ssr ? wrapper : path.join(dir, entry)],
      bundle: true,
      format: 'esm',
      platform: 'node',
      outfile,
      nodePaths: [path.join(webdev, 'node_modules')],
      plugins: [vuePlugin(ssr, report)],
      logLevel: 'silent',
      banner: { js: "import { createRequire as lcCreateRequire } from 'node:module'; const require = lcCreateRequire(import.meta.url);" },
    });
    r.warnings.forEach((w) => say(warnings, w.location ? w.location.file : entry, '打包', w.text));
    return true;
  } catch (e) {
    for (const x of e.errors || [{ text: String(e) }]) say(errors, x.location ? x.location.file : entry, ssr ? '打包（服务端）' : '打包', x.text);
    return false;
  }
}

const files = listVue(dir);
const out = { ok: false, errors, warnings, files, html: null };
const clientOk = await bundle(false, path.join(dir, '.lc-out/client.mjs'), true);
const ssrOk = await bundle(true, path.join(dir, '.lc-out/ssr.mjs'), false);
if (clientOk && ssrOk && errors.length === 0) {
  try {
    const mod = await import(pathToFileURL(path.join(dir, '.lc-out/ssr.mjs')).href);
    out.html = await mod.render(
      (msg) => say(warnings, entry, '运行时警告', msg),
      (e) => say(errors, entry, '渲染出错', e),
    );
  } catch (e) {
    say(errors, entry, '服务端渲染', e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e);
  }
}
out.ok = errors.length === 0;
process.stdout.write(JSON.stringify(out));
