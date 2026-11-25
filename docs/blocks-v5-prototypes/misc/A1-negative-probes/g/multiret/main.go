package main
func f() (int, string) { return 1, "a" }
func main(){ a, b := f(); _, _ = a, b }
