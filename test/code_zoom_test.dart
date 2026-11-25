// 代码区域的语法高亮 + 双指捏合缩放（2026-11-25 霜霜：代码区域没有高亮、不能缩放）。
// 覆盖：语言判断、各语言真的上了色、字号状态（默认 / 范围 / 坏数据 / 存盘）、
// 文件编辑器、“看代码”面板、原始 CSS 输入框、设置页里的代码字号。390×844，浅色 + 深色。
//   LOPI_SHOTS=1 flutter test test/code_zoom_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_block_host.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/lowcode/logic_block_host.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_css_sheet.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/templates/code_starters.dart';
import 'package:lopicode/ui/code_editor.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:lopicode/ui/code_langs.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Finder k(String key) => find.byKey(Key(key));

/// 一段文字片段里用到了几种颜色（不算 null）。
Set<Color> colorsOf(InlineSpan span) {
  final out = <Color>{};
  span.visitChildren((s) {
    final c = s.style?.color;
    if (c != null && s is TextSpan && (s.text?.isNotEmpty ?? false)) out.add(c);
    return true;
  });
  return out;
}

const goCode = '''package main

import (
	"fmt"
	"net/http"
)

// 入口
func main() {
	http.HandleFunc("/hello", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "你好 %d", 42)
	})
	http.ListenAndServe(":8080", nil)
}
''';

/// 每种语言一小段像样的代码：上色后至少要有两种颜色。
const samples = <String, String>{
  'html': '<div class="a"><!-- c --><p>hi</p></div>',
  'vue': '<template><p class="a">{{ n }}</p></template>',
  'css': '.a { color: red; margin: 8px 4px; }',
  'scss': r'$c: red; .a { .b { color: $c; } }',
  'less': '@c: red; .a { .b { color: @c; } }',
  'js': 'function f(a) { return "x" + 1; } // c',
  'ts': 'const n: number = 1; function f(a: string): void {}',
  'json': '{"a": 1, "b": "x", "c": true}',
  'dart': 'void main() { final x = "a"; print(1); } // c',
  'md': '# 标题\n\n- 一条 `code`\n\n**粗**',
  'yaml': 'name: x\non:\n  push: true # c\n',
  'sh': '#!/bin/sh\nif [ -f a ]; then echo "x"; fi',
  'kotlin': 'fun main() { val x = "a"; println(1) } // c',
  'python': 'def f(a):\n    return "x" + str(1)  # c\n',
  'go': goCode,
  'java': 'public class Main { public static void main(String[] a) { int x = 1; String s = "x"; } } // c',
  'php': '<?php\nfunction f(\$a) { return "x" . 1; } // c\n',
  'csharp': 'public class A { static void Main() { var s = "x"; int n = 1; } } // c',
  'rust': 'fn main() { let s = "x"; println!("{}", 1); } // c',
  'ruby': 'def f(a)\n  puts "x" + 1.to_s # c\nend\n',
  'c': '#include <stdio.h>\nint main(void) { printf("x %d", 1); return 0; } /* c */',
  'cpp': '#include <string>\nclass A { public: int f() { return 1; } }; // c',
  'sql': "SELECT id, name FROM users WHERE id = 1 AND name = 'x'; -- c",
  'ini': '[core]\nname = "x"\nport = 8080 ; c\n',
  'properties': 'a.b=1\n# c\nname=x\n',
  'dockerfile': 'FROM node:24\n# c\nRUN npm ci\nCMD ["node", "server.js"]\n',
  'gradle': 'plugins { id "java" }\ndependencies { implementation "a:b:1" } // c',
  'groovy': 'def f(a) { return "x" + 1 } // c',
  'swift': 'func f(a: Int) -> String { let s = "x"; return s } // c',
  'objectivec': '@interface A : NSObject\n- (void)f;\n@end // c',
  'lua': 'local function f(a) return "x" .. 1 end -- c',
  'perl': 'sub f { my \$a = shift; return "x" . 1; } # c',
  'r': 'f <- function(a) { paste("x", 1) } # c',
  'scala': 'object A { def f(a: Int): String = "x" } // c',
  'makefile': 'all: main.o\n\tgcc -o a main.o # c\n',
  'cmake': 'cmake_minimum_required(VERSION 3.22)\nproject(a) # c\n',
  'diff': '--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n',
  'powershell': 'function F(\$a) { Write-Host "x" } # c',
  'bat': '@echo off\nrem c\nset A=1\nif "%A%"=="1" echo x\n',
  'graphql': 'query { user(id: 1) { name } } # c',
  'protobuf': 'syntax = "proto3";\nmessage A { string name = 1; } // c',
  'nginx': 'server { listen 80; location / { return 200 "x"; } } # c',
  'haskell': 'module Main where\nmain :: IO ()\nmain = putStrLn "x" -- c',
  'elixir': 'defmodule A do\n  def f(a), do: "x" # c\nend',
  'erlang': '-module(a).\nf(A) -> "x". % c',
  'clojure': '(defn f [a] (str "x" 1)) ; c',
  'julia': 'function f(a)\n  return "x" * string(1) # c\nend',
  'fsharp': 'let f a = printfn "x %d" 1 // c',
  'vbnet': 'Module A\n  Sub Main()\n    Dim s As String = "x" \' c\n  End Sub\nEnd Module',
  'ocaml': 'let f a = print_string "x" (* c *)',
  'nim': 'proc f(a: int): string =\n  result = "x" # c',
  'latex': '\\documentclass{article}\n\\begin{document}\nx % c\n\\end{document}',
  'delphi': "program A;\nbegin\n  WriteLn('x'); // c\nend.",
  'lisp': '(defun f (a) (format t "x")) ; c',
  'scheme': '(define (f a) (display "x")) ; c',
  'elm': 'module Main exposing (main)\nf : Int -> String\nf a = "x" -- c',
  'crystal': 'def f(a : Int32)\n  puts "x" # c\nend',
  'coffeescript': 'f = (a) -> "x" + 1 # c',
  'stylus': '.a\n  color red // c\n  margin 8px',
  'handlebars': '<p>{{#if a}}{{name}}{{/if}}</p>',
  'twig': '{% if a %}<p>{{ name|upper }}</p>{% endif %}',
  'erb': '<p><%= name %></p><% if a %>x<% end %>',
  'haml': '%div.a\n  %p= name\n  -# c',
  'django': '{% if a %}<p>{{ name|upper }}</p>{% endif %}{# c #}',
  'nix': '{ pkgs ? import <nixpkgs> {} }: pkgs.mkShell { name = "x"; } # c',
  'vim': 'function! F(a)\n  echo "x"\nendfunction " c',
  'tcl': 'proc f {a} { puts "x" } ;# c',
  'awk': 'BEGIN { x = 1 } /a/ { print "x" } # c',
  'http': 'GET /hello HTTP/1.1\nHost: example.com\nAccept: */*\n',
  'apache': '<VirtualHost *:80>\n  ServerName x # c\n  RewriteEngine On\n</VirtualHost>',
  'qml': 'import QtQuick 2.0\nRectangle { width: 100; color: "red" } // c',
  'arduino': 'void setup() { pinMode(13, OUTPUT); } // c\nvoid loop() { delay(1000); }',
  'wasm': '(module (func \$f (param i32) (result i32) local.get 0)) ;; c',
  'verilog': 'module a(input clk, output reg q); always @(posedge clk) q <= 1; endmodule // c',
  'vhdl': 'entity a is port (clk : in std_logic); end a; -- c',
  'fortran': "program a\n  print *, 'x' ! c\nend program a",
  'thrift': 'struct A { 1: string name } // c\nservice S { void f() }',
  'prolog': 'f(X) :- X > 1, write("x"). % c',
  'pgsql': "SELECT id FROM users WHERE name = 'x'; -- c",
  'glsl': 'void main() { gl_FragColor = vec4(1.0); } // c',
  'x86asm': 'section .text\nglobal _start\n_start: mov eax, 1 ; c',
  'haxe': 'class A { static function main() { trace("x"); } } // c',
  'd': 'import std.stdio; void main() { writeln("x"); } // c',
  'vala': 'class A : Object { public void f() { print("x"); } } // c',
  'dts': '/dts-v1/;\n/ { model = "x"; a@0 { reg = <0>; }; }; // c',
  'llvm': 'define i32 @f(i32 %a) {\n  ret i32 %a ; c\n}',
  'smali': '.class public LA;\n.method public f()V\n  return-void # c\n.end method',
  'puppet': 'class a { file { "/x": ensure => present } } # c',
  'asciidoc': '= 标题\n\n* 一条 `code`\n\n*粗*',
  'matlab': "function y = f(a)\n  y = 'x'; % c\nend",
};

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('语言判断（单一入口 CodeHighlighter）', () {
    test('后端模板 / 积木会生成的语言和常见配置文件都认得', () {
      const want = {
        'main.go': 'go',
        'Main.java': 'java',
        'index.php': 'php',
        'Program.cs': 'csharp',
        'main.rs': 'rust',
        'app.rb': 'ruby',
        'a.c': 'c',
        'a.h': 'c',
        'a.cpp': 'cpp',
        'a.hpp': 'cpp',
        'q.sql': 'sql',
        'pom.xml': 'html',
        'Cargo.toml': 'ini',
        'Dockerfile': 'dockerfile',
        'api/Dockerfile': 'dockerfile',
        'Dockerfile.prod': 'dockerfile',
        'build.gradle': 'gradle',
        'build.gradle.kts': 'kotlin',
        'Makefile': 'makefile',
        'Gemfile': 'ruby',
        'a.swift': 'swift',
        'a.lua': 'lua',
        'server.js': 'js',
        'server.py': 'python',
        'main.dart': 'dart',
        'a.proto': 'protobuf',
        '.gitignore': 'ini',
        r'C:\proj\Main.java': 'java',
        'README': 'text',
        'a.bin': 'text',
      };
      for (final e in want.entries) {
        expect(CodeHighlighter.languageFor(e.key), e.value, reason: e.key);
      }
    });

    test('积木“看代码”按宿主给的文件名判断：页面逻辑是 JS，后端每种语言的入口文件都有高亮规则', () {
      final logic = LogicBlockHost(doc: LcDocument.starter('样本'), onEdit: (change) {});
      expect(CodeHighlighter.languageFor(logic.codeFileName), 'js');
      const want = {'node': 'js', 'python': 'python', 'go': 'go', 'java': 'java', 'php': 'php'};
      expect({for (final t in backendTargets) t.id}, want.keys.toSet(), reason: '加了后端语言要在这里补一行');
      for (final t in backendTargets) {
        final host = BeBlockHost(doc: backendStarterDocument('样本')..language = t.id);
        expect(CodeHighlighter.languageFor(host.codeFileName), want[t.id], reason: t.id);
        expect(highlightModeFor(host.codeFileName), isNotNull, reason: t.id);
      }
      // 没有生成器的语言：不高亮，不报错。
      expect(CodeHighlighter.languageFor((BeBlockHost(doc: backendStarterDocument('样本')..language = 'cobol')).codeFileName), 'text');
    });

    test('纯代码模板生成的每个代码文件：入口文件都有高亮规则', () {
      for (final s in codeStarters) {
        expect(highlightModeFor(s.entryFile), isNotNull, reason: '${s.id} 的 ${s.entryFile}');
      }
    });

    test('languageFor 能返回的每种语言都有高亮规则（除了 text）', () {
      // 样例表和规则表一一对应：加了语言没加样例，这里会失败。
      expect(samples.keys.toSet(), kCodeLanguages.keys.toSet());
      expect(highlightModeFor('main.go')?.$1, 'go');
      expect(highlightModeFor('a.bin'), isNull);
    });

    for (final dark in [false, true]) {
      test('每种语言的样例都真的上了色（${dark ? '深色' : '浅色'}）', () {
        const base = TextStyle(color: Color(0xFF010203));
        for (final e in samples.entries) {
          final span = highlightCode(e.value, e.key, dark: dark, base: base);
          expect(span.toPlainText(), e.value, reason: '${e.key}：上色不能改动文字');
          final colors = colorsOf(span)..remove(base.color);
          expect(colors, isNotEmpty, reason: '${e.key}：一处颜色都没有');
        }
      });
    }

    test('不认识的语言、空代码、太长的代码：原样一整段，不报错', () {
      const base = TextStyle(color: Color(0xFF010203));
      expect(highlightCode('abc', 'text', dark: false, base: base).toPlainText(), 'abc');
      expect(highlightCode('', 'go', dark: false, base: base).toPlainText(), '');
      final long = 'x = 1\n' * (kHighlightMaxChars ~/ 6 + 10);
      final span = highlightCode(long, 'python', dark: false, base: base);
      expect(span.children, isNull);
      expect(span.text, long);
    });
  });

  group('字号状态', () {
    late Directory tmp;
    late SettingsStore store;
    late ProviderContainer container;

    Future<void> boot([String? json]) async {
      tmp = Directory.systemTemp.createTempSync('lopi_font_');
      final file = File('${tmp.path}/settings.json');
      if (json != null) file.writeAsStringSync(json);
      store = SettingsStore(file);
      await store.load();
      container = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(store)]);
    }

    tearDown(() async {
      container.dispose();
      await pendingWrites();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('没设过是 14；存了范围外的夹回 10–24；不是数字的回默认', () async {
      await boot();
      expect(container.read(codeFontProvider), 14);
      container.dispose();
      await boot('{"ui.codeFontSize": 99}');
      expect(container.read(codeFontProvider), 24);
      container.dispose();
      await boot('{"ui.codeFontSize": 3}');
      expect(container.read(codeFontProvider), 10);
      container.dispose();
      await boot('{"ui.codeFontSize": "大"}');
      expect(container.read(codeFontProvider), 14);
      container.dispose();
      await boot('{"ui.codeFontSize": 17.4}');
      expect(container.read(codeFontProvider), 17);
    });

    test('preview 只改内存、commit 才写盘；set 立刻存；reset 把键删掉', () async {
      await boot();
      final n = container.read(codeFontProvider.notifier)..preview(18.6);
      expect(container.read(codeFontProvider), 19);
      await pendingWrites();
      expect(store.file.existsSync(), isFalse, reason: 'preview 不写盘');
      n.commit();
      await pendingWrites();
      expect((jsonDecode(store.file.readAsStringSync()) as Map)['ui.codeFontSize'], 19);
      n.set(100);
      expect(container.read(codeFontProvider), 24);
      n.reset();
      expect(container.read(codeFontProvider), 14);
      await pendingWrites();
      expect((jsonDecode(store.file.readAsStringSync()) as Map).containsKey('ui.codeFontSize'), isFalse);
      // 重开：从文件里读回来。
      n.set(12);
      await pendingWrites();
      final again = SettingsStore(store.file);
      await again.load();
      final c2 = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(again)]);
      addTearDown(c2.dispose);
      expect(c2.read(codeFontProvider), 12);
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    Future<TestEnv> boot(WidgetTester tester, Widget home) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.pumpWidget(appFor(env, home, mode: mode, font: kTestFont));
      await settle(tester, rounds: 2);
      return env;
    }

    /// 在 [target] 上用两根手指捏：两指间距从 [from] 变到 [to]。返回两根手指（还按着）。
    Future<(TestGesture, TestGesture)> pinch(WidgetTester tester, Finder target, {required double from, required double to}) async {
      final center = tester.getCenter(target);
      final a = await tester.startGesture(center - Offset(from / 2, 0), pointer: 11);
      final b = await tester.startGesture(center + Offset(from / 2, 0), pointer: 12);
      await tester.pump();
      const steps = 6;
      for (var i = 1; i <= steps; i++) {
        final d = from + (to - from) * i / steps;
        await a.moveTo(center - Offset(d / 2, 0));
        await b.moveTo(center + Offset(d / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return (a, b);
    }

    double sizeOf(TestEnv env) => env.services.container.read(codeFontProvider);

    testWidgets('“看代码”面板：Go 代码带颜色；双指张开变大、合拢变小、到头不再变；松手才存；重开还是这个字号 ($suffix)', (tester) async {
      Widget sheet() => const Scaffold(
        body: CodeSheetBody(title: '积木翻出来的 Go', note: '只读。改积木，代码会跟着变。', code: goCode, language: 'go'),
      );
      final env = await boot(tester, sheet());
      final text = tester.widget<SelectableText>(k('code-view-text'));
      expect(text.style?.fontSize, 14);
      expect(colorsOf(text.textSpan!).length, greaterThanOrEqualTo(3), reason: '关键字、字符串、注释至少三种颜色');
      await shot(tester, '120-code-sheet-go-$suffix');

      // 张开到 1.5 倍：14 → 21。捏的过程中右上角有字号提示。
      final (a, b) = await pinch(tester, find.byType(CodeView), from: 100, to: 150);
      expect(sizeOf(env), 21);
      expect(tester.widget<SelectableText>(k('code-view-text')).style?.fontSize, 21);
      expect(find.text('字号 21'), findsOneWidget);
      await shot(tester, '121-code-sheet-pinching-$suffix');
      await tester.runAsync(pendingWrites);
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), isNull, reason: '没松手不存');
      await a.up();
      await b.up();
      await tester.pump();
      expect(k('code-zoom-badge'), findsNothing);
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), 21);

      // 再张开很多：到 24 封顶。
      var (c, d) = await pinch(tester, find.byType(CodeView), from: 60, to: 300);
      expect(sizeOf(env), 24);
      await c.up();
      await d.up();
      // 合拢很多：到 10 封底。
      (c, d) = await pinch(tester, find.byType(CodeView), from: 300, to: 40);
      expect(sizeOf(env), 10);
      await c.up();
      await d.up();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 重开（换一个新的面板）：还是 10。
      await tester.pumpWidget(
        appFor(
          env,
          const Scaffold(body: SizedBox()),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pumpWidget(appFor(env, sheet(), mode: mode, font: kTestFont));
      await tester.pump();
      expect(tester.widget<SelectableText>(k('code-view-text')).style?.fontSize, 10);
      // 存进了文件：另开一个设置对象读回来也是 10。
      await tester.runAsync(pendingWrites);
      final again = SettingsStore(env.services.settings.file);
      await tester.runAsync(again.load);
      expect(again.get<num>(SettingKeys.codeFontSize), 10);
    });

    testWidgets('“看代码”面板：单指上下滑照常滚动，字号不变，也不出字号提示 ($suffix)', (tester) async {
      final env = await boot(
        tester,
        Scaffold(
          body: CodeSheetBody(title: 't', note: 'n', code: goCode * 12, language: 'go'),
        ),
      );
      final scrollable = find.descendant(of: find.byType(CodeSheetBody), matching: find.byType(Scrollable)).first;
      // 面板本身能上拉变高：头两下是把面板拉到顶，之后才是滚代码。
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(CodeSheetBody), const Offset(0, -300));
        await tester.pump();
      }
      expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0), reason: '单指滑动要能滚代码');
      expect(sizeOf(env), 14);
      expect(k('code-zoom-badge'), findsNothing);
      // 第一根手指先滑起来（页面已经在滚），再落第二根：照样能缩放。
      final a = await tester.startGesture(tester.getCenter(find.byType(CodeSheetBody)) - const Offset(50, 0), pointer: 21);
      await a.moveBy(const Offset(0, -40));
      await tester.pump();
      final b = await tester.startGesture(tester.getCenter(find.byType(CodeSheetBody)) + const Offset(50, -40), pointer: 22);
      await b.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(sizeOf(env), greaterThan(14));
      await a.up();
      await b.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('文件编辑器：.go / .java / .php 都装上了高亮；捏合改的是编辑器的字号，行号跟着小 2 ($suffix)', (tester) async {
      final c = CodeLineEditingController.fromText(goCode);
      final f = CodeFindController(c);
      addTearDown(() {
        f.dispose();
        c.dispose();
      });
      final env = await boot(
        tester,
        Scaffold(
          body: LopiCodeEditor(path: 'main.go', controller: c, findController: f, wordWrap: true),
        ),
      );
      CodeEditorStyle style() => tester.widget<CodeEditor>(find.byType(CodeEditor)).style!;
      expect(style().fontSize, 14);
      expect(style().codeTheme?.languages.keys, ['go']);
      expect(style().codeTheme?.theme['keyword']?.color, isNotNull);
      await settle(tester, rounds: 2);
      await shot(tester, '122-editor-go-$suffix');

      final (a, b) = await pinch(tester, find.byType(CodeEditor), from: 120, to: 154);
      expect(sizeOf(env), 18);
      expect(style().fontSize, 18);
      expect(find.text('字号 18'), findsOneWidget);
      await a.up();
      await b.up();
      await tester.pump();
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), 18);
      expect(c.text, goCode, reason: '捏合不能改动文件内容');
      await settle(tester, rounds: 2);
      await shot(tester, '123-editor-go-zoomed-$suffix');

      // re_editor 拿到焦点后有一个 100 毫秒的延时回调，编辑器在这之前被换掉会在调试模式下报“用了已释放的对象”（它自己的毛病，正式包里无害）：等它过去。
      await tester.pump(const Duration(milliseconds: 300));
      // 换文件：应用里每个文件有自己的控制器，这里也一样。
      for (final e in {'Main.java': 'java', 'index.php': 'php', 'main.rs': 'rust', 'Dockerfile': 'dockerfile', 'q.sql': 'sql'}.entries) {
        final c2 = CodeLineEditingController.fromText('x');
        final f2 = CodeFindController(c2);
        addTearDown(() {
          f2.dispose();
          c2.dispose();
        });
        await tester.pumpWidget(
          appFor(
            env,
            Scaffold(
              body: LopiCodeEditor(key: ValueKey(e.key), path: e.key, controller: c2, findController: f2, wordWrap: true),
            ),
            mode: mode,
            font: kTestFont,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(style().codeTheme?.languages.keys, [e.value], reason: e.key);
        expect(style().fontSize, 18, reason: '换文件字号不变');
      }
      // 编辑器自己有双击判定之类的短定时器：让它们走完。
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('原始 CSS 输入框：边输入边上色；捏合改字号；应用拿到的还是原文 ($suffix)', (tester) async {
      String? result = 'unset';
      final env = await boot(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => result = await showStyleCssEditor(context, initialCss: 'margin: 8px 4px;\ncolor: #333;', legacy: const {'width': '100px'}),
                child: const Text('开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(k('lc-css-input'));
      expect(field.controller, isA<CodeTextController>());
      expect(field.style?.fontSize, 14);
      final span = field.controller!.buildTextSpan(context: tester.element(k('lc-css-input')), style: field.style, withComposing: false);
      expect(span.toPlainText(), 'margin: 8px 4px;\ncolor: #333;');
      expect(colorsOf(span).length, greaterThanOrEqualTo(2), reason: '属性名和值颜色不同');
      await shot(tester, '124-css-input-$suffix');

      final (a, b) = await pinch(tester, k('lc-css-input'), from: 100, to: 130);
      expect(sizeOf(env), 18);
      expect(tester.widget<TextField>(k('lc-css-input')).style?.fontSize, 18);
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(k('lc-css-input'), 'color: red;');
      await tester.pump();
      await tester.ensureVisible(k('lc-css-apply'));
      await tester.tap(k('lc-css-apply'));
      await tester.pumpAndSettle();
      expect(result, 'color: red;');
    });

    testWidgets('设置 › 外观 › 代码字号：加减一步 1、到头灰掉、恢复默认；示例跟着变 ($suffix)', (tester) async {
      final env = await boot(tester, const AppearanceScreen());
      await tester.scrollUntilVisible(k('code-font-reset'), 120, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(tester.widget<Text>(k('code-font-value')).data, '14');
      expect(tester.widget<TextButton>(k('code-font-reset')).onPressed, isNull, reason: '已经是默认，恢复默认灰掉');
      await shot(tester, '125-settings-code-font-$suffix');

      await tester.tap(k('code-font-plus'));
      await tester.tap(k('code-font-plus'));
      await tester.pump();
      expect(tester.widget<Text>(k('code-font-value')).data, '16');
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), 16);
      final sample = find.descendant(of: k('code-font-sample'), matching: find.byType(SelectableText));
      expect(tester.widget<SelectableText>(sample).style?.fontSize, 16);

      for (var i = 0; i < 12; i++) {
        await tester.tap(k('code-font-plus'), warnIfMissed: false);
        await tester.pump();
      }
      expect(sizeOf(env), 24);
      expect(tester.widget<IconButton>(k('code-font-plus')).onPressed, isNull);

      await tester.ensureVisible(k('code-font-reset'));
      await tester.tap(k('code-font-reset'));
      await tester.pump();
      expect(sizeOf(env), 14);
      expect(env.services.settings.get<num>(SettingKeys.codeFontSize), isNull);

      for (var i = 0; i < 6; i++) {
        await tester.ensureVisible(k('code-font-minus'));
        await tester.tap(k('code-font-minus'), warnIfMissed: false);
        await tester.pump();
      }
      expect(sizeOf(env), 10);
      expect(tester.widget<IconButton>(k('code-font-minus')).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
