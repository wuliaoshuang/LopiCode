// 设计约束（本地打包 · 进度 / 失败 / 成功卡 · 390×844）
// 打包中：一句“正在打包”+ 七步清单（检查 → 收集文件 → 写清单 → 换图标 → 压缩 → 签名 → 写出）。做完的打勾、弱色；
//         当前这一步是正文色加粗，下面跟一句细节；还没到的更淡。第一次打包前面多一步“生成签名钥匙”。
// 失败：结论 + 卡在哪一步；真正的原因放在浅红底的块里；是哪个输入的问题就给一个“去改…”按钮（只有一个）。
// 成功：① 结论；② 这是哪个应用（图标、应用名、包名）；③ 版本 / 大小 / 文件数（一行一项的小表）；
//       ④ 安装包在哪（能在系统文件管理器里找到的那份排前面），每个位置一行、行尾复制；⑤ 一行“去文件页看”；⑥ 怎么装到手机上（三步）。
// 没有“直接安装”按钮：那要新权限，见汇报的“待定”。
// 颜色：状态靠图标 + 颜色一起表达（勾 / 叉 / 圈），不只靠颜色。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

/// 打包的七步在界面上叫什么。
const List<(ApkPackStep, String)> kPackStepLabels = [
  (ApkPackStep.check, '检查项目和填的内容'),
  (ApkPackStep.collect, '收集网页文件'),
  (ApkPackStep.manifest, '写入应用名、包名、版本、权限'),
  (ApkPackStep.icon, '换图标'),
  (ApkPackStep.zip, '压缩'),
  (ApkPackStep.sign, '签名'),
  (ApkPackStep.write, '写出安装包'),
];

String packStepLabel(ApkPackStep? step) => kPackStepLabels.where((e) => e.$1 == step).map((e) => e.$2).firstOrNull ?? '准备';

/// 出问题的输入叫什么（“去改…”按钮上的字）。
String? packFieldLabel(String? field) => switch (field) {
  'appName' => '去改应用名',
  'packageName' => '去改包名',
  'versionName' => '去改版本名',
  'versionCode' => '去改版本号',
  'icon' => '去换图标',
  'permissions' => '去改权限',
  'key' => '去看签名钥匙',
  _ => null,
};

class LocalPackRunCard extends ConsumerWidget {
  const LocalPackRunCard({super.key, required this.session, required this.onFix});
  final ProjectSession session;
  final void Function(String field) onFix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localPackProvider(session));
    return switch (s.phase) {
      LocalPackPhase.idle => const SizedBox.shrink(),
      LocalPackPhase.preparingKey || LocalPackPhase.packing => _Progress(state: s),
      LocalPackPhase.failed => _Failed(state: s, onFix: onFix),
      LocalPackPhase.done => _Done(state: s),
    };
  }
}

enum _Mark { done, current, pending, failed }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.mark, this.detail});
  final String label;
  final _Mark mark;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final Widget glyph = switch (mark) {
      _Mark.done => Icon(Icons.check_rounded, size: 18, color: c.textFaint),
      _Mark.current => const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      _Mark.pending => Icon(Icons.circle_outlined, size: 10, color: c.border),
      _Mark.failed => Icon(Icons.close_rounded, size: 18, color: c.danger),
    };
    final style = switch (mark) {
      _Mark.done => t.bodyMedium?.copyWith(color: c.textFaint),
      _Mark.current => t.bodyMedium?.copyWith(color: c.text, fontWeight: FontWeight.w600),
      _Mark.pending => t.bodyMedium?.copyWith(color: c.textFaint),
      _Mark.failed => t.bodyMedium?.copyWith(color: c.danger, fontWeight: FontWeight.w600),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, height: 21, child: Center(child: glyph)),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: style),
                if (detail != null && detail!.isNotEmpty)
                  Text(
                    detail!,
                    key: const Key('pack-step-detail'),
                    style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _stepRows(LocalPackState s, {required bool failed}) {
  final keyPhase = s.phase == LocalPackPhase.preparingKey;
  final at = failed ? s.failure?.step : s.step;
  final index = kPackStepLabels.indexWhere((e) => e.$1 == at);
  return [
    if (keyPhase) const _StepRow(label: '生成签名钥匙', mark: _Mark.current, detail: '只有第一次要做，手机上可能要十几秒。以后一直用这一把。'),
    for (final (i, (_, label)) in kPackStepLabels.indexed)
      _StepRow(
        label: label,
        mark: keyPhase || index < 0
            ? _Mark.pending
            : i < index
            ? _Mark.done
            : i == index
            ? (failed ? _Mark.failed : _Mark.current)
            : _Mark.pending,
        detail: !keyPhase && !failed && i == index ? s.detail : null,
      ),
  ];
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});
  final LocalPackState state;

  @override
  Widget build(BuildContext context) => RunCard(
    children: [
      Text('正在打包', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.x3),
      ..._stepRows(state, failed: false),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state, required this.onFix});
  final LocalPackState state;
  final void Function(String field) onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final failure = state.failure;
    final fix = packFieldLabel(failure?.field);
    return RunCard(
      children: [
        RunHeader(tone: RunTone.failed, title: '打包没成功', subtitle: failure?.step == null ? '还没开始打就停了' : '停在：${packStepLabel(failure!.step)}'),
        const SizedBox(height: Space.x3),
        Container(
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
          child: Text(
            failure?.message ?? '没有拿到原因。',
            key: const Key('pack-failure'),
            style: t.bodyMedium?.copyWith(color: c.danger),
          ),
        ),
        if (fix != null) ...[
          const SizedBox(height: Space.x3),
          OutlinedButton(
            key: const Key('pack-fix'),
            onPressed: () => onFix(failure!.field!),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: Text(fix),
          ),
        ],
        if (failure?.step != null) ...[const SizedBox(height: Space.x3), Divider(height: 1, color: c.border), const SizedBox(height: Space.x2), ..._stepRows(state, failed: true)],
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state});
  final LocalPackState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final r = state.result!;
    final shell = ShellScope.maybeOf(context);
    final fileName = r.path.split('/').last;
    Widget fact(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: t.bodyMedium?.copyWith(color: c.textFaint)),
          ),
          Expanded(
            child: Text(value, key: key, style: t.bodyMedium),
          ),
        ],
      ),
    );
    return RunCard(
      children: [
        const RunHeader(tone: RunTone.done, title: '打包完成'),
        const SizedBox(height: Space.x4),
        Row(
          children: [
            ApkIconPreview(png: state.form.customIcon ? state.icons[96] : null, size: 48),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.appName, key: const Key('pack-result-name'), style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    r.packageName,
                    style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        fact('版本', '${r.versionName}（版本号 ${r.versionCode}）', key: const Key('pack-result-version')),
        fact('大小', ApkBuildController.formatBytes(r.sizeBytes)),
        fact('网页文件', '${r.fileCount} 个'),
        fact('签名指纹', '${r.certSha256Hex.length > 16 ? r.certSha256Hex.substring(0, 16) : r.certSha256Hex}…'),
        const SizedBox(height: Space.x3),
        Divider(height: 1, color: c.border),
        const SizedBox(height: Space.x3),
        if (state.publicPath != null) ...[CopyLine(key: const Key('pack-result-public'), label: '手机存储里的位置（从这里安装）', value: state.publicPath!), const SizedBox(height: Space.x3)],
        CopyLine(key: const Key('pack-result-path'), label: '工作区里的位置', value: r.path, note: state.publicNote ?? '在“文件”页的 build 文件夹里，名字是 $fileName。'),
        if (shell != null) ...[
          const SizedBox(height: Space.x2),
          OutlinedButton(
            key: const Key('pack-open-files'),
            onPressed: () => shell.go(ShellDest.files),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('去“文件”页看 build 文件夹'),
          ),
        ],
        const SizedBox(height: Space.x4),
        Text('怎么装到手机上', style: t.labelMedium),
        const SizedBox(height: Space.x2),
        for (final (i, line) in [
          state.publicPath != null ? '打开手机自带的“文件管理”，按上面“手机存储里的位置”找到 $fileName。有的手机不让“文件管理”进 Android/data 这一层，进不去就把手机连上电脑去拿。' : '这台设备上安装包只在 LopiCode 自己的目录里，系统的文件管理器进不去；先在终端里把它拷到你找得到的地方。',
          '点它，按提示安装。第一次会让你允许“文件管理”安装应用。',
          '手机上已经装过同一个包名的应用：这次的版本号更大、又是同一把钥匙签的，才会直接升级；不然要先卸载旧的。',
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  child: Text('${i + 1}.', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.6)),
                ),
                Expanded(
                  child: Text(line, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
