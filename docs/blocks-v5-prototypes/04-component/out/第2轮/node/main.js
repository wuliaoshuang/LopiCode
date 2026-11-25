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

// ———— 模块 画面 ————
class M画面_片段 extends lcx.Obj {
  constructor(v_放法) {
    super();
    this.f_放法 = null;
    this.f_放法 = v_放法;
  }
  m_放上(v_父, v_前面的) {
    lcx.nowait(lc.call(this.f_放法, v_父, v_前面的));
    return null;
  }
}
lcx.named(M画面_片段, "片段");
lcx.sig(M画面_片段.prototype.m_放上, 2, 2);
const M画面_绑 = lc.fn("绑", 3, 3, function (v_元, v_名, v_值) {
  let v_上次 = null, v_写过 = null;
  if (lc.isType(v_值, "function")) {
    v_上次 = null;
    v_写过 = false;
    M反应_跟着做(lc.fn("", 0, 0, () => {
      let v_新 = null;
      v_新 = lcx.nowait(lc.call(v_值));
      if ((!lc.truthy(v_写过) || !lcx.isSame(v_新, v_上次))) {
        v_写过 = true;
        v_上次 = v_新;
        host.uiSet(v_元, v_名, v_新);
      }
      return null;
    }));
  } else {
    host.uiSet(v_元, v_名, v_值);
  }
  return null;
});
const M画面_听 = lc.fn("听", 3, 3, function (v_元, v_事件名, v_处理) {
  M反应_收尾时(host.uiOn(v_元, v_事件名, v_处理));
  return null;
});
const M画面_页面根 = lc.fn("页面根", 0, 0, function () {
  return host.uiRoot();
});
const M画面_放进 = lc.fn("放进", 3, 3, function (v_父, v_孩, v_前面的) {
  if (lc.isNull(v_孩)) {
    return null;
  } else if ((v_孩 instanceof M画面_片段)) {
    lcx.send(v_孩, "放上", v_父, v_前面的);
  } else {
    host.uiInsert(v_父, v_孩, v_前面的);
  }
  return null;
});
const M画面_元素 = lc.fn("元素", 1, 4, function (v_标签, v_设置 = null, v_孩子们 = null, v_事件们 = null) {
  let v_元 = null, v_名 = null, v_值 = null, v_事件名 = null, v_处理 = null, v_孩 = null;
  v_元 = host.uiCreate(v_标签);
  if (!lc.isNull(v_设置)) {
    for (let lcd14 = v_设置, lcks15 = lc.dictKeys(lcd14), lci16 = 0; lci16 < lcks15.length; lci16++) {
      v_名 = lcks15[lci16];
      v_值 = lc.dictGet(lcd14, v_名);
      M画面_绑(v_元, v_名, v_值);
    }
  }
  if (!lc.isNull(v_事件们)) {
    for (let lcd17 = v_事件们, lcks18 = lc.dictKeys(lcd17), lci19 = 0; lci19 < lcks18.length; lci19++) {
      v_事件名 = lcks18[lci19];
      v_处理 = lc.dictGet(lcd17, v_事件名);
      M画面_听(v_元, v_事件名, v_处理);
    }
  }
  if (!lc.isNull(v_孩子们)) {
    for (let lcxs20 = lc.items(v_孩子们), lci21 = 0; lci21 < lcxs20.length; lci21++) {
      v_孩 = lcxs20[lci21];
      M画面_放进(v_元, v_孩, null);
    }
  }
  return v_元;
});
const M画面_如果有 = lc.fn("如果有", 2, 3, function (v_条件, v_画法, v_否则画法 = null) {
  return new M画面_片段(lc.fn("", 2, 2, (v_父, v_前面的) => {
    let v_锚 = null, v_定过 = null, v_现在 = null, v_属 = null, v_节点 = null;
    v_锚 = host.uiCreate("#锚");
    host.uiInsert(v_父, v_锚, v_前面的);
    v_定过 = false;
    v_现在 = false;
    v_属 = null;
    v_节点 = null;
    M反应_跟着做(lc.fn("", 0, 0, () => {
      let v_要 = null;
      v_要 = (lc.truthy(lcx.nowait(lc.call(v_条件))) ? true : false);
      if ((lc.truthy(v_定过) && lc.eq(v_要, v_现在))) {
        return null;
      }
      v_定过 = true;
      v_现在 = v_要;
      M反应_不记依赖地做(lc.fn("", 0, 0, () => {
        let v_用 = null;
        if (!lc.isNull(v_属)) {
          lcx.send(v_属, "收");
          v_属 = null;
        }
        if (!lc.isNull(v_节点)) {
          host.uiRemove(v_节点);
          v_节点 = null;
        }
        v_用 = (lc.truthy(v_要) ? v_画法 : v_否则画法);
        if (!lc.isNull(v_用)) {
          v_属 = new M反应_归属();
          v_节点 = lcx.send(v_属, "里面做", v_用);
          host.uiInsert(v_父, v_节点, v_锚);
        }
        return null;
      }));
      return null;
    }));
    M反应_收尾时(lc.fn("", 0, 0, () => {
      if (!lc.isNull(v_属)) {
        lcx.send(v_属, "收");
        v_属 = null;
      }
      return null;
    }));
    return null;
  }));
});
const M画面_造一行 = lc.fn("造一行", 3, 3, function (v_条, v_序, v_画法) {
  let v_属 = null, v_条目 = null, v_序号 = null, v_节点 = null;
  v_属 = new M反应_归属();
  v_条目 = M反应_新状态(v_条);
  v_序号 = M反应_新状态(v_序);
  v_节点 = lcx.send(v_属, "里面做", lc.fn("", 0, 0, () => {
    return lcx.nowait(lc.call(v_画法, lc.fn("", 0, 0, () => {
      return lcx.send(v_条目, "读");
    }), lc.fn("", 0, 0, () => {
      return lcx.send(v_序号, "读");
    })));
  }));
  return lc.dictOf("属", v_属, "节点", v_节点, "条目", v_条目, "序号", v_序号);
});
const M画面_每一个 = lc.fn("每一个", 3, 3, function (v_列表取值, v_标识, v_画法) {
  return new M画面_片段(lc.fn("", 2, 2, (v_父, v_前面的) => {
    let v_锚 = null, v_表 = null, v_旧序 = null;
    v_锚 = host.uiCreate("#锚");
    host.uiInsert(v_父, v_锚, v_前面的);
    v_表 = lc.dictOf();
    v_旧序 = [];
    M反应_跟着做(lc.fn("", 0, 0, () => {
      let v_列 = null;
      v_列 = lcx.nowait(lc.call(v_列表取值));
      M反应_不记依赖地做(lc.fn("", 0, 0, () => {
        let v_新序 = null, v_新表 = null, v_条 = null, v_序 = null, v_键 = null, v_老行 = null, v_留下的旧 = null, v_旧键 = null, v_走的 = null, v_留下的新 = null, v_新键 = null, v_顺序没变 = null, v_下一个 = null, v_位 = null, v_这键 = null, v_这行 = null;
        v_新序 = [];
        v_新表 = lc.dictOf();
        for (let lcxs22 = lc.items(v_列), lci23 = 0; lci23 < lcxs22.length; lci23++) {
          v_条 = lcxs22[lci23];
          v_序 = lci23;
          v_键 = lc.toText(lcx.nowait(lc.call(v_标识, v_条)));
          if (lc.dictHas(v_新表, v_键)) {
            throw lcx.toErr(lc.join("“每一个”里有两条的标识一样：", v_键));
          }
          lc.listPush(v_新序, v_键);
          if (lc.dictHas(v_表, v_键)) {
            v_老行 = lc.dictGet(v_表, v_键);
            lcx.send(lc.dictGet(v_老行, "条目"), "写", v_条);
            lcx.send(lc.dictGet(v_老行, "序号"), "写", v_序);
            lc.setItem(v_新表, v_键, v_老行);
          } else {
            lc.setItem(v_新表, v_键, M画面_造一行(v_条, v_序, v_画法));
          }
        }
        v_留下的旧 = [];
        for (let lcxs24 = lc.items(v_旧序), lci25 = 0; lci25 < lcxs24.length; lci25++) {
          v_旧键 = lcxs24[lci25];
          if (lc.dictHas(v_新表, v_旧键)) {
            lc.listPush(v_留下的旧, v_旧键);
          } else {
            v_走的 = lc.dictGet(v_表, v_旧键);
            lcx.send(lc.dictGet(v_走的, "属"), "收");
            host.uiRemove(lc.dictGet(v_走的, "节点"));
          }
        }
        v_留下的新 = [];
        for (let lcxs26 = lc.items(v_新序), lci27 = 0; lci27 < lcxs26.length; lci27++) {
          v_新键 = lcxs26[lci27];
          if (lc.dictHas(v_表, v_新键)) {
            lc.listPush(v_留下的新, v_新键);
          }
        }
        v_顺序没变 = lc.eq(v_留下的旧, v_留下的新);
        v_下一个 = v_锚;
        v_位 = lc.sub(lc.size(v_新序), 1.0);
        while (lc.ge(v_位, 0.0)) {
          v_这键 = lc.listGet(v_新序, v_位);
          v_这行 = lc.dictGet(v_新表, v_这键);
          if ((!lc.truthy(v_顺序没变) || !lc.dictHas(v_表, v_这键))) {
            host.uiInsert(v_父, lc.dictGet(v_这行, "节点"), v_下一个);
          }
          v_下一个 = lc.dictGet(v_这行, "节点");
          v_位 = lc.sub(v_位, 1.0);
        }
        v_表 = v_新表;
        v_旧序 = v_新序;
        return null;
      }));
      return null;
    }));
    M反应_收尾时(lc.fn("", 0, 0, () => {
      let v_收键 = null, v_收行 = null;
      for (let lcd28 = v_表, lcks29 = lc.dictKeys(lcd28), lci30 = 0; lci30 < lcks29.length; lci30++) {
        v_收键 = lcks29[lci30];
        v_收行 = lc.dictGet(lcd28, v_收键);
        lcx.send(lc.dictGet(v_收行, "属"), "收");
      }
      return null;
    }));
    return null;
  }));
});
const M画面_放上以后 = lc.fn("放上以后", 1, 1, function (v_做) {
  lc.listPush(M画面_放上以后要做的, v_做);
  return null;
});
const M画面_拿走之前 = lc.fn("拿走之前", 1, 1, function (v_做) {
  M反应_收尾时(v_做);
  return null;
});
const M画面_挂上 = lc.fn("挂上", 2, 2, function (v_父, v_画法) {
  let v_属 = null, v_外面的 = null, v_节点 = null, v_这次的 = null, v_做 = null;
  v_属 = new M反应_归属();
  v_外面的 = M画面_放上以后要做的;
  M画面_放上以后要做的 = [];
  v_节点 = lcx.send(v_属, "里面做", v_画法);
  M画面_放进(v_父, v_节点, null);
  v_这次的 = M画面_放上以后要做的;
  M画面_放上以后要做的 = v_外面的;
  for (let lcxs31 = lc.items(v_这次的), lci32 = 0; lci32 < lcxs31.length; lci32++) {
    v_做 = lcxs31[lci32];
    lcx.send(v_属, "里面做", v_做);
  }
  return lc.fn("", 0, 0, () => {
    lcx.send(v_属, "收");
    host.uiRemove(v_节点);
    return null;
  });
});
let M画面_放上以后要做的 = [];

// ———— 模块 待办 ————
const M待办_取 = lc.fn("取", 3, 3, function (v_字典, v_键, v_默认) {
  if ((!lc.isNull(v_字典) && lc.dictHas(v_字典, v_键))) {
    return lc.dictGet(v_字典, v_键);
  }
  return v_默认;
});
const M待办_发 = lc.fn("发", 2, 2, function (v_回调, v_数据) {
  if (!lc.isNull(v_回调)) {
    lcx.spawn(async () => {
      (await lc.call(v_回调, v_数据));
      return null;
    });
  }
  return null;
});
const M待办_一行 = lc.fn("一行", 5, 5, function (v_条目, v_选中的, v_画一条, v_点了, v_删了) {
  return M画面_元素("li", lc.dictOf("类名", lc.fn("", 0, 0, () => {
    let v_条 = null;
    v_条 = lcx.nowait(lc.call(v_条目));
    return lc.join("item", (lc.truthy(M待办_取(v_条, "完成", false)) ? " done" : ""), (lc.eq(lcx.send(v_选中的, "读"), lc.dictGet(v_条, "号")) ? " sel" : ""));
  })), [lcx.nowait(lc.call(v_画一条, v_条目)), M画面_元素("button", lc.dictOf("类名", "del", "文字", "删"), null, lc.dictOf("点击", lc.fn("", 1, 1, (v_事件) => {
    lcx.nowait(lc.call(lc.dictGet(v_事件, "别再往上传")));
    M待办_发(v_删了, lcx.nowait(lc.call(v_条目)));
    return null;
  })))], lc.dictOf("点击", lc.fn("", 1, 1, (v_事件) => {
    lcx.send(v_选中的, "写", lc.dictGet(lcx.nowait(lc.call(v_条目)), "号"));
    M待办_发(v_点了, lcx.nowait(lc.call(v_条目)));
    return null;
  })));
});
const M待办_待办列表 = lc.fn("待办列表", 1, 3, function (v_属性, v_事件 = null, v_插槽 = null) {
  let v_条目们 = null, v_点了 = null, v_删了 = null, v_画一条 = null, v_画空的 = null, v_选中的 = null;
  v_条目们 = lc.dictGet(v_属性, "条目们");
  v_点了 = M待办_取(v_事件, "点了", null);
  v_删了 = M待办_取(v_事件, "删了", null);
  v_画一条 = M待办_取(v_插槽, "每一条", lc.fn("", 1, 1, (v_条目) => {
    return M画面_元素("span", lc.dictOf("类名", "title", "文字", lc.fn("", 0, 0, () => {
      return lc.dictGet(lcx.nowait(lc.call(v_条目)), "标题");
    })));
  }));
  v_画空的 = M待办_取(v_插槽, "空的时候", lc.fn("", 0, 0, () => {
    return M画面_元素("li", lc.dictOf("类名", "empty", "文字", "还没有待办"));
  }));
  v_选中的 = M反应_新状态(null);
  return M画面_元素("ul", lc.dictOf("类名", "todo"), [M画面_每一个(v_条目们, lc.fn("", 1, 1, (v_条) => {
    return lc.dictGet(v_条, "号");
  }), lc.fn("", 2, 2, (v_条目, v_序号) => {
    return M待办_一行(v_条目, v_选中的, v_画一条, v_点了, v_删了);
  })), M画面_如果有(lc.fn("", 0, 0, () => {
    return lc.eq(lc.size(lcx.nowait(lc.call(v_条目们))), 0.0);
  }), v_画空的)]);
});
const M待办_放待办列表 = lc.fn("放待办列表", 2, 4, function (v_父, v_条目们, v_点了 = null, v_删了 = null) {
  return M画面_挂上(v_父, lc.fn("", 0, 0, () => {
    return M待办_待办列表(lc.dictOf("条目们", v_条目们), lc.dictOf("点了", v_点了, "删了", v_删了));
  }));
});

// ———— 模块 检查 ————
const M检查_报 = lc.fn("报", 3, 3, function (v_号, v_名字, v_值) {
  lc.log(lc.join("[", v_号, "] ", v_名字, "：", v_值));
  return null;
});
const M检查_做了 = lc.fn("做了", 0, 0, function () {
  let v_o = null;
  v_o = host.testOps();
  return lc.join("新建 ", lc.dictGet(v_o, "新建"), "，写 ", lc.dictGet(v_o, "写"), "，插入 ", lc.dictGet(v_o, "插入"), "，拿走 ", lc.dictGet(v_o, "拿走"));
});
const M检查_树 = lc.fn("树", 1, 1, function (v_容器) {
  return host.testTree(host.testFind(v_容器, "ul", 1.0), false);
});
const M检查_行 = lc.fn("行", 2, 2, function (v_容器, v_第几) {
  return host.testFind(v_容器, "li.item", v_第几);
});
const M检查_去掉 = lc.fn("去掉", 2, 2, function (v_列, v_号) {
  let v_出 = null, v_条 = null;
  v_出 = [];
  for (let lcxs33 = lc.items(v_列), lci34 = 0; lci34 < lcxs33.length; lci34++) {
    v_条 = lcxs33[lci34];
    if (lc.ne(lc.dictGet(v_条, "号"), v_号)) {
      lc.listPush(v_出, v_条);
    }
  }
  return v_出;
});
const M检查_加上 = lc.fn("加上", 2, 2, function (v_列, v_条) {
  let v_出 = null, v_老 = null;
  v_出 = [];
  for (let lcxs35 = lc.items(v_列), lci36 = 0; lci36 < lcxs35.length; lci36++) {
    v_老 = lcxs35[lci36];
    lc.listPush(v_出, v_老);
  }
  lc.listPush(v_出, v_条);
  return v_出;
});
let M检查_积木条目 = M反应_新状态([lc.dictOf("号", 1.0, "标题", "积木放的", "完成", false)]);
let M检查_积木收到 = [];
async function lcMain_检查() {
  let v_记 = null, v_第二条 = null, v_条目们 = null, v_容器甲 = null, v_拿走甲 = null, v_元1 = null, v_元2 = null, v_元3 = null, v_元4 = null, v_现在的 = null, v_o = null, v_条目乙 = null, v_生命 = null, v_容器乙 = null, v_拿走乙 = null, v_乙的元素 = null, v_容器丙 = null;
  v_记 = [];
  v_第二条 = lc.dictOf("号", 2.0, "标题", "写作业", "完成", true);
  v_条目们 = M反应_新状态([lc.dictOf("号", 1.0, "标题", "买菜", "完成", false), v_第二条]);
  v_容器甲 = M画面_元素("div", lc.dictOf("类名", "a"));
  M画面_放进(M画面_页面根(), v_容器甲, null);
  v_拿走甲 = M画面_挂上(v_容器甲, lc.fn("", 0, 0, () => {
    return M待办_待办列表(lc.dictOf("条目们", lc.fn("", 0, 0, () => {
      return lcx.send(v_条目们, "读");
    })), lc.dictOf("点了", lc.fn("", 1, 1, (v_条) => {
      lc.listPush(v_记, lc.join("点了:", lc.dictGet(v_条, "标题")));
      return null;
    }), "删了", lc.fn("", 1, 1, (v_条) => {
      lc.listPush(v_记, lc.join("删了:", lc.dictGet(v_条, "标题")));
      lcx.send(v_条目们, "写", M检查_去掉(lcx.send(v_条目们, "偷看"), lc.dictGet(v_条, "号")));
      return null;
    })));
  }));
  (await M反应_等更新());
  M检查_报("1", "画出来的树", M检查_树(v_容器甲));
  v_元1 = M检查_行(v_容器甲, 1.0);
  v_元2 = M检查_行(v_容器甲, 2.0);
  M检查_做了();
  (await host.testClick(v_元2));
  M检查_报("2", "点第 2 条，收到的事件", v_记);
  M检查_报("3", "点了以后的树（第 2 条多了“选中”）", M检查_树(v_容器甲));
  M检查_报("4", "这一下宿主只被要求做了", M检查_做了());
  lcx.send(v_条目们, "写", [lc.dictOf("号", 1.0, "标题", "买菜", "完成", true), v_第二条]);
  (await M反应_等更新());
  M检查_报("5", "把第 1 条标成完成以后的树", M检查_树(v_容器甲));
  M检查_报("6", "这一下宿主只被要求做了", M检查_做了());
  lcx.send(v_条目们, "写", M检查_加上(lcx.send(v_条目们, "偷看"), lc.dictOf("号", 3.0, "标题", "复习", "完成", false)));
  (await M反应_等更新());
  M检查_报("7", "末尾加一条以后的树", M检查_树(v_容器甲));
  M检查_报("8", "原来两条还是原来那两个元素", lc.join(lcx.isSame(v_元1, M检查_行(v_容器甲, 1.0)), "，", lcx.isSame(v_元2, M检查_行(v_容器甲, 2.0))));
  lcx.send(v_条目们, "写", M检查_加上(lcx.send(v_条目们, "偷看"), lc.dictOf("号", 4.0, "标题", "交报告", "完成", false)));
  (await M反应_等更新());
  M检查_报("9", "再加第四条以后的树", M检查_树(v_容器甲));
  v_元3 = M检查_行(v_容器甲, 3.0);
  v_元4 = M检查_行(v_容器甲, 4.0);
  M检查_做了();
  (await host.testClick(host.testFind(v_容器甲, "button.del", 1.0)));
  M检查_报("10", "点第 1 条的“删”，收到的事件（没有多出“点了:买菜”）", v_记);
  M检查_报("11", "删了以后的树", M检查_树(v_容器甲));
  M检查_报("12", "这一下宿主只被要求做了", M检查_做了());
  M检查_报("13", "剩下三条还是原来的元素", lc.join(lcx.isSame(v_元2, M检查_行(v_容器甲, 1.0)), "，", lcx.isSame(v_元3, M检查_行(v_容器甲, 2.0)), "，", lcx.isSame(v_元4, M检查_行(v_容器甲, 3.0))));
  v_现在的 = lcx.send(v_条目们, "偷看");
  lcx.send(v_条目们, "写", [lc.listGet(v_现在的, 2.0), lc.listGet(v_现在的, 1.0), lc.listGet(v_现在的, 0.0)]);
  (await M反应_等更新());
  M检查_报("14", "把顺序倒过来以后的树", M检查_树(v_容器甲));
  v_o = host.testOps();
  M检查_报("15", "调顺序没有新建也没有拿走，元素还是原来的", lc.join("新建 ", lc.dictGet(v_o, "新建"), "，拿走 ", lc.dictGet(v_o, "拿走"), "，", lcx.isSame(v_元4, M检查_行(v_容器甲, 1.0)), "，", lcx.isSame(v_元3, M检查_行(v_容器甲, 2.0)), "，", lcx.isSame(v_元2, M检查_行(v_容器甲, 3.0))));
  lcx.send(v_条目们, "写", []);
  (await M反应_等更新());
  M检查_报("16", "清空以后（默认的“空的时候”）", M检查_树(v_容器甲));
  lcx.send(v_条目们, "写", [lc.dictOf("号", 5.0, "标题", "新的一条", "完成", false)]);
  (await M反应_等更新());
  M检查_报("17", "再加一条，空提示没了", M检查_树(v_容器甲));
  v_条目乙 = M反应_新状态([]);
  v_生命 = [];
  v_容器乙 = M画面_元素("div", lc.dictOf("类名", "b"));
  M画面_放进(M画面_页面根(), v_容器乙, null);
  v_拿走乙 = M画面_挂上(v_容器乙, lc.fn("", 0, 0, () => {
    M画面_放上以后(lc.fn("", 0, 0, () => {
      lc.listPush(v_生命, "放上以后");
      return null;
    }));
    M画面_拿走之前(lc.fn("", 0, 0, () => {
      lc.listPush(v_生命, "拿走之前");
      return null;
    }));
    return M待办_待办列表(lc.dictOf("条目们", lc.fn("", 0, 0, () => {
      return lcx.send(v_条目乙, "读");
    })), lc.dictOf("点了", lc.fn("", 1, 1, (v_条) => {
      lc.listPush(v_记, lc.join("乙点了:", lc.dictGet(v_条, "标题")));
      return null;
    })), lc.dictOf("每一条", lc.fn("", 1, 1, (v_条目) => {
      return M画面_元素("div", lc.dictOf("类名", "row"), [M画面_元素("span", lc.dictOf("类名", "pri", "文字", lc.fn("", 0, 0, () => {
        return lc.dictGet(lcx.nowait(lc.call(v_条目)), "级");
      }))), M画面_元素("span", lc.dictOf("类名", "name", "文字", lc.fn("", 0, 0, () => {
        return lc.dictGet(lcx.nowait(lc.call(v_条目)), "标题");
      })))]);
    }), "空的时候", lc.fn("", 0, 0, () => {
      return M画面_元素("p", lc.dictOf("类名", "none", "文字", "空空如也"));
    })));
  }));
  (await M反应_等更新());
  M检查_报("18", "第二个待办列表（自己给了两个插槽），空的时候", M检查_树(v_容器乙));
  lcx.send(v_条目乙, "写", [lc.dictOf("号", 1.0, "标题", "交报告", "级", "高")]);
  (await M反应_等更新());
  M检查_报("19", "第二个列表有了一条（“每一条怎么画”是自己给的）", M检查_树(v_容器乙));
  v_乙的元素 = M检查_行(v_容器乙, 1.0);
  (await host.testClick(v_乙的元素));
  M检查_报("20", "点第二个列表的第 1 条", lc.join("第二个：", M检查_树(v_容器乙), "｜第一个没变：", M检查_树(v_容器甲)));
  M检查_报("21", "第二个列表的“放上以后”叫过", v_生命);
  lcx.nowait(lc.call(v_拿走乙));
  (await M反应_等更新());
  M检查_报("22", "拿走第二个列表", lc.join("容器里：", host.testTree(v_容器乙, false), "｜", v_生命));
  M检查_做了();
  lcx.send(v_条目乙, "写", []);
  (await M反应_等更新());
  (await host.testClick(v_乙的元素));
  M检查_报("23", "拿走以后改它的条目、点它原来的元素", lc.join("宿主什么都没被要求做：", M检查_做了(), "｜事件一共还是 ", lc.size(v_记), " 个"));
  v_容器丙 = M画面_元素("div", lc.dictOf("类名", "c"));
  M画面_放进(M画面_页面根(), v_容器丙, null);
  M待办_放待办列表(v_容器丙, lc.fn("", 0, 0, () => {
    return lcx.send(M检查_积木条目, "读");
  }), lc.fn("", 1, 1, (v_条目) => {
    lc.listPush(M检查_积木收到, lc.dictGet(v_条目, "标题"));
    return null;
  }), null);
  (await M反应_等更新());
  M检查_报("24", "用积木外观放一个待办列表", M检查_树(v_容器丙));
  (await host.testClick(M检查_行(v_容器丙, 1.0)));
  M检查_报("25", "积木外观的“当点了”口收到", M检查_积木收到);
  return null;
}

(async () => {
  await lcMain_检查();
  host.ready();
})().catch(lcx.die);
