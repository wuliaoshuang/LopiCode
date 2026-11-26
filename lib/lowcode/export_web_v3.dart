/// 第 3 版的 11 个新组件在网页类导出（网页、Vue、React）里长什么样。
///
/// 三份导出共用一套“元素树”（[LcEl]）：这里只说“是哪些标签、带哪些属性、子组件放哪儿”，
/// 三种写法的差别（属性改名、文字怎么转义、事件怎么挂）由 [lcRenderEl] 按 [LcWebDialect] 处理。
/// 这样三份导出出来的结构保证一样，公共 CSS（export_web_v3_css.dart）也只写一份。
///
/// 规矩：
/// - 组件最外层的元素（[LcEl.host]）用各导出自己拼好的那串属性（class、显示绑定、事件），和旧组件完全一样。
/// - 自带的小交互（页签切换、弹窗的按钮和点遮罩关闭、导航栏的返回）**直接改网页元素**，不经框架的状态：
///   写成一句不带双引号的 JS 表达式，事件对象在三种写法里分别叫 `event` / `$event` / `event`。
///   弹窗要是被“改控件”积木管着显示，关闭时改的是那份状态（[LcWebCtx.closeExpr]），不然积木再让它显示会不灵。
/// - 底部导航栏每一项的 `page`（去哪一页）：项目里有这一页、而且不是当前这页时，点了就跳过去（[LcWebCtx.pageJump]）；
///   只有一页的项目没有可跳的地方，和以前一样不导出点击。
/// - 单选组：页面上节点 id 不重复，用 `name` 分组；自定义组件的定义会被用多次，`name` 会撞，
///   这时不写 `name`，改成点一个就把同组别的取消（[LcWebCtx.uniqueIds]）。
library;

import 'package:lopicode/lowcode/icon_set.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

enum LcWebDialect { html, vue, react }

/// 一个元素。属性值是 null＝只写名字的布尔属性。`@value` / `@checked` 是“初始值 / 初始勾选”，各写法自己翻。
class LcEl {
  LcEl(this.tag, {this.host = false, Map<String, String?>? attrs, this.text, List<Object>? kids, Map<String, String>? on}) : attrs = attrs ?? {}, kids = kids ?? [], on = on ?? {};
  final String tag;

  /// 是不是组件最外层的那个元素。
  final bool host;
  final Map<String, String?> attrs;

  /// 里面的文字（有文字就没有子元素）。
  final String? text;

  /// [LcEl]，或者一个子组件（[LcNode]，由各导出自己接着往下画）。
  final List<Object> kids;

  /// 事件（click / change）→ 一句 JS 表达式，里面用 `\u0001` 代表事件对象。
  final Map<String, String> on;
}

/// 事件对象的占位符（[lcRenderEl] 换成各写法里的名字）。
const String kLcEv = '\u0001';

class LcWebCtx {
  const LcWebCtx({required this.uniqueIds, required this.fieldClass, required this.closeExpr, required this.pageRoot, this.plainHtml = false, this.pageJump});

  /// 底部导航项“去哪一页”：页面 id → 点击时的一句 JS（见 export_pages.dart 的 lcPageJumper）；
  /// 没给、或者返回 null（页面不在了 / 就是当前这页）＝这一项点了没反应。
  final String? Function(String pageId)? pageJump;

  /// 导出的是不带框架的网页：弹窗的显示靠元素自己的 `style.display`（页面逻辑的“改控件 显示”改的就是它）。
  final bool plainHtml;

  /// 节点 id 在导出的页面上是不是唯一（自定义组件的定义里不是）。
  final bool uniqueIds;

  /// 带标签的输入框外面那层的 class。
  final String Function(LcNode n) fieldClass;

  /// 这个弹窗的显示被框架状态管着时，“关掉它”的表达式；没被管着返回 null。
  final String? Function(LcNode dialog) closeExpr;

  /// 页面的根节点（判断“页面级的栏”用）；在组件定义里是 null。
  final LcNode? pageRoot;
}

const Set<String> lcWebV3Types = {'icon', 'textarea', 'switch', 'checkbox', 'radio', 'select', 'listItem', 'appBar', 'bottomNav', 'tabs', 'dialog'};

/// 组件最外层元素的类型 class。图标用 `lc-glyph`：`lc-icon` 已经是按钮里那个小图标的类了，规则不一样。
String lcTypeClass(String type) => type == 'icon' ? 'lc-glyph' : 'lc-$type';

/// 页面级的栏：顶部导航栏是页面的第一个子节点、底部导航栏是最后一个（弹窗不占位置，不算）时，贴着页面的边。
bool lcIsPageBar(LcNode? root, LcNode n) {
  if (root == null || root.type != 'page') return false;
  final flow = [
    for (final c in root.children)
      if (c.type != 'dialog') c,
  ];
  if (flow.isEmpty) return false;
  return (n.type == 'appBar' && identical(flow.first, n)) || (n.type == 'bottomNav' && identical(flow.last, n));
}

LcEl _svg(String? iconName, {String? cls, num? size}) {
  final icon = lcIconByName(iconName);
  return LcEl(
    'svg',
    attrs: {'class': ?cls, 'viewBox': '0 0 24 24', if (size != null) 'width': '$size', if (size != null) 'height': '$size', 'aria-hidden': 'true'},
    kids: [
      if (icon != null) LcEl('path', attrs: {'d': icon.path}),
    ],
  );
}

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

const String _pickTab =
    "$kLcEv.currentTarget.closest('.lc-tabs').querySelectorAll(':scope > .lc-tabs-bar > button, :scope > .lc-tabs-panel').forEach((x) => x.classList.contains('lc-tabs-panel') ? (x.hidden = x.dataset.tab !== $kLcEv.currentTarget.dataset.tab) : x.setAttribute('aria-selected', String(x === $kLcEv.currentTarget)))";
const String _pickRadio = "$kLcEv.currentTarget.closest('.lc-radio').querySelectorAll('input').forEach((x) => (x.checked = x === $kLcEv.currentTarget))";

/// 这个新组件的元素树；不是新组件返回 null。
LcEl? lcWebElement(LcNode n, LcWebCtx ctx) {
  bool flag(String k) => n.props[k] == true;
  final variant = lcVariantOf(n);
  List<Object> slot(String name) => lcSlotChildren(n, name);
  switch (n.type) {
    case 'icon':
      return LcEl('span', host: true, kids: [_svg(n.strProp('icon'), size: n.numProp('size') ?? 24)]);
    case 'textarea':
      final label = n.strProp('label');
      final area = LcEl(
        'textarea',
        host: true,
        attrs: {
          'rows': _n(n.numProp('rows') ?? 3),
          'placeholder': n.strProp('placeholder') ?? '',
          if (n.numProp('maxLength') != null) 'maxlength': _n(n.numProp('maxLength')!),
          if (flag('autoGrow')) 'data-autogrow': '',
          if (flag('required')) 'required': null,
          if (flag('disabled')) 'disabled': null,
          if (n.strProp('value') != null) '@value': n.strProp('value'),
        },
      );
      if (label == null) return area;
      return LcEl(
        'label',
        attrs: {'class': ctx.fieldClass(n)},
        kids: [
          LcEl(
            'span',
            attrs: {'class': 'lc-label'},
            kids: [
              LcEl('span', text: label),
              if (flag('required')) LcEl('span', attrs: {'class': 'lc-required', 'aria-hidden': 'true'}, text: ' *'),
            ],
          ),
          area,
        ],
      );
    case 'switch':
      return LcEl('input', host: true, attrs: {'type': 'checkbox', 'role': 'switch', if (flag('checked')) '@checked': null, if (flag('disabled')) 'disabled': null});
    case 'checkbox':
      return LcEl(
        'label',
        host: true,
        kids: [
          LcEl('input', attrs: {'type': 'checkbox', if (flag('checked')) '@checked': null, if (flag('disabled')) 'disabled': null}),
          LcEl('span', text: n.strProp('text') ?? ''),
        ],
      );
    case 'radio':
      final value = n.strProp('value');
      return LcEl(
        'div',
        host: true,
        attrs: {'role': 'radiogroup', 'data-variant': variant, 'data-direction': n.strProp('direction') ?? 'column'},
        kids: [
          for (final o in lcObjects(n, 'options'))
            LcEl(
              'label',
              attrs: {'class': 'lc-radio-item'},
              kids: [
                LcEl(
                  'input',
                  attrs: {'type': 'radio', if (ctx.uniqueIds) 'name': 'lc-${n.id}', 'value': o['value'] as String, if (o['value'] == value) '@checked': null, if (flag('disabled')) 'disabled': null},
                  on: {if (!ctx.uniqueIds) 'change': _pickRadio},
                ),
                LcEl('span', text: lcItemLabel(o, 'value')),
              ],
            ),
        ],
      );
    case 'select':
      final placeholder = n.strProp('placeholder');
      return LcEl(
        'select',
        host: true,
        attrs: {if (flag('disabled')) 'disabled': null, '@value': n.strProp('value') ?? ''},
        kids: [
          if (placeholder != null) LcEl('option', attrs: {'value': '', 'disabled': null, 'hidden': null}, text: placeholder),
          for (final o in lcObjects(n, 'options')) LcEl('option', attrs: {'value': o['value'] as String}, text: lcItemLabel(o, 'value')),
        ],
      );
    case 'listItem':
      final left = slot('left'), right = slot('right');
      final sub = variant == 'two' ? n.strProp('subtitle') : null;
      return LcEl(
        'div',
        host: true,
        attrs: {'data-variant': variant},
        kids: [
          if (left.isNotEmpty) LcEl('div', attrs: {'class': 'lc-slot lc-slot-left'}, kids: left),
          LcEl(
            'div',
            attrs: {'class': 'lc-item-main'},
            kids: [
              LcEl('span', attrs: {'class': 'lc-item-title'}, text: n.strProp('title') ?? ''),
              if (sub != null) LcEl('span', attrs: {'class': 'lc-item-sub'}, text: sub),
            ],
          ),
          if (n.strProp('trailing') != null) LcEl('span', attrs: {'class': 'lc-item-trailing'}, text: n.strProp('trailing')),
          if (right.isNotEmpty) LcEl('div', attrs: {'class': 'lc-slot lc-slot-right'}, kids: right),
          if (flag('chevron')) _svg('chevron_right', cls: 'lc-item-chevron'),
        ],
      );
    case 'appBar':
      final left = slot('left'), right = slot('right');
      return LcEl(
        'header',
        host: true,
        attrs: {'data-variant': variant, if (flag('sticky')) 'data-sticky': '', if (lcIsPageBar(ctx.pageRoot, n)) 'data-page': ''},
        kids: [
          if (flag('back')) LcEl('button', attrs: {'type': 'button', 'class': 'lc-bar-back', 'aria-label': '返回'}, kids: [_svg('arrow_back')], on: {'click': '$kLcEv.view.history.back()'}),
          if (left.isNotEmpty) LcEl('div', attrs: {'class': 'lc-slot lc-slot-left'}, kids: left),
          LcEl('h1', attrs: {'class': 'lc-bar-title'}, text: n.strProp('title') ?? ''),
          if (right.isNotEmpty) LcEl('div', attrs: {'class': 'lc-slot lc-slot-right'}, kids: right),
        ],
      );
    case 'bottomNav':
      final items = lcObjects(n, 'items');
      final current = n.props['current'] is int ? n.props['current'] as int : 0;
      return LcEl(
        'nav',
        host: true,
        attrs: {'data-variant': variant, if (lcIsPageBar(ctx.pageRoot, n)) 'data-page': ''},
        kids: [
          for (final (i, item) in items.indexed)
            LcEl(
              'button',
              attrs: {
                'type': 'button',
                'class': 'lc-nav-item',
                if (i == current) 'aria-current': 'page',
                if (variant == 'iconOnly' && lcItemLabel(item, '').isNotEmpty) 'aria-label': lcItemLabel(item, ''),
              },
              kids: [
                _svg(item['icon'] as String?),
                if (variant != 'iconOnly') LcEl('span', text: lcItemLabel(item, '')),
              ],
              on: {if (item['page'] is String) 'click': ?ctx.pageJump?.call(item['page'] as String)},
            ),
        ],
      );
    case 'tabs':
      final current = lcCurrentTab(n);
      final tabs = lcObjects(n, 'tabs');
      return LcEl(
        'div',
        host: true,
        attrs: {'data-variant': variant},
        kids: [
          LcEl(
            'div',
            attrs: {'class': 'lc-tabs-bar', 'role': 'tablist'},
            kids: [
              for (final t in tabs)
                LcEl('button', attrs: {'type': 'button', 'role': 'tab', 'aria-selected': '${t['id'] == current}', 'data-tab': t['id'] as String}, text: lcItemLabel(t, 'id'), on: {'click': _pickTab}),
            ],
          ),
          for (final t in tabs)
            LcEl('div', attrs: {'class': 'lc-tabs-panel', 'role': 'tabpanel', 'data-tab': t['id'] as String, if (t['id'] != current) 'hidden': null}, kids: slot(t['id'] as String)),
        ],
      );
    case 'dialog':
      final bound = ctx.closeExpr(n);
      final close = bound ?? (ctx.plainHtml ? "$kLcEv.currentTarget.closest('.lc-dialog').style.display = 'none'" : "$kLcEv.currentTarget.closest('.lc-dialog').hidden = true");
      final shut = bound == null && !flag('open');
      final content = slot('content'), footer = slot('footer');
      LcEl button(String text) => LcEl('button', attrs: {'type': 'button', 'class': 'lc-dialog-btn'}, text: text, on: {'click': close});
      return LcEl(
        'div',
        host: true,
        attrs: {'role': 'dialog', 'aria-modal': 'true', 'data-variant': variant, if (shut && ctx.plainHtml) 'style': 'display: none', if (shut && !ctx.plainHtml) 'hidden': null},
        kids: [
          LcEl('div', attrs: {'class': 'lc-dialog-scrim'}, on: {if (n.props['dismissible'] != false) 'click': close}),
          LcEl(
            'div',
            attrs: {'class': 'lc-dialog-panel'},
            kids: [
              if (n.strProp('title') != null) LcEl('h2', attrs: {'class': 'lc-dialog-title'}, text: n.strProp('title')),
              if (n.strProp('text') != null) LcEl('p', attrs: {'class': 'lc-dialog-text'}, text: n.strProp('text')),
              if (content.isNotEmpty) LcEl('div', attrs: {'class': 'lc-dialog-content'}, kids: content),
              LcEl(
                'div',
                attrs: {'class': 'lc-dialog-footer'},
                kids: footer.isNotEmpty ? footer : [if (variant == 'confirm') button(n.strProp('cancelText') ?? '取消'), button(n.strProp('okText') ?? '确定')],
              ),
            ],
          ),
        ],
      );
  }
  return null;
}

// —— 写成三种代码 ——

/// 写出来的一段：一行代码（[line]），或者“这里接着画一个子组件”（[child]）。[indent] 是相对最外层缩进几级。
class LcWebPiece {
  const LcWebPiece.line(String this.line, this.indent) : child = null;
  const LcWebPiece.child(LcNode this.child, this.indent) : line = null;
  final String? line;
  final LcNode? child;
  final int indent;
}

const Set<String> _void = {'input'};
const Map<String, String> _reactNames = {'class': 'className', 'for': 'htmlFor', 'maxlength': 'maxLength', 'tabindex': 'tabIndex'};

/// 把元素树写成代码。[hostAttrs] 是最外层元素的那串属性；[text] / [attr] 是这种写法的转义函数。
List<LcWebPiece> lcRenderEl(LcEl root, LcWebDialect d, {required String hostAttrs, required String Function(String s) text, required String Function(String name, String value) attr}) {
  final out = <LcWebPiece>[];
  final react = d == LcWebDialect.react;
  final ev = d == LcWebDialect.vue ? r'$event' : 'event';

  void el(LcEl e, int depth, {String? selectValue}) {
    final b = StringBuffer('<${e.tag}');
    if (e.host) b.write(hostAttrs);
    String? areaText;
    String? pick;
    e.attrs.forEach((name, value) {
      if (name == '@checked') {
        b.write(react ? ' defaultChecked' : ' checked');
      } else if (name == '@value') {
        if (e.tag == 'select') {
          if (react) {
            b.write(attr('defaultValue', value ?? ''));
          } else {
            pick = value ?? '';
          }
        } else if (d == LcWebDialect.html) {
          areaText = value;
        } else {
          b.write(attr(react ? 'defaultValue' : 'value', value ?? ''));
        }
      } else if (value == null) {
        b.write(' ${react ? _reactNames[name] ?? name : name}');
      } else {
        b.write(attr(react ? _reactNames[name] ?? name : name, value));
      }
    });
    if (e.tag == 'option' && selectValue != null && e.attrs['value'] == selectValue) b.write(' selected');
    e.on.forEach((event, js) {
      final code = js.replaceAll(kLcEv, ev);
      b.write(switch (d) {
        LcWebDialect.html => ' on$event="$code"',
        LcWebDialect.vue => ' @$event="$code"',
        LcWebDialect.react => ' on${event[0].toUpperCase()}${event.substring(1)}={(event) => $code}',
      });
    });
    final inner = areaText ?? e.text;
    if (inner != null) {
      out.add(LcWebPiece.line('$b>${text(inner)}</${e.tag}>', depth));
    } else if (e.kids.isEmpty) {
      out.add(LcWebPiece.line(react ? '$b />' : (_void.contains(e.tag) ? '$b>' : '$b></${e.tag}>'), depth));
    } else {
      out.add(LcWebPiece.line('$b>', depth));
      for (final k in e.kids) {
        if (k is LcEl) {
          el(k, depth + 1, selectValue: e.tag == 'select' ? pick : null);
        } else if (k is LcNode) {
          out.add(LcWebPiece.child(k, depth + 1));
        }
      }
      out.add(LcWebPiece.line('</${e.tag}>', depth));
    }
  }

  el(root, 0);
  return out;
}
