package order

import (
	"context"
	"errors"
	"testing"
)

func testStore(t *testing.T) *Store {
	t.Helper()
	store, err := OpenStore(context.Background(), "file:"+t.Name()+"?mode=memory&cache=shared")
	if err != nil {
		t.Fatalf("OpenStore: %v", err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return store
}

func TestStoreCreateGetAndIdempotency(t *testing.T) {
	store := testStore(t)
	first, created, err := store.CreateOrGet(context.Background(), "checkout-1", 1990)
	if err != nil {
		t.Fatal(err)
	}
	if !created || first.Status != StatusPending {
		t.Fatalf("first create = %+v, created=%v", first, created)
	}

	second, created, err := store.CreateOrGet(context.Background(), "checkout-1", 9999)
	if err != nil {
		t.Fatal(err)
	}
	if created || second.ID != first.ID || second.AmountCents != 1990 {
		t.Fatalf("idempotency replay = %+v, created=%v", second, created)
	}

	if _, err := store.Get(context.Background(), "missing"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing error = %v, want ErrNotFound", err)
	}
}

func TestStoreStateTransitions(t *testing.T) {
	store := testStore(t)
	o, _, err := store.CreateOrGet(context.Background(), "checkout-2", 2000)
	if err != nil {
		t.Fatal(err)
	}
	claimed, err := store.MarkProcessing(context.Background(), o.ID)
	if err != nil || !claimed {
		t.Fatalf("MarkProcessing = claimed:%v err:%v", claimed, err)
	}
	claimed, err = store.MarkProcessing(context.Background(), o.ID)
	if err != nil || claimed {
		t.Fatalf("second MarkProcessing = claimed:%v err:%v", claimed, err)
	}
	if err := store.MarkPaid(context.Background(), o.ID); err != nil {
		t.Fatal(err)
	}
	got, err := store.Get(context.Background(), o.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != StatusPaid || got.Attempts != 1 {
		t.Fatalf("final order = %+v", got)
	}
}
