const lc = require("../_prelude/lc.js");
class 圆 {
  constructor(r) { this.r = r; }
  面积() { return 3 * (this.r * this.r); }
  名字() { return "圆"; }
}
class 方 {
  constructor(a) { this.a = a; }
  面积() { return this.a * this.a; }
  名字() { return "方"; }
}
class 动物 {
  constructor(名) { this.腿 = 4; this.名 = 名; }
  叫声() { return "…"; }
  介绍() { return this.名 + "说" + this.叫声() + "，" + this.腿 + "条腿"; }
}
class 狗 extends 动物 {
  constructor(名) { super(名); }
  叫声() { return "汪"; }
}
class 鸟 extends 动物 {
  constructor(名) { super(名); this.腿 = 2; }
  叫声() { return "啾" + super.叫声(); }
}
function 总面积(xs) {
  return xs.reduce((s, x) => s + x.面积(), 0);
}
lc.run(() => {
  let s, p;
  const 形 = [new 圆(1), new 方(2)];
  for (s of 形) lc.log(s.名字() + " " + lc.fmtNum(s.面积()));
  lc.log("总面积 " + lc.fmtNum(总面积(形)));
  const 宠 = [new 狗("旺财"), new 鸟("啾啾"), new 动物("某只")];
  for (p of 宠) lc.log(p.介绍());
  const d = lc.at(宠, 0);
  if (d instanceof 狗) lc.log("第一只是狗");
  lc.log("是鸟吗 " + lc.boolText(d instanceof 鸟));
});
