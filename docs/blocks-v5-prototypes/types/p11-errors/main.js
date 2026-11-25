const lc = require("../_prelude/lc.js");
function 安全除(a, b) {
  try {
    return a + "/" + b + "=" + lc.idiv(a, b);
  } catch (err) {
    if (!(err instanceof lc.LcError)) throw err;
    const e = err.message;
    return a + "/" + b + " 不行：" + e;
  } finally {
    lc.log("算完一次");
  }
}
function 取款(余额, 要取) {
  if (要取 > 余额) lc.fail("余额不够，还差 " + lc.isub(要取, 余额));
  return lc.isub(余额, 要取);
}
lc.run(() => {
  lc.log(安全除(7, 2));
  lc.log(安全除(7, 0));
  let 钱 = 100;
  try { 钱 = 取款(钱, 30); 钱 = 取款(钱, 100); lc.log("到不了这里"); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log("接住：" + e + " 还剩 " + 钱); }
  const xs = [1, 2, 3];
  try { lc.setAt(xs, 5, 9); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log(e); }
  try {
    try { lc.fail("里层"); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.fail(e + "→外层"); }
  } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e2 = err.message; lc.log(e2); }
  lc.log("结果 " + 取款(1, 2));
});
