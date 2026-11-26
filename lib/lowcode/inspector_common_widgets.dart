// 设计约束（低代码 · 合一面板的“常用”页 · 390×844）
// - 内容主次：按组件类型只放最常改的四到七项，最常改的排最上面（文字类先是文字本身，容器类先是间距和对齐）。
//   其余旧“属性”面板里有、这里没单列的（高度、外边距…）收在最下面的“更多”里，默认折着；再细的去“样式”页。
// - 一行一项：名字在左、值在右（行的样子在 inspector_presets_widgets.dart）；数值一律“预设档 + …”。
// - 没有主操作：改了就生效。文字框打字、加减算连续操作（停 0.4 秒记一条撤销），点档、点选项一下一条。
// - 写到哪儿：见 inspector_write.dart（能用简写属性表达且样式里没盖着就写简写属性——四种导出和旧面板逐字一样）。
// - 取用的 tokens：Space.x2/x3/x4、textMuted（名字）、textFaint（说明小字）。
import 'package:lopicode/lowcode/component_values_widgets.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_rows_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 合一面板里“正在改的这个组件”。
class InspectorEdit {
  const InspectorEdit({required this.doc, required this.node, required this.parent, required this.apply, this.pickImage});
  final LcDocument doc;

  /// 组件现在的样子（已经算上还没提交的改动）。只读；要改走 [apply]。
  final LcNode node;
  final LcNode? parent;

  /// 改这个组件。[merge]＝和紧接着的改动合成一条撤销（打字、加减）。
  final void Function(void Function(LcNode n, LcNode? parent) change, {bool merge}) apply;

  /// 选一张图片：`gallery` 从相册、`project` 从项目文件。返回写进“图片地址”的值；没选返回 null。
  /// 不给＝这个地方不能选图（只能填网址）。
  final Future<String?> Function(String from)? pickImage;
}

const Map<int, String> _zeroNone = {0: '无'};

class InspectorCommonPage extends StatefulWidget {
  const InspectorCommonPage({super.key, required this.ed});
  final InspectorEdit ed;

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

  num? _px(String cssName) => effectivePx(n, ed.parent, cssName);
  String? _css(String cssName) => effectiveCss(n, ed.parent, cssName);

  // ───────────── 各种行 ─────────────

  Widget _textRow(String prop, String label, {int maxLines = 1, String? hint, TextInputType? keyboard}) {
    final c = _text.putIfAbsent(prop, () => TextEditingController(text: n.strProp(prop) ?? ''));
    return InspectorRow(
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
    );
  }

  Widget _preset(String prop, String label, String cssName, {List<int> quick = const [0, 8, 16, 24], List<int> scale = kSpacingScale, Map<int, String> names = _zeroNone, bool clearable = true}) =>
      PresetRow(
        key: Key('lc-common-$prop'),
        id: prop,
        label: label,
        value: _px(cssName),
        quick: quick,
        scale: scale,
        names: names,
        clearable: clearable,
        onChanged: (v, {typing = false}) => _set(prop, v, merge: typing),
      );

  Widget _padding() => _preset('padding', '内边距', 'padding-top');
  Widget _margin() => _preset('margin', '外边距', 'margin-top');
  Widget _gap(String label) => _preset('gap', label, 'row-gap');
  Widget _radius() => _preset('radius', '圆角', 'border-top-left-radius', quick: const [0, 6, 10, 16], scale: kRadiusScale, names: const {0: '无', kRadiusFull: '全圆'});
  Widget _fontSize() => _preset('fontSize', '字号', 'font-size', quick: const [14, 16, 20, 24], scale: kFontScale, names: const {});
  Widget _height() => _preset('height', '高度', 'height', quick: const [48, 96, 160, 240], scale: const [32, 48, 64, 96, 128, 160, 200, 240, 320], names: const {});

  Widget _color(String prop, String label, String cssName, {void Function(String? v)? onChanged}) => InspectorRow(
    label: label,
    scroll: false,
    child: Align(
      alignment: Alignment.centerLeft,
      child: ColorButton(id: 'common-$prop', value: _css(cssName), title: label, onChanged: onChanged ?? (v) => _set(prop, v?.toUpperCase())),
    ),
  );

  Widget _width() {
    final w = n.props['width'];
    final px = _px('width');
    final mode = px != null ? 'fixed' : (w == 'fill' ? 'fill' : 'auto');
    return Column(
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
    );
  }

  Widget _textAlign() =>
      InspectorChoiceRow(id: 'textAlign', label: '对齐', options: const {'left': '靠左', 'center': '居中', 'right': '靠右'}, selected: _css('text-align') ?? 'left', onChanged: (v) => _set('textAlign', v));

  Widget _switch(String id, String label, bool value, ValueChanged<bool> onChanged) => InspectorRow(
    label: label,
    scroll: false,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Switch(key: Key('lc-common-$id'), value: value, onChanged: onChanged),
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
    final align = n.strProp('align') ?? (n.type == 'row' ? 'center' : 'start');
    final justify = n.strProp('justify') ?? 'start';
    // 横排：左右＝主方向（justify）、上下＝交叉方向（align）；竖排反过来。
    final hKey = horizontal ? justify : align, vKey = horizontal ? align : justify;
    return [
      if (n.type == 'container')
        InspectorChoiceRow(
          id: 'direction',
          label: '方向',
          options: const {'column': '↓ 竖排', 'row': '→ 横排'},
          selected: horizontal ? 'row' : 'column',
          onChanged: (v) => ed.apply((n, _) => writeStyleOnly(n, 'flex-direction', v == 'column' ? null : v)),
        ),
      _gap('间距'),
      InspectorRow(
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
      InspectorChoiceRow(
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
              if (n.strProp('justify') == 'between') writeCommon(n, 'justify', 'start');
              if (n.strProp('align') == 'stretch') writeCommon(n, 'align', 'start');
          }
        }),
      ),
      _switch('wrap', '换行', _css('flex-wrap') == 'wrap', (v) => ed.apply((n, _) => writeStyleOnly(n, 'flex-wrap', v ? 'wrap' : null))),
      _padding(),
      _color('bg', '背景', 'background-color'),
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
      InspectorChoiceRow(
        id: 'fit',
        label: '填充方式',
        options: const {'cover': '裁满', 'contain': '放全', 'fill': '拉伸'},
        selected: _css('object-fit') ?? 'cover',
        onChanged: (v) => ed.apply((n, _) => writeStyleOnly(n, 'object-fit', v == 'cover' ? null : v)),
      ),
      InspectorChoiceRow(
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
            InspectorChoiceRow(id: 'level', label: '级别', options: kTextLevelLabels, selected: textLevel(n, ed.parent), onChanged: (v) => ed.apply((n, _) => setTextLevel(n, v))),
            _color('color', '颜色', 'color'),
            _textAlign(),
            InspectorChoiceRow(
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
            InspectorChoiceRow(
              id: 'variant',
              label: '样子',
              options: const {'solid': '实心', 'outline': '描边', 'text': '文字'},
              selected: buttonVariant(n, ed.parent),
              onChanged: (v) => ed.apply((n, p) => setButtonVariant(n, p, v)),
            ),
            InspectorChoiceRow(id: 'size', label: '大小', options: const {'s': '小', 'm': '中', 'l': '大'}, selected: buttonSize(n, ed.parent), onChanged: (v) => ed.apply((n, _) => setButtonSize(n, v))),
            _width(),
            _color('accent', '颜色', buttonVariant(n, ed.parent) == 'solid' ? 'background-color' : 'color', onChanged: (v) => ed.apply((n, p) => setButtonAccent(n, p, (v ?? '#058654').toUpperCase()))),
          ],
          {'text', 'width'},
        );
      case 'image':
        return (_image(), {'src', 'radius'});
      case 'input':
        return ([_textRow('placeholder', '提示文字'), _width(), _radius()], {'placeholder', 'width', 'radius'});
      case 'page' || 'container' || 'row' || 'column':
        return (_layout(), {'gap', 'align', 'justify', 'padding', 'bg'});
      case 'card':
        final shadow = _css('box-shadow');
        final level = shadow == null ? 1 : kShadowScale.indexOf(shadow);
        return (
          [
            _padding(),
            _radius(),
            InspectorChoiceRow(
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
            InspectorRow(
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
            const SizedBox(height: Space.x2),
            _width(),
            _margin(),
          ],
          {'width', 'margin'},
        );
      default:
        return (const [], const {});
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
        const SizedBox(height: Space.x3),
        Text('更细的（四边分别设、边框、定位…）在“样式”页。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textFaint)),
      ],
    );
  }
}
