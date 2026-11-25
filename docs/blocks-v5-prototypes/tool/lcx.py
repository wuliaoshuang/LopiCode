#!/usr/bin/env python3
"""lcx —— 积木第 5 版“完备性验证”用的临时翻译脚本（一次性的验证工具，不是产品的生成器）。

把“语法树的文本形式”（S 表达式，*.lcx）翻成能直接跑的 Node 和 Python 代码。
节点集合＝docs/blocks-v4-language-design.md 第 4.2 节那张表；标准库函数＝lib/lang/rt.dart 的两张表；
宿主原生接口＝natives.json。表外的东西一律报错，除非登记在下面的 EXTRA_* 里（每一项都对着一条缺口编号）。

用法见同目录 README.md。只用 Python 标准库。
"""
import copy
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# ————————————————————————————————————————————————————————————————————————
# 一、核心的三张表：标准库函数、被迫加的东西、内置类
# ————————————————————————————————————————————————————————————————————————

# lib/lang/rt.dart 的 kLangCoreFns ＋ kLangRtFns（不含只给生成器内部用的 times / items / countSteps）。值＝参数个数，-1＝不定。
CORE_RT = {
    'add': 2, 'sub': 2, 'mul': 2, 'div': 2, 'mod': 2, 'eq': 2, 'ne': 2, 'lt': 2, 'le': 2, 'gt': 2, 'ge': 2,
    'isNot': 1, 'truthy': 1, 'join': -1, 'size': 1, 'isNull': 1, 'now': 0, 'log': 1,
    'isType': 2, 'toNumber': 1, 'toText': 1, 'toBool': 1, 'copy': 1,
    'pow': 2, 'round': 1, 'floor': 1, 'ceil': 1, 'abs': 1, 'sqrt': 1, 'max': 2, 'min': 2, 'random': 2,
    'charAt': 2, 'substring': 3, 'contains': 2, 'startsWith': 2, 'endsWith': 2, 'indexOf': 2, 'replace': 3, 'split': 2,
    'trim': 1, 'upper': 1, 'lower': 1, 'repeatText': 2, 'template': 2,
    'listOf': -1, 'listGet': 2, 'listSet': 3, 'listPush': 2, 'listInsert': 3, 'listRemove': 2, 'listPop': 1,
    'listContains': 2, 'listIndexOf': 2, 'listSlice': 3, 'listConcat': 2, 'listReverse': 1, 'listSort': 1, 'listJoin': 2, 'range': 3,
    'listSortBy': 2, 'listMap': 2, 'listFilter': 2, 'listReduce': 3, 'listFind': 2, 'listEvery': 2, 'listSome': 2, 'listEach': 2,
    'dictOf': -1, 'dictGet': 2, 'dictSet': 3, 'dictRemove': 2, 'dictHas': 2, 'dictKeys': 1, 'dictValues': 1, 'dictPairs': 1, 'dictMerge': 2,
    'item': 2, 'setItem': 3, 'toJson': 1, 'fromJson': 1,
}
# 返回的一定是“是 / 否”的函数：放进条件里不用再包一层 truthy。
BOOL_RT = {'eq', 'ne', 'lt', 'le', 'gt', 'ge', 'isNot', 'truthy', 'isNull', 'isType', 'toBool', 'contains', 'startsWith', 'endsWith',
           'listContains', 'listEvery', 'listSome', 'dictHas', 'isNumeric'}
# 拿函数当参数的（Node 里这些函数不会“等”，所以传进去的匿名函数不许是要等的）。
HOF_RT = {'listSortBy', 'listMap', 'listFilter', 'listReduce', 'listFind', 'listEvery', 'listSome', 'listEach'}

# 为了写通，被迫加进标准库的函数（实现在 lcx_ext.js / lcx_ext.py）。名字 → (参数个数, 缺口编号, 第几轮加的)。
EXTRA_RT = {
    'isNumeric': (1, 'GAP-F1-07', 2),   # 这段文字是不是一个数字的写法
    'orElse': (2, 'GAP-F1-08', 2),      # 第一个是空就用第二个
    'typeName': (1, 'GAP-F1-05', 2),    # 值的种类名：对象、错误、稍后的结果也认得
}
# 为了写通，被迫加的语法（文本形式里的写法 → (缺口编号, 第几轮)）。
EXTRA_SYNTAX = {
    'rethrow': ('GAP-F1-03', 2),        # 在“出错了”的口里把接到的错误原样再抛出去
}

# 内置类（GAP-F1-01：v4 说“自定义错误＝继承内置的错误类”，但没定义这个内置类长什么样）。
BUILTIN_CLASSES = {
    '错误': {'name': '错误', 'builtin': True, 'target': 'lcx.Err', 'parent': None, 'interfaces': [],
           'fields': [{'name': '消息', 'private': False, 'static': False}],
           'ctor_sig': (0, 1), 'methods': [], 'public': True},
}


class LcxError(Exception):
    pass


def fail(where, msg):
    src = getattr(where, 'src', None) or (where.get('src') if isinstance(where, dict) else None) or '?'
    raise LcxError('%s：%s' % (src, msg))


# ————————————————————————————————————————————————————————————————————————
# 二、读入：S 表达式
# ————————————————————————————————————————————————————————————————————————

class Sym(str):
    pass


class Str(str):
    pass


class L(list):
    src = ''


class Splice(list):
    """展开积木时“一块变成好几句”的结果，接到外面那一串里去。"""


_TOKEN = re.compile(r'''(;[^\n]*)|([()])|("(?:[^"\\]|\\.)*")|([^\s()";]+)''')
_NUMBER = re.compile(r'[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$')


def read_forms(text, fname):
    stack = [L()]
    pos = 0
    while True:
        m = re.compile(r'\s*').match(text, pos)
        pos = m.end()
        if pos >= len(text):
            break
        m = _TOKEN.match(text, pos)
        line = text.count('\n', 0, pos) + 1
        if not m:
            raise LcxError('%s:%d：看不懂这里：%r' % (fname, line, text[pos:pos + 20]))
        pos = m.end()
        comment, paren, string, atom = m.groups()
        if comment:
            continue
        if paren == '(':
            new = L()
            new.src = '%s:%d' % (os.path.basename(fname), line)
            stack.append(new)
        elif paren == ')':
            if len(stack) == 1:
                raise LcxError('%s:%d：多了一个右括号' % (fname, line))
            done = stack.pop()
            stack[-1].append(done)
        elif string is not None:
            try:
                stack[-1].append(Str(json.loads(string.replace('\n', '\\n').replace('\t', '\\t'))))
            except ValueError:
                raise LcxError('%s:%d：文字的写法不对：%s' % (fname, line, string[:30]))
        elif _NUMBER.match(atom):
            stack[-1].append(float(atom))
        else:
            stack[-1].append(Sym(atom))
    if len(stack) != 1:
        raise LcxError('%s：少了右括号（从 %s 开始的那个没关上）' % (fname, stack[-1].src))
    return stack[0]


def show(form):
    """把读进来的东西再写成文本（--dump-core 用）。"""
    if isinstance(form, list):
        return '(' + ' '.join(show(x) for x in form) + ')'
    if isinstance(form, Str):
        return json.dumps(str(form), ensure_ascii=False)
    if isinstance(form, float):
        return repr(int(form)) if form == int(form) and abs(form) < 1e15 else repr(form)
    return str(form)


def is_head(form, *names):
    return isinstance(form, list) and form and isinstance(form[0], Sym) and form[0] in names


# ————————————————————————————————————————————————————————————————————————
# 三、展开封装：库清单里的积木（@名字 …）→ 核心的写法。对应设计稿流水线的第 ② 步。
# ————————————————————————————————————————————————————————————————————————

SHAPES = ('语句型', '值型', '是否型', '收尾型', '帽子型')
SLOT_KINDS = ('值', '选项', '清单', '变量', '回调口', '内联口')


class Library:
    def __init__(self, folder):
        self.folder = folder
        path = os.path.join(folder, 'lib.json')
        self.manifest = json.load(open(path, encoding='utf-8'))
        self.name = self.manifest['name']
        self.modules = [m[:-4] if m.endswith('.lcx') else m for m in self.manifest.get('modules', [])]
        self.blocks = {}
        for b in self.manifest.get('blocks', []):
            if b.get('shape') not in SHAPES:
                raise LcxError('%s：积木 %s 的形状 %r 不认识' % (path, b.get('name'), b.get('shape')))
            for s in b.get('slots', []):
                if s.get('kind') not in SLOT_KINDS:
                    raise LcxError('%s：积木 %s 的槽 %s 种类 %r 不认识' % (path, b['name'], s.get('name'), s.get('kind')))
            self.blocks[b['name']] = b
            if b.get('id'):
                self.blocks[b['id']] = b


class Expander:
    def __init__(self, libs, project_lists, prelude, stats):
        self.libs = libs                # 这个模块用上的库
        self.lists = project_lists      # 清单名 → 这个项目里有的项
        self.prelude = prelude          # 旧文档的“每次请求重置的变量”：放在每个帽子回调的最前面
        self.ctx = []                   # 现在套在哪些回调口里：每层是 {参数小块名: 实际的名字}
        self.in_callback = 0
        self.counter = 0
        self.stats = stats

    def find(self, name, where):
        lib_name, _, block_name = name.rpartition('.')
        hits = [(lib, lib.blocks[block_name]) for lib in self.libs if (not lib_name or lib.name == lib_name) and block_name in lib.blocks]
        if not hits:
            fail(where, '没有“%s”这块积木（用上的库：%s）' % (name, '、'.join(l.name for l in self.libs) or '无'))
        if len(hits) > 1:
            fail(where, '“%s”在好几个库里都有，要写成 库名.积木名' % name)
        return hits[0]

    def expand(self, form):
        """展开一个写法里所有的积木。返回新的写法（可能是 Splice）。"""
        if not isinstance(form, list):
            return form
        if form and isinstance(form[0], Sym) and form[0].startswith('@'):
            return self.block(form)
        out = L()
        out.src = getattr(form, 'src', '')
        for x in form:
            y = self.expand(x)
            if isinstance(y, Splice):
                out.extend(y)
            else:
                out.append(y)
        return out

    def body(self, forms):
        out = []
        for x in forms:
            y = self.expand(x)
            out.extend(y) if isinstance(y, Splice) else out.append(y)
        return out

    def block(self, form):
        lib, b = self.find(form[0][1:], form)
        self.stats[b['name']] = self.stats.get(b['name'], 0) + 1
        slots = b.get('slots', [])
        given = list(form[1:])
        if len(given) > len(slots):
            fail(form, '“%s”只有 %d 个槽，给了 %d 个' % (b['name'], len(slots), len(given)))
        values = {}
        callback_ctx = {}
        for i, s in enumerate(slots):
            v = given[i] if i < len(given) else Sym('_')
            empty = isinstance(v, Sym) and v == '_'
            kind = s['kind']
            if empty:
                if not s.get('optional'):
                    fail(form, '“%s”的槽“%s”必须填' % (b['name'], s['name']))
                values[s['name']] = None
                continue
            if kind == '值':
                values[s['name']] = self.expand(v)
            elif kind == '选项':
                if not isinstance(v, Str) or v not in s.get('choices', []):
                    fail(form, '“%s”的槽“%s”只能是 %s 里的一个' % (b['name'], s['name'], s.get('choices')))
                values[s['name']] = v
            elif kind == '清单':
                items = self.lists.get(s.get('list'), None)
                if not isinstance(v, Str) or items is None or v not in items:
                    fail(form, '“%s”的槽“%s”要从清单“%s”里选（这个项目里有：%s）' % (b['name'], s['name'], s.get('list'), items))
                values[s['name']] = v
            elif kind == '变量':
                if not isinstance(v, Sym):
                    fail(form, '“%s”的槽“%s”要填一个变量名' % (b['name'], s['name']))
                values[s['name']] = v
            else:  # 两种口
                if not is_head(v, '口'):
                    fail(form, '“%s”的槽“%s”是一个口，要写成 (口 积木…)' % (b['name'], s['name']))
                if kind == '回调口':
                    params = s.get('params', [])
                    self.ctx.append({p: p for p in params})
                    self.in_callback += 1
                    pre = [self.expand(copy.deepcopy(p)) for p in self.prelude] if b['shape'] == '帽子型' else []
                    inner = self.body(v[1:])
                    self.in_callback -= 1
                    self.ctx.pop()
                    values[s['name']] = L([Sym('fn'), L([Sym(p) for p in params])] + pre + inner)
                    values[s['name']].src = v.src
                else:
                    values[s['name']] = self.body(v[1:])
        for need in b.get('needs_context', []):
            if not any(need in layer for layer in self.ctx):
                fail(form, '“%s”只能放在提供“%s”的积木的口里' % (b['name'], need))
        d = b['def']
        if 'template' in d:
            return self.template(lib, b, d, values, form)
        args = [self.arg(a, values, form) for a in d.get('args', [])]
        if 'fn' in d:          # 调库里的一个函数
            call = L([Sym('call'), Sym(d['fn'])] + args)
        elif 'method' in d:    # 调某个对象的方法：对象来自一个槽（"$槽名"）或隐含的上下文（"@名字"）
            call = L([Sym('send'), self.arg(d['on'], values, form), Sym(d['method'])] + args)
        elif 'static' in d:    # 调类的静态方法："类名.方法名"
            cls, _, method = d['static'].partition('.')
            call = L([Sym('send'), Sym(cls), Sym(method)] + args)
        else:
            fail(form, '“%s”的定义里要有 fn / method / static / template 之一' % b['name'])
        call.src = form.src
        shape = b['shape']
        if shape in ('值型', '是否型'):
            return call
        into = values.get(d.get('into', '')) if d.get('into') else None
        if shape == '收尾型':
            out = L([Sym('return'), call])
        elif into is not None:
            out = L([Sym('set'), into, call])
        else:
            out = L([Sym('do'), call])
        out.src = form.src
        return out

    def arg(self, a, values, form):
        if isinstance(a, str) and a.startswith('$'):
            v = values[a[1:]]
            return Sym('null') if v is None else v
        if isinstance(a, str) and a.startswith('@'):
            for layer in reversed(self.ctx):
                if a[1:] in layer:
                    return Sym(layer[a[1:]])
            fail(form, '这块积木要用到“%s”，只能放在提供它的积木的口里' % a[1:])
        if isinstance(a, str):
            return Str(a)
        if isinstance(a, bool):
            return Sym('true' if a else 'false')
        if a is None:
            return Sym('null')
        return float(a)

    def template(self, lib, b, d, values, form):
        """内联口：把定义里的那一段原样放进来，$槽 换成填的东西，($口 名字) 换成口里的积木，%名字 换成不会撞的临时名字。"""
        forms = read_forms(open(os.path.join(lib.folder, d['template']), encoding='utf-8').read(), d['template'])
        self.counter += 1
        n = self.counter

        def sub(f):
            if isinstance(f, Sym):
                if f.startswith('%'):
                    return Sym('_t%d_%s' % (n, f[1:]))
                if f.startswith('$'):
                    v = values.get(f[1:])
                    return Sym('null') if v is None else copy.deepcopy(v)
                return f
            if not isinstance(f, list):
                return f
            if is_head(f, '$口'):
                return Splice(copy.deepcopy(values.get(f[1]) or []))
            if is_head(f, '$有'):  # ($有 槽名 写法…)：槽填了才要这几句
                return Splice([y for x in f[2:] for y in flat(sub(x))]) if values.get(f[1]) is not None else Splice()
            out = L()
            out.src = form.src
            for x in f:
                out.extend(flat(sub(x)))
            return out

        def flat(x):
            return list(x) if isinstance(x, Splice) else [x]

        return Splice([y for f in forms for y in flat(sub(f))])


# ————————————————————————————————————————————————————————————————————————
# 四、文本形式 → 语法树（节点种类只有 v4 第 4.2 节那些）
# ————————————————————————————————————————————————————————————————————————

BINARY = {'+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod', '**': 'pow', '==': 'eq', '!=': 'ne', '<': 'lt', '<=': 'le', '>': 'gt', '>=': 'ge'}
BOOL_BINARY = {'==', '!=', '<', '<=', '>', '>='}


def N(kind, form, **kw):
    kw['k'] = kind
    kw['src'] = getattr(form, 'src', '')
    return kw


class Builder:
    def __init__(self, used):
        self.used = used  # 统计：用到了哪些节点

    def n(self, kind, form, **kw):
        self.used['nodes'][kind] = self.used['nodes'].get(kind, 0) + 1
        return N(kind, form, **kw)

    def params(self, form, where):
        out = []
        if not isinstance(form, list):
            fail(where, '参数表要写成括号里的一串名字')
        for p in form:
            if isinstance(p, Sym):
                out.append({'name': str(p), 'default': None, 'rest': False})
            elif is_head(p, 'rest') and len(p) == 2:
                out.append({'name': str(p[1]), 'default': None, 'rest': True})
            elif isinstance(p, list) and len(p) == 2 and isinstance(p[0], Sym):
                d = self.expr(p[1])
                if d['k'] != 'Lit':
                    fail(where, '参数的默认值只许是直接填的值')
                out.append({'name': str(p[0]), 'default': d, 'rest': False})
            else:
                fail(where, '参数的写法不对：%s' % show(p))
        for p in out[:-1]:
            if p['rest']:
                fail(where, '“剩下的全收”只能是最后一个参数')
        return out

    def func(self, name, params, body, form, public=False):
        return self.n('FuncDecl', form, name=name, params=self.params(params, form), body=self.stmts(body), public=public)

    def decl(self, form, public=False):
        if is_head(form, 'public'):
            return self.decl(form[1], True)
        if not isinstance(form, list) or not form:
            fail(form, '模块里只能放声明：%s' % show(form))
        h = form[0]
        if h in ('var', 'const'):
            return self.n('VarDecl', form, name=str(form[1]), init=self.expr(form[2]), const=h == 'const', public=public)
        if h == 'func':
            return self.func(str(form[1]), form[2], form[3:], form, public)
        if h == 'native':
            return self.n('NativeDecl', form, name=str(form[1]), params=self.params(form[2], form), public=False)
        if h == 'interface':
            sigs = [{'name': str(s[1]), 'params': self.params(s[2], s)} for s in form[2:]]
            return self.n('InterfaceDecl', form, name=str(form[1]), sigs=sigs, public=public)
        if h == 'class':
            c = self.n('ClassDecl', form, name=str(form[1]), parent=None, interfaces=[], fields=[], ctor=None, methods=[], public=public)
            for m in form[2:]:
                if is_head(m, 'extends'):
                    c['parent'] = str(m[1])
                elif is_head(m, 'implements'):
                    c['interfaces'] = [str(x) for x in m[1:]]
                elif is_head(m, 'field', 'private-field', 'static-field'):
                    c['fields'].append({'name': str(m[1]), 'init': self.expr(m[2]), 'private': m[0] == 'private-field', 'static': m[0] == 'static-field', 'src': m.src})
                elif is_head(m, 'ctor'):
                    c['ctor'] = self.func('创建时', m[1], m[2:], m)
                elif is_head(m, 'method', 'static-method'):
                    c['methods'].append({'fn': self.func(str(m[1]), m[2], m[3:], m), 'static': m[0] == 'static-method', 'abstract': False})
                elif is_head(m, 'abstract-method'):
                    c['methods'].append({'fn': self.func(str(m[1]), m[2], [], m), 'static': False, 'abstract': True})
                else:
                    fail(m, '类里不认识这个：%s' % show(m)[:60])
            return c
        fail(form, '不认识的声明：%s' % show(form)[:60])

    def stmts(self, forms):
        return [self.stmt(f) for f in forms]

    def target(self, f):
        if isinstance(f, Sym):
            return N('TName', f, name=str(f))
        if is_head(f, 'index'):
            return N('TIndex', f, of=self.expr(f[1]), key=self.expr(f[2]))
        if is_head(f, '.'):
            return N('TField', f, of=self.expr(f[1]), name=str(f[2]))
        fail(f, '这不是一个能赋值的位置：%s' % show(f))

    def stmt(self, f):
        if not isinstance(f, list) or not f or not isinstance(f[0], Sym):
            fail(f, '这里要一句语句：%s' % show(f)[:60])
        h = f[0]
        n = self.n
        if h in ('let', 'const'):
            return n('Let', f, name=str(f[1]), value=self.expr(f[2]), const=h == 'const')
        if h == 'set':
            return n('Assign', f, target=self.target(f[1]), value=self.expr(f[2]))
        if h == 'do':
            return n('ExprStmt', f, expr=self.expr(f[1]))
        if h == 'if':
            arms, other = [], []
            for a in f[1:]:
                if is_head(a, 'when'):
                    arms.append({'cond': self.expr(a[1]), 'body': self.stmts(a[2:])})
                elif is_head(a, 'else'):
                    other = self.stmts(a[1:])
                else:
                    fail(a, '“如果”里只能是 (when 条件 …) 和 (else …)')
            return n('If', f, arms=arms, orElse=other)
        if h == 'while':
            return n('While', f, cond=self.expr(f[1]), body=self.stmts(f[2:]))
        if h == 'forever':
            return n('While', f, cond=None, body=self.stmts(f[1:]))
        if h == 'for-count':
            return n('ForCount', f, name=str(f[1]), frm=self.expr(f[2]), to=self.expr(f[3]), step=self.expr(f[4]), body=self.stmts(f[5:]))
        if h == 'for-each':
            item, index = (str(f[1][0]), str(f[1][1])) if isinstance(f[1], list) else (str(f[1]), None)
            return n('ForEach', f, item=item, index=index, list=self.expr(f[2]), body=self.stmts(f[3:]))
        if h == 'for-pairs':
            return n('ForPairs', f, key=str(f[1][0]), value=str(f[1][1]), dict=self.expr(f[2]), body=self.stmts(f[3:]))
        if h == 'repeat':
            return n('Repeat', f, times=self.expr(f[1]), body=self.stmts(f[2:]))
        if h == 'break':
            return n('Break', f)
        if h == 'continue':
            return n('Continue', f)
        if h == 'return':
            return n('Return', f, value=self.expr(f[1]) if len(f) > 1 else None)
        if h == 'throw':
            return n('Throw', f, value=self.expr(f[1]))
        if h == 'rethrow':
            self.extra('rethrow', f)
            return N('Rethrow', f)
        if h == 'try':
            t = n('Try', f, body=[], errorName=None, errorClass=None, onError=[], finallyBody=[], hasCatch=False)
            for a in f[1:]:
                if is_head(a, 'body'):
                    t['body'] = self.stmts(a[1:])
                elif is_head(a, 'catch'):
                    t['hasCatch'] = True
                    t['errorName'] = str(a[1])
                    rest = a[2:]
                    if rest and is_head(rest[0], 'only'):
                        t['errorClass'] = str(rest[0][1])
                        rest = rest[1:]
                    t['onError'] = self.stmts(rest)
                elif is_head(a, 'finally'):
                    t['finallyBody'] = self.stmts(a[1:])
                else:
                    fail(a, '“试着做”里只能是 (body …) (catch 名字 …) (finally …)')
            return t
        if h == 'note':
            return n('Note', f, text=str(f[1]))
        if h == 'super-init':
            return N('SuperInit', f, args=[self.expr(a) for a in f[1:]])
        fail(f, '不认识的语句：%s' % show(f)[:60])

    def extra(self, name, form):
        gap, rnd = EXTRA_SYNTAX[name] if name in EXTRA_SYNTAX else EXTRA_RT[name][1:]
        self.used['extras'][name] = (gap, rnd)

    def expr(self, f):
        n = self.n
        if isinstance(f, float):
            return n('Lit', None, value=f)
        if isinstance(f, Str):
            return n('Lit', None, value=str(f))
        if isinstance(f, Sym):
            if f in ('true', 'false', 'null'):
                return n('Lit', None, value={'true': True, 'false': False, 'null': None}[f])
            return n('Name', None, name=str(f))
        if not isinstance(f, list) or not f or not isinstance(f[0], Sym):
            fail(f, '这里要一个式子：%s' % show(f)[:60])
        h = f[0]
        a = f[1:]
        e = self.expr
        if h == 'list':
            return n('ListLit', f, items=[e(x) for x in a])
        if h == 'dict':
            for p in a:
                if not isinstance(p, list) or len(p) != 2:
                    fail(f, '字典要写成 (dict (键 值) (键 值) …)')
            return n('DictLit', f, entries=[(e(p[0]), e(p[1])) for p in a])
        if h == '.':
            return n('Field', f, of=e(a[0]), name=str(a[1]))
        if h == 'index':
            return n('Index', f, of=e(a[0]), key=e(a[1]))
        if h in ('not', 'neg'):
            return n('Unary', f, op=str(h), x=e(a[0]))
        if h in BINARY:
            if len(a) != 2:
                fail(f, '%s 要正好两个式子' % h)
            return n('Binary', f, op=str(h), l=e(a[0]), r=e(a[1]))
        if h in ('and', 'or'):
            out = e(a[0])
            for x in a[1:]:
                out = n('Logic', f, op=str(h), l=out, r=e(x))
            return out
        if h == 'cond':
            return n('Cond', f, cond=e(a[0]), then=e(a[1]), orElse=e(a[2]))
        if h == 'call':
            return n('Call', f, callee=e(a[0]), args=[e(x) for x in a[1:]])
        if h == 'send':
            return n('Send', f, obj=e(a[0]), method=str(a[1]), args=[e(x) for x in a[2:]])
        if h == 'super':
            return n('SuperSend', f, method=str(a[0]), args=[e(x) for x in a[1:]])
        if h == 'new':
            return n('New', f, cls=str(a[0]), args=[e(x) for x in a[1:]])
        if h == 'is-a':
            return n('IsA', f, x=e(a[0]), cls=str(a[1]))
        if h == 'fn':
            return n('Lambda', f, params=self.params(a[0], f), body=self.stmts(a[1:]))
        if h == '->':
            return n('Lambda', f, params=self.params(a[0], f), body=[N('Return', f, value=e(a[1]))])
        if h == 'this':
            return n('This', f)
        if h == 'await':
            return n('Await', f, x=e(a[0]))
        if h == 'spawn':
            return n('Spawn', f, body=self.stmts(a))
        if h == 'rt':
            name = str(a[0])
            if name in EXTRA_RT:
                self.extra(name, f)
                want = EXTRA_RT[name][0]
            elif name in CORE_RT:
                want = CORE_RT[name]
            else:
                fail(f, '标准库里没有“%s”这个函数（见 lib/lang/rt.dart；真缺的话先记成缺口再登记到 EXTRA_RT）' % name)
            if want >= 0 and len(a) - 1 != want:
                fail(f, '标准库函数 %s 要 %d 个参数，给了 %d 个' % (name, want, len(a) - 1))
            self.used['rt'][name] = self.used['rt'].get(name, 0) + 1
            return n('Rt', f, fn=name, args=[e(x) for x in a[1:]])
        if h == 'native':
            return n('Native', f, name=str(a[0]), args=[e(x) for x in a[1:]])
        fail(f, '不认识的式子：%s' % show(f)[:60])


# ————————————————————————————————————————————————————————————————————————
# 五、装载模块和库
# ————————————————————————————————————————————————————————————————————————

class Program:
    def __init__(self, lib_dirs, round_limit):
        self.lib_dirs = lib_dirs
        self.round_limit = round_limit
        self.modules = {}      # 名字 → 模块
        self.order = []        # 依赖顺序
        self.libs = {}         # 库名 → Library
        self.used = {'nodes': {}, 'rt': {}, 'natives': {}, 'extras': {}, 'blocks': {}}
        self.natives = json.load(open(os.path.join(HERE, 'natives.json'), encoding='utf-8'))
        self.core_dump = []

    def find_lib(self, name):
        if name in self.libs:
            return self.libs[name]
        for d in self.lib_dirs:
            folder = os.path.join(d, name)
            if os.path.exists(os.path.join(folder, 'lib.json')):
                self.libs[name] = Library(folder)
                return self.libs[name]
        return None

    def load(self, path, loading=()):
        text = open(path, encoding='utf-8').read()
        forms = read_forms(text, path)
        if len(forms) != 1 or not is_head(forms[0], 'module'):
            raise LcxError('%s：一个文件要正好是一个 (module 名字 …)' % path)
        form = forms[0]
        name = str(form[1])
        if name in self.modules:
            return self.modules[name]
        if name in loading:
            raise LcxError('模块绕圈了：%s' % ' → '.join(loading + (name,)))
        folder = os.path.dirname(path)
        mod = {'name': name, 'path': path, 'uses': [], 'see': [], 'decls': [], 'main': [], 'src': path}
        used_libs, lists, prelude, body = [], {}, [], []
        for f in form[2:]:
            if is_head(f, 'uses'):
                for u in f[1:]:
                    u = str(u)
                    lib = None if os.path.exists(os.path.join(folder, u + '.lcx')) else self.find_lib(u)
                    if lib:
                        used_libs.append(lib)
                        for m in lib.modules:
                            mod['uses'].append(self.load(os.path.join(lib.folder, m + '.lcx'), loading + (name,))['name'])
                    elif os.path.exists(os.path.join(folder, u + '.lcx')):
                        mod['uses'].append(self.load(os.path.join(folder, u + '.lcx'), loading + (name,))['name'])
                    else:
                        raise LcxError('%s：找不到模块或库“%s”' % (path, u))
            elif is_head(f, 'project-list'):
                lists[str(f[1])] = [str(x) for x in f[2:]]
            elif is_head(f, 'hat-prelude'):
                prelude.extend(f[1:])
            else:
                body.append(f)
        ex = Expander(used_libs, lists, prelude, self.used['blocks'])
        builder = Builder(self.used)
        hats, main, core = [], [], []
        for f in body:
            if isinstance(f, list) and f and isinstance(f[0], Sym) and f[0].startswith('@'):
                _, b = ex.find(f[0][1:], f)
                if b['shape'] != '帽子型':
                    fail(f, '模块最外面只能放帽子型的积木，“%s”是%s' % (b['name'], b['shape']))
                hats.append(ex.expand(f))
            elif is_head(f, 'main'):
                main.extend(ex.body(f[1:]))
            else:
                g = ex.expand(f)
                core.append(g)
                mod['decls'].append(builder.decl(g))
        # 帽子型：下面那一串包成函数，启动时按文档里的顺序各调一次“注册”——排在“启动时”那一串的前面。
        mod['main'] = builder.stmts(hats + main)
        if hats or ex.stats:
            self.core_dump.append('; ———— 模块 %s 展开积木以后 ————\n' % name + '\n'.join(show(x) for x in core) + '\n(main\n  ' + '\n  '.join(show(x) for x in hats + main) + ')\n')
        self.modules[name] = mod
        self.order.append(name)
        for gap_name, (gap, rnd) in self.used['extras'].items():
            if rnd > self.round_limit:
                raise LcxError('%s：用到了第 %d 轮才加的“%s”（%s），而现在限定只用第 %d 轮的核心' % (path, rnd, gap_name, gap, self.round_limit))
        return mod


# ————————————————————————————————————————————————————————————————————————
# 六、检查：名字解析、参数个数、接口、哪些函数要“等”
# ————————————————————————————————————————————————————————————————————————

class Unit:
    """一个“函数单位”：函数、方法、构造、匿名函数、开始做、模块的启动串。"""

    def __init__(self, kind, node, parent, mod, cls):
        self.kind, self.node, self.parent, self.mod, self.cls = kind, node, parent, mod, cls
        self.params = [p['name'] for p in node.get('params', [])]
        self.locals = []
        self.nonlocals = set()
        self.globals = set()
        self.triggers = []
        self.is_async = False
        # “不许等”的匿名函数：直接传给“不会等”的地方（标准库的高阶函数、宿主接口里标了 sync_params 的参数）。
        # 它里面调函数值不等；它里面要是有确定要等的事就报错。（第 2 轮加的规矩，GAP-F1-09）
        self.force_sync = bool(node.get('force_sync'))
        self.static = False
        self.catch_depth = 0
        node['unit'] = self


def sig_of(params):
    need = sum(1 for p in params if p['default'] is None and not p['rest'])
    return (need, -1 if any(p['rest'] for p in params) else len(params))


def ident(name):
    return re.sub(r'[^\w]', lambda m: '_u%04x' % ord(m.group()), name)


class Analyzer:
    def __init__(self, prog):
        self.prog = prog
        self.units = []
        self.classes = dict(BUILTIN_CLASSES)   # 全名 → 类
        self.methods = {}                     # 方法名 → [Unit]
        self.private = {}                     # 私有字段名 → {类}

    def run(self):
        for name in self.prog.order:
            mod = self.prog.modules[name]
            mod['table'] = {}
            for d in mod['decls']:
                if d['name'] in mod['table']:
                    fail(d, '模块 %s 里“%s”声明了两次' % (name, d['name']))
                d['mod'] = name
                d['target'] = 'M%s_%s' % (ident(name), ident(d['name']))
                mod['table'][d['name']] = d
                if d['k'] == 'NativeDecl':
                    spec = self.prog.natives.get(d['name'])
                    if spec is None:
                        fail(d, '宿主没有“%s”这个原生接口（见 natives.json）' % d['name'])
                    if len(d['params']) != len(spec['params']):
                        fail(d, '原生接口 %s 的参数是 %s，这里声明的个数不对' % (d['name'], spec['params']))
                    self.prog.used['natives'][d['name']] = self.prog.used['natives'].get(d['name'], 0)
        for name in self.prog.order:
            mod = self.prog.modules[name]
            for d in mod['decls']:
                if d['k'] == 'ClassDecl':
                    self.prepare_class(mod, d)
        for name in self.prog.order:
            mod = self.prog.modules[name]
            for d in mod['decls']:
                if d['k'] == 'VarDecl':
                    u = Unit('init', {'params': []}, None, mod, None)
                    self.expr(d['init'], u)
                elif d['k'] == 'FuncDecl':
                    self.function('func', d, None, mod, None)
                elif d['k'] == 'ClassDecl':
                    self.klass(mod, d)
            main = {'params': [], 'body': mod['main'], 'src': mod['path']}
            mod['main_unit'] = self.function('main', main, None, mod, None)
        self.infer_async()

    # —— 名字 ——
    def lookup_module(self, mod, name, where, want=None):
        hits = []
        if name in mod['table']:
            hits.append(mod['table'][name])
        else:
            for u in mod['uses']:
                d = self.prog.modules[u]['table'].get(name)
                if d is not None and d.get('public'):
                    hits.append(d)
            if not hits and name in BUILTIN_CLASSES:
                return BUILTIN_CLASSES[name]
        if len(hits) > 1:
            fail(where, '“%s”在好几个用上的模块里都有：%s' % (name, '、'.join(h['mod'] for h in hits)))
        if not hits:
            hidden = [u for u in mod['uses'] if name in self.prog.modules[u]['table']]
            fail(where, '找不到“%s”' % name + ('（模块 %s 里有，但没有公开）' % hidden[0] if hidden else ''))
        return hits[0]

    def resolve(self, name, unit, where):
        u = unit
        while u is not None:
            if name in u.params or name in u.locals:
                return ('local', u)
            u = u.parent
        return ('module', self.lookup_module(unit.mod, name, where))

    def class_of(self, mod, name, where):
        d = self.lookup_module(mod, name, where)
        if d.get('k') != 'ClassDecl' and not d.get('builtin'):
            fail(where, '“%s”不是类' % name)
        return d

    # —— 类 ——
    def prepare_class(self, mod, c):
        c['parent_decl'] = self.class_of(mod, c['parent'], c) if c['parent'] else None
        seen, p = [c['name']], c['parent_decl']
        while p is not None:
            if p is c:
                fail(c, '类 %s 绕圈继承了' % c['name'])
            p = p.get('parent_decl')
        for f in c['fields']:
            if f['private']:
                self.private.setdefault(f['name'], set()).add(c['target'])
        c['ctor_sig'] = sig_of(c['ctor']['params']) if c['ctor'] else None

    def ancestors(self, c):
        while c is not None:
            yield c
            c = c.get('parent_decl')

    def ctor_sig(self, c):
        for a in self.ancestors(c):
            if a.get('ctor_sig') is not None:
                return a['ctor_sig']
        return (0, 0)

    def find_method(self, c, name):
        for a in self.ancestors(c):
            for m in a['methods']:
                if m['fn']['name'] == name:
                    return m
        return None

    def klass(self, mod, c):
        for f in c['fields']:
            u = Unit('init', {'params': []}, None, mod, None if f['static'] else c)
            self.expr(f['init'], u)
        if c['ctor']:
            body = c['ctor']['body']
            c['super_args'] = None
            if body and body[0]['k'] == 'SuperInit':
                c['super_args'] = body[0]['args']
                c['ctor']['body'] = body[1:]
            u = self.function('ctor', c['ctor'], None, mod, c, extra=c['super_args'] or [])
            if c['super_args'] is not None:
                lo, hi = self.ctor_sig(c['parent_decl']) if c['parent_decl'] else (0, 0)
                self.check_count(len(c['super_args']), (lo, hi), c, '父类的创建时')
        for m in c['methods']:
            u = self.function('method', m['fn'], None, mod, c)
            u.static = m['static']
            m['fn']['sig'] = sig_of(m['fn']['params'])
            self.methods.setdefault(m['fn']['name'], []).append(u)
        for i in c['interfaces']:
            d = self.lookup_module(mod, i, c)
            if d['k'] != 'InterfaceDecl':
                fail(c, '“%s”不是接口' % i)
            for s in d['sigs']:
                m = self.find_method(c, s['name'])
                if m is None:
                    fail(c, '类 %s 说自己实现了接口 %s，但少了方法“%s”' % (c['name'], i, s['name']))
                if sig_of(m['fn']['params']) != sig_of(s['params']):
                    fail(c, '类 %s 的方法“%s”参数个数和接口 %s 里写的不一样' % (c['name'], s['name'], i))

    def abstract_left(self, c):
        done, left = set(), []
        for a in self.ancestors(c):
            for m in a['methods']:
                n = m['fn']['name']
                if n not in done:
                    done.add(n)
                    if m['abstract']:
                        left.append(n)
        return left

    # —— 函数单位 ——
    def function(self, kind, node, parent, mod, cls, extra=()):
        u = Unit(kind, node, parent, mod, cls)
        self.units.append(u)
        names = []
        seen = set(u.params)
        if len(seen) != len(u.params):
            fail(node, '参数重名了')
        self.collect(node['body'], names)
        for n in names:
            if n not in seen:
                seen.add(n)
                u.locals.append(n)
        for a in extra:
            self.expr(a, u)
        self.stmts(node['body'], u)
        return u

    def collect(self, stmts, out):
        for s in stmts:
            k = s['k']
            if k == 'Let':
                out.append(s['name'])
            elif k == 'If':
                for a in s['arms']:
                    self.collect(a['body'], out)
                self.collect(s['orElse'], out)
            elif k in ('While', 'Repeat'):
                self.collect(s['body'], out)
            elif k == 'ForCount':
                out.append(s['name'])
                self.collect(s['body'], out)
            elif k == 'ForEach':
                out.append(s['item'])
                if s['index']:
                    out.append(s['index'])
                self.collect(s['body'], out)
            elif k == 'ForPairs':
                out.extend([s['key'], s['value']])
                self.collect(s['body'], out)
            elif k == 'Try':
                if s['errorName']:
                    out.append(s['errorName'])
                self.collect(s['body'], out)
                self.collect(s['onError'], out)
                self.collect(s['finallyBody'], out)

    def check_count(self, given, sig, where, what):
        lo, hi = sig
        if given < lo or (hi >= 0 and given > hi):
            fail(where, '%s要 %s 个参数，给了 %d 个' % (what, lo if lo == hi else ('%d 到 %s' % (lo, '不限' if hi < 0 else hi)), given))

    def stmts(self, stmts, u):
        for s in stmts:
            self.stmt(s, u)

    def assign_name(self, name, u, where):
        kind, at = self.resolve(name, u, where)
        if kind == 'local':
            if at is not u:
                u.nonlocals.add(name)
            return ('local', at)
        if at.get('k') != 'VarDecl':
            fail(where, '“%s”不是变量，不能赋值' % name)
        if at.get('const'):
            fail(where, '“%s”是常量，不能再改' % name)
        u.globals.add(at['target'])
        return ('module', at)

    def stmt(self, s, u):
        k = s['k']
        e = lambda x: self.expr(x, u)
        if k == 'Let':
            e(s['value'])
        elif k == 'Assign':
            t = s['target']
            if t['k'] == 'TName':
                t['ref'] = self.assign_name(t['name'], u, s)
            elif t['k'] == 'TIndex':
                e(t['of'])
                e(t['key'])
            else:
                self.field_access(t, u)
            e(s['value'])
        elif k == 'ExprStmt':
            e(s['expr'])
        elif k == 'If':
            for a in s['arms']:
                e(a['cond'])
                self.stmts(a['body'], u)
            self.stmts(s['orElse'], u)
        elif k == 'While':
            if s['cond'] is not None:
                e(s['cond'])
            self.stmts(s['body'], u)
        elif k == 'ForCount':
            e(s['frm']), e(s['to']), e(s['step'])
            self.stmts(s['body'], u)
        elif k == 'ForEach':
            e(s['list'])
            self.stmts(s['body'], u)
        elif k == 'ForPairs':
            e(s['dict'])
            self.stmts(s['body'], u)
        elif k == 'Repeat':
            e(s['times'])
            self.stmts(s['body'], u)
        elif k == 'Return':
            if s['value'] is not None:
                e(s['value'])
            if u.kind in ('ctor',) and s['value'] is not None:
                fail(s, '“创建时”里不能返回值')
        elif k == 'Throw':
            e(s['value'])
        elif k == 'Rethrow':
            if u.catch_depth == 0:
                fail(s, '“原样再抛出”只能放在“出错了”的口里')
        elif k == 'Try':
            self.stmts(s['body'], u)
            if s['errorClass']:
                s['errorClassDecl'] = self.class_of(u.mod, s['errorClass'], s)
            u.catch_depth += 1
            self.stmts(s['onError'], u)
            u.catch_depth -= 1
            self.stmts(s['finallyBody'], u)
        elif k == 'SuperInit':
            fail(s, '“调用父类的创建时”只能是“创建时”里的第一句')

    def field_access(self, n, u):
        of = n['of']
        n['static_cls'] = None
        if of['k'] == 'Name' and self.resolve_quiet(of['name'], u) == 'class':
            c = self.class_of(u.mod, of['name'], n)
            f = [f for a in self.ancestors(c) for f in a['fields'] if f['name'] == n['name'] and f['static']]
            if not f:
                fail(n, '类 %s 没有静态字段“%s”' % (of['name'], n['name']))
            n['static_cls'] = c
        else:
            self.expr(of, u)
        owners = self.private.get(n['name'])
        if owners and (u.cls is None or u.cls['target'] not in owners):
            fail(n, '“%s”是私有字段，只有它自己的类里能读写' % n['name'])

    def resolve_quiet(self, name, u):
        try:
            kind, at = self.resolve(name, u, {})
        except LcxError:
            return None
        if kind == 'module' and (at.get('k') == 'ClassDecl' or at.get('builtin')):
            return 'class'
        return kind

    def expr(self, x, u):
        k = x['k']
        e = lambda y: self.expr(y, u)
        if k == 'Lit':
            pass
        elif k == 'ListLit':
            for i in x['items']:
                e(i)
        elif k == 'DictLit':
            for a, b in x['entries']:
                e(a), e(b)
        elif k == 'Name':
            kind, at = self.resolve(x['name'], u, x)
            x['ref'] = (kind, at)
            if kind == 'module' and at.get('k') not in ('VarDecl', 'FuncDecl'):
                fail(x, '“%s”是%s，不能当值用' % (x['name'], {'ClassDecl': '类', 'InterfaceDecl': '接口', 'NativeDecl': '原生接口'}.get(at.get('k'), '类')))
        elif k == 'Field':
            self.field_access(x, u)
        elif k == 'Index':
            e(x['of']), e(x['key'])
        elif k == 'Unary':
            e(x['x'])
        elif k in ('Binary', 'Logic'):
            e(x['l']), e(x['r'])
        elif k == 'Cond':
            e(x['cond']), e(x['then']), e(x['orElse'])
        elif k == 'Call':
            c = x['callee']
            x['static'] = None
            if c['k'] == 'Name':
                kind, at = self.resolve(c['name'], u, x)
                if kind == 'module' and at.get('k') == 'FuncDecl':
                    x['static'] = at
                    self.check_count(len(x['args']), sig_of(at['params']), x, '函数“%s”' % c['name'])
                    u.triggers.append(('func', at))
            if x['static'] is None:
                e(c)
                u.triggers.append(('dynamic', None))
                x['in_sync'] = u.force_sync
            for a in x['args']:
                e(a)
        elif k == 'Send':
            o = x['obj']
            x['static_cls'] = None
            if o['k'] == 'Name' and self.resolve_quiet(o['name'], u) == 'class':
                c = self.class_of(u.mod, o['name'], x)
                m = self.find_method(c, x['method'])
                if m is None or not m['static']:
                    fail(x, '类 %s 没有静态方法“%s”' % (o['name'], x['method']))
                self.check_count(len(x['args']), sig_of(m['fn']['params']), x, '静态方法“%s”' % x['method'])
                x['static_cls'] = c
            else:
                e(o)
            u.triggers.append(('method', x['method']))
            for a in x['args']:
                e(a)
        elif k == 'SuperSend':
            if u_cls(u) is None or u_cls(u).get('parent_decl') is None:
                fail(x, '“调用父类的…”只能在有父类的类的方法里用')
            m = self.find_method(u_cls(u)['parent_decl'], x['method'])
            if m is None:
                fail(x, '父类没有方法“%s”' % x['method'])
            self.check_count(len(x['args']), sig_of(m['fn']['params']), x, '父类的方法“%s”' % x['method'])
            u.triggers.append(('method', x['method']))
            for a in x['args']:
                e(a)
        elif k == 'New':
            c = self.class_of(u.mod, x['cls'], x)
            x['cls_decl'] = c
            if not c.get('builtin'):
                left = self.abstract_left(c)
                if left:
                    fail(x, '类 %s 还有抽象方法没实现（%s），不能新建' % (x['cls'], '、'.join(left)))
            self.check_count(len(x['args']), self.ctor_sig(c), x, '新建 %s ' % x['cls'])
            u.triggers.append(('new', c))
            for a in x['args']:
                e(a)
        elif k == 'IsA':
            x['cls_decl'] = self.class_of(u.mod, x['cls'], x)
            e(x['x'])
        elif k == 'Lambda':
            self.function('lambda', x, u, u.mod, u.cls)
        elif k == 'This':
            if u_cls(u) is None or u_static(u):
                fail(x, '“这个对象”只能在方法和“创建时”里用')
        elif k == 'Await':
            e(x['x'])
            u.triggers.append(('await', None))
        elif k == 'Spawn':
            x['params'] = []
            self.function('spawn', x, u, u.mod, u.cls)
        elif k == 'Rt':
            if x['fn'] in HOF_RT:
                x['hof'] = True
                for a in x['args']:
                    if a['k'] == 'Lambda':
                        a['force_sync'] = True
            for a in x['args']:
                e(a)
        elif k == 'Native':
            d = u.mod['table'].get(x['name'])
            if d is None or d['k'] != 'NativeDecl':
                fail(x, '用原生接口“%s”之前要先在模块里声明 (native %s (参数…))' % (x['name'], x['name']))
            if len(x['args']) != len(d['params']):
                fail(x, '原生接口 %s 要 %d 个参数' % (x['name'], len(d['params'])))
            if self.prog.natives[x['name']].get('round', 1) > self.prog.round_limit:
                fail(x, '原生接口 %s 是第 %d 轮才加的，现在限定只用第 %d 轮的核心' % (x['name'], self.prog.natives[x['name']]['round'], self.prog.round_limit))
            self.prog.used['natives'][x['name']] += 1
            if self.prog.natives[x['name']].get('async'):
                u.triggers.append(('await', None))
            spec = self.prog.natives[x['name']]
            for i, a in enumerate(x['args']):
                if a['k'] == 'Lambda' and spec['params'][i] in spec.get('sync_params', []):
                    a['force_sync'] = True
                e(a)
        else:
            fail(x, '内部错误：没处理的节点 %s' % k)

    # —— 哪些函数要“等”（只有 Node 用得上）——
    def infer_async(self):
        changed = True
        while changed:
            changed = False
            for u in self.units:
                if u.is_async:
                    continue
                for kind, what in u.triggers:
                    hit = (kind == 'await' or (kind == 'dynamic' and not u.force_sync)
                           or (kind == 'func' and what['unit'].is_async)
                           or (kind == 'method' and any(m.is_async for m in self.methods.get(what, []))))
                    if hit and u.force_sync:
                        fail(u.node, '这个匿名函数是传给“不会等”的地方的（标准库的高阶函数，或宿主接口里要求不能等的参数），里面不能有要等的事——GAP-F1-09')
                    if hit:
                        u.is_async = True
                        changed = True
                        break
        for u in self.units:
            if u.kind == 'ctor' and u.is_async:
                fail(u.node, '“创建时”里不能有要等的事（JavaScript 的构造函数不能等）——GAP-F1-10')

    def method_async(self, name):
        return any(m.is_async for m in self.methods.get(name, []))


def u_cls(u):
    return u.cls


def u_static(u):
    while u is not None:
        if u.kind == 'method':
            return u.static
        u = u.parent
    return False


# ————————————————————————————————————————————————————————————————————————
# 七、生成：两种语言共用的部分
# ————————————————————————————————————————————————————————————————————————

def snake(name):
    return re.sub('[A-Z]', lambda m: '_' + m.group().lower(), name)


def lit_text(s):
    """文字常量：JavaScript 和 Python 都认的写法。"""
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif o < 0x20 or o == 0x7f or 0xd800 <= o <= 0xdfff or o in (0x2028, 0x2029, 0xfeff, 0x85):
            out.append('\\u%04x' % o)
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


def is_bool(x):
    k = x['k']
    return (k == 'Logic' or (k == 'Unary' and x['op'] == 'not') or (k == 'Binary' and x['op'] in BOOL_BINARY) or k == 'IsA'
            or (k == 'Rt' and x['fn'] in BOOL_RT) or (k == 'Lit' and isinstance(x['value'], bool)))


class Gen:
    def __init__(self, prog, an):
        self.prog, self.an = prog, an
        self.tmp = 0
        self.unit = None

    def t(self, base='t'):
        self.tmp += 1
        return 'lc%s%d' % (base, self.tmp)

    def local(self, name):
        return 'v_' + ident(name)

    def cls_target(self, c):
        return c['target']

    def name_ref(self, x):
        kind, at = x['ref']
        return self.local(x['name']) if kind == 'local' else at['target']


# ————————————————————————————————————————————————————————————————————————
# 八、生成 Node
# ————————————————————————————————————————————————————————————————————————

class NodeGen(Gen):
    def num(self, v):
        return repr(v)

    def lit(self, v):
        if v is None:
            return 'null'
        if isinstance(v, bool):
            return 'true' if v else 'false'
        if isinstance(v, float):
            return '(%s)' % repr(v) if v < 0 else repr(v)
        return lit_text(v)

    def truthy(self, x):
        return self.ex(x) if is_bool(x) else 'lc.truthy(%s)' % self.ex(x)

    def args(self, xs):
        return ', '.join(self.ex(a) for a in xs)

    def aw(self, code, is_async):
        return '(await %s)' % code if is_async else code

    def ex(self, x):
        k = x['k']
        e = self.ex
        if k == 'Lit':
            return self.lit(x['value'])
        if k == 'ListLit':
            return '[%s]' % self.args(x['items'])
        if k == 'DictLit':
            return 'lc.dictOf(%s)' % ', '.join('%s, %s' % (e(a), e(b)) for a, b in x['entries'])
        if k == 'Name':
            return self.name_ref(x)
        if k == 'Field':
            if x['static_cls']:
                return '%s.sf_%s' % (self.cls_target(x['static_cls']), ident(x['name']))
            if x['of']['k'] == 'This':
                return 'this.f_%s' % ident(x['name'])
            return 'lcx.getf(%s, %s)' % (e(x['of']), lit_text(x['name']))
        if k == 'Index':
            return 'lc.item(%s, %s)' % (e(x['of']), e(x['key']))
        if k == 'Unary':
            return '!%s' % self.truthy_atom(x['x']) if x['op'] == 'not' else 'lc.sub(0, %s)' % e(x['x'])
        if k == 'Binary':
            return 'lc.%s(%s, %s)' % (BINARY[x['op']], e(x['l']), e(x['r']))
        if k == 'Logic':
            return '(%s %s %s)' % (self.truthy(x['l']), '&&' if x['op'] == 'and' else '||', self.truthy(x['r']))
        if k == 'Cond':
            return '(%s ? %s : %s)' % (self.truthy(x['cond']), e(x['then']), e(x['orElse']))
        if k == 'Call':
            if x['static'] is not None:
                return self.aw('%s(%s)' % (x['static']['target'], self.args(x['args'])), x['static']['unit'].is_async)
            code = 'lc.call(%s)' % ', '.join([e(x['callee'])] + [e(a) for a in x['args']])
            return code if x.get('in_sync') else '(await %s)' % code
        if k == 'Send':
            if x['static_cls']:
                code = '%s.m_%s(%s)' % (self.cls_target(x['static_cls']), ident(x['method']), self.args(x['args']))
            else:
                code = 'lcx.send(%s)' % ', '.join([e(x['obj']), lit_text(x['method'])] + [e(a) for a in x['args']])
            return self.aw(code, self.an.method_async(x['method']))
        if k == 'SuperSend':
            return self.aw('super.m_%s(%s)' % (ident(x['method']), self.args(x['args'])), self.an.method_async(x['method']))
        if k == 'New':
            return 'new %s(%s)' % (self.cls_target(x['cls_decl']), self.args(x['args']))
        if k == 'IsA':
            return '(%s instanceof %s)' % (e(x['x']), self.cls_target(x['cls_decl']))
        if k == 'Lambda':
            u = x['unit']
            lo, hi = sig_of(x['params'])
            body = self.fn_body(u, x['body'])
            return 'lc.fn("", %d, %d, %s(%s) => {\n%s\n})' % (lo, hi, 'async ' if u.is_async else '', self.params(x['params']), '\n'.join(ind(body)))
        if k == 'This':
            return 'this'
        if k == 'Await':
            return '(await %s)' % e(x['x'])
        if k == 'Spawn':
            return 'lcx.spawn(async () => {\n%s\n})' % '\n'.join(ind(self.fn_body(x['unit'], x['body'])))
        if k == 'Rt':
            return '%s.%s(%s)' % ('lcx' if x['fn'] in EXTRA_RT else 'lc', x['fn'], self.args(x['args']))
        if k == 'Native':
            spec = self.prog.natives[x['name']]
            return self.aw('%s(%s)' % (spec['node'], self.args(x['args'])), spec.get('async'))
        fail(x, '内部错误：Node 不会生成 %s' % k)

    def truthy_atom(self, x):
        return self.ex(x) if is_bool(x) and x['k'] not in ('Logic',) else ('lc.truthy(%s)' % self.ex(x) if not is_bool(x) else self.ex(x))

    def params(self, ps):
        out = []
        for p in ps:
            if p['rest']:
                out.append('...' + self.local(p['name']))
            elif p['default'] is not None:
                out.append('%s = %s' % (self.local(p['name']), self.lit(p['default']['value'])))
            else:
                out.append(self.local(p['name']))
        return ', '.join(out)

    def fn_body(self, u, body, pre=()):
        lines = list(pre)
        if u.locals:
            lines.append('let %s;' % ', '.join('%s = null' % self.local(n) for n in u.locals))
        lines += self.block(body)
        if not (body and body[-1]['k'] in ('Return', 'Throw')):
            lines.append('return null;')
        return lines

    def block(self, stmts):
        out = []
        for s in stmts:
            out += self.stmt(s)
        return out

    def stmt(self, s):
        k = s['k']
        e = self.ex
        if k == 'Let':
            return ['%s = %s;' % (self.local(s['name']), e(s['value']))]
        if k == 'Assign':
            t = s['target']
            if t['k'] == 'TName':
                kind, at = t['ref']
                return ['%s = %s;' % (self.local(t['name']) if kind == 'local' else at['target'], e(s['value']))]
            if t['k'] == 'TIndex':
                return ['lc.setItem(%s, %s, %s);' % (e(t['of']), e(t['key']), e(s['value']))]
            if t['static_cls']:
                return ['%s.sf_%s = %s;' % (self.cls_target(t['static_cls']), ident(t['name']), e(s['value']))]
            if t['of']['k'] == 'This':
                return ['this.f_%s = %s;' % (ident(t['name']), e(s['value']))]
            return ['lcx.setf(%s, %s, %s);' % (e(t['of']), lit_text(t['name']), e(s['value']))]
        if k == 'ExprStmt':
            return [e(s['expr']) + ';']
        if k == 'If':
            out = []
            for i, a in enumerate(s['arms']):
                out.append('%sif (%s) {' % ('} else ' if i else '', self.truthy(a['cond'])))
                out += ind(self.block(a['body']))
            if s['orElse']:
                out.append('} else {')
                out += ind(self.block(s['orElse']))
            out.append('}')
            return out
        if k == 'While':
            return ['while (%s) {' % ('true' if s['cond'] is None else self.truthy(s['cond']))] + ind(self.block(s['body'])) + ['}']
        if k == 'ForCount':
            a, st, n, i = self.t('a'), self.t('s'), self.t('n'), self.t('k')
            return ['for (let %s = lc.toNumber(%s), %s = lc.toNumber(%s), %s = lc.countSteps(%s, %s, %s), %s = 0; %s < %s; %s++) {' % (
                a, e(s['frm']), st, e(s['step']), n, a, e(s['to']), st, i, i, n, i),
                '  %s = %s + %s * %s;' % (self.local(s['name']), a, i, st)] + ind(self.block(s['body'])) + ['}']
        if k == 'ForEach':
            xs, i = self.t('xs'), self.t('i')
            head = ['for (let %s = lc.items(%s), %s = 0; %s < %s.length; %s++) {' % (xs, e(s['list']), i, i, xs, i),
                    '  %s = %s[%s];' % (self.local(s['item']), xs, i)]
            if s['index']:
                head.append('  %s = %s;' % (self.local(s['index']), i))
            return head + ind(self.block(s['body'])) + ['}']
        if k == 'ForPairs':
            d, ks, i = self.t('d'), self.t('ks'), self.t('i')
            return ['for (let %s = %s, %s = lc.dictKeys(%s), %s = 0; %s < %s.length; %s++) {' % (d, e(s['dict']), ks, d, i, i, ks, i),
                    '  %s = %s[%s];' % (self.local(s['key']), ks, i),
                    '  %s = lc.dictGet(%s, %s);' % (self.local(s['value']), d, self.local(s['key']))] + ind(self.block(s['body'])) + ['}']
        if k == 'Repeat':
            n, i = self.t('n'), self.t('k')
            return ['for (let %s = lc.times(%s), %s = 0; %s < %s; %s++) {' % (n, e(s['times']), i, i, n, i)] + ind(self.block(s['body'])) + ['}']
        if k == 'Break':
            return ['break;']
        if k == 'Continue':
            return ['continue;']
        if k == 'Return':
            return ['return %s;' % ('null' if s['value'] is None else e(s['value']))]
        if k == 'Throw':
            return ['throw lcx.toErr(%s);' % e(s['value'])]
        if k == 'Rethrow':
            return ['throw %s;' % self.raw_stack[-1]]
        if k == 'Try':
            out = ['try {'] + ind(self.block(s['body']))
            if s['hasCatch']:
                raw = self.t('e')
                out.append('} catch (%s) {' % raw)
                out.append('  %s = lcx.caught(%s);' % (self.local(s['errorName']), raw))
                if s['errorClass']:
                    out.append('  if (!(%s instanceof %s)) throw %s;' % (self.local(s['errorName']), self.cls_target(s['errorClassDecl']), raw))
                self.raw_stack.append(raw)
                out += ind(self.block(s['onError']))
                self.raw_stack.pop()
            if s['finallyBody'] or not s['hasCatch']:
                out.append('} finally {')
                out += ind(self.block(s['finallyBody']))
            out.append('}')
            return out
        if k == 'Note':
            return ['// ' + s['text'].replace('\n', ' ')]
        fail(s, '内部错误：Node 不会生成 %s' % k)

    raw_stack = []

    def func(self, d):
        u = d['unit']
        lo, hi = sig_of(d['params'])
        return ['const %s = lc.fn(%s, %d, %d, %sfunction (%s) {' % (d['target'], lit_text(d['name']), lo, hi, 'async ' if u.is_async else '', self.params(d['params']))] \
            + ind(self.fn_body(u, d['body'])) + ['});']

    def klass(self, c):
        parent = self.cls_target(c['parent_decl']) if c['parent_decl'] else 'lcx.Obj'
        out = ['class %s extends %s {' % (c['target'], parent)]
        statics = [f for f in c['fields'] if f['static']]
        fields = ['this.f_%s = %s;' % (ident(f['name']), self.ex(f['init'])) for f in c['fields'] if not f['static']]
        for f in statics:
            out.append('  static sf_%s = %s;' % (ident(f['name']), self.ex(f['init'])))
        if c['ctor']:
            sup = 'super(%s);' % self.args(c['super_args'] or [])
            out.append('  constructor(%s) {' % self.params(c['ctor']['params']))
            body = self.fn_body(c['ctor']['unit'], c['ctor']['body'], [sup] + fields)
            out += ind(ind([l for l in body if l != 'return null;']))
            out.append('  }')
        else:
            out.append('  constructor(...lcArgs) {')
            out += ind(ind(['super(...lcArgs);'] + fields))
            out.append('  }')
        tail = []
        for m in c['methods']:
            f = m['fn']
            u = f['unit']
            name = 'm_' + ident(f['name'])
            out.append('  %s%s%s(%s) {' % ('static ' if m['static'] else '', 'async ' if u.is_async else '', name, self.params(f['params'])))
            if m['abstract']:
                out.append('    throw lcx.toErr(%s);' % lit_text('抽象方法“%s”还没有实现' % f['name']))
            else:
                out += ind(ind(self.fn_body(u, f['body'])))
            out.append('  }')
            lo, hi = sig_of(f['params'])
            tail.append('lcx.sig(%s%s.%s, %d, %d);' % (c['target'], '' if m['static'] else '.prototype', name, lo, hi))
        out.append('}')
        out.append('lcx.named(%s, %s);' % (c['target'], lit_text(c['name'])))
        return out + tail

    def program(self):
        out = ['// 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。',
               '"use strict";',
               'const lc = require("./lc_lang.js");',
               'const lcx = require("./lcx_ext.js");',
               'const host = require("./host_node.js");', '']
        mains = []
        for name in self.prog.order:
            mod = self.prog.modules[name]
            out.append('// ———— 模块 %s ————' % name)
            for d in sort_classes(mod):
                out += self.klass(d)
            for d in mod['decls']:
                if d['k'] == 'FuncDecl':
                    out += self.func(d)
            for d in mod['decls']:
                if d['k'] == 'VarDecl':
                    out.append('let %s = %s;' % (d['target'], self.ex(d['init'])))
            if mod['main']:
                u = mod['main_unit']
                fname = 'lcMain_%s' % ident(name)
                out += ['%sfunction %s() {' % ('async ' if u.is_async else '', fname)] + ind(self.fn_body(u, mod['main'])) + ['}']
                mains.append('  %s%s();' % ('await ' if u.is_async else '', fname))
            out.append('')
        out += ['(async () => {'] + mains + ['  host.ready();', '})().catch(lcx.die);', '']
        return '\n'.join(out)


def ind(lines):
    if isinstance(lines, str):
        lines = lines.split('\n')
    return ['  ' + l if l else l for l in '\n'.join(lines).split('\n')] if lines else []


def sort_classes(mod):
    """父类排在子类前面。"""
    out, done = [], set()
    todo = [d for d in mod['decls'] if d['k'] == 'ClassDecl']

    def put(c):
        if id(c) in done:
            return
        p = c.get('parent_decl')
        if p is not None and p in todo:
            put(p)
        done.add(id(c))
        out.append(c)

    for c in todo:
        put(c)
    return out


# ————————————————————————————————————————————————————————————————————————
# 九、生成 Python
# ————————————————————————————————————————————————————————————————————————

def pind(lines):
    return ['    ' + l if l else l for l in lines]


class PyGen(Gen):
    def __init__(self, prog, an):
        super().__init__(prog, an)
        self.pre = [[]]       # 当前这一句前面要先放的东西（匿名函数的定义）
        self.raw_stack = []

    def lit(self, v):
        if v is None:
            return 'None'
        if isinstance(v, bool):
            return 'True' if v else 'False'
        if isinstance(v, float):
            return '(%s)' % repr(v) if v < 0 else repr(v)
        return lit_text(v)

    def truthy(self, x):
        return self.ex(x) if is_bool(x) else 'lc.truthy(%s)' % self.ex(x)

    def args(self, xs):
        return ', '.join(self.ex(a) for a in xs)

    def ex(self, x):
        k = x['k']
        e = self.ex
        if k == 'Lit':
            return self.lit(x['value'])
        if k == 'ListLit':
            return '[%s]' % self.args(x['items'])
        if k == 'DictLit':
            return 'lc.dict_of(%s)' % ', '.join('%s, %s' % (e(a), e(b)) for a, b in x['entries'])
        if k == 'Name':
            return self.name_ref(x)
        if k == 'Field':
            if x['static_cls']:
                return '%s.sf_%s' % (self.cls_target(x['static_cls']), ident(x['name']))
            if x['of']['k'] == 'This':
                return 'lc_self.f_%s' % ident(x['name'])
            return 'lcx.getf(%s, %s)' % (e(x['of']), lit_text(x['name']))
        if k == 'Index':
            return 'lc.item(%s, %s)' % (e(x['of']), e(x['key']))
        if k == 'Unary':
            return '(not %s)' % self.truthy(x['x']) if x['op'] == 'not' else 'lc.sub(0.0, %s)' % e(x['x'])
        if k == 'Binary':
            return 'lc.%s(%s, %s)' % (BINARY[x['op']], e(x['l']), e(x['r']))
        if k == 'Logic':
            return '(%s %s %s)' % (self.truthy(x['l']), x['op'], self.truthy(x['r']))
        if k == 'Cond':
            return '(%s if %s else %s)' % (e(x['then']), self.truthy(x['cond']), e(x['orElse']))
        if k == 'Call':
            if x['static'] is not None:
                return '%s(%s)' % (x['static']['target'], self.args(x['args']))
            return 'lc.call(%s)' % ', '.join([e(x['callee'])] + [e(a) for a in x['args']])
        if k == 'Send':
            if x['static_cls']:
                return '%s.m_%s(%s)' % (self.cls_target(x['static_cls']), ident(x['method']), self.args(x['args']))
            return 'lcx.send(%s)' % ', '.join([e(x['obj']), lit_text(x['method'])] + [e(a) for a in x['args']])
        if k == 'SuperSend':
            return 'super(%s, lc_self).m_%s(%s)' % (self.cls_target(self.unit_cls), ident(x['method']), self.args(x['args']))
        if k == 'New':
            return '%s(%s)' % (self.cls_target(x['cls_decl']), self.args(x['args']))
        if k == 'IsA':
            return 'isinstance(%s, %s)' % (e(x['x']), self.cls_target(x['cls_decl']))
        if k == 'Lambda':
            name = self.t('fn')
            lo, hi = sig_of(x['params'])
            self.pre[-1] += self.define(name, x['unit'], x['params'], x['body'])
            return 'lc.fn("", %d, %d, %s)' % (lo, hi, name)
        if k == 'This':
            return 'lc_self'
        if k == 'Await':
            return 'lcx.await_(%s)' % e(x['x'])
        if k == 'Spawn':
            name = self.t('fn')
            self.pre[-1] += self.define(name, x['unit'], [], x['body'])
            return 'lcx.spawn(%s)' % name
        if k == 'Rt':
            return '%s.%s(%s)' % ('lcx' if x['fn'] in EXTRA_RT else 'lc', snake(x['fn']), self.args(x['args']))
        if k == 'Native':
            return '%s(%s)' % (self.prog.natives[x['name']]['python'], self.args(x['args']))
        fail(x, '内部错误：Python 不会生成 %s' % k)

    def params(self, ps, first=None):
        out = [first] if first else []
        for p in ps:
            if p['rest']:
                out.append('*' + self.local(p['name']))
            elif p['default'] is not None:
                out.append('%s=%s' % (self.local(p['name']), self.lit(p['default']['value'])))
            else:
                out.append(self.local(p['name']))
        return ', '.join(out)

    def define(self, name, u, params, body, first=None, pre=(), decorator=None):
        """一个函数的定义（几行）。"""
        lines = []
        if u.globals:
            lines.append('global ' + ', '.join(sorted(u.globals)))
        if u.nonlocals:
            lines.append('nonlocal ' + ', '.join(sorted(self.local(n) for n in u.nonlocals)))
        for p in params:
            if p['rest']:
                lines.append('%s = list(%s)' % (self.local(p['name']), self.local(p['name'])))
        lines += list(pre)
        for n in u.locals:
            lines.append('%s = None' % self.local(n))
        lines += self.block(body)
        if not lines:
            lines.append('pass')
        return ([decorator] if decorator else []) + ['def %s(%s):' % (name, self.params(params, first))] + pind(lines)

    def block(self, stmts):
        out = []
        for s in stmts:
            self.pre.append([])
            lines = self.stmt(s)
            out += self.pre.pop() + lines
        return out

    def body(self, stmts):
        return pind(self.block(stmts) or ['pass'])

    def stmt(self, s):
        k = s['k']
        e = self.ex
        if k == 'Let':
            return ['%s = %s' % (self.local(s['name']), e(s['value']))]
        if k == 'Assign':
            t = s['target']
            if t['k'] == 'TName':
                kind, at = t['ref']
                return ['%s = %s' % (self.local(t['name']) if kind == 'local' else at['target'], e(s['value']))]
            if t['k'] == 'TIndex':
                return ['lc.set_item(%s, %s, %s)' % (e(t['of']), e(t['key']), e(s['value']))]
            if t['static_cls']:
                return ['%s.sf_%s = %s' % (self.cls_target(t['static_cls']), ident(t['name']), e(s['value']))]
            if t['of']['k'] == 'This':
                return ['lc_self.f_%s = %s' % (ident(t['name']), e(s['value']))]
            return ['lcx.setf(%s, %s, %s)' % (e(t['of']), lit_text(t['name']), e(s['value']))]
        if k == 'ExprStmt':
            return [e(s['expr'])]
        if k == 'If':
            out = []
            for i, a in enumerate(s['arms']):
                out.append('%s %s:' % ('elif' if i else 'if', self.truthy(a['cond'])))
                out += self.body(a['body'])
            if s['orElse']:
                out.append('else:')
                out += self.body(s['orElse'])
            return out
        if k == 'While':
            return ['while %s:' % ('True' if s['cond'] is None else self.truthy(s['cond']))] + self.body(s['body'])
        if k == 'ForCount':
            a, st, i = self.t('a'), self.t('s'), self.t('k')
            return ['%s = lc.to_number(%s)' % (a, e(s['frm'])), '%s = lc.to_number(%s)' % (st, e(s['step'])),
                    'for %s in range(lc.count_steps(%s, %s, %s)):' % (i, a, e(s['to']), st),
                    '    %s = %s + %s * %s' % (self.local(s['name']), a, i, st)] + self.body(s['body'])
        if k == 'ForEach':
            i, v = self.t('i'), self.t('x')
            head = ['for %s, %s in enumerate(lc.items(%s)):' % (i, v, e(s['list'])), '    %s = %s' % (self.local(s['item']), v)]
            if s['index']:
                head.append('    %s = float(%s)' % (self.local(s['index']), i))
            return head + self.body(s['body'])
        if k == 'ForPairs':
            d = self.t('d')
            return ['%s = %s' % (d, e(s['dict'])), 'for %s in lc.dict_keys(%s):' % (self.local(s['key']), d),
                    '    %s = lc.dict_get(%s, %s)' % (self.local(s['value']), d, self.local(s['key']))] + self.body(s['body'])
        if k == 'Repeat':
            return ['for %s in range(lc.times(%s)):' % (self.t('k'), e(s['times']))] + self.body(s['body'])
        if k == 'Break':
            return ['break']
        if k == 'Continue':
            return ['continue']
        if k == 'Return':
            return ['return %s' % ('None' if s['value'] is None else e(s['value']))]
        if k == 'Throw':
            return ['raise lcx.to_err(%s)' % e(s['value'])]
        if k == 'Rethrow':
            return ['raise %s' % self.raw_stack[-1]]
        if k == 'Try':
            out = ['try:'] + self.body(s['body'])
            if s['hasCatch']:
                raw = self.t('e')
                out.append('except Exception as %s:' % raw)
                out.append('    %s = lcx.caught(%s)' % (self.local(s['errorName']), raw))
                if s['errorClass']:
                    out.append('    if not isinstance(%s, %s):' % (self.local(s['errorName']), self.cls_target(s['errorClassDecl'])))
                    out.append('        raise')
                self.raw_stack.append(raw)
                out += pind(self.block(s['onError']))
                self.raw_stack.pop()
            if s['finallyBody'] or not s['hasCatch']:
                out.append('finally:')
                out += self.body(s['finallyBody'])
            return out
        if k == 'Note':
            return ['# ' + s['text'].replace('\n', ' ')]
        fail(s, '内部错误：Python 不会生成 %s' % k)

    unit_cls = None

    def func(self, d):
        lo, hi = sig_of(d['params'])
        return self.define(d['target'], d['unit'], d['params'], d['body']) + ['', '', '%s = lc.fn(%s, %d, %d, %s)' % (d['target'], lit_text(d['name']), lo, hi, d['target']), '', '']

    def klass(self, c):
        self.unit_cls = c
        parent = self.cls_target(c['parent_decl']) if c['parent_decl'] else 'lcx.Obj'
        out = ['class %s(%s):' % (c['target'], parent)]
        self.pre.append([])
        statics = ['sf_%s = %s' % (ident(f['name']), self.ex(f['init'])) for f in c['fields'] if f['static']]
        fields = ['lc_self.f_%s = %s' % (ident(f['name']), self.ex(f['init'])) for f in c['fields'] if not f['static']]
        hoisted = self.pre.pop()
        if hoisted:
            fail(c, '字段的初始值里不能直接写匿名函数（Python 这边放不下）；改到“创建时”里设——原型的局限')
        out += pind(statics)
        sup = 'super(%s, lc_self).__init__(%s)'
        if c['ctor']:
            self.pre.append([])
            sup_line = sup % (c['target'], self.args(c['super_args'] or []))
            hoisted = self.pre.pop()
            out += pind(self.define('__init__', c['ctor']['unit'], c['ctor']['params'], c['ctor']['body'], 'lc_self', hoisted + [sup_line] + fields)) + ['']
        else:
            out += pind(['def __init__(lc_self, *lc_args):'] + pind([sup % (c['target'], '*lc_args')] + fields)) + ['']
        tail = []
        for m in c['methods']:
            f = m['fn']
            name = 'm_' + ident(f['name'])
            if m['abstract']:
                out += pind(['def %s(%s):' % (name, self.params(f['params'], 'lc_self')), '    raise lcx.to_err(%s)' % lit_text('抽象方法“%s”还没有实现' % f['name'])]) + ['']
            else:
                out += pind(self.define(name, f['unit'], f['params'], f['body'], None if m['static'] else 'lc_self', decorator='@staticmethod' if m['static'] else None)) + ['']
            lo, hi = sig_of(f['params'])
            tail.append('lcx.sig(%s.%s, %d, %d)' % (c['target'], name, lo, hi))
        self.unit_cls = None
        return out + ['', 'lcx.named(%s, %s)' % (c['target'], lit_text(c['name']))] + tail + ['', '']

    def program(self):
        out = ['# 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。',
               'import lc_lang as lc', 'import lcx_ext as lcx', 'import host_python as host', '', '']
        mains = []
        for name in self.prog.order:
            mod = self.prog.modules[name]
            out.append('# ———— 模块 %s ————' % name)
            for d in sort_classes(mod):
                out += self.klass(d)
            for d in mod['decls']:
                if d['k'] == 'FuncDecl':
                    out += self.func(d)
            for d in mod['decls']:
                if d['k'] == 'VarDecl':
                    self.pre.append([])
                    line = '%s = %s' % (d['target'], self.ex(d['init']))
                    out += self.pre.pop() + [line]
            if mod['main']:
                fname = 'lc_main_%s' % ident(name)
                out += ['', ''] + self.define(fname, mod['main_unit'], [], mod['main']) + ['', '']
                mains.append(fname)
            out.append('')
        out += ['def lc_start():'] + pind(['%s()' % m for m in mains] + ['host.ready()']) + ['', '', 'lcx.run(lc_start)', '']
        return '\n'.join(out)


# ————————————————————————————————————————————————————————————————————————
# 十、命令行
# ————————————————————————————————————————————————————————————————————————

RUNTIME_FILES = {
    'node': ['l2/node/lc_runtime.js', 'l2/node/lc_lang.js', 'lcx_ext.js', 'host_node.js'],
    'python': ['l2/python/lc_runtime.py', 'l2/python/lc_lang.py', 'lcx_ext.py', 'host_python.py'],
}


def report(prog, an):
    u = prog.used
    lines = ['用到的语法树节点（%d 种）：%s' % (len(u['nodes']), '、'.join('%s×%d' % kv for kv in sorted(u['nodes'].items()))),
             '用到的标准库函数（%d 个）：%s' % (len(u['rt']), '、'.join('%s×%d' % kv for kv in sorted(u['rt'].items()))),
             '用到的宿主原生接口（%d 个）：%s' % (len(u['natives']), '、'.join('%s×%d' % kv for kv in sorted(u['natives'].items()))),
             '展开的库积木（%d 种）：%s' % (len(u['blocks']), '、'.join('%s×%d' % kv for kv in sorted(u['blocks'].items())) or '无'),
             '核心表以外、被迫加的：%s' % ('、'.join('%s（%s，第 %d 轮）' % (k, v[0], v[1]) for k, v in sorted(u['extras'].items())) or '无'),
             '要“等”的函数单位（Node 里生成成 async）：%d / %d' % (sum(1 for x in an.units if x.is_async), len(an.units))]
    return '\n'.join(lines) + '\n'


def main(argv):
    if len(argv) < 2 or argv[0] != 'build':
        print(__doc__)
        print('用法：python3 lcx.py build 入口.lcx -o 输出目录 [-L 放库的目录]… [--target node|python|both] [--round 1|2] [--dump-core 文件] [--report 文件]')
        return 2
    entry, out, lib_dirs, target, rnd, dump, rep = argv[1], None, [], 'both', 2, None, None
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == '-o':
            out = argv[i + 1]
        elif a == '-L':
            lib_dirs.append(argv[i + 1])
        elif a == '--target':
            target = argv[i + 1]
        elif a == '--round':
            rnd = int(argv[i + 1])
        elif a == '--dump-core':
            dump = argv[i + 1]
        elif a == '--report':
            rep = argv[i + 1]
        else:
            print('不认识的参数：' + a)
            return 2
        i += 2
    if out is None:
        print('要用 -o 指定输出目录')
        return 2
    try:
        prog = Program(lib_dirs + [os.path.dirname(os.path.abspath(entry))], rnd)
        prog.load(entry)
        an = Analyzer(prog)
        an.run()
        outputs = {}
        if target in ('node', 'both'):
            outputs['node'] = ('main.js', NodeGen(prog, an).program())
        if target in ('python', 'both'):
            outputs['python'] = ('main.py', PyGen(prog, an).program())
    except LcxError as e:
        print('翻译失败：%s' % e, file=sys.stderr)
        return 1
    for lang, (fname, code) in outputs.items():
        folder = os.path.join(out, lang)
        os.makedirs(folder, exist_ok=True)
        for f in RUNTIME_FILES[lang]:
            shutil.copyfile(os.path.join(HERE, f), os.path.join(folder, os.path.basename(f)))
        with open(os.path.join(folder, fname), 'w', encoding='utf-8') as f:
            f.write(code)
    text = report(prog, an)
    if rep:
        open(rep, 'w', encoding='utf-8').write(text)
    if dump:
        open(dump, 'w', encoding='utf-8').write('\n'.join(prog.core_dump))
    print('翻好了：%s（模块 %s）' % (out, ' → '.join(prog.order)))
    print(text, end='')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
