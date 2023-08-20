#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ffigen_app.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'recovery'
  s.version          = '0.0.1'
  s.summary          = 'Library for key recovery'
  s.description      = <<-DESC
Binding for crapto1 key recovery library for Mifare Classic
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :type => 'GNU GPLv3',:file => '../../LICENSE' }
  s.author           = { 'Foxushka' => 'fox@localhost' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
