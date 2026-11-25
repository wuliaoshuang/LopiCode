// 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。
"use strict";
const lc = require("./lc_lang.js");
const lcx = require("./lcx_ext.js");
const host = require("./host_node.js");

// ———— 模块 错误们 ————
class M错误们_HTTP错误 extends lcx.Err {
  constructor(v_状态码, v_消息, v_详情 = null) {
    super(v_消息);
    this.f_状态码 = 500.0;
    this.f_详情 = null;
    this.f_状态码 = v_状态码;
    this.f_详情 = v_详情;
  }
  m_变成内容() {
    let v_内容 = null;
    v_内容 = lc.dictOf("error", this.f_消息);
    if (!lc.isNull(this.f_详情)) {
      lc.setItem(v_内容, "details", this.f_详情);
    }
    return v_内容;
  }
}
lcx.named(M错误们_HTTP错误, "HTTP错误");
lcx.sig(M错误们_HTTP错误.prototype.m_变成内容, 0, 0);
class M错误们_请求不对 extends M错误们_HTTP错误 {
  constructor(v_消息, v_详情 = null) {
    super(400.0, v_消息, v_详情);
  }
}
lcx.named(M错误们_请求不对, "请求不对");
class M错误们_未授权 extends M错误们_HTTP错误 {
  constructor(v_消息 = "请先登录") {
    super(401.0, v_消息);
  }
}
lcx.named(M错误们_未授权, "未授权");
class M错误们_没有这个 extends M错误们_HTTP错误 {
  constructor(v_消息 = "没有这个接口") {
    super(404.0, v_消息);
  }
}
lcx.named(M错误们_没有这个, "没有这个");
class M错误们_方式不对 extends M错误们_HTTP错误 {
  constructor(v_允许的) {
    super(405.0, "这个地址不支持这种请求方式");
    this.f_允许的 = [];
    this.f_允许的 = v_允许的;
  }
}
lcx.named(M错误们_方式不对, "方式不对");
class M错误们_校验没过 extends M错误们_HTTP错误 {
  constructor(v_问题们) {
    super(422.0, "提交的内容不对", v_问题们);
  }
}
lcx.named(M错误们_校验没过, "校验没过");

// ———— 模块 响应 ————
class M响应_响应 extends lcx.Obj {
  constructor(v_状态码, v_类型, v_内容) {
    super();
    this.f_状态码 = 200.0;
    this.f_头 = lc.dictOf();
    this.f_内容 = "";
    this.f_状态码 = v_状态码;
    this.f_头 = lc.dictOf();
    if (lc.ne(v_类型, "")) {
      lc.setItem(this.f_头, "Content-Type", v_类型);
    }
    this.f_内容 = v_内容;
  }
  static m_JSON(v_状态码, v_值) {
    return new M响应_响应(v_状态码, "application/json; charset=utf-8", lc.toJson(v_值));
  }
  static m_文字(v_状态码, v_值) {
    return new M响应_响应(v_状态码, "text/plain; charset=utf-8", lc.toText(v_值));
  }
  static m_空的() {
    return new M响应_响应(204.0, "", "");
  }
  m_加头(v_名字, v_值) {
    lc.setItem(this.f_头, v_名字, lc.toText(v_值));
    return this;
  }
  m_变成字典() {
    return lc.dictOf("status", this.f_状态码, "headers", this.f_头, "body", this.f_内容);
  }
}
lcx.named(M响应_响应, "响应");
lcx.sig(M响应_响应.m_JSON, 2, 2);
lcx.sig(M响应_响应.m_文字, 2, 2);
lcx.sig(M响应_响应.m_空的, 0, 0);
lcx.sig(M响应_响应.prototype.m_加头, 2, 2);
lcx.sig(M响应_响应.prototype.m_变成字典, 0, 0);

// ———— 模块 上下文 ————
class M上下文_上下文 extends lcx.Obj {
  constructor(v_请求) {
    super();
    this.f_方式 = "";
    this.f_路径 = "";
    this.f_段们 = [];
    this.f_路径参数们 = lc.dictOf();
    this.f_网址参数们 = lc.dictOf();
    this.f_数据 = lc.dictOf();
    this.f_请求 = lc.dictOf();
    this.f_内容读过了 = false;
    this.f_内容值 = null;
    let v_段 = null;
    this.f_请求 = v_请求;
    this.f_方式 = lc.dictGet(v_请求, "method");
    this.f_路径 = lc.dictGet(v_请求, "path");
    this.f_段们 = [];
    for (let lcxs1 = lc.items(lc.split(lc.dictGet(v_请求, "path"), "/")), lci2 = 0; lci2 < lcxs1.length; lci2++) {
      v_段 = lcxs1[lci2];
      if (lc.ne(v_段, "")) {
        lc.listPush(this.f_段们, host.urlDecode(v_段));
      }
    }
    this.f_路径参数们 = lc.dictOf();
    this.f_网址参数们 = M上下文_解析网址参数(lc.dictGet(v_请求, "query"));
    this.f_数据 = lc.dictOf();
  }
  m_路径参数(v_名字) {
    return lc.dictGet(this.f_路径参数们, v_名字);
  }
  m_网址参数(v_名字) {
    return lc.dictGet(this.f_网址参数们, v_名字);
  }
  m_请求头(v_名字) {
    return lc.dictGet(lc.dictGet(this.f_请求, "headers"), lc.lower(v_名字));
  }
  m_内容() {
    if (!lc.truthy(this.f_内容读过了)) {
      this.f_内容值 = lc.fromJson(lc.dictGet(this.f_请求, "body"));
      this.f_内容读过了 = true;
    }
    return this.f_内容值;
  }
  m_放(v_名字, v_值) {
    lc.setItem(this.f_数据, v_名字, v_值);
    return null;
  }
  m_取(v_名字) {
    return lc.dictGet(this.f_数据, v_名字);
  }
}
lcx.named(M上下文_上下文, "上下文");
lcx.sig(M上下文_上下文.prototype.m_路径参数, 1, 1);
lcx.sig(M上下文_上下文.prototype.m_网址参数, 1, 1);
lcx.sig(M上下文_上下文.prototype.m_请求头, 1, 1);
lcx.sig(M上下文_上下文.prototype.m_内容, 0, 0);
lcx.sig(M上下文_上下文.prototype.m_放, 2, 2);
lcx.sig(M上下文_上下文.prototype.m_取, 1, 1);
const M上下文_解析网址参数 = lc.fn("解析网址参数", 1, 1, function (v_原文) {
  let v_表 = null, v_段 = null, v_等号 = null, v_键 = null, v_值 = null;
  v_表 = lc.dictOf();
  for (let lcxs3 = lc.items(lc.split(v_原文, "&")), lci4 = 0; lci4 < lcxs3.length; lci4++) {
    v_段 = lcxs3[lci4];
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
    if (!lc.dictHas(v_表, v_键)) {
      lc.setItem(v_表, v_键, host.urlDecode(lc.replace(v_值, "+", " ")));
    }
  }
  return v_表;
});

// ———— 模块 中间件 ————
class M中间件_错误处理 extends lcx.Obj {
  constructor(v_出错时 = null) {
    super();
    this.f_出错时 = null;
    this.f_出错时 = v_出错时;
  }
  async m_处理(v_上下文, v_下一步) {
    let v_e = null, v_回复 = null;
    try {
      return (await lc.call(v_下一步, v_上下文));
    } catch (lce5) {
      v_e = lcx.caught(lce5);
      if ((v_e instanceof M错误们_HTTP错误)) {
        v_回复 = M响应_响应.m_JSON(lcx.getf(v_e, "状态码"), lcx.send(v_e, "变成内容"));
        if ((v_e instanceof M错误们_方式不对)) {
          lcx.send(v_回复, "加头", "Allow", lc.listJoin(lcx.getf(v_e, "允许的"), ", "));
        }
        return v_回复;
      }
      if (lc.isNull(this.f_出错时)) {
        host.logError(lc.join("出错：", lcx.getf(v_上下文, "方式"), " ", lcx.getf(v_上下文, "路径"), "：", lcx.getf(v_e, "消息")));
      } else {
        (await lc.call(this.f_出错时, v_e, v_上下文));
      }
      return M响应_响应.m_JSON(500.0, lc.dictOf("error", "服务器内部出错"));
    }
    return null;
  }
}
lcx.named(M中间件_错误处理, "错误处理");
lcx.sig(M中间件_错误处理.prototype.m_处理, 2, 2);
const M中间件_包一层 = lc.fn("包一层", 2, 2, function (v_这一层, v_里面) {
  if (lc.isType(v_这一层, "function")) {
    return lc.fn("", 1, 1, async (v_上下文) => {
      return (await lc.call(v_这一层, v_上下文, v_里面));
    });
  }
  return lc.fn("", 1, 1, async (v_上下文) => {
    return (await lcx.send(v_这一层, "处理", v_上下文, v_里面));
  });
});
const M中间件_串起来 = lc.fn("串起来", 2, 2, function (v_中间件们, v_最里面) {
  let v_结果 = null, v_i = null;
  v_结果 = v_最里面;
  v_i = lc.sub(lc.size(v_中间件们), 1.0);
  while (lc.ge(v_i, 0.0)) {
    v_结果 = M中间件_包一层(lc.listGet(v_中间件们, v_i), v_结果);
    v_i = lc.sub(v_i, 1.0);
  }
  return v_结果;
});

// ———— 模块 路由 ————
class M路由_路由器 extends lcx.Obj {
  constructor(v_前缀 = "", v_上级 = null) {
    super();
    this.f_前缀段 = [];
    this.f_上级 = null;
    this.f_中间件们 = [];
    this.f_路由们 = [];
    this.f_分组们 = [];
    this.f_前缀段 = M路由_切路径(v_前缀);
    if (!lc.isNull(v_上级)) {
      this.f_前缀段 = lc.listConcat(lcx.getf(v_上级, "前缀段"), this.f_前缀段);
    }
    this.f_上级 = v_上级;
    this.f_中间件们 = [];
    this.f_路由们 = [];
    this.f_分组们 = [];
  }
  m_用(v_一个中间件) {
    lc.listPush(this.f_中间件们, v_一个中间件);
    return this;
  }
  m_分组(v_前缀) {
    let v_组 = null;
    v_组 = new M路由_路由器(v_前缀, this);
    lc.listPush(this.f_分组们, v_组);
    return v_组;
  }
  m_加(v_方式, v_路径, v_处理) {
    lc.listPush(this.f_路由们, lc.dictOf("method", v_方式, "segments", lc.listConcat(this.f_前缀段, M路由_切路径(v_路径)), "handler", v_处理));
    return this;
  }
  m_GET(v_路径, v_处理) {
    return lcx.send(this, "加", "GET", v_路径, v_处理);
  }
  m_POST(v_路径, v_处理) {
    return lcx.send(this, "加", "POST", v_路径, v_处理);
  }
  m_PUT(v_路径, v_处理) {
    return lcx.send(this, "加", "PUT", v_路径, v_处理);
  }
  m_PATCH(v_路径, v_处理) {
    return lcx.send(this, "加", "PATCH", v_路径, v_处理);
  }
  m_DELETE(v_路径, v_处理) {
    return lcx.send(this, "加", "DELETE", v_路径, v_处理);
  }
  m_一路的中间件() {
    if (lc.isNull(this.f_上级)) {
      return [];
    }
    return lc.listConcat(lcx.send(this.f_上级, "一路的中间件"), this.f_中间件们);
  }
  m_全部路由() {
    let v_全部 = null, v_路由 = null, v_组 = null;
    v_全部 = [];
    for (let lcxs6 = lc.items(this.f_路由们), lci7 = 0; lci7 < lcxs6.length; lci7++) {
      v_路由 = lcxs6[lci7];
      lc.listPush(v_全部, lc.dictOf("route", v_路由, "router", this));
    }
    for (let lcxs8 = lc.items(this.f_分组们), lci9 = 0; lci9 < lcxs8.length; lci9++) {
      v_组 = lcxs8[lci9];
      v_全部 = lc.listConcat(v_全部, lcx.send(v_组, "全部路由"));
    }
    return v_全部;
  }
}
lcx.named(M路由_路由器, "路由器");
lcx.sig(M路由_路由器.prototype.m_用, 1, 1);
lcx.sig(M路由_路由器.prototype.m_分组, 1, 1);
lcx.sig(M路由_路由器.prototype.m_加, 3, 3);
lcx.sig(M路由_路由器.prototype.m_GET, 2, 2);
lcx.sig(M路由_路由器.prototype.m_POST, 2, 2);
lcx.sig(M路由_路由器.prototype.m_PUT, 2, 2);
lcx.sig(M路由_路由器.prototype.m_PATCH, 2, 2);
lcx.sig(M路由_路由器.prototype.m_DELETE, 2, 2);
lcx.sig(M路由_路由器.prototype.m_一路的中间件, 0, 0);
lcx.sig(M路由_路由器.prototype.m_全部路由, 0, 0);
class M路由_应用 extends M路由_路由器 {
  constructor() {
    super();
  }
  async m_找并处理(v_上下文) {
    let v_允许的 = null, v_项 = null, v_路由 = null, v_参数 = null, v_处理 = null, v_链 = null;
    v_允许的 = [];
    for (let lcxs10 = lc.items(lcx.send(this, "全部路由")), lci11 = 0; lci11 < lcxs10.length; lci11++) {
      v_项 = lcxs10[lci11];
      v_路由 = lc.dictGet(v_项, "route");
      v_参数 = M路由_对得上(lc.dictGet(v_路由, "segments"), lcx.getf(v_上下文, "段们"));
      if (lc.isNull(v_参数)) {
        continue;
      }
      if (lc.ne(lc.dictGet(v_路由, "method"), lcx.getf(v_上下文, "方式"))) {
        if (!lc.listContains(v_允许的, lc.dictGet(v_路由, "method"))) {
          lc.listPush(v_允许的, lc.dictGet(v_路由, "method"));
        }
        continue;
      }
      lcx.setf(v_上下文, "路径参数们", v_参数);
      v_处理 = lc.dictGet(v_路由, "handler");
      v_链 = M中间件_串起来(lcx.send(lc.dictGet(v_项, "router"), "一路的中间件"), lc.fn("", 1, 1, async (v_上下文) => {
        return M路由_变成响应((await lc.call(v_处理, v_上下文)));
      }));
      return (await lc.call(v_链, v_上下文));
    }
    if (lc.gt(lc.size(v_允许的), 0.0)) {
      throw lcx.toErr(new M错误们_方式不对(v_允许的));
    }
    throw lcx.toErr(new M错误们_没有这个());
  }
  async m_处理请求(v_请求) {
    let v_自己 = null, v_链 = null, v_回复 = null, v_e = null;
    v_自己 = this;
    v_链 = M中间件_串起来(this.f_中间件们, lc.fn("", 1, 1, async (v_上下文) => {
      return (await lcx.send(v_自己, "找并处理", v_上下文));
    }));
    v_回复 = null;
    try {
      v_回复 = M路由_变成响应((await lc.call(v_链, new M上下文_上下文(v_请求))));
    } catch (lce12) {
      v_e = lcx.caught(lce12);
      v_回复 = M响应_响应.m_JSON(500.0, lc.dictOf("error", "服务器内部出错"));
    }
    return lcx.send(v_回复, "变成字典");
  }
  m_开始服务(v_端口) {
    let v_自己 = null;
    v_自己 = this;
    host.httpServe(v_端口, lc.fn("", 1, 1, async (v_请求) => {
      return (await lcx.send(v_自己, "处理请求", v_请求));
    }));
    return null;
  }
}
lcx.named(M路由_应用, "应用");
lcx.sig(M路由_应用.prototype.m_找并处理, 1, 1);
lcx.sig(M路由_应用.prototype.m_处理请求, 1, 1);
lcx.sig(M路由_应用.prototype.m_开始服务, 1, 1);
const M路由_切路径 = lc.fn("切路径", 1, 1, function (v_路径) {
  let v_段们 = null, v_段 = null;
  v_段们 = [];
  for (let lcxs13 = lc.items(lc.split(v_路径, "/")), lci14 = 0; lci14 < lcxs13.length; lci14++) {
    v_段 = lcxs13[lci14];
    if (lc.ne(v_段, "")) {
      lc.listPush(v_段们, v_段);
    }
  }
  return v_段们;
});
const M路由_变成响应 = lc.fn("变成响应", 1, 1, function (v_值) {
  if ((v_值 instanceof M响应_响应)) {
    return v_值;
  } else if (lc.isNull(v_值)) {
    return M响应_响应.m_空的();
  } else if (lc.isType(v_值, "text")) {
    return M响应_响应.m_文字(200.0, v_值);
  }
  return M响应_响应.m_JSON(200.0, v_值);
});
const M路由_对得上 = lc.fn("对得上", 2, 2, function (v_模式, v_段们) {
  let v_参数 = null, v_想要 = null, v_i = null, v_实际 = null;
  if (lc.ne(lc.size(v_模式), lc.size(v_段们))) {
    return null;
  }
  v_参数 = lc.dictOf();
  for (let lcxs15 = lc.items(v_模式), lci16 = 0; lci16 < lcxs15.length; lci16++) {
    v_想要 = lcxs15[lci16];
    v_i = lci16;
    v_实际 = lc.listGet(v_段们, v_i);
    if (lc.startsWith(v_想要, ":")) {
      lc.setItem(v_参数, lc.substring(v_想要, 1.0, lc.size(v_想要)), v_实际);
    } else if (lc.ne(v_想要, v_实际)) {
      return null;
    }
  }
  return v_参数;
});

// ———— 模块 校验 ————
class M校验_校验器 extends lcx.Obj {
  constructor() {
    super();
    this.f_规则们 = [];
    this.f_规则们 = [];
  }
  m_规则(v_一条) {
    lc.listPush(this.f_规则们, v_一条);
    return this;
  }
  m_必填(v_字段) {
    return lcx.send(this, "规则", lc.fn("", 1, 1, (v_数据) => {
      if (lc.isNull(lc.dictGet(v_数据, v_字段))) {
        return lc.join(v_字段, " 必须填");
      }
      return null;
    }));
  }
  m_文字(v_字段, v_最短, v_最长) {
    return lcx.send(this, "规则", lc.fn("", 1, 1, (v_数据) => {
      let v_值 = null;
      v_值 = lc.dictGet(v_数据, v_字段);
      if (lc.isNull(v_值)) {
        return null;
      } else if (!lc.isType(v_值, "text")) {
        return lc.join(v_字段, " 要是文字");
      } else if ((lc.lt(lc.size(v_值), v_最短) || lc.gt(lc.size(v_值), v_最长))) {
        return lc.join(v_字段, " 的长度要在 ", v_最短, " 到 ", v_最长, " 之间");
      }
      return null;
    }));
  }
  m_数字(v_字段, v_最小, v_最大) {
    return lcx.send(this, "规则", lc.fn("", 1, 1, (v_数据) => {
      let v_值 = null;
      v_值 = lc.dictGet(v_数据, v_字段);
      if (lc.isNull(v_值)) {
        return null;
      } else if (!lc.isType(v_值, "number")) {
        return lc.join(v_字段, " 要是数字");
      } else if ((lc.lt(v_值, v_最小) || lc.gt(v_值, v_最大))) {
        return lc.join(v_字段, " 要在 ", v_最小, " 到 ", v_最大, " 之间");
      }
      return null;
    }));
  }
  m_其中之一(v_字段, v_可选的) {
    return lcx.send(this, "规则", lc.fn("", 1, 1, (v_数据) => {
      let v_值 = null;
      v_值 = lc.dictGet(v_数据, v_字段);
      if (lc.isNull(v_值)) {
        return null;
      } else if (!lc.listContains(v_可选的, v_值)) {
        return lc.join(v_字段, " 只能是 ", lc.listJoin(v_可选的, "、"), " 里的一个");
      }
      return null;
    }));
  }
  async m_检查(v_数据) {
    let v_问题们 = null, v_一条 = null, v_问题 = null;
    if (!lc.isType(v_数据, "dict")) {
      throw lcx.toErr(new M错误们_校验没过(["提交的内容要是一个 JSON 对象"]));
    }
    v_问题们 = [];
    for (let lcxs17 = lc.items(this.f_规则们), lci18 = 0; lci18 < lcxs17.length; lci18++) {
      v_一条 = lcxs17[lci18];
      v_问题 = (await lc.call(v_一条, v_数据));
      if (!lc.isNull(v_问题)) {
        lc.listPush(v_问题们, v_问题);
      }
    }
    if (lc.gt(lc.size(v_问题们), 0.0)) {
      throw lcx.toErr(new M错误们_校验没过(v_问题们));
    }
    return v_数据;
  }
}
lcx.named(M校验_校验器, "校验器");
lcx.sig(M校验_校验器.prototype.m_规则, 1, 1);
lcx.sig(M校验_校验器.prototype.m_必填, 1, 1);
lcx.sig(M校验_校验器.prototype.m_文字, 3, 3);
lcx.sig(M校验_校验器.prototype.m_数字, 3, 3);
lcx.sig(M校验_校验器.prototype.m_其中之一, 2, 2);
lcx.sig(M校验_校验器.prototype.m_检查, 1, 1);
const M校验_要数字 = lc.fn("要数字", 2, 2, function (v_文字, v_名字) {
  if (!lcx.isNumeric(v_文字)) {
    throw lcx.toErr(new M错误们_请求不对(lc.join(v_名字, " 要是数字")));
  }
  return lc.toNumber(v_文字);
});

// ———— 模块 仓库 ————
class M仓库_仓库 extends lcx.Obj {
  constructor(v_名字) {
    super();
    this.f_名字 = "";
    this.f_名字 = v_名字;
  }
  m_格子() {
    return lc.join("仓库:", this.f_名字);
  }
  m_改库(v_改法) {
    return host.storeUpdate(lcx.send(this, "格子"), lc.fn("", 1, 1, (v_库) => {
      return lc.call(v_改法, lcx.orElse(v_库, lc.dictOf("next", 1.0, "rows", [])));
    }));
  }
  m_全部() {
    return lcx.orElse(lc.dictGet(host.storeGet(lcx.send(this, "格子")), "rows"), []);
  }
  m_取(v_id) {
    return lc.listFind(lcx.send(this, "全部"), lc.fn("", 1, 1, (v_行) => {
      return lc.eq(lc.dictGet(v_行, "id"), v_id);
    }));
  }
  m_加(v_内容) {
    return lcx.send(this, "改库", lc.fn("", 1, 1, (v_库) => {
      let v_行 = null;
      v_行 = lc.dictMerge(v_内容, lc.dictOf("id", lc.dictGet(v_库, "next")));
      lc.setItem(v_库, "next", lc.add(lc.dictGet(v_库, "next"), 1.0));
      lc.listPush(lc.dictGet(v_库, "rows"), v_行);
      return [v_库, v_行];
    }));
  }
  m_改(v_id, v_内容) {
    return lcx.send(this, "改库", lc.fn("", 1, 1, (v_库) => {
      let v_结果 = null, v_行 = null, v_i = null;
      v_结果 = null;
      for (let lcxs19 = lc.items(lc.dictGet(v_库, "rows")), lci20 = 0; lci20 < lcxs19.length; lci20++) {
        v_行 = lcxs19[lci20];
        v_i = lci20;
        if (lc.eq(lc.dictGet(v_行, "id"), v_id)) {
          v_结果 = lc.dictMerge(lc.dictMerge(v_行, v_内容), lc.dictOf("id", v_id));
          lc.listSet(lc.dictGet(v_库, "rows"), v_i, v_结果);
        }
      }
      return [v_库, v_结果];
    }));
  }
  m_删(v_id) {
    return lcx.send(this, "改库", lc.fn("", 1, 1, (v_库) => {
      let v_剩下 = null, v_删了 = null;
      v_剩下 = lc.listFilter(lc.dictGet(v_库, "rows"), lc.fn("", 1, 1, (v_行) => {
        return lc.ne(lc.dictGet(v_行, "id"), v_id);
      }));
      v_删了 = lc.ne(lc.size(v_剩下), lc.size(lc.dictGet(v_库, "rows")));
      lc.setItem(v_库, "rows", v_剩下);
      return [v_库, v_删了];
    }));
  }
}
lcx.named(M仓库_仓库, "仓库");
lcx.sig(M仓库_仓库.prototype.m_格子, 0, 0);
lcx.sig(M仓库_仓库.prototype.m_改库, 1, 1);
lcx.sig(M仓库_仓库.prototype.m_全部, 0, 0);
lcx.sig(M仓库_仓库.prototype.m_取, 1, 1);
lcx.sig(M仓库_仓库.prototype.m_加, 1, 1);
lcx.sig(M仓库_仓库.prototype.m_改, 2, 2);
lcx.sig(M仓库_仓库.prototype.m_删, 1, 1);

// ———— 模块 书店服务 ————
class M书店服务_不许 extends M错误们_HTTP错误 {
  constructor(v_需要) {
    super(403.0, "这件事只有管理员能做");
    this.f_需要 = "";
    this.f_需要 = v_需要;
  }
  m_变成内容() {
    let v_内容 = null;
    v_内容 = super.m_变成内容();
    lc.setItem(v_内容, "need", this.f_需要);
    return v_内容;
  }
}
lcx.named(M书店服务_不许, "不许");
lcx.sig(M书店服务_不许.prototype.m_变成内容, 0, 0);
class M书店服务_茶壶 extends M错误们_HTTP错误 {
  constructor() {
    super(418.0, "我是茶壶");
  }
  m_变成内容() {
    return lc.dictMerge(super.m_变成内容(), lc.dictOf("tea", "龙井"));
  }
}
lcx.named(M书店服务_茶壶, "茶壶");
lcx.sig(M书店服务_茶壶.prototype.m_变成内容, 0, 0);
class M书店服务_预检 extends lcx.Obj {
  constructor(...lcArgs) {
    super(...lcArgs);
  }
  async m_处理(v_上下文, v_下一步) {
    if (lc.eq(lcx.getf(v_上下文, "方式"), "OPTIONS")) {
      return lcx.send(M响应_响应.m_空的(), "加头", "Allow", "GET, POST, PUT, DELETE");
    }
    return (await lc.call(v_下一步, v_上下文));
  }
}
lcx.named(M书店服务_预检, "预检");
lcx.sig(M书店服务_预检.prototype.m_处理, 2, 2);
class M书店服务_鉴权 extends lcx.Obj {
  constructor(v_钥匙们) {
    super();
    this.f_钥匙们 = lc.dictOf();
    this.f_钥匙们 = v_钥匙们;
  }
  async m_处理(v_上下文, v_下一步) {
    let v_头 = null, v_用户 = null;
    v_头 = lcx.send(v_上下文, "请求头", "Authorization");
    if ((lc.isNull(v_头) || !lc.startsWith(v_头, "Bearer "))) {
      throw lcx.toErr(new M错误们_未授权());
    }
    v_用户 = lc.dictGet(this.f_钥匙们, lc.substring(v_头, 7.0, lc.size(v_头)));
    if (lc.isNull(v_用户)) {
      throw lcx.toErr(new M错误们_未授权("钥匙不对"));
    }
    lcx.send(v_上下文, "放", "用户", v_用户);
    return (await lc.call(v_下一步, v_上下文));
  }
}
lcx.named(M书店服务_鉴权, "鉴权");
lcx.sig(M书店服务_鉴权.prototype.m_处理, 2, 2);
const M书店服务_记日志 = lc.fn("记日志", 2, 2, async function (v_上下文, v_下一步) {
  let v_号 = null, v_开始 = null, v_回复 = null;
  M书店服务_请求数 = lc.add(M书店服务_请求数, 1.0);
  v_号 = M书店服务_请求数;
  v_开始 = host.timeMs();
  v_回复 = (await lc.call(v_下一步, v_上下文));
  host.logError(lc.join("#", v_号, " 用了 ", lc.sub(host.timeMs(), v_开始), " 毫秒"));
  lc.log(lc.join("#", v_号, " ", lcx.getf(v_上下文, "方式"), " ", lcx.getf(v_上下文, "路径"), " → ", lcx.getf(v_回复, "状态码")));
  return lcx.send(v_回复, "加头", "X-Request-Id", v_号);
});
const M书店服务_要管理员 = lc.fn("要管理员", 1, 1, function (v_上下文) {
  if (lc.ne(lc.dictGet(lcx.send(v_上下文, "取", "用户"), "role"), "admin")) {
    throw lcx.toErr(new M书店服务_不许("admin"));
  }
  return null;
});
const M书店服务_书的校验 = lc.fn("书的校验", 1, 1, function (v_新建) {
  let v_v = null;
  v_v = new M校验_校验器();
  if (lc.truthy(v_新建)) {
    lcx.send(lcx.send(v_v, "必填", "title"), "必填", "year");
  }
  lcx.send(lcx.send(lcx.send(v_v, "文字", "title", 1.0, 40.0), "数字", "year", 1000.0, 2100.0), "其中之一", "tag", ["科幻", "文学", "未分类"]);
  return v_v;
});
const M书店服务_找书 = lc.fn("找书", 1, 1, function (v_上下文) {
  let v_书 = null;
  v_书 = lcx.send(M书店服务_书们, "取", M校验_要数字(lcx.send(v_上下文, "路径参数", "id"), "id"));
  if (lc.isNull(v_书)) {
    throw lcx.toErr(new M错误们_没有这个("没有这本书"));
  }
  return v_书;
});
let M书店服务_app = new M路由_应用();
let M书店服务_书们 = new M仓库_仓库("books");
let M书店服务_作者们 = new M仓库_仓库("authors");
let M书店服务_请求数 = 0.0;
function lcMain_书店服务() {
  let v_api = null, v_作者组 = null;
  lcx.send(M书店服务_app, "加", "GET", "/hello/:name", lc.fn("", 1, 1, (v_上下文) => {
    return M响应_响应.m_JSON(200.0, lc.dictOf("hello", lcx.send(v_上下文, "路径参数", "name")));
  }));
  lcx.send(M书店服务_app, "用", M书店服务_记日志);
  lcx.send(M书店服务_app, "用", new M中间件_错误处理());
  lcx.send(M书店服务_app, "用", new M书店服务_预检());
  lcx.send(M书店服务_app, "GET", "/", lc.fn("", 1, 1, (v_上下文) => {
    return "小书店";
  }));
  lcx.send(M书店服务_app, "GET", "/health", lc.fn("", 1, 1, (v_上下文) => {
    return lc.dictOf("ok", true, "books", lc.size(lcx.send(M书店服务_书们, "全部")));
  }));
  lcx.send(M书店服务_app, "GET", "/boom", lc.fn("", 1, 1, (v_上下文) => {
    throw lcx.toErr("炸了");
  }));
  lcx.send(M书店服务_app, "GET", "/boom/teapot", lc.fn("", 1, 1, (v_上下文) => {
    throw lcx.toErr(new M书店服务_茶壶());
  }));
  lcx.send(M书店服务_app, "GET", "/boom/lib", lc.fn("", 1, 1, (v_上下文) => {
    lc.listSet([], 5.0, 1.0);
    return "不该到这里";
  }));
  lcx.send(M书店服务_app, "GET", "/slow", lc.fn("", 1, 1, async (v_上下文) => {
    (await host.timeSleep(30.0));
    return lc.dictOf("slept", 30.0);
  }));
  lcx.send(M书店服务_app, "GET", "/parallel", lc.fn("", 1, 1, async (v_上下文) => {
    let v_甲 = null, v_乙 = null;
    v_甲 = lcx.spawn(async () => {
      (await host.timeSleep(20.0));
      return 1.0;
    });
    v_乙 = lcx.spawn(async () => {
      (await host.timeSleep(10.0));
      return 2.0;
    });
    return lc.dictOf("sum", lc.add((await v_甲), (await v_乙)));
  }));
  v_api = lcx.send(M书店服务_app, "分组", "/api");
  lcx.send(v_api, "用", new M书店服务_鉴权(lc.dictOf("k-ming", lc.dictOf("name", "小明", "role", "admin"), "k-hong", lc.dictOf("name", "小红", "role", "reader"))));
  lcx.send(v_api, "GET", "/me", lc.fn("", 1, 1, (v_上下文) => {
    return lcx.send(v_上下文, "取", "用户");
  }));
  lcx.send(v_api, "GET", "/books", lc.fn("", 1, 1, (v_上下文) => {
    let v_标签 = null;
    v_标签 = lcx.send(v_上下文, "网址参数", "tag");
    if (lc.isNull(v_标签)) {
      return lcx.send(M书店服务_书们, "全部");
    }
    return lc.listFilter(lcx.send(M书店服务_书们, "全部"), lc.fn("", 1, 1, (v_书) => {
      return lc.eq(lc.dictGet(v_书, "tag"), v_标签);
    }));
  }));
  lcx.send(v_api, "POST", "/books", lc.fn("", 1, 1, async (v_上下文) => {
    let v_数据 = null, v_书 = null;
    v_数据 = (await lcx.send(M书店服务_书的校验(true), "检查", lcx.send(v_上下文, "内容")));
    v_书 = lcx.send(M书店服务_书们, "加", lc.dictOf("title", lc.dictGet(v_数据, "title"), "year", lc.dictGet(v_数据, "year"), "tag", lcx.orElse(lc.dictGet(v_数据, "tag"), "未分类"), "by", lc.dictGet(lcx.send(v_上下文, "取", "用户"), "name")));
    return lcx.send(M响应_响应.m_JSON(201.0, v_书), "加头", "Location", lc.join("/api/books/", lc.dictGet(v_书, "id")));
  }));
  lcx.send(v_api, "GET", "/books/:id", lc.fn("", 1, 1, (v_上下文) => {
    return M书店服务_找书(v_上下文);
  }));
  lcx.send(v_api, "PUT", "/books/:id", lc.fn("", 1, 1, async (v_上下文) => {
    let v_书 = null, v_数据 = null, v_改动 = null, v_键 = null;
    v_书 = M书店服务_找书(v_上下文);
    v_数据 = (await lcx.send(M书店服务_书的校验(false), "检查", lcx.send(v_上下文, "内容")));
    v_改动 = lc.dictOf();
    for (let lcxs21 = lc.items(["title", "year", "tag"]), lci22 = 0; lci22 < lcxs21.length; lci22++) {
      v_键 = lcxs21[lci22];
      if (lc.dictHas(v_数据, v_键)) {
        lc.setItem(v_改动, v_键, lc.dictGet(v_数据, v_键));
      }
    }
    return lcx.send(M书店服务_书们, "改", lc.dictGet(v_书, "id"), v_改动);
  }));
  lcx.send(v_api, "DELETE", "/books/:id", lc.fn("", 1, 1, (v_上下文) => {
    let v_书 = null;
    M书店服务_要管理员(v_上下文);
    v_书 = M书店服务_找书(v_上下文);
    lcx.send(M书店服务_书们, "删", lc.dictGet(v_书, "id"));
    return null;
  }));
  v_作者组 = lcx.send(v_api, "分组", "/authors");
  lcx.send(v_作者组, "用", lc.fn("", 2, 2, async (v_上下文, v_下一步) => {
    return lcx.send((await lc.call(v_下一步, v_上下文)), "加头", "X-Group", "authors");
  }));
  lcx.send(v_作者组, "GET", "/", lc.fn("", 1, 1, (v_上下文) => {
    return lcx.send(M书店服务_作者们, "全部");
  }));
  lcx.send(v_作者组, "POST", "/", lc.fn("", 1, 1, async (v_上下文) => {
    let v_数据 = null;
    v_数据 = (await lcx.send(lcx.send(lcx.send(new M校验_校验器(), "必填", "name"), "文字", "name", 1.0, 20.0), "检查", lcx.send(v_上下文, "内容")));
    return M响应_响应.m_JSON(201.0, lcx.send(M书店服务_作者们, "加", lc.dictOf("name", lc.dictGet(v_数据, "name"))));
  }));
  lcx.send(M书店服务_app, "开始服务", 8200.0);
  return null;
}

(async () => {
  lcMain_书店服务();
  host.ready();
})().catch(lcx.die);
