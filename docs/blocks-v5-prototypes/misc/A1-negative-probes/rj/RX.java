import java.util.regex.*;
public class RX { public static void main(String[] a){ Matcher m = Pattern.compile("(a|ab)(c|bcd)").matcher("abcd"); m.find();
 System.out.println("JAVA " + Pattern.compile("a$").matcher("a\n").find() + " " + Pattern.compile("a\\z").matcher("a\n").find() + " " + "😀".matches("^.$") + " " + Pattern.compile("\\d").matcher("３").find() + " " + Pattern.compile("\\w").matcher("中").find() + " " + "aXbxc".split("(?i)x").length + " " + m.group(0)); } }
