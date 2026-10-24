# wpe-webkit-build

Relocatable builds of [WPE WebKit](https://wpewebkit.org) for the Linux
webview of [zkool](https://github.com/hhanh00/zkool2). Ubuntu stopped
packaging WPE after 22.04 and neither nixpkgs nor the Flatpak runtimes carry
it, so this repository compiles it once per release and publishes the result.

## What a release contains

For each of `x86_64` and `aarch64`, built on Ubuntu 24.04 (glibc 2.39, ICU 74):

- `wpe-webkit-<version>-ubuntu24.04-<arch>.tar.xz`: the install prefix,
  extract it anywhere. `lib/` holds `libWPEWebKit-2.0`, `libWPEPlatform-2.0`
  and `libwpe-1.0`, `lib/wpe/wpe-webkit-2.0/` the helper processes,
  `lib/wpe-webkit-2.0/injected-bundle/` the injected bundle, `include/` and
  `lib/pkgconfig/` the development files.
- `.sha256`: checksum to pin in the consumer.
- `.manifest.txt`: versions, configure options, and the host libraries
  `libWPEWebKit-2.0.so` still needs, which a consumer bundles next to it.

Every shared object carries an `$ORIGIN` rpath and the helpers an
`$ORIGIN/../..` rpath, so the tree works from any directory.

## Engine configuration

`cmake-flags.txt` is the single list of configure options, read by both
`build.sh` and `flake.nix`. In short: WPEPlatform headless backend, legacy
libwpe API kept, GPU process with DMA-BUF export, WebGL and image codecs
kept, the whole media stack (GStreamer, video, Web Audio, WebRTC, capture),
speech, gamepad, spellcheck, WebDriver, introspection, documentation and
journald logging off. WOFF2 fonts use FreeType's built-in decoder. The
bubblewrap web-process sandbox is compiled in.

## Patches

- `patches/0001-webkit-exec-path-in-release-builds.patch`: WebKit only honours
  `WEBKIT_EXEC_PATH` and the executable's directory when built in developer
  mode. The patch lifts that guard so a bundle can point WebKit at its own
  helper processes. The compiled-in path stays the fallback.
- `patches/nix-bubblewrap-store-paths.patch`: Nix only. Binds the Nix store
  and the system profile into the sandbox, as nixpkgs does for WebKitGTK.

## Using a release

```sh
curl -fLO https://github.com/hhanh00/wpe-webkit-build/releases/download/<tag>/<tarball>
sha256sum -c <tarball>.sha256
sudo mkdir -p /opt/wpe && sudo tar -C /opt/wpe -xf <tarball>
export PKG_CONFIG_PATH=/opt/wpe/lib/pkgconfig
```

At run time, before the first web view is created, the embedder sets

```
WEBKIT_EXEC_PATH=<bundle>/lib/wpe/wpe-webkit-2.0
WEBKIT_INJECTED_BUNDLE_PATH=<bundle>/lib/wpe-webkit-2.0/injected-bundle
```

and, because the sandbox only sees a fixed set of host directories, adds
`<bundle>/lib` with `webkit_web_context_add_path_to_sandbox()`.

## Cutting a release

Bump `versions.env`, then run the **Build WPE WebKit** workflow with a build
number. It compiles both architectures (two to three hours each) and creates
a non-latest release tagged `wpe-webkit-<version>-<build>`.

## Nix

```sh
nix build github:hhanh00/wpe-webkit-build#wpewebkit
```

The derivation installs to the store, so no relocation is involved; the
sandbox patch above makes the store visible to the web process.

## Local build

```sh
./install-deps-ubuntu.sh
./build.sh --prefix /opt/wpe --out ./dist        # add --configure-only to validate flags
```
