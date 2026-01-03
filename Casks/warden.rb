cask "warden" do
  version "0.9.2"
  sha256 "d0b8efe81a403b4114a7d19b0da51c58d17f861709be031f400c389dfa81ee5b"

  url "https://github.com/SidhuK/WardenApp/releases/download/v#{version}/Warden.zip",
      verified: "github.com/SidhuK/WardenApp/"
  name "Warden"
  desc "Native macOS AI chat client supporting 10+ providers"
  homepage "https://github.com/SidhuK/WardenApp"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Not notarized - users may need to right-click > Open on first launch
  # or run: xattr -cr /Applications/Warden.app

  app "Warden.app"

  zap trash: [
    "~/Library/Application Support/Warden",
    "~/Library/Preferences/com.SidhuK.Warden.plist",
    "~/Library/Caches/com.SidhuK.Warden",
    "~/Library/Saved Application State/com.SidhuK.Warden.savedState",
  ]
end
