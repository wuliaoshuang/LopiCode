// 设计约束（APK 打包 · 390×844）— 2026-11-26 重做（霜霜：原来的“有点丑”，并要求加全程在手机上完成的本地打包）
//
// 内容排序（Refactoring UI：先定层级，再排版，最后上色）
//   主要：用哪种方式打（最上面三选一）→ 这种方式要填的东西 → 唯一的主按钮“开始打包”→ 进度 / 结果卡。
//   次要：这种方式是怎么回事（选择下面一句弱色小字，不再是占半屏的灰色大块）。
//   再次：每项输入下面的一句说明。
// 三种方式：本地打包（排第一，没选过时默认是它）、GitHub Actions、SSH 构建机。选哪个，下面只出现那一种的表单；
//   三张表单都一直留着（只是不显示），所以切走再切回来，填到一半的内容和上一次的结果都还在。
//   任何一种正在打包时，三选一锁住（不然切走就看不到进度了）。
// 一行只做一件事：输入各占一行；开关、跳转各占一行；模板、权限、图标收进底部面板，钥匙是单独一页。
// 排版：和设置页同一套——浅灰底（canvas）上放白色分组卡片；页边 16，组与组相隔 24，组标题是弱色小字。
//   分组标题里的 ①②③ 留着（小字），告诉人从上往下做；它们不再是和正文抢戏的大标题。
// 颜色：强调色只给三样——选中的方式、主按钮、“完成”；红色只给失败和危险操作；其余是正文色和两档弱色。
// 顶栏：全应用那一套（ShellAppBar → PageBar），内容从顶栏下面滚过去。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/github_build_view.dart';
import 'package:lopicode/build/local_pack_view.dart';
import 'package:lopicode/build/ssh_build_controller.dart';
import 'package:lopicode/build/ssh_build_view.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

class BuildScreen extends ConsumerStatefulWidget {
  const BuildScreen({super.key, required this.session, this.debugController});
  final ProjectSession session;

  /// 测试 / 截图用：直接展示某个远程打包任务的状态（页面会切到它对应的那种方式）。
  final BuildJob? debugController;

  @override
  ConsumerState<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends ConsumerState<BuildScreen> {
  BuildMode _mode = BuildMode.local;
  bool _loaded = false;
  ApkBuildController? _githubJob;
  SshBuildController? _sshJob;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final debug = widget.debugController;
    // 没存过＝本地打包（2026-11-26 以前没存过是 GitHub）；原来存了 github / ssh 的照旧。
    _mode = switch (debug) {
      SshBuildController() => BuildMode.ssh,
      ApkBuildController() => BuildMode.github,
      _ => BuildMode.fromSetting(appOf(context).settings.getString(SettingKeys.apkBuildMode)),
    };
    if (debug is SshBuildController) _sshJob = debug..onChanged = _onJob;
    if (debug is ApkBuildController) _githubJob = debug..onChanged = _onJob;
  }

  @override
  void dispose() {
    _githubJob?.onChanged = null;
    _sshJob?.onChanged = null;
    super.dispose();
  }

  void _onJob() {
    if (mounted) setState(() {});
  }

  void _setMode(BuildMode mode) {
    setState(() => _mode = mode);
    appOf(context).settings.setLater(SettingKeys.apkBuildMode, mode.id);
  }

  /// “改用远程打包”：配过构建机的去 SSH，没配过的去 GitHub Actions。
  void _useRemote() => _setMode(SshConfig.load(appOf(context).settings).isComplete ? BuildMode.ssh : BuildMode.github);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final localBusy = ref.watch(localPackProvider(widget.session).select((s) => s.busy));
    final busy = localBusy || (_githubJob?.busy ?? false) || (_sshJob?.busy ?? false);
    final about = switch (_mode) {
      BuildMode.local => '就在这台手机上打包，几秒出包，不用联网。只适合网页项目：把网页装进一个现成的应用壳里。',
      BuildMode.github => '手机上跑不了 Android SDK 和 Gradle，要编译的项目不能在手机里打包：LopiCode 把项目推到你的 GitHub 仓库，让 GitHub Actions 打包，再把 APK 下载回来。',
      BuildMode.ssh => '手机上跑不了 Android SDK 和 Gradle，要编译的项目不能在手机里打包：LopiCode 通过 SSH 连到你的服务器，在上面运行构建命令，再把 APK 拉回手机。',
    };
    Widget section(BuildMode mode, Widget child) => Offstage(
      offstage: _mode != mode,
      child: TickerMode(enabled: _mode == mode, child: child),
    );
    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: ShellAppBar(title: 'APK 打包', background: c.canvas),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x8),
        children: [
          BuildModePicker(mode: _mode, onChanged: busy ? null : _setMode),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x1, Space.x3, Space.x1, Space.x6),
            child: Text(
              about,
              key: const Key('pack-mode-about'),
              style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.6),
            ),
          ),
          section(BuildMode.local, LocalPackView(session: widget.session, onUseRemote: _useRemote)),
          section(
            BuildMode.github,
            GithubBuildView(
              session: widget.session,
              job: _githubJob,
              onJob: (job) {
                _githubJob?.onChanged = null;
                setState(() => _githubJob = job..onChanged = _onJob);
              },
            ),
          ),
          section(
            BuildMode.ssh,
            SshBuildView(
              session: widget.session,
              job: _sshJob,
              onJob: (job) {
                _sshJob?.onChanged = null;
                setState(() => _sshJob = job..onChanged = _onJob);
              },
            ),
          ),
          if (_mode != BuildMode.local && widget.session.project.template == ProjectTemplate.lowcode)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x1, Space.x3, Space.x1, 0),
              child: Text('低代码页面会按“网页套壳”的方式打包（用导出的 index.html）。', style: t.bodySmall?.copyWith(color: c.textFaint)),
            ),
        ],
      ),
    );
  }
}
