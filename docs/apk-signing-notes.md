# 本地打包 APK：签名部分的格式核对记录

代码在 `lib/apkpack/sign/`，全部自己写（纯 Dart，只用了 `crypto` 包的 SHA-256）。这里记下每条格式事实是对着什么核对的、哪天核对的、核对到什么程度。
规矩：只读规范和源码了解格式，不抄代码。核对不了的明确标“未核对”。

核对日期：2026-11-26（北京时间；网页抓取时间为 2026-11-25 18:14 UTC 前后）。

## 一、对着官方文档 / 源码核对过的

| 事实 | 来源 | 状态 |
| --- | --- | --- |
| 签名块格式：`uint64 块大小` ‖ 一串 `uint64 长度 + uint32 ID + 值` ‖ `uint64 块大小`（同一个数）‖ 16 字节魔数 `APK Sig Block 42`；块大小不含第一个大小字段 | https://source.android.com/docs/security/features/apksigning/v2 | 已核对 |
| v2 的 ID 是 `0x7109871a`；里面是带长度前缀的 signer 序列，每个 signer = signed data（摘要们、证书们、附加属性）+ 签名们 + 公钥（SubjectPublicKeyInfo 的 DER） | 同上 | 已核对 |
| 算法 `0x0103` = RSASSA-PKCS1-v1_5 with SHA2-256；RSA 钥匙长度只认 1024 / 2048 / 4096 / 8192 / 16384（没有 3072） | 同上 | 已核对。所以导入只收 2048、4096 位 |
| 摘要算法：三段（条目内容、中央目录、结尾记录）各切成 1MB 的块，每块算 `SHA-256(0xa5 ‖ uint32 块长 ‖ 块)`，再算 `SHA-256(0x5a ‖ uint32 块数 ‖ 各块摘要)` | 同上 | 已核对 |
| 算摘要时，结尾记录里“中央目录偏移”那一格要当成签名块的起点（也就是没插签名块时的值） | 同上 | 已核对 |
| 验证方要求：中央目录紧挨着结尾记录、结尾记录之后没有多余数据 | 同上 | 已核对。不满足的输入直接报错 |
| 防剥离：`.SF` 主节写 `X-Android-APK-Signed: 2`，Android 7.0+ 看到它却找不到 v2 签名就拒绝 | 同上 | 已核对，并用 apksigner 实测（见第三节） |
| 签名块前先把条目段补零到 4096 的整数倍；块里再加一个 ID 为 `0x42726577` 的占位项，把整块大小也凑成 4096 的整数倍；剩余空间不足 12 字节（放不下一项的头）时再多加 4096 | AOSP apksig `ApkSigningBlockUtils.java`（`ANDROID_COMMON_PAGE_ALIGNMENT_BYTES = 4096`、`VERITY_PADDING_BLOCK_ID = 0x42726577`、`generateApkSigningBlockPadding`、`generateApkSigningBlock`）https://android.googlesource.com/platform/tools/apksig/+/master/src/main/java/com/android/apksig/internal/apk/ApkSigningBlockUtils.java | 已核对。**决定：照 apksigner 的做法加**（官方工具签出来就是这样，以后要加 v4 / fs-verity 也需要这个对齐） |
| 签名钥匙有效期：“A validity period of 25 years or more is recommended”；上架 Google Play 要求到期晚于 2033-10-22 | https://developer.android.com/studio/publish/app-signing | 已核对。这里取 30 年 |
| 备份口令的 PBKDF2-HMAC-SHA256 迭代次数：600,000 | OWASP Password Storage Cheat Sheet https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html | 已核对。取 600,000 |

## 二、没能逐字核对原文的（靠官方工具实测兜底）

| 事实 | 情况 |
| --- | --- |
| Miller–Rabin 轮数：FIPS 186-5 表 B.1，1024 位的 p、q 只做 Miller–Rabin 时，出错概率 2^-112 最少 5 轮（2^-100 是 4 轮） | **没打开 FIPS 186-5 的 PDF 原文**。数字是对着 OpenSSL 源码注释（`bn_rsa_fips186_5_prime_MR_rounds`：2048 位及以上的钥匙返回 5）和二手资料核对的。代码取 16 轮，比这个最低数宽裕得多。 |
| 钥匙生成的其他条件（p、q 最高两位置 1、\|p−q\| > 2^(1024−100)、d > 2^1024、e = 65537）出自 FIPS 186-5 附录 A.1 | **章节号未逐字核对**。生成出来的钥匙用 `openssl pkey -check` 实测为 “Key is valid”。 |
| 清单折行：一行（含行尾 CRLF）最多 72 字节，续行以一个空格开头 | JAR 规范原文和 apksig `ManifestWriter` 的常数**没有打开核对**，是凭对规范的了解写的。实测兜底：超长名字、中文名字的包 `apksigner`（按 Android 5–6 只看 v1）和 `jarsigner -verify` 都通过。 |
| `.SF` 各节摘要的算法（对清单里那一节从 `Name:` 到空行为止的原始字节算 SHA-256）、主节的 `SHA-256-Digest-Manifest` | 同上，未对原文；靠 apksigner / jarsigner 实测通过。 |
| 签名编码 EMSA-PKCS1-v1_5 和 SHA-256 的 DigestInfo 前缀（RFC 8017 第 9.2 节） | RFC 原文未打开；`openssl dgst -sha256 -verify` 实测 “Verified OK”，apksigner 也认。 |
| `CERT.RSA`：PKCS#7 SignedData（RFC 2315）不带内容、不带签名属性，签名算法标成 rsaEncryption | RFC 原文未打开；`openssl cms -verify`、apksigner、jarsigner、keytool 实测都认。 |
| 加密私钥：PKCS#8 EncryptedPrivateKeyInfo + PBES2（PBKDF2 / hmacWithSHA256 / aes256-CBC）的 ASN.1 结构和 OID（RFC 5958、RFC 8018） | RFC 原文未打开；`openssl asn1parse` 读出的结构与预期一致，`openssl pkcs8` 用口令解得开，反过来 openssl 造的也能导入。 |
| X.509 证书结构、2050 年起有效期改用 GeneralizedTime（RFC 5280） | RFC 原文未打开；`openssl x509 -text`、`openssl verify`、keytool 实测都认；到期时间（2056 年）用 GeneralizedTime，起始时间用 UTCTime。 |
| AES、PBKDF2 算法本身 | 用公开的已知答案测：FIPS 197 附录 C.1–C.3、NIST SP 800-38A F.2.1 / F.2.2 / F.2.5 / F.2.6（AES-CBC）、RFC 7914 第 11 节的 PBKDF2-HMAC-SHA256 向量；另外和 `crypto` 包的 HMAC 对拍。向量的数值是照文件抄进测试的，测试通过；没有再回头逐字对原文。 |

## 三、实测出来的工具行为（2026-11-26，build-tools 36.0.0 的 apksigner，JDK 21，OpenSSL 3.0.13）

- **`apksigner verify --min-sdk-version 24` 不验 v1。** 这时它那行永远打印 `Verified using v1 scheme (JAR signing): false`，官方 `apksigner sign` 自己签出来的 v1 + v2 包也一样（拿同一个夹具对比过）。要看到 v1、v2 同时为 true，用 `--min-sdk-version 21`（不设上限）；要单独证明 v1 是对的，用 `--min-sdk-version 21 --max-sdk-version 23`。
- 只有 v1 的包、不设上限去验会失败：`ERROR: Target SDK version 35 requires a minimum of signature scheme v2`。这是系统规矩（目标版本 30 起必须有 v2），不是 v1 签错了。
- `.SF` 里写了 `X-Android-APK-Signed: 2`、包里却没有 v2 签名块：apksigner 拒绝（防剥离生效）。所以只做 v1 时不能写这一行（`v1SignatureFiles(…, alsoV2Signed: false)`）。
- apksigner 打印证书名字时中文显示成 `?`（它的输出编码问题），指纹不受影响。

## 四、几个自己定的做法

- v2 只放一个签名者、一种算法（0x0103），附加属性为空；不做 v3 / v4。
- 输入已经带签名块：整块丢掉重签（注意这只换 v2；包里旧的 v1 文件得由打包器重新生成）。
- ZIP64、分卷、结尾记录后有多余数据、中央目录和结尾记录不挨着、旧签名块自相矛盾：一律报错，不猜。结尾记录带注释：照常处理。
- 条目名里有回车、换行、NUL：没法写进清单，报错。
- 清单条目按名字排序，输出是确定的（同样的输入、同一把钥匙，签两次结果逐字节相同）。
