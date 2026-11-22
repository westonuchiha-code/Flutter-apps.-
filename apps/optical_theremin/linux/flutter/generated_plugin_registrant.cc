//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <light_capture/light_capture_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) light_capture_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "LightCapturePlugin");
  light_capture_plugin_register_with_registrar(light_capture_registrar);
}
