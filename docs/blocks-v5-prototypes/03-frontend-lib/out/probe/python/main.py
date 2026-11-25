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
        if lcx.is_same(v_新值, lc_self.f_值):
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
        if (not lcx.is_same(v_新, v_旧)):
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


def M反应_收尾时(v_收法):
    if (not lc.is_null(M反应_当前归属)):
        lcx.send(M反应_当前归属, "记", v_收法)


M反应_收尾时 = lc.fn("收尾时", 1, 1, M反应_收尾时)


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



# ———— 模块 探针要等的处理 ————


def lc_main_探针要等的处理():
    v_总 = None
    v_记 = None
    v_总 = M总线_事件总线()
    v_记 = []
    def lcfn21(v_消息, v_事件名):
        lc.list_push(v_记, lc.join("出错：", v_消息))
    lcx.send(v_总, "设出错时", lc.fn("", 2, 2, lcfn21))
    def lcfn22(v_数据):
        lc.list_push(v_记, "开始")
        M反应_等更新()
        lc.list_push(v_记, "等完了")
    lcx.send(v_总, "订阅", "慢", lc.fn("", 1, 1, lcfn22))
    lcx.send(v_总, "发出", "慢")
    lc.log(lc.join("发出刚回来：", v_记))
    M反应_等更新()
    lc.log(lc.join("又等了一拍：", v_记))



def lc_start():
    lc_main_探针要等的处理()
    host.ready()


lcx.run(lc_start)
