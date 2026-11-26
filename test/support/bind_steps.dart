/// 第 5 期样例（support/bind_sample.dart）在浏览器里要走的一串步骤：tool/verify/run_dom.mjs 照着做。
/// [kind]：html / vue / react（只有“换页”那两步不一样：纯网页是打开另一个文件，Vue / React 是点按钮改地址栏）。
List<Map<String, Object?>> bindSampleSteps(String kind) {
  final s = <Map<String, Object?>>[];
  void text(String sel, String v, [int? at]) => s.add({'op': 'text', 'sel': sel, 'is': v, 'at': ?at});
  void click(String sel) => s.add({'op': 'click', 'sel': sel});
  void check(String op, String sel, Object v, [String? name]) => s.add({'op': op, 'sel': sel, 'is': v, 'name': ?name});

  // 第一屏：都是初值
  text('.n-hello', '你好，小塔塔');
  text('.n-tipText', '已点 0 次');
  check('shown', '.n-echo', false);
  check('disabled', '.n-submit', true);
  check('hasClass', '.n-submit', false, 'ready');
  check('style', '.n-submit', '120px', 'width');
  check('count', '.n-enough', 0);
  check('count', '.n-rowItem', 2);
  text('.n-itemName', '1. 苹果 ¥3', 0);
  text('.n-itemName', '2. 香蕉 ¥2', 1);
  check('count', '.n-nameList li', 2);
  text('.n-total', '共 2 件');
  // 改状态 → 界面跟着变（文字、派生值、样式、存在条件）
  click('.n-add');
  text('.n-tipText', '已点 1 次');
  check('style', '.n-submit', '130px', 'width');
  click('.n-add');
  click('.n-add');
  text('.n-tipText', '已点 3 次');
  check('count', '.n-enough', 1);
  text('.n-enough', '点够三次了');
  // 输入框双向 + 显示条件
  s.add({'op': 'type', 'sel': '.n-kw', 'text': '苹果'});
  check('shown', '.n-echo', true);
  text('.n-echo', '在搜：苹果');
  check('value', '.n-kw', '苹果');
  s.add({'op': 'type', 'sel': '.n-kw', 'text': ''});
  check('shown', '.n-echo', false);
  // 勾选框双向 + 禁用 + 类名开关
  click('.n-agreeBox');
  check('checked', '.n-agreeBox', true);
  check('disabled', '.n-submit', false);
  check('hasClass', '.n-submit', true, 'ready');
  // 跨页：项目级状态在第二页改，回首页还在；第二页自己的 user 盖住项目级的
  text('.n-homeVisits', '来过 0 次');
  if (kind == 'html') {
    s.add({'op': 'page', 'html': 'page-cart.html'});
  } else {
    click('.n-toCart');
    check('hash', '', '#/cart');
  }
  text('.n-who', '本页的名字');
  text('.n-sum', '共 2 件');
  click('.n-bump');
  click('.n-bump');
  text('.n-cartVisits', '来过 2 次');
  if (kind == 'html') {
    s.add({'op': 'page', 'html': 'index.html'});
  } else {
    click('.n-back');
    check('hash', '', '#/home');
  }
  text('.n-homeVisits', '来过 2 次');
  text('.n-hello', '你好，小塔塔');
  return s;
}
