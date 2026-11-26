/// 现在有哪些语言的生成器。加一种语言：写好它的 `BackendTarget`，在 [backendTargets] 里加一行。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/target_go.dart';
import 'package:lopicode/backend/target_java.dart';
import 'package:lopicode/backend/target_node.dart';
import 'package:lopicode/backend/target_php.dart';
import 'package:lopicode/backend/target_python.dart';
import 'package:lopicode/lang/rules.dart';

export 'package:lopicode/backend/backend_target.dart' show BackendTarget;

/// 全部生成器，按界面上的顺序。
const List<BackendTarget> backendTargets = [NodeBackendTarget(), PythonBackendTarget(), GoBackendTarget(), JavaBackendTarget(), PhpBackendTarget()];

/// 按语言 id 找生成器；没有返回 null。
BackendTarget? backendTargetFor(String language) {
  for (final t in backendTargets) {
    if (t.id == language) return t;
  }
  return null;
}

/// 生成的结果：用的哪种语言 + 文件（相对路径 → 内容）。
typedef BeGenerated = ({BackendTarget target, Map<String, String> files});

/// 严格规矩的文档现在为什么不生成、不启动（给人看的原话）。
const String kBeStrictGenPending = '这份积木用的是严格规矩，严格规矩的代码生成还没有接上：照老办法生成的话，除以 0 还是得 0，“变成整数 / 是空就用 / 一定不是空”这几块也生成不出来，和标红说的对不上。所以代码没有更新（上一次生成的文件原样留着）';

/// 这份文档是不是“严格规矩、但后端的严格生成还没接上”。
bool beStrictGenPending(BeDocument doc) => !kLangStrictBackendGen && langRulesStrict(doc.rules);

/// 按文档选的语言（或指定的 `language`）生成小工程。这种语言还没有生成器返回 null。
BeGenerated? generateBackend(BeDocument doc, {String? language}) {
  final target = backendTargetFor(language ?? doc.language);
  if (target == null) return null;
  return (target: target, files: target.generate(doc));
}
