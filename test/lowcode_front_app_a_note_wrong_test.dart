// 小应用甲组·“笔记”：故意把类型放错的，在检查阶段被拦下。
// 拦下＝导出前的检查数得出错误；纯网页 / Vue 3 / React 三种产物里这一页的逻辑都不出。
// 先放一条写对的作对照：同一个三页应用，只把详情页那一处改错，就拦。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/front_app_a_kit.dart';
import 'support/front_app_a_note.dart';
import 'support/page_front_samples.dart';

const String _base = 'http://127.0.0.1:1';

/// 三页应用，详情页换成 [front]，并翻到详情页。
LcDocument _app(J front) {
  final pages = notePages(_base);
  final doc = appDoc([pages[0], pages[1], noteEditPage(front)]);
  doc.openPageAt(2);
  return doc;
}

void _blocked(J front, String why) {
  final doc = _app(front);
  final issues = appIssues(doc);
  expect(lcLogicErrorCount(doc), greaterThan(0), reason: '$why：没拦住');
  expect(issues.where((x) => x.startsWith('edit')), isNotEmpty);
  // ignore: avoid_print
  print('$why → ${issues.where((x) => x.startsWith('edit')).join('；')}');
  for (final kind in const ['html', 'vue', 'react']) {
    final all = exportFilesOf(doc, kind).values.join('\n');
    expect(all, contains('这一页的逻辑没有导出'), reason: kind);
  }
}

J _edit({List<J>? saveBody, J? saveFn, List<J> extra = const []}) => noteEditFront(_base, saveBody: saveBody, saveFn: saveFn, mountedExtra: extra);
J _rec(List<J> fields) => ex('recNew', {'type': '笔记', 'fields': fields});

void main() {
  test('对照：写对的不拦，三种都出逻辑', () {
    final doc = _app(_edit());
    expect(appIssues(doc), isEmpty);
    for (final kind in const ['html', 'vue', 'react']) {
      expect(exportFilesOf(doc, kind).values.join('\n'), isNot(contains('这一页的逻辑没有导出')), reason: kind);
    }
  });

  test('新建“笔记”记录：编号（整数）给了一段字', () {
    _blocked(
      _edit(
        extra: [
          konst('x', _rec([pair('编号', tx('一')), pair('标题', tx('a')), pair('正文', tx('b'))])),
        ],
      ),
      '编号给了字',
    );
  });

  test('新建“笔记”记录：少给一个字段（正文）', () {
    _blocked(
      _edit(
        extra: [
          konst('x', _rec([pair('编号', nm(1)), pair('标题', tx('a'))])),
        ],
      ),
      '少给字段',
    );
  });

  test('新建“草稿”：标题（文字）给了一个数', () {
    _blocked(_edit(saveBody: noteSaveBody(draft: newObj('草稿', [nm(1), valOf('ed_body')]))), '创建时给错类型');
  });

  test('叫“存上”：要“草稿”的地方给了“笔记”记录', () {
    _blocked(
      _edit(
        saveBody: noteSaveBody(
          saveCall: call('f3', {
            'id': param('id'),
            'd': call('f2', {'id': param('id')}),
          }),
        ),
      ),
      '草稿的位置给了笔记',
    );
  });

  test('叫“存上”：编号（文字）给了一个数', () {
    _blocked(_edit(saveBody: noteSaveBody(saveCall: call('f3', {'id': nm(7), 'd': vr('d')}))), '编号给了数');
  });

  test('取“笔记”里没有的字段（作者）', () {
    _blocked(_edit(saveBody: noteSaveBody(shown: getF(vr('n'), '作者'))), '没有的字段');
  });

  test('叫“草稿”没有的方法', () {
    _blocked(
      _edit(
        saveBody: [
          konst('d', newObj('草稿', [valOf('ed_title'), valOf('ed_body')])),
          show('ed_msg', send(vr('d'), '发表')),
        ],
      ),
      '没有的方法',
    );
  });

  // 现状钉在这里（不算在“被拦下”的条数里；要不要拦等定，见汇报）：整数和文字用“等于”去比，检查不拦，运行时就是“不相等”。
  test('现状：“字数”（整数）和一段字用“等于”比，检查不拦', () {
    final doc = _app(
      _edit(
        saveBody: [
          konst('d', newObj('草稿', [valOf('ed_title'), valOf('ed_body')])),
          iff(op2('==', send(vr('d'), '字数'), tx('三')), [show('ed_msg', tx('三'))], noElse: true),
        ],
      ),
    );
    expect(appIssues(doc), isEmpty);
  });

  test('“存上”说好交回“笔记”，却交回一段字', () {
    _blocked(_edit(saveFn: tfn('f3', '存上', [tpar('id', tText), tpar('d', tRef('草稿'))], [ret(tx('好了'))], returns: tRef('笔记'))), '结果类型对不上');
  });

  test('错误的“状态码”（整数）直接放了请求给的状态码（数，没取整）', () {
    _blocked(_edit(saveFn: noteSaveFn(_base, code: lx('http', 'status', {'res': vr('res')}))), '整数的位置给了没取整的数');
  });

  test('“出错时”接一种没有的错误', () {
    _blocked(_edit(saveBody: noteSaveBody(catchKind: '没这种错')), '没有的错误种类');
  });

  test('改记录的字段（记录建好以后不能改）', () {
    _blocked(_edit(extra: [setF(vr('n'), '标题', tx('改'))]), '改记录');
  });
}
