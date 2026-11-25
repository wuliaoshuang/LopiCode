#!/usr/bin/env python3
"""把产品现有一致性测试的请求样本（test/support/backend_conformance.dart 里的 conformanceCases，只读）
原样转成 cases.json，给这个原型当验收样本。转法是机械替换（Dart 的写法换成 Python 的写法再求值），不改任何请求和期望。
cases.json 已经生成好放在这里；产品那边的样本改了才需要重跑：python3 make_cases.py
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "..", "test", "support", "backend_conformance.dart"))

kJson = "application/json; charset=utf-8"
kText = "text/plain; charset=utf-8"
# 下面两个是从 Dart 文件里手抄的常量（kConformanceNasty、_nastyJson）。
NASTY = '引号"\'反斜杠\\换行\n制表\t${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完'
NASTY_JSON = r'''"引号\"'反斜杠\\换行\n制表\t${x}`</script><!--*/ #{y} %s 😀''' + '\u2028' + r'''\u0001完"'''
kConformanceNasty = NASTY


def _nested(depth):
    return "[" * depth + "]" * depth


def _nestedObjects(depth):
    return "".join('{"a":' if i % 2 == 0 else "[" for i in range(depth)) + "1" + "".join("}" if i % 2 == 0 else "]" for i in range(depth - 1, -1, -1))


def fill(s):
    s = s.replace("$_nastyJson", NASTY_JSON)
    s = re.sub(r"\$\{_nested\((\d+)\)\}", lambda m: _nested(int(m.group(1))), s)
    s = re.sub(r"\$\{_nestedObjects\((\d+)\)\}", lambda m: _nestedObjects(int(m.group(1))), s)
    assert "${_" not in s and "$_" not in s, s
    return s


def C(method, target, status, expect, body=None, bodyBytes=None, headers=None, type=kJson, pattern=None):
    c = {"method": method, "target": target, "status": status, "expect": fill(expect), "type": type}
    if body is not None:
        c["body"] = fill(body)
    if bodyBytes is not None:
        c["bodyBytes"] = bodyBytes
    if headers:
        c["headers"] = headers
    if pattern is not None:
        c["pattern"] = pattern
    return c


def T(method, target, status, expect, body=None, headers=None):
    return C(method, target, status, expect, body=body, headers=headers, type=kText)


def NONE(method, target, body=None):
    return C(method, target, 204, "", body=body, type=None)


text = open(SRC, encoding="utf-8").read()
start = text.index("final List<BeCase> conformanceCases = [")
end = text.index("\n];", start)
src = text[start + len("final List<BeCase> conformanceCases = ") : end + 2]
src = re.sub(r"^\s*//.*$", "", src, flags=re.M)
src = src.replace("const BeCase(", "C(").replace("BeCase(", "C(").replace("_none(", "NONE(").replace("_t(", "T(")
src = re.sub(r"(?<=[ (])(body|headers|bodyBytes|type|pattern):(?=\s)", r"\1=", src)
cases = eval(src)
logs = re.search(r"conformanceLogLines = \[(.*?)\];", text).group(1)
json.dump(cases, open(os.path.join(HERE, "cases.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=0)
json.dump(eval("[" + logs + "]"), open(os.path.join(HERE, "expected-logs.json"), "w", encoding="utf-8"), ensure_ascii=False)
print("转好 %d 条请求样本 → cases.json；期望的日志 %s → expected-logs.json" % (len(cases), logs))
