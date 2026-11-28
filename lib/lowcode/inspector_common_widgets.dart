// 设计约束（低代码 · 合一面板的“常用”页 · 390×844）
// - 内容主次：按组件类型只放最常改的四到七项，最常改的排最上面（文字类先是文字本身，容器类先是间距和对齐）。
//   其余旧“属性”面板里有、这里没单列的（高度、外边距…）收在最下面的“更多”里，默认折着；再细的去“样式”页。
// - 一行一项：名字在左、值在右（行的样子在 inspector_presets_widgets.dart）；数值一律“预设档 + …”。
// - 没有主操作：改了就生效。文字框打字、加减算连续操作（停 0.4 秒记一条撤销），点档、点选项一下一条。
// - 写到哪儿：见 inspector_write.dart（能用简写属性表达且样式里没盖着就写简写属性——四种导出和旧面板逐字一样）。
// - 取用的 tokens：Space.x2/x3/x4、textMuted（名字）、textFaint（说明小字）。
import 'package:lopicode/lowcode/component_instance_widgets.dart';
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/inspector_bind_widgets.dart';
import 'package:lopicode/lowcode/inspector_bp_widgets.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/inspector_v3_components_widgets.dart';
import 'package:lopicode/lowcode/inspector_v3_rows_widgets.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_rows_widgets.dart';
import 'package:lopicode/lowcode/theme_scope_widgets.dart';
import 'package:lopicode/lowcode/theme_vars.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 合一面板里“正在改的这个组件”。
class InspectorEdit {
  const InspectorEdit({required this.doc, required this.node, required this.parent, required this.apply, this.pickImage, this.editDoc, this.canBind = false, this.bp});
  final LcDocument doc;

  /// 组件现在的样子（已经算上还没提交的改动）。只读；要改走 [apply]。
  final LcNode node;
  final LcNode? parent;

  /// 改这个组件。[merge]＝和紧接着的改动合成一条撤销（打字、加减）。
  final void Function(void Function(LcNode n, LcNode? parent) change, {bool merge}) apply;

  /// 选一张图片：`gallery` 从相册、`project` 从项目文件。返回写进“图片地址”的值；没选返回 null。
  /// 不给＝这个地方不能选图（只能填网址）。
  final Future<String?> Function(String from)? pickImage;

  /// 改整份文档（不只是这个组件；比如把导航栏改成各页共用）。不给＝这类操作不出现。
  final LcEdit? editDoc;

  /// 这里的设置能不能绑到状态（页面里的控件能；自定义组件里面的这一期不能）。
  final bool canBind;

  /// 画布现在看的是哪一档屏宽（null＝手机）。不是手机时 [node] 是这一档看到的样子，[apply] 里样子类的改动只记这一档。
  final String? bp;
}

const Map<int, String> _zeroNone = {0: '无'};

/// 颜色写进简写属性时一律大写（和旧面板一样）；主题变量原样。
String? _colorValue(String? v) => v == null || v.startsWith('var(') ? v : v.toUpperCase();

class InspectorCommonPage extends StatefulWidget {
  const InspectorCommonPage({super.key, required this.ed, this.only, this.wrap});
  final InspectorEdit ed;

  /// 只放这几项简写属性（多选“一起改样式”用：只列几个组件都有的）；不给＝按组件类型放整页。
  final List<String>? only;

  /// 给 [only] 里每一行再套一层（多选时值不一样的那几行先显示“多个值”）；不给＝原样。
  final Widget Function(String field, Widget row)? wrap;

  @override
  State<InspectorCommonPage> createState() => _InspectorCommonPageState();
}

class _InspectorCommonPageState extends State<InspectorCommonPage> {
  final Map<String, TextEditingController> _text = {};

  InspectorEdit get ed => widget.ed;
  LcNode get n => ed.node;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String prop, Object? value, {bool merge = false}) => ed.apply((n, _) => writeCommon(n, prop, value), merge: merge);

  /// 项目的主题变量；数值显示用“变量已经换成值”的那份（不然用了变量的项读不出数）。
  LcTheme get _theme => lcThemeOf(ed.doc);
  num? _px(String cssName) => effectivePx(lcViewNode(n, LcViewEnv(vars: _theme.values)), ed.parent, cssName);

  /// 这一项现在用着哪个变量（没用是 null）。
  String? _varOf(String cssName) {
    final name = lcVarNameIn(_css(cssName));
    return name != null && _theme.values.containsKey(name) ? name : null;
  }

  String? _css(String cssName) => effectiveCss(n, ed.parent, cssName);

  // ───────────── 各种行 ─────────────

  Widget _textRow(String prop, String label, {int maxLines = 1, String? hint, TextInputType? keyboard}) {
    final c = _text.putIfAbsent(prop, () => TextEditingController(text: n.strProp(prop) ?? ''));
    return LcBindableRow(
      ed: ed,
      prop: prop,
      label: label,
      child: InspectorRow(
        label: label,
        scroll: false,
        child: TextField(
          key: Key('lc-common-$prop'),
          controller: c,
          minLines: 1,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: InputDecoration(isDense: true, hintText: hint),
          onChanged: (v) => ed.apply((n, _) => n.props[prop] = v, merge: true),
        ),
      ),
    );
  }

  Widget _preset(String prop, String label, String cssName, {List<int> quick = const [0, 8, 16, 24], List<int> scale = kSpacingScale, Map<int, String> names = _zeroNone, bool clearable = true}) =>
      LcPerBp(
        child: PresetRow(
          key: Key('lc-common-$prop'),
          id: prop,
          label: label,
          value: _px(cssName),
          quick: quick,
          scale: scale,
          names: names,
          clearable: clearable,
          vars: lcVarChoices(_theme, cssName),
          varName: _varOf(cssName),
          onVar: (name) => _set(prop, lcVarRef(name)),
          onChanged: (v, {typing = false}) => _set(prop, v, merge: typing),
        ),
      );

  Widget _padding() => _preset('padding', '内边距', 'padding-top');
  Widget _margin() => _preset('margin', '外边距', 'margin-top');
  Widget _gap(String label) => _preset('gap', label, 'row-gap');
  Widget _radius() => _preset('radius', '圆角', 'border-top-left-radius', quick: const [0, 6, 10, 16], scale: kRadiusScale, names: const {0: '无', kRadiusFull: '全圆'});
  Widget _fontSize() => _preset('fontSize', '字号', 'font-size', quick: const [14, 16, 20, 24], scale: kFontScale, names: const {});
  Widget _height() => _preset('height', '高度', 'height', quick: const [48, 96, 160, 240], scale: const [32, 48, 64, 96, 128, 160, 200, 240, 320], names: const {});

  Widget _color(String prop, String label, String cssName, {void Function(String? v)? onChanged}) => LcPerBp(
    child: InspectorRow(
      label: label,
      scroll: false,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ColorButton(id: 'common-$prop', value: _css(cssName), title: label, onChanged: onChanged ?? (v) => _set(prop, _colorValue(v))),
      ),
    ),
  );

  /// 改样子的“选一个”那种行（能分屏宽）。
  Widget _look({required String id, required String label, required Map<String, String> options, required String? selected, required ValueChanged<String> onChanged}) => LcPerBp(
    child: InspectorChoiceRow(id: id, label: label, options: options, selected: selected, onChanged: onChanged),
  );

  /// 在平板 / 桌面档：对齐、分布、撑满这些要按“这一档看到的样式”显示（简写属性里记的是手机的）。
  static String? _back(Map<String, String> map, String? css) {
    for (final e in map.entries) {
      if (e.value == css) return e.key;
    }
    return null;
  }

  static const Map<String, String> _alignBack = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'stretch': 'stretch'};
  static const Map<String, String> _justifyBack = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'between': 'space-between'};

  Widget _width() {
    final w = n.props['width'];
    final px = _px('width');
    final fill = ed.bp == null ? w == 'fill' : (_css('flex-grow') == '1' || _css('align-self') == 'stretch');
    final mode = px != null ? 'fixed' : (fill ? 'fill' : 'auto');
    return LcPerBp(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InspectorChoiceRow(
            id: 'width',
            label: '宽度',
            options: const {'auto': '随内容', 'fill': '占满', 'fixed': '自定义'},
            selected: mode,
            onChanged: (v) => _set('width', switch (v) {
              'fill' => 'fill',
              'fixed' => 160,
              _ => null,
            }),
          ),
          if (mode == 'fixed')
            PresetRow(
              key: const Key('lc-common-width-px'),
              id: 'width-px',
              label: '',
              value: px,
              quick: const [80, 120, 160, 240],
              scale: const [48, 64, 80, 96, 120, 160, 200, 240, 320],
              clearable: false,
              onChanged: (v, {typing = false}) => _set('width', v ?? 160, merge: typing),
            ),
        ],
      ),
    );
  }

  Widget _textAlign() =>
      _look(id: 'textAlign', label: '对齐', options: const {'left': '靠左', 'center': '居中', 'right': '靠右'}, selected: _css('text-align') ?? 'left', onChanged: (v) => _set('textAlign', v));

  Widget _switch(String id, String label, bool value, ValueChanged<bool> onChanged) => LcPerBp(
    child: InspectorRow(
      label: label,
      scroll: false,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Switch(key: Key('lc-common-$id'), value: value, onChanged: onChanged),
      ),
    ),
  );

  // ───────────── 容器类 ─────────────

  static const List<String> _pos = ['start', 'center', 'end'];

  /// 这个容器里的东西是不是横着排。
  bool get _horizontal {
    final dir = _css('flex-direction');
    return dir == null ? n.type == 'row' : dir.startsWith('row');
  }

  List<Widget> _layout() {
    final horizontal = _horizontal;
    final atBp = ed.bp != null;
    final align = (atBp ? _back(_alignBack, _css('align-items')) : n.strProp('align')) ?? (n.type == 'row' ? 'center' : 'start');
    final justify = (atBp ? _back(_justifyBack, _css('justify-content')) : n.strProp('justify')) ?? 'start';
    // 横排：左右＝主方向（justify）、上下＝交叉方向（align）；竖排反过来。
    final hKey = horizontal ? justify : align, vKey = horizontal ? align : justify;
    return [
      if (n.type == 'container')
        _look(
          id: 'direction',
          label: '方向',
          options: const {'column': '↓ 竖排', 'row': '→ 横排'},
          selected: horizontal ? 'row' : 'column',
          onChanged: (v) => ed.apply((n, _) => writeStyleOnly(n, 'flex-direction', v == 'column' ? null : v)),
        ),
      _gap('间距'),
      LcPerBp(
        child: InspectorRow(
          label: '对齐',
          scroll: false,
          child: Align(
            alignment: Alignment.centerLeft,
            child: AlignGrid(
              h: _pos.contains(hKey) ? _pos.indexOf(hKey) : null,
              v: _pos.contains(vKey) ? _pos.indexOf(vKey) : null,
              onChanged: (x, y) => ed.apply((n, _) {
                writeCommon(n, horizontal ? 'justify' : 'align', _pos[x]);
                writeCommon(n, horizontal ? 'align' : 'justify', _pos[y]);
              }),
            ),
          ),
        ),
      ),
      _look(
        id: 'spread',
        label: '分布',
        options: const {'start': '紧挨', 'between': '两端', 'stretch': '拉伸'},
        selected: align == 'stretch' ? 'stretch' : (justify == 'between' ? 'between' : 'start'),
        onChanged: (v) => ed.apply((n, _) {
          switch (v) {
            case 'between':
              writeCommon(n, 'justify', 'between');
            case 'stretch':
              writeCommon(n, 'align', 'stretch');
            default:
              if (justify == 'between') writeCommon(n, 'justify', 'start');
              if (align == 'stretch') writeCommon(n, 'align', 'start');
          }
        }),
      ),
      _switch('wrap', '换行', _css('flex-wrap') == 'wrap', (v) => ed.apply((n, _) => writeStyleOnly(n, 'flex-wrap', v ? 'wrap' : null))),
      _padding(),
      _color('bg', '背景', 'background-color'),
      if (n.type == 'container') ...lcBoxOffRows(ed),
    ];
  }

  // ───────────── 图片 ─────────────

  List<Widget> _image() {
    final pick = ed.pickImage;
    Future<void> choose(String from) async {
      final src = await pick!(from);
      if (src == null || !mounted) return;
      _text['src']?.text = src;
      ed.apply((n, _) => n.props['src'] = src);
    }

    final ratio = _css('aspect-ratio')?.replaceAll(' ', '');
    return [
      if (pick != null)
        InspectorRow(
          label: '图片来源',
          child: Row(
            children: [
              InspectorChip(key: const Key('lc-common-src-gallery'), label: '从相册选', selected: false, onTap: () => choose('gallery')),
              InspectorChip(key: const Key('lc-common-src-project'), label: '项目文件', selected: false, onTap: () => choose('project')),
            ],
          ),
        ),
      _textRow('src', pick == null ? '图片地址' : '或网址', hint: 'https://…（留空显示占位图）', keyboard: TextInputType.url),
      _look(
        id: 'fit',
        label: '填充方式',
        options: const {'cover': '裁满', 'contain': '放全', 'fill': '拉伸'},
        selected: _css('object-fit') ?? 'cover',
        onChanged: (v) => ed.apply((n, _) => writeStyleOnly(n, 'object-fit', v == 'cover' ? null : v)),
      ),
      _look(
        id: 'ratio',
        label: '宽高比',
        options: const {'auto': '自动', '1/1': '1:1', '4/3': '4:3', '16/9': '16:9'},
        selected: ratio ?? 'auto',
        onChanged: (v) => ed.apply((n, _) => setImageRatio(n, v == 'auto' ? null : v.replaceAll('/', ' / '))),
      ),
      _radius(),
    ];
  }

  // ───────────── 每种组件放什么 ─────────────

  /// 返回：这一页要放的行，和“已经单列了的简写属性”（剩下的进“更多”）。
  (List<Widget>, Set<String>) _rows() {
    switch (n.type) {
      case 'text':
        final lines = textMaxLines(n.style);
        return (
          [
            _textRow('text', '文字', maxLines: 4),
            _look(id: 'level', label: '级别', options: kTextLevelLabels, selected: textLevel(n, ed.parent), onChanged: (v) => ed.apply((n, _) => setTextLevel(n, v))),
            _color('color', '颜色', 'color'),
            _textAlign(),
            _look(
              id: 'lines',
              label: '最多几行',
              options: const {'0': '不限', '1': '1', '2': '2', '3': '3'},
              selected: '${lines ?? 0}',
              onChanged: (v) => ed.apply((n, _) => setTextMaxLines(n, v == '0' ? null : int.parse(v))),
            ),
          ],
          {'text', 'color', 'textAlign'},
        );
      case 'button':
        return (
          [
            _textRow('text', '文字'),
            _look(
              id: 'variant',
              label: '样子',
              options: const {'solid': '实心', 'outline': '描边', 'text': '文字'},
              selected: buttonVariant(n, ed.parent),
              onChanged: (v) => ed.apply((n, p) => setButtonVariant(n, p, v)),
            ),
            _look(id: 'size', label: '大小', options: const {'s': '小', 'm': '中', 'l': '大'}, selected: buttonSize(n, ed.parent), onChanged: (v) => ed.apply((n, _) => setButtonSize(n, v))),
            _width(),
            _color('accent', '颜色', buttonVariant(n, ed.parent) == 'solid' ? 'background-color' : 'color', onChanged: (v) => ed.apply((n, p) => setButtonAccent(n, p, _colorValue(v ?? '#058654')!))),
            ...lcButtonV3Rows(context, ed),
          ],
          {'text', 'width'},
        );
      case 'image':
        return ([..._image(), ...lcImageV3Rows(ed)], {'src', 'radius'});
      case 'input':
        return ([_textRow('placeholder', '提示文字'), ...lcInputV3Rows(ed), _width(), _radius()], {'placeholder', 'width', 'radius'});
      case 'page' || 'container' || 'row' || 'column':
        return (_layout(), {'gap', 'align', 'justify', 'padding', 'bg'});
      case 'card':
        final shadow = _css('box-shadow');
        final level = shadow == null ? 1 : kShadowScale.indexOf(shadow);
        return (
          [
            _padding(),
            _radius(),
            _look(
              id: 'shadow',
              label: '阴影',
              options: const {'0': '无', '1': '一', '2': '二', '3': '三', '4': '四', '5': '五'},
              selected: level < 0 ? null : '$level',
              // 卡片本来就带第一级阴影（导出的样式表里写着）：选“一”＝不另写。
              onChanged: (v) => ed.apply((n, _) => writeStyleOnly(n, 'box-shadow', v == '1' ? null : kShadowScale[int.parse(v)])),
            ),
            _color('bg', '背景', 'background-color'),
            _gap('子项间距'),
          ],
          {'padding', 'radius', 'bg', 'gap'},
        );
      case 'list':
        final c = _text.putIfAbsent('items', () => TextEditingController(text: ((n.props['items'] as List?) ?? const []).join('\n')));
        return (
          [
            LcBindableRow(
              ed: ed,
              prop: 'items',
              label: '列表项',
              child: InspectorRow(
                label: '列表项',
                scroll: false,
                child: TextField(
                  key: const Key('lc-common-items'),
                  controller: c,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(isDense: true, hintText: '一行一项'),
                  onChanged: (v) => ed.apply((n, _) => n.props['items'] = v.split('\n').where((s) => s.trim().isNotEmpty).toList(), merge: true),
                ),
              ),
            ),
            _fontSize(),
            _color('color', '颜色', 'color'),
            _padding(),
          ],
          {'items', 'fontSize', 'color', 'padding'},
        );
      case 'spacer':
        return (
          [
            PresetRow(
              key: const Key('lc-common-size'),
              id: 'size',
              label: '间隔大小',
              value: n.numProp('size') ?? 16,
              quick: const [8, 16, 24, 32],
              scale: kSpacingScale.sublist(1),
              clearable: false,
              onChanged: (v, {typing = false}) => ed.apply((n, _) => n.props['size'] = v ?? 16, merge: typing),
            ),
          ],
          {'size'},
        );
      case 'component':
        return (
          [
            const LcNoBpTag(block: true),
            // 改的是这个实例自己传的值（props.values）；整张表交回去，空了就把 values 去掉。
            ComponentValuesForm(
              doc: ed.doc,
              node: n,
              onChanged: (values) => ed.apply((n, _) {
                if (values == null) {
                  n.props.remove('values');
                } else {
                  n.props['values'] = values;
                }
              }),
            ),
            ComponentInstanceExtras(doc: ed.doc, node: n, apply: (change) => ed.apply((n, _) => change(n))),
            const SizedBox(height: Space.x2),
            _width(),
            _margin(),
          ],
          {'width', 'margin'},
        );
      default:
        return lcV3ComponentRows(context, ed, color: _color, more: _more) ?? (const [], const {});
    }
  }

  /// 旧“属性”面板里有、上面没单列的项。
  Widget? _more(String prop) => switch (prop) {
    'width' => _width(),
    'height' => _height(),
    'padding' => _padding(),
    'margin' => _margin(),
    'radius' => _radius(),
    'gap' => _gap('子项间距'),
    'fontSize' => _fontSize(),
    'bg' => _color('bg', '背景', 'background-color'),
    'color' => _color('color', '文字颜色', 'color'),
    'textAlign' => _textAlign(),
    'bold' => _switch('bold', '加粗', n.props['bold'] == true || (int.tryParse(_css('font-weight') ?? '') ?? 400) >= 600, (v) => _set('bold', v ? true : null)),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final only = widget.only;
    if (only != null) {
      final wrap = widget.wrap;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in only)
            if (_more(f) case final row?) wrap == null ? row : wrap(f, row),
        ],
      );
    }
    if (n.type == 'slot') {
      return Text(
        '插槽只是一个空位，自己没有样子可改。要改排法、间距，选它外面那个容器；要改名或取消，用选中条上的按钮。',
        key: const Key('lc-slot-common-note'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted),
      );
    }
    final (rows, used) = _rows();
    final more = [
      for (final f in n.spec.fields)
        if (!used.contains(f)) ?_more(f),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        if (more.isNotEmpty && rows.isEmpty) ...more else if (more.isNotEmpty) MoreSection(id: 'common', children: more),
        InspectorDataSection(ed: ed),
        const SizedBox(height: Space.x3),
        Text('更细的（四边分别设、边框、定位…）在“样式”页。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textFaint)),
      ],
    );
  }
}
