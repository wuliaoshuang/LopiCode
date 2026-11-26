/// 规矩版本（设计 docs/blocks-v5-parts/B-type-system.md 5.1）：一份文档按哪一版的规矩检查和生成。
///
/// - **1**：老规矩。全是“任意”、全走小库、除以 0 得 0、文字自动变数字。旧文档没有这个字段，就是 1，行为一个字不变
///   （`test/rules_v1_frozen_test.dart` 钉着）。
/// - **2**：严格规矩。类型不对报错（T 开头的规则，typecheck.dart）、除以 0 报错、整数超范围报错、“等于”不再把 1 和 "1" 当一样。
///
/// 存盘：文档最外层的 [kLangRulesField]（一个整数）。是 1 就不写这个字段——旧文档存出来和以前一个字节都不差。
/// 1 → 2 是用户手动点的“升级到严格规矩”；不能自动降回去。
library;

const int kLangRulesLoose = 1;
const int kLangRulesStrict = 2;

/// 这个版本的应用认识的最高规矩版本。
const int kLangRulesLatest = kLangRulesStrict;

/// 存盘时的字段名。
const String kLangRulesField = 'rules';

/// **开关：新建的文档用哪个规矩版本。** 新建的入口（后端是 `backendStarterDocument`）都读它。
///
/// 2026-11-27（库 1 下半）起是 2：严格规矩的后端生成接上了（见 [kLangStrictBackendGen]），新建的文档直接用严格规矩。
/// 老文档没有这个字段，还是 1，一个字不变。
const int kLangRulesForNewDocs = kLangRulesStrict;

/// **后端文档的严格生成接上了没有。** 2026-11-27 起接上了：严格规矩的后端文档走“接口服务”库那条路
/// （backend_to_service.dart → 版本 2 的生成器），135 条一致性样例的严格版在 Node / Python / PHP / Go / Java 上真跑逐字节一致
/// （test/backend_conformance_strict_test.dart）。改回 false 的话，严格规矩的后端文档**不生成、不启动**，并明说原因
/// （backend_targets.dart 的 `kBeStrictGenPending`）——老的生成器对严格文档会写出和严格规矩不符的代码。
const bool kLangStrictBackendGen = true;

/// **开关：后端积木页“⋯”菜单里出不出现“升级到严格规矩…”。** 2026-11-27 起打开（严格生成接上了）。
/// 界面读的是 backend_screen.dart 的 `beStrictUpgradeEntry`（测试里可以改）。
const bool kStrictRulesUpgradeEnabled = true;

/// 从存盘的值读规矩版本：没有、不是整数、小于 1 → 1。比 [kLangRulesLatest] 大的原样留着（可能是新版本的应用写的）。
int langRulesFromJson(Object? raw) => raw is int && raw >= 1 ? raw : kLangRulesLoose;

/// 这份文档走不走严格规矩。
bool langRulesStrict(int rules) => rules >= kLangRulesStrict;
