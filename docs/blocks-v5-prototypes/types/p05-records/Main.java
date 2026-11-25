import java.util.ArrayList;
import java.util.Objects;

public class Main {
  // 记录 → record（类型名用 ASCII 的“代码名”：点→Dian、用户→YongHu，见第一轮问题 F1）；equals 自己生成（record 自带的 equals 对小数用的是 Double.compare，和“==”不是一回事）
  record Dian(double x, double y) {
    @Override public boolean equals(Object o) { return o instanceof Dian b && x == b.x && y == b.y; }
    @Override public int hashCode() { return Objects.hash(x, y); }
  }
  record YongHu(String 名字, long 年龄, Dian 位置, String 昵称) {
    @Override public boolean equals(Object o) {
      return o instanceof YongHu b && 名字.equals(b.名字) && 年龄 == b.年龄 && 位置.equals(b.位置) && Objects.equals(昵称, b.昵称);
    }
    @Override public int hashCode() { return Objects.hash(名字, 年龄, 位置, 昵称); }
  }

  static YongHu 搬家(YongHu u, double dx) {
    return new YongHu(u.名字(), u.年龄(), new Dian(u.位置().x() + dx, u.位置().y()), u.昵称());
  }

  static String 介绍(YongHu u) {
    return u.名字() + "(" + u.年龄() + ") 在 " + Lc.fmtNum(u.位置().x()) + "," + Lc.fmtNum(u.位置().y()) + " 昵称:" + Lc.or(u.昵称(), "无");
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      YongHu a = new YongHu("小明", 12, new Dian(1, 2.5), null);
      YongHu b = 搬家(a, 0.5);
      Lc.log(介绍(a));
      Lc.log(介绍(b));
      YongHu c = new YongHu(b.名字(), b.年龄(), b.位置(), "明明");
      Lc.log(介绍(c));
      Lc.log("a等于a的拷贝 " + Lc.boolText(a.equals(new YongHu(a.名字(), a.年龄(), a.位置(), a.昵称()))));
      Lc.log("a等于b " + Lc.boolText(a.equals(b)));
      ArrayList<YongHu> 全部 = Lc.list(a, b, c);
      Lc.log("平均年龄 " + Lc.fmtNum(Lc.fdiv(Lc.reduce(全部, 0L, (s, u) -> Lc.iadd(s, u.年龄())), 全部.size())));
    });
  }
}
