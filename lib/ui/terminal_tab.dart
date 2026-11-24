// 设计约束（终端 · 390×844）
// - 屏幕几乎全留给终端：xterm 仿真，等宽 13px，深浅色都用 codeBg。点一下屏幕弹键盘，直接打字。
// - 顶上一行只管“会话”：会话标签 + 新建（Ubuntu 环境 / SSH 远程主机；桌面调试时还有本机 shell）。
// - 安卓上不用手机自带的命令行（没有 git、node、python）。平台判断只在 LinuxRuntime.localShellAllowed 一处：
//   · 运行环境没装好、也没有别的会话：整页换成安装引导（lib/ui/terminal_setup_view.dart），会话行和按键行都不出现；
//   · 装了但 Ubuntu 没起来：会话行还在，终端区换成“启动失败”页（原因 + 重试 / 兼容模式重试 / 一键诊断 / 连接 SSH）；
//   · 桌面平台和宿主机测试：和以前一样可以开本机 shell（开发调试用）。
// - 底下一排手机键盘没有的键（Esc / Tab / Ctrl / 方向键 / 常用符号 / 清屏），横向可滚。
//   Ctrl 是粘滞键：点亮后下一个字母变成控制字符（Ctrl 再点 C = 中断）。
//   “中文”也在这排：默认每按一个键立刻进终端；点亮后才让输入法攒拼音选字。
// - Ubuntu 进去后一直没输出：终端下方出一条提示，三个出路各占一个按钮，不让人对着空屏
//   （兼容模式重试、去做一键诊断，第三个在安卓上是“连接 SSH”，桌面上是“先用本机 shell”）。
// - 点了后端“运行”而工具还没装：会话行下面多一条“正在检查 / 正在安装 … · 取消”（lib/ui/backend_run_bar.dart），
//   安装的输出就在下面的终端里；没事的时候这条不出现。
// - 没有单独的输入行：真正的终端里输入就在光标处。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/state/workspace_terminals.dart';
import 'package:lopicode/terminal/terminal_input.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/backend_run_bar.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_setup_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xterm/xterm.dart';

class TerminalTab extends ConsumerStatefulWidget {
  const TerminalTab({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends ConsumerState<TerminalTab> {
  final _focus = FocusNode();
  TerminalSession? _startedFor;

  ProjectSession get s => widget.session;
  // 一个会话都没有是正常状态（安卓上运行环境没装好）：这时是 null，页面显示安装引导。
  // 工作区刚关掉的那一帧列表也是空的：先用着上一个，免得闪一下。
  TerminalSession? get _term => ref.read(terminalsProvider(s)).current ?? (appOf(context).runtime.needsSetup ? null : _startedFor);

  @override
  void initState() {
    super.initState();
    _startCurrent();
    // 换了当前会话（新开、切换、关掉）：等它排完版再启动 shell
    ref.listenManual(terminalsProvider(s).select((v) => v.current), (_, _) => _startCurrent());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startCurrent() {
    final term = ref.read(terminalsProvider(s)).current;
    if (term == null || identical(_startedFor, term)) return;
    // 等第一帧排完版、终端知道自己有几行几列，再启动 shell。
    final target = _startedFor = term;
    WidgetsBinding.instance.addPostFrameCallback((_) => target.ensureStarted());
  }

  Future<void> _newSsh() async {
    final navigator = Navigator.of(context);
    final config = await navigator.push<SshConfig>(MaterialPageRoute(builder: (_) => const SshConnectScreen()));
    if (config == null || !mounted) return;
    s.addSshTerminal(config, onUnknownHost: (config, type, fingerprint) async => mounted ? confirmHostKey(navigator.context, config, type, fingerprint) : false);
  }

  void _newSession() {
    final saved = SshConfig.load(appOf(context).settings);
    final runtime = appOf(context).runtime;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (runtime.usable)
              ListTile(
                key: const Key('new-linux-session'),
                leading: const Icon(Icons.memory_outlined),
                title: const Text('Ubuntu 环境'),
                subtitle: const Text('能跑 node、python，项目目录在 /workspace'),
                onTap: () {
                  Navigator.pop(context);
                  appOf(this.context).runtime.resetLaunchFailures();
                  s.addTerminal();
                },
              ),
            // 还没装运行环境（这时开着的只会是 SSH 会话）：给一个去装的入口
            if (runtime.needsSetup)
              ListTile(
                key: const Key('new-session-install-runtime'),
                leading: const Icon(Icons.download_outlined),
                title: const Text('安装 Ubuntu 运行环境'),
                subtitle: const Text('装好后终端里能用 git、node、python'),
                onTap: () {
                  Navigator.pop(context);
                  ShellScope.maybeOf(this.context)?.go(ShellDest.runtime);
                },
              ),
            // 本机 shell 只在桌面调试 / 宿主机测试时有（见 LinuxRuntime.localShellAllowed）；安卓上没有这个入口
            if (runtime.localShellAllowed)
              ListTile(
                key: const Key('new-local-session'),
                leading: const Icon(Icons.computer_outlined),
                title: const Text('本机 shell'),
                subtitle: const Text('这台机器自带的 shell，在项目目录里打开'),
                onTap: () {
                  Navigator.pop(context);
                  s.addTerminal(forceLocal: true);
                },
              ),
            ListTile(
              key: const Key('new-ssh-session'),
              leading: const Icon(Icons.dns_outlined),
              title: const Text('SSH 远程主机'),
              subtitle: Text(saved.isComplete ? '上次：${saved.display}（可以改）' : '连到一台有完整工具链的服务器'),
              onTap: () {
                Navigator.pop(context);
                _newSsh();
              },
            ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }

  TerminalTheme _theme(AppColors c, bool dark) => TerminalTheme(
    cursor: c.accent,
    selection: c.accent.withValues(alpha: 0.3),
    foreground: c.text,
    background: c.codeBg,
    black: dark ? const Color(0xFF35394C) : const Color(0xFF222435),
    red: dark ? const Color(0xFFFE7FB6) : const Color(0xFFC6212F),
    green: dark ? const Color(0xFF5DEEDB) : const Color(0xFF017B43),
    yellow: dark ? const Color(0xFFFFE068) : const Color(0xFF893300),
    blue: dark ? const Color(0xFF8AB4F8) : const Color(0xFF1F5FBF),
    magenta: dark ? const Color(0xFFD7A6F5) : const Color(0xFF8A3FBF),
    cyan: dark ? const Color(0xFF9BFFF8) : const Color(0xFF0A7C8C),
    white: dark ? const Color(0xFFD3DEE4) : const Color(0xFF5C6479),
    brightBlack: dark ? const Color(0xFF707A8F) : const Color(0xFF5C6479),
    brightRed: dark ? const Color(0xFFFE7FB6) : const Color(0xFFAB131E),
    brightGreen: dark ? const Color(0xFF9BFFF8) : const Color(0xFF058654),
    brightYellow: dark ? const Color(0xFFFFE068) : const Color(0xFFA84C00),
    brightBlue: dark ? const Color(0xFFAECBFA) : const Color(0xFF1F5FBF),
    brightMagenta: dark ? const Color(0xFFE5C4FA) : const Color(0xFF8A3FBF),
    brightCyan: dark ? const Color(0xFFEBFFFF) : const Color(0xFF0A7C8C),
    brightWhite: dark ? const Color(0xFFF6FBFD) : const Color(0xFF222435),
    searchHitBackground: c.warningSoft,
    searchHitBackgroundCurrent: c.warning,
    searchHitForeground: c.text,
  );

  @override
  Widget build(BuildContext context) {
    // 会话列表、当前是哪个、Ctrl 的点亮状态、Ubuntu“没有响应”的提示：都从这里订阅
    ref.watch(terminalsProvider(s));
    // 运行环境装没装好：决定显示安装引导还是终端
    final runtime = ref.watch(runtimeProvider);
    final term = _term;
    if (term == null) return runtime.needsSetup ? TerminalSetupView(onConnectSsh: _newSsh, notice: backendRunSetupNotice(ref.watch(backendRunProvider(s)))) : const SizedBox.expand();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final settings = appOf(context).settings;
    final chinese = settings.getBool(SettingKeys.terminalChineseIme);
    final backend = term.backend;
    final stalledBackend = backend is LinuxShellBackend && backend.stalled ? backend : null;
    final failedBackend = backend is LinuxShellBackend && backend.failure != null ? backend : null;
    // 平时只剩一个会话时不让关；没装运行环境时（剩下的只会是 SSH 会话）可以关到一个不剩，回到安装引导
    final closable = s.terminals.length > 1 || runtime.needsSetup;
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  itemCount: s.terminals.length,
                  itemBuilder: (context, i) {
                    final active = i == s.activeTerminal;
                    return Padding(
                      padding: const EdgeInsets.only(right: Space.x2, top: 4, bottom: 4),
                      child: Material(
                        color: active ? c.accentSoft : c.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          side: BorderSide(color: active ? Colors.transparent : c.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => s.selectTerminal(i),
                          child: Padding(
                            padding: EdgeInsets.only(left: Space.x3, right: closable ? Space.x1 : Space.x3),
                            child: Row(
                              children: [
                                Text(s.terminals[i].title, style: t.labelLarge?.copyWith(color: active ? c.accent : c.textMuted)),
                                if (closable)
                                  IconButton(
                                    tooltip: '关闭会话',
                                    onPressed: () => s.closeTerminal(i),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(34, 34),
                                      fixedSize: const Size(34, 34),
                                      padding: EdgeInsets.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      foregroundColor: c.textFaint,
                                    ),
                                    icon: const Icon(Icons.close, size: 14),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: '新建会话',
                icon: Icon(Icons.add, color: c.accent),
                onPressed: _newSession,
              ),
              const SizedBox(width: Space.x1),
            ],
          ),
        ),
        // 点了后端“运行”、正在替她配工具时的一条：现在在干什么 + 取消 / 确认 / 重试（见 backend_run_bar.dart）
        BackendRunBar(session: s),
        if (failedBackend != null)
          Expanded(
            child: TerminalFailureView(backend: failedBackend, reason: failedBackend.failure!, onConnectSsh: _newSsh, projectDir: s.project.dir),
          )
        else ...[
          Expanded(
            child: ColoredBox(
              color: c.codeBg,
              child: TerminalInputView(
                key: ObjectKey(term),
                session: term,
                focusNode: _focus,
                theme: _theme(c, dark),
                textStyle: const TerminalStyle(fontSize: 13, height: 1.3, fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
                padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
                mode: chinese ? TerminalImeMode.chinese : TerminalImeMode.direct,
              ),
            ),
          ),
          if (stalledBackend != null) _StalledBar(backend: stalledBackend, localShellAllowed: runtime.localShellAllowed, onConnectSsh: _newSsh),
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: ListView(
              key: const Key('terminal-keys'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 4),
              children: [
                _Key('Esc', onTap: () => term.sendKey(TerminalKey.escape)),
                _Key('Tab', tooltip: '补全', onTap: () => term.sendKey(TerminalKey.tab)),
                _Key('Ctrl', tooltip: '点亮后再按字母，例如 Ctrl 再按 C 是中断', active: term.ctrlArmed, onTap: term.toggleCtrl),
                _Key('↑', onTap: () => term.sendKey(TerminalKey.arrowUp)),
                _Key('↓', onTap: () => term.sendKey(TerminalKey.arrowDown)),
                _Key('←', onTap: () => term.sendKey(TerminalKey.arrowLeft)),
                _Key('→', onTap: () => term.sendKey(TerminalKey.arrowRight)),
                for (final ch in const ['/', '-', '|', '~', '>', '&', '*', '"']) _Key(ch, onTap: () => term.sendText(ch)),
                _Key(
                  '中文',
                  tooltip: '点亮后输入法可以打拼音选字；不点亮时每按一个键立刻进终端',
                  active: chinese,
                  onTap: () {
                    settings.setLater(SettingKeys.terminalChineseIme, !chinese); // 内存里立刻生效，写盘在后台
                    setState(() {});
                  },
                ),
                _Key('清屏', onTap: term.clear),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label, {required this.onTap, this.tooltip, this.active = false});
  final String label;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final key = Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? c.accentSoft : c.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: Text(
              label,
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: 13, color: active ? c.accent : c.text),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? key : Tooltip(message: tooltip!, child: key);
  }
}

/// Ubuntu 进去后一直没有输出时的提示条：一行说明，下面三个出路各占一行按钮位。
class _StalledBar extends StatelessWidget {
  const _StalledBar({required this.backend, required this.localShellAllowed, required this.onConnectSsh});
  final LinuxShellBackend backend;

  /// 能不能退回本机 shell（安卓上不能：第二个出路换成“连接 SSH”）。
  final bool localShellAllowed;
  final VoidCallback onConnectSsh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('terminal-stalled'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
      decoration: BoxDecoration(
        color: c.warningSoft,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ubuntu 没有响应', style: t.titleSmall?.copyWith(color: c.warning)),
          const SizedBox(height: 2),
          Text('进去 ${backend.stallTimeout.inSeconds} 秒了一个字都没输出，多半卡在启动这一步。', style: t.bodySmall),
          const SizedBox(height: Space.x2),
          FilledButton(key: const Key('stalled-retry-compat'), onPressed: backend.retryCompat, child: const Text('改用兼容模式重试')),
          Row(
            children: [
              Expanded(
                child: localShellAllowed
                    ? TextButton(key: const Key('stalled-use-local'), onPressed: backend.switchToLocal, child: const Text('先用本机 shell'))
                    : TextButton(key: const Key('stalled-use-ssh'), onPressed: onConnectSsh, child: const Text('连接 SSH')),
              ),
              Expanded(
                child: TextButton(key: const Key('stalled-diagnose'), onPressed: () => ShellScope.maybeOf(context)?.go(ShellDest.runtime), child: const Text('去做一键诊断')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
