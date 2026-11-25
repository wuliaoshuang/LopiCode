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
const M待办_写 = lc.fn("写", 3, 3, function (v_控件, v_名, v_值) {
  if (!lcx.isSame(host.uiGet(v_控件, v_名), v_值)) {
    host.uiSet(v_控件, v_名, v_值);
  }
  return null;
});
const M待办_认领一行 = lc.fn("认领一行", 9, 9, function (v_位, v_行名, v_标题名, v_删名, v_条目们, v_选中的, v_画一条, v_点了, v_删了) {
  M反应_跟着做(lc.fn("", 0, 0, () => {
    let v_列 = null, v_条 = null;
    v_列 = lcx.nowait(lc.call(v_条目们));
    if (lc.lt(v_位, lc.size(v_列))) {
      v_条 = lc.listGet(v_列, v_位);
      M待办_写(v_行名, "显示", true);
      M待办_写(v_行名, "类名", lc.join("item", (lc.truthy(M待办_取(v_条, "完成", false)) ? " done" : ""), (lc.eq(lcx.send(v_选中的, "读"), lc.dictGet(v_条, "号")) ? " sel" : "")));
      M待办_写(v_标题名, "文字", lcx.nowait(lc.call(v_画一条, v_条)));
    } else {
      M待办_写(v_行名, "显示", false);
    }
    return null;
  }));
  host.uiOn(v_行名, "点击", lc.fn("", 1, 1, (v_事件) => {
    let v_列 = null;
    v_列 = lcx.nowait(lc.call(v_条目们));
    if (lc.lt(v_位, lc.size(v_列))) {
      lcx.send(v_选中的, "写", lc.dictGet(lc.listGet(v_列, v_位), "号"));
      M待办_发(v_点了, lc.listGet(v_列, v_位));
    }
    return null;
  }));
  host.uiOn(v_删名, "点击", lc.fn("", 1, 1, (v_事件) => {
    let v_列 = null;
    lcx.nowait(lc.call(lc.dictGet(v_事件, "别再往上传")));
    v_列 = lcx.nowait(lc.call(v_条目们));
    if (lc.lt(v_位, lc.size(v_列))) {
      M待办_发(v_删了, lc.listGet(v_列, v_位));
    }
    return null;
  }));
  return null;
});
const M待办_待办列表 = lc.fn("待办列表", 2, 4, function (v_控件名, v_属性, v_事件 = null, v_插槽 = null) {
  let v_条目们 = null, v_点了 = null, v_删了 = null, v_画一条 = null, v_画空的 = null, v_选中的 = null, v_行们 = null, v_行名 = null, v_位 = null;
  v_条目们 = lc.dictGet(v_属性, "条目们");
  v_点了 = M待办_取(v_事件, "点了", null);
  v_删了 = M待办_取(v_事件, "删了", null);
  v_画一条 = M待办_取(v_插槽, "每一条", lc.fn("", 1, 1, (v_条) => {
    return lc.dictGet(v_条, "标题");
  }));
  v_画空的 = M待办_取(v_插槽, "空的时候", lc.fn("", 0, 0, () => {
    return "还没有待办";
  }));
  v_选中的 = M反应_新状态(null);
  v_行们 = lc.dictGet(v_控件名, "行");
  for (let lcxs14 = lc.items(v_行们), lci15 = 0; lci15 < lcxs14.length; lci15++) {
    v_行名 = lcxs14[lci15];
    v_位 = lci15;
    M待办_认领一行(v_位, v_行名, lc.listGet(lc.dictGet(v_控件名, "标题"), v_位), lc.listGet(lc.dictGet(v_控件名, "删"), v_位), v_条目们, v_选中的, v_画一条, v_点了, v_删了);
  }
  M反应_跟着做(lc.fn("", 0, 0, () => {
    let v_空 = null;
    v_空 = lc.eq(lc.size(lcx.nowait(lc.call(v_条目们))), 0.0);
    M待办_写(lc.dictGet(v_控件名, "空提示"), "显示", v_空);
    if (lc.truthy(v_空)) {
      M待办_写(lc.dictGet(v_控件名, "空提示"), "文字", lcx.nowait(lc.call(v_画空的)));
    }
    return null;
  }));
  return null;
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
  return host.testTree("列表", false);
});
const M检查_行 = lc.fn("行", 2, 2, function (v_容器, v_第几) {
  return host.testFind(null, "li.item", v_第几);
});
const M检查_去掉 = lc.fn("去掉", 2, 2, function (v_列, v_号) {
  let v_出 = null, v_条 = null;
  v_出 = [];
  for (let lcxs16 = lc.items(v_列), lci17 = 0; lci17 < lcxs16.length; lci17++) {
    v_条 = lcxs16[lci17];
    if (lc.ne(lc.dictGet(v_条, "号"), v_号)) {
      lc.listPush(v_出, v_条);
    }
  }
  return v_出;
});
const M检查_加上 = lc.fn("加上", 2, 2, function (v_列, v_条) {
  let v_出 = null, v_老 = null;
  v_出 = [];
  for (let lcxs18 = lc.items(v_列), lci19 = 0; lci19 < lcxs18.length; lci19++) {
    v_老 = lcxs18[lci19];
    lc.listPush(v_出, v_老);
  }
  lc.listPush(v_出, v_条);
  return v_出;
});
async function lcMain_检查() {
  let v_记 = null, v_第二条 = null, v_条目们 = null, v_容器甲 = null, v_元1 = null, v_元2 = null, v_元3 = null, v_元4 = null, v_现在的 = null, v_o = null;
  v_记 = [];
  v_第二条 = lc.dictOf("号", 2.0, "标题", "写作业", "完成", true);
  v_条目们 = M反应_新状态([lc.dictOf("号", 1.0, "标题", "买菜", "完成", false), v_第二条]);
  v_容器甲 = null;
  host.testPage(lc.toJson(lc.dictOf("tag", "ul", "cls", "todo", "id", "列表", "children", [lc.dictOf("tag", "li", "cls", "item", "id", "行1", "shown", false, "children", [lc.dictOf("tag", "span", "cls", "title", "id", "标题1"), lc.dictOf("tag", "button", "cls", "del", "id", "删1", "text", "删")]), lc.dictOf("tag", "li", "cls", "item", "id", "行2", "shown", false, "children", [lc.dictOf("tag", "span", "cls", "title", "id", "标题2"), lc.dictOf("tag", "button", "cls", "del", "id", "删2", "text", "删")]), lc.dictOf("tag", "li", "cls", "item", "id", "行3", "shown", false, "children", [lc.dictOf("tag", "span", "cls", "title", "id", "标题3"), lc.dictOf("tag", "button", "cls", "del", "id", "删3", "text", "删")]), lc.dictOf("tag", "li", "cls", "empty", "id", "空提示", "shown", false)])));
  M待办_待办列表(lc.dictOf("行", ["行1", "行2", "行3"], "标题", ["标题1", "标题2", "标题3"], "删", ["删1", "删2", "删3"], "空提示", "空提示"), lc.dictOf("条目们", lc.fn("", 0, 0, () => {
    return lcx.send(v_条目们, "读");
  })), lc.dictOf("点了", lc.fn("", 1, 1, (v_条) => {
    lc.listPush(v_记, lc.join("点了:", lc.dictGet(v_条, "标题")));
    return null;
  }), "删了", lc.fn("", 1, 1, (v_条) => {
    lc.listPush(v_记, lc.join("删了:", lc.dictGet(v_条, "标题")));
    lcx.send(v_条目们, "写", M检查_去掉(lcx.send(v_条目们, "偷看"), lc.dictGet(v_条, "号")));
    return null;
  })));
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
  (await host.testClick(host.testFind(null, "button.del", 1.0)));
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
  M检查_报("18", "第二个待办列表（自己给了两个插槽），空的时候", "写不出来：页面上只摆了一套控件，组件认的是控件的名字；第二个实例要再摆一套、再起一套名字");
  M检查_报("19", "第二个列表有了一条（“每一条怎么画”是自己给的）", "写不出来：插槽只能交回一段文字，画不出“一行里两个带样式的小块”——没有造元素的接口");
  M检查_报("20", "点第二个列表的第 1 条", "写不出来：没有第二个实例");
  M检查_报("21", "第二个列表的“放上以后”叫过", "写不出来：组件不是被放上去的，是认领现成的控件，没有“放上”这个时刻");
  M检查_报("22", "拿走第二个列表", "写不出来：没有“拿下来”的接口，最多把控件藏起来；登记的事件处理也没有地方统一取消");
  M检查_报("23", "拿走以后改它的条目、点它原来的元素", "写不出来：同上");
  M检查_报("24", "用积木外观放一个待办列表", "写不出来：积木没法“放”一个组件到页面上，只能认领");
  M检查_报("25", "积木外观的“当点了”口收到", "写不出来：同上");
  return null;
}

(async () => {
  await lcMain_检查();
  host.ready();
})().catch(lcx.die);
