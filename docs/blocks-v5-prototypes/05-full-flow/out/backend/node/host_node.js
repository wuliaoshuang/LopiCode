// 宿主原生接口（L0）的 Node 实现：只用 Node 自带的东西。接口清单和签名见 natives.json，语义细则见 tool/README.md。
"use strict";
const http = require("node:http");
const lc = require("./lc_lang.js");

const BODY_LIMIT = 1048576; // 请求内容最多 1MB
const HOST_HEADERS_JSON = "application/json; charset=utf-8";

// —— http.serve ——

let pending = null; // { port, handler }

function httpServe(port, handler) {
  if (pending) throw new Error("http.serve 只能登记一次");
  pending = { port: Math.trunc(lc.toNum(port)), handler };
  return null;
}

// 请求头：名字转小写；同名的按来的顺序用 ", " 连起来；值两头的空格和制表去掉。
function headersOf(req) {
  const out = Object.create(null);
  for (let i = 0; i + 1 < req.rawHeaders.length; i += 2) {
    const name = req.rawHeaders[i].toLowerCase();
    const value = req.rawHeaders[i + 1].replace(/^[ \t]+|[ \t]+$/g, "");
    out[name] = name in out ? out[name] + ", " + value : value;
  }
  return out;
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

function writeRaw(res, status, headers, bytes) {
  const noBody = status === 204 || status === 304 || status < 200;
  const names = Object.keys(headers).filter((k) => k.toLowerCase() !== "content-length").sort(lc.cmpKeys);
  const list = [];
  for (const k of names) list.push([k, lc.toText(headers[k])]);
  if (!noBody) list.push(["Content-Length", String(bytes.length)]);
  res.writeHead(status, list);
  res.end(noBody ? undefined : bytes);
}

function hostError(res, status, message) {
  writeRaw(res, status, { "Content-Type": HOST_HEADERS_JSON }, Buffer.from(lc.toJson(lc.dictOf("error", message)), "utf8"));
}

async function handle(req, res, handler) {
  const raw = await readBody(req);
  if (raw === null) return hostError(res, 413, "请求内容太大");
  let body;
  try {
    // 不是合法 UTF-8 → 空；开头的 BOM 留着（所以带 BOM 的不算合法 JSON）
    body = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(raw);
  } catch (e) {
    body = null;
  }
  const url = req.url || "/";
  const q = url.indexOf("?");
  const request = lc.dictOf(
    "method", req.method,
    "path", q < 0 ? url : url.slice(0, q),
    "query", q < 0 ? "" : url.slice(q + 1),
    "headers", headersOf(req),
    "body", body,
  );
  let out;
  try {
    out = await lc.call(handler, request);
  } catch (e) {
    console.error(e);
    return hostError(res, 500, "服务器内部出错");
  }
  if (lc.kind(out) !== "obj" || Array.isArray(out)) {
    console.error("处理函数没有返回响应");
    return hostError(res, 500, "服务器内部出错");
  }
  const status = Math.trunc(lc.toNum(lc.dictGet(out, "status")));
  if (!(status >= 100 && status <= 599)) {
    console.error("响应的状态码不对");
    return hostError(res, 500, "服务器内部出错");
  }
  const headers = lc.dictGet(out, "headers");
  writeRaw(res, status, lc.kind(headers) === "obj" ? headers : {}, Buffer.from(lc.toText(lc.dictGet(out, "body")), "utf8"));
}

// 所有模块的“启动时”做完以后由生成的代码调一次：登记过 http.serve 就开门。
function ready() {
  if (!pending) return;
  const env = process.env.PORT || "";
  const port = /^[0-9]{1,5}$/.test(env) && Number(env) <= 65535 ? Number(env) : pending.port;
  const host = process.env.HOST || "0.0.0.0";
  const handler = pending.handler;
  const server = http.createServer((req, res) => {
    handle(req, res, handler).catch((e) => {
      console.error(e);
      if (!res.headersSent) hostError(res, 500, "服务器内部出错");
      else res.destroy();
    });
  });
  server.listen(port, host, () => {
    console.log("后端已启动：http://" + host + ":" + server.address().port);
  });
}

// —— store ——

const store = new Map();
const storeGet = (name) => (store.has(lc.toText(name)) ? lc.copy(store.get(lc.toText(name))) : null);
function storeSet(name, value) {
  store.set(lc.toText(name), lc.copy(value === undefined ? null : value));
  return null;
}
// 第 2 轮加的：函数(旧值) → [新值, 结果]；整件事不被别的请求插队（Node 只有一条线，函数又不许“等”，天然如此）。
function storeUpdate(name, fn) {
  const key = lc.toText(name);
  const out = lc.call(fn, store.has(key) ? store.get(key) : null);
  if (out instanceof Promise) throw new Error("store.update 的函数里不能有要等的事");
  if (!Array.isArray(out) || out.length !== 2) throw new Error("store.update 的函数要返回 [新值, 结果]");
  store.set(key, out[0]);
  return lc.copy(out[1]);
}

// —— url ——

function urlDecode(s) {
  const text = lc.toText(s);
  if (!text.includes("%") || /%(?![0-9A-Fa-f]{2})/.test(text)) return text;
  try {
    return decodeURIComponent(text);
  } catch (e) {
    return text;
  }
}

function urlEncode(s) {
  const bytes = Buffer.from(lc.toText(s), "utf8");
  let out = "";
  for (const b of bytes) {
    const ch = String.fromCharCode(b);
    out += /^[A-Za-z0-9\-._~]$/.test(ch) ? ch : "%" + b.toString(16).toUpperCase().padStart(2, "0");
  }
  return out;
}

// —— net / time / log ——

const netFetch = (method, url, data) => lc.fetch(method, url, data); // 第 3 版小库现成的那个，规矩不变
const timeSleep = (ms) => new Promise((done) => setTimeout(() => done(null), Math.max(0, lc.toNum(ms))));
const timeMs = () => Date.now();
function logError(x) {
  process.stderr.write(lc.toText(x) + "\n");
  return null;
}

module.exports = { httpServe, ready, storeGet, storeSet, storeUpdate, urlDecode, urlEncode, netFetch, timeSleep, timeMs, logError };
