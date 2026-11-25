// 设计约束（本地打包 · 签名钥匙 · 一页 · 390×844）
// 这一页只回答三件事，从上到下：
//   ① 现在有没有钥匙（指纹、哪天生成的；没有时说明“第一次打包会自动生成”，也可以现在就生成）；
//   ② 为什么要管它（一段话：同一把一直沿用，换了＝装不了升级包、要先卸载）——放在第一组的脚注里；
//   ③ 能做什么：导出备份、导入备份（各一行跳转）；最下面单独一组是危险的“重新生成”（红字，点了先确认）。
// 一行只做一件事；没有主按钮——这一页不是每次都要来的地方。
// 钥匙和口令不出现在任何提示、日志里；这一页只显示指纹。
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/signing_key_backup_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

Future<void> openSigningKeyScreen(BuildContext context, ProjectSession session) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => SigningKeyScreen(session: session)));

const String kKeyWhy =
    '手机靠这把钥匙认“这个应用是不是同一个人打的包”。同一把一直沿用，新包才能直接盖在旧的上面升级；'
    '换了钥匙，手机上已经装的应用就装不了升级包，要先卸载（应用里的数据也跟着没了）。'
    '所有工作区打出来的应用用的是同一把。它加密存在这台手机里：卸载 LopiCode 或换手机就没了，所以生成以后先导出一份备份。';

class SigningKeyScreen extends ConsumerStatefulWidget {
  const SigningKeyScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<SigningKeyScreen> createState() => _SigningKeyScreenState();
}

class _SigningKeyScreenState extends ConsumerState<SigningKeyScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(signingKeyProvider.notifier).load();
    });
  }

  Future<void> _generate({required bool replace}) async {
    if (replace) {
      final ok = await confirmDialog(context, title: '重新生成钥匙？', message: '现在这把会被换掉，而且找不回来（除非你有备份）。\n\n换了以后，手机上用旧钥匙装的应用都装不了新包，要先卸载再装。', confirmLabel: '换掉，重新生成', danger: true);
      if (!ok || !mounted) return;
    }
    final keys = ref.read(signingKeyProvider.notifier);
    try {
      await (replace ? keys.regenerate() : keys.ensure());
      if (mounted) showSnack(context, replace ? '已换成新钥匙，记得重新备份' : '钥匙生成好了，记得备份');
    } on SigningKeyException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final key = ref.watch(signingKeyProvider);
    final busy = key.busy != SigningKeyBusy.none;
    final d = key.createdAt;
    final date = d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return SettingsPage(
      title: '签名钥匙',
      children: [
        SettingsGroup(
          title: '现在的钥匙',
          footer: kKeyWhy,
          children: [
            if (!key.loaded)
              const SettingsRow(icon: Icons.key_outlined, title: '正在读…')
            else if (key.busy == SigningKeyBusy.generating)
              const SettingsRow(
                key: Key('key-generating'),
                leading: SizedBox(
                  width: SettingsMetrics.iconSlot,
                  child: Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
                title: '正在生成钥匙…',
                subtitle: '手机上可能要十几秒，先别退出应用',
              )
            else if (key.hasKey) ...[
              SettingsRow(
                key: const Key('key-fingerprint'),
                icon: Icons.key_outlined,
                title: '指纹 ${key.shortFingerprint}…',
                subtitle: '$date 生成。点一下复制完整指纹',
                trailing: Icon(Icons.copy_rounded, size: 18, color: c.textFaint),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: key.fingerprint!));
                  if (context.mounted) showSnack(context, '已复制完整指纹');
                },
              ),
            ] else ...[
              SettingsRow(key: const Key('key-none'), icon: Icons.key_off_outlined, title: '还没有钥匙', subtitle: key.error ?? '第一次打包时会自动生成，不用管'),
              SettingsRow(key: const Key('key-generate'), icon: Icons.add_rounded, title: '现在就生成一把', accent: true, onTap: () => _generate(replace: false)),
            ],
          ],
        ),
        SettingsGroup(
          title: '备份',
          footer: '备份是一段用你定的口令加密过的文字。口令 LopiCode 不存，忘了就打不开这份备份。',
          children: [
            SettingsRow(
              key: const Key('key-export'),
              icon: Icons.upload_file_outlined,
              title: '导出备份',
              subtitle: key.hasKey ? '设一个口令，存成文件' : '还没有钥匙，没东西可备份',
              enabled: key.hasKey && !busy,
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => KeyExportScreen(session: widget.session))),
            ),
            SettingsRow(
              key: const Key('key-import'),
              icon: Icons.download_outlined,
              title: '导入备份',
              subtitle: key.hasKey ? '用备份里的钥匙换掉现在这把' : '换手机、重装以后把原来那把拿回来',
              enabled: key.loaded && !busy,
              onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => KeyImportScreen(session: widget.session))),
            ),
          ],
        ),
        if (key.hasKey)
          SettingsGroup(
            title: '危险操作',
            children: [
              SettingsRow(
                key: const Key('key-regenerate'),
                icon: Icons.warning_amber_rounded,
                title: '重新生成钥匙',
                subtitle: '换掉现在这把；已装的应用要先卸载才能装新包',
                danger: true,
                enabled: !busy,
                onTap: () => _generate(replace: true),
              ),
            ],
          ),
      ],
    );
  }
}
