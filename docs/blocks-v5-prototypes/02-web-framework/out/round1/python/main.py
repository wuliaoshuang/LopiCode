# 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。
import lc_lang as lc
import lcx_ext as lcx
import host_python as host


# ———— 模块 错误们 ————
class M错误们_HTTP错误(lcx.Err):
    def __init__(lc_self, v_状态码, v_消息, v_详情=None):
        super(M错误们_HTTP错误, lc_self).__init__(v_消息)
        lc_self.f_状态码 = 500.0
        lc_self.f_详情 = None
        lc_self.f_状态码 = v_状态码
        lc_self.f_详情 = v_详情

    def m_变成内容(lc_self):
        v_内容 = None
        v_内容 = lc.dict_of("error", lc_self.f_消息)
        if (not lc.is_null(lc_self.f_详情)):
            lc.set_item(v_内容, "details", lc_self.f_详情)
        return v_内容


lcx.named(M错误们_HTTP错误, "HTTP错误")
lcx.sig(M错误们_HTTP错误.m_变成内容, 0, 0)


class M错误们_请求不对(M错误们_HTTP错误):
    def __init__(lc_self, v_消息, v_详情=None):
        super(M错误们_请求不对, lc_self).__init__(400.0, v_消息, v_详情)


lcx.named(M错误们_请求不对, "请求不对")


class M错误们_未授权(M错误们_HTTP错误):
    def __init__(lc_self, v_消息="请先登录"):
        super(M错误们_未授权, lc_self).__init__(401.0, v_消息)


lcx.named(M错误们_未授权, "未授权")


class M错误们_没有这个(M错误们_HTTP错误):
    def __init__(lc_self, v_消息="没有这个接口"):
        super(M错误们_没有这个, lc_self).__init__(404.0, v_消息)


lcx.named(M错误们_没有这个, "没有这个")


class M错误们_方式不对(M错误们_HTTP错误):
    def __init__(lc_self, v_允许的):
        super(M错误们_方式不对, lc_self).__init__(405.0, "这个地址不支持这种请求方式")
        lc_self.f_允许的 = []
        lc_self.f_允许的 = v_允许的


lcx.named(M错误们_方式不对, "方式不对")


class M错误们_校验没过(M错误们_HTTP错误):
    def __init__(lc_self, v_问题们):
        super(M错误们_校验没过, lc_self).__init__(422.0, "提交的内容不对", v_问题们)


lcx.named(M错误们_校验没过, "校验没过")



# ———— 模块 响应 ————
class M响应_响应(lcx.Obj):
    def __init__(lc_self, v_状态码, v_类型, v_内容):
        super(M响应_响应, lc_self).__init__()
        lc_self.f_状态码 = 200.0
        lc_self.f_头 = lc.dict_of()
        lc_self.f_内容 = ""
        lc_self.f_状态码 = v_状态码
        lc_self.f_头 = lc.dict_of()
        if lc.ne(v_类型, ""):
            lc.set_item(lc_self.f_头, "Content-Type", v_类型)
        lc_self.f_内容 = v_内容

    @staticmethod
    def m_JSON(v_状态码, v_值):
        return M响应_响应(v_状态码, "application/json; charset=utf-8", lc.to_json(v_值))

    @staticmethod
    def m_文字(v_状态码, v_值):
        return M响应_响应(v_状态码, "text/plain; charset=utf-8", lc.to_text(v_值))

    @staticmethod
    def m_空的():
        return M响应_响应(204.0, "", "")

    def m_加头(lc_self, v_名字, v_值):
        lc.set_item(lc_self.f_头, v_名字, lc.to_text(v_值))
        return lc_self

    def m_变成字典(lc_self):
        return lc.dict_of("status", lc_self.f_状态码, "headers", lc_self.f_头, "body", lc_self.f_内容)


lcx.named(M响应_响应, "响应")
lcx.sig(M响应_响应.m_JSON, 2, 2)
lcx.sig(M响应_响应.m_文字, 2, 2)
lcx.sig(M响应_响应.m_空的, 0, 0)
lcx.sig(M响应_响应.m_加头, 2, 2)
lcx.sig(M响应_响应.m_变成字典, 0, 0)



# ———— 模块 上下文 ————
class M上下文_上下文(lcx.Obj):
    def __init__(lc_self, v_请求):
        super(M上下文_上下文, lc_self).__init__()
        lc_self.f_方式 = ""
        lc_self.f_路径 = ""
        lc_self.f_段们 = []
        lc_self.f_路径参数们 = lc.dict_of()
        lc_self.f_网址参数们 = lc.dict_of()
        lc_self.f_数据 = lc.dict_of()
        lc_self.f_请求 = lc.dict_of()
        lc_self.f_内容读过了 = False
        lc_self.f_内容值 = None
        v_段 = None
        lc_self.f_请求 = v_请求
        lc_self.f_方式 = lc.dict_get(v_请求, "method")
        lc_self.f_路径 = lc.dict_get(v_请求, "path")
        lc_self.f_段们 = []
        for lci1, lcx2 in enumerate(lc.items(lc.split(lc.dict_get(v_请求, "path"), "/"))):
            v_段 = lcx2
            if lc.ne(v_段, ""):
                lc.list_push(lc_self.f_段们, host.url_decode(v_段))
        lc_self.f_路径参数们 = lc.dict_of()
        lc_self.f_网址参数们 = M上下文_解析网址参数(lc.dict_get(v_请求, "query"))
        lc_self.f_数据 = lc.dict_of()

    def m_路径参数(lc_self, v_名字):
        return lc.dict_get(lc_self.f_路径参数们, v_名字)

    def m_网址参数(lc_self, v_名字):
        return lc.dict_get(lc_self.f_网址参数们, v_名字)

    def m_请求头(lc_self, v_名字):
        return lc.dict_get(lc.dict_get(lc_self.f_请求, "headers"), lc.lower(v_名字))

    def m_内容(lc_self):
        if (not lc.truthy(lc_self.f_内容读过了)):
            lc_self.f_内容值 = lc.from_json(lc.dict_get(lc_self.f_请求, "body"))
            lc_self.f_内容读过了 = True
        return lc_self.f_内容值

    def m_放(lc_self, v_名字, v_值):
        lc.set_item(lc_self.f_数据, v_名字, v_值)

    def m_取(lc_self, v_名字):
        return lc.dict_get(lc_self.f_数据, v_名字)


lcx.named(M上下文_上下文, "上下文")
lcx.sig(M上下文_上下文.m_路径参数, 1, 1)
lcx.sig(M上下文_上下文.m_网址参数, 1, 1)
lcx.sig(M上下文_上下文.m_请求头, 1, 1)
lcx.sig(M上下文_上下文.m_内容, 0, 0)
lcx.sig(M上下文_上下文.m_放, 2, 2)
lcx.sig(M上下文_上下文.m_取, 1, 1)


def M上下文_解析网址参数(v_原文):
    v_表 = None
    v_段 = None
    v_等号 = None
    v_键 = None
    v_值 = None
    v_表 = lc.dict_of()
    for lci3, lcx4 in enumerate(lc.items(lc.split(v_原文, "&"))):
        v_段 = lcx4
        if lc.eq(v_段, ""):
            continue
        v_等号 = lc.index_of(v_段, "=")
        v_键 = v_段
        v_值 = ""
        if lc.ge(v_等号, 0.0):
            v_键 = lc.substring(v_段, 0.0, v_等号)
            v_值 = lc.substring(v_段, lc.add(v_等号, 1.0), lc.size(v_段))
        v_键 = host.url_decode(lc.replace(v_键, "+", " "))
        if (not lc.dict_has(v_表, v_键)):
            lc.set_item(v_表, v_键, host.url_decode(lc.replace(v_值, "+", " ")))
    return v_表


M上下文_解析网址参数 = lc.fn("解析网址参数", 1, 1, M上下文_解析网址参数)



# ———— 模块 中间件 ————
class M中间件_错误处理(lcx.Obj):
    def __init__(lc_self, *lc_args):
        super(M中间件_错误处理, lc_self).__init__(*lc_args)

    def m_处理(lc_self, v_上下文, v_下一步):
        v_e = None
        v_回复 = None
        try:
            return lc.call(v_下一步, v_上下文)
        except Exception as lce5:
            v_e = lcx.caught(lce5)
            if not isinstance(v_e, M错误们_HTTP错误):
                raise
            v_回复 = M响应_响应.m_JSON(lcx.getf(v_e, "状态码"), lcx.send(v_e, "变成内容"))
            if isinstance(v_e, M错误们_方式不对):
                lcx.send(v_回复, "加头", "Allow", lc.list_join(lcx.getf(v_e, "允许的"), ", "))
            return v_回复


lcx.named(M中间件_错误处理, "错误处理")
lcx.sig(M中间件_错误处理.m_处理, 2, 2)


class M中间件_兜底(lcx.Obj):
    def __init__(lc_self, v_出错时=None):
        super(M中间件_兜底, lc_self).__init__()
        lc_self.f_出错时 = None
        lc_self.f_出错时 = v_出错时

    def m_处理(lc_self, v_上下文, v_下一步):
        v_e = None
        try:
            return lc.call(v_下一步, v_上下文)
        except Exception as lce6:
            v_e = lcx.caught(lce6)
            if (not lc.is_null(lc_self.f_出错时)):
                lc.call(lc_self.f_出错时, v_e, v_上下文)
            return M响应_响应.m_JSON(500.0, lc.dict_of("error", "服务器内部出错"))


lcx.named(M中间件_兜底, "兜底")
lcx.sig(M中间件_兜底.m_处理, 2, 2)


def M中间件_包一层(v_这一层, v_里面):
    if lc.is_type(v_这一层, "function"):
        def lcfn7(v_上下文):
            return lc.call(v_这一层, v_上下文, v_里面)
        return lc.fn("", 1, 1, lcfn7)
    def lcfn8(v_上下文):
        return lcx.send(v_这一层, "处理", v_上下文, v_里面)
    return lc.fn("", 1, 1, lcfn8)


M中间件_包一层 = lc.fn("包一层", 2, 2, M中间件_包一层)


def M中间件_串起来(v_中间件们, v_最里面):
    v_结果 = None
    v_i = None
    v_结果 = v_最里面
    v_i = lc.sub(lc.size(v_中间件们), 1.0)
    while lc.ge(v_i, 0.0):
        v_结果 = M中间件_包一层(lc.list_get(v_中间件们, v_i), v_结果)
        v_i = lc.sub(v_i, 1.0)
    return v_结果


M中间件_串起来 = lc.fn("串起来", 2, 2, M中间件_串起来)



# ———— 模块 路由 ————
class M路由_路由器(lcx.Obj):
    def __init__(lc_self, v_前缀="", v_上级=None):
        super(M路由_路由器, lc_self).__init__()
        lc_self.f_前缀段 = []
        lc_self.f_上级 = None
        lc_self.f_中间件们 = []
        lc_self.f_路由们 = []
        lc_self.f_分组们 = []
        lc_self.f_前缀段 = M路由_切路径(v_前缀)
        if (not lc.is_null(v_上级)):
            lc_self.f_前缀段 = lc.list_concat(lcx.getf(v_上级, "前缀段"), lc_self.f_前缀段)
        lc_self.f_上级 = v_上级
        lc_self.f_中间件们 = []
        lc_self.f_路由们 = []
        lc_self.f_分组们 = []

    def m_用(lc_self, v_一个中间件):
        lc.list_push(lc_self.f_中间件们, v_一个中间件)
        return lc_self

    def m_分组(lc_self, v_前缀):
        v_组 = None
        v_组 = M路由_路由器(v_前缀, lc_self)
        lc.list_push(lc_self.f_分组们, v_组)
        return v_组

    def m_加(lc_self, v_方式, v_路径, v_处理):
        lc.list_push(lc_self.f_路由们, lc.dict_of("method", v_方式, "segments", lc.list_concat(lc_self.f_前缀段, M路由_切路径(v_路径)), "handler", v_处理))
        return lc_self

    def m_GET(lc_self, v_路径, v_处理):
        return lcx.send(lc_self, "加", "GET", v_路径, v_处理)

    def m_POST(lc_self, v_路径, v_处理):
        return lcx.send(lc_self, "加", "POST", v_路径, v_处理)

    def m_PUT(lc_self, v_路径, v_处理):
        return lcx.send(lc_self, "加", "PUT", v_路径, v_处理)

    def m_PATCH(lc_self, v_路径, v_处理):
        return lcx.send(lc_self, "加", "PATCH", v_路径, v_处理)

    def m_DELETE(lc_self, v_路径, v_处理):
        return lcx.send(lc_self, "加", "DELETE", v_路径, v_处理)

    def m_一路的中间件(lc_self):
        if lc.is_null(lc_self.f_上级):
            return []
        return lc.list_concat(lcx.send(lc_self.f_上级, "一路的中间件"), lc_self.f_中间件们)

    def m_全部路由(lc_self):
        v_全部 = None
        v_路由 = None
        v_组 = None
        v_全部 = []
        for lci9, lcx10 in enumerate(lc.items(lc_self.f_路由们)):
            v_路由 = lcx10
            lc.list_push(v_全部, lc.dict_of("route", v_路由, "router", lc_self))
        for lci11, lcx12 in enumerate(lc.items(lc_self.f_分组们)):
            v_组 = lcx12
            v_全部 = lc.list_concat(v_全部, lcx.send(v_组, "全部路由"))
        return v_全部


lcx.named(M路由_路由器, "路由器")
lcx.sig(M路由_路由器.m_用, 1, 1)
lcx.sig(M路由_路由器.m_分组, 1, 1)
lcx.sig(M路由_路由器.m_加, 3, 3)
lcx.sig(M路由_路由器.m_GET, 2, 2)
lcx.sig(M路由_路由器.m_POST, 2, 2)
lcx.sig(M路由_路由器.m_PUT, 2, 2)
lcx.sig(M路由_路由器.m_PATCH, 2, 2)
lcx.sig(M路由_路由器.m_DELETE, 2, 2)
lcx.sig(M路由_路由器.m_一路的中间件, 0, 0)
lcx.sig(M路由_路由器.m_全部路由, 0, 0)


class M路由_应用(M路由_路由器):
    def __init__(lc_self):
        super(M路由_应用, lc_self).__init__()

    def m_找并处理(lc_self, v_上下文):
        v_允许的 = None
        v_项 = None
        v_路由 = None
        v_参数 = None
        v_处理 = None
        v_链 = None
        v_允许的 = []
        for lci13, lcx14 in enumerate(lc.items(lcx.send(lc_self, "全部路由"))):
            v_项 = lcx14
            v_路由 = lc.dict_get(v_项, "route")
            v_参数 = M路由_对得上(lc.dict_get(v_路由, "segments"), lcx.getf(v_上下文, "段们"))
            if lc.is_null(v_参数):
                continue
            if lc.ne(lc.dict_get(v_路由, "method"), lcx.getf(v_上下文, "方式")):
                if (not lc.list_contains(v_允许的, lc.dict_get(v_路由, "method"))):
                    lc.list_push(v_允许的, lc.dict_get(v_路由, "method"))
                continue
            lcx.setf(v_上下文, "路径参数们", v_参数)
            v_处理 = lc.dict_get(v_路由, "handler")
            def lcfn15(v_上下文):
                return M路由_变成响应(lc.call(v_处理, v_上下文))
            v_链 = M中间件_串起来(lcx.send(lc.dict_get(v_项, "router"), "一路的中间件"), lc.fn("", 1, 1, lcfn15))
            return lc.call(v_链, v_上下文)
        if lc.gt(lc.size(v_允许的), 0.0):
            raise lcx.to_err(M错误们_方式不对(v_允许的))
        raise lcx.to_err(M错误们_没有这个())

    def m_处理请求(lc_self, v_请求):
        v_自己 = None
        v_链 = None
        v_回复 = None
        v_e = None
        v_自己 = lc_self
        def lcfn16(v_上下文):
            return lcx.send(v_自己, "找并处理", v_上下文)
        v_链 = M中间件_串起来(lc_self.f_中间件们, lc.fn("", 1, 1, lcfn16))
        v_回复 = None
        try:
            v_回复 = M路由_变成响应(lc.call(v_链, M上下文_上下文(v_请求)))
        except Exception as lce17:
            v_e = lcx.caught(lce17)
            v_回复 = M响应_响应.m_JSON(500.0, lc.dict_of("error", "服务器内部出错"))
        return lcx.send(v_回复, "变成字典")

    def m_开始服务(lc_self, v_端口):
        v_自己 = None
        v_自己 = lc_self
        def lcfn18(v_请求):
            return lcx.send(v_自己, "处理请求", v_请求)
        host.http_serve(v_端口, lc.fn("", 1, 1, lcfn18))


lcx.named(M路由_应用, "应用")
lcx.sig(M路由_应用.m_找并处理, 1, 1)
lcx.sig(M路由_应用.m_处理请求, 1, 1)
lcx.sig(M路由_应用.m_开始服务, 1, 1)


def M路由_切路径(v_路径):
    v_段们 = None
    v_段 = None
    v_段们 = []
    for lci19, lcx20 in enumerate(lc.items(lc.split(v_路径, "/"))):
        v_段 = lcx20
        if lc.ne(v_段, ""):
            lc.list_push(v_段们, v_段)
    return v_段们


M路由_切路径 = lc.fn("切路径", 1, 1, M路由_切路径)


def M路由_变成响应(v_值):
    if isinstance(v_值, M响应_响应):
        return v_值
    elif lc.is_null(v_值):
        return M响应_响应.m_空的()
    elif lc.is_type(v_值, "text"):
        return M响应_响应.m_文字(200.0, v_值)
    return M响应_响应.m_JSON(200.0, v_值)


M路由_变成响应 = lc.fn("变成响应", 1, 1, M路由_变成响应)


def M路由_对得上(v_模式, v_段们):
    v_参数 = None
    v_想要 = None
    v_i = None
    v_实际 = None
    if lc.ne(lc.size(v_模式), lc.size(v_段们)):
        return None
    v_参数 = lc.dict_of()
    for lci21, lcx22 in enumerate(lc.items(v_模式)):
        v_想要 = lcx22
        v_i = float(lci21)
        v_实际 = lc.list_get(v_段们, v_i)
        if lc.starts_with(v_想要, ":"):
            lc.set_item(v_参数, lc.substring(v_想要, 1.0, lc.size(v_想要)), v_实际)
        elif lc.ne(v_想要, v_实际):
            return None
    return v_参数


M路由_对得上 = lc.fn("对得上", 2, 2, M路由_对得上)



# ———— 模块 校验 ————
class M校验_校验器(lcx.Obj):
    def __init__(lc_self):
        super(M校验_校验器, lc_self).__init__()
        lc_self.f_规则们 = []
        lc_self.f_规则们 = []

    def m_规则(lc_self, v_一条):
        lc.list_push(lc_self.f_规则们, v_一条)
        return lc_self

    def m_必填(lc_self, v_字段):
        def lcfn23(v_数据):
            if lc.is_null(lc.dict_get(v_数据, v_字段)):
                return lc.join(v_字段, " 必须填")
            return None
        return lcx.send(lc_self, "规则", lc.fn("", 1, 1, lcfn23))

    def m_文字(lc_self, v_字段, v_最短, v_最长):
        def lcfn24(v_数据):
            v_值 = None
            v_值 = lc.dict_get(v_数据, v_字段)
            if lc.is_null(v_值):
                return None
            elif (not lc.is_type(v_值, "text")):
                return lc.join(v_字段, " 要是文字")
            elif (lc.lt(lc.size(v_值), v_最短) or lc.gt(lc.size(v_值), v_最长)):
                return lc.join(v_字段, " 的长度要在 ", v_最短, " 到 ", v_最长, " 之间")
            return None
        return lcx.send(lc_self, "规则", lc.fn("", 1, 1, lcfn24))

    def m_数字(lc_self, v_字段, v_最小, v_最大):
        def lcfn25(v_数据):
            v_值 = None
            v_值 = lc.dict_get(v_数据, v_字段)
            if lc.is_null(v_值):
                return None
            elif (not lc.is_type(v_值, "number")):
                return lc.join(v_字段, " 要是数字")
            elif (lc.lt(v_值, v_最小) or lc.gt(v_值, v_最大)):
                return lc.join(v_字段, " 要在 ", v_最小, " 到 ", v_最大, " 之间")
            return None
        return lcx.send(lc_self, "规则", lc.fn("", 1, 1, lcfn25))

    def m_其中之一(lc_self, v_字段, v_可选的):
        def lcfn26(v_数据):
            v_值 = None
            v_值 = lc.dict_get(v_数据, v_字段)
            if lc.is_null(v_值):
                return None
            elif (not lc.list_contains(v_可选的, v_值)):
                return lc.join(v_字段, " 只能是 ", lc.list_join(v_可选的, "、"), " 里的一个")
            return None
        return lcx.send(lc_self, "规则", lc.fn("", 1, 1, lcfn26))

    def m_检查(lc_self, v_数据):
        v_问题们 = None
        v_一条 = None
        v_问题 = None
        if (not lc.is_type(v_数据, "dict")):
            raise lcx.to_err(M错误们_校验没过(["提交的内容要是一个 JSON 对象"]))
        v_问题们 = []
        for lci27, lcx28 in enumerate(lc.items(lc_self.f_规则们)):
            v_一条 = lcx28
            v_问题 = lc.call(v_一条, v_数据)
            if (not lc.is_null(v_问题)):
                lc.list_push(v_问题们, v_问题)
        if lc.gt(lc.size(v_问题们), 0.0):
            raise lcx.to_err(M错误们_校验没过(v_问题们))
        return v_数据


lcx.named(M校验_校验器, "校验器")
lcx.sig(M校验_校验器.m_规则, 1, 1)
lcx.sig(M校验_校验器.m_必填, 1, 1)
lcx.sig(M校验_校验器.m_文字, 3, 3)
lcx.sig(M校验_校验器.m_数字, 3, 3)
lcx.sig(M校验_校验器.m_其中之一, 2, 2)
lcx.sig(M校验_校验器.m_检查, 1, 1)


def M校验_要数字(v_文字, v_名字):
    if lc.ne(lc.to_text(lc.to_number(v_文字)), v_文字):
        raise lcx.to_err(M错误们_请求不对(lc.join(v_名字, " 要是数字")))
    return lc.to_number(v_文字)


M校验_要数字 = lc.fn("要数字", 2, 2, M校验_要数字)



# ———— 模块 仓库 ————
class M仓库_仓库(lcx.Obj):
    def __init__(lc_self, v_名字):
        super(M仓库_仓库, lc_self).__init__()
        lc_self.f_名字 = ""
        lc_self.f_名字 = v_名字

    def m_读(lc_self):
        v_库 = None
        v_库 = host.store_get(lc.join("仓库:", lc_self.f_名字))
        if lc.is_null(v_库):
            return lc.dict_of("next", 1.0, "rows", [])
        return v_库

    def m_写(lc_self, v_库):
        host.store_set(lc.join("仓库:", lc_self.f_名字), v_库)

    def m_全部(lc_self):
        return lc.dict_get(lcx.send(lc_self, "读"), "rows")

    def m_取(lc_self, v_id):
        def lcfn29(v_行):
            return lc.eq(lc.dict_get(v_行, "id"), v_id)
        return lc.list_find(lcx.send(lc_self, "全部"), lc.fn("", 1, 1, lcfn29))

    def m_加(lc_self, v_内容):
        v_库 = None
        v_行 = None
        v_库 = lcx.send(lc_self, "读")
        v_行 = lc.dict_merge(v_内容, lc.dict_of("id", lc.dict_get(v_库, "next")))
        lc.set_item(v_库, "next", lc.add(lc.dict_get(v_库, "next"), 1.0))
        lc.list_push(lc.dict_get(v_库, "rows"), v_行)
        lcx.send(lc_self, "写", v_库)
        return v_行

    def m_改(lc_self, v_id, v_内容):
        v_库 = None
        v_结果 = None
        v_行 = None
        v_i = None
        v_库 = lcx.send(lc_self, "读")
        v_结果 = None
        for lci30, lcx31 in enumerate(lc.items(lc.dict_get(v_库, "rows"))):
            v_行 = lcx31
            v_i = float(lci30)
            if lc.eq(lc.dict_get(v_行, "id"), v_id):
                v_结果 = lc.dict_merge(lc.dict_merge(v_行, v_内容), lc.dict_of("id", v_id))
                lc.list_set(lc.dict_get(v_库, "rows"), v_i, v_结果)
        if (not lc.is_null(v_结果)):
            lcx.send(lc_self, "写", v_库)
        return v_结果

    def m_删(lc_self, v_id):
        v_库 = None
        v_剩下 = None
        v_库 = lcx.send(lc_self, "读")
        def lcfn32(v_行):
            return lc.ne(lc.dict_get(v_行, "id"), v_id)
        v_剩下 = lc.list_filter(lc.dict_get(v_库, "rows"), lc.fn("", 1, 1, lcfn32))
        if lc.eq(lc.size(v_剩下), lc.size(lc.dict_get(v_库, "rows"))):
            return False
        lc.set_item(v_库, "rows", v_剩下)
        lcx.send(lc_self, "写", v_库)
        return True


lcx.named(M仓库_仓库, "仓库")
lcx.sig(M仓库_仓库.m_读, 0, 0)
lcx.sig(M仓库_仓库.m_写, 1, 1)
lcx.sig(M仓库_仓库.m_全部, 0, 0)
lcx.sig(M仓库_仓库.m_取, 1, 1)
lcx.sig(M仓库_仓库.m_加, 1, 1)
lcx.sig(M仓库_仓库.m_改, 2, 2)
lcx.sig(M仓库_仓库.m_删, 1, 1)



# ———— 模块 书店服务 ————
class M书店服务_不许(M错误们_HTTP错误):
    def __init__(lc_self, v_需要):
        super(M书店服务_不许, lc_self).__init__(403.0, "这件事只有管理员能做")
        lc_self.f_需要 = ""
        lc_self.f_需要 = v_需要

    def m_变成内容(lc_self):
        v_内容 = None
        v_内容 = super(M书店服务_不许, lc_self).m_变成内容()
        lc.set_item(v_内容, "need", lc_self.f_需要)
        return v_内容


lcx.named(M书店服务_不许, "不许")
lcx.sig(M书店服务_不许.m_变成内容, 0, 0)


class M书店服务_茶壶(M错误们_HTTP错误):
    def __init__(lc_self):
        super(M书店服务_茶壶, lc_self).__init__(418.0, "我是茶壶")

    def m_变成内容(lc_self):
        return lc.dict_merge(super(M书店服务_茶壶, lc_self).m_变成内容(), lc.dict_of("tea", "龙井"))


lcx.named(M书店服务_茶壶, "茶壶")
lcx.sig(M书店服务_茶壶.m_变成内容, 0, 0)


class M书店服务_预检(lcx.Obj):
    def __init__(lc_self, *lc_args):
        super(M书店服务_预检, lc_self).__init__(*lc_args)

    def m_处理(lc_self, v_上下文, v_下一步):
        if lc.eq(lcx.getf(v_上下文, "方式"), "OPTIONS"):
            return lcx.send(M响应_响应.m_空的(), "加头", "Allow", "GET, POST, PUT, DELETE")
        return lc.call(v_下一步, v_上下文)


lcx.named(M书店服务_预检, "预检")
lcx.sig(M书店服务_预检.m_处理, 2, 2)


class M书店服务_鉴权(lcx.Obj):
    def __init__(lc_self, v_钥匙们):
        super(M书店服务_鉴权, lc_self).__init__()
        lc_self.f_钥匙们 = lc.dict_of()
        lc_self.f_钥匙们 = v_钥匙们

    def m_处理(lc_self, v_上下文, v_下一步):
        v_头 = None
        v_用户 = None
        v_头 = lcx.send(v_上下文, "请求头", "Authorization")
        if (lc.is_null(v_头) or (not lc.starts_with(v_头, "Bearer "))):
            raise lcx.to_err(M错误们_未授权())
        v_用户 = lc.dict_get(lc_self.f_钥匙们, lc.substring(v_头, 7.0, lc.size(v_头)))
        if lc.is_null(v_用户):
            raise lcx.to_err(M错误们_未授权("钥匙不对"))
        lcx.send(v_上下文, "放", "用户", v_用户)
        return lc.call(v_下一步, v_上下文)


lcx.named(M书店服务_鉴权, "鉴权")
lcx.sig(M书店服务_鉴权.m_处理, 2, 2)


def M书店服务_记日志(v_上下文, v_下一步):
    global M书店服务_请求数
    v_号 = None
    v_回复 = None
    M书店服务_请求数 = lc.add(M书店服务_请求数, 1.0)
    v_号 = M书店服务_请求数
    v_回复 = lc.call(v_下一步, v_上下文)
    lc.log(lc.join("#", v_号, " ", lcx.getf(v_上下文, "方式"), " ", lcx.getf(v_上下文, "路径"), " → ", lcx.getf(v_回复, "状态码")))
    return lcx.send(v_回复, "加头", "X-Request-Id", v_号)


M书店服务_记日志 = lc.fn("记日志", 2, 2, M书店服务_记日志)


def M书店服务_要管理员(v_上下文):
    if lc.ne(lc.dict_get(lcx.send(v_上下文, "取", "用户"), "role"), "admin"):
        raise lcx.to_err(M书店服务_不许("admin"))


M书店服务_要管理员 = lc.fn("要管理员", 1, 1, M书店服务_要管理员)


def M书店服务_书的校验(v_新建):
    v_v = None
    v_v = M校验_校验器()
    if lc.truthy(v_新建):
        lcx.send(lcx.send(v_v, "必填", "title"), "必填", "year")
    lcx.send(lcx.send(lcx.send(v_v, "文字", "title", 1.0, 40.0), "数字", "year", 1000.0, 2100.0), "其中之一", "tag", ["科幻", "文学", "未分类"])
    return v_v


M书店服务_书的校验 = lc.fn("书的校验", 1, 1, M书店服务_书的校验)


def M书店服务_找书(v_上下文):
    v_书 = None
    v_书 = lcx.send(M书店服务_书们, "取", M校验_要数字(lcx.send(v_上下文, "路径参数", "id"), "id"))
    if lc.is_null(v_书):
        raise lcx.to_err(M错误们_没有这个("没有这本书"))
    return v_书


M书店服务_找书 = lc.fn("找书", 1, 1, M书店服务_找书)


M书店服务_app = M路由_应用()
M书店服务_书们 = M仓库_仓库("books")
M书店服务_作者们 = M仓库_仓库("authors")
M书店服务_请求数 = 0.0


def lc_main_书店服务():
    v_api = None
    v_作者组 = None
    def lcfn33(v_上下文):
        return M响应_响应.m_JSON(200.0, lc.dict_of("hello", lcx.send(v_上下文, "路径参数", "name")))
    lcx.send(M书店服务_app, "加", "GET", "/hello/:name", lc.fn("", 1, 1, lcfn33))
    lcx.send(M书店服务_app, "用", M书店服务_记日志)
    def lcfn34(v_e, v_上下文):
        lc.log(lc.join("出错：", lcx.getf(v_e, "消息")))
    lcx.send(M书店服务_app, "用", M中间件_兜底(lc.fn("", 2, 2, lcfn34)))
    lcx.send(M书店服务_app, "用", M中间件_错误处理())
    lcx.send(M书店服务_app, "用", M书店服务_预检())
    def lcfn35(v_上下文):
        return "小书店"
    lcx.send(M书店服务_app, "GET", "/", lc.fn("", 1, 1, lcfn35))
    def lcfn36(v_上下文):
        return lc.dict_of("ok", True, "books", lc.size(lcx.send(M书店服务_书们, "全部")))
    lcx.send(M书店服务_app, "GET", "/health", lc.fn("", 1, 1, lcfn36))
    def lcfn37(v_上下文):
        raise lcx.to_err("炸了")
    lcx.send(M书店服务_app, "GET", "/boom", lc.fn("", 1, 1, lcfn37))
    def lcfn38(v_上下文):
        raise lcx.to_err(M书店服务_茶壶())
    lcx.send(M书店服务_app, "GET", "/boom/teapot", lc.fn("", 1, 1, lcfn38))
    def lcfn39(v_上下文):
        lc.list_set([], 5.0, 1.0)
        return "不该到这里"
    lcx.send(M书店服务_app, "GET", "/boom/lib", lc.fn("", 1, 1, lcfn39))
    def lcfn40(v_上下文):
        host.time_sleep(30.0)
        return lc.dict_of("slept", 30.0)
    lcx.send(M书店服务_app, "GET", "/slow", lc.fn("", 1, 1, lcfn40))
    def lcfn41(v_上下文):
        v_甲 = None
        v_乙 = None
        def lcfn42():
            host.time_sleep(20.0)
            return 1.0
        v_甲 = lcx.spawn(lcfn42)
        def lcfn43():
            host.time_sleep(10.0)
            return 2.0
        v_乙 = lcx.spawn(lcfn43)
        return lc.dict_of("sum", lc.add(lcx.await_(v_甲), lcx.await_(v_乙)))
    lcx.send(M书店服务_app, "GET", "/parallel", lc.fn("", 1, 1, lcfn41))
    v_api = lcx.send(M书店服务_app, "分组", "/api")
    lcx.send(v_api, "用", M书店服务_鉴权(lc.dict_of("k-ming", lc.dict_of("name", "小明", "role", "admin"), "k-hong", lc.dict_of("name", "小红", "role", "reader"))))
    def lcfn44(v_上下文):
        return lcx.send(v_上下文, "取", "用户")
    lcx.send(v_api, "GET", "/me", lc.fn("", 1, 1, lcfn44))
    def lcfn45(v_上下文):
        v_标签 = None
        v_标签 = lcx.send(v_上下文, "网址参数", "tag")
        if lc.is_null(v_标签):
            return lcx.send(M书店服务_书们, "全部")
        def lcfn46(v_书):
            return lc.eq(lc.dict_get(v_书, "tag"), v_标签)
        return lc.list_filter(lcx.send(M书店服务_书们, "全部"), lc.fn("", 1, 1, lcfn46))
    lcx.send(v_api, "GET", "/books", lc.fn("", 1, 1, lcfn45))
    def lcfn47(v_上下文):
        v_数据 = None
        v_标签 = None
        v_书 = None
        v_数据 = lcx.send(M书店服务_书的校验(True), "检查", lcx.send(v_上下文, "内容"))
        v_标签 = lc.dict_get(v_数据, "tag")
        if lc.is_null(v_标签):
            v_标签 = "未分类"
        v_书 = lcx.send(M书店服务_书们, "加", lc.dict_of("title", lc.dict_get(v_数据, "title"), "year", lc.dict_get(v_数据, "year"), "tag", v_标签, "by", lc.dict_get(lcx.send(v_上下文, "取", "用户"), "name")))
        return lcx.send(M响应_响应.m_JSON(201.0, v_书), "加头", "Location", lc.join("/api/books/", lc.dict_get(v_书, "id")))
    lcx.send(v_api, "POST", "/books", lc.fn("", 1, 1, lcfn47))
    def lcfn48(v_上下文):
        return M书店服务_找书(v_上下文)
    lcx.send(v_api, "GET", "/books/:id", lc.fn("", 1, 1, lcfn48))
    def lcfn49(v_上下文):
        v_书 = None
        v_数据 = None
        v_改动 = None
        v_键 = None
        v_书 = M书店服务_找书(v_上下文)
        v_数据 = lcx.send(M书店服务_书的校验(False), "检查", lcx.send(v_上下文, "内容"))
        v_改动 = lc.dict_of()
        for lci50, lcx51 in enumerate(lc.items(["title", "year", "tag"])):
            v_键 = lcx51
            if lc.dict_has(v_数据, v_键):
                lc.set_item(v_改动, v_键, lc.dict_get(v_数据, v_键))
        return lcx.send(M书店服务_书们, "改", lc.dict_get(v_书, "id"), v_改动)
    lcx.send(v_api, "PUT", "/books/:id", lc.fn("", 1, 1, lcfn49))
    def lcfn52(v_上下文):
        v_书 = None
        M书店服务_要管理员(v_上下文)
        v_书 = M书店服务_找书(v_上下文)
        lcx.send(M书店服务_书们, "删", lc.dict_get(v_书, "id"))
        return None
    lcx.send(v_api, "DELETE", "/books/:id", lc.fn("", 1, 1, lcfn52))
    v_作者组 = lcx.send(v_api, "分组", "/authors")
    def lcfn53(v_上下文, v_下一步):
        return lcx.send(lc.call(v_下一步, v_上下文), "加头", "X-Group", "authors")
    lcx.send(v_作者组, "用", lc.fn("", 2, 2, lcfn53))
    def lcfn54(v_上下文):
        return lcx.send(M书店服务_作者们, "全部")
    lcx.send(v_作者组, "GET", "/", lc.fn("", 1, 1, lcfn54))
    def lcfn55(v_上下文):
        v_数据 = None
        v_数据 = lcx.send(lcx.send(lcx.send(M校验_校验器(), "必填", "name"), "文字", "name", 1.0, 20.0), "检查", lcx.send(v_上下文, "内容"))
        return M响应_响应.m_JSON(201.0, lcx.send(M书店服务_作者们, "加", lc.dict_of("name", lc.dict_get(v_数据, "name"))))
    lcx.send(v_作者组, "POST", "/", lc.fn("", 1, 1, lcfn55))
    lcx.send(M书店服务_app, "开始服务", 8200.0)



def lc_start():
    lc_main_书店服务()
    host.ready()


lcx.run(lc_start)
