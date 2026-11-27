// 组件事件对接（2026-11-27 中途包）：线 A 的帽子“当〔组件实例〕发出〔事件〕”接上线 B 的**真**组件事件——
// 不再替线 B 发（lowcode_front_emit_test.dart 是替它发的），页面上放的是线 B 的样例组件，点的是组件里面的按钮。
// 三个形状：加量按钮（数据来自组件属性）、可选标签条（数据来自“重复”带出的项）、外壳（组件里套组件，事件一层层往外发）。
// 前半不依赖外部环境；后半（官方编译器真编译、Node＋jsdom 真跑）环境只在开发机上有，找不到就明确跳过。不联网。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/front_emit_bridge.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/comp_event_samples.dart';
import 'support/comp_samples.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';

J _emit(String name) => ex(pg('emitData'), {'name': tx(name)});

/// 页面走新的页面逻辑。[pick]＝放可选标签条；[shell]＝放外壳。
/// 帽子：a5 发“要加”→ got 设成带来的 n；a7 发“要加”→ got 加上带来的 n；标签条发“选了一个”→ cur 设成带来的 tag；外壳发“里面要加”→ got 设成带来的 n。
LcDocument _doc({bool pick = false, bool shell = false}) {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'id': 'home',
      'title': 'Pick',
      'components': [if (pick) pickBarDef(), addButtonDef(), if (shell) shellDef()],
      'root': cn('root', 'page', {}, [
        if (pick)
          cn(
            'tags',
            'component',
            {'ref': 'c5'},
            [],
            {
              'data': {'tags': cFrom('tagList'), 'picked': cFrom('cur')},
            },
          ),
        cn(
          'curText',
          'text',
          {'text': ''},
          [],
          {
            'data': {
              'text': cExpr(cJoin([cText('现在选的：'), cVar('cur')])),
            },
          },
        ),
        for (final (id, step) in [('a5', 5), ('a7', 7)])
          cn(id, 'component', {
            'ref': 'c6',
            'values': {'step': step},
          }),
        if (shell) cn('sh', 'component', {'ref': 'c7'}),
        cn(
          'gotText',
          'text',
          {'text': ''},
          [],
          {
            'data': {
              'text': cExpr(cJoin([cText('拿到 '), cVar('got')])),
            },
          },
        ),
      ]),
      'logic': {
        'variables': [
          {
            'name': 'tagList',
            'type': 'list',
            'initial': ['水果', '蔬菜', '零食'],
          },
          {'name': 'cur', 'type': 'text', 'initial': '蔬菜'},
          {'name': 'got', 'type': 'number', 'initial': 0},
        ],
        'front': frontDoc(
          hats: [
            hat('h1', 'onEmit', [stSet('got', asNum(_emit('n')))], args: {'node': 'a5', 'event': 'add'}),
            hat('h2', 'onEmit', [stSet('got', op2('+', asNum(stGet('got')), asNum(_emit('n'))))], args: {'node': 'a7', 'event': 'add'}),
            if (pick)
              hat(
                'h3',
                'onEmit',
                [
                  stSet('cur', ex(pg('oldText'), {'value': _emit('tag')})),
                ],
                args: {'node': 'tags', 'event': 'pick'},
              ),
            if (shell) hat('h4', 'onEmit', [stSet('got', asNum(_emit('n')))], args: {'node': 'sh', 'event': 'bump'}),
          ],
        ),
      },
    }),
  );
  lcFrontStore(doc.logic, lcFrontOf(doc.logic)!);
  return doc;
}

const Map<String, String> _defs = {'tags': 'c5', 'a5': 'c6', 'a7': 'c6'};

/// 加量按钮：三组步骤（a5 是“设成”，a7 是“加上”）。
List<CompSteps> _addSteps() => [
  [
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 0'},
    {'op': 'click', 'sel': '.n-a5__go'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 5'},
  ],
  [
    {'op': 'click', 'sel': '.n-a7__go'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 7'},
    {'op': 'click', 'sel': '.n-a7__go'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 14'},
    {'op': 'click', 'sel': '.n-a5__go'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 5'},
  ],
  [
    {'op': 'click', 'sel': '.n-a5__go'},
    {'op': 'click', 'sel': '.n-a7__go'},
    {'op': 'click', 'sel': '.n-a7__go'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 19'},
  ],
];

/// 外壳：点里面那个加量按钮（step 写死 9）。
List<CompSteps> _shellSteps() => [
  [
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 0'},
    {'op': 'click', 'sel': '.n-sh button'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 9'},
    {'op': 'click', 'sel': '.n-a7__go'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 16'},
    {'op': 'click', 'sel': '.n-sh button'},
    {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 9'},
  ],
];

List<CompSteps> _for(String kind, List<CompSteps> sets) => kind == 'html' ? sets : [for (final s in sets) compFileSteps(s, _defs)];

void main() {
  group('不真跑', () {
    test('Vue 3 / React：组件还是单独的组件文件；页面上实例的事件接一个处理函数，里面把事件带的 detail 转给页面宿主', () {
      for (final kind in ['vue', 'react']) {
        final files = exportFilesOf(_doc(pick: true, shell: true), kind);
        final all = files.values.join('\n');
        expect(files.keys.where((k) => k.startsWith('components/') && !k.endsWith('.css')), hasLength(3), reason: kind);
        for (final (inst, event) in [('a5', 'add'), ('a7', 'add'), ('tags', 'pick'), ('sh', 'bump')]) {
          expect(all, contains('lcPage.emit("$inst", "emit:$event", { lcData: (event && event.detail) || {} });'), reason: '$kind $inst');
        }
        expect(all, contains(kind == 'vue' ? '@add=' : 'onAdd={'), reason: kind);
        expect(all, isNot(contains('这一页的逻辑没有导出')), reason: kind);
      }
    });

    test('纯网页：实例摊开；组件里那个按钮的点击转成“实例发出事件”，带的数据当场算（属性写死的就是那个值）', () {
      final files = exportFilesOf(_doc(shell: true), 'html');
      final all = files.values.join('\n');
      expect(all, contains('function lcProgram(lc, lcHost)'), reason: '摊开以后还是新的页面逻辑（以前摊开时把它丢了）');
      expect(all, contains('lcPage.emit("a5", "emit:add", { lcData: { "n": 5 } });'));
      expect(all, contains('lcPage.emit("a7", "emit:add", { lcData: { "n": 7 } });'));
      expect(all, contains('lcPage.emit("sh", "emit:bump", { lcData: { "n": 9 } });'), reason: '套着的：里面的事件接着往外发到页面上的实例');
      expect(all, contains('lcOn("a5__go", "click",'));
    });

    test('没接帽子的事件不落处理；实例上旧的 on 在新逻辑的页面里不作数；原文档不被改动', () {
      final doc = _doc();
      final before = jsonEncode(doc.toJson());
      // 只留 a5 的帽子
      final front = lcFrontOf(doc.logic)!.clone();
      front.hats.removeWhere((h) => h.id != 'h1');
      lcFrontStore(doc.logic, front);
      expect(lcFrontEmitHats(doc.logic), {
        'a5': {'add'},
      });
      for (final kind in ['html', 'vue', 'react']) {
        final all = exportFilesOf(doc, kind).values.join('\n');
        expect('lcPage.emit("a5", "emit:add"'.allMatches(all), hasLength(1), reason: kind);
        expect(all, isNot(contains('lcPage.emit("a7"')), reason: kind);
      }
      expect(jsonEncode(doc.toJson()), isNot(contains(kLcEmitBridgeOp)), reason: '记号只活在给导出看的文档里');
      expect(jsonEncode(_doc().toJson()), before);
      // 旧的页面逻辑：没有帽子，这里什么都不做
      expect(lcFrontEmitHats(compEventDoc().logic), isEmpty);
      expect(exportFilesOf(compEventDoc(), 'vue').values.join(), isNot(contains('emit:')));
    });
  });

  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】组件事件对接的真编译 / 真跑：$skipWithoutDom');
  }
  for (final kind in kFrontKinds.keys) {
    test('${kFrontKinds[kind]}·加量按钮：真编译 0 错 0 警告；点组件里的按钮 → 帽子跑 → 页面状态变 → 界面跟着变（三组步骤）', () => frontCheckAll(kind, _doc(), _for(kind, _addSteps())), skip: skipWithoutDom);
    test('${kFrontKinds[kind]}·外壳（组件里套组件）：里面的事件带着数据一层层发到页面的帽子', () => frontCheckAll(kind, _doc(shell: true), _for(kind, _shellSteps())), skip: skipWithoutDom);
  }
  // “重复”带出的项：只有组件文件的两种导出拿得到（纯网页摊开以后处理里拿不到，是线 B 那边已知的限制）。
  for (final kind in ['vue', 'react']) {
    test('${kFrontKinds[kind]}·可选标签条：点第几个标签，页面状态就变成那一项的文字，选中的样子跟着变', () => frontCheckAll(kind, _doc(pick: true), [compFileSteps(pickBarSteps(), _defs)]), skip: skipWithoutDom);
  }
  test('React 开着 StrictMode：加量按钮', () => frontCheckAll('react', _doc(), _for('react', _addSteps()), strict: true), skip: skipWithoutDom);
}
