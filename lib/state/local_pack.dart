// 一个工作区的“本地打包”：表单 + 这个项目适不适用 + 一次打包的进度 / 结果（按工作区分身）。
//
// 照“不可变快照 + Notifier”写：界面只读 [LocalPackState]，要做什么调 [LocalPackNotifier] 的方法。
// 状态放在这里（不放在页面的 State 里），所以打包中离开打包页再回来，进度和结果都还在。
//
// 防并发和防“销毁后写状态”：
//   - 同一时间只受理一次打包：进行中再点“开始打包”直接不受理（返回 false）；
//   - 每次开始换一个代次，`await` 回来代次对不上、或工作区 / 应用已经关了，就什么都不写；
//   - 打包中表单不让改（改的方法直接不受理），界面也会锁住。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/apk_icon.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/local_pack_form.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/signing_key.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

enum LocalPackPhase {
  /// 没在打包，也没有上一次的结果。
  idle,

  /// 第一次打包：正在生成签名钥匙。
  preparingKey,

  /// 正在打包，[LocalPackState.step] 是走到哪一步。
  packing,

  /// 没成；原因在 [LocalPackState.failure]。
  failed,

  /// 成了；产物在 [LocalPackState.result]。
  done,
}

/// 一次没成功的打包：哪一步、真正的原因、哪个输入有问题。
class LocalPackFailure {
  const LocalPackFailure({required this.message, this.field, this.step});
  final String message;

  /// `packageName` / `appName` / `versionName` / `versionCode` / `icon` / `permissions` / `project` / `template` / `key`，没有是 null。
  final String? field;

  /// 走到哪一步出的事；null ＝ 还没开始打（准备钥匙 / 读模板时）。
  final ApkPackStep? step;
}

class LocalPackState {
  const LocalPackState({
    this.loaded = false,
    this.project,
    this.form = const LocalPackForm(appName: '', packageName: '', versionName: '', versionCode: '', permissions: {}),
    this.icons = const {},
    this.fieldErrors = const {},
    this.iconBusy = false,
    this.phase = LocalPackPhase.idle,
    this.step,
    this.detail = '',
    this.failure,
    this.result,
    this.publicPath,
    this.publicNote,
  });

  /// 表单和适用性读好了没有。
  final bool loaded;

  /// 这个项目能不能本地打包；null ＝ 还在看。
  final WebProjectInfo? project;
  final LocalPackForm form;

  /// 自己选的图标（边长 → PNG）；空 ＝ 用默认图标。
  final Map<int, Uint8List> icons;

  /// 输入框下面要显示的错（键是 field 名）。
  final Map<String, String> fieldErrors;

  /// 正在处理刚选的图。
  final bool iconBusy;
  final LocalPackPhase phase;
  final ApkPackStep? step;
  final String detail;
  final LocalPackFailure? failure;
  final ApkPackResult? result;

  /// 抄到“系统文件管理器找得到”的位置的那一份；没抄是 null。
  final String? publicPath;

  /// 没抄成 / 这台设备没有外部目录时的一句说明。
  final String? publicNote;

  bool get busy => phase == LocalPackPhase.preparingKey || phase == LocalPackPhase.packing;

  LocalPackState copyWith({
    bool? loaded,
    WebProjectInfo? project,
    LocalPackForm? form,
    Map<int, Uint8List>? icons,
    Map<String, String>? fieldErrors,
    bool? iconBusy,
    LocalPackPhase? phase,
    ApkPackStep? step,
    String? detail,
  }) => LocalPackState(
    loaded: loaded ?? this.loaded,
    project: project ?? this.project,
    form: form ?? this.form,
    icons: icons ?? this.icons,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    iconBusy: iconBusy ?? this.iconBusy,
    phase: phase ?? this.phase,
    step: step ?? this.step,
    detail: detail ?? this.detail,
    failure: failure,
    result: result,
    publicPath: publicPath,
    publicNote: publicNote,
  );

  /// 换掉“这一次打包”的那几样（阶段、步骤、失败、结果），别的不动。
  LocalPackState withRun({
    required LocalPackPhase phase,
    ApkPackStep? step,
    String detail = '',
    LocalPackFailure? failure,
    ApkPackResult? result,
    String? publicPath,
    String? publicNote,
    Map<String, String>? fieldErrors,
    LocalPackForm? form,
  }) => LocalPackState(
    loaded: loaded,
    project: project,
    form: form ?? this.form,
    icons: icons,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    iconBusy: iconBusy,
    phase: phase,
    step: step,
    detail: detail,
    failure: failure,
    result: result,
    publicPath: publicPath,
    publicNote: publicNote,
  );
}

class LocalPackNotifier extends Notifier<LocalPackState> {
  LocalPackNotifier(this.session);
  final ProjectSession session;

  late LocalPackState _snap;
  int _gen = 0;
  int _detectGen = 0;
  Future<void>? _loading;

  LocalPackBackend get _backend => currentLocalPackBackend();
  late final LocalPackFormStore _store = LocalPackFormStore(session.guard);
  bool get _alive => ref.mounted && !session.disposed && !session.app.disposed;

  /// 最近一份状态（工作区关掉以后也能读）。
  LocalPackState get current => _snap;

  @override
  LocalPackState build() {
    ref.onDispose(() {
      _gen++;
      _detectGen++;
    });
    // 项目文件变了（新建了 index.html、导出了页面…）：适不适用重新看一遍。打包中不看，打完会自己再看。
    ref.listen(filesRevProvider(session), (_, _) {
      if (_snap.loaded && !_snap.busy) unawaited(detect());
    });
    // 这个 provider 被重建时（invalidate）Notifier 对象可能还是同一个：上一轮“读过了”的记号要清掉，不然 load() 直接返回、页面一直停在“正在看…”。
    _loading = null;
    return _snap = const LocalPackState();
  }

  void _put(LocalPackState next) {
    _snap = next;
    if (_alive) state = next;
  }

  /// 读表单、看项目适不适用（重复调用复用同一次）。
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final options = _backend.permissionOptions;
    final fallback = LocalPackForm.defaults(projectId: session.project.id, projectName: session.project.name, options: options);
    var form = fallback;
    var icons = const <int, Uint8List>{};
    try {
      form = await _store.read(fallback: fallback, options: options);
      if (form.customIcon) {
        icons = await _store.readIcons();
        if (icons.isEmpty) form = form.copyWith(customIcon: false);
      }
    } on FileSystemException {
      // 读不了就用默认值；不让页面打不开。
    }
    if (!_alive) return;
    _put(_snap.copyWith(loaded: true, form: form, icons: icons));
    await detect();
  }

  /// 重新看这个项目适不适用。
  Future<void> detect() async {
    final gen = ++_detectGen;
    WebProjectInfo info;
    try {
      info = await _backend.detectProject(session.project.dir);
    } catch (e, st) {
      CrashLog.instance.record(e, st, source: '本地打包：识别项目', fatal: false);
      info = WebProjectInfo(applicable: false, reason: '没能看出这个项目能不能本地打包：${e is ApkPackException ? e.message : e.runtimeType}');
    }
    if (gen != _detectGen || !_alive) return;
    _put(_snap.copyWith(project: info));
  }

  void _saveLater() {
    final form = _snap.form;
    unawaited(
      // 不等写完：输入框每敲一下都会到这里。写盘失败只记错误日志，这次打开期间内存里的值照样有效。
      _store.write(form).catchError((Object e, StackTrace st) => CrashLog.instance.record(e, st, source: '保存本地打包表单', fatal: false)),
    );
  }

  /// 改表单的文字项。改了哪一项，那一项下面的报错就先收起来。打包中不受理。
  void edit({String? appName, String? packageName, String? versionName, String? versionCode}) {
    if (_snap.busy || !_snap.loaded) return;
    final errors = Map.of(_snap.fieldErrors);
    if (appName != null) errors.remove('appName');
    if (packageName != null) errors.remove('packageName');
    if (versionName != null) errors.remove('versionName');
    if (versionCode != null) errors.remove('versionCode');
    _put(
      _snap.copyWith(
        form: _snap.form.copyWith(appName: appName, packageName: packageName, versionName: versionName, versionCode: versionCode),
        fieldErrors: errors,
      ),
    );
    _saveLater();
  }

  void setPermission(String id, bool on) {
    if (_snap.busy || !_snap.loaded) return;
    final next = {..._snap.form.permissions};
    on ? next.add(id) : next.remove(id);
    final errors = Map.of(_snap.fieldErrors)..remove('permissions');
    _put(_snap.copyWith(form: _snap.form.copyWith(permissions: next), fieldErrors: errors));
    _saveLater();
  }

  /// 换图标：[source] 是用户选的那张图。不能用（太小 / 打不开）抛 [ApkIconException]，原来的图标不动。
  Future<void> setIcon(Uint8List source) async {
    if (_snap.busy || _snap.iconBusy || !_snap.loaded) return;
    _put(_snap.copyWith(iconBusy: true));
    try {
      final icons = await makeApkIcons(source);
      await _store.writeIcons(icons);
      if (!_alive) return;
      final errors = Map.of(_snap.fieldErrors)..remove('icon');
      _put(_snap.copyWith(icons: icons, form: _snap.form.copyWith(customIcon: true), fieldErrors: errors, iconBusy: false));
      _saveLater();
    } on FileSystemException catch (e) {
      if (_alive) _put(_snap.copyWith(iconBusy: false));
      throw ApkIconException('图标存不下来：${e.osError?.message ?? e.message}');
    } catch (_) {
      if (_alive) _put(_snap.copyWith(iconBusy: false));
      rethrow;
    }
  }

  /// 恢复默认图标。
  Future<void> clearIcon() async {
    if (_snap.busy || !_snap.loaded) return;
    final errors = Map.of(_snap.fieldErrors)..remove('icon');
    _put(_snap.copyWith(icons: const {}, form: _snap.form.copyWith(customIcon: false), fieldErrors: errors));
    _saveLater();
    await _store.clearIcons();
  }

  /// 把上一次的结果 / 失败收起来（表单不动）。打包中不受理。
  void dismissRun() {
    if (_snap.busy) return;
    _put(_snap.withRun(phase: LocalPackPhase.idle));
  }

  /// 四个文字项的校验结果（键是 field 名）；空 ＝ 都过了。
  Map<String, String> validate(LocalPackForm form) {
    final b = _backend;
    return {
      'appName': ?b.validateAppName(form.appName),
      'packageName': ?b.validatePackageName(form.packageName),
      'versionName': ?b.validateVersionName(form.versionName),
      'versionCode': ?b.validateVersionCode(form.versionCode),
    };
  }

  /// 开始打包。返回 false ＝ 没受理（正在打 / 还没读好 / 项目不适用 / 输入没过校验——后者的错在 [LocalPackState.fieldErrors] 里）。
  Future<bool> start() async {
    if (_snap.busy || !_snap.loaded) return false;
    final project = _snap.project;
    if (project == null || !project.applicable || project.webRoot == null || project.entry == null) return false;
    final form = _snap.form;
    final errors = validate(form);
    if (errors.isNotEmpty) {
      _put(_snap.withRun(phase: LocalPackPhase.idle, fieldErrors: errors));
      return false;
    }
    final gen = ++_gen;
    bool current() => gen == _gen && _alive;
    final keys = ref.read(signingKeyProvider.notifier);
    ApkPackStep? step;
    try {
      await keys.load();
      if (!current()) return true;
      _put(_snap.withRun(phase: ref.read(signingKeyProvider).hasKey ? LocalPackPhase.packing : LocalPackPhase.preparingKey, step: ApkPackStep.check, fieldErrors: const {}));
      final key = await keys.ensure();
      if (!current()) return true;
      _put(_snap.withRun(phase: LocalPackPhase.packing, step: step = ApkPackStep.check));
      final template = await _backend.loadTemplate();
      if (!current()) return true;
      final versionCode = int.parse(form.versionCode.trim());
      final outDir = Directory(session.guard.resolve('build'));
      await outDir.create(recursive: true);
      final request = ApkPackRequest(
        webRoot: project.webRoot!,
        entry: project.entry!,
        packageName: form.packageName.trim(),
        appName: form.appName.trim(),
        versionName: form.versionName.trim(),
        versionCode: versionCode,
        permissions: form.permissions,
        iconPngs: form.customIcon ? _snap.icons : const {},
        outputPath: p.join(outDir.path, apkFileName(appName: form.appName, versionName: form.versionName, versionCode: versionCode)),
      );
      final result = await _backend.pack(
        template: template,
        key: key,
        request: request,
        onProgress: (progress) {
          if (!current() || progress.step == ApkPackStep.done) return;
          step = progress.step;
          _put(_snap.withRun(phase: LocalPackPhase.packing, step: progress.step, detail: progress.detail));
        },
      );
      // 抄一份到系统文件管理器找得到的位置。抄不成不算打包失败：工作区里那一份是好的，如实说明就行。
      String? publicPath;
      String? publicNote;
      try {
        publicPath = await copyApkToPublic(result.path, session.project.id);
        if (publicPath == null) publicNote = '这台设备没有可以对外的存储目录，安装包只在工作区的 build 文件夹里。';
      } on FileSystemException catch (e) {
        publicNote = '没能抄一份到手机存储（${e.osError?.message ?? e.message}），安装包只在工作区的 build 文件夹里。';
      }
      if (!session.disposed) session.filesChanged();
      if (!current()) return true;
      // 成功一次：下次的版本号默认加 1（表单里马上看得到，可以改）。
      final bumped = _snap.form.versionCode.trim() == form.versionCode.trim() ? _snap.form.copyWith(versionCode: '${versionCode + 1}') : _snap.form;
      _put(_snap.withRun(phase: LocalPackPhase.done, step: ApkPackStep.done, result: result, publicPath: publicPath, publicNote: publicNote, form: bumped));
      _saveLater();
    } on ApkPackException catch (e) {
      if (!current()) return true;
      final field = e.field;
      _put(
        _snap.withRun(
          phase: LocalPackPhase.failed,
          failure: LocalPackFailure(message: e.message, field: field, step: step),
          fieldErrors: field != null && const {'appName', 'packageName', 'versionName', 'versionCode', 'icon', 'permissions'}.contains(field) ? {field: e.message} : const {},
        ),
      );
    } on SigningKeyException catch (e) {
      if (current()) {
        _put(
          _snap.withRun(
            phase: LocalPackPhase.failed,
            failure: LocalPackFailure(message: e.message, field: 'key'),
          ),
        );
      }
    } on FileSystemException catch (e) {
      if (current()) {
        _put(
          _snap.withRun(
            phase: LocalPackPhase.failed,
            failure: LocalPackFailure(message: '读写文件出错：${e.osError?.message ?? e.message}${e.path == null ? '' : '（${p.basename(e.path!)}）'}', step: step),
          ),
        );
      }
    } catch (e, st) {
      // 没预料到的：记进错误日志，界面上也要给个交代，不能一直转圈。
      CrashLog.instance.record(e, st, source: '本地打包', fatal: false);
      if (current()) {
        _put(
          _snap.withRun(
            phase: LocalPackPhase.failed,
            failure: LocalPackFailure(message: '打包时出了没预料到的错（${e.runtimeType}）。详情在 设置 › 关于 › 错误日志。', step: step),
          ),
        );
      }
    }
    if (_alive && !_snap.busy) unawaited(detect());
    return true;
  }
}

/// 某个工作区的本地打包状态。
final localPackProvider = NotifierProvider.family<LocalPackNotifier, LocalPackState, ProjectSession>(LocalPackNotifier.new);
