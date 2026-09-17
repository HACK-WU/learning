package order

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type PaymentClient interface {
	Charge(context.Context, Order) error
}

type HTTPPaymentClient struct {
	baseURL string
	client  *http.Client
}

func NewHTTPPaymentClient(baseURL string, client *http.Client) (*HTTPPaymentClient, error) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if baseURL == "" {
		return nil, fmt.Errorf("payment URL is empty")
	}
	if client == nil {
		client = &http.Client{}
	}
	return &HTTPPaymentClient{baseURL: baseURL, client: client}, nil
}

func (c *HTTPPaymentClient) Charge(ctx context.Context, o Order) error {
	payload, err := json.Marshal(struct {
		OrderID     string `json:"order_id"`
		AmountCents int64  `json:"amount_cents"`
	}{o.ID, o.AmountCents})
	if err != nil {
		return fmt.Errorf("marshal payment request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/charge", bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("build payment request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("payment request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<10))
		return fmt.Errorf("payment upstream status %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}
