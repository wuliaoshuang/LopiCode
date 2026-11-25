import java.util.*;
public class CaptureMut { static Runnable g(){ int x = 0; return () -> { x++; }; } }
