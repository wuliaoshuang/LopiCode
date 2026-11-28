// 自带的前端库第一批（积木第 5 版·前端 2）：定时、请求、本地保存、状态仓库、事件总线。
// 库本身读得进来、没有问题、只给前端用；各自和“页面”库放在一起过类型检查；六个一起放也不撞名字；
// 只读画布翻得出来（内容是语言核心写的，不是手写代码）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_from_text.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/lang/host_front.dart';
import 'package:lopicode/lang/host_v2.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/lib_front_builtin.dart';
import 'package:lopicode/lowcode/lib_page.dart';

void main() {
  test('五个库读得进来，没有问题，只给前端用，是自带的，不带手写代码', () {
    final libs = lcFrontBuiltinLibs();
    expect(libs.map((l) => l.name), ['定时', '请求', '本地保存', '状态仓库', '事件总线']);
    for (final l in libs) {
      expect(l.problems, isEmpty, reason: l.name);
      expect(l.side, LibSide.frontend, reason: l.name);
      expect(l.builtin, isTrue, reason: l.name);
      expect(l.natives, isEmpty, reason: l.name);
      expect(l.blocks, isNotEmpty, reason: l.name);
      expect(lcIsFrontOptional(l.id), isTrue);
      expect(lcFrontBuiltinLib(l.id), same(l));
    }
    expect(lcIsFrontBuiltin(kLcPageLibId), isTrue);
    expect(lcIsFrontOptional(kLcPageLibId), isFalse);
    expect(lcFrontBuiltinAll().first.id, kLcPageLibId);
  });

  test('每个库碰的宿主接口都是前端这一边有的，而且不碰只许“页面”库用的旧规矩接口', () {
    for (final l in lcFrontBuiltinLibs()) {
      for (final h in l.hosts) {
        expect(langHostOnFrontend(h), isTrue, reason: '${l.name}：$h');
        expect(kHostFrontBuiltinOnly.contains(h), isFalse, reason: '${l.name}：$h');
      }
    }
    // 事件总线是纯积木搭的，一个宿主接口都不碰。
    expect(lcFrontBuiltinLib('lopi/bus')!.hosts, isEmpty);
  });

  test('各自过类型检查；六个放在一起也过（公开的名字不撞）', () {
    for (final l in lcFrontBuiltinLibs()) {
      expect(beLibCheckWith(l, [lcPageLibrary()]), isEmpty, reason: l.name);
    }
    final all = lcFrontBuiltinAll();
    expect(beLibCheckWith(all.last, all), isEmpty);
  });

  test('只读画布：五个库的模块都翻得成积木，没有照文字原样放着的地方', () {
    for (final b in kLcFrontBuiltins) {
      final got = beFromText(b.moduleText, id: b.id, name: lcFrontBuiltinLib(b.id)!.name, side: LibSide.frontend);
      expect(got.problems, isEmpty, reason: b.id);
      expect(got.rawSpots, 0, reason: '${b.id}：${[for (final f in got.fns) ...f.raws]}');
    }
  });
}
