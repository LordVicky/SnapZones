#!/usr/bin/env python3
"""Protocol tests for the unprivileged cursor sampler."""

import json
import io
import socket
import unittest

from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "helpers"))
from cursor_sampler import HyprlandCommandClient, default_socket_path, parse_cursor_response  # noqa: E402


class FakeSocket:
    def __init__(self, chunks):
        self.chunks = list(chunks)
        self.sent = []
        self.timeout = None
        self.connected_to = None

    def settimeout(self, value):
        self.timeout = value

    def connect(self, path):
        self.connected_to = path

    def sendall(self, data):
        self.sent.append(data)

    def recv(self, _size):
        if self.chunks:
            return self.chunks.pop(0)
        return b""

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class FakeSocketFactory:
    def __init__(self, socket):
        self.socket = socket
        self.calls = []

    def __call__(self, family, kind):
        self.calls.append((family, kind))
        return self.socket


class CursorSamplerProtocolTests(unittest.TestCase):
    def test_client_uses_json_cursor_command_and_reads_fragmented_response(self):
        fake = FakeSocket([b'{"x": 10', b', "y": -20}', b""])
        factory = FakeSocketFactory(fake)
        client = HyprlandCommandClient(
            "/run/user/1000/hypr/test/.socket.sock",
            socket_factory=factory,
        )

        response = client.request("j/cursorpos")

        self.assertEqual(parse_cursor_response(response), (10, -20))
        self.assertEqual(fake.sent, [b"j/cursorpos"])
        self.assertEqual(fake.connected_to, "/run/user/1000/hypr/test/.socket.sock")
        self.assertEqual(factory.calls, [(socket.AF_UNIX, socket.SOCK_STREAM)])

    def test_parser_rejects_malformed_or_unbounded_cursor_values(self):
        self.assertEqual(parse_cursor_response(json.dumps({"x": 5, "y": 9})), (5, 9))
        self.assertIsNone(parse_cursor_response("not-json"))
        self.assertIsNone(parse_cursor_response(json.dumps({"x": 1e20, "y": 2})))
        self.assertIsNone(parse_cursor_response(json.dumps({"x": "5", "y": 2})))

    def test_socket_path_is_derived_from_bounded_user_environment(self):
        self.assertEqual(
            default_socket_path({
                "XDG_RUNTIME_DIR": "/run/user/1000",
                "HYPRLAND_INSTANCE_SIGNATURE": "abc-123",
            }),
            Path("/run/user/1000/hypr/abc-123/.socket.sock"),
        )
        with self.assertRaises(RuntimeError):
            default_socket_path({"XDG_RUNTIME_DIR": "relative", "HYPRLAND_INSTANCE_SIGNATURE": "abc"})
        with self.assertRaises(RuntimeError):
            default_socket_path({"XDG_RUNTIME_DIR": "/run/user/1000", "HYPRLAND_INSTANCE_SIGNATURE": "../escape"})

    def test_sampler_throttles_repeated_socket_failures(self):
        from cursor_sampler import CursorSampler

        class FailingClient:
            def cursor_position(self):
                raise OSError("socket unavailable")

        class StopSampling(Exception):
            pass

        output = io.StringIO()
        sampler = CursorSampler(
            FailingClient(),
            clock=lambda: 0.0,
            sleeper=lambda _delay: (_ for _ in ()).throw(StopSampling()),
        )
        with self.assertRaises(StopSampling):
            sampler.run(output)
        self.assertEqual(len(output.getvalue().splitlines()), 1)

    def test_sampler_emits_successful_cursor_samples(self):
        from cursor_sampler import CursorSampler

        class SuccessfulClient:
            def cursor_position(self):
                return (123, -45)

        output = io.StringIO()
        sampler = CursorSampler(
            SuccessfulClient(),
            token=7,
            clock=lambda: 12.5,
            sleeper=lambda _delay: None,
        )

        sampler.run(output, once=True)

        self.assertEqual(
            json.loads(output.getvalue()),
            {"type": "cursor", "x": 123, "y": -45, "time": 12.5, "token": 7},
        )


if __name__ == "__main__":
    unittest.main()
