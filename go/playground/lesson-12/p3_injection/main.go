// p3_injection —— 参数化查询 vs 字符串拼接：把 SQL 注入真的打出来。
package main

import (
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

func main() {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		panic(err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1) // :memory: 每条连接一个独立库，先锁到一条连接上

	if _, err := db.Exec(`CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, role TEXT)`); err != nil {
		panic(err)
	}
	for _, u := range []struct{ name, role string }{
		{"小谷", "admin"},
		{"小林", "user"},
	} {
		if _, err := db.Exec(`INSERT INTO users(name, role) VALUES(?, ?)`, u.name, u.role); err != nil {
			panic(err)
		}
	}

	inputs := []string{
		"小谷",
		"不存在的用户",
		`' OR '1'='1`,
		`' OR 1=1 --`,
		`'; DROP TABLE users; --`,
	}

	fmt.Println("=== 参数化：db.QueryRow(`... WHERE name = ?`, input) ===")
	for _, in := range inputs {
		var n int
		err := db.QueryRow(`SELECT COUNT(*) FROM users WHERE name = ?`, in).Scan(&n)
		fmt.Printf("  输入 %-24q → 命中 %d 行，err=%v\n", in, n, err)
	}

	fmt.Println()
	fmt.Println("=== 拼接：db.QueryRow(\"... WHERE name = '\" + input + \"'\") ===")
	for _, in := range inputs {
		q := "SELECT COUNT(*) FROM users WHERE name = '" + in + "'"
		var n int
		err := db.QueryRow(q).Scan(&n)
		show := q
		if len(show) > 72 {
			show = show[:72] + "..."
		}
		fmt.Printf("  输入 %-24q → 命中 %d 行，err=%v\n     实际 SQL: %s\n", in, n, err, show)
	}

	// 表还在吗？
	var cnt int
	if err := db.QueryRow(`SELECT COUNT(*) FROM sqlite_master WHERE name='users'`).Scan(&cnt); err != nil {
		fmt.Println("  查表是否存在时出错：", err)
	} else {
		fmt.Printf("  users 表还在吗：%v（1=在）\n", cnt)
	}

	// ---------------------------------------------------------------
	// 破坏性注入：DELETE 是最容易被注入打穿的一种语句
	// ---------------------------------------------------------------
	fmt.Println()
	fmt.Println("=== 破坏性注入：删除指定用户 ===")
	attacks := []string{"小谷", `' OR 1=1 --`} // 第二个输入由攻击者提供

	// 先演示参数化：只删掉匹配的那一行
	fmt.Println("A) 参数化 db.Exec(`DELETE FROM users WHERE name = ?`, input)")
	for _, in := range attacks {
		res, err := db.Exec(`DELETE FROM users WHERE name = ?`, in)
		aff, _ := res.RowsAffected()
		var left int
		_ = db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&left)
		fmt.Printf("   输入 %-14q → 删了 %d 行，全表剩 %d 行，err=%v\n", in, aff, left, err)
	}

	// 复位数据
	_, _ = db.Exec(`DELETE FROM users`)
	for _, u := range []struct{ name, role string }{
		{"小谷", "admin"},
		{"小林", "user"},
	} {
		_, _ = db.Exec(`INSERT INTO users(name, role) VALUES(?, ?)`, u.name, u.role)
	}

	// 再演示拼接：同一个输入把全表删光
	fmt.Println("B) 拼接 db.Exec(\"DELETE FROM users WHERE name = '\" + input + \"'\")")
	for _, in := range attacks {
		q := "DELETE FROM users WHERE name = '" + in + "'"
		res, err := db.Exec(q)
		var aff any
		if res != nil {
			v, _ := res.RowsAffected()
			aff = v
		}
		var left int
		_ = db.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&left)
		fmt.Printf("   输入 %-14q → 删了 %v 行，全表剩 %d 行，err=%v\n", in, aff, left, err)
		fmt.Printf("      实际 SQL: %s\n", q)
	}
}
