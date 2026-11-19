#!/bin/bash -eu
# Builds the fuzz target into $OUT (compile_python_fuzzer comes from the base
# image). The target imports nothing outside the standard library.
compile_python_fuzzer "$SRC/pwsh-termux/.clusterfuzzlite/fuzz_spdx_build_view.py"
