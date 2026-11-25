import java.util.*; import java.util.function.*;
public class G {
  interface Emit { boolean give(Object v); }
  interface Seq { void run(Emit e); }
  static Seq nat = e -> { long i = 1; while (true) { if (!e.give(i)) return; i++; } };
  static Seq map(Seq s, Function<Object,Object> f) { return e -> s.run(v -> e.give(f.apply(v))); }
  static Seq filter(Seq s, Predicate<Object> f) { return e -> s.run(v -> f.test(v) ? e.give(v) : true); }
  static Seq take(Seq s, int n) { return e -> { int[] k = {0}; if (n <= 0) return; s.run(v -> { k[0]++; if (!e.give(v)) return false; return k[0] < n; }); }; }
  static Object firstOver(Seq s, long limit) { Object[] box = {false, null}; s.run(v -> { if ((Long) v > limit) { box[0] = true; box[1] = v; return false; } return true; }); return (Boolean) box[0] ? box[1] : null; }
  public static void main(String[] a) {
    List<String> out = new ArrayList<>();
    take(filter(map(nat, x -> (Long) x * (Long) x), x -> (Long) x % 2 == 1), 4).run(v -> { out.add(String.valueOf(v)); return true; });
    System.out.println(String.join(",", out) + " " + firstOver(map(nat, x -> (Long) x * 3), 10));
  }
}
