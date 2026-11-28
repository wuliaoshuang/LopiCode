/// 自带的前端库“请求”（积木第 5 版·前端 2·第一批）：发请求、取 JSON、不成再试几次、几秒内用上次取到的、
/// “加载”（数据、正在加载、出错的话各放进一个状态）。
///
/// 内容是语言核心写的模块，底下包的是请求那一个原生绑定（`net.request`）、“现在的毫秒数”“等一会儿”，
/// 和状态的两个接口（“加载”要往状态里放东西）。连不上、超时会出错，可以用“试着做”接住；回应不是 200 多不算出错，
/// 看“回应成功吗”。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcHttpLibId = 'lopi/http';

const String kLcHttpManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/http",
  "name": "请求",
  "version": "1.0.0",
  "summary": "向网址要数据：发请求、取 JSON、不成再试、几秒内用上次的、把加载的三种样子放进状态",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/http.lc", "name": "请求"}],
  "blocks": ["blocks.json"],
  "types": [
    {"name": "回应", "module": "请求", "hint": "一次请求的回应：status 状态码、ok 是不是 200 多、headers 回应头、body 正文（文字）"}
  ]
}
''';

const String kLcHttpModuleLc = r'''
; 自带库“请求”的模块（严格规矩的语言核心写的）。
(模块 请求
  (宿主 net.request ((请求 (字典 任意))) -> (字典 任意))
  (宿主 time.now () -> 整数)
  (宿主 time.sleep ((毫秒 整数)) -> 空)
  (宿主 page.state.new ((名 文字) (初值 任意)) -> 任意)
  (宿主 page.state.write ((格子 任意) (值 任意)) -> 空)

  (公开 (别名 回应 (字典 任意)))
  ; 几秒内用上次的：网址 → {at 取到的时刻, value 取到的东西}
  (变量 记着的 (字典 (字典 任意)) (典))

  ; 带上的东西：是文字就原样发，别的变成 JSON 发（并且写明是 JSON）；GET 不带。超时毫秒 0＝不限。
  (公开 (函数 发请求 ((方式 文字) (网址 文字) (带上 任意) (超时毫秒 小数)) -> 回应
    (设 请求 (字典 任意) (典 ("url" 网址) ("method" 方式) ("timeoutMs" 超时毫秒)))
    (如果 (且 (非空 带上) (!= 方式 "GET"))
      (那么
        (如果 (是类 带上 "text")
          (那么 (存 请求 "body" 带上))
          (否则 (存 请求 "body" (转JSON 带上))
                (存 请求 "headers" (标 (字典 任意) (典 ("content-type" "application/json"))))))))
    (返回 (宿 net.request 请求))))
  ; 同上，多带一份自己写的头（名字 → 值）；自己写的头盖过自动加的。
  (公开 (函数 带头发请求 ((方式 文字) (网址 文字) (头 (字典 文字)) (带上 任意) (超时毫秒 小数)) -> 回应
    (设 请求 (字典 任意) (典 ("url" 网址) ("method" 方式) ("timeoutMs" 超时毫秒)))
    (设 全部头 (字典 任意) (典))
    (如果 (且 (非空 带上) (!= 方式 "GET"))
      (那么
        (如果 (是类 带上 "text")
          (那么 (存 请求 "body" 带上))
          (否则 (存 请求 "body" (转JSON 带上))
                (存 全部头 "content-type" "application/json")))))
    (每对 头名 头值 头 (存 全部头 头名 头值))
    (存 请求 "headers" 全部头)
    (返回 (宿 net.request 请求))))
  (公开 (函数 回应的状态码 ((回 回应)) -> 小数 (返回 (转 小数 (取 回 "status")))))
  (公开 (函数 回应成功吗 ((回 回应)) -> 是否 (返回 (转 是否 (取 回 "ok")))))
  (公开 (函数 回应的正文 ((回 回应)) -> 文字 (返回 (文 (取 回 "body")))))
  ; 正文按 JSON 读；回应不是 200 多、正文不是 JSON 都出错。
  (公开 (函数 回应的JSON ((回 回应)) -> 任意
    (如果 (非 (调 回应成功吗 回))
      (那么 (抛出 (连 "请求没成功：状态码 " (文 (取 回 "status"))))))
    (返回 (读JSON (调 回应的正文 回)))))
  (公开 (函数 取JSON ((网址 文字)) -> 任意
    (返回 (调 回应的JSON (调 发请求 "GET" 网址 (标 任意 空) 0.0)))))
  ; 不成再试：连不上、超时、回应不是 200 多都算不成；试完还不成，最后一次是什么样就交回什么样（连不上就出错）。
  (公开 (函数 再试着取 ((网址 文字) (再试几次 小数) (隔毫秒 整数)) -> 回应
    (设 试过 0)
    (当 是
      (设 最后一次 (>= 试过 再试几次))
      (试 (做
            (设 回 (调 发请求 "GET" 网址 (标 任意 空) 0.0))
            (如果 (或 最后一次 (调 回应成功吗 回)) (那么 (返回 回))))
          (出错时 _ 错 (如果 最后一次 (那么 (抛出 (. 错 消息))))))
      (改 试过 (+ 试过 1))
      (做 (宿 time.sleep 隔毫秒)))
    (抛出 "请求没成功")))
  ; 几秒内用上次的：这段时间里同一个网址不再真的去取。
  (公开 (函数 记着取JSON ((网址 文字) (几秒 小数)) -> 任意
    (设 现在 (宿 time.now))
    (设 上次 (取 记着的 网址))
    (如果 (非空 上次)
      (那么 (如果 (< (- 现在 (转 小数 (取 上次 "at"))) (* 几秒 1000)) (那么 (返回 (取 上次 "value"))))))
    (设 值 (调 取JSON 网址))
    (存 记着的 网址 (标 (字典 任意) (典 ("at" 现在) ("value" 值))))
    (返回 值)))
  (公开 (函数 忘掉记着的 ((网址 文字))
    (如果 (有键 记着的 网址) (那么 (删键 记着的 网址)))))
  ; 加载：正在加载、出错的话、数据各放进一个状态（名字是页面里声明过的状态）。
  (公开 (函数 加载到状态 ((网址 文字) (数据状态 文字) (加载中状态 文字) (出错状态 文字))
    (设 加载中 (宿 page.state.new 加载中状态 (标 任意 否)))
    (设 出错 (宿 page.state.new 出错状态 (标 任意 "")))
    (做 (宿 page.state.write 加载中 是))
    (做 (宿 page.state.write 出错 ""))
    (试 (做
          (设 值 (调 取JSON 网址))
          (做 (宿 page.state.write (宿 page.state.new 数据状态 (标 任意 空)) 值)))
        (出错时 _ 错 (做 (宿 page.state.write 出错 (. 错 消息)))))
    (做 (宿 page.state.write 加载中 否)))))
''';

const String kLcHttpBlocks = r'''
{"blocks": [
  {"id": "request", "category": "请求", "how": "expand",
   "expand": "(调 发请求 (槽 method) (槽 url) (标 任意 (槽 data)) (槽 timeout))",
   "look": {"name": "发请求", "shape": "value", "template": "用 {method} 请求 {url} 带上 {data}（最多等 {timeout} 毫秒）的回应", "colorKey": "network",
            "hint": "会等到回应回来才接着往下做。连不上、超时会出错（用“试着做”接）；最多等填 0＝不限",
            "slots": [{"name": "method", "kind": "choice", "options": ["GET", "POST", "PUT", "PATCH", "DELETE"], "defaultValue": "GET"}]}},
  {"id": "requestWith", "category": "请求", "how": "expand",
   "expand": "(调 带头发请求 (槽 method) (槽 url) (槽 headers) (标 任意 (槽 data)) (槽 timeout))",
   "look": {"name": "发请求（带头）", "shape": "value", "template": "用 {method} 请求 {url}，头是 {headers}，带上 {data}（最多等 {timeout} 毫秒）的回应", "colorKey": "network",
            "hint": "头填一个字典：名字 → 值（都是文字）。别的和“发请求”一样",
            "slots": [{"name": "method", "kind": "choice", "options": ["GET", "POST", "PUT", "PATCH", "DELETE"], "defaultValue": "GET"}]}},
  {"id": "status", "category": "请求", "how": "call", "of": "回应的状态码", "args": ["res"],
   "look": {"name": "回应的状态码", "shape": "value", "template": "{res} 的状态码", "colorKey": "network"}},
  {"id": "ok", "category": "请求", "how": "call", "of": "回应成功吗", "args": ["res"],
   "look": {"name": "回应成功吗", "shape": "value", "template": "{res} 成功了吗", "colorKey": "network", "hint": "状态码是 200 多就是成功"}},
  {"id": "body", "category": "请求", "how": "call", "of": "回应的正文", "args": ["res"],
   "look": {"name": "回应的正文", "shape": "value", "template": "{res} 的正文", "colorKey": "network"}},
  {"id": "json", "category": "请求", "how": "call", "of": "回应的JSON", "args": ["res"],
   "look": {"name": "回应里的 JSON", "shape": "value", "template": "{res} 里的 JSON", "colorKey": "network",
            "hint": "回应没成功、正文不是 JSON 都会出错"}},
  {"id": "getJson", "category": "请求", "how": "call", "of": "取JSON", "args": ["url"],
   "look": {"name": "取 JSON", "shape": "value", "template": "从 {url} 取到的 JSON", "colorKey": "network",
            "hint": "会等到取回来。连不上、回应没成功、不是 JSON 都会出错"}},
  {"id": "retry", "category": "请求", "how": "call", "of": "再试着取", "args": ["url", "times", "gap"],
   "look": {"name": "请求，不成再试", "shape": "value", "template": "请求 {url}，不成再试 {times} 次（隔 {gap} 毫秒）的回应", "colorKey": "network",
            "hint": "连不上、超时、回应没成功都算不成"}},
  {"id": "cached", "category": "请求", "how": "call", "of": "记着取JSON", "args": ["url", "seconds"],
   "look": {"name": "取 JSON（几秒内用上次的）", "shape": "value", "template": "从 {url} 取到的 JSON（{seconds} 秒内用上次的）", "colorKey": "network"}},
  {"id": "forget", "category": "请求", "how": "call", "of": "忘掉记着的", "args": ["url"],
   "look": {"name": "忘掉上次取到的", "shape": "statement", "template": "忘掉上次从 {url} 取到的", "colorKey": "network"}},
  {"id": "load", "category": "请求", "how": "expand",
   "expand": "(做 (调 加载到状态 (槽 url) (槽 data) (槽 loading) (槽 error)))",
   "look": {"name": "加载", "shape": "statement", "template": "加载 {url}：数据放进状态 {data}，正在加载放进状态 {loading}，出错的话放进状态 {error}", "colorKey": "network",
            "hint": "三个都填页面里状态的名字。开始时“正在加载”是“是”，结束时是“否”；出了错，那句话放进“出错的话”"}}
]}
''';

const Map<String, String> kLcHttpLibFiles = {kLibManifestFile: kLcHttpManifest, 'modules/http.lc': kLcHttpModuleLc, 'blocks.json': kLcHttpBlocks};
