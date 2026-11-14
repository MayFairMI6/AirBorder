# PROCEDURAL: Wait for the standalone driver to report its assigned loopback port.
import contextlib
import pathlib
import queue
import re
import subprocess
import sys
import threading


@contextlib.contextmanager
def running_driver():
    driver = pathlib.Path(__file__).with_name("indoor-signal-emulator.py")
    with subprocess.Popen(
        [sys.executable, str(driver), "--port", "0", "--paused", "--no-loop"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    ) as process:
        first_line = queue.Queue(maxsize=1)
        reader = threading.Thread(target=lambda: first_line.put(process.stdout.readline()), daemon=True)
        reader.start()
        try:
            try:
                line = first_line.get(timeout=30)
            except queue.Empty as error:
                raise RuntimeError("Indoor replay driver did not report readiness within 30 seconds") from error
            match = re.fullmatch(r"Indoor signal emulator: (http://127\.0\.0\.1:\d+)/reading\n", line)
            if match is None:
                raise RuntimeError(f"Indoor replay driver did not start: {line.strip() or 'no startup output'}")
            yield match.group(1)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            reader.join(timeout=5)
