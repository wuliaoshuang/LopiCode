public class Main {
  public static void main(String[] args) {
    Lc.run(() -> {
      long a = 7, b = 2;
      double x = 0.1, y = 0.2;
      Lc.log("7/2=" + Lc.fmtNum(Lc.fdiv(a, b)));
      Lc.log("7整除2=" + Lc.idiv(a, b));
      Lc.log("-7整除2=" + Lc.idiv(Lc.isub(0, a), b));
      Lc.log("-7余2=" + Lc.imod(Lc.isub(0, a), b));
      Lc.log("7余-2=" + Lc.imod(a, Lc.isub(0, b)));
      Lc.log("0.1+0.2=" + Lc.fmtNum(x + y));
      Lc.log("a+x=" + Lc.fmtNum(a + x));
      Lc.log("6/3=" + Lc.fmtNum(Lc.fdiv(6, 3)));
      long 大 = 9007199254740991L;
      Lc.log("最大整数=" + 大);
      double 平均 = Lc.fdiv(Lc.iadd(a, b), 2);
      Lc.log("平均=" + Lc.fmtNum(平均));
      long n = Lc.ftoi(x * 30);
      Lc.log("n=" + n);
      double f = 1e308;
      Lc.log("太大=" + Lc.fmtNum(f * 10));
      try { Lc.log("大+1=" + Lc.iadd(大, 1)); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log("接住：" + e); }
      try { Lc.log("7整除0=" + Lc.idiv(a, 0)); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log("接住：" + e); }
      try { Lc.log("x/0=" + Lc.fmtNum(Lc.fdiv(x, 0))); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log("接住：" + e); }
      Lc.log("平方=" + Lc.imul(94906267L, 94906267L));
    });
  }
}
