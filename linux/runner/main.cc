#include <stdlib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // NVIDIA's GL driver busy-waits on vblank during buffer swaps by
  // default, burning most of a CPU core whenever anything animates
  // (measured ~45% of a core just letting the pets idle). "usleep"
  // makes the driver sleep-wait instead; a pre-set user value wins.
  setenv("__GL_YIELD", "usleep", /*overwrite=*/0);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
