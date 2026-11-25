const lc = require("../_prelude/lc.js");
class 栈 {
  constructor() { this.项 = []; }
  压(x) { this.项.push(x); }
  弹() {
    if (this.项.length === 0) return null;
    const x = lc.at(this.项, lc.isub(this.项.length, 1));
    this.项.pop();
    return x;
  }
  大小() { return this.项.length; }
}
class 状态 {
  constructor(初) { this.听 = []; this.值 = 初; }
  读() { return this.值; }
  订阅(f) { this.听.push(f); }
  写(新值) {
    let f;
    const 旧 = this.值;
    this.值 = 新值;
    for (f of this.听) f(旧, 新值);
  }
}
lc.run(() => {
  const s = new 栈();
  s.压(1); s.压(2); s.压(3);
  lc.log("弹 " + (s.弹() ?? -1) + " 剩 " + s.大小());
  const 名 = new 栈();
  名.压("a");
  lc.log("弹 " + (名.弹() ?? "?") + " 再弹 " + (名.弹() ?? "空了"));
  const 计数 = new 状态(0);
  const 记 = [];
  计数.订阅((旧, 新值) => { 记.push(旧 + "→" + 新值); });
  计数.写(lc.iadd(计数.读(), 1));
  计数.写(lc.imul(计数.读(), 10));
  lc.log(记.join(" "));
  const 标题 = new 状态("你好");
  标题.订阅((旧, 新值) => { lc.log("标题变了：" + 新值); });
  标题.写("再见");
});
