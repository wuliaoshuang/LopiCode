// 自带的前端库（积木第 5 版·前端 2）：第一批定时、请求、本地保存、状态仓库、事件总线；第二批路由、表单校验、国际化、动画。
// 库本身读得进来、没有问题、只给前端用；各自和“页面”库放在一起过类型检查；十个一起放也不撞名字；
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
  test('九个库读得进来，没有问题，只给前端用，是自带的，不带手写代码', () {
    final libs = lcFrontBuiltinLibs();
    expect(libs.map((l) => l.name), ['定时', '请求', '本地保存', '状态仓库', '事件总线', '路由', '表单校验', '国际化', '动画']);
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
    // 第二批四个库碰的都是原来就有的接口：一个新的都没加（逐个钉住，多碰一个就红）。
    expect(lcFrontBuiltinLib('lopi/router')!.hosts.toSet(), {
      'page.ui.life',
      'loc.now',
      'loc.push',
      'loc.replace',
      'loc.go',
      'loc.onPop',
      'win.on',
      'page.state.new',
      'page.state.read',
      'page.state.write',
      'page.state.watch',
    });
    expect(lcFrontBuiltinLib('lopi/form')!.hosts.toSet(), {'page.state.new', 'page.state.write'});
    expect(lcFrontBuiltinLib('lopi/i18n')!.hosts.toSet(), {'page.state.new', 'page.state.read', 'page.state.write', 'page.state.watch'});
    expect(lcFrontBuiltinLib('lopi/anim')!.hosts.toSet(), {'timer.frame', 'time.now', 'page.state.new', 'page.state.read', 'page.state.write'});
  });

  test('各自过类型检查；十个放在一起也过（公开的名字不撞）', () {
    for (final l in lcFrontBuiltinLibs()) {
      expect(beLibCheckWith(l, [lcPageLibrary()]), isEmpty, reason: l.name);
    }
    final all = lcFrontBuiltinAll();
    expect(beLibCheckWith(all.last, all), isEmpty);
  });

  test('只读画布：九个库的模块都翻得成积木，没有照文字原样放着的地方', () {
    for (final b in kLcFrontBuiltins) {
      final got = beFromText(b.moduleText, id: b.id, name: lcFrontBuiltinLib(b.id)!.name, side: LibSide.frontend);
      expect(got.problems, isEmpty, reason: b.id);
      expect(got.rawSpots, 0, reason: '${b.id}：${[for (final f in got.fns) ...f.raws]}');
    }
  });
}
