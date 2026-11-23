// 一个工作区的“文件变了”信号。
//
// 谁改了项目文件（编辑器保存、Agent 写文件、低代码保存、打包下载、导出对话）就调一次
// `session.filesChanged()`；文件树和预览用 `ref.listen(filesRevProvider(session), …)` 跟着刷新。
import 'package:lopicode/project_session.dart';
import 'package:riverpod/riverpod.dart';

class FilesRev extends Notifier<int> {
  FilesRev(this.session);
  final ProjectSession session;

  @override
  int build() => 0;

  /// 项目文件有变化。工作区关掉以后不再通知。
  void bump() {
    if (ref.mounted && !session.disposed) state = state + 1;
  }
}

/// 某个工作区的文件变动次数（按工作区分身）。
final filesRevProvider = NotifierProvider.family<FilesRev, int, ProjectSession>(FilesRev.new);
