"""Pinned official weights, streamed to a persistent classroom cache."""
import hashlib
import os
from pathlib import Path
import urllib.request

REVISION = "f86cb2c1fa58255f8052cc32aeede1b7482d4361"
MODEL_URL = f"https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/{REVISION}/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
SHA256 = "cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046"
TARGET = Path("/models/qwen.gguf")


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


if __name__ == "__main__":
    if TARGET.exists() and digest(TARGET) == SHA256:
        print("Verified cached Qwen2.5-Coder 1.5B Q4_K_M.", flush=True)
    else:
        temporary = TARGET.with_suffix(".partial")
        print("Downloading 1,117,320,768 bytes of official model weights; allow several minutes.", flush=True)
        with urllib.request.urlopen(MODEL_URL, timeout=90) as source, temporary.open("wb") as output:
            while block := source.read(1024 * 1024):
                output.write(block)
                # Bound dirty page cache as well as Python buffers under the 160 MiB cap.
                output.flush()
                os.fsync(output.fileno())
                os.posix_fadvise(output.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
        if digest(temporary) != SHA256:
            temporary.unlink(missing_ok=True)
            raise RuntimeError("Model checksum mismatch. Run docker compose up again to retry.")
        os.replace(temporary, TARGET)
        print("Model checksum verified. Starting the local model server.", flush=True)
