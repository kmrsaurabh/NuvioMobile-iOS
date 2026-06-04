require 'xcodeproj'
require 'fileutils'

project_path = 'iosApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

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

# 2. Add C++ Engine Files
bridge_h = project.new_file('iosApp/TorrentEngine/cpp/LibtorrentBridge.h')
bridge_mm = project.new_file('iosApp/TorrentEngine/cpp/LibtorrentBridge.mm')
server_swift = project.new_file('iosApp/TorrentEngine/cpp/LibtorrentHTTPServer.swift')

# Add to compile phase
compile_phase = target.source_build_phase
compile_phase.add_file_reference(bridge_mm)
compile_phase.add_file_reference(server_swift)

# 3. Link LibTorrent static libs (.a) and libc++.tbd
Dir.glob('Frameworks/LibTorrent/lib/*.a').each do |lib_path|
  lib_ref = project.new_file(lib_path)
  target.frameworks_build_phase.add_file_reference(lib_ref)
end

# Add libc++.tbd for C++ standard library
libcxx = project.new_file('usr/lib/libc++.tbd')
libcxx.source_tree = 'SDKROOT'
target.frameworks_build_phase.add_file_reference(libcxx)

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
end

project.save
puts "Successfully updated Xcode project for C++ Libtorrent Engine!"
