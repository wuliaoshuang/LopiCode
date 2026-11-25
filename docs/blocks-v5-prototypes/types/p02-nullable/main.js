const lc = require("../_prelude/lc.js");
function 找年龄(名单, 名字) {
  return lc.get(名单, 名字);
}
function 描述(岁) {
  if (岁 === null) return "不知道";
  if (岁 >= 18) return 岁 + "岁，成年";
  return 岁 + "岁，未成年";
}
lc.run(() => {
  let 名, v;
  const 名单 = new Map([["小明", 12], ["小红", 20]]);
  lc.log(描述(找年龄(名单, "小明")));
  lc.log(描述(找年龄(名单, "小红")));
  lc.log(描述(找年龄(名单, "小刚")));
  const 岁 = lc.get(名单, "小刚");
  lc.log("默认：" + (岁 ?? 0));
  let 总 = 0;
  for (名 of ["小明", "小红", "小刚"]) {
    v = lc.get(名单, 名);
    if (v !== null) 总 = lc.iadd(总, v);
  }
  lc.log("总和：" + 总);
  let 首字 = null;
  if (岁 !== null && 岁 > 3) 首字 = "大"; else 首字 = "无";
  lc.log("首字：" + (首字 ?? "?"));
  lc.log("硬取：" + lc.must(岁));
});
