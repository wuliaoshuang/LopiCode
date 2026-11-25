import java.util.ArrayList;
import java.util.TreeMap;

public class Main {
  static String 读用户(Object 数据) {
    TreeMap<String, Object> d = Lc.asDict(数据);
    String 名 = Lc.asText(d.get("名字"));
    long 岁 = Lc.asInt(d.get("年龄"));
    ArrayList<String> 标签 = Lc.map(Lc.asList(d.get("标签")), t -> Lc.asText(t));
    return 名 + " " + Lc.iadd(岁, 1) + " " + String.join("/", 标签);
  }

  static TreeMap<String, Object> 典(Object... kv) {
    TreeMap<String, Object> m = Lc.dict();
    for (int i = 0; i < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
    return m;
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Object 好 = 典("名字", "小明", "年龄", 12.0, "标签", Lc.<Object>list("a", "b"));
      Lc.log(读用户(好));
      long n = 41;
      Object 装 = (double) n;
      Lc.log("装进再取出 " + Lc.iadd(Lc.asInt(装), 1));
      Lc.log("任意相加 " + Lc.dtext(Lc.dadd(装, 0.5)));
      Lc.log("任意的样子 " + Lc.dtext(好));
      for (Object 坏 : Lc.<Object>list(
          典("名字", "小红", "年龄", "十二", "标签", Lc.<Object>list()),
          典("名字", 7.0),
          典("名字", "小刚", "年龄", 12.5, "标签", Lc.<Object>list()),
          "不是字典",
          典("名字", "小白", "年龄", 3.0, "标签", Lc.<Object>list(1.0)))) {
        try { Lc.log(读用户(坏)); } catch (Lc.LcError err) { String e = err.getMessage(); Lc.log("不行：" + e); }
      }
    });
  }
}
