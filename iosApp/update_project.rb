require 'xcodeproj'

project_path = 'iosApp.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app target
target = project.targets.find { |t| t.name == 'iosApp' }

# Find the Player group
player_group = project.main_group.find_subpath(File.join('iosApp', 'Player'), true)

# Files to ensure are added
files_to_add = [
  'MPVPictureInPictureController.swift',
  'MPVPlayerViewController+PiP.swift'
]

files_to_add.each do |file_name|
  file_path = File.join('iosApp', 'Player', file_name)
  
  # Check if file is already in the project
  unless player_group.files.any? { |f| f.path == file_name }
    puts "Adding #{file_name} to Xcode project..."
    file_reference = player_group.new_file(file_name)
    target.source_build_phase.add_file_reference(file_reference)
  else
    puts "#{file_name} is already in the project."
  end
end

project.save
puts "Xcode project updated successfully."
