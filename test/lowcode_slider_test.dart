// 第四轮 B5：滑块（原生控件）——规格、存盘规矩、四种导出、双向绑定。
// 后半（开发机才有环境，找不到明确跳过）：三种网页导出官方编译器真编译 0 错 0 警告；Node + jsdom 真跑——
// 拖滑块（改它的值并发出 input 事件）状态跟着变；状态变了滑块跟着走；禁用绑到状态。
// 没覆盖的：真浏览器、真手机上手指拖动；Flutter 导出只看了生成的代码，没有真编译（开发机没有这条现成的路）。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_check.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';
import 'package:lopicode/lowcode/states.dart';

import 'support/bind_export_files.dart';
import 'support/comp_samples.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'Slide.vue', 'react': 'Slide.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

LcDocument _plain(Map<String, Object?> props) => LcDocument.fromJson(
  <String, Object?>{
    'version': 3,
    'title': 'Slide',
    'root': cn('root', 'page', {}, [cn('sl', 'slider', props)]),
  }.cast<String, dynamic>(),
);

/// 滑块双向绑到数字状态 n（0–10，一步 2）；一行字显示 n；按钮把 n 设成 4；禁用绑到状态 off，另一个按钮把 off 设成是。
LcDocument _bound() => LcDocument.fromJson(
  <String, Object?>{
    'version': 3,
    'title': 'Slide',
    'logic': {
      'variables': [
        {'name': 'n', 'type': 'number', 'initial': 6},
        {'name': 'off', 'type': 'bool', 'initial': false},
      ],
      'handlers': [
        {
          'id': 'h1',
          'event': 'click',
          'target': 'set4',
          'body': [
            {
              'op': 'setVar',
              'args': {'name': 'n', 'value': cNum(4)},
            },
          ],
        },
        {
          'id': 'h2',
          'event': 'click',
          'target': 'lock',
          'body': [
            {
              'op': 'setVar',
              'args': {
                'name': 'off',
                'value': {'e': 'bool', 'v': true},
              },
            },
          ],
        },
      ],
    },
    'root': cn('root', 'page', {}, [
      cn(
        'sl',
        'slider',
        {'min': 0, 'max': 10, 'step': 2, 'value': 2},
        [],
        {
          'model': {'state': 'n'},
          'data': {'disabled': cFrom('off')},
        },
      ),
      cn(
        'nText',
        'text',
        {'text': ''},
        [],
        {
          'data': {
            'text': cExpr(cJoin([cText('值 '), cVar('n')])),
          },
        },
      ),
      cn('set4', 'button', {'text': '设成 4'}),
      cn('lock', 'button', {'text': '锁住'}),
    ]),
  }.cast<String, dynamic>(),
);

const List<Map<String, Object?>> _steps = [
  {'op': 'value', 'sel': '.n-sl', 'is': '6'},
  {'op': 'text', 'sel': '.n-nText', 'is': '值 6'},
  // 拖到 8
  {'op': 'type', 'sel': '.n-sl', 'text': '8'},
  {'op': 'text', 'sel': '.n-nText', 'is': '值 8'},
  {'op': 'value', 'sel': '.n-sl', 'is': '8'},
  // 状态变了，滑块跟着走
  {'op': 'click', 'sel': '.n-set4'},
  {'op': 'text', 'sel': '.n-nText', 'is': '值 4'},
  {'op': 'value', 'sel': '.n-sl', 'is': '4'},
  // 禁用绑到状态
  {'op': 'disabled', 'sel': '.n-sl', 'is': false},
  {'op': 'click', 'sel': '.n-lock'},
  {'op': 'disabled', 'sel': '.n-sl', 'is': true},
];

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】滑块的真编译 / 真跑：$skipWithoutDom');
  }

  group('滑块', () {
    test('规格：在组件盒“表单”里、搜得到；默认 0–100、值 50、铺满；能禁用、能双向绑、禁用能绑', () {
      final spec = lcSpecs['slider']!;
      expect(spec.label, '滑块');
      expect(spec.defaults, {'value': 50, 'min': 0, 'max': 100, 'step': 1, 'width': 'fill'});
      expect(lcPaletteTypes, contains('slider'));
      final all = paletteEntries(const []);
      expect(paletteInGroup(all, PaletteGroup.form, const []).map((e) => e.type), contains('slider'));
      for (final q in ['滑块', 'range', 'huakuai', '拖动条']) {
        expect(paletteSearch(all, q).map((e) => e.type), contains('slider'), reason: q);
      }
      expect(kLcCanDisable, contains('slider'));
      expect(lcModelProp('slider'), 'value');
      expect(lcBindablesOf('slider').map((b) => b.prop), ['disabled']);
      final fresh = LcDocument.fromJson({'version': 3, 'title': 'T', 'root': cn('root', 'page')}.cast<String, dynamic>()).newNode('slider');
      expect(fresh.props, spec.defaults);
    });

    test('存盘规矩：四个数只认数；写错的丢掉；别的控件上的 value 还是一段文字，不受影响', () {
      final doc = LcDocument.fromJson(
        <String, Object?>{
          'version': 3,
          'title': 'T',
          'root': cn('root', 'page', {}, [
            cn('a', 'slider', {'value': 3.5, 'min': -10, 'max': 10, 'step': 0.5}),
            cn('b', 'slider', {'value': '7', 'min': 'x', 'max': 5, 'step': 0}),
            cn('c', 'input', {'value': 'abc'}),
            cn('d', 'slider', {'value': 99, 'min': 10, 'max': 5}),
          ]),
        }.cast<String, dynamic>(),
      );
      expect(doc.find('a')!.props, {'value': 3.5, 'min': -10, 'max': 10, 'step': 0.5});
      expect(doc.find('b')!.props, {'max': 5});
      expect(doc.find('c')!.props['value'], 'abc');
      final a = lcSliderOf(doc.find('a')!), b = lcSliderOf(doc.find('b')!), d = lcSliderOf(doc.find('d')!);
      expect((a.value, a.min, a.max, a.step), (3.5, -10, 10, 0.5));
      expect((b.value, b.min, b.max, b.step), (0, 0, 5, 1));
      expect((d.value, d.min, d.max), (11, 10, 11), reason: '最大不比最小大：当成最小 + 1，值夹进去');
      // 存出去再读回来一个字不变
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });

    test('四种导出（没绑定）：网页是 range 输入框，Flutter 是 Slider', () {
      final all = allExportFiles(_plain({'value': 30, 'min': 10, 'max': 60, 'step': 5, 'disabled': true}));
      expect(all['html/index.html'], contains('type="range" min="10" max="60" step="5" disabled value="30"'));
      expect(all['html/style.css'], contains('.lc-slider'));
      expect(all['vue/Slide.vue'], contains('type="range" min="10" max="60" step="5"'));
      expect(all['react/Slide.jsx'], contains('type={"range"} min={"10"} max={"60"} step={"5"} disabled defaultValue={"30"}'));
      final dart = all['flutter/page.dart']!;
      expect(dart, contains('Slider('));
      expect(dart, contains('value: 30'));
      expect(dart, contains('min: 10'));
      expect(dart, contains('max: 60'));
      expect(dart, contains('divisions: 10'));
      expect(dart, contains('onChanged: null'), reason: '禁用');
    });

    test('双向绑定：要数字状态；绑了文字状态会说；Flutter 导出读写状态', () {
      expect(lcCheckBindings(_bound()), isEmpty);
      final wrong = _bound();
      lcSetModel(wrong.find('sl')!, 'off');
      expect(lcCheckBindings(wrong).map((i) => i.message).join(), contains('要绑一个“数字”的状态'));
      final dart = allExportFiles(_bound())['flutter/page.dart']!;
      expect(dart, contains('Slider('));
      expect(dart, contains('.clamp(0, 10).toDouble()'));
      expect(dart, contains('divisions: 5'));
      expect(dart, contains('onChanged: (value) => update('));
    });

    for (final kind in ['html', 'vue', 'react']) {
      test('${_label[kind]}：真编译 0 错误 0 警告', () async {
        for (final doc in [
          _bound(),
          _plain(const {'value': 30}),
        ]) {
          final r = await compileExport('compile_$kind.mjs', exportFilesOf(doc, kind), _entry[kind]!);
          expect(r.errors, isEmpty, reason: r.raw);
          expect(r.warnings, isEmpty, reason: r.raw);
          expect(r.ok, isTrue);
        }
      }, skip: skipWithoutDom);

      test('${_label[kind]}：真跑——拖滑块状态变、状态变滑块跟着走、禁用', () async {
        final r = await runInDom(kind, exportFilesOf(_bound(), kind), _entry[kind]!, _steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, _steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  });
}
