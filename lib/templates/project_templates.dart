/// 模板目录里各模板的文件怎么来、要选语言的模板有哪些语言可选、怎么照模板建项目。
///
/// 目录本身（名字、说明、分组、图标）在 lib/core/templates.dart；内置的三个（空项目 / 前端网页 / 低代码页面）的文件也在那里。
/// 这里管用到 lib/backend 的那几个——core 不许依赖 backend，所以放在 core 外面，由“新建项目”的地方调 [createProjectFromTemplate]。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_templates.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/templates/code_starters.dart';
import 'package:lopicode/templates/fullstack_web.dart';

/// 新建项目时能选的一种语言。
class TemplateLanguage {
  const TemplateLanguage({required this.id, required this.label, required this.summary, required this.verified});

  /// 语言 id，也是图标 id（`FileIcon.language`）。
  final String id;
  final String label;

  /// 用什么写的，一句话。
  final String summary;

  /// 有没有在本机实际运行验证过。
  final bool verified;
}

/// 这个模板能选哪些语言（不用选语言的模板返回空表）。后端积木的直接取现有的生成器：别人注册了新语言，这里自动出现。
List<TemplateLanguage> templateLanguages(ProjectTemplate template) => switch (template.languages) {
  TemplateLanguageSource.none => const [],
  TemplateLanguageSource.blockTargets => [for (final t in backendTemplateTargets) TemplateLanguage(id: t.id, label: t.label, summary: t.summary, verified: t.verified)],
  TemplateLanguageSource.codeStarters => [for (final s in codeStarters) TemplateLanguage(id: s.id, label: s.label, summary: s.summary, verified: s.verified)],
};

/// 没指定语言（或指定的不在表里）时用哪种：表里的第一种。不用选语言的模板返回 null。
String? resolveTemplateLanguage(ProjectTemplate template, String? language) {
  final options = templateLanguages(template);
  if (options.isEmpty) return null;
  for (final o in options) {
    if (o.id == language) return o.id;
  }
  return options.first.id;
}

/// 模板 → 要写入的文件（相对路径 → 内容）。任何模板、任何语言都给得出来（语言不认识就用该模板的第一种）。
Map<String, String> projectTemplateFiles(ProjectTemplate template, String name, {String? language}) {
  final lang = resolveTemplateLanguage(template, language);
  switch (template) {
    case ProjectTemplate.empty:
    case ProjectTemplate.web:
    case ProjectTemplate.lowcode:
      return templateFiles(template, name)!;
    case ProjectTemplate.backendBlocks:
      return backendBlocksTemplateFiles(name, lang!) ?? _fallback(name);
    case ProjectTemplate.backendCode:
      return codeStarterFor(lang!)?.files(name) ?? _fallback(name);
    case ProjectTemplate.fullstack:
      final server = backendBlocksTemplateFiles(name, lang!, dir: 'server');
      final target = backendTargetForRules(lang, beNewDocRules);
      if (server == null || target == null) return _fallback(name);
      final command = ['cd server', for (final c in target.buildCommands) c.join(' '), target.startCommand.join(' ')].join(' && ');
      return {
        'README.md': fullstackReadme(name, languageLabel: target.label, serverCommand: command, port: kBeDefaultPort, verified: target.verified),
        ...fullstackWebFiles(name, port: kBeDefaultPort),
        ...server,
      };
  }
}

/// 一种语言都没有时（理论上不会：生成器表不会是空的）的兜底，免得建出一个空目录。
Map<String, String> _fallback(String name) => templateFiles(ProjectTemplate.empty, name)!;

/// 照模板新建项目：生成文件、建项目、给后端积木的项目记下“这些文件是生成的”（之后重新生成才认得出哪些没被手改过）。
/// 项目名不合规矩等问题照 `ProjectStore.create` 抛 [ProjectException]。
Future<Project> createProjectFromTemplate(ProjectStore store, String name, ProjectTemplate template, {String? language}) async {
  final lang = resolveTemplateLanguage(template, language);
  final cleanName = ProjectStore.validateName(name);
  final project = await store.create(
    cleanName,
    template,
    files: projectTemplateFiles(template, cleanName, language: lang),
    language: lang,
  );
  if (template == ProjectTemplate.backendBlocks || template == ProjectTemplate.fullstack) {
    // 内容和刚写进去的一模一样，所以这一步不会改任何代码文件，只是把校验值记进 .lopicode/backend-gen.json。
    await regenerateBackend(project.dir);
  }
  return project;
}
