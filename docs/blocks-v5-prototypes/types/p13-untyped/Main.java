import java.util.ArrayList;

public class Main {
  static double 平均(ArrayList<Long> xs) {
    long 总 = 0;
    for (long x : xs) 总 = Lc.iadd(总, x);
    return Lc.fdiv(总, xs.size());
  }

  static String 重复(String s, long n) {
    String out = "";
    for (long i = 0; i < n; i++) out = out + s;
    return out;
  }

  static double 较大(double a, long b) {
    if (a > b) return a;
    return b;
  }

  static long 阶乘(long n) {
    if (n <= 1) return 1;
    return Lc.imul(n, 阶乘(Lc.isub(n, 1)));
  }

  static String 随便(Object v) {
    return "[" + Lc.dtext(v) + "]";
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Lc.log("平均 " + Lc.fmtNum(平均(Lc.list(1L, 2L, 4L))));
      Lc.log(重复("ab", 3));
      Lc.log("较大 " + Lc.fmtNum(较大(3, 7)));
      Lc.log("较大 " + Lc.fmtNum(较大(2.5, 1)));
      Lc.log("阶乘 " + 阶乘(10));
      Lc.log(随便(1.0));
      Lc.log(随便("x"));
      Lc.log(随便(Lc.<Object>list(1.0, 2.0)));
      Lc.log("阶乘 " + 阶乘(19));
    });
  }
}
