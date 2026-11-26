// 设计约束（远程打包的进度 / 结果卡 · GitHub 和 SSH 共用 · 390×844）
// 层级：① 一句结论（正在做什么 / 打包完成 / 没成功）最显眼；② 成了以后是主按钮“安装”和“APK 在哪”，没成是最后那句原因；
//       ③ 一步一句的过程是弱色小字——想看才看；构建命令的原始输出在最下面的等宽框里。
// 排版：卡内 16；块与块之间 12；过程每行之间 4。一行只放一样东西：路径、网址各占一行，复制按钮在行尾。
// 颜色：结论的图标和字用状态色（完成＝强调色、没成＝危险色、停了＝警告色），其余全是正文色 / 弱色。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/apk_install_view.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class BuildJobCard extends ConsumerWidget {
  const BuildJobCard({super.key, required this.job});
  final BuildJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (String title, RunTone tone) = switch (job.phase) {
      BuildPhase.done => ('打包完成', RunTone.done),
      BuildPhase.failed => ('打包没成功', RunTone.failed),
      BuildPhase.cancelled => ('已停止等待', RunTone.paused),
      BuildPhase.connecting => ('正在连接构建机', RunTone.busy),
      BuildPhase.building => ('构建机正在打包', RunTone.busy),
      BuildPhase.pushing => ('正在上传文件', RunTone.busy),
      BuildPhase.dispatching => ('正在触发工作流', RunTone.busy),
      BuildPhase.waiting => ('GitHub 正在打包', RunTone.busy),
      BuildPhase.downloading => ('正在下载 APK', RunTone.busy),
      BuildPhase.idle => ('准备中', RunTone.busy),
    };
    final codeSize = ref.watch(compactCodeFontProvider);
    final failed = job.phase == BuildPhase.failed;
    // 没成功时最后一句就是原因：单独拎出来放在结论下面，不埋在过程里。
    final reason = failed && job.log.isNotEmpty ? job.log.last : null;
    final steps = reason == null ? job.log : job.log.sublist(0, job.log.length - 1);
    return RunCard(
      children: [
        RunHeader(tone: tone, title: title),
        if (reason != null) ...[
          const SizedBox(height: Space.x3),
          Container(
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(reason, style: t.bodyMedium?.copyWith(color: c.danger)),
          ),
        ],
        // 下载回来的安装包在外部目录里（“文件”页看不到那里），所以在这张卡上直接给“安装”，和本地打包的结果卡一样。
        if (job.apkPath != null) ...[
          const SizedBox(height: Space.x3),
          ApkInstallButton(path: job.apkPath!),
          const SizedBox(height: Space.x3),
          CopyLine(label: 'APK 保存在', value: job.apkPath!, note: '点“安装”不行的话，用手机自带的文件管理器找到它，点开也能装。'),
        ],
        if (job.runUrl != null) ...[const SizedBox(height: Space.x3), CopyLine(label: '运行页面（完整日志）', value: job.runUrl!)],
        if (steps.isNotEmpty) ...[
          const SizedBox(height: Space.x3),
          Divider(height: 1, color: c.border),
          const SizedBox(height: Space.x3),
          Text('过程', style: t.labelMedium),
          const SizedBox(height: Space.x2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, line) in steps.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x1),
                      // 进行中时最后一行是“现在在做的”，用正文色；之前的都是弱色。
                      child: Text(line, style: t.bodySmall?.copyWith(color: job.busy && i == steps.length - 1 ? c.text : c.textFaint, height: 1.5)),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (job.output.trim().isNotEmpty) ...[
          const SizedBox(height: Space.x3),
          Text('构建命令的输出', style: t.labelMedium),
          const SizedBox(height: Space.x2),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                job.output.trimRight(),
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: codeSize, height: 1.45, color: c.text),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
