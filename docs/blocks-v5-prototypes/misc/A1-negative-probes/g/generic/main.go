package main
func M[T any](a []T) T { return a[0] }
func main(){ _ = M([]int{1}) }
