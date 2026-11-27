/// 规矩版本 2 的小库·Node·“要等的事”那一块（拼在 `lc2.js` 中间，见 rt2_node.dart）：这条线、等一会儿、开始做、等、
/// 等最多 / 等全部 / 等最先的一个、取消、一次只让一个做。规矩见 docs/blocks-v5-parts/B-gen-notes.md 第 16 节。只用 Node 自带的模块。
library;

import 'package:lopicode/lang/rt2_js_task.dart';

const String kRt2NodeTask =
    r'''
// —— 要等的事 ——
// “这条线”：一件事（主程序、一次“开始做”、一个请求）。Node 用自带的 AsyncLocalStorage 记着现在跑的是哪一条，
// 取消、“一次只让一个做”靠它认。wake：这条线正停在要等的地方时，叫醒它（让它抛“取消了”）的办法。
const lineStore = new (require("node:async_hooks").AsyncLocalStorage)();
const mainLine = { cancelled: false, wake: null };
const lineNow = () => lineStore.getStore() || mainLine;
const inLine = (f) => lineStore.run({ cancelled: false, wake: null }, f);
''' +
    kRt2JsTaskA +
    r'''
// 开始做一件事：马上开始（做到它第一件要等的事为止），拿到“稍后的结果”；出了错先记着，等它的时候再抛。
function spawn(f) {
  const t = { done: false, val: null, err: null, line: { cancelled: false, wake: null }, p: null };
  t.p = lineStore.run(t.line, async () => {
    try { t.val = await f(); return t.val; } catch (e) { t.err = e; throw e; } finally { t.done = true; }
  });
  t.p.catch(() => {});
  return t;
}
''' +
    kRt2JsTaskB;
