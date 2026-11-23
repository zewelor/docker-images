import json
import re
import unittest
from urllib.parse import unquote

from pxopulse_ocr.receipt import format_receipt


CONCERT = {"name": "Concerto", "start_date": "21/11/2026", "location": "Centro Cultural"}
WORKSHOP = {"name": "Oficina", "start_date": "22/11/2026"}
REVIEW = {
    "stage": "admission",
    "group_id": 1,
    "reason": "missing_start_date",
    "message": None,
    "candidate": {"name": "Feira", "start_date": "23/11/2026", "internal": "ignore"},
    "trace": {"verified": False},
    "validation_errors": {"start_date": ["invalid"], "internal": ["invalid"]},
}


class ReceiptTest(unittest.TestCase):
    def test_held_batch_links_preserve_separate_candidates_and_validation_fields(self):
        data = {
            "status": "error", "error_code": "ocr_review_required", "message": "Review",
            "events": [CONCERT], "review_items": [REVIEW],
        }
        result = format_receipt(422, data)
        self.assertIn("Nic z tego plakatu nie zapisano.", result)
        self.assertIn("Sprawdź datę rozpoczęcia", result)
        links = re.findall(r"https://pxopulse\.com/add_event/#prefill=([^>)\s]+)", result)
        self.assertEqual([CONCERT, {"name": "Feira", "start_date": "23/11/2026"}],
                         [json.loads(unquote(link))["event"] for link in links])
        self.assertEqual(["start_date"], json.loads(unquote(links[1]))["validation_fields"])

    def test_mixed_results_include_saved_and_held_events(self):
        data = {
            "status": "ok", "events": [CONCERT, WORKSHOP], "review_items": [REVIEW],
            "results": [
                {"index": 0, "status": "added", "range": "Pending!A42:S42"},
                {"index": 1, "status": "skipped", "existing_row": "Approved!A16:S16"},
            ],
        }
        result = format_receipt(200, data)
        self.assertIn("Dodano", result)
        self.assertIn("Pending!A42:S42", result)
        self.assertIn("Już w arkuszu", result)
        self.assertIn("Approved!A16:S16", result)
        self.assertIn("Feira", result)
        self.assertNotIn("Nic z tego plakatu nie zapisano.", result)

    def test_conflict_shows_matching_row_and_field_values(self):
        result = format_receipt(409, {
            "status": "needs_review", "events": [CONCERT], "results": [{
                "index": 0, "status": "conflict", "event": CONCERT, "candidates": [{
                    "event": {**CONCERT, "location": "Biblioteca"},
                    "reference": "Approved!A12:S12", "differences": ["location"],
                }],
            }],
        })
        self.assertIn("Możliwy duplikat", result)
        self.assertIn("Approved!A12:S12", result)
        self.assertIn("Miejsce: plakat — Centro Cultural. Arkusz — Biblioteca.", result)

    def test_partial_failure_preserves_confirmed_prefix_via_exception(self):
        data = {
            "status": "error", "error_code": "ingestion_failed", "events": [CONCERT, WORKSHOP],
            "results": [
                {"index": 0, "status": "added", "range": "Pending!A42:S42"},
                {"index": 1, "status": "failed"},
            ],
        }
        with self.assertRaisesRegex(ValueError, r"(?s)Pending!A42:S42.*Oficina"):
            format_receipt(503, data)

    def test_ambiguous_or_inconsistent_receipts_fail_closed(self):
        fake = {
            "status": "error", "error_code": "ocr_review_required", "message": "Review",
            "events": [], "review_items": [REVIEW], "results": [],
        }
        for status, data in [
            (422, fake),
            (200, {"status": "ok", "events": [CONCERT], "results": []}),
            (409, {"status": "needs_review", "events": [], "results": []}),
            (503, {"status": "error", "message": "unknown"}),
        ]:
            with self.subTest(status=status), self.assertRaises(ValueError):
                format_receipt(status, data)

    def test_empty_result_points_to_manual_form(self):
        result = format_receipt(200, {"status": "ok", "events": [], "results": []})
        self.assertIn("Nie odczytano żadnego wydarzenia", result)
        self.assertIn("https://pxopulse.com/add_event/", result)
