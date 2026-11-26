// 设计约束（“安装”按钮 + 它下面的一句话 · 390×844）
// 一个整行宽的主按钮，下面最多一块说明；不弹对话框、不另开页面——打包结果卡和安装包信息面板里都是原地用。
// 按钮上的字跟着走到哪一步变：安装 → 正在交给系统安装器… → （系统还没允许）去设置里允许 → 继续安装 → 再装一次 / 再试一次。
// 说明块：交出去了是弱色底 + 勾；要去设置是警示色底 + 叹号；失败是浅红底 + 叉（不只靠颜色）。文案如实：
//   交给系统安装器以后装没装成我们看不到，就直说看不到。
// 从设置页回来（应用回到前台）会自己再试一次；也可以点“继续安装”。
import 'package:lopicode/build/apk_installer.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

enum _Phase { idle, working, needPermission, waitingSettings, launched, failed }

class ApkInstallButton extends StatefulWidget {
  const ApkInstallButton({super.key, required this.path, this.primary = true, this.idleLabel = '安装'});

  /// 安装包在手机上的完整路径。
  final String path;

  /// false ＝ 画成次要按钮（描边），给“这个文件看着不像安装包，仍然想试”的场合。
  final bool primary;
  final String idleLabel;

  @override
  State<ApkInstallButton> createState() => _ApkInstallButtonState();
}

class _ApkInstallButtonState extends State<ApkInstallButton> with WidgetsBindingObserver {
  _Phase _phase = _Phase.idle;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(ApkInstallButton old) {
    super.didUpdateWidget(old);
    // 换了一个安装包（重新打包了）：上一次的结果不算数了
    if (old.path != widget.path && _phase != _Phase.working) {
      _phase = _Phase.idle;
      _message = null;
    }
  }

  /// 从“允许安装未知应用”设置页回来：自己接着装，不用她再点。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _Phase.waitingSettings) _install(afterSettings: true);
  }

  Future<void> _install({bool afterSettings = false}) async {
    if (_phase == _Phase.working) return;
    setState(() {
      _phase = _Phase.working;
      _message = null;
    });
    final result = await currentApkInstaller().install(widget.path);
    if (!mounted) return;
    setState(() {
      switch (result.status) {
        case ApkInstallStatus.launched:
          _phase = _Phase.launched;
          _message = installStatusText(result.status);
        case ApkInstallStatus.needPermission:
          _phase = _Phase.needPermission;
          _message = afterSettings ? '开关还没打开，所以没装。再去设置里把 LopiCode 的“允许安装未知应用”打开，回来会自动接着装。' : installStatusText(result.status);
        default:
          _phase = _Phase.failed;
          _message = installStatusText(result.status);
      }
    });
  }

  Future<void> _openSettings() async {
    final opened = await currentApkInstaller().openPermissionSettings();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.waitingSettings;
      _message = opened ? '在设置里把 LopiCode 的“允许安装未知应用”打开，然后回到这里，会自动接着装。没有自动继续就点上面的“继续安装”。' : '没能替你打开那个设置页。请自己到系统的 设置 › 应用 › 特殊权限 › 安装未知应用 里，给 LopiCode 打开开关，再回来点“继续安装”。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final label = switch (_phase) {
      _Phase.idle => widget.idleLabel,
      _Phase.working => '正在交给系统安装器…',
      _Phase.needPermission => '去设置里允许',
      _Phase.waitingSettings => '继续安装',
      _Phase.launched => '再装一次',
      _Phase.failed => '再试一次',
    };
    final onPressed = switch (_phase) {
      _Phase.working => null,
      _Phase.needPermission => _openSettings,
      _ => _install,
    };
    final (Color bg, Color fg, IconData icon) = switch (_phase) {
      _Phase.launched => (c.surfaceMuted, c.textMuted, Icons.check_circle_outline_rounded),
      _Phase.failed => (c.dangerSoft, c.danger, Icons.error_outline_rounded),
      _ => (c.warningSoft, c.warning, Icons.info_outline_rounded),
    };
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(48)));
    final child = Text(label);
    const buttonKey = Key('apk-install');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 说明要去设置时，“去设置里允许”就是这一步该做的事，所以一直画成主按钮
        if (widget.primary || _phase == _Phase.needPermission || _phase == _Phase.waitingSettings)
          FilledButton(key: buttonKey, onPressed: onPressed, style: style, child: child)
        else
          OutlinedButton(key: buttonKey, onPressed: onPressed, style: style, child: child),
        if (_message != null) ...[
          const SizedBox(height: Space.x2),
          Container(
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(
                    _message!,
                    key: const Key('apk-install-message'),
                    style: t.bodySmall?.copyWith(color: _phase == _Phase.launched ? c.textMuted : c.text, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
