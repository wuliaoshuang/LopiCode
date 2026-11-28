// 把导出的网页真的“跑”起来：在 Node 里用 jsdom 当浏览器，照着一串步骤点按钮、往输入框里打字，再看界面有没有跟着变。
// 第 5 期（状态与数据绑定）用它验“改状态→界面跟着变”“输入框双向”“重复”“条件”“跨页的项目级状态”。
// 用法：node run_dom.mjs <html|vue|react> <导出目录> <入口文件>      步骤在 <导出目录>/.lc-steps.json
// 环境：LOPI_WEBDEV 指向装了 vue / react / esbuild 的目录；LOPI_WEBDEV_DOM 指向装了 jsdom 的目录。不联网。
// 输出：标准输出一行 JSON {ok, errors, warnings, done}（done＝做完了几步）
// 没覆盖的：真浏览器的排版和样式表（这里只看元素在不在、文字、属性、行内样式）。
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const [kind, dir, entry] = process.argv.slice(2);
const webdev = process.env.LOPI_WEBDEV;
const { JSDOM, VirtualConsole } = createRequire(path.join(process.env.LOPI_WEBDEV_DOM, 'package.json'))('jsdom');
const requireDev = createRequire(path.join(webdev, 'package.json'));

const errors = [];
const warnings = [];
const out = { ok: false, errors, warnings, done: 0 };
const finish = () => {
  out.ok = errors.length === 0;
  process.stdout.write(JSON.stringify(out));
  process.exit(0);
};
const steps = JSON.parse(fs.readFileSync(path.join(dir, '.lc-steps.json'), 'utf8'));
const tick = () => new Promise((r) => setTimeout(r, 25));

function consoleFor() {
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e) => {
    const text = String((e && e.message) || e);
    // jsdom 不会真的换页（location.href = …），也没有 scrollTo：走到这两处算正常，换页后面用“换页”那一步接着验。
    if (/Not implemented: (navigation|Window's scrollTo)/.test(text)) return;
    errors.push(`页面里出错：${text}${e && e.detail ? `：${String(e.detail).split('\n')[0]}` : ''}`);
  });
  vc.on('error', (...a) => warnings.push(`控制台报错：${a.map(String).join(' ').split('\n')[0]}`));
  vc.on('warn', (...a) => warnings.push(`控制台警告：${a.map(String).join(' ').split('\n')[0]}`));
  return vc;
}

// “接真网络”（net 步骤）开没开；开了以后每个新开的页面都先接好再跑脚本。
let netOn = false;
function wireNet(w) {
  w.fetch = (url, init) => {
    const ctl = new AbortController();
    const sig = init && init.signal;
    if (sig) {
      if (sig.aborted) ctl.abort();
      else sig.addEventListener('abort', () => ctl.abort());
    }
    return fetch(String(url), { method: (init && init.method) || 'GET', headers: (init && init.headers) || {}, body: init && init.body, signal: ctl.signal }).then((res) => ({
      ok: res.ok,
      status: res.status,
      headers: res.headers,
      text: () => res.text(),
    }));
  };
}

// —— 纯网页：把 .css / .js 直接塞进网页里（不走网络、不走文件加载器）——
function openHtml(file, carry, local) {
  let html = fs.readFileSync(path.join(dir, file), 'utf8');
  html = html.replace(/<link rel="stylesheet" href="([^"]+)">/g, (_, f) => `<style>${fs.readFileSync(path.join(dir, f), 'utf8')}</style>`);
  const scripts = [];
  html = html.replace(/<script src="([^"]+)"[^>]*><\/script>/g, (_, f) => {
    scripts.push(f);
    return '';
  });
  const dom = new JSDOM(html, { url: `https://lopi.test/${file}`, runScripts: 'outside-only', pretendToBeVisual: true, virtualConsole: consoleFor() });
  for (const [k, v] of Object.entries(carry || {})) dom.window.sessionStorage.setItem(k, v);
  for (const [k, v] of Object.entries(local || {})) dom.window.localStorage.setItem(k, v);
  if (netOn) wireNet(dom.window);
  for (const f of scripts) {
    try {
      dom.window.eval(fs.readFileSync(path.join(dir, f), 'utf8'));
    } catch (e) {
      errors.push(`${f}：运行出错：${e && e.stack ? e.stack.split('\n').slice(0, 2).join(' | ') : e}`);
    }
  }
  // 脚本是事后塞进去的，网页早就“准备好了”：补发一次，让等着它的代码开工。
  dom.window.document.dispatchEvent(new dom.window.Event('DOMContentLoaded'));
  return dom;
}

// —— Vue / React：用 esbuild 打成一个给浏览器用的包，放进 jsdom 里挂到页面上 ——
async function openBundle(local) {
  const esbuild = requireDev('esbuild');
  const wrapper = path.join(dir, kind === 'vue' ? '.lc-dom-entry.js' : '.lc-dom-entry.jsx');
  fs.writeFileSync(
    wrapper,
    kind === 'vue'
      ? `import { createApp } from "vue";\nimport Page from ${JSON.stringify(`./${entry}`)};\nconst app = createApp(Page);\napp.config.warnHandler = (m) => console.warn("Vue 警告：" + m);\napp.config.errorHandler = (e) => console.error("Vue 出错：" + ((e && e.message) || e));\napp.mount(document.getElementById("app"));\n`
      : `import React from "react";\nimport { createRoot } from "react-dom/client";\nimport Page from ${JSON.stringify(`./${entry}`)};\ncreateRoot(document.getElementById("app")).render(${process.env.LOPI_REACT_STRICT === "1" ? "React.createElement(React.StrictMode, null, React.createElement(Page))" : "React.createElement(Page)"});\n`,
  );
  const plugins = [];
  if (kind === 'vue') {
    const sfc = requireDev('@vue/compiler-sfc');
    plugins.push({
      name: 'lc-vue',
      setup(build) {
        build.onLoad({ filter: /\.vue$/ }, (args) => {
          const rel = path.relative(dir, args.path).split(path.sep).join('/');
          const { descriptor, errors: bad } = sfc.parse(fs.readFileSync(args.path, 'utf8'), { filename: rel });
          if (bad.length) return { errors: bad.map((e) => ({ text: `${rel}：${e.message}` })) };
          const id = `lc${Buffer.from(rel).toString('hex').slice(0, 12)}`;
          return { contents: sfc.compileScript(descriptor, { id, inlineTemplate: true }).content, loader: 'js' };
        });
      },
    });
  }
  const outfile = path.join(dir, '.lc-out/dom.js');
  try {
    await esbuild.build({
      entryPoints: [wrapper],
      bundle: true,
      format: 'iife',
      platform: 'browser',
      outfile,
      jsx: 'automatic',
      nodePaths: [path.join(webdev, 'node_modules')],
      plugins,
      logLevel: 'silent',
      define: { __VUE_OPTIONS_API__: 'true', __VUE_PROD_DEVTOOLS__: 'false', __VUE_PROD_HYDRATION_MISMATCH_DETAILS__: 'false', 'process.env.NODE_ENV': '"development"' },
    });
  } catch (e) {
    for (const x of e.errors || [{ text: String(e) }]) errors.push(`${x.location ? `${x.location.file}:${x.location.line}` : entry}：编译：${x.text}`);
    return null;
  }
  const dom = new JSDOM('<!doctype html><html><body><div id="app"></div></body></html>', { url: 'https://lopi.test/', runScripts: 'outside-only', pretendToBeVisual: true, virtualConsole: consoleFor() });
  for (const [k, v] of Object.entries(local || {})) dom.window.localStorage.setItem(k, v);
  if (netOn) wireNet(dom.window);
  try {
    dom.window.eval(fs.readFileSync(outfile, 'utf8'));
  } catch (e) {
    errors.push(`${entry}：运行出错：${e && e.stack ? e.stack.split('\n').slice(0, 2).join(' | ') : e}`);
  }
  return dom;
}

let dom = kind === 'html' ? openHtml(entry) : await openBundle();
// 现在开着的是哪个网页文件（纯网页换页以后会变；“关掉再开”要重开它）。
let current = entry;
const storageOf = (st) => {
  const out = {};
  for (let i = 0; i < st.length; i++) out[st.key(i)] = st.getItem(st.key(i));
  return out;
};
if (!dom) finish();
await tick();

const doc = () => dom.window.document;
const all = (sel) => Array.from(doc().querySelectorAll(sel));
function one(sel, at) {
  const list = all(sel);
  const el = list[at || 0];
  if (!el) throw new Error(`找不到 ${sel}${at ? ` 的第 ${at + 1} 个` : ''}（一共 ${list.length} 个）`);
  return el;
}
// 这个控件里真正能填能点的那一个。
function control(el) {
  return el.matches('input, textarea, select') ? el : el.querySelector('input, textarea, select') || el;
}
function shown(el) {
  for (let e = el; e && e.style; e = e.parentElement) {
    if (e.style.display === 'none') return false;
  }
  return true;
}
const textOf = (el) => el.textContent.replace(/\s+/g, ' ').trim();

for (const s of steps) {
  const where = `第 ${out.done + 1} 步（${JSON.stringify(s)}）`;
  try {
    const same = (got) => {
      if (got !== s.is) errors.push(`${where}：应该是 ${JSON.stringify(s.is)}，实际是 ${JSON.stringify(got)}`);
    };
    switch (s.op) {
      case 'click':
        control(one(s.sel, s.at)).click();
        break;
      case 'type': {
        const el = control(one(s.sel, s.at));
        // 用元素原型上的写法改内容：React 盯着 value 的改动，直接赋值它会当成“没变”。
        const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, s.text);
        el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
        break;
      }
      case 'fire':
        // 发一个事件（jsdom 不放 CSS 动画：轻提示的“动画放完”要自己发）。
        {
          const el = one(s.sel, s.at);
          const ev = new dom.window.Event(s.name, { bubbles: true });
          // jsdom 不认 onanimationend 这类写在标签上的处理（浏览器认）：这里照浏览器的规矩替它跑一遍。
          const inline = el.getAttribute('on' + s.name);
          if (inline && !(('on' + s.name) in el)) el.addEventListener(s.name, new dom.window.Function('event', inline), { once: true });
          el.dispatchEvent(ev);
          // jsdom 没有 AnimationEvent：React 这时改听带 webkit 前缀的老名字（真浏览器里它听的就是 animationend）。
          const old = { animationend: 'webkitAnimationEnd' }[s.name];
          if (old && !('AnimationEvent' in dom.window)) el.dispatchEvent(new dom.window.Event(old, { bubbles: true }));
        }
        break;
      case 'text':
        same(textOf(one(s.sel, s.at)));
        break;
      case 'count':
        same(all(s.sel).length);
        break;
      case 'shown':
        same(all(s.sel).length > 0 && shown(one(s.sel, s.at)));
        break;
      case 'value':
        same(control(one(s.sel, s.at)).value);
        break;
      case 'checked':
        same(control(one(s.sel, s.at)).checked);
        break;
      case 'disabled':
        same(control(one(s.sel, s.at)).disabled);
        break;
      case 'hasClass':
        same(one(s.sel, s.at).classList.contains(s.name));
        break;
      case 'style':
        same(one(s.sel, s.at).style.getPropertyValue(s.name));
        break;
      case 'page':
        // 换页。纯网页：带着 sessionStorage 打开另一个文件（浏览器里换页时它本来就跟着走）；Vue / React：改地址栏的 # 后面。
        if (kind === 'html') {
          const carry = {};
          for (let i = 0; i < dom.window.sessionStorage.length; i++) {
            const k = dom.window.sessionStorage.key(i);
            carry[k] = dom.window.sessionStorage.getItem(k);
          }
          const local = storageOf(dom.window.localStorage);
          dom.window.close();
          dom = openHtml(s.html, carry, local);
          current = s.html;
        } else {
          dom.window.location.hash = s.hash;
        }
        break;
      case 'fake': {
        // 假网络、假对话框（页面逻辑的“请求网址”“弹提示”要它们）：routes＝网址 → {status, body}；不在表里的网址当“连不上”。
        const w = dom.window;
        const routes = s.routes || {};
        w.lcAlerts = [];
        w.alert = (m) => { w.lcAlerts.push(String(m)); };
        w.confirm = (m) => { w.lcAlerts.push('问：' + String(m)); return s.confirm !== false; };
        w.fetch = (url) => {
          const r = routes[String(url)];
          if (!r) return Promise.reject(new TypeError('Failed to fetch'));
          const status = r.status || 200;
          return Promise.resolve({ ok: status >= 200 && status < 300, status, headers: new Map(), text: () => Promise.resolve(String(r.body)) });
        };
        break;
      }
      case 'net':
        // 真网络（“请求”库对着本地假服务测）：页面里的 fetch 交给 Node 自带的 fetch；页面那边中止了，这边跟着中止。
        // 一经打开就一直开着：换页、关掉再开以后的新页面，在它的脚本开跑以前就接好（一放上就发请求的页面要它）。
        netOn = true;
        wireNet(dom.window);
        break;
      case 'until': {
        // 等到这段字变成要的样子（定时器到点、请求回来）：成立就往下走，最多等 10 秒。
        const limit = Date.now() + 10000;
        let got = null;
        for (;;) {
          got = all(s.sel).length > (s.at || 0) ? textOf(one(s.sel, s.at)) : null;
          if (got === s.is || Date.now() > limit) break;
          await new Promise((r) => setTimeout(r, 15));
        }
        same(got);
        break;
      }
      case 'storedUntil': {
        // 等到本地存储里这个名字下存的变成要的样子，最多等 10 秒。
        const limit = Date.now() + 10000;
        let got = null;
        for (;;) {
          got = dom.window.localStorage.getItem(s.key);
          if (got === s.is || Date.now() > limit) break;
          await new Promise((r) => setTimeout(r, 15));
        }
        same(got);
        break;
      }
      case 'stored':
        // 本地存储里这个名字下存的原文（没有＝null）。
        same(dom.window.localStorage.getItem(s.key));
        break;
      case 'store':
        dom.window.localStorage.setItem(s.key, String(s.value));
        break;
      case 'reload': {
        // 关掉再开：本地存储留着（本次存储也留着），页面从头来。
        const local = storageOf(dom.window.localStorage);
        const carry = storageOf(dom.window.sessionStorage);
        dom.window.close();
        dom = kind === 'html' ? openHtml(current, carry, local) : await openBundle(local);
        if (!dom) throw new Error('重开没成');
        await tick();
        break;
      }
      case 'alerts':
        same((dom.window.lcAlerts || []).join(' | '));
        break;
      case 'wait':
        // 等一小会儿（让定时器、请求回来），最多 2 秒。
        await new Promise((r) => setTimeout(r, Math.min(Number(s.ms) || 0, 2000)));
        break;
      case 'hash':
        same(dom.window.location.hash);
        break;
      default:
        errors.push(`${where}：不认识的步骤`);
    }
  } catch (e) {
    errors.push(`${where}：${(e && e.message) || e}`);
  }
  await tick();
  out.done++;
}
finish();
