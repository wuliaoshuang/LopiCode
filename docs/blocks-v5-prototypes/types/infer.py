#!/usr/bin/env python3
"""类型推断规则的原型：读 prog.lc（S 表达式写的语法树），按 B-type-system.md 第 4 节的规则自动推断，
打印每个函数的签名、每个变量的类型，以及 T 开头的类型错误。只用来验证规则说得清、算得出，不是产品代码。

用法：python3 infer.py 某目录/prog.lc
覆盖了哪些规则、没覆盖哪些，见同目录 README.md。
"""
import re
import sys

# ───────── 读 S 表达式 ─────────
TOK = re.compile(r'\s*(;[^\n]*|\(|\)|"[^"]*"|[^\s()";]+)')


def parse(src):
    toks = [t for t in TOK.findall(src) if not t.startswith(";")]
    pos = 0

    def rd():
        nonlocal pos
        t = toks[pos]
        pos += 1
        if t == "(":
            out = []
            while toks[pos] != ")":
                out.append(rd())
            pos += 1
            return out
        return t

    out = []
    while pos < len(toks):
        out.append(rd())
    return out


# ───────── 类型 ─────────
INT, FLT, TXT, BOOL, NUL, ANY, NEVER = ("整数",), ("小数",), ("文字",), ("是否",), ("空",), ("任意",), ("永不",)
MAXI = 9007199254740991


def opt(t):
    return t if t[0] in ("可空", "任意", "永不", "空") else ("可空", t)


def strip(t):
    return t[1] if t[0] == "可空" else t


def show(t, top=True):
    k = t[0]
    if k in ("整数", "小数", "文字", "是否", "空", "任意", "永不"):
        return k
    if k == "可空":
        s = show(t[1], False)
        return ("(" + s + ")" if t[1][0] == "函数" else s) + "?"
    if k == "列表":
        return "列表〈" + show(t[1]) + "〉"
    if k == "字典":
        return "字典〈" + show(t[1]) + "〉"
    if k == "函数":
        return "(" + ", ".join(show(p) for p in t[1]) + ") → " + show(t[2])
    if k == "名":
        return t[1] + ("〈" + ", ".join(show(a) for a in t[2]) + "〉" if t[2] else "")
    if k == "变":
        return t[1]
    if k == "洞":
        return "待定"
    return str(t)


class Infer:
    def __init__(self, prog):
        self.prog = prog
        self.records, self.enums, self.variants, self.vcase = {}, {}, {}, {}
        self.ifaces, self.classes, self.funcs, self.alias = {}, {}, {}, {}
        self.VT, self.RT, self.PT, self.HB = {}, {}, {}, {}  # 变量 / 返回值 / 没标的参数 / 待定的洞
        self.order, self.sigorder = [], []
        self.errors, self.final, self.changed = [], False, False
        self.main = []
        for d in prog:
            h = d[0]
            if h == "记录":
                self.records[d[1]] = [(f[0], f[1]) for f in d[2:]]
            elif h == "枚举":
                self.enums[d[1]] = d[2:]
            elif h == "变体":
                self.variants[d[1]] = {c[0]: [(f[0], f[1]) for f in c[1:]] for c in d[2:]}
                for c in d[2:]:
                    self.vcase[c[0]] = d[1]
            elif h == "接口":
                self.ifaces[d[1]] = {m[0]: m for m in d[2:]}
            elif h == "别名":
                self.alias[d[1]] = d[2]
            elif h == "类":
                c = dict(name=d[1], tv=[], parent=None, impl=[], fields=[], ctor=None, methods={})
                for x in d[2:]:
                    if x == "可继承":
                        continue
                    if x[0] == "泛型":
                        c["tv"] = x[1:]
                    elif x[0] == "继承":
                        c["parent"] = x[1]
                    elif x[0] == "实现":
                        c["impl"] = x[1:]
                    elif x[0] == "字段":
                        c["fields"].append(x)
                    elif x[0] == "创建":
                        c["ctor"] = x
                    elif x[0] == "方法":
                        c["methods"][x[1]] = self.fdecl(x, d[1] + "." + x[1], c["tv"])
                self.classes[d[1]] = c
            elif h == "函数":
                self.funcs[d[1]] = self.fdecl(d, d[1], [])
            elif h == "主":
                self.main = d[1:]

    def fdecl(self, d, key, ctv):
        i = 2
        tv, cons = list(ctv), {}
        if isinstance(d[i], list) and d[i] and d[i][0] == "泛型":
            for x in d[i][1:]:
                if isinstance(x, list):
                    tv.append(x[0])
                    cons[x[0]] = x[1]
                else:
                    tv.append(x)
            i += 1
        params = [(p, None) if isinstance(p, str) else (p[0], p[1]) for p in d[i]]
        i += 1
        ret = None
        if i < len(d) and d[i] == "->":
            ret = d[i + 1]
            i += 2
        self.sigorder.append(key)
        return dict(key=key, tv=tv, own=[t for t in tv if t not in ctv], cons=cons, params=params, ret=ret, body=d[i:])

    # ───────── 类型的写法 → 类型 ─────────
    def ty(self, s, tv=()):
        if isinstance(s, str):
            if s in ("整数", "小数", "文字", "是否", "空", "任意"):
                return (s,)
            if s in tv:
                return ("变", s)
            if s in self.alias:
                return self.ty(self.alias[s], tv)
            return ("名", s, ())
        h = s[0]
        if h == "可空":
            return opt(self.ty(s[1], tv))
        if h in ("列表", "字典"):
            return (h, self.ty(s[1], tv))
        if h == "函数":
            return ("函数", tuple(self.ty(p, tv) for p in s[1]), self.ty(s[2], tv))
        return ("名", h, tuple(self.ty(a, tv) for a in s[1:]))

    def res(self, t):  # 把已经定下来的“洞”换成它的类型
        k = t[0]
        if k == "洞":
            b = self.HB.get(t[1], NEVER)
            return t if b == NEVER else self.res(b)
        if k in ("可空",):
            return opt(self.res(t[1]))
        if k in ("列表", "字典"):
            return (k, self.res(t[1]))
        if k == "函数":
            return ("函数", tuple(self.res(p) for p in t[1]), self.res(t[2]))
        if k == "名":
            return ("名", t[1], tuple(self.res(a) for a in t[2]))
        return t

    def subst(self, t, b):
        k = t[0]
        if k == "变":
            return b.get(t[1], t)
        if k == "可空":
            return opt(self.subst(t[1], b))
        if k in ("列表", "字典"):
            return (k, self.subst(t[1], b))
        if k == "函数":
            return ("函数", tuple(self.subst(p, b) for p in t[1]), self.subst(t[2], b))
        if k == "名":
            return ("名", t[1], tuple(self.subst(a, b) for a in t[2]))
        return t

    def supers(self, name):  # 一个类的所有“上面”：父类链 + 实现的接口
        out, c = [], self.classes.get(name)
        while c:
            out.append(c["name"])
            out += c["impl"]
            c = self.classes.get(c["parent"])
        return out

    def join(self, a, b):
        a, b = self.res(a), self.res(b)
        if a == b:
            return a
        if a == NEVER or a[0] == "洞":
            return b
        if b == NEVER or b[0] == "洞":
            return a
        if ANY in (a, b):
            return ANY
        if {a, b} == {INT, FLT}:
            return FLT
        if a == NUL:
            return opt(b)
        if b == NUL:
            return opt(a)
        if a[0] == "可空" or b[0] == "可空":
            return opt(self.join(strip(a), strip(b)))
        if a[0] == b[0] == "函数" and len(a[1]) == len(b[1]):
            return ("函数", tuple(self.join(x, y) for x, y in zip(a[1], b[1])), self.join(a[2], b[2]))
        if a[0] == b[0] and a[0] in ("列表", "字典"):
            ia, ib = a[1], b[1]
            if ia[0] == "洞" or ia == NEVER:
                return b
            if ib[0] == "洞" or ib == NEVER:
                return a
            return ANY  # 两个都已经定下来、又不一样的列表：合不到一起
        if a[0] == b[0] == "名":
            sa, sb = self.supers(a[1]), self.supers(b[1])
            for s in sa:  # 最近的公共父类
                if s in sb and s in self.classes:
                    return ("名", s, ())
            both = [s for s in sa if s in sb and s in self.ifaces]
            if len(set(both)) == 1:  # 正好共同实现一个接口
                return ("名", both[0], ())
        return ANY

    def ok(self, src, dst):  # src 能不能放进要 dst 的地方
        src, dst = self.res(src), self.res(dst)
        if src == dst or dst == ANY or src in (NEVER, ANY) or src[0] == "洞" or dst[0] == "洞":
            return True  # 任意 → 确定类型：允许，生成一次检查
        if src == INT and dst == FLT:
            return True
        if dst[0] == "可空":
            return src == NUL or self.ok(strip(src), dst[1])
        if src[0] == "可空":
            return False
        if src[0] == dst[0] == "名":
            if src[1] != dst[1]:
                return dst[1] in self.supers(src[1])
            return all(self.same(x, y) for x, y in zip(src[2], dst[2]))
        if src[0] == dst[0] == "函数" and len(src[1]) == len(dst[1]):
            return all(self.ok(d, s) for s, d in zip(src[1], dst[1])) and (dst[2] == NUL or self.ok(src[2], dst[2]))
        if src[0] == dst[0] and src[0] in ("列表", "字典"):
            return self.same(src[1], dst[1])
        return False

    def same(self, a, b):
        a, b = self.res(a), self.res(b)
        return a == b or a[0] == "洞" or b[0] == "洞" or a == NEVER or b == NEVER

    def unify(self, pat, act, b):  # 用实际类型 act 去定 pat 里的类型变量和洞
        act = self.res(act)
        if act == NEVER:
            return
        if pat[0] == "变" and pat[1] in b:
            b[pat[1]] = self.join(b[pat[1]], act)
        elif pat[0] == "洞":
            self.bind(pat[1], act)
        elif act[0] == "洞":
            p = self.res(self.subst(pat, b))
            if not self.has_open(p):
                self.bind(act[1], p)
        elif pat[0] == "可空":
            self.unify(pat[1], strip(act) if act != NUL else NEVER, b)
        elif pat[0] in ("列表", "字典") and act[0] == pat[0]:
            self.unify(pat[1], act[1], b)
        elif pat[0] == "函数" and act[0] == "函数" and len(pat[1]) == len(act[1]):
            for p, a in zip(pat[1], act[1]):
                self.unify(p, a, b)
            self.unify(pat[2], act[2], b)
        elif pat[0] == "名" and act[0] == "名" and pat[1] == act[1]:
            for p, a in zip(pat[2], act[2]):
                self.unify(p, a, b)

    def has_open(self, t):
        if t[0] in ("变", "洞") or t == NEVER:
            return True
        return any(self.has_open(x) for x in t[1:] if isinstance(x, tuple) and x and isinstance(x[0], str) and x[0] in
                   ("整数", "小数", "文字", "是否", "空", "任意", "永不", "可空", "列表", "字典", "函数", "名", "变", "洞")) or \
            any(self.has_open(y) for x in t[1:] if isinstance(x, tuple) and x and isinstance(x[0], tuple) for y in x)

    def bind(self, hid, t):
        old = self.HB.get(hid, NEVER)
        new = self.join(old, t)
        if new != old:
            self.HB[hid] = new
            self.changed = True

    def err(self, code, where, msg):
        if self.final:
            e = f"{code} {where}：{msg}"
            if e not in self.errors:
                self.errors.append(e)

    # ───────── 变量表 ─────────
    def note(self, sc, name, t, declared=None):
        key = self.find(sc, name) if declared is None and self.find(sc, name) else (sc["key"], name)
        if key not in self.VT:
            self.VT[key] = dict(t=NEVER, fixed=False)
            if not sc.get("lam"):
                self.order.append(key)
        v = self.VT[key]
        if declared is not None:
            v["t"], v["fixed"] = declared, True
        if v["fixed"]:
            if not self.ok(t, v["t"]):
                self.err("T01", sc["fn"], f"「{name}」是{show(self.res(v['t']))}，放进来的是{show(self.res(t))}")
            self.unify(v["t"], t, {})
            return
        new = self.join(v["t"], t)
        if new != v["t"]:
            v["t"] = new
            self.changed = True

    def find(self, sc, name):
        while sc:
            if (sc["key"], name) in self.VT and name in sc["names"]:
                return (sc["key"], name)
            sc = sc["parent"]
        return None

    def declare(self, sc, name, t, declared=None):
        sc["names"].add(name)
        self.note(sc, name, t, declared if declared is not None else None)
        sc["nn"].discard(name)

    def scope(self, key, fn, parent=None, lam=False, tv=(), this=None):
        return dict(key=key, fn=fn, parent=parent, lam=lam, names=set(), nn=set(), tv=tuple(tv) if tv else (parent["tv"] if parent else ()),
                    this=this if this else (parent["this"] if parent else None), rets=[], cons=parent["cons"] if parent else {},
                    reassigned=parent["reassigned"] if parent else set())

    # ───────── 式子 ─────────
    def num(self, sc, op, ts):
        ts = [self.res(t) for t in ts]
        for t in ts:
            if t[0] == "可空":
                self.err("T02", sc["fn"], f"{op}的一边可能是空，要先判断“不是空”才能算")
                return NEVER
        if any(t == NEVER or t[0] == "洞" for t in ts):
            return NEVER
        if any(t == ANY for t in ts):
            return ANY
        for t in ts:
            if t not in (INT, FLT):
                self.err("T06", sc["fn"], f"{op}的两边要数字，这里有一边是{show(t)}")
                return NEVER
        return None

    def ex(self, sc, e, want=None):
        t = self.ex0(sc, e, want)
        return t

    def ex0(self, sc, e, want):
        if isinstance(e, str):
            if e.startswith('"'):
                return TXT
            if re.fullmatch(r"-?\d+", e):
                if abs(int(e)) > MAXI:
                    self.err("T16", sc["fn"], f"{e} 太大了，整数最大只能到 {MAXI}")
                return INT
            if re.fullmatch(r"-?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?", e):
                return FLT
            if e == "空":
                return NUL
            if e in ("是", "否"):
                return BOOL
            k = self.find(sc, e)
            if k:
                t = self.res(self.VT[k]["t"])
                return strip(t) if self.narrowed(sc, e) else t
            if e in self.funcs:
                f = self.funcs[e]
                return ("函数", tuple(self.ptype(f, i) for i in range(len(f["params"]))), self.rtype(f))
            self.err("T08", sc["fn"], f"没有叫「{e}」的变量")
            return NEVER
        h, a = e[0], e[1:]
        if h in ("+", "-", "*"):
            ts = [self.ex(sc, x) for x in a]
            r = self.num(sc, {"+": "加法", "-": "减法", "*": "乘法"}[h], ts)
            return r if r is not None else (INT if all(self.res(t) == INT for t in ts) else FLT)
        if h == "/":
            r = self.num(sc, "除法", [self.ex(sc, x) for x in a])
            return r if r is not None else FLT
        if h in ("整除", "余"):
            ts = [self.res(self.ex(sc, x)) for x in a]
            r = self.num(sc, h, ts)
            if r is None and FLT in ts:
                self.err("T06", sc["fn"], f"“{h}”的两边要整数，这里有一边是小数")
            return r if r is not None else INT
        if h in ("<", ">", "<=", ">="):
            ts = [self.res(self.ex(sc, x)) for x in a]
            for t in ts:
                if t[0] == "可空":
                    self.err("T02", sc["fn"], "比大小的一边可能是空，要先判断“不是空”才能比")
                elif t[0] == "变" and sc["cons"].get(t[1]) != "能比较":
                    self.err("T05", sc["fn"], f"{t[1]} 没有说明“能比大小”，不能比")
                elif t not in (INT, FLT, TXT, ANY, NEVER) and t[0] not in ("变", "洞"):
                    self.err("T06", sc["fn"], f"只有数字和文字能比大小，这里有一边是{show(t)}")
            if TXT in ts and (INT in ts or FLT in ts):
                self.err("T06", sc["fn"], "数字和文字不能互相比大小")
            return BOOL
        if h in ("==", "!="):
            for x in a:
                self.ex(sc, x)
            return BOOL
        if h in ("且", "或"):
            keep = set(sc["nn"])
            for i, x in enumerate(a):
                self.cond(sc, x)
                if h == "且":
                    sc["nn"] |= self.facts(x, True)
            sc["nn"] = keep
            return BOOL
        if h == "非":
            self.cond(sc, a[0])
            return BOOL
        if h in ("是空", "非空"):
            self.ex(sc, a[0])
            return BOOL
        if h == "连":
            for x in a:
                self.ex(sc, x)
            return TXT
        if h == "文":
            self.ex(sc, a[0])
            return TXT
        if h == "取整":
            self.arg(sc, a[0], FLT, "“取整”里的数")
            return INT
        if h == "拼":
            self.arg(sc, a[0], ("列表", TXT), "“拼起来”的列表")
            self.arg(sc, a[1], TXT, "“拼起来”的分隔")
            return TXT
        if h in ("长", "文长"):
            self.ex(sc, a[0])
            return INT
        if h == "标":
            w = self.ty(a[0], sc["tv"])
            t = self.ex(sc, a[1], w)
            if not self.ok(t, w):
                self.err("T01", sc["fn"], f"这里标的是{show(w)}，放进来的是{show(self.res(t))}")
            return w
        if h == "转":
            self.ex(sc, a[1])
            return self.ty(a[0], sc["tv"])
        if h == "列":
            if want and self.res(want)[0] == "列表":
                for x in a:
                    self.arg(sc, x, self.res(want)[1], "列表里的一项")
                return self.res(want)
            el, lams = NEVER, []
            for x in a:
                if isinstance(x, list) and x[0] in ("λ", "λ块"):
                    lams.append(x)
                else:
                    el = self.join(el, self.ex(sc, x))
            for x in lams:  # 匿名函数放到最后看，拿别的项的类型当线索
                el = self.join(el, self.ex(sc, x, el if el != NEVER else None))
            return ("列表", el if (a and el != NEVER) else ("洞", id(e)))
        if h == "典":
            if want and self.res(want)[0] == "字典":
                for x in a:
                    self.arg(sc, x[1], self.res(want)[1], "字典里的一项")
                return self.res(want)
            el = NEVER
            for x in a:
                el = self.join(el, self.ex(sc, x[1]))
            return ("字典", el if (a and el != NEVER) else ("洞", id(e)))
        if h == "项":
            t = self.nonnull(sc, a[0], "列表")
            self.arg(sc, a[1], INT, "位置")
            return t[1] if t[0] == "列表" else (ANY if t == ANY else NEVER)
        if h == "取":
            t = self.nonnull(sc, a[0], "字典")
            self.arg(sc, a[1], TXT, "字典的键")
            return opt(t[1]) if t[0] == "字典" else (ANY if t == ANY else NEVER)
        if h in ("有键",):
            self.ex(sc, a[0])
            return BOOL
        if h == "键们":
            self.ex(sc, a[0])
            return ("列表", TXT)
        if h == "或空":
            t = self.res(self.ex(sc, a[0]))
            d = self.ex(sc, a[1])
            if t == NEVER:
                return NEVER
            if not self.ok(d, strip(t)) and not self.ok(strip(t), d):
                self.err("T01", sc["fn"], f"“如果是空就用”后面要{show(strip(t))}，放进来的是{show(self.res(d))}")
            return self.join(strip(t), d)
        if h == "必有":
            return strip(self.res(self.ex(sc, a[0])))
        if h == "切":
            return ("列表", TXT)
        if h == "截":
            return TXT
        if h == "开头是":
            return BOOL
        if h == "解析整数":
            self.arg(sc, a[0], TXT, "“变成整数”里的文字")
            return opt(INT)
        if h == "码点们":
            return ("列表", INT)
        if h == "试算":
            self.ex(sc, a[0])
            return TXT
        if h.startswith("任"):
            for x in a:
                self.ex(sc, x)
            return ANY
        if h in ("λ", "λ块"):
            return self.lam(sc, e, want)
        if h == "调":
            return self.call(sc, a[0], a[1:])
        if h == "新记":
            return self.newrec(sc, a[0], a[1:])
        if h == "改记":
            t = self.res(self.ex(sc, a[0]))
            if t[0] == "名" and t[1] in self.records:
                fs = dict(self.records[t[1]])
                for f in a[1:]:
                    if f[0] not in fs:
                        self.err("T04", sc["fn"], f"「{t[1]}」没有「{f[0]}」这一项")
                    else:
                        self.arg(sc, f[1], self.ty(fs[f[0]]), f"「{t[1]}」的「{f[0]}」")
            return t
        if h == ".":
            return self.field(sc, a[0], a[1])
        if h == "这":
            return sc["this"]
        if h == "枚":
            if a[1] not in self.enums[a[0]]:
                self.err("T08", sc["fn"], f"「{a[0]}」里没有「{a[1]}」")
            return ("名", a[0], ())
        if h == "造":
            v = self.vcase[a[0]]
            fs = self.variants[v][a[0]]
            if len(fs) != len(a) - 1:
                self.err("T07", sc["fn"], f"「{a[0]}」要 {len(fs)} 个值，给了 {len(a) - 1} 个")
            for (fn_, ft), x in zip(fs, a[1:]):
                self.arg(sc, x, self.ty(ft), f"「{a[0]}」的「{fn_}」")
            return ("名", v, ())
        if h == "新":
            return self.new(sc, e)
        if h == "发":
            return self.send(sc, a[0], a[1], a[2:])
        if h == "父":
            c = self.classes[self.classes[sc["this"][1]]["parent"]]
            return self.msig(c, a[0], ())[1]
        if h == "是":
            self.ex(sc, a[1])
            return BOOL
        raise SystemExit(f"原型不认识的式子：{h}")

    def narrowed(self, sc, name):
        return name in sc["nn"]

    def nonnull(self, sc, e, what):
        t = self.res(self.ex(sc, e))
        if t[0] == "可空":
            nm = e if isinstance(e, str) else "这个值"
            self.err("T02", sc["fn"], f"「{nm}」可能是空，要先判断“不是空”才能当{what}用")
            return strip(t)
        return t

    def arg(self, sc, e, want, where):
        t = self.res(self.ex(sc, e, want))
        w = self.res(want)
        if not self.ok(t, w):
            if t[0] == "可空" and self.ok(t[1], w):
                nm = f"「{e}」" if isinstance(e, str) else "这个值"
                self.err("T02", sc["fn"], f"{where}要{show(w)}，{nm}可能是空，要先判断“不是空”")
            else:
                self.err("T01", sc["fn"], f"{where}要{show(w)}，放进来的是{show(t)}")
        self.unify(want, t, {})
        return t

    def cond(self, sc, e):
        t = self.res(self.ex(sc, e))
        if t not in (BOOL, ANY, NEVER):
            self.err("T09", sc["fn"], f"这里要“是/否”，放进来的是{show(t)}")

    def facts(self, e, truth):  # 条件成立（或不成立）时，哪些变量肯定不是空
        if not isinstance(e, list):
            return set()
        h = e[0]
        if h == "非空" and isinstance(e[1], str):
            return {e[1]} if truth else set()
        if h == "是空" and isinstance(e[1], str):
            return set() if truth else {e[1]}
        if h == "!=" and e[2] == "空" and isinstance(e[1], str):
            return {e[1]} if truth else set()
        if h == "==" and e[2] == "空" and isinstance(e[1], str):
            return set() if truth else {e[1]}
        if h == "非":
            return self.facts(e[1], not truth)
        if h == "且" and truth or h == "或" and not truth:
            out = set()
            for x in e[1:]:
                out |= self.facts(x, truth)
            return out
        return set()

    def lam(self, sc, e, want):
        want = self.res(want) if want else None
        ps = [(p, None) if isinstance(p, str) else (p[0], p[1]) for p in e[1]]
        ls = self.scope(("λ", id(e)), sc["fn"], parent=sc, lam=True)
        # 外面“判断过不是空”的变量带进匿名函数：只带那些在整个函数里从没被“改”过的（被改过的，等匿名函数真跑的时候可能又是空了）
        ls["nn"] = {n for n in sc["nn"] if n not in sc["reassigned"]}
        pts = []
        for i, (n, t) in enumerate(ps):
            if t is not None:
                pt = self.ty(t, sc["tv"])
            elif want and want[0] == "函数" and i < len(want[1]):
                pt = want[1][i]  # 没标的参数：看上下文
            else:
                pt = ANY  # 没有上下文：任意
            pts.append(pt)
            ls["names"].add(n)
            self.VT[(ls["key"], n)] = dict(t=pt, fixed=True)
        if want and want[0] == "函数" and len(want[1]) != len(ps):
            self.err("T07", sc["fn"], f"这里要一个收 {len(want[1])} 个参数的函数，给的收 {len(ps)} 个")
        if e[0] == "λ":
            rt = self.ex(ls, e[2], want[2] if want and want[0] == "函数" else None)
        else:
            self.block(ls, e[2:])
            rt = NUL
            for r in ls["rets"]:
                rt = r if rt == NUL else self.join(rt, r)
        return ("函数", tuple(pts), rt)

    def ptype(self, f, i):
        n, t = f["params"][i]
        if t is not None:
            return self.ty(t, f["tv"])
        return self.PT.get((f["key"], i), NEVER)

    def rtype(self, f):
        if f["ret"] is not None:
            return self.ty(f["ret"], f["tv"])
        return self.RT.get(f["key"], NEVER)

    def apply(self, sc, name, pts, rt, tvs, cons, args, pre=None, f=None):
        if len(pts) != len(args):
            self.err("T07", sc["fn"], f"「{name}」要 {len(pts)} 个参数，给了 {len(args)} 个")
            return NEVER
        b = {v: NEVER for v in tvs}
        if pre:
            b.update(pre)
        got = [None] * len(args)
        islam = [isinstance(x, list) and x[0] in ("λ", "λ块") for x in args]
        for i, x in enumerate(args):  # 第一步：先看不是匿名函数的参数
            if not islam[i]:
                got[i] = self.res(self.ex(sc, x, self.subst(pts[i], b) if not self.has_open(self.subst(pts[i], b)) else None))
                self.unify(pts[i], got[i], b)
        for again in (1, 2):  # 第二步：带着已经定下来的类型去看匿名函数。
            before = dict(b)  # 看完以后类型变量要是变宽了（整数 → 小数），带着变宽后的类型再看一遍（第一轮发现 F13）
            for i, x in enumerate(args):
                if islam[i]:
                    got[i] = self.res(self.ex(sc, x, self.subst(pts[i], b)))
                    self.unify(pts[i], got[i], b)
            if b == before:
                break
        for i, x in enumerate(args):
            want = self.res(self.subst(pts[i], b))
            if f is not None and f["params"][i][1] is None:  # 没标类型的参数：把这次调用的实参类型记下来
                old = self.PT.get((f["key"], i), NEVER)
                new = self.join(old, got[i])
                if new != old:
                    self.PT[(f["key"], i)] = new
                    self.changed = True
                continue
            if not self.ok(got[i], want):
                if got[i][0] == want[0] == "函数" and len(got[i][1]) != len(want[1]):
                    continue  # 参数个数不对已经报过 T07，不再连带报一条 T01（一处错只说一句）
                if got[i][0] == "可空" and self.ok(got[i][1], want):
                    nm = f"「{x}」" if isinstance(x, str) else "这个值"
                    self.err("T02", sc["fn"], f"「{name}」的第 {i + 1} 个参数要{show(want)}，{nm}可能是空，要先判断“不是空”")
                else:
                    self.err("T01", sc["fn"], f"「{name}」的第 {i + 1} 个参数要{show(want)}，放进来的是{show(got[i])}")
        for v, c in cons.items():
            t = self.res(b.get(v, NEVER))
            if c == "能比较" and t not in (INT, FLT, TXT, NEVER, ANY) and t[0] not in ("变", "洞"):
                self.err("T05", sc["fn"], f"「{name}」要的是能比大小的东西（数字或文字），{show(t)}不能比大小")
        return self.res(self.subst(rt, b))

    BUILTIN = {
        "映射": (("T", "U"), [("列表", ("变", "T")), ("函数", (("变", "T"),), ("变", "U"))], ("列表", ("变", "U"))),
        "筛选": (("T",), [("列表", ("变", "T")), ("函数", (("变", "T"),), BOOL)], ("列表", ("变", "T"))),
        "归并": (("T", "A"), [("列表", ("变", "T")), ("变", "A"), ("函数", (("变", "A"), ("变", "T")), ("变", "A"))], ("变", "A")),
    }

    def call(self, sc, fe, args):
        if isinstance(fe, str) and fe in self.BUILTIN and not self.find(sc, fe):
            tv, pts, rt = self.BUILTIN[fe]
            return self.apply(sc, fe, pts, rt, tv, {}, args)
        if isinstance(fe, str) and fe in self.funcs and not self.find(sc, fe):
            f = self.funcs[fe]
            pts = [self.ptype(f, i) for i in range(len(f["params"]))]
            return self.apply(sc, fe, pts, self.rtype(f), f["tv"], f["cons"], args, f=f)
        t = self.res(self.ex(sc, fe))
        if t[0] == "函数":
            return self.apply(sc, fe if isinstance(fe, str) else "这个函数", list(t[1]), t[2], (), {}, args)
        for x in args:
            self.ex(sc, x)
        if t not in (ANY, NEVER):
            self.err("T01", sc["fn"], f"「{fe}」是{show(t)}，不是函数，不能调用")
        return t

    def newrec(self, sc, name, fields):
        if name not in self.records:
            self.err("T08", sc["fn"], f"没有叫「{name}」的记录")
            return NEVER
        fs = dict(self.records[name])
        given = [f[0] for f in fields]
        miss = [n for n in fs if n not in given]
        if miss:
            self.err("T04", sc["fn"], f"新建「{name}」还缺：{'、'.join(miss)}")
        for f in fields:
            if f[0] not in fs:
                self.err("T04", sc["fn"], f"「{name}」没有「{f[0]}」这一项")
            else:
                self.arg(sc, f[1], self.ty(fs[f[0]]), f"「{name}」的「{f[0]}」")
        return ("名", name, ())

    def cfield(self, c, name):
        while c:
            for f in c["fields"]:
                if f[1] == name:
                    return self.ty(f[2], c["tv"]), c
            c = self.classes.get(c["parent"])
        return None, None

    def field(self, sc, oe, name):
        t = self.nonnull(sc, oe, "有字段的东西")
        if t[0] == "名" and t[1] in self.records:
            fs = dict(self.records[t[1]])
            if name in fs:
                return self.ty(fs[name])
        elif t[0] == "名" and t[1] in self.classes:
            ft, c = self.cfield(self.classes[t[1]], name)
            if ft:
                return self.res(self.subst(ft, dict(zip(c["tv"], t[2]))))
        elif t in (ANY, NEVER):
            return t
        self.err("T08", sc["fn"], f"{show(t)}没有「{name}」这一项")
        return NEVER

    def msig(self, c, name, targs):
        while c:
            if name in c["methods"]:
                f = c["methods"][name]
                b = dict(zip(c["tv"], targs))
                return [self.subst(self.ptype(f, i), b) for i in range(len(f["params"]))], self.subst(self.rtype(f), b), f
            c = self.classes.get(c["parent"])
        return None

    def send(self, sc, oe, name, args):
        t = self.nonnull(sc, oe, "对象")
        if t[0] == "名" and t[1] in self.classes:
            m = self.msig(self.classes[t[1]], name, t[2])
            if m:
                return self.apply(sc, name, m[0], m[1], (), {}, args, f=m[2])
        elif t[0] == "名" and t[1] in self.ifaces and name in self.ifaces[t[1]]:
            m = self.ifaces[t[1]][name]
            return self.apply(sc, name, [self.ty(p[1]) for p in m[1]], self.ty(m[2]), (), {}, args)
        elif t in (ANY, NEVER):
            for x in args:
                self.ex(sc, x)
            return t
        self.err("T08", sc["fn"], f"{show(t)}没有「{name}」这个方法")
        return NEVER

    def new(self, sc, e):
        spec, args = e[1], e[2:]
        name = spec if isinstance(spec, str) else spec[0]
        c = self.classes[name]
        if isinstance(spec, list):
            targs = tuple(self.ty(x, sc["tv"]) for x in spec[1:])
        else:
            targs = tuple(("洞", (id(e), v)) for v in c["tv"])  # 没写〈…〉：先留着，看后面怎么用
        cc = c
        while cc and not cc["ctor"]:
            cc = self.classes.get(cc["parent"])
        ps = cc["ctor"][1] if cc else []
        b = dict(zip(c["tv"], targs))
        self.apply(sc, "新建" + name, [self.subst(self.ty(p[1], c["tv"]), b) for p in ps], NUL, (), {}, args)
        return self.res(("名", name, targs))

    # ───────── 语句 ─────────
    def exits(self, body):
        return bool(body) and isinstance(body[-1], list) and body[-1][0] in ("返回", "抛出")

    def block(self, sc, body):
        for s in body:
            self.st(sc, s)

    def st(self, sc, s):
        h, a = s[0], s[1:]
        if h in ("设", "常"):
            if len(a) == 3:
                w = self.ty(a[1], sc["tv"])
                t = self.ex(sc, a[2], w)
                self.declare(sc, a[0], t, declared=w)
            else:
                self.declare(sc, a[0], self.ex(sc, a[1]))
        elif h == "改":
            k = self.find(sc, a[0])
            if not k:
                self.err("T08", sc["fn"], f"没有叫「{a[0]}」的变量")
                return
            t = self.ex(sc, a[1], self.VT[k]["t"] if self.VT[k]["fixed"] else None)
            owner = sc
            while a[0] not in owner["names"]:
                owner = owner["parent"]
            self.note(owner, a[0], t)
            if self.res(t)[0] == "可空" or self.res(t) == NUL:
                sc["nn"].discard(a[0])
            elif owner is sc and self.res(self.VT[k]["t"])[0] == "可空":
                sc["nn"].add(a[0])  # 刚放进去一个肯定不是空的值
        elif h == "加项":
            t = self.nonnull(sc, a[0], "列表")
            if t[0] == "列表":
                self.arg(sc, a[1], t[1], "往列表里加的东西")
            else:
                self.ex(sc, a[1])
        elif h == "删末项":
            self.ex(sc, a[0])
        elif h == "存":
            t = self.nonnull(sc, a[0], "字典")
            self.arg(sc, a[1], TXT, "字典的键")
            if t[0] == "字典":
                self.arg(sc, a[2], t[1], "往字典里存的东西")
            else:
                self.ex(sc, a[2])
        elif h == "删键":
            self.ex(sc, a[0])
        elif h == "改项":
            t = self.nonnull(sc, a[0], "列表")
            self.arg(sc, a[1], INT, "位置")
            self.arg(sc, a[2], t[1] if t[0] == "列表" else ANY, "往列表里放的东西")
        elif h == "改字段":
            t = self.res(self.ex(sc, a[0]))
            if t[0] == "名" and t[1] in self.records:
                self.err("T10", sc["fn"], f"记录「{t[1]}」建好以后不能改，用“复制并改”")
                return
            ft = self.field(sc, a[0], a[1])
            self.arg(sc, a[2], ft, f"「{a[1]}」")
        elif h == "如果":
            self.cond(sc, a[0])
            keep = set(sc["nn"])
            then = a[1][1:]
            els = a[2][1:] if len(a) > 2 else []
            sc["nn"] = keep | self.facts(a[0], True)
            self.block(sc, then)
            n1 = set(sc["nn"])
            sc["nn"] = keep | self.facts(a[0], False)
            self.block(sc, els)
            n2 = set(sc["nn"])
            if self.exits(then) and self.exits(els):
                sc["nn"] = keep
            elif self.exits(then):
                sc["nn"] = n2
            elif self.exits(els):
                sc["nn"] = n1
            else:
                sc["nn"] = n1 & n2
        elif h == "当":
            self.cond(sc, a[0])
            self.loop(sc, a[1:])
        elif h == "每个":
            t = self.nonnull(sc, a[1], "列表")
            self.declare(sc, a[0], t[1] if t[0] == "列表" else (ANY if t == ANY else NEVER))
            if t[0] not in ("列表", "任意", "永不"):
                self.err("T01", sc["fn"], f"“每个”后面要列表，放进来的是{show(t)}")
            self.loop(sc, a[2:])
        elif h == "每对":
            t = self.nonnull(sc, a[2], "字典")
            self.declare(sc, a[0], TXT)
            self.declare(sc, a[1], t[1] if t[0] == "字典" else ANY)
            self.loop(sc, a[3:])
        elif h == "数":
            self.arg(sc, a[1], INT, "“数数”的起点")
            self.arg(sc, a[2], INT, "“数数”的终点")
            self.declare(sc, a[0], INT)
            self.loop(sc, a[3:])
        elif h == "返回":
            f = sc.get("f")
            want = self.ty(f["ret"], f["tv"]) if f and f["ret"] is not None else None
            t = self.ex(sc, a[0], want) if a else NUL
            if want is not None and not self.ok(t, want):
                t = self.res(t)
                if t[0] == "可空" and self.ok(t[1], want):
                    self.err("T02", sc["fn"], f"「{sc['fn']}」说好返回{show(want)}，这里返回的可能是空")
                else:
                    self.err("T01", sc["fn"], f"「{sc['fn']}」说好返回{show(want)}，这里返回的是{show(t)}")
            sc["rets"].append(t)
        elif h == "抛出":
            self.arg(sc, a[0], TXT, "抛出的错误信息")
        elif h == "试":
            for part in a:
                if part[0] == "做":
                    keep = set(sc["nn"])
                    self.block(sc, part[1:])
                    sc["nn"] = keep & sc["nn"]
                elif part[0] == "出错":
                    self.declare(sc, part[1], TXT)
                    self.block(sc, part[2:])
                else:
                    self.block(sc, part[1:])
        elif h == "打印":
            self.ex(sc, a[0])
        elif h == "做":
            self.ex(sc, a[0])
        elif h == "父创建":
            for x in a:
                self.ex(sc, x)
        elif h == "分情况":
            self.match(sc, a[0], a[1:])
        else:
            self.ex(sc, s)

    def loop(self, sc, body):
        keep = set(sc["nn"])
        self.block(sc, body)
        sc["nn"] = keep & sc["nn"]

    def match(self, sc, subj, cases):
        t = self.res(self.ex(sc, subj))
        names = [c[0] for c in cases]
        allc = None
        if t[0] == "名" and t[1] in self.enums:
            allc = self.enums[t[1]]
        elif t[0] == "名" and t[1] in self.variants:
            allc = list(self.variants[t[1]])
        elif t not in (ANY, NEVER):
            self.err("T01", sc["fn"], f"“分情况”要枚举或者变体，放进来的是{show(t)}")
        if allc is not None and "其余" not in names:
            miss = [c for c in allc if c not in names]
            if miss:
                self.err("T03", sc["fn"], f"“分情况”还少了：{'、'.join(miss)}（或者加一个“其余”）")
        keep = set(sc["nn"])
        for c in cases:
            sc["nn"] = set(keep)
            if c[0] == "其余":
                self.block(sc, c[1:])
                continue
            if allc is not None and c[0] not in allc:
                self.err("T08", sc["fn"], f"「{t[1]}」里没有「{c[0]}」")
                continue
            if t[0] == "名" and t[1] in self.variants:
                fs = self.variants[t[1]][c[0]]
                for (fn_, ft), bn in zip(fs, c[1]):
                    ms = sc
                    ms["names"].add(bn)
                    self.VT[(ms["key"], "分情况:" + bn)] = None
                    self.VT.pop((ms["key"], "分情况:" + bn))
                    if (ms["key"], bn) not in self.VT:
                        self.VT[(ms["key"], bn)] = dict(t=self.ty(ft), fixed=False, hidden=True)
            self.block(sc, c[2:])
        sc["nn"] = keep

    # ───────── 整个程序 ─────────
    def run_fn(self, f, this=None):
        sc = self.scope(f["key"], f["key"], tv=f["tv"], this=this)
        sc["f"], sc["cons"] = f, f["cons"]
        sc["reassigned"] = self.targets(f["body"])
        for i, (n, t) in enumerate(f["params"]):
            sc["names"].add(n)
            self.VT[(f["key"], n)] = dict(t=self.ptype(f, i), fixed=True, hidden=True)
        self.block(sc, f["body"])
        if f["ret"] is None:
            rt = NUL if not sc["rets"] else NEVER
            for r in sc["rets"]:
                rt = self.join(rt, r)
            if sc["rets"] and not self.exits(f["body"]) and not self.all_exit(f["body"]):
                rt = self.join(rt, NUL)
            old = self.RT.get(f["key"], NEVER)
            new = self.join(old, rt)
            if new != old:
                self.RT[f["key"]] = new
                self.changed = True

    def targets(self, x):  # 这段程序里所有被“改”过的变量名
        out = set()
        if isinstance(x, list):
            if x and x[0] == "改" and isinstance(x[1], str):
                out.add(x[1])
            for y in x:
                out |= self.targets(y)
        return out

    def all_exit(self, body):  # 最后一句是“分情况”而且每种情况都以返回结束，也算一定会返回
        if not body or not isinstance(body[-1], list):
            return False
        s = body[-1]
        if s[0] == "分情况":
            return all(self.exits(c[1:] if c[0] == "其余" else c[2:]) for c in s[2:])
        if s[0] == "试":
            return all(self.exits(p[1:] if p[0] == "做" else p[2:]) for p in s[1:] if p[0] in ("做", "出错"))
        return False

    def one_pass(self):
        for c in self.classes.values():
            this = ("名", c["name"], tuple(("变", v) for v in c["tv"]))
            for fd in c["fields"]:
                if len(fd) > 3:
                    sc = self.scope(c["name"] + ".字段", c["name"], tv=c["tv"], this=this)
                    self.arg(sc, fd[3], self.ty(fd[2], c["tv"]), f"「{fd[1]}」的初始值")
            if c["ctor"]:
                f = dict(key=c["name"] + ".创建", tv=c["tv"], cons={}, params=[(p[0], p[1]) for p in c["ctor"][1]], ret=None, body=c["ctor"][2:])
                self.run_fn(f, this)
            for m in c["methods"].values():
                self.run_fn(m, this)
            for i in c["impl"]:
                for mn, m in self.ifaces[i].items():
                    got = self.msig(c, mn, ())
                    if not got:
                        self.err("T11", c["name"], f"「{c['name']}」说自己是「{i}」，但是没有「{mn}」这个方法")
                    elif not self.ok(got[1], self.ty(m[2])):
                        self.err("T11", c["name"], f"「{c['name']}」的「{mn}」要返回{show(self.ty(m[2]))}，现在返回的是{show(self.res(got[1]))}")
        for f in self.funcs.values():
            self.run_fn(f)
        sc = self.scope("主", "主")
        sc["reassigned"] = self.targets(self.main)
        self.block(sc, self.main)

    def run(self):
        for n in range(12):
            self.changed = False
            self.order_backup = list(self.order)
            self.one_pass()
            if not self.changed:
                break
        self.passes = n + 1
        self.final = True
        self.one_pass()
        out = []
        for key in self.sigorder:
            f = self.funcs.get(key)
            if f is None:
                cn, mn = key.split(".")
                f = self.classes[cn]["methods"][mn]
            ps = []
            for i in range(len(f["params"])):
                t = self.res(self.ptype(f, i))
                ps.append(show(ANY if t == NEVER else t))
            rt = self.res(self.rtype(f))
            g = ""
            if f["own"]:
                g = "〈" + ", ".join(v + (": " + f["cons"][v] if v in f["cons"] else "") for v in f["own"]) + "〉"
            out.append(f"{key}: {g}({', '.join(ps)}) → {show(ANY if rt == NEVER else rt)}")
        for key in self.order:
            v = self.VT[key]
            if v.get("hidden") or key[0].endswith(".创建") or key[0].endswith(".字段"):
                continue
            t = self.res(v["t"])
            if self.has_hole(t):
                self.errors.append(f"T12 {key[0]}：「{key[1]}」里放什么还看不出来，先当成“任意”")
                t = self.close(t)
            out.append(f"{key[0]}.{key[1]}: {show(ANY if t == NEVER else t)}")
        return out, self.errors

    def has_hole(self, t):  # 还有没定下来的“洞”（因为别的错误变成“永不”的不算：那里已经报过了）
        if t[0] == "洞":
            return True
        return any(self.has_hole(x) for x in t[1:] if isinstance(x, tuple) and x and isinstance(x[0], str) and len(x[0]) <= 2 and x[0] != "T") or \
            any(self.has_hole(y) for x in t[1:] if isinstance(x, tuple) and x and isinstance(x[0], tuple) for y in x)

    def has_var_only(self, t):  # 只含类型变量（泛型函数里的 T），不含没定下来的洞
        if t[0] == "洞" or t == NEVER:
            return False
        for x in t[1:]:
            if isinstance(x, tuple) and x and isinstance(x[0], str) and x[0] in ("可空", "列表", "字典", "函数", "名", "变", "洞", "永不"):
                if not self.has_var_only(x):
                    return False
            elif isinstance(x, tuple) and x and isinstance(x[0], tuple):
                if not all(self.has_var_only(y) for y in x):
                    return False
        return True

    def close(self, t):
        if t[0] == "洞" or t == NEVER:
            return ANY
        if t[0] in ("可空", "列表", "字典"):
            return (t[0], self.close(t[1]))
        if t[0] == "名":
            return ("名", t[1], tuple(self.close(a) for a in t[2]))
        return t


if __name__ == "__main__":
    inf = Infer(parse(open(sys.argv[1], encoding="utf-8").read()))
    out, errs = inf.run()
    if "--errors" in sys.argv:
        print("\n".join(errs))
    else:
        print("\n".join(out))
        if errs:
            print("—— 报的问题 ——")
            print("\n".join(errs))
