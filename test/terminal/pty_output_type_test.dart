import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 真机上出过的问题：flutter_pty 的输出是 `Stream<Uint8List>`，
/// 直接 transform(Utf8Decoder) 会在运行时报类型错误，终端一片空白。
void main() {
  test('Uint8List 流不转型直接解码会报错，转型后正常', () async {
    Stream<List<int>> raw() => Stream<Uint8List>.fromIterable([Uint8List.fromList(utf8.encode('ok\n'))]);
    expect(() => raw().transform(const Utf8Decoder(allowMalformed: true)), throwsA(isA<TypeError>()));
    final text = await raw().cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).join();
    expect(text, 'ok\n');
  });
}
