// p4_tx —— 事务：Commit / Rollback、事务绑定单条连接、忘记 Rollback 的后果。
package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

func count(db *sql.DB) int {
	var n int
	_ = db.QueryRow(`SELECT COUNT(*) FROM accounts`).Scan(&n)
	return n
}

func main() {
	ctx := context.Background()
	dir, _ := os.MkdirTemp("", "l12tx")
	defer os.RemoveAll(dir)
	db, err := sql.Open("sqlite", filepath.Join(dir, "bank.db"))
	if err != nil {
		panic(err)
	}
	defer db.Close()

	if _, err := db.Exec(`CREATE TABLE accounts(id INTEGER PRIMARY KEY, name TEXT, balance INTEGER)`); err != nil {
		panic(err)
	}
	if _, err := db.Exec(`INSERT INTO accounts(name, balance) VALUES('小谷', 1000), ('小林', 500)`); err != nil {
		panic(err)
	}
	fmt.Printf("初始：小谷=1000 小林=500，共 %d 行\n\n", count(db))

	// ---- 1) Rollback ----
	fmt.Println("1) 转账 100：BeginTx → UPDATE → Rollback")
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		panic(err)
	}
	if _, err := tx.Exec(`UPDATE accounts SET balance = balance - 100 WHERE name = '小谷'`); err != nil {
		fmt.Println("   update err:", err)
	}
	if _, err := tx.Exec(`UPDATE accounts SET balance = balance + 100 WHERE name = '小林'`); err != nil {
		fmt.Println("   update err:", err)
	}
	var b1, b2 int
	_ = tx.QueryRow(`SELECT balance FROM accounts WHERE name='小谷'`).Scan(&b1)
	_ = tx.QueryRow(`SELECT balance FROM accounts WHERE name='小林'`).Scan(&b2)
	fmt.Printf("   事务内看：小谷=%d 小林=%d（事务里读到的是自己的未提交改动）\n", b1, b2)
	if err := tx.Rollback(); err != nil {
		fmt.Println("   rollback err:", err)
	}
	_ = db.QueryRow(`SELECT balance FROM accounts WHERE name='小谷'`).Scan(&b1)
	_ = db.QueryRow(`SELECT balance FROM accounts WHERE name='小林'`).Scan(&b2)
	fmt.Printf("   回滚后看：小谷=%d 小林=%d ← 回到原值\n\n", b1, b2)

	// ---- 2) Commit ----
	fmt.Println("2) 同样的转账，这次 Commit")
	tx2, _ := db.BeginTx(ctx, nil)
	_, _ = tx2.Exec(`UPDATE accounts SET balance = balance - 100 WHERE name = '小谷'`)
	_, _ = tx2.Exec(`UPDATE accounts SET balance = balance + 100 WHERE name = '小林'`)
	if err := tx2.Commit(); err != nil {
		fmt.Println("   commit err:", err)
	}
	_ = db.QueryRow(`SELECT balance FROM accounts WHERE name='小谷'`).Scan(&b1)
	_ = db.QueryRow(`SELECT balance FROM accounts WHERE name='小林'`).Scan(&b2)
	fmt.Printf("   提交后看：小谷=%d 小林=%d ← 生效了\n\n", b1, b2)

	// ---- 3) 事务结束后再提交 / 回滚 → ErrTxDone ----
	fmt.Println("3) defer tx.Rollback() 的经典写法：Commit 之后 Rollback 会怎样")
	err = tx2.Rollback()
	fmt.Printf("   Commit 之后再 Rollback → err = %v\n", err)
	fmt.Printf("   errors.Is(err, sql.ErrTxDone) = %v\n", errors.Is(err, sql.ErrTxDone))
	fmt.Println("   （所以 `defer tx.Rollback()` 是安全的：成功提交后的 Rollback 只是白跑一次）")
	fmt.Println()

	// ---- 4) 事务绑定单条连接 ----
	fmt.Println("4) 事务绑定一条连接：最大连接数 4，事务开着时 InUse 恒为 1")
	db.SetMaxOpenConns(4)
	tx3, _ := db.BeginTx(ctx, nil)
	fmt.Printf("   事务内：Stats().Open=%d InUse=%d Idle=%d\n",
		db.Stats().OpenConnections, db.Stats().InUse, db.Stats().Idle)
	var x int
	go func() { _ = db.QueryRow(`SELECT 1`).Scan(&x) }() // 事务外并发一条
	rs, _ := tx3.Query(`SELECT 1`)
	rs.Close()
	time.Sleep(80 * time.Millisecond)
	fmt.Printf("   事务内又查一次：Stats().Open=%d InUse=%d Idle=%d\n",
		db.Stats().OpenConnections, db.Stats().InUse, db.Stats().Idle)
	_ = tx3.Rollback()
	fmt.Println()

	// ---- 5) 忘记 Rollback：连接被事务占死 ----
	fmt.Println("5) 忘记 Rollback：把 MaxOpenConns 降到 1，看第二次 BeginTx")
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	txA, _ := db.BeginTx(ctx, nil)
	_, _ = txA.Exec(`UPDATE accounts SET balance = balance + 1 WHERE name='小谷'`)
	ctxT, cancel := context.WithTimeout(ctx, 200*time.Millisecond)
	defer cancel()
	_, errB := db.BeginTx(ctxT, nil)
	fmt.Printf("   漏掉的 tx 还占着唯一连接时，第二次 BeginTx → err = %v\n", errB)
	fmt.Printf("   Stats(): Open=%d InUse=%d WaitCount=%d\n",
		db.Stats().OpenConnections, db.Stats().InUse, db.Stats().WaitCount)
	_ = txA.Rollback()
	// 归还之后再试一次
	txC, errC := db.BeginTx(ctx, nil)
	fmt.Printf("   txA.Rollback() 之后，再 BeginTx → err = %v\n", errC)
	if errC == nil {
		_ = txC.Rollback()
	}
	fmt.Println()

	// ---- 6) 事务内复用 Stmt ----
	fmt.Println("6) 事务内 PrepareContext + 多次 Exec")
	tx4, _ := db.BeginTx(ctx, nil)
	st, err := tx4.PrepareContext(ctx, `INSERT INTO accounts(name, balance) VALUES(?, ?)`)
	fmt.Printf("   Prepare → err=%v\n", err)
	for i := 1; i <= 3; i++ {
		if _, err := st.ExecContext(ctx, fmt.Sprintf("批量%d", i), i*10); err != nil {
			fmt.Println("   exec err:", err)
		}
	}
	_ = st.Close()
	_ = tx4.Commit()
	fmt.Printf("   提交后共 %d 行\n", count(db))

	// ---- 7) 事务内某条语句出错，事务本身不会自动回滚 ----
	fmt.Println()
	fmt.Println("7) 事务里某条语句报错后，事务仍然“活着”，必须显式 Rollback")
	tx5, _ := db.BeginTx(ctx, nil)
	_, err2 := tx5.Exec(`INSERT INTO 不存在的表(name) VALUES('x')`)
	fmt.Printf("   事务内一条语句报错 → err = %v\n", err2)
	_, _ = tx5.Exec(`INSERT INTO accounts(name, balance) VALUES('出错后仍可写', 7)`)
	var n5 int
	_ = tx5.QueryRow(`SELECT COUNT(*) FROM accounts`).Scan(&n5)
	fmt.Printf("   报错之后事务里还能继续写、还能读到 %d 行 → 说明事务没被自动回滚\n", n5)
	_ = tx5.Rollback()
	fmt.Printf("   显式 Rollback 之后共 %d 行（那一行没进去）\n", count(db))
}
