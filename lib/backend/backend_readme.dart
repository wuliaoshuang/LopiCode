/// 生成的 README 后面接的两节：在 LopiCode 里怎么启动、每个接口用 curl 怎么试。
///
/// 这两节是照着积木文档现算的，所以重新生成以后还在（不会被冲掉）。例子里的字段名、参数名只取
/// “字母数字下划线”的那些——别的名字不放进命令里，免得拼出一条有问题的命令。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/lowcode/logic_model.dart';

final RegExp _plainName = RegExp(r'^[A-Za-z0-9_]{1,32}$');

const Set<String> _boolish = {'done', 'completed', 'finished', 'ok', 'enabled', 'active', 'checked', 'open', 'visible'};
const Set<String> _numberish = {'count', 'age', 'price', 'amount', 'n', 'num', 'number', 'score', 'qty', 'quantity', 'total', 'size', 'level'};

/// 例子里某个字段放什么值（JSON 写法）：看名字猜是不是 / 数字，其余给一段文字。
String _sampleJson(String field) {
  final key = field.toLowerCase();
  if (_boolish.contains(key)) return 'true';
  if (_numberish.contains(key)) return '1';
  return '"示例"';
}

void _walkValue(Object? value, void Function(Map<Object?, Object?> expr) visit, [int depth = 0]) {
  if (depth > 40) return;
  if (value is Map) {
    if (value['e'] is String) visit(value);
    for (final v in value.values) {
      _walkValue(v, visit, depth + 1);
    }
  } else if (value is List) {
    for (final v in value) {
      _walkValue(v, visit, depth + 1);
    }
  }
}

void _walkBlocks(List<LcBlock> list, void Function(Map<Object?, Object?> expr) visit, [int depth = 0]) {
  if (depth > LcBlock.maxDepth + 2) return;
  for (final b in list) {
    _walkValue(b.args, visit);
    _walkBlocks(b.body, visit, depth + 1);
    _walkBlocks(b.orElse, visit, depth + 1);
  }
}

/// 一个接口用到的 请求内容字段 / 网址参数（只留名字规矩的，按出现顺序），以及有没有用到“整个请求内容”。
({List<String> fields, List<String> queries, bool wholeBody}) beRouteInputs(BeRoute route) {
  final fields = <String>[];
  final queries = <String>[];
  var whole = false;
  _walkBlocks(route.body, (e) {
    final name = e['name'];
    switch (e['e']) {
      case 'bodyField':
        if (name is String && _plainName.hasMatch(name) && !fields.contains(name)) fields.add(name);
      case 'query':
        if (name is String && _plainName.hasMatch(name) && !queries.contains(name)) queries.add(name);
      case 'body':
        whole = true;
    }
  });
  return (fields: fields, queries: queries, wholeBody: whole);
}

/// 试这个接口的一条 curl 命令；路径格式不对的返回 null。
String? beCurlExample(BeRoute route, int port) {
  final segs = parseBePath(route.path);
  if (segs == null) return null;
  final path = '/${[for (final s in segs) s.isParam ? '1' : s.text].join('/')}';
  final inputs = beRouteInputs(route);
  final query = inputs.queries.isEmpty ? '' : '?${[for (final q in inputs.queries) '$q=Lopi'].join('&')}';
  final out = StringBuffer('curl');
  if (route.method != 'GET') out.write(' -X ${route.method}');
  out.write(' "http://localhost:$port$path$query"');
  if (route.method != 'GET' && route.method != 'DELETE' && (inputs.fields.isNotEmpty || inputs.wholeBody)) {
    final body = '{${[for (final f in inputs.fields) '"$f":${_sampleJson(f)}'].join(',')}}';
    out.write(" -H \"Content-Type: application/json\" -d '$body'");
  }
  return out.toString();
}

/// 接在生成器的 README 后面的内容。`dir`＝后端在工作区里的子目录（空＝根目录）。
String beReadmeExtras(BeDocument doc, BackendTarget target, {String dir = ''}) {
  final out = StringBuffer();
  final start = target.startCommandFor(doc.port).join(' ');
  out.writeln();
  out.writeln('## 在 LopiCode 里启动');
  out.writeln();
  out.writeln('1. 点底部导航的“终端”（第一次用要先在侧边栏“运行环境”里装好 Ubuntu 环境和这种语言的工具）。');
  var step = 2;
  if (dir.isNotEmpty) out.writeln('${step++}. 进到后端的目录：`cd $dir`');
  for (final c in target.buildCommands) {
    out.writeln('${step++}. 先编译：`${c.join(' ')}`');
  }
  out.writeln('${step++}. 启动：`$start`');
  out.writeln('${step++}. 看到“后端已启动”那一行就好了。想停下来按 Ctrl+C。');
  out.writeln();
  out.writeln('手机上的 `localhost` 指的是手机自己：在这台手机上启动的服务，只有这台手机上的浏览器、预览和终端能用 `localhost` 访问到。');
  out.writeln();
  out.writeln('## 用 curl 试一试');
  out.writeln();
  final lines = [for (final r in doc.routes) ?beCurlExample(r, doc.port)];
  if (lines.isEmpty) {
    out.writeln('（还没有接口）');
  } else {
    out.writeln('服务启动以后，另开一个终端，一条一条试（例子里的值随便改）：');
    out.writeln();
    out.writeln('```');
    lines.forEach(out.writeln);
    out.writeln('```');
  }
  return out.toString();
}
