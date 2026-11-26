// 下载正文里的 https 图片（纯逻辑）。规矩：只许 https（跳转的每一跳也是）、有超时、有大小上限、必须真是图片。
// 下好的放内存里留一会儿（滚出去再滚回来不用重新下），不写盘。
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lopicode/markdown/md_links.dart';

/// 内存里最多留这么多字节的图片（自己定的：24MB），超了先丢最久没用的。
const int kMdImageCacheMaxBytes = 24 * 1024 * 1024;

class MdImageException implements Exception {
  MdImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MdImageLoader {
  MdImageLoader({http.Client Function()? clientFactory, this.timeout = kMdImageTimeout, this.maxBytes = kMdNetImageMaxBytes}) : _clientFactory = clientFactory ?? http.Client.new;

  /// 全应用共用的一个；测试里可以换掉。
  static MdImageLoader instance = MdImageLoader();

  final http.Client Function() _clientFactory;
  final Duration timeout;
  final int maxBytes;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  int _cacheBytes = 0;
  final Map<String, Future<Uint8List>> _pending = {};

  /// 已经下好的（没有返回 null）。
  Uint8List? cached(Uri uri) {
    final hit = _cache.remove('$uri');
    if (hit != null) _cache['$uri'] = hit;
    return hit;
  }

  /// 下载。失败抛 [MdImageException]，里面是能直接给她看的原因（只带主机名，不带完整网址）。
  Future<Uint8List> load(Uri uri) {
    final hit = cached(uri);
    if (hit != null) return Future.value(hit);
    // 同一张图同时只下一次
    // 注意：whenComplete 的回调不能把 remove 的返回值（就是这个 Future 自己）交回去，否则它会等自己，永远不结束
    return _pending['$uri'] ??= _fetch(uri).whenComplete(() {
      _pending.remove('$uri');
    });
  }

  Future<Uint8List> _fetch(Uri first) async {
    final client = _clientFactory();
    try {
      return await _run(client, first).timeout(timeout, onTimeout: () => throw MdImageException('等了 ${timeout.inSeconds} 秒还没下完（${first.host}）'));
    } on MdImageException {
      rethrow;
    } on Exception catch (e) {
      throw MdImageException('连不上 ${first.host}（${e.runtimeType}）');
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _run(http.Client client, Uri first) async {
    var uri = first;
    for (var hop = 0; ; hop++) {
      if (uri.scheme != 'https') throw MdImageException('图片跳到了没加密的地址，不加载');
      final req = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['accept'] = 'image/*';
      final res = await client.send(req);
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final to = res.headers['location'];
        // 丢掉这一跳的内容
        unawaited(res.stream.listen((_) {}, onError: (_) {}).cancel());
        if (to == null || hop >= kMdImageMaxRedirects) throw MdImageException('图片地址跳转太多次');
        uri = uri.resolve(to);
        continue;
      }
      if (res.statusCode != 200) throw MdImageException('${first.host} 返回了 ${res.statusCode}');
      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (!type.startsWith('image/') || type.startsWith('image/svg')) throw MdImageException('这个地址给的不是能显示的图片');
      if ((res.contentLength ?? 0) > maxBytes) throw MdImageException('图片太大（超过 ${maxBytes ~/ (1024 * 1024)}MB），不加载');
      final out = BytesBuilder(copy: false);
      await for (final chunk in res.stream) {
        out.add(chunk);
        if (out.length > maxBytes) throw MdImageException('图片太大（超过 ${maxBytes ~/ (1024 * 1024)}MB），不加载');
      }
      final bytes = out.takeBytes();
      _put('$first', bytes);
      return bytes;
    }
  }

  void _put(String key, Uint8List bytes) {
    final old = _cache.remove(key);
    if (old != null) _cacheBytes -= old.length;
    _cache[key] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > kMdImageCacheMaxBytes && _cache.length > 1) {
      final k = _cache.keys.first;
      _cacheBytes -= _cache.remove(k)!.length;
    }
  }
}
