/// 自带的前端库“状态仓库”（积木第 5 版·前端 2·第一批）：新建仓库、读、改、当仓库变了、动作、关掉再开还在。
///
/// 一个仓库＝一个有名字的记录（字典），放在一个“会通知的格子”里：改了它，在看它的人（“当仓库变了”）会收到。
/// 内容是语言核心写的模块，底下包的是状态那四个接口和存储的读、写两个原生绑定（“关掉再开还在”用）。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcStoreLibId = 'lopi/store';

const String kLcStoreManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/store",
  "name": "状态仓库",
  "version": "1.0.0",
  "summary": "把一组有关的数据放在一个有名字的仓库里：读、改、看它变没变、给它定动作、关掉再开还在",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/store.lc", "name": "状态仓库"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcStoreModuleLc = r'''
; 自带库“状态仓库”的模块（严格规矩的语言核心写的）。
(模块 状态仓库
  (宿主 page.state.new ((名 文字) (初值 任意)) -> 任意)
  (宿主 page.state.read ((格子 任意)) -> 任意)
  (宿主 page.state.write ((格子 任意) (值 任意)) -> 空)
  (宿主 page.state.watch ((取值 (不等函数 () 任意)) (做法 (要等函数 (任意 任意) 空))) -> (函数 () 空))
  (宿主 storage.read ((区 文字) (键 文字)) -> (可空 文字))
  (宿主 storage.write ((区 文字) (键 文字) (值 文字)) -> 空)

  (记录 动作 (做法 (要等函数 (任意) 空)))
  ; 仓库名 → 它的格子（没有名字的、会通知的格子，里面放一个字典）。
  (变量 格子们 (字典 任意) (典))
  ; “仓库名/动作名” → 动作
  (变量 动作们 (字典 动作) (典))

  ; 还没有这个仓库就先建一个空的：先看、后建都行。
  (函数 仓库的格子 ((名 文字)) -> 任意
    (如果 (非 (有键 格子们 名))
      (那么 (存 格子们 名 (宿 page.state.new "" (标 任意 (标 (字典 任意) (典)))))))
    (返回 (取 格子们 名)))
  (公开 (函数 仓库全部 ((名 文字)) -> (字典 任意)
    (返回 (转 (字典 任意) (宿 page.state.read (调 仓库的格子 名))))))
  ; 新建仓库：开始时的那些项放进去；已经有的项不动（所以写两遍也没事）。
  (公开 (函数 新建仓库 ((名 文字) (开始是 (字典 任意)))
    (设 现在 (调 仓库全部 名))
    (设 新的 (字典 任意) (典))
    (每对 键 值 开始是 (存 新的 键 值))
    (每对 键 值 现在 (存 新的 键 值))
    (做 (宿 page.state.write (调 仓库的格子 名) 新的))))
  (公开 (函数 读仓库 ((名 文字) (键 文字)) -> 任意
    (设 全部 (调 仓库全部 名))
    (如果 (有键 全部 键) (那么 (返回 (取 全部 键))))
    (返回 空)))
  ; 改一项：抄一份新的再整个放回去（放回去在看的人才收得到）。
  (公开 (函数 改仓库 ((名 文字) (键 文字) (值 任意))
    (设 新的 (字典 任意) (典))
    (每对 旧键 旧值 (调 仓库全部 名) (存 新的 旧键 旧值))
    (存 新的 键 值)
    (做 (宿 page.state.write (调 仓库的格子 名) 新的))))
  ; 当仓库变了：一段里改了好几次，做完以后只来一次。交回“不看了”。
  (公开 (函数 看仓库 ((名 文字) (做法 (要等函数 ((字典 任意)) 空))) -> (函数 () 空)
    (设 格子 (调 仓库的格子 名))
    (返回 (宿 page.state.watch
            (λ () (宿 page.state.read 格子))
            (λ块 ((新值 任意) (旧值 任意)) (做 (调用 做法 (转 (字典 任意) 新值))))))))
  ; 动作：给仓库定一件有名字的事，别处“让仓库做动作”就做它。
  (公开 (函数 定动作 ((名 文字) (动作名 文字) (做法 (要等函数 (任意) 空)))
    (存 动作们 (连 名 "/" 动作名) (新记 动作 (做法 做法)))))
  (公开 (函数 做动作 ((名 文字) (动作名 文字) (带上 任意))
    (设 找 (连 名 "/" 动作名))
    (如果 (非 (有键 动作们 找)) (那么 (抛出 (连 "仓库「" 名 "」没有叫「" 动作名 "」的动作"))))
    (设 这个 (取 动作们 找))
    (如果 (非空 这个) (那么 (做 (调用 (. 这个 做法) 带上))))))
  ; 关掉再开还在：先把上次存的放回仓库，以后仓库每变一次就存一次。
  (公开 (函数 记住仓库 ((名 文字) (键 文字))
    (设 格子 (调 仓库的格子 名))
    (设 原文 (宿 storage.read "local" 键))
    (如果 (非空 原文)
      (那么 (试 (做
                  (设 读到 (读JSON (必有 原文)))
                  (如果 (是类 读到 "dict")
                    (那么 (设 新的 (字典 任意) (典))
                          (每对 原键 原值 (调 仓库全部 名) (存 新的 原键 原值))
                          (每对 存键 存值 (转 (字典 任意) 读到) (存 新的 存键 存值))
                          (做 (宿 page.state.write 格子 新的)))))
                (出错时 _ _ (做 (宿 storage.write "local" 键 "{}"))))))
    (做 (宿 page.state.watch
          (λ () (宿 page.state.read 格子))
          (λ块 ((新值 任意) (旧值 任意)) (做 (宿 storage.write "local" 键 (转JSON 新值)))))))))
''';

const String kLcStoreBlocks = r'''
{"blocks": [
  {"id": "create", "category": "状态仓库", "how": "expand",
   "expand": "(做 (调 新建仓库 (槽 store) (槽 initial)))",
   "look": {"name": "新建仓库", "shape": "statement", "template": "新建仓库 {store}，开始是 {initial}", "colorKey": "variable",
            "hint": "开始是一个字典：名字 : 值。放在“当页面放上以后”里"}},
  {"id": "get", "category": "状态仓库", "how": "call", "of": "读仓库", "args": ["store", "key"],
   "look": {"name": "仓库里的", "shape": "value", "template": "仓库 {store} 里的 {key}", "colorKey": "variable", "hint": "没有这一项就是空"}},
  {"id": "all", "category": "状态仓库", "how": "call", "of": "仓库全部", "args": ["store"],
   "look": {"name": "整个仓库", "shape": "value", "template": "整个仓库 {store}", "colorKey": "variable", "hint": "一个字典"}},
  {"id": "set", "category": "状态仓库", "how": "expand",
   "expand": "(做 (调 改仓库 (槽 store) (槽 key) (标 任意 (槽 value))))",
   "look": {"name": "改仓库", "shape": "statement", "template": "把仓库 {store} 里的 {key} 改成 {value}", "colorKey": "variable"}},
  {"id": "watch", "category": "状态仓库", "how": "expand", "provides": {"仓库": "变了以后的仓库"}, "slotKinds": {"store": "literal", "body": "mouth"},
   "expand": "(做 (调 看仓库 (槽 store) (λ块 ((变了以后的仓库 (字典 任意))) (口 body))))",
   "look": {"name": "当仓库变了", "shape": "hat", "template": "当仓库 {store} 变了 {body}", "colorKey": "variable",
            "hint": "一段里改了好几次，做完以后只来一次"}},
  {"id": "changed", "category": "状态仓库", "how": "expand", "needs": ["仓库"], "expand": "(隐含 仓库)",
   "look": {"name": "变了以后的仓库", "shape": "value", "template": "变了以后的仓库", "colorKey": "variable"}},
  {"id": "action", "category": "状态仓库", "how": "expand", "provides": {"带来的": "动作带来的"}, "slotKinds": {"store": "literal", "action": "literal", "body": "mouth"},
   "expand": "(做 (调 定动作 (槽 store) (槽 action) (λ块 ((动作带来的 任意)) (口 body))))",
   "look": {"name": "仓库的动作", "shape": "hat", "template": "仓库 {store} 的动作 {action} {body}", "colorKey": "variable",
            "hint": "给仓库定一件有名字的事；别处“让仓库做动作”就到这里来"}},
  {"id": "payload", "category": "状态仓库", "how": "expand", "needs": ["带来的"], "expand": "(隐含 带来的)",
   "look": {"name": "动作带来的", "shape": "value", "template": "动作带来的", "colorKey": "variable"}},
  {"id": "dispatch", "category": "状态仓库", "how": "expand",
   "expand": "(做 (调 做动作 (槽 store) (槽 action) (标 任意 (槽 value))))",
   "look": {"name": "让仓库做动作", "shape": "statement", "template": "让仓库 {store} 做动作 {action} 带上 {value}", "colorKey": "variable",
            "hint": "没有这个动作会出错"}},
  {"id": "persist", "category": "状态仓库", "how": "expand",
   "expand": "(做 (调 记住仓库 (槽 store) (槽 key)))",
   "look": {"name": "仓库关掉再开还在", "shape": "statement", "template": "仓库 {store} 关掉再开还在（存在本地的 {key} 下）", "colorKey": "variable",
            "hint": "放在“当页面放上以后”里、“新建仓库”后面"}}
]}
''';

const Map<String, String> kLcStoreLibFiles = {kLibManifestFile: kLcStoreManifest, 'modules/store.lc': kLcStoreModuleLc, 'blocks.json': kLcStoreBlocks};
