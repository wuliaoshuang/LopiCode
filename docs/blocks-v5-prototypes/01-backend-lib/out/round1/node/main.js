// 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。
"use strict";
const lc = require("./lc_lang.js");
const lcx = require("./lcx_ext.js");
const host = require("./host_node.js");

// ———— 模块 响应 ————
const M响应_状态码 = lc.fn("状态码", 1, 1, function (v_v) {
  let v_n = null;
  v_n = lc.floor(lc.toNumber(v_v));
  if ((lc.ge(v_n, 200.0) && lc.le(v_n, 599.0))) {
    return v_n;
  }
  return 200.0;
});
const M响应_做响应 = lc.fn("做响应", 3, 3, function (v_状态, v_类型, v_内容) {
  let v_头 = null;
  v_头 = lc.dictOf("Access-Control-Allow-Origin", "*");
  if ((lc.eq(v_状态, 204.0) || lc.eq(v_状态, 304.0))) {
    return lc.dictOf("status", v_状态, "headers", v_头, "body", "");
  }
  lc.setItem(v_头, "Content-Type", v_类型);
  return lc.dictOf("status", v_状态, "headers", v_头, "body", v_内容);
});
const M响应_JSON响应 = lc.fn("JSON响应", 2, 2, function (v_状态, v_值) {
  return M响应_做响应(M响应_状态码(v_状态), "application/json; charset=utf-8", lc.toJson(v_值));
});
const M响应_文字响应 = lc.fn("文字响应", 2, 2, function (v_状态, v_值) {
  return M响应_做响应(M响应_状态码(v_状态), "text/plain; charset=utf-8", lc.toText(v_值));
});
const M响应_错误响应 = lc.fn("错误响应", 2, 2, function (v_状态, v_消息) {
  return M响应_JSON响应(v_状态, lc.dictOf("error", v_消息));
});
const M响应_空响应 = lc.fn("空响应", 0, 0, function () {
  return M响应_做响应(204.0, "", "");
});
const M响应_预检响应 = lc.fn("预检响应", 0, 0, function () {
  return lc.dictOf("status", 204.0, "headers", lc.dictOf("Access-Control-Allow-Origin", "*", "Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers", "*"), "body", "");
});

// ———— 模块 请求 ————
const M请求_解析网址参数 = lc.fn("解析网址参数", 1, 1, function (v_原文) {
  let v_表 = null, v_段 = null, v_等号 = null, v_键 = null, v_值 = null;
  v_表 = lc.dictOf();
  for (let lcxs1 = lc.items(lc.split(v_原文, "&")), lci2 = 0; lci2 < lcxs1.length; lci2++) {
    v_段 = lcxs1[lci2];
    if (lc.eq(v_段, "")) {
      continue;
    }
    v_等号 = lc.indexOf(v_段, "=");
    v_键 = v_段;
    v_值 = "";
    if (lc.ge(v_等号, 0.0)) {
      v_键 = lc.substring(v_段, 0.0, v_等号);
      v_值 = lc.substring(v_段, lc.add(v_等号, 1.0), lc.size(v_段));
    }
    v_键 = host.urlDecode(lc.replace(v_键, "+", " "));
    v_值 = host.urlDecode(lc.replace(v_值, "+", " "));
    if (!lc.dictHas(v_表, v_键)) {
      lc.setItem(v_表, v_键, v_值);
    }
  }
  return v_表;
});
const M请求_网址参数 = lc.fn("网址参数", 2, 2, function (v_请求, v_名字) {
  let v_表 = null;
  v_表 = lc.dictGet(v_请求, "_query");
  if (lc.isNull(v_表)) {
    v_表 = M请求_解析网址参数(lc.dictGet(v_请求, "query"));
    lc.setItem(v_请求, "_query", v_表);
  }
  return lc.dictGet(v_表, v_名字);
});
const M请求_路径参数 = lc.fn("路径参数", 2, 2, function (v_请求, v_名字) {
  return lc.dictGet(lc.dictGet(v_请求, "params"), v_名字);
});
const M请求_请求内容 = lc.fn("请求内容", 1, 1, function (v_请求) {
  if (!lc.dictHas(v_请求, "_body")) {
    lc.setItem(v_请求, "_body", lc.fromJson(lc.dictGet(v_请求, "body")));
  }
  return lc.dictGet(v_请求, "_body");
});
const M请求_请求内容的字段 = lc.fn("请求内容的字段", 2, 2, function (v_请求, v_名字) {
  return lc.dictGet(M请求_请求内容(v_请求), v_名字);
});
const M请求_请求头 = lc.fn("请求头", 2, 2, function (v_请求, v_名字) {
  return lc.dictGet(lc.dictGet(v_请求, "headers"), lc.lower(v_名字));
});

// ———— 模块 路由 ————
const M路由_切路径 = lc.fn("切路径", 2, 2, function (v_路径, v_解码) {
  let v_段们 = null, v_段 = null;
  v_段们 = [];
  for (let lcxs3 = lc.items(lc.split(v_路径, "/")), lci4 = 0; lci4 < lcxs3.length; lci4++) {
    v_段 = lcxs3[lci4];
    if (lc.ne(v_段, "")) {
      lc.listPush(v_段们, (lc.truthy(v_解码) ? host.urlDecode(v_段) : v_段));
    }
  }
  return v_段们;
});
const M路由_注册 = lc.fn("注册", 3, 3, function (v_方式, v_路径, v_处理) {
  lc.listPush(M路由_路由表, lc.dictOf("method", v_方式, "segments", M路由_切路径(v_路径, false), "handler", v_处理));
  return null;
});
const M路由_对得上 = lc.fn("对得上", 2, 2, function (v_模式, v_段们) {
  let v_参数 = null, v_想要 = null, v_i = null, v_实际 = null;
  if (lc.ne(lc.size(v_模式), lc.size(v_段们))) {
    return null;
  }
  v_参数 = lc.dictOf();
  for (let lcxs5 = lc.items(v_模式), lci6 = 0; lci6 < lcxs5.length; lci6++) {
    v_想要 = lcxs5[lci6];
    v_i = lci6;
    v_实际 = lc.listGet(v_段们, v_i);
    if (lc.startsWith(v_想要, ":")) {
      lc.setItem(v_参数, lc.substring(v_想要, 1.0, lc.size(v_想要)), v_实际);
    } else if (lc.ne(v_想要, v_实际)) {
      return null;
    }
  }
  return v_参数;
});
const M路由_分发 = lc.fn("分发", 1, 1, async function (v_请求) {
  let v_段们 = null, v_路径对了 = null, v_路由 = null, v_参数 = null, v_结果 = null, v_e = null;
  if (lc.eq(lc.dictGet(v_请求, "method"), "OPTIONS")) {
    return M响应_预检响应();
  }
  v_段们 = M路由_切路径(lc.dictGet(v_请求, "path"), true);
  v_路径对了 = false;
  for (let lcxs7 = lc.items(M路由_路由表), lci8 = 0; lci8 < lcxs7.length; lci8++) {
    v_路由 = lcxs7[lci8];
    v_参数 = M路由_对得上(lc.dictGet(v_路由, "segments"), v_段们);
    if (lc.isNull(v_参数)) {
      continue;
    }
    v_路径对了 = true;
    if (lc.ne(lc.dictGet(v_路由, "method"), lc.dictGet(v_请求, "method"))) {
      continue;
    }
    lc.setItem(v_请求, "params", v_参数);
    v_结果 = null;
    try {
      v_结果 = (await lc.call(lc.dictGet(v_路由, "handler"), v_请求));
    } catch (lce9) {
      v_e = lcx.caught(lce9);
      return M响应_错误响应(500.0, "服务器内部出错");
    }
    if (lc.isNull(v_结果)) {
      return M响应_空响应();
    }
    return v_结果;
  }
  if (lc.truthy(v_路径对了)) {
    return M响应_错误响应(405.0, "这个地址不支持这种请求方式");
  }
  return M响应_错误响应(404.0, "没有这个接口");
});
const M路由_开始服务 = lc.fn("开始服务", 1, 1, function (v_端口) {
  host.httpServe(v_端口, M路由_分发);
  return null;
});
let M路由_路由表 = [];

// ———— 模块 集合 ————
class M集合_集合 extends lcx.Obj {
  constructor(v_名字) {
    super();
    this.f_名字 = "";
    this.f_名字 = v_名字;
  }
  m_读() {
    let v_库 = null;
    v_库 = host.storeGet(lc.join("集合:", this.f_名字));
    if (lc.isNull(v_库)) {
      v_库 = lc.dictOf("next", 1.0, "rows", []);
    }
    return v_库;
  }
  m_写(v_库) {
    host.storeSet(lc.join("集合:", this.f_名字), v_库);
    return null;
  }
  m_位置(v_rows, v_id) {
    let v_要找 = null, v_行 = null, v_i = null;
    v_要找 = lc.toNumber(v_id);
    for (let lcxs10 = lc.items(v_rows), lci11 = 0; lci11 < lcxs10.length; lci11++) {
      v_行 = lcxs10[lci11];
      v_i = lci11;
      if (lc.eq(lc.dictGet(v_行, "id"), v_要找)) {
        return v_i;
      }
    }
    return (-1.0);
  }
  m_全部() {
    return lc.dictGet(lcx.send(this, "读"), "rows");
  }
  m_个数() {
    return lc.size(lcx.send(this, "全部"));
  }
  m_取(v_id) {
    let v_rows = null;
    v_rows = lcx.send(this, "全部");
    return lc.listGet(v_rows, lcx.send(this, "位置", v_rows, v_id));
  }
  m_找(v_键, v_值) {
    return lc.listFilter(lcx.send(this, "全部"), lc.fn("", 1, 1, (v_行) => {
      return lc.eq(lc.dictGet(v_行, v_键), v_值);
    }));
  }
  m_加(v_值) {
    let v_库 = null, v_行 = null;
    v_库 = lcx.send(this, "读");
    v_行 = lc.dictMerge(lc.dictOf(), v_值);
    lc.setItem(v_行, "id", lc.dictGet(v_库, "next"));
    lc.setItem(v_库, "next", lc.add(lc.dictGet(v_库, "next"), 1.0));
    lc.listPush(lc.dictGet(v_库, "rows"), v_行);
    lcx.send(this, "写", v_库);
    return v_行;
  }
  m_改(v_id, v_值) {
    let v_库 = null, v_rows = null, v_i = null, v_旧 = null, v_新 = null;
    v_库 = lcx.send(this, "读");
    v_rows = lc.dictGet(v_库, "rows");
    v_i = lcx.send(this, "位置", v_rows, v_id);
    if (lc.lt(v_i, 0.0)) {
      return null;
    }
    v_旧 = lc.listGet(v_rows, v_i);
    if (!lc.isType(v_值, "dict")) {
      return v_旧;
    }
    v_新 = lc.dictMerge(v_旧, v_值);
    lc.setItem(v_新, "id", lc.dictGet(v_旧, "id"));
    lc.listSet(v_rows, v_i, v_新);
    lcx.send(this, "写", v_库);
    return v_新;
  }
  m_删(v_id) {
    let v_库 = null, v_rows = null, v_i = null;
    v_库 = lcx.send(this, "读");
    v_rows = lc.dictGet(v_库, "rows");
    v_i = lcx.send(this, "位置", v_rows, v_id);
    if (lc.lt(v_i, 0.0)) {
      return false;
    }
    lc.listRemove(v_rows, v_i);
    lcx.send(this, "写", v_库);
    return true;
  }
}
lcx.named(M集合_集合, "集合");
lcx.sig(M集合_集合.prototype.m_读, 0, 0);
lcx.sig(M集合_集合.prototype.m_写, 1, 1);
lcx.sig(M集合_集合.prototype.m_位置, 2, 2);
lcx.sig(M集合_集合.prototype.m_全部, 0, 0);
lcx.sig(M集合_集合.prototype.m_个数, 0, 0);
lcx.sig(M集合_集合.prototype.m_取, 1, 1);
lcx.sig(M集合_集合.prototype.m_找, 2, 2);
lcx.sig(M集合_集合.prototype.m_加, 1, 1);
lcx.sig(M集合_集合.prototype.m_改, 2, 2);
lcx.sig(M集合_集合.prototype.m_删, 1, 1);
const M集合_集合全部 = lc.fn("集合全部", 1, 1, function (v_名) {
  return lcx.send(new M集合_集合(v_名), "全部");
});
const M集合_集合个数 = lc.fn("集合个数", 1, 1, function (v_名) {
  return lcx.send(new M集合_集合(v_名), "个数");
});
const M集合_集合取 = lc.fn("集合取", 2, 2, function (v_名, v_id) {
  return lcx.send(new M集合_集合(v_名), "取", v_id);
});
const M集合_集合找 = lc.fn("集合找", 3, 3, function (v_名, v_键, v_值) {
  return lcx.send(new M集合_集合(v_名), "找", v_键, v_值);
});
const M集合_集合加 = lc.fn("集合加", 2, 2, function (v_名, v_值) {
  return lcx.send(new M集合_集合(v_名), "加", v_值);
});
const M集合_集合改 = lc.fn("集合改", 3, 3, function (v_名, v_id, v_值) {
  return lcx.send(new M集合_集合(v_名), "改", v_id, v_值);
});
const M集合_集合删 = lc.fn("集合删", 2, 2, function (v_名, v_id) {
  return lcx.send(new M集合_集合(v_名), "删", v_id);
});

// ———— 模块 网络 ————
const M网络_请求网址 = lc.fn("请求网址", 3, 3, async function (v_方式, v_网址, v_数据) {
  return (await host.netFetch(v_方式, v_网址, v_数据));
});

// ———— 模块 样本服务 ————
function lcMain_样本服务() {
  M路由_注册("GET", "/todos", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, M集合_集合全部("todos"));
  }));
  M路由_注册("POST", "/todos", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    if (lc.isNull(M请求_请求内容的字段(v_请求, "title"))) {
      return M响应_JSON响应(400.0, lc.dictOf("error", "缺少 title"));
    }
    v_todo = M集合_集合加("todos", lc.dictOf("title", M请求_请求内容的字段(v_请求, "title"), "done", false));
    return M响应_JSON响应(201.0, v_todo);
  }));
  M路由_注册("GET", "/todos/count", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("count", M集合_集合个数("todos")));
  }));
  M路由_注册("GET", "/todos/:id", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v_todo = M集合_集合取("todos", M请求_路径参数(v_请求, "id"));
    if (lc.isNull(v_todo)) {
      return M响应_JSON响应(404.0, lc.dictOf("error", lc.join("找不到 id 是 ", M请求_路径参数(v_请求, "id"), " 的待办")));
    }
    return M响应_JSON响应(200.0, v_todo);
  }));
  M路由_注册("PATCH", "/todos/:id", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    if (lc.isNull(M集合_集合取("todos", M请求_路径参数(v_请求, "id")))) {
      return M响应_JSON响应(404.0, lc.dictOf("error", lc.join("找不到 id 是 ", M请求_路径参数(v_请求, "id"), " 的待办")));
    }
    M集合_集合改("todos", M请求_路径参数(v_请求, "id"), M请求_请求内容(v_请求));
    return M响应_JSON响应(200.0, M集合_集合取("todos", M请求_路径参数(v_请求, "id")));
  }));
  M路由_注册("DELETE", "/todos/:id", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    if (lc.isNull(M集合_集合取("todos", M请求_路径参数(v_请求, "id")))) {
      return M响应_JSON响应(404.0, lc.dictOf("error", lc.join("找不到 id 是 ", M请求_路径参数(v_请求, "id"), " 的待办")));
    }
    M集合_集合删("todos", M请求_路径参数(v_请求, "id"));
    return null;
  }));
  M路由_注册("GET", "/done", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, M集合_集合找("todos", "done", true));
  }));
  M路由_注册("GET", "/by-title", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, M集合_集合找("todos", "title", M请求_网址参数(v_请求, "t")));
  }));
  M路由_注册("POST", "/notes", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    M集合_集合加("notes", M请求_请求内容(v_请求));
    return M响应_JSON响应(200.0, M集合_集合全部("notes"));
  }));
  M路由_注册("GET", "/calc", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("sum", lc.add(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "diff", lc.sub(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "prod", lc.mul(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "quot", lc.div(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "rem", lc.mod(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "lt", lc.lt(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "le", lc.le(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "gt", lc.gt(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "ge", lc.ge(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "eq", lc.eq(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "ne", lc.ne(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "and", (lc.truthy(M请求_网址参数(v_请求, "a")) && lc.truthy(M请求_网址参数(v_请求, "b"))), "or", (lc.truthy(M请求_网址参数(v_请求, "a")) || lc.truthy(M请求_网址参数(v_请求, "b"))), "notA", !lc.truthy(M请求_网址参数(v_请求, "a"))));
  }));
  M路由_注册("GET", "/numbers", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("third", lc.div(1.0, 3.0), "pointThree", lc.add(0.1, 0.2), "whole", lc.div(6.0, 2.0), "half", lc.div(1.0, 2.0), "negRem", lc.mod((-7.0), 3.0), "fracRem", lc.mod(5.5, 2.0), "divZero", lc.div(5.0, 0.0), "remZero", lc.mod(5.0, 0.0), "negZero", lc.mul(0.0, (-1.0)), "overflow", lc.mul(1e+308, 10.0), "big", 1e+21, "e15", 1000000000000000.0, "justUnder", 999999999999999.0, "nines", 999999999999999.9, "small", 2.5e-10, "tiny", 1.2e-07, "tinier", 1.2e-08, "tie", 12345678901.25, "negTie", (-12345678901.25), "frac", 123456.789, "neg", (-42.0), "negFrac", (-0.5), "long", 1234567890.1234567, "bigInt", 1.2345678901234568e+17));
  }));
  M路由_注册("GET", "/equal", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("numText", lc.eq(5.0, "5"), "numTextDot", lc.eq(5.0, "5.0"), "nullEmpty", lc.eq(lc.dictGet(lc.dictOf(), "x"), ""), "nullNull", lc.eq(lc.dictGet(lc.dictOf(), "x"), lc.dictGet(lc.dictOf(), "x")), "nullZero", lc.eq(lc.dictGet(lc.dictOf(), "x"), 0.0), "zeroEmpty", lc.eq(0.0, ""), "boolText", lc.eq(true, "true"), "oneTrue", lc.eq(1.0, true), "objOrder", lc.eq(lc.dictOf("a", 1.0, "b", 2.0), lc.dictOf("b", 2.0, "a", 1.0)), "objDiff", lc.eq(lc.dictOf("a", 1.0), lc.dictOf("a", 2.0)), "objText", lc.eq(lc.dictOf("a", 1.0), "{\"a\":1}"), "listSame", lc.eq(M集合_集合全部("todos"), M集合_集合全部("todos")), "floatSum", lc.eq(lc.add(0.1, 0.2), 0.3), "neText", lc.ne("a", "b")));
  }));
  M路由_注册("GET", "/truthy", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("null", !!lc.truthy(lc.dictGet(lc.dictOf(), "x")), "false", !!false, "zero", !!lc.truthy(0.0), "empty", !!lc.truthy(""), "textZero", !!lc.truthy("0"), "space", !!lc.truthy(" "), "emptyObj", !!lc.truthy(lc.dictOf()), "emptyList", !!lc.truthy(M集合_集合全部("notes")), "one", !!lc.truthy(1.0), "true", !!true));
  }));
  M路由_注册("GET", "/len", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("text", lc.size("你好😀"), "list", lc.size(M集合_集合全部("todos")), "obj", lc.size(lc.dictOf("a", 1.0, "b", 2.0)), "num", lc.size(12345.0), "null", lc.size(lc.dictGet(lc.dictOf(), "x"))));
  }));
  M路由_注册("GET", "/text/:what", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_文字响应(200.0, lc.join("你好，", M请求_路径参数(v_请求, "what"), "！", 3.0, true, lc.dictGet(lc.dictOf(), "x"), 1.5, lc.dictOf("a", 1.0), M请求_网址参数(v_请求, "q")));
  }));
  M路由_注册("GET", "/special", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("value", "引号\"'反斜杠\\换行\u000a制表\u0009${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完", "引号\"'反斜杠\\换行\u000a制表\u0009${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完", 1.0, "Ａ", 2.0, "😀", 3.0, "a", 4.0, "B", 5.0, "10", 6.0, "9", 7.0, "__proto__", 8.0, "constructor", 9.0));
  }));
  M路由_注册("GET", "/special-text", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_文字响应(200.0, "引号\"'反斜杠\\换行\u000a制表\u0009${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完");
  }));
  M路由_注册("GET", "/loop", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v_n = 0.0;
    for (let lcn12 = lc.times(5.0), lck13 = 0; lck13 < lcn12; lck13++) {
      v_n = lc.add(v_n, 2.0);
    }
    for (let lcn14 = lc.times(M请求_网址参数(v_请求, "times")), lck15 = 0; lck15 < lcn14; lck15++) {
      v_n = lc.add(v_n, 1.0);
    }
    return M响应_JSON响应(200.0, lc.dictOf("n", v_n));
  }));
  M路由_注册("GET", "/each", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v_s = "";
    for (let lcxs16 = lc.items(M集合_集合全部("todos")), lci17 = 0; lci17 < lcxs16.length; lci17++) {
      v_item = lcxs16[lci17];
      v_s = lc.join(v_s, lc.dictGet(v_item, "title"), ";");
      v_acc = lc.add(v_acc, lc.dictGet(v_item, "id"));
      if (lc.eq(M请求_网址参数(v_请求, "grow"), "1")) {
        M集合_集合加("notes", lc.dictOf("from", lc.dictGet(v_item, "id")));
      }
    }
    for (let lcxs18 = lc.items("abc"), lci19 = 0; lci19 < lcxs18.length; lci19++) {
      v_item = lcxs18[lci19];
      v_acc = lc.add(v_acc, 1000.0);
    }
    return M响应_JSON响应(200.0, lc.dictOf("titles", v_s, "sum", v_acc, "count", lc.size(M集合_集合全部("todos"))));
  }));
  M路由_注册("GET", "/early", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_文字响应(200.0, "先返回");
    M集合_集合加("notes", lc.dictOf("bad", "返回之后不该执行"));
    return M响应_文字响应(500.0, "不该到这里");
  }));
  M路由_注册("GET", "/early-loop", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v_n = 0.0;
    for (let lcn20 = lc.times(10.0), lck21 = 0; lck21 < lcn20; lck21++) {
      v_n = lc.add(v_n, 1.0);
      if (lc.eq(v_n, 3.0)) {
        return M响应_JSON响应(200.0, lc.dictOf("stoppedAt", v_n));
      }
    }
    return M响应_文字响应(500.0, "不该到这里");
  }));
  M路由_注册("GET", "/nothing", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    lc.log(lc.join("日志：", 1.5, " ", lc.dictOf("k", "v")));
    return null;
  }));
  M路由_注册("GET", "/branch", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    if (lc.gt(M请求_网址参数(v_请求, "x"), 10.0)) {
      return M响应_文字响应(200.0, "大");
    } else {
      if (lc.truthy(M请求_网址参数(v_请求, "x"))) {
        return M响应_文字响应(200.0, "小");
      } else {
        return M响应_文字响应(200.0, "没有");
      }
    }
    return null;
  }));
  M路由_注册("GET", "/vars", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("n", v_n, "s", v_s, "flag", v_flag, "todo", v_todo, "acc", v_acc));
  }));
  M路由_注册("GET", "/bump", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v_n = lc.add(v_n, 1.0);
    v_s = lc.add(v_s, 2.0);
    v_class = lc.add(v_class, lc.add(v_def, v_func));
    return M响应_JSON响应(200.0, lc.dictOf("n", v_n, "s", v_s, "class", v_class));
  }));
  M路由_注册("POST", "/echo", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("body", M请求_请求内容(v_请求), "name", M请求_请求内容的字段(v_请求, "name"), "nameLen", lc.size(M请求_请求内容的字段(v_请求, "name")), "q", M请求_网址参数(v_请求, "q"), "missing", M请求_网址参数(v_请求, "nope"), "header", M请求_请求头(v_请求, "X-Test"), "noHeader", M请求_请求头(v_请求, "X-Nope"), "noBody", lc.isNull(M请求_请求内容(v_请求))));
  }));
  M路由_注册("GET", "/status", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(M请求_网址参数(v_请求, "code"), lc.dictOf("ok", true));
  }));
  M路由_注册("GET", "/", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_文字响应(200.0, "根");
  }));
  M路由_注册("PUT", "/a/:x/b/:y", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("x", M请求_路径参数(v_请求, "x"), "y", M请求_路径参数(v_请求, "y")));
  }));
  M路由_注册("GET", "/holes", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_JSON响应(200.0, lc.dictOf("unknown", null, "undeclared", null, "badParam", M请求_路径参数(v_请求, "nope"), "badCollection", null, "missing", lc.add(null, null), "badOp", null, "ok", 1.0));
  }));
  M路由_注册("GET", "/relay", lc.fn("", 1, 1, async (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null, v__t1_结果 = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v__t1_结果 = (await M网络_请求网址("GET", lc.join("http://", M请求_请求头(v_请求, "Host"), "/text/relay?q=%E5%A5%BD"), null));
    if (!lc.isNull(v__t1_结果)) {
      v_s = v__t1_结果;
      return M响应_文字响应(200.0, lc.join("拿到：", v_s));
    } else {
      return M响应_文字响应(502.0, "失败");
    }
    return null;
  }));
  M路由_注册("GET", "/relay-post", lc.fn("", 1, 1, async (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null, v__t2_结果 = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v__t2_结果 = (await M网络_请求网址("POST", lc.join("http://", M请求_请求头(v_请求, "Host"), "/echo"), lc.dictOf("name", "转发")));
    if (!lc.isNull(v__t2_结果)) {
      v_s = v__t2_结果;
      return M响应_文字响应(200.0, v_s);
    } else {
      return M响应_文字响应(502.0, "失败");
    }
    return null;
  }));
  M路由_注册("GET", "/relay-fail", lc.fn("", 1, 1, async (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null, v__t3_结果 = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v__t3_结果 = (await M网络_请求网址("GET", M请求_网址参数(v_请求, "url"), null));
    if (!lc.isNull(v__t3_结果)) {
      v_s = v__t3_结果;
      return M响应_文字响应(200.0, "不该成功");
    } else {
      return M响应_文字响应(502.0, lc.join("失败，s 还是：", v_s));
    }
    return null;
  }));
  M路由_注册("GET", "/relay-get", lc.fn("", 1, 1, async (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null, v__t4_结果 = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    v__t4_结果 = (await M网络_请求网址("GET", M请求_网址参数(v_请求, "url"), null));
    if (!lc.isNull(v__t4_结果)) {
      v_s = v__t4_结果;
      return M响应_文字响应(200.0, v_s);
    } else {
      return M响应_文字响应(502.0, "失败");
    }
    return null;
  }));
  M路由_注册("GET", "/say", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_文字响应(200.0, M请求_网址参数(v_请求, "t"));
  }));
  M路由_注册("GET", "/now", lc.fn("", 1, 1, (v_请求) => {
    let v_n = null, v_s = null, v_flag = null, v_todo = null, v_item = null, v_acc = null, v_class = null, v_def = null, v_func = null;
    v_n = 7.0;
    v_s = "初始\"值\\";
    v_flag = true;
    v_todo = "";
    v_item = "";
    v_acc = 0.0;
    v_class = 1.0;
    v_def = 2.0;
    v_func = 3.0;
    return M响应_文字响应(200.0, lc.now());
  }));
  M路由_开始服务(8123.0);
  return null;
}

(async () => {
  lcMain_样本服务();
  host.ready();
})().catch(lcx.die);
