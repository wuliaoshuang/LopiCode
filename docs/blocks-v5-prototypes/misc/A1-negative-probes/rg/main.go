package main
import ("fmt";"regexp")
func main(){ m := regexp.MustCompile
 fmt.Println("GO", m(`a$`).MatchString("a\n"), m(`^.$`).MatchString("😀"), m(`\d`).MatchString("３"), m(`\w`).MatchString("中"), len(m(`(?i)x`).Split("aXbxc", -1)), m(`(a|ab)(c|bcd)`).FindString("abcd"), m(`a*?`).FindString("aaa") == "", m(`(?<y>\d+)`).ReplaceAllString("a12", "<${y}>")) }
