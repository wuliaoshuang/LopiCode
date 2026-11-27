/// 规矩版本 2 的小库·浏览器版。公共部分（值、文字、列表、字典、JSON、“要等的事”）和 Node 那份是同一段字（rt2_js.dart、
/// rt2_js_task.dart）；这里只写浏览器自己的：现在是哪条线、宿主（打印、时间、随机）、20 个原生绑定、旧页面积木的旧规矩、
/// 没人接的错交给谁。规矩见 docs/blocks-v5-parts/D-frontend-logic.md §2.3 和末尾的“落地说明（第四轮·A2）”。
///
/// 样子：一个函数 `lcRuntime(win)`，交回小库对象 `lc`。`win` 是浏览器的 window（测试里换成假的）——所有浏览器能力都从它身上拿，
/// 不直接碰全局。纯网页产物里直接放进 logic.js；Vue / React 产物里前面加 `export` 成一个模块。
library;

import 'package:lopicode/lang/rt2_js.dart';
import 'package:lopicode/lang/rt2_js_task.dart';

/// 浏览器小库在工程里的文件名（Vue / React 产物）。
const String kRt2BrowserFile = 'lc2.js';

const String kRt2BrowserSource =
    r'''
// LopiCode 积木的小库（浏览器，严格规矩）。由 LopiCode 生成，别手改。
function lcRuntime(win) {
"use strict";
''' +
    kRt2JsValues +
    r'''
// —— 输出：写到控制台 ——
const log = (s) => { win.console.log(s); };

''' +
    kRt2JsMore +
    r'''
// —— 两边的值怎么对：状态、存储、历史里放的是普通的 JSON 值（数组、普通对象）；程序里对象是字典（Map）——
function fromPlain(v) {
  if (v === undefined || v === null) return null;
  if (Array.isArray(v)) return v.map(fromPlain);
  if (typeof v === "object" && !(v instanceof Map) && Object.getPrototypeOf(v) === Object.prototype) {
    const m = new Map();
    for (const k of Object.keys(v)) m.set(k, fromPlain(v[k]));
    return m;
  }
  return v;
}
function toPlain(v) {
  if (v === undefined || v === null) return null;
  if (Array.isArray(v)) return v.map(toPlain);
  if (v instanceof Map) { const o = {}; for (const k of keys(v)) o[k] = toPlain(v.get(k)); return o; }
  return v;
}

// —— 没人接的错：交给“当页面出错时”；没有人管就写到控制台 ——
const failHandlers = [];
const errText = (e) => (e instanceof LcError ? e.message : String((e && e.message) || e));
let reporting = false;
function report(e) {
  if (reporting || failHandlers.length === 0) { win.console.error("出错：" + errText(e)); return; }
  reporting = true;
  try { for (const f of failHandlers.slice()) f(errText(e)); } catch (e2) { win.console.error("出错：" + errText(e2)); } finally { reporting = false; }
}
const onFail = (f) => { failHandlers.push(f); };

// —— 宿主里两边都有的几个 ——
function hostPrint(s, ch) {
  if (ch === "out") win.console.log(s);
  else if (ch === "err") win.console.error(s);
  else fail("通道只能是 out 或 err");
}
const hostNow = () => Date.now();
function hostRandomBytes(n) {
  if (n < 1 || n > 1024) fail("随机字节的个数要在 1 到 1024 之间");
  return Array.from(win.crypto.getRandomValues(new Uint8Array(n)));
}

// —— 要等的事 ——
// “这条线”：一件事（页面开始时那一段、一次事件回调、一次“开始做”）。浏览器里没有现成的办法记“现在跑的是哪一条”，
// 小库自己记在 cur 里：每个“等”回来的时候由生成的代码放回去（back），所以一段不停下来的代码里 cur 总是对的。
const mainLine = { cancelled: false, wake: null };
let cur = mainLine;
const lineNow = () => cur;
const safe = (p) => Promise.resolve(p).then((v) => ({ v }), (e) => ({ e }));
function back(line, r) {
  cur = line;
  if ("e" in r) throw r.e;
  return r.v;
}
function inLine(line, f) {
  const prev = cur;
  cur = line;
  try { return f(); } finally { cur = prev; }
}
''' +
    kRt2JsTaskA +
    r'''
// 开始做一件事：马上开始（做到它第一件要等的事为止），拿到“稍后的结果”；出了错先记着，等它的时候再抛。
function spawn(f) {
  const t = { done: false, val: null, err: null, line: { cancelled: false, wake: null }, p: null };
  t.p = inLine(t.line, async () => {
    try { t.val = await f(); return t.val; } catch (e) { t.err = e; throw e; } finally { t.done = true; }
  });
  t.p.catch(() => {});
  return t;
}
''' +
    kRt2JsTaskB +
    r'''
// 浏览器叫回来的时候（事件、定时、当…变了）：当成新的一条线跑；出了错没人接＝交给“当页面出错时”。
function fire(f, ...args) {
  let r;
  try { r = inLine({ cancelled: false, wake: null }, () => f(...args)); } catch (e) { report(e); return; }
  if (r instanceof Promise) r.catch(report);
}
// 跑页面开始时那一段。交回一个“做完了”的记号（里面有要等的事就等它做完；出了错已经交出去了，这里不再抛）。
function run(main) {
  let r;
  try { r = inLine(mainLine, main); } catch (e) { report(e); return Promise.resolve(); }
  return r instanceof Promise ? r.then(() => {}, report) : Promise.resolve();
}

// —— 原生绑定·定时 ——
let timerSeq = 0;
const timers = new Map();
function timerAfter(ms, f) {
  const id = ++timerSeq;
  timers.set(id, ["t", win.setTimeout(() => { timers.delete(id); fire(f); }, Math.max(0, ms))]);
  return id;
}
function timerEvery(ms, f) {
  const id = ++timerSeq;
  timers.set(id, ["i", win.setInterval(() => fire(f), Math.max(0, ms))]);
  return id;
}
function timerFrame(f) {
  const id = ++timerSeq;
  const go = (t) => { timers.delete(id); fire(f, typeof t === "number" ? t : Date.now()); };
  timers.set(id, win.requestAnimationFrame ? ["f", win.requestAnimationFrame(go)] : ["t", win.setTimeout(go, 16)]);
  return id;
}
function timerCancel(id) {
  const t = timers.get(id);
  if (!t) return null;
  timers.delete(id);
  if (t[0] === "t") win.clearTimeout(t[1]);
  else if (t[0] === "i") win.clearInterval(t[1]);
  else win.cancelAnimationFrame(t[1]);
  return null;
}

// —— 原生绑定·请求 ——
// 只有网络层失败才出错（连不上、超时、被中止）；404、500 是正常交回的回应，自己看 status / ok。
const REQ_METHODS = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"];
const netAbortNew = () => ({ lcAbort: true, aborted: false, subs: new Set() });
function netAbort(token) {
  if (!token || token.lcAbort !== true) fail("这不是一个中止令牌");
  if (token.aborted) return null;
  token.aborted = true;
  for (const f of [...token.subs]) f();
  return null;
}
function netRequest(req) {
  const url = req.get("url");
  if (typeof url !== "string" || url === "") fail("请求不了：没有写网址");
  const method = req.has("method") && req.get("method") !== null ? String(req.get("method")).toUpperCase() : "GET";
  if (!REQ_METHODS.includes(method)) fail("请求不了：不认识的方式「" + method + "」");
  const ms = req.has("timeoutMs") && typeof req.get("timeoutMs") === "number" ? req.get("timeoutMs") : 0;
  const token = req.has("abort") ? req.get("abort") : null;
  if (token !== null && (!token || token.lcAbort !== true)) fail("请求不了：abort 里放的不是中止令牌");
  const headers = {};
  const hs = req.has("headers") ? req.get("headers") : null;
  if (hs instanceof Map) for (const k of keys(hs)) headers[k] = String(hs.get(k));
  const init = { method, headers };
  const body = req.has("body") ? req.get("body") : null;
  if (body !== null && method !== "GET" && method !== "HEAD") init.body = typeof body === "string" ? body : toJson(body);
  return pause((ok, bad) => {
    const ctl = new win.AbortController();
    init.signal = ctl.signal;
    let why = null;
    const stop = () => { why = why || "已中止"; ctl.abort(); };
    const timer = ms > 0 ? win.setTimeout(() => { why = "超时"; ctl.abort(); }, ms) : null;
    if (token) { if (token.aborted) why = "已中止"; else token.subs.add(stop); }
    if (why !== null) { bad(new LcError(why)); return null; }
    win.fetch(url, init).then((res) => res.text().then((text) => {
      const back = new Map();
      res.headers.forEach((v, k) => back.set(k.toLowerCase(), v));
      ok(new Map([["status", res.status], ["ok", res.ok === true], ["headers", back], ["body", text]]));
    })).catch(() => bad(new LcError(why || "请求不了：连不上")));
    return () => { if (timer !== null) win.clearTimeout(timer); if (token) token.subs.delete(stop); ctl.abort(); };
  });
}

// —— 原生绑定·存储（区：local＝长期、session＝本次）——
function storageArea(area) {
  let s = null;
  try { s = area === "local" ? win.localStorage : area === "session" ? win.sessionStorage : null; } catch (e) { fail("这里用不了本地存储"); }
  if (area !== "local" && area !== "session") fail("存储的区只能是 local 或 session");
  if (!s) fail("这里用不了本地存储");
  return s;
}
function storageRead(area, key) {
  const v = storageArea(area).getItem(key);
  return v === null || v === undefined ? null : String(v);
}
function storageWrite(area, key, value) {
  const s = storageArea(area);
  try { s.setItem(key, value); } catch (e) { fail("存不进去：地方不够了，或者浏览器不让存"); }
  return null;
}
function storageRemove(area, key) { storageArea(area).removeItem(key); return null; }
function storageKeys(area) {
  const s = storageArea(area);
  const out = [];
  for (let i = 0; i < s.length; i++) out.push(String(s.key(i)));
  return out.sort(cmpText);
}

// —— 原生绑定·地址和历史 ——
function locNow() {
  const l = win.location;
  return new Map([["href", l.href], ["path", l.pathname], ["query", l.search], ["hash", l.hash], ["state", fromPlain(win.history.state)]]);
}
function locPush(url, state) { win.history.pushState(toPlain(state), "", url); return null; }
function locReplace(url, state) { win.history.replaceState(toPlain(state), "", url); return null; }
function locGo(n) { win.history.go(n); return null; }
function locOnPop(f) {
  const h = (ev) => fire(f, fromPlain(ev.state));
  win.addEventListener("popstate", h);
  return () => { win.removeEventListener("popstate", h); return null; };
}
function locAssign(url) { win.location.href = url; return null; }

// —— 原生绑定·对话框 ——
function pageAlert(s) { win.alert(s); return null; }
const pageConfirm = (s) => win.confirm(s) === true;

// —— 事件记录（界面的事件和窗口的事件都交这个样子）——
function eventRec(ev) {
  const t = ev && ev.target ? ev.target : null;
  const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
  return new Map([
    ["value", t && t.value !== null && t.value !== undefined ? String(t.value) : ""],
    ["checked", !!(t && t.checked === true)],
    ["key", ev && typeof ev.key === "string" ? ev.key : ""],
    ["x", num(ev && ev.clientX)],
    ["y", num(ev && ev.clientY)],
    ["target", t && typeof t.id === "string" ? t.id : ""],
    ["preventDefault", () => { if (ev && ev.preventDefault) ev.preventDefault(); return null; }],
    ["stopPropagation", () => { if (ev && ev.stopPropagation) ev.stopPropagation(); return null; }],
  ]);
}
// —— 原生绑定·窗口事件 ——
function winOn(target, type, f, opts) {
  const on = target === "window" ? win : target === "document" ? win.document : fail("窗口事件的对象只能是 window 或 document");
  const o = { once: opts.get("once") === true, passive: opts.get("passive") === true };
  const h = (ev) => fire(f, eventRec(ev));
  on.addEventListener(type, h, o);
  return () => { on.removeEventListener(type, h, o); return null; };
}

// —— 旧页面积木的旧规矩（和旧生成器里的 lcNum / lcText / lcEq 同一个算法（logic_js_core.dart 的 lcJsRuntime））——
function oldNum(v) {
  const n = typeof v === "string" ? Number(v.trim()) : Number(v);
  return Number.isFinite(n) ? n : 0;
}
function oldText(v) {
  if (v === null || v === undefined) return "";
  if (typeof v === "number") return String(Number(v.toPrecision(12)));
  return String(v);
}
function oldEq(a, b) {
  return typeof a === typeof b ? a === b : oldText(a) === oldText(b);
}
const oldTruthy = (v) => !!v;
function oldOp(op, a, b) {
  switch (op) {
    case "+": return a + b;
    case "-": return a - b;
    case "*": return a * b;
    case "/": return oldNum(a / b);
    case "%": return oldNum(a % b);
    case "<": return a < b;
    case ">": return a > b;
    case "<=": return a <= b;
    case ">=": return a >= b;
    case "===": return a === b;
    case "!==": return a !== b;
    case "min": return Math.min(a, b);
    default: return fail("不认识的运算「" + op + "」");
  }
}
const oldLog = (v) => { win.console.log(toPlain(v)); return null; };

return {
  LcError, errKind, errSetup, errObj, kindOf, Rec, Variant, Enum, Obj, MAX, fail, fmtNum, itext, boolText,
  iadd, isub, imul, imod, idiv, fdiv, fpow, toInt, floor, ceil, round, sqrt, now, steps, fsteps,
  textLen, cmpText, substring, charAt, codePoints, split, startsWith, endsWith, contains, indexOf, replace, trim, upper, lower,
  repeatText, parseInt: parseInt_,
  kind, asNum, asInt, asText, asBool, asFn, asList, asDict, asOpt, asA, isKind, asKind, widenOpt, asListOf, asDictOf, toDyn,
  eq, cmp, dcmp, at, setAt, push, pop, len, items, keys, get, dictSet, dictRemove, dictKeys, dictValues, dictHas, must,
  listMap, listFilter, listReduce, listFind, listEvery, listSome, listEach, listJoin, listReverse, listConcat, listSlice,
  listIndexOf, listContains, range, recCopy,
  abs, max, min, random, copy, template, toBool, listInsert, listRemove, listSort, dictPairs,
  dadd, dsub, dmul, ddiv, dpow, didiv, dmod, dynGet, dynSet, dynPush, dynPop, dynRemove, dynOrElse, dynSize,
  toJson, fromJson, dtext, log, run, isNumeric, isType, dictMerge, toNumber, urlDecode,
  hostPrint, hostNow, hostSleep, hostRandomBytes, spawn, wait, awaitMax, awaitAll, awaitAny, cancel, cancelled, lockEnter, lockLeave,
  lineNow, safe, back, inLine, fire, report, onFail, fromPlain, toPlain, eventRec, errText,
  timerAfter, timerEvery, timerCancel, timerFrame, netRequest, netAbortNew, netAbort,
  storageRead, storageWrite, storageRemove, storageKeys,
  locNow, locPush, locReplace, locGo, locOnPop, locAssign, pageAlert, pageConfirm, winOn,
  oldNum, oldText, oldEq, oldTruthy, oldOp, oldLog,
};
}
''';
