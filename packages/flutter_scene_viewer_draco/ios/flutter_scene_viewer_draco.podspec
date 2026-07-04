Pod::Spec.new do |s|
  s.name             = 'flutter_scene_viewer_draco'
  s.version          = '0.1.0-alpha.0'
  s.summary          = 'Optional native Draco decoder plugin for flutter_scene_viewer.'
  s.description      = <<-DESC
Optional native Draco decoder plugin for flutter_scene_viewer. The root package
stays pure Dart; apps opt in when they need KHR_draco_mesh_compression.
                       DESC
  s.homepage         = 'https://github.com/your-org/flutter_scene_viewer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter_scene_viewer' => 'maintainers@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.exclude_files    = [
    'third_party/draco/src/draco/**/*_test.cc',
    'third_party/draco/src/draco/core/draco_test_utils.cc',
    'third_party/draco/src/draco/core/draco_test_utils.h',
    'third_party/draco/src/draco/core/draco_test_base.h'
  ]
  s.preserve_paths   = [
    'third_party/draco/AUTHORS',
    'third_party/draco/LICENSE',
    'third_party/draco/README.md'
  ]
  s.public_header_files = 'Classes/FlutterSceneViewerDracoPlugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/third_party/draco/src"'
  }
end
