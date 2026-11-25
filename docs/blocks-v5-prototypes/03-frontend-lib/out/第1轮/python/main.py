# 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。
import lc_lang as lc
import lcx_ext as lcx
import host_python as host


# ———— 模块 反应 ————
class M反应_状态(lcx.Obj):
    def __init__(lc_self, v_初值):
        super(M反应_状态, lc_self).__init__()
        lc_self.f_号 = 0.0
        lc_self.f_值 = None
        lc_self.f_订阅 = lc.dict_of()
        lc_self.f_号 = M反应_新号()
        lc_self.f_值 = v_初值
        lc_self.f_订阅 = lc.dict_of()

    def m_读(lc_self):
        M反应_记依赖(lc_self)
        return lc_self.f_值

    def m_偷看(lc_self):
        return lc_self.f_值

    def m_写(lc_self, v_新值):
        if ((not lc.is_null(M反应_正在跑的)) and isinstance(M反应_正在跑的, M反应_派生)):
            raise lcx.to_err("派生值的算法里不能改状态")
        if lc.eq(v_新值, lc_self.f_值):
            return None
        lc_self.f_值 = v_新值
        M反应_通知(lc_self)


lcx.named(M反应_状态, "状态")
lcx.sig(M反应_状态.m_读, 0, 0)
lcx.sig(M反应_状态.m_偷看, 0, 0)
lcx.sig(M反应_状态.m_写, 1, 1)


class M反应_派生(lcx.Obj):
    def __init__(lc_self, v_算法):
        super(M反应_派生, lc_self).__init__()
        lc_self.f_号 = 0.0
        lc_self.f_算法 = None
        lc_self.f_值 = None
        lc_self.f_旧了 = True
        lc_self.f_正在算 = False
        lc_self.f_订阅 = lc.dict_of()
        lc_self.f_依赖 = lc.dict_of()
        lc_self.f_算了几次 = 0.0
        lc_self.f_号 = M反应_新号()
        lc_self.f_算法 = v_算法
        lc_self.f_订阅 = lc.dict_of()
        lc_self.f_依赖 = lc.dict_of()

    def m_标旧(lc_self):
        if (not lc.truthy(lc_self.f_旧了)):
            lc_self.f_旧了 = True
            M反应_通知(lc_self)

    def m_读(lc_self):
        global M反应_正在跑的
        v_之前 = None
        M反应_记依赖(lc_self)
        if lc.truthy(lc_self.f_旧了):
            if lc.truthy(lc_self.f_正在算):
                raise lcx.to_err("派生值绕回了自己")
            lc_self.f_正在算 = True
            M反应_断开(lc_self)
            v_之前 = M反应_正在跑的
            M反应_正在跑的 = lc_self
            try:
                lc_self.f_值 = lc.call(lc_self.f_算法)
                lc_self.f_算了几次 = lc.add(lc_self.f_算了几次, 1.0)
            finally:
                M反应_正在跑的 = v_之前
                lc_self.f_正在算 = False
            lc_self.f_旧了 = False
        return lc_self.f_值


lcx.named(M反应_派生, "派生")
lcx.sig(M反应_派生.m_标旧, 0, 0)
lcx.sig(M反应_派生.m_读, 0, 0)


class M反应_跟随(lcx.Obj):
    def __init__(lc_self, v_做法):
        super(M反应_跟随, lc_self).__init__()
        lc_self.f_号 = 0.0
        lc_self.f_做法 = None
        lc_self.f_依赖 = lc.dict_of()
        lc_self.f_停了 = False
        lc_self.f_排着 = False
        lc_self.f_收尾 = None
        lc_self.f_号 = M反应_新号()
        lc_self.f_做法 = v_做法
        lc_self.f_依赖 = lc.dict_of()

    def m_标旧(lc_self):
        if (lc.truthy(lc_self.f_停了) or lc.truthy(lc_self.f_排着)):
            return None
        lc_self.f_排着 = True
        lc.list_push(M反应_等着跑的, lc_self)
        M反应_排一下()

    def m_做收尾(lc_self):
        v_收 = None
        if (not lc.is_null(lc_self.f_收尾)):
            v_收 = lc_self.f_收尾
            lc_self.f_收尾 = None
            lc.call(v_收)

    def m_跑(lc_self):
        global M反应_正在跑的
        v_之前 = None
        v_结果 = None
        if lc.truthy(lc_self.f_停了):
            return None
        lcx.send(lc_self, "做收尾")
        M反应_断开(lc_self)
        v_之前 = M反应_正在跑的
        M反应_正在跑的 = lc_self
        try:
            v_结果 = lc.call(lc_self.f_做法)
            if lc.is_type(v_结果, "function"):
                lc_self.f_收尾 = v_结果
        finally:
            M反应_正在跑的 = v_之前

    def m_停(lc_self):
        if lc.truthy(lc_self.f_停了):
            return None
        lc_self.f_停了 = True
        lcx.send(lc_self, "做收尾")
        M反应_断开(lc_self)


lcx.named(M反应_跟随, "跟随")
lcx.sig(M反应_跟随.m_标旧, 0, 0)
lcx.sig(M反应_跟随.m_做收尾, 0, 0)
lcx.sig(M反应_跟随.m_跑, 0, 0)
lcx.sig(M反应_跟随.m_停, 0, 0)


class M反应_归属(lcx.Obj):
    def __init__(lc_self):
        super(M反应_归属, lc_self).__init__()
        lc_self.f_要收的 = []
        lc_self.f_收了 = False
        lc_self.f_要收的 = []

    def m_记(lc_self, v_收法):
        lc.list_push(lc_self.f_要收的, v_收法)

    def m_里面做(lc_self, v_做):
        global M反应_当前归属
        v_之前 = None
        v_之前 = M反应_当前归属
        M反应_当前归属 = lc_self
        try:
            return lc.call(v_做)
        finally:
            M反应_当前归属 = v_之前

    def m_收(lc_self):
        v_表 = None
        v_收法 = None
        if lc.truthy(lc_self.f_收了):
            return None
        lc_self.f_收了 = True
        v_表 = lc.list_reverse(lc_self.f_要收的)
        lc_self.f_要收的 = []
        for lci1, lcx2 in enumerate(lc.items(v_表)):
            v_收法 = lcx2
            lc.call(v_收法)


lcx.named(M反应_归属, "归属")
lcx.sig(M反应_归属.m_记, 1, 1)
lcx.sig(M反应_归属.m_里面做, 1, 1)
lcx.sig(M反应_归属.m_收, 0, 0)


def M反应_新号():
    global M反应_下一个号
    M反应_下一个号 = lc.add(M反应_下一个号, 1.0)
    return M反应_下一个号


M反应_新号 = lc.fn("新号", 0, 0, M反应_新号)


def M反应_记依赖(v_源):
    if (not lc.is_null(M反应_正在跑的)):
        lc.set_item(lcx.getf(v_源, "订阅"), lcx.getf(M反应_正在跑的, "号"), M反应_正在跑的)
        lc.set_item(lcx.getf(M反应_正在跑的, "依赖"), lcx.getf(v_源, "号"), v_源)


M反应_记依赖 = lc.fn("记依赖", 1, 1, M反应_记依赖)


def M反应_断开(v_谁):
    v_键 = None
    v_源 = None
    lcd3 = lcx.getf(v_谁, "依赖")
    for v_键 in lc.dict_keys(lcd3):
        v_源 = lc.dict_get(lcd3, v_键)
        lc.dict_remove(lcx.getf(v_源, "订阅"), lcx.getf(v_谁, "号"))
    lcx.setf(v_谁, "依赖", lc.dict_of())


M反应_断开 = lc.fn("断开", 1, 1, M反应_断开)


def M反应_通知(v_源):
    v_键 = None
    v_谁 = None
    lcd4 = lcx.getf(v_源, "订阅")
    for v_键 in lc.dict_keys(lcd4):
        v_谁 = lc.dict_get(lcd4, v_键)
        lcx.send(v_谁, "标旧")


M反应_通知 = lc.fn("通知", 1, 1, M反应_通知)


def M反应_报错(v_消息):
    if lc.is_null(M反应_出错时):
        host.log_error(lc.join("跟着做的事出错：", v_消息))
    else:
        lc.call(M反应_出错时, v_消息)


M反应_报错 = lc.fn("报错", 1, 1, M反应_报错)


def M反应_排一下():
    global M反应_排上了
    if (lc.truthy(M反应_排上了) or lc.gt(M反应_一起改层数, 0.0)):
        return None
    M反应_排上了 = True
    def lcfn5():
        M反应_冲刷()
    host.tick_defer(lc.fn("", 0, 0, lcfn5))


M反应_排一下 = lc.fn("排一下", 0, 0, M反应_排一下)


def M反应_冲刷():
    global M反应_排上了, M反应_等着跑的
    v_轮 = None
    v_丢 = None
    v_这批 = None
    v_一个 = None
    v_e = None
    M反应_排上了 = False
    v_轮 = 0.0
    while lc.gt(lc.size(M反应_等着跑的), 0.0):
        v_轮 = lc.add(v_轮, 1.0)
        if lc.gt(v_轮, 100.0):
            for lci6, lcx7 in enumerate(lc.items(M反应_等着跑的)):
                v_丢 = lcx7
                lcx.setf(v_丢, "排着", False)
            M反应_等着跑的 = []
            M反应_报错("跟着变的积木互相触发超过 100 轮")
            return None
        v_这批 = M反应_等着跑的
        M反应_等着跑的 = []
        for lci8, lcx9 in enumerate(lc.items(v_这批)):
            v_一个 = lcx9
            lcx.setf(v_一个, "排着", False)
            try:
                lcx.send(v_一个, "跑")
            except Exception as lce10:
                v_e = lcx.caught(lce10)
                M反应_报错(lcx.getf(v_e, "消息"))


M反应_冲刷 = lc.fn("冲刷", 0, 0, M反应_冲刷)


def M反应_新状态(v_初值):
    return M反应_状态(v_初值)


M反应_新状态 = lc.fn("新状态", 1, 1, M反应_新状态)


def M反应_新派生(v_算法):
    return M反应_派生(v_算法)


M反应_新派生 = lc.fn("新派生", 1, 1, M反应_新派生)


def M反应_跟着做(v_做法):
    v_一个 = None
    v_取消 = None
    v_一个 = M反应_跟随(v_做法)
    def lcfn11():
        lcx.send(v_一个, "停")
    v_取消 = lc.fn("", 0, 0, lcfn11)
    if (not lc.is_null(M反应_当前归属)):
        lcx.send(M反应_当前归属, "记", v_取消)
    lcx.send(v_一个, "跑")
    return v_取消


M反应_跟着做 = lc.fn("跟着做", 1, 1, M反应_跟着做)


def M反应_不记依赖地做(v_做):
    global M反应_正在跑的
    v_之前 = None
    v_之前 = M反应_正在跑的
    M反应_正在跑的 = None
    try:
        return lc.call(v_做)
    finally:
        M反应_正在跑的 = v_之前


M反应_不记依赖地做 = lc.fn("不记依赖地做", 1, 1, M反应_不记依赖地做)


def M反应_当变了(v_取值, v_回调, v_马上=False):
    v_旧 = None
    v_第一次 = None
    v_旧 = None
    v_第一次 = True
    def lcfn12():
        nonlocal v_旧, v_第一次
        v_新 = None
        v_原来 = None
        v_新 = lc.call(v_取值)
        if lc.truthy(v_第一次):
            v_第一次 = False
            v_旧 = v_新
            if lc.truthy(v_马上):
                def lcfn13():
                    lc.call(v_回调, v_新, None)
                M反应_不记依赖地做(lc.fn("", 0, 0, lcfn13))
            return None
        if lc.ne(v_新, v_旧):
            v_原来 = v_旧
            v_旧 = v_新
            def lcfn14():
                lc.call(v_回调, v_新, v_原来)
            M反应_不记依赖地做(lc.fn("", 0, 0, lcfn14))
        return None
    return M反应_跟着做(lc.fn("", 0, 0, lcfn12))


M反应_当变了 = lc.fn("当变了", 2, 3, M反应_当变了)


def M反应_一起改(v_做):
    global M反应_一起改层数
    M反应_一起改层数 = lc.add(M反应_一起改层数, 1.0)
    try:
        lc.call(v_做)
    finally:
        M反应_一起改层数 = lc.sub(M反应_一起改层数, 1.0)
        if (lc.eq(M反应_一起改层数, 0.0) and lc.gt(lc.size(M反应_等着跑的), 0.0)):
            M反应_排一下()


M反应_一起改 = lc.fn("一起改", 1, 1, M反应_一起改)


def M反应_等更新():
    host.tick_wait()


M反应_等更新 = lc.fn("等更新", 0, 0, M反应_等更新)


def M反应_设出错时(v_回调):
    global M反应_出错时
    M反应_出错时 = v_回调


M反应_设出错时 = lc.fn("设出错时", 1, 1, M反应_设出错时)


M反应_正在跑的 = None
M反应_当前归属 = None
M反应_下一个号 = 100000.0
M反应_等着跑的 = []
M反应_排上了 = False
M反应_一起改层数 = 0.0
M反应_出错时 = None

# ———— 模块 总线 ————
class M总线_事件总线(lcx.Obj):
    def __init__(lc_self):
        super(M总线_事件总线, lc_self).__init__()
        lc_self.f_听的 = lc.dict_of()
        lc_self.f_下一个号 = 1.0
        lc_self.f_出错时 = None
        lc_self.f_听的 = lc.dict_of()

    def m_登记(lc_self, v_事件名, v_回调, v_一次):
        v_号 = None
        v_自己 = None
        v_号 = lc_self.f_下一个号
        lc_self.f_下一个号 = lc.add(v_号, 1.0)
        if (not lc.dict_has(lc_self.f_听的, v_事件名)):
            lc.set_item(lc_self.f_听的, v_事件名, [])
        lc.list_push(lc.dict_get(lc_self.f_听的, v_事件名), lc.dict_of("号", v_号, "回调", v_回调, "一次", v_一次, "停了", False))
        v_自己 = lc_self
        def lcfn15():
            return lcx.send(v_自己, "退订", v_事件名, v_号)
        return lc.fn("", 0, 0, lcfn15)

    def m_订阅(lc_self, v_事件名, v_回调):
        return lcx.send(lc_self, "登记", v_事件名, v_回调, False)

    def m_只听一次(lc_self, v_事件名, v_回调):
        return lcx.send(lc_self, "登记", v_事件名, v_回调, True)

    def m_退订(lc_self, v_事件名, v_号):
        v_表 = None
        v_条 = None
        v_i = None
        v_表 = lcx.or_else(lc.dict_get(lc_self.f_听的, v_事件名), [])
        for lci16, lcx17 in enumerate(lc.items(v_表)):
            v_条 = lcx17
            v_i = float(lci16)
            if lc.eq(lc.dict_get(v_条, "号"), v_号):
                lc.set_item(v_条, "停了", True)
                lc.list_remove(v_表, v_i)
                return True
        return False

    def m_有几个在听(lc_self, v_事件名):
        return lc.size(lcx.or_else(lc.dict_get(lc_self.f_听的, v_事件名), []))

    def m_发出(lc_self, v_事件名, v_数据=None):
        v_表 = None
        v_这次 = None
        v_叫了 = None
        v_条 = None
        v_e = None
        v_表 = lc.dict_get(lc_self.f_听的, v_事件名)
        if lc.is_null(v_表):
            return 0.0
        v_这次 = lc.list_slice(v_表, 0.0, lc.size(v_表))
        v_叫了 = 0.0
        for lci18, lcx19 in enumerate(lc.items(v_这次)):
            v_条 = lcx19
            if lc.truthy(lc.dict_get(v_条, "停了")):
                continue
            if lc.truthy(lc.dict_get(v_条, "一次")):
                lcx.send(lc_self, "退订", v_事件名, lc.dict_get(v_条, "号"))
            v_叫了 = lc.add(v_叫了, 1.0)
            try:
                lc.call(lc.dict_get(v_条, "回调"), v_数据)
            except Exception as lce20:
                v_e = lcx.caught(lce20)
                if lc.is_null(lc_self.f_出错时):
                    host.log_error(lc.join("事件“", v_事件名, "”的处理出错：", lcx.getf(v_e, "消息")))
                else:
                    lc.call(lc_self.f_出错时, lcx.getf(v_e, "消息"), v_事件名)
        return v_叫了

    def m_设出错时(lc_self, v_回调):
        lc_self.f_出错时 = v_回调


lcx.named(M总线_事件总线, "事件总线")
lcx.sig(M总线_事件总线.m_登记, 3, 3)
lcx.sig(M总线_事件总线.m_订阅, 2, 2)
lcx.sig(M总线_事件总线.m_只听一次, 2, 2)
lcx.sig(M总线_事件总线.m_退订, 2, 2)
lcx.sig(M总线_事件总线.m_有几个在听, 1, 1)
lcx.sig(M总线_事件总线.m_发出, 1, 2)
lcx.sig(M总线_事件总线.m_设出错时, 1, 1)



# ———— 模块 检查 ————
def M检查_报(v_号, v_名字, v_值):
    lc.log(lc.join("[", v_号, "] ", v_名字, "：", v_值))


M检查_报 = lc.fn("报", 3, 3, M检查_报)


M检查_积木计数 = M反应_新状态(0.0)
M检查_积木记录 = []
M检查_全局总线 = M总线_事件总线()
M检查_积木收到的 = []


def lc_main_检查():
    v_错们 = None
    v_a = None
    v_b = None
    v_两倍 = None
    v_文字 = None
    v_写了几次 = None
    v_停2 = None
    v_甲 = None
    v_乙 = None
    v_丙 = None
    v_见过的 = None
    v_丁 = None
    v_开关 = None
    v_内容 = None
    v_跑4 = None
    v_看到 = None
    v_停4 = None
    v_c = None
    v_跑5 = None
    v_停5 = None
    v_表 = None
    v_跑5c = None
    v_停5c = None
    v_同一个 = None
    v_d = None
    v_记6 = None
    v_停6 = None
    v_e7 = None
    v_跑7 = None
    v_停7 = None
    v_绕甲 = None
    v_绕乙 = None
    v_结果8 = None
    v_e = None
    v_f = None
    v_记9 = None
    v_停9 = None
    v_记10 = None
    v_停10 = None
    v_g = None
    v_h = None
    v_记12 = None
    v_停12 = None
    v_坏派生 = None
    v_结果13 = None
    v_主 = None
    v_i = None
    v_记14 = None
    v_j = None
    v_跑15 = None
    v_停15 = None
    v_跑15b = None
    v_停15b = None
    v_次 = None
    v_k = None
    v_懒 = None
    v_m = None
    v_平方 = None
    v_记17 = None
    v_停17 = None
    v_n = None
    v_记18 = None
    v_停18a = None
    v_停18b = None
    v_总 = None
    v_记20 = None
    v_退甲 = None
    v_退乙 = None
    v_个数 = None
    v_第一次退 = None
    v_记22 = None
    v_第二次 = None
    v_记23 = None
    v_退后面 = None
    v_叫23 = None
    v_记24 = None
    v_记25 = None
    v_错25 = None
    v_叫25 = None
    v_另一条 = None
    v_记27 = None
    v_计 = None
    v_跑28 = None
    v_停28 = None
    v_记29 = None
    def lcfn21():
        return lcx.send(M检查_积木计数, "读")
    def lcfn22(v_新值, v_旧值):
        lc.list_push(M检查_积木记录, lc.join(v_旧值, "→", v_新值))
    M反应_当变了(lc.fn("", 0, 0, lcfn21), lc.fn("", 2, 2, lcfn22))
    def lcfn23(v_数据):
        lc.list_push(M检查_积木收到的, v_数据)
    lcx.send(M检查_全局总线, "订阅", "积木事件", lc.fn("", 1, 1, lcfn23))
    v_错们 = []
    def lcfn24(v_消息):
        lc.list_push(v_错们, v_消息)
    M反应_设出错时(lc.fn("", 1, 1, lcfn24))
    v_a = M反应_新状态(0.0)
    lcx.send(v_a, "写", lc.add(lcx.send(v_a, "读"), 1.0))
    lcx.send(v_a, "写", lc.add(lcx.send(v_a, "读"), 1.0))
    M检查_报("1", "先写后读，连加两次", lcx.send(v_a, "读"))
    v_b = M反应_新状态(1.0)
    def lcfn25():
        return lc.mul(lcx.send(v_b, "读"), 2.0)
    v_两倍 = M反应_新派生(lc.fn("", 0, 0, lcfn25))
    v_文字 = ""
    v_写了几次 = 0.0
    def lcfn26():
        nonlocal v_写了几次, v_文字
        v_文字 = lc.join("值是", lcx.send(v_两倍, "读"))
        v_写了几次 = lc.add(v_写了几次, 1.0)
    v_停2 = M反应_跟着做(lc.fn("", 0, 0, lcfn26))
    M检查_报("2.0", "跟着做：登记时马上做一次", lc.join(v_文字, "，", v_写了几次))
    lcx.send(v_b, "写", 5.0)
    M检查_报("2a", "改完马上读派生值，是新的", lcx.send(v_两倍, "读"))
    M检查_报("2b", "这一刻跟着做的还没跑", lc.join(v_文字, "，", v_写了几次))
    lcx.send(v_b, "写", 6.0)
    lcx.send(v_b, "写", 7.0)
    M反应_等更新()
    M检查_报("2c", "一段里改三次，只多跑一次", lc.join(v_文字, "，", v_写了几次))
    v_甲 = M反应_新状态(1.0)
    def lcfn27():
        return lc.add(lcx.send(v_甲, "读"), 1.0)
    v_乙 = M反应_新派生(lc.fn("", 0, 0, lcfn27))
    def lcfn28():
        return lc.mul(lcx.send(v_甲, "读"), 10.0)
    v_丙 = M反应_新派生(lc.fn("", 0, 0, lcfn28))
    v_见过的 = []
    def lcfn29():
        v_v = None
        v_v = lc.add(lcx.send(v_乙, "读"), lcx.send(v_丙, "读"))
        lc.list_push(v_见过的, v_v)
        return v_v
    v_丁 = M反应_新派生(lc.fn("", 0, 0, lcfn29))
    M检查_报("3a", "菱形：第一次读丁", lcx.send(v_丁, "读"))
    lcx.send(v_甲, "写", 2.0)
    M检查_报("3b", "菱形：改了甲以后读丁", lcx.send(v_丁, "读"))
    M检查_报("3c", "丁算出过的值（没有半新半旧的）", v_见过的)
    M检查_报("3d", "丁一共算了几次", lcx.getf(v_丁, "算了几次"))
    v_开关 = M反应_新状态(True)
    v_内容 = M反应_新状态("A")
    v_跑4 = 0.0
    v_看到 = ""
    def lcfn30():
        nonlocal v_看到, v_跑4
        v_跑4 = lc.add(v_跑4, 1.0)
        if lc.truthy(lcx.send(v_开关, "读")):
            v_看到 = lcx.send(v_内容, "读")
        else:
            v_看到 = "关"
    v_停4 = M反应_跟着做(lc.fn("", 0, 0, lcfn30))
    lcx.send(v_内容, "写", "B")
    M反应_等更新()
    lcx.send(v_开关, "写", False)
    M反应_等更新()
    lcx.send(v_内容, "写", "C")
    M反应_等更新()
    M检查_报("4", "条件里的依赖关掉以后不再触发", lc.join(v_跑4, "，", v_看到))
    v_c = M反应_新状态(1.0)
    v_跑5 = 0.0
    def lcfn31():
        nonlocal v_跑5
        lcx.send(v_c, "读")
        v_跑5 = lc.add(v_跑5, 1.0)
    v_停5 = M反应_跟着做(lc.fn("", 0, 0, lcfn31))
    lcx.send(v_c, "写", 1.0)
    M反应_等更新()
    M检查_报("5a", "设成同一个值不触发", v_跑5)
    lcx.send(v_c, "写", "1")
    M反应_等更新()
    M检查_报("5b", "数字 1 换成文字“1”：算变了", v_跑5)
    v_表 = M反应_新状态([1.0, 2.0])
    v_跑5c = 0.0
    def lcfn32():
        nonlocal v_跑5c
        lcx.send(v_表, "读")
        v_跑5c = lc.add(v_跑5c, 1.0)
    v_停5c = M反应_跟着做(lc.fn("", 0, 0, lcfn32))
    lcx.send(v_表, "写", [1.0, 2.0])
    M反应_等更新()
    M检查_报("5c", "换成内容一样的另一个列表：算变了", v_跑5c)
    v_同一个 = lcx.send(v_表, "偷看")
    lc.list_push(v_同一个, 3.0)
    lcx.send(v_表, "写", v_同一个)
    M反应_等更新()
    M检查_报("5d", "原地改了再写回同一个列表：不算变（已知的坑）", v_跑5c)
    v_d = M反应_新状态(0.0)
    v_记6 = []
    def lcfn33():
        v_v = None
        v_v = lcx.send(v_d, "读")
        lc.list_push(v_记6, lc.join("做", v_v))
        def lcfn34():
            lc.list_push(v_记6, lc.join("收", v_v))
        return lc.fn("", 0, 0, lcfn34)
    v_停6 = M反应_跟着做(lc.fn("", 0, 0, lcfn33))
    lcx.send(v_d, "写", 1.0)
    M反应_等更新()
    lc.call(v_停6)
    lcx.send(v_d, "写", 2.0)
    M反应_等更新()
    M检查_报("6", "收尾函数：重做前叫、停掉时叫，停掉后不再做", v_记6)
    v_e7 = M反应_新状态(0.0)
    v_跑7 = 0.0
    def lcfn35():
        nonlocal v_跑7
        v_跑7 = lc.add(v_跑7, 1.0)
        lcx.send(v_e7, "写", lc.add(lcx.send(v_e7, "读"), 1.0))
    v_停7 = M反应_跟着做(lc.fn("", 0, 0, lcfn35))
    M反应_等更新()
    M检查_报("7a", "跟着做的事改它自己看的状态：报错停下", v_错们)
    M检查_报("7b", "它一共跑了几次", v_跑7)
    lc.call(v_停7)
    v_绕甲 = None
    v_绕乙 = None
    def lcfn36():
        return lc.add(lcx.send(v_绕乙, "读"), 1.0)
    v_绕甲 = M反应_新派生(lc.fn("", 0, 0, lcfn36))
    def lcfn37():
        return lc.add(lcx.send(v_绕甲, "读"), 1.0)
    v_绕乙 = M反应_新派生(lc.fn("", 0, 0, lcfn37))
    v_结果8 = "没出错"
    try:
        lcx.send(v_绕甲, "读")
    except Exception as lce38:
        v_e = lcx.caught(lce38)
        v_结果8 = lcx.getf(v_e, "消息")
    M检查_报("8", "两个派生值互相绕", v_结果8)
    v_f = M反应_新状态(1.0)
    v_记9 = []
    def lcfn39():
        return lcx.send(v_f, "读")
    def lcfn40(v_新, v_旧):
        lc.list_push(v_记9, lc.join(v_旧, "→", v_新))
    v_停9 = M反应_当变了(lc.fn("", 0, 0, lcfn39), lc.fn("", 2, 2, lcfn40))
    M检查_报("9a", "当…变了：登记时不先叫", v_记9)
    lcx.send(v_f, "写", 2.0)
    lcx.send(v_f, "写", 3.0)
    M反应_等更新()
    M检查_报("9b", "一轮里变多次只叫一次，拿到最后的值和原来的值", v_记9)
    lcx.send(v_f, "写", 9.0)
    lcx.send(v_f, "写", 3.0)
    M反应_等更新()
    M检查_报("9c", "变了又变回来：不叫", v_记9)
    v_记10 = []
    def lcfn41():
        return lcx.send(v_f, "读")
    def lcfn42(v_新, v_旧):
        lc.list_push(v_记10, lc.join(v_旧, "→", v_新))
    v_停10 = M反应_当变了(lc.fn("", 0, 0, lcfn41), lc.fn("", 2, 2, lcfn42), True)
    M检查_报("10", "“马上先做一次”（旧值是空）", v_记10)
    lc.call(v_停9)
    lc.call(v_停10)
    lcx.send(v_f, "写", 4.0)
    M反应_等更新()
    M检查_报("11", "取消以后不再叫", lc.join(lc.size(v_记9), "，", lc.size(v_记10)))
    v_g = M反应_新状态(0.0)
    v_h = M反应_新状态(0.0)
    v_记12 = []
    def lcfn43():
        lc.list_push(v_记12, lc.join(lcx.send(v_g, "读"), "+", lcx.send(v_h, "读")))
    v_停12 = M反应_跟着做(lc.fn("", 0, 0, lcfn43))
    def lcfn44():
        lcx.send(v_g, "写", 1.0)
        M反应_等更新()
        lc.list_push(v_记12, "中间")
        lcx.send(v_h, "写", 1.0)
    M反应_一起改(lc.fn("", 0, 0, lcfn44))
    M反应_等更新()
    M检查_报("12a", "一起改：中间等过，跟着做的也只跑一次", v_记12)
    lcx.send(v_g, "写", 2.0)
    M反应_等更新()
    lcx.send(v_h, "写", 2.0)
    M反应_等更新()
    M检查_报("12b", "不用一起改：等一次跑一次", v_记12)
    def lcfn45():
        lcx.send(v_g, "写", 99.0)
        return 1.0
    v_坏派生 = M反应_新派生(lc.fn("", 0, 0, lcfn45))
    v_结果13 = "没出错"
    try:
        lcx.send(v_坏派生, "读")
    except Exception as lce46:
        v_e = lcx.caught(lce46)
        v_结果13 = lcx.getf(v_e, "消息")
    M检查_报("13a", "派生值的算法里改状态", v_结果13)
    M检查_报("13b", "那个状态没被改", lcx.send(v_g, "偷看"))
    v_主 = M反应_归属()
    v_i = M反应_新状态(0.0)
    v_记14 = []
    def lcfn47():
        def lcfn48():
            lc.list_push(v_记14, lc.join("甲", lcx.send(v_i, "读")))
            def lcfn49():
                lc.list_push(v_记14, "甲收")
            return lc.fn("", 0, 0, lcfn49)
        M反应_跟着做(lc.fn("", 0, 0, lcfn48))
        def lcfn50():
            lc.list_push(v_记14, lc.join("乙", lcx.send(v_i, "读")))
            def lcfn51():
                lc.list_push(v_记14, "乙收")
            return lc.fn("", 0, 0, lcfn51)
        M反应_跟着做(lc.fn("", 0, 0, lcfn50))
    lcx.send(v_主, "里面做", lc.fn("", 0, 0, lcfn47))
    lcx.send(v_i, "写", 1.0)
    M反应_等更新()
    lcx.send(v_主, "收")
    lcx.send(v_i, "写", 2.0)
    M反应_等更新()
    M检查_报("14", "归属收了：里面的都停、收尾都叫（后建的先收）", v_记14)
    v_j = M反应_新状态(0.0)
    v_跑15 = 0.0
    def lcfn52():
        nonlocal v_跑15
        lcx.send(v_j, "偷看")
        v_跑15 = lc.add(v_跑15, 1.0)
    v_停15 = M反应_跟着做(lc.fn("", 0, 0, lcfn52))
    v_跑15b = 0.0
    def lcfn53():
        nonlocal v_跑15b
        def lcfn54():
            return lcx.send(v_j, "读")
        M反应_不记依赖地做(lc.fn("", 0, 0, lcfn54))
        v_跑15b = lc.add(v_跑15b, 1.0)
    v_停15b = M反应_跟着做(lc.fn("", 0, 0, lcfn53))
    lcx.send(v_j, "写", 1.0)
    M反应_等更新()
    M检查_报("15", "偷看、不记依赖地做：不算依赖", lc.join(v_跑15, "，", v_跑15b))
    v_次 = 0.0
    v_k = M反应_新状态(1.0)
    def lcfn55():
        nonlocal v_次
        v_次 = lc.add(v_次, 1.0)
        return lcx.send(v_k, "读")
    v_懒 = M反应_新派生(lc.fn("", 0, 0, lcfn55))
    M检查_报("16a", "派生值没人读就不算", v_次)
    lcx.send(v_懒, "读")
    lcx.send(v_懒, "读")
    M检查_报("16b", "读两次只算一次", v_次)
    lcx.send(v_k, "写", 2.0)
    M检查_报("16c", "依赖变了也不马上算", v_次)
    M检查_报("16d", "再读才算", lc.join(lcx.send(v_懒, "读"), "，", v_次))
    v_m = M反应_新状态(1.0)
    def lcfn56():
        return lc.mul(lcx.send(v_m, "读"), lcx.send(v_m, "读"))
    v_平方 = M反应_新派生(lc.fn("", 0, 0, lcfn56))
    v_记17 = []
    def lcfn57():
        lc.list_push(v_记17, lcx.send(v_平方, "读"))
    v_停17 = M反应_跟着做(lc.fn("", 0, 0, lcfn57))
    lcx.send(v_m, "写", 2.0)
    M反应_等更新()
    lcx.send(v_m, "写", lc.sub(0.0, 2.0))
    M反应_等更新()
    M检查_报("17", "跟着做的事读派生值（已知的粗糙处：派生值没变也重做一次）", v_记17)
    v_n = M反应_新状态(0.0)
    v_记18 = []
    def lcfn58():
        if lc.eq(lcx.send(v_n, "读"), 1.0):
            raise lcx.to_err("故意的")
    v_停18a = M反应_跟着做(lc.fn("", 0, 0, lcfn58))
    def lcfn59():
        lc.list_push(v_记18, lc.join("好", lcx.send(v_n, "读")))
    v_停18b = M反应_跟着做(lc.fn("", 0, 0, lcfn59))
    lcx.send(v_n, "写", 1.0)
    M反应_等更新()
    M检查_报("18", "一件跟着做的事出错，不影响别的", lc.join(v_记18, "｜", lc.list_get(v_错们, lc.sub(lc.size(v_错们), 1.0))))
    lcx.send(M检查_积木计数, "写", 5.0)
    def lcfn60():
        lcx.send(M检查_积木计数, "写", 6.0)
        lcx.send(M检查_积木计数, "写", 7.0)
    M反应_一起改(lc.fn("", 0, 0, lcfn60))
    M反应_等更新()
    M检查_报("19a", "用积木外观写的“当…变了”", M检查_积木记录)
    M检查_报("19b", "用积木外观读状态", lcx.send(M检查_积木计数, "读"))
    v_总 = M总线_事件总线()
    v_记20 = []
    def lcfn61(v_数据):
        lc.list_push(v_记20, lc.join("甲:", v_数据))
    v_退甲 = lcx.send(v_总, "订阅", "招呼", lc.fn("", 1, 1, lcfn61))
    def lcfn62(v_数据):
        lc.list_push(v_记20, lc.join("乙:", v_数据))
    v_退乙 = lcx.send(v_总, "订阅", "招呼", lc.fn("", 1, 1, lcfn62))
    v_个数 = lcx.send(v_总, "发出", "招呼", "你好")
    M检查_报("20", "订阅和发出：按订阅的先后叫", lc.join(v_记20, "，叫到 ", v_个数, " 个"))
    v_第一次退 = lc.call(v_退甲)
    lcx.send(v_总, "发出", "招呼", "再见")
    M检查_报("21", "退订以后不叫；再退一次也没事", lc.join(v_记20, "，", v_第一次退, "，", lc.call(v_退甲)))
    v_记22 = []
    def lcfn63(v_数据):
        lc.list_push(v_记22, v_数据)
    lcx.send(v_总, "只听一次", "铃", lc.fn("", 1, 1, lcfn63))
    lcx.send(v_总, "发出", "铃", 1.0)
    v_第二次 = lcx.send(v_总, "发出", "铃", 2.0)
    M检查_报("22", "只听一次", lc.join(v_记22, "，第二次叫到 ", v_第二次, "，还在听的 ", lcx.send(v_总, "有几个在听", "铃")))
    v_记23 = []
    v_退后面 = None
    def lcfn64(v_数据):
        lc.list_push(v_记23, "一")
        lc.call(v_退后面)
    lcx.send(v_总, "订阅", "改", lc.fn("", 1, 1, lcfn64))
    def lcfn65(v_数据):
        lc.list_push(v_记23, "二")
    v_退后面 = lcx.send(v_总, "订阅", "改", lc.fn("", 1, 1, lcfn65))
    def lcfn66(v_数据):
        lc.list_push(v_记23, "三")
    lcx.send(v_总, "订阅", "改", lc.fn("", 1, 1, lcfn66))
    v_叫23 = lcx.send(v_总, "发出", "改")
    M检查_报("23", "发出过程中把排在后面的退订了：它不被叫", lc.join(v_记23, "，叫到 ", v_叫23))
    v_记24 = []
    def lcfn67(v_数据):
        lc.list_push(v_记24, "老")
        def lcfn68(v_数据2):
            lc.list_push(v_记24, "新")
        lcx.send(v_总, "订阅", "加", lc.fn("", 1, 1, lcfn68))
    lcx.send(v_总, "订阅", "加", lc.fn("", 1, 1, lcfn67))
    lcx.send(v_总, "发出", "加")
    lcx.send(v_总, "发出", "加")
    M检查_报("24", "发出过程中新订阅的：这一次不叫，下一次才叫", v_记24)
    v_记25 = []
    v_错25 = []
    def lcfn69(v_消息, v_事件名):
        lc.list_push(v_错25, lc.join(v_事件名, ":", v_消息))
    lcx.send(v_总, "设出错时", lc.fn("", 2, 2, lcfn69))
    def lcfn70(v_数据):
        raise lcx.to_err("坏了")
    lcx.send(v_总, "订阅", "炸", lc.fn("", 1, 1, lcfn70))
    def lcfn71(v_数据):
        lc.list_push(v_记25, "还是叫到了")
    lcx.send(v_总, "订阅", "炸", lc.fn("", 1, 1, lcfn71))
    def lcfn72():
        lc.list_push(v_记25, "不该到这里")
    lcx.send(v_总, "订阅", "炸", lc.fn("", 0, 0, lcfn72))
    v_叫25 = lcx.send(v_总, "发出", "炸", 0.0)
    M检查_报("25", "一个处理出错（或者参数个数不对）不影响别的", lc.join(v_记25, "｜", v_错25, "｜", v_叫25))
    M检查_报("26", "没人听的事件", lcx.send(v_总, "发出", "没人听"))
    v_另一条 = M总线_事件总线()
    v_记27 = []
    def lcfn73(v_数据):
        lc.list_push(v_记27, v_数据)
    lcx.send(v_另一条, "订阅", "招呼", lc.fn("", 1, 1, lcfn73))
    lcx.send(v_总, "发出", "招呼", "只给第一条")
    M检查_报("27", "两条总线互不相干", lc.join(lc.size(v_记27), "，", lcx.send(v_另一条, "发出", "招呼", "给第二条"), "，", v_记27))
    v_计 = M反应_新状态(0.0)
    v_跑28 = 0.0
    def lcfn74():
        nonlocal v_跑28
        lcx.send(v_计, "读")
        v_跑28 = lc.add(v_跑28, 1.0)
    v_停28 = M反应_跟着做(lc.fn("", 0, 0, lcfn74))
    def lcfn75(v_数据):
        lcx.send(v_计, "写", lc.add(lcx.send(v_计, "偷看"), v_数据))
    lcx.send(v_总, "订阅", "加一", lc.fn("", 1, 1, lcfn75))
    lcx.send(v_总, "发出", "加一", 1.0)
    lcx.send(v_总, "发出", "加一", 1.0)
    lcx.send(v_总, "发出", "加一", 1.0)
    M反应_等更新()
    M检查_报("28", "事件处理里改状态：三次改动，跟着做的只多跑一次", lc.join(lcx.send(v_计, "偷看"), "，", v_跑28))
    v_记29 = []
    def lcfn76(v_数据):
        lc.list_push(v_记29, "外1")
        lcx.send(v_总, "发出", "内")
        lc.list_push(v_记29, "外1完")
    lcx.send(v_总, "订阅", "外", lc.fn("", 1, 1, lcfn76))
    def lcfn77(v_数据):
        lc.list_push(v_记29, "外2")
    lcx.send(v_总, "订阅", "外", lc.fn("", 1, 1, lcfn77))
    def lcfn78(v_数据):
        lc.list_push(v_记29, "内")
    lcx.send(v_总, "订阅", "内", lc.fn("", 1, 1, lcfn78))
    lcx.send(v_总, "发出", "外")
    M检查_报("29", "处理里再发出：里面的先做完", v_记29)
    lcx.send(M检查_全局总线, "发出", "积木事件", "来了")
    lcx.send(M检查_全局总线, "发出", "积木事件", None)
    M检查_报("30", "用积木外观写的订阅和发出", M检查_积木收到的)



def lc_start():
    lc_main_检查()
    host.ready()


lcx.run(lc_start)
