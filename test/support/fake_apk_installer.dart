// 应用内安装的假实现（测试和截图用）：不碰系统，按预先设好的样子回话，并记下被叫了几次。
import 'dart:async';

import 'package:lopicode/build/apk_installer.dart';

class FakeApkInstaller implements ApkInstaller {
  FakeApkInstaller({this.allowed = true});

  /// 系统让不让装。测试里模拟“去设置里打开了开关”就把它改成 true。
  bool allowed;

  /// 设置页打不打得开。
  bool settingsOpen = true;

  /// 允许时 install 回什么。
  ApkInstallStatus outcome = ApkInstallStatus.launched;

  /// 卡住 install，测试自己放行（看“正在交给安装器”用）。
  Completer<void>? gate;

  int settingsOpened = 0;
  final List<String> installed = [];

  /// install 一共被叫了几次（包括被“还没允许”挡回去的）。
  int asked = 0;

  @override
  Future<bool> openPermissionSettings() async {
    settingsOpened++;
    return settingsOpen;
  }

  @override
  Future<ApkInstallResult> install(String path) async {
    asked++;
    await gate?.future;
    if (!allowed) return const ApkInstallResult(ApkInstallStatus.needPermission);
    if (outcome == ApkInstallStatus.launched) installed.add(path);
    return ApkInstallResult(outcome);
  }
}
