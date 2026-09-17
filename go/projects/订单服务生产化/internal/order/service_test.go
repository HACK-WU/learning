package order

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

type fakePayment struct {
	mu       sync.Mutex
	count    int
	err      error
	delay    time.Duration
	byAmount map[int64]error
}

func (f *fakePayment) Charge(ctx context.Context, o Order) error {
	f.mu.Lock()
	f.count++
	err := f.err
	if f.byAmount != nil && f.byAmount[o.AmountCents] != nil {
		err = f.byAmount[o.AmountCents]
	}
	delay := f.delay
	f.mu.Unlock()
	if delay > 0 {
		timer := time.NewTimer(delay)
		defer timer.Stop()
		select {
		case <-timer.C:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return err
}

func (f *fakePayment) Calls() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.count
}

func eventuallyOrder(t *testing.T, store *Store, id string, want Status) Order {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		o, err := store.Get(context.Background(), id)
		if err == nil && o.Status == want {
			return o
		}
		time.Sleep(5 * time.Millisecond)
	}
	o, err := store.Get(context.Background(), id)
	t.Fatalf("order did not reach %s: order=%+v err=%v", want, o, err)
	return Order{}
}

func TestServiceWorkerMarksPaid(t *testing.T) {
	store := testStore(t)
	payment := &fakePayment{}
	svc := NewService(store, payment, nil, ServiceConfig{QueueSize: 2, PaymentTimeout: time.Second})
	svc.Start(context.Background())
	stopService(t, svc)

	o, created, err := svc.Create(context.Background(), "paid-1", 100)
	if err != nil || !created {
		t.Fatalf("Create = %+v created:%v err:%v", o, created, err)
	}
	got := eventuallyOrder(t, store, o.ID, StatusPaid)
	if got.Attempts != 1 || payment.Calls() != 1 {
		t.Fatalf("paid order = %+v calls=%d", got, payment.Calls())
	}
}

func TestServiceRetriesThenMarksFailed(t *testing.T) {
	store := testStore(t)
	payment := &fakePayment{err: errors.New("declined"), byAmount: map[int64]error{}}
	svc := NewService(store, payment, nil, ServiceConfig{
		QueueSize: 2, PaymentTimeout: time.Second, MaxAttempts: 2, RetryDelay: time.Millisecond,
	})
	svc.Start(context.Background())
	stopService(t, svc)

	o, _, err := svc.Create(context.Background(), "failed-1", 999)
	if err != nil {
		t.Fatal(err)
	}
	got := eventuallyOrder(t, store, o.ID, StatusFailed)
	if got.Attempts != 1 || payment.Calls() != 2 {
		t.Fatalf("failed order = %+v calls=%d", got, payment.Calls())
	}
	if got.LastError != "declined" || svc.Metrics().PaymentRetry.Load() != 1 {
		t.Fatalf("failure metadata = %+v retry=%d", got, svc.Metrics().PaymentRetry.Load())
	}
}

func TestServiceQueueFullRejectsPendingOrder(t *testing.T) {
	store := testStore(t)
	svc := NewService(store, &fakePayment{}, nil, ServiceConfig{QueueSize: 1})

	first, created, err := svc.Create(context.Background(), "queue-1", 100)
	if err != nil || !created {
		t.Fatalf("first Create = %+v created:%v err:%v", first, created, err)
	}

	second, created, err := svc.Create(context.Background(), "queue-2", 200)
	if !errors.Is(err, ErrQueueFull) || created {
		t.Fatalf("second Create = %+v created:%v err:%v", second, created, err)
	}
	got, err := store.Get(context.Background(), second.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != StatusFailed || got.LastError != ErrQueueFull.Error() {
		t.Fatalf("rejected order = %+v", got)
	}
}

func stopService(t *testing.T, svc *Service) {
	t.Helper()
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		defer cancel()
		if err := svc.Stop(ctx); err != nil {
			t.Errorf("Stop: %v", err)
		}
	})
}
