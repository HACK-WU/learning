package order

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"
)

type ServiceConfig struct {
	QueueSize      int
	PaymentTimeout time.Duration
	MaxAttempts    int
	RetryDelay     time.Duration
	Logger         *slog.Logger
}

type Service struct {
	store          *Store
	payment        PaymentClient
	queue          chan string
	queueSize      int
	paymentTimeout time.Duration
	maxAttempts    int
	retryDelay     time.Duration
	metrics        *Metrics
	logger         *slog.Logger
	workerCtx      context.Context
	cancel         context.CancelFunc
	done           chan struct{}
}

func NewService(store *Store, payment PaymentClient, metrics *Metrics, cfg ServiceConfig) *Service {
	if cfg.QueueSize <= 0 {
		cfg.QueueSize = 32
	}
	if cfg.PaymentTimeout <= 0 {
		cfg.PaymentTimeout = 500 * time.Millisecond
	}
	if cfg.MaxAttempts <= 0 {
		cfg.MaxAttempts = 2
	}
	if cfg.RetryDelay <= 0 {
		cfg.RetryDelay = 20 * time.Millisecond
	}
	if cfg.Logger == nil {
		cfg.Logger = slog.Default()
	}
	if metrics == nil {
		metrics = &Metrics{}
	}
	return &Service{
		store:          store,
		payment:        payment,
		queue:          make(chan string, cfg.QueueSize),
		queueSize:      cfg.QueueSize,
		paymentTimeout: cfg.PaymentTimeout,
		maxAttempts:    cfg.MaxAttempts,
		retryDelay:     cfg.RetryDelay,
		metrics:        metrics,
		logger:         cfg.Logger,
		done:           make(chan struct{}),
	}
}

func (s *Service) Metrics() *Metrics { return s.metrics }

func (s *Service) Start(ctx context.Context) {
	if s.cancel != nil {
		return
	}
	s.workerCtx, s.cancel = context.WithCancel(ctx)
	go s.runWorker()
}

func (s *Service) Stop(ctx context.Context) error {
	if s.cancel == nil {
		return nil
	}
	s.cancel()
	select {
	case <-s.done:
		return nil
	case <-ctx.Done():
		return fmt.Errorf("stop worker: %w", ctx.Err())
	}
}

func (s *Service) Create(ctx context.Context, key string, amountCents int64) (Order, bool, error) {
	current, created, err := s.store.CreateOrGet(ctx, key, amountCents)
	if err != nil {
		return Order{}, false, err
	}
	if !created {
		if current.AmountCents != amountCents {
			return current, false, ErrIdempotencyConflict
		}
		return current, false, nil
	}

	select {
	case s.queue <- current.ID:
		s.metrics.OrdersCreated.Add(1)
		return current, true, nil
	default:
		_ = s.store.RejectPending(ctx, current.ID, ErrQueueFull.Error())
		return current, false, ErrQueueFull
	}
}

func (s *Service) Get(ctx context.Context, id string) (Order, error) {
	return s.store.Get(ctx, id)
}

func (s *Service) runWorker() {
	defer close(s.done)
	for {
		select {
		case <-s.workerCtx.Done():
			return
		case id := <-s.queue:
			s.process(id)
		}
	}
}

func (s *Service) process(id string) {
	claimed, err := s.store.MarkProcessing(s.workerCtx, id)
	if err != nil || !claimed {
		if err != nil && !errors.Is(err, context.Canceled) {
			s.logger.Error("claim order failed", "order_id", id, "err", err)
		}
		return
	}

	order, err := s.store.Get(s.workerCtx, id)
	if err != nil {
		s.logger.Error("load processing order failed", "order_id", id, "err", err)
		return
	}

	var lastErr error
	for attempt := 1; attempt <= s.maxAttempts; attempt++ {
		paymentCtx, cancel := context.WithTimeout(s.workerCtx, s.paymentTimeout)
		err = s.payment.Charge(paymentCtx, order)
		cancel()
		if err == nil {
			if markErr := s.store.MarkPaid(s.workerCtx, id); markErr != nil {
				s.logger.Error("mark paid failed", "order_id", id, "err", markErr)
				return
			}
			s.metrics.OrdersPaid.Add(1)
			return
		}
		lastErr = err
		if attempt == s.maxAttempts {
			break
		}
		s.metrics.PaymentRetry.Add(1)
		if !s.waitRetry() {
			return
		}
	}

	if markErr := s.store.MarkFailed(s.workerCtx, id, lastErr.Error()); markErr != nil {
		s.logger.Error("mark failed failed", "order_id", id, "err", markErr)
		return
	}
	s.metrics.OrdersFailed.Add(1)
}

func (s *Service) waitRetry() bool {
	timer := time.NewTimer(s.retryDelay)
	defer func() {
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
	}()
	select {
	case <-timer.C:
		return true
	case <-s.workerCtx.Done():
		return false
	}
}
