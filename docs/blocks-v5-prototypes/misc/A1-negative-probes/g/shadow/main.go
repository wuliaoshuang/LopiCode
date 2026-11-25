package main
import "fmt"
func main(){ x := 1; { x := 2; _ = x }; fmt.Println(x) }
