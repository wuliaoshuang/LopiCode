/// 页面宿主（甲类 13 个接口（设计时 9 个，第四轮 A3 加了去页面带参数、读带来的参数、这一项、第几项））在产物里的那一段 JS。设计见 docs/blocks-v5-parts/D-frontend-logic.md §2.2、§4.2 和末尾“落地说明（第四轮·A2）”。
///
/// 做法：这些接口的规矩（立刻生效、派生读时才算、“当…变了”攒到这一轮做完再跑、超过 100 轮报错、事件记录、页面的几个时刻）
/// 只写一遍，就是这里的 `lcPageHost(lc, t)`；三种产物各给一张“读写表” `t`，说清楚在自己那里状态和控件属性放在哪：
///
/// ```
/// t.state(名字)      → [读, 写] 或 null     页面（或项目）里声明过的状态。纯网页＝state 对象；Vue＝ref；React＝lcVars / lcShared。
/// t.prop(控件, 属性)  → [读, 写] 或 null     控件属性。纯网页＝直接读写页面上的元素；Vue / React＝模板绑着的那些 ref / lcUi。
/// t.changed()                              改完以后要不要叫界面重画（React 要；别的不用）。可以没有。
/// t.page / t.go(页 id)                    这一页是谁；换到项目里的另一页（去不了交回 false）。新的页面逻辑才给。
/// t.item(控件, 浏览器事件)                   纯网页：这次事件是从“重复”出来的第几份上来的（{item, index}）。可以没有。
/// t.listen(控件, 事件, 叫谁)                 纯网页：往元素上挂监听。Vue / React 没有这一项——事件由模板接好，再调 host.emit。
/// ```
///
/// 交回的对象除了这些接口，还有给产物接线用的：`emit(控件, 事件, 浏览器事件)`、`emitLife(哪个时刻)`、`poke()`（外面改了状态，叫“当…变了”看一眼）。
library;

const String kLcPageHostJs = r'''
// —— 页面宿主：状态、控件、事件、页面的几个时刻（三种导出共用这一段；各自给一张读写表 t）——
function lcPageHost(lc, t) {
  const watchers = [];
  const handlers = Object.create(null);
  const life = { mounted: [], unmount: [] };
  let queued = false, deriving = 0, mounted = false;

  function poke() {
    if (queued || watchers.length === 0) return;
    queued = true;
    Promise.resolve().then(flush);
  }
  // 这一轮代码做完以后：把“当…变了”都看一遍，值变了的叫它的回调；回调里又改了状态就再看一轮，最多 100 轮。
  function flush() {
    // 看的这段时间里 queued 一直是真的：回调里再改状态不另排一次，由下面这一轮接一轮地看（不然超过 100 轮以后还会没完没了地排下去）。
    try {
      flushRounds();
    } finally {
      queued = false;
    }
  }
  function flushRounds() {
    for (let round = 0; round < 100; round++) {
      let any = false;
      for (const w of watchers.slice()) {
        if (!w.live) continue;
        let now;
        try { now = w.get(); } catch (e) { lc.report(e); continue; }
        if (same(now, w.last)) continue;
        const old = w.last;
        w.last = now;
        any = true;
        lc.fire(w.f, now, old);
      }
      if (!any) return;
    }
    lc.report(new lc.LcError("“当…变了”互相触发超过 100 轮，停下了"));
  }
  function same(a, b) {
    if (a === b) return true;
    try { return lc.toJson(a) === lc.toJson(b); } catch (e) { return false; }
  }
  function touched() {
    if (t.changed) t.changed();
    poke();
  }

  // 新建状态。名字不空＝页面里声明过的那个（交回它的把手）；名字是空的＝一个没有名字的新格子。
  function stateNew(name, init) {
    if (name === "") return { lcCell: true, v: init };
    const io = t.state(name);
    if (!io) lc.fail("页面里没有叫「" + name + "」的状态");
    return { lcCell: true, io: io, name: name };
  }
  function cellOf(c) {
    if (!c || c.lcCell !== true) lc.fail("这不是一个状态");
    return c;
  }
  function stateRead(c) {
    cellOf(c);
    if (c.io) return lc.fromPlain(c.io[0]());
    if (c.calc) {
      deriving++;
      try { return c.calc(); } finally { deriving--; }
    }
    return c.v;
  }
  function stateWrite(c, v) {
    cellOf(c);
    if (deriving > 0) lc.fail("派生值的算法里不能改状态");
    if (c.calc) lc.fail("派生值是算出来的，不能改");
    if (c.io) {
      if (!c.io[1]) lc.fail("「" + c.name + "」是派生值，算出来的，不能改");
      c.io[1](lc.toPlain(v));
    } else {
      if (same(c.v, v)) return null;
      c.v = v;
    }
    touched();
    return null;
  }
  const stateDerived = (calc) => ({ lcCell: true, calc: calc });
  function stateWatch(get, f) {
    const w = { get: get, f: f, last: get(), live: true };
    watchers.push(w);
    return () => {
      w.live = false;
      const i = watchers.indexOf(w);
      if (i >= 0) watchers.splice(i, 1);
      return null;
    };
  }

  function uiRead(id, prop) {
    const io = t.prop(id, prop);
    return io ? lc.fromPlain(io[0]()) : "";
  }
  function uiWrite(id, prop, v) {
    const io = t.prop(id, prop);
    if (!io || !io[1]) return null;
    io[1](lc.toPlain(v));
    touched();
    return null;
  }
  function uiOn(id, type, f, opts) {
    const key = id + " " + type;
    if (!handlers[key]) {
      handlers[key] = [];
      if (t.listen) t.listen(id, type, (ev) => emit(id, type, ev));
    }
    const h = { f: f, once: opts.get("once") === true };
    handlers[key].push(h);
    return () => {
      const list = handlers[key], i = list.indexOf(h);
      if (i >= 0) list.splice(i, 1);
      return null;
    };
  }
  function emit(id, type, ev) {
    const list = handlers[id + " " + type];
    if (!list || list.length === 0) return;
    const rec = lc.eventRec(ev);
    // “重复”出来的控件：这一份是第几项、那一项是什么（导出的模板递过来的，或者读写表从页面上找的）。
    const at = ev && ev.lcAt ? ev.lcAt : t.item ? t.item(id, ev) : null;
    if (at) rec.set("lcAt", at);
    // 组件实例发出来的事件：带的数据。
    if (ev && ev.lcData && typeof ev.lcData === "object") rec.set("lcData", lc.fromPlain(ev.lcData));
    for (const h of list.slice()) {
      if (h.once) list.splice(list.indexOf(h), 1);
      lc.fire(h.f, rec);
    }
  }
  function uiLife(which, f) {
    if (which === "error") { lc.onFail((msg) => lc.fire(f, msg)); return null; }
    if (which !== "mounted" && which !== "unmount") lc.fail("页面的时刻只能是 mounted、unmount 或 error");
    life[which].push(f);
    if (which === "mounted" && mounted) lc.fire(f, null);
    return null;
  }
  function emitLife(which) {
    if (which === "mounted") {
      if (mounted) return;
      mounted = true;
    }
    for (const f of life[which].slice()) lc.fire(f, null);
  }

  // 去项目里的另一页（带上参数）；这一页这次带来的参数。怎么换页、参数放哪，读写表说了算（t.go / t.params）。
  // 带的参数放两处：这次打开的网页里记一份（同一个网页里换页用它）；sessionStorage 里记一份（纯网页换页是换了一个文件，靠它带过去；刷新也还在）。
  function navStore() {
    const g = typeof globalThis === "object" ? globalThis : {};
    if (!g.lcNav) g.lcNav = Object.create(null);
    return g.lcNav;
  }
  function navGo(id, params) {
    const plain = lc.toPlain(params);
    navStore()[id] = plain;
    try { sessionStorage.setItem("lc-nav:" + id, JSON.stringify(plain)); } catch (e) { /* 存不了（隐私模式）：同一个网页里换页照样带得过去 */ }
    if (!t.go || !t.go(id)) lc.fail("项目里没有这一页，去不了");
    return null;
  }
  function navParams() {
    const id = t.page || "";
    let p = navStore()[id];
    if (p === undefined) {
      try { p = JSON.parse(sessionStorage.getItem("lc-nav:" + id) || "{}"); } catch (e) { p = {}; }
    }
    return lc.fromPlain(p && typeof p === "object" && !Array.isArray(p) ? p : {});
  }
  // 这次事件是从“重复”出来的哪一份控件上来的：读写表按控件和浏览器事件找（t.item）；不在重复里＝空、-1。
  function itemOf(rec) {
    const at = rec instanceof Map ? rec.get("lcAt") : null;
    return at && typeof at === "object" ? at : null;
  }
  function uiItem(rec) {
    const at = itemOf(rec);
    return at ? lc.fromPlain(at.item) : null;
  }
  function uiIndex(rec) {
    const at = itemOf(rec);
    return at ? at.index : -1;
  }

  return { stateNew, stateRead, stateWrite, stateDerived, stateWatch, uiRead, uiWrite, uiOn, uiLife, navGo, navParams, uiItem, uiIndex, emit, emitLife, poke };
}
''';
