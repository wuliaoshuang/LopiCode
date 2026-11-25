const lc = require("../_prelude/lc.js");
const 方法 = Object.freeze({ GET: "GET", POST: "POST" });
const 请求 = (方法, 路径, 内容) => Object.freeze({ 方法, 路径, 内容 });
const 响应 = (状态, 内容) => Object.freeze({ 状态, 内容 });
const 路由 = (方法, 段, 处理) => Object.freeze({ 方法, 段, 处理 });
class 路由器 {
  constructor() { this.表 = []; this.中间件 = []; }
  加(m, 路径, h) { this.表.push(路由(m, lc.split(路径, "/"), h)); }
  用(mw) { this.中间件.push(mw); }
  匹配(模, 实) {
    let a, b;
    if (模.length !== 实.length) return null;
    const 参 = new Map();
    for (let i = 0; i < 模.length; i++) {
      a = lc.at(模, i);
      b = lc.at(实, i);
      if (a.startsWith(":")) 参.set(lc.substr(a, 1, lc.textLen(a)), b);
      else if (a !== b) return null;
    }
    return 参;
  }
  处理(req) {
    let r, 参, h, mw;
    const 实 = lc.split(req.路径, "/");
    for (r of this.表) {
      if (r.方法 === req.方法) {
        参 = this.匹配(r.段, 实);
        if (参 !== null) {
          h = r.处理;
          for (mw of this.中间件) h = mw(h);
          return h(req, 参);
        }
      }
    }
    return 响应(404, "没有这个地址：" + req.路径);
  }
}
lc.run(() => {
  let q, res;
  const app = new 路由器();
  let 次数 = 0;
  app.用((下一个) => (req, 参) => { 次数 = lc.iadd(次数, 1); return 下一个(req, 参); });
  app.用((下一个) => (req, 参) => {
    const res = 下一个(req, 参);
    return Object.freeze({ ...res, 内容: res.内容 + " ✓" });
  });
  app.加(方法.GET, "/hello/:name", (req, 参) => 响应(200, "你好，" + (lc.get(参, "name") ?? "?")));
  app.加(方法.POST, "/sum/:a/:b", (req, 参) => {
    const a = lc.parseInt(lc.get(参, "a") ?? "");
    const b = lc.parseInt(lc.get(参, "b") ?? "");
    if (a === null || b === null) return 响应(400, "要两个整数");
    return 响应(200, lc.iadd(a, b) + " " + req.内容);
  });
  for (q of [请求(方法.GET, "/hello/小明", ""), 请求(方法.POST, "/sum/3/4", "ok"), 请求(方法.POST, "/sum/3/x", ""), 请求(方法.GET, "/nope", ""), 请求(方法.GET, "/sum/1/2", "")]) {
    res = app.处理(q);
    lc.log(res.状态 + " " + res.内容);
  }
  lc.log("经过中间件 " + 次数 + " 次");
});
