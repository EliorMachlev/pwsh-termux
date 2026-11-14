"""Property-based fuzzing of scripts/spdx-build-view.py with Hypothesis.

Run from the repository root:

    python -m unittest discover -s tests/fuzz -v

HYPOTHESIS_PROFILE picks how hard: "ci" (the default; every pull request)
or "long" (the weekly scheduled run). A failure prints the smallest input
that fails and a @reproduce_failure line to replay it.

What must hold for any input:
  - a build record that is not what build-deb.sh or build-keyring.sh writes
    (any JSON value, or a real record with fields dropped or replaced) gives
    BuildRecordError, never another exception, and the command line exits
    with a one-line message instead of a traceback;
  - any Depends field (any text) gives unique, clean package names, and a
    well-formed one gives back exactly the names it was made from;
  - every document is valid SPDX 2.3 in the ways this script controls:
    identifiers allowed by SPDX and unique, every relationship between
    elements that exist, one DESCRIBES, one package per dependency, SHA-256
    checksums in lowercase hex, purls that decode to the recorded values,
    and the same JSON after a round trip;
  - the same inputs give the same document, apart from the creation time
    and the namespace's random UUID.
"""

import importlib.util
import json
import os
import re
import string
import sys
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path
from typing import Any
from unittest import mock
from urllib.parse import unquote

from hypothesis import given, settings
from hypothesis import strategies as st

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "spdx-build-view.py"


def load_script() -> Any:
    """The script as a module (its file name has a hyphen, so no import)."""
    spec = importlib.util.spec_from_file_location("spdx_build_view", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sbv = load_script()

settings.register_profile(
    "ci",
    max_examples=300,
    deadline=timedelta(seconds=2),
    print_blob=True,
)
settings.register_profile(
    "long",
    max_examples=20_000,
    deadline=timedelta(seconds=2),
    print_blob=True,
)
settings.load_profile(os.environ.get("HYPOTHESIS_PROFILE", "ci"))

SPDX_ID = re.compile(r"SPDXRef-[A-Za-z0-9.-]+")
SHA256 = re.compile(r"[0-9a-f]{64}")
FAKE_DEB_SHA = "0" * 64

# --- Strategies -------------------------------------------------------------

json_scalars = (
    st.none()
    | st.booleans()
    | st.integers()
    | st.floats(allow_nan=False, allow_infinity=False)
    | st.text()
)
json_values = st.recursive(
    json_scalars,
    lambda inner: (
        st.lists(inner, max_size=5) | st.dictionaries(st.text(), inner, max_size=5)
    ),
    max_leaves=20,
)

# A Debian package name: lowercase letters, digits, "+", "-", ".", starting
# with a letter or digit, at least two characters (Debian policy 5.6.1).
deb_names = st.from_regex(r"[a-z0-9][a-z0-9+.-]{1,30}", fullmatch=True)
deb_versions = st.from_regex(
    r"([0-9]:)?[0-9][A-Za-z0-9.+~]{0,15}(-[A-Za-z0-9.+~]{1,8})?", fullmatch=True
)
sha256s = st.text(alphabet="0123456789abcdef", min_size=64, max_size=64)
# Any text that is a non-empty, valid-Unicode field value.
field_texts = st.text(
    alphabet=st.characters(exclude_categories=["Cs"]), min_size=1
).filter(lambda s: s.strip())


@st.composite
def upstream_records(draw: st.DrawFn, values: st.SearchStrategy[str]) -> dict:
    return {
        "package": draw(values),
        "version": draw(values),
        "upstream_tag": draw(
            (values.map(lambda s: "v" + s) | values).filter(
                lambda tag: tag.removeprefix("v")
            )
        ),
        "upstream_url": draw(values),
        "upstream_sha256": draw(sha256s | sha256s.map(str.upper)),
        "patchelf_version": draw(values),
    }


@st.composite
def keyring_records(draw: st.DrawFn, values: st.SearchStrategy[str]) -> dict:
    return {
        "package": draw(values),
        "version": draw(values),
        "architecture": "all",
        "source_file": draw(values),
        "source_sha256": draw(sha256s),
        "source_date_epoch": draw(st.integers(min_value=0)),
    }


def records(values: st.SearchStrategy[str]) -> st.SearchStrategy[dict]:
    return upstream_records(values) | keyring_records(values)


realistic_records = records(deb_names | deb_versions)
any_valid_records = records(field_texts)


@st.composite
def broken_records(draw: st.DrawFn) -> dict:
    """A valid record with one required field dropped or replaced."""
    record = draw(any_valid_records)
    required = sbv.UPSTREAM_FIELDS if "upstream_tag" in record else sbv.KEYRING_FIELDS
    field = draw(st.sampled_from(required))
    if draw(st.booleans()):
        del record[field]
    else:
        record[field] = draw(
            json_values.filter(lambda v: not isinstance(v, str))
            | st.text(alphabet=string.whitespace)
            | st.just("\ud800")
            | (
                st.text().filter(lambda s: not SHA256.fullmatch(s.lower()))
                if field.endswith("sha256")
                else st.nothing()
            )
        )
    return record


@st.composite
def depends_fields(draw: st.DrawFn) -> tuple[str, list[str]]:
    """A well-formed Depends field and the names in it, in order, once each."""
    groups, names = [], []
    for _ in range(draw(st.integers(0, 6))):
        alternatives = []
        for _ in range(draw(st.integers(1, 3))):
            name = draw(deb_names)
            if name not in names:
                names.append(name)
            arch = draw(st.sampled_from(["", ":any", ":native", ":aarch64"]))
            space = draw(st.sampled_from(["", " "]))
            constraint = draw(
                st.none()
                | st.tuples(
                    st.sampled_from(["<<", "<=", "=", ">=", ">>"]), deb_versions
                ).map(lambda t: f"({t[0]} {t[1]})")
            )
            alternatives.append(
                name + arch + (space + constraint if constraint else "")
            )
        sep = draw(st.sampled_from(["|", " | ", " |"]))
        groups.append(sep.join(alternatives))
    joiner = draw(st.sampled_from([",", ", ", " ,  "]))
    return joiner.join(groups), names


arches = st.sampled_from(["aarch64", "all", "arm", "x86_64"]) | field_texts


# --- Helpers ----------------------------------------------------------------


def fake_dpkg(depends: str, arch: str) -> Any:
    """deb_field and file_sha256 without dpkg-deb or a .deb."""
    fields = {"Depends": depends, "Architecture": arch}
    return (
        mock.patch.object(sbv, "deb_field", lambda _deb, field: fields[field]),
        mock.patch.object(sbv, "file_sha256", lambda _path: FAKE_DEB_SHA),
    )


def build(record: Any, depends: str = "", arch: str = "aarch64") -> dict:
    deb_field, file_sha = fake_dpkg(depends, arch)
    with deb_field, file_sha:
        return sbv.build_document("pkg.deb", record)


def purl_parts(locator: str) -> tuple[str, str, str]:
    """(type/namespace/name, version, qualifiers) of a purl, decoded."""
    assert locator.startswith("pkg:"), locator
    rest, _, qualifiers = locator[4:].partition("?")
    path, sep, version = rest.rpartition("@")
    assert sep, locator
    for part in (path, version, qualifiers):
        assert not set(part) & set("@?# "), locator
    return path, unquote(version), qualifiers


class DocumentChecks(unittest.TestCase):
    def assert_valid_document(self, doc: dict, record: dict, deps: list[str]) -> None:
        # Plain JSON: the same after a round trip.
        self.assertEqual(json.loads(json.dumps(doc)), doc)
        self.assertEqual(doc["spdxVersion"], "SPDX-2.3")
        self.assertEqual(doc["SPDXID"], sbv.DOCUMENT_ID)

        ids = [p["SPDXID"] for p in doc["packages"]]
        self.assertEqual(len(ids), len(set(ids)), "duplicate SPDXID")
        for sid in [*ids, doc["SPDXID"]]:
            self.assertTrue(SPDX_ID.fullmatch(sid), sid)

        elements = {*ids, doc["SPDXID"]}
        for rel in doc["relationships"]:
            self.assertIn(rel["spdxElementId"], elements)
            self.assertIn(rel["relatedSpdxElement"], elements)
        describes = [
            r for r in doc["relationships"] if r["relationshipType"] == "DESCRIBES"
        ]
        self.assertEqual(
            describes,
            [
                {
                    "spdxElementId": sbv.DOCUMENT_ID,
                    "relationshipType": "DESCRIBES",
                    "relatedSpdxElement": sbv.DEB_ID,
                }
            ],
        )

        dep_packages = [
            p
            for p in doc["packages"]
            if p["SPDXID"].startswith(sbv.DEPENDENCY_ID_PREFIX)
        ]
        self.assertEqual([p["name"] for p in dep_packages], deps)
        depends_on = {
            r["relatedSpdxElement"]
            for r in doc["relationships"]
            if r["relationshipType"] == "DEPENDS_ON"
        }
        self.assertEqual(depends_on, {p["SPDXID"] for p in dep_packages})

        for p in doc["packages"]:
            for checksum in p.get("checksums", []):
                self.assertEqual(checksum["algorithm"], "SHA256")
                self.assertTrue(SHA256.fullmatch(checksum["checksumValue"]))
            for ref in p.get("externalRefs", []):
                purl_parts(ref["referenceLocator"])

        deb = doc["packages"][0]
        self.assertEqual(deb["SPDXID"], sbv.DEB_ID)
        self.assertEqual(deb["name"], record["package"])
        self.assertEqual(deb["versionInfo"], record["version"])
        path, version, _ = purl_parts(deb["externalRefs"][0]["referenceLocator"])
        self.assertEqual(unquote(path), f"deb/termux/{record['package']}")
        self.assertEqual(version, record["version"])

        if "upstream_tag" in record:
            upstream = next(
                p for p in doc["packages"] if p["SPDXID"] == sbv.UPSTREAM_ID
            )
            self.assertEqual(
                upstream["checksums"][0]["checksumValue"],
                record["upstream_sha256"].lower(),
            )
            _, tag, _ = purl_parts(upstream["externalRefs"][0]["referenceLocator"])
            self.assertEqual(tag, record["upstream_tag"])
        else:
            source = next(
                p for p in doc["packages"] if p["SPDXID"] == sbv.KEYRING_SOURCE_ID
            )
            self.assertEqual(
                source["checksums"][0]["checksumValue"], record["source_sha256"]
            )


# --- Properties -------------------------------------------------------------


class BuildRecordFuzz(DocumentChecks):
    @given(json_values)
    def test_any_json_value_is_a_document_or_refused(self, value: Any) -> None:
        try:
            doc = build(value)
        except sbv.BuildRecordError:
            return
        self.assert_valid_document(doc, value, [])

    @given(broken_records())
    def test_broken_record_is_refused(self, record: dict) -> None:
        with self.assertRaises(sbv.BuildRecordError):
            build(record)

    @given(any_valid_records, st.text(), arches)
    def test_valid_record_any_depends_gives_valid_document(
        self, record: dict, depends: str, arch: str
    ) -> None:
        doc = build(record, depends, arch)
        self.assert_valid_document(doc, record, sbv.dependency_names(depends))

    @given(realistic_records, depends_fields(), arches)
    def test_realistic_record_lists_every_dependency(
        self, record: dict, depends: tuple[str, list[str]], arch: str
    ) -> None:
        field, names = depends
        doc = build(record, field, arch)
        self.assert_valid_document(doc, record, names)

    @given(any_valid_records, st.text(), arches)
    def test_same_inputs_same_document(
        self, record: dict, depends: str, arch: str
    ) -> None:
        first, second = build(record, depends, arch), build(record, depends, arch)
        for doc in (first, second):
            self.assertRegex(
                doc["creationInfo"]["created"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"
            )
            self.assertTrue(
                doc["documentNamespace"].startswith(sbv.SPDX_NAMESPACE_BASE)
            )
            doc["creationInfo"].pop("created")
        ns_first, ns_second = (
            first.pop("documentNamespace"),
            second.pop("documentNamespace"),
        )
        self.assertNotEqual(ns_first, ns_second, "the namespace must be unique")
        self.assertEqual(ns_first[:-36], ns_second[:-36])
        self.assertEqual(first, second)
        # And the record is not changed by building from it.
        self.assertEqual(
            build(dict(record), depends, arch)["packages"], first["packages"]
        )


class DependsFuzz(unittest.TestCase):
    @given(st.text())
    def test_any_text_gives_clean_unique_names(self, depends: str) -> None:
        names = sbv.dependency_names(depends)
        self.assertEqual(len(names), len(set(names)))
        for name in names:
            self.assertTrue(name)
            self.assertFalse(set(name) & set(",|(:[<"), name)
            self.assertFalse(any(c.isspace() for c in name), name)
        # Idempotent: the names, as a Depends field, give the same names.
        self.assertEqual(sbv.dependency_names(", ".join(names)), names)

    @given(depends_fields())
    def test_well_formed_field_gives_its_names(
        self, depends: tuple[str, list[str]]
    ) -> None:
        field, names = depends
        self.assertEqual(sbv.dependency_names(field), names)

    @given(st.lists(st.text(min_size=1), max_size=20))
    def test_spdx_ids_are_valid_and_unique(self, names: list[str]) -> None:
        ids = sbv.spdx_ids(sbv.DEPENDENCY_ID_PREFIX, names)
        self.assertEqual(len(ids), len(names))
        self.assertEqual(len(set(ids)), len(ids))
        for sid in ids:
            self.assertTrue(SPDX_ID.fullmatch(sid), sid)

    def test_real_depends_field(self) -> None:
        field = "glibc, gcc-libs-glibc, libicu-glibc, openssl-glibc, zlib-glibc"
        self.assertEqual(
            sbv.dependency_names(field),
            ["glibc", "gcc-libs-glibc", "libicu-glibc", "openssl-glibc", "zlib-glibc"],
        )
        self.assertEqual(
            sbv.spdx_ids(sbv.DEPENDENCY_ID_PREFIX, ["libc++", "libc--"]),
            ["SPDXRef-Package-dep-libc--", "SPDXRef-Package-dep-libc---2"],
        )


class CommandLineFuzz(unittest.TestCase):
    def run_main(self, record_bytes: bytes, depends: str = "") -> tuple[Any, Any]:
        """(exit code or None, the written document or None)."""
        with tempfile.TemporaryDirectory() as tmp:
            record, out = Path(tmp, "pkg.build.json"), Path(tmp, "out.json")
            record.write_bytes(record_bytes)
            deb_field, file_sha = fake_dpkg(depends, "aarch64")
            with deb_field, file_sha:
                try:
                    sbv.main(["pkg.deb", str(record), str(out)])
                except SystemExit as e:
                    self.assertFalse(out.exists())
                    return e.code, None
            return None, json.loads(out.read_text(encoding="utf-8"))

    @given(st.binary(max_size=300) | json_values.map(lambda v: json.dumps(v).encode()))
    def test_any_file_is_written_or_refused_in_one_line(self, data: bytes) -> None:
        code, doc = self.run_main(data)
        if doc is None:
            self.assertIsInstance(code, str)
            self.assertTrue(code.startswith("spdx-build-view.py: "), code)
        else:
            self.assertEqual(doc["spdxVersion"], "SPDX-2.3")

    @given(realistic_records, depends_fields())
    def test_valid_record_file_is_written(
        self, record: dict, depends: tuple[str, list[str]]
    ) -> None:
        code, doc = self.run_main(json.dumps(record).encode(), depends[0])
        self.assertIsNone(code)
        names = [
            p["name"]
            for p in doc["packages"]
            if p["SPDXID"].startswith(sbv.DEPENDENCY_ID_PREFIX)
        ]
        self.assertEqual(names, depends[1])

    def test_wrong_argument_count_is_a_usage_error(self) -> None:
        for argv in ([], ["a"], ["a", "b"], ["a", "b", "c", "d"]):
            with self.assertRaises(SystemExit) as e:
                sbv.main(argv)
            self.assertTrue(str(e.exception.code).startswith("usage: "))


if __name__ == "__main__":
    sys.exit(unittest.main())
