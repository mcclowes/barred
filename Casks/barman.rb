cask "barman" do
  version "0.1.0"
  sha256 "PLACEHOLDER"

  url "https://github.com/mcclowes/barman/releases/download/v#{version}/Barman.zip"
  name "Barman"
  desc "macOS menu bar manager"
  homepage "https://github.com/mcclowes/barman"

  depends_on macos: ">= :sonoma"

  app "Barman.app"

  zap trash: [
    "~/Library/Preferences/com.barman.app.plist",
  ]
end
