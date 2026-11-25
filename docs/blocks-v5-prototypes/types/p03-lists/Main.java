import java.util.ArrayList;

public class Main {
  public static void main(String[] args) {
    Lc.run(() -> {
      ArrayList<Long> 数 = Lc.list(1L, 2L, 3L, 4L, 5L, 6L);
      ArrayList<Long> 平方 = Lc.map(数, n -> Lc.imul(n, n));
      ArrayList<Long> 偶 = Lc.filter(平方, n -> Lc.imod(n, 2) == 0);
      long 和 = Lc.reduce(偶, 0L, (acc, n) -> Lc.iadd(acc, n));
      ArrayList<Double> 半 = Lc.map(数, n -> Lc.fdiv(n, 2));
      double 均 = Lc.reduce(半, 0.0, (acc, h) -> acc + h);
      ArrayList<String> 词 = Lc.map(数, n -> "#" + n);
      ArrayList<Double> 空的 = Lc.list();
      空的.add(2.5);
      空的.add(1.0);
      Lc.log("平方 " + String.join(",", Lc.map(平方, n -> Lc.intText(n))));
      Lc.log("偶 " + String.join(",", Lc.map(偶, n -> Lc.intText(n))));
      Lc.log("和 " + 和);
      Lc.log("半 " + String.join(",", Lc.map(半, h -> Lc.fmtNum(h))));
      Lc.log("均 " + Lc.fmtNum(均));
      Lc.log("词 " + String.join(",", 词));
      Lc.log("空的 " + String.join(",", Lc.map(空的, h -> Lc.fmtNum(h))) + " 长 " + 空的.size());
      Lc.log("第7项 " + Lc.at(数, 6));
    });
  }
}
