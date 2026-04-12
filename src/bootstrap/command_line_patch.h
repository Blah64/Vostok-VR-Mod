#pragma once

namespace rtv_vr::bootstrap {

/// Hooks GetCommandLineW to append "--xr-mode on" to the process command line.
bool install_command_line_patch();

/// Removes the GetCommandLineW hook.
void remove_command_line_patch();

} // namespace rtv_vr::bootstrap
