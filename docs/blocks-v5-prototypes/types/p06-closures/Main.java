import java.util.ArrayList;

public class Main {
  static Lc.Fn0<Long> 做计数器(long 步) {
    Lc.Ref<Long> n = new Lc.Ref<>(0L); // 被匿名函数改写的变量 → 盒子
    return () -> {
      n.v = Lc.iadd(n.v, 步);
      return n.v;
    };
  }

  static <A, B, C> Lc.Fn1<A, C> 组合(Lc.Fn1<A, B> f, Lc.Fn1<B, C> g) {
    return x -> g.call(f.call(x));
  }

  static long 做两次(Lc.Fn1<Long, Long> f, long x) {
    return f.call(f.call(x));
  }

  public static void main(String[] args) {
    Lc.run(() -> {
      Lc.Fn0<Long> c1 = 做计数器(1);
      Lc.Fn0<Long> c2 = 做计数器(10);
      c1.call();
      c1.call();
      Lc.log("c1=" + c1.call() + " c2=" + c2.call());
      Lc.Fn1<Long, Long> 加一 = n -> Lc.iadd(n, 1);
      Lc.Fn1<Long, String> 转文 = n -> "<" + n + ">";
      Lc.Fn1<Long, String> 管 = 组合(加一, 转文);
      Lc.log(管.call(41L));
      Lc.log("两次 " + 做两次(加一, 5));
      ArrayList<Lc.Fn1<Long, Long>> 动作 = Lc.list(加一, n -> Lc.imul(n, 2));
      long x = 3;
      for (Lc.Fn1<Long, Long> f : 动作) x = f.call(x);
      Lc.log("x=" + x);
    });
  }
}
