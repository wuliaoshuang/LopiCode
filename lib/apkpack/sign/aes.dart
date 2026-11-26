// AES（FIPS 197）和 CBC 模式（NIST SP 800-38A）+ PKCS#7 补位，纯 Dart。只给“导出 / 导入钥匙备份”用。
// 查表实现，不是常数时间：这里只在本机对一千多字节做一次加解密，没有可被远程计时的接口，可以接受。
// 正确性由测试里的 NIST 已知答案向量守着（FIPS 197 附录 C、SP 800-38A F.2）。
import 'dart:typed_data';

final Uint8List _sbox = _buildSbox();
final Uint8List _invSbox = _invert(_sbox);

int _xtime(int a) => ((a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0)) & 0xff;

int _mul(int a, int b) {
  var r = 0;
  var x = a;
  for (var y = b; y > 0; y >>= 1) {
    if (y & 1 != 0) r ^= x;
    x = _xtime(x);
  }
  return r;
}

/// S 盒按定义现算（GF(2^8) 里求逆，再做仿射变换），不手抄 256 个数。
Uint8List _buildSbox() {
  final box = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    var inv = 0;
    if (i != 0) {
      for (var j = 1; j < 256; j++) {
        if (_mul(i, j) == 1) {
          inv = j;
          break;
        }
      }
    }
    var s = inv;
    for (var r = 1; r <= 4; r++) {
      s ^= ((inv << r) | (inv >> (8 - r))) & 0xff;
    }
    box[i] = s ^ 0x63;
  }
  return box;
}

Uint8List _invert(Uint8List box) {
  final inv = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    inv[box[i]] = i;
  }
  return inv;
}

/// 一把展开好的 AES 钥匙（16 / 24 / 32 字节）。
class Aes {
  Aes(List<int> key) : _rounds = key.length ~/ 4 + 6, _rk = _expand(key);

  final int _rounds;
  final Uint8List _rk;

  static Uint8List _expand(List<int> key) {
    final nk = key.length ~/ 4;
    if (key.length != 16 && key.length != 24 && key.length != 32) throw ArgumentError('AES 钥匙长度只能是 16、24、32 字节');
    final total = 16 * (nk + 7);
    final rk = Uint8List(total)..setRange(0, key.length, key);
    var rcon = 1;
    for (var i = key.length; i < total; i += 4) {
      var t0 = rk[i - 4], t1 = rk[i - 3], t2 = rk[i - 2], t3 = rk[i - 1];
      final word = i ~/ 4;
      if (word % nk == 0) {
        final tmp = t0;
        t0 = _sbox[t1] ^ rcon;
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[tmp];
        rcon = _xtime(rcon);
      } else if (nk > 6 && word % nk == 4) {
        t0 = _sbox[t0];
        t1 = _sbox[t1];
        t2 = _sbox[t2];
        t3 = _sbox[t3];
      }
      rk[i] = rk[i - key.length] ^ t0;
      rk[i + 1] = rk[i - key.length + 1] ^ t1;
      rk[i + 2] = rk[i - key.length + 2] ^ t2;
      rk[i + 3] = rk[i - key.length + 3] ^ t3;
    }
    return rk;
  }

  void _addRoundKey(Uint8List s, int round) {
    for (var i = 0; i < 16; i++) {
      s[i] ^= _rk[round * 16 + i];
    }
  }

  /// 就地加密一个 16 字节的块（状态按列存：s[4*列 + 行]）。
  void encryptBlock(Uint8List s) {
    final t = Uint8List(16);
    _addRoundKey(s, 0);
    for (var round = 1; round <= _rounds; round++) {
      // SubBytes + ShiftRows：第 r 行左移 r 格。
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          t[4 * c + r] = _sbox[s[4 * ((c + r) & 3) + r]];
        }
      }
      if (round < _rounds) {
        for (var c = 0; c < 4; c++) {
          final a0 = t[4 * c], a1 = t[4 * c + 1], a2 = t[4 * c + 2], a3 = t[4 * c + 3];
          s[4 * c] = _xtime(a0) ^ _xtime(a1) ^ a1 ^ a2 ^ a3;
          s[4 * c + 1] = a0 ^ _xtime(a1) ^ _xtime(a2) ^ a2 ^ a3;
          s[4 * c + 2] = a0 ^ a1 ^ _xtime(a2) ^ _xtime(a3) ^ a3;
          s[4 * c + 3] = _xtime(a0) ^ a0 ^ a1 ^ a2 ^ _xtime(a3);
        }
      } else {
        s.setAll(0, t);
      }
      _addRoundKey(s, round);
    }
  }

  /// 就地解密一个 16 字节的块。
  void decryptBlock(Uint8List s) {
    final t = Uint8List(16);
    _addRoundKey(s, _rounds);
    for (var round = _rounds - 1; round >= 0; round--) {
      // InvShiftRows + InvSubBytes：第 r 行右移 r 格。
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          t[4 * ((c + r) & 3) + r] = _invSbox[s[4 * c + r]];
        }
      }
      s.setAll(0, t);
      _addRoundKey(s, round);
      if (round > 0) {
        for (var c = 0; c < 4; c++) {
          final a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
          s[4 * c] = _mul(a0, 14) ^ _mul(a1, 11) ^ _mul(a2, 13) ^ _mul(a3, 9);
          s[4 * c + 1] = _mul(a0, 9) ^ _mul(a1, 14) ^ _mul(a2, 11) ^ _mul(a3, 13);
          s[4 * c + 2] = _mul(a0, 13) ^ _mul(a1, 9) ^ _mul(a2, 14) ^ _mul(a3, 11);
          s[4 * c + 3] = _mul(a0, 11) ^ _mul(a1, 13) ^ _mul(a2, 9) ^ _mul(a3, 14);
        }
      }
    }
  }
}

/// CBC 加密，不补位：[data] 长度必须是 16 的倍数。
Uint8List aesCbcEncryptRaw(List<int> key, List<int> iv, List<int> data) {
  if (iv.length != 16 || data.length % 16 != 0) throw ArgumentError('CBC 的初始向量要 16 字节，数据要是 16 的倍数');
  final aes = Aes(key);
  final out = Uint8List(data.length);
  final block = Uint8List(16);
  var prev = iv;
  var prevOff = 0;
  for (var off = 0; off < data.length; off += 16) {
    for (var i = 0; i < 16; i++) {
      block[i] = data[off + i] ^ prev[prevOff + i];
    }
    aes.encryptBlock(block);
    out.setRange(off, off + 16, block);
    prev = out;
    prevOff = off;
  }
  return out;
}

/// CBC 解密，不去补位。
Uint8List aesCbcDecryptRaw(List<int> key, List<int> iv, List<int> data) {
  if (iv.length != 16 || data.length % 16 != 0) throw ArgumentError('CBC 的初始向量要 16 字节，数据要是 16 的倍数');
  final aes = Aes(key);
  final out = Uint8List(data.length);
  final block = Uint8List(16);
  for (var off = 0; off < data.length; off += 16) {
    block.setRange(0, 16, data, off);
    aes.decryptBlock(block);
    for (var i = 0; i < 16; i++) {
      out[off + i] = block[i] ^ (off == 0 ? iv[i] : data[off - 16 + i]);
    }
  }
  return out;
}

/// CBC + PKCS#7 补位（总会补 1–16 字节）。
Uint8List aesCbcEncrypt(List<int> key, List<int> iv, List<int> plain) {
  final pad = 16 - plain.length % 16;
  return aesCbcEncryptRaw(key, iv, [...plain, for (var i = 0; i < pad; i++) pad]);
}

/// CBC 解密并去掉 PKCS#7 补位；补位不对返回 null（多半是钥匙 / 口令不对）。
Uint8List? aesCbcDecrypt(List<int> key, List<int> iv, List<int> cipher) {
  if (cipher.isEmpty || cipher.length % 16 != 0) return null;
  final plain = aesCbcDecryptRaw(key, iv, cipher);
  final pad = plain.last;
  if (pad < 1 || pad > 16) return null;
  for (var i = plain.length - pad; i < plain.length; i++) {
    if (plain[i] != pad) return null;
  }
  return Uint8List.sublistView(plain, 0, plain.length - pad);
}
