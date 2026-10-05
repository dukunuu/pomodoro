#!/usr/bin/env python3
"""Package the optional shared build key. Never print it or read the user's keystore."""
import argparse
import hashlib
import os
from pathlib import Path
import tempfile

# The packaged key is sealed so it is not readable text in the download: no
# file to open, nothing for `strings` or a secret scanner to match. This is
# obfuscation, not encryption — the app holds everything needed to reverse it.
# OpenRouterCredentials.swift and OpenRouterCredentials.cs carry the same
# constants and the same keystream.
SEAL_VERSION = 1
SEAL_NONCE_BYTES = 16
SEAL_PEPPER = bytes.fromhex('9d3f6c1ae4725b08c6a1f04d7be2953817ac40e96f2d8b5c03d17e94a86bf225')


def keystream(nonce: bytes, length: int) -> bytes:
    stream = b''
    counter = 0
    while len(stream) < length:
        stream += hashlib.sha256(SEAL_PEPPER + nonce + counter.to_bytes(4, 'big')).digest()
        counter += 1
    return stream[:length]


def seal(key: str) -> bytes:
    nonce = os.urandom(SEAL_NONCE_BYTES)
    plain = key.encode('ascii')
    body = bytes(a ^ b for a, b in zip(plain, keystream(nonce, len(plain))))
    return bytes([SEAL_VERSION]) + nonce + body


def unseal(blob: bytes) -> str | None:
    if len(blob) <= 1 + SEAL_NONCE_BYTES or blob[0] != SEAL_VERSION:
        return None
    nonce, body = blob[1:1 + SEAL_NONCE_BYTES], blob[1 + SEAL_NONCE_BYTES:]
    plain = bytes(a ^ b for a, b in zip(body, keystream(nonce, len(body))))
    return plain.decode('ascii') if all(0x21 <= c <= 0x7e for c in plain) else None


def bundle(destination: Path, value: str | None) -> bool:
    key = (value or '').strip()
    if not key:
        destination.unlink(missing_ok=True)
        return False
    if any(not ('!' <= c <= '~') for c in key):
        raise ValueError('OPENROUTER_API_KEY must be a single ASCII token.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=destination.parent, prefix='.openrouter-key-')
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(seal(key))
        os.replace(name, destination)
        # A shared distributed default must be readable by all installed-app users.
        # Sealing keeps it out of sight, but once packaged it is not a protected
        # user credential.
        destination.chmod(0o644)
    finally:
        Path(name).unlink(missing_ok=True)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        embedded = bundle(args.destination, os.environ.get('OPENROUTER_API_KEY'))
    except ValueError as error:
        parser.error(str(error))
    print('    shared OpenRouter build key included (sealed, but recoverable from the app)' if embedded
          else '    no OpenRouter build key supplied; users provide their own')


if __name__ == '__main__':
    main()
