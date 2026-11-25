import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/skill_scripts.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/stores.dart';
import 'package:path/path.dart' as p;

class Skill {
  Skill({required this.name, required this.description, required this.dir, required this.global, required this.enabled, this.files = SkillFiles.none});

  /// 技能目录里除了 SKILL.md 以外附带的文件（脚本和别的）。
  final SkillFiles files;
  List<String> get scripts => files.scripts;

  /// 文件夹名，也是 Agent 读取时用的名字。
  final String name;
  final String description;
  final String dir;

  /// true＝全局技能；false＝只属于当前工作区。
  final bool global;
  final bool enabled;

  String get key => '${global ? 'g' : 'w'}:$name';
  File get file => File(p.join(dir, 'SKILL.md'));
}

class SkillException implements Exception {
  SkillException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 技能：一个文件夹一份 SKILL.md。全局的在应用目录，工作区的在 `<工作区>/.lopicode/skills/`。
class SkillStore {
  SkillStore(this.settings, this.globalDir);
  final SettingsStore settings;
  final String globalDir;

  static const kDisabled = 'skills.disabled';

  /// 技能文件增删了（状态层据此通知界面）。
  final List<void Function()> changeListeners = [];

  void _changed() {
    for (final listener in List.of(changeListeners)) {
      listener();
    }
  }

  static const int maxSkillChars = 40000;

  static String workspaceSkillsDir(String workspaceDir) => p.join(workspaceDir, PathGuard.reservedDir, 'skills');

  Set<String> get _disabled => {
    for (final k in settings.get<List<dynamic>>(kDisabled) ?? const [])
      if (k is String) k,
  };

  /// 从 SKILL.md 开头的 `---` 区块里读 name 和 description。
  static ({String? name, String description, String body}) parse(String text) {
    final lines = text.split('\n');
    String? name;
    var description = '';
    var bodyStart = 0;
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim() == '---') {
          bodyStart = i + 1;
          break;
        }
        final m = RegExp(r'^(name|description)\s*:\s*(.*)$').firstMatch(line.trim());
        if (m == null) continue;
        var v = m.group(2)!.trim();
        if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
          v = v.substring(1, v.length - 1);
        }
        if (m.group(1) == 'name') name = v;
        if (m.group(1) == 'description') description = v;
      }
    }
    final body = lines.skip(bodyStart).join('\n').trim();
    if (description.isEmpty) {
      // 没写描述：拿正文第一行非标题的话顶上。
      description = body.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
    }
    if (description.length > 200) description = '${description.substring(0, 200)}…';
    return (name: name, description: description, body: body);
  }

  Future<List<Skill>> _scan(String dir, bool global) async {
    final root = Directory(dir);
    if (!await root.exists()) return [];
    final out = <Skill>[];
    final disabled = _disabled;
    final entries = await root.list(followLinks: false).toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final e in entries) {
      if (e is! Directory) continue;
      final file = File(p.join(e.path, 'SKILL.md'));
      if (!await file.exists()) continue;
      String text;
      try {
        text = await file.readAsString();
      } on FileSystemException {
        continue;
      }
      final name = p.basename(e.path);
      final key = '${global ? 'g' : 'w'}:$name';
      out.add(Skill(name: name, description: parse(text).description, dir: e.path, global: global, enabled: !disabled.contains(key), files: scanSkillFilesSync(e.path)));
    }
    return out;
  }

  /// 全部技能：工作区的排前面；同名时工作区的盖过全局的。
  Future<List<Skill>> list({String? workspaceDir}) async {
    final ws = workspaceDir == null ? <Skill>[] : await _scan(workspaceSkillsDir(workspaceDir), false);
    final global = await _scan(globalDir, true);
    return [...ws, ...global];
  }

  /// Agent 这次能用的技能（开着的；同名取工作区那份）。
  Future<List<Skill>> enabled({String? workspaceDir}) async {
    final seen = <String>{};
    return [
      for (final s in await list(workspaceDir: workspaceDir))
        if (s.enabled && seen.add(s.name)) s,
    ];
  }

  Future<void> setEnabled(Skill skill, bool on) async {
    final d = _disabled;
    on ? d.remove(skill.key) : d.add(skill.key);
    await settings.set(kDisabled, d.toList()..sort());
  }

  static String validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw SkillException('技能名不能为空');
    if (name.length > 40) throw SkillException('技能名最多 40 个字');
    if (name.startsWith('.') || RegExp(r'[/\\:*?"<>|\s]').hasMatch(name)) throw SkillException('技能名不能有空格和 / \\ : * ? " < > | 这些符号，也不能以 . 开头');
    return name;
  }

  Future<Skill> create({required String name, required String description, required String body, String? workspaceDir}) async {
    final clean = validateName(name);
    final global = workspaceDir == null;
    final dir = Directory(p.join(global ? globalDir : workspaceSkillsDir(workspaceDir), clean));
    if (await dir.exists()) throw SkillException('已经有叫“$clean”的技能了');
    await dir.create(recursive: true);
    final desc = description.trim().replaceAll('\n', ' ');
    await File(p.join(dir.path, 'SKILL.md')).writeAsString('---\nname: $clean\ndescription: $desc\n---\n\n${body.trim()}\n');
    _changed();
    return Skill(name: clean, description: desc, dir: dir.path, global: global, enabled: true);
  }

  Future<void> delete(Skill skill) async {
    final dir = Directory(skill.dir);
    // 只删技能目录下面的文件夹，防止误删。
    if (p.basename(skill.dir) != skill.name || !await File(p.join(skill.dir, 'SKILL.md')).exists()) {
      throw SkillException('这不是一个技能目录，已拒绝删除');
    }
    await dir.delete(recursive: true);
    _changed();
    final d = _disabled..remove(skill.key);
    await settings.set(kDisabled, d.toList()..sort());
  }

  Future<String> readFull(Skill skill) async {
    final text = await skill.file.readAsString();
    return text.length > maxSkillChars ? '${text.substring(0, maxSkillChars)}\n…（太长，只显示前 $maxSkillChars 字符）' : text;
  }

  /// 拼进系统提示词的技能清单（只有名字和描述；带脚本的多一句“带 N 个脚本”，脚本在哪读全文时才说）。
  static String promptSection(List<Skill> skills) =>
      skills.isEmpty ? '' : '可用的技能（需要时先用 read_skill 读全文，再照着做）：\n${skills.map((s) => '- ${s.name}：${s.description}${s.scripts.isEmpty ? '' : '（带 ${s.scripts.length} 个脚本）'}').join('\n')}';

  /// `read_skill` 工具。没有开着的技能时返回 null（工具不出现）。
  /// [scriptEnv]：现在脚本能在哪跑（每次读的时候现问）；不给就不提脚本。
  ExtraTool? tool(List<Skill> skills, {SkillScriptEnv Function()? scriptEnv}) => skills.isEmpty
      ? null
      : ExtraTool(
          spec: toolSpec(
            'read_skill',
            '读取一个技能的完整说明（SKILL.md）。',
            {
              'name': {'type': 'string', 'description': '技能名：${skills.map((s) => s.name).join('、')}'},
            },
            ['name'],
          ),
          kind: ToolKind.read,
          run: (args) async {
            final name = AgentToolbox.argString(args, 'name').trim();
            final skill = skills.where((s) => s.name == name).firstOrNull;
            if (skill == null) return ToolOutcome('错误：没有叫 $name 的技能。可用的有：${skills.map((s) => s.name).join('、')}', ok: false);
            final text = await readFull(skill);
            // 附带的脚本现扫一遍（技能文件可能刚被改过），说明接在全文后面。
            final note = scriptEnv == null ? '' : skillScriptNote(name: skill.name, hostDir: skill.dir, files: scanSkillFilesSync(skill.dir), env: scriptEnv());
            return ToolOutcome('$text$note');
          },
        );
}
