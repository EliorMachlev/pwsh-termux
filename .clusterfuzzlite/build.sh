#!/bin/bash -eu
# Builds the fuzz target into $OUT (compile_python_fuzzer comes from the base
# image). The script under test is copied next to the target as a module the
# packed fuzzer can import; nothing outside the standard library is needed.
cp "$SRC/pwsh-termux/scripts/spdx-build-view.py" "$SRC/pwsh-termux/.clusterfuzzlite/spdx_build_view.py"
compile_python_fuzzer "$SRC/pwsh-termux/.clusterfuzzlite/fuzz_spdx_build_view.py"
