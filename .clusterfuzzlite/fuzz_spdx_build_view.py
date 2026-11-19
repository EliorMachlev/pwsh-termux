"""Atheris fuzz target for scripts/spdx-build-view.py.

Random bytes become a Depends field and a build record. The script must
either refuse a record with BuildRecordError or give a document; any other
exception is a bug the fuzzer reports.
"""

import importlib.util
import json
import sys
from pathlib import Path

import atheris

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "spdx-build-view.py"
spec = importlib.util.spec_from_file_location("spdx_build_view", SCRIPT)
assert spec is not None and spec.loader is not None
sbv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sbv)


def test_one_input(data: bytes) -> None:
    fdp = atheris.FuzzedDataProvider(data)
    depends = fdp.ConsumeUnicodeNoSurrogates(fdp.ConsumeIntInRange(0, 512))
    names = sbv.dependency_names(depends)
    assert len(names) == len(set(names))
    text = fdp.ConsumeUnicodeNoSurrogates(fdp.remaining_bytes())
    try:
        record = json.loads(text)
    except ValueError:
        return
    try:
        sbv.build_document("pkg.deb", record)
    except sbv.BuildRecordError:
        pass


if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
