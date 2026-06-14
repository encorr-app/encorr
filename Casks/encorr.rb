cask "encorr" do
  version "2.7.1"
  sha256 "b649195b030add21f3901dabfc90e3f893e08171c51928a7327f19b4ac9150c5"

  url "https://github.com/encorr-app/encorr/releases/download/#{version}/encorr-macos.dmg"
  name "Encorr"
  desc "Modern Plex and Jellyfin client built with Flutter"
  homepage "https://github.com/encorr-app/encorr"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "Encorr.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Encorr.app"],
                   sudo: false
  end

  uninstall quit: "app.encorr.encorr"

  zap trash: [
    "~/Library/Application Support/app.encorr.encorr",
    "~/Library/Caches/app.encorr.encorr",
    "~/Library/HTTPStorages/app.encorr.encorr",
    "~/Library/Preferences/app.encorr.encorr.plist",
    "~/Library/Saved Application State/app.encorr.encorr.savedState",
    "~/Library/WebKit/app.encorr.encorr",
  ]
end
