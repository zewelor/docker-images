import asyncio
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import tempfile
from threading import Event, Thread
import unittest
from unittest.mock import patch

from pxopulse_ocr import delivery


class StubResponse:
    def __init__(self, data, status_code=200):
        self.status_code = status_code
        self.data = data

    def json(self):
        return self.data


class DeliveryTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.enterContext(patch.object(delivery, "URL", "http://127.0.0.1:1/events_ocr"))
        self.enterContext(patch.dict("os.environ", {"NO_PROXY": "127.0.0.1"}))
        self.body = b"\x89PNG\r\n\x1a\n\0\xffplakat"

    async def deliver(self, attachment_id="24"):
        return await delivery.deliver(
            self.home, "17", attachment_id, "test.png", "image/png",
            self.body, "Feira amanhã", "test-bearer",
        )

    async def test_concurrent_claims_send_only_once(self):
        entered = Event()
        release = Event()

        def send(*_args, **_kwargs):
            entered.set()
            release.wait(4)
            return StubResponse({"status": "ok", "outcome": "added", "events": [], "results": []})

        with patch.object(delivery.requests, "post", side_effect=send) as request:
            task = asyncio.create_task(self.deliver())
            try:
                self.assertTrue(await asyncio.to_thread(entered.wait, 2))
                pending = await delivery.lookup_receipt(self.home, "17", "24")
                self.assertIn("Rozpoczęto", pending)
                self.assertNotIn("trwa", pending)
                self.assertEqual(pending, await self.deliver())
            finally:
                release.set()
                await task
        request.assert_called_once()

    async def test_timeout_does_not_repeat_upload_after_reopen(self):
        with patch.object(delivery.requests, "post", side_effect=delivery.requests.Timeout) as request:
            result = await self.deliver()
            replay = await self.deliver()
        self.assertIn("potwierdzić", result)
        self.assertEqual(result, replay)
        request.assert_called_once()
        self.assertEqual(request.call_args.args[0], delivery.URL)
        self.assertEqual(request.call_args.kwargs["timeout"], 600)
        self.assertIs(request.call_args.kwargs["allow_redirects"], False)

    async def test_partial_failure_details_are_replayed(self):
        payload = {
            "status": "error", "error_code": "ingestion_failed",
            "events": [
                {"name": "Feira", "start_date": "2026-12-07"},
                {"name": "Concerto", "start_date": "2026-12-08"},
            ],
            "results": [
                {"status": "added", "index": 0, "range": "Review!42"},
                {"status": "failed", "index": 1},
            ],
        }
        response = StubResponse(payload, status_code=503)
        with patch.object(delivery.requests, "post", return_value=response) as request:
            result = await self.deliver()
            replay = await self.deliver()
        self.assertIn("Feira", result)
        self.assertEqual(result, replay)
        request.assert_called_once()

    async def test_multipart_distinct_attachments_and_review_reply_from_http_stub(self):
        self.assertIsNone(await delivery.lookup_receipt(self.home, "17", "024"))
        self.assertFalse(any(self.home.iterdir()))
        received = []
        review = json.dumps({
            "status": "error",
            "error_code": "ocr_review_required",
            "message": "Hold for review",
            "events": [],
            "review_items": [{
                "stage": "admission",
                "group_id": 1,
                "trace": {"verified": False},
                "reason": "missing_location",
                "message": "Potwierdź miejsce",
                "candidate": {"name": "Concerto", "start_date": "2026-12-08"},
            }],
        }).encode()

        class Backend(BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                mime = f"Content-Type: {self.headers['Content-Type']}\r\n\r\n".encode() + body
                received.append((self.path, self.headers["Authorization"], mime))
                self.send_response(422)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(review)))
                self.end_headers()
                self.wfile.write(review)

            def log_message(self, *_args):
                pass

        with HTTPServer(("127.0.0.1", 0), Backend) as server:
            worker = Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
            worker.start()
            try:
                endpoint = f"http://127.0.0.1:{server.server_port}/events_ocr"
                with patch.object(delivery, "URL", endpoint):
                    first = await self.deliver("024")
                    second = await self.deliver("025")
                    replay = await delivery.lookup_receipt(self.home, "17", "024")
            finally:
                server.shutdown()
                worker.join()
        self.assertIn("Nic z tego plakatu nie zapisano", first)
        self.assertIn("Potwierdź miejsce", first)
        self.assertIn("add_event/#prefill", first)
        self.assertEqual(first, second)
        self.assertEqual(first, replay)
        self.assertEqual(len(received), 2)
        for path, auth, mime in received:
            self.assertEqual(path, "/events_ocr")
            self.assertEqual(auth, "Bearer test-bearer")
            parts = {
                part.get_param("name", header="content-disposition"): part
                for part in BytesParser(policy=policy.default).parsebytes(mime).iter_parts()
            }
            self.assertEqual(parts["event_image"].get_filename(), "test.png")
            self.assertEqual(parts["event_image"].get_content_type(), "image/png")
            self.assertEqual(parts["event_image"].get_payload(decode=True), self.body)
            self.assertEqual(parts["use_event_image"].get_payload(decode=True), b"on")
            self.assertEqual(parts["event_text"].get_payload(decode=True), "Feira amanhã".encode())
