import java.util.*;
public class Spread { static void f(int... a) {} static void g(){ f(new int[]{1,2}); f(1,2); } }
