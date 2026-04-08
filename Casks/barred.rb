cask "barred" do
  version "0.1.0"
  sha256 "PLACEHOLDER"

  url "https://github.com/mcclowes/barred/releases/download/v#{version}/Barred.zip"
  name "Barred"
  desc "macOS menu bar manager"
  homepage "https://github.com/mcclowes/barred"

  depends_on macos: ">= :sonoma"

  app "Barred.app"

  zap trash: [
    "~/Library/Preferences/com.barred.app.plist",
  ]
end
