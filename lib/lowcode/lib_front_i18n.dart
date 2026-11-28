/// 自带的前端库“国际化”（积木第 5 版·前端 2·第二批）：语言表、文案（能带占位）、换语言、备用语言、当语言变了。
///
/// 文案不写死在控件上：放进语言表，要用的时候按名字取；换了语言，“当语言变了”和“这句文案跟着放进状态”会跟着来。
/// 内容是语言核心写的模块，只碰状态的四个接口（现在的语言放在一个会通知的格子里）。
/// 数字、日期、货币照各地习惯的写法要浏览器的 `Intl`，那得新加原生绑定，这一版没做；只有一块纯计算的“写成带千位分隔的样子”。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcI18nLibId = 'lopi/i18n';

const String kLcI18nManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/i18n",
  "name": "国际化",
  "version": "1.0.0",
  "summary": "一份页面好几种语言：语言表、按名字取文案（能带占位）、换语言、备用语言、当语言变了",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/i18n.lc", "name": "国际化"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcI18nModuleLc = r'''
; 自带库“国际化”的模块（严格规矩的语言核心写的）。
(模块 国际化
  (宿主 page.state.new ((名 文字) (初值 任意)) -> 任意)
  (宿主 page.state.read ((格子 任意)) -> 任意)
  (宿主 page.state.write ((格子 任意) (值 任意)) -> 空)
  (宿主 page.state.watch ((取值 (不等函数 () 任意)) (做法 (要等函数 (任意 任意) 空))) -> (函数 () 空))

  ; 语言 → （文案的名字 → 那句话）
  (变量 表们 (字典 (字典 文字)) (典))
  (变量 备用 文字 "")
  ; 只有一个格子（“语言”）：里面放现在的语言，改了它在看的人会收到。
  (变量 格子们 (字典 任意) (典))

  (函数 语言格子 () -> 任意
    (如果 (非 (有键 格子们 "语言"))
      (那么 (存 格子们 "语言" (宿 page.state.new "" (标 任意 "")))))
    (返回 (取 格子们 "语言")))
  (公开 (函数 现在的语言 () -> 文字
    (设 值 (宿 page.state.read (调 语言格子)))
    (如果 (是类 值 "text") (那么 (返回 (转 文字 值))))
    (返回 "")))
  ; 加一张语言表：同一种语言加好几次，后加的盖住先加的同名文案。头一张表的语言就是开始时的语言。
  (公开 (函数 加语言表 ((语言 文字) (表 (字典 文字)))
    (设 新的 (字典 文字) (典))
    (设 旧的 (取 表们 语言))
    (如果 (非空 旧的) (那么 (每对 旧名 旧话 旧的 (存 新的 旧名 旧话))))
    (每对 名 话 表 (存 新的 名 话))
    (存 表们 语言 新的)
    (如果 (== (调 现在的语言) "") (那么 (做 (宿 page.state.write (调 语言格子) 语言))))))
  (公开 (函数 换语言 ((语言 文字))
    (如果 (非 (有键 表们 语言)) (那么 (抛出 (连 "还没有「" 语言 "」的语言表"))))
    (做 (宿 page.state.write (调 语言格子) 语言))))
  (公开 (函数 定备用 ((语言 文字))
    (改 备用 语言)))
  (函数 找文案 ((语言 文字) (名 文字)) -> (可空 文字)
    (设 表 (取 表们 语言))
    (如果 (非空 表) (那么 (返回 (取 表 名))))
    (返回 空))
  ; 现在的语言里没有，就用备用语言的；都没有，就是名字自己。
  (公开 (函数 文案 ((名 文字)) -> 文字
    (设 话 (调 找文案 (调 现在的语言) 名))
    (如果 (非空 话) (那么 (返回 话)))
    (设 备用的话 (调 找文案 备用 名))
    (如果 (非空 备用的话) (那么 (返回 备用的话)))
    (返回 名)))
  ; 文案里写 {名字} 的地方换成带上的那一项。
  (公开 (函数 文案带 ((名 文字) (带上 (字典 任意))) -> 文字
    (返回 (库 template (调 文案 名) 带上))))
  (公开 (函数 有文案 ((名 文字)) -> 是否
    (返回 (非空 (调 找文案 (调 现在的语言) 名)))))
  (公开 (函数 所有语言 () -> (列表 文字)
    (返回 (键们 表们))))
  ; 当语言变了：交回“不看了”。
  (公开 (函数 看语言 ((做法 (要等函数 (文字) 空))) -> (函数 () 空)
    (设 格子 (调 语言格子))
    (返回 (宿 page.state.watch
            (λ () (宿 page.state.read 格子))
            (λ块 ((新值 任意) (旧值 任意))
              (如果 (是类 新值 "text") (那么 (做 (调用 做法 (转 文字 新值))))))))))
  ; 这句文案跟着放进一个状态：控件的文字绑这个状态，换了语言它自己跟着变。
  (公开 (函数 文案放进状态 ((名 文字) (状态名 文字))
    (设 目标 (宿 page.state.new 状态名 (标 任意 "")))
    (做 (宿 page.state.write 目标 (调 文案 名)))
    (设 格子 (调 语言格子))
    (做 (宿 page.state.watch
          (λ () (宿 page.state.read 格子))
          (λ块 ((新值 任意) (旧值 任意)) (做 (宿 page.state.write 目标 (调 文案 名))))))))
  ; 1234567.5 留 2 位 → "1,234,567.50"（纯计算，哪种语言都是这个样子；各地不同的写法这一版没有）。
  (公开 (函数 写成千位 ((值 小数) (几位小数 整数)) -> 文字
    (设 负的 (< 值 0))
    (设 正的 值)
    (如果 负的 (那么 (改 正的 (- 0 值))))
    (设 倍 1)
    (重复 几位小数 (改 倍 (* 倍 10)))
    (设 整个 (库 round (* 正的 倍)))
    (设 剩 (文 (整除 整个 倍)))
    (设 出 "")
    (当 (> (文长 剩) 3)
      (改 出 (连 "," (截 剩 (- (文长 剩) 3) (文长 剩)) 出))
      (改 剩 (截 剩 0 (- (文长 剩) 3))))
    (改 出 (连 剩 出))
    (如果 (> 几位小数 0)
      (那么 (设 零头 (文 (余 整个 倍)))
            (当 (< (文长 零头) 几位小数) (改 零头 (连 "0" 零头)))
            (改 出 (连 出 "." 零头))))
    (如果 (且 负的 (> 整个 0)) (那么 (改 出 (连 "-" 出))))
    (返回 出))))
''';

const String kLcI18nBlocks = r'''
{"blocks": [
  {"id": "table", "category": "国际化", "how": "call", "of": "加语言表", "args": ["lang", "table"],
   "look": {"name": "语言表", "shape": "statement", "template": "语言 {lang} 的文案是 {table}", "colorKey": "data",
            "hint": "文案填一个字典：名字 : 那句话。放在“当页面放上以后”里；头一张表的语言就是开始时的语言"}},
  {"id": "use", "category": "国际化", "how": "call", "of": "换语言", "args": ["lang"],
   "look": {"name": "换语言", "shape": "statement", "template": "换成语言 {lang}", "colorKey": "data", "hint": "还没有这种语言的表会出错"}},
  {"id": "fallback", "category": "国际化", "how": "call", "of": "定备用", "args": ["lang"],
   "look": {"name": "备用语言", "shape": "statement", "template": "现在的语言里没有的文案，用语言 {lang} 的", "colorKey": "data"}},
  {"id": "current", "category": "国际化", "how": "call", "of": "现在的语言", "args": [],
   "look": {"name": "现在的语言", "shape": "value", "template": "现在的语言", "colorKey": "data"}},
  {"id": "langs", "category": "国际化", "how": "call", "of": "所有语言", "args": [],
   "look": {"name": "所有语言", "shape": "value", "template": "所有语言", "colorKey": "data"}},
  {"id": "t", "category": "国际化", "how": "call", "of": "文案", "args": ["key"],
   "look": {"name": "文案", "shape": "value", "template": "文案 {key}", "colorKey": "data",
            "hint": "现在的语言里叫这个名字的那句话；没有就用备用语言的，都没有就是名字自己"}},
  {"id": "tWith", "category": "国际化", "how": "call", "of": "文案带", "args": ["key", "data"],
   "look": {"name": "文案（带上）", "shape": "value", "template": "文案 {key}，带上 {data}", "colorKey": "data",
            "hint": "文案里写 {名字} 的地方，换成带上的字典里那一项"}},
  {"id": "has", "category": "国际化", "how": "call", "of": "有文案", "args": ["key"],
   "look": {"name": "有这句文案吗", "shape": "value", "template": "现在的语言有文案 {key} 吗", "colorKey": "data"}},
  {"id": "onChange", "category": "国际化", "how": "expand", "provides": {"语言": "新的语言"}, "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 看语言 (λ块 ((新的语言 文字)) (口 body))))",
   "look": {"name": "当语言变了", "shape": "hat", "template": "当语言变了 {body}", "colorKey": "event"}},
  {"id": "newLang", "category": "国际化", "how": "expand", "needs": ["语言"], "expand": "(隐含 语言)",
   "look": {"name": "新的语言", "shape": "value", "template": "新的语言", "colorKey": "event"}},
  {"id": "bind", "category": "国际化", "how": "call", "of": "文案放进状态", "args": ["key", "state"],
   "look": {"name": "文案跟着放进状态", "shape": "statement", "template": "文案 {key}，跟着放进状态 {state}", "colorKey": "data",
            "hint": "填页面里一个文字状态的名字，放在语言表后面。控件的文字绑这个状态，换了语言它自己跟着变"}},
  {"id": "group", "category": "国际化", "how": "call", "of": "写成千位", "args": ["value", "digits"],
   "look": {"name": "带千位分隔的写法", "shape": "value", "template": "把 {value} 写成带千位分隔的样子，留 {digits} 位小数", "colorKey": "data",
            "hint": "1234567.5 留 2 位是 1,234,567.50"}}
]}
''';

const Map<String, String> kLcI18nLibFiles = {kLibManifestFile: kLcI18nManifest, 'modules/i18n.lc': kLcI18nModuleLc, 'blocks.json': kLcI18nBlocks};
