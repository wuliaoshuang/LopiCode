import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 下载失败的真实原因（直接给用户看）。
class DownloadException implements Exception {
  DownloadException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

/// 取消下载用的开关。
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// 可断点续传的下载：没下完的内容留在 `目标文件.part` 里，下次从断的地方接着下。
/// 下完后核对大小和 sha256，对不上就删掉重来，绝不把坏文件当成好的。
class ResumableDownload {
  ResumableDownload(this.client, {this.stallTimeout = const Duration(seconds: 45)});
  final http.Client client;

  /// 这么久一个字节都没收到，就当连接卡死了，停下来报错（已下载的部分留着）。
  final Duration stallTimeout;

  static File partFile(File target) => File('${target.path}.part');

  Future<void> fetch(Uri url, File target, {required int expectedSize, required String expectedSha256, void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    final part = partFile(target);
    await target.parent.create(recursive: true);
    if (await target.exists() && await target.length() == expectedSize && await sha256Of(target) == expectedSha256) {
      onProgress?.call(expectedSize, expectedSize);
      return;
    }
    var have = await part.exists() ? await part.length() : 0;
    if (have > expectedSize) {
      await part.delete();
      have = 0;
    }
    if (have < expectedSize) {
      await _download(url, part, have, expectedSize, onProgress, cancel, allowRestart: true);
    }
    onProgress?.call(expectedSize, expectedSize);
    final size = await part.length();
    if (size != expectedSize) {
      await part.delete();
      throw DownloadException('下载到的文件大小不对（应为 $expectedSize 字节，实际 $size 字节），已删除，请重新下载');
    }
    final digest = await sha256Of(part);
    if (digest != expectedSha256) {
      await part.delete();
      throw DownloadException('文件校验不一致，可能下载源出了问题，已删除。换一个下载源再试');
    }
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
  }

  Future<void> _download(Uri url, File part, int have, int expectedSize, void Function(int received, int total)? onProgress, CancelToken? cancel, {required bool allowRestart}) async {
    final request = http.Request('GET', url);
    if (have > 0) request.headers['Range'] = 'bytes=$have-';
    final http.StreamedResponse response;
    try {
      response = await client.send(request).timeout(stallTimeout);
    } on TimeoutException {
      throw DownloadException('连不上下载源 ${url.host}：${stallTimeout.inSeconds} 秒没有回应');
    } on Exception catch (e) {
      throw DownloadException('连不上下载源 ${url.host}：${_reason(e)}');
    }
    var mode = FileMode.writeOnlyAppend;
    if (response.statusCode == 200) {
      // 服务器不支持续传（或本来就是从头下）：从头写。
      have = 0;
      mode = FileMode.writeOnly;
    } else if (response.statusCode == 206) {
      final range = response.headers['content-range'] ?? '';
      final match = RegExp(r'bytes (\d+)-').firstMatch(range);
      if (match == null || int.parse(match.group(1)!) != have) {
        await response.stream.drain<void>().catchError((_) {});
        if (!allowRestart) throw DownloadException('下载源返回的续传位置不对');
        if (await part.exists()) await part.delete();
        return _download(url, part, 0, expectedSize, onProgress, cancel, allowRestart: false);
      }
    } else if (response.statusCode == 416 && allowRestart) {
      await response.stream.drain<void>().catchError((_) {});
      if (await part.exists()) await part.delete();
      return _download(url, part, 0, expectedSize, onProgress, cancel, allowRestart: false);
    } else {
      await response.stream.drain<void>().catchError((_) {});
      throw DownloadException('下载源 ${url.host} 返回了错误（HTTP ${response.statusCode}）');
    }

    final sink = part.openWrite(mode: mode);
    var received = have;
    onProgress?.call(received, expectedSize);
    try {
      await for (final chunk in response.stream.timeout(stallTimeout)) {
        if (cancel?.isCancelled ?? false) {
          throw DownloadException('已取消下载，下到一半的内容留着，下次接着下', cancelled: true);
        }
        sink.add(chunk);
        received += chunk.length;
        if (received > expectedSize) throw DownloadException('下载源给的内容比预期的多，已停止');
        onProgress?.call(received, expectedSize);
      }
    } on DownloadException {
      rethrow;
    } on TimeoutException {
      throw DownloadException('下载中断：${stallTimeout.inSeconds} 秒没有收到数据。已下载的部分留着，重试会接着下');
    } on Exception catch (e) {
      throw DownloadException('下载中断：${_reason(e)}。已下载的部分留着，重试会接着下');
    } finally {
      await sink.flush().catchError((_) {});
      await sink.close().catchError((_) {});
    }
    if (received < expectedSize) {
      throw DownloadException('下载中断：连接提前断开。已下载的部分留着，重试会接着下');
    }
  }

  static String _reason(Object e) {
    if (e is SocketException) return e.osError?.message ?? e.message;
    if (e is http.ClientException) return e.message;
    if (e is HandshakeException) return '安全连接握手失败';
    if (e is TimeoutException) return '连接超时';
    return e.toString();
  }
}

Future<String> sha256Of(File file) async => (await sha256.bind(file.openRead()).first).toString();
