// 聊天正文里图片、链接、HTML 预览文档的规矩（纯逻辑），和网络图片下载（假客户端：超时 / 太大 / 跳转 / 不是图片）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/markdown/html_preview_doc.dart';
import 'package:lopicode/markdown/md_image_loader.dart';
import 'package:lopicode/markdown/md_links.dart';
import 'package:path/path.dart' as p;

void main() {
  group('图片从哪来、能不能加载', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('md_img_');
      Directory(p.join(tmp.path, 'ws', 'img')).createSync(recursive: true);
      File(p.join(tmp.path, 'ws', 'img', 'a b.png')).writeAsBytesSync([1]);
      File(p.join(tmp.path, 'secret.png')).writeAsBytesSync([1]);
      guard = PathGuard(p.join(tmp.path, 'ws'));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('工作区里的相对路径（带空格、%20、./、?query）', () {
      for (final s in ['img/a b.png', 'img/a%20b.png', './img/a b.png', 'img/a b.png?v=2#x', '/workspace/img/a b.png', '${guard.root}/img/a b.png']) {
        final r = mdResolveImage(s, guard);
        expect(r, isA<MdLocalImage>(), reason: s);
        expect((r as MdLocalImage).path, p.join(guard.root, 'img', 'a b.png'), reason: s);
      }
    });
    test('跳出工作区的一律不加载', () {
      for (final s in [
        '../secret.png',
        'img/../../secret.png',
        '/etc/passwd.png',
        '${tmp.path}/secret.png',
        '~/a.png',
        '.lopicode/x.png',
        'file:///sdcard/a.png',
        'content://x/a.png',
        '%2e%2e/secret.png',
      ]) {
        expect(mdResolveImage(s, guard), isA<MdBlockedImage>(), reason: s);
      }
    });
    test('符号链接指到工作区外面：不加载', () {
      Link(p.join(guard.root, 'out.png')).createSync(p.join(tmp.path, 'secret.png'));
      expect(mdResolveImage('out.png', guard), isA<MdBlockedImage>());
    });
    test('https 可以（要点一下）；http 明文、带账号密码、别的协议不行', () {
      expect(mdResolveImage('https://a.com/x.png', guard), isA<MdNetImage>());
      expect(mdResolveImage('HTTPS://a.com/x', null), isA<MdNetImage>());
      expect((mdResolveImage('http://a.com/x.png', guard) as MdBlockedImage).reason, contains('http'));
      expect(mdResolveImage('https://user:pw@a.com/x.png', guard), isA<MdBlockedImage>());
      expect(mdResolveImage('ftp://a.com/x.png', guard), isA<MdBlockedImage>());
      expect(mdResolveImage('javascript:alert(1)', guard), isA<MdBlockedImage>());
    });
    test('data: 图片：只认常见位图，有大小上限，坏数据不崩', () {
      expect(mdResolveImage('data:image/png;base64,${base64.encode([1, 2, 3])}', null), isA<MdDataImage>());
      expect(mdResolveImage('data:image/svg+xml;base64,AAAA', null), isA<MdBlockedImage>());
      expect(mdResolveImage('data:text/html;base64,AAAA', null), isA<MdBlockedImage>());
      expect(mdResolveImage('data:image/png;base64,@@@', null), isA<MdBlockedImage>());
      expect(mdResolveImage('data:image/png;base64,${'A' * (kMdDataImageMaxBytes * 4 ~/ 3 + 8)}', null), isA<MdBlockedImage>());
    });
    test('没有工作区、不是图片的扩展名', () {
      expect(mdResolveImage('img/a.png', null), isA<MdBlockedImage>());
      expect(mdResolveImage('img/a.svg', guard), isA<MdBlockedImage>());
      expect(mdResolveImage('notes.txt', guard), isA<MdBlockedImage>());
      expect(mdResolveImage('', guard), isA<MdBlockedImage>());
    });
  });

  group('链接', () {
    test('种类说明和看得见的完整网址', () {
      expect(mdLinkKind('https://a.com'), '网页链接');
      expect(mdLinkKind('http://a.com'), contains('没加密'));
      expect(mdLinkKind('mailto:a@b.c'), '邮箱地址');
      expect(mdLinkKind('docs/readme.md'), '工作区里的路径');
      expect(mdLinkKind('javascript:x'), 'javascript: 链接');
      // 藏方向控制符 / 零宽字符的网址：换成看得见的记号
      expect(mdVisibleUrl('https://a.com/\u202Egnp.exe\u200B'), 'https://a.com/�gnp.exe�');
    });
  });

  group('网络图片下载', () {
    MdImageLoader loader(http.Client client, {Duration timeout = const Duration(seconds: 2), int maxBytes = 100}) => MdImageLoader(clientFactory: () => client, timeout: timeout, maxBytes: maxBytes);
    final png = {'content-type': 'image/png'};

    test('正常下载，第二次走内存', () async {
      var hits = 0;
      final l = loader(
        MockClient((req) async {
          hits++;
          expect(req.followRedirects, isFalse);
          return http.Response.bytes([1, 2, 3], 200, headers: png);
        }),
      );
      final uri = Uri.parse('https://a.com/x.png');
      expect(await l.load(uri), [1, 2, 3]);
      expect(await l.load(uri), [1, 2, 3]);
      expect(l.cached(uri), isNotNull);
      expect(hits, 1);
    });
    test('超时', () async {
      final never = Completer<http.Response>();
      final l = loader(MockClient((_) => never.future), timeout: const Duration(milliseconds: 50));
      await expectLater(l.load(Uri.parse('https://slow.example/x.png')), throwsA(isA<MdImageException>().having((e) => e.message, 'message', contains('还没下完'))));
    });
    test('太大（按声明的长度和按实际收到的）', () async {
      final l = loader(MockClient((_) async => http.Response.bytes(List.filled(500, 0), 200, headers: png)));
      await expectLater(l.load(Uri.parse('https://a.com/big.png')), throwsA(isA<MdImageException>().having((e) => e.message, 'message', contains('太大'))));
      final streamed = loader(MockClient.streaming((_, _) async => http.StreamedResponse(Stream.fromIterable([List.filled(80, 0), List.filled(80, 0)]), 200, headers: png)));
      await expectLater(streamed.load(Uri.parse('https://a.com/big2.png')), throwsA(isA<MdImageException>().having((e) => e.message, 'message', contains('太大'))));
    });
    test('不是图片、svg、非 200', () async {
      final html = loader(MockClient((_) async => http.Response('<html>', 200, headers: {'content-type': 'text/html'})));
      await expectLater(html.load(Uri.parse('https://a.com/x')), throwsA(isA<MdImageException>()));
      final svg = loader(MockClient((_) async => http.Response('<svg/>', 200, headers: {'content-type': 'image/svg+xml'})));
      await expectLater(svg.load(Uri.parse('https://a.com/x.svg')), throwsA(isA<MdImageException>()));
      final missing = loader(MockClient((_) async => http.Response('', 404)));
      await expectLater(missing.load(Uri.parse('https://a.com/x.png')), throwsA(isA<MdImageException>().having((e) => e.message, 'message', contains('404'))));
    });
    test('跳转：https 跟着走；跳到 http 不加载；跳太多次不加载', () async {
      final ok = loader(MockClient((req) async => req.url.path == '/a' ? http.Response('', 302, headers: {'location': '/b'}) : http.Response.bytes([9], 200, headers: png)));
      expect(await ok.load(Uri.parse('https://a.com/a')), [9]);
      final down = loader(MockClient((req) async => http.Response('', 302, headers: {'location': 'http://a.com/b'})));
      await expectLater(down.load(Uri.parse('https://a.com/a')), throwsA(isA<MdImageException>().having((e) => e.message, 'message', contains('没加密'))));
      final loop = loader(MockClient((req) async => http.Response('', 302, headers: {'location': '/a'})));
      await expectLater(loop.load(Uri.parse('https://a.com/a')), throwsA(isA<MdImageException>().having((e) => e.message, 'message', contains('跳转'))));
    });
    test('连不上：报主机名，不带完整网址', () async {
      final l = loader(MockClient((_) async => throw const SocketException('boom')));
      await expectLater(
        l.load(Uri.parse('https://a.com/x.png?token=SECRET')),
        throwsA(isA<MdImageException>().having((e) => e.message, 'message', allOf(contains('a.com'), isNot(contains('SECRET'))))),
      );
    });
  });

  group('HTML 预览文档', () {
    test('内容安全策略在最前面，默认不联网', () {
      final doc = buildPreviewDocument('<!DOCTYPE html><html><head><meta http-equiv="Content-Security-Policy" content="default-src *"></head><body><img src="https://x/a.png"></body></html>');
      expect(doc, startsWith('<!DOCTYPE html><meta http-equiv="Content-Security-Policy" content="$kHtmlPreviewCspOffline">'));
      expect(doc.indexOf(kHtmlPreviewCspOffline), lessThan(doc.indexOf('default-src *')));
      expect(kHtmlPreviewCspOffline, contains("default-src 'none'"));
      expect(kHtmlPreviewCspOffline, isNot(contains('http')));
      expect('<!DOCTYPE'.allMatches(doc).length, 1);
      expect(doc, contains(kHtmlPreviewChannel));
    });
    test('允许这次联网：只许 https', () {
      final doc = buildPreviewDocument('<p>x</p>', allowNetwork: true);
      expect(doc, contains(kHtmlPreviewCspOnline));
      expect(kHtmlPreviewCspOnline, contains('https:'));
      expect(kHtmlPreviewCspOnline, isNot(contains('http:')));
      expect(kHtmlPreviewCspOnline, isNot(contains('*')));
    });
    test('svg 包一层；哪些语言能预览', () {
      expect(buildPreviewDocument('<svg></svg>', lang: 'svg'), contains('<body style="margin:0"><svg></svg></body>'));
      expect(htmlPreviewable('HTML'), isTrue);
      expect(htmlPreviewable('svg'), isTrue);
      expect(htmlPreviewable('js'), isFalse);
      expect(htmlPreviewable(''), isFalse);
    });
    test('通道只收数字', () {
      expect(parsePreviewSignal('240'), 240);
      expect(parsePreviewSignal('-1'), kHtmlPreviewBlockedSignal);
      for (final bad in ['', 'abc', '{"a":1}', '-5', 'NaN', 'Infinity', '1e999', '1234567890123', 'file:///x', '12px']) {
        expect(parsePreviewSignal(bad), isNull, reason: bad);
      }
    });
  });
}
