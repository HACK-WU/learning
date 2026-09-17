package order

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	_ "modernc.org/sqlite"
)

// Store 把 SQL 细节收口在 database/sql 之下，业务层只看 Order。
type Store struct {
	db *sql.DB
}

func OpenStore(ctx context.Context, dsn string) (*Store, error) {
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}

	// SQLite 是单文件数据库；单连接让内存 DSN 和状态转换都保持可预测。
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(30 * time.Minute)
	db.SetConnMaxIdleTime(5 * time.Minute)

	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("PingContext: %w", err)
	}

	const schema = `
CREATE TABLE IF NOT EXISTS orders (
    id              TEXT PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    amount_cents    INTEGER NOT NULL CHECK (amount_cents > 0),
    status          TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'paid', 'failed')),
    attempts        INTEGER NOT NULL DEFAULT 0,
    last_error      TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL
)`
	if _, err := db.ExecContext(ctx, schema); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("create orders table: %w", err)
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) CreateOrGet(ctx context.Context, key string, amountCents int64) (Order, bool, error) {
	id, err := newOrderID()
	if err != nil {
		return Order{}, false, err
	}
	now := time.Now().UTC()
	_, err = s.db.ExecContext(ctx, `
INSERT OR IGNORE INTO orders
    (id, idempotency_key, amount_cents, status, attempts, last_error, created_at, updated_at)
VALUES (?, ?, ?, ?, 0, '', ?, ?)`,
		id, key, amountCents, StatusPending, now.Format(time.RFC3339Nano), now.Format(time.RFC3339Nano))
	if err != nil {
		return Order{}, false, fmt.Errorf("insert order: %w", err)
	}

	created, err := s.getByKey(ctx, key)
	if err != nil {
		return Order{}, false, err
	}
	return created, created.ID == id, nil
}

func (s *Store) Get(ctx context.Context, id string) (Order, error) {
	row := s.db.QueryRowContext(ctx, `
SELECT id, idempotency_key, amount_cents, status, attempts, last_error, created_at, updated_at
FROM orders WHERE id = ?`, id)
	out, err := scanOrder(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Order{}, ErrNotFound
	}
	if err != nil {
		return Order{}, fmt.Errorf("get order %q: %w", id, err)
	}
	return out, nil
}

func (s *Store) MarkProcessing(ctx context.Context, id string) (bool, error) {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	result, err := s.db.ExecContext(ctx, `
UPDATE orders SET status = ?, attempts = attempts + 1, updated_at = ?
WHERE id = ? AND status = ?`, StatusProcessing, now, id, StatusPending)
	if err != nil {
		return false, fmt.Errorf("mark processing: %w", err)
	}
	n, err := result.RowsAffected()
	return n == 1, err
}

func (s *Store) MarkPaid(ctx context.Context, id string) error {
	return s.markFinal(ctx, id, StatusPaid, "")
}

func (s *Store) MarkFailed(ctx context.Context, id, reason string) error {
	return s.markFinal(ctx, id, StatusFailed, reason)
}

func (s *Store) RejectPending(ctx context.Context, id, reason string) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	result, err := s.db.ExecContext(ctx, `
UPDATE orders SET status = ?, last_error = ?, updated_at = ?
WHERE id = ? AND status = ?`, StatusFailed, reason, now, id, StatusPending)
	if err != nil {
		return fmt.Errorf("reject pending order: %w", err)
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("reject pending order %q: %w", id, ErrNotFound)
	}
	return nil
}

func (s *Store) getByKey(ctx context.Context, key string) (Order, error) {
	row := s.db.QueryRowContext(ctx, `
SELECT id, idempotency_key, amount_cents, status, attempts, last_error, created_at, updated_at
FROM orders WHERE idempotency_key = ?`, key)
	out, err := scanOrder(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Order{}, ErrNotFound
	}
	if err != nil {
		return Order{}, fmt.Errorf("get order by idempotency key: %w", err)
	}
	return out, nil
}

type scanner interface {
	Scan(...any) error
}

func scanOrder(row scanner) (Order, error) {
	var out Order
	var createdAt, updatedAt string
	err := row.Scan(
		&out.ID, &out.IdempotencyKey, &out.AmountCents, &out.Status,
		&out.Attempts, &out.LastError, &createdAt, &updatedAt)
	if err != nil {
		return Order{}, err
	}
	out.CreatedAt, err = time.Parse(time.RFC3339Nano, createdAt)
	if err != nil {
		return Order{}, fmt.Errorf("parse created_at: %w", err)
	}
	out.UpdatedAt, err = time.Parse(time.RFC3339Nano, updatedAt)
	if err != nil {
		return Order{}, fmt.Errorf("parse updated_at: %w", err)
	}
	return out, nil
}

func (s *Store) markFinal(ctx context.Context, id string, status Status, reason string) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	result, err := s.db.ExecContext(ctx, `
UPDATE orders SET status = ?, last_error = ?, updated_at = ?
WHERE id = ? AND status = ?`, status, reason, now, id, StatusProcessing)
	if err != nil {
		return fmt.Errorf("mark %s: %w", status, err)
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("mark %s %q: %w", status, id, ErrNotFound)
	}
	return nil
}

func newOrderID() (string, error) {
	var raw [8]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", fmt.Errorf("generate order id: %w", err)
	}
	return "ord_" + hex.EncodeToString(raw[:]), nil
}
