"""Route new Discord posters to PS Events OCR."""

import asyncio
import logging
import re

logger = logging.getLogger(__name__)
PROFILE = "pxopulse"
OCR_TOKEN = "FB_EVENTS_OCR_TOKEN_PXOPULSE"
MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # PS Events ImageService limit.
MAX_CAPTION_LENGTH = 5_000
MAX_REPLY_UNITS = 1_950  # Headroom below the Discord adapter limit.
IMAGE_TYPES = {
    "image/jpeg", "image/jpg", "image/png", "image/gif",
    "image/webp", "image/bmp", "image/tiff", "image/tif",
}


def register(ctx):
    ctx.register_hook("pre_gateway_dispatch", handle_poster)


def reply_chunks(text):
    """Keep review links on one line and under Discord's UTF-16 length limit."""
    pending = ""
    pending_units = 0
    for line in text.splitlines(keepends=True):
        line_units = len(line.encode("utf-16-le")) // 2
        if pending_units + line_units > MAX_REPLY_UNITS:
            if pending.strip():
                yield pending
            pending = ""
            pending_units = 0
        if line_units > MAX_REPLY_UNITS:
            # OCR may return an overlong plain field. Links are already bounded
            # by the prefill formatter, so only long plain lines need slicing.
            used = start = 0
            for index, char in enumerate(line):
                units = 2 if ord(char) > 0xFFFF else 1
                if used + units > MAX_REPLY_UNITS:
                    yield line[start:index]
                    used = 0
                    start = index
                used += units
            line = line[start:]
            line_units = used
        pending += line
        pending_units += line_units
    if pending.strip():
        yield pending


async def send(adapter, thread_id, text):
    # OCR fields and original filenames are untrusted Discord message text.
    content = re.sub(r"@(?!\u200b)", "@\u200b", text)
    for chunk in reply_chunks(content):
        try:
            result = await adapter.send(thread_id, chunk)
            if not result.success:
                logger.warning("PxoPulse OCR reply was not delivered to thread %s", thread_id)
        except Exception:
            logger.warning("PxoPulse OCR reply failed for thread %s", thread_id)


async def handle_poster(event, gateway):
    source = event.source
    if source.platform.value != "discord" or source.profile != PROFILE:
        return None

    # This lane is handled without entering a model turn, including replies.
    handled = {"action": "skip", "reason": "PxoPulse poster channel"}
    routes = [
        route for route in gateway.config.profile_routes
        if route.enabled and route.name == PROFILE and route.profile == PROFILE
        and route.platform == "discord" and route.bot_profile is None
    ]
    if len(routes) != 1 or not routes[0].guild_id or not routes[0].chat_id:
        logger.warning("PxoPulse OCR requires one Discord guild and channel route")
        return handled

    route = routes[0]
    if (
        source.guild_id != route.guild_id
        or source.parent_chat_id != route.chat_id
        or not source.auto_thread_created
        or not source.thread_id
        or not source.user_id
        or source.is_bot
    ):
        return handled

    # This hook precedes the runner's authorization gate. Ask it to check the
    # actual transport identity, which owns the existing Discord allowlist.
    if not gateway._is_user_authorized_for_source(source):
        return handled

    message = event.raw_message
    if (
        message is None
        or str(getattr(getattr(message, "guild", None), "id", "")) != route.guild_id
        or str(getattr(getattr(message, "channel", None), "id", "")) != route.chat_id
        or str(message.id) != event.message_id
        or str(message.author.id) != source.user_id
        or message.author.bot
        or message.webhook_id is not None
        or message.reference is not None
        or getattr(message, "message_snapshots", None)
    ):
        return handled

    adapter = gateway._adapter_for_source(source)
    if adapter is None:
        logger.warning("PxoPulse OCR has no Discord adapter for message %s", event.message_id)
        return handled

    images = [item for item in message.attachments if item.content_type in IMAGE_TYPES]
    if not images:
        await send(adapter, source.thread_id, "Dodaj plakat jako załącznik JPEG, PNG, GIF, WebP, BMP lub TIFF.")
        return handled

    from agent.secret_scope import get_secret
    from hermes_constants import get_hermes_home

    from .delivery import deliver, lookup_receipt

    home = get_hermes_home()
    caption = message.content.strip()[:MAX_CAPTION_LENGTH]
    await send(adapter, source.thread_id, f"Liczba plakatów w wiadomości: {len(images)}.")
    for image in images:
        attachment_id = str(image.id)
        try:
            previous = await lookup_receipt(home, event.message_id, attachment_id)
        except Exception:
            logger.error("PxoPulse OCR could not read delivery status for attachment %s", attachment_id)
            await send(adapter, source.thread_id, f"{image.filename}\nNie udało się sprawdzić stanu wcześniejszej wysyłki.")
            continue
        if previous is not None:
            await send(adapter, source.thread_id, f"{image.filename}\n{previous}")
            continue

        token = get_secret(OCR_TOKEN)
        if not token:
            logger.error("PxoPulse OCR token missing for profile %s", PROFILE)
            await send(adapter, source.thread_id, f"{image.filename}\nBrakuje poświadczenia do OCR. Plakat nie został wysłany.")
            continue

        if image.size > MAX_UPLOAD_BYTES:
            await send(adapter, source.thread_id, f"{image.filename}\nPlakat przekracza limit 10 MiB.")
            continue
        try:
            body = await asyncio.wait_for(image.read(), timeout=30)
            if not body or len(body) > MAX_UPLOAD_BYTES:
                raise ValueError("Unexpected attachment size")
        except Exception:
            logger.warning("PxoPulse OCR failed to read attachment %s", image.id)
            await send(adapter, source.thread_id, f"{image.filename}\nNie udało się pobrać plakatu.")
            continue

        try:
            reply = await deliver(
                home,
                event.message_id,
                attachment_id,
                image.filename,
                image.content_type,
                body,
                caption,
                token,
            )
        except Exception:
            logger.error("PxoPulse OCR could not confirm the result for attachment %s", image.id)
            reply = "Nie udało się potwierdzić wyniku OCR. Sprawdź arkusz przed kolejną wysyłką."
        await send(adapter, source.thread_id, f"{image.filename}\n{reply}")

    return handled
