#!/bin/bash
# Build WASM for the PWA example.
# Works around bats compiler issues:
# 1. #target wasm blocks need separate patsopt pass
# 2. do_build_wasm doesn't run patsopt
# 3. do_build_wasm doesn't link namespaced dep .o files
set -e

REPO="${1:?usage: build-wasm.sh <repository-path>}"
shift
EXTRA_ARGS="$*"
BATS="${BATS:-bats}"
export PATSHOME="${PATSHOME:-$HOME/.bats/ats2}"

# Step 1: Run bats build --only native to preprocess and run patsopt
# (will fail at link since pwa-web is wasm-only, that's expected)
"$BATS" build --only native --repository "$REPO" $EXTRA_ARGS 2>&1 || true

# Step 2: Remove cached .sats/.dats for namespaced deps to force
# re-preprocessing with wasm target
find build/bats_modules/wasm.bats-packages.dev/ \
  \( -name "*.sats" -o -name "*.dats" -o -name "*_dats.c" \) \
  -delete 2>/dev/null || true

# Step 3: Run bats build --only wasm to re-preprocess with wasm target
# (this creates .dats with #target wasm blocks included)
"$BATS" build --only wasm --repository "$REPO" $EXTRA_ARGS 2>&1

# Step 4: Run patsopt on all re-preprocessed .dats files
for dats in build/bats_modules/wasm.bats-packages.dev/*/src/*.dats; do
  base=$(basename "$dats" .dats)
  out="${dats%%.dats}_dats.c"
  "$PATSHOME/bin/patsopt" -o "$out" \
    -IATS build -IATS build/src -IATS build/bats_modules \
    -d "$dats"
done

# Step 5: Compile all _dats.c to WASM .o (excluding native-only binaries)
for c_file in $(find build/ -name "*_dats.c" ! -name "build-pwa_dats.c" ! -name "_bats_entry_build-pwa*"); do
  o_file="${c_file%.c}.o"
  clang --target=wasm32 -O2 -nostdlib -ffreestanding -fvisibility=default \
    -D_ATS_CCOMP_HEADER_NONE_ -D_ATS_CCOMP_EXCEPTION_NONE_ \
    -D_ATS_CCOMP_PRELUDE_NONE_ -D_ATS_CCOMP_RUNTIME_NONE_ \
    -D_BRIDGE_RUNTIME_DEFINED \
    -include build/_bats_wasm_runtime.h \
    -I build/_bats_wasm_stubs \
    -Wno-implicit-function-declaration -Wno-int-conversion \
    -c -o "$o_file" "$c_file"
done

# Step 6: Link all WASM .o files
mkdir -p dist/wasm
wasm-ld --no-entry --allow-undefined --lto-O2 \
  -z stack-size=1048576 --initial-memory=16777216 --max-memory=268435456 \
  --export=mainats_0_void --export=malloc \
  --export=bats_on_event --export=bats_timer_fire \
  --export=bats_idb_fire --export=bats_idb_fire_get \
  --export=bats_measure_set --export=bats_on_fetch_complete \
  --export=bats_on_file_open --export=bats_on_decompress_complete \
  --export=bats_bridge_stash_set_int --export=bats_bridge_stash_get_int \
  --export=bats_listener_get --export=bats_on_popstate \
  --export=bats_on_clipboard_complete --export=bats_on_clipboard_read_complete \
  --export=bats_on_permission_result --export=bats_on_push_subscribe \
  --export=bats_on_media_change \
  -o dist/wasm/app.wasm \
  build/_bats_wasm_runtime.o \
  $(find build/ -name "*_dats.o" -type f ! -name "build-pwa_dats.o" ! -path "build/_bats_entry_build-pwa*" | sort)

echo "Built: dist/wasm/app.wasm"
