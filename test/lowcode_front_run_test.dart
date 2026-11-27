// 新的页面逻辑（前端这一边的积木文档）的验收（积木第 5 版·前端 1·下半）：
// 每种形状的样例在纯网页 / Vue 3 / React 三种产物里用官方编译器真编译 0 错 0 警告，再在 Node＋jsdom 里真跑——每种形状三组步骤，
// 每组都从新开的页面跑起；React 另外开着 StrictMode 再跑一遍（开工那段不许做两遍事）。
// 环境只在开发机上有；找不到就明确跳过。不联网。没覆盖的：真浏览器、真手机。
@Tags(['external'])
@Timeout(Duration(minutes: 30))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/backend/front_upgrade.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/dev_tools.dart';
import 'support/lib_switches.dart';
import 'support/page_core_samples.dart';
import 'support/page_front_check.dart';
import 'support/page_front_samples.dart';
import 'support/page_front_samples2.dart';

/// 旧积木全集的样例，升级成新的页面逻辑。
LcDocument _upgraded() {
  final doc = coreSampleOld();
  lcFrontStore(doc.logic, lcUpgradeToFront(doc.logic).doc);
  return doc;
}

void main() {
  // 中途包：带手写代码的库的启用、自己的库直接用宿主接口默认都关着（rules.dart）；这里测的是开着时的样子，每条先打开、测完改回默认。
  libSwitchesOn();
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】新的页面逻辑的真编译 / 真跑：$skipWithoutDom');
  }
  for (final kind in kFrontKinds.keys) {
    group('${kFrontKinds[kind]}', () {
      test('函数＋闭包＋类＋错误：三组步骤', () => frontCheckAll(kind, frontSampleCore(), frontStepSetsCore()), skip: skipWithoutDom);
      test('旧积木全集升级成新的页面逻辑：原来那串步骤照过，另加两组（升级不改行为）', () => frontCheckAll(kind, _upgraded(), frontStepSetsOld()), skip: skipWithoutDom);
      test('列表和记录状态＋重复里的事件拿这一项＋去页面带参数（两页）：三组步骤', () => frontCheckAll(kind, frontSampleList(), frontStepSetsList(kind)), skip: skipWithoutDom);
      test('“要等的事”（等、超时、取消、等全部、等最先）＋请求（假网络）：三组步骤', () => frontCheckAll(kind, frontSampleWait(), frontStepSetsWait()), skip: skipWithoutDom);
      test('用了“都行”库和前端库的页面：三组步骤', () => frontCheckAll(kind, frontSampleLibs(), frontStepSetsLibs()), skip: skipWithoutDom);
    });
  }

  group('React 开着 StrictMode 再跑一遍', () {
    test('函数＋闭包＋类＋错误', () => frontCheckAll('react', frontSampleCore(), frontStepSetsCore(), strict: true), skip: skipWithoutDom);
    test('旧积木全集升级', () => frontCheckAll('react', _upgraded(), frontStepSetsOld(), strict: true), skip: skipWithoutDom);
    test('列表和记录状态＋重复里的事件＋去页面带参数', () => frontCheckAll('react', frontSampleList(), frontStepSetsList('react'), strict: true), skip: skipWithoutDom);
    test('“要等的事”＋请求', () => frontCheckAll('react', frontSampleWait(), frontStepSetsWait(), strict: true), skip: skipWithoutDom);
    test('用了库的页面', () => frontCheckAll('react', frontSampleLibs(), frontStepSetsLibs(), strict: true), skip: skipWithoutDom);
  });
}
