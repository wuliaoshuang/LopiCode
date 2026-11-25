/// Node.js 运行时小库的源码（生成的工程里的 `lc_runtime.js`）。每份工程都一样。
///
/// 只用 Node 自带的 `node:http`。值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库
/// （`test/backend_conformance_test.dart` 会让各语言跑同一套请求、比对响应是否逐字节相同）。
library;

const String kNodeRuntimeSource = r'''
// LopiCode 后端运行时小库（Node.js，只用自带的 node:http，不用装任何包）。
// 每份生成的工程都一样，不用改；你的接口在 server.js 里。
"use strict";
const http = require("node:http");

const BODY_LIMIT = 1048576; // 请求内容最多 1MB
const REPEAT_LIMIT = 10000; // “重复”最多做这么多遍
const FETCH_TIMEOUT_MS = 10000; // “请求别的网址”最多等 10 秒
const JSON_DEPTH_LIMIT = 64; // 请求内容的 JSON 最多套这么多层

// —— 值：空 / 是否 / 数字 / 文字 / 列表 / 对象 ——

const NUM = /^[ \t\r\n]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \t\r\n]*$/;

function kind(v) {
  if (v === null || v === undefined) return "null";
  if (typeof v === "boolean") return "bool";
  if (typeof v === "number") return "num";
  if (typeof v === "string") return "text";
  if (typeof v === "function") return "fn"; // “函数”这种值（积木第 4 版；怎么造、怎么调在 lc_lang.js 里）
  return Array.isArray(v) ? "list" : "obj";
}

function fin(n) {
  return Number.isFinite(n) ? n : 0;
}

// 转成数字：转不了的当 0。
function toNum(v) {
  if (typeof v === "number") return fin(v);
  if (typeof v === "string") return NUM.test(v) ? fin(Number(v)) : 0;
  return v === true ? 1 : 0;
}

// 数字的写法：整数不带小数点；其余保留 12 位有效数字（0.1 + 0.2 写成 0.3）。
function fmtNum(n) {
  if (!Number.isFinite(n) || n === 0) return "0";
  if (Number.isInteger(n) && Math.abs(n) < 1e15) return String(n);
  const m = /^(-?)([0-9])(?:\.([0-9]+))?e([+-][0-9]+)$/.exec(n.toExponential(11));
  const digits = (m[2] + (m[3] || "")).replace(/0+$/, "");
  const e = Number(m[4]);
  if (e >= 15 || e < -7) return m[1] + digits[0] + (digits.length > 1 ? "." + digits.slice(1) : "") + "e" + e;
  if (e >= digits.length - 1) return m[1] + digits + "0".repeat(e - digits.length + 1);
  if (e >= 0) return m[1] + digits.slice(0, e + 1) + "." + digits.slice(e + 1);
  return m[1] + "0." + "0".repeat(-e - 1) + digits;
}

// 按 Unicode 码点比较两个键（JavaScript 默认按 UTF-16 比，表情符号的顺序会和别的语言不一样）。
function cmpKeys(a, b) {
  const x = Array.from(a);
  const y = Array.from(b);
  for (let i = 0; i < x.length && i < y.length; i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d !== 0) return d;
  }
  return x.length - y.length;
}

// 写成 JSON：对象的键排好序，数字按上面的写法。
function toJson(v) {
  switch (kind(v)) {
    case "null":
      return "null";
    case "bool":
      return v ? "true" : "false";
    case "num":
      return fmtNum(v);
    case "text":
      return JSON.stringify(v);
    case "list":
      return "[" + v.map(toJson).join(",") + "]";
    case "fn":
      return "null"; // 函数写不成 JSON：当空
    default:
      return "{" + Object.keys(v).sort(cmpKeys).map((k) => JSON.stringify(k) + ":" + toJson(v[k])).join(",") + "}";
  }
}

// 转成文字。
function toText(v) {
  switch (kind(v)) {
    case "null":
      return "";
    case "text":
      return v;
    case "fn":
      return v.lcName ? "[函数 " + v.lcName + "]" : "[函数]";
    default:
      return toJson(v);
  }
}

// 算不算“是”：空、否、0、空文字算“否”。
function truthy(v) {
  return !(v === null || v === undefined || v === false || v === 0 || v === "");
}

// “等于”：类型一样直接比；不一样就都转成文字再比。
function eq(a, b) {
  const ka = kind(a);
  if (ka !== kind(b)) return toText(a) === toText(b);
  // 两个函数：是同一个，或者是同一个有名字的函数
  if (ka === "fn") return a === b || (!!a.lcName && a.lcName === b.lcName);
  return ka === "list" || ka === "obj" ? toJson(a) === toJson(b) : a === b;
}

// 把 JSON.parse 出来的值收拾干净：对象换成“没有原型”的（免得 __proto__、constructor 这些键捣乱），
// 文字里不成对的代理项换成 U+FFFD，超出范围的数字当 0；列表 / 对象套得太深就报错（整份当成空）。
function norm(v, depth) {
  if (typeof v === "string") return v.toWellFormed();
  if (typeof v === "number") return fin(v);
  if (v === null || typeof v !== "object") return v;
  if (depth >= JSON_DEPTH_LIMIT) throw new RangeError("JSON 套得太深");
  if (Array.isArray(v)) return v.map((x) => norm(x, depth + 1));
  const o = Object.create(null);
  for (const k of Object.keys(v)) o[k.toWellFormed()] = norm(v[k], depth + 1);
  return o;
}

function isObj(v) {
  return kind(v) === "obj";
}

// —— 运算 ——

const add = (a, b) => fin(toNum(a) + toNum(b));
const sub = (a, b) => fin(toNum(a) - toNum(b));
const mul = (a, b) => fin(toNum(a) * toNum(b));
function div(a, b) {
  const d = toNum(b);
  return d === 0 ? 0 : fin(toNum(a) / d);
}
function mod(a, b) {
  const d = toNum(b);
  return d === 0 ? 0 : fin(toNum(a) % d);
}
const ne = (a, b) => !eq(a, b);
const lt = (a, b) => toNum(a) < toNum(b);
const le = (a, b) => toNum(a) <= toNum(b);
const gt = (a, b) => toNum(a) > toNum(b);
const ge = (a, b) => toNum(a) >= toNum(b);
const allOf = (a, b) => truthy(a) && truthy(b);
const anyOf = (a, b) => truthy(a) || truthy(b);
const isNot = (x) => !truthy(x);
const isNull = (x) => x === null || x === undefined;
const join = (...items) => items.map(toText).join("");

function size(x) {
  switch (kind(x)) {
    case "list":
      return x.length;
    case "text":
      return Array.from(x).length;
    case "obj":
      return Object.keys(x).length;
    default:
      return 0;
  }
}

// obj("title", "买菜", "done", false) → { title: "买菜", done: false }
function obj(...pairs) {
  const o = Object.create(null);
  for (let i = 0; i + 1 < pairs.length; i += 2) o[pairs[i]] = pairs[i + 1];
  return o;
}

function field(o, key) {
  return isObj(o) && Object.hasOwn(o, key) && o[key] !== undefined ? o[key] : null;
}

function times(x) {
  return Math.min(Math.max(Math.trunc(toNum(x)), 0), REPEAT_LIMIT);
}

function items(x) {
  return Array.isArray(x) ? x.slice() : [];
}

function now() {
  return new Date().toISOString().slice(0, 19) + "Z";
}

function log(x) {
  console.log(toText(x));
}

// —— 数据集合（存在内存里，进程重启就没了）——

const collections = new Map();

function collection(name) {
  let c = collections.get(name);
  if (!c) {
    c = { next: 1, rows: [] };
    collections.set(name, c);
  }
  return c;
}

function copyFields(target, source) {
  if (isObj(source)) for (const k of Object.keys(source)) target[k] = source[k];
  return target;
}

const dbAll = (name) => collection(name).rows.slice();
const dbCount = (name) => collection(name).rows.length;

function dbGet(name, id) {
  const want = toNum(id);
  return collection(name).rows.find((r) => r.id === want) ?? null;
}

function dbFind(name, key, value) {
  return collection(name).rows.filter((r) => eq(field(r, key), value));
}

function dbInsert(name, value) {
  const c = collection(name);
  const row = copyFields(Object.create(null), value);
  row.id = c.next++;
  c.rows.push(row);
  return row;
}

// 改的是一份新的记录（之前读出来的那份不会跟着变）。
function dbUpdate(name, id, value) {
  const c = collection(name);
  const want = toNum(id);
  const i = c.rows.findIndex((r) => r.id === want);
  if (i < 0) return null;
  if (!isObj(value)) return c.rows[i];
  const row = copyFields(copyFields(Object.create(null), c.rows[i]), value);
  row.id = c.rows[i].id;
  c.rows[i] = row;
  return row;
}

function dbDelete(name, id) {
  const c = collection(name);
  const want = toNum(id);
  const i = c.rows.findIndex((r) => r.id === want);
  if (i < 0) return false;
  c.rows.splice(i, 1);
  return true;
}

// —— 请求 ——

// 百分号解码；写法不对（%zz、解出来不是合法 UTF-8）就原样返回。
function pct(s) {
  if (!s.includes("%") || /%(?![0-9A-Fa-f]{2})/.test(s)) return s;
  try {
    return decodeURIComponent(s);
  } catch (e) {
    return s;
  }
}

function parseQuery(raw) {
  const out = new Map();
  for (const part of raw.split("&")) {
    if (part === "") continue;
    const i = part.indexOf("=");
    const key = pct((i < 0 ? part : part.slice(0, i)).replace(/\+/g, " "));
    const value = i < 0 ? "" : pct(part.slice(i + 1).replace(/\+/g, " "));
    if (!out.has(key)) out.set(key, value);
  }
  return out;
}

function parseBody(bytes) {
  if (bytes.length === 0) return null;
  try {
    return norm(JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes)), 0);
  } catch (e) {
    return null;
  }
}

function pathParam(req, name) {
  return req.params.has(name) ? req.params.get(name) : null;
}

function query(req, name) {
  if (!req.query) req.query = parseQuery(req.rawQuery);
  return req.query.has(name) ? req.query.get(name) : null;
}

function body(req) {
  if (!req.parsed) {
    req.parsed = true;
    req.body = parseBody(req.rawBody);
  }
  return req.body;
}

function bodyField(req, name) {
  return field(body(req), name);
}

function header(req, name) {
  const v = req.headers[String(name).toLowerCase()];
  if (v === undefined) return null;
  return Array.isArray(v) ? v.join(", ") : String(v);
}

// —— 响应 ——

function statusOf(v) {
  const n = Math.trunc(toNum(v));
  return n >= 200 && n <= 599 ? n : 200;
}

function sendJson(status, value) {
  return { status: statusOf(status), type: "application/json; charset=utf-8", body: Buffer.from(toJson(value), "utf8") };
}

function sendText(status, value) {
  return { status: statusOf(status), type: "text/plain; charset=utf-8", body: Buffer.from(toText(value), "utf8") };
}

function errorResponse(status, message) {
  return sendJson(status, obj("error", message));
}

function write(res, out) {
  const headers = { "Access-Control-Allow-Origin": "*" };
  if (out.status === 204 || out.status === 304) {
    res.writeHead(out.status, headers);
    res.end();
    return;
  }
  headers["Content-Type"] = out.type;
  headers["Content-Length"] = out.body.length;
  res.writeHead(out.status, headers);
  res.end(out.body);
}

// —— 请求别的网址 ——

// 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义：各语言自己的处理不一样（有的自动转、有的直接报错），这里统一。
// 字母、数字和 -._~:/?#[]@!$&'()*+,;= 原样；后面跟着两位十六进制的 % 原样；其余每个字节写成 %XX（大写）。
function encodeUrl(s) {
  const bytes = Buffer.from(s, "utf8");
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    const ch = String.fromCharCode(bytes[i]);
    const escaped = ch === "%" && i + 2 < bytes.length && /^[0-9A-Fa-f]{2}$/.test(String.fromCharCode(bytes[i + 1], bytes[i + 2]));
    if (escaped || /^[A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=]$/.test(ch)) out += ch;
    else out += "%" + bytes[i].toString(16).toUpperCase().padStart(2, "0");
  }
  return out;
}

// 成功（2xx）返回响应的文字；失败、超时、不是 http(s) 网址、网址里带用户名密码一律返回 null。
async function fetchText(method, url, data) {
  let target = toText(url);
  if (!/^https?:\/\//i.test(target)) return null;
  // 主机那一段带 @（用户名密码）的不请求
  if (/^[^\/?#]*@/.test(target.slice(target.indexOf("://") + 3))) return null;
  target = encodeUrl(target);
  try {
    const init = { method: method === "POST" ? "POST" : "GET", signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) };
    if (init.method === "POST" && !isNull(data)) {
      init.body = toJson(data);
      init.headers = { "Content-Type": "application/json; charset=utf-8" };
    }
    const res = await fetch(target, init);
    if (!res.ok) return null;
    // 自己按 UTF-8 读（坏的地方换成 U+FFFD），开头的 BOM 去掉一个。不用 res.text()：Node 24 上它会去掉两个。
    const text = new TextDecoder("utf-8", { ignoreBOM: true }).decode(await res.arrayBuffer());
    return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  } catch (e) {
    return null;
  }
}

// —— 路由与启动 ——

const routes = [];

// 登记一个接口。path 里的 :名字 是路径参数。
function route(method, path, handler) {
  routes.push({ method, segments: path.split("/").filter((s) => s !== ""), handler });
}

// 路径对得上就返回参数表，否则 null。
function match(pattern, segments) {
  if (pattern.length !== segments.length) return null;
  const params = new Map();
  for (let i = 0; i < pattern.length; i++) {
    if (pattern[i].startsWith(":")) params.set(pattern[i].slice(1), segments[i]);
    else if (pattern[i] !== segments[i]) return null;
  }
  return params;
}

async function readBody(req) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total <= BODY_LIMIT) chunks.push(chunk);
  }
  return total > BODY_LIMIT ? null : Buffer.concat(chunks);
}

async function handle(req, res) {
  const rawBody = await readBody(req);
  if (rawBody === null) return write(res, errorResponse(413, "请求内容太大"));
  if (req.method === "OPTIONS") {
    // 浏览器跨域调用前的“预检”
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "*",
    });
    return res.end();
  }
  const url = req.url || "/";
  const q = url.indexOf("?");
  const segments = (q < 0 ? url : url.slice(0, q)).split("/").filter((s) => s !== "").map(pct);
  let pathMatched = false;
  for (const r of routes) {
    const params = match(r.segments, segments);
    if (!params) continue;
    pathMatched = true;
    if (r.method !== req.method) continue;
    const request = { params, rawQuery: q < 0 ? "" : url.slice(q + 1), query: null, headers: req.headers, rawBody, parsed: false, body: null };
    let out;
    try {
      out = await r.handler(request);
    } catch (e) {
      console.error(e);
      out = errorResponse(500, "服务器内部出错");
    }
    // 没有碰到“返回”积木：204 空响应
    return write(res, out || { status: 204 });
  }
  return write(res, pathMatched ? errorResponse(405, "这个地址不支持这种请求方式") : errorResponse(404, "没有这个接口"));
}

// 启动服务。端口先看环境变量 PORT，没有就用 defaultPort；HOST 默认 0.0.0.0（所有网卡）。
function start(defaultPort) {
  const env = process.env.PORT || "";
  const port = /^[0-9]{1,5}$/.test(env) && Number(env) <= 65535 ? Number(env) : defaultPort;
  const host = process.env.HOST || "0.0.0.0";
  const server = http.createServer((req, res) => {
    handle(req, res).catch((e) => {
      console.error(e);
      if (!res.headersSent) write(res, errorResponse(500, "服务器内部出错"));
      else res.destroy();
    });
  });
  server.listen(port, host, () => {
    console.log("后端已启动：http://" + host + ":" + server.address().port);
  });
  return server;
}

module.exports = {
  add, sub, mul, div, mod, eq, ne, lt, le, gt, ge, allOf, anyOf, isNot, truthy, join, size, isNull, obj, field,
  pathParam, query, bodyField, body, header,
  dbAll, dbGet, dbFind, dbCount, dbInsert, dbUpdate, dbDelete,
  now, log, times, items, sendJson, sendText, fetch: fetchText,
  collection, route, start, toNum, toText, toJson,
  // 下面几个给 lc_lang.js（语言核心的小库）用
  kind, cmpKeys, parseBody,
};
''';
