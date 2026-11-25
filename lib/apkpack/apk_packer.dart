// 本地打包 APK 的门面：界面只用这个类和 apk_pack_contract.dart 里的类型。
// 重活（读文件、压缩、签名）放在后台 isolate 里跑，不卡界面；进度通过 [onProgress] 回到调用方所在的 isolate。
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_pack_core.dart';
import 'package:lopicode/apkpack/apk_signer.dart';

export 'package:lopicode/apkpack/apk_signer.dart' show ApkSigner;
export 'package:lopicode/apkpack/apk_validators.dart' show kApkPermissionOptions, validateAppName, validateIconPng, validatePackageName, validateVersionCode, validateVersionName;
export 'package:lopicode/apkpack/web_project.dart' show detectWebProject;

class LocalApkPacker {
  /// [template] 是壳模板 APK 的全部字节（assets/apk_shell/shell.apk）；[signer] 是已经选定钥匙的签名器。
  /// [useIsolate] 只给测试用：false 时在当前 isolate 里同步跑。
  LocalApkPacker({required this.template, required this.signer, this.useIsolate = true});

  final Uint8List template;
  final ApkSigner signer;
  final bool useIsolate;

  /// 打一个包。步骤按 [ApkPackStep] 的顺序上报；先写临时文件再改名，失败不留半截产物。
  /// 能预料的失败抛 [ApkPackException]（大白话 + 出问题的是哪一项）。
  Future<ApkPackResult> pack(ApkPackRequest request, {void Function(ApkPackProgress)? onProgress}) async {
    void report(ApkPackProgress p) => onProgress?.call(p);
    if (!useIsolate) return packApkSync(template, signer, request, report);

    final port = ReceivePort();
    final done = Completer<ApkPackResult>();
    final sub = port.listen((Object? msg) {
      if (done.isCompleted) return;
      switch (msg) {
        case ApkPackProgress():
          report(msg);
        case ApkPackResult():
          done.complete(msg);
        case ApkPackException():
          done.completeError(msg);
        case [final String error, final String stack]:
          // 没预料到的错误：原样往上抛，交给全局的错误日志
          done.completeError(StateError('本地打包出错：$error'), StackTrace.fromString(stack));
        default:
          // 后台退出了却没有给结果（比如内存不够被系统结束）
          done.completeError(const ApkPackException('打包中途被打断了，没有生成安装包。可能是手机内存不够：关掉其他应用，或者减少网页里的大文件后再试。'));
      }
    });
    try {
      await Isolate.spawn(_packInIsolate, (port.sendPort, template, signer, request), onExit: port.sendPort, errorsAreFatal: true);
      return await done.future;
    } finally {
      await sub.cancel();
      port.close();
    }
  }
}

void _packInIsolate((SendPort, Uint8List, ApkSigner, ApkPackRequest) job) {
  final (port, template, signer, request) = job;
  try {
    port.send(packApkSync(template, signer, request, port.send));
  } on ApkPackException catch (e) {
    port.send(e);
  } on Object catch (e, st) {
    port.send(['$e', '$st']);
  }
}
