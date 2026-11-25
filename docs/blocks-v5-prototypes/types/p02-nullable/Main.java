import java.util.TreeMap;

public class Main {
  static Long 找年龄(TreeMap<String, Long> 名单, String 名字) {
    return 名单.get(名字);
  }

  static String 描述(Long 岁) {
    if (岁 == null) return "不知道";
    if (岁 >= 18) return 岁 + "岁，成年";
    return 岁 + "岁，未成年";
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Long v;
      TreeMap<String, Long> 名单 = Lc.dict();
      名单.put("小明", 12L);
      名单.put("小红", 20L);
      Lc.log(描述(找年龄(名单, "小明")));
      Lc.log(描述(找年龄(名单, "小红")));
      Lc.log(描述(找年龄(名单, "小刚")));
      Long 岁 = 名单.get("小刚");
      Lc.log("默认：" + Lc.or(岁, 0L));
      long 总 = 0;
      for (String 名 : Lc.list("小明", "小红", "小刚")) {
        v = 名单.get(名);
        if (v != null) 总 = Lc.iadd(总, v);
      }
      Lc.log("总和：" + 总);
      String 首字 = null;
      if (岁 != null && 岁 > 3) 首字 = "大"; else 首字 = "无";
      Lc.log("首字：" + Lc.or(首字, "?"));
      Lc.log("硬取：" + Lc.must(岁));
    });
  }
}
