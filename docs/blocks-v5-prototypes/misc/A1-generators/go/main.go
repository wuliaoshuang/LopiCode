package main
import ("fmt";"strings")
type Seq func(yield func(any) bool)
func nat(yield func(any) bool) { for i := 1; ; i++ { if !yield(i) { return } } }
func Map(s Seq, f func(any) any) Seq { return func(y func(any) bool) { s(func(v any) bool { return y(f(v)) }) } }
func Filter(s Seq, f func(any) bool) Seq { return func(y func(any) bool) { s(func(v any) bool { if f(v) { return y(v) }; return true }) } }
func Take(s Seq, n int) Seq { return func(y func(any) bool) { k := 0; if n <= 0 { return }; s(func(v any) bool { k++; if !y(v) { return false }; return k < n }) } }
func firstOver(s Seq, limit int) any { for v := range s { if v.(int) > limit { return v } }; return nil } // Go 新版：原生 range，提前返回编译器代劳
func main() {
  out := []string{}
  for v := range Take(Filter(Map(nat, func(x any) any { return x.(int) * x.(int) }), func(x any) bool { return x.(int)%2 == 1 }), 4) { out = append(out, fmt.Sprint(v)) }
  fmt.Println(strings.Join(out, ","), firstOver(Map(nat, func(x any) any { return x.(int) * 3 }), 10))
}
