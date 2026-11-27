/// 内置库“页面”（积木第 5 版·前端 1）：清单、积木表，和读好的库。
///
/// 和内置库“接口服务”、和用户自己写的库是**同一种格式**（docs/blocks-v5-parts/library-format.md）、走同一个读入器（`libRead`）。
/// 旧页面积木（设置变量、改控件、等一会儿、请求网址……）在这里各有一块对着的库积木，靠 `legacy` 旧名对照自动翻（旧文件不改写）。
/// 对照表见 docs/blocks-v5-parts/D-frontend-logic.md §7.1 和末尾的落地说明。
library;

import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_page_module.dart';

/// 库的标识。
const String kLcPageLibId = 'lopi/page';

/// 清单 `lib.json`。
const String kLcPageManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/page",
  "name": "页面",
  "version": "1.0.0",
  "summary": "状态、控件、页面上的事件、弹提示、去网址",
  "rules": 2,
  "for": "frontend",
  "autoUse": ["frontend"],
  "native": {"allowed": false},
  "modules": [{"file": "modules/page.lc", "name": "页面"}],
  "blocks": ["blocks.json"],
  "types": [
    {"name": "事件", "module": "页面", "hint": "一次事件：value 输入的内容、checked 勾上了、key 键、x / y 坐标、target 触发的控件"}
  ]
}
''';

/// 积木表 `blocks.json`。带 `legacy` 的是旧页面积木对着的那一块；分类“旧积木”的只给旧文件用，不进积木盒。
const String kLcPageBlocks = r'''
{"blocks": [
  {"id": "onClick", "category": "事件", "how": "expand", "provides": {"事件": "这次事件"},
   "slotKinds": {"node": "literal", "body": "mouth"},
   "expand": "(做 (调 当控件事件 (槽 node) \"click\" (λ块 ((这次事件 事件)) (口 body))))",
   "look": {"name": "当控件被点击", "shape": "hat", "template": "当 {node} 被点击 {body}", "colorKey": "event"}},
  {"id": "onInput", "category": "事件", "how": "expand", "provides": {"事件": "这次事件"},
   "slotKinds": {"node": "literal", "body": "mouth"},
   "expand": "(做 (调 当控件事件 (槽 node) \"input\" (λ块 ((这次事件 事件)) (口 body))))",
   "look": {"name": "当输入内容变化", "shape": "hat", "template": "当 {node} 的输入内容变化 {body}", "colorKey": "event"}},
  {"id": "onMounted", "category": "事件", "how": "expand", "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 当页面放上以后 (λ块 () (口 body))))",
   "look": {"name": "当页面放上以后", "shape": "hat", "template": "当页面放上以后 {body}", "colorKey": "event",
            "hint": "页面打开、控件都在了以后做一次"}},
  {"id": "onUnmount", "category": "事件", "how": "expand", "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 当页面拿走之前 (λ块 () (口 body))))",
   "look": {"name": "当页面拿走之前", "shape": "hat", "template": "当页面拿走之前 {body}", "colorKey": "event"}},
  {"id": "onError", "category": "事件", "how": "expand", "provides": {"出错的话": "出错的那句话"}, "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 当页面出错时 (λ块 ((出错的那句话 文字)) (口 body))))",
   "look": {"name": "当页面出错时", "shape": "hat", "template": "当页面出错时 {body}", "colorKey": "event",
            "hint": "哪里出了错又没有人接住，就到这里来"}},
  {"id": "errorText", "category": "事件", "how": "expand", "needs": ["出错的话"],
   "expand": "(隐含 出错的话)",
   "look": {"name": "出错的那句话", "shape": "value", "template": "出错的那句话", "colorKey": "event"}},
  {"id": "eventValue", "category": "事件", "how": "call", "of": "事件的值", "args": [{"context": "事件"}], "needs": ["事件"],
   "legacy": {"fn": "event", "args": ["@事件"]},
   "look": {"name": "输入的内容", "shape": "value", "template": "输入的内容", "colorKey": "event",
            "hint": "输入框现在的内容（在“当输入内容变化”里用）"}},
  {"id": "eventKey", "category": "事件", "how": "call", "of": "事件的键", "args": [{"context": "事件"}], "needs": ["事件"],
   "look": {"name": "按下的键", "shape": "value", "template": "按下的键", "colorKey": "event"}},

  {"id": "stateGet", "category": "状态", "how": "call", "of": "读状态", "args": ["name"], "slotKinds": {"name": "literal"},
   "legacy": {"fn": "var", "args": ["name"]},
   "look": {"name": "状态的值", "shape": "value", "template": "状态 {name}", "colorKey": "state"}},
  {"id": "stateSet", "category": "状态", "how": "expand", "slotKinds": {"name": "literal"},
   "legacy": {"fn": "setVar", "args": ["name", "value"]},
   "expand": "(做 (调 写状态 (槽 name) (标 任意 (槽 value))))",
   "look": {"name": "设置状态", "shape": "statement", "template": "把状态 {name} 设成 {value}", "colorKey": "state",
            "hint": "改了马上生效；绑着它的界面等这一段做完再一起更新"}},
  {"id": "stateWatch", "category": "状态", "how": "expand", "provides": {"新值": "变成的新值", "旧值": "原来的旧值"},
   "slotKinds": {"name": "literal", "body": "mouth"},
   "expand": "(做 (调 当状态变了 (槽 name) (λ块 ((变成的新值 任意) (原来的旧值 任意)) (口 body))))",
   "look": {"name": "当状态变了", "shape": "hat", "template": "当状态 {name} 变了 {body}", "colorKey": "state",
            "hint": "一段代码里改了好几次，只在做完以后来一次"}},
  {"id": "watchNew", "category": "状态", "how": "expand", "needs": ["新值"], "expand": "(隐含 新值)",
   "look": {"name": "新值", "shape": "value", "template": "新值", "colorKey": "state"}},
  {"id": "watchOld", "category": "状态", "how": "expand", "needs": ["旧值"], "expand": "(隐含 旧值)",
   "look": {"name": "旧值", "shape": "value", "template": "旧值", "colorKey": "state"}},

  {"id": "propGet", "category": "控件", "how": "call", "of": "读控件", "args": ["node", "prop"],
   "slotKinds": {"node": "literal", "prop": "literal"}, "legacy": {"fn": "prop", "args": ["node", "prop"]},
   "look": {"name": "控件的属性", "shape": "value", "template": "{node} 的 {prop}", "colorKey": "ui"}},
  {"id": "propSet", "category": "控件", "how": "expand", "slotKinds": {"node": "literal", "prop": "literal"},
   "legacy": {"fn": "setProp", "args": ["node", "prop", "value"]},
   "expand": "(做 (调 改控件 (槽 node) (槽 prop) (标 任意 (槽 value))))",
   "look": {"name": "改控件", "shape": "statement", "template": "把 {node} 的 {prop} 改成 {value}", "colorKey": "ui"}},

  {"id": "alert", "category": "页面", "how": "expand", "legacy": {"fn": "alert", "args": ["message"]},
   "expand": "(做 (调 弹提示 (标 任意 (槽 message))))",
   "look": {"name": "弹提示", "shape": "statement", "template": "弹出提示 {message}", "colorKey": "page"}},
  {"id": "confirm", "category": "页面", "how": "expand",
   "expand": "(调 问一句 (标 任意 (槽 message)))",
   "look": {"name": "问一句", "shape": "value", "template": "问一句 {message}（点了确定吗）", "colorKey": "page"}},
  {"id": "navigate", "category": "页面", "how": "expand", "legacy": {"fn": "navigate", "args": ["url"]},
   "expand": "(做 (调 去网址 (调 旧文 (标 任意 (槽 url)))))",
   "look": {"name": "去网址", "shape": "statement", "template": "打开网址 {url}", "colorKey": "page"}},
  {"id": "after", "category": "页面", "how": "expand", "slotKinds": {"body": "mouth"},
   "legacy": {"fn": "wait", "args": ["ms"]},
   "expand": "(做 (调 过后做 (调 旧数 (标 任意 (槽 ms))) (λ块 () (口 body))))",
   "look": {"name": "过一会儿做", "shape": "statement", "template": "过 {ms} 毫秒以后 {body}", "colorKey": "page",
            "hint": "只管它里面的积木：排在它后面的积木不等，马上接着做"}},

  {"id": "oldNum", "category": "旧积木", "how": "call", "of": "旧数", "args": ["value"], "legacy": {"fn": "lcNum", "args": ["value"]},
   "look": {"name": "转成数字（旧）", "shape": "value", "template": "{value} 转成数字", "colorKey": "old"}},
  {"id": "oldText", "category": "旧积木", "how": "call", "of": "旧文", "args": ["value"], "legacy": {"fn": "lcText", "args": ["value"]},
   "look": {"name": "转成文字（旧）", "shape": "value", "template": "{value} 转成文字", "colorKey": "old"}},
  {"id": "oldTruthy", "category": "旧积木", "how": "call", "of": "旧真", "args": ["value"], "legacy": {"fn": "lcBool", "args": ["value"]},
   "look": {"name": "算不算成立（旧）", "shape": "value", "template": "{value} 成立", "colorKey": "old"}},
  {"id": "oldEq", "category": "旧积木", "how": "call", "of": "旧等", "args": ["a", "b"], "legacy": {"fn": "lcEq", "args": ["a", "b"]},
   "look": {"name": "等于（旧）", "shape": "value", "template": "{a} 等于 {b}", "colorKey": "old"}},
  {"id": "oldOp", "category": "旧积木", "how": "call", "of": "旧算", "args": ["op", "a", "b"], "slotKinds": {"op": "literal"},
   "legacy": {"fn": "bin", "args": ["op", "a", "b"]},
   "look": {"name": "运算（旧）", "shape": "value", "template": "{a} {op} {b}", "colorKey": "old"}},
  {"id": "oldLog", "category": "旧积木", "how": "expand", "legacy": {"fn": "log", "args": ["value"]},
   "expand": "(做 (调 旧打印 (标 任意 (槽 value))))",
   "look": {"name": "打印（旧）", "shape": "statement", "template": "打印 {value}", "colorKey": "old"}},
  {"id": "oldFetch", "category": "旧积木", "how": "expand", "provides": {"回应文字": "拿到的回应文字"},
   "slotKinds": {"method": "literal", "body": "mouth", "orElse": "mouth"},
   "legacy": {"fn": "fetch", "args": ["method", "url"]},
   "expand": "(做 (开始做块 (设 拿到的 (调 旧请求 (槽 method) (调 旧文 (标 任意 (槽 url))))) (如果 (是空 拿到的) (那么 (口 orElse)) (否则 (设 拿到的回应文字 (必有 拿到的)) (口 body)))))",
   "look": {"name": "请求网址（旧）", "shape": "statement", "template": "用 {method} 请求 {url} 成功后 {body} 失败后 {orElse}", "colorKey": "old",
            "hint": "只管它里面的积木：排在它后面的积木不等，马上接着做",
            "slots": [{"name": "method", "kind": "choice", "options": ["GET", "POST"], "defaultValue": "GET"}]}},
  {"id": "fetchText", "category": "旧积木", "how": "expand", "needs": ["回应文字"], "expand": "(隐含 回应文字)",
   "look": {"name": "拿到的回应文字", "shape": "value", "template": "拿到的回应文字", "colorKey": "old"}}
]}
''';

/// 只给旧文件用、不进积木盒的那一类。
const String kLcPageOldCategory = '旧积木';

/// 库文件夹的内容：相对路径 → 文件内容。
const Map<String, String> kLcPageLibFiles = {kLibManifestFile: kLcPageManifest, 'modules/page.lc': kLcPageModuleLc, 'blocks.json': kLcPageBlocks};

LibLibrary? _cached;

/// 读好的内置库（只读一次）。
LibLibrary lcPageLibrary() => _cached ??= libRead(kLcPageLibFiles, builtin: true);
