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

// ———— 模块 探针要等的处理 ————
async function lcMain_探针要等的处理() {
  let v_总 = null, v_记 = null;
  v_总 = new M总线_事件总线();
  v_记 = [];
  lcx.send(v_总, "设出错时", lc.fn("", 2, 2, (v_消息, v_事件名) => {
    lc.listPush(v_记, lc.join("出错：", v_消息));
    return null;
  }));
  lcx.send(v_总, "订阅", "慢", lc.fn("", 1, 1, async (v_数据) => {
    lc.listPush(v_记, "开始");
    (await M反应_等更新());
    lc.listPush(v_记, "等完了");
    return null;
  }));
  lcx.send(v_总, "发出", "慢");
  lc.log(lc.join("发出刚回来：", v_记));
  (await M反应_等更新());
  lc.log(lc.join("又等了一拍：", v_记));
  return null;
}

(async () => {
  await lcMain_探针要等的处理();
  host.ready();
})().catch(lcx.die);
