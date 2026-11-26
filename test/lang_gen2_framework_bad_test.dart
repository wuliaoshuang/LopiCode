// “小框架”库故意用错的几组：都要在检查阶段被拦下来（五种语言一行都不生成）。
// 库的七个模块就是 test/fixtures/framework/bookshop.lc 里的那七个，后面换上一个写错的入口模块。
// 最后两组是“要不要等”（核心 3）：处理函数里有要等的事不用标，检查器自己推出来，五种语言照常生成；放错地方的在检查阶段拦（T30）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/typecheck.dart';

import 'support/proto_lc.dart';

final String _lib = () {
  final src = File('test/fixtures/framework/bookshop.lc').readAsStringSync();
  return src.substring(0, src.indexOf('(模块 书店服务'));
}();

const String _uses = '(用 错误们 响应 上下文 中间件 路由 校验 仓库)';

LProgram _program(String body) => lcProgram('$_lib (模块 我的服务 $_uses $body)');

/// 连模块、查类型，说了哪些问题（“规则号 提示语”）。
List<String> _said(String body) {
  final linked = linkProgram(_program(body));
  if (linked.module == null) return [for (final i in linked.issues) '${i.code} ${i.message}'];
  return [for (final i in checkModuleTypes(linked.module!).errors) '${i.code} ${i.message}'];
}

/// 只有这一条规则号，提示语里有这些字；五种语言都不生成。
void _only(String body, String code, List<String> parts) {
  final said = _said(body);
  expect(said, isNotEmpty, reason: body);
  expect({for (final s in said) s.split(' ').first}, {code}, reason: said.join('\n'));
  for (final p in parts) {
    expect(said.any((s) => s.contains(p)), isTrue, reason: '提示语里要有「$p」：\n${said.join('\n')}');
  }
  for (final l in kGen2Languages) {
    expect(() => gen2ProgramFiles(l, _program(body)), throwsA(isA<LangUnsupported>()), reason: l);
  }
}

const String _app = '(变量 app 应用 (新 应用))';

void main() {
  test('写对的最小服务：没有问题，五种语言都生成得出来', () {
    const ok = '$_app (主 (做 (发 app GET "/" (λ ((c 上下文)) (标 任意 "好")))) (做 (发 app 开始服务 8200)))';
    expect(_said(ok), isEmpty);
    for (final l in kGen2Languages) {
      expect(gen2ProgramFiles(l, _program(ok)), isNotEmpty, reason: l);
    }
  });

  test('用了框架里没公开的东西（M06）', () {
    _only('$_app (主 (打印 (. (调 变成响应 (标 任意 1)) 状态码)))', 'M06', ['模块「路由」里的「变成响应」没有公开']);
    _only('$_app (主 (打印 (长 (调 切路径 "/a/b"))))', 'M06', ['「切路径」没有公开']);
    _only('$_app (主 (打印 (调 解码 "%41")))', 'M06', ['模块「上下文」里的「解码」没有公开']);
  });

  test('在外面碰框架的内部字段（T22）', () {
    _only('$_app (主 (做 (发 app GET "/" (λ ((c 上下文)) (标 任意 (. c 请求))))))', 'T22', ['「上下文」的「请求」是内部的']);
  });

  test('路由处理函数的样子不对：参数类型不对、参数个数不对、根本不是函数（T01、T07）', () {
    _only('$_app (主 (做 (发 app GET "/" (λ ((n 整数)) (标 任意 n)))))', 'T01', const []);
    _only('$_app (主 (做 (发 app GET "/" (λ ((c 上下文) (多的 文字)) (标 任意 多的)))))', 'T07', ['这里要一个收 1 个参数的函数，给的收 2 个']);
    _only('$_app (主 (做 (发 app GET "/" "不是函数")))', 'T01', const []);
  });

  test('中间件类没把接口的方法写全、写的样子不对（T11）', () {
    _only('(类 空壳 (实现 中间件)) $_app (主 (做 (发 app 用 (标 任意 (新 空壳)))))', 'T11', ['「空壳」说自己是「中间件」，但是没有「处理」这个方法']);
    _only('(类 歪的 (实现 中间件) (要等方法 处理 ((c 上下文)) -> 响应 (返回 (发 响应 空的)))) $_app (主 (做 (发 app 用 (标 任意 (新 歪的)))))', 'T11', const []);
  });

  test('接的错误种类不存在、抛的不是错误（T19）', () {
    _only('$_app (主 (试 (做 (打印 1)) (出错时 没这种错 e (打印 (. e 消息)))))', 'T19', ['“出错时”要接的「没这种错」不存在']);
    _only('$_app (主 (抛出 (发 响应 空的)))', 'T19', const []);
    _only('$_app (主 (试 (做 (打印 1)) (出错时 响应 e (打印 1))))', 'T19', const []);
  });

  test('框架里没有的方法、给错参数（T08、T01）', () {
    _only('$_app (主 (做 (发 app HEAD "/" (λ ((c 上下文)) (标 任意 1)))))', 'T08', ['没有「HEAD」这个方法']);
    _only('$_app (主 (做 (发 app 开始服务 "8200")))', 'T01', const []);
    _only('$_app (主 (做 (新 未授权 401)))', 'T01', const []);
  });

  test('要等的事写在没标“要等”的处理函数里：检查器自己推出来它要等，五种语言照常生成', () {
    const body =
        '(宿主 time.sleep ((毫秒 整数)) -> 空) $_app '
        '(主 (做 (发 app GET "/" (λ块 ((c 上下文)) (做 (宿 time.sleep 5)) (返回 (标 任意 1))))))';
    expect(_said(body), isEmpty);
    for (final l in kGen2Languages) {
      expect(gen2ProgramFiles(l, _program(body)), isNotEmpty, reason: l);
    }
    // Node 里这个匿名函数自动带上 async、里面那句自动带上 await。
    final js = gen2ProgramFiles('node', _program(body)).values.join('\n');
    expect(js, contains('(async (v1_c) => {'));
    expect(js, contains('(await lc.hostSleep(5))'));
  });

  test('要等的函数放进只收不用等的函数的地方（T30）：检查阶段拦下', () {
    _only(
      '(宿主 time.sleep ((毫秒 整数)) -> 空) $_app '
      '(主 (打印 (长 (调 筛选 (列 1 2 3) (λ块 ((x 整数)) (做 (宿 time.sleep 5)) (返回 (> x 1)))))))',
      'T30',
      ['只收不用等的函数', '用了「等一会儿」'],
    );
  });
}
