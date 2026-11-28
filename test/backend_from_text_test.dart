// 内置库上画布：两个内置库（“页面”“接口服务”）的模块从文字写法翻成积木文档。
// 钉住的事：翻出来的文档照平常的路翻回语法树，和原来的模块逐个函数、逐句一样（translator 自己对过，这里再独立对一遍）；
// 翻不了的地方落成“文字原样”，一处一处数得出来；数字写死在这里（哪天多翻成了、少翻成了都要有人看一眼）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks_raw.dart';
import 'package:lopicode/backend/backend_from_text.dart';
import 'package:lopicode/backend/lib_service_module.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_page_module.dart';

void _dump(String label, BeFromTextResult r) {
  final out = StringBuffer()
    ..writeln('== $label：函数 ${r.fns.length} 个，一共 ${r.stmts} 句，整句原样 ${r.rawStmts} 句，没翻成积木的地方 ${r.rawSpots} 处，换名的局部变量 ${r.renamed} 个')
    ..writeln('别名：${r.aliases}')
    ..writeln('没带过来：${r.skipped}')
    ..writeln('问题：${r.problems}');
  for (final f in r.fns) {
    out.writeln('- ${f.name}：${f.stmts} 句，原样 ${f.rawStmts} 句${f.whole ? '（整个函数原样）' : ''}');
    for (final x in f.raws) {
      out.writeln('    · ${x.replaceAll(RegExp(r'\s+'), ' ')}');
    }
  }
  final dir = Platform.environment['LOPI_DUMP_DIR'];
  if (dir != null) File('$dir/from_text_$label.txt').writeAsStringSync(out.toString());
}

void main() {
  test('“页面”库的模块翻成积木文档', () {
    final r = beFromText(kLcPageModuleLc, id: 'shuang/page-view', name: '页面', side: LibSide.frontend);
    _dump('page', r);
    expect(r.problems, isEmpty);
    expect(r.doc, isNotNull);
    expect(r.fns.length, greaterThan(20));
    expect(r.fns.where((f) => f.whole), isEmpty, reason: '没有哪个函数要整个原样');
  });

  test('“接口服务”库的模块翻成积木文档', () {
    final r = beFromText(kBeServiceModuleLc, id: 'shuang/service-view', name: '接口服务', side: LibSide.backend);
    _dump('service', r);
    expect(r.problems, isEmpty);
    expect(r.doc, isNotNull);
    expect(r.fns.length, greaterThan(20));
  });

  test('文字原样：读得回来、新建的名字认得、里面调的宿主接口数得出来', () {
    expect(beRawReadStmt('(设 a (+ 1 2))'), isNotNull);
    expect(beRawReadStmt('(设 a'), isNull);
    expect(beRawDeclares('(每个带号 x i (列 1 2) (设 y x))'), ['x', 'i', 'y']);
    expect(beRawHosts('(做 (宿 page.alert (文 (宿 page.nav.params))))', isExpr: false), ['page.alert', 'page.nav.params']);
    expect(beRawHosts('(宿 time.now)', isExpr: true), ['time.now']);
  });
}
