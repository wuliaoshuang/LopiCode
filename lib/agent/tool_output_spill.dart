// 任何工具的结果太长时：全文存到工作区的 `.lopicode/outputs/tool-….txt`，回给模型的是开头 + 结尾 + 文件路径 + 怎么接着看。
// （run_command 自己在 8000 字就转存了，文件名是 cmd-…，见 command_output_store.dart；这里管的是其余所有工具的兜底。）
//
// 规矩：
// - 上限沿用原来的兜底 [kMaxToolResultChars]（24000 字）；回给模型的头尾合起来也是这么多。
// - 用 read_file 读转存目录里的文件（含后台命令的日志）本身超长时，**不再套一层存文件**：全文本来就在那个文件里，
//   只截成头尾并提醒按行分段读——否则读一次生一个新文件，没完没了。
// - 存不了（磁盘满、目录建不出来）不影响工具结果：退回原来的“只留头尾”。
// - 存之前不做额外处理（和命令输出一致）；文件内容不进日志。
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/core/path_guard.dart';

/// 超长时回给模型的开头、结尾各多少字符（合起来等于 [kMaxToolResultChars]）。
const int kToolSpillHeadChars = 16000;
const int kToolSpillTailChars = kMaxToolResultChars - kToolSpillHeadChars;

/// 超长结果回给模型的样子。[rel] 是转存文件的相对路径。
String spilledToolText(String text, String rel) {
  final skipped = text.length - kToolSpillHeadChars - kToolSpillTailChars;
  final lines = '\n'.allMatches(text).length + 1;
  // 命令是在项目目录里执行的（Ubuntu 里默认项目是 /workspace，Linux 项目是它自己的目录），所以写相对路径在哪种环境都对。
  final how =
      '完整结果（共 ${text.length} 字符、$lines 行）已存到 $rel。要看被省略的部分：用 read_file 读这个文件并带 start_line / end_line 一段一段读，不要一次读完；'
      '或者用 run_command 在这个文件里检索，例如 grep -n "关键词" $rel（命令在项目目录里执行，路径照这样写就行）。';
  return '${text.substring(0, kToolSpillHeadChars)}\n\n…（结果太长，中间省略了 $skipped 字符。$how）…\n\n${text.substring(text.length - kToolSpillTailChars)}';
}

/// 这次调用是不是在读转存目录里的文件（读它的结果不再转存）。
bool _readsSpilledFile(PathGuard guard, String name, Map<String, dynamic> args) {
  final path = args['path'];
  if (name != 'read_file' || path is! String) return false;
  try {
    return isCommandOutputPath(guard.relative(guard.resolve(path, allowReserved: true)));
  } on PathGuardException {
    return false;
  }
}

/// 工具结果的兜底：不超过上限原样返回；超了就转存并换成头尾 + 路径。
Future<ToolOutcome> spillLongResult(PathGuard guard, String name, Map<String, dynamic> args, ToolOutcome outcome) async {
  final text = outcome.text;
  if (text.length <= kMaxToolResultChars) return outcome;
  if (_readsSpilledFile(guard, name, args)) {
    return outcome.withText('${clipToolResult(text)}\n（这已经是转存的完整输出文件，不会再另存一份；请用 start_line / end_line 缩小范围分段读。）');
  }
  final rel = await CommandOutputStore(guard).saveToolResult(text);
  return outcome.withText(rel == null ? clipToolResult(text) : spilledToolText(text, rel));
}
