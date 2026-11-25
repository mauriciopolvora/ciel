#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_args=(test)
test_swiftc="$(xcrun --find swiftc)"
test_toolchain_usr="$(dirname "$(dirname "$test_swiftc")")"
test_macro_library="$test_toolchain_usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
# WARNING: some Command Line Tools builds ship Testing.framework without its macro plugin, so load the bundled one.
if [[ "$test_swiftc" == */CommandLineTools/usr/bin/swiftc && -f "$test_macro_library" ]]; then
    test_args+=(-Xswiftc -load-plugin-library -Xswiftc "$test_macro_library")
fi
swift "${test_args[@]}" "$@"
