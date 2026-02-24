#!/usr/bin/env python3
# @noindex
"""Bundled worker used by the REAPER Lua scripts.

It keeps the Lua side shell-agnostic and executes Demucs through the
same Python interpreter that launched this file.
"""

from __future__ import annotations

import sys


def main() -> int:
    try:
        from demucs.separate import main as demucs_main
    except Exception as exc:
        print(f"[worker] Failed to import demucs.separate: {exc}", file=sys.stderr)
        return 2

    try:
        result = demucs_main()
    except SystemExit as exc:
        code = exc.code
        if code is None:
            return 0
        if isinstance(code, int):
            return code
        return 1
    except Exception as exc:
        print(f"[worker] Demucs worker crashed: {exc}", file=sys.stderr)
        return 1

    if isinstance(result, int):
        return result
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
