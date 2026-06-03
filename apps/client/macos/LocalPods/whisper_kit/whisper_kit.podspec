Pod::Spec.new do |s|
  s.name             = 'whisper_kit'
  s.version          = '0.3.1'
  s.summary          = 'whisper_kit macOS stub'
  s.homepage         = 'https://github.com/CodeSagePath/whisper_kit'
  s.license          = { :type => 'MIT' }
  s.author           = { 'whisper_kit' => 'https://github.com/CodeSagePath/whisper_kit' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
