const lc = require("../_prelude/lc.js");
// 记录 → 冻结的普通对象 ＋ 生成的“按内容比较”函数
const 点 = (x, y) => Object.freeze({ x, y });
const 点_eq = (a, b) => a.x === b.x && a.y === b.y;
const 用户 = (名字, 年龄, 位置, 昵称) => Object.freeze({ 名字, 年龄, 位置, 昵称 });
const 用户_eq = (a, b) => a.名字 === b.名字 && a.年龄 === b.年龄 && 点_eq(a.位置, b.位置) && a.昵称 === b.昵称;
function 搬家(u, dx) {
  return Object.freeze({ ...u, 位置: Object.freeze({ ...u.位置, x: u.位置.x + dx }) });
}
function 介绍(u) {
  return u.名字 + "(" + u.年龄 + ") 在 " + lc.fmtNum(u.位置.x) + "," + lc.fmtNum(u.位置.y) + " 昵称:" + (u.昵称 ?? "无");
}
lc.run(() => {
  const a = 用户("小明", 12, 点(1, 2.5), null);
  const b = 搬家(a, 0.5);
  lc.log(介绍(a));
  lc.log(介绍(b));
  const c = Object.freeze({ ...b, 昵称: "明明" });
  lc.log(介绍(c));
  lc.log("a等于a的拷贝 " + lc.boolText(用户_eq(a, Object.freeze({ ...a }))));
  lc.log("a等于b " + lc.boolText(用户_eq(a, b)));
  const 全部 = [a, b, c];
  lc.log("平均年龄 " + lc.fmtNum(lc.fdiv(全部.reduce((s, u) => lc.iadd(s, u.年龄), 0), 全部.length)));
});
