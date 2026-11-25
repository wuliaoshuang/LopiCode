import java.util.*; import java.time.*; import java.time.format.*; import java.math.*;
public class R { public static void main(String[] a){
 System.out.println(new HashMap<>(Map.of("b",1,"a",2)).keySet() + " " + new LinkedHashMap<>(){{put("b",1);put("a",2);}}.keySet() + " " + new TreeMap<>(Map.of("b",1,"a",2)).keySet());
 List<String> p = new ArrayList<>(List.of("b","a","B","10","9")); Collections.sort(p); System.out.println(p);
 System.out.println(List.of(1,2).equals(Arrays.asList(1,2)) + " " + (new int[]{1}).equals(new int[]{1}) + " " + Arrays.equals(new int[]{1}, new int[]{1}) + " " + Set.of(1,2).equals(Set.of(2,1)));
 System.out.println(Instant.ofEpochSecond(0) + " " + Duration.ofMinutes(90) + " " + LocalDate.of(2026,1,31).plusMonths(1) + " " + ZonedDateTime.of(2026,11,25,0,0,0,0,ZoneId.of("Asia/Shanghai")).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME));
 System.out.println((-7>>1) + " " + (~5) + " " + (-7>>>28) + " " + Long.MAX_VALUE + " " + (long)(1e30) + " " + (int)Double.NaN + " " + (int)-3.7 + " " + Integer.toBinaryString(25) + " " + (byte)200 + " " + (char)('a'+1) + " " + 5/2.0 + " " + (float)0.1 + " " + 1e6 + " " + 1e7+ " " + 0.001 + " " + 0.0001);
 System.out.println(String.format("%.2f %s", 1.005, 2.5) + " " + new BigDecimal("1.005").setScale(2, RoundingMode.HALF_UP) + " " + new BigDecimal(1.005).setScale(2, RoundingMode.HALF_UP)+ " " + new BigDecimal("0.1").add(new BigDecimal("0.2")) + " " + BigInteger.TWO.pow(100) + " " + new BigDecimal("1.0").equals(new BigDecimal("1.00")));
 try { Integer.parseInt("12px"); } catch (NumberFormatException e) { System.out.println("NumberFormatException"); }
 try { List.of(1).get(5); } catch (IndexOutOfBoundsException e) { System.out.println("IOOBE; map miss=" + new HashMap<String,Integer>().get("k")); }
 String s = null; System.out.println("null+str=" + s + 1 + " " + Objects.requireNonNullElse(s, "d") + " " + Optional.ofNullable(s).map(String::length).orElse(-1));
 System.out.println("a1b22".replaceAll("(?<d>\\d+)", "<${d}>") + " " + "a.a".replace(".", "-") + " " + "  x ".strip() + " " + "ab".repeat(2) + " " + String.join(",", List.of("a","b")) + " " + "é".length() + " " + "a,b,,".split(",").length);
 int[] arr = {3,1,2}; int[] cp = Arrays.copyOfRange(arr, 1, 3); System.out.println(cp.length + " " + List.of(1,2,3).subList(1,3) + " " + List.of(3,1,2).stream().map(x -> x * 2).filter(x -> x > 2).sorted().toList());
 System.out.println(Fall.g(1) + " " + Fall.g(2) + " " + Fall.g(3));
}}
