"""Format the indexed /events_ocr receipt and links to the PXO Pulse form."""

import json
import re
from urllib.parse import quote


FORM_URL = "https://pxopulse.com/add_event/"
MAX_REVIEW_URL_BYTES = 1900
UNKNOWN_OUTCOME = "Nie udało się potwierdzić wyniku OCR. Sprawdź arkusz przed ponowieniem."
FIELD_LABELS = {
    "name": "Nazwa",
    "start_date": "Data rozpoczęcia",
    "location": "Miejsce",
    "start_time": "Godzina rozpoczęcia",
    "end_date": "Data zakończenia",
    "end_time": "Godzina zakończenia",
    "category": "Kategoria",
    "organizer": "Organizator",
    "price_type": "Wstęp",
    "description": "Opis",
    "contact_email": "Adres e-mail",
    "contact_tel": "Telefon",
    "event_link1": "Link 1",
    "event_link2": "Link 2",
    "event_link3": "Link 3",
    "event_link4": "Link 4",
}
REVIEW_REASONS = {
    "conflicting_location_evidence": "Na plakacie są sprzeczne informacje o miejscu.",
    "missing_location": "Brakuje potwierdzonego miejsca.",
    "missing_start_date": "Sprawdź datę rozpoczęcia.",
    "conflicting_inset": "Sprawdź datę i godzinę wydarzenia.",
    "missing_required_fields": "Uzupełnij wymagane pola.",
    "invalid_event_fields": "Sprawdź pola oznaczone poniżej.",
    "unavailable_additional_text": "Doprecyzuj informacje z opisu plakatu.",
}


def _require(condition):
    if not condition:
        raise ValueError(UNKNOWN_OUTCOME)


def _nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def _plain(value):
    # Keep OCR text from becoming Discord markdown or mentions.
    value = " ".join(value.split()).replace("@", "@\u200b")
    return re.sub(r"([\\\x60*_~|<>\[\]])", r"\\\1", value)


def _validate_event(event, *, ready=False):
    _require(isinstance(event, dict))
    _require(all(event.get(field) is None or isinstance(event[field], str) for field in FIELD_LABELS))
    if ready:
        _require(_nonempty(event.get("name")) and _nonempty(event.get("start_date")))


def _summary(event):
    parts = (_plain(event[key]) for key in ("name", "start_date", "start_time", "location")
             if _nonempty(event.get(key)))
    return " · ".join(parts) or "Brak danych o wydarzeniu"


def _review_url(event, reason, invalid_fields):
    def make_url(values):
        payload = {"event": values, "reason": reason}
        if invalid_fields:
            payload["validation_fields"] = invalid_fields
        return FORM_URL + "#prefill=" + quote(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), safe="")

    prefill = {}
    omitted = []
    for field, label in FIELD_LABELS.items():
        value = event.get(field)
        if not _nonempty(value):
            continue
        candidate = {**prefill, field: value}
        if len(make_url(candidate)) <= MAX_REVIEW_URL_BYTES:
            prefill = candidate
        elif field not in invalid_fields:
            omitted.append(f"{label}: {_plain(value)}")
    return make_url(prefill), omitted


def _format_review(event, reason=None, message=None, errors=None):
    invalid_fields = [field for field in FIELD_LABELS if errors and field in errors]
    reason_code = reason if reason and re.fullmatch(r"[a-z][a-z0-9_]{0,63}", reason) else None
    lines = [f"**Do sprawdzenia:** {_summary(event)}" if reason else f"**Wstrzymano:** {_summary(event)}"]
    if reason in REVIEW_REASONS:
        lines.append(REVIEW_REASONS[reason])
    elif reason:
        lines.append(f"Powód przeglądu: {_plain(reason)}.")
    if _nonempty(message):
        lines.append(_plain(message))
    for field in invalid_fields:
        hint = f"Sprawdź pole „{FIELD_LABELS[field]}”."
        if _nonempty(event.get(field)):
            hint += f" OCR odczytał: {_plain(event[field])}."
        lines.append(hint)
    url, omitted = _review_url(event, reason_code, invalid_fields)
    return "\n".join([*lines, *omitted, f"[Otwórz formularz review](<{url}>)",
                      "Aby opublikować plakat, dołącz go ponownie w formularzu."])


def _review_items(data):
    items = data.get("review_items", [])
    _require(isinstance(items, list))
    formatted = []
    for item in items:
        _require(isinstance(item, dict) and item.get("stage") == "admission"
                 and type(item.get("group_id")) is int and _nonempty(item.get("reason")))
        trace = item.get("trace")
        _require(isinstance(trace, dict) and trace.get("verified") is False)
        _require("message" in item and (item["message"] is None or isinstance(item["message"], str)))
        _require("candidate" in item)
        candidate = item["candidate"] if item["candidate"] is not None else {}
        _validate_event(candidate)
        errors = item.get("validation_errors", {})
        _require(isinstance(errors, dict))
        formatted.append(_format_review(candidate, item["reason"], item["message"], errors))
    return formatted


def _format_conflict(result):
    event = result.get("event")
    _validate_event(event)
    candidates = result.get("candidates")
    _require(isinstance(candidates, list) and candidates)
    lines = [f"**Możliwy duplikat:** {_summary(event)}"]
    for candidate in candidates:
        _require(isinstance(candidate, dict) and _nonempty(candidate.get("reference")))
        existing = candidate.get("event")
        _validate_event(existing)
        differences = candidate.get("differences")
        _require(isinstance(differences, list)
                 and all(isinstance(field, str) and field in FIELD_LABELS for field in differences))
        lines.append(f"- {_plain(candidate['reference'])} · {_summary(existing)}")
        for field in differences:
            label = FIELD_LABELS[field]
            proposed_value = _plain(event.get(field) or "brak")
            existing_value = _plain(existing.get(field) or "brak")
            lines.append(f"  {label}: plakat — {proposed_value}. Arkusz — {existing_value}.")
    url, _ = _review_url(event, None, [])
    lines.append(f"[Otwórz formularz, jeśli to inne wydarzenie](<{url}>)")
    lines.append("Dołącz plakat ponownie. Jeśli formularz wskaże ten sam wiersz, "
                 "wybierz „É outro evento” tylko po potwierdzeniu, że to osobne wydarzenie.")
    return "\n".join(lines)


def _format_outcomes(events, results, *, failed, conflict):
    _require(isinstance(results, list) and len(results) == len(events))
    allowed = {"added", "skipped", "conflict"} if failed or conflict else {"added", "skipped"}
    lines = []
    seen_conflict = False
    seen_failure = False
    for index, (event, result) in enumerate(zip(events, results)):
        _require(isinstance(result, dict) and type(result.get("index")) is int and result["index"] == index)
        outcome = result.get("status")
        _require(isinstance(outcome, str))
        if seen_failure:
            _require(outcome == "not_attempted")
            lines.append(f"**Pominięto próbę zapisu:** {_summary(event)}")
        elif outcome == "failed":
            _require(failed)
            seen_failure = True
            lines.append(f"**Zapis niepotwierdzony:** {_summary(event)}")
        else:
            _require(outcome in allowed)
            if outcome == "conflict":
                seen_conflict = True
                lines.append(_format_conflict(result))
            else:
                label, key = ("Dodano", "range") if outcome == "added" else ("Już w arkuszu", "existing_row")
                _require(_nonempty(result.get(key)))
                lines.append(f"**{label}:** {_summary(event)} ({_plain(result[key])})")
    _require(failed == seen_failure and (not conflict or seen_conflict))
    return lines


def format_receipt(status: int, data: dict) -> str:
    """Return the Discord message for a confirmed outcome, or raise ValueError."""
    _require(isinstance(data, dict))
    events = data.get("events")
    _require(isinstance(events, list))
    for event in events:
        _validate_event(event, ready=True)

    if status == 422 and data.get("error_code") == "ocr_review_required":
        _require(data.get("status") == "error" and isinstance(data.get("message"), str))
        _require(not ({"results", "counts", "image_ref", "retry_safe"} & data.keys()))
        reviews = _review_items(data)
        _require(reviews)
        ready = [_format_review(event) for event in events]
        return "\n\n".join(["**Nic z tego plakatu nie zapisano.**", *ready, *reviews])

    failed = status == 503 and data.get("status") == "error" and data.get("error_code") == "ingestion_failed"
    conflict = status == 409 and data.get("status") == "needs_review" and "error_code" not in data
    success = status == 200 and data.get("status") == "ok" and "error_code" not in data
    _require((failed or conflict or success) and "retry_safe" not in data)
    outcomes = _format_outcomes(events, data.get("results"), failed=failed, conflict=conflict)
    reviews = _review_items(data)
    if failed:
        raise ValueError("\n\n".join(["**Zapis plakatu nie został zakończony. Sprawdź arkusz przed ponowieniem.**",
                                      *outcomes, *reviews]))
    if not outcomes and not reviews:
        return f"Nie odczytano żadnego wydarzenia. [Otwórz formularz](<{FORM_URL}>)"
    return "\n\n".join([*outcomes, *reviews])
