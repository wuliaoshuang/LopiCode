// 设计约束（联网搜索 · 390×844）— 2026-11-24 从 settings_agent.dart 拆出来并按设置的统一样式重排
// - 两组：〔搜索服务〕地址 → 一键填官方地址 → API Key → 保存（表单组；是什么、要不要钱写在组上面的提示条和脚注里）；
//   〔测试〕一行“搜一次试试”（会真的发一次搜索，点了先确认），结果显示在这一组下面。
// - Key 输入框默认遮住，已保存的不回显；清除已保存的 Key 是输入框尾部的小按钮。
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class WebSearchSettingsScreen extends StatefulWidget {
  const WebSearchSettingsScreen({super.key});

  @override
  State<WebSearchSettingsScreen> createState() => _WebSearchSettingsScreenState();
}

class _WebSearchSettingsScreenState extends State<WebSearchSettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _hasKey = false;
  bool _loaded = false;
  bool _busy = false;
  String? _status;
  bool _statusOk = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = appOf(context);
    _url.text = app.settings.getString(WebSearchConfig.kUrl);
    app.secrets.read(WebSearchConfig.secretKey).then((v) {
      if (mounted) setState(() => _hasKey = v != null && v.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = appOf(context);
    await app.settings.set(WebSearchConfig.kUrl, _url.text.trim().isEmpty ? null : _url.text.trim());
    if (_key.text.trim().isNotEmpty) {
      await app.secrets.write(WebSearchConfig.secretKey, _key.text.trim());
      _key.clear();
      _hasKey = true;
    }
    app.container.read(webSearchRevProvider.notifier).bump();
    if (mounted) {
      setState(() {});
      FocusScope.of(context).unfocus();
      showSnack(context, _url.text.trim().isNotEmpty && _hasKey ? '已保存：Agent 现在有联网搜索工具了' : '已保存。地址和 Key 都填好，Agent 才有搜索工具');
    }
  }

  Future<void> _clear() async {
    final app = appOf(context);
    await app.secrets.delete(WebSearchConfig.secretKey);
    app.container.read(webSearchRevProvider.notifier).bump();
    if (mounted) setState(() => _hasKey = false);
  }

  Future<void> _test() async {
    final app = appOf(context);
    final ok = await confirmDialog(context, title: '搜一次试试？', message: '会真的向搜索服务发一次搜索（关键词“LopiCode”），按服务商的规则可能消耗一次额度。', confirmLabel: '搜一次');
    if (!ok) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final key = _key.text.trim().isNotEmpty ? _key.text.trim() : (await app.secrets.read(WebSearchConfig.secretKey) ?? '');
    final outcome = await WebSearchClient(WebSearchConfig(_url.text.trim(), key)).search('LopiCode', count: 1);
    if (mounted) {
      setState(() {
        _busy = false;
        _statusOk = outcome.ok;
        _status = outcome.ok ? '搜索服务可以用。' : outcome.text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canTest = !_busy && _url.text.trim().isNotEmpty;
    return SettingsPage(
      title: '联网搜索',
      children: [
        const InfoBanner('目前按 Tavily 搜索服务的接口格式对接。Key 要你自己去它的官网申请，费用和免费额度以它官网为准；LopiCode 不会替你注册或付费。', margin: EdgeInsets.only(bottom: Space.x6)),
        SettingsGroup(
          title: '搜索服务',
          footer: '填好之后，Agent 多一个“联网搜索”工具，需要查资料时会自己用。没填的时候 Agent 没有这个工具。',
          padded: true,
          children: [
            TextField(
              key: const Key('search-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: '搜索服务地址', hintText: WebSearchConfig.defaultUrl),
              onChanged: (_) => setState(() {}),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _url.text = WebSearchConfig.defaultUrl), child: const Text('填入 Tavily 的官方地址')),
            ),
            TextField(
              key: const Key('search-key'),
              controller: _key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: _hasKey ? '已保存，留空表示不改' : '粘贴你的 Key',
                helperText: _hasKey ? '已保存一个 Key（不显示明文）' : null,
                suffixIcon: _hasKey ? IconButton(tooltip: '清除已保存的 Key', icon: const Icon(Icons.delete_outline), onPressed: _clear) : null,
              ),
            ),
            const SizedBox(height: Space.x4),
            FilledButton(key: const Key('search-save'), onPressed: _save, child: const Text('保存')),
          ],
        ),
        SettingsGroup(
          title: '测试',
          footer: canTest || _busy ? null : '先填搜索服务地址，才能测试。',
          children: [SettingsRow(key: const Key('search-test'), icon: Icons.travel_explore, title: '搜一次试试', subtitle: '会真的发一次搜索，可能消耗一次额度', enabled: canTest, onTap: _test)],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_status != null) InfoBanner(_status!, tone: _statusOk ? BannerTone.info : BannerTone.danger),
      ],
    );
  }
}
