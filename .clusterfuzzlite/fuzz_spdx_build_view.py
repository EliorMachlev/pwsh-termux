"""Atheris fuzz target for scripts/spdx-build-view.py.

Random bytes become a Depends field and a build record. The script must
either refuse a record with BuildRecordError or give a document; any other
exception is a bug the fuzzer reports.
"""

import json
import sys

import atheris

# build.sh copies scripts/spdx-build-view.py next to this file as
# spdx_build_view.py (the file name has a hyphen, and the packed fuzzer
# cannot reach the repository's scripts/ folder).
with atheris.instrument_imports():
    import spdx_build_view as sbv


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
