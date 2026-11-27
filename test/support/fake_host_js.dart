// “假宿主”测试用的 Node 脚本（D 分册 §9.2）：乙类 20 个原生绑定换一个假的浏览器窗口，甲类 9 个页面宿主接口换一张假的读写表。
// 每个接口一个用例；过了打印 `ok 名字`，没过打印 `FAIL 名字：原因`。不联网、不碰真浏览器。
const String kFakeHostHarness = r'''
"use strict";
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/lc2.js", "utf8") + "\n" + fs.readFileSync(__dirname + "/host.js", "utf8") + "\nreturn [lcRuntime, lcPageHost];";
const [lcRuntime, lcPageHost] = new Function(src)();

function fakeWin() {
  const timers = new Map();
  let seq = 0;
  const log = [];
  const mkStore = (full) => {
    const m = new Map();
    return {
      getItem: (k) => (m.has(k) ? m.get(k) : null),
      setItem: (k, v) => { if (full) throw new Error("QuotaExceededError"); m.set(k, String(v)); },
      removeItem: (k) => { m.delete(k); },
      get length() { return m.size; },
      key: (i) => [...m.keys()][i],
    };
  };
  const mkTarget = () => {
    const ls = {};
    return {
      ls,
      addEventListener(t, h, o) { (ls[t] = ls[t] || []).push([h, o]); },
      removeEventListener(t, h) { ls[t] = (ls[t] || []).filter((x) => x[0] !== h); },
      send(t, ev) { for (const [h] of (ls[t] || []).slice()) h(ev); },
    };
  };
  const w = mkTarget();
  const d = mkTarget();
  const routes = {};
  const win = {
    log, timers, routes, w, d,
    console: { log: (s) => log.push("log:" + s), error: (s) => log.push("err:" + s) },
    setTimeout: (f, ms) => { timers.set(++seq, { f, ms, kind: "t" }); return seq; },
    clearTimeout: (id) => { timers.delete(id); },
    setInterval: (f, ms) => { timers.set(++seq, { f, ms, kind: "i" }); return seq; },
    clearInterval: (id) => { timers.delete(id); },
    requestAnimationFrame: (f) => { timers.set(++seq, { f, kind: "f" }); return seq; },
    cancelAnimationFrame: (id) => { timers.delete(id); },
    AbortController,
    fetch: (url, init) => new Promise((ok, bad) => {
      log.push("fetch:" + init.method + " " + url + (init.body !== undefined ? " " + init.body : ""));
      const r = routes[url];
      if (init.signal) init.signal.addEventListener("abort", () => bad(new Error("aborted")));
      if (!r) { bad(new TypeError("Failed to fetch")); return; }
      if (r.hang) return;
      ok({ ok: r.status >= 200 && r.status < 300, status: r.status, headers: new Map([["Content-Type", "text/plain"]]), text: () => Promise.resolve(r.body) });
    }),
    localStorage: mkStore(false),
    sessionStorage: mkStore(false),
    fullStore: mkStore(true),
    location: { href: "https://x.test/a?b=1#c", pathname: "/a", search: "?b=1", hash: "#c" },
    history: {
      state: null,
      pushState(s, _, u) { this.state = s; log.push("push:" + u); },
      replaceState(s, _, u) { this.state = s; log.push("replace:" + u); },
      go(n) { log.push("go:" + n); },
    },
    addEventListener: w.addEventListener, removeEventListener: w.removeEventListener,
    document: { addEventListener: d.addEventListener, removeEventListener: d.removeEventListener },
    alert: (s) => { log.push("alert:" + s); },
    confirm: (s) => { log.push("confirm:" + s); return s !== "不"; },
    // 让到点的定时器跑一遍（kind：t 一次的 / i 重复的 / f 下一帧）。
    run(kind) {
      for (const [id, t] of [...timers]) {
        if (t.kind !== kind) continue;
        if (kind !== "i") timers.delete(id);
        t.f(kind === "f" ? 123 : undefined);
      }
    },
  };
  return win;
}
const settle = () => new Promise((r) => setImmediate(r));
function eq(got, want, what) {
  const a = JSON.stringify(got), b = JSON.stringify(want);
  if (a !== b) throw new Error((what || "值") + " 应该是 " + b + "，实际是 " + a);
}
async function fails(f, part) {
  try { await f(); } catch (e) {
    const m = String((e && e.message) || e);
    if (!m.includes(part)) throw new Error("错的话应该带「" + part + "」，实际是「" + m + "」");
    return;
  }
  throw new Error("应该出错（" + part + "）却没有");
}
const M = (o) => new Map(Object.entries(o));

const cases = {};
''';

const String kFakeHostRun = r'''
(async () => {
  for (const name of Object.keys(cases)) {
    try {
      await cases[name]();
      console.log("ok " + name);
    } catch (e) {
      console.log("FAIL " + name + "：" + ((e && e.message) || e));
    }
  }
})();
''';

/// 乙类 20 个原生绑定：各一个用例。
const String kFakeBrowserCases = r'''
function boot() { const win = fakeWin(); return [lcRuntime(win), win]; }

cases["timer.after"] = async () => {
  const [lc, win] = boot(); const got = [];
  const id = lc.timerAfter(50, () => { got.push("到点"); return null; });
  eq(typeof id, "number"); eq(got, []); eq([...win.timers.values()][0].ms, 50);
  win.run("t"); await settle(); eq(got, ["到点"]); eq(win.timers.size, 0);
  lc.timerAfter(-5, () => null); eq([...win.timers.values()][0].ms, 0, "负数当 0");
};
cases["timer.every"] = async () => {
  const [lc, win] = boot(); let n = 0;
  lc.timerEvery(10, () => { n++; return null; });
  win.run("i"); win.run("i"); win.run("i"); await settle(); eq(n, 3); eq(win.timers.size, 1, "重复的还在");
};
cases["timer.cancel"] = async () => {
  const [lc, win] = boot(); let n = 0;
  const a = lc.timerAfter(10, () => { n++; return null; });
  const b = lc.timerEvery(10, () => { n++; return null; });
  const c = lc.timerFrame(() => { n++; return null; });
  lc.timerCancel(a); lc.timerCancel(b); lc.timerCancel(c); lc.timerCancel(a); lc.timerCancel(9999);
  win.run("t"); win.run("i"); win.run("f"); await settle(); eq(n, 0); eq(win.timers.size, 0);
};
cases["timer.frame"] = async () => {
  const [lc, win] = boot(); const got = [];
  lc.timerFrame((t) => { got.push(t); return null; });
  win.run("f"); await settle(); eq(got, [123]);
};
cases["net.request"] = async () => {
  const [lc, win] = boot();
  win.routes["https://a.test/x"] = { status: 201, body: "好" };
  win.routes["https://a.test/404"] = { status: 404, body: "没有" };
  win.routes["https://a.test/hang"] = { hang: true };
  const r = lc.toPlain(await lc.netRequest(M({ url: "https://a.test/x", method: "post", body: "正文", headers: M({ A: "1" }) })));
  eq(r, { body: "好", headers: { "content-type": "text/plain" }, ok: true, status: 201 });
  eq(win.log, ["fetch:POST https://a.test/x 正文"]);
  const r2 = lc.toPlain(await lc.netRequest(M({ url: "https://a.test/404" })));
  eq([r2.status, r2.ok, r2.body], [404, false, "没有"], "不是 200 多不算出错");
  await fails(() => lc.netRequest(M({ url: "https://a.test/nope" })), "连不上");
  await fails(() => lc.netRequest(M({ url: "" })), "没有写网址");
  await fails(() => lc.netRequest(M({ url: "https://a.test/x", method: "FLY" })), "不认识的方式");
  const p = lc.netRequest(M({ url: "https://a.test/hang", timeoutMs: 30 }));
  await settle(); win.run("t");
  await fails(() => p, "超时");
};
cases["net.abortNew"] = async () => {
  const [lc] = boot();
  const t = lc.netAbortNew(); eq(t.lcAbort, true); eq(t.aborted, false);
  if (lc.netAbortNew() === t) throw new Error("每次要是新的");
};
cases["net.abort"] = async () => {
  const [lc, win] = boot();
  win.routes["https://a.test/hang"] = { hang: true };
  const t = lc.netAbortNew();
  const p = lc.netRequest(M({ url: "https://a.test/hang", abort: t }));
  await settle(); lc.netAbort(t); lc.netAbort(t);
  await fails(() => p, "已中止");
  await fails(() => lc.netRequest(M({ url: "https://a.test/hang", abort: t })), "已中止");
  await fails(async () => lc.netAbort(42), "不是一个中止令牌");
};
cases["storage.read"] = async () => {
  const [lc, win] = boot();
  eq(lc.storageRead("local", "k"), null); win.localStorage.setItem("k", "v"); eq(lc.storageRead("local", "k"), "v");
  eq(lc.storageRead("session", "k"), null, "两个区互不相干");
  await fails(async () => lc.storageRead("别的", "k"), "只能是 local 或 session");
};
cases["storage.write"] = async () => {
  const [lc, win] = boot();
  lc.storageWrite("session", "a", "1"); eq(win.sessionStorage.getItem("a"), "1"); eq(win.localStorage.getItem("a"), null);
  win.localStorage = win.fullStore;
  await fails(async () => lc.storageWrite("local", "a", "1"), "存不进去");
  delete win.sessionStorage;
  await fails(async () => lc.storageWrite("session", "a", "1"), "用不了本地存储");
};
cases["storage.remove"] = async () => {
  const [lc, win] = boot();
  win.localStorage.setItem("a", "1"); lc.storageRemove("local", "a"); lc.storageRemove("local", "没有的");
  eq(win.localStorage.getItem("a"), null);
};
cases["storage.keys"] = async () => {
  const [lc, win] = boot();
  for (const k of ["丙", "b", "a"]) win.localStorage.setItem(k, "1");
  eq(lc.storageKeys("local"), ["a", "b", "丙"], "按字排好"); eq(lc.storageKeys("session"), []);
};
cases["loc.now"] = async () => {
  const [lc, win] = boot();
  win.history.state = { n: 1 };
  eq(lc.toPlain(lc.locNow()), { hash: "#c", href: "https://x.test/a?b=1#c", path: "/a", query: "?b=1", state: { n: 1 } });
};
cases["loc.push"] = async () => {
  const [lc, win] = boot();
  lc.locPush("/b", M({ page: 2 })); eq(win.log, ["push:/b"]); eq(win.history.state, { page: 2 });
};
cases["loc.replace"] = async () => {
  const [lc, win] = boot();
  lc.locReplace("/c", null); eq(win.log, ["replace:/c"]); eq(win.history.state, null);
};
cases["loc.go"] = async () => {
  const [lc, win] = boot();
  lc.locGo(-1); lc.locGo(2); eq(win.log, ["go:-1", "go:2"]);
};
cases["loc.onPop"] = async () => {
  const [lc, win] = boot(); const got = [];
  const off = lc.locOnPop((s) => { got.push(lc.toPlain(s)); return null; });
  win.w.send("popstate", { state: { n: 7 } }); await settle(); eq(got, [{ n: 7 }]);
  off(); win.w.send("popstate", { state: null }); await settle(); eq(got.length, 1, "不听以后不再来");
};
cases["loc.assign"] = async () => {
  const [lc, win] = boot();
  lc.locAssign("other.html"); eq(win.location.href, "other.html");
};
cases["page.alert"] = async () => {
  const [lc, win] = boot();
  eq(lc.pageAlert("你好"), null); eq(win.log, ["alert:你好"]);
};
cases["page.confirm"] = async () => {
  const [lc, win] = boot();
  eq(lc.pageConfirm("行吗"), true); eq(lc.pageConfirm("不"), false); eq(win.log, ["confirm:行吗", "confirm:不"]);
};
cases["win.on"] = async () => {
  const [lc, win] = boot(); const got = [];
  const off = lc.winOn("window", "keydown", (ev) => { got.push(ev.get("key")); return null; }, M({ passive: true }));
  eq(win.w.ls.keydown[0][1], { once: false, passive: true });
  win.w.send("keydown", { key: "a" }); await settle(); eq(got, ["a"]);
  off(); win.w.send("keydown", { key: "b" }); await settle(); eq(got, ["a"]);
  lc.winOn("document", "click", (ev) => { got.push(ev.get("x")); return null; }, M({}));
  win.d.send("click", { clientX: 5 }); await settle(); eq(got, ["a", 5]);
  await fails(async () => lc.winOn("别的", "click", () => null, M({})), "只能是 window 或 document");
};
// 事件记录（§2.4）：八样东西齐全，拦默认、拦冒泡传得到浏览器事件上。
cases["事件记录"] = async () => {
  const [lc] = boot(); const hit = [];
  const ev = { target: { value: 12, checked: true }, key: "Enter", clientX: 3, clientY: 4, preventDefault() { hit.push("p"); }, stopPropagation() { hit.push("s"); } };
  const rec = lc.eventRec(ev);
  eq([...rec.keys()], ["value", "checked", "key", "x", "y", "target", "preventDefault", "stopPropagation"]);
  eq([rec.get("value"), rec.get("checked"), rec.get("key"), rec.get("x"), rec.get("y")], ["12", true, "Enter", 3, 4]);
  rec.get("preventDefault")(); rec.get("stopPropagation")(); eq(hit, ["p", "s"]);
  const none = lc.eventRec(undefined);
  eq([none.get("value"), none.get("checked"), none.get("key"), none.get("x")], ["", false, "", 0], "没有事件也不出错");
};
''';

/// 甲类 9 个页面宿主接口：各一个用例（假读写表）。
const String kFakePageCases = r'''
function page() {
  const win = fakeWin(); const lc = lcRuntime(win);
  const states = { count: 1, list: [1, 2] }, props = { "n1 text": "甲" };
  const t = {
    changed: 0, listened: [], hooks: {},
    state: (n) => (n === "sum" ? [() => states.count + 1, null] : n in states ? [() => states[n], (v) => { states[n] = v; }] : null),
    prop: (id, p) => (id + " " + p in props ? [() => props[id + " " + p], (v) => { props[id + " " + p] = v; }] : null),
  };
  t.changedFn = () => { t.changed++; };
  const table = { state: t.state, prop: t.prop, changed: t.changedFn, listen: (id, type, f) => { t.listened.push(id + " " + type); t.hooks[id + " " + type] = f; } };
  return [lcPageHost(lc, table), lc, win, states, props, t];
}

cases["page.state.new"] = async () => {
  const [h, lc] = page();
  const c = h.stateNew("count", 99); eq(h.stateRead(c), 1, "声明过的状态：初值以页面的为准");
  const free = h.stateNew("", 5); eq(h.stateRead(free), 5);
  await fails(async () => h.stateNew("没有的", 0), "没有叫「没有的」的状态");
};
cases["page.state.read"] = async () => {
  const [h, lc] = page();
  const l = h.stateRead(h.stateNew("list", null));
  eq(lc.toPlain(l), [1, 2]);
  await fails(async () => h.stateRead(42), "不是一个状态");
};
cases["page.state.write"] = async () => {
  const [h, lc, win, states, props, t] = page();
  const c = h.stateNew("count", 0);
  h.stateWrite(c, 7); eq(states.count, 7, "立刻生效"); eq(h.stateRead(c), 7); eq(t.changed, 1, "叫了界面重画");
  h.stateWrite(h.stateNew("list", null), [3]); eq(states.list, [3]);
  await fails(async () => h.stateWrite(h.stateNew("sum", 0), 1), "派生值");
};
cases["page.state.derived"] = async () => {
  const [h] = page(); let ran = 0;
  const c = h.stateNew("count", 0);
  const d = h.stateDerived(() => { ran++; return h.stateRead(c) * 2; });
  eq(ran, 0, "读的时候才算"); eq(h.stateRead(d), 2); h.stateWrite(c, 5); eq(h.stateRead(d), 10);
  await fails(async () => h.stateWrite(d, 1), "不能改");
  const bad = h.stateDerived(() => { h.stateWrite(c, 0); return 1; });
  await fails(async () => h.stateRead(bad), "派生值的算法里不能改状态");
};
cases["page.state.watch"] = async () => {
  const [h, lc, win] = page(); const got = [];
  const c = h.stateNew("count", 0);
  const off = h.stateWatch(() => h.stateRead(c), (now, old) => { got.push([now, old]); return null; });
  h.stateWrite(c, 2); h.stateWrite(c, 3); eq(got, [], "这一轮做完才叫");
  await settle(); eq(got, [[3, 1]], "一轮里改两次只叫一次");
  h.stateWrite(c, 3); await settle(); eq(got.length, 1, "值没变不叫");
  off(); h.stateWrite(c, 9); await settle(); eq(got.length, 1, "不听以后不再叫");
  // 互相触发：超过 100 轮停下并报错
  const a = h.stateNew("", 0);
  h.stateWatch(() => h.stateRead(a), () => { h.stateWrite(a, h.stateRead(a) + 1); return null; });
  h.stateWrite(a, 1); await settle(); await settle();
  if (!win.log.some((l) => l.includes("超过 100 轮"))) throw new Error("没有报“超过 100 轮”：" + JSON.stringify(win.log));
};
cases["page.ui.read"] = async () => {
  const [h] = page();
  eq(h.uiRead("n1", "text"), "甲"); eq(h.uiRead("没有", "text"), "", "读不到给空文字");
};
cases["page.ui.write"] = async () => {
  const [h, lc, win, states, props, t] = page();
  h.uiWrite("n1", "text", "乙"); eq(props["n1 text"], "乙"); eq(t.changed, 1);
  eq(h.uiWrite("没有", "text", "x"), null, "写不了安静跳过"); eq(t.changed, 1);
};
cases["page.ui.on"] = async () => {
  const [h, lc, win, states, props, t] = page(); const got = [];
  const off = h.uiOn("n1", "click", (ev) => { got.push("甲" + ev.get("value")); return null; }, new Map());
  h.uiOn("n1", "click", (ev) => { got.push("乙"); return null; }, new Map([["once", true]]));
  eq(t.listened, ["n1 click"], "一个控件一个事件只往页面上挂一次");
  t.hooks["n1 click"]({ target: { value: "v" } }); await settle(); eq(got, ["甲v", "乙"], "按登记的先后");
  h.emit("n1", "click", {}); await settle(); eq(got, ["甲v", "乙", "甲"], "只一次的做过就不在了");
  off(); h.emit("n1", "click", {}); await settle(); eq(got.length, 3);
  h.emit("别的", "click", {}); await settle(); eq(got.length, 3, "没登记的事件安静跳过");
  // 处理里出错：不拖累别的处理，交给“页面出错时”
  const errs = [];
  h.uiLife("error", (msg) => { errs.push(msg); return null; });
  h.uiOn("n2", "click", () => { lc.fail("坏了"); }, new Map());
  h.uiOn("n2", "click", () => { got.push("后面的照做"); return null; }, new Map());
  h.emit("n2", "click", {}); await settle(); await settle();
  eq(got[got.length - 1], "后面的照做"); eq(errs.length, 1); if (!errs[0].includes("坏了")) throw new Error("出错的话不对：" + errs[0]);
};
cases["page.ui.life"] = async () => {
  const [h] = page(); const got = [];
  h.uiLife("mounted", () => { got.push("放上"); return null; });
  h.uiLife("unmount", () => { got.push("拿走"); return null; });
  eq(got, []); h.emitLife("mounted"); h.emitLife("mounted"); await settle(); eq(got, ["放上"], "放上只算一次");
  h.uiLife("mounted", () => { got.push("晚来的"); return null; }); await settle(); eq(got, ["放上", "晚来的"], "页面已经放上了，晚登记的马上做");
  h.emitLife("unmount"); await settle(); eq(got, ["放上", "晚来的", "拿走"]);
  await fails(async () => h.uiLife("别的", () => null), "只能是 mounted、unmount 或 error");
};
''';
