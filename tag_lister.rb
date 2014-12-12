load 'config.rb'
load 'image_generator.rb'
include Config

class Info
	def list_render_state_of_tags
		tags = get_tags
		@last_composite = nil
		tags.each { |tag|
			print_render_state_of_tag tag[0], tag[1]
		}
	end

	def print_render_state_of_tag(key, value)
		if is_rendered key, value
			puts "#{key}=#{value} - primary"
			@last_composite = nil
		else
			if is_rendered_as_composite key, value, @last_composite
				@last_composite = how_rendered_as_composite key, value, @last_composite
				puts "#{key}=#{value} - composite with #{@last_composite} - and maybe other tags"
			else
				puts "#{key}=#{value} - not displayed"
				@last_composite = nil
			end
		end
	end

	def is_rendered(key, value)
		[false, true].each { |on_water|
			[Config.get_max_z].each { |zlevel|
				if rendered_on_zlevel({key => value, 'area' => 'yes'}, 'closed_way', zlevel, on_water)
					return true
				end
				if rendered_on_zlevel({key => value}, 'closed_way', zlevel, on_water)
					return true
				end
				#workaround for bug detected by check_problems_with_closed_line
				if rendered_on_zlevel({key => value}, 'way', zlevel, on_water)
					return true
				end
				if rendered_on_zlevel({key => value}, 'node', zlevel, on_water)
					return true
				end
			}
		}
		return false
	end

	def is_rendered_as_composite(key, value, suggested_composite=nil)
		reason = how_rendered_as_composite key, value, suggested_composite
		if reason == nil
			return false
		end
		return true
	end

	protected

	def how_rendered_as_composite(key, value, suggested_composite)
		[false, true].each { |on_water|
			[Config.get_max_z].each { |zlevel|
				result = how_rendered_on_zlevel_as_composite({key => value}, 'closed_way', zlevel, on_water, suggested_composite)
				if result != nil
					return result
				end
				result = how_rendered_on_zlevel_as_composite({key => value}, 'way', zlevel, on_water, suggested_composite)
				if result != nil
					return result
				end
				result = how_rendered_on_zlevel_as_composite({key => value}, 'node', zlevel, on_water, suggested_composite)
				if result != nil
					return result
				end
			}
		}
		if suggested_composite != nil
			return how_rendered_as_composite key, value, nil
		end
		return nil
	end

	def rendered_on_zlevel(tags, type, zlevel, on_water)
		empty = Scene.new({}, zlevel, on_water, type)
		tested = Scene.new(tags, zlevel, on_water, type)
		return tested.is_output_different(empty)
	end

	def how_rendered_on_zlevel_as_composite(tags, type, zlevel, on_water, suggested_composite)
		if suggested_composite != nil
			if is_rendered_with_this_composite tags, type, suggested_composite, zlevel, on_water
				return suggested_composite
			end
			return nil
		end
		composite_sets = [
				{'name' => 'a'}, #place=*
				{'highway' => 'service'}, #access, ref, bridge, tunnel, service=parking_aisle...
				{'railway' => 'rail'}, #service=siding
				{'boundary' => 'administrative'}, #admin_level
				{'admin_level' => '2'}, #boundary=administrative
				{'natural' => 'peak'}, #ele
				{'ref' => '3'}, #aeroway=gate
				{'amenity' => 'place_of_worship'}, #religion
				{'amenity' => 'place_of_worship', 'religion' => 'christian'}, #denomination
				{'waterway' => 'river'}, #bridge=aqueduct, tunnel=culvert
				#{'barrier' => 'hedge'}, #area=yes
		]
		composite_sets.each { |composite|
			if is_rendered_with_this_composite tags, type, composite, zlevel, on_water
				return composite
			end
		}
		return nil
	end

	def is_rendered_with_this_composite(tags, type, provided_composite, zlevel, on_water)
		#puts "<<<\n#{tags}\n#{composite}<<<\n\n"
		# noinspection RubyResolve
		# see https://youtrack.jetbrains.com/issue/RUBY-16061
		tags_with_composite = Marshal.load(Marshal.dump(tags))
		# noinspection RubyResolve
		# see https://youtrack.jetbrains.com/issue/RUBY-16061
		composite = Marshal.load(Marshal.dump(provided_composite))
		composite.each { |key, value|
			if tags_with_composite[key] != nil
				return false #shadowing
			end
			tags_with_composite[key] = value
		}
		with_composite = Scene.new(tags_with_composite, zlevel, on_water, type)
		only_composite = Scene.new(composite, zlevel, on_water, type)
		empty = Scene.new({}, zlevel, on_water, type)
		if with_composite.is_output_different(empty)
			if with_composite.is_output_different(only_composite)
				if composite['area'] != nil
					return true
				end
				composite['area'] = 'yes'
				composite_interpreted_as_area = Scene.new(composite, zlevel, on_water, type)
				if with_composite.is_output_different(composite_interpreted_as_area)
					return true
				end
			end
		end
		return false
	end
end