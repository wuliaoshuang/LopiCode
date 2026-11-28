/// 自带的前端库“事件总线”（积木第 5 版·前端 2·第一批）：发消息、当收到消息、不再听。
///
/// 纯语言核心写的，一个原生绑定都不碰：一张“消息名 → 在听的人”的表。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcBusLibId = 'lopi/bus';

const String kLcBusManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/bus",
  "name": "事件总线",
  "version": "1.0.0",
  "summary": "页面里各处互相递消息：发消息、当收到消息、不再听",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/bus.lc", "name": "事件总线"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcBusModuleLc = r'''
; 自带库“事件总线”的模块（严格规矩的语言核心写的，不碰宿主接口）。
(模块 事件总线
  (记录 听的人 (号 整数) (做法 (要等函数 (任意) 空)))
  (变量 在听的 (字典 (列表 听的人)) (典))
  (变量 下一个号 整数 1)

  ; 开始听一种消息；交回一个号，拿它可以“不再听”。
  (公开 (函数 听消息 ((名 文字) (做法 (要等函数 (任意) 空))) -> 整数
    (设 号 下一个号)
    (改 下一个号 (+ 下一个号 1))
    (设 新的 (列表 听的人) (列))
    (设 原来的 (取 在听的 名))
    (如果 (非空 原来的) (那么 (每个 旧 原来的 (加项 新的 旧))))
    (加项 新的 (新记 听的人 (号 号) (做法 做法)))
    (存 在听的 名 新的)
    (返回 号)))
  ; 发消息：这一刻在听的人挨个收到（收的时候有人不听了、有人新来听，都不影响这一次）。
  (公开 (函数 发消息 ((名 文字) (带上 任意))
    (设 这一刻 (取 在听的 名))
    (如果 (非空 这一刻) (那么 (每个 人 这一刻 (做 (调用 (. 人 做法) 带上)))))))
  ; 号可以是直接拿到的整数，也可以是存进状态又读出来的；不是数字就什么都不做。
  (公开 (函数 不再听 ((给的号 任意))
    (如果 (非 (是类 给的号 "number")) (那么 (返回)))
    (设 号 (取整 (转 小数 给的号)))
    (设 新表 (字典 (列表 听的人)) (典))
    (每对 名 人们 在听的
      (设 剩下 (列表 听的人) (列))
      (每个 人 人们 (如果 (!= (. 人 号) 号) (那么 (加项 剩下 人))))
      (存 新表 名 剩下))
    (改 在听的 新表)))
  (公开 (函数 都不听了 ((名 文字))
    (如果 (有键 在听的 名) (那么 (删键 在听的 名)))))
  (公开 (函数 有几个在听 ((名 文字)) -> 整数
    (设 人们 (取 在听的 名))
    (如果 (非空 人们) (那么 (返回 (长 人们))))
    (返回 0))))
''';

const String kLcBusBlocks = r'''
{"blocks": [
  {"id": "on", "category": "事件总线", "how": "expand", "provides": {"消息": "收到的消息"}, "slotKinds": {"name": "literal", "body": "mouth"},
   "expand": "(做 (调 听消息 (槽 name) (λ块 ((收到的消息 任意)) (口 body))))",
   "look": {"name": "当收到消息", "shape": "hat", "template": "当收到消息 {name} {body}", "colorKey": "event",
            "hint": "别处“发消息”发了这个名字的消息，就到这里来"}},
  {"id": "data", "category": "事件总线", "how": "expand", "needs": ["消息"], "expand": "(隐含 消息)",
   "look": {"name": "消息带来的", "shape": "value", "template": "消息带来的", "colorKey": "event"}},
  {"id": "emit", "category": "事件总线", "how": "expand",
   "expand": "(做 (调 发消息 (槽 name) (标 任意 (槽 value))))",
   "look": {"name": "发消息", "shape": "statement", "template": "发消息 {name} 带上 {value}", "colorKey": "event",
            "hint": "在听这个名字的人挨个收到；都收完了才接着往下做"}},
  {"id": "listen", "category": "事件总线", "how": "expand", "provides": {"消息": "收到的消息"}, "slotKinds": {"into": "assign", "body": "mouth"},
   "expand": "(放进 into (调 听消息 (槽 name) (λ块 ((收到的消息 任意)) (口 body))))",
   "look": {"name": "开始听消息", "shape": "statement", "template": "开始听消息 {name}，号放进 {into} {body}", "colorKey": "event",
            "hint": "和“当收到消息”一样，只是从这一句才开始听；号留着，可以拿去“不再听”"}},
  {"id": "off", "category": "事件总线", "how": "expand", "expand": "(做 (调 不再听 (标 任意 (槽 id))))",
   "look": {"name": "不再听", "shape": "statement", "template": "不再听 {id}", "colorKey": "event", "hint": "号是“开始听消息”放进变量的那个"}},
  {"id": "clear", "category": "事件总线", "how": "call", "of": "都不听了", "args": ["name"],
   "look": {"name": "都不听了", "shape": "statement", "template": "消息 {name} 谁都不听了", "colorKey": "event"}},
  {"id": "count", "category": "事件总线", "how": "call", "of": "有几个在听", "args": ["name"],
   "look": {"name": "有几个在听", "shape": "value", "template": "消息 {name} 有几个在听", "colorKey": "event"}}
]}
''';

const Map<String, String> kLcBusLibFiles = {kLibManifestFile: kLcBusManifest, 'modules/bus.lc': kLcBusModuleLc, 'blocks.json': kLcBusBlocks};
