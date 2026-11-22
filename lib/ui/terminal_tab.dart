// 设计约束（终端 · 390×844）
// - 屏幕大部分留给输出：等宽 13px、深浅色都用 codeBg，新输出自动滚到底。
// - 顶上一行只管“会话”：会话标签 + 新建。
// - 输入行上方一排手机键盘没有的键（Esc / Tab / Ctrl+C / Ctrl+D / ↑ / ↓ / 清屏），横向可滚。
// - 如实说明：这是基础终端（管道 + 手机自带 sh），说明写在会话开头，不藏在设置里。
import 'package:lopicode/project_session.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key, required this.session});
  final ProjectSession session;

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  TerminalSession? _listening;
  int _historyIndex = -1;

  ProjectSession get s => widget.session;
  TerminalSession get term => s.terminals[s.activeTerminal];

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    _attach();
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    _listening?.removeListener(_onOutput);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    _attach();
    setState(() {});
  }

  void _attach() {
    if (identical(_listening, term)) return;
    _listening?.removeListener(_onOutput);
    _listening = term..addListener(_onOutput);
    _historyIndex = -1;
    term.ensureStarted();
    _scrollToEnd();
  }

  void _onOutput() {
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _run() {
    final line = _input.text;
    _input.clear();
    _historyIndex = -1;
    term.run(line);
    _focus.requestFocus();
  }

  void _setInput(String text) {
    _input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _history(int delta) {
    final h = term.history;
    if (h.isEmpty) return;
    var i = _historyIndex == -1 ? h.length : _historyIndex;
    i = (i + delta).clamp(0, h.length);
    _historyIndex = i == h.length ? -1 : i;
    _setInput(i == h.length ? '' : h[i]);
  }

  void _insert(String text) {
    final v = _input.value;
    final start = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    _input.value = TextEditingValue(
      text: v.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  void _newSession() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('本机 shell'),
              subtitle: const Text('手机自带的 sh，在项目目录里打开'),
              onTap: () {
                Navigator.pop(context);
                s.addTerminal();
              },
            ),
            ListTile(
              enabled: false,
              leading: const Icon(Icons.dns_outlined),
              title: const Text('SSH 远程主机'),
              subtitle: const Text('这一版还没接入（缺 SSH 依赖包），接入后可以连到有完整工具链的服务器'),
            ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: 13, height: 1.45, color: c.text);
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  itemCount: s.terminals.length,
                  itemBuilder: (context, i) {
                    final active = i == s.activeTerminal;
                    return Padding(
                      padding: const EdgeInsets.only(right: Space.x2, top: 6, bottom: 6),
                      child: Material(
                        color: active ? c.accentSoft : c.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          side: BorderSide(color: active ? Colors.transparent : c.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => s.selectTerminal(i),
                          child: Padding(
                            padding: EdgeInsets.only(left: Space.x3, right: s.terminals.length > 1 ? Space.x1 : Space.x3),
                            child: Row(
                              children: [
                                Text(s.terminals[i].title, style: t.labelLarge?.copyWith(color: active ? c.accent : c.textMuted)),
                                if (s.terminals.length > 1)
                                  InkWell(
                                    onTap: () => s.closeTerminal(i),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(Icons.close, size: 14, color: c.textFaint),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              IconButton(tooltip: '新建会话', icon: Icon(Icons.add, color: c.accent), onPressed: _newSession),
              const SizedBox(width: Space.x1),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _focus.requestFocus,
            child: Container(
              width: double.infinity,
              color: c.codeBg,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(Space.x3),
                child: SelectableText(term.text.isEmpty ? ' ' : term.text, style: mono),
              ),
            ),
          ),
        ),
        Container(
          height: 40,
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 5),
            children: [
              _Key('Esc', tooltip: '清空当前输入', onTap: () => _setInput('')),
              _Key('Tab', onTap: () => _insert('\t')),
              _Key('Ctrl+C', tooltip: '中断并重开 shell', onTap: term.interrupt),
              _Key('Ctrl+D', tooltip: '结束输入', onTap: term.sendEof),
              _Key('↑', tooltip: '上一条命令', onTap: () => _history(-1)),
              _Key('↓', tooltip: '下一条命令', onTap: () => _history(1)),
              for (final ch in const ['/', '-', '|', '~', '>', '&', '*', '"']) _Key(ch, onTap: () => _insert(ch)),
              _Key('清屏', onTap: term.clear),
            ],
          ),
        ),
        Container(
          color: c.surface,
          padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x2, Space.x2),
          child: Row(
            children: [
              Text('\$', style: mono.copyWith(color: c.accent, fontWeight: FontWeight.w600, fontSize: FontSize.base)),
              const SizedBox(width: Space.x2),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _run(),
                  style: mono.copyWith(fontSize: FontSize.sm),
                  decoration: InputDecoration(
                    hintText: '输入命令，回车执行',
                    fillColor: c.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(tooltip: '执行', icon: Icon(Icons.keyboard_return, color: c.accent), onPressed: _run),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label, {required this.onTap, this.tooltip});
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final key = Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(Radii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: Text(label, style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: 13, color: c.text)),
          ),
        ),
      ),
    );
    return tooltip == null ? key : Tooltip(message: tooltip!, child: key);
  }
}

/// 给别处复用：把提示写成一句话的小条。
class TerminalLimitsNote extends StatelessWidget {
  const TerminalLimitsNote({super.key});

  @override
  Widget build(BuildContext context) => const InfoBanner('这一版是基础终端：手机自带 sh、一次一条命令。完整终端模拟（xterm + PTY）和 SSH 还没接入。');
}
