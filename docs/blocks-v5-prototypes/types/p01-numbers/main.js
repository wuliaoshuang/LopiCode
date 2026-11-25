const lc = require("../_prelude/lc.js");
lc.run(() => {
  const a = 7, b = 2;
  const x = 0.1, y = 0.2;
  lc.log("7/2=" + lc.fmtNum(lc.fdiv(a, b)));
  lc.log("7整除2=" + lc.idiv(a, b));
  lc.log("-7整除2=" + lc.idiv(lc.isub(0, a), b));
  lc.log("-7余2=" + lc.imod(lc.isub(0, a), b));
  lc.log("7余-2=" + lc.imod(a, lc.isub(0, b)));
  lc.log("0.1+0.2=" + lc.fmtNum(x + y));
  lc.log("a+x=" + lc.fmtNum(a + x));
  lc.log("6/3=" + lc.fmtNum(lc.fdiv(6, 3)));
  const 大 = 9007199254740991;
  lc.log("最大整数=" + 大);
  const 平均 = lc.fdiv(lc.iadd(a, b), 2);
  lc.log("平均=" + lc.fmtNum(平均));
  const n = lc.ftoi(x * 30);
  lc.log("n=" + n);
  const f = 1e308;
  lc.log("太大=" + lc.fmtNum(f * 10));
  try { lc.log("大+1=" + lc.iadd(大, 1)); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log("接住：" + e); }
  try { lc.log("7整除0=" + lc.idiv(a, 0)); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log("接住：" + e); }
  try { lc.log("x/0=" + lc.fmtNum(lc.fdiv(x, 0))); } catch (err) { if (!(err instanceof lc.LcError)) throw err; const e = err.message; lc.log("接住：" + e); }
  lc.log("平方=" + lc.imul(94906267, 94906267));
});
