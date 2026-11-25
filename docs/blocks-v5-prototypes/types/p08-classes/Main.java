import java.util.ArrayList;

public class Main {
  interface YouMianJi {
    double 面积();
    String 名字();
  }
  static final class Yuan implements YouMianJi {
    double r;
    Yuan(double r) { this.r = r; }
    public double 面积() { return 3 * (this.r * this.r); }
    public String 名字() { return "圆"; }
  }
  static final class Fang implements YouMianJi {
    double a;
    Fang(double a) { this.a = a; }
    public double 面积() { return this.a * this.a; }
    public String 名字() { return "方"; }
  }
  static class DongWu {
    String 名;
    long 腿 = 4;
    DongWu(String 名) { this.名 = 名; }
    String 叫声() { return "…"; }
    String 介绍() { return this.名 + "说" + this.叫声() + "，" + this.腿 + "条腿"; }
  }
  static final class Gou extends DongWu {
    Gou(String 名) { super(名); }
    @Override String 叫声() { return "汪"; }
  }
  static class Niao extends DongWu {
    Niao(String 名) { super(名); this.腿 = 2; }
    @Override String 叫声() { return "啾" + super.叫声(); }
  }

  static double 总面积(ArrayList<YouMianJi> xs) {
    return Lc.reduce(xs, 0.0, (s, x) -> s + x.面积());
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      ArrayList<YouMianJi> 形 = Lc.list(new Yuan(1), new Fang(2));
      for (YouMianJi s : 形) Lc.log(s.名字() + " " + Lc.fmtNum(s.面积()));
      Lc.log("总面积 " + Lc.fmtNum(总面积(形)));
      ArrayList<DongWu> 宠 = Lc.list(new Gou("旺财"), new Niao("啾啾"), new DongWu("某只"));
      for (DongWu p : 宠) Lc.log(p.介绍());
      DongWu d = Lc.at(宠, 0);
      if (d instanceof Gou) Lc.log("第一只是狗");
      Lc.log("是鸟吗 " + Lc.boolText(d instanceof Niao));
    });
  }
}
