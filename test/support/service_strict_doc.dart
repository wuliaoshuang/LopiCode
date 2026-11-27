// 一致性样本里“只考服务这一层”的那些接口，做成一份严格规矩（版本 2）的后端文档：
// 接口、积木取自 conformanceDocument()：规矩版本标成 2、去掉考宽松规矩的那些接口，/echo 里一处“有几个”照严格写法重写（见下）。
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/rules.dart';

import 'backend_conformance.dart';

const Set<String> _kept = {'', 'todos', 'done', 'by-title', 'notes', 'echo', 'status', 'a', 'say', 'now'};

String _first(String target) {
  final segs = target.split('?').first.split('/').where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? '' : segs.first;
}

/// 样本里有的接口（去掉网址参数以后的路径开头）；`nope` 是故意没有的接口（考 404）。
bool serviceCaseCovered(BeCase c) {
  // “循环中途往集合里加东西”那几条要靠 /each 接口先加进去，这里没有那个接口。
  if (_first(c.target) == 'notes' && c.expect.contains('"from"')) return false;
  return _kept.contains(_first(c.target)) || _first(c.target) == 'nope';
}

List<BeCase> serviceCases() => [
  for (final c in conformanceCases)
    if (serviceCaseCovered(c)) c,
];

BeDocument serviceStrictDocument() {
  final doc = conformanceDocument();
  doc.routes.removeWhere((r) => !_kept.contains(_first(r.path)));
  doc.rules = kLangRulesStrict;
  // 严格规矩下“有几个”只收文字、列表、字典（给空会出错——这是升级的本意）。/echo 里那一处照严格写法重写：
  // 是这三种才数，不是就 0（和宽松规矩下的结果一样）。
  final echo = doc.routes.firstWhere((r) => r.path == '/echo');
  final fields = ((echo.body.single.args['value'] as Map)['fields'] as List).cast<Map<String, dynamic>>();
  final len = fields.firstWhere((f) => f['key'] == 'nameLen');
  final name = (len['value'] as Map)['x'];
  Map<String, dynamic> isA(String type) => {'e': 'isType', 'x': name, 'type': type};
  len['value'] = {
    'e': 'cond',
    'cond': {
      'e': 'logic',
      'op': 'or',
      'l': isA('text'),
      'r': {'e': 'logic', 'op': 'or', 'l': isA('list'), 'r': isA('dict')},
    },
    'then': {'e': 'len', 'x': name},
    'orElse': {'e': 'num', 'v': 0},
  };
  return doc;
}
