# encoding: UTF-8
load 'heuristic.rb'
load 'image_generator.rb'
load 'config.rb'

include Heuristic

module Validator
	def run_tests
		compare_expected_with_real_rendering
		puts
		puts 'failed display of closed way, unlosed way works:'
		run_global_check(:check_problems_with_closed_line)
		puts
		puts "bad dy values (tall names like 'É' are not displayed, short names like 'a' are):"
		run_global_check(:check_dy)
	end

	def compare_expected_with_real_rendering
		list_of_expected = get_expected_tag_status
		info = Info.new
		info.get_render_state_of_tags.each { |state|
			compare_expected_with_state list_of_expected, state
		}
	end

	def compare_expected_with_state(list_of_expected, state)
		list_of_expected.each { |expected|
			if expected.key == state.key
				if expected.value == state.value
					if expected.equal? state
						puts 'expected'
						expected.print
						puts 'real'
						state.print
						puts
					end
					return
				end
			end
		}
		puts 'expected'
		puts 'missing'
		puts 'real'
		state.print
		puts
	end

	def run_global_check(function)
		Heuristic.get_tags.each { |element|
			(Config.get_max_z..Config.get_max_z).each { |zlevel| #get_min_z should be used - but as renderer is extremely slow this hack was used TODO
				send(function, element[0], element[1], zlevel)
			}
		}
	end

	#TODO - what about composite tags?
	def check_problems_with_closed_line(key, value, zlevel, on_water = false)
		way = Scene.new({key => value}, zlevel, on_water, 'way')
		closed_way = Scene.new({key => value}, zlevel, on_water, 'closed_way')
		empty = Scene.new({}, zlevel, on_water, 'node')
		if way.is_output_different(empty)
			if !closed_way.is_output_different(empty)
				puts key+'='+value
			end
		end
	end

	def check_dy(key, value, zlevel, interactive=false)
		on_water = false #TODO -is it OK
		if !is_object_displaying_anything key, value, zlevel, on_water
			#puts key+"="+value+" - not displayed as node on z#{zlevel}"
			return
		end
		if !is_object_displaying_name key, value, 'a', zlevel, on_water
			#puts key+"="+value+" - label is missing on z#{zlevel} nodes"
			return
		end
		test_name = 'ÉÉÉÉÉÉ ÉÉÉÉÉÉ ÉÉÉÉÉÉ'
		on_water = false #TODO -is it OK
		while !is_object_displaying_name key, value, test_name, zlevel, on_water
			puts key+'='+value+" - name is missing for name '#{test_name}' on z#{zlevel}"
			if interactive
				puts 'press enter'
				gets
			else
				return
			end
			with_name = Scene.new({key => value, 'name' => test_name}, zlevel, on_water, 'node')
			with_name.flush_cache
			puts 'calculating'
		end
		#puts key+"="+value+" - name is OK for name '#{name}'"
	end

	def is_object_displaying_name(key, value, name, zlevel, on_water)
		name_tags = {key => value, 'name' => name}
		with_name = Scene.new(name_tags, zlevel, on_water, 'node')
		nameless_tags = {key => value}
		nameless = Scene.new(nameless_tags, zlevel, on_water, 'node')
		return with_name.is_output_different(nameless)
	end

	def is_object_displaying_anything(key, value, zlevel, on_water)
		object = Scene.new({key => value}, zlevel, on_water, 'node')
		empty = Scene.new({}, zlevel, on_water, 'node')
		return object.is_output_different(empty)
	end
end