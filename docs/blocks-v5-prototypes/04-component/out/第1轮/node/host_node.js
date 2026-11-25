// F2 的前端假宿主（Node）：调度 ＋ 一棵假的页面树（“假 DOM”）＋ 发请求 ＋ 只给检查程序用的 test.* 接口。
// 04-component 和 05-full-flow 共用这一份。接口清单、哪一轮加的，见同目录的 natives.json。
// 只用 Node 自带的东西。这不是浏览器：没有排版、没有真的事件捕获阶段、没有默认行为。
"use strict";
const lc = require("./lc_lang.js");

function fail(message) {
  throw new Error(message);
}

// ———— 调度（和 03 的宿主一样）————

function tickDefer(fn) {
  queueMicrotask(() => {
    let out;
    try {
      out = lc.call(fn);
    } catch (e) {
      process.stderr.write("攒着做的事出错：" + (e && e.message) + "\n");
      return;
    }
    if (out instanceof Promise) {
      out.catch(() => {});
      process.stderr.write("攒着做的事出错：tick.defer 的函数里不能有要等的事\n");
    }
  });
  return null;
}
const tickWait = () => new Promise((done) => setTimeout(() => done(null), 0));
function logError(x) {
  process.stderr.write(lc.toText(x) + "\n");
  return null;
}

// ———— 假的页面树 ————

let serial = 0;
const ops = { 新建: 0, 写: 0, 插入: 0, 拿走: 0 };
const ids = new Map(); // 第 1 轮的“页面上事先摆好的控件”：名字 → 元素

class El {
  constructor(tag) {
    this.serial = ++serial;
    this.tag = tag;
    this.cls = "";
    this.text = "";
    this.value = "";
    this.shown = true;
    this.attrs = {};
    this.children = [];
    this.parent = null;
    this.handlers = {};
  }
}
const root = new El("页面");

function el(x) {
  if (x instanceof El) return x;
  if (typeof x === "string" && ids.has(x)) return ids.get(x);
  fail(typeof x === "string" ? "页面上没有叫“" + x + "”的控件" : "这不是页面上的元素");
}

const uiRoot = () => root;

// 标签是“#锚”的元素是库用来占位置的，画出来看不见，也不计数。
function uiCreate(tag) {
  const e = new El(lc.toText(tag));
  if (e.tag !== "#锚") ops.新建++;
  return e;
}

function uiSet(ctrl, name, value) {
  const e = el(ctrl);
  ops.写++;
  if (name === "文字") e.text = lc.toText(value);
  else if (name === "类名") e.cls = lc.toText(value);
  else if (name === "显示") e.shown = lc.truthy(value);
  else if (name === "值") e.value = lc.toText(value);
  else e.attrs[lc.toText(name)] = lc.toText(value);
  return null;
}

function uiGet(ctrl, name) {
  const e = el(ctrl);
  if (name === "文字") return e.text;
  if (name === "类名") return e.cls;
  if (name === "显示") return e.shown;
  if (name === "值") return e.value;
  const v = e.attrs[lc.toText(name)];
  return v === undefined ? null : v;
}

function detach(e) {
  if (!e.parent) return;
  const i = e.parent.children.indexOf(e);
  if (i >= 0) e.parent.children.splice(i, 1);
  e.parent = null;
}

// 把 子 放进 父 里、排在 前面的 之前（前面的 是空＝放最后）。子 已经在别处就先拿下来（＝挪动）。
function uiInsert(parent, child, before) {
  const p = el(parent), c = el(child);
  if (c.tag !== "#锚") ops.插入++;
  detach(c);
  if (before === null || before === undefined) p.children.push(c);
  else {
    const i = p.children.indexOf(el(before));
    if (i < 0) fail("要排在它前面的那个元素不在这个父元素里");
    p.children.splice(i, 0, c);
  }
  c.parent = p;
  return null;
}

function uiRemove(child) {
  const c = el(child);
  if (c.tag !== "#锚") ops.拿走++;
  detach(c);
  return null;
}

// 登记事件处理；返回“取消函数”。
function uiOn(ctrl, name, callback) {
  const e = el(ctrl);
  const key = lc.toText(name);
  const entry = { callback };
  (e.handlers[key] = e.handlers[key] || []).push(entry);
  return lc.fn("", 0, 0, () => {
    const list = e.handlers[key] || [];
    const i = list.indexOf(entry);
    if (i >= 0) list.splice(i, 1);
    return null;
  });
}

// 触发一个事件：从目标一路往上传（冒泡）。处理函数宿主不等它（它要等的事自己在后面做完），出的错写到错误输出。
// 返回所有处理函数交回来的“稍后的结果”，检查程序要等它们做完时用。
function dispatch(target, name, extra) {
  let stopped = false;
  const waits = [];
  const event = lc.dictOf(
    "值", target.value,
    "目标", target,
    "别再往上传", lc.fn("", 0, 0, () => { stopped = true; return null; }),
    "阻止默认行为", lc.fn("", 0, 0, () => null),
  );
  for (const k of Object.keys(extra || {})) event[k] = extra[k];
  for (let e = target; e && !stopped; e = e.parent) {
    for (const entry of (e.handlers[name] || []).slice()) {
      try {
        const out = lc.call(entry.callback, event);
        if (out instanceof Promise) waits.push(out.catch((err) => process.stderr.write("事件处理出错：" + (err && (err.f_消息 || err.message)) + "\n")));
      } catch (err) {
        process.stderr.write("事件处理出错：" + (err && (err.f_消息 || err.message)) + "\n");
      }
    }
  }
  return waits;
}

// ———— 发请求（05 用）————

let netCount = 0; // 宿主真的发出去了几个请求（检查程序用）

// 第 1 轮：F1 的 net.fetch——成功（2xx）得到响应的文字，其余一律得空。
async function netFetch(method, url, data) {
  netCount++;
  try {
    const res = await fetch(lc.toText(url), {
      method: lc.toText(method),
      headers: data === null || data === undefined ? {} : { "Content-Type": "application/json; charset=utf-8" },
      body: data === null || data === undefined ? undefined : lc.toJson(data),
      signal: AbortSignal.timeout(10000),
    });
    const text = await res.text();
    return res.ok ? text : null;
  } catch (e) {
    return null;
  }
}

// 第 2 轮：D 的“网络.请求”。请求是字典 {方法, 网址, 头, 正文, 超时毫秒}；回应是字典 {状态码, 成功, 头, 正文}。
// 只有网络层失败才出错（消息统一）：超时 →“超时”，别的 →“网络错误”。404、422、500 不出错。
async function netRequest(req) {
  netCount++;
  const method = lc.toText(lc.dictGet(req, "方法") ?? "GET");
  const headers = {};
  const h = lc.dictGet(req, "头");
  if (lc.kind(h) === "obj") for (const k of Object.keys(h)) headers[k] = lc.toText(h[k]);
  const body = lc.dictGet(req, "正文");
  const timeout = lc.dictGet(req, "超时毫秒");
  let res, text;
  try {
    res = await fetch(lc.toText(lc.dictGet(req, "网址")), {
      method,
      headers,
      body: body === null || body === undefined ? undefined : lc.toText(body),
      signal: AbortSignal.timeout(timeout === null || timeout === undefined ? 10000 : lc.toNum(timeout)),
    });
    text = await res.text();
  } catch (e) {
    fail(e && e.name === "TimeoutError" ? "超时" : "网络错误");
  }
  const outHeaders = Object.create(null);
  res.headers.forEach((v, k) => { outHeaders[k] = v; });
  return lc.dictOf("状态码", res.status, "成功", res.ok, "头", outHeaders, "正文", text);
}

const envGet = (name) => {
  const v = process.env[lc.toText(name)];
  return v === undefined ? null : v;
};

// ———— 只给检查程序用的 ————

// 第 1 轮：页面上的控件是事先摆好的（一份 JSON：{tag, cls, id, text, shown, children}）。
function testPage(json) {
  const build = (d) => {
    const e = new El(d.tag);
    e.cls = d.cls || "";
    e.text = d.text || "";
    e.shown = d.shown !== false;
    if (d.id) ids.set(d.id, e);
    for (const c of d.children || []) {
      const ce = build(c);
      ce.parent = e;
      e.children.push(ce);
    }
    return e;
  };
  const e = build(JSON.parse(lc.toText(json)));
  e.parent = root;
  root.children.push(e);
  return null;
}

function dump(e, withSerial) {
  if (e.tag === "#锚" || !e.shown) return null;
  let s = e.tag + (e.cls ? "." + e.cls.split(/\s+/).filter(Boolean).join(".") : "") + (withSerial ? "#" + e.serial : "");
  if (e.tag === "input") s += "〔" + e.value + "〕";
  if (e.text !== "") s += "“" + e.text + "”";
  const kids = e.children.map((c) => dump(c, withSerial)).filter((x) => x !== null);
  if (kids.length || e.tag === "ul") s += "[" + kids.join(" ") + "]";
  return s;
}

// 把看得见的树写成一行文字。带号＝是：每个元素后面跟它的出厂编号（用来看“还是不是原来那个元素”）。
function testTree(start, withSerial) {
  const e = start === null || start === undefined ? root : el(start);
  const kids = e === root ? e.children.map((c) => dump(c, lc.truthy(withSerial))).filter((x) => x !== null).join(" ") : dump(e, lc.truthy(withSerial));
  return kids === null ? "（看不见）" : kids;
}

// 找第 n 个（从 1 数）看得见的、对得上“标签.类名”的元素；范围＝某个元素里面（空＝整页）。找不到得空。
function testFind(scope, selector, n) {
  const [tag, ...classes] = lc.toText(selector).split(".");
  const hits = [];
  const walk = (e) => {
    if (e.tag === "#锚" || !e.shown) return;
    const have = e.cls.split(/\s+/);
    if ((tag === "" || e.tag === tag) && classes.every((c) => have.includes(c)) && e !== root) hits.push(e);
    e.children.forEach(walk);
  };
  walk(scope === null || scope === undefined ? root : el(scope));
  const i = Math.trunc(lc.toNum(n)) - 1;
  return i >= 0 && i < hits.length ? hits[i] : null;
}

async function settle(waits) {
  await Promise.all(waits);
  await tickWait();
  return null;
}

// 点一下：触发“点击”，等处理函数里要等的事都做完，再让攒着的更新跑完。
const testClick = (ctrl) => settle(dispatch(el(ctrl), "点击"));
// 往输入框里打字：先改它的值，再触发“输入”。
function testInput(ctrl, text) {
  const e = el(ctrl);
  e.value = lc.toText(text);
  return settle(dispatch(e, "输入"));
}
// 只触发、不等（用来模拟“连点两下”）：返回一个“稍后的结果”。
function testClickNoWait(ctrl) {
  return settle(dispatch(el(ctrl), "点击"));
}

// 从上次问到现在，宿主被要求做了几件事（问完清零）。
function testOps() {
  const out = lc.dictOf("新建", ops.新建, "写", ops.写, "插入", ops.插入, "拿走", ops.拿走);
  ops.新建 = ops.写 = ops.插入 = ops.拿走 = 0;
  return out;
}

const testNetCount = () => netCount;

function ready() {}

module.exports = {
  tickDefer, tickWait, logError, ready,
  uiRoot, uiCreate, uiSet, uiGet, uiInsert, uiRemove, uiOn,
  netFetch, netRequest, envGet,
  testPage, testTree, testFind, testClick, testInput, testClickNoWait, testOps, testNetCount,
};
