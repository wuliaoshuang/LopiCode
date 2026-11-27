// 浏览器目标“真跑”用的小工具：把页面程序和浏览器小库交给 Node 跑（不是真浏览器——`win` 是一个只有控制台和定时器的假窗口）。
// 输出的规矩照 Node 目标的样子：打印的每一行写到标准输出；没人接的错写一行“出错：…”、退出码 1；什么都没写过补一个空行。
import 'package:lopicode/lang/rt2_browser.dart';

import 'gen2_run.dart';

const String _harness = r'''
"use strict";
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/lc2.js", "utf8") + "\n" + fs.readFileSync(__dirname + "/program.js", "utf8") + "\nreturn [lcRuntime, lcProgram];";
const [lcRuntime, lcProgram] = new Function(src)();
let wrote = false, code = 0;
const out = (s) => { wrote = true; process.stdout.write(s + "\n"); };
const win = {
  console: { log: out, error: (s) => { code = 1; out(s); } },
  setTimeout, clearTimeout, setInterval, clearInterval,
};
const lc = lcRuntime(win);
Promise.resolve(lcProgram(lc, {})).then(() => { process.stdout.write(wrote ? "" : "\n", () => process.exit(code)); });
''';

/// 跑一份页面程序（`lcProgram` 函数的全文），交回标准输出和退出码。
Future<Gen2Run> browserRunProgram(String program) => gen2RunFiles('node', {'main.js': _harness, 'lc2.js': kRt2BrowserSource, 'program.js': program});
