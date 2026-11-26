// 格式第 3 版加的那批属性（按钮图标 / 禁用，图片说明文字，输入框类型 / 默认值 / 标签 / 必填 / 禁用）：
// 四种导出都写出来了、写得对；节点名字 / 锁定 / 编辑器里隐藏不影响导出；导出的 Flutter 代码能编译、能渲染。
// Vue / React 的真编译在 test/dev_webdev_compile_test.dart（样本同一份）。
import 'dart:io';

// 导出的代码用的是 package:flutter/material.dart，这里必须用同一套。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/icon_set.dart';
import 'package:lopicode/lowcode/icon_set_widgets.dart';
import 'package:lopicode/lowcode/model.dart';

import 'generated/v3_page.dart';
import 'support/v3_sample.dart';

String _all(LcFrameworkExport e) => e.files.map((f) => f.content).join('\n');

void main() {
  group('内置图标', () {
    test('清单和“名字 → Flutter 图标”的对照一一对应；名字不重复、合页面文件的规矩', () {
      expect(lcIcons.map((i) => i.name).toSet(), lcIconData.keys.toSet());
      expect(lcIcons.map((i) => i.name).toSet().length, lcIcons.length);
      for (final i in lcIcons) {
        expect(RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(i.name), isTrue, reason: i.name);
        expect(i.label, isNotEmpty);
        expect(RegExp(r'^[MmLlHhVvCcSsQqTtAaZz0-9 .,\-]+$').hasMatch(i.path), isTrue, reason: '${i.name} 的路径里有不该有的字符');
        expect(lcIconByName(i.name), same(i));
      }
      expect(lcIconByName('no_such_icon'), isNull);
      expect(lcIconByName(null), isNull);
    });
  });

  group('网页导出', () {
    final html = exportHtml(v3Sample()).html;
    final css = exportHtml(v3Sample()).css;

    test('按钮：图标是内嵌的 SVG；只有图标没有字的不留右边距；禁用写 disabled', () {
      expect(html, contains('<svg class="lc-icon" viewBox="0 0 24 24" aria-hidden="true">'));
      expect(html, contains('<svg class="lc-icon lc-icon-solo"'));
      expect(RegExp(r'<button[^>]*\bdisabled\b').allMatches(html).length, 2);
      expect(css, contains('.lc-icon {'));
      expect(css, contains('.lc-button:disabled, .lc-input:disabled'));
    });

    test('图片：说明文字进 alt，里面的引号和尖括号都转义了；没放图的占位块带 aria-label', () {
      expect(html, contains('alt="一只 &quot;猫&quot; &lt;在&gt; 睡觉"'));
      expect(html, contains('aria-label="还没放图"'));
      expect(html, isNot(contains('<在>')));
    });

    test('输入框：类型、默认值、必填、禁用；带标签的外面包一层 label，必填的标签后面有星号', () {
      expect(html, contains('type="tel"'));
      expect(html, contains('type="password"'));
      expect(html, contains('type="number"'));
      expect(html, contains('type="email"'));
      expect(html, contains('value="138&quot;00"'));
      expect(RegExp(r'<input[^>]*\brequired\b').allMatches(html).length, 2);
      expect(RegExp(r'<input[^>]*\bdisabled\b').allMatches(html).length, 1);
      expect(RegExp(r'<label class="lc-field ').allMatches(html).length, 2);
      expect(html, contains('账号 &lt;b&gt;&amp;'));
      expect(html, contains('lc-required'));
      expect(css, contains('.lc-field {'));
      expect(css, contains('.lc-required {'));
    });

    test('名字、锁定、编辑器里隐藏不影响导出：隐藏的照样导出，名字不出现在网页里', () {
      expect(html, contains('placeholder="邮箱"'));
      expect(html, isNot(contains('头图')));
      expect(html, isNot(contains('账号框')));
      final bare = v3Sample();
      void strip(LcNode n) {
        n
          ..name = ''
          ..locked = false
          ..hidden = false;
        n.children.forEach(strip);
      }

      strip(bare.root);
      expect(exportHtml(bare).html, html);
      expect(exportHtml(bare).css, css);
      expect(exportDart(bare), exportDart(v3Sample()));
      expect(_all(exportVue(bare)), _all(exportVue(v3Sample())));
      expect(_all(exportReact(bare)), _all(exportReact(v3Sample())));
    });
  });

  group('Vue / React 导出', () {
    test('Vue：图标、禁用、说明文字、类型、默认值、标签都在', () {
      final out = _all(exportVue(v3Sample()));
      expect(out, contains('<svg class="lc-icon"'));
      expect(RegExp(r'<button[^>]*\bdisabled\b').allMatches(out).length, 2);
      expect(out, contains('alt="一只 &quot;猫&quot; &lt;在&gt; 睡觉"'));
      expect(out, contains('type="password"'));
      expect(out, contains('value="138&quot;00"'));
      expect(out, contains('<label class="lc-field '));
      expect(out, contains('.lc-icon {'));
    });

    test('React：属性名用 JSX 的写法（className、defaultValue），默认值不把输入框锁死', () {
      final out = _all(exportReact(v3Sample()));
      expect(out, contains('<svg className="lc-icon"'));
      expect(out, isNot(contains('<svg class=')));
      expect(out, contains('defaultValue='));
      expect(RegExp(r'<input[^>]*\svalue=').hasMatch(out), isFalse, reason: 'React 里写死 value 的输入框打不了字');
      expect(RegExp(r'<button[^>]*\bdisabled\b').allMatches(out).length, 2);
      expect(out, contains('type="tel"'));
      expect(out, contains('<label className="lc-field '));
    });
  });

  group('Flutter 导出', () {
    test('检入的样本和导出器当前的输出一致', () {
      expect(File('test/generated/v3_page.dart').readAsStringSync(), exportDart(v3Sample(), className: 'V3Page'), reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
    });

    test('写的是同名的 Icons.xxx、禁用、说明文字、密码、键盘类型、标签', () {
      final code = exportDart(v3Sample());
      expect(code, contains('Icons.send'));
      expect(code, contains('Icons.delete'));
      expect(code, contains('onPressed: null'));
      expect(code, contains('semanticLabel:'));
      expect(code, contains('obscureText: true'));
      expect(code, contains('TextInputType.phone'));
      expect(code, contains('TextInputType.number'));
      expect(code, contains('TextInputType.emailAddress'));
      expect(code, contains('enabled: false'));
      expect(code, contains('labelText:'));
      expect(code, contains('initialValue:'));
    });

    testWidgets('导出的页面能在 390 宽的屏幕上渲染：没有溢出；禁用的按钮点不了；默认值填着', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // 样本里有一张网络图片：测试环境不联网，加载失败是预期的，不算页面出错。
      await tester.pumpWidget(const MaterialApp(home: V3Page()));
      await tester.pump();
      final e = tester.takeException();
      expect(e == null || e is NetworkImageLoadException, isTrue, reason: '$e');
      expect(find.text('发送'), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.text('138"00'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.textContaining('账号 <b>&'), findsOneWidget);
      final off = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('不能点'), matching: find.bySubtype<ButtonStyleButton>()).first);
      expect(off.onPressed, isNull);
    });
  });
}
