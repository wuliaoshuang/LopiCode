// 设计约束（额度上限 / 项目规则 · 390×844）
// - 沿用设置页的卡片分组：浅灰底，白色大圆角卡片，一行只做一件事。
// - 额度上限页从上到下：余额卡（大字余额、明细、更新时间、刷新）→ 已用卡（设了上限才有：进度条 + “已使用 x%（剩余 ¥y）”）
//   → 上限表单（金额、币种、提醒阈值、保存）→ 危险操作（从现在重新算、取消上限）→ 说明。
// - 数字全部来自 DeepSeek 余额接口；查不到就写“余额没查到”和原因，不显示任何估的数。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

String _clock(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String _day(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.month} 月 ${t.day} 日 ${two(t.hour)}:${two(t.minute)}';
}

/// 一个 DeepSeek 官方渠道的余额和额度上限。
class QuotaScreen extends ConsumerStatefulWidget {
  const QuotaScreen({super.key, required this.channelId});
  final String channelId;

  @override
  ConsumerState<QuotaScreen> createState() => _QuotaScreenState();
}

class _QuotaScreenState extends ConsumerState<QuotaScreen> {
  final _limit = TextEditingController();
  final _warn = TextEditingController();
  String? _currency;
  bool _loaded = false;
  String? _formError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = appOf(context);
    final q = app.quota.quotaOf(widget.channelId);
    _limit.text = q == null ? '' : _trim(q.limit);
    _warn.text = '${q?.warnPct ?? ChannelQuota.defaultWarnPct}';
    _currency = q?.currency;
    final ch = _channel(app);
    if (ch != null) app.quota.refresh(ch); // 进页面查一次（有节流）
  }

  @override
  void dispose() {
    _limit.dispose();
    _warn.dispose();
    super.dispose();
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Channel? _channel(AppServices app) => app.models.channels.where((c) => c.id == widget.channelId).firstOrNull;

  Future<void> _save(AppServices app, Channel ch, String currency) async {
    final limit = double.tryParse(_limit.text.trim());
    final warn = _warn.text.trim().isEmpty ? 0 : int.tryParse(_warn.text.trim());
    if (limit == null || !(limit > 0) || !limit.isFinite) {
      setState(() => _formError = '上限要填一个大于 0 的金额');
      return;
    }
    if (warn == null || warn < 0 || warn > 99) {
      setState(() => _formError = '提醒阈值填 0 到 99 之间的整数（0 表示不提醒）');
      return;
    }
    setState(() => _formError = null);
    FocusScope.of(context).unfocus();
    await app.quota.setLimit(ch, limit: limit, currency: currency, warnPct: warn);
    if (mounted) showSnack(context, '已保存：上限 ${formatMoney(currency, limit)}');
  }

  Future<void> _restart(AppServices app, Channel ch) async {
    final ok = await confirmDialog(context, title: '从现在重新算？', message: '已用会清零，以现在的余额作为新的起点。上限金额不变。', confirmLabel: '重新算');
    if (!ok) return;
    await app.quota.restart(ch);
    if (mounted) showSnack(context, '已从现在重新计算');
  }

  Future<void> _clear(AppServices app) async {
    final ok = await confirmDialog(context, title: '取消额度上限？', message: '取消后这个渠道不再按额度拦截请求，也不再提醒。', confirmLabel: '取消上限', danger: true);
    if (!ok) return;
    await app.quota.clearLimit(widget.channelId);
    if (mounted) {
      setState(_limit.clear);
      showSnack(context, '已取消上限');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modelsProvider);
    final app = appOf(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ch = _channel(app);
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: PageBar(background: c.canvas, title: const Text('额度上限')),
      body: ch == null || !isDeepSeekOfficial(ch.baseUrl)
          ? const Padding(padding: EdgeInsets.all(Space.x4), child: InfoBanner('这个渠道不是 DeepSeek 官方接口（api.deepseek.com），查不了余额，也就设不了额度上限。'))
          : QuotaBuilder(
              builder: (context, _) {
                final state = app.quota.stateOf(ch.id);
                final q = app.quota.quotaOf(ch.id);
                final infos = state.result?.infos ?? const <BalanceInfo>[];
                final currencies = [for (final i in infos) i.currency];
                final currency = _currency != null && (currencies.isEmpty || currencies.contains(_currency) || q?.currency == _currency)
                    ? _currency!
                    : (q?.currency ?? currencies.firstOrNull ?? 'CNY');
                final dirtyCurrency = q != null && q.currency != currency;
                return ListView(
                  key: const Key('quota-list'),
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
                  children: [
                    GroupLabel('余额 · ${ch.name}'),
                    GroupCard(
                      dividers: false,
                      padding: const EdgeInsets.all(Space.x4),
                      children: [
                        if (infos.isEmpty)
                          Text(
                            state.loading ? '正在查余额…' : (state.keyInvalid ? 'Key 无效，查不到余额' : (state.error != null ? '余额没查到' : '还没查过余额')),
                            key: const Key('quota-balance'),
                            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400, fontSize: FontSize.xl),
                          )
                        else
                          for (final info in infos) ...[
                            Text(
                              formatMoney(info.currency, info.total),
                              key: Key('quota-balance-${info.currency}'),
                              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400, fontSize: FontSize.xl),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                '${info.currency} 余额',
                                if (info.toppedUp != null) '充值 ${formatMoney(info.currency, info.toppedUp!)}',
                                if (info.granted != null) '赠送 ${formatMoney(info.currency, info.granted!)}',
                              ].join(' · '),
                              style: t.bodyMedium?.copyWith(color: c.textFaint),
                            ),
                            const SizedBox(height: Space.x3),
                          ],
                        if (state.error != null)
                          InfoBanner(
                            '余额没查到：${state.error}${infos.isEmpty ? '' : '\n上面是上一次查到的数。'}',
                            key: const Key('quota-error'),
                            tone: BannerTone.warning,
                            margin: const EdgeInsets.only(top: Space.x1, bottom: Space.x2),
                          ),
                        if (state.result != null && !state.result!.isAvailable)
                          const InfoBanner(
                            'DeepSeek 说这个账号的余额已经不够调用接口了。',
                            tone: BannerTone.warning,
                            margin: EdgeInsets.only(bottom: Space.x2),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(state.at == null ? '数字来自 DeepSeek 的余额接口' : '${state.error == null ? '更新于' : '上次尝试'} ${_clock(state.at!)}', style: t.bodySmall?.copyWith(color: c.textFaint)),
                            ),
                            TextButton.icon(
                              key: const Key('quota-refresh'),
                              onPressed: state.loading ? null : () => app.quota.refresh(ch, force: true),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(state.loading ? '正在查…' : '刷新'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (q != null) ...[
                      const GroupLabel('已用'),
                      GroupCard(
                        dividers: false,
                        padding: const EdgeInsets.all(Space.x4),
                        children: [
                          Text(
                            '已使用 ${q.percent}%（剩余 ${formatMoney(q.currency, q.remaining)}）',
                            key: const Key('quota-used'),
                            style: t.bodyLarge?.copyWith(fontSize: FontSize.lg, color: q.reached ? c.danger : c.text),
                          ),
                          const SizedBox(height: Space.x3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(value: q.fraction, minHeight: 6, color: q.reached ? c.danger : c.accentFill, backgroundColor: c.border),
                          ),
                          const SizedBox(height: Space.x3),
                          Text('已用 ${formatMoney(q.currency, q.used)} / 上限 ${formatMoney(q.currency, q.limit)} · 从 ${_day(q.since)} 算起', style: t.bodySmall?.copyWith(color: c.textFaint)),
                          if (q.lastBalance == null)
                            const InfoBanner(
                              '还没查到过余额，起点没记上；查到第一次余额后才开始算已用。',
                              tone: BannerTone.warning,
                              margin: EdgeInsets.only(top: Space.x3),
                            ),
                          if (q.reached)
                            const InfoBanner(
                              '已达到你设的额度上限，这个渠道的新请求现在会被拦住。调高上限或“从现在重新算”后恢复。',
                              tone: BannerTone.danger,
                              margin: EdgeInsets.only(top: Space.x3),
                            ),
                          if (q.recharge)
                            const InfoBanner(
                              '余额比上次查到的变多了（可能充值了）。已用没有因此减少；想从现在的余额重新开始算，点下面的“从现在重新算”。',
                              key: Key('quota-recharge'),
                              margin: EdgeInsets.only(top: Space.x3),
                            ),
                        ],
                      ),
                    ],
                    GroupLabel(q == null ? '设置额度上限' : '修改上限'),
                    GroupCard(
                      dividers: false,
                      padding: const EdgeInsets.all(Space.x4),
                      children: [
                        TextField(
                          key: const Key('quota-limit'),
                          controller: _limit,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: '额度上限', prefixText: '${currencySymbol(currency)} ', helperText: '用到这个金额就拦住这个渠道的新请求'),
                        ),
                        if (currencies.length > 1) ...[
                          const SizedBox(height: Space.x3),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [for (final cur in currencies) ButtonSegment(value: cur, label: Text(cur))],
                            selected: {currency},
                            onSelectionChanged: (v) => setState(() => _currency = v.first),
                          ),
                        ],
                        if (dirtyCurrency)
                          const InfoBanner(
                            '换币种会把已用清零，按新币种的余额重新开始算。',
                            tone: BannerTone.warning,
                            margin: EdgeInsets.only(top: Space.x3),
                          ),
                        const SizedBox(height: Space.x3),
                        TextField(
                          key: const Key('quota-warn'),
                          controller: _warn,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '提醒阈值', suffixText: '%', helperText: '用到这个比例时在聊天里提醒一次，不拦。填 0 不提醒'),
                        ),
                        if (_formError != null)
                          InfoBanner(
                            _formError!,
                            tone: BannerTone.danger,
                            margin: const EdgeInsets.only(top: Space.x3),
                          ),
                        const SizedBox(height: Space.x4),
                        FilledButton(key: const Key('quota-save'), onPressed: () => _save(app, ch, currency), child: const Text('保存')),
                      ],
                    ),
                    if (q != null)
                      GroupCard(
                        children: [
                          GroupRow(key: const Key('quota-restart'), icon: Icons.restart_alt, title: '从现在重新算', subtitle: '已用清零，以现在的余额为起点', onTap: () => _restart(app, ch)),
                          GroupRow(key: const Key('quota-clear'), icon: Icons.block, title: '取消上限', subtitle: '不再拦截，也不再提醒', danger: true, onTap: () => _clear(app)),
                        ],
                      ),
                    const GroupLabel('怎么算的'),
                    GroupCard(
                      dividers: false,
                      padding: const EdgeInsets.all(Space.x4),
                      children: [
                        Text(
                          '· DeepSeek 的接口只告诉我们“还剩多少余额”，没有“限额”这个概念。上限是你自己在这里定的，只在 LopiCode 里生效。\n'
                          '· 已用 = 设上限之后余额减少了多少（每次查到余额时累加）。同一个 Key 在别的软件里花的钱、赠送余额过期，也会算进来。\n'
                          '· 余额变多（充值）不会让已用变少。\n'
                          '· 查余额的时机：打开聊天或设置、打开用量弹层、每轮对话结束后、发请求前（最多每分钟查一次），以及你点“刷新”；换 Key 后马上重查。\n'
                          '· 余额查不到（没网、Key 没权限）时不拦截，按上一次查到的数算。\n'
                          '· 已用是两次查询之间的差，所以可能在一段对话中途才发现超了，会略微超过上限。',
                          style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.7),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// 当前工作区的项目规则。
class ProjectRulesScreen extends StatefulWidget {
  const ProjectRulesScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  State<ProjectRulesScreen> createState() => _ProjectRulesScreenState();
}

class _ProjectRulesScreenState extends State<ProjectRulesScreen> {
  late final _text = TextEditingController(text: widget.session.projectRules);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // 规则是跟着对话一起读盘的；还没读过就先读，免得把已有的规则当成空的盖掉。
    widget.session.loadChat().then((_) {
      if (!mounted) return;
      setState(() {
        if (_text.text.isEmpty) _text.text = widget.session.projectRules;
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    await widget.session.setProjectRules(_text.text);
    if (mounted) showSnack(context, _text.text.trim().isEmpty ? '已清空：这个工作区现在没有规则' : '已保存：下一条消息起生效');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: PageBar(background: c.canvas, title: const Text('项目规则')),
      body: SectionedList(
        inner: const EdgeInsets.all(Space.x4),
        children: [
          Text('工作区：${widget.session.project.name}', style: t.bodyLarge?.copyWith(fontSize: FontSize.lg)),
          const SizedBox(height: Space.x1),
          Text('写在这里的规则只对这个工作区生效，Agent 在这个工作区里的每段对话都必须遵守。换一个工作区要另外写。', style: t.bodySmall?.copyWith(color: c.textMuted)),
          const SizedBox(height: Space.x4),
          TextField(
            key: const Key('rules-field'),
            controller: _text,
            enabled: _ready,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(hintText: '例如：\n用中文写注释\n不要改 lib/legacy 目录\n改完代码先跑测试', alignLabelWithHint: true),
          ),
          const SizedBox(height: Space.x2),
          Text('存在工作区的 .lopicode/rules.md 里。', style: t.bodySmall?.copyWith(color: c.textFaint)),
          const SizedBox(height: Space.x4),
          FilledButton(key: const Key('rules-save'), onPressed: _ready ? _save : null, child: const Text('保存')),
        ],
      ),
    );
  }
}
