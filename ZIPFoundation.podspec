Pod::Spec.new do |s|
  s.name = 'ZIPFoundation'
  s.version = '0.9.17'
  s.license = 'MIT'
  s.summary = 'Effortless ZIP Handling in Swift'
  s.homepage = 'https://github.com/weichsel/ZIPFoundation'
  s.social_media_url = 'http://twitter.com/weichsel'
  s.authors = { 'Thomas Zoechling' => 'thomas@peakstep.com' }
  s.source = { :git => 'https://github.com/weichsel/ZIPFoundation.git', :tag => s.version }
  s.swift_versions = ['4.0', '4.2', '5.0']

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.11'
  s.tvos.deployment_target = '12.0'
  s.watchos.deployment_target = '2.0'
  s.visionos.deployment_target = '1.0'

  s.source_files = 'Sources/ZIPFoundation/*.swift'
  s.resource = 'Sources/ZIPFoundation/Resources/PrivacyInfo.xcprivacy'
end
