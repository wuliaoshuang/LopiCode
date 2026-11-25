const lc = require("../_prelude/lc.js");
function 做计数器(步) {
  let n = 0;
  return () => { n = lc.iadd(n, 步); return n; };
}
function 组合(f, g) {
  return (x) => g(f(x));
}
function 做两次(f, x) {
  return f(f(x));
}
lc.run(() => {
  let f;
  const c1 = 做计数器(1);
  const c2 = 做计数器(10);
  c1();
  c1();
  lc.log("c1=" + c1() + " c2=" + c2());
  const 加一 = (n) => lc.iadd(n, 1);
  const 转文 = (n) => "<" + n + ">";
  const 管 = 组合(加一, 转文);
  lc.log(管(41));
  lc.log("两次 " + 做两次(加一, 5));
  const 动作 = [加一, (n) => lc.imul(n, 2)];
  let x = 3;
  for (f of 动作) x = f(x);
  lc.log("x=" + x);
});
