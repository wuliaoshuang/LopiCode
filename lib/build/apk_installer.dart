// 应用内安装 APK 的入口（逻辑层）。界面只认 [ApkInstaller] 这个接口：
// - 生产实现 [ChannelApkInstaller] 走平台通道 `lopicode/apk_install`（原生那头是 ApkInstallChannel.kt）；
// - 测试 / 截图用假实现（test/support/fake_apk_installer.dart），通过 [apkInstallerOverride] 换进来。
//
// 能知道的只有“有没有把安装包交到系统安装器手里”。装没装成、用户点没点取消，系统不告诉我们，这里也不猜。
// 官方文档的核对记录见 docs/api-notes.md 的“应用内安装 APK”。纯逻辑，不 import 界面库。
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum ApkInstallStatus {
  /// 已经交给系统安装器（界面已经切过去了）。
  launched,

  /// 系统还没允许 LopiCode 安装应用：要用户去设置里打开开关。
  needPermission,

  /// 文件不在了。
  missing,

  /// 文件在，但应用读不了它。
  unreadable,

  /// 系统里没有能接这件事的安装器。
  noInstaller,

  /// 文件不在能直接交出去的目录里，抄一份的时候失败了（多半是空间不够）。
  copyFailed,

  /// 文件所在的位置交不出去。
  notShareable,

  /// 系统拒绝了这次请求。
  blocked,

  /// 这台设备不是安卓（桌面调试），或者这个安装包太老、没有安装通道。
  unsupported,

  /// 等原生那头回话超时。
  timeout,
}

class ApkInstallResult {
  const ApkInstallResult(this.status, {this.staged = false});
  final ApkInstallStatus status;

  /// 是不是先抄了一份到缓存目录再交出去的。
  final bool staged;

  bool get ok => status == ApkInstallStatus.launched;
}

abstract class ApkInstaller {
  /// 打开系统的“允许安装未知应用”设置页。打不开返回 false。
  Future<bool> openPermissionSettings();

  /// 把 [path] 交给系统安装器。系统还没允许 LopiCode 安装应用（Android 8 起要用户在设置里单独打开）时
  /// 回 [ApkInstallStatus.needPermission]，什么都不会发生，可以放心再问。
  Future<ApkInstallResult> install(String path);
}

/// 测试 / 截图用：换掉真实现。
ApkInstaller? apkInstallerOverride;

ApkInstaller currentApkInstaller() => apkInstallerOverride ?? const ChannelApkInstaller();

/// 问一句话的超时（自己定的）。
const Duration kInstallAskTimeout = Duration(seconds: 10);

/// 交给安装器的超时（自己定的）：文件不在登记目录里时原生那头要先抄一份，大文件要一会儿。
const Duration kInstallLaunchTimeout = Duration(minutes: 2);

class ChannelApkInstaller implements ApkInstaller {
  const ChannelApkInstaller();
  static const _channel = MethodChannel('lopicode/apk_install');

  @override
  Future<bool> openPermissionSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings').timeout(kInstallAskTimeout) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<ApkInstallResult> install(String path) async {
    if (!Platform.isAndroid) return const ApkInstallResult(ApkInstallStatus.unsupported);
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('install', path).timeout(kInstallLaunchTimeout);
      return ApkInstallResult(installStatusOf(reply?['status']), staged: reply?['staged'] == true);
    } on PlatformException {
      return const ApkInstallResult(ApkInstallStatus.blocked);
    } on MissingPluginException {
      return const ApkInstallResult(ApkInstallStatus.unsupported);
    } on TimeoutException {
      return const ApkInstallResult(ApkInstallStatus.timeout);
    }
  }
}

/// 原生那头回的字 → 状态。不认识的一律当“系统拒绝了”。
ApkInstallStatus installStatusOf(Object? code) => switch (code) {
  'launched' => ApkInstallStatus.launched,
  'need_permission' => ApkInstallStatus.needPermission,
  'missing' => ApkInstallStatus.missing,
  'unreadable' => ApkInstallStatus.unreadable,
  'no_installer' => ApkInstallStatus.noInstaller,
  'copy_failed' => ApkInstallStatus.copyFailed,
  'not_shareable' => ApkInstallStatus.notShareable,
  _ => ApkInstallStatus.blocked,
};

/// 每种结果给用户看的大白话。
String installStatusText(ApkInstallStatus status) => switch (status) {
  ApkInstallStatus.launched => '已经交给系统安装器了，接下来按系统的提示点“安装”。装没装成由系统安装器告诉你，LopiCode 这边看不到结果。',
  ApkInstallStatus.needPermission => '系统还没允许 LopiCode 安装应用。去设置里把“允许安装未知应用”的开关打开，回来会自动接着装。',
  ApkInstallStatus.missing => '这个安装包已经不在了（被删掉或挪走了），没法安装。',
  ApkInstallStatus.unreadable => '这个安装包 LopiCode 读不了（没有读它的权限），没法交给系统安装器。',
  ApkInstallStatus.noInstaller => '这台设备上没有找到系统安装器，装不了。可以把安装包拷到别的地方用文件管理器装。',
  ApkInstallStatus.copyFailed => '这个文件所在的位置不能直接交给系统安装器，要先抄一份，但没抄成——多半是手机存储空间不够了。腾出空间再试。',
  ApkInstallStatus.notShareable => '这个文件所在的位置没法交给系统安装器。把它挪到工作区里再试。',
  ApkInstallStatus.blocked => '系统拒绝了这次安装请求。到系统设置里看看 LopiCode 有没有被禁止安装应用。',
  ApkInstallStatus.unsupported => '只有装在安卓手机上的 LopiCode 才能直接安装；这台设备上请把安装包拷到手机里再装。',
  ApkInstallStatus.timeout => '等了两分钟系统还没回应，这次没装。再点一次试试。',
};
