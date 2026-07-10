#include <stdlib.h>

#include <gdk/gdk.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // NVIDIA's GL driver busy-waits on vblank during buffer swaps by
  // default, burning most of a CPU core whenever anything animates
  // (measured ~45% of a core just letting the pets idle). "usleep"
  // makes the driver sleep-wait instead; a pre-set user value wins.
  setenv("__GL_YIELD", "usleep", /*overwrite=*/0);

  // Prefer XWayland over native Wayland: GTK3's GL compositing on
  // Wayland copies every frame through the CPU (gdk_cairo_draw_from_gl
  // readback — full-window pixman blits in the profile), which more
  // than doubled CPU while anything animated (measured 112% → 44% of
  // a core playing, 62% → 20% idle on NVIDIA + KWin). The trailing
  // "*" still allows native Wayland when no X server exists; an
  // explicit GDK_BACKEND from the user wins over both.
  gdk_set_allowed_backends("x11,*");

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
