/// 规矩版本 2 的小库·“要等的事”的 JS 公共部分（Node 和浏览器共用；“现在是哪条线”怎么认、“开始做”怎么开各写各的）。
library;

/// 停下来等、等一会儿。要先有 `lineNow()`。
const String kRt2JsTaskA = r'''
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
''';

/// 等、等最多、取消、等全部、等最先、被取消了吗、一次只让一个做。要先有 `spawn` 用的那几样。
const String kRt2JsTaskB = r'''
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
