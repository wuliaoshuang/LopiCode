// 把一段样式表放进 jsdom 当浏览器解析，把里面的媒体查询规则列出来（第四轮 B1：验证“分屏宽”的规则真的写出来了、浏览器认得）。
// 用法：node media_rules.mjs <css 文件> …   → 标准输出一行 JSON：
//   {"ok":true,"media":[{"cond":"(min-width: 768px)","rules":[{"selector":".n-buy","style":{"padding-top":"24px"}}]}],"plain":12}
// 环境：LOPI_WEBDEV_DOM 指向装了 jsdom 的目录。不联网、不跑页面里的脚本。
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

function done(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
  process.exit(0);
}

try {
  const { JSDOM } = createRequire(path.join(process.env.LOPI_WEBDEV_DOM, 'package.json'))('jsdom');
  const css = process.argv.slice(2).map((f) => fs.readFileSync(f, 'utf8'));
  const dom = new JSDOM('<!doctype html><html><head></head><body></body></html>');
  const doc = dom.window.document;
  for (const text of css) {
    const el = doc.createElement('style');
    el.textContent = text;
    doc.head.appendChild(el);
  }
  const media = [];
  let plain = 0;
  for (const sheet of doc.styleSheets) {
    for (const rule of sheet.cssRules) {
      if (rule.media && rule.cssRules) {
        const rules = [];
        for (const r of rule.cssRules) {
          const style = {};
          for (let i = 0; i < r.style.length; i++) style[r.style[i]] = r.style.getPropertyValue(r.style[i]);
          rules.push({ selector: r.selectorText, style });
        }
        media.push({ cond: rule.media.mediaText, rules });
      } else if (rule.selectorText) {
        plain++;
      }
    }
  }
  dom.window.close();
  done({ ok: true, media, plain });
} catch (e) {
  done({ ok: false, error: String(e && e.stack ? e.stack : e) });
}
