class Router:
    def __init__(self):
        self.routes = []
    def on(self, method, path, handler):
        self.routes.append({"method": method, "path": path, "handler": handler})
    def handle(self, method, path):
        for r in self.routes:
            if r["method"] == method and r["path"] == path:
                try:
                    return r["handler"]({"path": path})
                except Exception as e:
                    return "500 " + str(e)
        return "404"
class LoggingRouter(Router):
    def handle(self, method, path):
        out = super().handle(method, path)
        print(method + " " + path + " -> " + out)
        return out
def make_counter():
    n = 0
    def lc_fn1():
        nonlocal n
        n = n + 1
        return n
    return lc_fn1
app = LoggingRouter()
nxt = make_counter()
def lc_fn2(req):
    return "200 你好 #" + str(nxt())
def lc_fn3(req):
    raise Exception("坏了")
app.on("GET", "/hello", lc_fn2)
app.on("GET", "/boom", lc_fn3)
app.handle("GET", "/hello"); app.handle("GET", "/hello"); app.handle("GET", "/boom"); app.handle("GET", "/nope")
