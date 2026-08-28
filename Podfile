MACOS_DEPLOYMENT_TARGET = "26.0"

platform :osx, MACOS_DEPLOYMENT_TARGET

source 'https://github.com/MacDownApp/cocoapods-specs.git'  # Patched libraries.
source 'https://cdn.cocoapods.org/'

project 'MacDown.xcodeproj'

inhibit_all_warnings!

target "MacDown" do
  pod 'handlebars-objc', '~> 1.4'
  pod 'hoedown', '~> 3.0.7', :inhibit_warnings => false
  pod 'JJPluralForm', '~> 2.1'
  pod 'LibYAML', '~> 0.1'
  pod 'M13OrderedDictionary', '~> 1.1'
  pod 'MASPreferences', '~> 1.3'

  # `~> 0.4` already resolves to 0.5 (see Podfile.lock), and this is pure
  # NSUserDefaults persistence with no UI, so the baseline bump is a no-op.
  pod 'PAPreferences', '~> 0.4'
end

target "MacDownTests" do
  pod 'PAPreferences', '~> 0.4'
end

target "macdown-cmd" do
  pod 'GBCli', '~> 1.1'
end

# Each pod inherits the deployment target declared in its own podspec, which
# for these is 10.6-10.8. Xcode 27 refuses to build anything below 12.0, so
# pin every pod target to the app's own baseline.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = MACOS_DEPLOYMENT_TARGET
    end
  end
end
