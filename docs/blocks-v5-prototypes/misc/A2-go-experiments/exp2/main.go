package main

import "fmt"

// “怎么出来的标记”
const (
	exitNormal = iota
	exitReturn
	exitBreak
	exitContinue
)

type lcError struct{ Msg string }

// try：跑 body，接住 panic；finally 一定执行。返回 body 怎么出来的 + 接到的错误
func try(body func() int, onError func(e *lcError) int, finally func()) (how int) {
	defer func() {
		if finally != nil {
			finally()
		}
	}()
	how = func() (h int) {
		defer func() {
			if r := recover(); r != nil {
				e, ok := r.(*lcError)
				if !ok {
					e = &lcError{fmt.Sprint(r)}
				}
				if onError != nil {
					h = onError(e)
				} else {
					h = exitNormal
				}
			}
		}()
		return body()
	}()
	return how
}

// 积木：函数 找(列表, 目标) { 对每个 x { 试着做 { 如果 x<0 抛出; 如果 x==0 跳过; 如果 x==99 跳出; 如果 x==目标 返回 "找到" } 出错了 { 打印; 如果 目标==-1 返回 "错误时返回" } 最后总要 { 打印 } } 返回 "没找到" }
func find(list []int, target int) string {
	var ret string
	for _, x := range list {
		how := try(func() int {
			if x < 0 {
				panic(&lcError{"负数"})
			}
			if x == 0 {
				return exitContinue
			}
			if x == 99 {
				return exitBreak
			}
			if x == target {
				ret = "找到"
				return exitReturn
			}
			fmt.Println("  看过", x)
			return exitNormal
		}, func(e *lcError) int {
			fmt.Println("  出错了:", e.Msg)
			if target == -1 {
				ret = "错误时返回"
				return exitReturn
			}
			return exitNormal
		}, func() { fmt.Println("  最后总要", x) })
		if how == exitReturn {
			return ret
		}
		if how == exitBreak {
			break
		}
		if how == exitContinue {
			continue
		}
		fmt.Println("  口后面的语句", x)
	}
	return "没找到"
}

func main() {
	fmt.Println(find([]int{1, 0, -5, 3, 4}, 3))
	fmt.Println(find([]int{1, 99, 3}, 3))
	fmt.Println(find([]int{1, -2, 3}, -1))
	// 错误处理块里再抛出：应穿出去，且 finally 仍执行
	func() {
		defer func() { fmt.Println("外层接到:", recover().(*lcError).Msg) }()
		try(func() int { panic(&lcError{"一号"}) }, func(e *lcError) int { panic(&lcError{"二号(原因:" + e.Msg + ")"}) }, func() { fmt.Println("  最后总要(重抛)") })
	}()
}
