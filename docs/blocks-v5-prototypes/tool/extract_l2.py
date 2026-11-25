#!/usr/bin/env python3
"""把产品里现成的“标准库（小库）”源码原样抄出来，给原型当 L2 用。只读 lib/，不改它。

产品把每种语言的小库写成 Dart 文件里的一段原样文字（r'''...'''）。这个脚本把那段文字取出来写成能直接用的文件：
  l2/node/lc_runtime.js   ← lib/backend/runtime_node.dart
  l2/node/lc_lang.js      ← lib/backend/runtime_node_lang.dart ＋ runtime_node_func.dart
  l2/python/lc_runtime.py ← lib/backend/runtime_python.dart
  l2/python/lc_lang.py    ← lib/backend/runtime_python_lang.dart ＋ runtime_python_func.dart
用法：python3 extract_l2.py   （在 tool/ 目录里跑；抄出来的文件已经放在 l2/ 里，一般不用再跑）
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.normpath(os.path.join(HERE, "..", "..", "..", "lib", "backend"))


def raw(name):
    text = open(os.path.join(LIB, name), encoding="utf-8").read()
    blocks = re.findall(r"= r'''\n(.*?)''';", text, re.S)
    assert len(blocks) == 1, (name, len(blocks))
    return blocks[0]


def write(path, text):
    path = os.path.join(HERE, "l2", path)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("写好", os.path.relpath(path, HERE), len(text), "字")


write("node/lc_runtime.js", raw("runtime_node.dart"))
write("node/lc_lang.js", raw("runtime_node_lang.dart") + raw("runtime_node_func.dart"))
write("python/lc_runtime.py", raw("runtime_python.dart"))
write("python/lc_lang.py", raw("runtime_python_lang.dart") + raw("runtime_python_func.dart"))
