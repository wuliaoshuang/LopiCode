import java.util.ArrayList;

public class Main {
  static final class Zhan<T> {
    ArrayList<T> 项 = Lc.list();
    void 压(T x) { this.项.add(x); }
    T 弹() {
      if (this.项.size() == 0) return null;
      T x = Lc.at(this.项, Lc.isub(this.项.size(), 1));
      this.项.remove(this.项.size() - 1);
      return x;
    }
    long 大小() { return this.项.size(); }
  }
  static final class ZhuangTai<T> {
    T 值;
    ArrayList<Lc.Act2<T, T>> 听 = Lc.list();
    ZhuangTai(T 初) { this.值 = 初; }
    T 读() { return this.值; }
    void 订阅(Lc.Act2<T, T> f) { this.听.add(f); }
    void 写(T 新值) {
      T 旧 = this.值;
      this.值 = 新值;
      for (Lc.Act2<T, T> f : this.听) f.call(旧, 新值);
    }
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Zhan<Long> s = new Zhan<>();
      s.压(1L); s.压(2L); s.压(3L);
      Lc.log("弹 " + Lc.or(s.弹(), -1L) + " 剩 " + s.大小());
      Zhan<String> 名 = new Zhan<>();
      名.压("a");
      Lc.log("弹 " + Lc.or(名.弹(), "?") + " 再弹 " + Lc.or(名.弹(), "空了"));
      ZhuangTai<Long> 计数 = new ZhuangTai<>(0L);
      ArrayList<String> 记 = Lc.list();
      计数.订阅((旧, 新值) -> { 记.add(旧 + "→" + 新值); });
      计数.写(Lc.iadd(计数.读(), 1));
      计数.写(Lc.imul(计数.读(), 10));
      Lc.log(String.join(" ", 记));
      ZhuangTai<String> 标题 = new ZhuangTai<>("你好");
      标题.订阅((旧, 新值) -> { Lc.log("标题变了：" + 新值); });
      标题.写("再见");
    });
  }
}
