/// 规矩版本 2 的小库·JS 公共部分（Node 的 `lc2.js` 和浏览器的小运行时都从这里拼）：值的规矩、文字、列表、字典、JSON……
/// 只用语言自带的东西，不碰 Node、不碰浏览器。Node 那份拼出来和拆之前逐字节一样（test/lang_js_split_test.dart 钉着）。
library;

/// 从“抛出去的错”到“变成文字”（dtext）。
const String kRt2JsValues = r'''
// 抛出去的错：外面这层带着那句话；obj 是错误对象（小库自己报的错没有，接住的时候才按种类造）。
class LcError extends Error {
  constructor(m, obj) { super(m); this.obj = obj === undefined ? null : obj; }
}
const ERR_KINDS = [["除以 0", "数值不对"], ["整数超出范围", "数值不对"], ["变不成整数", "数值不对"], ["超出了", "找不到"], ["拿到的是", "类型不对"], ["值是空", "类型不对"], ["还没做完", "超时"], ["被取消了", "取消了"]];
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
function range(a, b, s) { const n = Math.min(steps(a, b, s), 10000), out = []; for (let k = 0; k < n; k++) out.push(a + k * s); return out; }
// —— 后端积木里早就有的那几个（严格规矩下的说法见 rt_v2.dart） ——
const numArg = (name, x) => (typeof x === "number" ? x : fail("「" + name + "」要数字，拿到的是" + kind(x)));
const abs = (x) => Math.abs(numArg("绝对值", x)) + 0;
const max = (a, b) => (numArg("较大的", a) >= numArg("较大的", b) ? a : b);
const min = (a, b) => (numArg("较小的", a) <= numArg("较小的", b) ? a : b);
function random(a, b) { const lo = Math.min(a, b), hi = Math.max(a, b); return lo + Math.floor(Math.random() * (hi - lo + 1)); }
function copy(x) {
  if (Array.isArray(x)) return x.map(copy);
  if (x instanceof Map) return new Map(Array.from(x, ([k, v]) => [k, copy(v)]));
  return x;
}
const template = (s, d) => s.replace(/\{([^{}]*)\}/g, (whole, key) => (d.has(key) ? dtext(d.get(key)) : whole));
const toBool = (x) => !(x === null || x === undefined || x === false || x === 0 || x === "");
function listInsert(xs, i, v) { if (i >= 0 && i <= xs.length) xs.splice(i, 0, v); else outOf(i, xs.length); }
const listRemove = (xs, i) => (i >= 0 && i < xs.length ? xs.splice(i, 1)[0] : outOf(i, xs.length));
function listSort(xs) {
  const nums = xs.every((v) => typeof v === "number"), texts = xs.every((v) => typeof v === "string");
  if (!nums && !texts) fail("排序要全是数字或者全是文字的列表，拿到的是混着的");
  return xs.slice().sort(cmp);
}
const dictPairs = (d) => keys(d).map((k) => [k, toDyn(d.get(k))]);
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

''';

/// 是不是数字、字典合并、网址解码。
const String kRt2JsMore = r'''
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

''';
