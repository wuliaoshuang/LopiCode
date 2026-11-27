import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_dart_hook.dart';
import 'package:lopicode/lowcode/export_dart_live.dart';
import 'package:lopicode/lowcode/export_dart_v3.dart';
import 'package:lopicode/lowcode/export_live_doc.dart';
import 'package:lopicode/lowcode/icon_set.dart';
import 'package:lopicode/lowcode/image_assets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/quick_actions.dart';

/// 把页面导出成一个可直接放进 Flutter 项目的 Dart 文件（一个 StatelessWidget）。
///
/// 多页面的项目：每页一个类，都写在这一个文件里（第一个是首页，[className] 是首页的类名）；底部导航项、
/// “点击时去页面”的快捷操作用 Navigator 跳过去。别的积木逻辑这一份一直不导出（按钮的 `onPressed` 是空的）。
/// 只有一页时和以前逐字节一样。
///
/// 项目里用了主题变量、状态与绑定、断点、状态样式、网格中的任何一样，走“会动的那一路”（export_dart_live.dart）：
/// 变量集中在一个类里、状态变了界面重画、按屏宽取样子。一样都没用的项目走原来的路，结果和以前逐字节一样。
String exportDart(LcDocument source, {String? className}) {
  lcSettleSharedNav(source); // 共用的底部导航：各页都取“刚改过的那一份”（编辑器里每次修改后已经做过，这里是给直接调导出的人兜底）
  // 用了第 6 期新东西的组件实例先化成普通页面的样子（没有这种实例时就是原来的文档）。
  final doc = lcExportDoc(source, allPages: true);
  final live = dartLiveWanted(doc) ? DartLiveExport(doc) : null;
  String page(String name) => live == null ? _pageClass(doc, name) : live.pageClass(name);
  String file(List<String> classes, String tail) => live == null ? _file(classes, tail, '') : _file(classes, tail + live.tail(), live.header());
  if (!doc.isMultiPage) return file([page(className ?? dartClassName(doc.title))], '');
  final names = <String>[];
  for (final p in doc.pages) {
    final base = names.isEmpty && className != null ? className : dartClassName(p.title);
    var name = base;
    for (var k = 2; names.contains(name); k++) {
      name = '$base$k';
    }
    names.add(name);
  }
  final classes = <String>[];
  final keep = doc.pageIndex;
  try {
    for (var i = 0; i < doc.pages.length; i++) {
      doc.openPageAt(i);
      String? classOf(String id) {
        final at = doc.pages.indexWhere((p) => p.id == id);
        return at < 0 || at == i ? null : names[at];
      }

      dartPageJumps = DartPageJumps(classOf, (n) {
        final id = lcQuickValue(doc, n.id, kLcGoPageQuick);
        return id == null ? null : classOf(id);
      });
      classes.add(page(names[i]));
    }
  } finally {
    dartPageJumps = null;
    doc.openPageAt(keep);
  }
  return file(classes, kDartPageHelpers);
}

String _file(List<String> classes, String tail, String note) =>
    '''// 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。
${note}import 'package:flutter/material.dart';

${classes.join('\n')}$tail''';

String _pageClass(LcDocument doc, String name) {
  // 自定义组件的实例先展开成普通控件再生成；展开不了的那个位置是一个空的 SizedBox。
  final tree = expandedTree(doc);
  final body = _node(tree, null, 3);
  // 弹窗不在控件树里：每个弹窗一个静态方法（没有弹窗的页面一个字都不多）。
  final dialogs = [for (final d in dartDialogsOf(tree)) '\n${dartDialogMethodCode(d, _node)}'].join();
  return '''class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
    return $body;
  }
$dialogs}
''';
}

/// 标题 → 合法的 Dart 类名（非 ASCII 字符会被丢掉，全丢光就用默认名）。
String dartClassName(String title) {
  final parts = title.split(RegExp(r'[^A-Za-z0-9]+')).where((s) => s.isNotEmpty);
  var name = parts.map((s) => s[0].toUpperCase() + s.substring(1)).join();
  if (name.isEmpty || RegExp(r'^[0-9]').hasMatch(name)) name = 'Lowcode$name';
  return name.endsWith('Page') ? name : '${name}Page';
}

String _s(String v) => "'${v.replaceAll('\\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\r', '').replaceAll('\n', r'\n')}'";

String _d(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

String _color(String hex) => 'const Color(0xFF${hex.substring(1).toUpperCase()})';

String _ind(int n) => '  ' * n;

/// 一个节点的代码。多页面时，设了“点击时去页面”的组件在这里接上跳转：
/// 按钮直接写进 `onPressed`；别的组件外面包一层 GestureDetector（在行里被 Expanded / Flexible 包着的，包在它们里面）。
String _node(LcNode n, LcNode? parent, int i) => dartLive?.node(n, parent, i, _nodeJump) ?? _nodeJump(n, parent, i);

/// 给“会动的那一路”用：生成一个节点（弹窗的内容、页面的根）。
String dartNode(LcNode n, LcNode? parent, int indent) => _node(n, parent, indent);

String _nodeJump(LcNode n, LcNode? parent, int i) {
  final code = _nodeCore(n, parent, i);
  final to = dartPageJumps?.clickPage(n);
  if (to == null) return code;
  final go = '() => _lcGoTo(context, const $to())';
  if (n.type == 'button') return code.replaceFirst('onPressed: () {}', 'onPressed: $go');
  final m = RegExp(r'^(Expanded|Flexible)\(\n(\s*)child: ').firstMatch(code);
  final tail = ',\n${_ind(i)})';
  if (m != null && code.endsWith(tail)) {
    final inner = code.substring(m.end, code.length - tail.length);
    return '${m[1]}(\n${m[2]}child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: $go, child: $inner)$tail';
  }
  return 'GestureDetector(behavior: HitTestBehavior.opaque, onTap: $go, child: $code)';
}

String _nodeCore(LcNode n, LcNode? parent, int i) {
  final inRow = parent?.type == 'row';
  // 行里的容器类组件：没给固定宽度就用 Expanded 平分剩余空间。
  // 否则行套行、行里放“拉伸”的列会拿到无限宽度，Flutter 直接报布局错误。
  final expand = inRow && (n.fillWidth || (n.isContainer && n.props['width'] is! num));
  String wrapFill(String w) => expand ? 'Expanded(\n${_ind(i + 1)}child: ${_reindent(w, 1)},\n${_ind(i)})' : w;

  switch (n.type) {
    case 'page':
      final bg = n.strProp('bg');
      // 页面级的栏（顶部导航栏排第一个、底部导航栏排最后一个）放进 Scaffold 自己的位置。
      final flow = [
        for (final c in n.children)
          if (c.type != 'dialog') c,
      ];
      final top = flow.isNotEmpty && flow.first.type == 'appBar' ? flow.first : null;
      final bottom = flow.isNotEmpty && flow.last.type == 'bottomNav' ? flow.last : null;
      String gen(LcNode b) => dartV3Node(b, i + 1, _node, inRow: false)!;
      String bar(LcNode b) => dartLive?.bar(b, gen) ?? gen(b);
      return 'Scaffold(\n'
          '${bg != null ? '${_ind(i + 1)}backgroundColor: ${_color(bg)},\n' : ''}'
          '${top == null ? '' : '${_ind(i + 1)}appBar: ${bar(top).replaceFirst('primary: false', 'primary: true')},\n'}'
          '${bottom == null ? '' : '${_ind(i + 1)}bottomNavigationBar: ${bar(bottom)},\n'}'
          '${_ind(i + 1)}body: SafeArea(\n'
          '${_ind(i + 2)}child: SingleChildScrollView(\n'
          '${_ind(i + 3)}padding: const EdgeInsets.all(${_d(n.numProp('padding') ?? 0)}),\n'
          '${_ind(i + 3)}child: ${_flex(n, i + 3, column: true, forceStretchWidth: true, skip: [?top, ?bottom])},\n'
          '${_ind(i + 2)}),\n'
          '${_ind(i + 1)}),\n'
          '${_ind(i)})';
    case 'container' || 'column' || 'card' || 'row':
      final inner = _flex(n, i + 1, column: n.type != 'row');
      return wrapFill(_box(n, i, inner, inRow: inRow, shadow: n.type == 'card'));
    case 'text':
      final style = <String>[
        if (n.numProp('fontSize') != null) 'fontSize: ${_d(n.numProp('fontSize')!)}',
        if (n.props['bold'] == true) 'fontWeight: FontWeight.w600',
        if (n.strProp('color') != null) 'color: ${_color(n.strProp('color')!)}',
        'height: 1.5',
      ];
      final ta = n.strProp('textAlign');
      final text =
          'Text(\n${_ind(i + 1)}${_s(n.strProp('text') ?? '')},\n'
          '${ta != null ? '${_ind(i + 1)}textAlign: TextAlign.$ta,\n' : ''}'
          '${_ind(i + 1)}style: const TextStyle(${style.join(', ')}),\n${_ind(i)})';
      final boxed = _needsBox(n) ? _box(n, i, _reindent(text, 1), inRow: inRow) : text;
      if (inRow && !n.fillWidth && n.props['width'] == null) {
        return 'Flexible(\n${_ind(i + 1)}child: ${_reindent(boxed, 1)},\n${_ind(i)})';
      }
      return wrapFill(boxed);
    case 'button':
      final styles = <String>[
        if (n.strProp('bg') != null) 'backgroundColor: ${_color(n.strProp('bg')!)}',
        if (n.strProp('color') != null) 'foregroundColor: ${_color(n.strProp('color')!)}',
        if (n.numProp('padding') != null) 'padding: const EdgeInsets.all(${_d(n.numProp('padding')!)})',
        if (n.numProp('radius') != null) 'shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(${_d(n.numProp('radius')!)}))',
        if (n.numProp('fontSize') != null) 'textStyle: const TextStyle(fontSize: ${_d(n.numProp('fontSize')!)})',
      ];
      // 第 3 版加的：图标（FilledButton.icon）、禁用（onPressed: null）。没用到时和以前一个字都不差。
      final icon = lcIconByName(n.strProp('icon'));
      final button =
          '${icon == null ? 'FilledButton' : 'FilledButton.icon'}(\n${_ind(i + 1)}onPressed: ${n.props['disabled'] == true ? 'null' : '() {}'},\n'
          '${_ind(i + 1)}style: FilledButton.styleFrom(${styles.join(', ')}),\n'
          '${icon == null ? '' : '${_ind(i + 1)}icon: const Icon(Icons.${icon.name}),\n'}'
          '${_ind(i + 1)}${icon == null ? 'child' : 'label'}: Text(${_s(n.strProp('text') ?? '')}),\n${_ind(i)})';
      return wrapFill(_sized(n, i, button, inRow: inRow));
    case 'image':
      final radius = _d(n.numProp('radius') ?? 0);
      final h = n.numProp('height');
      final src = n.strProp('src');
      final alt = n.strProp('alt');
      final size =
          '${h != null ? 'height: ${_d(h)}, ' : ''}'
          '${n.props['width'] is num ? 'width: ${_d(n.props['width'] as num)}, ' : (n.fillWidth && !inRow ? 'width: double.infinity, ' : '')}';
      final liveSrc = dartLive?.boundText(n, 'src');
      final img = liveSrc != null
          ? '_lcImage($liveSrc, ${size}fit: BoxFit.cover, ${alt == null ? '' : 'semanticLabel: ${_s(alt)}, '}errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined))'
          : src == null
          ? 'Container(${size}color: const Color(0xFFD3DEE4), alignment: Alignment.center, child: const Icon(Icons.image_outlined${alt == null ? '' : ', semanticLabel: ${_s(alt)}'}))'
          // 图片加载失败（没网、地址错）时显示占位，而不是抛异常。
          // 项目里的图片（相对地址）用 Image.asset：要在工程的 pubspec.yaml 的 assets 里列上这个文件。
          : '${lcIsRemoteSrc(src) ? 'Image.network' : 'Image.asset'}(${_s(src)}, ${size}fit: BoxFit.cover, ${alt == null ? '' : 'semanticLabel: ${_s(alt)}, '}errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined))';
      final clipped = 'ClipRRect(\n${_ind(i + 1)}borderRadius: BorderRadius.circular($radius),\n${_ind(i + 1)}child: $img,\n${_ind(i)})';
      return wrapFill(_margin(n, i, clipped));
    case 'input':
      // 第 3 版加的：类型、默认值、标签、必填、禁用。没用到时和以前一个字都不差。
      final value = n.strProp('value');
      final label = n.strProp('label');
      final keyboard = const {'number': 'number', 'email': 'emailAddress', 'tel': 'phone'}[n.strProp('inputType')];
      final live = dartLive?.fieldArgs(n);
      final field =
          '${value == null || live != null ? 'TextField' : 'TextFormField'}(\n'
          '${live == null ? '' : [for (final a in live) '${_ind(i + 1)}$a,\n'].join()}'
          '${value == null || live != null ? '' : '${_ind(i + 1)}initialValue: ${_s(value)},\n'}'
          '${n.props['disabled'] == true ? '${_ind(i + 1)}enabled: false,\n' : ''}'
          '${n.strProp('inputType') == 'password' ? '${_ind(i + 1)}obscureText: true,\n' : ''}'
          '${keyboard == null ? '' : '${_ind(i + 1)}keyboardType: TextInputType.$keyboard,\n'}'
          '${_ind(i + 1)}decoration: InputDecoration(\n'
          '${label == null ? '' : '${_ind(i + 2)}labelText: ${_s(n.props['required'] == true ? '$label *' : label)},\n'}'
          '${_ind(i + 2)}hintText: ${_s(n.strProp('placeholder') ?? '')},\n'
          '${_ind(i + 2)}border: OutlineInputBorder(borderRadius: BorderRadius.circular(${_d(n.numProp('radius') ?? 4)})),\n'
          '${_ind(i + 1)}),\n${_ind(i)})';
      // 行里的输入框必须有确定宽度，否则 Flutter 会报布局错误。
      final w = n.props['width'];
      if (inRow && w == null) {
        return _margin(n, i, 'SizedBox(\n${_ind(i + 1)}width: 160,\n${_ind(i + 1)}child: ${_reindent(field, 1)},\n${_ind(i)})');
      }
      return wrapFill(_sized(n, i, field, inRow: inRow));
    case 'list':
      final style = <String>[if (n.numProp('fontSize') != null) 'fontSize: ${_d(n.numProp('fontSize')!)}', if (n.strProp('color') != null) 'color: ${_color(n.strProp('color')!)}', 'height: 1.75'];
      final liveItems = dartLive?.boundList(n);
      final items = liveItems != null
          ? "${_ind(i + 2)}for (final item in $liveItems) Text('• ' + _lcText(item), style: const TextStyle(${style.join(', ')})),\n"
          : [for (final item in (n.props['items'] as List?) ?? const []) '${_ind(i + 2)}Text(${_s('• $item')}, style: const TextStyle(${style.join(', ')})),\n'].join();
      final col =
          'Column(\n${_ind(i + 1)}crossAxisAlignment: CrossAxisAlignment.start,\n'
          '${_ind(i + 1)}mainAxisSize: MainAxisSize.min,\n${_ind(i + 1)}children: [\n$items${_ind(i + 1)}],\n${_ind(i)})';
      return wrapFill(_needsBox(n) ? _box(n, i, _reindent(col, 1), inRow: inRow) : col);
    case 'divider':
      return _margin(n, i, inRow ? 'const SizedBox(height: 24, child: VerticalDivider(width: 1))' : 'const Divider(height: 1)');
    case 'spacer':
      final size = _d(n.numProp('size') ?? 16);
      return inRow ? 'const SizedBox(width: $size)' : 'const SizedBox(height: $size)';
  }
  // 第 3 版的新组件（export_dart_v3.dart）。弹窗不在控件树里，这里不会走到（_flex 已经把它挑出去了）。
  final v3 = n.type == 'dialog' ? null : dartV3Node(n, i, _node, inRow: inRow);
  if (v3 != null) {
    return switch (n.type) {
      // 顶部导航栏不在页面最上面时：当一个 56 高的条放在内容里。
      'appBar' => 'SizedBox(\n${_ind(i + 1)}height: 56,\n${_ind(i + 1)}child: ${_reindent(v3, 1)},\n${_ind(i)})',
      // 一行里的勾选框、单选组可以被压窄（字会折行），不然一行放不下就溢出了。
      'checkbox' || 'radio' when inRow => 'Flexible(\n${_ind(i + 1)}child: ${_reindent(_margin(n, i, v3), 1)},\n${_ind(i)})',
      'icon' || 'switch' || 'checkbox' || 'radio' || 'bottomNav' => _margin(n, i, v3),
      'select' => _margin(n, i, v3),
      'textarea' when inRow && n.props['width'] == null => _margin(n, i, 'SizedBox(\n${_ind(i + 1)}width: 160,\n${_ind(i + 1)}child: ${_reindent(v3, 1)},\n${_ind(i)})'),
      _ => wrapFill(_sized(n, i, v3, inRow: inRow)),
    };
  }
  return 'const SizedBox.shrink()';
}

bool _needsBox(LcNode n) => n.props['width'] != null || n.numProp('padding') != null || n.numProp('margin') != null || n.strProp('bg') != null;

String _reindent(String code, int by) => code.replaceAll('\n', '\n${_ind(by)}');

String _flex(LcNode n, int i, {required bool column, bool forceStretchWidth = false, List<LcNode> skip = const []}) {
  const cross = {'start': 'start', 'center': 'center', 'end': 'end', 'stretch': 'stretch'};
  const main = {'start': 'start', 'center': 'center', 'end': 'end', 'between': 'spaceBetween'};
  final a = n.strProp('align') ?? (column ? 'start' : 'center');
  final j = n.strProp('justify');
  final children = [
    for (final c in n.children)
      if (c.type != 'dialog' && !skip.contains(c)) '${_ind(i + 2)}${_node(c, n, i + 2)},\n',
  ].join();
  final flex =
      '${column ? 'Column' : 'Row'}(\n'
      '${_ind(i + 1)}mainAxisSize: ${column ? 'MainAxisSize.min' : 'MainAxisSize.max'},\n'
      '${_ind(i + 1)}crossAxisAlignment: CrossAxisAlignment.${cross[a]},\n'
      '${j != null ? '${_ind(i + 1)}mainAxisAlignment: MainAxisAlignment.${main[j]},\n' : ''}'
      '${n.numProp('gap') != null ? '${_ind(i + 1)}spacing: ${_d(n.numProp('gap')!)},\n' : ''}'
      '${_ind(i + 1)}children: [\n$children${_ind(i + 1)}],\n${_ind(i)})';
  final grid = dartLive?.grid(n, i, children);
  if (forceStretchWidth) {
    return 'SizedBox(\n${_ind(i + 1)}width: double.infinity,\n${_ind(i + 1)}child: ${_reindent(grid ?? flex, 1)},\n${_ind(i)})';
  }
  return grid ?? flex;
}

/// Container 包一层：尺寸、内外边距、背景、圆角、阴影。
String _box(LcNode n, int i, String child, {required bool inRow, bool shadow = false}) {
  final w = n.props['width'];
  final deco = <String>[
    if (n.strProp('bg') != null) 'color: ${_color(n.strProp('bg')!)}',
    if (n.numProp('radius') != null) 'borderRadius: BorderRadius.circular(${_d(n.numProp('radius')!)})',
    if (shadow) 'boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]',
  ];
  return 'Container(\n'
      '${w is num ? '${_ind(i + 1)}width: ${_d(w)},\n' : (w == 'fill' && !inRow ? '${_ind(i + 1)}width: double.infinity,\n' : '')}'
      '${n.numProp('height') != null ? '${_ind(i + 1)}height: ${_d(n.numProp('height')!)},\n' : ''}'
      '${n.numProp('margin') != null ? '${_ind(i + 1)}margin: const EdgeInsets.all(${_d(n.numProp('margin')!)}),\n' : ''}'
      '${n.numProp('padding') != null ? '${_ind(i + 1)}padding: const EdgeInsets.all(${_d(n.numProp('padding')!)}),\n' : ''}'
      '${deco.isNotEmpty ? '${_ind(i + 1)}decoration: BoxDecoration(${deco.join(', ')}),\n' : ''}'
      '${_ind(i + 1)}child: $child,\n${_ind(i)})';
}

/// 只管宽度和外边距（按钮、输入框自己处理内边距和背景）。
String _sized(LcNode n, int i, String child, {required bool inRow}) {
  final w = n.props['width'];
  var out = child;
  if (w is num) {
    out = 'SizedBox(\n${_ind(i + 1)}width: ${_d(w)},\n${_ind(i + 1)}child: ${_reindent(out, 1)},\n${_ind(i)})';
  } else if (w == 'fill' && !inRow) {
    out = 'SizedBox(\n${_ind(i + 1)}width: double.infinity,\n${_ind(i + 1)}child: ${_reindent(out, 1)},\n${_ind(i)})';
  }
  return _margin(n, i, out);
}

String _margin(LcNode n, int i, String child) {
  final m = n.numProp('margin');
  if (m == null || m == 0) return child;
  return 'Padding(\n${_ind(i + 1)}padding: const EdgeInsets.all(${_d(m)}),\n${_ind(i + 1)}child: ${_reindent(child, 1)},\n${_ind(i)})';
}
