/// 第 3 版的 11 个新组件导出成 Flutter 代码时怎么写（export_dart.dart 用）。
///
/// 导出的页面是一个 StatelessWidget，所以：
/// - 开关、勾选框、单选组、下拉选择画的是**页面里设的那个值**，点了不会变（`onChanged` 是空的，和按钮的 `onPressed: () {}` 一个意思）；
///   要它们真的能改，得在自己的工程里接上状态。单选组的圆点画的是图标，不是 Radio 控件（各版本 Flutter 的 Radio 写法不一样）。
/// - 标签页用 DefaultTabController，点页签真的会切。
/// - 弹窗不在页面的控件树里：每个弹窗导出成一个静态方法 `showDialog_<id>(context)`，要打开时调用它；
///   页面里“一开始就打开”（`open`）导不出来。
/// - 页面级的栏（顶部导航栏是页面第一个、底部导航栏是最后一个）放进 Scaffold 的 `appBar` / `bottomNavigationBar`。
/// - 底部导航栏每一项的 `page`（去哪一页）：多页面的项目里点了会换到那一页（[dartPageJumps]）；只有一页的项目点了没反应。
/// - 状态样式（按下 / 禁用 / 聚焦）、网格布局、`style` 里的 CSS：没用主题变量 / 绑定 / 断点 / 状态样式 / 网格的项目这一份都不读
///   （它一直只读简写属性）；用了的项目走“会动的那一路”（export_dart_live.dart），那里开关这些会写回状态、样式折回简写属性。
library;

import 'package:lopicode/lowcode/export_dart_hook.dart';
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

/// 多页面导出时“页面之间怎么跳”（export_dart.dart 在导出每一页的前后设上 / 清掉；只有一页的项目一直是 null）。
class DartPageJumps {
  const DartPageJumps(this.classOf, this.clickPage);

  /// 页面 id → 那一页的类名；页面不在了、或者就是当前这页，返回 null。
  final String? Function(String pageId) classOf;

  /// 这个组件“点击时去页面”（快捷操作存下来的那种：点击下面正好一块“去页面”）去的那一页的类名；没有返回 null。
  final String? Function(LcNode n) clickPage;
}

DartPageJumps? dartPageJumps;

/// 多页面导出的文件末尾带的两个小函数：叠一页上去（能返回）、换成另一页（底部导航用）。
/// 用到哪个带哪个（没用到的不写，免得导出的文件里有“写了没用上”的警告）。
const String _kDartGoTo = '''

/// 去另一页（叠在当前页上面，系统的返回能回来）。
void _lcGoTo(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
''';

const String _kDartSwitchTo = '''

/// 换成另一页（底部导航用：不往上叠）。page 是 null＝这一项没设去哪页，什么都不做。
void _lcSwitchTo(BuildContext context, Widget? page) {
  if (page == null) return;
  Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
}
''';

/// [code]（各页的类）里用到的跳页小函数。
String dartPageHelpersFor(String code) => '${code.contains('_lcGoTo(') ? _kDartGoTo : ''}${code.contains('_lcSwitchTo(') ? _kDartSwitchTo : ''}';

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
  // 双向绑定（只在“会动的那一路”里有）：现在的值、写回去的那句。
  final read = dartLive?.modelRead(n);
  String write(String value) => dartLive!.modelWrite(n, value);
  switch (n.type) {
    case 'icon':
      final size = _d(n.numProp('size') ?? 24);
      return _iconCode(n.strProp('icon'), extra: ', size: $size${color == null ? '' : ', color: ${_color(color)}'}') ?? 'const SizedBox(width: $size, height: $size)';
    case 'textarea':
      final value = n.strProp('value'), label = n.strProp('label');
      final rows = _d(n.numProp('rows') ?? 3);
      final live = dartLive?.fieldArgs(n);
      return _call(value == null || live != null ? 'TextField' : 'TextFormField', [
        ...?live,
        if (value != null && live == null) 'initialValue: ${_s(value)}',
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
      return 'Switch(value: ${read == null ? flag('checked') : '_lcBool($read)'}, onChanged: ${flag('disabled') ? 'null' : (read == null ? '(value) {}' : '(value) => ${write('value')}')})';
    case 'slider':
      final s = lcSliderOf(n);
      final steps = ((s.max - s.min) / s.step).round();
      return _call('Slider', [
        // 状态里的数可能跑到范围外面：夹回来（Slider 遇到范围外的值会直接报错）。
        'value: ${read == null ? _d(s.value) : '_lcNum($read).clamp(${_d(s.min)}, ${_d(s.max)}).toDouble()'}',
        'min: ${_d(s.min)}',
        'max: ${_d(s.max)}',
        if (steps >= 1 && steps <= 1000) 'divisions: $steps',
        'onChanged: ${flag('disabled') ? 'null' : (read == null ? '(value) {}' : '(value) => ${write('value')}')}',
      ], i);
    case 'checkbox':
      return _call('Row', [
        'mainAxisSize: MainAxisSize.min',
        'children: ${_list(['Checkbox(value: ${read == null ? flag('checked') : '_lcBool($read)'}, onChanged: ${flag('disabled') ? 'null' : (read == null ? '(value) {}' : '(value) => ${write('value == true')}')})', 'Flexible(child: ${text(n.strProp('text') ?? '')})'], i + 1)}',
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
          if (read != null)
            'selected: _lcPick($read, const [${[for (final o in options) _s(o['value'] as String)].join(', ')}])'
          else
            'selected: ${options.any((o) => o['value'] == value) ? '{${_s(value!)}}' : 'const <String>{}'}',
          'onSelectionChanged: ${flag('disabled') ? 'null' : (read == null ? '(value) {}' : "(value) => ${write("value.isEmpty ? '' : value.first")}")}',
        ], i);
      }
      final dot = color == null ? '' : ', color: ${_color(color)}';
      String mark(Map<String, dynamic> o) => read == null
          ? 'Icons.${o['value'] == value ? 'radio_button_checked' : 'radio_button_unchecked'}'
          : '_lcEq($read, ${_s(o['value'] as String)}) ? Icons.radio_button_checked : Icons.radio_button_unchecked';
      String row(Map<String, dynamic> o) => _call('Row', [
        'mainAxisSize: MainAxisSize.min',
        'children: ${_list(['Icon(${mark(o)}, size: 20$dot)', 'const SizedBox(width: 8)', 'Flexible(child: ${text(lcItemLabel(o, 'value'))})'], i + 3)}',
      ], i + 2);
      final items = [
        for (final o in options)
          if (read == null || flag('disabled')) row(o) else 'GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => ${write(_s(o['value'] as String))}, child: ${row(o)})',
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
        if (read != null) ...[
          'initialSelection: _lcPickOne($read, const [${[for (final o in options) _s(o['value'] as String)].join(', ')}])',
          "onSelected: (value) => ${write("value ?? ''")}",
        ] else if (options.any((o) => o['value'] == value))
          'initialSelection: ${_s(value!)}',
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
      // 每一项去哪页（多页面时才有）：没设 / 页面不在了 / 就是当前页的是 null。
      final jumps = dartPageJumps;
      final targets = [for (final m in items) m['page'] is String ? jumps?.classOf(m['page'] as String) : null];
      return _call('NavigationBar', [
        'selectedIndex: ${current.clamp(0, items.length - 1)}',
        targets.every((t) => t == null)
            ? 'onDestinationSelected: (index) {}'
            : 'onDestinationSelected: (index) => _lcSwitchTo(context, const <Widget?>[${[for (final t in targets) t == null ? 'null' : '$t()'].join(', ')}][index])',
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
  if (variant == 'toast') {
    final words = (n.strProp('text') ?? '').replaceAll(RegExp(r'[\r\n]'), ' ');
    return '''
  /// 轻提示${words.isEmpty ? '' : '「$words」'}：要它出现的时候调用（屏幕下方一句话，${lcToastSeconds(n)} 秒后自己消失）。
  static Future<void> ${dartDialogMethod(n)}(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(${_s(n.strProp('text') ?? '')}), duration: const Duration(seconds: ${lcToastSeconds(n)}), behavior: SnackBarBehavior.floating));
    return Future<void>.value();
  }
''';
  }
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
