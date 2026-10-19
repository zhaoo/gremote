Pod::Spec.new do |s|
  s.name = 'gremote_imaging'
  s.version = '1.0.0'
  s.summary = 'GRemote local JPEG imaging core'
  s.homepage = 'https://github.com/zhaoo/gremote'
  s.author = { 'GRemote' => 'https://github.com/zhaoo' }
  s.license = { :type => 'Proprietary' }
  s.source = { :git => 'https://github.com/zhaoo/gremote.git' }
  s.platform = :ios, '14.0'
  s.vendored_frameworks = 'dist/ios/gremote_imaging.xcframework'
end
