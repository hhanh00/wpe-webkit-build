{
  description = "WPE WebKit for the zkool Linux webview, built with the same options as the Ubuntu tarballs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      versions =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./versions.env);
          kv = builtins.filter (l: l != "" && !(nixpkgs.lib.hasPrefix "#" l)) lines;
          pair = l: let p = nixpkgs.lib.splitString "=" l; in { name = builtins.head p; value = builtins.elemAt p 1; };
        in builtins.listToAttrs (map pair kv);

      cmakeFlags = builtins.filter
        (l: l != "" && !(nixpkgs.lib.hasPrefix "#" l))
        (nixpkgs.lib.splitString "\n" (builtins.readFile ./cmake-flags.txt));
    in
    {
      packages = forAll (pkgs:
        let
          wpewebkit = pkgs.clangStdenv.mkDerivation {
            pname = "wpewebkit";
            version = versions.WPE_VERSION;

            src = pkgs.fetchurl {
              url = "https://wpewebkit.org/releases/wpewebkit-${versions.WPE_VERSION}.tar.xz";
              sha256 = versions.WPE_SHA256;
            };

            outputs = [ "out" "dev" ];
            separateDebugInfo = true;

            patches = [
              ./patches/0001-webkit-exec-path-in-release-builds.patch
              (pkgs.replaceVars ./patches/nix-bubblewrap-store-paths.patch {
                inherit (builtins) storeDir;
                inherit (pkgs.addDriverRunpath) driverLink;
              })
            ];

            nativeBuildInputs = with pkgs; [
              bison cmake flex gettext gperf ninja perl perl.pkgs.FileCopyRecursive
              pkg-config python3 ruby unifdef glib # gdbus-codegen
            ];

            buildInputs = with pkgs; [
              libwpe libsoup_3 glib icu libxml2 libxslt sqlite harfbuzzFull freetype fontconfig
              libjpeg libpng libwebp libavif libjxl lcms2 libepoxy libGL libgbm libdrm
              libxkbcommon libgcrypt libgpg-error libtasn1 hyphen libsecret libseccomp
              expat zlib
            ];

            inherit cmakeFlags;
            # Nix-specific: sandbox helper paths and no lld wrapper games.
            preConfigure = ''
              cmakeFlagsArray+=(
                "-DBWRAP_EXECUTABLE=${pkgs.lib.getExe pkgs.bubblewrap}"
                "-DDBUS_PROXY_EXECUTABLE=${pkgs.lib.getExe pkgs.xdg-dbus-proxy}"
              )
            '';

            postPatch = "patchShebangs .";
            requiredSystemFeatures = [ "big-parallel" ];

            meta = with pkgs.lib; {
              description = "WPE WebKit, headless WPEPlatform backend, media stack disabled";
              homepage = "https://wpewebkit.org";
              license = with licenses; [ bsd2 lgpl21Plus ];
              platforms = systems;
            };
          };
        in
        {
          inherit wpewebkit;
          libwpe = pkgs.libwpe;
          default = wpewebkit;
        });
    };
}
