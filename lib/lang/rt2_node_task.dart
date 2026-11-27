/// 规矩版本 2 的小库·Node·“要等的事”那一块（拼在 `lc2.js` 中间，见 rt2_node.dart）：这条线、等一会儿、开始做、等、
/// 等最多 / 等全部 / 等最先的一个、取消、一次只让一个做。规矩见 docs/blocks-v5-parts/B-gen-notes.md 第 16 节。只用 Node 自带的模块。
library;

const String kRt2NodeTask = r'''
// —— 要等的事 ——
// “这条线”：一件事（主程序、一次“开始做”、一个请求）。Node 用自带的 AsyncLocalStorage 记着现在跑的是哪一条，
// 取消、“一次只让一个做”靠它认。wake：这条线正停在要等的地方时，叫醒它（让它抛“取消了”）的办法。
const lineStore = new (require("node:async_hooks").AsyncLocalStorage)();
const mainLine = { cancelled: false, wake: null };
const lineNow = () => lineStore.getStore() || mainLine;
const inLine = (f) => lineStore.run({ cancelled: false, wake: null }, f);
const cancelErr = () => new LcError("这件事被取消了");
// 停下来等：start(ok, bad) 开始等、交回“不等了要收拾什么”；等的时候这条线被取消＝收拾好、抛“取消了”。
function pause(start) {
  const me = lineNow();
  if (me.cancelled) return Promise.reject(cancelErr());
  return new Promise((ok, bad) => {
    let live = true;
    const end = (f) => (v) => { if (!live) return; live = false; me.wake = null; if (tidy) tidy(); f(v); };
    let tidy = null;
    me.wake = () => end(bad)(cancelErr());
    tidy = start(end(ok), end(bad));
    if (!live && tidy) tidy();
  });
}
const hostSleep = (ms) => pause((ok) => { const t = setTimeout(() => ok(null), Math.max(0, ms)); return () => clearTimeout(t); });
// 开始做一件事：马上开始（做到它第一件要等的事为止），拿到“稍后的结果”；出了错先记着，等它的时候再抛。
function spawn(f) {
  const t = { done: false, val: null, err: null, line: { cancelled: false, wake: null }, p: null };
  t.p = lineStore.run(t.line, async () => {
    try { t.val = await f(); return t.val; } catch (e) { t.err = e; throw e; } finally { t.done = true; }
  });
  t.p.catch(() => {});
  return t;
}
const wait = (t) => pause((ok, bad) => { t.p.then(ok, bad); return null; });
// 最多等 ms 毫秒；到时候还没做完＝“超时”错误（那件事自己接着做）。
function awaitMax(t, ms) {
  ms = Math.max(0, ms);
  return pause((ok, bad) => {
    const timer = setTimeout(() => bad(new LcError("等了 " + ms + " 毫秒还没做完")), ms);
    t.p.then(ok, bad);
    return () => clearTimeout(timer);
  });
}
function cancel(t) {
  if (t.done || t.line.cancelled) return null;
  t.line.cancelled = true;
  if (t.line.wake) t.line.wake();
  return null;
}
// 全做完才交回（结果按列表的顺序）。有一件出了错，或者等的人自己被取消了＝把还没做完的都取消，把错抛出去。
async function awaitAll(list) {
  const ts = items(list).slice();
  try {
    await pause((ok, bad) => { Promise.all(ts.map((t) => t.p)).then(ok, bad); return null; });
  } catch (e) {
    for (const t of ts) cancel(t);
    throw e;
  }
  return ts.map((t) => t.val);
}
// 谁先做完（成了或者出错）就用谁的；别的接着做。
function awaitAny(list) {
  const ts = items(list).slice();
  if (ts.length === 0) fail("“等最先的一个”的列表是空的");
  return pause((ok, bad) => { Promise.race(ts.map((t) => t.p)).then(ok, bad); return null; });
}
const cancelled = () => lineNow().cancelled;
// 一次只让一个做：按名字。别人在里面＝排队（先来先进）；自己已经在里面＝出错（不然会自己等自己）。
const gates = new Map();
function lockEnter(name) {
  const me = lineNow();
  let g = gates.get(name);
  if (!g) gates.set(name, (g = { owner: null, queue: [] }));
  if (g.owner === me) fail("「" + name + "」已经在“一次只让一个做”里面了，不能在里面再进一次");
  return pause((ok) => {
    if (g.owner === null && g.queue.length === 0) { g.owner = me; ok(name); return null; }
    const ticket = () => { g.owner = me; ok(name); };
    g.queue.push(ticket);
    return () => { const i = g.queue.indexOf(ticket); if (i >= 0) g.queue.splice(i, 1); };
  });
}
function lockLeave(name) {
  const g = gates.get(name);
  if (!g || g.owner !== lineNow()) return null;
  g.owner = null;
  const next = g.queue.shift();
  if (next) next();
  return null;
}

''';
