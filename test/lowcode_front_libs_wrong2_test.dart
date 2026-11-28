// 自带前端库第二批（路由、表单校验、国际化、动画）：故意写错的在检查阶段被拦下（每个库至少三条）。
// 拦下＝导出前的检查数得出错误；纯网页 / Vue 3 / React 三种产物里这一页的逻辑都不出。
// 每组先放一条写对的作对照：同一个页面，只把那一处改对，就不拦。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/front_libs_samples.dart';
import 'support/page_front_samples.dart';

LcDocument _page(List<String> libs, List<J> body, {List<J> hats = const []}) =>
    frontPage([btn('b1', '点'), txt('t1')], [numVar('n')], frontDoc(uses: [for (final l in libs) useLib(l)], hats: [onClick('h1', 'b1', body), ...hats]));

void _blocked(LcDocument doc) {
  expect(lcLogicErrorCount(doc), greaterThan(0));
  for (final kind in const ['html', 'vue', 'react']) {
    final all = exportFilesOf(doc, kind).values.join('\n');
    expect(all, contains('这一页的逻辑没有导出'), reason: kind);
    expect(all, isNot(contains('function lcProgram(lc, lcHost)')), reason: kind);
  }
}

void _fine(LcDocument doc) {
  final front = lcFrontOf(doc.logic)!;
  expect(lcLogicErrorCount(doc), 0, reason: [...backendErrors(front).map((i) => i.message), ...lcFrontProgram(front).problems].join('；'));
  for (final kind in const ['html', 'vue', 'react']) {
    expect(exportFilesOf(doc, kind).values.join('\n'), contains('function lcProgram(lc, lcHost)'), reason: kind);
  }
}

J _x(String lib, String id, [J args = const {}]) => ex(fl(lib, id), args);
J _b(String lib, String id, [J args = const {}, List<J> body = const []]) => blk(fl(lib, id), args, body);

/// 一组：一条写对的＋几条写错的＋“没用上这个库”。
void _group(String name, String lib, List<J> right, Map<String, List<J>> wrong) {
  group(name, () {
    test('对照：写对的不拦', () => _fine(_page([lib], right)));
    for (final w in wrong.entries) {
      test(w.key, () => _blocked(_page([lib], w.value)));
    }
    test('没在“积木库…”里用上这个库就拖了它的积木', () => _blocked(_page(const [], right)));
  });
}

void main() {
  _group(
    '路由',
    'router',
    [
      _b('router', 'go', {'path': tx('/a')}),
    ],
    {
      '去的路径填了数': [
        _b('router', 'go', {'path': nm(1)}),
      ],
      '路由的名字填了数': [
        _b('router', 'route', {'pattern': tx('/a'), 'name': nm(1)}),
      ],
      '“新的路径”用在“当路由变了”外面': [show('t1', _x('router', 'newPath'))],
      '路由参数的名字填了列表': [
        show(
          't1',
          _x('router', 'param', {
            'name': ls([tx('id')]),
          }),
        ),
      ],
    },
  );

  _group(
    '表单校验',
    'form',
    [
      _b('form', 'rules', {
        'form': tx('注册'),
        'field': tx('名字'),
        'rules': ls([
          _x('form', 'required', {'msg': tx('')}),
        ]),
      }),
    ],
    {
      '规则的列表里放了一段字': [
        _b('form', 'rules', {
          'form': tx('注册'),
          'field': tx('名字'),
          'rules': ls([tx('必填')]),
        }),
      ],
      '最少几个字填了一段字': [
        _b('form', 'rules', {
          'form': tx('注册'),
          'field': tx('名字'),
          'rules': ls([
            _x('form', 'minLen', {'n': tx('两'), 'msg': tx('')}),
          ]),
        }),
      ],
      '“这一格不对”用在“自己的规则”外面': [
        _b('form', 'fail', {'msg': tx('不行')}),
      ],
      '“要查的值”用在“自己的规则”外面': [show('t1', toText(_x('form', 'value')))],
      '查全部填的不是字典': [
        iff(_x('form', 'checkAll', {'form': tx('注册'), 'values': tx('名字')}), [show('t1', tx('好'))]),
      ],
    },
  );

  _group(
    '国际化',
    'i18n',
    [
      show('t1', _x('i18n', 't', {'key': tx('欢迎')})),
    ],
    {
      '语言表填了一段字': [
        _b('i18n', 'table', {'lang': tx('中文'), 'table': tx('欢迎＝你好')}),
      ],
      '换成的语言填了数': [
        _b('i18n', 'use', {'lang': nm(1)}),
      ],
      '“新的语言”用在“当语言变了”外面': [show('t1', _x('i18n', 'newLang'))],
      '留几位小数填了一段字': [
        show('t1', _x('i18n', 'group', {'value': nm(1234), 'digits': tx('两位')})),
      ],
    },
  );

  _group(
    '动画',
    'anim',
    [
      _b('anim', 'tween', {'state': tx('n'), 'to': nm(100), 'ms': nm(200), 'ease': '匀速'}),
    ],
    {
      '变到的数填了一段字': [
        _b('anim', 'tween', {'state': tx('n'), 'to': tx('很大'), 'ms': nm(200), 'ease': '匀速'}),
      ],
      '毫秒数填了一段字': [
        _b('anim', 'tween', {'state': tx('n'), 'to': nm(100), 'ms': tx('很快'), 'ease': '匀速'}),
      ],
      '状态的名字填了数': [
        _b('anim', 'stop', {'state': nm(1)}),
      ],
      '“走到”填了一段字': [
        show('t1', toText(_x('anim', 'mix', {'from': nm(0), 'to': nm(1), 't': tx('一半')}))),
      ],
    },
  );
}
