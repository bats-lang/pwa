/* Bridge runtime forward declarations for WASM builds */
#ifndef _WASM_BRIDGE_STUBS_H
#define _WASM_BRIDGE_STUBS_H
void bats_bridge_stash_set_int(int slot, int v);
int bats_bridge_stash_get_int(int slot);
void bats_measure_set(int slot, int v);
int bats_bridge_measure_get(int slot);
void bats_listener_set(int id, void *cb);
void *bats_listener_get(int id);
#endif
