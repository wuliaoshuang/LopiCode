// PBKDF2-HMAC-SHA256（RFC 8018 §5.2），纯 Dart。
// 为什么自己写 SHA-256 的压缩函数：导出备份要迭代几十万次，直接用 crypto 包的 Hmac 每次迭代要新建好几个对象、
// 压 4 个块；这里把口令对应的内外两个中间状态先算好，每次迭代只压 2 个块、不新建对象，手机上才等得起。
// 正确性由测试守着：和 crypto 包的 SHA-256 / HMAC 对拍，加 RFC 7914 §11 的 PBKDF2-HMAC-SHA-256 向量。
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, //
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, //
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, //
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, //
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, //
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, //
];

const List<int> _iv = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];

const int _m = 0xffffffff;

/// SHA-256 压一个块：[w] 前 16 个字是这一块（大端字），后 48 个当草稿；结果 = [init] 状态压完后的 8 个字，写进 [out]。
void sha256Compress(Uint32List init, Uint32List w, Uint32List out) {
  for (var i = 16; i < 64; i++) {
    final x = w[i - 15];
    final y = w[i - 2];
    final s0 = ((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3);
    final s1 = ((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10);
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & _m;
  }
  var a = init[0], b = init[1], c = init[2], d = init[3];
  var e = init[4], f = init[5], g = init[6], h = init[7];
  for (var i = 0; i < 64; i++) {
    final s1 = (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) & _m;
    final ch = (e & f) ^ ((~e & _m) & g);
    final t1 = (h + s1 + ch + _k[i] + w[i]) & _m;
    final s0 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) & _m;
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (s0 + maj) & _m;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & _m;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & _m;
  }
  out[0] = (init[0] + a) & _m;
  out[1] = (init[1] + b) & _m;
  out[2] = (init[2] + c) & _m;
  out[3] = (init[3] + d) & _m;
  out[4] = (init[4] + e) & _m;
  out[5] = (init[5] + f) & _m;
  out[6] = (init[6] + g) & _m;
  out[7] = (init[7] + h) & _m;
}

void _loadBlock(List<int> block64, Uint32List w) {
  for (var i = 0; i < 16; i++) {
    w[i] = (block64[i * 4] << 24) | (block64[i * 4 + 1] << 16) | (block64[i * 4 + 2] << 8) | block64[i * 4 + 3];
  }
}

/// PBKDF2-HMAC-SHA256。[iterations] ≥ 1，[length] 是要多少字节的钥匙。
Uint8List pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations, int length) {
  if (iterations < 1 || length < 1) throw ArgumentError('迭代次数和长度都要大于 0');
  // HMAC 的钥匙：超过一个块先摘要，再补零到 64 字节。
  final key = Uint8List(64);
  final k = password.length > 64 ? crypto.sha256.convert(password).bytes : password;
  key.setRange(0, k.length, k);

  final iv = Uint32List.fromList(_iv);
  final w = Uint32List(64);
  final inner = Uint32List(8); // 压完 (key ^ ipad) 的状态
  final outer = Uint32List(8); // 压完 (key ^ opad) 的状态
  _loadBlock([for (final b in key) b ^ 0x36], w);
  sha256Compress(iv, w, inner);
  _loadBlock([for (final b in key) b ^ 0x5c], w);
  sha256Compress(iv, w, outer);

  final hmac = crypto.Hmac(crypto.sha256, password);
  final out = Uint8List(length);
  final u = Uint32List(8);
  final t = Uint32List(8);
  final mid = Uint32List(8);
  final blocks = (length + 31) ~/ 32;
  for (var block = 1; block <= blocks; block++) {
    // U1 = HMAC(口令, 盐 || 块号)：消息长度不定，走通用实现。
    final first = hmac.convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff, block >> 8 & 0xff, block & 0xff]).bytes;
    for (var i = 0; i < 8; i++) {
      u[i] = (first[i * 4] << 24) | (first[i * 4 + 1] << 16) | (first[i * 4 + 2] << 8) | first[i * 4 + 3];
      t[i] = u[i];
    }
    // U(n) = HMAC(口令, U(n-1))：消息固定 32 字节，内外各正好一个块（消息 32 字节 + 0x80 + 补零 + 位长 768）。
    for (var n = 1; n < iterations; n++) {
      for (var i = 0; i < 8; i++) {
        w[i] = u[i];
      }
      w[8] = 0x80000000;
      w.fillRange(9, 15, 0);
      w[15] = 768;
      sha256Compress(inner, w, mid);
      for (var i = 0; i < 8; i++) {
        w[i] = mid[i];
      }
      w[8] = 0x80000000;
      w.fillRange(9, 15, 0);
      w[15] = 768;
      sha256Compress(outer, w, u);
      for (var i = 0; i < 8; i++) {
        t[i] ^= u[i];
      }
    }
    final base = (block - 1) * 32;
    for (var i = 0; i < 32 && base + i < length; i++) {
      out[base + i] = (t[i >> 2] >> (24 - 8 * (i & 3))) & 0xff;
    }
  }
  return out;
}
