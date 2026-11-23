"""Submit one poster and keep Discord delivery outcomes across restarts."""

import asyncio
from contextlib import closing
import logging
from pathlib import Path
import sqlite3

import requests

from .receipt import format_receipt

URL = "https://be.pxopulse.com/events_ocr"
TIMEOUT = 600
UNKNOWN_OUTCOME = (
    "Nie udało się potwierdzić wyniku wysyłki. "
    "Sprawdź arkusz przed ponownym wysłaniem plakatu."
)
PENDING_OUTCOME = (
    "Rozpoczęto obsługę plakatu, ale wynik wysyłki jest niedostępny. "
    "Sprawdź arkusz przed ponownym wysłaniem plakatu."
)
LOG = logging.getLogger(__name__)


def _submit(filename: str, content_type: str, body: bytes, caption: str, token: str) -> str:
    fields = {"use_event_image": "on"}
    caption = caption.strip()[:5000]
    if caption:
        fields["event_text"] = caption

    try:
        response = requests.post(
            URL,
            files={"event_image": (filename, body, content_type)},
            data=fields,
            headers={"Authorization": f"Bearer {token}"},
            timeout=TIMEOUT,
            allow_redirects=False,
        )
        status = response.status_code
        data = response.json()
    except (requests.RequestException, ValueError) as error:
        LOG.warning("OCR response unavailable (%s)", type(error).__name__)
        return UNKNOWN_OUTCOME

    if isinstance(data, dict) and data.get("status") == "error":
        code = data.get("error_code")
        safe_503 = status == 503 and code == "ocr_temporarily_unavailable"
        safe_429 = status == 429 and code == "rate_limit_exceeded" and data.get("retry_safe") is True
        if safe_503 or safe_429:
            return "OCR jest chwilowo niedostępny. Nic nie zapisano. Spróbuj ponownie później."
    try:
        return format_receipt(status, data)
    except ValueError as error:
        LOG.warning("OCR could not confirm all writes (HTTP %s)", status)
        return str(error) or UNKNOWN_OUTCOME


def _database(home: Path) -> Path:
    return home / "plugin-data" / "pxopulse-ocr" / "deliveries.sqlite3"


def _read_receipt(connection: sqlite3.Connection, key: tuple[str, str]) -> str | None:
    row = connection.execute(
        "SELECT receipt FROM deliveries WHERE message_id = ? AND attachment_id = ?",
        key,
    ).fetchone()
    if row is None:
        return None
    return row[0] or PENDING_OUTCOME


def _lookup(database: Path, key: tuple[str, str]) -> str | None:
    if not database.exists():
        return None
    with closing(sqlite3.connect(database.absolute().as_uri() + "?mode=ro", uri=True)) as connection:
        # A concurrent first delivery may have created the database file but
        # not its schema yet. deliver() always claims the row again atomically.
        exists = connection.execute(
            "SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = 'deliveries'"
        ).fetchone()
        return _read_receipt(connection, key) if exists else None


async def lookup_receipt(home: Path, message_id: str, attachment_id: str) -> str | None:
    """Read an existing outcome without requiring an attachment or a token."""
    return await asyncio.to_thread(_lookup, _database(home), (message_id, attachment_id))


def _deliver_once(
    database: Path,
    key: tuple[str, str],
    filename: str,
    content_type: str,
    body: bytes,
    caption: str,
    token: str,
) -> str:
    database.parent.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(database)) as connection:
        with connection:
            connection.execute(
                """CREATE TABLE IF NOT EXISTS deliveries (
                       message_id TEXT NOT NULL,
                       attachment_id TEXT NOT NULL,
                       receipt TEXT,
                       PRIMARY KEY (message_id, attachment_id)
                   )"""
            )
            inserted = connection.execute(
                """INSERT INTO deliveries (message_id, attachment_id) VALUES (?, ?)
                   ON CONFLICT (message_id, attachment_id) DO NOTHING""",
                key,
            ).rowcount
            if not inserted:
                return _read_receipt(connection, key) or PENDING_OUTCOME

        # The claim must commit before the network request. A crash or an
        # unavailable receipt leaves the claim in place for manual inspection.
        receipt = _submit(filename, content_type, body, caption, token)
        with connection:
            connection.execute(
                "UPDATE deliveries SET receipt = ? WHERE message_id = ? AND attachment_id = ?",
                (receipt, *key),
            )
        return receipt


async def deliver(
    home: Path,
    message_id: str,
    attachment_id: str,
    filename: str,
    content_type: str,
    body: bytes,
    caption: str,
    token: str,
) -> str:
    """Return a stored outcome, or claim and submit an attachment exactly once locally."""
    return await asyncio.to_thread(
        _deliver_once, _database(home), (message_id, attachment_id), filename, content_type, body, caption, token,
    )
