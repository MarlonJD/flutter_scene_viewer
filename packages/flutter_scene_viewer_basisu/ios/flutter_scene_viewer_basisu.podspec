Pod::Spec.new do |s|
  s.name             = 'flutter_scene_viewer_basisu'
  s.version          = '0.1.0-alpha.0'
  s.summary          = 'Optional native BasisU/KTX2 transcoder plugin for flutter_scene_viewer.'
  s.description      = <<-DESC
Optional native BasisU/KTX2 transcoder plugin for flutter_scene_viewer.
  DESC
  s.homepage         = 'https://example.invalid/flutter_scene_viewer_basisu'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'marlonjd' => 'marlonjd@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.preserve_paths   = 'third_party/basis_universal/LICENSE',
                       'third_party/basis_universal/NOTICE',
                       'third_party/basis_universal/README.md',
                       'third_party/basis_universal/transcoder/*.{h,cpp}',
                       'third_party/basis_universal/transcoder/*.{inc,inl}',
                       'third_party/basis_universal/zstd/*.{h,c}',
                       'third_party/basis_universal/zstd/LICENSE'
  s.public_header_files = 'Classes/FlutterSceneViewerBasisuPlugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) BASISD_SUPPORT_KTX2=1 BASISD_SUPPORT_KTX2_ZSTD=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/third_party/basis_universal/transcoder" "${PODS_TARGET_SRCROOT}/third_party/basis_universal/zstd"'
  }
end
