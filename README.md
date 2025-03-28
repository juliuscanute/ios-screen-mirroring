xcodebuild clean build-for-testing \
  -project WebDriverAgent.xcodeproj \
  -derivedDataPath appium_wda_ios \
  -scheme WebDriverAgentRunner \
  -destination "generic/platform=iOS" \
  ARCHS=arm64