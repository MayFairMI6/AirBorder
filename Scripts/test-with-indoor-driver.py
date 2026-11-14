#!/usr/bin/env python3
# PROCEDURAL: Owns the replay subprocess for a simulator test invocation.
import os
import subprocess
import sys
from indoor_replay_process import running_driver


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python3 Scripts/test-with-indoor-driver.py xcodebuild [arguments...]")

    with running_driver() as base_url:
        env = os.environ.copy()
        env["TEST_RUNNER_AIRBORDER_QA_REPLAY_URL"] = base_url
        return subprocess.call(sys.argv[1:], env=env)


if __name__ == "__main__":
    sys.exit(main())
