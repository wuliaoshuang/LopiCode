// “积木第 4 版·第 1 阶段”新积木的一致性样本：一份后端积木文档（就是 backend.lc.json 里存的那种结构，不是直接写语法树），
// 每个接口走一类新积木；后面是一串请求和写死的预期响应。test/backend_lang_blocks_test.dart 用它生成四种语言的后端真跑。
//
// 写法：`blk(op, 参数, …)` 是一块积木的 JSON，`ex(种类, 参数)` 是一个值的 JSON；文档整个先编成 JSON 文字再用 `BeDocument.parse` 读回来，
// 所以“存盘 → 读回 → 翻译 → 生成”整条路都走到。
import 'dart:convert';

import 'package:lopicode/backend/backend_model.dart';

typedef J = Map<String, dynamic>;

/// 一块积木。[arms]＝中间那些段（否则如果 / 是…时），每段是 `arm(参数, 里面的积木)`。
J blk(String op, [J args = const {}, List<J> body = const [], List<J> orElse = const [], List<J> arms = const [], bool noElse = false]) => {
  'op': op,
  if (args.isNotEmpty) 'args': args,
  if (body.isNotEmpty) 'body': body,
  if (arms.isNotEmpty) 'arms': arms,
  if (orElse.isNotEmpty) 'else': orElse,
  if (noElse) 'noElse': true,
};
J arm(J args, List<J> body) => {'args': args, 'body': body};

/// 一个值。
J ex(String kind, [J args = const {}]) => {'e': kind, ...args};
J tx(String v) => ex('text', {'v': v});
J nm(num v) => ex('num', {'v': v});
J yes() => ex('bool', {'v': true});
J no() => ex('bool', {'v': false});
J vr(String name) => ex('var', {'name': name});
J q(String name) => ex('query', {'name': name});
J qn(String name) => ex('convert', {'x': q(name), 'fn': 'toNumber'});
J op2(String op, J l, J r) => ex('bin', {'op': op, 'l': l, 'r': r});
J cat(List<J> items) => ex('join', {'items': items});
J ls(List<J> items) => ex('listLit', {'items': items});
J dc(Map<String, J> fields) => ex('obj', {
  'fields': [
    for (final e in fields.entries) ex('pair', {'key': e.key, 'value': e.value}),
  ],
});
J fam(String kind, String fn, J args) => ex(kind, {...args, 'fn': fn});

// —— 常用的积木 ——
J let(String name, J value) => blk('let', {'name': name, 'value': value});
J konst(String name, J value) => blk('const', {'name': name, 'value': value});
J setv(String name, J value) => blk('setVar', {'name': name, 'value': value});
J push(String list, J value) => blk('listPush', {'xs': vr(list), 'v': value});
J json(J value, [int status = 200]) => blk('respondJson', {'status': nm(status), 'value': value});
J text(J value, [int status = 200]) => blk('respondText', {'status': nm(status), 'value': value});
J iff(J cond, List<J> then, {List<J> orElse = const [], List<J> arms = const [], bool noElse = false}) => blk('if', {'cond': cond}, then, orElse, arms, noElse);
J route(String id, String method, String path, List<J> body) => {'id': id, 'method': method, 'path': path, 'body': body};

/// 一条请求和它的预期。
class LangBlocksCase {
  const LangBlocksCase(this.target, this.expect, {this.method = 'GET', this.status = 200, this.type = 'application/json', this.body});
  final String method;
  final String target;
  final int status;
  final String type;
  final String expect;
  final String? body;

  @override
  String toString() => '$method $target';
}

/// 把 JSON 结构的文档读成模型（走真的读盘路径）。
BeDocument parseLangBlocksDocument(J json) {
  final parsed = BeDocument.parse(jsonEncode(json));
  if (parsed.note != null) throw StateError('样本文档里有读不懂的内容：${parsed.note}');
  return parsed.doc;
}

J langBlocksDocumentJson(List<J> routes) => {
  'version': 2,
  'kind': 'backend',
  'name': '第 4 版新积木',
  'port': 8125,
  'language': 'node',
  'variables': [
    {'name': 'total', 'type': 'number', 'initial': 0},
    {'name': 'item', 'type': 'text', 'initial': ''},
    {'name': 'saved', 'type': 'text', 'initial': ''},
  ],
  'collections': [
    {'name': 'notes'},
  ],
  'routes': routes,
};
