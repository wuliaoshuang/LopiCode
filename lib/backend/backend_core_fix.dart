/// 核心 2 的“一键修”落到积木文档上（积木第 5 版·核心 2·A3）。纯数据，不碰界面；调用方（宿主）负责放进撤销栈。
///
/// 第一轮剩下没法点的五种（补上漏掉的情况、加“其他情况”、补缺字段、去多余字段、换成“复制并改”）在这里接上；另外加了：
/// 把错误当文字用 →“读它的消息”，数值约束不对 →“变成数字”，以及 T11 / T17 / T18 / T21 / T27、M05 / M06 / M08 里有明确修法的那些。
/// 接不了的（要人起名字、要人做设计决定的）理由写在 docs/blocks-v5-parts/B-impl-notes.md“A3”一节。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 一条能点的修法：按钮上的字 + 怎么改文档（改了返回 true；东西已经不在了返回 false，什么都不动）。
class BeCoreFix {
  const BeCoreFix(this.label, this.apply);
  final String label;
  final bool Function(BeDocument doc) apply;
}

/// 文档里的一串积木：接口、“我的积木”、类的方法 / “创建时”、“程序开始时”。
LcBlockTree? beTreeById(BeDocument doc, String id) => doc.function(id) ?? doc.route(id) ?? doc.core.tree(id);

/// 一格的位置（和 backend_type_bridge.dart 的 `BeSlotRef` 一样的四样，这里不依赖它）。
typedef BeSpot = ({String treeId, LcBlockPath path, String? arg, List<Object> exprPath});

Object? _valueAt(LcBlock block, BeSpot at) {
  Object? v = block.argValue(at.arg!);
  for (final step in at.exprPath) {
    if (step is int) {
      if (v is! List || step < 0 || step >= v.length) return null;
      v = v[step];
    } else {
      if (v is! Map) return null;
      v = v[step];
    }
  }
  return v;
}

bool _setAt(LcBlock block, BeSpot at, Object? value) {
  if (at.exprPath.isEmpty) return block.setArgValue(at.arg!, value);
  Object? parent = block.argValue(at.arg!);
  for (final step in at.exprPath.sublist(0, at.exprPath.length - 1)) {
    parent = step is int ? (parent is List && step >= 0 && step < parent.length ? parent[step] : null) : (parent is Map ? parent[step] : null);
  }
  final last = at.exprPath.last;
  if (last is int && parent is List && last >= 0 && last < parent.length) {
    parent[last] = value;
    return true;
  }
  if (last is String && parent is Map) {
    parent[last] = value;
    return true;
  }
  return false;
}

LcBlock? _block(BeDocument doc, BeSpot at) => beTreeById(doc, at.treeId)?.blockAt(at.path);

/// 那一格里的值（一个值积木的 JSON）；不在了返回 null。
Map<String, dynamic>? _expr(BeDocument doc, BeSpot at) {
  final b = _block(doc, at);
  if (b == null || at.arg == null) return null;
  final v = _valueAt(b, at);
  return v is Map<String, dynamic> ? v : null;
}

/// 把那一格里的东西外面包一层。
BeCoreFix _wrap(String label, BeSpot at, Map<String, dynamic> Function(Object inner) wrap) => BeCoreFix(label, (doc) {
  final b = _block(doc, at);
  if (b == null || at.arg == null) return false;
  final inner = _valueAt(b, at);
  return inner != null && _setAt(b, at, wrap(inner));
});

String _bindFor(BeField f, int i, RegExp varPattern) => varPattern.hasMatch(f.name) ? f.name : 'v${i + 1}';

/// 类型检查器给的修法里，第一轮没法在积木上做的那五种。[block]＝要改的那块积木在哪；[slot]＝要改的那个值在哪（补字段、删字段用）。
BeCoreFix? beCoreFixOf(LFix fix, {BeSpot? block, BeSpot? slot}) {
  switch (fix.kind) {
    case LFixKind.addMatchCases:
      final cases = fix.params['cases'];
      if (block == null || cases is! List) return null;
      return BeCoreFix(fix.label, (doc) {
        final b = _block(doc, block);
        if (b == null || b.op != 'match') return false;
        for (final c in cases.whereType<String>()) {
          final fields = doc.core.types.expand((t) => t.cases).where((k) => k.name == c).firstOrNull?.fields ?? const <BeField>[];
          b.arms.add(
            LcArm(
              args: {
                'case': c,
                'binds': [for (final (i, f) in fields.indexed) _bindFor(f, i, beNamePattern)].join(', '),
              },
            ),
          );
        }
        return true;
      });
    case LFixKind.addMatchElse:
      if (block == null) return null;
      return BeCoreFix('加一个“其他情况”', (doc) {
        final b = _block(doc, block);
        if (b == null || b.op != 'match' || !b.noElse) return false;
        b.noElse = false;
        return true;
      });
    case LFixKind.addRecordFields:
      final names = fix.params['fields'];
      if (slot == null || names is! List) return null;
      return BeCoreFix(fix.label, (doc) {
        final e = _expr(doc, slot);
        final fields = e?['fields'];
        if (e == null || e['e'] != 'recNew' || fields is! List) return false;
        final def = doc.core.typeNamed(e['type']);
        for (final n in names.whereType<String>()) {
          final f = def?.fields.where((f) => f.name == n).firstOrNull;
          fields.add(bePair(n, f == null ? exText('') : beDefaultExprOf(f.type)));
        }
        return true;
      });
    case LFixKind.removeRecordField:
      final name = fix.params['field'];
      if (slot == null || name is! String) return null;
      return BeCoreFix(fix.label, (doc) {
        final fields = _expr(doc, slot)?['fields'];
        if (fields is! List) return false;
        final before = fields.length;
        fields.removeWhere((p) => p is Map && p['key'] == name);
        return fields.length != before;
      });
    case LFixKind.useRecordCopy:
      if (block == null) return null;
      return BeCoreFix(fix.label, (doc) {
        final tree = beTreeById(doc, block.treeId);
        final b = tree?.blockAt(block.path);
        final of = b?.args['of'];
        final value = b?.args['value'];
        // 只有“把 (某个变量) 的 字段 改成 …”能原地换：换成“把那个变量设为 复制它并改”。别的写法（改的是算出来的东西）说不准要放回哪儿，不猜。
        if (tree == null || b == null || b.op != 'setField' || of is! Map || of['e'] != 'var' || of['name'] is! String) return false;
        final home = tree.listAt(block.path.sublist(0, block.path.length - 1), inElse: block.path.last.inElse, arm: block.path.last.arm);
        final i = block.path.last.index;
        if (home == null || i < 0 || i >= home.length) return false;
        home[i] = LcBlock(
          op: 'setVar',
          args: {
            'name': of['name'],
            'value': {
              'e': 'recCopy',
              'of': of,
              'fields': [bePair('${b.args['name']}', value is Map ? Map<String, dynamic>.from(value) : exText(''))],
            },
          },
        );
        return true;
      });
    case LFixKind.wrapToText || LFixKind.wrapToInt || LFixKind.wrapParseInt || LFixKind.wrapOrElse || LFixKind.wrapMust || LFixKind.compareNotZero || LFixKind.dropAwait || LFixKind.wrapSpawn:
      return null; // 这几种在 backend_type_fix.dart
  }
}

final RegExp _quoted = RegExp('「(.+?)」');
List<String> _names(String message) => [for (final m in _quoted.allMatches(message)) m.group(1)!];

String? _keyOf(BeDocument doc, String name) => doc.core.typeNamed(name)?.id ?? doc.functions.where((f) => f.ident == name).firstOrNull?.id ?? doc.core.global(name)?.key;

/// 检查器没给修法、但积木上有明确修法的问题。[treeId]＝问题在哪一串（类一级的问题是类型的 id）；[slot]＝问题在哪一格（有的话）；
/// [gotError]＝那一格里的东西是不是一个错误对象。
List<BeCoreFix> beCoreExtraFixes(BeDocument doc, LTypeIssue issue, {required String treeId, BeSpot? slot, BeSpot? block, bool gotError = false}) {
  final core = doc.core;
  final msg = issue.message;
  final names = _names(msg);
  BeTypeDef? owner(BeDocument d) => d.core.type(treeId) ?? d.core.ownerOf(treeId);
  switch (issue.code) {
    case 'T01' when gotError && slot != null && msg.contains('要文字'):
      return [
        _wrap('读它的消息', slot, (inner) => {'e': 'getField', 'of': inner, 'name': kErrMessageField}),
      ];
    case 'T05' when slot != null && msg.contains('要的是数字'):
      // 问题记在那块“绝对值 / 较大的…”上：要包的是它里面的东西（已经是直接填的数的不包）。
      return [
        BeCoreFix('变成数字', (d) {
          final e = _expr(d, slot);
          if (e == null) return false;
          var done = false;
          for (final k in const ['x', 'a', 'b']) {
            final v = e[k];
            if (v is! Map || v['e'] == 'num' || (v['e'] == 'convert' && v['fn'] == 'toNumber')) continue;
            e[k] = {'e': 'convert', 'x': v, 'fn': 'toNumber'};
            done = true;
          }
          return done;
        }),
      ];
    case 'T17' when owner(doc)?.parent != null:
      return [
        BeCoreFix('给「${owner(doc)!.parent}」勾上“可以被继承”', (d) {
          final up = d.core.typeNamed(owner(d)?.parent);
          if (up == null || up.isOpen) return false;
          return up.isOpen = true;
        }),
      ];
    case 'T18' || 'T11' when names.length >= 2 && owner(doc) != null:
      final method = msg.contains('但是没有') ? names.last : names[1]; // “「类」说自己是「接口」，但是没有「方法」这个方法”：方法名在最后
      BeMethod? above(BeDocument d) {
        final t = owner(d);
        if (t == null) return null;
        final from = issue.code == 'T18'
            ? d.core.parentsOf(t)
            : [
                for (final c in [t, ...d.core.parentsOf(t)]) ...c.interfaces.map(d.core.typeNamed).nonNulls,
              ];
        return from.expand((c) => c.methods).where((m) => m.name == method).firstOrNull;
      }

      if (above(doc) == null) return const [];
      final has = owner(doc)!.methods.any((m) => m.name == method);
      return [
        BeCoreFix(has ? '照抄上面的签名' : '加上这个方法', (d) {
          final t = owner(d), up = above(d);
          if (t == null || up == null) return false;
          var m = t.methods.where((m) => m.name == method).firstOrNull;
          if (m == null) t.methods.add(m = BeMethod(id: d.core.freeId('m', {for (final r in d.routes) r.id, for (final f in d.functions) f.id}), name: method));
          m.params
            ..clear()
            ..addAll([for (final p in up.params) p.clone()]);
          m.returns = up.returns;
          return true;
        }),
      ];
    case 'T21' when block != null && names.isNotEmpty:
      return [
        BeCoreFix('删掉这一节', (d) {
          final b = _block(d, block);
          if (b == null || b.op != 'try') return false;
          final k = b.arms.lastIndexWhere((a) => a.args['kind'] == names.first);
          if (k < 0) return false;
          b.arms.removeAt(k);
          return true;
        }),
      ];
    case 'T27':
      final t = core.ownerOf(treeId) ?? core.type(treeId);
      final ctor = t?.ctor;
      if (t == null || ctor == null) return const [];
      final at = ctor.body.indexWhere((b) => b.op == 'superInit');
      if (at > 0) {
        return [
          BeCoreFix('挪到第一句', (d) {
            final c = (d.core.ownerOf(treeId) ?? d.core.type(treeId))?.ctor;
            final i = c?.body.indexWhere((b) => b.op == 'superInit') ?? -1;
            if (c == null || i <= 0) return false;
            c.body.insert(0, c.body.removeAt(i));
            return true;
          }),
        ];
      }
      if (at == 0) return const [];
      return [
        BeCoreFix('在第一句放上“调父类的创建时”', (d) {
          final c = d.core.ownerOf(treeId) ?? d.core.type(treeId);
          return c != null && beEnsureSuperInit(d.core, c);
        }),
      ];
    case 'M05' when names.length >= 3:
      return [
        BeCoreFix('在「${names[2]}」里勾上用到了「${names[1]}」', (d) {
          final m = d.core.module(names[2]);
          if (m == null || m.uses.contains(names[1]) || d.core.module(names[1]) == null) return false;
          m.uses.add(names[1]);
          return true;
        }),
      ];
    case 'M06' when names.length >= 2:
      final also = names.length >= 4 ? (names[2], names[3]) : null;
      return [
        BeCoreFix(also == null ? '把「${names[1]}」设成公开' : '把「${names[1]}」设成公开，并勾上用到了「${names[0]}」', (d) {
          final key = _keyOf(d, names[1]);
          if (key == null) return false;
          var changed = d.core.publics.add(key);
          final m = also == null ? null : d.core.module(also.$1);
          if (m != null && !m.uses.contains(also!.$2) && d.core.module(also.$2) != null) {
            m.uses.add(also.$2);
            changed = true;
          }
          return changed;
        }),
      ];
    case 'M08' when names.length >= 2 && names[0] != names[1]:
      return [
        BeCoreFix('把「${names[1]}」挪到「${names[0]}」前面', (d) {
          final gs = d.core.globals;
          final from = gs.indexWhere((g) => g.name == names[1]), to = gs.indexWhere((g) => g.name == names[0]);
          if (from < 0 || to < 0 || from < to) return false;
          gs.insert(to, gs.removeAt(from));
          return true;
        }),
      ];
  }
  return const [];
}

/// 父类的“创建时”要参数、子类有“创建时”但第一句不是“调父类的创建时”：放一块进去（参数先空着等人填）。放了返回 true。
bool beEnsureSuperInit(BeCore core, BeTypeDef t) {
  final ctor = t.ctor;
  final up = core.typeNamed(t.parent);
  if (ctor == null || (up == null && !langIsBuiltinError(t.parent)) || ctor.body.any((b) => b.op == 'superInit')) return false;
  final want = up == null ? const <String>[kErrMessageField] : beCtorParams(core, up);
  if (want.isEmpty) return false;
  ctor.body.insert(
    0,
    LcBlock(
      op: 'superInit',
      args: {
        'args': [for (final _ in want) exText('')],
      },
    ),
  );
  return true;
}

/// “看是哪种情况”看的是可空的值 / “任意”的值时，语言核心不查“列全了没有”（它们翻成了一段段“如果”），这里查：
/// 可空的要“空”“有值”两段都有；“任意”的要有“其他情况”。返回 (说明, 修法)；没问题返回 null。
(String, List<BeCoreFix>)? beMatchGap(LcBlock b, BeSpot at) {
  if (b.op != 'match' || !b.noElse) return null;
  final mode = beMatchMode(b);
  if (mode == 'case') return null;
  final addElse = beCoreFixOf(const LFix(LFixKind.addMatchElse, ''), block: at)!;
  if (mode == 'any') return ('“看是哪种情况”看的是“任意”的值，列不全：要有一个“其他情况”', [addElse]);
  final have = {for (final a in b.arms) a.args['case']};
  final miss = [
    for (final c in const [kBeCaseNull, kBeCaseSome])
      if (!have.contains(c)) c,
  ];
  if (miss.isEmpty) return null;
  return (
    '“看是哪种情况”还少了：${[for (final c in miss) kBeCaseLabels[c]].join('、')}（或者加一个“其他情况”）',
    [
      BeCoreFix('补上少的情况', (doc) {
        final blk = _block(doc, at);
        if (blk == null || blk.op != 'match') return false;
        for (final c in miss) {
          blk.arms.add(LcArm(args: {'case': c, 'binds': c == kBeCaseSome ? 'v' : ''}));
        }
        return true;
      }),
      addElse,
    ],
  );
}
