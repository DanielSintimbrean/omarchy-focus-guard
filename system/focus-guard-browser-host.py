#!/usr/bin/python3
"""Read Focus Guard's current browser blocking state over native messaging."""

import json
import os
import re
import select
import struct
import subprocess
import sys
import time


CONTROLLER = "/usr/local/bin/focus-guardctl"
DOMAINS_FILE = "/etc/focus-guard/domains.conf"
MAX_MESSAGE_BYTES = 1024 * 1024
POLL_SECONDS = 1
HEARTBEAT_SECONDS = 15
DOMAIN_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")


def read_exact(size):
    parts = []
    remaining = size
    while remaining:
        chunk = os.read(sys.stdin.fileno(), remaining)
        if not chunk:
            return None
        parts.append(chunk)
        remaining -= len(chunk)
    return b"".join(parts)


def receive_message():
    header = read_exact(4)
    if header is None:
        return None

    length = struct.unpack("=I", header)[0]
    if length == 0 or length > MAX_MESSAGE_BYTES:
        return None

    payload = read_exact(length)
    if payload is None:
        return None
    return json.loads(payload.decode("utf-8"))


def send_message(message):
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    if len(payload) > MAX_MESSAGE_BYTES:
        raise ValueError("native messaging response is too large")

    sys.stdout.buffer.write(struct.pack("=I", len(payload)))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()


def read_domains():
    domains = set()
    try:
        with open(DOMAINS_FILE, "r", encoding="utf-8") as source:
            for line in source:
                domain = line.strip().lower().rstrip(".")
                labels = domain.split(".")
                if (
                    not domain
                    or len(domain) > 253
                    or len(labels) < 2
                    or not all(DOMAIN_LABEL.fullmatch(label) for label in labels)
                ):
                    continue
                domains.add(domain)
    except OSError:
        return []

    return sorted(domains)


def read_state():
    try:
        result = subprocess.run(
            [CONTROLLER, "status"],
            capture_output=True,
            check=True,
            text=True,
            timeout=2,
        )
        status = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return {"active": False, "domains": []}

    return {
        "active": status.get("expectedActive") is True,
        "domains": read_domains(),
    }


def main():
    try:
        request = receive_message()
    except (OSError, ValueError, json.JSONDecodeError):
        return
    if not isinstance(request, dict) or request.get("type") != "watch":
        return

    previous_state = None
    last_sent = 0.0
    while True:
        state = read_state()
        now = time.monotonic()
        if state != previous_state or now - last_sent >= HEARTBEAT_SECONDS:
            try:
                send_message(state)
            except (BrokenPipeError, OSError, ValueError):
                return
            previous_state = state
            last_sent = now

        try:
            readable, _, _ = select.select([sys.stdin.fileno()], [], [], POLL_SECONDS)
            if readable:
                message = receive_message()
                if message is None:
                    return
        except (OSError, ValueError, json.JSONDecodeError):
            return


if __name__ == "__main__":
    main()
