#!/usr/bin/env python3
"""Package the optional shared build key. Never print it or read the user's keystore."""
import argparse
import os
from pathlib import Path
import tempfile


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
        with os.fdopen(fd, 'w', encoding='utf-8') as output:
            output.write(key + '\n')
        os.replace(name, destination)
        # A shared distributed default must be readable by all installed-app users.
        # This is intentionally public once packaged, not a protected user credential.
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
    print('    shared OpenRouter build key included (extractable from the app)' if embedded
          else '    no OpenRouter build key supplied; users provide their own')


if __name__ == '__main__':
    main()
