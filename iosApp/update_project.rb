require 'xcodeproj'
require 'fileutils'

project_path = 'iosApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'iosApp' }

# 1. Remove GoTorrent
project.frameworks_group.files.each do |f|
  if f.path == 'Frameworks/GoTorrent.xcframework' || f.name == 'GoTorrent.xcframework'
    f.remove_from_project
  end
end
target.frameworks_build_phase.files.each do |f|
  if f.file_ref && f.file_ref.name == 'GoTorrent.xcframework'
    f.remove_from_project
  end
end
target.build_phases.each do |phase|
  if phase.isa == 'PBXCopyFilesBuildPhase' && phase.name == 'Embed Frameworks'
    phase.files.each do |f|
      if f.file_ref && f.file_ref.name == 'GoTorrent.xcframework'
        f.remove_from_project
      end
    end
  end
end

# 2. Add C++ Engine Files (skipped because Xcode 16 Synchronized Groups will pick them up automatically)

# 3. Link LibTorrent static libs and system frameworks via Build Settings
# Avoid project.new_file because xcodeproj gem crashes on PBXFileSystemSynchronizedRootGroup

# 4. Update Build Settings
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'iosApp-Bridging-Header.h'
  
  header_paths = config.build_settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
  header_paths << '$(SRCROOT)/Frameworks/LibTorrent/include'
  config.build_settings['HEADER_SEARCH_PATHS'] = header_paths.uniq

  lib_paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || ['$(inherited)']
  lib_paths << '$(SRCROOT)/Frameworks/LibTorrent/lib'
  config.build_settings['LIBRARY_SEARCH_PATHS'] = lib_paths.uniq
  
  # For ObjC++ and linking C++ static libraries
  config.build_settings['ENABLE_STRICT_OBJC_MSGSEND'] = 'YES'
  config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
  config.build_settings['CLANG_CXX_LIBRARY'] = 'libc++'
  
  ldflags = config.build_settings['OTHER_LDFLAGS'] || ['$(inherited)']
  ldflags += [
    '-ObjC',
    '-ltorrent-rasterbar',
    '-lboost_chrono',
    '-lboost_container',
    '-lboost_context',
    '-lboost_date_time',
    '-lboost_random',
    '-lcrypto',
    '-lssl',
    '-lc++',
    '-liconv',
    '-framework', 'SystemConfiguration',
    '-framework', 'Security',
    '-framework', 'CoreFoundation'
  ]
  config.build_settings['OTHER_LDFLAGS'] = ldflags.uniq
  
  # Crucial for ABI compatibility with vcpkg libtorrent 2.0.11 compilation
  config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = [
    '$(inherited)',
    'TORRENT_ABI_VERSION=3',
    'TORRENT_NO_DEPRECATE=1',
    'TORRENT_USE_LIBCRYPTO=1'
  ]
end

project.save
puts "Successfully updated Xcode project for C++ Libtorrent Engine!"
