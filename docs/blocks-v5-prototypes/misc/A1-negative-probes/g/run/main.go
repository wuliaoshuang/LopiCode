package main
import ("fmt";"sort";"strings";"time";"math";"strconv";"math/big";"unicode/utf8")
func main(){
 m := map[string]int{"b":1,"a":2,"c":3}; ks := ""; for k := range m { ks += k }; fmt.Println("map order varies:", len(ks))
 s := []int{1,2,3,4}; fmt.Println(s[1:3], len(s[:0]), cap(s[1:]))
 a := [2]int{1,2}; b := a; b[0]=9; fmt.Println("array is value:", a, b, a == [2]int{1,2})
 sl := s; sl[0]=9; fmt.Println("slice shares:", s[0])
 p := []string{"b","a","B","10","9"}; sort.Strings(p); fmt.Println(p)
 fmt.Println(strings.ToUpper("ß"), utf8.RuneCountInString("é"), "abc"[1], string(rune(0x1F600)), strings.Repeat("a",3), strings.Fields(" a  b "), strings.Title("x"))
 fmt.Println(time.Unix(0,0).UTC().Format(time.RFC3339), time.Duration(90)*time.Minute, time.Date(2026,1,31,0,0,0,0,time.UTC).AddDate(0,1,0).Format("2006-01-02"))
 fmt.Println(math.MaxInt64, -7>>1, 1<<3, 7&^5, math.Trunc(-3.5), math.Floor(-3.5), strconv.FormatFloat(0.1+0.2+0*float64(len(s)),'g',-1,64), strconv.Itoa(25), strconv.FormatInt(25,2))
 x := 0.1; y := 0.2; fmt.Println(x+y, float64(1e21), 1e6, float64(123456789), 1e20, float32(0.1), 100.0, fmt.Sprintf("%.2f %v %g", 1.005, 2.5, 1e-7))
 n, err := strconv.Atoi("12px"); fmt.Println(n, err != nil)
 bi := new(big.Int).Exp(big.NewInt(2), big.NewInt(100), nil); fmt.Println(bi)
 var i8 int8 = 127; i8++; fmt.Println(i8, i8-i8)
 var e interface{} = 1; _, ok := e.(string); fmt.Println(ok, e == 1, any(nil) == nil)
 defer fmt.Println("defer1"); defer fmt.Println("defer2 (LIFO)")
 type P struct{X int}; fmt.Println(P{1} == P{1}, &P{1} == &P{1})
}
