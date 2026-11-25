const lc = require("../_prelude/lc.js");
lc.run(() => {
  let w, k, v;
  const 词 = ["苹果", "香蕉", "苹果", "😀", "橙子", "香蕉", "苹果", "ｚ"];
  const 数 = new Map();
  for (w of 词) 数.set(w, lc.iadd(lc.get(数, w) ?? 0, 1));
  for (k of lc.keys(数)) {
    v = 数.get(k);
    lc.log(k + "=" + v);
  }
  lc.log("共 " + 数.size + " 种");
  lc.log("有梨吗 " + lc.boolText(数.has("梨")));
  数.delete("香蕉");
  lc.log(lc.keys(数).join("|"));
});
