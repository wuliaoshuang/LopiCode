import 'dart:io';

import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/safe_file.dart';

/// 密钥存储接口。API Key、GitHub Token、SSH 密码 / 私钥只走这里，
/// 永远不进普通设置文件，也不进日志。
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// 是否能在应用重启后保留（用于界面如实提示）。
  bool get persistent;
}

/// 只存在内存里的实现：测试用，也是安全存储插件不可用时的退路。
class MemorySecretStore implements SecretStore {
  final Map<String, String> _data = {};

  @override
  bool get persistent => false;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// 普通（非敏感）设置：一个 JSON 文件。
class SettingsStore {
  SettingsStore(this.file);
  final File file;
  Map<String, dynamic> _data = {};

  Future<void> load() async {
    // 文件坏了：readJsonFile 会把坏文件另存一份再返回 null，这里回退成空设置。
    final decoded = await readJsonFile(file, accept: (j) => j is Map<String, dynamic>, label: '设置文件');
    _data = decoded is Map<String, dynamic> ? decoded : {};
  }

  T? get<T>(String key) {
    final v = _data[key];
    return v is T ? v : null;
  }

  String getString(String key, [String fallback = '']) => get<String>(key) ?? fallback;

  bool getBool(String key, [bool fallback = false]) => get<bool>(key) ?? fallback;

  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    // 内存里的值已经换了：先告诉关心这个键的人（界面立刻跟着变），再去写盘。
    for (final listener in List.of(_keyListeners)) {
      listener(key);
    }
    await writeJsonAtomic(file, _data);
  }

  /// 改一个设置但不等它写完盘（按钮回调、后台顺手记一笔这类没法等的地方用）。
  /// 内存里的值立刻生效；写盘失败只记进错误日志，不会变成没人接的异常。
  void setLater(String key, Object? value) {
    set(key, value).catchError((Object e, StackTrace st) {
      CrashLog.instance.record(e, st, source: '保存设置 $key');
    });
  }

  final List<void Function(String key)> _keyListeners = [];

  /// 某个键被 [set] 之后回调（状态层用它做到“哪个设置变了，只通知关心它的界面”）。
  /// 现在挂着几个监听（测试用来确认订阅取消后没有残留）。
  int get keyListenerCount => _keyListeners.length;

  void addKeyListener(void Function(String key) listener) => _keyListeners.add(listener);
  void removeKeyListener(void Function(String key) listener) => _keyListeners.remove(listener);
}

/// 设置项的键名集中在这里。
class SettingKeys {
  /// 积木盒里加的星：后面接编辑器种类（`blocks.stars.logic`、`blocks.stars.backend`），值是一张字符串表。
  static const blockStarsPrefix = 'blocks.stars.';
  static const agentBaseUrl = 'agent.baseUrl';
  static const agentModel = 'agent.model';
  static const themeMode = 'ui.themeMode'; // system / light / dark
  static const themeLight = 'ui.themeLight'; // 浅色时用哪套主题（主题的标识；默认 default-light）
  static const themeDark = 'ui.themeDark'; // 深色时用哪套主题（默认 default-dark）
  static const githubOwner = 'github.owner';
  static const githubRepo = 'github.repo';
  static const githubRef = 'github.ref';
  static const githubWorkflow = 'github.workflow';
  static const sshHost = 'ssh.host';
  static const sshPort = 'ssh.port';
  static const sshUser = 'ssh.user';
  static const sshAuth = 'ssh.auth'; // password / key
  static const sshBuildCommand = 'ssh.buildCommand';
  static const sshBuildOutput = 'ssh.buildOutput';
  static const sshBuildDir = 'ssh.buildDir';
  static const sshKnownHosts = 'ssh.knownHosts'; // {"host:port": "SHA256:..."}
  static const apkBuildMode = 'apk.buildMode'; // github / ssh
  static const lastProject = 'ui.lastProject';
  static const runtimeRootfsSource = 'runtime.rootfsSource'; // tuna / aliyun / official
  static const runtimeAptMirror = 'runtime.aptMirror';
  static const terminalChineseIme = 'terminal.chinese_ime'; // 终端软键盘：中文输入（默认是直接输入）
  static const runtimeCompat = 'runtime.compat'; // PRoot 兼容模式（PROOT_NO_SECCOMP）
  static const defaultPermission = 'agent.defaultPermission'; // view / workspace / full
  static const subagentEnabled = 'subagent.enabled';
  static const subagentMaxDepth = 'subagent.maxDepth'; // 委派层数，0–3，默认 1
  static const subagentMaxConcurrent = 'subagent.maxConcurrent'; // 同时跑几个，1–4，默认 2
  static const subagentAllowedModels = 'subagent.allowedModels'; // ["渠道ID/模型ID"]；空＝只能跟随上级
  static const teamEnabled = 'team.enabled';
  static const chatSuggestions = 'chat.suggestions'; // 新对话里显示开场建议，默认开
  static const chatUsage = 'chat.usage'; // 在回复下方显示用量，默认开
  static const codeFontSize = 'ui.codeFontSize'; // 代码区域的字号（10–24，默认 14），全应用一个值
  static const chatThinking = 'chat.thinking'; // 在聊天里显示思考过程，默认开
  static const agentAutoCompact = 'agent.autoCompact'; // 上下文快满时自动把较早的对话压成摘要，默认开
  static const agentMaxSteps = 'agent.maxSteps'; // 连着执行多少步后停下来问，10–100，默认 30
  static const agentKeepAlive = 'agent.keepAlive'; // Agent 干活时保持后台运行（前台服务 + 常驻通知），默认开
  static const agentNotifyDone = 'agent.notifyDone'; // 应用不在前台时，做完 / 出错 / 等确认发通知，默认开
  static const memoryEnabled = 'memory.enabled'; // 文件记忆总开关，默认开
  static const memoryAutoConsolidate = 'memory.autoConsolidate'; // 每轮结束后自动整理记忆（每次多花一次模型调用），默认关
}

class SecretKeys {
  static const agentApiKey = 'agent_api_key';
  static const githubToken = 'github_token';
  static const sshPassword = 'ssh_password';
  static const sshPrivateKey = 'ssh_private_key';
  static const sshKeyPassphrase = 'ssh_key_passphrase';
}
