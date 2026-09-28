#!/usr/bin/env python3
"""Exercise standalone CLI persistence using a disposable memo library."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="memos-cli-check-") as directory:
    environment = {**os.environ, "MEMOS_STORE": str(Path(directory) / "store.json")}
    def run(*arguments):
        return subprocess.check_output([str(binary), *arguments], env=environment, text=True).strip()
    assert "Memos" in run("--help")
    identifier = run("new", "Disposable CLI verification")
    assert run("show", identifier) == "Disposable CLI verification"
    run("append", identifier, "Second paragraph")
    assert "Second paragraph" in run("show", identifier)
    assert len(json.loads(run("list", "--json"))) == 1
    run("delete", identifier)
    assert json.loads(run("list", "--json")) == []
print("Standalone CLI create/read/update/delete passed on a disposable library.")
