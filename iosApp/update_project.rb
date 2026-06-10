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

# 2. Add PiP Files explicitly
player_group = project.main_group.find_subpath(File.join('iosApp', 'Player'), true)
['MPVPictureInPictureController.swift', 'MPVPlayerViewController+PiP.swift'].each do |file_name|
  unless player_group.files.any? { |f| f.path == file_name }
    file_reference = player_group.new_file(file_name)
    target.source_build_phase.add_file_reference(file_reference)
  end
end
# 3. Link LibTorrent static libs (.a) and libc++.tbd
Dir.glob('Frameworks/LibTorrent/lib/*.a').each do |lib_path|
  # Skip vcpkg's iconv/charset because they shadow Apple's system libiconv.tbd,
  # causing missing _iconv symbols for MPVKit/Libass.
  next if lib_path.end_with?('libiconv.a') || lib_path.end_with?('libcharset.a')

  lib_ref = project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)
end


# Add libc++.tbd for C++ standard library
libcxx = project.new_file('usr/lib/libc++.tbd')
libcxx.source_tree = 'SDKROOT'
target.frameworks_build_phase.add_file_reference(libcxx)

# Add libiconv.tbd (required by MPVKit/Libass since GoTorrent was removed)
libiconv = project.new_file('usr/lib/libiconv.tbd')
libiconv.source_tree = 'SDKROOT'
target.frameworks_build_phase.add_file_reference(libiconv)


# Add System frameworks required by libtorrent on iOS
%w[
  System/Library/Frameworks/SystemConfiguration.framework
  System/Library/Frameworks/Security.framework
  System/Library/Frameworks/CoreFoundation.framework
].each do |fw|
  fw_ref = project.new_file(fw)
  fw_ref.source_tree = 'SDKROOT'
  target.frameworks_build_phase.add_file_reference(fw_ref)
end

# 4. Update Build Settings
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'iosApp-Bridging-Header.h'
  
  header_paths = config.build_settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
  header_paths << '$(SRCROOT)/Frameworks/LibTorrent/include'
  config.build_settings['HEADER_SEARCH_PATHS'] = header_paths.uniq

  lib_paths = config.build_settings['LIBRARY_SEARCH_PATHS'] || ['$(inherited)']
  lib_paths << '$(SRCROOT)/Frameworks/LibTorrent/lib'
  config.build_settings['LIBRARY_SEARCH_PATHS'] = lib_paths.uniq
  
  # For ObjC++
  config.build_settings['ENABLE_STRICT_OBJC_MSGSEND'] = 'YES'
  config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'c++17'
  config.build_settings['CLANG_CXX_LIBRARY'] = 'libc++'
  config.build_settings['OTHER_LDFLAGS'] = ['$(inherited)', '-ObjC']
  
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
