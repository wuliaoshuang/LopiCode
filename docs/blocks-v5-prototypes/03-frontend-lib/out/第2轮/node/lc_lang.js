// LopiCode 语言核心小库（Node.js）：积木第 4 版新加的操作——类型、数学、文字、列表、字典、JSON、数列。
// 值的规矩（数字化、文字化、等于…）在 lc_runtime.js 里；这里把它的函数也一起导出，生成的代码只认这一个文件。
// 每份生成的工程都一样，不用改。规矩：位置从 0 数；文字按 Unicode 码点算；读不到得空；写到不存在的位置抛错。
"use strict";
const base = require("./lc_runtime.js");
const { toNum, toText, toJson, truthy, eq, kind, cmpKeys, parseBody } = base;

const RANGE_LIMIT = 10000; // “数列”“重复文字”最多这么多项
const COUNT_LIMIT = 2147483647; // “从…数到…”最多数这么多遍

const E_NOT_LIST = "这不是列表，改不了";
const E_NOT_DICT = "这不是字典，改不了";
const E_NO_ITEM = "列表里没有这个位置";
const E_NOT_INDEXABLE = "这个值不能按位置或键来改";

function fail(message) {
  throw new Error(message);
}

const fin = (n) => (Number.isFinite(n) ? n : 0);
// 去掉“负零”（各语言写出来不一样）。
const pz = (n) => (n === 0 ? 0 : n);
const isList = (x) => Array.isArray(x);
const isDict = (x) => kind(x) === "obj";
const index = (i) => Math.trunc(toNum(i));
const clamp = (n, lo, hi) => (n < lo ? lo : n > hi ? hi : n);
const chars = (s) => Array.from(toText(s));

// —— 类型 ——

const TYPE_NAMES = { num: "number", text: "text", bool: "bool", null: "null", list: "list", obj: "dict", fn: "function" };
const isType = (x, name) => TYPE_NAMES[kind(x)] === toText(name);
const toNumber = (x) => toNum(x);
const toBool = (x) => truthy(x);

function copy(x) {
  if (isList(x)) return x.map(copy);
  if (!isDict(x)) return x;
  const o = Object.create(null);
  for (const k of Object.keys(x)) o[k] = copy(x[k]);
  return o;
}

// —— 数学 ——

const pow = (a, b) => pz(fin(Math.pow(toNum(a), toNum(b))));
function round(x) {
  const n = toNum(x);
  const t = Math.trunc(n);
  return pz(Math.abs(n - t) >= 0.5 ? t + (n < 0 ? -1 : 1) : t);
}
const floor = (x) => pz(Math.floor(toNum(x)));
const ceil = (x) => pz(Math.ceil(toNum(x)));
const abs = (x) => Math.abs(toNum(x));
function sqrt(x) {
  const n = toNum(x);
  return n < 0 ? 0 : Math.sqrt(n);
}
function max(a, b) {
  const x = toNum(a);
  const y = toNum(b);
  return x >= y ? x : y;
}
function min(a, b) {
  const x = toNum(a);
  const y = toNum(b);
  return x <= y ? x : y;
}
function random(a, b) {
  const x = index(a);
  const y = index(b);
  const lo = x <= y ? x : y;
  const hi = x <= y ? y : x;
  return pz(lo + Math.floor(Math.random() * (hi - lo + 1)));
}

// —— 文字 ——

function charAt(s, i) {
  const cs = chars(s);
  const n = index(i);
  return n >= 0 && n < cs.length ? cs[n] : null;
}
function substring(s, from, to) {
  const cs = chars(s);
  const a = clamp(index(from), 0, cs.length);
  const b = clamp(index(to), 0, cs.length);
  return a >= b ? "" : cs.slice(a, b).join("");
}
const contains = (s, sub) => toText(s).includes(toText(sub));
const startsWith = (s, p) => toText(s).startsWith(toText(p));
const endsWith = (s, p) => toText(s).endsWith(toText(p));
function indexOf(s, sub) {
  const text = toText(s);
  const at = text.indexOf(toText(sub));
  return at < 0 ? -1 : Array.from(text.slice(0, at)).length;
}
function replace(s, from, to) {
  const f = toText(from);
  return f === "" ? toText(s) : toText(s).split(f).join(toText(to));
}
function split(s, sep) {
  const p = toText(sep);
  return p === "" ? chars(s) : toText(s).split(p);
}
const trim = (s) => toText(s).replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "");
const upper = (s) => toText(s).replace(/[a-z]+/g, (m) => m.toUpperCase());
const lower = (s) => toText(s).replace(/[A-Z]+/g, (m) => m.toLowerCase());
const repeatText = (s, n) => toText(s).repeat(clamp(index(n), 0, RANGE_LIMIT));
function template(s, d) {
  return toText(s).replace(/\{([^{}]*)\}/g, (whole, key) => (isDict(d) && Object.hasOwn(d, key) ? toText(d[key]) : whole));
}

// —— 列表 ——

const listOf = (...xs) => xs;
const items = (x) => (isList(x) ? x : []);
function listGet(xs, i) {
  const n = index(i);
  return isList(xs) && n >= 0 && n < xs.length ? xs[n] : null;
}
function listSet(xs, i, v) {
  if (!isList(xs)) fail(E_NOT_LIST);
  const n = index(i);
  if (n < 0 || n >= xs.length) fail(E_NO_ITEM);
  xs[n] = v;
}
function listPush(xs, v) {
  if (!isList(xs)) fail(E_NOT_LIST);
  xs.push(v);
}
function listInsert(xs, i, v) {
  if (!isList(xs)) fail(E_NOT_LIST);
  const n = index(i);
  if (n < 0 || n > xs.length) fail(E_NO_ITEM);
  xs.splice(n, 0, v);
}
function listRemove(xs, i) {
  if (!isList(xs)) fail(E_NOT_LIST);
  const n = index(i);
  if (n < 0 || n >= xs.length) fail(E_NO_ITEM);
  return xs.splice(n, 1)[0];
}
const listPop = (xs) => (isList(xs) && xs.length > 0 ? xs.pop() : null);
const listIndexOf = (xs, v) => items(xs).findIndex((x) => eq(x, v));
const listContains = (xs, v) => listIndexOf(xs, v) >= 0;
function listSlice(xs, from, to) {
  const list = items(xs);
  const a = clamp(index(from), 0, list.length);
  const b = clamp(index(to), 0, list.length);
  return a >= b ? [] : list.slice(a, b);
}
const listConcat = (a, b) => items(a).concat(items(b));
const listReverse = (xs) => items(xs).slice().reverse();
// 数字排在前面、按大小；其余的文字化后按码点。
function listSort(xs) {
  const keyed = items(xs).map((v) => (typeof v === "number" ? { v, n: v, t: null } : { v, n: 0, t: toText(v) }));
  keyed.sort((x, y) => {
    if (x.t === null && y.t === null) return x.n < y.n ? -1 : x.n > y.n ? 1 : 0;
    if (x.t === null) return -1;
    if (y.t === null) return 1;
    return cmpKeys(x.t, y.t);
  });
  return keyed.map((k) => k.v);
}
const listJoin = (xs, sep) => items(xs).map(toText).join(toText(sep));

function countSteps(from, to, step) {
  const a = toNum(from);
  const s = toNum(step);
  if (s === 0) return 0;
  const d = (toNum(to) - a) / s;
  if (!(d >= 0)) return 0;
  const n = Math.floor(d + 1e-9) + 1;
  return n > COUNT_LIMIT ? COUNT_LIMIT : n;
}
function range(from, to, step) {
  const a = toNum(from);
  const s = toNum(step);
  const n = Math.min(countSteps(a, to, s), RANGE_LIMIT);
  const out = [];
  for (let k = 0; k < n; k++) out.push(a + k * s);
  return out;
}

// —— 字典 ——

function dictOf(...pairs) {
  const o = Object.create(null);
  for (let i = 0; i + 1 < pairs.length; i += 2) o[toText(pairs[i])] = pairs[i + 1];
  return o;
}
const dictHas = (d, k) => isDict(d) && Object.hasOwn(d, toText(k));
const dictGet = (d, k) => (dictHas(d, k) ? d[toText(k)] : null);
function dictSet(d, k, v) {
  if (!isDict(d)) fail(E_NOT_DICT);
  d[toText(k)] = v;
}
function dictRemove(d, k) {
  if (!isDict(d)) fail(E_NOT_DICT);
  delete d[toText(k)];
}
const dictKeys = (d) => (isDict(d) ? Object.keys(d).sort(cmpKeys) : []);
const dictValues = (d) => dictKeys(d).map((k) => d[k]);
const dictPairs = (d) => dictKeys(d).map((k) => [k, d[k]]);
function dictMerge(a, b) {
  const o = Object.create(null);
  for (const d of [a, b]) {
    if (isDict(d)) for (const k of Object.keys(d)) o[k] = d[k];
  }
  return o;
}

// —— 列表 / 字典 / 文字通用 ——

function item(x, k) {
  if (isList(x)) return listGet(x, k);
  if (isDict(x)) return dictGet(x, k);
  return typeof x === "string" ? charAt(x, k) : null;
}
function setItem(x, k, v) {
  if (isList(x)) return listSet(x, k, v);
  if (isDict(x)) return dictSet(x, k, v);
  return fail(E_NOT_INDEXABLE);
}

// —— JSON ——

const fromJson = (s) => parseBody(Buffer.from(toText(s), "utf8"));

module.exports = Object.assign({}, base, {
  isType, toNumber, toText, toBool, copy,
  pow, round, floor, ceil, abs, sqrt, max, min, random,
  charAt, substring, contains, startsWith, endsWith, indexOf, replace, split, trim, upper, lower, repeatText, template,
  listOf, listGet, listSet, listPush, listInsert, listRemove, listPop, listContains, listIndexOf, listSlice, listConcat,
  listReverse, listSort, listJoin, range,
  dictOf, dictGet, dictSet, dictRemove, dictHas, dictKeys, dictValues, dictPairs, dictMerge,
  item, setItem, toJson, fromJson, countSteps,
});
// —— 函数（第 2 阶段）——
// 函数值就是 JavaScript 的函数，身上多记三样：名字、最少 / 最多收几个参数（最多是 -1＝不限）。

const E_NOT_FUNCTION = "这不是函数，不能调用";
const E_ARG_COUNT = "调用函数时给的参数个数对不上";

function fn(name, min, max, impl) {
  impl.lcName = name;
  impl.lcMin = min;
  impl.lcMax = max;
  return impl;
}

function needFn(f) {
  if (typeof f !== "function" || f.lcMin === undefined) fail(E_NOT_FUNCTION);
}

// 调一个函数值：不是函数、参数个数对不上 → 抛错。没有返回值的函数得空。
function call(f, ...args) {
  needFn(f);
  if (args.length < f.lcMin || (f.lcMax >= 0 && args.length > f.lcMax)) fail(E_ARG_COUNT);
  const out = f(...args);
  return out === undefined ? null : out;
}

// 开始时把列表抄一份再走：回调里改了原来的列表也不影响这一趟。
function each(xs, f) {
  needFn(f);
  return isList(xs) ? xs.slice() : [];
}

function listMap(xs, f) {
  const out = [];
  for (const x of each(xs, f)) out.push(call(f, x));
  return out;
}
function listFilter(xs, f) {
  const out = [];
  for (const x of each(xs, f)) if (truthy(call(f, x))) out.push(x);
  return out;
}
function listReduce(xs, f, init) {
  let acc = init === undefined ? null : init;
  for (const x of each(xs, f)) acc = call(f, acc, x);
  return acc;
}
function listFind(xs, f) {
  for (const x of each(xs, f)) if (truthy(call(f, x))) return x;
  return null;
}
function listEvery(xs, f) {
  for (const x of each(xs, f)) if (!truthy(call(f, x))) return false;
  return true;
}
function listSome(xs, f) {
  for (const x of each(xs, f)) if (truthy(call(f, x))) return true;
  return false;
}
function listEach(xs, f) {
  for (const x of each(xs, f)) call(f, x);
}
// 按 f(项) 给的分从小到大：分是数字的排前面、按大小；其余的文字化后按码点；一样的保持原来的先后。
function listSortBy(xs, f) {
  const keyed = each(xs, f).map((v) => {
    const k = call(f, v);
    return typeof k === "number" ? { v, n: k, t: null } : { v, n: 0, t: toText(k) };
  });
  keyed.sort((x, y) => {
    if (x.t === null && y.t === null) return x.n < y.n ? -1 : x.n > y.n ? 1 : 0;
    if (x.t === null) return -1;
    if (y.t === null) return 1;
    return cmpKeys(x.t, y.t);
  });
  return keyed.map((k) => k.v);
}

Object.assign(module.exports, { fn, call, listMap, listFilter, listReduce, listFind, listEvery, listSome, listEach, listSortBy });
