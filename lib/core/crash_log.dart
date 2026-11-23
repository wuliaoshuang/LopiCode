// 错误日志：没被接住的异常统一记到这里——写进本地文件（应用私有目录 logs/errors.log），
// 同时留在内存里给界面看（可复制）。不联网、不上传。
//
// 规矩：
// - 记之前先把像 Key 的东西抹掉（[redactSecrets]）。日志里不许出现 API Key / Token / 密码。
// - 记日志这件事本身绝不抛异常（磁盘满了、目录没了都只是不记文件）。
// - 这个文件不依赖 Flutter 界面库，纯 Dart，任何一层都能用。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CrashEntry {
  CrashEntry(this.time, this.source, this.message, this.stack, {this.fatal = true});
  final DateTime time;

  /// 哪儿来的：界面 / 平台 / 后台任务 / 启动…
  final String source;
  final String message;
  final String stack;

  /// false 表示只是“记一笔”（比如存盘文件坏了已回退），不用打扰用户。
  final bool fatal;

  String format() {
    final b = StringBuffer('[${time.toIso8601String()}] $source\n$message');
    if (stack.isNotEmpty) b.write('\n$stack');
    return b.toString();
  }
}

/// 把看着像密钥的东西抹掉。宁可多抹，不可漏。
String redactSecrets(String text) {
  var out = text;
  // Authorization: Bearer xxx / x-api-key: xxx / api_key=xxx / "apiKey":"xxx" / password=xxx / token=xxx
  out = out.replaceAllMapped(
    RegExp(r'''((?:authorization|x-api-key|api[-_ ]?key|apikey|token|password|passwd|secret)["']?\s*[:=]\s*["']?(?:bearer\s+)?)([^\s"',;&]+)''', caseSensitive: false),
    (m) => '${m[1]}***',
  );
  out = out.replaceAllMapped(RegExp(r'(bearer\s+)([A-Za-z0-9._\-]{8,})', caseSensitive: false), (m) => '${m[1]}***');
  // 常见 Key 的样子：sk-…、ghp_…、github_pat_…、tvly-…、AIza…
  out = out.replaceAll(RegExp(r'\b(?:sk|pk|rk)-[A-Za-z0-9_\-]{8,}'), 'sk-***');
  out = out.replaceAll(RegExp(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{8,}'), 'gh*_***');
  out = out.replaceAll(RegExp(r'\bgithub_pat_[A-Za-z0-9_]{8,}'), 'github_pat_***');
  out = out.replaceAll(RegExp(r'\btvly-[A-Za-z0-9_\-]{8,}'), 'tvly-***');
  out = out.replaceAll(RegExp(r'\bAIza[A-Za-z0-9_\-]{16,}'), 'AIza***');
  // 网址里的 user:pass@
  out = out.replaceAllMapped(RegExp(r'(://[^/\s:@]+:)([^@\s/]+)(@)'), (m) => '${m[1]}***${m[3]}');
  return out;
}

class CrashLog {
  CrashLog._();
  static final CrashLog instance = CrashLog._();

  /// 内存里最多留几条。
  static const int maxEntries = 50;

  /// 日志文件超过这么大就轮换（旧的留一份 .1）。
  static const int maxFileBytes = 256 * 1024;

  /// 一条记录的堆栈最多留几行。
  static const int maxStackLines = 40;

  File? _file;
  final List<CrashEntry> _entries = [];
  final StreamController<CrashEntry> _changes = StreamController<CrashEntry>.broadcast();
  Future<void> _writing = Future<void>.value();

  /// 最近的记录，新的在后。
  List<CrashEntry> get entries => List.unmodifiable(_entries);

  /// 每记一条发一次（界面用来弹提示）。
  Stream<CrashEntry> get changes => _changes.stream;

  File? get file => _file;

  /// 指定日志目录。没调用过也能 record（只进内存）。
  void attach(Directory dir) {
    _file = File('${dir.path}${Platform.pathSeparator}errors.log');
  }

  /// 测试用：回到刚启动的样子。
  void resetForTest() {
    _file = null;
    _entries.clear();
  }

  /// 记一个没被接住的异常。
  void record(Object error, StackTrace? stack, {String source = '应用', bool fatal = true}) {
    try {
      final lines = (stack?.toString() ?? '').trimRight().split('\n');
      final clipped = lines.length > maxStackLines ? [...lines.take(maxStackLines), '…（共 ${lines.length} 行，后面省略）'] : lines;
      var message = redactSecrets('$error');
      if (message.length > 4000) message = '${message.substring(0, 4000)}…';
      _add(CrashEntry(DateTime.now(), source, message, redactSecrets(clipped.join('\n')), fatal: fatal));
    } catch (_) {
      // 记日志不能再出错
    }
  }

  /// 记一笔不用打扰用户的事（存盘文件坏了已回退之类）。
  void note(String message, {String source = '存盘'}) {
    try {
      _add(CrashEntry(DateTime.now(), source, redactSecrets(message), '', fatal: false));
    } catch (_) {
      // 同上
    }
  }

  void _add(CrashEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeRange(0, _entries.length - maxEntries);
    if (!_changes.isClosed) _changes.add(entry);
    final file = _file;
    if (file == null) return;
    _writing = _writing.then((_) => _append(file, entry)).catchError((Object _) {});
  }

  Future<void> _append(File file, CrashEntry entry) async {
    try {
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() > maxFileBytes) {
        final old = File('${file.path}.1');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
      }
      await file.writeAsString('${entry.format()}\n\n', mode: FileMode.append, encoding: utf8, flush: true);
    } on FileSystemException {
      // 写不了文件：内存里还有
    }
  }

  /// 等排队的写入做完（测试、退出前用）。
  Future<void> flush() => _writing;

  /// 给“复制”按钮的全文：内存里的记录，新的在前。
  String export() => _entries.reversed.map((e) => e.format()).join('\n\n');

  /// 清空内存和文件。
  Future<void> clear() async {
    _entries.clear();
    final file = _file;
    if (file == null) return;
    _writing = _writing.then((_) async {
      for (final f in [file, File('${file.path}.1')]) {
        try {
          if (await f.exists()) await f.delete();
        } on FileSystemException {
          // 删不掉就算了
        }
      }
    });
    await _writing;
  }

  /// 读日志文件全文（含上次运行留下的）；没有文件就返回内存里的。
  Future<String> readAll() async {
    await flush();
    final file = _file;
    if (file == null) return export();
    final b = StringBuffer();
    for (final f in [File('${file.path}.1'), file]) {
      try {
        if (await f.exists()) b.write(await f.readAsString());
      } on Exception {
        // 读不了这一份就跳过
      }
    }
    final text = b.toString().trim();
    return text.isEmpty ? export() : text;
  }
}
