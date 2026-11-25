// 设计约束（打包页 · 本地打包 · 390×844）
// 内容排序（先定的这个）：
//   主要：这个项目能不能打（一句话）→ 应用是谁（应用名、包名、版本）→ 唯一的主按钮“开始打包”→ 进度 / 结果。
//   次要：图标、权限、签名钥匙——都有能用的默认值，各收成一行，点进去才是面板 / 页面。
//   再次：每项下面的一句说明（弱色小字）。
// 一行只做一件事：四个输入各占一行；图标 / 权限 / 钥匙各一行跳转；不并排。
// 项目不适用时（Flutter、原生、纯后端、找不到网页入口）：只留一张说明卡和“改用远程打包”一个按钮，表单整个不出现——
//   摆一堆填了也没用的输入框只会让人白填。
// 打包中：表单整个锁住；主按钮变灰写“正在打包…”（本地打包几秒就完，不做“停止”）。
// 排版 / 颜色：和设置页同一套（浅灰底上的白色分组卡片，间距取自 tokens）；强调色只给主按钮和“可以打包”的勾。
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/build/apk_icon_sheet.dart';
import 'package:lopicode/build/apk_permissions_sheet.dart';
import 'package:lopicode/build/build_widgets.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/local_pack_run_view.dart';
import 'package:lopicode/build/signing_key_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

class LocalPackView extends ConsumerStatefulWidget {
  const LocalPackView({super.key, required this.session, required this.onUseRemote});
  final ProjectSession session;

  /// “改用远程打包”。
  final VoidCallback onUseRemote;

  @override
  ConsumerState<LocalPackView> createState() => _LocalPackViewState();
}

class _LocalPackViewState extends ConsumerState<LocalPackView> {
  final _appName = TextEditingController();
  final _package = TextEditingController();
  final _versionName = TextEditingController();
  final _versionCode = TextEditingController();
  final _focus = {for (final f in _fields) f: FocusNode()};
  final _keys = {for (final f in _fields) f: GlobalKey()};
  final _runKey = GlobalKey();
  final _iconKey = GlobalKey();
  final _keyRowKey = GlobalKey();
  bool _filled = false;

  static const _fields = ['appName', 'packageName', 'versionName', 'versionCode'];

  LocalPackNotifier get _pack => ref.read(localPackProvider(widget.session).notifier);

  @override
  void initState() {
    super.initState();
    // 读表单要写状态，不能在搭界面的过程中做：推后一拍。
    Future.microtask(() {
      if (!mounted) return;
      _pack.load();
      ref.read(signingKeyProvider.notifier).load();
    });
    // 输入框的内容跟着状态走。放在这里（不放在 build 里）：build 过程中改输入框会报错。
    ref.listenManual(localPackProvider(widget.session), (_, next) => _sync(next), fireImmediately: true);
  }

  @override
  void dispose() {
    _appName.dispose();
    _package.dispose();
    _versionName.dispose();
    _versionCode.dispose();
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// 把状态里的表单值放进输入框：第一次读好时全放；之后只在某一项不是她正在敲的那一项、而且值真的不一样时才换
  /// （打包成功后版本号自动加 1 走这里）。
  void _sync(LocalPackState s) {
    if (!s.loaded) return;
    void put(TextEditingController c, String value, String field) {
      if (c.text == value) return;
      if (_filled && _focus[field]!.hasFocus) return;
      c.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    put(_appName, s.form.appName, 'appName');
    put(_package, s.form.packageName, 'packageName');
    put(_versionName, s.form.versionName, 'versionName');
    put(_versionCode, s.form.versionCode, 'versionCode');
    _filled = true;
  }

  /// 把某个控件滚到顶栏下面；[focus] 不为空时滚完再把光标放进去。
  /// 先滚后给焦点：反过来的话，输入框“把光标露出来”的那一下会把它停在屏幕最上沿，正好被悬浮的顶栏盖住。
  void _reveal(GlobalKey key, {FocusNode? focus}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = key.currentContext;
      if (!mounted || target == null) return;
      await revealBelowBar(target);
      if (mounted) focus?.requestFocus();
    });
  }

  Future<void> _start() async {
    FocusScope.of(context).unfocus();
    final accepted = await _pack.start();
    if (!mounted) return;
    if (accepted) return; // 进度卡由下面的 listen 滚进视野
    // 没受理：多半是哪一项没填对——滚到第一项有错的输入框并把光标放进去。
    final errors = ref.read(localPackProvider(widget.session)).fieldErrors;
    for (final f in _fields) {
      if (errors.containsKey(f)) return _reveal(_keys[f]!, focus: _focus[f]);
    }
  }

  /// 失败卡上的“去改…”：定位到出问题的那一项。
  void _goFix(String field) {
    if (_fields.contains(field)) {
      _reveal(_keys[field]!, focus: _focus[field]);
    } else if (field == 'icon') {
      _reveal(_iconKey);
    } else if (field == 'key') {
      openSigningKeyScreen(context, widget.session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = localPackProvider(widget.session);
    final s = ref.watch(provider);
    final key = ref.watch(signingKeyProvider);
    // 一开始打、打完 / 没成：把进度卡滚进视野（主按钮在表单最下面，卡片在它下面，不滚看不到）。
    ref.listen(provider.select((v) => v.phase), (before, now) {
      if (now != LocalPackPhase.idle && now != before) _reveal(_runKey);
    });
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final project = s.project;
    final busy = s.busy;
    final options = currentLocalPackBackend().permissionOptions;

    if (!s.loaded || project == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Space.x3),
            Text('正在看这个项目能不能本地打包…', style: t.bodyMedium?.copyWith(color: c.textMuted)),
          ],
        ),
      );
    }

    if (!project.applicable) {
      return _NotApplicable(reason: project.reason, onUseRemote: widget.onUseRemote);
    }

    final onPerms = [
      for (final o in options)
        if (s.form.permissions.contains(o.id)) o.label,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          title: '打包内容',
          children: [
            SettingsRow(
              key: const Key('pack-project'),
              leading: SizedBox(
                width: SettingsMetrics.iconSlot,
                child: Icon(Icons.check_circle_rounded, size: SettingsMetrics.iconSize, color: c.accent),
              ),
              title: '这个项目可以本地打包',
              subtitle: project.reason,
            ),
          ],
        ),
        SettingsGroup(
          title: '应用信息',
          padded: true,
          children: [
            PackField(
              key: _keys['appName'],
              fieldKey: const Key('pack-app-name'),
              label: '应用名',
              controller: _appName,
              focusNode: _focus['appName'],
              enabled: !busy,
              error: s.fieldErrors['appName'],
              helper: '装到手机上，图标下面显示的名字',
              onChanged: (v) => _pack.edit(appName: v),
            ),
            PackField(
              key: _keys['packageName'],
              fieldKey: const Key('pack-package'),
              label: '包名',
              controller: _package,
              focusNode: _focus['packageName'],
              enabled: !busy,
              mono: true,
              error: s.fieldErrors['packageName'],
              helper: '应用的“身份证”。手机靠它认是不是同一个应用：想升级就别改，改了会装成另一个应用',
              onChanged: (v) => _pack.edit(packageName: v),
            ),
            PackField(
              key: _keys['versionName'],
              fieldKey: const Key('pack-version-name'),
              label: '版本名',
              controller: _versionName,
              focusNode: _focus['versionName'],
              enabled: !busy,
              mono: true,
              error: s.fieldErrors['versionName'],
              helper: '给人看的版本，比如 1.0.0',
              onChanged: (v) => _pack.edit(versionName: v),
            ),
            PackField(
              key: _keys['versionCode'],
              fieldKey: const Key('pack-version-code'),
              label: '版本号',
              controller: _versionCode,
              focusNode: _focus['versionCode'],
              enabled: !busy,
              mono: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              error: s.fieldErrors['versionCode'],
              helper: '给手机看的整数。升级包必须比手机上已装的那个大；每次打包成功后这里自动加 1，也可以自己改',
              onChanged: (v) => _pack.edit(versionCode: v),
              last: true,
            ),
          ],
        ),
        SettingsGroup(
          title: '图标、权限和签名',
          iconRows: false,
          children: [
            SettingsRow(
              key: _iconKey,
              leading: ApkIconPreview(png: s.icons[96], size: 40, busy: s.iconBusy),
              title: '图标',
              subtitle: s.fieldErrors['icon'] ?? (s.form.customIcon ? '用的是你选的图' : '用的是默认图标'),
              enabled: !busy && !s.iconBusy,
              onTap: () => showApkIconSheet(context, widget.session),
            ),
            SettingsRow(
              key: const Key('pack-perm-row'),
              icon: Icons.shield_outlined,
              title: '权限',
              subtitle: onPerms.isEmpty ? '一项都没开（网页连不了网）' : '已开：${onPerms.join('、')}',
              enabled: !busy,
              onTap: () => showApkPermissionsSheet(context, widget.session),
            ),
            SettingsRow(key: _keyRowKey, icon: Icons.key_outlined, title: '签名钥匙', subtitle: signingKeySummary(key), onTap: () => openSigningKeyScreen(context, widget.session)),
          ],
        ),
        PrimaryBuildButton(
          buttonKey: const Key('pack-start'),
          label: busy ? '正在打包…' : (s.phase == LocalPackPhase.done || s.phase == LocalPackPhase.failed ? '重新打包' : '开始打包'),
          onPressed: busy ? null : _start,
        ),
        if (s.phase != LocalPackPhase.idle) ...[const SizedBox(height: Space.x4), LocalPackRunCard(key: _runKey, session: widget.session, onFix: _goFix)],
      ],
    );
  }
}

/// 钥匙那一行的副标题。
String signingKeySummary(SigningKeyState key) {
  if (!key.loaded) return '正在读…';
  if (key.busy == SigningKeyBusy.generating) return '正在生成…';
  if (key.error != null && !key.hasKey) return '读不出来，点进去处理';
  if (!key.hasKey) return '还没有，第一次打包时自动生成';
  final d = key.createdAt;
  final date = d == null ? '' : '，${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} 生成';
  return '已有（指纹 ${key.shortFingerprint}…$date）';
}

class _NotApplicable extends StatelessWidget {
  const _NotApplicable({required this.reason, required this.onUseRemote});
  final String reason;
  final VoidCallback onUseRemote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return RunCard(
      children: [
        Row(
          children: [
            Icon(Icons.block_rounded, size: 22, color: c.warning),
            const SizedBox(width: Space.x3),
            Expanded(child: Text('这个项目不能本地打包', style: t.titleMedium)),
          ],
        ),
        const SizedBox(height: Space.x3),
        Text(
          reason,
          key: const Key('pack-not-applicable'),
          style: t.bodyMedium?.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.x2),
        Text('本地打包只会把网页装进一个现成的壳里，不会编译代码。要编译的项目用远程打包。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
        const SizedBox(height: Space.x4),
        PrimaryBuildButton(buttonKey: const Key('pack-switch-remote'), label: '改用远程打包', onPressed: onUseRemote),
      ],
    );
  }
}
