import java.util.ArrayList;

public class Main {
  static <T> T 第一个(ArrayList<T> xs) {
    if (xs.size() == 0) return null;
    return Lc.at(xs, 0);
  }

  static <T extends Comparable<T>> T 最大(ArrayList<T> xs, T 底) {
    T m = 底;
    for (T x : xs) if (Lc.cmp(x, m) > 0) m = x;
    return m;
  }

  static <K, V> ArrayList<String> 配对(ArrayList<K> ks, ArrayList<V> vs, Lc.Fn2<K, V, String> f) {
    ArrayList<String> out = Lc.list();
    for (long i = 0; i < ks.size(); i++) out.add(f.call(Lc.at(ks, i), Lc.at(vs, i)));
    return out;
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Lc.log("第一个 " + Lc.or(第一个(Lc.list(3L, 1L, 2L)), -1L));
      ArrayList<String> 空表 = Lc.list();
      Lc.log("空的第一个 " + Lc.or(第一个(空表), "没有"));
      Lc.log("最大整数 " + 最大(Lc.list(3L, 9L, 2L), 0L));
      Lc.log("最大小数 " + Lc.fmtNum(最大(Lc.list(1.5, 0.25), 0.0)));
      Lc.log("最大文字 " + 最大(Lc.list("ｚ", "😀", "a"), ""));
      Lc.log(String.join(";", 配对(Lc.list("a", "b"), Lc.list(1L, 2L), (k, v) -> k + "=" + v)));
    });
  }
}
