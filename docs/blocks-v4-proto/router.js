"use strict";
class Router {
  constructor() { this.routes = []; }
  on(method, path, handler) { this.routes.push({ method, path, handler }); }
  handle(method, path) {
    for (const r of this.routes) {
      if (r.method === method && r.path === path) {
        try { return r.handler({ path }); } catch (e) { return "500 " + e.message; }
      }
    }
    return "404";
  }
}
class LoggingRouter extends Router {
  handle(method, path) { const out = super.handle(method, path); console.log(method + " " + path + " -> " + out); return out; }
}
function makeCounter() { let n = 0; return () => { n = n + 1; return n; }; }
const app = new LoggingRouter();
const next = makeCounter();
app.on("GET", "/hello", (req) => "200 你好 #" + next());
app.on("GET", "/boom", (req) => { throw new Error("坏了"); });
app.handle("GET", "/hello"); app.handle("GET", "/hello"); app.handle("GET", "/boom"); app.handle("GET", "/nope");
