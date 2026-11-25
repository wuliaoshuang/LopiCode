import java.util.ArrayList;

public class Main {
  enum Deng { 红, 黄, 绿 }
  sealed interface XingZhuang permits Yuan, JuXing, Dian {}
  record Yuan(double r) implements XingZhuang {}
  record JuXing(double w, double h) implements XingZhuang {}
  record Dian() implements XingZhuang {}

  static Deng 下一个(Deng l) {
    switch (l) {
      case 红: return Deng.绿;
      case 绿: return Deng.黄;
      case 黄: return Deng.红;
      default: throw new IllegalStateException("到不了这里");
    }
  }

  static double 面积(XingZhuang s) {
    switch (s) {
      case Yuan(double r): return 3 * (r * r);
      case JuXing(double w, double h): return w * h;
      case Dian(): return 0;
      default: throw new IllegalStateException("到不了这里");
    }
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Deng l = Deng.红;
      for (long i = 0; i < 4; i++) {
        Lc.log(i + ":" + l.name());
        l = 下一个(l);
      }
      ArrayList<XingZhuang> 全 = Lc.list(new Yuan(1), new JuXing(2, 3.5), new Dian());
      for (XingZhuang s : 全) Lc.log("面积 " + Lc.fmtNum(面积(s)));
      Lc.log("红==红 " + Lc.boolText(l == Deng.红));
      switch (Lc.at(全, 1)) {
        case JuXing(double w, double h) -> Lc.log("宽" + Lc.fmtNum(w));
        default -> Lc.log("不是矩形");
      }
    });
  }
}
