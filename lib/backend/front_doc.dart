/// 新的页面逻辑＝一份“前端这一边”的积木文档（积木第 5 版·前端 1·下半）。
///
/// 页面逻辑里要用函数、类、模块、错误、“要等的事”、库，这些后端积木页的文档（[BeDocument]）里都已经有了；所以新的页面逻辑不另造一套，
/// 就是一份标了“前端”的 [BeDocument]，原样存在页面逻辑的 `front` 里（`LcLogic.front`）：
///
/// - 事件帽子＝内置“页面”库的帽子积木（当控件被点击……），放在文档的 `hats` 里；
/// - 页面的状态还是页面逻辑的 `variables`（数据绑定照旧用它）；
/// - 页面逻辑的 `handlers` 这时只放“空壳”：每个要接的事件一条、里面没有积木——导出器照旧拿它给控件接线，
///   处理函数里只有一句“转给页面宿主”（见 lib/lowcode/logic_core_js.dart）。
///
/// 这里是读、写回、和“这份逻辑碰了页面上的哪些东西”。不依赖界面。
library;

import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_blocks.dart' show libOpOf;
import 'package:lopicode/lowcode/lib_page.dart';
import 'package:lopicode/lowcode/logic_expr.dart' show kMaxExprDepth;
import 'package:lopicode/lowcode/logic_model.dart';

/// 一份空白的新页面逻辑（严格规矩）。
BeDocument lcFrontNew() => BeDocument(name: '页面逻辑', rules: kLangRulesForNewDocs, front: true);

final Expando<BeDocument> _parsed = Expando('lcFront');

/// 这一页的新逻辑；不是新逻辑（旧页面）＝null。读不懂的当空白的新逻辑。项目里的库（`logic.loaded`）顺手挂上。
/// 交回的文档别直接改（同一份 `front` 再读还是它）；要改先 `clone()`，改完用 [lcFrontStore] 写回。
BeDocument? lcFrontOf(LcLogic logic) {
  final raw = logic.front;
  if (raw == null) return null;
  var doc = _parsed[raw];
  if (doc == null) {
    doc = BeDocument.fromJson(raw).doc;
    if (!doc.front || !langRulesStrict(doc.rules)) {
      doc = BeDocument.fromJson({...doc.toJson(), 'side': 'frontend', kLangRulesField: doc.rules < kLangRulesStrict ? kLangRulesStrict : doc.rules}).doc;
    }
    _parsed[raw] = doc;
  }
  doc.loaded = logic.loaded;
  return doc;
}

/// 把改好的新逻辑写回页面逻辑：`front`、用上的库（不算自带的“页面”库）、给导出器接线用的空壳。
void lcFrontStore(LcLogic logic, BeDocument doc) {
  logic.front = doc.toJson();
  logic.uses
    ..clear()
    ..addAll([
      for (final u in doc.uses)
        if (u.id != kLcPageLibId) {'id': u.id},
    ]);
  logic.handlers
    ..clear()
    ..addAll(lcFrontShells(doc));
}

/// 给导出器接线用的空壳：永远有一条“页面打开时”（开工以后发一次“放上了”）；每个接了点击 / 输入的控件各一条。
List<LcHandler> lcFrontShells(BeDocument doc) {
  final out = [LcHandler(id: 'fs0', event: 'load')];
  final seen = <String>{};
  void add(String event, Object? node) {
    if (node is! String || node.isEmpty || !seen.add('$node $event')) return;
    out.add(LcHandler(id: 'fs${out.length}', event: event, target: node));
  }

  for (final h in doc.hats) {
    final ref = libOpOf(h.op);
    if (ref == null || ref.lib != kLcPageLibId) continue;
    switch (ref.block) {
      case 'onClick':
        add('click', h.args['node']);
      case 'onInput':
        add('input', h.args['node']);
    }
  }
  return out;
}

/// 这份逻辑碰了页面上的哪些东西（导出器照这个准备读写表）。
class LcFrontTouch {
  final Set<String> states = {};
  final Set<(String, String)> props = {};
  final Set<String> pages = {};
}

LcFrontTouch lcFrontTouch(BeDocument doc) {
  final out = LcFrontTouch();
  void use(Object? op, Object? Function(String slot) arg) {
    final ref = libOpOf(op);
    if (ref == null || ref.lib != kLcPageLibId) return;
    final node = arg('node'), prop = arg('prop'), name = arg('name'), page = arg('page');
    if (node is String && prop is String && node.isNotEmpty && prop.isNotEmpty) out.props.add((node, prop));
    if (name is String && name.isNotEmpty && lcPagePickOf(ref.block, 'name') == 'state') out.states.add(name);
    if (page is String && page.isNotEmpty) out.pages.add(page);
  }

  void expr(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 4) return;
    if (v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        expr(x, depth + 1);
      }
    } else if (v is Map) {
      use(v['e'], (s) => v[s]);
      for (final x in v.values) {
        expr(x, depth + 1);
      }
    }
  }

  void walk(List<LcBlock> list, int depth) {
    if (depth > LcBlock.maxDepth + 2) return;
    for (final b in list) {
      use(b.op, (s) => b.args[s]);
      expr(b.args, 0);
      for (final a in b.arms) {
        expr(a.args, 0);
        walk(a.body, depth + 1);
      }
      walk(b.body, depth + 1);
      walk(b.orElse, depth + 1);
    }
  }

  for (final body in doc.libBodies) {
    walk(body, 0);
  }
  for (final h in doc.hats) {
    use(h.op, (s) => h.args[s]);
  }
  return out;
}

/// 积木页在页面逻辑里问“页面上有什么”的口子（控件、状态、属性、页面的下拉）。库文档没有页面，不给它。
abstract interface class BePageCx {
  /// 能挂事件 / 能读写属性的控件。
  List<BlockOption> get nodes;

  /// 页面（和项目）的状态。
  List<BlockOption> get states;

  /// 这个控件能读写的属性。
  List<BlockOption> props(String? node);

  /// 项目里的页面。
  List<BlockOption> get pages;

  /// 这个值在积木上显示成什么（控件的名字、页面的标题）；不认识＝null。
  String? label(String pick, String value);
}

/// 这顶帽子是不是“页面”库的；是的话交回库积木的 id。
String? lcFrontHatBlock(BeLibHat h) {
  final ref = libOpOf(h.op);
  return ref != null && ref.lib == kLcPageLibId ? ref.block : null;
}
