// 后台保活的假宿主：不碰平台通道，只把每次调用记下来。
import 'package:flutter/services.dart';
import 'package:lopicode/agent/keep_alive_host.dart';

class FakeKeepAliveHost implements KeepAliveHost {
  /// 按顺序记下的调用：`start:文字`、`update:文字`、`stop`、`alert:种类:标题|正文|锁屏`、`cancel:种类或all`。
  final List<String> calls = [];

  /// 最近一次交给系统显示的进度。
  KeepAliveStatus? shown;

  /// 系统让不让开前台服务（false＝应用在后台时被拒）。
  bool allowStart = true;

  /// 每个方法都抛错（模拟通道坏了）。
  bool broken = false;

  bool? allowed = true;
  bool canOpenSettings = true;
  int permissionRequests = 0;
  int openedNotificationSettings = 0;
  int openedAppSettings = 0;

  void Function()? pressStop;
  void Function(bool visible)? setVisible;

  List<String> of(String prefix) => [
    for (final c in calls)
      if (c == prefix || c.startsWith('$prefix:')) c,
  ];

  void _check() {
    if (broken) throw PlatformException(code: 'boom', message: '假的：通道坏了');
  }

  @override
  void bind({required void Function() onStop, required void Function(bool visible) onVisible}) {
    pressStop = onStop;
    setVisible = onVisible;
  }

  @override
  Future<bool> start(KeepAliveStatus status) async {
    calls.add('start:${status.text}');
    _check();
    if (allowStart) shown = status;
    return allowStart;
  }

  @override
  Future<void> update(KeepAliveStatus status) async {
    calls.add('update:${status.text}');
    _check();
    shown = status;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _check();
    shown = null;
  }

  @override
  Future<void> alert(KeepAliveAlert kind, {required String title, required String text, required String lockText}) async {
    calls.add('alert:${kind.name}:$title|$text|$lockText');
    _check();
  }

  @override
  Future<void> cancelAlerts([KeepAliveAlert? kind]) async {
    calls.add('cancel:${kind?.name ?? 'all'}');
    _check();
  }

  @override
  Future<bool?> notificationsAllowed() async {
    _check();
    return allowed;
  }

  @override
  Future<void> requestNotifications() async {
    permissionRequests++;
    _check();
  }

  @override
  Future<bool> openNotificationSettings() async {
    openedNotificationSettings++;
    _check();
    return canOpenSettings;
  }

  @override
  Future<bool> openAppSettings() async {
    openedAppSettings++;
    _check();
    return canOpenSettings;
  }
}
