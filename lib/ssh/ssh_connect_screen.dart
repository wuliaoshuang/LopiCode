// 设计约束（SSH 主机设置 · 390×844）
// - 一屏一件事：填一台主机。顺序就是连接时用到的顺序：地址 → 端口 → 用户名 → 登录方式 → 密码或私钥。
// - 地址和端口同一行（端口窄），其余一行一项。
// - 主按钮只有一个，文字随来源变（“保存并连接” / “保存”）；“忘记指纹”是次要操作，放最下面、弱化。
// - 已保存的密码 / 私钥不回显，只说“已保存，留空表示不改”。
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 填写并保存 SSH 主机。保存成功后 pop 出 [SshConfig]。
class SshConnectScreen extends StatefulWidget {
  const SshConnectScreen({super.key, this.submitLabel = '保存并连接'});
  final String submitLabel;

  @override
  State<SshConnectScreen> createState() => _SshConnectScreenState();
}

class _SshConnectScreenState extends State<SshConnectScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();
  bool _useKey = false;
  bool _hasPassword = false;
  bool _hasKey = false;
  bool _loaded = false;
  String? _error;
  String? _knownFingerprint;

  /// 改了任何一项，上一次的错误提示就过时了。
  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = AppScope.of(context);
    final config = SshConfig.load(app.settings);
    _host.text = config.host;
    _port.text = '${config.port}';
    _user.text = config.user;
    _useKey = config.useKey;
    for (final c in [_host, _port, _user, _password, _key, _passphrase]) {
      c.addListener(_clearError);
    }
    _knownFingerprint = config.host.isEmpty ? null : KnownHosts(app.settings).fingerprintOf(config.hostPort);
    () async {
      final password = await app.secrets.read(SecretKeys.sshPassword);
      final key = await app.secrets.read(SecretKeys.sshPrivateKey);
      if (!mounted) return;
      setState(() {
        _hasPassword = password != null && password.isNotEmpty;
        _hasKey = key != null && key.isNotEmpty;
      });
    }();
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _password, _key, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final app = AppScope.of(context);
    var error = SshConfig.validate(host: _host.text, port: _port.text, user: _user.text);
    if (error == null) {
      if (_useKey && !_hasKey && _key.text.trim().isEmpty) error = '请粘贴私钥';
      if (!_useKey && !_hasPassword && _password.text.isEmpty) error = '请填写密码';
      if (_useKey && _key.text.trim().isNotEmpty && !_key.text.contains('PRIVATE KEY')) {
        error = '这不像一把私钥：要包含 BEGIN … PRIVATE KEY 那一行';
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_error != null) setState(() => _error = null);
    final config = SshConfig(host: _host.text.trim(), port: int.parse(_port.text.trim()), user: _user.text.trim(), useKey: _useKey);
    await config.save(app.settings);
    if (_useKey) {
      if (_key.text.trim().isNotEmpty) {
        await app.secrets.write(SecretKeys.sshPrivateKey, '${_key.text.trim()}\n');
        // 换了私钥：旧的密码短语不再适用。
        if (_passphrase.text.isEmpty) await app.secrets.delete(SecretKeys.sshKeyPassphrase);
      }
      if (_passphrase.text.isNotEmpty) await app.secrets.write(SecretKeys.sshKeyPassphrase, _passphrase.text);
    } else if (_password.text.isNotEmpty) {
      await app.secrets.write(SecretKeys.sshPassword, _password.text);
    }
    if (mounted) Navigator.of(context).pop(config);
  }

  Future<void> _forgetFingerprint() async {
    final app = AppScope.of(context);
    final config = SshConfig.load(app.settings);
    await KnownHosts(app.settings).forget(config.hostPort);
    if (!mounted) return;
    setState(() => _knownFingerprint = null);
    showSnack(context, '已忘记，下次连接会重新确认指纹');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: PageBar(background: context.colors.canvas, title: const Text('SSH 主机')),
      body: SectionedList(
        inner: const EdgeInsets.all(Space.x4),
        children: [
          Text('终端的 SSH 会话和 SSH 构建机共用这一台主机。', style: t.bodySmall?.copyWith(color: c.textMuted)),
          const SizedBox(height: Space.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ssh-host'),
                  controller: _host,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '主机地址', hintText: '域名或 IP'),
                ),
              ),
              const SizedBox(width: Space.x3),
              SizedBox(
                width: 88,
                child: TextField(
                  key: const Key('ssh-port'),
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '端口'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('ssh-user'),
            controller: _user,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: Space.x4),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('密码登录')),
              ButtonSegment(value: true, label: Text('私钥登录')),
            ],
            selected: {_useKey},
            onSelectionChanged: (s) => setState(() {
              _useKey = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: Space.x3),
          if (!_useKey)
            TextField(
              key: const Key('ssh-password'),
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: '密码', hintText: _hasPassword ? '已保存，留空表示不改' : null),
            )
          else ...[
            TextField(
              key: const Key('ssh-key'),
              controller: _key,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs),
              decoration: InputDecoration(labelText: '私钥', alignLabelWithHint: true, hintText: _hasKey ? '已保存，留空表示不改' : '粘贴整段私钥（-----BEGIN … PRIVATE KEY----- 开头）'),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _passphrase,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: '私钥的密码短语（没有就留空）'),
            ),
          ],
          const SizedBox(height: Space.x3),
          if (_error != null)
            InfoBanner(
              _error!,
              tone: BannerTone.danger,
              margin: const EdgeInsets.only(bottom: Space.x3),
            ),
          if (!app.secrets.persistent)
            const InfoBanner(
              '这台设备上安全存储不可用，密码 / 私钥只保存在内存里，关掉应用后要重新填写。',
              tone: BannerTone.warning,
              margin: EdgeInsets.only(bottom: Space.x3),
            )
          else
            const InfoBanner('密码和私钥加密保存在系统安全存储里，不会写进普通设置文件或日志。', margin: EdgeInsets.only(bottom: Space.x3)),
          FilledButton(key: const Key('ssh-submit'), onPressed: _submit, child: Text(widget.submitLabel)),
          if (_knownFingerprint != null) ...[
            const SizedBox(height: Space.x6),
            Text('已记住的主机指纹', style: t.labelLarge?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.x1),
            Text(
              _knownFingerprint!,
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, color: c.textMuted),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _forgetFingerprint, child: const Text('忘记这台主机的指纹')),
            ),
          ],
        ],
      ),
    );
  }
}

/// 第一次连接时的指纹确认框。
Future<bool> confirmHostKey(BuildContext context, SshConfig config, String keyType, String fingerprint) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('第一次连接这台主机'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${config.hostPort} 的主机指纹（$keyType）：'),
          const SizedBox(height: Space.x2),
          SelectableText(
            fingerprint,
            style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, color: c.text),
          ),
          const SizedBox(height: Space.x3),
          Text(
            '确认是你的服务器再信任。之后每次连接都会核对，指纹变了会拒绝连接。',
            style: TextStyle(fontSize: FontSize.sm, color: c.textMuted),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('信任并连接')),
      ],
    ),
  );
  return result ?? false;
}
