// 2026-11-27 中途包：`lib/lang/rules.dart` 里两条路默认关着——带手写代码的库的启用（libNativeCodeEntry）、
// 自己的库直接用宿主接口（userLibHostEntry）。测“开着时是什么样”的测试文件在 main() 开头调一下这里：
// 每条测试前打开、测完改回默认。不许靠全局配置把默认翻成开。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/rules.dart';

void libSwitchesOn({bool native = true, bool hosts = true}) {
  setUp(() {
    if (native) libNativeCodeEntry = true;
    if (hosts) userLibHostEntry = true;
  });
  tearDown(libSwitchesReset);
}

/// 改回默认。
void libSwitchesReset() {
  libNativeCodeEntry = kLibNativeCodeEnabled;
  userLibHostEntry = kUserLibHostEnabled;
}
