/// 现在有哪些语言的生成器。加一种语言：写好它的 `BackendTarget`，在 [backendTargets] 里加一行。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_strict_target.dart';
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

/// 严格规矩的后端文档走不走新的生成（“接口服务”库那条路）。默认跟着 [kLangStrictBackendGen]；测试里可以改，测完改回去。
bool beStrictBackendGen = kLangStrictBackendGen;

/// 新建的后端文档用哪个规矩版本。默认跟着 [kLangRulesForNewDocs]（现在是 2，严格规矩）；考老规矩行为的测试里可以改成 1，测完改回去。
int beNewDocRules = kLangRulesForNewDocs;

/// 严格规矩的生成关着的时候（现在默认开着，只有把开关改回去或者测试里关掉才会走到），严格文档为什么不生成、不启动（给人看的原话）。
const String kBeStrictGenPending = '这份积木用的是严格规矩，严格规矩的代码生成还没有接上：照老办法生成的话，除以 0 还是得 0，“变成整数 / 是空就用 / 一定不是空”这几块也生成不出来，和标红说的对不上。所以代码没有更新（上一次生成的文件原样留着）';

/// 这份文档是不是“严格规矩、但严格生成关着”。
bool beStrictGenPending(BeDocument doc) => !beStrictBackendGen && langRulesStrict(doc.rules);

/// 这份文档用哪个生成器：严格规矩的（并且严格生成开着）用 [StrictBackendTarget]，别的用老的。`language` 不给就用文档里选的。
/// 这种语言还没有生成器返回 null。
BackendTarget? backendTargetOf(BeDocument doc, {String? language}) => backendTargetForRules(language ?? doc.language, doc.rules);

/// 同上，手里只有语言和规矩版本的时候用。
BackendTarget? backendTargetForRules(String language, int rules) {
  final base = backendTargetFor(language);
  if (base == null) return null;
  return beStrictBackendGen && langRulesStrict(rules) && kBeStrictFiles.containsKey(language) ? StrictBackendTarget(base) : base;
}

/// 按文档选的语言（或指定的 `language`）生成小工程。这种语言还没有生成器返回 null。
BeGenerated? generateBackend(BeDocument doc, {String? language}) {
  final target = backendTargetOf(doc, language: language);
  if (target == null) return null;
  return (target: target, files: target.generate(doc));
}
