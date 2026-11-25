const lc = require("../_prelude/lc.js");
// 枚举 → 一组固定的文字；变体 → 带 tag 的冻结对象
const 灯 = Object.freeze({ 红: "红", 黄: "黄", 绿: "绿" });
const 形状 = {
  圆: (r) => Object.freeze({ tag: "圆", r }),
  矩形: (w, h) => Object.freeze({ tag: "矩形", w, h }),
  点: () => Object.freeze({ tag: "点" }),
};
function 下一个(l) {
  switch (l) {
    case 灯.红: return 灯.绿;
    case 灯.绿: return 灯.黄;
    case 灯.黄: return 灯.红;
  }
  throw new Error("到不了这里");
}
function 面积(s) {
  switch (s.tag) {
    case "圆": { const r = s.r; return 3 * (r * r); }
    case "矩形": { const w = s.w, h = s.h; return w * h; }
    case "点": return 0;
  }
  throw new Error("到不了这里");
}
lc.run(() => {
  let s;
  let l = 灯.红;
  for (let i = 0; i < 4; i++) {
    lc.log(i + ":" + l);
    l = 下一个(l);
  }
  const 全 = [形状.圆(1), 形状.矩形(2, 3.5), 形状.点()];
  for (s of 全) lc.log("面积 " + lc.fmtNum(面积(s)));
  lc.log("红==红 " + lc.boolText(l === 灯.红));
  const t = lc.at(全, 1);
  switch (t.tag) {
    case "矩形": { const w = t.w; lc.log("宽" + lc.fmtNum(w)); break; }
    default: lc.log("不是矩形");
  }
});
