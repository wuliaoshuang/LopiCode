/// 内置库“接口服务”（积木第 5 版·库 1）：清单、积木表，和读好的库。
///
/// 它和用户自己写的库是**同一种格式**（docs/blocks-v5-parts/library-format.md）、走同一个读入器（`libRead`）；
/// 这里只是把库文件夹里的三个文件写成了 Dart 里的文字（随应用带着，不用读磁盘）。对照表见 docs/blocks-v5-parts/backend-lib-mapping.md。
library;

import 'package:lopicode/backend/lib_service_module.dart';
import 'package:lopicode/lang/lib_model.dart';

/// 库的标识。
const String kBeServiceLibId = 'lopi/service';

/// 清单 `lib.json`。
const String kBeServiceManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/service",
  "name": "接口服务",
  "version": "1.0.0",
  "summary": "收请求、回应、数据集合",
  "rules": 2,
  "autoUse": ["backend"],
  "native": {"allowed": false},
  "modules": [{"file": "modules/service.lc", "name": "接口服务"}],
  "blocks": ["blocks.json"],
  "types": [
    {"name": "请求", "module": "接口服务", "hint": "这次请求：方式、路径参数、网址参数、请求头、内容"},
    {"name": "回应类型", "module": "接口服务", "hint": "回给对方的东西：状态码、说明、内容"},
    {"name": "一条记录", "module": "接口服务", "hint": "数据集合里的一条：一个带 id 的字典"}
  ],
  "settings": [
    {"id": "port", "name": "端口", "type": "整数", "default": 8080, "min": 1, "max": 65535, "legacyKey": "port",
     "hint": "服务器上设了 PORT 这个环境变量就听它的"},
    {"id": "collections", "name": "数据集合", "type": "(列表 文字)", "default": [], "legacyKey": "collections",
     "hint": "这份文档里有哪些集合（积木上“集合”那一格从这里选）"}
  ],
  "init": "(设 接口服务的路由表 (调 新路由表))",
  "start": "(做 (调 开服务 接口服务的路由表 (设置 port)))",
  "provides": {"路由表": "接口服务的路由表"}
}
''';

/// 积木表 `blocks.json`。对照表里的 17 块都在（“请求别的网址”是库 1 下半加的，带两个口的展开型）。
/// 另有两块“现在的时间”“字典的字段”：对照表把它们归在基础库，基础库还没有成库之前先放这里（旧名 now、field）。
const String kBeServiceBlocks = r'''
{"blocks": [
  {"id": "onRequest", "category": "接口", "how": "expand", "needs": ["路由表"], "provides": {"请求": "这次请求"},
   "slotKinds": {"method": "literal", "path": "literal", "body": "mouth"},
   "expand": "(做 (调 加路由 (隐含 路由表) (槽 method) (槽 path) (λ块 ((这次请求 请求)) (口 body (收尾 (返回 (调 没有内容)))))))",
   "look": {"name": "当收到请求", "shape": "hat", "template": "当收到 {method} {path} {body}", "colorKey": "route",
            "hint": "走完没有“返回”就回 204（没有内容）",
            "slots": [{"name": "method", "kind": "choice", "options": ["GET", "POST", "PUT", "PATCH", "DELETE"], "defaultValue": "GET"}]}},

  {"id": "respondJson", "category": "返回", "how": "expand", "legacy": {"fn": "sendJson", "args": ["status", "value"]},
   "expand": "(返回 (调 回JSON (调 状态码 (标 任意 (槽 status))) (标 任意 (槽 value))))",
   "look": {"name": "返回数据", "shape": "cap", "template": "返回数据 {value}，状态码 {status}", "colorKey": "respond",
            "slots": [{"name": "status", "kind": "value", "defaultValue": 200}]}},
  {"id": "respondText", "category": "返回", "how": "expand", "legacy": {"fn": "sendText", "args": ["status", "value"]},
   "expand": "(返回 (调 回文字 (调 状态码 (标 任意 (槽 status))) (标 任意 (槽 value))))",
   "look": {"name": "返回文字", "shape": "cap", "template": "返回文字 {value}，状态码 {status}", "colorKey": "respond",
            "slots": [{"name": "status", "kind": "value", "defaultValue": 200}]}},
  {"id": "respond", "category": "返回", "how": "expand",
   "expand": "(返回 (调 回应 (调 状态码 (标 任意 (槽 status))) (槽 type) (槽 content)))",
   "look": {"name": "回应", "shape": "cap", "template": "回应：状态码 {status}，说明 {type}，内容 {content}", "colorKey": "respond",
            "hint": "说明＝内容是什么（比如 text/html; charset=utf-8）；内容是文字",
            "slots": [{"name": "status", "kind": "value", "defaultValue": 200}]}},

  {"id": "pathParam", "category": "请求", "how": "call", "of": "路径参数", "args": [{"context": "请求"}, "name"], "needs": ["请求"],
   "slotKinds": {"name": "literal"}, "legacy": {"fn": "pathParam", "args": ["@请求", "name"]},
   "look": {"name": "路径参数", "shape": "value", "template": "路径参数 {name}", "colorKey": "request"}},
  {"id": "query", "category": "请求", "how": "call", "of": "网址参数", "args": [{"context": "请求"}, "name"], "needs": ["请求"],
   "slotKinds": {"name": "literal"}, "legacy": {"fn": "query", "args": ["@请求", "name"]},
   "look": {"name": "网址参数", "shape": "value", "template": "网址参数 {name}", "colorKey": "request"}},
  {"id": "bodyField", "category": "请求", "how": "expand", "needs": ["请求"],
   "slotKinds": {"name": "literal"}, "legacy": {"fn": "bodyField", "args": ["@请求", "name"]},
   "expand": "(调 字段 (调 读内容 (隐含 请求)) (槽 name))",
   "look": {"name": "请求内容的字段", "shape": "value", "template": "请求内容的 {name}", "colorKey": "request"}},
  {"id": "body", "category": "请求", "how": "call", "of": "读内容", "args": [{"context": "请求"}], "needs": ["请求"],
   "legacy": {"fn": "body", "args": ["@请求"]},
   "look": {"name": "整个请求内容", "shape": "value", "template": "整个请求内容", "colorKey": "request"}},
  {"id": "header", "category": "请求", "how": "call", "of": "请求头", "args": [{"context": "请求"}, "name"], "needs": ["请求"],
   "slotKinds": {"name": "literal"}, "legacy": {"fn": "header", "args": ["@请求", "name"]},
   "look": {"name": "请求头", "shape": "value", "template": "请求头 {name}", "colorKey": "request"}},

  {"id": "dbAll", "category": "数据集合", "how": "call", "of": "全部记录", "args": ["collection"],
   "slotKinds": {"collection": "literal"}, "legacy": {"fn": "dbAll", "args": ["collection"]},
   "look": {"name": "集合的全部", "shape": "value", "template": "{collection} 的全部", "colorKey": "data"}},
  {"id": "dbGet", "category": "数据集合", "how": "expand",
   "slotKinds": {"collection": "literal"}, "legacy": {"fn": "dbGet", "args": ["collection", "id"]},
   "expand": "(调 按号取 (槽 collection) (标 任意 (槽 id)))",
   "look": {"name": "集合里的一条", "shape": "value", "template": "{collection} 里 id 是 {id} 的那条", "colorKey": "data"}},
  {"id": "dbFind", "category": "数据集合", "how": "expand",
   "slotKinds": {"collection": "literal", "key": "literal"}, "legacy": {"fn": "dbFind", "args": ["collection", "key", "value"]},
   "expand": "(调 按字段找 (槽 collection) (槽 key) (标 任意 (槽 value)))",
   "look": {"name": "集合里符合的", "shape": "value", "template": "{collection} 里 {key} 等于 {value} 的", "colorKey": "data"}},
  {"id": "dbCount", "category": "数据集合", "how": "call", "of": "有几条", "args": ["collection"],
   "slotKinds": {"collection": "literal"}, "legacy": {"fn": "dbCount", "args": ["collection"]},
   "look": {"name": "集合有几条", "shape": "value", "template": "{collection} 有几条", "colorKey": "data"}},
  {"id": "dbInsert", "category": "数据集合", "how": "expand",
   "slotKinds": {"collection": "literal", "into": "assign"}, "legacy": {"fn": "dbInsert", "args": ["collection", "value"]},
   "expand": "(放进 into (调 加一条 (槽 collection) (标 任意 (槽 value))))",
   "look": {"name": "往集合里加", "shape": "statement", "template": "往 {collection} 里加 {value}，加好的那条放进 {into}", "colorKey": "data"}},
  {"id": "dbUpdate", "category": "数据集合", "how": "expand",
   "slotKinds": {"collection": "literal"}, "legacy": {"fn": "dbUpdate", "args": ["collection", "id", "value"]},
   "expand": "(做 (调 改一条 (槽 collection) (标 任意 (槽 id)) (标 任意 (槽 value))))",
   "look": {"name": "改集合里的一条", "shape": "statement", "template": "把 {collection} 里 id 是 {id} 的那条改成 {value}", "colorKey": "data"}},
  {"id": "dbDelete", "category": "数据集合", "how": "expand",
   "slotKinds": {"collection": "literal"}, "legacy": {"fn": "dbDelete", "args": ["collection", "id"]},
   "expand": "(做 (调 删一条 (槽 collection) (标 任意 (槽 id))))",
   "look": {"name": "删集合里的一条", "shape": "statement", "template": "把 {collection} 里 id 是 {id} 的那条删掉", "colorKey": "data"}},

  {"id": "fetch", "category": "网络", "how": "expand",
   "slotKinds": {"method": "literal", "into": "assign", "body": "mouth", "orElse": "mouth"},
   "legacy": {"fn": "fetch", "args": ["method", "url", "data"]},
   "expand": "(设 拿到的 (调 请求网址 (槽 method) (标 任意 (槽 url)) (标 任意 (槽 data)))) (如果 (是空 拿到的) (那么 (口 orElse)) (否则 (放进 into (必有 拿到的)) (口 body)))",
   "look": {"name": "请求别的网址", "shape": "statement", "template": "用 {method} 请求 {url} 带上 {data} 结果放进 {into} 成功后 {body} 失败后 {orElse}", "colorKey": "network",
            "hint": "最多等 10 秒；只有 200 多的回应算成功；带用户名密码（@）的网址不请求",
            "slots": [{"name": "method", "kind": "choice", "options": ["GET", "POST"], "defaultValue": "GET"}]}},

  {"id": "field", "category": "其他", "how": "expand", "slotKinds": {"key": "literal"}, "legacy": {"fn": "field", "args": ["of", "key"]},
   "expand": "(调 字段 (标 任意 (槽 of)) (槽 key))",
   "look": {"name": "字典的字段", "shape": "value", "template": "{of} 的 {key}", "colorKey": "data",
            "hint": "给的不是字典就得空（宽松的取法；严格的用语言基础里的“取”）"}},
  {"id": "nowText", "category": "其他", "how": "call", "of": "现在", "args": [], "legacy": {"fn": "now", "args": []},
   "look": {"name": "现在的时间", "shape": "value", "template": "现在的时间", "colorKey": "data",
            "hint": "形如 2026-11-24T06:00:00Z 的文字（世界标准时间）"}}
]}
''';

/// 库文件夹的内容：相对路径 → 文件内容。
const Map<String, String> kBeServiceLibFiles = {kLibManifestFile: kBeServiceManifest, 'modules/service.lc': kBeServiceModuleLc, 'blocks.json': kBeServiceBlocks};

LibLibrary? _cached;

/// 读好的内置库（只读一次）。
LibLibrary beServiceLibrary() => _cached ??= libRead(kBeServiceLibFiles, builtin: true);
