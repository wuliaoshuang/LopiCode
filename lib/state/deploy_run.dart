// “构建与部署”三种方式共用的东西：这个工作区是什么类型（[deployProjectProvider]）、
// 选的哪种方式、一次运行的进度快照 [DeployRunState]。
//
// 三种方式各有一个 Notifier（deploy_local.dart / deploy_github.dart / deploy_ssh.dart），快照长得一样，
// 界面用同一张进度卡显示。
import 'package:lopicode/build/deploy_project.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:riverpod/riverpod.dart';

/// 后端项目的三种方式（标签和打 APK 的不一样）。
enum DeployMode {
  local('local', '本地构建', '在手机的 Ubuntu 环境里做：能编译的编译成程序，不用编译的检查语法后打成压缩包。产物放在工作区的 build 目录。'),
  github('github', 'GitHub 部署', '把代码推送到 GitHub 仓库，再启动部署工作流：在 GitHub 的机器上构建，要不要接着部署到服务器由你定。'),
  ssh('ssh', 'SSH 部署', '把代码传到你的服务器，在服务器上编译、装依赖，需要的话重启服务。每一步的命令会先给你看。');

  const DeployMode(this.id, this.label, this.about);
  final String id;
  final String label;
  final String about;

  static DeployMode byId(String id) => DeployMode.values.firstWhere((m) => m.id == id, orElse: () => DeployMode.local);
}

String deployKey(String key, ProjectSession session) => SettingKeys.perProject(key, session.project.id);

/// 这个工作区是什么类型的项目。文件变了、手动改了类型都会重新认。
final deployProjectProvider = Provider.family<DeployProject, ProjectSession>((ref, session) {
  ref.watch(filesRevProvider(session));
  final key = deployKey(SettingKeys.deployKind, session);
  ref.watch(settingRevProvider(key));
  final project = session.project;
  return detectDeployProject(project.dir, template: project.template, templateLanguage: project.language, override: ProjectKind.fromSetting(ref.watch(settingsStoreProvider).getString(key)));
});

/// 后端项目选的哪种方式（按工作区记）。
final deployModeProvider = Provider.family<DeployMode, ProjectSession>((ref, session) {
  final key = deployKey(SettingKeys.deployMode, session);
  ref.watch(settingRevProvider(key));
  return DeployMode.byId(ref.watch(settingsStoreProvider).getString(key));
});

enum DeployPhase { idle, running, failed, cancelled, done }

enum StepStatus { pending, running, ok, failed }

class DeployStepState {
  const DeployStepState(this.title, {this.status = StepStatus.pending, this.command});
  final String title;
  final StepStatus status;

  /// 这一步执行的命令全文（没有命令行的步骤是 null）。
  final String? command;
  DeployStepState withStatus(StepStatus s) => DeployStepState(title, status: s, command: command);
}

/// 成了以后给用户看的结果。
class DeployResult {
  const DeployResult({required this.headline, this.fileName, this.bytes, this.location, this.url, this.notes = const []});
  final String headline;
  final String? fileName;
  final int? bytes;

  /// 产物在哪（相对工作区，或远程目录）。
  final String? location;

  /// GitHub 运行页的地址。
  final String? url;

  /// “怎么用”的几句话。
  final List<String> notes;
}

/// 日志最多留这么多字符（自定）；超了丢前面的。
const int kDeployLogMax = 60000;

class DeployRunState {
  const DeployRunState({this.phase = DeployPhase.idle, this.headline = '', this.steps = const [], this.log = '', this.failure, this.needsRuntime = false, this.ask, this.result, this.url});

  final DeployPhase phase;

  /// 现在在做什么（一句话）。
  final String headline;
  final List<DeployStepState> steps;
  final String log;

  /// 没成的原因（大白话，说清停在哪一步）。
  final String? failure;

  /// 没成是因为运行环境没装 / 进不去：界面给“去装运行环境”的按钮。
  final bool needsRuntime;

  /// 正等用户点头的问题（装大的语言包之前）；没在等是 null。
  final String? ask;
  final DeployResult? result;

  /// GitHub 运行页的地址（失败时也给，方便去看日志）。
  final String? url;

  bool get busy => phase == DeployPhase.running;

  DeployRunState copyWith({
    DeployPhase? phase,
    String? headline,
    List<DeployStepState>? steps,
    String? log,
    String? Function()? failure,
    bool? needsRuntime,
    String? Function()? ask,
    DeployResult? result,
    String? url,
  }) => DeployRunState(
    phase: phase ?? this.phase,
    headline: headline ?? this.headline,
    steps: steps ?? this.steps,
    log: log ?? this.log,
    failure: failure != null ? failure() : this.failure,
    needsRuntime: needsRuntime ?? this.needsRuntime,
    ask: ask != null ? ask() : this.ask,
    result: result ?? this.result,
    url: url ?? this.url,
  );

  DeployRunState addLog(String chunk) {
    // 终端控制序列（颜色、回车）去掉，日志框里只留字。
    final clean = chunk.replaceAll(RegExp('\x1b\\[[0-9;?]*[A-Za-z]'), '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (clean.isEmpty) return this;
    final next = log + clean;
    return copyWith(log: next.length > kDeployLogMax ? next.substring(next.length - kDeployLogMax) : next);
  }

  DeployRunState mark(int index, StepStatus status) => copyWith(
    steps: [
      for (var i = 0; i < steps.length; i++)
        if (i == index) steps[i].withStatus(status) else steps[i],
    ],
  );
}

/// 三个 Notifier 共用的骨架：代次、活没活着、只在活着时写状态。
mixin DeployRunBase on Notifier<DeployRunState> {
  ProjectSession get session;
  DeployRunState snap = const DeployRunState();
  int gen = 0;

  bool get alive => ref.mounted && !session.disposed && !session.app.disposed;

  /// 最近一份状态（工作区关掉以后也能读）。
  DeployRunState get current => snap;

  void put(DeployRunState next) {
    snap = next;
    if (alive) state = next;
  }

  DeployRunState initial() {
    ref.onDispose(() => gen++);
    return snap = const DeployRunState();
  }

  /// 把上一次的结果 / 失败收起来（进行中不受理）。
  void reset() {
    if (snap.busy) return;
    put(const DeployRunState());
  }
}
