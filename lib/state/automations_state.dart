// 自动化任务的状态（完整版：不可变快照 + Notifier，照额度那个样板）。
//
// 任务清单和运行历史落在 automations.json 里（lib/agent/automation.dart 的 AutomationStore 负责读写和校验）；
// “哪些正在跑”不落盘，由调度器（lib/automation_scheduler.dart）来说。
// 这里把两样合成一份不可变的快照给界面订阅；界面要改就调 [AutomationsNotifier] 的方法。
// 不管是谁改的（界面、Agent 的 schedule_task 工具、调度器记运行结果），快照都会跟着换。
// `Automation` 本身也是不可变的：界面拿到手改不了字段。
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

class AutomationsState {
  AutomationsState({required List<Automation> items, Set<String> running = const {}}) : items = List.unmodifiable(items), running = Set.unmodifiable(running);

  final List<Automation> items;

  /// 正在跑的任务 id。
  final Set<String> running;

  Automation? byId(String? id) => items.where((a) => a.id == id).firstOrNull;
  bool isRunning(String id) => running.contains(id);
}

class AutomationsNotifier extends Notifier<AutomationsState> {
  AutomationStore get _store => ref.read(appServicesProvider).automations;

  @override
  AutomationsState build() {
    final app = ref.watch(appServicesProvider);
    final store = app.automations;
    void onChange() {
      if (ref.mounted) state = AutomationsState(items: store.items, running: state.running);
    }

    store.changeListeners.add(onChange);
    ref.onDispose(() => store.changeListeners.remove(onChange));
    return AutomationsState(items: store.items, running: app.scheduler.running);
  }

  /// 调度器来说一声：正在跑的任务变了。
  void setRunning(Set<String> running) {
    if (ref.mounted) state = AutomationsState(items: state.items, running: running);
  }

  /// 新建（不传 id）或修改一个任务。**调用前必须已经让用户在确认卡上点过头。**
  Future<Automation> upsert({String? id, required String title, required String instruction, required String workspaceId, required TimeRule rule, String permission = 'workspace'}) =>
      _store.upsert(id: id, title: title, instruction: instruction, workspaceId: workspaceId, rule: rule, permission: permission);

  Future<void> remove(String id) => _store.remove(id);

  /// 开 / 关一个任务（重新开启：从现在起算）。
  Future<void> setEnabled(String id, bool on) => _store.setEnabled(id, on);
}

final automationsProvider = NotifierProvider<AutomationsNotifier, AutomationsState>(AutomationsNotifier.new);
