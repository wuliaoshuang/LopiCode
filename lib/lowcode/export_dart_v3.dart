/// 第 3 版的 11 个新组件导出成 Flutter 代码时怎么写（export_dart.dart 用）。
///
/// 导出的页面是一个 StatelessWidget，所以：
/// - 开关、勾选框、单选组、下拉选择画的是**页面里设的那个值**，点了不会变（`onChanged` 是空的，和按钮的 `onPressed: () {}` 一个意思）；
///   要它们真的能改，得在自己的工程里接上状态。单选组的圆点画的是图标，不是 Radio 控件（各版本 Flutter 的 Radio 写法不一样）。
/// - 标签页用 DefaultTabController，点页签真的会切。
/// - 弹窗不在页面的控件树里：每个弹窗导出成一个静态方法 `showDialog_<id>(context)`，要打开时调用它；
///   页面里“一开始就打开”（`open`）导不出来。
/// - 页面级的栏（顶部导航栏是页面第一个、底部导航栏是最后一个）放进 Scaffold 的 `appBar` / `bottomNavigationBar`。
/// - 底部导航栏每一项的 `page`（去哪一页）要等多页面，点了没反应。
/// - 状态样式（按下 / 禁用 / 聚焦）、网格布局、`style` 里的 CSS 这一份都不读（它一直只读简写属性）。
library;

import 'package:lopicode/lowcode/icon_set.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

String _s(String v) => "'${v.replaceAll('\\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\r', '').replaceAll('\n', r'\n')}'";
String _d(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
String _color(String hex, [String alpha = 'FF']) => 'const Color(0x$alpha${hex.substring(1).toUpperCase()})';
String _ind(int n) => '  ' * n;

/// `头(\n  参数,\n  参数,\n)`；参数已经是按 i + 1 级缩进写好的。
String _call(String head, List<String> args, int i) => '$head(\n${[for (final a in args) '${_ind(i + 1)}$a,\n'].join()}${_ind(i)})';

String _list(List<String> items, int i) => items.isEmpty ? '[]' : '[\n${[for (final x in items) '${_ind(i + 1)}$x,\n'].join()}${_ind(i)}]';

/// 当“在一行里”的父节点用（插槽里的子组件横着排：撑满的用 Expanded，输入框给固定宽度）。
final LcNode _rowParent = LcNode(id: '_slot', type: 'row');

typedef DartChild = String Function(LcNode child, LcNode parent, int indent);

String? _iconCode(String? name, {String extra = ''}) => lcIconByName(name) == null ? null : 'Icon(Icons.$name$extra)';

/// 弹窗对应的方法名。
String dartDialogMethod(LcNode n) => 'showDialog_${n.id.replaceAll(RegExp('[^A-Za-z0-9_]'), '_')}';

/// 页面里所有的弹窗（按出现的先后）。
List<LcNode> dartDialogsOf(LcNode root) {
  final out = <LcNode>[];
  void walk(LcNode n, int depth) {
    if (depth > LcNode.maxDepth * 4) return;
    if (n.type == 'dialog') out.add(n);
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  return out;
}

/// 新组件的控件代码（按 [i] 级缩进，不带宽度 / 外边距那层包装）；不是新组件返回 null。
/// [inRow]：它是不是在一行里。弹窗返回 null 以外的东西没有意义，调用方应该先把弹窗挑出去。
String? dartV3Node(LcNode n, int i, DartChild child, {required bool inRow}) {
  bool flag(String k) => n.props[k] == true;
  final variant = lcVariantOf(n);
  List<String> slot(String name, LcNode parent, int at) => [
    for (final c in lcSlotChildren(n, name))
      if (c.type != 'dialog') child(c, parent, at),
  ];
  final color = n.strProp('color'), bg = n.strProp('bg');
  final textStyle = [if (n.numProp('fontSize') != null) 'fontSize: ${_d(n.numProp('fontSize')!)}', if (color != null) 'color: ${_color(color)}'];
  String text(String v) => textStyle.isEmpty ? 'Text(${_s(v)})' : 'Text(${_s(v)}, style: const TextStyle(${textStyle.join(', ')}))';
  switch (n.type) {
    case 'icon':
      final size = _d(n.numProp('size') ?? 24);
      return _iconCode(n.strProp('icon'), extra: ', size: $size${color == null ? '' : ', color: ${_color(color)}'}') ?? 'const SizedBox(width: $size, height: $size)';
    case 'textarea':
      final value = n.strProp('value'), label = n.strProp('label');
      final rows = _d(n.numProp('rows') ?? 3);
      return _call(value == null ? 'TextField' : 'TextFormField', [
        if (value != null) 'initialValue: ${_s(value)}',
        if (flag('disabled')) 'enabled: false',
        if (flag('autoGrow')) ...['minLines: $rows', 'maxLines: null'] else 'maxLines: $rows',
        if (n.numProp('maxLength') != null) 'maxLength: ${_d(n.numProp('maxLength')!)}',
        _call('decoration: InputDecoration', [
          if (label != null) 'labelText: ${_s(flag('required') ? '$label *' : label)}',
          if (label != null) 'alignLabelWithHint: true',
          'hintText: ${_s(n.strProp('placeholder') ?? '')}',
          'border: OutlineInputBorder(borderRadius: BorderRadius.circular(${_d(n.numProp('radius') ?? 4)}))',
        ], i + 1),
      ], i);
    case 'switch':
      return 'Switch(value: ${flag('checked')}, onChanged: ${flag('disabled') ? 'null' : '(value) {}'})';
    case 'checkbox':
      return _call('Row', [
        'mainAxisSize: MainAxisSize.min',
        'children: ${_list(['Checkbox(value: ${flag('checked')}, onChanged: ${flag('disabled') ? 'null' : '(value) {}'})', 'Flexible(child: ${text(n.strProp('text') ?? '')})'], i + 1)}',
      ], i);
    case 'radio':
      final options = lcObjects(n, 'options');
      final value = n.strProp('value');
      if (options.isEmpty) return 'const SizedBox.shrink()';
      if (variant == 'button') {
        return _call('SegmentedButton<String>', [
          'showSelectedIcon: false',
          'emptySelectionAllowed: true',
          'segments: ${_list([for (final o in options) 'ButtonSegment(value: ${_s(o['value'] as String)}, label: Text(${_s(lcItemLabel(o, 'value'))}))'], i + 1)}',
          'selected: ${options.any((o) => o['value'] == value) ? '{${_s(value!)}}' : 'const <String>{}'}',
          'onSelectionChanged: ${flag('disabled') ? 'null' : '(value) {}'}',
        ], i);
      }
      final dot = color == null ? '' : ', color: ${_color(color)}';
      final items = [
        for (final o in options)
          _call('Row', [
            'mainAxisSize: MainAxisSize.min',
            'children: ${_list(['Icon(Icons.${o['value'] == value ? 'radio_button_checked' : 'radio_button_unchecked'}, size: 20$dot)', 'const SizedBox(width: 8)', 'Flexible(child: ${text(lcItemLabel(o, 'value'))})'], i + 3)}',
          ], i + 2),
      ];
      final group = n.strProp('direction') == 'row'
          ? _call('Wrap', ['spacing: 16', 'runSpacing: 8', 'children: ${_list(items, i + 1)}'], i)
          : _call('Column', ['mainAxisSize: MainAxisSize.min', 'crossAxisAlignment: CrossAxisAlignment.start', 'spacing: 8', 'children: ${_list(items, i + 1)}'], i);
      return flag('disabled') ? 'Opacity(opacity: 0.5, child: $group)' : group;
    case 'select':
      final options = lcObjects(n, 'options');
      final value = n.strProp('value');
      final w = n.props['width'];
      return _call('DropdownMenu<String>', [
        if (options.any((o) => o['value'] == value)) 'initialSelection: ${_s(value!)}',
        if (n.strProp('placeholder') != null) 'hintText: ${_s(n.strProp('placeholder')!)}',
        if (flag('disabled')) 'enabled: false',
        if (w is num) 'width: ${_d(w)}' else if (w == 'fill' && !inRow) 'expandedInsets: EdgeInsets.zero',
        'dropdownMenuEntries: ${_list([for (final o in options) 'DropdownMenuEntry(value: ${_s(o['value'] as String)}, label: ${_s(lcItemLabel(o, 'value'))})'], i + 1)}',
      ], i);
    case 'listItem':
      final sub = variant == 'two' ? n.strProp('subtitle') : null;
      final main = _call('Expanded', [
        _call('child: Column', [
          'mainAxisSize: MainAxisSize.min',
          'crossAxisAlignment: CrossAxisAlignment.start',
          'children: ${_list([text(n.strProp('title') ?? ''), if (sub != null) 'Text(${_s(sub)}, style: const TextStyle(fontSize: 13, color: Color(0xFF5C6479)))'], i + 5)}',
        ], i + 4),
      ], i + 3);
      return _call('Container', [
        if (bg != null) 'color: ${_color(bg)}',
        'constraints: const BoxConstraints(minHeight: 48)',
        'padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)',
        _call('child: Row', [
          'spacing: 12',
          'children: ${_list([...slot('left', _rowParent, i + 3), main, if (n.strProp('trailing') != null) 'Text(${_s(n.strProp('trailing')!)}, style: const TextStyle(fontSize: 14, color: Color(0xFF5C6479)))', ...slot('right', _rowParent, i + 3), if (flag('chevron')) 'const Icon(Icons.chevron_right, size: 20, color: Color(0xFF8B93A7))'], i + 2)}',
        ], i + 1),
      ], i);
    case 'appBar':
      final left = slot('left', _rowParent, i + 3), right = slot('right', _rowParent, i + 3);
      final center = variant == 'center';
      final title = left.isEmpty && right.isEmpty
          ? 'title: Text(${_s(n.strProp('title') ?? '')})'
          : _call('title: Row', [
              'spacing: 8',
              'children: ${_list([...left, 'Expanded(child: Text(${_s(n.strProp('title') ?? '')}${center ? ', textAlign: TextAlign.center' : ''}))', ...right], i + 2)}',
            ], i + 1);
      return _call('AppBar', [
        'primary: false',
        'automaticallyImplyLeading: false',
        if (flag('back')) 'leading: const BackButton()',
        title,
        'centerTitle: $center',
        if (bg != null) 'backgroundColor: ${_color(bg)}',
        if (color != null) 'foregroundColor: ${_color(color)}',
      ], i);
    case 'bottomNav':
      final items = lcObjects(n, 'items');
      final current = n.props['current'] is int ? n.props['current'] as int : 0;
      String icon(Map<String, dynamic> m) => _iconCode(m['icon'] as String?) ?? 'SizedBox(width: 24, height: 24)';
      if (items.length < 2) {
        // NavigationBar 至少要两项：只有一项（或没有）时画成一个 56 高的条。
        return _call('SizedBox', [
          'height: 56',
          'child: Center(child: ${items.isEmpty ? 'SizedBox.shrink()' : 'Column(mainAxisSize: MainAxisSize.min, children: [${icon(items.first)}, Text(${_s(lcItemLabel(items.first, ''))}, style: const TextStyle(fontSize: 12))])'})',
        ], i);
      }
      return _call('NavigationBar', [
        'selectedIndex: ${current.clamp(0, items.length - 1)}',
        'onDestinationSelected: (index) {}',
        if (variant == 'iconOnly') 'labelBehavior: NavigationDestinationLabelBehavior.alwaysHide',
        if (bg != null) 'backgroundColor: ${_color(bg)}',
        if (color != null) 'indicatorColor: ${_color(color, '33')}',
        'destinations: ${_list([for (final m in items) 'NavigationDestination(icon: ${icon(m)}, label: ${_s(lcItemLabel(m, ''))})'], i + 1)}',
      ], i);
    case 'tabs':
      final tabs = lcObjects(n, 'tabs');
      if (tabs.isEmpty) return 'const SizedBox.shrink()';
      final current = lcCurrentTab(n);
      final panels = [
        for (final t in tabs)
          _call('Column', ['mainAxisSize: MainAxisSize.min', 'crossAxisAlignment: CrossAxisAlignment.start', 'children: ${_list(slot(t['id'] as String, n, i + 9), i + 8)}'], i + 7),
      ];
      return _call('DefaultTabController', [
        'length: ${tabs.length}',
        'initialIndex: ${tabs.indexWhere((t) => t['id'] == current)}',
        _call('child: Column', [
          'mainAxisSize: MainAxisSize.min',
          'crossAxisAlignment: CrossAxisAlignment.stretch',
          'children: ${_list([
            _call('TabBar', [
              if (color != null) ...['labelColor: ${_color(color)}', 'indicatorColor: ${_color(color)}'],
              if (variant == 'pill') ...['isScrollable: true', 'tabAlignment: TabAlignment.start', 'dividerHeight: 0', 'indicatorSize: TabBarIndicatorSize.tab', 'indicator: BoxDecoration(color: const Color(0x14000000), borderRadius: BorderRadius.circular(999))'],
              'tabs: ${_list([for (final t in tabs) 'Tab(text: ${_s(lcItemLabel(t, 'id'))})'], i + 4)}',
            ], i + 3),
            'const SizedBox(height: 12)',
            _call('Builder', [
              ['builder: (context) {', '${_ind(i + 5)}final tabs = DefaultTabController.of(context);', '${_ind(i + 5)}return AnimatedBuilder(', '${_ind(i + 6)}animation: tabs,', '${_ind(i + 6)}builder: (context, child) => IndexedStack(index: tabs.index, children: ${_list(panels, i + 6)}),', '${_ind(i + 5)});', '${_ind(i + 4)}}'].join('\n'),
            ], i + 3),
          ], i + 2)}',
        ], i + 1),
      ], i);
  }
  return null;
}

/// 一个弹窗对应的静态方法（两级缩进，放在页面类里）。
String dartDialogMethodCode(LcNode n, DartChild child) {
  final variant = lcVariantOf(n);
  List<String> slot(String name, int at) => [
    for (final c in lcSlotChildren(n, name))
      if (c.type != 'dialog') child(c, n, at),
  ];
  final content = slot('content', 7), footer = slot('footer', 5);
  final body = [if (n.strProp('text') != null) 'Text(${_s(n.strProp('text')!)})', ...content];
  String button(String label) => 'TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(${_s(label)}))';
  final actions = footer.isNotEmpty ? footer : [if (variant == 'confirm') button(n.strProp('cancelText') ?? '取消'), button(n.strProp('okText') ?? '确定')];
  final dialog = _call('AlertDialog', [
    if (n.strProp('title') != null) 'title: Text(${_s(n.strProp('title')!)})',
    if (body.isNotEmpty)
      _call('content: SingleChildScrollView', [
        _call('child: Column', ['mainAxisSize: MainAxisSize.min', 'crossAxisAlignment: CrossAxisAlignment.start', 'spacing: 8', 'children: ${_list(body, 6)}'], 5),
      ], 4),
    'actions: ${_list(actions, 4)}',
  ], 3);
  final label = (n.strProp('title') ?? '').replaceAll(RegExp(r'[\r\n]'), ' ');
  return '''
  /// 弹窗${label.isEmpty ? '' : '「$label」'}：要打开它的时候调用（比如放在按钮的 onPressed 里）。
  static Future<void> ${dartDialogMethod(n)}(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: ${n.props['dismissible'] != false},
      builder: (context) => $dialog,
    );
  }
''';
}
