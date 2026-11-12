#!/usr/bin/env python3
"""with_timeout.py <seconds> <command...>: runs the command, and ends it if it has not finished in time (exit 124).

macOS has no `timeout`; a simctl call that never returns would otherwise hold a CI job until the job's own limit.
"""
import subprocess
import sys

try:
    sys.exit(subprocess.run(sys.argv[2:], timeout=float(sys.argv[1])).returncode)
except subprocess.TimeoutExpired:
    print(f"TIMED OUT after {sys.argv[1]} s: {' '.join(sys.argv[2:])}", file=sys.stderr, flush=True)
    sys.exit(124)
