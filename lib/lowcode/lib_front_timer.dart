/// 自带的前端库“定时”（积木第 5 版·前端 2·第一批）：过一会儿做、每隔一会儿做、取消、下一帧做、防抖、节流。
///
/// 和“页面”库是同一种格式、走同一个读入器；内容是语言核心写的模块，底下只包了定时那一组原生绑定
/// （`timer.after / every / cancel / frame`）和“现在的毫秒数”。防抖、节流是在这上面用语言核心搭的（一张按名字记号的表）。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcTimerLibId = 'lopi/timer';

const String kLcTimerManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/timer",
  "name": "定时",
  "version": "1.0.0",
  "summary": "过一会儿做、每隔一会儿做、取消、下一帧做、防抖、节流",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/timer.lc", "name": "定时"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcTimerModuleLc = r'''
; 自带库“定时”的模块（严格规矩的语言核心写的）。
(模块 定时
  (宿主 timer.after ((毫秒 小数) (做法 (要等函数 () 空))) -> 整数)
  (宿主 timer.every ((毫秒 小数) (做法 (要等函数 () 空))) -> 整数)
  (宿主 timer.cancel ((号 整数)) -> 空)
  (宿主 timer.frame ((做法 (要等函数 (小数) 空))) -> 整数)
  (宿主 time.now () -> 整数)

  ; 防抖：名字 → 还没到点的那个定时的号。节流：名字 → 上一次做的时刻。
  (变量 防抖表 (字典 整数) (典))
  (变量 节流表 (字典 整数) (典))

  (公开 (函数 定时过后做 ((毫秒 小数) (做法 (要等函数 () 空))) -> 整数
    (返回 (宿 timer.after 毫秒 做法))))
  (公开 (函数 定时每隔做 ((毫秒 小数) (做法 (要等函数 () 空))) -> 整数
    (返回 (宿 timer.every 毫秒 做法))))
  ; 号可以是直接拿到的整数，也可以是存进状态又读出来的（那时候不知道是哪一类）；不是数字就什么都不做。
  (公开 (函数 取消定时 ((号 任意))
    (如果 (是类 号 "number") (那么 (做 (宿 timer.cancel (取整 (转 小数 号))))))))
  ; 让界面先更新一下，再做口里的事。
  (公开 (函数 下一帧做 ((做法 (要等函数 () 空)))
    (做 (宿 timer.frame (λ块 ((_ 小数)) (做 (调 做法)))))))
  ; 防抖：同一个名字又来了，前一个还没到点的就不做了，重新等。
  (公开 (函数 防抖做 ((名 文字) (毫秒 小数) (做法 (要等函数 () 空)))
    (设 旧号 (取 防抖表 名))
    (如果 (非空 旧号) (那么 (做 (宿 timer.cancel 旧号))))
    (存 防抖表 名 (宿 timer.after 毫秒 (λ块 ()
      (删键 防抖表 名)
      (做 (调 做法)))))))
  ; 节流：同一个名字在这段时间里只做头一次。
  (公开 (函数 节流做 ((名 文字) (毫秒 小数) (做法 (要等函数 () 空)))
    (设 现在 (宿 time.now))
    (设 上次 (取 节流表 名))
    (如果 (非空 上次) (那么 (如果 (< (- 现在 上次) 毫秒) (那么 (返回)))))
    (存 节流表 名 现在)
    (做 (调 做法)))))
''';

const String kLcTimerBlocks = r'''
{"blocks": [
  {"id": "after", "category": "定时", "how": "expand", "slotKinds": {"into": "assign", "body": "mouth"},
   "expand": "(放进 into (调 定时过后做 (槽 ms) (λ块 () (口 body))))",
   "look": {"name": "过一会儿做", "shape": "statement", "template": "过 {ms} 毫秒以后做，定时的号放进 {into} {body}", "colorKey": "control",
            "hint": "只管它里面的积木：排在它后面的积木不等，马上接着做。号留着，可以拿去“取消定时”"}},
  {"id": "every", "category": "定时", "how": "expand", "slotKinds": {"into": "assign", "body": "mouth"},
   "expand": "(放进 into (调 定时每隔做 (槽 ms) (λ块 () (口 body))))",
   "look": {"name": "每隔一会儿做", "shape": "statement", "template": "每隔 {ms} 毫秒做一次，定时的号放进 {into} {body}", "colorKey": "control",
            "hint": "一直做下去，直到“取消定时”"}},
  {"id": "cancel", "category": "定时", "how": "expand", "expand": "(做 (调 取消定时 (标 任意 (槽 id))))",
   "look": {"name": "取消定时", "shape": "statement", "template": "取消定时 {id}", "colorKey": "control",
            "hint": "号是“过一会儿做”“每隔一会儿做”放进变量的那个"}},
  {"id": "frame", "category": "定时", "how": "expand", "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 下一帧做 (λ块 () (口 body))))",
   "look": {"name": "让界面先更新一下再做", "shape": "statement", "template": "让界面先更新一下，再 {body}", "colorKey": "control"}},
  {"id": "debounce", "category": "定时", "how": "expand", "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 防抖做 (槽 key) (槽 ms) (λ块 () (口 body))))",
   "look": {"name": "防抖", "shape": "statement", "template": "防抖 {key}：停手 {ms} 毫秒以后才 {body}", "colorKey": "control",
            "hint": "同一个名字接连来好几次，只做最后一次（比如打字停下来才搜）"}},
  {"id": "throttle", "category": "定时", "how": "expand", "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 节流做 (槽 key) (槽 ms) (λ块 () (口 body))))",
   "look": {"name": "节流", "shape": "statement", "template": "节流 {key}：{ms} 毫秒里最多 {body}", "colorKey": "control",
            "hint": "同一个名字接连来好几次，这段时间里只做头一次（比如连点按钮）"}}
]}
''';

const Map<String, String> kLcTimerLibFiles = {kLibManifestFile: kLcTimerManifest, 'modules/timer.lc': kLcTimerModuleLc, 'blocks.json': kLcTimerBlocks};
