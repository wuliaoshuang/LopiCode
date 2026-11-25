// 选一张图当背景：走系统自带的选择器，不申请任何权限。
//
// 安卓上（android/…/BackdropPicker.kt）：优先系统的照片选择器（Photo Picker，Android 13 起自带，
// Android 11–12 靠系统组件更新带上）；这台手机没有就退到系统的文件选择器（ACTION_OPEN_DOCUMENT，image/*）。
// 两种都是“用户亲手挑了哪张，应用就只拿到哪张”，不用存储权限（核对记录见 docs/api-notes.md）。
//
// 原生那头把选中的图复制（太大就先缩小）到应用缓存目录，只把**缓存文件的路径**交回来——
// 几十 MB 的图不会整个塞过通道。之后由 BackdropStore.importFile 校验并搬进应用私有目录。
import 'package:flutter/services.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';

/// 选图的结果。
sealed class BackdropPick {
  const BackdropPick();
}

/// 选好了：[path] 是应用缓存目录里的一份副本（用完由入库那一步删掉）。
class BackdropPicked extends BackdropPick {
  const BackdropPicked(this.path);
  final String path;
}

/// 用户没选就退出来了。
class BackdropPickCancelled extends BackdropPick {
  const BackdropPickCancelled();
}

/// 没选成；[message] 是能直接给用户看的原因。
class BackdropPickFailed extends BackdropPick {
  const BackdropPickFailed(this.message);
  final String message;
}

abstract class BackdropPicker {
  Future<BackdropPick> pick();
}

/// 真机上的实现：平台通道 `lopicode/backdrop`。
class ChannelBackdropPicker implements BackdropPicker {
  const ChannelBackdropPicker();

  static const MethodChannel channel = MethodChannel('lopicode/backdrop');

  @override
  Future<BackdropPick> pick() async {
    try {
      final r = await channel.invokeMethod<Object?>('pickImage', {'maxBytes': kBackdropMaxFileBytes, 'maxSide': kBackdropMaxSide});
      if (r is! Map) return const BackdropPickFailed('系统选择器没有交回图片。');
      final status = r['status'];
      if (status == 'cancelled') return const BackdropPickCancelled();
      final path = r['path'];
      if (status == 'ok' && path is String && path.isNotEmpty) return BackdropPicked(path);
      return const BackdropPickFailed('系统选择器没有交回图片。');
    } on PlatformException catch (e) {
      return BackdropPickFailed(_reason(e.code));
    } on MissingPluginException {
      return const BackdropPickFailed('这台设备上不能选图（只支持安卓手机）。');
    }
  }

  /// 原生那头只回错误代号，人话在这里（不把系统的原始报错直接甩给用户）。
  static String _reason(String code) => switch (code) {
    'too_large' => '这张图太大了（超过 ${kBackdropMaxFileBytes ~/ (1024 * 1024)}MB）。换一张小一点的。',
    'unsupported' => '这个文件不是能用的图片。请选 JPG、PNG 或 WebP。',
    'read_failed' => '读不出这张图：它可能已经被删掉，或者还在云端没下载到手机上。',
    'no_picker' => '这台手机上找不到系统的图片选择器。',
    'no_space' => '存不下这张图：手机存储空间可能不够了。',
    'busy' => '上一次选图还没结束。',
    _ => '选图没成功（$code）。',
  };
}
