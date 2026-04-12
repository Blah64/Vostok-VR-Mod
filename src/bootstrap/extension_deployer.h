#pragma once

namespace rtv_vr::bootstrap {

/// Copies override.cfg, .gdextension, and GDExtension DLL to the exe directory.
bool deploy_extension_files();

/// Removes previously deployed files from the exe directory.
void cleanup_extension_files();

} // namespace rtv_vr::bootstrap
