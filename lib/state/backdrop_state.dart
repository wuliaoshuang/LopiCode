import 'dart:async';
import 'dart:io';

import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/backdrop_theme_bridge.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

/// 背景图片放哪、设置存哪（`<设置所在目录>/appearance/`）。
final backdropStoreProvider = Provider<BackdropStore>((ref) => BackdropStore(p.join(ref.watch(settingsStoreProvider).file.parent.path, 'appearance')));

/// 选图用哪个实现。真机上是系统选择器；测试里 `use(假实现)`，绝不拉起真的选择器。
class BackdropPickerHolder extends Notifier<BackdropPicker> {
  @override
  BackdropPicker build() => const ChannelBackdropPicker();

  void use(BackdropPicker picker) => state = picker;
}

final backdropPickerProvider = NotifierProvider<BackdropPickerHolder, BackdropPicker>(BackdropPickerHolder.new);

/// “选一张图并入库”的结果。
sealed class BackdropImportResult {
  const BackdropImportResult();
}

class BackdropImportOk extends BackdropImportResult {
  const BackdropImportOk(this.image);
  final ImportedBackdrop image;
}

class BackdropImportCancelled extends BackdropImportResult {
  const BackdropImportCancelled();
}

class BackdropImportFailed extends BackdropImportResult {
  const BackdropImportFailed(this.message);
  final String message;
}

/// 背景图片设置。状态是不可变快照；只有这里能改。
///
/// 存盘文件是异步读的：读完之前 `loaded` 是 false（界面当作没有背景），这期间的修改一律不受理。
class BackdropNotifier extends Notifier<BackdropSettings> {
  final Completer<void> _ready = Completer<void>();
  bool _picking = false;

  /// 存盘文件读完（测试里先等它）。
  Future<void> get ready => _ready.future;

  BackdropStore get _store => ref.read(backdropStoreProvider);

  @override
  BackdropSettings build() {
    unawaited(_load()); // 读完自己写状态；出错在里面接住了
    return const BackdropSettings();
  }

  Future<void> _load() async {
    var loaded = const BackdropSettings(loaded: true);
    try {
      loaded = await _store.load();
      // 设置里记着、但文件已经不在了的图：当作没有图（比如清过应用数据的一部分）
      for (final dark in [false, true]) {
        final look = dark ? loaded.dark : loaded.light;
        if (look.file != null && !await _store.imageFile(look.file!).exists()) {
          loaded = dark ? loaded.copyWith(dark: look.withoutImage()) : loaded.copyWith(light: look.withoutImage());
        }
      }
    } on Exception catch (e, st) {
      CrashLog.instance.record(e, st, source: '读取背景图片设置');
    }
    if (ref.mounted) state = loaded;
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> _save() async {
    try {
      await _store.save(state);
    } on Exception catch (e, st) {
      CrashLog.instance.record(e, st, source: '保存背景图片设置');
    }
  }

  /// 改设置。[persist] 为 false 时只改内存（滑杆拖动过程中），松手再 [commit]。
  void update(BackdropSettings Function(BackdropSettings s) change, {bool persist = true}) {
    if (!state.loaded) return;
    final next = change(state).copyWith(loaded: true);
    if (next != state) state = next;
    if (persist) unawaited(_save()); // 出错在 _save 里接住了
  }

  /// 改浅色 / 深色那一份的样子。
  void updateLook({required bool dark, required BackdropLook Function(BackdropLook l) change, bool persist = true}) => update(
    (s) => dark ? s.copyWith(dark: change(s.dark)) : s.copyWith(light: change(s.light)),
    persist: persist,
  );

  /// 把现在的值写进存盘文件。
  Future<void> commit() => _save();

  /// 拉起系统选择器选一张图，校验后搬进私有目录。这一步**不改设置**：裁剪页点了确认才 [setImage]；
  /// 中途放弃就 [discard]。
  Future<BackdropImportResult> pickAndImport() async {
    if (_picking) return const BackdropImportFailed('上一次选图还没结束。');
    _picking = true;
    try {
      final picked = await ref.read(backdropPickerProvider).pick();
      switch (picked) {
        case BackdropPickCancelled():
          return const BackdropImportCancelled();
        case BackdropPickFailed(:final message):
          return BackdropImportFailed(message);
        case BackdropPicked(:final path):
          try {
            return BackdropImportOk(await _store.importFile(File(path)));
          } on BackdropImportException catch (e) {
            return BackdropImportFailed(e.message);
          }
      }
    } finally {
      _picking = false;
    }
  }

  /// 用上一张入库好的图（裁剪页确认之后）。旧图没人用了就删掉。
  Future<void> setImage({required bool dark, required ImportedBackdrop image, required CropRect crop, int turns = 0}) async {
    if (!state.loaded) return;
    update((s) {
      final look = (dark ? s.dark : s.light).withImage(file: image.file, width: image.width, height: image.height, crop: crop, turns: turns);
      return (dark ? s.copyWith(dark: look) : s.copyWith(light: look)).copyWith(enabled: true);
    }, persist: false);
    await _save();
    await _store.cleanup(state.files);
  }

  /// 重新裁剪：只换裁剪区域和旋转，图不动。
  Future<void> setCrop({required bool dark, required CropRect crop, required int turns}) async {
    updateLook(
      dark: dark,
      change: (l) => l.copyWith(crop: crop, turns: turns),
      persist: false,
    );
    await _save();
  }

  /// 入库了但没用上（裁剪页退出来了）：把它删掉。
  Future<void> discard() => _store.cleanup(state.files);

  /// 移除一张图并删文件（效果参数留着）。
  Future<void> removeImage({required bool dark}) async {
    updateLook(dark: dark, change: (l) => l.withoutImage(), persist: false);
    await _save();
    await _store.cleanup(state.files);
  }

  /// 给主题导出用：把现在的背景（浅色 / 深色那一份）变成能嵌进主题导出文件的数据。不改任何东西。
  Future<BackdropThemeExport> exportForTheme({required bool dark}) async {
    if (!state.loaded) await ready;
    return exportBackdropForTheme(_store, state.lookFor(dark: dark));
  }

  /// 给主题导入用：把导入文件里带的背景图入库并用上（[dark]＝放到深色那一份，同时打开“深色单独设置”）。
  /// 成功返回 null；没成返回原因（人话），原来的背景不动。
  Future<String?> applyThemeBackground(Map<Object?, Object?> data, {bool dark = false}) async {
    if (!state.loaded) await ready;
    if (!state.loaded) return '背景设置还没读出来，稍后再试。';
    try {
      final r = await importBackdropFromTheme(_store, data, base: dark ? state.dark : state.light);
      update((s) => (dark ? s.copyWith(dark: r.look, darkSeparate: true) : s.copyWith(light: r.look)).copyWith(enabled: true), persist: false);
      await _save();
      await _store.cleanup(state.files);
      return null;
    } on BackdropImportException catch (e) {
      await _store.cleanup(state.files);
      return e.message;
    }
  }

  /// 深色外观要不要单独一份。第一次打开时把浅色那份原样抄过来（同一个图片文件，不多占地方）。
  Future<void> setDarkSeparate(bool on) async {
    update((s) => s.copyWith(darkSeparate: on, dark: on && !s.dark.hasImage ? s.light : s.dark), persist: false);
    await _save();
  }
}

final backdropProvider = NotifierProvider<BackdropNotifier, BackdropSettings>(BackdropNotifier.new);

/// 外观页“背景图”那一行右边的一句当前状态。
String backdropStatusLabel(BackdropSettings s) {
  if (!s.loaded || s.files.isEmpty || !(s.light.hasImage || (s.darkSeparate && s.dark.hasImage))) return '未设置';
  return s.enabled ? '已启用' : '已关闭';
}

final backdropStatusProvider = Provider<String>((ref) => backdropStatusLabel(ref.watch(backdropProvider)));
