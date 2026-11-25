// lcx 原型的“核心补充”（Node）：语言核心里设计了、但现在的标准库（lc_lang.js）还没有的东西。
// 分两部分：① 类 / 对象 / 错误 / 稍后的结果——v4 第 4.2 节的节点要用到的运行时支持；
//          ② 为了写通被迫加的标准库函数（每个都对着一条缺口编号，见 lcx.py 的 EXTRA_RT）。
// 所有会抛的错都用统一的中文消息，这样两种语言“出错了”接到的消息逐字相同。
"use strict";
const lc = require("./lc_lang.js");

function fail(message) {
  throw new Error(message);
}

// —— 对象：所有用“类”造出来的东西的共同祖先 ——
class Obj {}

// —— 内置的“错误”类（GAP-F1-01）：一个字段“消息”。自定义错误继承它。——
class Err extends Obj {
  constructor(message = "") {
    super();
    this.f_消息 = lc.toText(message);
  }
}

function named(cls, name) {
  cls.lcName = name;
}
named(Obj, "对象");
named(Err, "错误");

function sig(method, min, max) {
  method.lcMin = min;
  method.lcMax = max;
}

function getf(o, name) {
  if (!(o instanceof Obj) || !Object.hasOwn(o, "f_" + name)) fail("这个值没有“" + name + "”这个字段");
  return o["f_" + name];
}

function setf(o, name, value) {
  if (!(o instanceof Obj) || !Object.hasOwn(o, "f_" + name)) fail("这个值没有“" + name + "”这个字段");
  o["f_" + name] = value;
}

// 调方法：不是对象、没有这个方法、参数个数对不上 → 抛错（消息两种语言一样）。
function send(o, name, ...args) {
  const f = o instanceof Obj ? o["m_" + name] : undefined;
  if (typeof f !== "function") fail("这个值没有“" + name + "”这个方法");
  if (args.length < f.lcMin || (f.lcMax >= 0 && args.length > f.lcMax)) fail("调用方法时给的参数个数对不上");
  const out = f.apply(o, args);
  return out === undefined ? null : out;
}

// “抛出”：抛的要是一个“错误”对象；给的是别的值就文字化后包成“错误”。
function toErr(x) {
  return x instanceof Err ? x : new Err(lc.toText(x));
}

// “出错了”接到的东西统一成“错误”对象：标准库抛的（普通 Error）取它的消息；
// 语言自己的错（TypeError、栈溢出…）各语言消息不一样，统一成一句话。
function caught(e) {
  if (e instanceof Err) return e;
  if (e instanceof Error && e.constructor === Error) return new Err(e.message);
  return new Err("运行时内部出错");
}

// “开始做”：马上开始、不等它。得到“稍后的结果”（Node 里就是 Promise）。
function spawn(body) {
  const p = body();
  p.catch(() => {}); // 没人等它时出的错不让进程崩；等它的人照样会接到
  return p;
}

// 没接住的错误：写到错误输出，进程以 1 退出。
function die(e) {
  const err = caught(e);
  process.stderr.write("没接住的错误：" + err.f_消息 + "\n");
  if (!(e instanceof Err)) console.error(e);
  process.exit(1);
}

// —— 被迫加的标准库函数 ——

const NUM = /^[ \t\r\n]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \t\r\n]*$/;

// GAP-F1-07：是不是一个数字（数字本身，或者写法是数字的文字——和“数字化”认的写法一样，且在范围内）。
function isNumeric(x) {
  if (typeof x === "number") return true;
  return typeof x === "string" && NUM.test(x) && Number.isFinite(Number(x));
}

// GAP-F1-08：第一个是空就用第二个。
function orElse(a, b) {
  return a === null || a === undefined ? b : a;
}

// GAP-F1-05：值的种类名（isType 不认识对象）。
function typeName(x) {
  if (x instanceof Err) return "error";
  if (x instanceof Obj) return "object";
  if (x instanceof Promise) return "future";
  return { num: "number", text: "text", bool: "bool", null: "null", list: "list", obj: "dict", fn: "function" }[lc.kind(x)];
}

module.exports = { Obj, Err, named, sig, getf, setf, send, toErr, caught, spawn, die, isNumeric, orElse, typeName };
