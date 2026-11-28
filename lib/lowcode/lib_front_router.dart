/// 自带的前端库“路由”（积木第 5 版·前端 2·第二批）：一页里按地址栏井号后面那一段决定“现在是哪一页”。
///
/// 路由表（样子 → 名字）、去、换成、后退、现在的路径、现在是哪一页、路由参数、当路由变了、“现在是哪一页”跟着放进状态。
/// 内容是语言核心写的模块；底下包的是地址那一组原生绑定（`loc.now / push / replace / go / onPop`）、窗口事件（听 `hashchange`）
/// 、页面的时刻（“当路由变了”等页面放上以后才开始看）和状态的四个接口（当前路径放在一个会通知的格子里）。“页面”库只有“去项目里的另一页”“整页跳转”，没有地址栏历史这一组，
/// 所以这里直接声明（都是前端这一边原来就有的接口，没有新加）。
///
/// 用井号方式（`#/detail/7`）：不用服务器配合，直接双击打开的网页也能用。“加一条历史”“换掉这条”不会让浏览器发前进后退事件，
/// 所以“去”“换成”以后自己对一遍；“后退”会发事件，等事件来了再对（核对见 docs/api-notes.md）。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcRouterLibId = 'lopi/router';

const String kLcRouterManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/router",
  "name": "路由",
  "version": "1.0.0",
  "summary": "一页里按地址决定现在显示哪一块：路由表、去、换成、后退、路由参数、当路由变了",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/router.lc", "name": "路由"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcRouterModuleLc = r'''
; 自带库“路由”的模块（严格规矩的语言核心写的）。
(模块 路由
  (宿主 loc.now () -> (字典 任意))
  (宿主 loc.push ((网址 文字) (附带 任意)) -> 空)
  (宿主 loc.replace ((网址 文字) (附带 任意)) -> 空)
  (宿主 loc.go ((几步 整数)) -> 空)
  (宿主 loc.onPop ((做法 (要等函数 (任意) 空))) -> (函数 () 空))
  (宿主 win.on ((对象 文字) (事件 文字) (做法 (要等函数 ((字典 任意)) 空)) (选项 (字典 任意))) -> (函数 () 空))
  (宿主 page.ui.life ((时刻 文字) (做法 (要等函数 (任意) 空))) -> 空)
  (宿主 page.state.new ((名 文字) (初值 任意)) -> 任意)
  (宿主 page.state.read ((格子 任意)) -> 任意)
  (宿主 page.state.write ((格子 任意) (值 任意)) -> 空)
  (宿主 page.state.watch ((取值 (不等函数 () 任意)) (做法 (要等函数 (任意 任意) 空))) -> (函数 () 空))

  (记录 一条路由 (样子 文字) (名字 文字))
  (变量 路由表 (列表 一条路由) (列))
  ; 只有一个格子（“位置”）：里面放当前路径，改了它在看的人会收到。
  (变量 格子们 (字典 任意) (典))
  (变量 听着了 是否 否)

  ; 把路径按斜杠切开，空的段不要。
  (函数 拆段 ((路径 文字)) -> (列表 文字)
    (设 段们 (列表 文字) (列))
    (每个 段 (切 路径 "/") (如果 (!= 段 "") (那么 (加项 段们 段))))
    (返回 段们))
  ; 样子 "/detail/:id" 对路径 "/detail/42" → {id: "42"}；没对上＝空。地址里的百分号编码是坏的也当没对上。
  (函数 对一对 ((样子 文字) (路径 文字)) -> (可空 (字典 文字))
    (设 甲 (调 拆段 样子))
    (设 乙 (调 拆段 路径))
    (如果 (!= (长 甲) (长 乙)) (那么 (返回 空)))
    (设 参数 (字典 文字) (典))
    (每个带号 样段 号 甲
      (设 实段 (项 乙 号))
      (如果 (开头是 样段 ":")
        (那么 (试 (做 (存 参数 (截 样段 1 (文长 样段)) (网址解码 实段)))
                  (出错时 _ _ (返回 空))))
        (否则 (如果 (!= 样段 实段) (那么 (返回 空))))))
    (返回 参数))
  (公开 (函数 对得上吗 ((路径 文字) (样子 文字)) -> 是否
    (返回 (非空 (调 对一对 样子 路径)))))

  ; 地址栏井号后面那一段；没有就是 "/"。
  (函数 现在的地址 () -> 文字
    (设 井 (取 (宿 loc.now) "hash"))
    (如果 (非 (是类 井 "text")) (那么 (返回 "/")))
    (设 井字 (转 文字 井))
    (如果 (< (文长 井字) 2) (那么 (返回 "/")))
    (返回 (截 井字 1 (文长 井字))))
  (函数 位置格子 () -> 任意
    (如果 (非 (有键 格子们 "位置"))
      (那么 (存 格子们 "位置" (宿 page.state.new "" (标 任意 (调 现在的地址))))))
    (返回 (取 格子们 "位置")))
  (函数 对一遍 ()
    (做 (宿 page.state.write (调 位置格子) (调 现在的地址))))
  ; 头一次用到的时候才开始听：前进后退、地址栏里的井号被改。
  (函数 开始听 ()
    (如果 听着了 (那么 (返回)))
    (改 听着了 是)
    (做 (宿 loc.onPop (λ块 ((附带 任意)) (做 (调 对一遍)))))
    (做 (宿 win.on "window" "hashchange" (λ块 ((事件 (字典 任意))) (做 (调 对一遍))) (标 (字典 任意) (典))))
    (做 (调 对一遍)))

  (公开 (函数 登记 ((样子 文字) (名字 文字))
    (加项 路由表 (新记 一条路由 (样子 样子) (名字 名字)))))
  (公开 (函数 当前路径 () -> 文字
    (做 (调 开始听))
    (设 值 (宿 page.state.read (调 位置格子)))
    (如果 (是类 值 "text") (那么 (返回 (转 文字 值))))
    (返回 "/")))
  ; 路由表里头一条对得上的。
  (函数 找路由 ((路径 文字)) -> (可空 一条路由)
    (每个 条 路由表 (如果 (调 对得上吗 路径 (. 条 样子)) (那么 (返回 条))))
    (返回 空))
  (公开 (函数 当前页名 () -> 文字
    (设 这条 (调 找路由 (调 当前路径)))
    (如果 (非空 这条) (那么 (返回 (. 这条 名字))))
    (返回 "")))
  (公开 (函数 路由参数 ((名 文字)) -> 文字
    (设 路径 (调 当前路径))
    (设 这条 (调 找路由 路径))
    (如果 (非空 这条)
      (那么 (设 参数 (调 对一对 (. 这条 样子) 路径))
            (如果 (非空 参数)
              (那么 (设 值 (取 参数 名))
                    (如果 (非空 值) (那么 (返回 值)))))))
    (返回 "")))
  (公开 (函数 去 ((路径 文字))
    (做 (调 开始听))
    (做 (宿 loc.push (连 "#" 路径) (标 任意 空)))
    (做 (调 对一遍))))
  (公开 (函数 换成 ((路径 文字))
    (做 (调 开始听))
    (做 (宿 loc.replace (连 "#" 路径) (标 任意 空)))
    (做 (调 对一遍))))
  (公开 (函数 后退 ()
    (做 (调 开始听))
    (做 (宿 loc.go -1))))
  ; 当路由变了。等页面放上以后才开始看：这之前（比如在服务器上先出一遍页面的时候）没有地址栏可看。
  (公开 (函数 看路由 ((做法 (要等函数 (文字) 空)))
    (做 (宿 page.ui.life "mounted" (λ块 ((_ 任意))
      (做 (调 开始听))
      (设 格子 (调 位置格子))
      (做 (宿 page.state.watch
            (λ () (宿 page.state.read 格子))
            (λ块 ((新值 任意) (旧值 任意))
              (如果 (是类 新值 "text") (那么 (做 (调用 做法 (转 文字 新值)))))))))))))
  ; “现在是哪一页”跟着放进一个状态：控件的“存在条件”绑这个状态，就是按路由显示哪一块。
  (公开 (函数 页名放进状态 ((状态名 文字))
    (做 (调 开始听))
    (设 目标 (宿 page.state.new 状态名 (标 任意 "")))
    (做 (宿 page.state.write 目标 (调 当前页名)))
    (设 格子 (调 位置格子))
    (做 (宿 page.state.watch
          (λ () (宿 page.state.read 格子))
          (λ块 ((新值 任意) (旧值 任意)) (做 (宿 page.state.write 目标 (调 当前页名)))))))))
''';

const String kLcRouterBlocks = r'''
{"blocks": [
  {"id": "route", "category": "路由", "how": "call", "of": "登记", "args": ["pattern", "name"],
   "look": {"name": "路由", "shape": "statement", "template": "路由 {pattern} 叫做 {name}", "colorKey": "control",
            "hint": "放在“当页面放上以后”里。样子像 /detail/:id：冒号开头的那一段是参数，什么都对得上"}},
  {"id": "go", "category": "路由", "how": "call", "of": "去", "args": ["path"],
   "look": {"name": "去", "shape": "statement", "template": "去 {path}", "colorKey": "control",
            "hint": "地址栏井号后面换成这个路径，留一条后退的历史；页面不重新加载"}},
  {"id": "replace", "category": "路由", "how": "call", "of": "换成", "args": ["path"],
   "look": {"name": "换成", "shape": "statement", "template": "换成 {path}（不留后退）", "colorKey": "control"}},
  {"id": "back", "category": "路由", "how": "call", "of": "后退", "args": [],
   "look": {"name": "后退", "shape": "statement", "template": "后退一步", "colorKey": "control",
            "hint": "和点浏览器的后退一样；要过一小会儿才退完"}},
  {"id": "path", "category": "路由", "how": "call", "of": "当前路径", "args": [],
   "look": {"name": "现在的路径", "shape": "value", "template": "现在的路径", "colorKey": "control"}},
  {"id": "name", "category": "路由", "how": "call", "of": "当前页名", "args": [],
   "look": {"name": "现在是哪一页", "shape": "value", "template": "现在是哪一页", "colorKey": "control",
            "hint": "路由表里头一条对得上的那条的名字；都对不上是空字"}},
  {"id": "param", "category": "路由", "how": "call", "of": "路由参数", "args": ["name"],
   "look": {"name": "路由参数", "shape": "value", "template": "路由参数 {name}", "colorKey": "control", "hint": "没有这个参数是空字"}},
  {"id": "match", "category": "路由", "how": "call", "of": "对得上吗", "args": ["path", "pattern"],
   "look": {"name": "路径对得上吗", "shape": "value", "template": "路径 {path} 对得上 {pattern} 吗", "colorKey": "control"}},
  {"id": "onChange", "category": "路由", "how": "expand", "provides": {"路由": "新的路径"}, "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 看路由 (λ块 ((新的路径 文字)) (口 body))))",
   "look": {"name": "当路由变了", "shape": "hat", "template": "当路由变了 {body}", "colorKey": "event",
            "hint": "“去”“换成”“后退”、点浏览器的前进后退、手改地址栏以后到这里来"}},
  {"id": "newPath", "category": "路由", "how": "expand", "needs": ["路由"], "expand": "(隐含 路由)",
   "look": {"name": "新的路径", "shape": "value", "template": "新的路径", "colorKey": "event"}},
  {"id": "bind", "category": "路由", "how": "call", "of": "页名放进状态", "args": ["state"],
   "look": {"name": "现在是哪一页跟着放进状态", "shape": "statement", "template": "现在是哪一页，跟着放进状态 {state}", "colorKey": "control",
            "hint": "填页面里一个文字状态的名字，放在路由表后面。控件的“存在条件”绑这个状态，就是按路由显示哪一块"}}
]}
''';

const Map<String, String> kLcRouterLibFiles = {kLibManifestFile: kLcRouterManifest, 'modules/router.lc': kLcRouterModuleLc, 'blocks.json': kLcRouterBlocks};
