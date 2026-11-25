import java.util.ArrayList;
import java.util.TreeMap;

public class Main {
  enum FangFa { GET, POST }
  record QingQiu(FangFa 方法, String 路径, String 内容) {}
  record XiangYing(long 状态, String 内容) {}
  // Java 没有类型别名：“处理”在每个用到的地方展开成 Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing>
  record LuYou(FangFa 方法, ArrayList<String> 段, Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing> 处理) {}

  static final class LuYouQi {
    ArrayList<LuYou> 表 = Lc.list();
    ArrayList<Lc.Fn1<Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing>, Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing>>> 中间件 = Lc.list();

    void 加(FangFa m, String 路径, Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing> h) {
      this.表.add(new LuYou(m, Lc.split(路径, "/"), h));
    }
    void 用(Lc.Fn1<Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing>, Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing>> mw) {
      this.中间件.add(mw);
    }
    TreeMap<String, String> 匹配(ArrayList<String> 模, ArrayList<String> 实) {
      String a, b;
      if (模.size() != 实.size()) return null;
      TreeMap<String, String> 参 = Lc.dict();
      for (long i = 0; i < 模.size(); i++) {
        a = Lc.at(模, i);
        b = Lc.at(实, i);
        if (a.startsWith(":")) 参.put(Lc.substr(a, 1, Lc.textLen(a)), b);
        else if (!a.equals(b)) return null;
      }
      return 参;
    }
    XiangYing 处理(QingQiu req) {
      TreeMap<String, String> 参;
      Lc.Fn2<QingQiu, TreeMap<String, String>, XiangYing> h;
      ArrayList<String> 实 = Lc.split(req.路径(), "/");
      for (LuYou r : this.表) {
        if (r.方法() == req.方法()) {
          参 = this.匹配(r.段(), 实);
          if (参 != null) {
            h = r.处理();
            for (var mw : this.中间件) h = mw.call(h);
            return h.call(req, 参);
          }
        }
      }
      return new XiangYing(404, "没有这个地址：" + req.路径());
    }
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      LuYouQi app = new LuYouQi();
      Lc.Ref<Long> 次数 = new Lc.Ref<>(0L);
      app.用(下一个 -> (req, 参) -> {
        次数.v = Lc.iadd(次数.v, 1);
        return 下一个.call(req, 参);
      });
      app.用(下一个 -> (req, 参) -> {
        XiangYing res = 下一个.call(req, 参);
        return new XiangYing(res.状态(), res.内容() + " ✓");
      });
      app.加(FangFa.GET, "/hello/:name", (req, 参) -> new XiangYing(200, "你好，" + Lc.or(参.get("name"), "?")));
      app.加(FangFa.POST, "/sum/:a/:b", (req, 参) -> {
        Long a = Lc.parseInt(Lc.or(参.get("a"), ""));
        Long b = Lc.parseInt(Lc.or(参.get("b"), ""));
        if (a == null || b == null) return new XiangYing(400, "要两个整数");
        return new XiangYing(200, Lc.iadd(a, b) + " " + req.内容());
      });
      for (QingQiu q : Lc.list(new QingQiu(FangFa.GET, "/hello/小明", ""), new QingQiu(FangFa.POST, "/sum/3/4", "ok"), new QingQiu(FangFa.POST, "/sum/3/x", ""), new QingQiu(FangFa.GET, "/nope", ""), new QingQiu(FangFa.GET, "/sum/1/2", ""))) {
        XiangYing res = app.处理(q);
        Lc.log(res.状态() + " " + res.内容());
      }
      Lc.log("经过中间件 " + 次数.v + " 次");
    });
  }
}
