# encoding: UTF-8
require 'fileutils'

def get_max_z
	return 22
end

def get_style_path
	return ENV['HOME']+'/Documents/OSM/tilemill/osm-carto/' #TODO - stop hardcoding this
end

def get_path_to_folder_for_temporary_files
	#TODO - stop hardcoding this
	location = ENV['HOME']+"/Documents/OSM/tilemill/CartoCSSHelper/tmp/#{$commit}/"
	FileUtils::mkdir_p location
	return location
end