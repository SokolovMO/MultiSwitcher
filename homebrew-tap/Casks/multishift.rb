cask "multishift" do
  version "0.3.0,6"
  sha256 "d3ed90ab23ebca9668fb97fe13cff619bc2a69d6f4df0556b07f96df381798cc"

  url "https://sokolovmo.ru/multishift/MultiShift-#{version.csv.first}-#{version.csv.second}-arm64.zip"
  name "MultiShift"
  desc "File conversion and tools for Finder"
  homepage "https://sokolovmo.ru/multishift/"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "MultiShift.app"

  if ENV["HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED"] == "1"
    postflight_steps do
      run "/usr/bin/codesign", args: ["--verify", "--deep", "--strict", "{{appdir}}/MultiShift.app"]
      run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/MultiShift.app"]
    end
  end

  caveats <<~EOS
    This app is not notarized by Apple. To install without quarantine, explicitly use:
      HOMEBREW_MULTI_APPS_ALLOW_UNNOTARIZED=1 brew install --cask SokolovMO/apps/multishift
    Updates are available inside the app and require confirmation.
    Quit the app after current work finishes before a Homebrew upgrade.
    Uninstalling this cask preserves your settings and history.
  EOS
end
