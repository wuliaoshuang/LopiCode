/// 现在有哪些语言的生成器。加一种语言：写好它的 `BackendTarget`，在 [backendTargets] 里加一行。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_target.dart';
import 'package:lopicode/backend/target_go.dart';
import 'package:lopicode/backend/target_java.dart';
import 'package:lopicode/backend/target_node.dart';
import 'package:lopicode/backend/target_php.dart';
import 'package:lopicode/backend/target_python.dart';

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

/// 按文档选的语言（或指定的 `language`）生成小工程。这种语言还没有生成器返回 null。
BeGenerated? generateBackend(BeDocument doc, {String? language}) {
  final target = backendTargetFor(language ?? doc.language);
  if (target == null) return null;
  return (target: target, files: target.generate(doc));
}
