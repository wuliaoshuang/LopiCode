const lc = require("../_prelude/lc.js");
function 读用户(数据) {
  const d = lc.asDict(数据);
  const 名 = lc.asText(lc.get(d, "名字"));
  const 岁 = lc.asInt(lc.get(d, "年龄"));
  const 标签 = lc.asList(lc.get(d, "标签")).map((t) => lc.asText(t));
  return 名 + " " + lc.iadd(岁, 1) + " " + 标签.join("/");
}
lc.run(() => {
  let 坏;
  const 好 = new Map([["名字", "小明"], ["年龄", 12], ["标签", ["a", "b"]]]);
  lc.log(读用户(好));
  const n = 41;
  const 装 = n;
  lc.log("装进再取出 " + lc.iadd(lc.asInt(装), 1));
  lc.log("任意相加 " + lc.dtext(lc.dadd(装, 0.5)));
  lc.log("任意的样子 " + lc.dtext(好));
  for (坏 of [
    new Map([["名字", "小红"], ["年龄", "十二"], ["标签", []]]),
    new Map([["名字", 7]]),
    new Map([["名字", "小刚"], ["年龄", 12.5], ["标签", []]]),
    "不是字典",
    new Map([["名字", "小白"], ["年龄", 3], ["标签", [1]]]),
  ]) {
    try { lc.log(读用户(坏)); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log("不行：" + e); }
  }
});
