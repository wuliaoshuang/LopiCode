/// Node.js 语言核心小库里“函数”那一部分（积木第 4 版·第 2 阶段）：函数值、调用、拿函数当参数的 8 个列表操作。
/// 接在 `kNodeLangRuntimeSource` 后面，同一个文件（`lc_lang.js`）。规矩见 lib/lang/rt.dart；五种语言要一起改。
library;

const String kNodeLangFuncSource = r'''
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
''';
