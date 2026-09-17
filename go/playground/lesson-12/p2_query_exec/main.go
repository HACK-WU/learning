// p2_query_exec —— 真实数据库（modernc.org/sqlite，纯 Go 无 CGO）上的
// Query / Exec 分工、Scan、ErrNoRows、Rows 关闭。
package main

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite"
)

func must(err error, what string) {
	if err != nil {
		fmt.Printf("   [%s] err = %v\n", what, err)
	}
}

func main() {
	dir, _ := os.MkdirTemp("", "l12")
	defer os.RemoveAll(dir)
	dsn := filepath.Join(dir, "shop.db")

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		panic(err)
	}
	defer db.Close()

	// ---- 建表 + 写入：Exec（不返回行） ----
	res, err := db.Exec(`CREATE TABLE orders(
		id      INTEGER PRIMARY KEY AUTOINCREMENT,
		sku     TEXT    NOT NULL,
		qty     INTEGER NOT NULL,
		amount  REAL
	)`)
	must(err, "CREATE TABLE")
	fmt.Printf("1) CREATE TABLE → LastInsertId=%v RowsAffected=%v\n",
		func() any { v, _ := res.LastInsertId(); return v }(),
		func() any { v, _ := res.RowsAffected(); return v }())

	// Exec 带参数：参数化插入
	rows := []struct {
		sku    string
		qty    int
		amount float64
	}{
		{"A-100", 2, 19.90},
		{"B-200", 1, 99.00},
		{"A-100", 5, 49.75},
	}
	for _, r := range rows {
		res, err := db.Exec(`INSERT INTO orders(sku, qty, amount) VALUES(?, ?, ?)`, r.sku, r.qty, r.amount)
		must(err, "INSERT")
		id, _ := res.LastInsertId()
		n, _ := res.RowsAffected()
		fmt.Printf("   INSERT %-6s → id=%d RowsAffected=%d\n", r.sku, id, n)
	}

	// ---- 查询多行：Query + Next + Scan ----
	fmt.Println("2) Query 多行：")
	rs, err := db.Query(`SELECT id, sku, qty, amount FROM orders ORDER BY id`)
	if err != nil {
		panic(err)
	}
	defer rs.Close() // 铁律：Query 成功就要关
	for rs.Next() {
		var id, qty int
		var sku string
		var amount sql.NullFloat64 // amount 允许 NULL
		if err := rs.Scan(&id, &sku, &qty, &amount); err != nil {
			fmt.Println("   scan err:", err)
			continue
		}
		fmt.Printf("   id=%-2d sku=%-6s qty=%d amount=%v(valid=%v)\n",
			id, sku, qty, amount.Float64, amount.Valid)
	}
	// 遍历完必须再看 Err()，否则可能吞掉中途的错误
	if err := rs.Err(); err != nil {
		fmt.Println("   rows.Err:", err)
	}

	// ---- 单行：QueryRow 把错误推迟到 Scan ----
	fmt.Println("3) QueryRow：")
	var id int
	var sku string
	err = db.QueryRow(`SELECT id, sku FROM orders WHERE sku = ?`, "B-200").Scan(&id, &sku)
	fmt.Printf("   命中 → id=%d sku=%s err=%v\n", id, sku, err)

	err = db.QueryRow(`SELECT id, sku FROM orders WHERE sku = ?`, "不存在的SKU").Scan(&id, &sku)
	fmt.Printf("   未命中 → err=%v（是 sql.ErrNoRows）\n", err)
	fmt.Printf("   errors.Is(err, sql.ErrNoRows) = %v\n", errors.Is(err, sql.ErrNoRows))

	// ---- ErrNoRows 的真实报错原文 ----
	var cnt int
	err = db.QueryRow(`SELECT COUNT(*) FROM orders WHERE sku = ?`, "不存在的SKU").Scan(&cnt)
	fmt.Printf("4) 用聚合函数就不会 ErrNoRows：COUNT=%d err=%v\n", cnt, err)

	// ---- 参数类型不匹配的报错原文 ----
	var bad string
	err = db.QueryRow(`SELECT id FROM orders WHERE id = ?`, "不是数字").Scan(&bad)
	fmt.Printf("5) 参数类型不匹配 → err = %v\n", err)

	// ---- Scan 列数与目标不符 ----
	err = db.QueryRow(`SELECT id, sku, qty FROM orders WHERE id = 1`).Scan(&bad)
	fmt.Printf("6) Scan 目标少一个 → err = %v\n", err)

	// ---- Scan 到不能接收 NULL 的类型 ----
	_, _ = db.Exec(`INSERT INTO orders(sku, qty, amount) VALUES(?, ?, NULL)`, "C-300", 1)
	err = db.QueryRow(`SELECT amount FROM orders WHERE sku = ?`, "C-300").Scan(new(float64))
	fmt.Printf("7) NULL 扫进 *float64 → err = %v\n", err)
	var nf sql.NullFloat64
	err = db.QueryRow(`SELECT amount FROM orders WHERE sku = ?`, "C-300").Scan(&nf)
	fmt.Printf("   用 sql.NullFloat64 → err=%v valid=%v\n", err, nf.Valid)

	// ---- 列数 / 列名 ----
	rs2, _ := db.Query(`SELECT id, sku, amount FROM orders LIMIT 1`)
	cols, _ := rs2.Columns()
	fmt.Printf("8) Columns() = %v\n", cols)
	rs2.Close()

	// ---- 返回结果集大小 ----
	var total float64
	_ = db.QueryRow(`SELECT COALESCE(SUM(qty*amount),0) FROM orders`).Scan(&total)
	fmt.Printf("9) SUM(qty*amount) = %.2f\n", total)
}
