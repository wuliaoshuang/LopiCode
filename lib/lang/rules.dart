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
/// 现在是 1：严格规矩的生成路径（带类型的生成、运行时检查的小函数）还没接上，这时候把新文档标成 2，它实际还是按老规矩跑，
/// 等生成路径接上那天行为又会变——正好违反“版本号保证行为不变”。生成路径接上的那一段把它改成 [kLangRulesStrict]（就这一行）；
/// 改完以后哪几条现有断言要跟着改，见 docs/blocks-v5-parts/B-impl-notes.md 第 6 节。
const int kLangRulesForNewDocs = kLangRulesLoose;

/// 从存盘的值读规矩版本：没有、不是整数、小于 1 → 1。比 [kLangRulesLatest] 大的原样留着（可能是新版本的应用写的）。
int langRulesFromJson(Object? raw) => raw is int && raw >= 1 ? raw : kLangRulesLoose;

/// 这份文档走不走严格规矩。
bool langRulesStrict(int rules) => rules >= kLangRulesStrict;
