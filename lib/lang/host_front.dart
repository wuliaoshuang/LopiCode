import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/types.dart';

/// 前端（浏览器）的宿主接口。设计见 docs/blocks-v5-parts/D-frontend-logic.md §2；落地时改了什么见同文件末尾“落地说明（第四轮·A2）”。
///
/// 三组：
/// - **甲类 9 个**（`page.state.*`、`page.ui.*`）：归框架管的界面。一个接口三份实现（纯网页 / Vue 3 / React），
///   生成的程序里写成 `lcHost.名字(…)`，三种产物各给一个 `lcHost`。
/// - **乙类 20 个**（定时、请求、存储、地址、对话框、窗口事件）：不归框架管的浏览器能力，一份实现，在浏览器小运行时里（rt2_browser.dart）。
/// - **旧规矩 6 个**（`compat.*`）：旧页面积木的“转数字 / 转文字 / 等于 / 运算 / 打印”原样留着，只给内置“页面”库的兼容积木用。
///
/// 值在两边怎么对：状态里放的是普通的 JSON 值（文字、数字、是否、数组、对象）；程序读到的是语言核心的“任意”
/// （数组＝列表、对象＝字典）。来回换算由宿主做（`lc.fromPlain` / `lc.toPlain`）。
const LType _dictAny = LType.dictOf(LType.any);
const LType _cb0 = LType.func([LType.nul], waits: true);
const LType _cancel = LType.func([LType.nul]);

const Map<String, LRtSig> kHostFront = {
  // —— 甲类：状态 ——
  // 新建一个会通知的格子。名字不空＝页面（或项目）里声明过的那个状态，已经有了就直接交回它；名字是空的＝库自己用的、没有名字的格子。
  'page.state.new': LRtSig('新建状态', [LType.text, LType.any], LType.any),
  'page.state.read': LRtSig('读状态', [LType.any], LType.any),
  // 立刻生效；和旧值一样就什么都不做。
  'page.state.write': LRtSig('写状态', [LType.any, LType.any], LType.nul),
  // 读的时候才算；算法里不许改状态、不许等。
  'page.state.derived': LRtSig('派生值', [
    LType.func([LType.any], waits: false),
  ], LType.any),
  // 取值结果变了才叫回调（新值, 旧值）；一轮里变多次只叫一次。交回“不看了”的函数。
  'page.state.watch': LRtSig('当…变了', [
    LType.func([LType.any], waits: false),
    LType.func([LType.any, LType.any, LType.nul], waits: true),
  ], _cancel),
  // —— 甲类：界面 ——
  'page.ui.read': LRtSig('读控件属性', [LType.text, LType.text], LType.any),
  'page.ui.write': LRtSig('改控件属性', [LType.text, LType.text, LType.any], LType.nul),
  // 回调拿到的是事件记录（字典：value / checked / key / x / y / target / preventDefault / stopPropagation）。选项：once。
  'page.ui.on': LRtSig('当控件事件', [
    LType.text,
    LType.text,
    LType.func([_dictAny, LType.nul], waits: true),
    _dictAny,
  ], _cancel),
  // 哪个：mounted（放上以后）/ unmount（拿走之前）/ error（没人接的错，回调拿到那句话）。
  'page.ui.life': LRtSig('页面的时刻', [
    LType.text,
    LType.func([LType.any, LType.nul], waits: true),
  ], LType.nul),

  // 去项目里的另一页，带上参数；这一页“这次带来的参数”。三种产物各有各的换页办法，所以也是甲类（前端 1·下半加的）。
  'page.nav.go': LRtSig('去页面', [LType.text, _dictAny], LType.nul),
  'page.nav.params': LRtSig('这次带来的参数', [], _dictAny),
  // 这一轮事件是从“重复”出来的第几份控件上来的：那一项、第几项（不在重复里＝空、-1）。
  'page.ui.item': LRtSig('这一项', [_dictAny], LType.any),
  'page.ui.index': LRtSig('第几项', [_dictAny], LType.number),

  // —— 乙类：定时 ——
  'timer.after': LRtSig('过后做', [LType.number, _cb0], LType.integer),
  'timer.every': LRtSig('每隔做', [LType.number, _cb0], LType.integer),
  'timer.cancel': LRtSig('取消定时', [LType.integer], LType.nul),
  'timer.frame': LRtSig('下一帧做', [
    LType.func([LType.number, LType.nul], waits: true),
  ], LType.integer),
  // —— 乙类：请求 —— 请求记录 {method, url, headers, body, timeoutMs, abort} → 回应记录 {status, ok, headers, body}。只有网络层失败才出错。
  'net.request': LRtSig('发请求', [_dictAny], _dictAny),
  'net.abortNew': LRtSig('新中止令牌', [], LType.any),
  'net.abort': LRtSig('中止请求', [LType.any], LType.nul),
  // —— 乙类：存储 —— 区：local（长期）/ session（本次）。
  'storage.read': LRtSig('读本地', [LType.text, LType.text], LType(LKind.text, nullable: true)),
  'storage.write': LRtSig('存本地', [LType.text, LType.text, LType.text], LType.nul),
  'storage.remove': LRtSig('删本地', [LType.text, LType.text], LType.nul),
  'storage.keys': LRtSig('本地的所有键', [LType.text], LType.listOf(LType.text)),
  // —— 乙类：地址 ——
  'loc.now': LRtSig('现在的地址', [], _dictAny),
  'loc.push': LRtSig('加一条历史', [LType.text, LType.any], LType.nul),
  'loc.replace': LRtSig('换掉这条历史', [LType.text, LType.any], LType.nul),
  'loc.go': LRtSig('走几步', [LType.integer], LType.nul),
  'loc.onPop': LRtSig('当前进后退', [
    LType.func([LType.any, LType.nul], waits: true),
  ], _cancel),
  'loc.assign': LRtSig('整页跳转', [LType.text], LType.nul),
  // —— 乙类：对话框 ——
  'page.alert': LRtSig('弹提示', [LType.text], LType.nul),
  'page.confirm': LRtSig('问一句', [LType.text], LType.boolean),
  // —— 乙类：窗口 —— 对象：window / document。选项：once、passive。
  'win.on': LRtSig('当窗口事件', [
    LType.text,
    LType.text,
    LType.func([_dictAny, LType.nul], waits: true),
    _dictAny,
  ], _cancel),

  // —— 旧规矩（只给“页面”库的兼容积木用）——
  'compat.num': LRtSig('转数字（旧）', [LType.any], LType.number),
  'compat.text': LRtSig('转文字（旧）', [LType.any], LType.text),
  'compat.truthy': LRtSig('算不算成立（旧）', [LType.any], LType.boolean),
  'compat.eq': LRtSig('等于（旧）', [LType.any, LType.any], LType.boolean),
  'compat.op': LRtSig('运算（旧）', [LType.text, LType.any, LType.any], LType.any),
  'compat.log': LRtSig('打印（旧）', [LType.any], LType.nul),
};

/// 哪几个是“要等”的。
const Set<String> kHostFrontWaits = {'net.request'};

/// 甲类（三份实现）的那 13 个（A2 的 9 个＋换页 2 个＋重复里的“这一项”2 个）。
const Set<String> kHostFrontPage = {
  'page.nav.go',
  'page.nav.params',
  'page.ui.item',
  'page.ui.index',
  'page.state.new',
  'page.state.read',
  'page.state.write',
  'page.state.derived',
  'page.state.watch',
  'page.ui.read',
  'page.ui.write',
  'page.ui.on',
  'page.ui.life',
};

/// 乙类（一份实现）的那 20 个。
const Set<String> kHostFrontBrowser = {
  'timer.after',
  'timer.every',
  'timer.cancel',
  'timer.frame',
  'net.request',
  'net.abortNew',
  'net.abort',
  'storage.read',
  'storage.write',
  'storage.remove',
  'storage.keys',
  'loc.now',
  'loc.push',
  'loc.replace',
  'loc.go',
  'loc.onPop',
  'loc.assign',
  'page.alert',
  'page.confirm',
  'win.on',
};

/// 只许应用自带的库声明的（旧规矩那 6 个）：用户的前端库写了就是问题。
const Set<String> kHostFrontBuiltinOnly = {'compat.num', 'compat.text', 'compat.truthy', 'compat.eq', 'compat.op', 'compat.log'};

/// 后端那张表里、浏览器里也有的几个（意思一样）：写一行、现在的毫秒数、等一会儿、随机字节。
const Set<String> kHostBothSides = {'sys.print', 'time.now', 'time.sleep', 'random.bytes'};

/// 在生成的代码里叫什么：甲类前面带 `@`（＝`lcHost.名字`），其余是浏览器小运行时里的函数（`lc.名字`）。
const Map<String, String> kHostFrontCode = {
  'page.state.new': '@stateNew',
  'page.state.read': '@stateRead',
  'page.state.write': '@stateWrite',
  'page.state.derived': '@stateDerived',
  'page.state.watch': '@stateWatch',
  'page.ui.read': '@uiRead',
  'page.ui.write': '@uiWrite',
  'page.ui.on': '@uiOn',
  'page.ui.life': '@uiLife',
  'page.nav.go': '@navGo',
  'page.nav.params': '@navParams',
  'page.ui.item': '@uiItem',
  'page.ui.index': '@uiIndex',
  'timer.after': 'timerAfter',
  'timer.every': 'timerEvery',
  'timer.cancel': 'timerCancel',
  'timer.frame': 'timerFrame',
  'net.request': 'netRequest',
  'net.abortNew': 'netAbortNew',
  'net.abort': 'netAbort',
  'storage.read': 'storageRead',
  'storage.write': 'storageWrite',
  'storage.remove': 'storageRemove',
  'storage.keys': 'storageKeys',
  'loc.now': 'locNow',
  'loc.push': 'locPush',
  'loc.replace': 'locReplace',
  'loc.go': 'locGo',
  'loc.onPop': 'locOnPop',
  'loc.assign': 'locAssign',
  'page.alert': 'pageAlert',
  'page.confirm': 'pageConfirm',
  'win.on': 'winOn',
  'compat.num': 'oldNum',
  'compat.text': 'oldText',
  'compat.truthy': 'oldTruthy',
  'compat.eq': 'oldEq',
  'compat.op': 'oldOp',
  'compat.log': 'oldLog',
};
