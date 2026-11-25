// 打包器和签名之间的接口。打包器只管“把要签的东西交出去、把签好的东西接回来”，签名算法在 lib/apkpack/sign/。
import 'dart:typed_data';

/// 一把已经选定钥匙的签名器。实现要能整个发到后台 isolate 里（只含普通数据，不含句柄、回调）。
abstract class ApkSigner {
  /// v1（JAR）签名。[entries] 是“条目名 → 解压后的内容”，包含安装包里除签名文件外的全部条目。
  /// 返回要加进安装包的签名文件（`META-INF/MANIFEST.MF`、`META-INF/CERT.SF`、`META-INF/CERT.RSA`）；返回空表示不做 v1。
  Map<String, Uint8List> v1Files(Map<String, Uint8List> entries);

  /// v2 签名。[alignedZip] 是已经对齐、已含 v1 签名文件的完整 ZIP；返回插入了签名块并修正偏移后的最终字节。
  Uint8List v2(Uint8List alignedZip);

  /// 签名证书的 SHA-256，小写十六进制（和 apksigner 打印的一致）。
  String get certSha256Hex;
}
