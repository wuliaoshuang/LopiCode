# 由 docs/blocks-v5-prototypes/tool/lcx.py 生成（验证原型，不是产品生成器的输出）。
import lc_lang as lc
import lcx_ext as lcx
import host_python as host


# ———— 模块 响应 ————
def M响应_状态码(v_v):
    v_n = None
    v_n = lc.floor(lc.to_number(v_v))
    if (lc.ge(v_n, 200.0) and lc.le(v_n, 599.0)):
        return v_n
    return 200.0


M响应_状态码 = lc.fn("状态码", 1, 1, M响应_状态码)


def M响应_做响应(v_状态, v_类型, v_内容):
    v_头 = None
    v_头 = lc.dict_of("Access-Control-Allow-Origin", "*")
    if (lc.eq(v_状态, 204.0) or lc.eq(v_状态, 304.0)):
        return lc.dict_of("status", v_状态, "headers", v_头, "body", "")
    lc.set_item(v_头, "Content-Type", v_类型)
    return lc.dict_of("status", v_状态, "headers", v_头, "body", v_内容)


M响应_做响应 = lc.fn("做响应", 3, 3, M响应_做响应)


def M响应_JSON响应(v_状态, v_值):
    return M响应_做响应(M响应_状态码(v_状态), "application/json; charset=utf-8", lc.to_json(v_值))


M响应_JSON响应 = lc.fn("JSON响应", 2, 2, M响应_JSON响应)


def M响应_文字响应(v_状态, v_值):
    return M响应_做响应(M响应_状态码(v_状态), "text/plain; charset=utf-8", lc.to_text(v_值))


M响应_文字响应 = lc.fn("文字响应", 2, 2, M响应_文字响应)


def M响应_错误响应(v_状态, v_消息):
    return M响应_JSON响应(v_状态, lc.dict_of("error", v_消息))


M响应_错误响应 = lc.fn("错误响应", 2, 2, M响应_错误响应)


def M响应_空响应():
    return M响应_做响应(204.0, "", "")


M响应_空响应 = lc.fn("空响应", 0, 0, M响应_空响应)


def M响应_预检响应():
    return lc.dict_of("status", 204.0, "headers", lc.dict_of("Access-Control-Allow-Origin", "*", "Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers", "*"), "body", "")


M响应_预检响应 = lc.fn("预检响应", 0, 0, M响应_预检响应)



# ———— 模块 请求 ————
def M请求_解析网址参数(v_原文):
    v_表 = None
    v_段 = None
    v_等号 = None
    v_键 = None
    v_值 = None
    v_表 = lc.dict_of()
    for lci1, lcx2 in enumerate(lc.items(lc.split(v_原文, "&"))):
        v_段 = lcx2
        if lc.eq(v_段, ""):
            continue
        v_等号 = lc.index_of(v_段, "=")
        v_键 = v_段
        v_值 = ""
        if lc.ge(v_等号, 0.0):
            v_键 = lc.substring(v_段, 0.0, v_等号)
            v_值 = lc.substring(v_段, lc.add(v_等号, 1.0), lc.size(v_段))
        v_键 = host.url_decode(lc.replace(v_键, "+", " "))
        v_值 = host.url_decode(lc.replace(v_值, "+", " "))
        if (not lc.dict_has(v_表, v_键)):
            lc.set_item(v_表, v_键, v_值)
    return v_表


M请求_解析网址参数 = lc.fn("解析网址参数", 1, 1, M请求_解析网址参数)


def M请求_网址参数(v_请求, v_名字):
    v_表 = None
    v_表 = lc.dict_get(v_请求, "_query")
    if lc.is_null(v_表):
        v_表 = M请求_解析网址参数(lc.dict_get(v_请求, "query"))
        lc.set_item(v_请求, "_query", v_表)
    return lc.dict_get(v_表, v_名字)


M请求_网址参数 = lc.fn("网址参数", 2, 2, M请求_网址参数)


def M请求_路径参数(v_请求, v_名字):
    return lc.dict_get(lc.dict_get(v_请求, "params"), v_名字)


M请求_路径参数 = lc.fn("路径参数", 2, 2, M请求_路径参数)


def M请求_请求内容(v_请求):
    if (not lc.dict_has(v_请求, "_body")):
        lc.set_item(v_请求, "_body", lc.from_json(lc.dict_get(v_请求, "body")))
    return lc.dict_get(v_请求, "_body")


M请求_请求内容 = lc.fn("请求内容", 1, 1, M请求_请求内容)


def M请求_请求内容的字段(v_请求, v_名字):
    return lc.dict_get(M请求_请求内容(v_请求), v_名字)


M请求_请求内容的字段 = lc.fn("请求内容的字段", 2, 2, M请求_请求内容的字段)


def M请求_请求头(v_请求, v_名字):
    return lc.dict_get(lc.dict_get(v_请求, "headers"), lc.lower(v_名字))


M请求_请求头 = lc.fn("请求头", 2, 2, M请求_请求头)



# ———— 模块 路由 ————
def M路由_切路径(v_路径, v_解码):
    v_段们 = None
    v_段 = None
    v_段们 = []
    for lci3, lcx4 in enumerate(lc.items(lc.split(v_路径, "/"))):
        v_段 = lcx4
        if lc.ne(v_段, ""):
            lc.list_push(v_段们, (host.url_decode(v_段) if lc.truthy(v_解码) else v_段))
    return v_段们


M路由_切路径 = lc.fn("切路径", 2, 2, M路由_切路径)


def M路由_注册(v_方式, v_路径, v_处理):
    lc.list_push(M路由_路由表, lc.dict_of("method", v_方式, "segments", M路由_切路径(v_路径, False), "handler", v_处理))


M路由_注册 = lc.fn("注册", 3, 3, M路由_注册)


def M路由_对得上(v_模式, v_段们):
    v_参数 = None
    v_想要 = None
    v_i = None
    v_实际 = None
    if lc.ne(lc.size(v_模式), lc.size(v_段们)):
        return None
    v_参数 = lc.dict_of()
    for lci5, lcx6 in enumerate(lc.items(v_模式)):
        v_想要 = lcx6
        v_i = float(lci5)
        v_实际 = lc.list_get(v_段们, v_i)
        if lc.starts_with(v_想要, ":"):
            lc.set_item(v_参数, lc.substring(v_想要, 1.0, lc.size(v_想要)), v_实际)
        elif lc.ne(v_想要, v_实际):
            return None
    return v_参数


M路由_对得上 = lc.fn("对得上", 2, 2, M路由_对得上)


def M路由_分发(v_请求):
    v_段们 = None
    v_路径对了 = None
    v_路由 = None
    v_参数 = None
    v_结果 = None
    v_e = None
    if lc.eq(lc.dict_get(v_请求, "method"), "OPTIONS"):
        return M响应_预检响应()
    v_段们 = M路由_切路径(lc.dict_get(v_请求, "path"), True)
    v_路径对了 = False
    for lci7, lcx8 in enumerate(lc.items(M路由_路由表)):
        v_路由 = lcx8
        v_参数 = M路由_对得上(lc.dict_get(v_路由, "segments"), v_段们)
        if lc.is_null(v_参数):
            continue
        v_路径对了 = True
        if lc.ne(lc.dict_get(v_路由, "method"), lc.dict_get(v_请求, "method")):
            continue
        lc.set_item(v_请求, "params", v_参数)
        v_结果 = None
        try:
            v_结果 = lc.call(lc.dict_get(v_路由, "handler"), v_请求)
        except Exception as lce9:
            v_e = lcx.caught(lce9)
            return M响应_错误响应(500.0, "服务器内部出错")
        if lc.is_null(v_结果):
            return M响应_空响应()
        return v_结果
    if lc.truthy(v_路径对了):
        return M响应_错误响应(405.0, "这个地址不支持这种请求方式")
    return M响应_错误响应(404.0, "没有这个接口")


M路由_分发 = lc.fn("分发", 1, 1, M路由_分发)


def M路由_开始服务(v_端口):
    host.http_serve(v_端口, M路由_分发)


M路由_开始服务 = lc.fn("开始服务", 1, 1, M路由_开始服务)


M路由_路由表 = []

# ———— 模块 集合 ————
class M集合_集合(lcx.Obj):
    def __init__(lc_self, v_名字):
        super(M集合_集合, lc_self).__init__()
        lc_self.f_名字 = ""
        lc_self.f_名字 = v_名字

    def m_格子(lc_self):
        return lc.join("集合:", lc_self.f_名字)

    def m_改库(lc_self, v_改法):
        def lcfn10(v_库):
            return lc.call(v_改法, lcx.or_else(v_库, lc.dict_of("next", 1.0, "rows", [])))
        return host.store_update(lcx.send(lc_self, "格子"), lc.fn("", 1, 1, lcfn10))

    def m_位置(lc_self, v_rows, v_id):
        v_要找 = None
        v_行 = None
        v_i = None
        v_要找 = lc.to_number(v_id)
        for lci11, lcx12 in enumerate(lc.items(v_rows)):
            v_行 = lcx12
            v_i = float(lci11)
            if lc.eq(lc.dict_get(v_行, "id"), v_要找):
                return v_i
        return (-1.0)

    def m_全部(lc_self):
        return lcx.or_else(lc.dict_get(host.store_get(lcx.send(lc_self, "格子")), "rows"), [])

    def m_个数(lc_self):
        return lc.size(lcx.send(lc_self, "全部"))

    def m_取(lc_self, v_id):
        v_rows = None
        v_rows = lcx.send(lc_self, "全部")
        return lc.list_get(v_rows, lcx.send(lc_self, "位置", v_rows, v_id))

    def m_找(lc_self, v_键, v_值):
        def lcfn13(v_行):
            return lc.eq(lc.dict_get(v_行, v_键), v_值)
        return lc.list_filter(lcx.send(lc_self, "全部"), lc.fn("", 1, 1, lcfn13))

    def m_加(lc_self, v_值):
        def lcfn14(v_库):
            v_行 = None
            v_行 = lc.dict_merge(lc.dict_of(), v_值)
            lc.set_item(v_行, "id", lc.dict_get(v_库, "next"))
            lc.set_item(v_库, "next", lc.add(lc.dict_get(v_库, "next"), 1.0))
            lc.list_push(lc.dict_get(v_库, "rows"), v_行)
            return [v_库, v_行]
        return lcx.send(lc_self, "改库", lc.fn("", 1, 1, lcfn14))

    def m_改(lc_self, v_id, v_值):
        v_自己 = None
        v_自己 = lc_self
        def lcfn15(v_库):
            v_rows = None
            v_i = None
            v_旧 = None
            v_新 = None
            v_rows = lc.dict_get(v_库, "rows")
            v_i = lcx.send(v_自己, "位置", v_rows, v_id)
            if lc.lt(v_i, 0.0):
                return [v_库, None]
            v_旧 = lc.list_get(v_rows, v_i)
            if (not lc.is_type(v_值, "dict")):
                return [v_库, v_旧]
            v_新 = lc.dict_merge(v_旧, v_值)
            lc.set_item(v_新, "id", lc.dict_get(v_旧, "id"))
            lc.list_set(v_rows, v_i, v_新)
            return [v_库, v_新]
        return lcx.send(lc_self, "改库", lc.fn("", 1, 1, lcfn15))

    def m_删(lc_self, v_id):
        v_自己 = None
        v_自己 = lc_self
        def lcfn16(v_库):
            v_rows = None
            v_i = None
            v_rows = lc.dict_get(v_库, "rows")
            v_i = lcx.send(v_自己, "位置", v_rows, v_id)
            if lc.lt(v_i, 0.0):
                return [v_库, False]
            lc.list_remove(v_rows, v_i)
            return [v_库, True]
        return lcx.send(lc_self, "改库", lc.fn("", 1, 1, lcfn16))


lcx.named(M集合_集合, "集合")
lcx.sig(M集合_集合.m_格子, 0, 0)
lcx.sig(M集合_集合.m_改库, 1, 1)
lcx.sig(M集合_集合.m_位置, 2, 2)
lcx.sig(M集合_集合.m_全部, 0, 0)
lcx.sig(M集合_集合.m_个数, 0, 0)
lcx.sig(M集合_集合.m_取, 1, 1)
lcx.sig(M集合_集合.m_找, 2, 2)
lcx.sig(M集合_集合.m_加, 1, 1)
lcx.sig(M集合_集合.m_改, 2, 2)
lcx.sig(M集合_集合.m_删, 1, 1)


def M集合_集合全部(v_名):
    return lcx.send(M集合_集合(v_名), "全部")


M集合_集合全部 = lc.fn("集合全部", 1, 1, M集合_集合全部)


def M集合_集合个数(v_名):
    return lcx.send(M集合_集合(v_名), "个数")


M集合_集合个数 = lc.fn("集合个数", 1, 1, M集合_集合个数)


def M集合_集合取(v_名, v_id):
    return lcx.send(M集合_集合(v_名), "取", v_id)


M集合_集合取 = lc.fn("集合取", 2, 2, M集合_集合取)


def M集合_集合找(v_名, v_键, v_值):
    return lcx.send(M集合_集合(v_名), "找", v_键, v_值)


M集合_集合找 = lc.fn("集合找", 3, 3, M集合_集合找)


def M集合_集合加(v_名, v_值):
    return lcx.send(M集合_集合(v_名), "加", v_值)


M集合_集合加 = lc.fn("集合加", 2, 2, M集合_集合加)


def M集合_集合改(v_名, v_id, v_值):
    return lcx.send(M集合_集合(v_名), "改", v_id, v_值)


M集合_集合改 = lc.fn("集合改", 3, 3, M集合_集合改)


def M集合_集合删(v_名, v_id):
    return lcx.send(M集合_集合(v_名), "删", v_id)


M集合_集合删 = lc.fn("集合删", 2, 2, M集合_集合删)



# ———— 模块 网络 ————
def M网络_请求网址(v_方式, v_网址, v_数据):
    return host.net_fetch(v_方式, v_网址, v_数据)


M网络_请求网址 = lc.fn("请求网址", 3, 3, M网络_请求网址)



# ———— 模块 样本服务 ————


def lc_main_样本服务():
    def lcfn17(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, M集合_集合全部("todos"))
    M路由_注册("GET", "/todos", lc.fn("", 1, 1, lcfn17))
    def lcfn18(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        if lc.is_null(M请求_请求内容的字段(v_请求, "title")):
            return M响应_JSON响应(400.0, lc.dict_of("error", "缺少 title"))
        v_todo = M集合_集合加("todos", lc.dict_of("title", M请求_请求内容的字段(v_请求, "title"), "done", False))
        return M响应_JSON响应(201.0, v_todo)
    M路由_注册("POST", "/todos", lc.fn("", 1, 1, lcfn18))
    def lcfn19(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("count", M集合_集合个数("todos")))
    M路由_注册("GET", "/todos/count", lc.fn("", 1, 1, lcfn19))
    def lcfn20(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v_todo = M集合_集合取("todos", M请求_路径参数(v_请求, "id"))
        if lc.is_null(v_todo):
            return M响应_JSON响应(404.0, lc.dict_of("error", lc.join("找不到 id 是 ", M请求_路径参数(v_请求, "id"), " 的待办")))
        return M响应_JSON响应(200.0, v_todo)
    M路由_注册("GET", "/todos/:id", lc.fn("", 1, 1, lcfn20))
    def lcfn21(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        if lc.is_null(M集合_集合取("todos", M请求_路径参数(v_请求, "id"))):
            return M响应_JSON响应(404.0, lc.dict_of("error", lc.join("找不到 id 是 ", M请求_路径参数(v_请求, "id"), " 的待办")))
        M集合_集合改("todos", M请求_路径参数(v_请求, "id"), M请求_请求内容(v_请求))
        return M响应_JSON响应(200.0, M集合_集合取("todos", M请求_路径参数(v_请求, "id")))
    M路由_注册("PATCH", "/todos/:id", lc.fn("", 1, 1, lcfn21))
    def lcfn22(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        if lc.is_null(M集合_集合取("todos", M请求_路径参数(v_请求, "id"))):
            return M响应_JSON响应(404.0, lc.dict_of("error", lc.join("找不到 id 是 ", M请求_路径参数(v_请求, "id"), " 的待办")))
        M集合_集合删("todos", M请求_路径参数(v_请求, "id"))
    M路由_注册("DELETE", "/todos/:id", lc.fn("", 1, 1, lcfn22))
    def lcfn23(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, M集合_集合找("todos", "done", True))
    M路由_注册("GET", "/done", lc.fn("", 1, 1, lcfn23))
    def lcfn24(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, M集合_集合找("todos", "title", M请求_网址参数(v_请求, "t")))
    M路由_注册("GET", "/by-title", lc.fn("", 1, 1, lcfn24))
    def lcfn25(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        M集合_集合加("notes", M请求_请求内容(v_请求))
        return M响应_JSON响应(200.0, M集合_集合全部("notes"))
    M路由_注册("POST", "/notes", lc.fn("", 1, 1, lcfn25))
    def lcfn26(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("sum", lc.add(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "diff", lc.sub(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "prod", lc.mul(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "quot", lc.div(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "rem", lc.mod(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "lt", lc.lt(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "le", lc.le(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "gt", lc.gt(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "ge", lc.ge(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "eq", lc.eq(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "ne", lc.ne(M请求_网址参数(v_请求, "a"), M请求_网址参数(v_请求, "b")), "and", (lc.truthy(M请求_网址参数(v_请求, "a")) and lc.truthy(M请求_网址参数(v_请求, "b"))), "or", (lc.truthy(M请求_网址参数(v_请求, "a")) or lc.truthy(M请求_网址参数(v_请求, "b"))), "notA", (not lc.truthy(M请求_网址参数(v_请求, "a")))))
    M路由_注册("GET", "/calc", lc.fn("", 1, 1, lcfn26))
    def lcfn27(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("third", lc.div(1.0, 3.0), "pointThree", lc.add(0.1, 0.2), "whole", lc.div(6.0, 2.0), "half", lc.div(1.0, 2.0), "negRem", lc.mod((-7.0), 3.0), "fracRem", lc.mod(5.5, 2.0), "divZero", lc.div(5.0, 0.0), "remZero", lc.mod(5.0, 0.0), "negZero", lc.mul(0.0, (-1.0)), "overflow", lc.mul(1e+308, 10.0), "big", 1e+21, "e15", 1000000000000000.0, "justUnder", 999999999999999.0, "nines", 999999999999999.9, "small", 2.5e-10, "tiny", 1.2e-07, "tinier", 1.2e-08, "tie", 12345678901.25, "negTie", (-12345678901.25), "frac", 123456.789, "neg", (-42.0), "negFrac", (-0.5), "long", 1234567890.1234567, "bigInt", 1.2345678901234568e+17))
    M路由_注册("GET", "/numbers", lc.fn("", 1, 1, lcfn27))
    def lcfn28(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("numText", lc.eq(5.0, "5"), "numTextDot", lc.eq(5.0, "5.0"), "nullEmpty", lc.eq(lc.dict_get(lc.dict_of(), "x"), ""), "nullNull", lc.eq(lc.dict_get(lc.dict_of(), "x"), lc.dict_get(lc.dict_of(), "x")), "nullZero", lc.eq(lc.dict_get(lc.dict_of(), "x"), 0.0), "zeroEmpty", lc.eq(0.0, ""), "boolText", lc.eq(True, "true"), "oneTrue", lc.eq(1.0, True), "objOrder", lc.eq(lc.dict_of("a", 1.0, "b", 2.0), lc.dict_of("b", 2.0, "a", 1.0)), "objDiff", lc.eq(lc.dict_of("a", 1.0), lc.dict_of("a", 2.0)), "objText", lc.eq(lc.dict_of("a", 1.0), "{\"a\":1}"), "listSame", lc.eq(M集合_集合全部("todos"), M集合_集合全部("todos")), "floatSum", lc.eq(lc.add(0.1, 0.2), 0.3), "neText", lc.ne("a", "b")))
    M路由_注册("GET", "/equal", lc.fn("", 1, 1, lcfn28))
    def lcfn29(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("null", (not (not lc.truthy(lc.dict_get(lc.dict_of(), "x")))), "false", (not (not False)), "zero", (not (not lc.truthy(0.0))), "empty", (not (not lc.truthy(""))), "textZero", (not (not lc.truthy("0"))), "space", (not (not lc.truthy(" "))), "emptyObj", (not (not lc.truthy(lc.dict_of()))), "emptyList", (not (not lc.truthy(M集合_集合全部("notes")))), "one", (not (not lc.truthy(1.0))), "true", (not (not True))))
    M路由_注册("GET", "/truthy", lc.fn("", 1, 1, lcfn29))
    def lcfn30(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("text", lc.size("你好😀"), "list", lc.size(M集合_集合全部("todos")), "obj", lc.size(lc.dict_of("a", 1.0, "b", 2.0)), "num", lc.size(12345.0), "null", lc.size(lc.dict_get(lc.dict_of(), "x"))))
    M路由_注册("GET", "/len", lc.fn("", 1, 1, lcfn30))
    def lcfn31(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_文字响应(200.0, lc.join("你好，", M请求_路径参数(v_请求, "what"), "！", 3.0, True, lc.dict_get(lc.dict_of(), "x"), 1.5, lc.dict_of("a", 1.0), M请求_网址参数(v_请求, "q")))
    M路由_注册("GET", "/text/:what", lc.fn("", 1, 1, lcfn31))
    def lcfn32(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("value", "引号\"'反斜杠\\换行\u000a制表\u0009${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完", "引号\"'反斜杠\\换行\u000a制表\u0009${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完", 1.0, "Ａ", 2.0, "😀", 3.0, "a", 4.0, "B", 5.0, "10", 6.0, "9", 7.0, "__proto__", 8.0, "constructor", 9.0))
    M路由_注册("GET", "/special", lc.fn("", 1, 1, lcfn32))
    def lcfn33(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_文字响应(200.0, "引号\"'反斜杠\\换行\u000a制表\u0009${x}`</script><!--*/ #{y} %s 😀\u2028\u0001完")
    M路由_注册("GET", "/special-text", lc.fn("", 1, 1, lcfn33))
    def lcfn34(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v_n = 0.0
        for lck35 in range(lc.times(5.0)):
            v_n = lc.add(v_n, 2.0)
        for lck36 in range(lc.times(M请求_网址参数(v_请求, "times"))):
            v_n = lc.add(v_n, 1.0)
        return M响应_JSON响应(200.0, lc.dict_of("n", v_n))
    M路由_注册("GET", "/loop", lc.fn("", 1, 1, lcfn34))
    def lcfn37(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v_s = ""
        for lci38, lcx39 in enumerate(lc.items(M集合_集合全部("todos"))):
            v_item = lcx39
            v_s = lc.join(v_s, lc.dict_get(v_item, "title"), ";")
            v_acc = lc.add(v_acc, lc.dict_get(v_item, "id"))
            if lc.eq(M请求_网址参数(v_请求, "grow"), "1"):
                M集合_集合加("notes", lc.dict_of("from", lc.dict_get(v_item, "id")))
        for lci40, lcx41 in enumerate(lc.items("abc")):
            v_item = lcx41
            v_acc = lc.add(v_acc, 1000.0)
        return M响应_JSON响应(200.0, lc.dict_of("titles", v_s, "sum", v_acc, "count", lc.size(M集合_集合全部("todos"))))
    M路由_注册("GET", "/each", lc.fn("", 1, 1, lcfn37))
    def lcfn42(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_文字响应(200.0, "先返回")
        M集合_集合加("notes", lc.dict_of("bad", "返回之后不该执行"))
        return M响应_文字响应(500.0, "不该到这里")
    M路由_注册("GET", "/early", lc.fn("", 1, 1, lcfn42))
    def lcfn43(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v_n = 0.0
        for lck44 in range(lc.times(10.0)):
            v_n = lc.add(v_n, 1.0)
            if lc.eq(v_n, 3.0):
                return M响应_JSON响应(200.0, lc.dict_of("stoppedAt", v_n))
        return M响应_文字响应(500.0, "不该到这里")
    M路由_注册("GET", "/early-loop", lc.fn("", 1, 1, lcfn43))
    def lcfn45(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        lc.log(lc.join("日志：", 1.5, " ", lc.dict_of("k", "v")))
    M路由_注册("GET", "/nothing", lc.fn("", 1, 1, lcfn45))
    def lcfn46(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        if lc.gt(M请求_网址参数(v_请求, "x"), 10.0):
            return M响应_文字响应(200.0, "大")
        else:
            if lc.truthy(M请求_网址参数(v_请求, "x")):
                return M响应_文字响应(200.0, "小")
            else:
                return M响应_文字响应(200.0, "没有")
    M路由_注册("GET", "/branch", lc.fn("", 1, 1, lcfn46))
    def lcfn47(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("n", v_n, "s", v_s, "flag", v_flag, "todo", v_todo, "acc", v_acc))
    M路由_注册("GET", "/vars", lc.fn("", 1, 1, lcfn47))
    def lcfn48(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v_n = lc.add(v_n, 1.0)
        v_s = lc.add(v_s, 2.0)
        v_class = lc.add(v_class, lc.add(v_def, v_func))
        return M响应_JSON响应(200.0, lc.dict_of("n", v_n, "s", v_s, "class", v_class))
    M路由_注册("GET", "/bump", lc.fn("", 1, 1, lcfn48))
    def lcfn49(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("body", M请求_请求内容(v_请求), "name", M请求_请求内容的字段(v_请求, "name"), "nameLen", lc.size(M请求_请求内容的字段(v_请求, "name")), "q", M请求_网址参数(v_请求, "q"), "missing", M请求_网址参数(v_请求, "nope"), "header", M请求_请求头(v_请求, "X-Test"), "noHeader", M请求_请求头(v_请求, "X-Nope"), "noBody", lc.is_null(M请求_请求内容(v_请求))))
    M路由_注册("POST", "/echo", lc.fn("", 1, 1, lcfn49))
    def lcfn50(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(M请求_网址参数(v_请求, "code"), lc.dict_of("ok", True))
    M路由_注册("GET", "/status", lc.fn("", 1, 1, lcfn50))
    def lcfn51(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_文字响应(200.0, "根")
    M路由_注册("GET", "/", lc.fn("", 1, 1, lcfn51))
    def lcfn52(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("x", M请求_路径参数(v_请求, "x"), "y", M请求_路径参数(v_请求, "y")))
    M路由_注册("PUT", "/a/:x/b/:y", lc.fn("", 1, 1, lcfn52))
    def lcfn53(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_JSON响应(200.0, lc.dict_of("unknown", None, "undeclared", None, "badParam", M请求_路径参数(v_请求, "nope"), "badCollection", None, "missing", lc.add(None, None), "badOp", None, "ok", 1.0))
    M路由_注册("GET", "/holes", lc.fn("", 1, 1, lcfn53))
    def lcfn54(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v__t1_结果 = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v__t1_结果 = M网络_请求网址("GET", lc.join("http://", M请求_请求头(v_请求, "Host"), "/text/relay?q=%E5%A5%BD"), None)
        if (not lc.is_null(v__t1_结果)):
            v_s = v__t1_结果
            return M响应_文字响应(200.0, lc.join("拿到：", v_s))
        else:
            return M响应_文字响应(502.0, "失败")
    M路由_注册("GET", "/relay", lc.fn("", 1, 1, lcfn54))
    def lcfn55(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v__t2_结果 = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v__t2_结果 = M网络_请求网址("POST", lc.join("http://", M请求_请求头(v_请求, "Host"), "/echo"), lc.dict_of("name", "转发"))
        if (not lc.is_null(v__t2_结果)):
            v_s = v__t2_结果
            return M响应_文字响应(200.0, v_s)
        else:
            return M响应_文字响应(502.0, "失败")
    M路由_注册("GET", "/relay-post", lc.fn("", 1, 1, lcfn55))
    def lcfn56(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v__t3_结果 = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v__t3_结果 = M网络_请求网址("GET", M请求_网址参数(v_请求, "url"), None)
        if (not lc.is_null(v__t3_结果)):
            v_s = v__t3_结果
            return M响应_文字响应(200.0, "不该成功")
        else:
            return M响应_文字响应(502.0, lc.join("失败，s 还是：", v_s))
    M路由_注册("GET", "/relay-fail", lc.fn("", 1, 1, lcfn56))
    def lcfn57(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v__t4_结果 = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        v__t4_结果 = M网络_请求网址("GET", M请求_网址参数(v_请求, "url"), None)
        if (not lc.is_null(v__t4_结果)):
            v_s = v__t4_结果
            return M响应_文字响应(200.0, v_s)
        else:
            return M响应_文字响应(502.0, "失败")
    M路由_注册("GET", "/relay-get", lc.fn("", 1, 1, lcfn57))
    def lcfn58(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_文字响应(200.0, M请求_网址参数(v_请求, "t"))
    M路由_注册("GET", "/say", lc.fn("", 1, 1, lcfn58))
    def lcfn59(v_请求):
        v_n = None
        v_s = None
        v_flag = None
        v_todo = None
        v_item = None
        v_acc = None
        v_class = None
        v_def = None
        v_func = None
        v_n = 7.0
        v_s = "初始\"值\\"
        v_flag = True
        v_todo = ""
        v_item = ""
        v_acc = 0.0
        v_class = 1.0
        v_def = 2.0
        v_func = 3.0
        return M响应_文字响应(200.0, lc.now())
    M路由_注册("GET", "/now", lc.fn("", 1, 1, lcfn59))
    M路由_开始服务(8123.0)



def lc_start():
    lc_main_样本服务()
    host.ready()


lcx.run(lc_start)
