import java.util.*;
public class Destruct { record P(int x, int y) {} static int g(Object o){ if (o instanceof P(int x, int y)) return x + y; return 0; } }
