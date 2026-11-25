// Agent 后台保活要问系统的几件事。真机走平台通道（安卓原生的前台服务 + 通知），测试里换成假的，
// 桌面 / 测试环境是空实现。这里只有“怎么跟系统说话”，什么时候开、显示什么在 keep_alive.dart。
import 'package:flutter/services.dart';

/// 通知栏那条常驻通知上显示的内容。
class KeepAliveStatus {
  const KeepAliveStatus({required this.title, required this.text, required this.lockText});

  /// 标题（不含任何对话内容）。
  final String title;

  /// 正在做什么（已脱敏、已截短）。
  final String text;

  /// 锁屏上设了“隐藏敏感内容”时显示的那一句（不含文件名、命令）。
  final String lockText;

  @override
  bool operator ==(Object other) => other is KeepAliveStatus && other.title == title && other.text == text && other.lockText == lockText;

  @override
  int get hashCode => Object.hash(title, text, lockText);
}

/// 一轮结束 / 卡住时单独发的那条提醒是哪一种。
enum KeepAliveAlert { done, failed, waiting }

abstract class KeepAliveHost {
  /// 接上原生那头的两个回调：通知上的“停止”被点了；应用看得见 / 看不见了。
  void bind({required void Function() onStop, required void Function(bool visible) onVisible});

  /// 开前台服务并显示 [status]。系统不让开（应用在后台时）返回 false。
  Future<bool> start(KeepAliveStatus status);

  /// 服务已经开着：只换通知上的字。
  Future<void> update(KeepAliveStatus status);

  /// Agent 这头不再需要保活（运行环境那头还要的话，服务会留着）。
  Future<void> stop();

  /// 发一条提醒。应用看得见时原生那头也会再拦一次。
  Future<void> alert(KeepAliveAlert kind, {required String title, required String text, required String lockText});

  /// 把发过的提醒收掉；[kind] 为空＝全部。
  Future<void> cancelAlerts([KeepAliveAlert? kind]);

  /// 通知权限给没给。问不到（不是安卓）返回 null。
  Future<bool?> notificationsAllowed();

  /// 请系统弹“允许通知”的询问（Android 13 起才有；被拒绝过两次后系统不再弹）。
  Future<void> requestNotifications();

  /// 打开系统里这个应用的通知设置 / 应用详情页。打不开返回 false。
  Future<bool> openNotificationSettings();
  Future<bool> openAppSettings();
}

/// 什么都不做的宿主（测试、非安卓平台）。
class NoKeepAliveHost implements KeepAliveHost {
  const NoKeepAliveHost();
  @override
  void bind({required void Function() onStop, required void Function(bool visible) onVisible}) {}
  @override
  Future<bool> start(KeepAliveStatus status) async => true;
  @override
  Future<void> update(KeepAliveStatus status) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> alert(KeepAliveAlert kind, {required String title, required String text, required String lockText}) async {}
  @override
  Future<void> cancelAlerts([KeepAliveAlert? kind]) async {}
  @override
  Future<bool?> notificationsAllowed() async => null;
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<bool> openNotificationSettings() async => false;
  @override
  Future<bool> openAppSettings() async => false;
}

/// 真机：走 `lopicode/agent_keepalive` 通道（原生那头在 MainActivity.kt / KeepAliveHub.kt）。
class ChannelKeepAliveHost implements KeepAliveHost {
  static const _channel = MethodChannel('lopicode/agent_keepalive');

  @override
  void bind({required void Function() onStop, required void Function(bool visible) onVisible}) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'stopPressed':
          onStop();
        case 'visible':
          final v = call.arguments;
          if (v is bool) onVisible(v);
      }
      return null;
    });
  }

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Map<String, String> _status(KeepAliveStatus s) => {'title': s.title, 'text': s.text, 'lockText': s.lockText};

  @override
  Future<bool> start(KeepAliveStatus status) async => await _call<bool>('start', _status(status)) ?? false;

  @override
  Future<void> update(KeepAliveStatus status) => _call<void>('update', _status(status));

  @override
  Future<void> stop() => _call<void>('stop');

  @override
  Future<void> alert(KeepAliveAlert kind, {required String title, required String text, required String lockText}) =>
      _call<void>('alert', {'kind': kind.name, 'title': title, 'text': text, 'lockText': lockText});

  @override
  Future<void> cancelAlerts([KeepAliveAlert? kind]) => _call<void>('cancelAlerts', kind?.name);

  @override
  Future<bool?> notificationsAllowed() => _call<bool>('notificationsAllowed');

  @override
  Future<void> requestNotifications() => _call<void>('requestNotifications');

  @override
  Future<bool> openNotificationSettings() async => await _call<bool>('openNotificationSettings') ?? false;

  @override
  Future<bool> openAppSettings() async => await _call<bool>('openAppSettings') ?? false;
}
