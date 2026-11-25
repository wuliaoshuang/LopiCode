// 测试用的假宿主：一门小小的“语言”，专门用来试积木编辑器第 4 版的新本事——
// 多口积木（如果…否则如果…否则、分情况、试着做）、积木盒的两级分类、别名搜索、入门积木、“一块顶多块”。
// 真实的前端 / 后端宿主不改；它们接这些本事是后面的事（见 docs/blocks-v4-language-design.md “实施记录·阶段 1·编辑器”）。
import 'dart:convert';

import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

class FakeScript with LcBlockTree {
  FakeScript(this.id, {List<LcBlock>? body, double? x, double? y}) : body = body ?? [] {
    this.x = x;
    this.y = y;
  }

  @override
  final String id;
  @override
  final List<LcBlock> body;

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': ?x,
    'y': ?y,
    'body': [for (final b in body) b.toJson()],
  };

  static FakeScript parse(Map<String, dynamic> j) {
    final x = j['x'], y = j['y'];
    return FakeScript('${j['id']}', body: LcBlock.parseList(j['body'], 0), x: x is num ? x.toDouble() : null, y: y is num ? y.toDouble() : null);
  }
}

const _arith = ['+', '-', '*', '/'];
const _arithLabels = ['+', '−', '×', '÷'];
const _cmp = ['==', '!=', '<', '>'];
const _cmpLabels = ['=', '≠', '<', '>'];
const _vars = ['分数', '名字', '次数'];

const LcArgSpec _cond = LcArgSpec('cond', '条件', LcArgKind.expr, valueType: LcType.boolean);

const Map<String, LcBlockSpec> fakeBlockSpecs = {
  'say': LcBlockSpec('say', '说', '输出', [LcArgSpec('text', '内容', LcArgKind.expr, valueType: LcType.text)]),
  'set': LcBlockSpec('set', '设置变量', '变量', [LcArgSpec('name', '变量', LcArgKind.choice, choices: _vars, choiceLabels: _vars), LcArgSpec('value', '值', LcArgKind.expr)]),
  'change': LcBlockSpec('change', '变量加上', '变量', [LcArgSpec('name', '变量', LcArgKind.choice, choices: _vars, choiceLabels: _vars), LcArgSpec('by', '加上', LcArgKind.expr, valueType: LcType.number)]),
  // 如果：开头口“那么” + 任意多段“否则如果 <条件>” + 可收起的收尾口“否则”。
  'if': LcBlockSpec('if', '如果', '流程', [_cond], bodyLabel: '那么', elseLabel: '否则', arms: LcArmSpec('否则如果', [_cond], max: 8, tailOptional: true)),
  // 分情况：没有开头口 + 至少一段“是 (值) 时” + 可收起的收尾口“都不是”。
  'switch': LcBlockSpec(
    'switch',
    '分情况',
    '流程',
    [LcArgSpec('x', '看谁', LcArgKind.expr)],
    elseLabel: '都不是',
    arms: LcArmSpec('是…时', [LcArgSpec('value', '值', LcArgKind.expr)], min: 1, max: 8, tailOptional: true),
  ),
  // 试着做：开头口 + 正好一段不带参数的“出错了” + 可收起的收尾口“最后总要”。
  'try': LcBlockSpec('try', '试着做', '出错', [], bodyLabel: '试着做', elseLabel: '最后总要', arms: LcArmSpec('出错了', [], min: 1, max: 1, tailOptional: true)),
  'repeat': LcBlockSpec('repeat', '重复', '流程', [LcArgSpec('times', '次数', LcArgKind.expr, valueType: LcType.number)], bodyLabel: '重复做'),
  'while': LcBlockSpec('while', '当…时重复', '流程', [_cond], bodyLabel: '重复做'),
  'forEach': LcBlockSpec('forEach', '对每一项', '流程', [LcArgSpec('list', '列表', LcArgKind.expr)], bodyLabel: '做'),
  'break': LcBlockSpec('break', '跳出', '流程', []),
  'continue': LcBlockSpec('continue', '跳过这一次', '流程', []),
  'listAdd': LcBlockSpec('listAdd', '加一项', '列表', [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('item', '项', LcArgKind.expr)]),
  'listRemove': LcBlockSpec('listRemove', '删一项', '列表', [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('index', '第几项', LcArgKind.expr, valueType: LcType.number)]),
  'dictSet': LcBlockSpec('dictSet', '设置键', '字典', [LcArgSpec('dict', '字典', LcArgKind.expr), LcArgSpec('key', '键', LcArgKind.expr, valueType: LcType.text), LcArgSpec('value', '值', LcArgKind.expr)]),
  'throw': LcBlockSpec('throw', '报错', '出错', [LcArgSpec('message', '内容', LcArgKind.expr, valueType: LcType.text)]),
};

const Map<String, LcExprSpec> fakeExprSpecs = {
  'text': LcExprSpec('text', '文字', '值', [LcArgSpec('v', '文字', LcArgKind.literalText)]),
  'num': LcExprSpec('num', '数字', '值', [LcArgSpec('v', '数字', LcArgKind.literalNumber)]),
  'bool': LcExprSpec('bool', '是否', '值', [LcArgSpec('v', '是否', LcArgKind.literalBool)]),
  'var': LcExprSpec('var', '变量', '变量', [LcArgSpec('name', '变量', LcArgKind.choice, choices: _vars, choiceLabels: _vars)]),
  // 一块顶多块：四种算术是同一块，靠积木上的下拉切换。
  'arith': LcExprSpec('arith', '算术', '运算', [
    LcArgSpec('l', '左', LcArgKind.expr, valueType: LcType.number),
    LcArgSpec('op', '算法', LcArgKind.choice, choices: _arith, choiceLabels: _arithLabels),
    LcArgSpec('r', '右', LcArgKind.expr, valueType: LcType.number),
  ]),
  'cmp': LcExprSpec('cmp', '比较', '运算', [LcArgSpec('l', '左', LcArgKind.expr), LcArgSpec('op', '比法', LcArgKind.choice, choices: _cmp, choiceLabels: _cmpLabels), LcArgSpec('r', '右', LcArgKind.expr)]),
  'logic': LcExprSpec('logic', '并且 / 或者', '运算', [
    LcArgSpec('l', '左', LcArgKind.expr, valueType: LcType.boolean),
    LcArgSpec('op', '关系', LcArgKind.choice, choices: ['and', 'or'], choiceLabels: ['并且', '或者']),
    LcArgSpec('r', '右', LcArgKind.expr, valueType: LcType.boolean),
  ]),
  'not': LcExprSpec('not', '不是', '运算', [LcArgSpec('x', '值', LcArgKind.expr, valueType: LcType.boolean)]),
  'textCase': LcExprSpec('textCase', '转大小写', '文字', [
    LcArgSpec('x', '文字', LcArgKind.expr, valueType: LcType.text),
    LcArgSpec('mode', '转成', LcArgKind.choice, choices: ['upper', 'lower'], choiceLabels: ['大写', '小写']),
  ]),
  'textLen': LcExprSpec('textLen', '文字长度', '文字', [LcArgSpec('x', '文字', LcArgKind.expr, valueType: LcType.text)]),
  'textHas': LcExprSpec('textHas', '包含', '文字', [LcArgSpec('x', '文字', LcArgKind.expr, valueType: LcType.text), LcArgSpec('part', '什么', LcArgKind.expr, valueType: LcType.text)]),
  'listNew': LcExprSpec('listNew', '空列表', '列表', []),
  'listLen': LcExprSpec('listLen', '列表长度', '列表', [LcArgSpec('list', '列表', LcArgKind.expr)]),
  'listGet': LcExprSpec('listGet', '取一项', '列表', [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('index', '第几项', LcArgKind.expr, valueType: LcType.number)]),
  'listHas': LcExprSpec('listHas', '列表里有', '列表', [LcArgSpec('list', '列表', LcArgKind.expr), LcArgSpec('item', '项', LcArgKind.expr)]),
  'dictNew': LcExprSpec('dictNew', '空字典', '字典', []),
  'dictGet': LcExprSpec('dictGet', '取键', '字典', [LcArgSpec('dict', '字典', LcArgKind.expr), LcArgSpec('key', '键', LcArgKind.expr, valueType: LcType.text)]),
};

const Map<String, String> _blockSentences = {
  'say': '说 {text}',
  'set': '把 {name} 设为 {value}',
  'change': '把 {name} 加上 {by}',
  'if': '如果 {cond} 那么',
  'switch': '按 {x} 分情况',
  'try': '试着做',
  'repeat': '重复 {times} 次',
  'while': '当 {cond} 时重复',
  'forEach': '对 {list} 的每一项',
  'listAdd': '往 {list} 加 {item}',
  'listRemove': '删掉 {list} 的第 {index} 项',
  'dictSet': '把 {dict} 的 {key} 设为 {value}',
  'throw': '报错 {message}',
};

const Map<String, String> _armSentences = {'if': '否则如果 {cond}', 'switch': '是 {value} 时', 'try': '出错了'};

const Map<String, String> _exprSentences = {
  'var': '{name}',
  'arith': '{l} {op} {r}',
  'cmp': '{l} {op} {r}',
  'logic': '{l} {op} {r}',
  'not': '不是 {x}',
  'textCase': '{x} 转成 {mode}',
  'textLen': '{x} 的长度',
  'textHas': '{x} 包含 {part}',
  'listNew': '空列表',
  'listLen': '{list} 的长度',
  'listGet': '{list} 的第 {index} 项',
  'listHas': '{list} 里有 {item}',
  'dictNew': '空字典',
  'dictGet': '{dict} 的 {key}',
};

const Map<String, List<String>> _aliases = {
  'block:repeat': ['循环', 'for', '遍历', 'loop'],
  'block:while': ['循环', 'while'],
  'block:forEach': ['循环', '遍历', 'for', 'foreach'],
  'block:if': ['判断', '条件', 'if', 'else'],
  'block:switch': ['switch', 'case', '多选一'],
  'block:try': ['try', 'catch', '异常'],
  'expr:arith': ['四则运算', '计算'],
  'expr:textCase': ['case'],
};

/// 每一种变体自己的别名（`表达式:选项值`）。
const Map<String, List<String>> _variantAliases = {
  'arith:+': ['加', 'plus'],
  'arith:-': ['减'],
  'arith:*': ['乘', '倍'],
  'arith:/': ['除'],
  'cmp:==': ['等于'],
  'cmp:!=': ['不等于'],
  'cmp:<': ['小于'],
  'cmp:>': ['大于'],
  'textCase:upper': ['upper'],
  'textCase:lower': ['lower'],
};

Map<String, dynamic> _e(String kind, [Map<String, dynamic> more = const {}]) => {'e': kind, ...more};
Map<String, dynamic> fxNum(num v) => _e('num', {'v': v});
Map<String, dynamic> fxText(String v) => _e('text', {'v': v});
Map<String, dynamic> fxBool(bool v) => _e('bool', {'v': v});
Map<String, dynamic> fxVar(String name) => _e('var', {'name': name});
Map<String, dynamic> fxCmp(Object l, String op, Object r) => _e('cmp', {'l': l, 'op': op, 'r': r});

class FakeHost extends BlockHost {
  FakeHost({List<FakeScript>? scripts}) : _scripts = scripts ?? [];

  List<FakeScript> _scripts;
  final List<String> _undo = [], _redo = [];
  int _revision = 0;
  int _nextId = 1;

  /// 进了几次“统一改动入口”（＝几条撤销记录）。
  int edits = 0;

  String encode() => jsonEncode([for (final s in _scripts) s.toJson()]);

  void _restore(String text) {
    _scripts = [for (final j in jsonDecode(text) as List) FakeScript.parse((j as Map).cast<String, dynamic>())];
    _revision++;
    onChanged?.call();
  }

  @override
  List<BlockCategory> get categories => [
    const BlockCategory(
      id: 'event',
      label: '事件',
      colorKey: BlockColorKey.event,
      hats: [
        BlockHatTemplate('start', BlockHat([BlockHatPart.text('当开始运行时')])),
      ],
    ),
    const BlockCategory(id: 'variable', label: '变量', colorKey: BlockColorKey.variable, blocks: ['set', 'change'], exprs: ['var']),
    const BlockCategory(
      id: 'operator',
      label: '运算',
      colorKey: BlockColorKey.operator,
      groups: [
        BlockGroup('算术', exprs: ['arith']),
        BlockGroup('比较', exprs: ['cmp']),
        BlockGroup('逻辑', exprs: ['logic', 'not']),
      ],
    ),
    const BlockCategory(
      id: 'control',
      label: '流程',
      colorKey: BlockColorKey.control,
      groups: [
        BlockGroup('判断', blocks: ['if', 'switch']),
        BlockGroup('循环', blocks: ['repeat', 'while', 'forEach', 'break', 'continue']),
      ],
    ),
    const BlockCategory(id: 'text', label: '文字', colorKey: BlockColorKey.text, blocks: ['say'], exprs: ['textCase', 'textLen', 'textHas']),
    const BlockCategory(
      id: 'list',
      label: '列表',
      colorKey: BlockColorKey.list,
      groups: [
        BlockGroup('造', exprs: ['listNew']),
        BlockGroup('取', exprs: ['listGet', 'listLen', 'listHas']),
        BlockGroup('改', blocks: ['listAdd', 'listRemove']),
      ],
    ),
    const BlockCategory(id: 'dict', label: '字典', colorKey: BlockColorKey.dict, blocks: ['dictSet'], exprs: ['dictNew', 'dictGet']),
    const BlockCategory(id: 'error', label: '出错', colorKey: BlockColorKey.error, blocks: ['try', 'throw']),
    const BlockCategory(id: 'value', label: '值', colorKey: BlockColorKey.value, exprs: ['text', 'num', 'bool']),
  ];

  @override
  List<String> aliasesOf(BlockItemRef item) => item.preset.isEmpty ? (_aliases[item.token] ?? const []) : (_variantAliases['${item.id}:${item.preset.values.first}'] ?? const []);

  /// 一块顶多块：算术、比较、并且 / 或者、转大小写各占一个位置，每一种都能单独搜到。
  @override
  List<BlockItemRef> variantsOf(BlockItemRef item) {
    if (item.kind != BlockPaletteKind.expr) return const [];
    final arg = switch (item.id) {
      'arith' || 'cmp' || 'logic' => 'op',
      'textCase' => 'mode',
      _ => null,
    };
    if (arg == null) return const [];
    return [
      for (final c in fakeExprSpecs[item.id]!.arg(arg)!.choices) BlockItemRef.expr(item.id, preset: {arg: c}),
    ];
  }

  @override
  List<BlockItemRef> get starterItems => const [
    BlockItemRef.hat('start'),
    BlockItemRef.block('say'),
    BlockItemRef.block('set'),
    BlockItemRef.block('if'),
    BlockItemRef.block('repeat'),
    BlockItemRef.expr('arith'),
  ];

  @override
  LcBlockSpec? blockSpec(String op) => fakeBlockSpecs[op];
  @override
  LcExprSpec? exprSpec(String kind) => fakeExprSpecs[kind];
  @override
  String? blockSentence(String op) => _blockSentences[op];
  @override
  String? armSentence(String op) => _armSentences[op];
  @override
  String? exprSentence(String kind) => _exprSentences[kind];

  @override
  bool isBooleanExpr(Map<String, dynamic> expr) => const {'bool', 'cmp', 'logic', 'not', 'textHas', 'listHas'}.contains(expr['e']);

  @override
  List<LcBlockTree> get scripts => _scripts;

  @override
  BlockHat hatOf(LcBlockTree tree) => const BlockHat([BlockHatPart.text('当开始运行时')]);
  @override
  String hatSlotValue(LcBlockTree tree, String slotId) => '';
  @override
  List<BlockOption> hatSlotOptions(LcBlockTree tree, String slotId) => const [];
  @override
  bool setHatSlot(LcBlockTree tree, String slotId, String value) => false;

  @override
  LcBlockTree? addScript(String templateId, {double? x, double? y}) {
    if (templateId != 'start') return null;
    final s = FakeScript('s${_nextId++}', x: x, y: y);
    _scripts.add(s);
    return s;
  }

  @override
  bool removeScript(String id) {
    final n = _scripts.length;
    _scripts.removeWhere((s) => s.id == id);
    return _scripts.length < n;
  }

  @override
  LcBlock newBlock(String op) => switch (op) {
    'say' => LcBlock(op: op, args: {'text': fxText('你好')}),
    'set' => LcBlock(op: op, args: {'name': '分数', 'value': fxNum(0)}),
    'change' => LcBlock(op: op, args: {'name': '分数', 'by': fxNum(1)}),
    // 新拿出来的“如果”是最简单的样子：没有“否则”，要的时候点“＋”加。
    'if' => LcBlock(op: op, args: {'cond': fxBool(true)}, noElse: true),
    'switch' => LcBlock(
      op: op,
      args: {'x': fxVar('分数')},
      arms: [
        LcArm(args: {'value': fxNum(1)}),
      ],
    ),
    'try' => LcBlock(op: op, arms: [LcArm()], noElse: true),
    'repeat' => LcBlock(op: op, args: {'times': fxNum(3)}),
    'while' => LcBlock(op: op, args: {'cond': fxBool(true)}),
    'forEach' => LcBlock(op: op, args: {'list': _e('listNew')}),
    'listAdd' => LcBlock(op: op, args: {'list': _e('listNew'), 'item': fxText('')}),
    'listRemove' => LcBlock(op: op, args: {'list': _e('listNew'), 'index': fxNum(1)}),
    'dictSet' => LcBlock(op: op, args: {'dict': _e('dictNew'), 'key': fxText('名字'), 'value': fxText('')}),
    'throw' => LcBlock(op: op, args: {'message': fxText('出错了')}),
    _ => LcBlock(op: op),
  };

  @override
  Map<String, dynamic> newExpr(String kind) => switch (kind) {
    'num' => fxNum(0),
    'bool' => fxBool(true),
    'var' => fxVar('分数'),
    'arith' => _e(kind, {'l': fxNum(1), 'op': '+', 'r': fxNum(1)}),
    'cmp' => fxCmp(fxNum(1), '==', fxNum(1)),
    'logic' => _e(kind, {'l': fxBool(true), 'op': 'and', 'r': fxBool(true)}),
    'not' => _e(kind, {'x': fxBool(true)}),
    'textCase' => _e(kind, {'x': fxText('abc'), 'mode': 'upper'}),
    'textLen' => _e(kind, {'x': fxText('abc')}),
    'textHas' => _e(kind, {'x': fxText('abc'), 'part': fxText('a')}),
    'listLen' => _e(kind, {'list': _e('listNew')}),
    'listGet' => _e(kind, {'list': _e('listNew'), 'index': fxNum(1)}),
    'listHas' => _e(kind, {'list': _e('listNew'), 'item': fxText('')}),
    'dictGet' => _e(kind, {'dict': _e('dictNew'), 'key': fxText('名字')}),
    'listNew' || 'dictNew' => _e(kind),
    _ => fxText(''),
  };

  @override
  Map<String, dynamic> defaultExpr(LcArgSpec arg) => switch (arg.valueType) {
    LcType.number => fxNum(0),
    LcType.boolean => fxBool(true),
    _ => fxText(''),
  };

  @override
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr}) => [for (final c in arg.choices) BlockOption(c, arg.choiceLabel(c))];

  /// 假校验：段的条件是“否”的字面量＝错误（标到那一格）；分情况有两段的值一模一样＝警告（标到后一段的值上）。
  @override
  List<BlockIssue> get issues {
    final out = <BlockIssue>[];
    for (final s in _scripts) {
      s.visitBlocks((b, path) {
        final seen = <String>{};
        for (var i = 0; i < b.arms.length; i++) {
          final args = b.arms[i].args;
          final cond = args['cond'];
          if (b.op == 'if' && cond is Map && cond['e'] == 'bool' && cond['v'] == false) {
            out.add(BlockIssue(message: '第 ${i + 1} 段“否则如果”的条件永远不成立', scriptId: s.id, path: path, arg: lcArmArg(i, 'cond'), exprPath: const [], rule: 'F01'));
          }
          if (b.op == 'switch' && !seen.add(jsonEncode(args['value']))) {
            out.add(BlockIssue(message: '第 ${i + 1} 段和前面的值重复了', isError: false, scriptId: s.id, path: path, arg: lcArmArg(i, 'value'), exprPath: const [], rule: 'F02'));
          }
        }
      });
    }
    return out;
  }

  @override
  String get codeText => encode();
  @override
  String get codeLanguage => 'JSON';

  @override
  void edit(void Function() change) {
    _undo.add(encode());
    _redo.clear();
    change();
    edits++;
    _revision++;
    onChanged?.call();
  }

  @override
  bool get canUndo => _undo.isNotEmpty;
  @override
  bool get canRedo => _redo.isNotEmpty;

  @override
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(encode());
    _restore(_undo.removeLast());
  }

  @override
  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(encode());
    _restore(_redo.removeLast());
  }

  @override
  int get revision => _revision;
}
