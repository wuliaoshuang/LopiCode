// 设计约束（渠道编辑页的步骤 · 390×844）— 2026-11-24 真机反馈“不知道先测试连接还是先获取模型”后重排
// - 一页一条路，组标题带序号：第 1 步 填接口地址和 Key → 第 2 步 获取模型 → 第 3 步 选模型 → 第 4 步 保存。一行只做一件事。
// - 没有单独的“测试连接”：它和“获取模型”本来就是同一个请求。获取成功＝连接正常；失败分开说原因和下一步。
// - 第 2 步缺东西（地址 / Key）时按钮置灰，旁边写明还差什么；本机 / 局域网地址不要 Key。
// - 模型行右边一个“测试”：发一句很短的话确认这个模型能对话（会花一点点额度，用户点了才发），结果写在这一行下面。
import 'package:lopicode/agent/channel_check.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 检查结果条：第一行结论（加粗），第二行下一步，第三行接口原话（小字）。
class CheckResultBanner extends StatelessWidget {
  const CheckResultBanner(this.result, {super.key, this.margin});
  final CheckResult result;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = result.ok ? c.accent : c.danger;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(color: result.ok ? c.accentSoft : c.dangerSoft, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: fg),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  result.title,
                  style: t.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600, height: 1.4),
                ),
                if (result.advice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(result.advice!, style: t.bodySmall?.copyWith(color: c.text, height: 1.5)),
                  ),
                if (result.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x1),
                    child: Text(
                      '接口原话：${result.detail}',
                      style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 第 2 步的内容（放在表单组里）：一句说明 → “获取模型”按钮 → 还差什么 / 进度 / 结果。
class FetchModelsStep extends StatelessWidget {
  const FetchModelsStep({super.key, required this.missing, required this.busy, required this.result, required this.onFetch});

  /// 第 1 步还差什么（“接口地址” / “API Key”）；不差就是 null。
  final String? missing;
  final bool busy;
  final CheckResult? result;
  final VoidCallback onFetch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('从接口读模型列表。读得到，就说明地址和 Key 都能用——不用另外测试连接，也不产生对话费用。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
        const SizedBox(height: Space.x3),
        // 还没读成功时它是这一步的主操作（实心）；读成功以后退成描边，主操作让给底下的“保存”。
        if (result?.ok ?? false)
          OutlinedButton.icon(key: const Key('channel-fetch'), onPressed: busy ? null : onFetch, icon: const Icon(Icons.cloud_download_outlined, size: 18), label: Text(busy ? '正在读取…' : '重新获取'))
        else
          FilledButton.icon(
            key: const Key('channel-fetch'),
            onPressed: missing != null || busy ? null : onFetch,
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: Text(busy ? '正在读取…' : (result == null ? '获取模型' : '重新获取')),
          ),
        if (missing != null)
          Padding(
            key: const Key('channel-fetch-missing'),
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text('还差$missing：先在第 1 步填好，这一步才能点。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: Space.x2),
            child: LinearProgressIndicator(),
          ),
        if (result != null && !busy)
          CheckResultBanner(
            result!,
            key: const Key('channel-fetch-result'),
            margin: const EdgeInsets.only(top: Space.x3),
          ),
      ],
    );
  }
}

/// 第 3 步里的一个模型：点整行改参数；右边“测试”发一句短话确认能对话，结果写在下面。
class ModelStepRow extends StatelessWidget {
  const ModelStepRow({super.key, required this.model, required this.onEdit, required this.onTest, required this.testing, required this.result});
  final ModelSpec model;
  final VoidCallback onEdit;

  /// null＝现在不能测（第 1 步没填好，或者别的检查正在跑）。
  final VoidCallback? onTest;
  final bool testing;
  final CheckResult? result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final m = model;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.name, style: t.bodyLarge?.copyWith(height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${m.contextLength ~/ 1000}K 上下文 · 输出 ${m.maxOutput ~/ 1000}K · ${m.vision ? '文本和图片' : '文本'}${m.thinking ? ' · 可思考' : ''}',
                          style: t.bodySmall?.copyWith(color: c.textFaint),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x3),
                OutlinedButton(
                  key: Key('model-test-${m.id}'),
                  onPressed: testing ? null : onTest,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 40),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  ),
                  child: testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('测试'),
                ),
              ],
            ),
            if (result != null && !testing)
              CheckResultBanner(
                result!,
                key: Key('model-test-result-${m.id}'),
                margin: const EdgeInsets.only(top: Space.x2),
              ),
          ],
        ),
      ),
    );
  }
}

/// 第 4 步：小标题 +（没有模型时的一句提醒）+ 实心“保存”。没有模型也能保存，只是提醒一句。
class SaveStep extends StatelessWidget {
  const SaveStep({super.key, required this.noModels, required this.onSave});
  final bool noModels;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
          child: Text('第 4 步 · 保存', style: t.labelMedium?.copyWith(color: c.textFaint)),
        ),
        FilledButton(key: const Key('channel-save'), onPressed: onSave, child: const Text('保存')),
        if (noModels)
          Padding(
            key: const Key('channel-save-hint'),
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
            child: Text('还没有模型。现在也能保存，但对话里要用它，得先在第 2 步或第 3 步加上模型。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
          ),
      ],
    );
  }
}
