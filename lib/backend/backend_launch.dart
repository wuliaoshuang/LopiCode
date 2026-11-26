/// 在应用的终端里启动后端：拼出要执行的那一行命令、找（或新开）一个专门跑后端的终端、把命令打进去。
///
/// 这里只管“打字”。点“运行”时先核对对应语言的工具（node / python3 / go / java+javac / php）装没装、没装就自动装，
/// 是 lib/state/backend_run.dart 的事。
library;

import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_project.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/terminal/terminal_session.dart';

/// 专门跑后端的那个终端叫什么（终端页的会话标签上显示）。
const String kBackendTerminalTitle = '后端';

/// 每个工作区记着自己那个“后端终端”（工作区关掉它也跟着没了）。
final Expando<TerminalSession> _backendTerminal = Expando('backendTerminal');

/// 从工作区根目录出发启动这份后端的一整行命令；这种语言没有生成器返回 null。
///
/// 后端在子目录里时整行包在括号里（`(cd server && node server.js)`）：这样停掉以后终端还在工作区根目录，
/// 再启动一次不会因为“已经在 server 里了”而 cd 失败。端口写在命令里的语言（PHP）用文档里的端口。
String? backendLaunchCommand(BeDocument doc, {String dir = ''}) {
  final info = BackendProjectInfo(
    file: dir.isEmpty ? kBackendFileName : '$dir/$kBackendFileName',
    dir: dir,
    readable: true,
    name: doc.name,
    language: doc.language,
    port: doc.port,
    target: backendTargetOf(doc),
  );
  final line = info.terminalCommand;
  if (line == null) return null;
  return dir.isEmpty ? line : '($line)';
}

/// 找到（没有就新开）那个专门跑后端的终端，并切到它。`fresh`＝是不是这次新开的。
///
/// 安卓上运行环境还没装好时开不了终端（不再用手机自带的 sh）：返回 null。
({TerminalSession terminal, bool fresh})? backendTerminal(ProjectSession session) {
  final known = _backendTerminal[session];
  final at = known == null ? -1 : session.terminals.indexOf(known);
  if (known != null && at >= 0) {
    session.selectTerminal(at);
    return (terminal: known, fresh: false);
  }
  final fresh = session.addTerminal();
  if (fresh == null) return null;
  fresh.title = kBackendTerminalTitle;
  _backendTerminal[session] = fresh;
  return (terminal: fresh, fresh: true);
}

/// 把命令打进“后端终端”并回车。第一次新开一个终端；之后复用它——先发一个 Ctrl+C 把上次还在跑的服务停掉，再启动。
/// 返回用的那个终端（调用方接着切到终端页）。
///
/// 这里只“打字”。要“工具没装就先装好再启动”，走 `backendRunProvider`（lib/state/backend_run.dart），它最后也是调这里。
///
/// [justOpened]：这一次“运行”里刚新开的那个终端（里面还没跑过东西），用的还是它就不用先 Ctrl+C。
///
/// 安卓上运行环境还没装好时开不了终端：什么都不打，返回 null。
TerminalSession? launchBackendInTerminal(ProjectSession session, String command, {TerminalSession? justOpened}) {
  final found = backendTerminal(session);
  if (found == null) return null;
  if (!found.fresh && !identical(found.terminal, justOpened)) found.terminal.sendText('\x03');
  found.terminal.run(command);
  return found.terminal;
}
