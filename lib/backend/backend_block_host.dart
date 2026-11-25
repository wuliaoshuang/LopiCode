/// 后端这一边的积木宿主：把 [BeDocument] 的接口、变量、集合、积木目录、校验、生成的代码
/// 包成积木编辑器认的 [BlockHost]。编辑器（lib/blocks）不直接碰后端文档。
///
/// 一串脚本＝一个接口（[BeRoute]）；帽子＝“当收到 [GET▾] [/todos/:id]”（请求方式是下拉槽，路径是直接输入的文字槽）。
/// 积木盒：事件（五种请求方式的新接口）＋ 变量 / 运算 / 流程 / 文字 / 列表 / 字典 / 请求 / 返回 / 数据集合 / 调试 / 网络 / 值
/// （怎么排、别名、入门积木在 backend_palette.dart）。
/// 撤销重做是这里自己的快照栈（每次改动前记一份文档的副本）；落盘和重新生成代码由外面（后端积木页）接 [onEdited] 去做。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_edit.dart';
import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_func_host.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_palette.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 积木上的话。`{名字}` 是参数的位置；有 body 的积木，第一个口的叫法写在末尾。
const Map<String, String> beBlockSentences = {
  'respondJson': '返回 JSON {value} 状态码 {status}',
  'respondText': '返回文字 {value} 状态码 {status}',
  'dbInsert': '往 {collection} 里加一条 {value} 加好的放进 {into}',
  'dbUpdate': '把 {collection} 里 id 是 {id} 的那条改成 {value}',
  'dbDelete': '删掉 {collection} 里 id 是 {id} 的那条',
  'setVar': '把 {name} 设为 {value}',
  'changeVar': '把 {name} 加上 {by}',
  'if': '如果 {cond} 那么',
  'repeat': '重复 {times} 次',
  'forEach': '对 {list} 的每一项 放进 {item} 序号叫 {index} 依次做',
  'log': '写到日志 {value}',
  'fetch': '用 {method} 请求 {url} 带上 {data} 结果放进 {into} 成功后',
  ...beLangBlockSentences,
  ...beFuncBlockSentences,
};

const Map<String, String> beExprSentences = {
  'pathParam': '路径参数 {name}',
  'query': '网址参数 {name}',
  'bodyField': '请求内容的 {name}',
  'body': '整个请求内容',
  'header': '请求头 {name}',
  'dbAll': '{collection} 的全部',
  'dbGet': '{collection} 里 id 是 {id} 的那条',
  'dbFind': '{collection} 里 {key} 等于 {value} 的',
  'dbCount': '{collection} 有几条',
  'var': '{name}',
  'bin': '{l} {op} {r}',
  'not': '不是 {x}',
  'join': '拼接 {items}',
  'len': '{x} 有几个',
  'isNull': '{x} 是空的',
  'now': '现在的时间',
  'obj': '字典 {fields}',
  'pair': '{key} : {value}',
  'field': '{of} 的 {key}',
  ...beLangExprSentences,
  ...beFuncExprSentences,
};

/// 运算符在积木上显示成符号（下拉里还是中文全称）。
const Map<String, String> _opSigns = {'+': '+', '-': '−', '*': '×', '/': '÷', '%': '余', '==': '=', '!=': '≠', '<': '<', '<=': '≤', '>': '>', '>=': '≥', 'and': '并且', 'or': '或者'};

/// 每一类用哪种颜色（键在 lib/blocks/block_colors.dart 里都有，浅深两套）。
const Map<String, String> beCategoryColors = {
  '返回': BlockColorKey.response,
  '数据': BlockColorKey.data,
  '变量': BlockColorKey.variable,
  '流程': BlockColorKey.control,
  '调试': BlockColorKey.action,
  '网络': BlockColorKey.network,
  '请求': BlockColorKey.request,
  '运算': BlockColorKey.operator,
  '文字': BlockColorKey.text,
  '列表': BlockColorKey.list,
  '对象': BlockColorKey.dict,
  '函数': BlockColorKey.function,
  '直接填': BlockColorKey.value,
};

/// “路径参数”的名字在编辑器里是下拉（从这个接口路径里的 `:参数` 里挑），所以给编辑器的说明和目录里的不一样（目录里是直接填的文字）。
const LcExprSpec _pathParamSpec = LcExprSpec('pathParam', '路径参数', '请求', [LcArgSpec('name', '名字', LcArgKind.choice)], hint: '接口路径里 :名字 那一段实际填的内容');

/// 路径格式不对时给人看的原因。
String bePathProblem(String path) {
  if (path.isEmpty) return '路径不能是空的';
  if (!path.startsWith('/')) return '路径要用 / 开头，比如 /todos';
  if (path.length > 200) return '路径太长了（最多 200 个字符）';
  if (path != '/' && path.endsWith('/')) return '路径末尾不要带 /';
  if (path.contains('//')) return '路径里不能有连着的两个 /';
  for (final seg in path.substring(1).split('/')) {
    if (seg.startsWith(':')) {
      if (!beNamePattern.hasMatch(seg.substring(1))) return '参数名“$seg”不合规矩：冒号后面用英文字母、数字、下划线，不用数字开头';
    } else if (parseBePath('/$seg') == null) {
      return '“$seg”里有不能用的字符：每一段只能用英文字母、数字和 _ . ~ -（参数写成 :名字）';
    }
  }
  return '路径格式不对';
}

class BeBlockHost extends BlockHost with BeFuncHost {
  /// `doc`＝要编辑的文档（宿主拿走以后外面别再直接改它，要改走 [edit]）。
  /// `onEdited`＝内容真的变了以后调（改动、撤销、重做；外面拿去落盘、重新生成）。
  /// `onNotice`＝有一句话要告诉用户（比如路径格式不对、为什么没改）。
  BeBlockHost({required BeDocument doc, this.onEdited, this.onNotice, this.maxHistory = 100}) : _doc = doc; // ignore: prefer_initializing_formals 对外的参数名要叫 doc，不叫 _doc

  BeDocument _doc;
  void Function()? onEdited;
  @override
  void Function(String message)? onNotice;
  final int maxHistory;
  final List<BeDocument> _undo = [];
  final List<BeDocument> _redo = [];
  int _revision = 0;

  @override
  BeDocument get doc => _doc;

  /// 外面换了文档（文件在别处被改了、重新读盘）。撤销记录作废。
  void replaceDoc(BeDocument doc) {
    _doc = doc;
    _undo.clear();
    _redo.clear();
    _bump();
  }

  void _bump() {
    _revision++;
    _categories = null;
    dropFuncTable();
    _code = null;
    onChanged?.call();
  }

  // —— 目录 ——

  List<BlockCategory>? _categories;

  /// 新接口默认的路径：`/new`、`/new2`…，挑一个同一种请求方式下还没人用的。
  String freePath(String method) {
    final used = {
      for (final r in _doc.routes)
        if (r.method == method) bePathShape(r.path) ?? r.path,
    };
    var n = 1;
    while (used.contains(n == 1 ? '/new' : '/new$n')) {
      n++;
    }
    return n == 1 ? '/new' : '/new$n';
  }

  BlockHat _hat(String method, String path) =>
      BlockHat([const BlockHatPart.text('当收到'), BlockHatPart.slot('method', method), BlockHatPart.slot('path', path.isEmpty ? '路径' : path, empty: path.isEmpty, kind: LcArgKind.literalText)]);

  @override
  List<BlockCategory> get categories => _categories ??= [
    BlockCategory(
      id: 'event',
      label: '事件',
      colorKey: BlockColorKey.event,
      hats: [for (final m in kBeMethods) BlockHatTemplate(m, _hat(m, freePath(m)), hint: '新接口：${describeBeMethod(m)}')],
    ),
    ...bePaletteCategories,
  ];

  @override
  List<String> aliasesOf(BlockItemRef item) => beAliasesOf(item);

  @override
  List<BlockItemRef> variantsOf(BlockItemRef item) => beVariantsOf(item);

  @override
  List<BlockItemRef> get starterItems => beStarterItems;

  @override
  String? armSentence(String op) => beArmSentences[op];

  @override
  LcBlockSpec? blockSpec(String op) => funcBlockSpec(op);

  @override
  LcExprSpec? exprSpec(String kind) => kind == 'pathParam' ? _pathParamSpec : funcExprSpec(kind);

  /// `pair` 不在积木盒里（只能出现在“对象”里），颜色跟着“对象”。
  @override
  String exprColorKey(String kind) => kind == 'pair' ? BlockColorKey.dict : (funcColorKey(kind) ?? (kind == 'param' ? BlockColorKey.function : super.exprColorKey(kind)));

  @override
  String blockColorKey(String op) => funcColorKey(op) ?? super.blockColorKey(op);

  @override
  String? blockSentence(String op) => funcTable.sentenceOf(op) ?? beBlockSentences[op];

  @override
  String? exprSentence(String kind) => funcTable.sentenceOf(kind) ?? beExprSentences[kind];

  @override
  bool isBooleanExpr(Map<String, dynamic> expr) => funcTable.isBool(expr) || beExprIsBool(expr);

  // —— 脚本 ——

  @override
  List<LcBlockTree> get scripts => beTrees(_doc);

  @override
  BlockHat hatOf(LcBlockTree tree) => tree is BeFunction
      ? beDefineHat(tree.name)
      : tree is BeRoute
      ? _hat(tree.method, tree.path)
      : const BlockHat([BlockHatPart.text('不认识的接口')], colorKey: BlockColorKey.unknown);

  @override
  String hatSlotValue(LcBlockTree tree, String slotId) => tree is BeFunction
      ? (slotId == 'name' ? tree.name : '')
      : tree is! BeRoute
      ? ''
      : switch (slotId) {
          'method' => tree.method,
          'path' => tree.path,
          _ => '',
        };

  @override
  List<BlockOption> hatSlotOptions(LcBlockTree tree, String slotId) => slotId == 'method' ? [for (final m in kBeMethods) BlockOption(m, m, hint: describeBeMethod(m))] : const [];

  /// 改请求方式 / 路径。路径会收拾一下（去掉两头空格）再校验格式；不对就不改，并通过 [onNotice] 说原因。
  /// 路径参数只是改了名字（个数没变）时，这个接口里读旧名字的“路径参数”积木跟着改名。
  @override
  bool setHatSlot(LcBlockTree tree, String slotId, String value) {
    if (tree is BeFunction) return slotId == 'name' && renameFunction(tree, value);
    if (tree is! BeRoute) return false;
    if (slotId == 'method') return _doc.setRouteMethod(tree.id, value);
    if (slotId != 'path') return false;
    final path = value.trim();
    if (parseBePath(path) == null) {
      onNotice?.call('${bePathProblem(path)}，没有改。');
      return false;
    }
    return _doc.setRoutePath(tree.id, path);
  }

  @override
  LcBlockTree? addScript(String templateId, {double? x, double? y}) {
    if (templateId == kBeDefineTemplate) return addDefinition(x: x, y: y);
    final method = templateId.toUpperCase();
    if (!kBeMethods.contains(method)) return null;
    return _doc.addRoute(method, freePath(method), x: x, y: y);
  }

  @override
  bool removeScript(String id) => _doc.function(id) != null ? removeFunctionScript(id) : _doc.removeRoute(id);

  // —— 造新的 ——

  @override
  LcBlock newBlock(String op) {
    final f = _doc.function(beCallId(op) ?? '');
    return f != null ? beNewCallBlock(f) : newBeBlock(op, _doc);
  }

  @override
  Map<String, dynamic> newExpr(String kind) {
    final f = _doc.function(beCallId(kind) ?? '');
    return f != null ? beNewCallExpr(f) : newBeExpr(kind, _doc);
  }

  /// “对象”的字段里加一项＝加一个“名字 : 值”；别的“一串值”加一段空文字。
  @override
  Map<String, dynamic> newListItem(Map<String, dynamic> expr, LcArgSpec arg) => newBeListItem(exprKind(expr) ?? '', arg.name);

  // —— 参数 ——

  @override
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr}) {
    final own = funcOptions(arg, tree: tree, expr: expr);
    if (own != null) return own;
    switch (arg.kind) {
      case LcArgKind.variable:
        // 文档里声明的变量 ＋ 这个接口里用“新建变量 / 常量”“从…数到…”这些新建的名字。
        final locals = tree == null ? const <String, bool>{} : beLocalNames(tree.body, beNamePattern);
        return [
          if (arg.optional) const BlockOption('', '不选'),
          // 自定义积木里看不见文档变量（它不在哪个接口里跑）。
          if (tree is! BeFunction)
            for (final v in _doc.variables) BlockOption(v.name, v.name),
          for (final e in locals.entries)
            if (_doc.variable(e.key) == null) BlockOption(e.key, e.key, hint: e.value ? '这个接口里新建的常量' : '这个接口里新建的'),
        ];
      case LcArgKind.collection:
        return [for (final c in _doc.collections) BlockOption(c.name, c.name)];
      case LcArgKind.choice:
        if (expr != null && exprKind(expr) == 'pathParam' && arg.name == 'name') {
          // 这个接口路径里有哪些 :参数；现在填的那个不在里面也列出来（标一句），免得菜单是空的。
          final params = tree is BeRoute ? bePathParams(tree.path) : const <String>[];
          final current = expr['name'];
          return [
            for (final p in params) BlockOption(p, p),
            if (current is String && current.isNotEmpty && !params.contains(current)) BlockOption(current, current, hint: '路径里没有这个参数'),
            if (params.isEmpty && (current is! String || current.isEmpty)) const BlockOption('id', 'id', hint: '路径里还没有 :参数'),
          ];
        }
        return [for (final c in arg.choices) BlockOption(c, arg.choiceLabel(c))];
      default:
        return const [];
    }
  }

  /// 刚改过的这个参数里有“路径参数”积木（新建的默认叫 id）、名字在这个接口的路径里对不上：
  /// 路径里正好只有一个参数时换成它（没有歧义）；有好几个就不猜，留给校验去提示。
  @override
  void argChanged(LcBlockTree tree, LcBlock block, String arg, List<Object> exprPath) {
    if (tree is! BeRoute) return;
    final params = bePathParams(tree.path);
    if (params.length != 1) return;
    void fix(Object? value, int depth) {
      if (depth > kMaxExprDepth * 2) return;
      if (value is Map) {
        if (value['e'] == 'pathParam' && !params.contains(value['name'])) value['name'] = params.first;
        for (final v in value.values) {
          fix(v, depth + 1);
        }
      } else if (value is List) {
        for (final v in value) {
          fix(v, depth + 1);
        }
      }
    }

    fix(block.args[arg], 0);
  }

  @override
  String optionLabel(LcArgSpec arg, String value) {
    if (arg.kind != LcArgKind.choice) return value;
    final fn = funcOptionLabel(arg, value);
    if (fn != null) return fn;
    if (arg.name == 'op') return _opSigns[value] ?? arg.choiceLabel(value);
    return arg.choiceLabel(value).split('（').first;
  }

  // —— 校验与代码 ——

  late final BlockIssueCache _issueCache = BlockIssueCache(
    () => [
      for (final i in validateBackend(_doc, languages: [for (final t in backendTargets) t.id], table: funcTable)) blockIssueOf(i),
    ],
    () => _revision,
    () => onChanged?.call(),
  );

  @override
  List<BlockIssue> get issues => _issueCache.fresh();

  @override
  List<BlockIssue> get liveIssues => _issueCache.read();

  @override
  void stopIssueTimer() => _issueCache.stop();

  /// “错误”级的问题有几条（有错误时不重新生成代码）。照现在的内容算，不用缓存里可能慢一拍的结果。
  int get errorCount => issues.where((i) => i.isError).length;

  BackendTarget? get target => backendTargetFor(_doc.language);

  String? _code;

  /// 当前语言生成的路由文件（入口文件）。这种语言没有生成器时是一句说明。
  @override
  String get codeText {
    final cached = _code;
    if (cached != null) return cached;
    final gen = generateBackend(_doc);
    return _code = gen == null ? '语言“${_doc.language}”还没有生成器，没有代码可看。' : (gen.files[gen.target.entryFile] ?? '');
  }

  @override
  String get codeLanguage => target?.label ?? _doc.language;

  // —— 改动、撤销 ——

  /// 一次改动＝一条撤销记录。`change` 跑完内容其实没变（比如路径格式不对被拒绝了）就不记、也不通知落盘。
  @override
  void edit(void Function() change) {
    final before = _doc.clone();
    final was = before.encode();
    change();
    if (_doc.encode() == was) return;
    _undo.add(before);
    if (_undo.length > maxHistory) _undo.removeAt(0);
    _redo.clear();
    _bump();
    onEdited?.call();
  }

  @override
  bool get canUndo => _undo.isNotEmpty;

  @override
  bool get canRedo => _redo.isNotEmpty;

  @override
  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_doc);
    _doc = _undo.removeLast();
    _bump();
    onEdited?.call();
  }

  @override
  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_doc);
    _doc = _redo.removeLast();
    _bump();
    onEdited?.call();
  }

  @override
  int get revision => _revision;
}
