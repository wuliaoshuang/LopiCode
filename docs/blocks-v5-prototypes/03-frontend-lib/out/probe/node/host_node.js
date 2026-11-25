// 03 第 2 轮的前端宿主（Node）：只有“调度”和“写到错误输出”。接口清单见 natives.json。
"use strict";
const lc = require("./lc_lang.js");

// 这一段跑完以后做：浏览器和 Node 里都是“微任务”。
function tickDefer(fn) {
  queueMicrotask(() => {
    let out;
    try {
      out = lc.call(fn);
    } catch (e) {
      process.stderr.write("攒着做的事出错：" + (e && e.message) + "\n");
      return;
    }
    // 第 2 轮：这个函数不许“等”。交回了“稍后的结果”就说出来（并接住它的错，不让进程崩）。
    if (out instanceof Promise) {
      out.catch(() => {});
      process.stderr.write("攒着做的事出错：tick.defer 的函数里不能有要等的事\n");
    }
  });
  return null;
}

// 让攒着的事先跑完：等一个“宏任务”，微任务队列这时已经清空。
const tickWait = () => new Promise((done) => setTimeout(() => done(null), 0));

function logError(x) {
  process.stderr.write(lc.toText(x) + "\n");
  return null;
}

function ready() {}

module.exports = { tickDefer, tickWait, logError, ready };
