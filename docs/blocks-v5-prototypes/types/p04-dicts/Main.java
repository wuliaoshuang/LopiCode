import java.util.ArrayList;
import java.util.TreeMap;

public class Main {
  public static void main(String[] args) {
    Lc.run(() -> {
      ArrayList<String> 词 = Lc.list("苹果", "香蕉", "苹果", "😀", "橙子", "香蕉", "苹果", "ｚ");
      TreeMap<String, Long> 数 = Lc.dict();
      for (String w : 词) 数.put(w, Lc.iadd(Lc.or(数.get(w), 0L), 1));
      for (String k : 数.keySet()) {
        long v = 数.get(k);
        Lc.log(k + "=" + v);
      }
      Lc.log("共 " + 数.size() + " 种");
      Lc.log("有梨吗 " + Lc.boolText(数.containsKey("梨")));
      数.remove("香蕉");
      Lc.log(String.join("|", 数.keySet()));
    });
  }
}
