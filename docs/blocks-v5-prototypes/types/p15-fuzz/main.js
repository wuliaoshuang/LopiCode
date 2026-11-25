const lc = require("../_prelude/lc.js");
const 下一个 = (x) => lc.imod(lc.imul(x, 48271), 2147483647);
function 搅(h, s) {
  for (const ch of s) h = lc.imod(lc.iadd(lc.imul(h, 31), ch.codePointAt(0)), 1000000007);
  return h;
}
const 试算 = (f) => { try { return f(); } catch (e) { if (!(e instanceof lc.LcError)) throw e; return e.message; } };
lc.run(() => {
  let x = 20261125, h1 = 7, h2 = 7, 错 = 0, 不同 = 0;
  for (let i = 0; i < 2000; i++) {
    x = 下一个(x); const a = lc.isub(lc.imod(x, 2000001), 1000000);
    x = 下一个(x); const b = lc.isub(lc.imod(x, 41), 20);
    x = 下一个(x); const p = lc.fdiv(lc.isub(lc.imod(x, 2000001), 1000000), 997);
    x = 下一个(x); const q = lc.fdiv(lc.isub(lc.imod(x, 20001), 10000), 7);
    const r1 = 试算(() => lc.iadd(a, b) + "," + lc.isub(a, b) + "," + lc.imul(a, b) + "," + lc.idiv(a, b) + "," + lc.imod(a, b) + "," + lc.fmtNum(lc.fdiv(a, b)) + "," + lc.fmtNum(p + q) + "," + lc.fmtNum(p - q) + "," + lc.fmtNum(p * q) + "," + lc.fmtNum(lc.fdiv(p, q)));
    const r2 = 试算(() => lc.dtext(lc.dadd(a, b)) + "," + lc.dtext(lc.dsub(a, b)) + "," + lc.dtext(lc.dmul(a, b)) + "," + lc.dtext(lc.didiv(a, b)) + "," + lc.dtext(lc.dimod(a, b)) + "," + lc.dtext(lc.ddiv(a, b)) + "," + lc.dtext(lc.dadd(p, q)) + "," + lc.dtext(lc.dsub(p, q)) + "," + lc.dtext(lc.dmul(p, q)) + "," + lc.dtext(lc.ddiv(p, q)));
    if (r1 === "除以 0") 错 = lc.iadd(错, 1);
    if (r1 !== r2) 不同 = lc.iadd(不同, 1);
    h1 = 搅(h1, r1); h2 = 搅(h2, r2);
  }
  lc.log("校验和（原生类型的路）" + h1);
  lc.log("校验和（任意的路）" + h2);
  lc.log("除以 0 的次数 " + 错 + "，两条路不同的次数 " + 不同);
});
