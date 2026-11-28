/// 自带的前端库“本地保存”（积木第 5 版·前端 2·第一批）：读、存、删、清空浏览器的本地存储；“这个状态关掉再开还在”。
///
/// 内容是语言核心写的模块，底下包的是存储那一组原生绑定（`storage.read / write / remove / keys`，区固定用 local）
/// 和状态的三个接口（“关掉再开还在”要读写状态、看它变没变）。存进去的值一律先变成 JSON 文字，读出来再变回来。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcStorageLibId = 'lopi/storage';

const String kLcStorageManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/storage",
  "name": "本地保存",
  "version": "1.0.0",
  "summary": "把东西存在这台设备的浏览器里：读、存、删、清空；让一个状态关掉再开还在",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/storage.lc", "name": "本地保存"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcStorageModuleLc = r'''
; 自带库“本地保存”的模块（严格规矩的语言核心写的）。
(模块 本地保存
  (宿主 storage.read ((区 文字) (键 文字)) -> (可空 文字))
  (宿主 storage.write ((区 文字) (键 文字) (值 文字)) -> 空)
  (宿主 storage.remove ((区 文字) (键 文字)) -> 空)
  (宿主 storage.keys ((区 文字)) -> (列表 文字))
  (宿主 page.state.new ((名 文字) (初值 任意)) -> 任意)
  (宿主 page.state.read ((格子 任意)) -> 任意)
  (宿主 page.state.write ((格子 任意) (值 任意)) -> 空)
  (宿主 page.state.watch ((取值 (不等函数 () 任意)) (做法 (要等函数 (任意 任意) 空))) -> (函数 () 空))

  ; 存的时候变成 JSON 文字，读的时候变回来；没存过、或者存的东西读不回来，就用给的那个值。
  (公开 (函数 读本地 ((键 文字) (没有就用 任意)) -> 任意
    (设 原文 (宿 storage.read "local" 键))
    (如果 (是空 原文) (那么 (返回 没有就用)))
    (试 (做 (返回 (读JSON (必有 原文))))
        (出错时 _ _ (返回 没有就用)))
    (返回 没有就用)))
  (公开 (函数 存本地 ((键 文字) (值 任意))
    (做 (宿 storage.write "local" 键 (转JSON 值)))))
  (公开 (函数 删本地 ((键 文字))
    (做 (宿 storage.remove "local" 键))))
  (公开 (函数 本地有 ((键 文字)) -> 是否
    (返回 (非空 (宿 storage.read "local" 键)))))
  (公开 (函数 本地的键 () -> (列表 文字)
    (返回 (宿 storage.keys "local"))))
  (公开 (函数 清空本地 ()
    (每个 键 (宿 storage.keys "local") (做 (宿 storage.remove "local" 键)))))
  ; 这个状态关掉再开还在：先把上次存的放回状态，以后状态每变一次就存一次。
  (公开 (函数 记住状态 ((名 文字) (键 文字))
    (设 格子 (宿 page.state.new 名 (标 任意 空)))
    (设 原文 (宿 storage.read "local" 键))
    (如果 (非空 原文)
      (那么 (试 (做 (做 (宿 page.state.write 格子 (读JSON (必有 原文)))))
                (出错时 _ _ (做 (宿 storage.remove "local" 键))))))
    (做 (宿 page.state.watch
          (λ () (宿 page.state.read 格子))
          (λ块 ((新值 任意) (旧值 任意)) (做 (宿 storage.write "local" 键 (转JSON 新值)))))))))
''';

const String kLcStorageBlocks = r'''
{"blocks": [
  {"id": "get", "category": "本地保存", "how": "expand",
   "expand": "(调 读本地 (槽 key) (标 任意 (槽 orElse)))",
   "look": {"name": "本地存的", "shape": "value", "template": "本地存的 {key}，没有就用 {orElse}", "colorKey": "data",
            "hint": "存在这台设备的浏览器里的东西；换一台设备、清了浏览器数据就没有了"}},
  {"id": "set", "category": "本地保存", "how": "expand",
   "expand": "(做 (调 存本地 (槽 key) (标 任意 (槽 value))))",
   "look": {"name": "存到本地", "shape": "statement", "template": "把 {value} 存到本地，名字叫 {key}", "colorKey": "data"}},
  {"id": "remove", "category": "本地保存", "how": "call", "of": "删本地", "args": ["key"],
   "look": {"name": "删掉本地存的", "shape": "statement", "template": "删掉本地存的 {key}", "colorKey": "data"}},
  {"id": "has", "category": "本地保存", "how": "call", "of": "本地有", "args": ["key"],
   "look": {"name": "本地存过吗", "shape": "value", "template": "本地存过 {key} 吗", "colorKey": "data"}},
  {"id": "keys", "category": "本地保存", "how": "call", "of": "本地的键", "args": [],
   "look": {"name": "本地存的所有名字", "shape": "value", "template": "本地存的所有名字", "colorKey": "data"}},
  {"id": "clear", "category": "本地保存", "how": "call", "of": "清空本地", "args": [],
   "look": {"name": "清空本地", "shape": "statement", "template": "清空本地存的所有东西", "colorKey": "data",
            "hint": "这个网址下存的全部删掉，删了找不回来"}},
  {"id": "persist", "category": "本地保存", "how": "expand",
   "expand": "(做 (调 记住状态 (槽 name) (槽 key)))",
   "look": {"name": "状态关掉再开还在", "shape": "statement", "template": "状态 {name} 关掉再开还在（存在本地的 {key} 下）", "colorKey": "data",
            "hint": "放在“当页面放上以后”里：先把上次存的放回这个状态，以后它每变一次就存一次"}}
]}
''';

const Map<String, String> kLcStorageLibFiles = {kLibManifestFile: kLcStorageManifest, 'modules/storage.lc': kLcStorageModuleLc, 'blocks.json': kLcStorageBlocks};
