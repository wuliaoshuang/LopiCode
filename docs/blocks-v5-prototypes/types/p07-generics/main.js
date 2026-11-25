const lc = require("../_prelude/lc.js");
function 第一个(xs) {
  if (xs.length === 0) return null;
  return lc.at(xs, 0);
}
function 最大(xs, 底) {
  let x;
  let m = 底;
  for (x of xs) if (lc.cmp(x, m) > 0) m = x;
  return m;
}
function 配对(ks, vs, f) {
  const out = [];
  for (let i = 0; i < ks.length; i++) out.push(f(lc.at(ks, i), lc.at(vs, i)));
  return out;
}
lc.run(() => {
  lc.log("第一个 " + (第一个([3, 1, 2]) ?? -1));
  const 空表 = [];
  lc.log("空的第一个 " + (第一个(空表) ?? "没有"));
  lc.log("最大整数 " + 最大([3, 9, 2], 0));
  lc.log("最大小数 " + lc.fmtNum(最大([1.5, 0.25], 0)));
  lc.log("最大文字 " + 最大(["ｚ", "😀", "a"], ""));
  lc.log(配对(["a", "b"], [1, 2], (k, v) => k + "=" + v).join(";"));
});
