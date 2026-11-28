/// 自带的前端库“动画”（积木第 5 版·前端 2·第二批）：在一段时间里把一个数字状态一点点变到一个数、缓动方式、停。
///
/// 能用样式里的过渡就用过渡；要一帧一帧自己算才用这个。内容是语言核心写的模块：每一帧（“让界面先更新一下”那个原生绑定）
/// 看过了多久、照缓动方式算出这一刻的数、写进状态；到点了写成正好的那个数。碰的是 `timer.frame`、`time.now` 和状态的三个接口。
/// 一个状态同一时间只有一段动画：新的一来，旧的那段就不走了（旧的“变完以后”不会来）。
library;

import 'package:lopicode/lang/lib_model.dart';

const String kLcAnimLibId = 'lopi/anim';

const String kLcAnimManifest = r'''
{
  "kind": "lopicode-lib",
  "format": 1,
  "id": "lopi/anim",
  "name": "动画",
  "version": "1.0.0",
  "summary": "在一段时间里把一个数字状态一点点变到一个数：缓动方式、变完以后做、停",
  "rules": 2,
  "for": "frontend",
  "native": {"allowed": false},
  "modules": [{"file": "modules/anim.lc", "name": "动画"}],
  "blocks": ["blocks.json"]
}
''';

const String kLcAnimModuleLc = r'''
; 自带库“动画”的模块（严格规矩的语言核心写的）。
(模块 动画
  (宿主 timer.frame ((做法 (要等函数 (小数) 空))) -> 整数)
  (宿主 time.now () -> 整数)
  (宿主 page.state.new ((名 文字) (初值 任意)) -> 任意)
  (宿主 page.state.read ((格子 任意)) -> 任意)
  (宿主 page.state.write ((格子 任意) (值 任意)) -> 空)

  (记录 一段动画 (起 小数) (止 小数) (开始 整数) (多久 小数) (缓 文字) (代 整数) (完了 (要等函数 () 空)))
  ; 状态名 → 正在走的那一段
  (变量 动着的 (字典 一段动画) (典))
  (变量 下一代 整数 1)

  ; 缓动：走到 0～1 的哪里 → 该变了多少（也是 0～1）。不认识的方式当匀速。
  (公开 (函数 缓动值 ((缓 文字) (走到 小数)) -> 小数
    (设 比 走到)
    (如果 (< 比 0) (那么 (改 比 0.0)))
    (如果 (> 比 1) (那么 (改 比 1.0)))
    (设 剩 (- 1 比))
    (如果 (== 缓 "先慢后快") (那么 (返回 (* 比 比))))
    (如果 (== 缓 "先快后慢") (那么 (返回 (- 1 (* 剩 剩)))))
    (如果 (== 缓 "两头慢")
      (那么 (如果 (< 比 0.5) (那么 (返回 (* 2 比 比))))
            (返回 (- 1 (* 2 剩 剩)))))
    (返回 比)))
  (公开 (函数 中间值 ((起 小数) (止 小数) (走到 小数)) -> 小数
    (返回 (+ 起 (* (- 止 起) 走到)))))

  (函数 状态的数 ((格子 任意)) -> 小数
    (设 值 (宿 page.state.read 格子))
    (如果 (是类 值 "number") (那么 (返回 (转 小数 值))))
    (返回 0.0))
  ; 等下一帧：这一段还在、还是这一代，就照过了多久算出这一刻的数；到点了写成正好的那个数、叫“变完以后”。
  (函数 走一帧 ((名 文字) (这一代 整数))
    (做 (宿 timer.frame (λ块 ((帧时刻 小数))
      (设 段 (取 动着的 名))
      (如果 (非空 段)
        (那么 (如果 (== (. 段 代) 这一代)
                (那么 (设 格子 (宿 page.state.new 名 (标 任意 空)))
                      (设 过了 (- (宿 time.now) (. 段 开始)))
                      (如果 (>= 过了 (. 段 多久))
                        (那么 (做 (宿 page.state.write 格子 (. 段 止)))
                              (删键 动着的 名)
                              (做 (调用 (. 段 完了))))
                        (否则 (做 (宿 page.state.write 格子
                                     (调 中间值 (. 段 起) (. 段 止) (调 缓动值 (. 段 缓) (/ 过了 (. 段 多久))))))
                              (做 (调 走一帧 名 这一代))))))))))))

  (公开 (函数 变到 ((名 文字) (目标 小数) (毫秒 小数) (缓 文字) (完了 (要等函数 () 空)))
    (设 格子 (宿 page.state.new 名 (标 任意 空)))
    (如果 (有键 动着的 名) (那么 (删键 动着的 名)))
    (设 这一代 下一代)
    (改 下一代 (+ 下一代 1))
    (如果 (<= 毫秒 0)
      (那么 (做 (宿 page.state.write 格子 目标))
            (做 (调用 完了))
            (返回)))
    (存 动着的 名 (新记 一段动画 (起 (调 状态的数 格子)) (止 目标) (开始 (宿 time.now)) (多久 毫秒) (缓 缓) (代 这一代) (完了 完了)))
    (做 (调 走一帧 名 这一代))))
  ; 停在现在这个数上；“变完以后”不会来。
  (公开 (函数 停下 ((名 文字))
    (如果 (有键 动着的 名) (那么 (删键 动着的 名)))))
  (公开 (函数 都停下 ()
    (设 空的 (字典 一段动画) (典))
    (改 动着的 空的)))
  (公开 (函数 在动吗 ((名 文字)) -> 是否
    (返回 (有键 动着的 名)))))
''';

const String _ease = '{"name": "ease", "kind": "choice", "options": ["匀速", "先慢后快", "先快后慢", "两头慢"], "defaultValue": "匀速"}';

const String kLcAnimBlocks =
    '''
{"blocks": [
  {"id": "tween", "category": "动画", "how": "expand",
   "expand": "(做 (调 变到 (槽 state) (槽 to) (槽 ms) (槽 ease) (λ块 ())))",
   "look": {"name": "把状态变到", "shape": "statement", "template": "在 {ms} 毫秒里把状态 {state} 变到 {to}（{ease}）", "colorKey": "control",
            "hint": "填页面里一个数字状态的名字。排在它后面的积木不等，马上接着做",
            "slots": [$_ease]}},
  {"id": "tweenThen", "category": "动画", "how": "expand", "slotKinds": {"body": "mouth"},
   "expand": "(做 (调 变到 (槽 state) (槽 to) (槽 ms) (槽 ease) (λ块 () (口 body))))",
   "look": {"name": "把状态变到，变完以后做", "shape": "statement", "template": "在 {ms} 毫秒里把状态 {state} 变到 {to}（{ease}），变完以后 {body}", "colorKey": "control",
            "hint": "中途被停下、被新的一段换掉的话，“变完以后”不会来",
            "slots": [$_ease]}},
  {"id": "stop", "category": "动画", "how": "call", "of": "停下", "args": ["state"],
   "look": {"name": "停下", "shape": "statement", "template": "停下状态 {state} 的动画", "colorKey": "control", "hint": "停在现在这个数上"}},
  {"id": "stopAll", "category": "动画", "how": "call", "of": "都停下", "args": [],
   "look": {"name": "都停下", "shape": "statement", "template": "停下所有动画", "colorKey": "control"}},
  {"id": "running", "category": "动画", "how": "call", "of": "在动吗", "args": ["state"],
   "look": {"name": "在动吗", "shape": "value", "template": "状态 {state} 在动吗", "colorKey": "control"}},
  {"id": "ease", "category": "动画", "how": "expand", "expand": "(调 缓动值 (槽 ease) (槽 t))",
   "look": {"name": "缓动的值", "shape": "value", "template": "{ease} 走到 {t} 的时候变了多少", "colorKey": "control",
            "hint": "走到填 0 到 1 的数（0＝刚开始，1＝到头）；结果也是 0 到 1",
            "slots": [$_ease]}},
  {"id": "mix", "category": "动画", "how": "call", "of": "中间值", "args": ["from", "to", "t"],
   "look": {"name": "中间的数", "shape": "value", "template": "从 {from} 到 {to} 走到 {t} 的地方是多少", "colorKey": "control"}}
]}
''';

const Map<String, String> kLcAnimLibFiles = {kLibManifestFile: kLcAnimManifest, 'modules/anim.lc': kLcAnimModuleLc, 'blocks.json': kLcAnimBlocks};
