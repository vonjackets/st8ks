{
  description = "st8ks, a Kubernetes desktop client";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Builds without a tag use the same scheme as the release workflow.
      version = "dev-${self.shortRev or self.dirtyShortRev or "unknown"}";
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          inherit (pkgs) lib stdenv;
          fs = lib.fileset;

          frontend = pkgs.buildNpmPackage {
            pname = "st8ks-frontend";
            inherit version;
            src = fs.toSource {
              root = ./frontend;
              fileset = fs.difference ./frontend (
                fs.unions [
                  (fs.maybeMissing ./frontend/node_modules)
                  (fs.maybeMissing ./frontend/dist)
                  (fs.maybeMissing ./frontend/wailsjs)
                ]
              );
            };
            nodejs = pkgs.nodejs_24;
            npmDeps = pkgs.importNpmLock { npmRoot = ./frontend; };
            npmConfigHook = pkgs.importNpmLock.npmConfigHook;
            installPhase = ''
              runHook preInstall
              cp -r dist $out
              runHook postInstall
            '';
          };

          # Info.plist for the app bundle. build/darwin/Info.plist is a Wails
          # template, so it can't be used as is. The bundle ID matches the
          # release builds.
          infoPlist = pkgs.writeText "Info.plist" ''
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
              <dict>
                <key>CFBundlePackageType</key>
                <string>APPL</string>
                <key>CFBundleName</key>
                <string>st8ks</string>
                <key>CFBundleExecutable</key>
                <string>st8ks</string>
                <key>CFBundleIdentifier</key>
                <string>com.wails.st8ks</string>
                <key>CFBundleVersion</key>
                <string>0.0.0</string>
                <key>CFBundleShortVersionString</key>
                <string>0.0.0</string>
                <key>CFBundleGetInfoString</key>
                <string>A Kubernetes desktop client (${version})</string>
                <key>CFBundleIconFile</key>
                <string>iconfile</string>
                <key>LSMinimumSystemVersion</key>
                <string>10.13.0</string>
                <key>NSHighResolutionCapable</key>
                <string>true</string>
                <key>NSHumanReadableCopyright</key>
                <string>st8ks contributors</string>
              </dict>
            </plist>
          '';

          st8ks = (pkgs.buildGoModule.override { go = pkgs.go_1_27; }) {
            pname = "st8ks";
            inherit version;
            src = fs.toSource {
              root = ./.;
              fileset = fs.unions [
                (fs.fileFilter (f: f.hasExt "go") ./.)
                ./go.mod
                ./go.sum
                ./internal
                ./build
                ./frontend/dist/.gitkeep
              ];
            };

            # hack/update-vendor-hash.sh rewrites this line.
            vendorHash = "sha256-k+SP8N9ICa8xQjasiRDI7Ufs+bBRF3ae8GW4B4WM3B0=";

            subPackages = [ "." ];
            tags = [
              "desktop"
              "production"
            ]
            ++ lib.optional stdenv.hostPlatform.isLinux "webkit2_41";
            ldflags = [
              "-s"
              "-w"
              "-X main.version=${version}"
            ];

            # wails build adds this framework on macOS. The file dialogs need it.
            env = lib.optionalAttrs stdenv.hostPlatform.isDarwin {
              CGO_LDFLAGS = "-framework UniformTypeIdentifiers";
            };

            nativeBuildInputs =
              lib.optionals stdenv.hostPlatform.isLinux [
                pkgs.pkg-config
                pkgs.wrapGAppsHook3
              ]
              ++ lib.optionals stdenv.hostPlatform.isDarwin [
                pkgs.libicns
                pkgs.imagemagick
              ];
            buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
              pkgs.gtk3
              pkgs.webkitgtk_4_1
            ];

            preBuild = ''
              cp -r ${frontend}/. frontend/dist/
              chmod -R u+w frontend/dist
            '';

            # CI runs the tests. Some of them need a network or a cluster.
            doCheck = false;

            postInstall =
              lib.optionalString stdenv.hostPlatform.isLinux ''
                install -Dm644 build/linux/st8ks.desktop $out/share/applications/st8ks.desktop
                install -Dm644 build/appicon.png $out/share/icons/hicolor/1024x1024/apps/st8ks.png
              ''
              + lib.optionalString stdenv.hostPlatform.isDarwin ''
                app=$out/Applications/st8ks.app/Contents
                mkdir -p $app/MacOS $app/Resources
                mv $out/bin/st8ks $app/MacOS/st8ks
                ln -s $app/MacOS/st8ks $out/bin/st8ks
                cp ${infoPlist} $app/Info.plist

                icons=$(mktemp -d)
                for size in 16 32 128 256 512; do
                  magick build/appicon.png -resize ''${size}x''${size} $icons/icon_$size.png
                done
                png2icns $app/Resources/iconfile.icns $icons/*.png
              '';

            meta = {
              description = "A Kubernetes desktop client";
              license = lib.licenses.mit;
              mainProgram = "st8ks";
              platforms = systems;
            };
          };
        in
        {
          inherit frontend st8ks;
          default = st8ks;
        }
      );

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.st8ks}/bin/st8ks";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.go_1_27
            pkgs.nodejs_24
            pkgs.wails
            pkgs.gnumake
          ]
          ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            pkgs.pkg-config
            pkgs.gtk3
            pkgs.webkitgtk_4_1
          ];
        };
      });
    };
}
