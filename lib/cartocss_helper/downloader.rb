# encoding: UTF-8
require 'rest-client'
require 'digest/sha1'
require 'sys/filesystem'


module CartoCSSHelper
  class Downloader
    def self.get_file_with_downloaded_osm_data_for_location(latitude, longitude, size)
      query = get_query_to_download_data_around_location(latitude, longitude, size)
      return get_overpass_query_results_file_location(query, "download data for #{latitude} #{longitude} (#{size})")
    end


    def self.download_osm_data_for_location(latitude, longitude, size, accept_cache=true)
      filename = CartoCSSHelper::Configuration.get_path_to_folder_for_cache + "#{latitude} #{longitude} #{size}.osm"
      if File.exists?(filename)
        if accept_cache
          return filename
        end
        File.delete(filename)
      end
      query = get_query_to_download_data_around_location(latitude, longitude, size)
      text = get_overpass_query_results(query, "download data for #{latitude} #{longitude} (#{size})")
      file = File.new(filename, 'w')
      file.write text
      file.close
      return filename
    end

    def self.get_query_to_download_data_around_location(latitude, longitude, size)
      min_latitude = latitude - size.to_f/2
      max_latitude = latitude + size.to_f/2
      min_longitude = longitude - size.to_f/2
      max_longitude = longitude + size.to_f/2
      bb = "#{min_latitude},#{min_longitude},#{max_latitude},#{max_longitude}"
      query = "[timeout:#{Downloader.get_allowed_timeout_in_seconds}];"
      query += "\n"
      query += "(node(#{bb});<;);"
      query += "\n"
      query += 'out meta;'
      query += "\n"
      query += '/*'
      query += "\nbbox size: #{size}"
      query += "\nhttp://www.openstreetmap.org/#map=17/#{latitude}/#{longitude}"
      query += "\n"
      query += '*/'
      query += "\n"
      return query
    end

    def self.locate_element_with_given_tags_and_type(tags, type, latitude, longitude)
      max_range_in_km_for_radius = 1600

      #special support for following tag values:  :any_value
      range = 10*1000
      loop do
        list = Downloader.get_overpass_query_results(Downloader.get_query_to_get_location(tags, type, latitude, longitude, range), "find #{tags} within #{range/1000}km from #{latitude}, #{longitude}")
        if list.length != 0
          return self.list_returned_by_overpass_to_a_single_location(list)
        end
        range=range+[2*range, 200000].min
        if range >= max_range_in_km_for_radius*1000
          list = Downloader.get_overpass_query_results(Downloader.get_query_to_get_location(tags, type, latitude, longitude, :infinity), "find #{tags} across the world")
          if list.length != 0
            return self.list_returned_by_overpass_to_a_single_location(list)
          else
            raise 'failed to find such location'
          end
        end
      end
    end

    def self.list_returned_by_overpass_to_a_single_location(list)
      list = list.match(/((|-)[\d\.]+)\s+((|-)[\d\.]+)/).to_a
      lat = Float(list[1])
      lon = Float(list[3])
      return lat, lon
    end

    def self.get_query_to_get_location(tags, type, latitude, longitude, range)
      #special support for following tag values:  :any_value
      locator = "[timeout:#{Downloader.get_allowed_timeout_in_seconds}][out:csv(::lat,::lon;false)];"
      locator += "\n"
      if type == 'closed_way'
        type = 'way'
      end
      locator += Downloader.get_query_element_to_get_location(tags, latitude, longitude, type, range)
      locator +='out center;'
      locator += "\n"
      locator += '/*'
      range_string = ''
      if range == :infinity
        range_string = 'infinity'
      else
        range_string = "#{range/1000}km"
      end
      locator += "\nrange: #{range_string}"
      locator += "\nhttp://www.openstreetmap.org/#map=17/#{latitude}/#{longitude}"
      locator += "\n"
      locator += '*/'
      locator += "\n"
      return locator
    end

    def self.get_query_element_to_get_location(tags, latitude, longitude, type, range)
      #special support for following tag values:  :any_value
      #TODO - escape value with quotation signs in them
      element="(#{type}"
      element += "\n"
      tags.each {|tag|
        if tag[1] == :any_value
          element+="\t['#{tag[0]}']"
        else
          element+="\t['#{tag[0]}'='#{tag[1]}']"
        end
        element += "\n"
      }
      if range != :infinity
        element+="\t(around:#{range},#{latitude},#{longitude});"
        element += "\n"
      end
      element+=');'
      element += "\n"
      return element
    end

    def self.get_overpass_query_results_file_location(query, description, debug=false)
      filename = get_query_cache_filename(query)
      get_overpass_query_results(query, description, debug)
      return filename
    end

    def self.get_overpass_query_results(query, description, debug=false)
      cached = get_overpass_query_results_from_cache(query)
      if cached == ''
        raise OverpassRefusedResponse
      end
      return cached unless cached == nil

      check_for_free_space

      puts 'Running Overpass query (connection initiated on ' + Time.now.to_s + ') ' + description
      if debug
        puts query
        puts
      end
      begin
        cached = Downloader.run_overpass_query query
      rescue OverpassRefusedResponse
        write_to_cache(query, '')
        raise OverpassRefusedResponse
      end
      write_to_cache(query, cached)
      return cached
    end

    def self.write_to_cache(query, response)
      file = File.new(get_query_cache_filename(query), 'w')
      file.write response
      file.close
    end

    def self.get_timestamp_of_file(timestamp_filename)
      if !File.exists?(timestamp_filename)
        return nil
      end
      f = File.new(timestamp_filename)
      timestamp = f.mtime.to_i
      f.close
      return timestamp
    end

    def self.get_overpass_query_results_from_cache(query)
      query_cache_filename = get_query_cache_filename(query)
      if File.exists?(query_cache_filename)
        file = File.new(query_cache_filename)
        cached = file.read
        file.close
        return cached
      end
      return nil
    end

    def self.get_query_cache_filename(query)
      # noinspection RubyResolve
      hash = Digest::SHA1.hexdigest query
      query_cache_filename = CartoCSSHelper::Configuration.get_path_to_folder_for_overpass_cache + hash + '_query.cache'
      return query_cache_filename
    end

    def self.check_for_free_space
      if not_enough_free_space
        attempt_cleanup
        if not_enough_free_space
          raise 'less than 2GB of free space on disk with cache folder'
        end
      end
    end

    def self.not_enough_free_space
      minimum_gb = 2
      return get_available_space_for_cache_in_gb < minimum_gb
    end

    def self.get_available_space_for_cache_in_gb
      stat = Sys::Filesystem.stat(CartoCSSHelper::Configuration.get_path_to_folder_for_cache)
      return stat.block_size * stat.blocks_available / 1024 / 1024 / 1024
    end

    def self.attempt_cleanup
      if not_enough_free_space
        delete_large_overpass_caches
      end
    end

    def self.delete_file(file)
      open(CartoCSSHelper::Configuration.get_path_to_folder_for_cache+'log.txt', 'a') { |file|
        file.puts("deleting #{file}, #{File.size(file)/1024/1024}MB")
      }
      File.delete(file)
    end

    def self.delete_large_overpass_caches
      #todo - find library that deals with caches like this, bug here may be unfunny
      Dir.glob(CartoCSSHelper::Configuration.get_path_to_folder_for_overpass_cache+'*') {|file|
        if File.size(file) > (1024 * 1024 * 50)
          delete_file(file)
        end
      }
    end

    class OverpassRefusedResponse < IOError; end

    def self.run_overpass_query(query, retry_count=0, retry_max=5)
      start = Time.now.to_s
      begin
        url = Downloader.format_query_into_url(query)
        timeout = Downloader.get_allowed_timeout_in_seconds+10
        return RestClient::Request.execute(:method => :get, :url => url, :timeout => timeout)
      rescue RestClient::RequestTimeout
        puts 'Overpass API refused to process this request. It will be not attemped again, most likely query is too complex.'
        raise OverpassRefusedResponse
      rescue RestClient::RequestFailed => e
        puts query
        puts e.response
        puts e.http_code
        puts start
        puts Time.now.to_s
        if retry_count < retry_max
          sleep 60*5
          Downloader.run_overpass_query(query, retry_count+1, retry_max)
        else
          e.raise
        end
      rescue ArgumentError => e
        puts 'ArgumentError from rest-client, most likely caused by https://github.com/rest-client/rest-client/issues/359'
        puts 'try overpass query that will return smaller amount of data'
        puts e
        e.raise
      rescue => e
        puts 'query failed'
        puts query
        puts
        puts url
        puts e
        e.raise
      end
    end

    def self.get_allowed_timeout_in_seconds
      return 10 * 60
    end

    def self.format_query_into_url(query)
      query = query.gsub(/\n/, '')
      query = query.gsub(/\t/, '')
      return 'http://overpass-api.de/api/interpreter?data=' + URI.escape(query)
    end
  end
end
