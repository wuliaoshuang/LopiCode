// RSA：钥匙生成、PKCS#1 v1.5 签名与验签（SHA-256），用 Dart 自带的 BigInt，纯 Dart。
//
// 依据（核对记录见 docs/apk-signing-notes.md；FIPS 186-5 和 RFC 8017 的原文没有逐字核对，轮数是对着 OpenSSL 源码注释核的，
// 章节号凭记忆；生成的钥匙和签名用 openssl 实测过）：
// - 素数检验轮数：FIPS 186-5 表 B.1——2048 位钥匙的 p、q（各 1024 位）只做 Miller–Rabin 时，
//   出错概率 2^-112 最少 5 轮（2^-100 是 4 轮）。这里取 [kRsaMillerRabinRounds] = 16 轮（多出来的只在最后那个真素数上花时间）。
// - 生成条件照 FIPS 186-5 附录 A.1 对“随机取素数”的要求：e = 65537；p、q 最高两位都置 1（保证 n 正好 2048 位，也满足 p、q ≥ √2·2^1023）；
//   gcd(p-1, e) = gcd(q-1, e) = 1；|p - q| > 2^(1024-100)；d = e^-1 mod lcm(p-1, q-1) 且 d > 2^1024。
// - 签名编码：RFC 8017 §9.2 EMSA-PKCS1-v1_5，DigestInfo 前缀是 §9.2 注 1 里 SHA-256 那一串。
//
// 取舍：BigInt 的运算不是常数时间。签名时做了盲化（乘一个随机数再算）并在算完后用公钥验一遍，
// 挡住计时和算错泄露；钥匙只在本机用，没有对外的签名接口。
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lopicode/apkpack/sign/der.dart';

/// 生成素数时 Miller–Rabin 的轮数（FIPS 186-5 表 B.1 的最低要求是 5）。
const int kRsaMillerRabinRounds = 16;

final BigInt kRsaPublicExponent = BigInt.from(65537);

final BigInt _one = BigInt.one;
final BigInt _two = BigInt.two;

/// RSA 私钥（带 CRT 参数）。不可变；[toString] 不带任何数。
class RsaPrivateKey {
  const RsaPrivateKey({required this.n, required this.e, required this.d, required this.p, required this.q, required this.dp, required this.dq, required this.qInv});

  final BigInt n;
  final BigInt e;
  final BigInt d;
  final BigInt p;
  final BigInt q;
  final BigInt dp;
  final BigInt dq;
  final BigInt qInv;

  int get bits => n.bitLength;

  @override
  String toString() => 'RsaPrivateKey($bits 位)';
}

BigInt _randomBits(int bits, Random random) {
  final bytes = Uint8List((bits + 7) >> 3);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  final extra = bytes.length * 8 - bits;
  if (extra > 0) bytes[0] &= 0xff >> extra;
  return bytesToBigInt(bytes);
}

/// [2, n-2] 里的随机数。
BigInt _randomBelow(BigInt n, Random random) {
  final limit = n - BigInt.from(3);
  while (true) {
    final r = _randomBits(n.bitLength, random);
    if (r <= limit) return r + _two;
  }
}

final List<int> _smallPrimes = () {
  const limit = 2047; // 盖住所有 11 位以内的数
  final sieve = List<bool>.filled(limit + 1, true);
  final out = <int>[];
  for (var i = 2; i <= limit; i++) {
    if (!sieve[i]) continue;
    out.add(i);
    for (var j = i * i; j <= limit; j += i) {
      sieve[j] = false;
    }
  }
  return out;
}();

/// 小素数分组相乘（每组的积不超过 2^52）：一次大数取余就能筛掉一组。
final List<(BigInt, List<int>)> _primeGroups = () {
  final groups = <(BigInt, List<int>)>[];
  var product = 1;
  var members = <int>[];
  for (final p in _smallPrimes.skip(1)) {
    if (product * p >= 1 << 52) {
      groups.add((BigInt.from(product), members));
      product = 1;
      members = <int>[];
    }
    product *= p;
    members.add(p);
  }
  groups.add((BigInt.from(product), members));
  return groups;
}();

bool _hasSmallFactor(BigInt n) {
  for (final (product, members) in _primeGroups) {
    final r = (n % product).toInt();
    for (final p in members) {
      if (r % p == 0) return true;
    }
  }
  return false;
}

/// Miller–Rabin：[n] 是不是（很可能是）素数。底数随机取。
bool isProbablePrime(BigInt n, int rounds, Random random) {
  if (n < _two) return false;
  if (n.bitLength <= 11) return _smallPrimes.contains(n.toInt());
  if (n.isEven || _hasSmallFactor(n)) return false;
  final nMinus1 = n - _one;
  var d = nMinus1;
  var s = 0;
  while (d.isEven) {
    d = d >> 1;
    s++;
  }
  for (var round = 0; round < rounds; round++) {
    var x = _randomBelow(n, random).modPow(d, n);
    if (x == _one || x == nMinus1) continue;
    var composite = true;
    for (var i = 1; i < s; i++) {
      x = (x * x) % n;
      if (x == nMinus1) {
        composite = false;
        break;
      }
      if (x == _one) break;
    }
    if (composite) return false;
  }
  return true;
}

BigInt _randomPrime(int bits, BigInt e, Random random) {
  final top = (_one << (bits - 1)) | (_one << (bits - 2));
  while (true) {
    final candidate = _randomBits(bits, random) | top | _one;
    if (_hasSmallFactor(candidate)) continue;
    if ((candidate - _one).gcd(e) != _one) continue;
    if (isProbablePrime(candidate, kRsaMillerRabinRounds, random)) return candidate;
  }
}

/// 生成一把 RSA 钥匙。同步、很费时（见测试里的实测），界面上要放到 isolate 里跑。
/// [random] 只给测试换；正式用默认的 `Random.secure()`。
RsaPrivateKey rsaGenerate({int bits = 2048, Random? random}) {
  if (bits < 512 || bits.isOdd) throw ArgumentError('位数不对');
  final rnd = random ?? Random.secure();
  final e = kRsaPublicExponent;
  final half = bits ~/ 2;
  while (true) {
    var p = _randomPrime(half, e, rnd);
    var q = _randomPrime(half, e, rnd);
    if ((p - q).abs().bitLength <= half - 100) continue;
    if (p < q) (p, q) = (q, p);
    final n = p * q;
    if (n.bitLength != bits) continue;
    final p1 = p - _one;
    final q1 = q - _one;
    final lcm = (p1 * q1) ~/ p1.gcd(q1);
    final d = e.modInverse(lcm);
    if (d.bitLength <= half) continue;
    return RsaPrivateKey(n: n, e: e, d: d, p: p, q: q, dp: d % p1, dq: d % q1, qInv: q.modInverse(p));
  }
}

/// RFC 8017 §9.2 注 1：SHA-256 的 DigestInfo 前缀。
const List<int> _sha256DigestInfo = [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20];

/// EMSA-PKCS1-v1_5：`00 01 FF…FF 00 DigestInfo`，总长 [length] 字节。
Uint8List emsaPkcs1v15Sha256(List<int> message, int length) {
  final digest = crypto.sha256.convert(message).bytes;
  final tLen = _sha256DigestInfo.length + digest.length;
  if (length < tLen + 11) throw ArgumentError('钥匙太短，放不下签名');
  final em = Uint8List(length)..fillRange(0, length, 0xff);
  em[0] = 0x00;
  em[1] = 0x01;
  em[length - tLen - 1] = 0x00;
  em.setRange(length - tLen, length - digest.length, _sha256DigestInfo);
  em.setRange(length - digest.length, length, digest);
  return em;
}

BigInt _privateOp(RsaPrivateKey key, BigInt m) {
  final m1 = m.modPow(key.dp, key.p);
  final m2 = m.modPow(key.dq, key.q);
  final h = (key.qInv * (m1 - m2)) % key.p;
  return m2 + key.q * h;
}

/// RSASSA-PKCS1-v1_5 + SHA-256 签名，返回和模数一样长的字节。钥匙自相矛盾（算出来验不过）抛 [StateError]。
Uint8List rsaSignSha256(RsaPrivateKey key, List<int> message, {Random? random}) {
  final rnd = random ?? Random.secure();
  final k = (key.n.bitLength + 7) >> 3;
  final m = bytesToBigInt(emsaPkcs1v15Sha256(message, k));
  // 盲化：算 (m·r^e)^d = m^d·r，再除掉 r。
  BigInt r;
  BigInt rInv;
  while (true) {
    r = _randomBelow(key.n, rnd);
    try {
      rInv = r.modInverse(key.n);
      break;
    } on Exception {
      // r 和 n 不互素（几乎不可能）：换一个随机数。
    }
  }
  final blinded = (m * r.modPow(key.e, key.n)) % key.n;
  final s = (_privateOp(key, blinded) * rInv) % key.n;
  if (s.modPow(key.e, key.n) != m) throw StateError('RSA 钥匙内部对不上，签不了名');
  return bigIntToBytes(s, k);
}

/// 用公钥验 RSASSA-PKCS1-v1_5 + SHA-256 签名。
bool rsaVerifySha256(BigInt n, BigInt e, List<int> message, List<int> signature) {
  final k = (n.bitLength + 7) >> 3;
  if (signature.length != k) return false;
  final s = bytesToBigInt(signature);
  if (s >= n) return false;
  final Uint8List expected;
  try {
    expected = emsaPkcs1v15Sha256(message, k);
  } on ArgumentError {
    return false;
  }
  final actual = bigIntToBytes(s.modPow(e, n), k);
  var diff = 0;
  for (var i = 0; i < k; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}
