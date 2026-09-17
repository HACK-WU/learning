// p6_rows_memory —— database/sql 两个最高频的坑：
//  1. Rows 不 Close，连接被一直占住（池被抽干）
//  2. ":memory:" 每条连接一个独立的库
package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"time"

	_ "modernc.org/sqlite"
)

func main() {
	dir, _ := os.MkdirTemp("", "l12rows")
	defer os.RemoveAll(dir)

	// ---------------------------------------------------------------- 1
	fmt.Println("1) 忘了 rows.Close()：把连接池抽干")
	db, err := sql.Open("sqlite", filepath.Join(dir, "a.db"))
	if err != nil {
		panic(err)
	}
	db.SetMaxOpenConns(2)
	db.SetMaxIdleConns(2)
	if _, err := db.Exec(`CREATE TABLE t(id INTEGER PRIMARY KEY)`); err != nil {
		panic(err)
	}
	for i := 0; i < 5; i++ {
		_, _ = db.Exec(`INSERT INTO t(id) VALUES(?)`, i)
	}

	// 故意漏掉 Close：只 Next 一次就丢下
	for i := 0; i < 2; i++ {
		rows, err := db.Query(`SELECT id FROM t`)
		if err != nil {
			fmt.Println("   Query err:", err)
			break
		}
		rows.Next() // 只读一行，然后什么都不做
		fmt.Printf("   第 %d 次 Query 之后（没 Close）：Open=%d InUse=%d Idle=%d\n",
			i+1, db.Stats().OpenConnections, db.Stats().InUse, db.Stats().Idle)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	var n int
	err = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM t`).Scan(&n)
	fmt.Printf("   池里两条连接都被占住后再查 → err = %v\n", err)
	fmt.Printf("   Stats(): Open=%d InUse=%d WaitCount=%d\n",
		db.Stats().OpenConnections, db.Stats().InUse, db.Stats().WaitCount)
	fmt.Println()

	// 正确写法：defer rows.Close()
	db2, _ := sql.Open("sqlite", filepath.Join(dir, "b.db"))
	defer db2.Close()
	db2.SetMaxOpenConns(2)
	_, _ = db2.Exec(`CREATE TABLE t(id INTEGER PRIMARY KEY)`)
	for i := 0; i < 5; i++ {
		_, _ = db2.Exec(`INSERT INTO t(id) VALUES(?)`, i)
	}
	for i := 0; i < 2; i++ {
		rows, err := db2.Query(`SELECT id FROM t`)
		if err != nil {
			fmt.Println("   Query err:", err)
			break
		}
		rows.Next()
		rows.Close() // 用完就还
	}
	fmt.Printf("   每次都 Close 之后：Open=%d InUse=%d Idle=%d\n",
		db2.Stats().OpenConnections, db2.Stats().InUse, db2.Stats().Idle)
	var n2 int
	err = db2.QueryRow(`SELECT COUNT(*) FROM t`).Scan(&n2)
	fmt.Printf("   再查一次 → 正常返回 count=%d err=%v\n", n2, err)
	fmt.Println()

	// 遍历到自然结束也会自动归还
	db2.SetMaxOpenConns(1)
	rows, _ := db2.Query(`SELECT id FROM t`)
	for rows.Next() {
	}
	_ = rows.Err()
	fmt.Printf("   用 for rows.Next() 遍历到结束（未显式 Close）：InUse=%d（已自动归还）\n",
		db2.Stats().InUse)
	rows.Close()
	fmt.Println()

	// ---------------------------------------------------------------- 2
	fmt.Println("2) \":memory:\" 是「每条连接一个独立的库」")
	mem, _ := sql.Open("sqlite", ":memory:")
	defer mem.Close()
	mem.SetMaxOpenConns(1) // 先用一条连接把表和数据建好
	if _, err := mem.Exec(`CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)`); err != nil {
		fmt.Println("   建表 err:", err)
	}
	_, _ = mem.Exec(`INSERT INTO users(name) VALUES('小谷')`)
	var c int
	err = mem.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&c)
	fmt.Printf("   在唯一那条连接上查：COUNT(*) = %d，err=%v\n", c, err)

	// 把上限放开，并发 4 条 → 池会新建连接，新连接是空库
	mem.SetMaxOpenConns(4)
	var (
		wg      sync.WaitGroup
		okCnt   atomic.Int64
		errCnt  atomic.Int64
		sampleE atomic.Value
	)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var n int
			if err := mem.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&n); err != nil {
				errCnt.Add(1)
				sampleE.Store(err.Error())
				return
			}
			okCnt.Add(1)
		}()
	}
	wg.Wait()
	fmt.Printf("   放开上限到 4 后并发 4 次：成功 %d 次，失败 %d 次\n", okCnt.Load(), errCnt.Load())
	if v := sampleE.Load(); v != nil {
		fmt.Printf("   失败的原文 = %v\n", v)
	}
	fmt.Println("   ↑ 同一个 sql.DB、同一份 SQL，落在不同连接上就是不同的库")
	fmt.Println()

	fmt.Println("3) 想让内存库跨连接共享：改成 file::memory:?cache=shared")
	shared, _ := sql.Open("sqlite", "file::memory:?cache=shared")
	defer shared.Close()
	shared.SetMaxOpenConns(1)
	_, _ = shared.Exec(`CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)`)
	_, _ = shared.Exec(`INSERT INTO users(name) VALUES('小谷')`)
	shared.SetMaxOpenConns(4)
	okCnt.Store(0)
	errCnt.Store(0)
	var wg2 sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg2.Add(1)
		go func() {
			defer wg2.Done()
			var n int
			if err := shared.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&n); err != nil {
				errCnt.Add(1)
				return
			}
			okCnt.Add(1)
		}()
	}
	wg2.Wait()
	fmt.Printf("   并发 4 次：成功 %d 次，失败 %d 次（共享缓存后新连接也能看到同一份数据）\n",
		okCnt.Load(), errCnt.Load())
}
