public class Main {
  static long 下一个(long x) { return Lc.imod(Lc.imul(x, 48271), 2147483647L); }

  static long 搅(long h, String s) {
    for (int c : s.codePoints().toArray()) h = Lc.imod(Lc.iadd(Lc.imul(h, 31), c), 1000000007L);
    return h;
  }

  static String 试算(Lc.Fn0<String> f) {
    try { return f.call(); } catch (Lc.LcError e) { return e.getMessage(); }
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      long x = 20261125, h1 = 7, h2 = 7, 错 = 0, 不同 = 0;
      for (long i = 0; i < 2000; i++) {
        x = 下一个(x); final long a = Lc.isub(Lc.imod(x, 2000001), 1000000);
        x = 下一个(x); final long b = Lc.isub(Lc.imod(x, 41), 20);
        x = 下一个(x); final double p = Lc.fdiv(Lc.isub(Lc.imod(x, 2000001), 1000000), 997);
        x = 下一个(x); final double q = Lc.fdiv(Lc.isub(Lc.imod(x, 20001), 10000), 7);
        String r1 = 试算(() -> Lc.iadd(a, b) + "," + Lc.isub(a, b) + "," + Lc.imul(a, b) + "," + Lc.idiv(a, b) + "," + Lc.imod(a, b) + "," + Lc.fmtNum(Lc.fdiv(a, b)) + "," + Lc.fmtNum(p + q) + "," + Lc.fmtNum(p - q) + "," + Lc.fmtNum(p * q) + "," + Lc.fmtNum(Lc.fdiv(p, q)));
        final Object fa = (double) a, fb = (double) b, ap = p, aq = q;
        String r2 = 试算(() -> Lc.dtext(Lc.dadd(fa, fb)) + "," + Lc.dtext(Lc.dsub(fa, fb)) + "," + Lc.dtext(Lc.dmul(fa, fb)) + "," + Lc.dtext(Lc.didiv(fa, fb)) + "," + Lc.dtext(Lc.dimod(fa, fb)) + "," + Lc.dtext(Lc.ddiv(fa, fb)) + "," + Lc.dtext(Lc.dadd(ap, aq)) + "," + Lc.dtext(Lc.dsub(ap, aq)) + "," + Lc.dtext(Lc.dmul(ap, aq)) + "," + Lc.dtext(Lc.ddiv(ap, aq)));
        if (r1.equals("除以 0")) 错 = Lc.iadd(错, 1);
        if (!r1.equals(r2)) 不同 = Lc.iadd(不同, 1);
        h1 = 搅(h1, r1);
        h2 = 搅(h2, r2);
      }
      Lc.log("校验和（原生类型的路）" + h1);
      Lc.log("校验和（任意的路）" + h2);
      Lc.log("除以 0 的次数 " + 错 + "，两条路不同的次数 " + 不同);
    });
  }
}
