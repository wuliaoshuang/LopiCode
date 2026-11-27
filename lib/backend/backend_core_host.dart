/// 后端积木宿主里“核心 2”的那一半（积木第 5 版·核心 2·A3；规矩版本 2 的文档才有东西，版本 1 的文档这里每个入口都是“没有”）：
/// - 积木盒多两页：“错误”“类型”；
/// - 下拉的选项跟着文档走（错误种类、类型、情况、字段、方法），换了类型 / 情况 / 种类，后面的字段、参数格子跟着重排；
/// - 画布能切到某个类里面（看到的是这个类的“创建时”和方法），再切回来；
/// - 改类型、模块、模块顶上的变量（都走 `edit`，一次一条撤销记录）。
///
/// 做成 mixin 混进 `BeBlockHost`。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/backend/backend_blocks_wait.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_core_edit.dart';
import 'package:lopicode/backend/backend_core_gen.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/lib_native.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 帽子模板的 id。
const String kBeMainTemplate = 'core:main';
const String kBeMethodTemplate = 'core:method';
const String kBeCtorTemplate = 'core:ctor';

const BlockHat _mainHat = BlockHat([BlockHatPart.text('程序开始时')], colorKey: BlockColorKey.event);
const BlockHat _ctorHat = BlockHat([BlockHatPart.text('创建时')], colorKey: BlockColorKey.classes);

BlockHat _methodHat(String name, {bool isStatic = false}) =>
    BlockHat([BlockHatPart.text(isStatic ? '类本身的方法' : '方法'), BlockHatPart.slot('name', name, kind: LcArgKind.literalText)], colorKey: BlockColorKey.classes);

mixin BeCoreHost on BlockHost {
  BeDocument get doc;
  void Function(String message)? get onNotice;

  BeCore get core => doc.core;
  bool get _strict => langRulesStrict(doc.rules);

  // —— 当前画布 ——

  String? _canvas;

  /// 现在画布上是哪个类里面（类型的 id）；null＝主画布。那个类不在了（被删、撤销掉了）自动回主画布。
  BeTypeDef? get canvasType {
    final t = _canvas == null ? null : core.type(_canvas!);
    return t != null && t.kind == BeTypeKind.klass ? t : null;
  }

  /// 进某个类里面 / 回主画布（null）。不是改动，不进撤销。
  void openCanvas(String? typeId) {
    if (_canvas == typeId) return;
    _canvas = typeId;
    canvasChanged();
  }

  /// 画布换了：宿主丢掉积木盒的缓存并通知界面。
  void canvasChanged();

  /// 画布上的串：在类里面＝它的“创建时”和方法；主画布＝[base]（接口、“我的积木”）加“程序开始时”。
  List<LcBlockTree> coreScripts(List<LcBlockTree> base) {
    final t = canvasType;
    if (t != null) return t.trees;
    return [...base, ?core.main];
  }

  BlockHat? coreHatOf(LcBlockTree tree) {
    if (tree is! BeMethod) return null;
    if (tree.id == kBeMainId) return _mainHat;
    if (tree.name == kBeCtorName && core.ownerOf(tree.id)?.ctor == tree) return _ctorHat;
    return _methodHat(tree.name, isStatic: tree.isStatic);
  }

  /// 给问题列表用的“在哪一串”。
  String? coreScopeOf(LcBlockTree tree) {
    return tree is BeMethod ? core.labelOf(tree) : null;
  }

  bool? coreSetHatSlot(LcBlockTree tree, String slotId, String value) {
    if (tree is! BeMethod) return null;
    if (slotId != 'name') return false;
    final bad = beRenameMethod(doc, tree.id, value);
    if (bad != null) onNotice?.call('$bad，没有改。');
    return bad == null;
  }

  LcBlockTree? coreAddScript(String templateId, {double? x, double? y}) {
    final t = canvasType;
    switch (templateId) {
      case kBeMainTemplate:
        if (!_strict || t != null) return null;
        return core.main ??= BeMethod(id: kBeMainId, name: kBeMainId, x: x, y: y);
      case kBeMethodTemplate:
        return t == null ? null : beAddMethod(doc, t.id, x: x, y: y);
      case kBeCtorTemplate:
        return t == null ? null : (t.ctor ?? beAddCtor(doc, t.id, x: x, y: y));
    }
    return null;
  }

  bool isCoreTemplate(String id) => id == kBeMainTemplate || id == kBeMethodTemplate || id == kBeCtorTemplate;

  // —— 积木盒 ——

  /// 严格规矩的文档多出来的两页（接在别的页后面）。在类里面时“事件”页换成这个类能放的帽子。
  List<BlockCategory> coreCategories(List<BlockCategory> base) {
    if (!_strict) return base;
    final t = canvasType;
    return [
      for (final c in base)
        if (c.id != 'event')
          c
        else if (t != null)
          BlockCategory(
            id: c.id,
            label: c.label,
            colorKey: BlockColorKey.classes,
            hats: [
              if (t.ctor == null) const BlockHatTemplate(kBeCtorTemplate, _ctorHat, hint: '新建这个类的对象时先做的事；参数在“类型与类”里这个类的卡片上加'),
              BlockHatTemplate(kBeMethodTemplate, _methodHat('方法${t.methods.length + 1}'), hint: '这个类的对象会做的一件事'),
            ],
          )
        else
          BlockCategory(
            id: c.id,
            label: c.label,
            colorKey: c.colorKey,
            hats: [
              ...c.hats,
              if (core.main == null) const BlockHatTemplate(kBeMainTemplate, _mainHat, hint: '不靠接口、一启动就从这里往下做（只用语言核心的积木时，“看代码”能看到五种语言的代码）'),
            ],
          ),
      const BlockCategory(id: kBeCatError, label: kBeCatError, colorKey: BlockColorKey.error, blocks: ['try', 'throw'], exprs: ['errNew']),
      BlockCategory(
        id: kBeCatType,
        label: kBeCatType,
        colorKey: BlockColorKey.classes,
        groups: [
          const BlockGroup('看是哪种', blocks: ['match'], exprs: ['isA']),
          const BlockGroup('当成和标上', exprs: [kBeCast, kBeAscribe]),
          const BlockGroup('记录', exprs: ['recNew', 'getField', 'recCopy']),
          const BlockGroup('枚举和变体', exprs: ['enumVal', 'varNew']),
          BlockGroup('对象', blocks: const ['setField', 'callMethodStmt'], exprs: ['classNew', 'callMethod', if (t != null) 'this', 'classRef']),
          if (t != null && (t.parent != null)) const BlockGroup('父类', blocks: ['superInit', 'superCallStmt'], exprs: ['superCall']),
          // 原生绑定积木：只在库的画布上、开关开着、这一边有宿主接口可调时才有（见 backend_blocks_typeops.dart）。
          if (userLibHostEntry && doc.library != null && doc.library!.side != LibSide.both) const BlockGroup('宿主接口', blocks: [kBeHostCallStmt], exprs: [kBeHostCall]),
        ],
      ),
      // “要等的事”排在最后（核心 3）：前面几页的位置不动。
      const BlockCategory(
        id: kBeCatWait,
        label: kBeCatWait,
        colorKey: BlockColorKey.async,
        groups: [
          BlockGroup('同时做', blocks: ['spawn', 'sleep'], exprs: ['spawnOf']),
          BlockGroup('等结果', exprs: ['await', 'awaitMax', 'awaitAll', 'awaitAny']),
          BlockGroup('取消', blocks: ['cancel'], exprs: ['cancelled']),
          BlockGroup('排队', blocks: ['critical']),
        ],
      ),
    ];
  }

  LcBlockSpec? coreBlockSpec(String op) => _strict ? beCoreBlockSpecs[op] : null;
  LcExprSpec? coreExprSpec(String kind) => _strict ? beCoreExprSpecs[kind] : null;
  String? coreBlockSentence(String op) => beCoreBlockSentences[op];
  String? coreExprSentence(String kind) => beCoreExprSentences[kind];
  String? coreArmSentence(String op) => beCoreArmSentences[op];

  String? coreColorKey(String id) => switch (id) {
    'try' || 'throw' || 'errNew' => BlockColorKey.error,
    _ when beWaitBlockSpecs.containsKey(id) || beWaitExprSpecs.containsKey(id) => BlockColorKey.async,
    _ => beIsCoreOp(id) || beIsCoreExpr(id) ? BlockColorKey.classes : null,
  };

  LcBlock? coreNewBlock(String op) => _strict ? newBeCoreBlock(op, core) : null;
  Map<String, dynamic>? coreNewExpr(String kind) => _strict ? newBeCoreExpr(kind, core) : null;

  /// 字段那一串里加一项＝加一个“名字 : 值”（名字先挑一个还没写的字段）。
  Map<String, dynamic>? coreNewListItem(Map<String, dynamic> expr, LcArgSpec arg) {
    if (arg.name != 'fields' || !beIsCoreExpr(exprKind(expr))) return null;
    final have = {
      for (final p in (expr['fields'] is List ? expr['fields'] as List : const <dynamic>[]))
        if (p is Map) p['key'],
    };
    final all = switch (exprKind(expr)) {
      'recNew' => core.typeNamed(expr['type'])?.fields ?? const <BeField>[],
      'errNew' => beErrorFields(core, expr['kind'] is String ? expr['kind'] as String : null),
      _ => [
        for (final t in core.types)
          if (t.kind == BeTypeKind.record) ...t.fields,
      ],
    };
    final next = all.where((f) => !have.contains(f.name)).firstOrNull;
    return bePair(next?.name ?? '字段', next == null ? exText('') : beDefaultExprOf(next.type));
  }

  // —— 下拉 ——

  List<String> _memberNames({required bool methods}) {
    final out = <String>{};
    if (!methods) out.addAll([kErrMessageField, kErrKindField]);
    for (final t in core.types) {
      if (methods) {
        out.addAll([for (final m in t.methods) m.name]);
      } else {
        out.addAll([for (final f in t.fields) f.name]);
      }
    }
    return out.toList();
  }

  /// 核心 2 积木上的下拉有哪些选项；不归这里管的返回 null。
  List<BlockOption>? coreOptions(LcArgSpec arg, {LcBlock? block, Map<String, dynamic>? expr}) {
    if (arg.kind != LcArgKind.choice || !_strict) return null;
    final kind = expr == null ? null : exprKind(expr);
    List<BlockOption> named(Iterable<BeTypeDef> types) => [for (final t in types) BlockOption(t.name, t.name, hint: t.kind.label)];
    List<BlockOption> keep(List<BlockOption> list, Object? current, String gone) => [
      ...list,
      if (current is String && current.isNotEmpty && !list.any((o) => o.value == current)) BlockOption(current, current, hint: gone),
    ];
    if (expr == null && block != null && block.op == 'try' && arg.name == 'kind') {
      return [const BlockOption(kBeCatchAny, '任何错误', hint: '什么错都接；放在最后一节'), for (final k in core.errorKinds) BlockOption(k, k)];
    }
    if (expr == null && block != null && block.op == 'match' && arg.name == 'case') {
      return [
        for (final t in core.types)
          if (t.kind == BeTypeKind.enumeration || t.kind == BeTypeKind.variant)
            for (final c in t.cases) BlockOption(c.name, c.name, hint: '${t.kind.label}「${t.name}」的'),
        const BlockOption(kBeCaseNull, '空', hint: '看的是可能是空的值'),
        const BlockOption(kBeCaseSome, '有值', hint: '看的是可能是空的值；带出来的是不空的那个值'),
        for (final k in kBeCaseIsTypes) BlockOption('$kBeCaseIsPrefix$k', kBeCaseLabels['$kBeCaseIsPrefix$k']!, hint: '看的是“任意”的值'),
      ];
    }
    if (expr == null && block != null && block.op == kBeHostCallStmt && arg.name == 'name') {
      return keep(beHostOptions(doc.library?.side ?? LibSide.both), block.args['name'], '这一边没有这个接口');
    }
    if (kind == kBeHostCall && arg.name == 'name') return keep(beHostOptions(doc.library?.side ?? LibSide.both), expr!['name'], '这一边没有这个接口');
    if ((kind == kBeCast || kind == kBeAscribe) && arg.name == 'to') {
      final list = beTypeOptions(core);
      final now = expr!['to'];
      return [...list, if (now is String && now.isNotEmpty && !list.any((o) => o.value == now)) BlockOption(now, beTypeLabel(now) ?? now, hint: beTypeLabel(now) == null ? '读不出来的类型' : '')];
    }
    if (expr == null && block != null && beIsCoreOp(block.op) && arg.name == 'name') {
      return keep([for (final n in _memberNames(methods: block.op != 'setField')) BlockOption(n, n)], block.args['name'], '现在没有叫这个的');
    }
    if (kind == null || !beIsCoreExpr(kind)) return null;
    switch (arg.name) {
      case 'kind':
        return keep([for (final k in core.errorKinds) BlockOption(k, k)], expr!['kind'], '这个种类已经不在了');
      case 'type':
        final types = switch (kind) {
          'recNew' => named(core.types.where((t) => t.kind == BeTypeKind.record)),
          'enumVal' => named(core.types.where((t) => t.kind == BeTypeKind.enumeration)),
          'varNew' => named(core.types.where((t) => t.kind == BeTypeKind.variant)),
          'classNew' || 'classRef' => named(core.types.where((t) => t.kind == BeTypeKind.klass)),
          _ => [for (final k in kErrBuiltinNames) BlockOption(k, k, hint: '内置的错误种类'), ...named(core.types.where((t) => t.isClassLike || t.kind == BeTypeKind.interface))],
        };
        return keep(types, expr!['type'], '这个类型已经不在了');
      case 'case':
        return keep([for (final c in core.typeNamed(expr!['type'])?.cases ?? const <BeCase>[]) BlockOption(c.name, c.name)], expr['case'], '这种情况已经不在了');
      case 'name':
        return keep([for (final n in _memberNames(methods: kind != 'getField')) BlockOption(n, n)], expr!['name'], '现在没有叫这个的');
    }
    return null;
  }

  String? coreOptionLabel(LcArgSpec arg, String value) => value == kBeCatchAny ? '任何错误' : (kBeCaseLabels[value] ?? (arg.name == 'to' ? beTypeLabel(value) : null));

  /// 刚改过的这一格里，选的类型 / 情况 / 种类变了：后面的字段、参数格子按新的重排（原来填的、名字还对得上的留着）。
  void coreArgChanged(LcBlock block, String arg, List<Object> exprPath) {
    if (!_strict) return;
    void relayout(Object? value, int depth) {
      if (depth > kMaxExprDepth * 2 + 4 || value is List<LcBlock>) return;
      if (value is List) {
        for (final v in value) {
          relayout(v, depth + 1);
        }
        return;
      }
      if (value is! Map) return;
      for (final v in value.values) {
        relayout(v, depth + 1);
      }
      List<dynamic> pairs(List<BeField> want) {
        final old = value['fields'];
        Object? was(String name) => old is List ? old.whereType<Map<dynamic, dynamic>>().where((p) => p['key'] == name).firstOrNull : null;
        return [for (final f in want) was(f.name) ?? bePair(f.name, beDefaultExprOf(f.type))];
      }

      List<dynamic> resized(int n, Map<String, dynamic> Function(int i) fresh) {
        final old = value['args'];
        return [for (var i = 0; i < n; i++) old is List && i < old.length ? old[i] : fresh(i)];
      }

      switch (value['e']) {
        case 'recNew':
          final t = core.typeNamed(value['type']);
          if (t != null) value['fields'] = pairs(t.fields);
        case 'errNew':
          value['fields'] = pairs(beErrorFields(core, value['kind'] is String ? value['kind'] as String : null));
        case 'enumVal':
          final t = core.typeNamed(value['type']);
          if (t != null && !t.cases.any((c) => c.name == value['case'])) value['case'] = t.cases.firstOrNull?.name ?? '';
        case 'varNew':
          final t = core.typeNamed(value['type']);
          if (t == null) return;
          if (!t.cases.any((c) => c.name == value['case'])) value['case'] = t.cases.firstOrNull?.name ?? '';
          final c = t.cases.where((c) => c.name == value['case']).firstOrNull;
          value['args'] = resized(c?.fields.length ?? 0, (i) => beDefaultExprOf(c!.fields[i].type));
        case 'classNew':
          final t = core.typeNamed(value['type']);
          if (t != null) value['args'] = resized(beCtorParams(core, t).length, (_) => exText(''));
      }
    }

    // “看是哪种情况”：这一段刚选了情况，“带出”还空着就按那种情况带的东西起好名字。
    if (block.op == 'match') {
      for (final a in block.arms) {
        final c = a.args['case'];
        final binds = a.args['binds'];
        if (c is! String || (binds is String && binds.isNotEmpty)) continue;
        final fields = core.types.expand((t) => t.cases).where((k) => k.name == c).firstOrNull?.fields ?? const <BeField>[];
        a.args['binds'] = c == kBeCaseSome || c.startsWith(kBeCaseIsPrefix) ? 'v' : [for (final (i, f) in fields.indexed) beNamePattern.hasMatch(f.name) ? f.name : 'v${i + 1}'].join(', ');
      }
    }
    relayout(block.argValue(arg), 0);
  }

  // —— 改定义（界面的面板调；每次一条撤销记录）——

  /// 做一件改定义的事；[change] 返回一句“为什么不能改”就通过 [onNotice] 说出来。改成了返回 true。
  bool coreEdit(String? Function(BeDocument doc) change) {
    String? bad;
    edit(() => bad = change(doc));
    if (bad != null) onNotice?.call('$bad，没有改。');
    return bad == null;
  }

  /// 新建一个类型，返回它的 id（满了返回 null）。
  String? addType(BeTypeKind kind) {
    String? id;
    edit(() => id = beAddType(doc, kind)?.id);
    if (id == null) onNotice?.call('类型最多 $kBeMaxTypes 个，没有加。');
    return id;
  }

  // —— 看代码 ——

  /// 这份文档“看代码”走不走语言核心那条路（见 backend_core_gen.dart）。
  bool get coreCodeMode => beIsCoreProgram(doc);
  String coreCodeText(String language) => beCoreCodeText(doc, language);
  String coreCodeFileName(String language) => beCoreCodeFileName(doc, language);
}
