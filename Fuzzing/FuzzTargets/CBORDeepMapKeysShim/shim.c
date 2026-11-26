/* A C executable supplies libFuzzer's entry points; see CBORDecodeShim. */
#include <inttypes.h>
#include <stddef.h>

int swift_fuzz_run(const uint8_t *data, size_t size);
void swift_fuzz_initialize(void);

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc;
  (void)argv;
  swift_fuzz_initialize();
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  return swift_fuzz_run(data, size);
}
