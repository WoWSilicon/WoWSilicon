# DXVK builds used by WoWSilicon

WoWSilicon bundles separate Direct3D 9 builds for the two Vulkan drivers:

- `Patching/d9vk/d3d9.dll` is the stable macOS D9VK 1.10.3 build for MoltenVK.
- `Patching/dxvk-kosmickrisp/d3d9.dll` is the stripped patched DXVK 3.0.2
  build for KosmicKrisp.

WoWSilicon installs the matching file as the game's `d3d9.dll` before launch.

The experimental DXVK 3.0.2 source tree lives at:

    /Users/marco/VSCode/dxvk-kosmickrisp

Its WoWSilicon patch is also tracked as
`tools/wine-runtime/dxvk-3.0.2-kosmickrisp.patch`. Build instructions are in
the source checkout's `KOSMICKRISP_BUILD.md`.

## Compact release packaging

From the DXVK checkout, after building D3D9:

```sh
cp build.w32/src/d3d9/d3d9.dll \
  ../WoWSilicon/Sources/WoWSiliconSwift/Resources/Patching/dxvk-kosmickrisp/d3d9.dll
i686-w64-mingw32-strip --strip-all \
  ../WoWSilicon/Sources/WoWSiliconSwift/Resources/Patching/dxvk-kosmickrisp/d3d9.dll
make -C ../WoWSilicon bundle
```