// 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。
"use strict";
const lc = require("./lc_lang.js");
const lcx = require("./lcx_ext.js");
const host = require("./host_node.js");

// ———— 模块 反应 ————
class M反应_状态 extends lcx.Obj {
  constructor(v_初值) {
    super();
    this.f_号 = 0.0;
    this.f_值 = null;
    this.f_订阅 = lc.dictOf();
    this.f_号 = M反应_新号();
    this.f_值 = v_初值;
    this.f_订阅 = lc.dictOf();
  }
  m_读() {
    M反应_记依赖(this);
    return this.f_值;
  }
  m_偷看() {
    return this.f_值;
  }
  m_写(v_新值) {
    if ((!lc.isNull(M反应_正在跑的) && (M反应_正在跑的 instanceof M反应_派生))) {
      throw lcx.toErr("派生值的算法里不能改状态");
    }
    if (lcx.isSame(v_新值, this.f_值)) {
      return null;
    }
    this.f_值 = v_新值;
    M反应_通知(this);
    return null;
  }
}
lcx.named(M反应_状态, "状态");
lcx.sig(M反应_状态.prototype.m_读, 0, 0);
lcx.sig(M反应_状态.prototype.m_偷看, 0, 0);
lcx.sig(M反应_状态.prototype.m_写, 1, 1);
class M反应_派生 extends lcx.Obj {
  constructor(v_算法) {
    super();
    this.f_号 = 0.0;
    this.f_算法 = null;
    this.f_值 = null;
    this.f_旧了 = true;
    this.f_正在算 = false;
    this.f_订阅 = lc.dictOf();
    this.f_依赖 = lc.dictOf();
    this.f_算了几次 = 0.0;
    this.f_号 = M反应_新号();
    this.f_算法 = v_算法;
    this.f_订阅 = lc.dictOf();
    this.f_依赖 = lc.dictOf();
  }
  m_标旧() {
    if (!lc.truthy(this.f_旧了)) {
      this.f_旧了 = true;
      M反应_通知(this);
    }
    return null;
  }
  m_读() {
    let v_之前 = null;
    M反应_记依赖(this);
    if (lc.truthy(this.f_旧了)) {
      if (lc.truthy(this.f_正在算)) {
        throw lcx.toErr("派生值绕回了自己");
      }
      this.f_正在算 = true;
      M反应_断开(this);
      v_之前 = M反应_正在跑的;
      M反应_正在跑的 = this;
      try {
        this.f_值 = lcx.nowait(lc.call(this.f_算法));
        this.f_算了几次 = lc.add(this.f_算了几次, 1.0);
      } finally {
        M反应_正在跑的 = v_之前;
        this.f_正在算 = false;
      }
      this.f_旧了 = false;
    }
    return this.f_值;
  }
}
lcx.named(M反应_派生, "派生");
lcx.sig(M反应_派生.prototype.m_标旧, 0, 0);
lcx.sig(M反应_派生.prototype.m_读, 0, 0);
class M反应_跟随 extends lcx.Obj {
  constructor(v_做法) {
    super();
    this.f_号 = 0.0;
    this.f_做法 = null;
    this.f_依赖 = lc.dictOf();
    this.f_停了 = false;
    this.f_排着 = false;
    this.f_收尾 = null;
    this.f_号 = M反应_新号();
    this.f_做法 = v_做法;
    this.f_依赖 = lc.dictOf();
  }
  m_标旧() {
    if ((lc.truthy(this.f_停了) || lc.truthy(this.f_排着))) {
      return null;
    }
    this.f_排着 = true;
    lc.listPush(M反应_等着跑的, this);
    M反应_排一下();
    return null;
  }
  m_做收尾() {
    let v_收 = null;
    if (!lc.isNull(this.f_收尾)) {
      v_收 = this.f_收尾;
      this.f_收尾 = null;
      lcx.nowait(lc.call(v_收));
    }
    return null;
  }
  m_跑() {
    let v_之前 = null, v_结果 = null;
    if (lc.truthy(this.f_停了)) {
      return null;
    }
    lcx.send(this, "做收尾");
    M反应_断开(this);
    v_之前 = M反应_正在跑的;
    M反应_正在跑的 = this;
    try {
      v_结果 = lcx.nowait(lc.call(this.f_做法));
      if (lc.isType(v_结果, "function")) {
        this.f_收尾 = v_结果;
      }
    } finally {
      M反应_正在跑的 = v_之前;
    }
    return null;
  }
  m_停() {
    if (lc.truthy(this.f_停了)) {
      return null;
    }
    this.f_停了 = true;
    lcx.send(this, "做收尾");
    M反应_断开(this);
    return null;
  }
}
lcx.named(M反应_跟随, "跟随");
lcx.sig(M反应_跟随.prototype.m_标旧, 0, 0);
lcx.sig(M反应_跟随.prototype.m_做收尾, 0, 0);
lcx.sig(M反应_跟随.prototype.m_跑, 0, 0);
lcx.sig(M反应_跟随.prototype.m_停, 0, 0);
class M反应_归属 extends lcx.Obj {
  constructor() {
    super();
    this.f_要收的 = [];
    this.f_收了 = false;
    this.f_要收的 = [];
  }
  m_记(v_收法) {
    lc.listPush(this.f_要收的, v_收法);
    return null;
  }
  m_里面做(v_做) {
    let v_之前 = null;
    v_之前 = M反应_当前归属;
    M反应_当前归属 = this;
    try {
      return lcx.nowait(lc.call(v_做));
    } finally {
      M反应_当前归属 = v_之前;
    }
    return null;
  }
  m_收() {
    let v_表 = null, v_收法 = null;
    if (lc.truthy(this.f_收了)) {
      return null;
    }
    this.f_收了 = true;
    v_表 = lc.listReverse(this.f_要收的);
    this.f_要收的 = [];
    for (let lcxs1 = lc.items(v_表), lci2 = 0; lci2 < lcxs1.length; lci2++) {
      v_收法 = lcxs1[lci2];
      lcx.nowait(lc.call(v_收法));
    }
    return null;
  }
}
lcx.named(M反应_归属, "归属");
lcx.sig(M反应_归属.prototype.m_记, 1, 1);
lcx.sig(M反应_归属.prototype.m_里面做, 1, 1);
lcx.sig(M反应_归属.prototype.m_收, 0, 0);
const M反应_新号 = lc.fn("新号", 0, 0, function () {
  M反应_下一个号 = lc.add(M反应_下一个号, 1.0);
  return M反应_下一个号;
});
const M反应_记依赖 = lc.fn("记依赖", 1, 1, function (v_源) {
  if (!lc.isNull(M反应_正在跑的)) {
    lc.setItem(lcx.getf(v_源, "订阅"), lcx.getf(M反应_正在跑的, "号"), M反应_正在跑的);
    lc.setItem(lcx.getf(M反应_正在跑的, "依赖"), lcx.getf(v_源, "号"), v_源);
  }
  return null;
});
const M反应_断开 = lc.fn("断开", 1, 1, function (v_谁) {
  let v_键 = null, v_源 = null;
  for (let lcd3 = lcx.getf(v_谁, "依赖"), lcks4 = lc.dictKeys(lcd3), lci5 = 0; lci5 < lcks4.length; lci5++) {
    v_键 = lcks4[lci5];
    v_源 = lc.dictGet(lcd3, v_键);
    lc.dictRemove(lcx.getf(v_源, "订阅"), lcx.getf(v_谁, "号"));
  }
  lcx.setf(v_谁, "依赖", lc.dictOf());
  return null;
});
const M反应_通知 = lc.fn("通知", 1, 1, function (v_源) {
  let v_键 = null, v_谁 = null;
  for (let lcd6 = lcx.getf(v_源, "订阅"), lcks7 = lc.dictKeys(lcd6), lci8 = 0; lci8 < lcks7.length; lci8++) {
    v_键 = lcks7[lci8];
    v_谁 = lc.dictGet(lcd6, v_键);
    lcx.send(v_谁, "标旧");
  }
  return null;
});
const M反应_报错 = lc.fn("报错", 1, 1, function (v_消息) {
  if (lc.isNull(M反应_出错时)) {
    host.logError(lc.join("跟着做的事出错：", v_消息));
  } else {
    lcx.nowait(lc.call(M反应_出错时, v_消息));
  }
  return null;
});
const M反应_排一下 = lc.fn("排一下", 0, 0, function () {
  if ((lc.truthy(M反应_排上了) || lc.gt(M反应_一起改层数, 0.0))) {
    return null;
  }
  M反应_排上了 = true;
  host.tickDefer(lc.fn("", 0, 0, () => {
    M反应_冲刷();
    return null;
  }));
  return null;
});
const M反应_冲刷 = lc.fn("冲刷", 0, 0, function () {
  let v_轮 = null, v_丢 = null, v_这批 = null, v_一个 = null, v_e = null;
  M反应_排上了 = false;
  v_轮 = 0.0;
  while (lc.gt(lc.size(M反应_等着跑的), 0.0)) {
    v_轮 = lc.add(v_轮, 1.0);
    if (lc.gt(v_轮, 100.0)) {
      for (let lcxs9 = lc.items(M反应_等着跑的), lci10 = 0; lci10 < lcxs9.length; lci10++) {
        v_丢 = lcxs9[lci10];
        lcx.setf(v_丢, "排着", false);
      }
      M反应_等着跑的 = [];
      M反应_报错("跟着变的积木互相触发超过 100 轮");
      return null;
    }
    v_这批 = M反应_等着跑的;
    M反应_等着跑的 = [];
    for (let lcxs11 = lc.items(v_这批), lci12 = 0; lci12 < lcxs11.length; lci12++) {
      v_一个 = lcxs11[lci12];
      lcx.setf(v_一个, "排着", false);
      try {
        lcx.send(v_一个, "跑");
      } catch (lce13) {
        v_e = lcx.caught(lce13);
        M反应_报错(lcx.getf(v_e, "消息"));
      }
    }
  }
  return null;
});
const M反应_新状态 = lc.fn("新状态", 1, 1, function (v_初值) {
  return new M反应_状态(v_初值);
});
const M反应_新派生 = lc.fn("新派生", 1, 1, function (v_算法) {
  return new M反应_派生(v_算法);
});
const M反应_跟着做 = lc.fn("跟着做", 1, 1, function (v_做法) {
  let v_一个 = null, v_取消 = null;
  v_一个 = new M反应_跟随(v_做法);
  v_取消 = lc.fn("", 0, 0, () => {
    lcx.send(v_一个, "停");
    return null;
  });
  if (!lc.isNull(M反应_当前归属)) {
    lcx.send(M反应_当前归属, "记", v_取消);
  }
  lcx.send(v_一个, "跑");
  return v_取消;
});
const M反应_不记依赖地做 = lc.fn("不记依赖地做", 1, 1, function (v_做) {
  let v_之前 = null;
  v_之前 = M反应_正在跑的;
  M反应_正在跑的 = null;
  try {
    return lcx.nowait(lc.call(v_做));
  } finally {
    M反应_正在跑的 = v_之前;
  }
  return null;
});
const M反应_当变了 = lc.fn("当变了", 2, 3, function (v_取值, v_回调, v_马上 = false) {
  let v_旧 = null, v_第一次 = null;
  v_旧 = null;
  v_第一次 = true;
  return M反应_跟着做(lc.fn("", 0, 0, () => {
    let v_新 = null, v_原来 = null;
    v_新 = lcx.nowait(lc.call(v_取值));
    if (lc.truthy(v_第一次)) {
      v_第一次 = false;
      v_旧 = v_新;
      if (lc.truthy(v_马上)) {
        M反应_不记依赖地做(lc.fn("", 0, 0, () => {
          lcx.nowait(lc.call(v_回调, v_新, null));
          return null;
        }));
      }
      return null;
    }
    if (!lcx.isSame(v_新, v_旧)) {
      v_原来 = v_旧;
      v_旧 = v_新;
      M反应_不记依赖地做(lc.fn("", 0, 0, () => {
        lcx.nowait(lc.call(v_回调, v_新, v_原来));
        return null;
      }));
    }
    return null;
  }));
});
const M反应_一起改 = lc.fn("一起改", 1, 1, async function (v_做) {
  M反应_一起改层数 = lc.add(M反应_一起改层数, 1.0);
  try {
    (await lc.call(v_做));
  } finally {
    M反应_一起改层数 = lc.sub(M反应_一起改层数, 1.0);
    if ((lc.eq(M反应_一起改层数, 0.0) && lc.gt(lc.size(M反应_等着跑的), 0.0))) {
      M反应_排一下();
    }
  }
  return null;
});
const M反应_收尾时 = lc.fn("收尾时", 1, 1, function (v_收法) {
  if (!lc.isNull(M反应_当前归属)) {
    lcx.send(M反应_当前归属, "记", v_收法);
  }
  return null;
});
const M反应_等更新 = lc.fn("等更新", 0, 0, async function () {
  (await host.tickWait());
  return null;
});
const M反应_设出错时 = lc.fn("设出错时", 1, 1, function (v_回调) {
  M反应_出错时 = v_回调;
  return null;
});
let M反应_正在跑的 = null;
let M反应_当前归属 = null;
let M反应_下一个号 = 100000.0;
let M反应_等着跑的 = [];
let M反应_排上了 = false;
let M反应_一起改层数 = 0.0;
let M反应_出错时 = null;

// ———— 模块 总线 ————
class M总线_事件总线 extends lcx.Obj {
  constructor() {
    super();
    this.f_听的 = lc.dictOf();
    this.f_下一个号 = 1.0;
    this.f_出错时 = null;
    this.f_听的 = lc.dictOf();
  }
  m_登记(v_事件名, v_回调, v_一次) {
    let v_号 = null, v_自己 = null;
    v_号 = this.f_下一个号;
    this.f_下一个号 = lc.add(v_号, 1.0);
    if (!lc.dictHas(this.f_听的, v_事件名)) {
      lc.setItem(this.f_听的, v_事件名, []);
    }
    lc.listPush(lc.dictGet(this.f_听的, v_事件名), lc.dictOf("号", v_号, "回调", v_回调, "一次", v_一次, "停了", false));
    v_自己 = this;
    return lc.fn("", 0, 0, () => {
      return lcx.send(v_自己, "退订", v_事件名, v_号);
    });
  }
  m_订阅(v_事件名, v_回调) {
    return lcx.send(this, "登记", v_事件名, v_回调, false);
  }
  m_只听一次(v_事件名, v_回调) {
    return lcx.send(this, "登记", v_事件名, v_回调, true);
  }
  m_退订(v_事件名, v_号) {
    let v_表 = null, v_条 = null, v_i = null;
    v_表 = lcx.orElse(lc.dictGet(this.f_听的, v_事件名), []);
    for (let lcxs14 = lc.items(v_表), lci15 = 0; lci15 < lcxs14.length; lci15++) {
      v_条 = lcxs14[lci15];
      v_i = lci15;
      if (lc.eq(lc.dictGet(v_条, "号"), v_号)) {
        lc.setItem(v_条, "停了", true);
        lc.listRemove(v_表, v_i);
        return true;
      }
    }
    return false;
  }
  m_有几个在听(v_事件名) {
    return lc.size(lcx.orElse(lc.dictGet(this.f_听的, v_事件名), []));
  }
  m_发出(v_事件名, v_数据 = null) {
    let v_表 = null, v_这次 = null, v_叫了 = null, v_条 = null, v_e = null;
    v_表 = lc.dictGet(this.f_听的, v_事件名);
    if (lc.isNull(v_表)) {
      return 0.0;
    }
    v_这次 = lc.listSlice(v_表, 0.0, lc.size(v_表));
    v_叫了 = 0.0;
    for (let lcxs16 = lc.items(v_这次), lci17 = 0; lci17 < lcxs16.length; lci17++) {
      v_条 = lcxs16[lci17];
      if (lc.truthy(lc.dictGet(v_条, "停了"))) {
        continue;
      }
      if (lc.truthy(lc.dictGet(v_条, "一次"))) {
        lcx.send(this, "退订", v_事件名, lc.dictGet(v_条, "号"));
      }
      v_叫了 = lc.add(v_叫了, 1.0);
      try {
        lcx.nowait(lc.call(lc.dictGet(v_条, "回调"), v_数据));
      } catch (lce18) {
        v_e = lcx.caught(lce18);
        if (lc.isNull(this.f_出错时)) {
          host.logError(lc.join("事件“", v_事件名, "”的处理出错：", lcx.getf(v_e, "消息")));
        } else {
          lcx.nowait(lc.call(this.f_出错时, lcx.getf(v_e, "消息"), v_事件名));
        }
      }
    }
    return v_叫了;
  }
  m_设出错时(v_回调) {
    this.f_出错时 = v_回调;
    return null;
  }
}
lcx.named(M总线_事件总线, "事件总线");
lcx.sig(M总线_事件总线.prototype.m_登记, 3, 3);
lcx.sig(M总线_事件总线.prototype.m_订阅, 2, 2);
lcx.sig(M总线_事件总线.prototype.m_只听一次, 2, 2);
lcx.sig(M总线_事件总线.prototype.m_退订, 2, 2);
lcx.sig(M总线_事件总线.prototype.m_有几个在听, 1, 1);
lcx.sig(M总线_事件总线.prototype.m_发出, 1, 2);
lcx.sig(M总线_事件总线.prototype.m_设出错时, 1, 1);

// ———— 模块 检查 ————
const M检查_报 = lc.fn("报", 3, 3, function (v_号, v_名字, v_值) {
  lc.log(lc.join("[", v_号, "] ", v_名字, "：", v_值));
  return null;
});
let M检查_积木计数 = M反应_新状态(0.0);
let M检查_积木记录 = [];
let M检查_全局总线 = new M总线_事件总线();
let M检查_积木收到的 = [];
async function lcMain_检查() {
  let v_错们 = null, v_a = null, v_b = null, v_两倍 = null, v_文字 = null, v_写了几次 = null, v_停2 = null, v_甲 = null, v_乙 = null, v_丙 = null, v_见过的 = null, v_丁 = null, v_开关 = null, v_内容 = null, v_跑4 = null, v_看到 = null, v_停4 = null, v_c = null, v_跑5 = null, v_停5 = null, v_表 = null, v_跑5c = null, v_停5c = null, v_同一个 = null, v_d = null, v_记6 = null, v_停6 = null, v_e7 = null, v_跑7 = null, v_停7 = null, v_绕甲 = null, v_绕乙 = null, v_结果8 = null, v_e = null, v_f = null, v_记9 = null, v_停9 = null, v_记10 = null, v_停10 = null, v_g = null, v_h = null, v_记12 = null, v_停12 = null, v_坏派生 = null, v_结果13 = null, v_主 = null, v_i = null, v_记14 = null, v_j = null, v_跑15 = null, v_停15 = null, v_跑15b = null, v_停15b = null, v_次 = null, v_k = null, v_懒 = null, v_m = null, v_平方 = null, v_记17 = null, v_停17 = null, v_n = null, v_记18 = null, v_停18a = null, v_停18b = null, v_总 = null, v_记20 = null, v_退甲 = null, v_退乙 = null, v_个数 = null, v_第一次退 = null, v_记22 = null, v_第二次 = null, v_记23 = null, v_退后面 = null, v_叫23 = null, v_记24 = null, v_记25 = null, v_错25 = null, v_叫25 = null, v_另一条 = null, v_记27 = null, v_计 = null, v_跑28 = null, v_停28 = null, v_记29 = null;
  M反应_当变了(lc.fn("", 0, 0, () => {
    return lcx.send(M检查_积木计数, "读");
  }), lc.fn("", 2, 2, (v_新值, v_旧值) => {
    lc.listPush(M检查_积木记录, lc.join(v_旧值, "→", v_新值));
    return null;
  }));
  lcx.send(M检查_全局总线, "订阅", "积木事件", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(M检查_积木收到的, v_数据);
    return null;
  }));
  v_错们 = [];
  M反应_设出错时(lc.fn("", 1, 1, (v_消息) => {
    lc.listPush(v_错们, v_消息);
    return null;
  }));
  v_a = M反应_新状态(0.0);
  lcx.send(v_a, "写", lc.add(lcx.send(v_a, "读"), 1.0));
  lcx.send(v_a, "写", lc.add(lcx.send(v_a, "读"), 1.0));
  M检查_报("1", "先写后读，连加两次", lcx.send(v_a, "读"));
  v_b = M反应_新状态(1.0);
  v_两倍 = M反应_新派生(lc.fn("", 0, 0, () => {
    return lc.mul(lcx.send(v_b, "读"), 2.0);
  }));
  v_文字 = "";
  v_写了几次 = 0.0;
  v_停2 = M反应_跟着做(lc.fn("", 0, 0, () => {
    v_文字 = lc.join("值是", lcx.send(v_两倍, "读"));
    v_写了几次 = lc.add(v_写了几次, 1.0);
    return null;
  }));
  M检查_报("2.0", "跟着做：登记时马上做一次", lc.join(v_文字, "，", v_写了几次));
  lcx.send(v_b, "写", 5.0);
  M检查_报("2a", "改完马上读派生值，是新的", lcx.send(v_两倍, "读"));
  M检查_报("2b", "这一刻跟着做的还没跑", lc.join(v_文字, "，", v_写了几次));
  lcx.send(v_b, "写", 6.0);
  lcx.send(v_b, "写", 7.0);
  (await M反应_等更新());
  M检查_报("2c", "一段里改三次，只多跑一次", lc.join(v_文字, "，", v_写了几次));
  v_甲 = M反应_新状态(1.0);
  v_乙 = M反应_新派生(lc.fn("", 0, 0, () => {
    return lc.add(lcx.send(v_甲, "读"), 1.0);
  }));
  v_丙 = M反应_新派生(lc.fn("", 0, 0, () => {
    return lc.mul(lcx.send(v_甲, "读"), 10.0);
  }));
  v_见过的 = [];
  v_丁 = M反应_新派生(lc.fn("", 0, 0, () => {
    let v_v = null;
    v_v = lc.add(lcx.send(v_乙, "读"), lcx.send(v_丙, "读"));
    lc.listPush(v_见过的, v_v);
    return v_v;
  }));
  M检查_报("3a", "菱形：第一次读丁", lcx.send(v_丁, "读"));
  lcx.send(v_甲, "写", 2.0);
  M检查_报("3b", "菱形：改了甲以后读丁", lcx.send(v_丁, "读"));
  M检查_报("3c", "丁算出过的值（没有半新半旧的）", v_见过的);
  M检查_报("3d", "丁一共算了几次", lcx.getf(v_丁, "算了几次"));
  v_开关 = M反应_新状态(true);
  v_内容 = M反应_新状态("A");
  v_跑4 = 0.0;
  v_看到 = "";
  v_停4 = M反应_跟着做(lc.fn("", 0, 0, () => {
    v_跑4 = lc.add(v_跑4, 1.0);
    if (lc.truthy(lcx.send(v_开关, "读"))) {
      v_看到 = lcx.send(v_内容, "读");
    } else {
      v_看到 = "关";
    }
    return null;
  }));
  lcx.send(v_内容, "写", "B");
  (await M反应_等更新());
  lcx.send(v_开关, "写", false);
  (await M反应_等更新());
  lcx.send(v_内容, "写", "C");
  (await M反应_等更新());
  M检查_报("4", "条件里的依赖关掉以后不再触发", lc.join(v_跑4, "，", v_看到));
  v_c = M反应_新状态(1.0);
  v_跑5 = 0.0;
  v_停5 = M反应_跟着做(lc.fn("", 0, 0, () => {
    lcx.send(v_c, "读");
    v_跑5 = lc.add(v_跑5, 1.0);
    return null;
  }));
  lcx.send(v_c, "写", 1.0);
  (await M反应_等更新());
  M检查_报("5a", "设成同一个值不触发", v_跑5);
  lcx.send(v_c, "写", "1");
  (await M反应_等更新());
  M检查_报("5b", "数字 1 换成文字“1”：算变了", v_跑5);
  v_表 = M反应_新状态([1.0, 2.0]);
  v_跑5c = 0.0;
  v_停5c = M反应_跟着做(lc.fn("", 0, 0, () => {
    lcx.send(v_表, "读");
    v_跑5c = lc.add(v_跑5c, 1.0);
    return null;
  }));
  lcx.send(v_表, "写", [1.0, 2.0]);
  (await M反应_等更新());
  M检查_报("5c", "换成内容一样的另一个列表：算变了", v_跑5c);
  v_同一个 = lcx.send(v_表, "偷看");
  lc.listPush(v_同一个, 3.0);
  lcx.send(v_表, "写", v_同一个);
  (await M反应_等更新());
  M检查_报("5d", "原地改了再写回同一个列表：不算变（已知的坑）", v_跑5c);
  v_d = M反应_新状态(0.0);
  v_记6 = [];
  v_停6 = M反应_跟着做(lc.fn("", 0, 0, () => {
    let v_v = null;
    v_v = lcx.send(v_d, "读");
    lc.listPush(v_记6, lc.join("做", v_v));
    return lc.fn("", 0, 0, () => {
      lc.listPush(v_记6, lc.join("收", v_v));
      return null;
    });
  }));
  lcx.send(v_d, "写", 1.0);
  (await M反应_等更新());
  (await lc.call(v_停6));
  lcx.send(v_d, "写", 2.0);
  (await M反应_等更新());
  M检查_报("6", "收尾函数：重做前叫、停掉时叫，停掉后不再做", v_记6);
  v_e7 = M反应_新状态(0.0);
  v_跑7 = 0.0;
  v_停7 = M反应_跟着做(lc.fn("", 0, 0, () => {
    v_跑7 = lc.add(v_跑7, 1.0);
    lcx.send(v_e7, "写", lc.add(lcx.send(v_e7, "读"), 1.0));
    return null;
  }));
  (await M反应_等更新());
  M检查_报("7a", "跟着做的事改它自己看的状态：报错停下", v_错们);
  M检查_报("7b", "它一共跑了几次", v_跑7);
  (await lc.call(v_停7));
  v_绕甲 = null;
  v_绕乙 = null;
  v_绕甲 = M反应_新派生(lc.fn("", 0, 0, () => {
    return lc.add(lcx.send(v_绕乙, "读"), 1.0);
  }));
  v_绕乙 = M反应_新派生(lc.fn("", 0, 0, () => {
    return lc.add(lcx.send(v_绕甲, "读"), 1.0);
  }));
  v_结果8 = "没出错";
  try {
    lcx.send(v_绕甲, "读");
  } catch (lce19) {
    v_e = lcx.caught(lce19);
    v_结果8 = lcx.getf(v_e, "消息");
  }
  M检查_报("8", "两个派生值互相绕", v_结果8);
  v_f = M反应_新状态(1.0);
  v_记9 = [];
  v_停9 = M反应_当变了(lc.fn("", 0, 0, () => {
    return lcx.send(v_f, "读");
  }), lc.fn("", 2, 2, (v_新, v_旧) => {
    lc.listPush(v_记9, lc.join(v_旧, "→", v_新));
    return null;
  }));
  M检查_报("9a", "当…变了：登记时不先叫", v_记9);
  lcx.send(v_f, "写", 2.0);
  lcx.send(v_f, "写", 3.0);
  (await M反应_等更新());
  M检查_报("9b", "一轮里变多次只叫一次，拿到最后的值和原来的值", v_记9);
  lcx.send(v_f, "写", 9.0);
  lcx.send(v_f, "写", 3.0);
  (await M反应_等更新());
  M检查_报("9c", "变了又变回来：不叫", v_记9);
  v_记10 = [];
  v_停10 = M反应_当变了(lc.fn("", 0, 0, () => {
    return lcx.send(v_f, "读");
  }), lc.fn("", 2, 2, (v_新, v_旧) => {
    lc.listPush(v_记10, lc.join(v_旧, "→", v_新));
    return null;
  }), true);
  M检查_报("10", "“马上先做一次”（旧值是空）", v_记10);
  (await lc.call(v_停9));
  (await lc.call(v_停10));
  lcx.send(v_f, "写", 4.0);
  (await M反应_等更新());
  M检查_报("11", "取消以后不再叫", lc.join(lc.size(v_记9), "，", lc.size(v_记10)));
  v_g = M反应_新状态(0.0);
  v_h = M反应_新状态(0.0);
  v_记12 = [];
  v_停12 = M反应_跟着做(lc.fn("", 0, 0, () => {
    lc.listPush(v_记12, lc.join(lcx.send(v_g, "读"), "+", lcx.send(v_h, "读")));
    return null;
  }));
  (await M反应_一起改(lc.fn("", 0, 0, async () => {
    lcx.send(v_g, "写", 1.0);
    (await M反应_等更新());
    lc.listPush(v_记12, "中间");
    lcx.send(v_h, "写", 1.0);
    return null;
  })));
  (await M反应_等更新());
  M检查_报("12a", "一起改：中间等过，跟着做的也只跑一次", v_记12);
  lcx.send(v_g, "写", 2.0);
  (await M反应_等更新());
  lcx.send(v_h, "写", 2.0);
  (await M反应_等更新());
  M检查_报("12b", "不用一起改：等一次跑一次", v_记12);
  v_坏派生 = M反应_新派生(lc.fn("", 0, 0, () => {
    lcx.send(v_g, "写", 99.0);
    return 1.0;
  }));
  v_结果13 = "没出错";
  try {
    lcx.send(v_坏派生, "读");
  } catch (lce20) {
    v_e = lcx.caught(lce20);
    v_结果13 = lcx.getf(v_e, "消息");
  }
  M检查_报("13a", "派生值的算法里改状态", v_结果13);
  M检查_报("13b", "那个状态没被改", lcx.send(v_g, "偷看"));
  v_主 = new M反应_归属();
  v_i = M反应_新状态(0.0);
  v_记14 = [];
  lcx.send(v_主, "里面做", lc.fn("", 0, 0, () => {
    M反应_跟着做(lc.fn("", 0, 0, () => {
      lc.listPush(v_记14, lc.join("甲", lcx.send(v_i, "读")));
      return lc.fn("", 0, 0, () => {
        lc.listPush(v_记14, "甲收");
        return null;
      });
    }));
    M反应_跟着做(lc.fn("", 0, 0, () => {
      lc.listPush(v_记14, lc.join("乙", lcx.send(v_i, "读")));
      return lc.fn("", 0, 0, () => {
        lc.listPush(v_记14, "乙收");
        return null;
      });
    }));
    return null;
  }));
  lcx.send(v_i, "写", 1.0);
  (await M反应_等更新());
  lcx.send(v_主, "收");
  lcx.send(v_i, "写", 2.0);
  (await M反应_等更新());
  M检查_报("14", "归属收了：里面的都停、收尾都叫（后建的先收）", v_记14);
  v_j = M反应_新状态(0.0);
  v_跑15 = 0.0;
  v_停15 = M反应_跟着做(lc.fn("", 0, 0, () => {
    lcx.send(v_j, "偷看");
    v_跑15 = lc.add(v_跑15, 1.0);
    return null;
  }));
  v_跑15b = 0.0;
  v_停15b = M反应_跟着做(lc.fn("", 0, 0, () => {
    M反应_不记依赖地做(lc.fn("", 0, 0, () => {
      return lcx.send(v_j, "读");
    }));
    v_跑15b = lc.add(v_跑15b, 1.0);
    return null;
  }));
  lcx.send(v_j, "写", 1.0);
  (await M反应_等更新());
  M检查_报("15", "偷看、不记依赖地做：不算依赖", lc.join(v_跑15, "，", v_跑15b));
  v_次 = 0.0;
  v_k = M反应_新状态(1.0);
  v_懒 = M反应_新派生(lc.fn("", 0, 0, () => {
    v_次 = lc.add(v_次, 1.0);
    return lcx.send(v_k, "读");
  }));
  M检查_报("16a", "派生值没人读就不算", v_次);
  lcx.send(v_懒, "读");
  lcx.send(v_懒, "读");
  M检查_报("16b", "读两次只算一次", v_次);
  lcx.send(v_k, "写", 2.0);
  M检查_报("16c", "依赖变了也不马上算", v_次);
  M检查_报("16d", "再读才算", lc.join(lcx.send(v_懒, "读"), "，", v_次));
  v_m = M反应_新状态(1.0);
  v_平方 = M反应_新派生(lc.fn("", 0, 0, () => {
    return lc.mul(lcx.send(v_m, "读"), lcx.send(v_m, "读"));
  }));
  v_记17 = [];
  v_停17 = M反应_跟着做(lc.fn("", 0, 0, () => {
    lc.listPush(v_记17, lcx.send(v_平方, "读"));
    return null;
  }));
  lcx.send(v_m, "写", 2.0);
  (await M反应_等更新());
  lcx.send(v_m, "写", lc.sub(0, 2.0));
  (await M反应_等更新());
  M检查_报("17", "跟着做的事读派生值（已知的粗糙处：派生值没变也重做一次）", v_记17);
  v_n = M反应_新状态(0.0);
  v_记18 = [];
  v_停18a = M反应_跟着做(lc.fn("", 0, 0, () => {
    if (lc.eq(lcx.send(v_n, "读"), 1.0)) {
      throw lcx.toErr("故意的");
    }
    return null;
  }));
  v_停18b = M反应_跟着做(lc.fn("", 0, 0, () => {
    lc.listPush(v_记18, lc.join("好", lcx.send(v_n, "读")));
    return null;
  }));
  lcx.send(v_n, "写", 1.0);
  (await M反应_等更新());
  M检查_报("18", "一件跟着做的事出错，不影响别的", lc.join(v_记18, "｜", lc.listGet(v_错们, lc.sub(lc.size(v_错们), 1.0))));
  lcx.send(M检查_积木计数, "写", 5.0);
  (await M反应_一起改(lc.fn("", 0, 0, () => {
    lcx.send(M检查_积木计数, "写", 6.0);
    lcx.send(M检查_积木计数, "写", 7.0);
    return null;
  })));
  (await M反应_等更新());
  M检查_报("19a", "用积木外观写的“当…变了”", M检查_积木记录);
  M检查_报("19b", "用积木外观读状态", lcx.send(M检查_积木计数, "读"));
  v_总 = new M总线_事件总线();
  v_记20 = [];
  v_退甲 = lcx.send(v_总, "订阅", "招呼", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记20, lc.join("甲:", v_数据));
    return null;
  }));
  v_退乙 = lcx.send(v_总, "订阅", "招呼", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记20, lc.join("乙:", v_数据));
    return null;
  }));
  v_个数 = lcx.send(v_总, "发出", "招呼", "你好");
  M检查_报("20", "订阅和发出：按订阅的先后叫", lc.join(v_记20, "，叫到 ", v_个数, " 个"));
  v_第一次退 = (await lc.call(v_退甲));
  lcx.send(v_总, "发出", "招呼", "再见");
  M检查_报("21", "退订以后不叫；再退一次也没事", lc.join(v_记20, "，", v_第一次退, "，", (await lc.call(v_退甲))));
  v_记22 = [];
  lcx.send(v_总, "只听一次", "铃", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记22, v_数据);
    return null;
  }));
  lcx.send(v_总, "发出", "铃", 1.0);
  v_第二次 = lcx.send(v_总, "发出", "铃", 2.0);
  M检查_报("22", "只听一次", lc.join(v_记22, "，第二次叫到 ", v_第二次, "，还在听的 ", lcx.send(v_总, "有几个在听", "铃")));
  v_记23 = [];
  v_退后面 = null;
  lcx.send(v_总, "订阅", "改", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记23, "一");
    lcx.nowait(lc.call(v_退后面));
    return null;
  }));
  v_退后面 = lcx.send(v_总, "订阅", "改", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记23, "二");
    return null;
  }));
  lcx.send(v_总, "订阅", "改", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记23, "三");
    return null;
  }));
  v_叫23 = lcx.send(v_总, "发出", "改");
  M检查_报("23", "发出过程中把排在后面的退订了：它不被叫", lc.join(v_记23, "，叫到 ", v_叫23));
  v_记24 = [];
  lcx.send(v_总, "订阅", "加", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记24, "老");
    lcx.send(v_总, "订阅", "加", lc.fn("", 1, 1, (v_数据2) => {
      lc.listPush(v_记24, "新");
      return null;
    }));
    return null;
  }));
  lcx.send(v_总, "发出", "加");
  lcx.send(v_总, "发出", "加");
  M检查_报("24", "发出过程中新订阅的：这一次不叫，下一次才叫", v_记24);
  v_记25 = [];
  v_错25 = [];
  lcx.send(v_总, "设出错时", lc.fn("", 2, 2, (v_消息, v_事件名) => {
    lc.listPush(v_错25, lc.join(v_事件名, ":", v_消息));
    return null;
  }));
  lcx.send(v_总, "订阅", "炸", lc.fn("", 1, 1, (v_数据) => {
    throw lcx.toErr("坏了");
  }));
  lcx.send(v_总, "订阅", "炸", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记25, "还是叫到了");
    return null;
  }));
  lcx.send(v_总, "订阅", "炸", lc.fn("", 0, 0, () => {
    lc.listPush(v_记25, "不该到这里");
    return null;
  }));
  v_叫25 = lcx.send(v_总, "发出", "炸", 0.0);
  M检查_报("25", "一个处理出错（或者参数个数不对）不影响别的", lc.join(v_记25, "｜", v_错25, "｜", v_叫25));
  M检查_报("26", "没人听的事件", lcx.send(v_总, "发出", "没人听"));
  v_另一条 = new M总线_事件总线();
  v_记27 = [];
  lcx.send(v_另一条, "订阅", "招呼", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记27, v_数据);
    return null;
  }));
  lcx.send(v_总, "发出", "招呼", "只给第一条");
  M检查_报("27", "两条总线互不相干", lc.join(lc.size(v_记27), "，", lcx.send(v_另一条, "发出", "招呼", "给第二条"), "，", v_记27));
  v_计 = M反应_新状态(0.0);
  v_跑28 = 0.0;
  v_停28 = M反应_跟着做(lc.fn("", 0, 0, () => {
    lcx.send(v_计, "读");
    v_跑28 = lc.add(v_跑28, 1.0);
    return null;
  }));
  lcx.send(v_总, "订阅", "加一", lc.fn("", 1, 1, (v_数据) => {
    lcx.send(v_计, "写", lc.add(lcx.send(v_计, "偷看"), v_数据));
    return null;
  }));
  lcx.send(v_总, "发出", "加一", 1.0);
  lcx.send(v_总, "发出", "加一", 1.0);
  lcx.send(v_总, "发出", "加一", 1.0);
  (await M反应_等更新());
  M检查_报("28", "事件处理里改状态：三次改动，跟着做的只多跑一次", lc.join(lcx.send(v_计, "偷看"), "，", v_跑28));
  v_记29 = [];
  lcx.send(v_总, "订阅", "外", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记29, "外1");
    lcx.send(v_总, "发出", "内");
    lc.listPush(v_记29, "外1完");
    return null;
  }));
  lcx.send(v_总, "订阅", "外", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记29, "外2");
    return null;
  }));
  lcx.send(v_总, "订阅", "内", lc.fn("", 1, 1, (v_数据) => {
    lc.listPush(v_记29, "内");
    return null;
  }));
  lcx.send(v_总, "发出", "外");
  M检查_报("29", "处理里再发出：里面的先做完", v_记29);
  lcx.send(M检查_全局总线, "发出", "积木事件", "来了");
  lcx.send(M检查_全局总线, "发出", "积木事件", null);
  M检查_报("30", "用积木外观写的订阅和发出", M检查_积木收到的);
  return null;
}

(async () => {
  await lcMain_检查();
  host.ready();
})().catch(lcx.die);
