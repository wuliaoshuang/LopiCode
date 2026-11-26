/// 规矩版本 2 的小库·Node.js（`lc2.js`）。规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、8、11 节。
///
/// 值在 JS 里的样子：整数、小数＝number；文字＝string；是否＝boolean；空＝null；列表＝Array；字典＝Map（键是文字，
/// 遍历按码点从小到大）；记录 / 变体 / 枚举 / 对象＝生成的 class（分别继承 Rec / Variant / Enum / Obj）；函数＝function。
library;

const String kRt2NodeSource = r'''
// LopiCode 积木的小库（Node.js，严格规矩）。由 LopiCode 生成，别手改。
"use strict";
// 抛出去的错：外面这层带着那句话；obj 是错误对象（小库自己报的错没有，接住的时候才按种类造）。
class LcError extends Error {
  constructor(m, obj) { super(m); this.obj = obj === undefined ? null : obj; }
}
const ERR_KINDS = [["除以 0", "数值不对"], ["整数超出范围", "数值不对"], ["变不成整数", "数值不对"], ["超出了", "找不到"], ["拿到的是", "类型不对"], ["值是空", "类型不对"]];
const errKind = (m) => { for (const [part, k] of ERR_KINDS) if (m.includes(part)) return k; return "错误"; };
let errMake = null;
const errSetup = (f) => { errMake = f; };
const errObj = (e) => { if (e.obj === null) e.obj = errMake(errKind(e.message), e.message); return e.obj; };
const kindOf = (x) => x.constructor.lcName;
class Rec {}
class Variant extends Rec {}
class Enum { constructor(name, index) { this.name = name; this.index = index; Object.freeze(this); } }
class Obj {}
const MAX = 9007199254740991;
const fail = (m) => { throw new LcError(m); };

function fmtNum(n) {
  if (Number.isNaN(n)) return "不是数";
  if (n === Infinity) return "无穷大";
  if (n === -Infinity) return "-无穷大";
  if (n === 0) return "0";
  if (Number.isInteger(n) && Math.abs(n) <= MAX) return String(n);
  const m = /^(-?)([0-9])(?:\.([0-9]+))?e([+-][0-9]+)$/.exec(n.toExponential(11));
  const digits = (m[2] + (m[3] || "")).replace(/0+$/, "");
  const e = Number(m[4]);
  if (e >= 15 || e < -7) return m[1] + digits[0] + (digits.length > 1 ? "." + digits.slice(1) : "") + "e" + e;
  if (e >= digits.length - 1) return m[1] + digits + "0".repeat(e - digits.length + 1);
  if (e >= 0) return m[1] + digits.slice(0, e + 1) + "." + digits.slice(e + 1);
  return m[1] + "0." + "0".repeat(-e - 1) + digits;
}
const itext = (n) => String(n);
const boolText = (b) => (b ? "true" : "false");

// —— 整数、小数 ——
const chk = (r) => (Number.isSafeInteger(r) ? r + 0 : fail("整数超出范围"));
const iadd = (a, b) => chk(a + b);
const isub = (a, b) => chk(a - b);
const imul = (a, b) => chk(a * b);
const imod = (a, b) => (b === 0 ? fail("除以 0") : (a % b) + 0);
const idiv = (a, b) => (b === 0 ? fail("除以 0") : (a - (a % b)) / b + 0);
const fdiv = (a, b) => (b === 0 ? fail("除以 0") : a / b);
const fpow = (a, b) => Math.pow(a, b);
const toInt = (x) => (Number.isFinite(x) && Math.abs(Math.trunc(x)) <= MAX ? Math.trunc(x) + 0 : fail("这个小数变不成整数：" + fmtNum(x)));
const floor = (x) => toInt(Math.floor(x));
const ceil = (x) => toInt(Math.ceil(x));
function round(x) {
  if (!Number.isFinite(x)) return toInt(x);
  const t = Math.trunc(x);
  return toInt(Math.abs(x - t) >= 0.5 ? t + (x < 0 ? -1 : 1) : t);
}
const sqrt = (x) => Math.sqrt(x);
const now = () => Date.now();
function steps(a, b, s) {
  if (s === 0) return 0;
  const d = (b - a) / s;
  return d >= 0 ? Math.floor(d) + 1 : 0;
}
function fsteps(a, b, s) {
  if (s === 0) return 0;
  const d = (b - a) / s;
  return d >= 0 ? Math.min(Math.floor(d + 1e-9) + 1, MAX) : 0;
}

// —— 文字（按码点） ——
const cps = (s) => Array.from(s);
const textLen = (s) => cps(s).length;
function cmpText(a, b) {
  const x = cps(a), y = cps(b);
  for (let i = 0; i < x.length && i < y.length; i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return x.length === y.length ? 0 : x.length < y.length ? -1 : 1;
}
const clamp = (i, n) => (i < 0 ? 0 : i > n ? n : i);
function substring(s, from, to) {
  const cs = cps(s);
  const a = clamp(from, cs.length), b = clamp(to, cs.length);
  return a >= b ? "" : cs.slice(a, b).join("");
}
function charAt(s, i) {
  const cs = cps(s);
  return i >= 0 && i < cs.length ? cs[i] : fail("位置 " + i + " 超出了文字的范围（共 " + cs.length + " 个字）");
}
const codePoints = (s) => cps(s).map((c) => c.codePointAt(0));
const split = (s, sep) => (sep === "" ? cps(s) : s.split(sep));
const startsWith = (s, p) => s.startsWith(p);
const endsWith = (s, p) => s.endsWith(p);
const contains = (s, p) => s.includes(p);
function indexOf(s, p) {
  const at = s.indexOf(p);
  return at < 0 ? -1 : textLen(s.slice(0, at));
}
const replace = (s, from, to) => (from === "" ? s : s.split(from).join(to));
const trim = (s) => s.trim();
const upper = (s) => s.toUpperCase();
const lower = (s) => s.toLowerCase();
const repeatText = (s, n) => (n <= 0 ? "" : s.repeat(n));
const parseInt_ = (s) => (/^-?[0-9]+$/.test(s) && Number.isSafeInteger(Number(s)) ? Number(s) + 0 : null);

// —— 这个值是什么 ——
function kind(x) {
  if (x === null || x === undefined) return "空";
  if (typeof x === "boolean") return "是否";
  if (typeof x === "number") return "数字";
  if (typeof x === "string") return "文字";
  if (Array.isArray(x)) return "列表";
  if (x instanceof Map) return "字典";
  if (typeof x === "function") return "函数";
  return "「" + (x.constructor.lcName || "对象") + "」";
}
const want = (name, x) => fail("这里要" + name + "，拿到的是" + kind(x));
const asNum = (x) => (typeof x === "number" ? x : want("小数", x));
const asInt = (x) => (typeof x !== "number" ? want("整数", x) : Number.isSafeInteger(x) ? x : fail("这里要整数，拿到的是 " + fmtNum(x)));
const asText = (x) => (typeof x === "string" ? x : want("文字", x));
const asBool = (x) => (typeof x === "boolean" ? x : want("是否", x));
const asFn = (x) => (typeof x === "function" ? x : want("函数", x));
const asList = (x) => (Array.isArray(x) ? x : want("列表", x));
const asDict = (x) => (x instanceof Map ? x : want("字典", x));
const asOpt = (x, f) => (x === null || x === undefined ? null : f(x));
const asA = (x, type, name) => (x instanceof type ? x : want("「" + name + "」", x));
const isKind = (x, name) => x instanceof Obj && (x.constructor.lcKinds || []).includes(name);
const asKind = (x, name) => (isKind(x, name) ? x : want("「" + name + "」", x));
const widenOpt = (x) => x;
function inside(where, f) {
  try { return f(); } catch (e) { if (!(e instanceof LcError)) throw e; return fail(where + "：" + e.message); }
}
const asListOf = (x, f) => asList(x).map((v, i) => inside("列表的位置 " + i, () => f(v)));
const asDictOf = (x, f) => new Map(keys(asDict(x)).map((k) => [k, inside("字典的「" + k + "」", () => f(x.get(k)))]));
// 确定类型的列表 / 字典装进“任意”：拍一份快照
const toDyn = (x) => (Array.isArray(x) ? x.map(toDyn) : x instanceof Map ? new Map([...x].map(([k, v]) => [k, toDyn(v)])) : x);

// —— 相等、比大小 ——
function eq(a, b) {
  if (a === b) return true;
  if (a === null || a === undefined || b === null || b === undefined) return (a ?? null) === (b ?? null);
  if (Array.isArray(a)) return Array.isArray(b) && a.length === b.length && a.every((v, i) => eq(v, b[i]));
  if (a instanceof Map) {
    if (!(b instanceof Map) || a.size !== b.size) return false;
    for (const [k, v] of a) if (!b.has(k) || !eq(v, b.get(k))) return false;
    return true;
  }
  if (a instanceof Rec) return b instanceof Rec && a.constructor === b.constructor && Object.keys(a).every((k) => eq(a[k], b[k]));
  return false;
}
const cmp = (a, b) => (typeof a === "string" ? cmpText(a, b) : a < b ? -1 : a > b ? 1 : 0);
function dcmp(a, b) {
  if (typeof a === "number" && typeof b === "number") return cmp(a, b);
  if (typeof a === "string" && typeof b === "string") return cmpText(a, b);
  return fail("比大小的两边要都是数字或者都是文字，拿到的是" + kind(a) + "和" + kind(b));
}

// —— 列表、字典 ——
const outOf = (i, n) => fail("位置 " + i + " 超出了列表的范围（共 " + n + " 项）");
const at = (xs, i) => (i >= 0 && i < xs.length ? xs[i] : outOf(i, xs.length));
const setAt = (xs, i, v) => { if (i >= 0 && i < xs.length) xs[i] = v; else outOf(i, xs.length); };
const push = (xs, v) => { xs.push(v); };
const pop = (xs) => (xs.length > 0 ? xs.pop() : null);
const len = (x) => (x instanceof Map ? x.size : x.length);
const items = (xs) => xs.slice();
const keys = (d) => Array.from(d.keys()).sort(cmpText);
const get = (d, k) => (d.has(k) ? d.get(k) : null);
const dictSet = (d, k, v) => { d.set(k, v); };
const dictRemove = (d, k) => { d.delete(k); };
const dictKeys = keys;
const dictValues = (d) => keys(d).map((k) => d.get(k));
const dictHas = (d, k) => d.has(k);
const must = (x) => (x === null || x === undefined ? fail("这里的值是空，不能直接用") : x);
const listMap = (xs, f) => items(xs).map((v) => f(v));
const listFilter = (xs, f) => items(xs).filter((v) => f(v));
const listReduce = (xs, f, init) => items(xs).reduce((acc, v) => f(acc, v), init);
function listFind(xs, f) { for (const v of items(xs)) if (f(v)) return v; return null; }
const listEvery = (xs, f) => items(xs).every((v) => f(v));
const listSome = (xs, f) => items(xs).some((v) => f(v));
const listEach = (xs, f) => { for (const v of items(xs)) f(v); };
const listJoin = (xs, sep) => xs.join(sep);
const listReverse = (xs) => xs.slice().reverse();
const listConcat = (a, b) => a.concat(b);
function listSlice(xs, from, to) {
  const a = clamp(from, xs.length), b = clamp(to, xs.length);
  return a >= b ? [] : xs.slice(a, b);
}
const listIndexOf = (xs, v) => xs.findIndex((x) => eq(x, v));
const listContains = (xs, v) => listIndexOf(xs, v) >= 0;
function range(a, b) { const out = []; for (let i = a; i <= b; i++) out.push(i); return out; }
function recCopy(r, changes) {
  const o = Object.create(Object.getPrototypeOf(r));
  return Object.freeze(Object.assign(o, r, changes));
}

// —— “任意”的值之间（严格：不偷偷转换） ——
const dnum = (op, x) => (typeof x === "number" ? x : fail(op + "的两边要数字，拿到的是" + kind(x)));
const dadd = (a, b) => dnum("加法", a) + dnum("加法", b);
const dsub = (a, b) => dnum("减法", a) - dnum("减法", b);
const dmul = (a, b) => dnum("乘法", a) * dnum("乘法", b);
const ddiv = (a, b) => fdiv(dnum("除法", a), dnum("除法", b));
const dpow = (a, b) => fpow(dnum("乘方", a), dnum("乘方", b));
const didiv = (a, b) => idiv(asInt(a), asInt(b));
const dmod = (a, b) => imod(asInt(a), asInt(b));
function dynGet(x, k) {
  if (Array.isArray(x)) return at(x, asInt(k));
  if (x instanceof Map) return get(x, asText(k));
  return fail("这里要列表或字典，拿到的是" + kind(x));
}
function dynSet(x, k, v) {
  if (Array.isArray(x)) return setAt(x, asInt(k), v);
  if (x instanceof Map) return dictSet(x, asText(k), v);
  return fail("这里要列表或字典，拿到的是" + kind(x));
}
const dynPush = (x, v) => push(asList(x), v);
const dynPop = (x) => pop(asList(x));
const dynRemove = (x, k) => dictRemove(asDict(x), asText(k));
const dynOrElse = (x, d) => (x === null || x === undefined ? d : x);
function dynSize(x) {
  if (typeof x === "string") return textLen(x);
  if (Array.isArray(x) || x instanceof Map) return len(x);
  return fail("这里要文字、列表或字典，拿到的是" + kind(x));
}
function toJson(x) {
  if (x === null || x === undefined) return "null";
  if (typeof x === "boolean") return boolText(x);
  if (typeof x === "number") return Number.isFinite(x) ? fmtNum(x) : "null";
  if (typeof x === "string") return JSON.stringify(x.toWellFormed());
  if (Array.isArray(x)) return "[" + x.map(toJson).join(",") + "]";
  if (x instanceof Map) return "{" + keys(x).map((k) => JSON.stringify(k.toWellFormed()) + ":" + toJson(x.get(k))).join(",") + "}";
  if (x instanceof Enum) return JSON.stringify(x.name);
  if (x instanceof Rec) return "{" + Object.keys(x).sort(cmpText).map((k) => JSON.stringify(k.replace(/^m_/, "")) + ":" + toJson(x[k])).join(",") + "}";
  return "null";
}
function fromJson(s) {
  const conv = (v) => (Array.isArray(v) ? v.map(conv) : v !== null && typeof v === "object" ? new Map(Object.keys(v).map((k) => [k, conv(v[k])])) : v);
  try { return conv(JSON.parse(s)); } catch (e) { return fail("这段文字不是 JSON"); }
}
function dtext(x) {
  if (x === null || x === undefined) return "";
  if (typeof x === "boolean") return boolText(x);
  if (typeof x === "number") return fmtNum(x);
  if (typeof x === "string") return x;
  if (typeof x === "function") return "[函数]";
  if (x instanceof Enum) return x.name;
  if (Array.isArray(x) || x instanceof Map || x instanceof Rec) return toJson(x);
  return "[" + (x.constructor.lcName || "对象") + "]";
}

// —— 输出：写一行就马上写出去（服务被关掉的时候不会丢）——
let wrote = false;
const log = (s) => { wrote = true; process.stdout.write(s + "\n"); };

// —— 是不是数字、网址解码 ——
const NUM = /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/;
const numTrim = (s) => s.replace(/^[ \t\n\r]+|[ \t\n\r]+$/g, "");
// 这个值是不是某一类：null bool number text list dict function object。
function isType(x, name) {
  switch (name) {
    case "null": return x === null || x === undefined;
    case "bool": return typeof x === "boolean";
    case "number": return typeof x === "number";
    case "text": return typeof x === "string";
    case "list": return Array.isArray(x);
    case "dict": return x instanceof Map;
    case "function": return typeof x === "function";
    case "object": return x instanceof Obj || x instanceof Rec || x instanceof Enum;
  }
  return fail("没有「" + name + "」这一类值");
}
// 两个字典合成一个新的：后面的盖住前面的。
const dictMerge = (a, b) => new Map([...a, ...b]);
const isNumeric = (x) => typeof x === "number" || (typeof x === "string" && NUM.test(numTrim(x)) && Number.isFinite(Number(numTrim(x))));
const toNumber = (s) => (isNumeric(s) ? Number(numTrim(s)) : fail("「" + s + "」变不成数字"));
function urlDecode(s) {
  try { return decodeURIComponent(s); } catch (e) { return fail("这段网址编码解不开"); }
}

// —— 宿主（清单见 host_v2.dart）——
function hostPrint(s, ch) {
  if (ch === "out") log(s);
  else if (ch === "err") process.stderr.write(s + "\n");
  else fail("通道只能是 out 或 err");
}
const hostNow = () => Date.now();
const copyVal = (v) => (Array.isArray(v) ? v.map(copyVal) : v instanceof Map ? new Map([...v].map(([k, x]) => [k, copyVal(x)])) : v);
const store = new Map();
const storeBusy = new Set();
const storeRead = (name) => (store.has(name) ? copyVal(store.get(name)) : null);
// Node 只有一条线，改格子的函数又不许“等”，所以别人插不进来；函数里再改同一个格子＝报错。
function storeUpdate(name, f) {
  if (storeBusy.has(name)) fail("「" + name + "」这个格子正在改，不能在改它的函数里再改它");
  storeBusy.add(name);
  try {
    const v = copyVal(f(storeRead(name)));
    store.set(name, v);
    return copyVal(v);
  } finally { storeBusy.delete(name); }
}
const hostEnv = (name) => { const v = process.env[name]; return v === undefined ? null : v; };

// —— 要等的事 ——
const hostSleep = (ms) => new Promise((done) => setTimeout(() => done(null), Math.max(0, ms)));
// 开始做一件事：马上开始，拿到“稍后的结果”；出了错先记着，等它的时候再抛。
function spawn(f) {
  const p = f();
  p.catch(() => {});
  return p;
}

// —— 开服务（细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节）——
const BODY_LIMIT = 1048576;
const errText = (e) => (e instanceof LcError ? "出错：" + e.message : String((e && e.stack) || e));
function writeRaw(req, res, status, headers, text) {
  const bytes = Buffer.from(text, "utf8");
  const noBody = status === 204 || status === 304 || status < 200;
  const list = [];
  for (const k of keys(headers)) if (k.toLowerCase() !== "content-length") list.push([k, dtext(headers.get(k))]);
  if (!noBody) list.push(["Content-Length", String(bytes.length)]);
  res.writeHead(status, list);
  res.end(noBody || req.method === "HEAD" ? undefined : bytes);
}
const hostError = (req, res, status, message) =>
  writeRaw(req, res, status, new Map([["Content-Type", "application/json; charset=utf-8"]]), toJson(new Map([["error", message]])));
async function serveOne(req, res, handler) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total <= BODY_LIMIT) chunks.push(chunk);
  }
  if (total > BODY_LIMIT) return hostError(req, res, 413, "请求内容太大");
  let body;
  try { body = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.concat(chunks)); } catch (e) { body = null; }
  const headers = new Map();
  for (let i = 0; i + 1 < req.rawHeaders.length; i += 2) {
    const name = req.rawHeaders[i].toLowerCase();
    const value = req.rawHeaders[i + 1].replace(/^[ \t]+|[ \t]+$/g, "");
    headers.set(name, headers.has(name) ? headers.get(name) + ", " + value : value);
  }
  const url = req.url || "/";
  const q = url.indexOf("?");
  const request = new Map([["method", req.method], ["path", q < 0 ? url : url.slice(0, q)], ["query", q < 0 ? "" : url.slice(q + 1)], ["headers", headers], ["body", body]]);
  let out;
  try { out = await handler(request); } catch (e) {
    process.stderr.write(errText(e) + "\n");
    return hostError(req, res, 500, "服务器内部出错");
  }
  const status = out instanceof Map ? out.get("status") : null;
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    process.stderr.write("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）\n");
    return hostError(req, res, 500, "服务器内部出错");
  }
  const hs = out.get("headers");
  return writeRaw(req, res, status, hs instanceof Map ? hs : new Map(), dtext(out.get("body")));
}
// 一直服务，不返回；端口用不了＝出错。
function hostServe(port, host, handler) {
  return new Promise((done, bad) => {
    if (port < 0 || port > 65535) return bad(new LcError("开不了服务：端口要在 0 到 65535 之间"));
    const server = require("node:http").createServer((req, res) => {
      serveOne(req, res, handler).catch((e) => {
        process.stderr.write(errText(e) + "\n");
        if (!res.headersSent) hostError(req, res, 500, "服务器内部出错");
        else res.destroy();
      });
    });
    server.on("error", () => bad(new LcError("开不了服务：" + host + ":" + port + " 用不了")));
    server.listen(port, host, () => log("后端已启动：http://" + host + ":" + server.address().port));
  });
}

function fatal(e) {
  if (!(e instanceof LcError)) throw e;
  log("出错：" + e.message);
  process.exitCode = 1;
}
// 跑主程序。什么都没写过的，最后补一个空行（和原来“攒到最后一次写”的样子一样）。
const finish = () => { if (!wrote) process.stdout.write("\n"); };
function run(main) {
  let r;
  try { r = main(); } catch (e) {
    try { fatal(e); } finally { finish(); }
    return;
  }
  if (r instanceof Promise) r.then(finish, (e) => { try { fatal(e); } finally { finish(); } });
  else finish();
}

module.exports = {
  LcError, errKind, errSetup, errObj, kindOf, Rec, Variant, Enum, Obj, MAX, fail, fmtNum, itext, boolText,
  iadd, isub, imul, imod, idiv, fdiv, fpow, toInt, floor, ceil, round, sqrt, now, steps, fsteps,
  textLen, cmpText, substring, charAt, codePoints, split, startsWith, endsWith, contains, indexOf, replace, trim, upper, lower,
  repeatText, parseInt: parseInt_,
  kind, asNum, asInt, asText, asBool, asFn, asList, asDict, asOpt, asA, isKind, asKind, widenOpt, asListOf, asDictOf, toDyn,
  eq, cmp, dcmp, at, setAt, push, pop, len, items, keys, get, dictSet, dictRemove, dictKeys, dictValues, dictHas, must,
  listMap, listFilter, listReduce, listFind, listEvery, listSome, listEach, listJoin, listReverse, listConcat, listSlice,
  listIndexOf, listContains, range, recCopy,
  dadd, dsub, dmul, ddiv, dpow, didiv, dmod, dynGet, dynSet, dynPush, dynPop, dynRemove, dynOrElse, dynSize,
  toJson, fromJson, dtext, log, run, isNumeric, isType, dictMerge, toNumber, urlDecode,
  hostPrint, hostNow, hostEnv, hostSleep, hostServe, spawn, storeRead, storeUpdate,
};
''';
