#!/usr/bin/env python3
"""逐行比对“检查程序的输出”和“事先手写的期望”。每行形如 `[编号] 名字：值`。
用法：python3 check_lines.py 期望.txt 实际.txt 名字
打印：通过几条、哪几条不一样（期望 / 实际各是什么）、实际里有没有多出来或缺的行。全过退出码 0。"""
import re
import sys

def load(path):
    out, order = {}, []
    for line in open(path, encoding='utf-8').read().split('\n'):
        if not line:
            continue
        m = re.match(r'\[([^\]]+)\] ', line)
        key = m.group(1) if m else '行:' + line
        if key in out:
            key = key + '（重复）'
        out[key] = line
        order.append(key)
    return out, order

exp, order = load(sys.argv[1])
act, act_order = load(sys.argv[2])
name = sys.argv[3]
bad = [k for k in order if act.get(k) != exp[k]]
extra = [k for k in act_order if k not in exp]
print('[%s] %d 条检查，%d 条等于手写的期望，%d 条不等%s' % (name, len(order), len(order) - len(bad), len(bad),
      '；另有 %d 行是期望里没有的' % len(extra) if extra else ''))
for k in bad:
    print('  [%s] 第 [%s] 条\n      期望：%s\n      实际：%s' % (name, k, exp[k], act.get(k, '（没有这一行）')))
for k in extra:
    print('  [%s] 多出来的行：%s' % (name, act[k]))
sys.exit(1 if bad or extra else 0)
