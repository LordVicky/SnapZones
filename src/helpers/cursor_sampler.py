#!/usr/bin/env python3
"""Small, unprivileged Hyprland cursor sampler.

The helper talks directly to Hyprland's user-owned command socket. It never
opens raw input devices, shells out, asks for privileges, or writes a service
file. JSON lines on stdout are consumed by CursorSampler.qml.
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import socket
import sys
import time
from typing import Any, Callable, Mapping, Optional


DEFAULT_INTERVAL_MS = 16
MIN_INTERVAL_MS = 8
MAX_INTERVAL_MS = 1000
MAX_RESPONSE_BYTES = 64 * 1024
MAX_COORDINATE = 10_000_000
MAX_TOKEN = 2**31 - 1


def _safe_instance_signature(value: str) -> bool:
    return bool(value) and len(value) <= 128 and all(character.isalnum() or character in "_-" for character in value)


def default_socket_path(environ: Optional[Mapping[str, str]] = None) -> Path:
    """Resolve the per-user Hyprland command socket without a shell."""

    values = os.environ if environ is None else environ
    runtime_dir = str(values.get("XDG_RUNTIME_DIR", ""))
    signature = str(values.get("HYPRLAND_INSTANCE_SIGNATURE", ""))
    if not runtime_dir or not Path(runtime_dir).is_absolute():
        raise RuntimeError("XDG_RUNTIME_DIR is not an absolute directory")
    if not _safe_instance_signature(signature):
        raise RuntimeError("HYPRLAND_INSTANCE_SIGNATURE is missing or invalid")
    return Path(runtime_dir) / "hypr" / signature / ".socket.sock"


def _bounded_number(value: Any) -> Optional[int]:
    # bool is an int subclass but is never a valid cursor coordinate.
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    if not math.isfinite(number) or abs(number) > MAX_COORDINATE:
        return None
    return int(round(number))


def parse_cursor_response(payload: Any) -> Optional[tuple[int, int]]:
    """Parse ``j/cursorpos`` JSON, rejecting malformed/unbounded values."""

    try:
        if isinstance(payload, bytes):
            payload = payload.decode("utf-8")
        if isinstance(payload, str):
            parsed = json.loads(payload)
        elif isinstance(payload, Mapping):
            parsed = payload
        else:
            return None
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
        return None
    if not isinstance(parsed, Mapping):
        return None
    x = _bounded_number(parsed.get("x"))
    y = _bounded_number(parsed.get("y"))
    if x is None or y is None:
        return None
    return x, y


class HyprlandCommandClient:
    """A tiny request client that is straightforward to replace in tests."""

    def __init__(
        self,
        socket_path: str | Path,
        *,
        socket_factory: Callable[[int, int], Any] = socket.socket,
        timeout: float = 0.25,
        max_response_bytes: int = MAX_RESPONSE_BYTES,
    ) -> None:
        self.socket_path = str(socket_path)
        self.socket_factory = socket_factory
        self.timeout = max(0.05, min(float(timeout), 2.0))
        self.max_response_bytes = max(1024, min(int(max_response_bytes), MAX_RESPONSE_BYTES))

    def request(self, command: str) -> str:
        if command != "j/cursorpos":
            raise ValueError("only the cursor position request is allowed")
        sock = self.socket_factory(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.settimeout(self.timeout)
            sock.connect(self.socket_path)
            sock.sendall(command.encode("ascii"))
            chunks: list[bytes] = []
            total = 0
            while total < self.max_response_bytes:
                chunk = sock.recv(min(4096, self.max_response_bytes - total))
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
            if total >= self.max_response_bytes:
                raise RuntimeError("Hyprland response exceeded the safety limit")
            return b"".join(chunks).decode("utf-8")
        finally:
            close = getattr(sock, "close", None)
            if callable(close):
                close()

    def cursor_position(self) -> Optional[tuple[int, int]]:
        return parse_cursor_response(self.request("j/cursorpos"))


class CursorSampler:
    """Emit bounded cursor samples at a modest polling rate."""

    def __init__(
        self,
        client: HyprlandCommandClient,
        *,
        interval_ms: int = DEFAULT_INTERVAL_MS,
        token: int = 0,
        clock: Callable[[], float] = time.monotonic,
        sleeper: Callable[[float], None] = time.sleep,
    ) -> None:
        self.client = client
        self.interval_ms = max(MIN_INTERVAL_MS, min(int(interval_ms), MAX_INTERVAL_MS))
        self.token = max(0, min(int(token), MAX_TOKEN))
        self.clock = clock
        self.sleeper = sleeper

    def sample(self) -> Optional[dict[str, Any]]:
        point = self.client.cursor_position()
        if point is None:
            return None
        return {
            "type": "cursor",
            "x": point[0],
            "y": point[1],
            "time": self.clock(),
            "token": self.token,
        }

    def run(self, output: Any = sys.stdout, *, once: bool = False) -> None:
        last_error_at = -1.0
        last_error = ""
        while True:
            event = None
            try:
                event = self.sample()
            except (OSError, RuntimeError, TimeoutError, ValueError) as error:
                message = str(error)[:240]
                now = self.clock()
                # Do not fill Quickshell's pipe when Hyprland is restarting;
                # report the first failure and then at most twice per second.
                if message != last_error or last_error_at < 0 or now - last_error_at >= 0.5:
                    event = {
                        "type": "status",
                        "available": False,
                        "error": message,
                        "token": self.token,
                    }
                    last_error = message
                    last_error_at = now
            if event is not None:
                try:
                    output.write(json.dumps(event, separators=(",", ":")) + "\n")
                    output.flush()
                except BrokenPipeError:
                    return
            if once:
                return
            self.sleeper(self.interval_ms / 1000.0)


def _interval(value: str) -> int:
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("interval must be an integer") from error
    if number < MIN_INTERVAL_MS or number > MAX_INTERVAL_MS:
        raise argparse.ArgumentTypeError(f"interval must be between {MIN_INTERVAL_MS} and {MAX_INTERVAL_MS} ms")
    return number


def _token(value: str) -> int:
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("token must be an integer") from error
    if number < 0 or number > MAX_TOKEN:
        raise argparse.ArgumentTypeError(f"token must be between 0 and {MAX_TOKEN}")
    return number


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval-ms", type=_interval, default=DEFAULT_INTERVAL_MS)
    parser.add_argument("--token", type=_token, default=0, help=argparse.SUPPRESS)
    parser.add_argument("--socket-path", default="", help=argparse.SUPPRESS)
    parser.add_argument("--once", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        socket_path = Path(args.socket_path) if args.socket_path else default_socket_path()
        sampler = CursorSampler(HyprlandCommandClient(socket_path), interval_ms=args.interval_ms, token=args.token)
        sampler.run(once=args.once)
    except KeyboardInterrupt:
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"snapzones cursor sampler: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
