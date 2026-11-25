import java.util.*;
public class StrSwitch { static int g(String s){ return switch (s) { case "a", "b" -> 1; default -> 2; }; } }
