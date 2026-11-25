// 类型原型用的“小库”（Node 版）。只为验证类型设计，不是产品代码。规矩见 ../../../blocks-v5-parts/B-type-system.md 第 1、7 节。
"use strict";
class LcError extends Error {}
const MAX = 9007199254740991; // 2^53 - 1
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
// 整数：范围 ±(2^53-1)，超了抛错
const chk = (r) => (Number.isSafeInteger(r) ? r : fail("整数超出范围"));
const iadd = (a, b) => chk(a + b);
const isub = (a, b) => chk(a - b);
const imul = (a, b) => chk(a * b);
const imod = (a, b) => (b === 0 ? fail("除以 0") : (a % b) + 0); // +0：把 -0 变成 0
const idiv = (a, b) => (b === 0 ? fail("除以 0") : (a - (a % b)) / b + 0);
const fdiv = (a, b) => (b === 0 ? fail("除以 0") : a / b);
const ftoi = (x) => (Number.isFinite(x) && Math.abs(Math.trunc(x)) <= MAX ? Math.trunc(x) + 0 : fail("这个小数变不成整数：" + fmtNum(x)));

// 文字按码点
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
const cmp = (a, b) => (typeof a === "string" ? cmpText(a, b) : a < b ? -1 : a > b ? 1 : 0);

// 列表
const at = (xs, i) => (i >= 0 && i < xs.length ? xs[i] : fail("位置 " + i + " 超出了列表的范围（共 " + xs.length + " 项）"));
const setAt = (xs, i, v) => { if (i >= 0 && i < xs.length) xs[i] = v; else fail("位置 " + i + " 超出了列表的范围（共 " + xs.length + " 项）"); };
// 字典：用 Map；键的顺序＝按码点从小到大
const keys = (d) => Array.from(d.keys()).sort(cmpText);
const get = (d, k) => (d.has(k) ? d.get(k) : null);
const must = (x) => (x === null || x === undefined ? fail("这里的值是空，不能直接用") : x);

// 任意 → 确定类型（严格：不对就抛错）
function kind(x) {
  if (x === null || x === undefined) return "空";
  if (typeof x === "boolean") return "是否";
  if (typeof x === "number") return "数字";
  if (typeof x === "string") return "文字";
  if (Array.isArray(x)) return "列表";
  if (x instanceof Map) return "字典";
  if (typeof x === "function") return "函数";
  return "对象";
}
const want = (name, x) => fail("这里要" + name + "，拿到的是" + kind(x));
const asNum = (x) => (typeof x === "number" ? x : want("小数", x));
const asInt = (x) => (typeof x !== "number" ? want("整数", x) : Number.isSafeInteger(x) ? x : fail("这里要整数，拿到的是 " + fmtNum(x)));
const asText = (x) => (typeof x === "string" ? x : want("文字", x));
const asBool = (x) => (typeof x === "boolean" ? x : want("是否", x));
const asList = (x) => (Array.isArray(x) ? x : want("列表", x));
const asDict = (x) => (x instanceof Map ? x : want("字典", x));

// 任意值之间的运算（严格规矩下：不偷偷转换）
const dnum = (op, x) => (typeof x === "number" ? x : fail(op + "的两边要数字，拿到的是" + kind(x)));
const dadd = (a, b) => dnum("加法", a) + dnum("加法", b);
const dsub = (a, b) => dnum("减法", a) - dnum("减法", b);
const dmul = (a, b) => dnum("乘法", a) * dnum("乘法", b);
const ddiv = (a, b) => fdiv(dnum("除法", a), dnum("除法", b));
const didiv = (a, b) => idiv(asInt(a), asInt(b));
const dimod = (a, b) => imod(asInt(a), asInt(b));
function dtext(x) {
  switch (kind(x)) {
    case "空": return "";
    case "是否": return x ? "true" : "false";
    case "数字": return fmtNum(x);
    case "文字": return x;
    case "列表": return "[" + x.map(djson).join(",") + "]";
    case "字典": return "{" + keys(x).map((k) => '"' + k + '":' + djson(x.get(k))).join(",") + "}";
    default: return "[" + kind(x) + "]";
  }
}
// 原型里的 JSON 写法从简：文字不做转义（产品里沿用第 3 版小库的完整写法）
function djson(x) { const k = kind(x); return k === "空" ? "null" : k === "文字" ? '"' + x + '"' : dtext(x); }
const boolText = (b) => (b ? "true" : "false");

const split = (s, sep) => s.split(sep);
const substr = (s, from, to) => cps(s).slice(from, to).join("");
const parseInt_ = (s) => (/^-?[0-9]+$/.test(s) && Number.isSafeInteger(Number(s)) ? Number(s) + 0 : null);

// 确定类型的列表 / 字典装进“任意”：拍一份快照（第二轮定的规矩）
const toDyn = (x) => (Array.isArray(x) ? x.map(toDyn) : x instanceof Map ? new Map([...x].map(([k, v]) => [k, toDyn(v)])) : x);
// “任意”取回成 列表〈T〉：逐项检查，得到一份新的
const asListOf = (x, f) => asList(x).map((v, i) => { try { return f(v); } catch (e) { if (!(e instanceof LcError)) throw e; return fail("列表的位置 " + i + "：" + e.message); } });

const out = [];
const log = (s) => out.push(s);
function run(main) {
  try { main(); } catch (e) { if (e instanceof LcError) out.push("出错：" + e.message); else throw e; }
  process.stdout.write(out.join("\n") + "\n");
}
module.exports = { LcError, fail, fmtNum, iadd, isub, imul, imod, idiv, fdiv, ftoi, textLen, cmpText, cmp, at, setAt, keys, get, must, kind,
  asNum, asInt, asText, asBool, asList, asDict, dadd, dsub, dmul, ddiv, didiv, dimod, dtext, boolText, log, run, MAX, split, substr, toDyn, asListOf, parseInt: parseInt_ };
