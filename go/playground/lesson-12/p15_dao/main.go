// package main —— 用 modernc.org/sqlite（纯 Go、无 CGO）跑一个真实的 mini DAO
package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

// ---------- §1 池子配置：四个旋钮全部显式设 ----------
func newDB(ctx context.Context, dsn string) (*sql.DB, error) {
	// Open 只是建池子，不连接
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}

	db.SetMaxOpenConns(10)                  // 0 = 不限 → 必须显式设
	db.SetMaxIdleConns(10)                  // 默认只有 2；先设 MaxOpen 再设它
	db.SetConnMaxLifetime(30 * time.Minute) // 别超过后端 LB 的空闲超时
	db.SetConnMaxIdleTime(5 * time.Minute)

	// Open 不连接，这里显式验证一次，早失败
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("Ping: %w", err)
	}
	return db, nil
}

// ---------- §2 建表 ----------
func initSchema(ctx context.Context, db *sql.DB) error {
	ddl := `CREATE TABLE orders (
		id      INTEGER PRIMARY KEY AUTOINCREMENT,
		sku     TEXT    NOT NULL,
		qty     INTEGER NOT NULL,
		amount  REAL,
		status  TEXT    NOT NULL DEFAULT 'pending'
	)`
	if _, err := db.ExecContext(ctx, ddl); err != nil {
		return fmt.Errorf("create table: %w", err)
	}
	return nil
}

// ---------- §3 参数化写入：占位符 ? 而不是拼接 ----------
func insertOrder(ctx context.Context, db *sql.DB, sku string, qty int, amount *float64) (int64, error) {
	res, err := db.ExecContext(ctx,
		`INSERT INTO orders (sku, qty, amount) VALUES (?, ?, ?)`,
		sku, qty, amount)
	if err != nil {
		return 0, fmt.Errorf("insert: %w", err)
	}
	return res.LastInsertId()
}

// ---------- §4 QueryRow + ErrNoRows：先判 ErrNoRows ----------
type Order struct {
	ID     int64
	SKU    string
	Qty    int
	Amount sql.NullFloat64
}

func getOrder(ctx context.Context, db *sql.DB, id int64) (*Order, error) {
	var o Order
	err := db.QueryRowContext(ctx,
		`SELECT id, sku, qty, amount FROM orders WHERE id = ?`, id).
		Scan(&o.ID, &o.SKU, &o.Qty, &o.Amount)

	switch {
	case errors.Is(err, sql.ErrNoRows):
		return nil, nil // 业务语义：不存在
	case err != nil:
		return nil, fmt.Errorf("query order %d: %w", id, err)
	}
	return &o, nil
}

// ---------- §5 Query + rows ----------
func listOrders(ctx context.Context, db *sql.DB, sku string) ([]Order, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT id, sku, qty, amount FROM orders WHERE sku = ? ORDER BY id`, sku)
	if err != nil {
		return nil, fmt.Errorf("query list: %w", err)
	}
	defer rows.Close() // ← 必须在遍历之前注册

	var out []Order
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.SKU, &o.Qty, &o.Amount); err != nil {
			return nil, fmt.Errorf("scan: %w", err)
		}
		out = append(out, o)
	}
	// ★ 循环结束后必须查 Err
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}
	return out, nil
}

// ---------- §6 事务：BeginTx + defer Rollback + 显式 Commit ----------
func transfer(ctx context.Context, db *sql.DB, fromID, toID int64, delta int, fail bool) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer tx.Rollback() // 幂等；成功 Commit 后只返回 sql.ErrTxDone

	if _, err := tx.ExecContext(ctx, `UPDATE orders SET qty = qty - ? WHERE id = ?`, delta, fromID); err != nil {
		return fmt.Errorf("debit: %w", err)
	}
	if fail {
		return errors.New("业务校验失败，事务作废")
	}
	if _, err := tx.ExecContext(ctx, `UPDATE orders SET qty = qty + ? WHERE id = ?`, delta, toID); err != nil {
		return fmt.Errorf("credit: %w", err)
	}
	return tx.Commit()
}

// ---------- main ----------
func main() {
	ctx := context.Background()

	dir, err := os.MkdirTemp("", "l12dao")
	if err != nil {
		log.Fatal(err)
	}
	defer os.RemoveAll(dir)

	db, err := newDB(ctx, "file:"+filepath.Join(dir, "demo.db"))
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close() // 进程退出时关一次即可；正常服务里"极少需要 Close"

	if err := initSchema(ctx, db); err != nil {
		log.Fatal(err)
	}

	id1, err := insertOrder(ctx, db, "A-100", 2, ptr(19.90))
	if err != nil {
		log.Fatal(err)
	}
	_, _ = insertOrder(ctx, db, "B-200", 1, ptr(99.00))
	_, _ = insertOrder(ctx, db, "A-100", 5, ptr(49.75))
	fmt.Printf("① 插入 3 单，第一条 id=%d\n", id1)

	o, err := getOrder(ctx, db, id1)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("② 查 id=%d → sku=%s qty=%d amount=%.2f(valid=%v)\n", id1, o.SKU, o.Qty, o.Amount.Float64, o.Amount.Valid)

	missing, err := getOrder(ctx, db, 99999)
	fmt.Printf("③ 查 id=99999 → 订单=%v err=%v（业务分支，不是错误）\n", missing, err)

	list, err := listOrders(ctx, db, "A-100")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("④ sku=A-100 共 %d 单\n", len(list))

	// 事务：先失败一次（看回滚），再成功一次（看提交）
	before, _ := getOrder(ctx, db, 1)
	if err := transfer(ctx, db, 1, 2, 100, true); err != nil {
		fmt.Printf("⑤ 事务（预期失败）→ %v\n", err)
	}
	after, _ := getOrder(ctx, db, 1)
	fmt.Printf("   回滚验证：id=1 的 qty 事务前=%d 事务后=%d（有变化吗：%v）\n",
		before.Qty, after.Qty, before.Qty != after.Qty)

	if err := transfer(ctx, db, 1, 2, 1, false); err != nil {
		log.Fatal(err)
	}
	committed, _ := getOrder(ctx, db, 1)
	fmt.Printf("⑥ 事务（预期成功）→ 已提交；id=1 的 qty 由 %d 变 %d\n", after.Qty, committed.Qty)

	// 幂等性检查：对已提交的事务再 Rollback
	tx, _ := db.BeginTx(ctx, nil)
	_ = tx.Commit()
	err = tx.Rollback()
	fmt.Printf("⑦ 对已提交的事务再 Rollback → err=%v（errors.Is ErrTxDone=%v）\n",
		err, errors.Is(err, sql.ErrTxDone))

	// 注入对照：同一个输入，参数化 vs 拼接
	_, _ = db.ExecContext(ctx, `INSERT INTO orders (sku, qty, amount) VALUES ('B-200', 1, 10)`)
	evil := "' OR 1=1 --"
	var nParam int
	_ = db.QueryRowContext(ctx, `SELECT COUNT(*) FROM orders WHERE sku = ?`, evil).Scan(&nParam)
	fmt.Printf("⑧ 参数化 WHERE sku=? 传 %q → 命中 %d 行\n", evil, nParam)

	// 观测：池子的四个数字
	s := db.Stats()
	fmt.Printf("⑨ Stats(): Open=%d InUse=%d Idle=%d WaitCount=%d WaitDuration=%v\n",
		s.OpenConnections, s.InUse, s.Idle, s.WaitCount, s.WaitDuration)
}

func ptr[T any](v T) *T { return &v }
