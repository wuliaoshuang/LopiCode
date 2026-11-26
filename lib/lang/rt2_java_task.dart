/// 规矩版本 2 的小库·Java·“要等的事”那一块（`LcTask.java`）：这条线、等一会儿、开始做、等、
/// 等最多 / 等全部 / 等最先的一个、取消、一次只让一个做。规矩见 docs/blocks-v5-parts/B-gen-notes.md 第 16 节。只用 JDK 自带的。
library;

const String kRt2JavaTask = r'''
// LopiCode 积木的小库（Java，严格规矩）·要等的事。由 LopiCode 生成，别手改。
import java.util.ArrayList;
import java.util.HashMap;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;

final class LcTask {
  private LcTask() {}

  /** “这条线”：一件事（主程序、一次“开始做”、一个请求）。记在线程自己身上，取消、“一次只让一个做”靠它认。 */
  static final class Line { boolean cancelled; }
  private static final ThreadLocal<Line> LINE = new ThreadLocal<>();
  private static final Line MAIN = new Line();
  private static final String CANCEL = "这件事被取消了";
  // 所有“要等”的地方共用一把锁：有一件事做完、被取消、有人从“一次只让一个做”里出来，就把在等的都叫醒，各自再看一眼。
  private static final ReentrantLock MU = new ReentrantLock();
  private static final Condition WAKE = MU.newCondition();

  static Line line() { Line l = LINE.get(); return l == null ? MAIN : l; }
  /** 一个请求一条线。 */
  static void newLine() { LINE.set(new Line()); }
  /** 到了要等的地方先看一眼，这条线被取消了就抛“取消了”。 */
  static void check() {
    boolean gone;
    MU.lock();
    try { gone = line().cancelled; } finally { MU.unlock(); }
    if (gone) Lc.fail(CANCEL);
  }

  interface Ready { boolean ok(); }
  // 等到 ready 说行。这条线被取消＝先做 quit（有的话）再抛“取消了”；过了 deadline（System.nanoTime 的那种数，null＝一直等）＝交回 false。
  private static boolean block(Ready ready, Long deadline, Runnable quit) {
    Line me = line();
    MU.lock();
    try {
      while (true) {
        if (me.cancelled) {
          if (quit != null) quit.run();
          Lc.fail(CANCEL);
        }
        if (ready.ok()) return true;
        try {
          if (deadline == null) {
            WAKE.await();
          } else {
            long left = deadline - System.nanoTime();
            if (left <= 0) return false;
            WAKE.awaitNanos(left);
          }
        } catch (InterruptedException e) {
          Thread.currentThread().interrupt();
          Lc.fail("等的时候被打断了");
        }
      }
    } finally {
      MU.unlock();
    }
  }
  private static Long after(long ms) { return System.nanoTime() + Math.max(0, ms) * 1000000L; }

  static void sleep(long ms) { block(() -> false, after(ms), null); }

  /** “开始做”的结果。出了错先记着，等它的时候再抛。 */
  static final class Task<T> {
    private boolean done;
    private T val;
    private RuntimeException err;
    private final Line line = new Line();
    private T get() {
      if (err != null) throw err;
      return val;
    }
  }
  static <T> Task<T> spawn(Lc.Fn0<T> f) {
    Task<T> t = new Task<>();
    Thread.ofVirtual().start(() -> {
      LINE.set(t.line);
      try {
        t.val = f.call();
      } catch (RuntimeException e) {
        t.err = e;
      } finally {
        MU.lock();
        try { t.done = true; WAKE.signalAll(); } finally { MU.unlock(); }
      }
    });
    return t;
  }
  static <T> T await(Task<T> t) {
    block(() -> t.done, null, null);
    return t.get();
  }
  /** 最多等 ms 毫秒；到时候还没做完＝“超时”错误（那件事自己接着做）。 */
  static <T> T awaitMax(Task<T> t, long ms) {
    long most = Math.max(0, ms);
    if (!block(() -> t.done, after(most), null)) Lc.fail("等了 " + most + " 毫秒还没做完");
    return t.get();
  }
  static <T> void cancel(Task<T> t) {
    MU.lock();
    try {
      if (!t.done && !t.line.cancelled) {
        t.line.cancelled = true;
        WAKE.signalAll();
      }
    } finally {
      MU.unlock();
    }
  }
  /** 全做完才交回（结果按列表的顺序）。有一件出了错，或者等的人自己被取消了＝把还没做完的都取消，把错抛出去。 */
  static <T> ArrayList<T> awaitAll(ArrayList<Task<T>> list) {
    ArrayList<Task<T>> ts = new ArrayList<>(list);
    ArrayList<Task<T>> bad = new ArrayList<>();
    try {
      block(() -> {
        boolean every = true;
        for (Task<T> t : ts) {
          if (!t.done) {
            every = false;
          } else if (t.err != null) {
            bad.add(t);
            return true;
          }
        }
        return every;
      }, null, null);
    } catch (RuntimeException e) {
      for (Task<T> t : ts) cancel(t);
      throw e;
    }
    if (!bad.isEmpty()) {
      for (Task<T> t : ts) cancel(t);
      throw bad.get(0).err;
    }
    ArrayList<T> out = new ArrayList<>(ts.size());
    for (Task<T> t : ts) out.add(t.val);
    return out;
  }
  /** 谁先做完（成了或者出错）就用谁的；别的接着做。 */
  static <T> T awaitAny(ArrayList<Task<T>> list) {
    ArrayList<Task<T>> ts = new ArrayList<>(list);
    if (ts.isEmpty()) Lc.fail("“等最先的一个”的列表是空的");
    ArrayList<Task<T>> first = new ArrayList<>();
    block(() -> {
      for (Task<T> t : ts) {
        if (t.done) {
          first.add(t);
          return true;
        }
      }
      return false;
    }, null, null);
    return first.get(0).get();
  }
  static boolean cancelled() {
    MU.lock();
    try { return line().cancelled; } finally { MU.unlock(); }
  }

  // —— 一次只让一个做：按名字。别人在里面＝排队（先来先进）；自己已经在里面＝出错（不然会自己等自己）——
  private static final class Gate {
    Line owner;
    final ArrayList<Line> queue = new ArrayList<>();
  }
  private static final HashMap<String, Gate> GATES = new HashMap<>();
  static String lockEnter(String name) {
    Line me = line();
    Gate g;
    MU.lock();
    try {
      g = GATES.computeIfAbsent(name, k -> new Gate());
      if (g.owner == me) Lc.fail("「" + name + "」已经在“一次只让一个做”里面了，不能在里面再进一次");
      g.queue.add(me);
    } finally {
      MU.unlock();
    }
    block(() -> {
      if (g.owner != null || g.queue.get(0) != me) return false;
      g.owner = me;
      g.queue.remove(0);
      return true;
    }, null, () -> {
      g.queue.remove(me);
      WAKE.signalAll();
    });
    return name;
  }
  static void lockLeave(String name) {
    Line me = line();
    MU.lock();
    try {
      Gate g = GATES.get(name);
      if (g != null && g.owner == me) {
        g.owner = null;
        WAKE.signalAll();
      }
    } finally {
      MU.unlock();
    }
  }
}
''';
