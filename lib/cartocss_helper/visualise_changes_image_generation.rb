# frozen_string_literal: true

require_relative 'visualise_changes_diff_from_images'
require_relative 'git'
require_relative 'renderer_handler'
require_relative 'overpass_query_generator'
require_relative 'util/filehelper'

module CartoCSSHelper
  class VisualDiff
    @@job_pooling = false
    @@jobs = []

    def self.enable_job_pooling
      # it results in avoiding loading the same database mutiple times
      # useful if the same database will be used multiple times (for example the same place in multiple comparisons)
      # use run_jobs function to run jobs
      @@job_pooling = true
    end

    def self.disable_job_pooling
      @@job_pooling = false
    end

    class MapGenerationJob
      attr_reader :filename
      def initialize(filename, latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size, image_size)
        @latitude = latitude
        @longitude = longitude
        @zlevels = zlevels
        @header = header
        @old_branch = old_branch
        @new_branch = new_branch
        @image_size = image_size
        @filename = filename
        @data_source = CartoCSSHelper::VisualDiff::FileDataSource.new(@latitude, @longitude, download_bbox_size, @filename)
      end

      def run_job
        CartoCSSHelper::VisualDiff.visualise_for_given_source(@latitude, @longitude, @zlevels, @header, @new_branch, @old_branch, @image_size, @data_source)
      end

      def print
        puts "#{@filename.gsub(Configuration.get_path_to_folder_for_cache, '#')} [#{@latitude};#{@longitude}], z: #{@zlevels}, text: #{@header}, '#{@old_branch}'->'#{@new_branch}', bbox:#{@download_bbox_size}, #{@image_size}px"
      end
    end

    def self.add_job(filename, latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size, image_size, prefix)
      print prefix
      new_job = MapGenerationJob.new(filename, latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size, image_size)
      new_job.print

      raise "#{filename} does not exists" unless File.exist?(filename)
      raise "#{latitude} is not a number" unless latitude.is_a? Numeric
      raise "#{longitude} is not a number" unless longitude.is_a? Numeric
      raise "#{zlevels} is not a range" unless zlevels.class == Range
      raise "#{header} is not a string" unless header.class == String
      raise "#{new_branch} is not a string" unless new_branch.class == String
      raise "#{old_branch} is not a string" unless old_branch.class == String
      raise "#{download_bbox_size} is not a number" unless download_bbox_size.is_a? Numeric
      raise "#{image_size} is not a integer" unless image_size.is_a? Integer

      @@jobs.push(new_job)
    end

    def self.run_jobs
      new_job_array = []
      return if @@jobs == []
      @@jobs[0].run_job
      for x in 1..@@jobs.length - 1
        if @@jobs[0].filename == @@jobs[x].filename
          # requires loading the same file as just run job
          # it may be safely run without reloading database
          @@jobs[x].run_job
        else
          new_job_array << @@jobs[x].filename
        end
      end
      @@jobs = new_job_array
    end

    def self.shuffle_jobs(seed)
      @@jobs.shuffle!(random: Random.new(seed))
    end

    def self.make_header(tags, type, on_water)
      on_water_string = ''
      on_water_string = ' on water' if on_water
      return "#{VisualDiff.tag_dict_to_string(tags)} #{type}#{on_water_string}"
    end

    def self.visualise_on_synthethic_data(tags, type, on_water, zlevel_range, new_branch, old_branch)
      header = make_header(tags, type, on_water)
      puts "visualise_on_synthethic_data <#{header}> #{old_branch} -> #{new_branch}"
      Git.checkout(old_branch)
      old = VisualDiff.collect_images_for_synthethic_test(tags, type, on_water, zlevel_range)
      Git.checkout(new_branch)
      new = VisualDiff.collect_images_for_synthethic_test(tags, type, on_water, zlevel_range)
      VisualDiff.pack_image_sets old, new, header, new_branch, old_branch, 200
    end

    def self.collect_images_for_synthethic_test(tags, type, on_water, zlevel_range)
      collection = []
      zlevel_range.each do |zlevel|
        scene = Scene.new(tags, zlevel, on_water, type)
        collection.push(ImageForComparison.new(scene.get_image_filename, "z#{zlevel}"))
      end
      return collection
    end

    class FileDataSource
      attr_reader :download_bbox_size, :data_filename
      def initialize(latitude, longitude, download_bbox_size, filename)
        @download_bbox_size = download_bbox_size
        @latitude = latitude
        @longitude = longitude
        @data_filename = filename
        @loaded = false
      end

      def load
        unless @loaded
          DataFileLoader.load_data_into_database(@data_filename)
          puts "\tgenerating images"
          @loaded = true
        end
      end

      def get_timestamp
        return GenericCachedDownloader.new.get_cache_timestamp(@data_filename)
      end
    end

    def self.visualise_on_overpass_data(tags, type, wanted_latitude, wanted_longitude, zlevels, new_branch, old_branch = 'master')
      # special support for some tag values - see CartoCSSHelper::OverpassQueryGenerator.turn_list_of_tags_in_overpass_filter for details
      header_prefix = "#{VisualDiff.tag_dict_to_string(tags)} #{type} [#{wanted_latitude}, #{wanted_longitude}] -> "
      target_location = '[?, ?]'
      header_sufix = " #{old_branch}->#{new_branch} #{zlevels}"
      puts "visualise_on_overpass_data <#{header_prefix}#{header_sufix}> #{old_branch} -> #{new_branch}"
      begin
        latitude, longitude = OverpassQueryGenerator.locate_element_with_given_tags_and_type tags, type, wanted_latitude, wanted_longitude
        target_location = "[#{latitude}, #{longitude}]"
      rescue OverpassQueryGenerator::NoLocationFound, OverpassDownloader::OverpassRefusedResponse
        puts 'No nearby instances of tags and tag is not extremely rare - no generation of nearby location and wordwide search was impossible. No diff image will be generated for this location.'
        return false
      end
      visualise_for_location(latitude, longitude, zlevels, header_prefix + target_location + header_sufix, new_branch, old_branch)
      return true
    end

    def self.visualise_for_location(latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size = 0.4, image_size = 400)
      filename = OverpassQueryGenerator.get_file_with_downloaded_osm_data_for_location(latitude, longitude, download_bbox_size)
      visualise_for_location_from_file(filename, latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size, image_size)
    end

    def self.visualise_for_location_from_file(filename, latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size = 0.4, image_size = 400)
      prefix = ''
      prefix = 'pool <- ' if @@job_pooling
      add_job(filename, latitude, longitude, zlevels, header, new_branch, old_branch, download_bbox_size, image_size, prefix)
      run_jobs unless @@job_pooling
    end

    def self.visualise_for_given_source(latitude, longitude, zlevels, header, new_branch, old_branch, image_size, source)
      Git.checkout old_branch
      old = VisualDiff.collect_images_for_real_data_test(latitude, longitude, zlevels, source, image_size)
      Git.checkout new_branch
      new = VisualDiff.collect_images_for_real_data_test(latitude, longitude, zlevels, source, image_size)
      VisualDiff.pack_image_sets old, new, header, new_branch, old_branch, image_size
    end

    def self.get_render_bbox_size(zlevel, wanted_image_size, latitude)
      longitude_equator_rendered_length_in_pixels = 256 * 2**zlevel
      longitude_size = 360 * wanted_image_size.to_f / longitude_equator_rendered_length_in_pixels
      latitude_size = longitude_size * Math.cos(latitude * Math::PI / 180)
      return [latitude_size, longitude_size]
    end

    def self.collect_images_for_real_data_test(latitude, longitude, zlevels, source, image_size = 400)
      collection = []
      zlevels.each do |zlevel|
        render_bbox_size = VisualDiff.get_render_bbox_size(zlevel, image_size, latitude)
        filename = "#{latitude} #{longitude} #{zlevel}zlevel #{image_size}px #{source.get_timestamp} #{source.download_bbox_size}.png"
        unless RendererHandler.image_available_from_cache(latitude, longitude, zlevel, render_bbox_size, image_size, filename)
          source.load
        end
        file_location = RendererHandler.request_image_from_renderer(latitude, longitude, zlevel, render_bbox_size, image_size, filename)
        collection.push(ImageForComparison.new(file_location, "z#{zlevel}"))
      end
      return collection
    end

    def self.pack_image_sets(old, new, header, new_branch, old_branch, image_size)
      old_branch = FileHelper.make_string_usable_as_filename(old_branch)
      new_branch = FileHelper.make_string_usable_as_filename(new_branch)
      header_for_filename = FileHelper.make_string_usable_as_filename(header)
      filename_sufix = "#{old_branch} -> #{new_branch}"
      filename = CartoCSSHelper::Configuration.get_path_to_folder_for_output + "#{header_for_filename} #{filename_sufix} #{image_size}px #{RendererHandler.renderer_marking}.png"
      diff = FullSetOfComparedImages.new(old, new, header, filename, image_size)
      diff.save
    end

    def self.tag_dict_to_string(dict)
      return OverpassQueryGenerator.turn_list_of_tags_in_overpass_filter(dict)
    end
  end
end
