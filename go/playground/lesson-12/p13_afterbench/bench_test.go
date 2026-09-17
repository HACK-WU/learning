package afterbench

import (
	"testing"
	"time"
)

var sink chan time.Time

// A：每次迭代新建一个「超时保护」用的 timer，然后被另一个分支先选中
func BenchmarkAfterInLoop(b *testing.B) {
	ready := make(chan struct{}, 1)
	for i := 0; i < b.N; i++ {
		ready <- struct{}{}
		select {
		case <-ready:
		case <-time.After(time.Hour):
		}
	}
}

// B：复用同一个 Timer，用 Reset 改期限
func BenchmarkNewTimerReuse(b *testing.B) {
	ready := make(chan struct{}, 1)
	t := time.NewTimer(time.Hour)
	defer t.Stop()
	for i := 0; i < b.N; i++ {
		ready <- struct{}{}
		if !t.Stop() {
			select {
			case <-t.C:
			default:
			}
		}
		t.Reset(time.Hour)
		select {
		case <-ready:
		case <-t.C:
		}
	}
}

// C：time.After 但期限很短、真的会触发（对照：真触发的成本）
func BenchmarkAfterFired(b *testing.B) {
	for i := 0; i < b.N; i++ {
		<-time.After(time.Microsecond)
	}
}

// D：NewTimer + Reset，期限很短、真的会触发
func BenchmarkNewTimerFired(b *testing.B) {
	t := time.NewTimer(time.Microsecond)
	defer t.Stop()
	for i := 0; i < b.N; i++ {
		if !t.Stop() {
			select {
			case <-t.C:
			default:
			}
		}
		t.Reset(time.Microsecond)
		<-t.C
	}
}
