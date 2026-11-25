const lc = require("../_prelude/lc.js");
function 平均(xs) {
  let x;
  let 总 = 0;
  for (x of xs) 总 = lc.iadd(总, x);
  return lc.fdiv(总, xs.length);
}
function 重复(s, n) {
  let out = "";
  for (let i = 0; i < n; i++) out = out + s;
  return out;
}
function 较大(a, b) {
  if (a > b) return a;
  return b;
}
function 阶乘(n) {
  if (n <= 1) return 1;
  return lc.imul(n, 阶乘(lc.isub(n, 1)));
}
function 随便(v) {
  return "[" + lc.dtext(v) + "]";
}
lc.run(() => {
  lc.log("平均 " + lc.fmtNum(平均([1, 2, 4])));
  lc.log(重复("ab", 3));
  lc.log("较大 " + lc.fmtNum(较大(3, 7)));
  lc.log("较大 " + lc.fmtNum(较大(2.5, 1)));
  lc.log("阶乘 " + 阶乘(10));
  lc.log(随便(1));
  lc.log(随便("x"));
  lc.log(随便([1, 2]));
  lc.log("阶乘 " + 阶乘(19));
});
