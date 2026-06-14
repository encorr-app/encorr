cask "encorr" do
  version "2.6.0"
  sha256 "e408fe84c07e0ff4a2f1a78e8dcfc418233c66ca98c79028a7b099499307a59e"

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
