// p1_pool —— 用「自写的假 driver」证明 sql.DB 是连接池，不是一条连接。
//
// 这个包不依赖任何真实数据库：我们自己实现 database/sql/driver 的几个接口，
// 在每个 Open / Close 上打点，于是「池」的行为第一次变得肉眼可见。
package main

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// ---------------------------------------------------------------- 记录器

var (
	mu       sync.Mutex
	events   []string
	openSeq  atomic.Int64 // 累计 Open 次数
	closeSeq atomic.Int64 // 累计 Close 次数
	live     atomic.Int64 // 当前存活连接数
	peak     atomic.Int64 // 存活峰值
)

func logf(format string, a ...any) {
	mu.Lock()
	defer mu.Unlock()
	events = append(events, fmt.Sprintf(format, a...))
}

func dump(title string) {
	mu.Lock()
	defer mu.Unlock()
	fmt.Printf("---- %s ----\n", title)
	for _, e := range events {
		fmt.Println(e)
	}
	fmt.Println()
	events = events[:0]
}

func reset() {
	openSeq.Store(0)
	closeSeq.Store(0)
	live.Store(0)
	peak.Store(0)
	mu.Lock()
	events = events[:0]
	mu.Unlock()
}

func bumpPeak(n int64) {
	for {
		p := peak.Load()
		if n <= p || peak.CompareAndSwap(p, n) {
			return
		}
	}
}

// ---------------------------------------------------------------- 假 driver

type fakeConn struct{ id int64 }

func (c *fakeConn) Prepare(query string) (driver.Stmt, error) {
	return &fakeStmt{conn: c, query: query}, nil
}

func (c *fakeConn) Close() error {
	n := live.Add(-1)
	closeSeq.Add(1)
	logf("    conn#%-2d CLOSE  （存活 %d）", c.id, n)
	return nil
}

func (c *fakeConn) Begin() (driver.Tx, error) { return &fakeTx{c: c}, nil }

type fakeTx struct{ c *fakeConn }

func (t *fakeTx) Commit() error   { logf("    conn#%-2d COMMIT", t.c.id); return nil }
func (t *fakeTx) Rollback() error { logf("    conn#%-2d ROLLBACK", t.c.id); return nil }

type fakeStmt struct {
	conn  *fakeConn
	query string
}

func (s *fakeStmt) Close() error  { return nil }
func (s *fakeStmt) NumInput() int { return -1 }

func (s *fakeStmt) Exec(args []driver.Value) (driver.Result, error) {
	logf("    conn#%-2d EXEC   %q", s.conn.id, s.query)
	return driver.RowsAffected(1), nil
}

func (s *fakeStmt) Query(args []driver.Value) (driver.Rows, error) {
	logf("    conn#%-2d QUERY  %q", s.conn.id, s.query)
	if strings.Contains(s.query, "slow") {
		time.Sleep(120 * time.Millisecond)
	}
	return &fakeRows{}, nil
}

type fakeRows struct{ done bool }

func (r *fakeRows) Columns() []string { return []string{"v"} }
func (r *fakeRows) Close() error      { return nil }
func (r *fakeRows) Next(dest []driver.Value) error {
	if r.done {
		return fmt.Errorf("EOF")
	}
	r.done = true
	dest[0] = "ok"
	return nil
}

type fakeDriver struct{}

func (fakeDriver) Open(dsn string) (driver.Conn, error) {
	id := openSeq.Add(1)
	n := live.Add(1)
	bumpPeak(n)
	logf("    conn#%-2d OPEN   （存活 %d） dsn=%s", id, n, dsn)
	return &fakeConn{id: id}, nil
}

func init() { sql.Register("fakedb", fakeDriver{}) }

// ---------------------------------------------------------------- 演示

func mustOpen(dsn string) *sql.DB {
	db, err := sql.Open("fakedb", dsn)
	if err != nil {
		panic(err)
	}
	return db
}

func queryN(db *sql.DB, n int) {
	for i := 0; i < n; i++ {
		var v string
		if err := db.QueryRow("SELECT v").Scan(&v); err != nil {
			fmt.Println("  query err:", err)
			return
		}
	}
}

func main() {
	ctx := context.Background()

	// ---- A：sql.Open 本身不建连接 ----
	reset()
	db := mustOpen("tcp(fake:1)/a")
	fmt.Printf("A) 刚 sql.Open 完：Open 次数 = %d（池是空的，一条连接都没建）\n", openSeq.Load())
	var v string
	_ = db.QueryRow("SELECT v").Scan(&v)
	fmt.Printf("   第一次真正查询之后：Open 次数 = %d\n", openSeq.Load())
	dump("A) Open 不连接，首次查询才连接")

	// ---- B：串行查询复用同一条连接 ----
	reset()
	queryN(db, 5)
	dump("B) 串行复用同一条连接")
	fmt.Printf("B) 串行 5 次查询 → Open 次数 = %d，Close 次数 = %d\n\n", openSeq.Load(), closeSeq.Load())

	// ---- C：SetMaxIdleConns(0) —— 每次都重开 ----
	reset()
	dbC := mustOpen("tcp(fake:1)/c")
	dbC.SetMaxIdleConns(0)
	queryN(dbC, 5)
	dump("C) 不保留空闲连接 = 每次重开")
	fmt.Printf("C) MaxIdleConns=0，串行 5 次查询 → Open 次数 = %d，Close 次数 = %d\n\n",
		openSeq.Load(), closeSeq.Load())
	_ = dbC.Close()

	// ---- D：默认 MaxIdleConns=2 ----
	reset()
	dbD := mustOpen("tcp(fake:1)/d")
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			var s string
			_ = dbD.QueryRow("SELECT slow").Scan(&s)
		}()
	}
	close(start)
	wg.Wait()
	time.Sleep(50 * time.Millisecond) // 让连接归还池中
	st := dbD.Stats()
	dump("D) 默认 MaxIdleConns=2 只留两条空闲")
	fmt.Printf("D) 默认配置，并发 6 次慢查询 → 峰值连接 %d，Open 合计 %d\n", peak.Load(), openSeq.Load())
	fmt.Printf("   Stats(): Open=%d Idle=%d InUse=%d   ← 6 条用完后只留 2 条\n\n",
		st.OpenConnections, st.Idle, st.InUse)
	_ = dbD.Close()

	// ---- E：SetMaxOpenConns(3) + 10 并发 ----
	reset()
	dbE := mustOpen("tcp(fake:1)/e")
	dbE.SetMaxOpenConns(3)
	dbE.SetMaxIdleConns(3)
	var wg2 sync.WaitGroup
	start2 := make(chan struct{})
	for i := 0; i < 10; i++ {
		wg2.Add(1)
		go func() {
			defer wg2.Done()
			<-start2
			var s string
			_ = dbE.QueryRow("SELECT slow").Scan(&s)
		}()
	}
	close(start2)
	wg2.Wait()
	stE := dbE.Stats()
	dump("E) 上限 3 把并发压成串行排队")
	fmt.Printf("E) MaxOpenConns=3，并发 10 次慢查询 → 存活峰值 = %d\n", peak.Load())
	fmt.Printf("   Stats(): Open=%d InUse=%d Idle=%d WaitCount=%d WaitDuration=%v\n\n",
		stE.OpenConnections, stE.InUse, stE.Idle, stE.WaitCount, stE.WaitDuration)
	_ = dbE.Close()

	// ---- F：并发超限时等待，超时返回失败 ----
	reset()
	dbF := mustOpen("tcp(fake:1)/f")
	dbF.SetMaxOpenConns(1)
	dbF.SetMaxIdleConns(1)
	done := make(chan struct{}, 2)
	go func() {
		var s string
		_ = dbF.QueryRow("SELECT slow").Scan(&s)
		done <- struct{}{}
	}()
	time.Sleep(20 * time.Millisecond) // 让第一条占住唯一连接
	ctxT, cancel := context.WithTimeout(ctx, 30*time.Millisecond)
	defer cancel()
	var s string
	err := dbF.QueryRowContext(ctxT, "SELECT v").Scan(&s)
	dump("F) 池满时 QueryContext 会等，ctx 超时就返回")
	fmt.Printf("F) MaxOpenConns=1，第二条等不到连接 → err = %v\n", err)
	fmt.Printf("   Stats(): WaitCount=%d WaitDuration=%v\n\n",
		dbF.Stats().WaitCount, dbF.Stats().WaitDuration)
	<-done
	_ = dbF.Close()

	// ---- G：SetConnMaxIdleTime —— 空闲超时后被回收 ----
	reset()
	dbG := mustOpen("tcp(fake:1)/g")
	dbG.SetConnMaxIdleTime(60 * time.Millisecond)
	var s2 string
	_ = dbG.QueryRow("SELECT v").Scan(&s2)
	fmt.Printf("G) MaxIdleTime=60ms，刚查完：Idle=%d\n", dbG.Stats().Idle)
	time.Sleep(1500 * time.Millisecond)
	fmt.Printf("   睡 1.5s 后：Idle=%d（清理协程把它关了）\n", dbG.Stats().Idle)
	fmt.Printf("   注意：源码里 connectionCleaner 有 const minInterval = time.Second，\n" +
		"   所以即使设 60ms，清理也最快 1 秒一轮。\n")
	dump("G) 空闲超时会回收连接（清理协程，最快每秒一轮）")
	_ = dbG.Close()

	_ = db.Close()
}
