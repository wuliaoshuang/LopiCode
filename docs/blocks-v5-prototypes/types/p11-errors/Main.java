import java.util.ArrayList;

public class Main {
  static String 安全除(long a, long b) {
    try {
      return a + "/" + b + "=" + Lc.idiv(a, b);
    } catch (Lc.LcError err) {
      String e = err.getMessage();
      return a + "/" + b + " 不行：" + e;
    } finally {
      Lc.log("算完一次");
    }
  }

  static long 取款(long 余额, long 要取) {
    if (要取 > 余额) Lc.fail("余额不够，还差 " + Lc.isub(要取, 余额));
    return Lc.isub(余额, 要取);
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Lc.log(安全除(7, 2));
      Lc.log(安全除(7, 0));
      long 钱 = 100;
      try { 钱 = 取款(钱, 30); 钱 = 取款(钱, 100); Lc.log("到不了这里"); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log("接住：" + e + " 还剩 " + 钱); }
      ArrayList<Long> xs = Lc.list(1L, 2L, 3L);
      try { Lc.setAt(xs, 5, 9L); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log(e); }
      try {
        try { Lc.fail("里层"); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.fail(e + "→外层"); }
      } catch (Lc.LcError err) { String e2 = err.getMessage(); Lc.log(e2); }
      Lc.log("结果 " + 取款(1, 2));
    });
  }
}
