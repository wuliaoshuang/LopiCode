// 第四轮 B2 三种形状的组件（support/comp_samples.dart）在浏览器里要走的步骤：tool/verify/run_dom.mjs 照着做。
import 'package:lopicode/lowcode/model.dart';

typedef CompSteps = List<Map<String, Object?>>;

class _S {
  final CompSteps s = [];
  void text(String sel, String v, [int? at]) => s.add({'op': 'text', 'sel': sel, 'is': v, 'at': ?at});
  void click(String sel) => s.add({'op': 'click', 'sel': sel});
  void type(String sel, String v) => s.add({'op': 'type', 'sel': sel, 'text': v});
  void check(String op, String sel, Object v, {String? name, int? at}) => s.add({'op': op, 'sel': sel, 'is': v, 'name': ?name, 'at': ?at});
}

/// 商品卡片：插槽、属性绑定到页面状态、每个实例一份自己的状态、事件传到页面。
CompSteps productCardSteps() {
  final s = _S();
  s.text('.n-cartText', '购物车 0 件');
  s.text('.n-p1__name', '苹果');
  s.text('.n-p1__money', '¥3');
  s.text('.n-p2__name', '香蕉');
  s.text('.n-p2__money', '¥2');
  s.text('.n-p1img', '苹果的图');
  s.text('.n-p1tag', '新');
  s.text('.n-p2__picText', '（放图片）');
  // 事件：点卡片里的按钮，页面上接的积木真跑（两个实例各接各的）
  s.click('.n-p1__buy');
  s.text('.n-cartText', '购物车 1 件');
  s.click('.n-p2__buy');
  s.text('.n-cartText', '购物车 11 件');
  // 属性绑到页面状态：状态变了，卡片里的字跟着变；写死的那个不动
  s.click('.n-rename');
  s.text('.n-p1__name', '红苹果');
  s.text('.n-p2__name', '香蕉');
  // 组件自己的状态：每个实例一份
  s.check('shown', '.n-p1__favTip', false);
  s.click('.n-p1__fav');
  s.check('shown', '.n-p1__favTip', true);
  s.check('shown', '.n-p2__favTip', false);
  return s.s;
}

/// 登录表单：输入框双向到页面状态（经过组件属性）、存在条件、禁用、事件。
CompSteps loginFormSteps() {
  final s = _S();
  s.text('.n-login__head', '请登录');
  s.text('.n-loginFoot', '忘记密码？');
  s.check('disabled', '.n-login__go', true);
  s.type('.n-login__userIn', '霜霜');
  s.text('.n-echo', '用户=霜霜 密码= 登录了 0 次');
  s.check('disabled', '.n-login__go', false);
  s.check('count', '.n-login__tip', 0);
  s.click('.n-login__show');
  s.text('.n-login__tip', '要登录的是：霜霜');
  s.type('.n-login__passIn', 'abc');
  s.click('.n-login__go');
  s.text('.n-echo', '用户=霜霜 密码=abc 登录了 1 次');
  s.click('.n-login__go');
  s.text('.n-echo', '用户=霜霜 密码=abc 登录了 2 次');
  return s.s;
}

/// 标签筛选条：重复（列表从页面绑进来）、类名开关、事件。
CompSteps tagBarSteps() {
  final s = _S();
  s.check('count', '.n-tags__chip', 3);
  s.text('.n-tags__chip', '水果', 0);
  s.text('.n-tags__chip', '零食', 2);
  s.text('.n-tags__count', '共 3 个');
  s.check('hasClass', '.n-tags__chip', false, name: 'on', at: 0);
  s.check('hasClass', '.n-tags__chip', true, name: 'on', at: 1);
  s.text('.n-curText', '现在选的：蔬菜');
  s.click('.n-tags__clear');
  s.text('.n-curText', '现在选的：');
  s.check('hasClass', '.n-tags__chip', false, name: 'on', at: 1);
  return s.s;
}

/// 第四轮 B4 起，Vue 3 / React 的导出里用了新东西的组件是单独的组件文件，不再摊开进页面：组件里面的控件不再叫
/// `<实例>__<控件>`，而是“实例最外层元素里面的 `<定义>-<控件>`”。步骤（点什么、该是什么）一条不变，只换找元素的写法。
/// [defOf]：实例 id → 它用的定义 id。
CompSteps compFileSteps(CompSteps steps, Map<String, String> defOf) => [
  for (final s in steps)
    if (s['sel'] is! String)
      s // 不找元素的步骤（看地址栏）原样留着
    else
      {...s, 'sel': (s['sel']! as String).replaceAllMapped(RegExp(r'\.n-([A-Za-z0-9]+)__([A-Za-z0-9]+)'), (m) => defOf[m[1]] == null ? m[0]! : '.n-${m[1]} .n-${defOf[m[1]]}-${m[2]}')},
];

/// 样例页（support/comp_samples.dart 的 compUserPageJson）里各实例用的定义。
const Map<String, String> kCompUserDefs = {'p1': 'c1', 'p2': 'c1', 'login': 'c2', 'tags': 'c3'};

/// 当前这一页上各实例用的定义（定义的 id 导入库以后会变，从文档里现查）。
Map<String, String> compDefsOf(LcDocument doc) {
  final out = <String, String>{};
  void walk(LcNode n) {
    if (n.type == 'component' && n.props['ref'] is String) out[n.id] = n.props['ref'] as String;
    n.children.forEach(walk);
  }

  walk(doc.root);
  return out;
}
