// 设计约束（后端积木 · 运行面板 · 390×844，浅色 + 深色）— 2026-11-24，2026-11-25 改
// - 主操作只有一个，钉在面板底部：“在终端启动”。工具没装它会先自动装好再启动（lib/state/backend_run.dart），不用她自己去装。
// - 从上到下，一段只说一件事：
//   1) 要用到什么工具、没装会自动装什么（多大；比较大的会先问一次）；想自己看就去“运行环境”
//   2) 要执行的那一行命令（等宽，可复制）
//   3) 怎么停（Ctrl+C）和启动以后的地址（可复制；提醒 localhost 指手机自己）
//   4) 接口清单：一行一个接口（请求方式 + 路径），下面是试它的 curl 命令（点一下复制）
// - 有错误的积木：最上面一条警示，说清楚“出错的接口不在生成的代码里”。
import 'package:flutter/services.dart';
import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_readme.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/lowcode/logic_vars_sheet.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 启动这种语言的后端要用到什么工具、没装会怎样。`oneTap`＝应用能不能替她装（“运行环境”页的清单里有没有这一项）。
/// 版本要求取自各生成器自己的说明（lib/backend/target_*.dart 的 summary）；装的是什么、多大取自清单
/// （lib/runtime/runtime_sources.dart，来源见 docs/api-notes.md）。清单里的安装脚本都还没有在真机上跑过。
({String text, bool oneTap}) beToolchainNote(String language) {
  final need = switch (language) {
    'node' => 'Node.js（20 或更新）',
    'python' => 'Python 3（3.8 或更新）',
    'go' => 'Go（1.18 或更新）',
    'java' => 'JDK（11 或更新，要带 javac）',
    'php' => 'PHP 的命令行版',
    _ => null,
  };
  // 清单里各项的名字、体积不随下载源变，随便取一个下载源的清单即可。
  final pack = runtimePackById(runtimePacks(''), language);
  if (need == null || pack == null) return (text: '这种语言的工具要你自己在终端里装好。', oneTap: false);
  // 英文数字结尾的名字后面空一格；带了括号说明就不用空。
  final size = pack.sizeNote == null ? ' ' : '（${pack.sizeNote}）';
  final ask = pack.needsConfirm ? '因为比较大，装之前会先问你一次。' : '';
  final slow = language == 'go' || language == 'java' ? '第一次启动要先编译，会慢一些。' : '';
  return (text: '要用到 $need。没装也不用管：点“在终端启动”会先自动装好 ${pack.title}$size再启动。$ask$slow', oneTap: true);
}

/// 运行面板。[onStart]＝点了“在终端启动”（外面负责先存盘、切到终端页）；[onOpenRuntime]＝去“运行环境”页。
class BeRunSheet extends StatelessWidget {
  const BeRunSheet({super.key, required this.doc, required this.dir, required this.errorCount, required this.onStart, this.onOpenRuntime});
  final BeDocument doc;

  /// 后端在工作区里的子目录（空＝根目录）。
  final String dir;
  final int errorCount;
  final VoidCallback onStart;
  final VoidCallback? onOpenRuntime;

  Future<void> _copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showSnack(context, '已复制$what');
  }

  Widget _code(BuildContext context, String key, String text, String what) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x1),
      child: Material(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(Radii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey(key),
          onTap: () => _copy(context, text, what),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs + 1, height: 1.4, color: c.text),
                  ),
                ),
                const SizedBox(width: Space.x2),
                Icon(Icons.copy_rounded, size: 16, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _para(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x1),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final target = backendTargetFor(doc.language);
    final command = backendLaunchCommand(doc, dir: dir);
    final url = 'http://localhost:${doc.port}';
    final tools = beToolchainNote(doc.language);
    return LcSheetFrame(
      title: '启动后端',
      note: target == null ? '语言“${doc.language}”还没有生成器，启动不了。先在“更多”里换一种语言。' : '${doc.name} · ${target.label.split('（').first} · 端口 ${doc.port}',
      footer: FilledButton.icon(key: const ValueKey('be-run-start'), onPressed: command == null ? null : onStart, icon: const Icon(Icons.play_arrow_rounded, size: 20), label: const Text('在终端启动')),
      children: [
        if (errorCount > 0) InfoBanner('积木里还有 $errorCount 处错误：出错的接口不在生成的代码里，启动以后访问不到它们。', tone: BannerTone.warning, margin: const EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2)),
        if (target != null && !target.verified) const InfoBanner('这种语言生成的代码还没有实际运行过，只检查过结构，可能启动不了。', tone: BannerTone.warning, margin: EdgeInsets.fromLTRB(Space.x4, Space.x1, Space.x4, Space.x2)),
        if (target != null) ...[
          const SectionLabel('1 · 要用到的工具'),
          _para(context, tools.text),
          if (tools.oneTap && onOpenRuntime != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                child: TextButton(key: const ValueKey('be-run-runtime'), onPressed: onOpenRuntime, child: const Text('去“运行环境”看看')),
              ),
            ),
          const SectionLabel('2 · 要执行的命令'),
          if (command != null) _code(context, 'be-run-command', command, '命令'),
          _para(context, '点“在终端启动”会切到终端页，在一个叫“后端”的终端里替你打这一行（再点一次会先停掉上一次的）。工具没装会先自动装好再打；连运行环境都还没装的话，会先把它装上，装好后自动接着来。安装过程在终端页看得到，也可以取消。'),
          const SectionLabel('3 · 停止和地址'),
          _para(context, '停止：在终端底下那排键里点 Ctrl，再按 C。${target.dataInMemory ? '数据存在内存里，服务一停就没了。' : '数据存在后端目录的 lc_data.json 里，重启还在。'}'),
          _code(context, 'be-run-url', url, '地址'),
          _para(context, '手机上的 localhost 指手机自己：只有这台手机上的浏览器、预览和终端访问得到。'),
          const SectionLabel('4 · 接口和试法'),
          if (doc.routes.isEmpty) _para(context, '还没有接口。'),
          for (final r in doc.routes) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
              child: Text('${r.method} ${r.path}', key: ValueKey('be-run-route-${r.id}'), style: t.labelLarge),
            ),
            if (beCurlExample(r, doc.port) case final curl?) _code(context, 'be-run-curl-${r.id}', curl, ' curl 命令') else _para(context, '路径格式不对，先改好。'),
          ],
          for (final n in target.notes) _para(context, '· ${n.replaceAll('`', '')}'),
        ],
      ],
    );
  }
}
