#!/usr/bin/env python3
"""Print a freshly generated fake secret of the requested kind.

Fixtures are generated at runtime so this repository never contains a
token-shaped string (GitHub push protection would reject the push, and
scanners would flag the repo).
"""
import base64
import secrets
import string
import sys

ALNUM = string.ascii_letters + string.digits
UPPER = string.ascii_uppercase + string.digits


def rand(chars, n):
    return "".join(secrets.choice(chars) for _ in range(n))


KINDS = {
    "github": lambda: "gh" + "p_" + rand(ALNUM, 36),
    "github-oauth": lambda: "gh" + "o_" + rand(ALNUM, 36),
    "github-pat": lambda: "github" + "_pat_" + rand(ALNUM + "_", 82),
    "aws-id": lambda: "AK" + "IA" + rand(UPPER, 16),
    "aws-secret": lambda: "aws_secret_access_key = " + rand(ALNUM + "/+", 40),
    "private-key": lambda: ("-----BEGIN " + "OPENSSH PRIVATE KEY-----\n"
                            + base64.b64encode(secrets.token_bytes(48)).decode() + "\n"
                            + "-----END " + "OPENSSH PRIVATE KEY-----"),
    "slack": lambda: "xo" + "xb-" + rand(string.digits, 12) + "-" + rand(ALNUM, 24),
    "stripe": lambda: "sk" + "_live_" + rand(ALNUM, 24),
    "google": lambda: "AI" + "za" + rand(ALNUM + "_-", 35),
    "anthropic": lambda: "sk-" + "ant-" + rand(ALNUM, 40),
    "low-entropy": lambda: "gh" + "p_" + "a" * 36,
    "aws-doc": lambda: "AKIAIOSFODNN7" + "EXAMPLE",
}

if __name__ == "__main__":
    print(KINDS[sys.argv[1]](), end="")
