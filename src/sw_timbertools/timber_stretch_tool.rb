

module SW
  module TimberTools
    class TimberStretchTool
      def activate
        @ip1 = Sketchup::InputPoint.new	 #inupt point for first mouse click
        @ip2 = Sketchup::InputPoint.new  # input point for second mouse click
        @gp1 = Geom::Point3d.new(0,0,0)  # global values for the input point positions
        @gp2 = Geom::Point3d.new(0,0,0)  
        @gv = Geom::Vector3d.new(0,0,0) # global vector - this is the direction we are stretching, in global space
        @tp = Geom::Point3d.new(0,0,0)	#stretch target point in global space
        @ip = Sketchup::InputPoint.new	# the current input point while moving the mouse
        @drawn = false
        @prev_pos = Geom::Point3d.new(0,0,0)	# used to compute how far to move with each mouse event
        @length = 0.0						# how far we have moved so far, negative meaning getting smaller
        @min_length = 0						# kind of a kludge  the original size.
        #@instance = nil
        #@initial_comp_selected = false		# if there was nothing selected when we start, then we 'select' any comp that the mouse hovers over
        @last_comp_moved = nil
        Sketchup.vcb_label = ""
        reset(nil)
      end

      def deactivate(view)
        view.invalidate if @drawn
      end
      
      # onCancel is called when the user hits the escape key
      def onCancel(flag, view)
        Sketchup.active_model.abort_operation
        reset(view)
      end

      def onSetCursor()
        @cursor ||= UI.create_cursor(File.join(PLUGIN_DIR, "images", 'stretch_tool.png'), 16, 16)
        cursor = UI.set_cursor(@cursor)
      end

      def reset(view)
        @moving = false
        @ip1.clear
        @ip2.clear
        @drawn = false
        
        if( view )
            view.tooltip = nil
            view.invalidate if @drawn
        end

        Sketchup.active_model.selection.clear()
        Sketchup::set_status_text("Select Stretch Start Point", SB_PROMPT)
      end
      

      def onMouseMove(flags, x, y, view)
        if( @moving == false )
          choose_face(x, y, view)
        else
          move_face(x, y, view)
        end
      end
      
      
      # As the mouse moves around choose a component and face
      # @selected_instance and @best_face are added to the model.selection array
      
      def choose_face(x, y, view)
        model = Sketchup.active_model
        sel = model.selection
        
        ph = view.pick_helper
        ph.do_pick(x,y)
        hits = ph.all_picked
        hits = hits.grep(Sketchup::ComponentInstance)
        hits.uniq!
        
        # stay with last component as long as the mouse is over it.
        @last_component = nil unless hits.size > 0
        hits = [@last_component] if hits.include?(@last_component)

        intersections = []
        ray = view.pickray( x, y)
        
        if hits.size > 0
          hits.each {|e|
            face = find_nearest_face( e, ray)
            intersections << face if face
          }
          
          if intersections.size > 0
            # sort by closest
            intersections.sort!{|a, b| a[0] <=> b[0]}
            @best_face = intersections[0][1]
            @verts = @best_face.vertices
            
            #remember this component
            @last_component = intersections[0][2]
            
            @selected_instance = intersections[0][2]
            @intersection_point = intersections[0][3] 
            @ip1 = Sketchup::InputPoint.new(@intersection_point)
            
            sel.clear
            sel.add(@best_face)
            sel.add(@best_face.parent.instances)
            view.tooltip = 'On Face'            
          else
            sel.clear
            @selected_instance = nil
            view.tooltip = ''
          end
        else
          sel.clear
          @selected_instance = nil
          view.tooltip = ''
        end
        view.invalidate
       end
      
      def find_nearest_face( e, ray)
        nearest = nil
        tr = e.transformation
                
        point = ray[0].transform(tr.inverse)
        dir = ray[1].transform(tr.inverse)
        ray2 = [point, dir]
        
        e.definition.entities.grep(Sketchup::Face).each {|face|
          #return face if within_face?(point, face)

          intersection = Geom.intersect_line_plane(ray2, face.plane)
          next unless intersection
          next if intersection == point

          next unless (intersection - point).samedirection?(dir)
          next unless within_face?(intersection, face)
          
          distance = intersection.distance(point)
          if (nearest == nil)  || distance < nearest[0]
            nearest = [distance, face, e, intersection.transform!(tr)]
          end  
        }
        nearest
      end
      
      
      def move_face(x, y, view)
          @ip2.pick view, x, y, @ip1
          view.tooltip = @ip2.tooltip if( @ip2.valid? )
          view.invalidate
    
        if( @ip2.valid? )
          @gp2 = @ip2.position							#global p2
                
          tplane = [@gp2, @gv]						# target plane
          @tp = @gp1.project_to_plane(tplane)			#target point (in global space)
          ltp = @tp.clone								# local target point
          ltp.transform!(@selected_instance.transformation.inverse)
          
          # Update the length displayed in the VCB
          @length = @gp1.distance_to_plane(tplane)
          @length = @gp1.distance(@tp)
          if @length != 0 
            vv = @tp.vector_to(@gp1)
            if vv.samedirection? @gv
              @length = @length * -1
            end
          end
          return if @length < @min_length
                Sketchup.vcb_value = @length.to_l.to_s
          
          offs_vector = @prev_pos.vector_to(ltp)
          #p offs_vector
          
          #puts "offset vector " << offs_vector.to_s
          move_it(offs_vector)
          
          @prev_pos = ltp
        end
      end
      
      def move_it(offs_vector)
        xlat = Geom::Transformation.new(offs_vector)
        @selected_instance.definition.entities.transform_entities(xlat, @verts)
        #p offs_vector.length
        #status = @best_face.pushpull(offs_vector.length, true)
        @last_comp_moved = @selected_instance
      end	
      
      # Test if point is inside of a face.
      #
      # @param point [Geom::Point3d]
      # @param face [Sketchup::Face]
      # @param on_boundary [Boolean] Value to return if point is on the boundary
      #   (edge/vertex) of face.
      #
      # @return [Boolean]
      def within_face?(point, face, on_boundary = true)
        pc = face.classify_point(point)
        return on_boundary if [Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(pc)

        pc == Sketchup::Face::PointInside
      end

      def onLButtonDown(flags, x, y, view)
          if @moving == false  && @selected_instance
              @gp1 = @ip1.position  # global position
              model = Sketchup.active_model
                    
              #if @instance == nil
              #  # there was no ci selected when we started to tool, but perhps the user was hovering over one when they clicked the mouse
                #@instance = @selected_instance
                
             # end
              
              @intersection_point.transform!(@selected_instance.transformation.inverse)
              lv = @best_face.normal
              midplane = [@selected_instance.definition.bounds.center, lv]
              pp1 = @intersection_point.project_to_plane(midplane)
              vec1 = pp1.vector_to(@intersection_point)
              @gv = @best_face.normal.clone
              @gv.transform!(@selected_instance.transformation)

              #if not @best_face.normal.samedirection?(vec1)
               # @best_face.normal.reverse!	
              #end

              #puts "global vector: " << @gv.to_s
              @min_length = -1.5 * (vec1.length)
              #puts "min_length: " << @min_length.to_s
              @prev_pos = @intersection_point	
              #puts "@prev_pos: " << @prev_pos.to_s
              Sketchup::set_status_text "Select Stretch Destination", SB_PROMPT
              Sketchup.vcb_label = "Stretch Distance"
              @moving = true
              
              Sketchup.active_model.start_operation("Timber Stretch", true)			

            #end
           
          else  # second mouse click - we're done, just clean up
            if( @ip2.valid? )
              Sketchup.active_model.commit_operation
              reset(view)
            end
          end
          
          # Clear any inference lock
          view.lock_inference
      end
      
   	

      # onKeyDown is called when the user presses a key on the keyboard.
      # We are checking it here to see if the user pressed the shift key
      # so that we can do inference locking
      def onKeyDown(key, repeat, flags, view)
          if( key == CONSTRAIN_MODIFIER_KEY && repeat == 1 )
              @shift_down_time = Time.now
              
              # if we already have an inference lock, then unlock it
              if( view.inference_locked? )
                  # calling lock_inference with no arguments actually unlocks
                  view.lock_inference
              elsif( @moving == false && @ip1.valid? )
                  view.lock_inference @ip1
              elsif( @moving == true && @ip2.valid? )
                  view.lock_inference @ip2, @ip1
              end
          end
      end

      def onKeyUp(key, repeat, flags, view)
          if( key == CONSTRAIN_MODIFIER_KEY &&
              view.inference_locked? &&
              (Time.now - @shift_down_time) > 0.5 )
              view.lock_inference
          end
      end

      def onUserText(text, view)
          return if @last_comp_moved == nil
          
          begin
              distance = text.to_l
          rescue
              # Error parsing the text
              UI.beep
              puts "Cannot convert #{text} to a Length"
              distance = nil
              Sketchup::set_status_text "", SB_VCB_VALUE
          end
          return if !distance
        
      #	puts "moving via VCB: " << distance.to_s
        
        # put everything back the way we started
        if @moving == true 
          reset(view)
        end	
        Sketchup.undo	
        
        if @length < 0 
          distance = distance * -1
        end
        
        #@instance = @last_comp_moved
      #	puts "@gv: " << @gv.to_s
        mov_vec = @gv.clone
        mov_vec.transform!(@instance.transformation.inverse)
        mov_vec.length = distance
      #	puts "mov_vec: " << mov_vec.to_s
        move_it(mov_vec)
        reset(view)
      end

      # The draw method is called whenever the view is refreshed.  It lets the
      # tool draw any temporary geometry that it needs to.
      # def draw(view)
        # if( @ip1.valid? )
          # if( @ip1.display? )
            # @ip1.draw(view)
            # @drawn = true
          # end
          
          # if( @ip2.valid? )
            # @ip2.draw(view) if( @ip2.display? )
            
            # # The set_color_from_line method determines what color
            # # to use to draw a line based on its direction.  For example
            # # red, green or blue.
            # view.set_color_from_line(@ip1, @ip2)
            # view.line_stipple = "."
            # view.draw_line(@gp1, @gp2)
            # view.line_stipple = ""
           
            # @drawn = true
          # end
        # end
      # end

      

    end # 
    
    def self.activate_timber_stretch_tool
      Sketchup.active_model.select_tool(TimberStretchTool.new)
    end
    
  end
end # module 