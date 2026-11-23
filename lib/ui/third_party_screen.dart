// 设计约束（第三方声明 · 390×844）
// - 一个组件一组：先说它是什么，再是许可证，再是来源；一行只放一件事。
// - 校验值和地址很长：默认收起，展开后可以长按复制。
// - 许可证全文单独一页，原文不翻译、不删改。
import 'package:lopicode/core/third_party.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:material_ui/material_ui.dart';

class ThirdPartyScreen extends StatelessWidget {
  const ThirdPartyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: ShellAppBar(background: context.colors.canvas, title: '第三方声明', subtitle: '随安装包带的开源组件'),
      body: SectionedList(
        listKey: const Key('third-party-list'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, 0),
            child: InfoBanner('前三个组件用来进入 Ubuntu 环境。它们是 Termux 官方软件源里的原样文件，内容没有改动，只改了文件名。每个组件有自己的许可证，全文在各自那一组里。最后一组是服务商图标。'),
          ),
          for (final component in bundledComponents) ...[
            SectionLabel('${component.name} ${component.version}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(component.purpose, style: t.bodyMedium?.copyWith(height: 1.5)),
                  const SizedBox(height: Space.x2),
                  Text('许可证：${component.license}', style: t.bodySmall?.copyWith(color: c.textMuted)),
                  const SizedBox(height: Space.x1),
                  Text(component.copyright, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
                ],
              ),
            ),
            for (final asset in component.licenseAssets)
              ListTile(
                key: Key('license-$asset'),
                leading: const Icon(Icons.description_outlined),
                title: Text(licenseTitle(asset)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => LicenseTextScreen(asset: asset)),
                ),
              ),
            ExpansionTile(
              key: Key('source-${component.name}'),
              leading: const Icon(Icons.link),
              title: const Text('来源、校验值和源码'),
              childrenPadding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Fact('二进制来自（Termux 官方软件源）', component.packageUrl),
                _Fact('这个包的 sha256', component.packageSha256),
                for (final binary in component.binaries) ...[
                  _Fact('安装包里的文件', '${binary.fileName}（原名 ${binary.originalPath}，${binary.size} 字节）'),
                  _Fact('${binary.fileName} 的 sha256', binary.sha256),
                ],
                _Fact('对应源码', component.sourceUrl),
                Text(component.sourceNote, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
              ],
            ),
          ],
          SectionLabel('${providerIconPack.name} ${providerIconPack.version}'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(providerIconPack.purpose, style: t.bodyMedium?.copyWith(height: 1.5)),
                const SizedBox(height: Space.x2),
                Text('许可证：${providerIconPack.license}', style: t.bodySmall?.copyWith(color: c.textMuted)),
                const SizedBox(height: Space.x1),
                Text(providerIconPack.copyright, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
                const SizedBox(height: Space.x2),
                Text(providerIconPack.trademarkNote, key: const Key('third-party-trademark'), style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
              ],
            ),
          ),
          ListTile(
            key: Key('license-${providerIconPack.licenseAsset}'),
            leading: const Icon(Icons.description_outlined),
            title: Text(licenseTitle(providerIconPack.licenseAsset)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => LicenseTextScreen(asset: providerIconPack.licenseAsset)),
            ),
          ),
          ExpansionTile(
            key: const Key('source-lobe-icons'),
            leading: const Icon(Icons.link),
            title: const Text('来源和校验值'),
            childrenPadding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x3),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Fact('图标包（npm 镜像）', providerIconPack.packageUrl),
              _Fact('这个包的完整性校验值', providerIconPack.packageIntegrity),
              _Fact('项目仓库', providerIconPack.sourceUrl),
            ],
          ),
          const SectionLabel('怎么拿到源码'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Text(
              '每个组件的源码都可以从它那一组“对应源码”的地址下载。地址打不开时，可以向 LopiCode 的发布者索取这些组件的对应源码。',
              key: const Key('third-party-source-offer'),
              style: t.bodySmall?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条“名称 + 可复制的值”。
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: c.textFaint)),
          const SizedBox(height: 2),
          SelectableText(value, style: t.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['sans-serif'], height: 1.4)),
        ],
      ),
    );
  }
}

/// 许可证全文（原文）。
class LicenseTextScreen extends StatelessWidget {
  const LicenseTextScreen({super.key, required this.asset, this.bundle});
  final String asset;
  final AssetBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: ShellAppBar(background: context.colors.canvas, title: licenseTitle(asset), subtitle: '英文原文'),
      body: FutureBuilder<String>(
        future: (bundle ?? DefaultAssetBundle.of(context)).loadString(asset),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(Space.x4),
              child: InfoBanner('许可证全文读不出来。这是安装包的问题，请告诉 LopiCode 的发布者。', tone: BannerTone.danger),
            );
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return SingleChildScrollView(
            key: const Key('license-text'),
            padding: const EdgeInsets.all(Space.x4),
            child: SelectableText(
              snapshot.data!,
              style: t.bodySmall?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['sans-serif'], fontSize: 11, height: 1.45),
            ),
          );
        },
      ),
    );
  }
}
