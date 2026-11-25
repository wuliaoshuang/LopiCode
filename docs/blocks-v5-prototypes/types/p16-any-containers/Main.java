import java.util.ArrayList;
import java.util.TreeMap;

public class Main {
  public static void main(String[] args) {
    Lc.run(() -> {
      ArrayList<Long> xs = Lc.list(1L, 2L, 3L);
      Object 装 = Lc.dynList(xs, n -> (double) n);
      xs.add(4L);
      Lc.log("原来的有 " + xs.size() + " 项，装进任意的是 " + Lc.dtext(装));
      ArrayList<Object> 动 = Lc.asList(装);
      动.add("五");
      Lc.log("任意里的 " + Lc.dtext(装));
      try { Lc.listFrom(装, Lc::asInt); Lc.log("到不了这里"); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log("不行：" + e); }
      动.remove(动.size() - 1);
      ArrayList<Long> 回 = Lc.listFrom(装, Lc::asInt);
      回.add(9L);
      Lc.log("取回来的 " + String.join(",", Lc.map(回, n -> Lc.intText(n))) + "，任意里的 " + Lc.dtext(装) + "，原来的有 " + xs.size() + " 项");
      TreeMap<String, Double> d = Lc.dict();
      d.put("a", 1.5);
      Object 装2 = Lc.dynDict(d, v -> v);
      d.put("b", 2.0);
      Lc.log("字典 " + Lc.dtext(装2) + "，原来的有 " + d.size() + " 项");
    });
  }
}
