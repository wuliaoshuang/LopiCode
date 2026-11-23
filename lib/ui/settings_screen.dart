// 设计约束（设置 · 390×844）
// - 三组：Agent 模型、外观、关于。每组一个小标题，组内每行只做一件事。
// - 密钥输入框默认遮住；已保存的 Key 不回显明文，只显示“已保存”。
// - 密钥存不住（安全存储不可用）时，如实用警告条说明。
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  bool _hasKey = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = AppScope.of(context);
    _baseUrl.text = app.settings.getString(SettingKeys.agentBaseUrl);
    _model.text = app.settings.getString(SettingKeys.agentModel);
    app.secrets.read(SecretKeys.agentApiKey).then((v) {
      if (mounted) setState(() => _hasKey = v != null && v.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    await app.settings.set(SettingKeys.agentBaseUrl, _baseUrl.text.trim());
    await app.settings.set(SettingKeys.agentModel, _model.text.trim());
    if (_key.text.isNotEmpty) {
      await app.secrets.write(SecretKeys.agentApiKey, _key.text.trim());
      _key.clear();
      _hasKey = true;
    }
    app.touch();
    if (mounted) {
      setState(() {});
      FocusScope.of(context).unfocus();
      showSnack(context, '已保存');
    }
  }

  Future<void> _clearKey() async {
    final app = AppScope.of(context);
    await app.secrets.delete(SecretKeys.agentApiKey);
    if (mounted) setState(() => _hasKey = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const ShellAppBar(title: '设置', subtitle: 'LopiCode'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x8),
        children: [
          const SectionLabel('Agent 模型'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('支持任何 OpenAI 兼容的 Chat Completions 接口，模型需要支持工具调用。', style: t.bodySmall),
                const SizedBox(height: Space.x3),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '接口地址', hintText: 'https://api.openai.com/v1'),
                ),
                const SizedBox(height: Space.x3),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '模型名', hintText: '例如 gpt-4o-mini'),
                ),
                const SizedBox(height: Space.x3),
                TextField(
                  controller: _key,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: _hasKey ? '已保存，留空表示不改' : '粘贴你的 Key',
                    helperText: _hasKey ? '已保存一个 Key（不显示明文）' : null,
                    suffixIcon: _hasKey
                        ? IconButton(tooltip: '清除已保存的 Key', icon: const Icon(Icons.delete_outline), onPressed: _clearKey)
                        : null,
                  ),
                ),
                const SizedBox(height: Space.x3),
                if (!app.secrets.persistent)
                  const InfoBanner(
                    '这台设备上安全存储不可用，Key 只保存在内存里，关掉应用后要重新填写。',
                    tone: BannerTone.warning,
                    margin: EdgeInsets.only(bottom: Space.x3),
                  )
                else
                  const InfoBanner(
                    'Key 用系统密钥库（Android Keystore）加密保存，不会写进普通设置文件或日志。',
                    margin: EdgeInsets.only(bottom: Space.x3),
                  ),
                FilledButton(onPressed: _save, child: const Text('保存')),
              ],
            ),
          ),
          const SectionLabel('外观'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) => app.setThemeMode(s.first),
            ),
          ),
          const SectionLabel('关于'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Text(
              'LopiCode 1.0.0\n在手机上通过 Agent 完成代码项目：写代码、终端、网页预览、低代码搭建、远程打包 APK。',
              style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
