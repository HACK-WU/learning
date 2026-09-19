#!/usr/bin/env python3
"""综合项目的最小回归测试。"""

from __future__ import annotations

import unittest

from client import request
from server import ALLOWED_ORIGIN, DEMO_TOKEN, start_server


class DiagnosticLabTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server, cls.thread = start_server()
        cls.host, cls.port = cls.server.server_address

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=1)

    def test_redirect_and_slow_response(self) -> None:
        redirect = request(self.host, self.port, "/api/redirect")
        self.assertEqual(redirect.status, 302)
        self.assertEqual(redirect.headers["location"], "/api/orders?source=redirect")

        slow = request(self.host, self.port, "/api/slow?header_delay_ms=1&body_delay_ms=1")
        self.assertEqual(slow.status, 200)
        self.assertGreaterEqual(slow.total_ms, 1)
        self.assertIn("app;dur=1", slow.headers["server-timing"])

    def test_authentication_states(self) -> None:
        missing = request(self.host, self.port, "/api/auth")
        self.assertEqual(missing.status, 401)
        self.assertIn("Bearer", missing.headers["www-authenticate"])

        forbidden = request(
            self.host,
            self.port,
            "/api/auth",
            headers={"Authorization": "Bearer wrong"},
        )
        self.assertEqual(forbidden.status, 403)

        valid = request(
            self.host,
            self.port,
            "/api/auth",
            headers={"Authorization": f"Bearer {DEMO_TOKEN}"},
        )
        self.assertEqual(valid.status, 200)

    def test_cors_preflight_and_cache_validation(self) -> None:
        preflight = request(
            self.host,
            self.port,
            "/api/orders",
            method="OPTIONS",
            headers={
                "Origin": ALLOWED_ORIGIN,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization, content-type",
            },
        )
        self.assertEqual(preflight.status, 204)
        self.assertEqual(preflight.headers["access-control-allow-origin"], ALLOWED_ORIGIN)

        created = request(
            self.host,
            self.port,
            "/api/orders",
            method="POST",
            headers={
                "Origin": ALLOWED_ORIGIN,
                "Authorization": f"Bearer {DEMO_TOKEN}",
                "Content-Type": "application/json",
            },
            body=b'{"item_id":"demo-001"}',
        )
        self.assertEqual(created.status, 201)
        self.assertEqual(created.headers["access-control-allow-origin"], ALLOWED_ORIGIN)

        denied = request(
            self.host,
            self.port,
            "/api/orders",
            method="OPTIONS",
            headers={
                "Origin": "http://evil.example",
                "Access-Control-Request-Method": "POST",
            },
        )
        self.assertEqual(denied.status, 403)

        first = request(self.host, self.port, "/api/orders")
        self.assertEqual(first.status, 200)
        second = request(
            self.host,
            self.port,
            "/api/orders",
            headers={"If-None-Match": first.headers["etag"]},
        )
        self.assertEqual(second.status, 304)
        self.assertEqual(second.body, b"")

        asset = request(self.host, self.port, "/static/app.abc123.js")
        self.assertIn("immutable", asset.headers["cache-control"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
