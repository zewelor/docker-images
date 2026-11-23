import re
import sys
import unittest
from pathlib import Path
from types import ModuleType, SimpleNamespace as NS
from unittest.mock import AsyncMock, Mock, patch

import pxopulse_ocr
from pxopulse_ocr.receipt import format_receipt


def attachment(attachment_id, filename, content_type, data):
    return NS(
        id=attachment_id,
        filename=filename,
        content_type=content_type,
        size=len(data),
        read=AsyncMock(return_value=data),
    )


class TestPosterGateway(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.poster = attachment(101, "festa.png", "image/png", b"original-poster")
        self.message = NS(
            id=200,
            guild=NS(id=300),
            channel=NS(id=400),
            author=NS(id=500, bot=False),
            webhook_id=None,
            reference=None,
            message_snapshots=[],
            content="",
            attachments=[self.poster],
        )
        self.source = NS(
            platform=NS(value="discord"),
            profile="pxopulse",
            guild_id="300",
            parent_chat_id="400",
            chat_id="200",
            thread_id="200",
            auto_thread_created=True,
            is_bot=False,
            user_id="500",
        )
        self.event = NS(
            raw_message=self.message,
            source=self.source,
            text="(The user sent a message with no text content)",
            message_id="200",
        )
        self.transport = NS(send=AsyncMock(return_value=NS(success=True)))
        self.gateway = NS(
            config=NS(profile_routes=[NS(
                enabled=True, platform="discord", profile="pxopulse", name="pxopulse",
                guild_id="300", chat_id="400", bot_profile=None,
            )]),
            _is_user_authorized_for_source=Mock(return_value=True),
            _adapter_for_source=Mock(return_value=self.transport),
        )
        self.home = Path("/opt/data/profiles/pxopulse")
        constants = ModuleType("hermes_constants")
        constants.get_hermes_home = Mock(return_value=self.home)
        agent = ModuleType("agent")
        secret_scope = ModuleType("agent.secret_scope")
        self.token = secret_scope.get_secret = Mock(return_value="scoped-ocr-token")
        delivery = ModuleType("pxopulse_ocr.delivery")
        self.deliver = delivery.deliver = AsyncMock(return_value="Dodano wydarzenie.")
        self.lookup = delivery.lookup_receipt = AsyncMock(return_value=None)
        modules = patch.dict(sys.modules, {
            "hermes_constants": constants,
            "agent": agent,
            "agent.secret_scope": secret_scope,
            "pxopulse_ocr.delivery": delivery,
        })
        modules.start()
        self.addCleanup(modules.stop)
        ctx = NS(register_hook=Mock())
        pxopulse_ocr.register(ctx)
        name, self.handler = ctx.register_hook.call_args.args
        self.assertEqual(name, "pre_gateway_dispatch")

    async def dispatch(self):
        return await self.handler(self.event, self.gateway)

    async def test_image_only_uses_original_bytes_and_same_bots_thread(self):
        result = await self.dispatch()

        self.assertEqual(result["action"], "skip")
        self.gateway._is_user_authorized_for_source.assert_called_once_with(self.source)
        self.gateway._adapter_for_source.assert_called_once_with(self.source)
        self.token.assert_called_once_with("FB_EVENTS_OCR_TOKEN_PXOPULSE")
        self.deliver.assert_awaited_once_with(
            self.home, "200", "101", "festa.png", "image/png",
            b"original-poster", "", "scoped-ocr-token",
        )
        replies = [call.args for call in self.transport.send.await_args_list]
        self.assertEqual([channel for channel, _ in replies], ["200", "200"])
        self.assertIn("Dodano wydarzenie.", replies[-1][1])

    async def test_caption_two_images_and_a_non_image(self):
        self.message.content = "  Sala da vila às 20h  "
        other = attachment(102, "orquestra.webp", "image/webp", b"second-poster")
        document = attachment(103, "document.pdf", "application/pdf", b"pdf")
        self.message.attachments.extend([document, other])
        await self.dispatch()

        self.assertEqual(
            [call.args[2:] for call in self.deliver.await_args_list],
            [
                ("101", "festa.png", "image/png", b"original-poster", "Sala da vila às 20h", "scoped-ocr-token"),
                ("102", "orquestra.webp", "image/webp", b"second-poster", "Sala da vila às 20h", "scoped-ocr-token"),
            ],
        )
        document.read.assert_not_awaited()

    async def test_unauthorized_sender_does_not_download_or_upload(self):
        self.gateway._is_user_authorized_for_source.return_value = False
        await self.dispatch()
        self.poster.read.assert_not_awaited()
        self.transport.send.assert_not_awaited()
        self.deliver.assert_not_awaited()

    async def test_different_guild_or_channel_has_no_ocr(self):
        self.message.guild.id = 301
        await self.dispatch()
        self.message.guild.id = 300
        self.message.channel.id = 401
        await self.dispatch()

        self.poster.read.assert_not_awaited()
        self.deliver.assert_not_awaited()

    async def test_unrelated_default_profile_falls_through_to_agent(self):
        self.source.profile = None
        self.assertIsNone(await self.dispatch())
        self.deliver.assert_not_awaited()
        self.transport.send.assert_not_awaited()

    async def test_caption_without_poster_is_consumed_with_help(self):
        self.message.attachments.clear()
        self.message.content = "Czy to wystarczy?"
        self.assertEqual((await self.dispatch())["action"], "skip")
        self.assertIn("Dodaj plakat", self.transport.send.await_args.args[1])
        self.deliver.assert_not_awaited()

    async def test_missing_profile_secret_is_reported_before_upload(self):
        self.token.return_value = None
        with self.assertLogs("pxopulse_ocr", level="ERROR"):
            self.assertEqual((await self.dispatch())["action"], "skip")
        self.assertIn("Brakuje poświadczenia", self.transport.send.await_args.args[1])
        self.poster.read.assert_not_awaited()
        self.deliver.assert_not_awaited()

    async def test_thread_replies_and_forwarded_posts_have_no_ocr(self):
        self.message.channel.id = 200
        self.source.auto_thread_created = False
        await self.dispatch()
        self.message.channel.id = 400
        self.source.auto_thread_created = True
        self.message.reference = NS(message_id=123)
        await self.dispatch()
        self.message.reference = None
        self.message.message_snapshots = [NS()]
        await self.dispatch()

        self.poster.read.assert_not_awaited()
        self.deliver.assert_not_awaited()

    async def test_bot_posts_and_dms_have_no_ocr(self):
        self.message.author.bot = self.source.is_bot = True
        await self.dispatch()
        self.message.author.bot = self.source.is_bot = False
        self.message.guild = None
        await self.dispatch()

        self.poster.read.assert_not_awaited()
        self.deliver.assert_not_awaited()

    async def test_attachment_failure_stays_visible_and_does_not_stop_other_images(self):
        self.poster.read.side_effect = OSError("test failure")
        self.message.attachments.append(attachment(102, "other.png", "image/png", b"second"))
        with self.assertLogs("pxopulse_ocr", level="WARNING"):
            result = await self.dispatch()

        self.assertEqual(result["action"], "skip")
        self.deliver.assert_awaited_once()
        self.assertEqual(self.deliver.await_args.args[2], "102")
        replies = [call.args[1] for call in self.transport.send.await_args_list]
        self.assertTrue(any("Nie udało się pobrać" in reply for reply in replies))

    async def test_large_review_keeps_every_link_in_the_original_thread(self):
        ready = [
            {"name": f"Wydarzenie {index}", "start_date": "24/11/2026", "description": "x" * 1700}
            for index in range(9)
        ]
        receipt = format_receipt(422, {
            "status": "error",
            "error_code": "ocr_review_required",
            "message": "Pedido de revisão.",
            "events": ready,
            "review_items": [{
                "stage": "admission",
                "group_id": 1,
                "reason": "missing_location",
                "trace": {"verified": False},
                "message": None,
                "candidate": {"name": "Ostatnie wydarzenie", "start_date": "24/11/2026"},
            }],
        })
        links = re.findall(r"\[Otwórz formularz review\]\(<[^>]+>\)", receipt)
        self.assertEqual(len(links), 10)
        self.assertGreater(len(links[0]), 1800)
        self.deliver.return_value = receipt

        await self.dispatch()

        replies = self.transport.send.await_args_list[1:]
        self.assertGreater(len(replies), 8)
        self.assertTrue(all(reply.args[0] == "200" for reply in replies))
        chunks = [reply.args[1] for reply in replies]
        self.assertTrue(all(len(chunk.encode("utf-16-le")) <= 3900 for chunk in chunks))
        for link in links:
            self.assertTrue(any(link in chunk for chunk in chunks))
        self.assertEqual("".join(chunks), "festa.png\n" + receipt)

    async def test_overlong_line_preserves_emoji_and_suppresses_mentions(self):
        self.poster.filename = "<@123>.png"
        self.deliver.return_value = "🎆" * 2_000 + " @everyone"

        await self.dispatch()

        chunks = [reply.args[1] for reply in self.transport.send.await_args_list[1:]]
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(chunk.encode("utf-16-le")) <= 3900 for chunk in chunks))
        self.assertEqual("".join(chunks), "<@\u200b123>.png\n" + "🎆" * 2_000 + " @\u200beveryone")

    async def test_redelivery_replays_result_when_original_attachment_and_token_are_unavailable(self):
        self.lookup.return_value = "Wynik poprzedniej wysyłki."
        self.poster.read.side_effect = OSError("attachment expired")
        self.token.return_value = None

        self.assertEqual((await self.dispatch())["action"], "skip")

        self.lookup.assert_awaited_once_with(self.home, "200", "101")
        self.poster.read.assert_not_awaited()
        self.deliver.assert_not_awaited()
        self.token.assert_not_called()
        self.assertIn("Wynik poprzedniej wysyłki.", self.transport.send.await_args.args[1])
