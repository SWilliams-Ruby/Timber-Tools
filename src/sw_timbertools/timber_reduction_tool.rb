

module SW
  module TimberTools
    class TimberReductionTool
      def activate
        @ip = Sketchup::InputPoint.new

        @gp1 = Geom::Point3d.new(0,0,0)
        #@gp2 = Geom::Point3d.new(0,0,0)  
        #@gv = Geom::Vector3d.new(0,0,0)
        
        #@tp = Geom::Point3d.new(0,0,0)
        #@last_comp_moved = nil
        Sketchup.vcb_label = ""
        reset(nil)
      end

      #def deactivate(view)
        #view.invalidate if @drawn
      #end

      # def onSetCursor()
        # @cursor ||= UI.create_cursor(File.join(PLUGIN_DIR, "images", 'stretch_tool.png'), 16, 16)
        # cursor = UI.set_cursor(@cursor)
      # end

      def reset(view)
        view.tooltip = nil if view
        view.invalidate if view
        Sketchup.active_model.selection.clear()
        Sketchup::set_status_text("Select Reduction location", SB_PROMPT)
      end
      
      def onMouseMove(flags, x, y, view)
        mm = Sketchup.active_model
        ss = mm.selection
        
        # has the mouse moved over a new entity
        if @ip.pick( view, x, y)
          view.invalidate 
        
          # find all components at the mouse x,y 
          ph = view.pick_helper
          ph.do_pick(x,y)
          hits = ph.all_picked
          hits = hits.grep(Sketchup::ComponentInstance)
          hits.uniq!
          
          # stay with last component as long as the mouse is over it.
          if hits.size == 0
            @last_component = nil 
          else
           hits = [@last_component] if hits.include?(@last_component)
          end
          
          # find the closest face in the hits array
          if (hits.size != 0) && intersections = find_closest_face(hits, view, x, y)
              @best_face = intersections[1]
              @last_component = intersections[2]
              @intersection_point = intersections[3] 
              ss.clear
              ss.add(@best_face)
          else
            ss.clear
          end
        end
      
        # set the tooltip that should be displayed to this point
        view.tooltip = @ip.tooltip
        view.invalidate
      end
      
      # find the closest object in the array of hit components.
      def find_closest_face(hits, view, x, y)
        intersections = []
        ray = view.pickray( x, y)
        
        hits.each {|e|
          tr = e.transformation
          point = ray[0].transform(tr.inverse)
          dir = ray[1].transform(tr.inverse)
          ray2 = [point, dir]
          
          e.definition.entities.grep(Sketchup::Face).each {|face|
            intersection = Geom.intersect_line_plane(ray2, face.plane)
            next unless intersection
            next if intersection == point
            next unless (intersection - point).samedirection?(dir)
            next unless within_face?(intersection, face)
            intersections << [intersection.distance(point), face, e, intersection.transform!(tr)]
          }
        }
        # return the closest object. On rare occasions there can be no hits due to
        # differences between the do_pick and intersect_line_plane 
        intersections.min{|a, b| a[0] <=> b[0]}
      end
      
      # Eneroth's - Test if point is inside of a face.
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


      # def longest_edge(timber)
        # cd = timber.definition
        # longest = nil
        # cd.entities.each do |e|
          # next if not e.instance_of? Sketchup::Edge
          # if (longest == nil) or (e.length > longest.length)
            # longest = e
          # end
        # end
        # return longest
      # end

      # The onLButtonDOwn method is called when the user presses the left mouse button.
      def onLButtonDown(flags, x, y, view)
          # When the user clicks the first time, we colelct all the elements in this half of the component. 
          #  When they click a second time we stop
          #if( @state == 0 )
          # first click
            #@ip1.pick view, x, y
            #p @ip1.position
            #if( @ip1.valid? )
            if @intersection_point
              #p @intersection_point
              @ip1 = Sketchup::InputPoint.new(@intersection_point)
              # user picked first point.

              @gp1 = @ip1.position  # global position
              
              #@gp1 = @intersection_point

              model = Sketchup.active_model
                    
              if @ci == nil
                # there was no ci selected when we started to tool, but perhps the user was hovering over one when they clicked the mouse
                @ci = selected_component
                return if @ci == nil
              end
              cd = @ci.definition		# the definition for the component
              #print("gp1: "+@gp1.to_s + "\n")
              
              #lp1 = @ip1.position # local position
              lp1 =  @intersection_point
              lp1.transform!(@ci.transformation.inverse)
              le = longest_edge(@ci)
              #puts "longest edge: " << le.start.position.to_s << "  " << le.end.position.to_s
              lv = Geom::Vector3d.new(le.line[1])	#local vector
              #puts "local vector: " << lv.to_s
              # We need to locate all gemoetry at "this" end of the componenet.  We divide it in half the "long" way
              # Lets start by finding the plane that bisects the component - the midplane
              midplane = [cd.bounds.center, lv]   					# plane is just a point and a vector - both local
              pp1 = lp1.project_to_plane(midplane)		# pp1 = lp1 projected onto the midplane
              vec1 = pp1.vector_to(lp1)					# vec1 = vector from pp1 to lp1.  
              #puts "vec1: " << vec1.to_s
              #We do the same for all other points - those whose vector is the same direction as vec1 are on the same side
              @ents_to_move.clear
              # cd.entities.each do |e|
                # case e
                # when Sketchup::Edge
                  # # For edges, both vertices must lie on this side
                  # ep1 = e.start.position
                  # pep1 = ep1.project_to_plane(midplane)
                  # next if ep1 == pep1
                  # ep2 = e.end.position
                  # pep2 = ep2.project_to_plane(midplane)
                  # next if ep2 == pep2
                  # if pep1.vector_to(ep1).samedirection?(vec1) and pep2.vector_to(ep2).samedirection?(vec1) then
                    # @ents_to_move.push(e)
                  # end
                
                # when Sketchup::ComponentInstance
                  # # for comps, we'll just test the center point
                  # cp = e.bounds.center
                  # #puts "cp: " << cp.to_s
                  # pcp = cp.project_to_plane(midplane)
                  # #puts "pcp: " << pcp.to_s
                  # next if pcp == cp	# component center is on the midplane.  Can't take a vector of that.  Just skip it.
                  # if pcp.vector_to(cp).samedirection?(vec1) then
                    # @ents_to_move.push(e)
                  # end	
                  # # seems that all we need are edges and sub-cmps
                # end
              # end
              
              #puts "ents to move:"
              #@ents_to_move.each do |e|
              #	puts e.to_s
              #end
              
              @gv = lv.clone							# global vector
              @gv.transform!(@ci.transformation)		# transform to global space
              if not lv.samedirection?(vec1) 		# we want @gv to point in the "growing" direction, not the "shrinking" direction
                #puts "reversing @gv"
                @gv.reverse!	
              end
              #puts "global vector: " << @gv.to_s
              @min_length = -1.5 * (vec1.length)
              #puts "min_length: " << @min_length.to_s
              @prev_pos = lp1	
              #puts "@prev_pos: " << @prev_pos.to_s
              Sketchup::set_status_text "Select Stretch Destination", SB_PROMPT
              Sketchup.vcb_label = "Stretch Distance"
              @state = 1
              Sketchup.active_model.start_operation("Timber Stretch", true)			

            end
           
          # else  # second mouse click - we're done, just clean up
            # if( @ip2.valid? )
              # Sketchup.active_model.commit_operation
              # reset(view)
            # end
          # end
          
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
              elsif( @state == 0 && @ip1.valid? )
                  view.lock_inference @ip1
              elsif( @state == 1 && @ip2.valid? )
                  view.lock_inference @ip2, @ip1
              end
          end
      end

      # onKeyUp is called when the user releases the key
      # We use this to unlock the interence
      # If the user holds down the shift key for more than 1/2 second, then we
      # unlock the inference on the release.  Otherwise, the user presses shift
      # once to lock and a second time to unlock.
      def onKeyUp(key, repeat, flags, view)
          if( key == CONSTRAIN_MODIFIER_KEY &&
              view.inference_locked? &&
              (Time.now - @shift_down_time) > 0.5 )
              view.lock_inference
          end
      end

      # onUserText is called when the user enters something into the VCB
      # def onUserText(text, view)
          # return if @last_comp_moved == nil
          
          # # The user may type in something that we can't parse as a length
          # # so we set up some exception handling to trap that
          # begin
              # distance = text.to_l
          # rescue
              # # Error parsing the text
              # UI.beep
              # puts "Cannot convert #{text} to a Length"
              # distance = nil
              # Sketchup::set_status_text "", SB_VCB_VALUE
          # end
          # return if !distance
        
      # #	puts "moving via VCB: " << distance.to_s
        
        # # put everything bakc the way we started
        # if @state == 1 
          # self.reset(view)
        # end	
        # Sketchup.undo	
        
        # if @length < 0 
          # distance = distance * -1
        # end
        
        # @ci = @last_comp_moved
      # #	puts "@gv: " << @gv.to_s
        # mov_vec = @gv.clone
        # mov_vec.transform!(@ci.transformation.inverse)
        # mov_vec.length = distance
      # #	puts "mov_vec: " << mov_vec.to_s
        # move_it(mov_vec)
        # self.reset(view)
      # end

      # The draw method is called whenever the view is refreshed.  It lets the
      # tool draw any temporary geometry that it needs to.
      def draw(view)
        if( @ip.valid? )
          if( @ip.display? )
            @ip.draw(view)
             #@drawn = true
          end
        end
      end

      # onCancel is called when the user hits the escape key
      def onCancel(flag, view)
        #Sketchup.active_model.abort_operation
        reset(view)
      end

    end # reduction tool
    
    def self.activate_timber_reduction_tool
      Sketchup.active_model.select_tool(TimberReductionTool.new)
    end
    
  end
end # module 