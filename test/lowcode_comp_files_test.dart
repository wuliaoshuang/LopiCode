// 第四轮 B4：用了事件 / 变体 / 自己的状态 / 属性绑定的自定义组件，在 Vue 3 / React 的导出里各出一个组件文件
// （不再摊开进页面）；事件带的数据能在页面上用（快捷动作“把一个状态设成事件带来的值”存的那块积木）。
// 前半（不依赖外部环境）：文件有没有、页面里是不是引用、没用新东西的项目没变。
// 后半（开发机才有环境，找不到明确跳过）：官方编译器真编译 0 错 0 警告，Node + jsdom 真跑。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_expand_live.dart';
import 'package:lopicode/lowcode/component_instance_widgets.dart';
import 'package:lopicode/lowcode/export_comp_files.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/quick_actions.dart';

import 'support/bind_export_files.dart';
import 'support/comp_event_samples.dart';
import 'support/comp_samples.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'Pick.vue', 'react': 'Pick.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

void main() {
  group('组件文件', () {
    test('三种形状：Vue 3 各出一个 .vue，页面里引用、传属性、接事件，不再摊开', () {
      final files = exportFilesOf(compUserDoc([productCardDef(), loginFormDef(), tagBarDef()]), 'vue');
      final comps = [
        for (final k in files.keys)
          if (k.startsWith('components/')) k,
      ]..sort();
      expect(comps, ['components/LcComponent.vue', 'components/LcComponent2.vue', 'components/LcComponent3.vue']);
      final page = files['Shop.vue']!;
      expect(page, contains('import LcComponent from "./components/LcComponent.vue";'));
      expect('<LcComponent '.allMatches(page).length, 2, reason: '两个商品卡片实例都是引用');
      expect(page, isNot(contains('n-p1__buy')), reason: '组件里面的控件不该摊在页面里');
      expect(page, contains('@addCart='));
      expect(page, contains('lcv_kind="hot"'));
      expect(page, contains('v-model:'), reason: '登录表单的双向属性');
      final card = files['components/LcComponent.vue']!;
      expect(card, contains('defineEmits(["addCart"])'));
      expect(card, contains('const liked = ref(false);'), reason: '组件自己的状态');
      expect(card, contains('lcv_kind'));
    });

    test('三种形状：React 各出一个 .jsx（带样式表），页面里引用', () {
      final files = exportFilesOf(compUserDoc([productCardDef(), loginFormDef(), tagBarDef()]), 'react');
      final comps = [
        for (final k in files.keys)
          if (k.startsWith('components/')) k,
      ]..sort();
      expect(comps, [
        'components/LcComponent.css',
        'components/LcComponent.jsx',
        'components/LcComponent2.css',
        'components/LcComponent2.jsx',
        'components/LcComponent3.css',
        'components/LcComponent3.jsx',
      ]);
      final page = files['Shop.jsx']!;
      expect(page, contains('import LcComponent from "./components/LcComponent.jsx";'));
      expect('<LcComponent '.allMatches(page).length, 2);
      expect(page, isNot(contains('n-p1__buy')));
      expect(page, contains('onAddCart={'));
      expect(page, contains('onLcUpdate_'));
      final card = files['components/LcComponent.jsx']!;
      expect(card, contains('onAddCart'));
      expect(card, contains('liked: false'));
    });

    test('多页面共用一份组件文件', () {
      final json = compUserPageJson([productCardDef()]);
      final doc = LcDocument.fromJson(
        {
          ...json,
          'pages': [
            {
              'id': 'pg2',
              'title': 'Other',
              'root': cn('root', 'page', {}, [
                cn(
                  'p9',
                  'component',
                  {'ref': 'c1'},
                  [],
                  {
                    'variant': {'kind': 'hot'},
                  },
                ),
              ]),
            },
          ],
        }.cast<String, dynamic>(),
      );
      for (final kind in ['vue', 'react']) {
        final files = exportFilesOf(doc, kind);
        final ext = kind == 'vue' ? 'vue' : 'jsx';
        expect(
          [
            for (final k in files.keys)
              if (k.startsWith('components/') && k.endsWith('.$ext')) k,
          ],
          ['components/LcComponent.$ext'],
          reason: kind,
        );
        expect(
          [
            for (final e in files.entries)
              if (!e.key.startsWith('components/') && e.value.contains('<LcComponent ')) e.key,
          ].length,
          2,
          reason: '$kind：两页都引用它',
        );
      }
    });

    test('没用新东西的项目：拿回来的就是原文档（导出一个字不变由基线测试守着）', () {
      final doc = LcDocument.fromJson({
        'version': 3,
        'title': 'Old',
        'components': [
          {
            'id': 'c1',
            'name': '老组件',
            'props': [
              {'name': 'title', 'type': 'text', 'default': '标题'},
            ],
            'root': cn('box', 'column', {}, [
              cn(
                't',
                'text',
                {'text': '标题'},
                [],
                {
                  'bind': {'text': 'title'},
                },
              ),
            ]),
          },
        ],
        'root': cn('root', 'page', {}, [
          cn('u1', 'component', {
            'ref': 'c1',
            'values': {'title': '你好'},
          }),
        ]),
      });
      expect(identical(lcFrameworkDoc(doc), doc), isTrue);
    });

    test('定义里直接读了页面的状态：出不了组件文件，照 B2 的做法摊开', () {
      final def = productCardDef();
      final json = compUserPageJson([def]);
      ((def['root']! as Map)['children'] as List).add(
        cn(
          'peek',
          'text',
          {'text': ''},
          [],
          {
            'data': {'text': cFrom('cart')},
          },
        ),
      );
      final doc = LcDocument.fromJson(json.cast<String, dynamic>());
      expect(lcLiveFilesOk(doc), isFalse);
      expect(lcLiveFilesOk(compUserDoc([productCardDef(), loginFormDef(), tagBarDef()])), isTrue);
      for (final kind in ['vue', 'react']) {
        final files = exportFilesOf(doc, kind);
        expect(files.keys.where((k) => k.startsWith('components/')), isEmpty, reason: kind);
        expect(files.values.join(), contains('n-p1__peek'), reason: kind);
      }
    });

    test('纯网页、Flutter：照旧摊开（没有组件文件）', () {
      final all = allExportFiles(compUserDoc([productCardDef()]));
      expect(
        [
          for (final k in all.keys)
            if (k.startsWith('html/') || k.startsWith('flutter/')) k,
        ].where((k) => k.contains('components/')),
        isEmpty,
      );
      expect(all['html/index.html'], contains('n-p1__buy'));
    });
  });

  group('事件带的数据', () {
    test('快捷动作存的积木认得回来；摊开时换成那一项数据的式子', () {
      final b = lcQuickBlock(kLcTakeQuick, 'cur');
      expect(b.op, 'setVar');
      expect(b.args['name'], 'cur');
      expect(b.args['value'], {'e': 'event'});
      expect(lcQuickBlockValue(b, kLcTakeQuick), 'cur');
      expect(lcEventQuickOf([b])?.$1, same(kLcTakeQuick));
      // 别的快捷动作不会把它认错
      expect(
        lcQuickBlockValue(
          LcBlock(
            op: 'setVar',
            args: {
              'name': 'cur',
              'value': {'e': 'text', 'v': ''},
            },
          ),
          kLcTakeQuick,
        ),
        isNull,
      );
      final swapped = lcWithEventData([b], {'e': 'var', 'name': 'step'});
      expect(swapped.single.args['value'], {'e': 'var', 'name': 'step'});
      expect(b.args['value'], {'e': 'event'}, reason: '原来的不动');
      expect(lcWithEventData([b], null).single.args['value'], {'e': 'text', 'v': ''});
    });

    test('事件对象的样子（给页面逻辑的约定）', () {
      expect(kLcEvtJs, contains('lcEvent: name'));
      expect(kLcEvtJs, contains('detail'));
      expect(kLcEvtJs, contains('target: { value:'));
    });

    // 组件里套着组件：里面那个发的事件一层层往外发到页面，带的数据原样带出去。
    for (final kind in ['vue', 'react']) {
      test('${_label[kind]}·组件里套组件：真编译 0 错误 0 警告，里面的事件带着数据传到页面', () async {
        final files = exportFilesOf(compNestedDoc(), kind);
        expect(files.keys.where((k) => k.startsWith('components/') && !k.endsWith('.css')), hasLength(2));
        final c = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
        expect(c.errors, isEmpty, reason: c.raw);
        expect(c.warnings, isEmpty, reason: c.raw);
        final steps = nestedSteps();
        final r = await runInDom(kind, files, _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }

    for (final kind in ['html', 'vue', 'react']) {
      // “重复”里带出的项：只有组件文件的两种导出拿得到。
      final withPick = kind != 'html';
      final plain = [...addButtonSteps(), if (withPick) ...pickBarSteps()];
      final steps = kind == 'html' ? plain : compFileSteps(plain, kCompEventDefs);
      test('${_label[kind]}：真编译 0 错误 0 警告', () async {
        final files = exportFilesOf(compEventDoc(withPick: withPick), kind);
        final r = await compileExport('compile_$kind.mjs', files, _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);

      test('${_label[kind]}：真跑——点组件里的按钮，页面状态变成事件带来的值，界面跟着变', () async {
        final r = await runInDom(kind, exportFilesOf(compEventDoc(withPick: withPick), kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  });
}
