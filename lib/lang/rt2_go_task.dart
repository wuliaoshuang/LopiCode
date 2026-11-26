/// 规矩版本 2 的小库·Go·“要等的事”那一块（`lc/task.go`，和 lc.go 同一个包）：这条线、等一会儿、开始做、等、
/// 等最多 / 等全部 / 等最先的一个、取消、一次只让一个做。规矩见 docs/blocks-v5-parts/B-gen-notes.md 第 16 节。只用 Go 自带的包。
library;

const String kRt2GoTask = r'''
// LopiCode 积木的小库（Go，严格规矩）·要等的事。由 LopiCode 生成，别手改。
package lc

import (
	"sync"
	"time"
)

// Line：一件事（主程序、一次“开始做”、一个请求）。Go 里没有现成的办法知道“我是哪件事”，
// 所以生成的每个函数第一个参数都是它，一路传下去：取消、“一次只让一个做”、格子“正在改”都靠它认。
type Line struct {
	cancelled bool // 拿着 taskMu 才读写
}

// 所有“要等”的地方共用一把锁和一个“有事发生了”的信号：有一件事做完、被取消、有人从“一次只让一个做”里出来，
// 就把信号关掉换个新的，在等的都醒过来各自再看一眼。
var taskMu sync.Mutex
var taskWake = make(chan struct{})

func wakeAll() { // 拿着 taskMu 调
	close(taskWake)
	taskWake = make(chan struct{})
}

const cancelMsg = "这件事被取消了"

// lineCheck：到了要等的地方先看一眼，这条线被取消了就抛“取消了”。
func lineCheck(lt *Line) {
	taskMu.Lock()
	c := lt.cancelled
	taskMu.Unlock()
	if c {
		Fail(cancelMsg)
	}
}

// block：等到 ready 说行（它是拿着 taskMu 被调的）。这条线被取消＝先做 quit（有的话）再抛“取消了”；过了 deadline＝交回 false。
func block(lt *Line, deadline *time.Time, quit func(), ready func() bool) bool {
	taskMu.Lock()
	for {
		if lt.cancelled {
			if quit != nil {
				quit()
			}
			taskMu.Unlock()
			Fail(cancelMsg)
		}
		if ready() {
			taskMu.Unlock()
			return true
		}
		wake := taskWake
		var left time.Duration
		if deadline != nil {
			left = time.Until(*deadline)
			if left <= 0 {
				taskMu.Unlock()
				return false
			}
		}
		taskMu.Unlock()
		if deadline == nil {
			<-wake
		} else {
			timer := time.NewTimer(left)
			select {
			case <-wake:
				timer.Stop()
			case <-timer.C:
			}
		}
		taskMu.Lock()
	}
}

func after(ms int64) *time.Time {
	if ms < 0 {
		ms = 0
	}
	t := time.Now().Add(time.Duration(ms) * time.Millisecond)
	return &t
}

func HostSleep(lt *Line, ms int64) {
	block(lt, after(ms), nil, func() bool { return false })
}

// Task：“开始做”的结果。出了错先记着，等它的时候再抛。
type Task[T any] struct {
	done bool // 拿着 taskMu 才读写
	val  T
	err  any
	line *Line
}

func Spawn[T any](lt *Line, f func(*Line) T) *Task[T] {
	t := &Task[T]{line: &Line{}}
	go func() {
		defer func() {
			e := recover()
			taskMu.Lock()
			t.err = e
			t.done = true
			wakeAll()
			taskMu.Unlock()
		}()
		t.val = f(t.line)
	}()
	return t
}

func (t *Task[T]) isDone() bool { return t.done }
func (t *Task[T]) get() T {
	if t.err != nil {
		panic(t.err)
	}
	return t.val
}

func Wait[T any](lt *Line, t *Task[T]) T {
	block(lt, nil, nil, t.isDone)
	return t.get()
}

// WaitMax：最多等 ms 毫秒；到时候还没做完＝“超时”错误（那件事自己接着做）。
func WaitMax[T any](lt *Line, t *Task[T], ms int64) T {
	if ms < 0 {
		ms = 0
	}
	if !block(lt, after(ms), nil, t.isDone) {
		Fail("等了 " + IntText(ms) + " 毫秒还没做完")
	}
	return t.get()
}

func cancelAll[T any](ts []*Task[T]) {
	for _, t := range ts {
		Cancel(t)
	}
}

// WaitAll：全做完才交回（结果按列表的顺序）。有一件出了错，或者等的人自己被取消了＝把还没做完的都取消，把错抛出去。
func WaitAll[T any](lt *Line, list *List[*Task[T]]) *List[T] {
	ts := list.Snap()
	var bad *Task[T]
	func() {
		defer func() {
			if e := recover(); e != nil {
				cancelAll(ts)
				panic(e)
			}
		}()
		block(lt, nil, nil, func() bool {
			all := true
			for _, t := range ts {
				if !t.done {
					all = false
				} else if t.err != nil {
					bad = t
					return true
				}
			}
			return all
		})
	}()
	if bad != nil {
		cancelAll(ts)
		panic(bad.err)
	}
	out := &List[T]{Items: make([]T, 0, len(ts))}
	for _, t := range ts {
		out.Items = append(out.Items, t.val)
	}
	return out
}

// WaitAny：谁先做完（成了或者出错）就用谁的；别的接着做。
func WaitAny[T any](lt *Line, list *List[*Task[T]]) T {
	ts := list.Snap()
	if len(ts) == 0 {
		Fail("“等最先的一个”的列表是空的")
	}
	var first *Task[T]
	block(lt, nil, nil, func() bool {
		for _, t := range ts {
			if t.done {
				first = t
				return true
			}
		}
		return false
	})
	return first.get()
}

// Cancel：给那件事做个记号，它下一次到要等的地方就抛“取消了”；已经做完的不管。
func Cancel[T any](t *Task[T]) {
	taskMu.Lock()
	if !t.done && !t.line.cancelled {
		t.line.cancelled = true
		wakeAll()
	}
	taskMu.Unlock()
}

func Cancelled(lt *Line) bool {
	taskMu.Lock()
	defer taskMu.Unlock()
	return lt.cancelled
}

// —— 一次只让一个做：按名字。别人在里面＝排队（先来先进）；自己已经在里面＝出错（不然会自己等自己）——
type gate struct {
	owner *Line
	queue []*Line
}

var gates = map[string]*gate{}

func LockEnter(lt *Line, name string) string {
	taskMu.Lock()
	g := gates[name]
	if g == nil {
		g = &gate{}
		gates[name] = g
	}
	if g.owner == lt {
		taskMu.Unlock()
		Fail("「" + name + "」已经在“一次只让一个做”里面了，不能在里面再进一次")
	}
	g.queue = append(g.queue, lt)
	taskMu.Unlock()
	leave := func() {
		for i, l := range g.queue {
			if l == lt {
				g.queue = append(g.queue[:i], g.queue[i+1:]...)
				break
			}
		}
		wakeAll()
	}
	block(lt, nil, leave, func() bool {
		if g.owner != nil || g.queue[0] != lt {
			return false
		}
		g.owner = lt
		g.queue = g.queue[1:]
		return true
	})
	return name
}

func LockLeave(lt *Line, name string) {
	taskMu.Lock()
	if g := gates[name]; g != nil && g.owner == lt {
		g.owner = nil
		wakeAll()
	}
	taskMu.Unlock()
}
''';
