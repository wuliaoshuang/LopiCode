const lc = require("../_prelude/lc.js");
lc.run(() => {
  const xs = [1, 2, 3];
  const 装 = lc.toDyn(xs);
  xs.push(4);
  lc.log("原来的有 " + xs.length + " 项，装进任意的是 " + lc.dtext(装));
  const 动 = lc.asList(装);
  动.push("五");
  lc.log("任意里的 " + lc.dtext(装));
  try { lc.asListOf(装, lc.asInt); lc.log("到不了这里"); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log("不行：" + e); }
  动.pop();
  const 回 = lc.asListOf(装, lc.asInt);
  回.push(9);
  lc.log("取回来的 " + 回.map((n) => String(n)).join(",") + "，任意里的 " + lc.dtext(装) + "，原来的有 " + xs.length + " 项");
  const d = new Map([["a", 1.5]]);
  const 装2 = lc.toDyn(d);
  d.set("b", 2);
  lc.log("字典 " + lc.dtext(装2) + "，原来的有 " + d.size + " 项");
});
