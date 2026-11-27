// 第四轮 B1：把导出的样式表交给 jsdom 解析，列出里面的媒体查询规则（tool/verify/media_rules.mjs）。只在开发机上有环境。
import 'dart:convert';
import 'dart:io';

import 'dev_tools.dart';

/// 一条媒体查询里的一条规则。
typedef MediaRule = ({String cond, String selector, Map<String, String> style});

/// 解析 [sheets]（每个是一整份 css 文字）；返回里面所有媒体查询下的规则。脚本没给结果就抛错。
/// 进程是 Process.run 起的：跑完才返回，超时（30 秒）就杀掉。
Future<List<MediaRule>> mediaRulesOf(List<String> sheets) async {
  final dir = Directory.systemTemp.createTempSync('lopi_media_');
  try {
    final paths = <String>[];
    for (var i = 0; i < sheets.length; i++) {
      final f = File('${dir.path}/s$i.css')..writeAsStringSync(sheets[i]);
      paths.add(f.path);
    }
    final p = await Process.start('node', ['${Directory.current.path}/tool/verify/media_rules.mjs', ...paths], environment: {'LOPI_WEBDEV_DOM': webdevDomDir!});
    final outF = p.stdout.transform(utf8.decoder).join(), errF = p.stderr.transform(utf8.decoder).join();
    final code = await p.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final out = (await outF).trim();
    if (code != 0 || !out.startsWith('{')) throw StateError('media_rules.mjs 没给出结果（退出码 $code）：${await errF}');
    final json = jsonDecode(out) as Map<String, Object?>;
    if (json['ok'] != true) throw StateError('media_rules.mjs：${json['error']}');
    return [
      for (final m in (json['media']! as List).cast<Map<String, Object?>>())
        for (final r in (m['rules']! as List).cast<Map<String, Object?>>()) (cond: '${m['cond']}', selector: '${r['selector']}', style: (r['style']! as Map).map((k, v) => MapEntry('$k', '$v'))),
    ];
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Vue 单文件里各段 `<style>` 的内容。
List<String> vueStyles(String sfc) => [for (final m in RegExp(r'<style[^>]*>([\s\S]*?)</style>').allMatches(sfc)) m[1]!];
