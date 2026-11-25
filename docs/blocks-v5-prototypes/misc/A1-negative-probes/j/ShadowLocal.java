import java.util.*;
public class ShadowLocal { static void g(){ int x = 1; { int x = 2; } } }
