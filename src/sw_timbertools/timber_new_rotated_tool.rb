# SW::TimberTools.reload

module SW
module TimberTools

  class TimberNewRotateTool
    @@latest_timber = nil         # a reference to the last timber drawn
    @@locked_axis = nil           # set by the arrow keys
    @@slope = nil                 # a user entered slope, 3:12
    @@context_menu_open = false   # a flag to catch errant mouse clicks
    @@instance_rotation = 0.0     # rotate timber 90 degrees with the control key
    @@instance_rotation_saved = nil
    @@protractor_state = 0        # show the protractor
    @@protractor_plane = nil      # 
    @@protractor_rot_plane = nil  #
    @@protractor_points = []      # 
    @@end_points = nil            # the current end points 
    @@end_points_saved = nil      # latest timber end points 
    
    def activate
      @mouse_ip = Sketchup::InputPoint.new
      @picked_first_ip = Sketchup::InputPoint.new
      @picked_second_ip = Sketchup::InputPoint.new
      Sketchup.vcb_label = "Timber Size #{SW::TimberTools.get_active_dimensions}"

      reset_tool()
    end
    
    def deactivate(view)
      view.invalidate
    end

    def resume(view)
      update_ui
      view.invalidate
    end

    def onCancel(reason, view)
      reset_tool
      view.invalidate
    end
    
    if Sketchup.version.to_i < 15
      # Compatible with SketchUp 2014 and older:
      def getMenu(menu)
        @@context_menu_open = true
      end
    else
    
      def getMenu(menu, flags, x, y, view)
        @@context_menu_open = true
      end
    end
      
    # allow vcb text entry while the tool is active.
    def enableVCB?
      return true
    end
    
    
    ### possible entries are 
    ### a length: 24' 5"
    ### a lumber dimension: 2x4, 2x4* nominal dimensions
    ### a slope:  4:12
    
    def onUserText(text, view)
      begin
        dims = text.split(%r{[xX]})
        if dims.size == 2
          #entry was a width and height, check validity        
          dim2 = dims[1].split('*')
          raise ArgumentError unless dims[0].to_l > 0
          raise ArgumentError unless dim2[0].to_l > 0
          SW::TimberTools.set_new_timber_size(text) #in preferences.rb
          view.invalidate

        else
          dims = text.split(%r{[:]})
          if dims.size == 2
           #entry was a slope
           z = dims[0].to_l
           x = dims[1].to_l
           @@slope = Math.atan(z/x)
           view.invalidate
          else
            # entry was a timber length
            add_timber_to_model(text.to_l) # save current points if this is a new timber
            reset_tool()
            Sketchup.vcb_value = "" # erase the last VCB value
          end
        end
      rescue ArgumentError
      view.tooltip = 'Invalid text entry'
      end
    end

    def onMouseMove(flags, x, y, view)
      @mouse_current_x = x
      @mouse_current_y = y
      @@context_menu_open = false # reset
      
      if picked_first_point?
        @mouse_ip.pick(view, x, y, @picked_first_ip)
      else
        @mouse_ip.pick(view, x, y)
      end
      
      Sketchup.set_status_text( (@picked_first_ip.position.distance(@mouse_ip.position)).to_s, SB_VCB_VALUE)
      view.tooltip = @mouse_ip.tooltip if @mouse_ip.valid?
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      #Skip the first click after the context menu is closed
      if @@context_menu_open
        @@context_menu_open = false
        return
      end
      
      if !picked_first_point?
        @mouse_ip.pick(view, x, y) 
        @picked_first_ip.copy!(@mouse_ip)
        @@latest_timber = nil
        @@instance_rotation = 0.0
        
      elsif  picked_second_point? 
        add_timber_to_model()
        reset_tool
      else
        @mouse_ip.pick(view, x, y) 
        @picked_second_ip.copy!(@mouse_ip)
      end
      update_ui
      view.invalidate
    end
    
    def onKeyDown(key, repeat, flags, view)
      # # cache/toggle the arrow keys for Axis locking
      # if [VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN].include?(key)
        # @@slope = nil if @@slope
        # if [VK_UP, VK_DOWN].include?(key)
          # [VK_UP, VK_DOWN].include?(@@locked_axis) ?  @@locked_axis = nil : @@locked_axis = key
        # else
          # @@locked_axis = key
        # end
      # end
 
      
      # if key == CONSTRAIN_MODIFIER_KEY
        # if @@end_points.size == 2
          # direction = direction = @@end_points[0].vector_to(@@end_points[1])
          # @@locked_axis = VK_RIGHT if direction.parallel?(X_AXIS) 
          # @@locked_axis = VK_LEFT if direction.parallel?(Y_AXIS) 
          # @@locked_axis = VK_UP if direction.parallel?(Z_AXIS) 
        # end
      # end
           
      # Show the protractor toggle
       # if key == ALT_MODIFIER_KEY 
        # @@protractor_state += 1; @@protractor_state = 0 if @@protractor_state == 3
        # if @@protractor_state == 1
          # direction = @picked_first_ip.position.vector_to(@mouse_ip.position)
          # if !((direction.length == 0) || direction.parallel?(Z_AXIS))
            # # save the protractor state
            # @@protractor_points[0] = @picked_first_ip.position
            # @@protractor_points[1] = Geom::Point3d.new(@mouse_ip.position.x, @mouse_ip.position.y, @picked_first_ip.position.z)
            # direction = @@protractor_points[0].vector_to(@@protractor_points[1])
            # @@protractor_rot_plane = direction.clone
            # direction.transform!(Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees))
            # @@protractor_plane = [@picked_first_ip, direction]
          # else
            # @@protractor_state = 0
          # end
        # end
        # view.invalidate
        # return true # inform windows that the key was handled
      #  end
      
      # rotate the timber around the long axis if the Control Key was pressed
      if key == COPY_MODIFIER_KEY 
        @@instance_rotation += 90.degrees
        @@instance_rotation -= 360.degrees if @@instance_rotation >= 360.degrees
        view.invalidate
      end
      
      if( key == CONSTRAIN_MODIFIER_KEY && repeat == 1 )
        @shift_down_time = Time.now
        
        # if we already have an inference lock, then unlock it
        if( view.inference_locked? )
            # calling lock_inference with no arguments actually unlocks
            view.lock_inference
 #       elsif( !picked_first_point? && @ip1.valid? )
 #           view.lock_inference @ip1
        elsif( !picked_first_point? && @picked_first_ip.valid? )
            view.lock_inference @picked_first_ip
        end 
      end
    end

    # onKeyUp is called when the user releases the key
    # We use this to unlock the inference
    # If the user holds down the shift key for more than 1/2 second, then we
    # unlock the inference on the release.  Otherwise, the user presses shift
    # once to lock and a second time to unlock.
    def onKeyUp(key, repeat, flags, view)
      @@locked_axis = nil if key == CONSTRAIN_MODIFIER_KEY 
      if( key == CONSTRAIN_MODIFIER_KEY &&
        view.inference_locked? &&
        (Time.now - @shift_down_time) > 0.5 )
        view.lock_inference
      end
    end

    CURSOR_ROTATE = UI.create_cursor(File.join(PLUGIN_DIR, "images", 'timber pointer rotate.png'), 1, 7) 
    
    def onSetCursor
      UI.set_cursor(CURSOR_ROTATE)
    end

    def draw(view)
      draw_preview(view)
      @mouse_ip.draw(view) if @mouse_ip.display?
      @picked_first_ip.draw(view) if !@picked_first_ip.nil? && @picked_first_ip.valid? && @picked_first_ip.display?
      @picked_second_ip.draw(view) if !@picked_second_ip.nil? &&  @picked_second_ip.valid? && @picked_second_ip.display?
      Sketchup.vcb_label = "Timber Size #{SW::TimberTools.get_active_dimensions}"

    end

     def getExtents
       bb = Geom::BoundingBox.new
       bb.add(@picked_first_ip.position) if picked_first_point?
       bb.add(@mouse_ip.position) if @mouse_ip.valid?
       bb
    end

    private

     def update_ui
      if picked_first_point?
        if !picked_second_point?
          Sketchup.status_text = 'Select width direction.'
        else
          Sketchup.status_text = 'Select end point.'
        end
      else
        Sketchup.status_text = 'Select start point.'
      end
    end
    
    def reset_tool
      @picked_first_ip.clear
      @picked_second_ip.clear
      @@locked_axis = nil
      @@slope = nil
      @@context_menu_open = false
      @@instance_rotation = 0.0
      @@protractor_state = 0
      update_ui
    end

    def picked_first_point?
      @picked_first_ip.valid?
    end
    
    def picked_second_point?
      @picked_second_ip.valid?
    end
    
    #######################
    ###  Draw  Routines ###
    #######################

  
    
    def picked_points(view)
      end_pos = @mouse_ip.position
 
      # if @@slope
        # end_pos = @mouse_ip.position
        # direction = @picked_first_ip.position.vector_to( @mouse_ip.position)
        # hypo = Math.sqrt(direction.x**2+direction.y**2)
        # end_pos.z = hypo * Math.tan(@@slope) + @picked_first_ip.position.z
      # end
      
      # if @@protractor_state != 0
        # # find a point on the protractor plane
        # ray = view.pickray(@mouse_current_x, @mouse_current_y )
        # end_pos = Geom::intersect_line_plane( ray, @@protractor_plane )
        
        # #calculate the angle to the point and round to the "snap" points
        # vector_to_end = @picked_first_ip.position.vector_to(end_pos)
        # a = @@protractor_rot_plane.angle_between(vector_to_end)
        # a = a * -1 if vector_to_end.z >= 0
        
        # if @@protractor_state == 1
          # # protractor with degrees
          # snap_angle = 5.degrees
          # diff = a % snap_angle

          # if diff > snap_angle / 2.0
            # nearest_angle = a + (snap_angle - diff)
          # else
            # nearest_angle = a - diff
          # end
          # display_angle = -nearest_angle
        
          # angle_formatted = Sketchup.format_angle( display_angle )
          # Sketchup.vcb_label = 'Angle'
          # Sketchup.vcb_value = angle_formatted
          # view.tooltip = "Rotate: #{angle_formatted}"
          
        # else
          # # rotating in 12ths
          # y = 12
          # x = (Math::tan(a) * y).round()
          # nearest_angle = Math::atan(x.to_f/y)
          # nearest_angle = -(180.degrees - nearest_angle)  if a >= 90.degrees || a <= -90.degrees
          
          # if (x.abs > 12) && ((x/2).floor == x/2.0)
            # x = x/2
            # y = y/2
          # end
          
          # Sketchup.vcb_label = 'Angle'
          # Sketchup.vcb_value = "#{-x}:#{y}"
          # view.tooltip = "Rotate: #{-x}:#{y}"
        # end

        # new_end = Geom::Point3d.new(@@protractor_rot_plane.normalize.to_a)
        # tr = Geom::Transformation.scaling(vector_to_end.length)
        # tr = Geom::Transformation.rotation(ORIGIN, @@protractor_plane[1], nearest_angle) * tr
        # tr = Geom::Transformation.translation(@picked_first_ip.position) * tr
        # end_pos = new_end.transform!(tr)
        
 #     end # protractor

      if picked_second_point?
        ph = view.pick_helper
		    ph.do_pick  @mouse_current_x, @mouse_current_y
		    best = ph.best_picked
        direction = @picked_first_ip.position.vector_to(@picked_second_ip.position)
        timber_plane = [@picked_first_ip.position, direction]
        if best
          line = [@mouse_ip.position, direction]  
          end_pos = Geom::intersect_line_plane( line, timber_plane )
        else
          ray = view.pickray(@mouse_current_x, @mouse_current_y )
          end_pos = Geom::intersect_line_plane( ray, timber_plane )
        end
      end
  
      points = []
      points << @picked_first_ip.position if picked_first_point?
      points << @picked_second_ip.position if picked_second_point?
      points << end_pos if @mouse_ip.valid?
      points
    end
    
    def draw_preview(view)
      if !picked_second_point?
        # draw a simple line to the second point
        points = picked_points(view)
        return unless points.size == 2
        
        view.set_color_from_line(points[0],points[1])
        view.line_width = 1
        view.line_stipple = ''
        view.draw(GL_LINES, points)
    
      else
        @@end_points = picked_points(view)
        return unless @@end_points.size == 3
        return if @@end_points[0] == @@end_points[2]
        
        #p @@end_points

        timber_points  = calculate_preview_points(@@end_points)
        return if timber_points.nil?
   
        points = create_drawing_points_quads(timber_points)
        
        #draw faces
        color = Sketchup.active_model.rendering_options["FaceFrontColor"]
        color.alpha = 170
        view.drawing_color = color
        view.draw(GL_QUADS, points)
        
        # draw edges
        points = create_drawing_points_lines(timber_points)
        
        view.set_color_from_line(timber_points[0],timber_points[4])
        view.line_width = 1
        view.line_stipple = ''
        view.draw(GL_LINES, points)
        
        # draw protractor
        #draw_whirly_gig(view) if @@protractor_state != 0
      end
    end
    
    # def draw_whirly_gig(view)
      # #p 'draw whirly'
      # size = view.pixels_to_model(400, @@protractor_points[0])
      # view.set_color_from_line([0,0,0],@@protractor_rot_plane.to_a )
      
      
      # tr = Geom::Transformation.scaling(ORIGIN, size)
      # tr = calc_transform(@@protractor_points[0], @@protractor_points[1]) * tr
      
      # view.line_width = 2
      # view.line_stipple = ''
      
      # if @@protractor_state == 1 # this is SU8 compatible - yet ugly
        # (0..@@whirly_points.size/2 - 1).each {|i|
            # view.draw(GL_LINES, @@whirly_points[2*i].transform(tr),@@whirly_points[2*i+1].transform(tr))
            # }
      # else
        # (0..@@whirly_slope_points.size/2 - 1).each{|i|
            # view.draw(GL_LINES, @@whirly_slope_points[2*i].transform(tr),@@whirly_slope_points[2*i+1].transform(tr))
            # }
      # end
    # end
    
    def create_drawing_points_quads(points_out)
      points = []
        points << points_out[0]
        points << points_out[1]
        points << points_out[2]
        points << points_out[3]
        
        points << points_out[4]
        points << points_out[7]
        points << points_out[6]
        points << points_out[5]
                   
        points << points_out[0]
        points << points_out[1]
        points << points_out[5]
        points << points_out[4]
                   
        points << points_out[1]
        points << points_out[2]
        points << points_out[6]
        points << points_out[5]
                   
        points << points_out[2]
        points << points_out[3]
        points << points_out[7]
        points << points_out[6]
                   
        points << points_out[3]
        points << points_out[0]
        points << points_out[4]
        points << points_out[7]
      points
    end
 
    def create_drawing_points_lines(points_out)
      points = []
        points << points_out[0]
        points << points_out[1]
        points << points_out[1]
        points << points_out[2]
        points << points_out[2]
        points << points_out[3]
        points << points_out[3]
        points << points_out[0]
        
        points << points_out[0]
        points << points_out[4]
        points << points_out[1]
        points << points_out[5]
        points << points_out[2]
        points << points_out[6]
        points << points_out[3]
        points << points_out[7]

        points << points_out[4]
        points << points_out[5]
        points << points_out[5]
        points << points_out[6]
        points << points_out[6]
        points << points_out[7]
        points << points_out[7]
        points << points_out[4]
      points
    end
    
    def calculate_preview_points(end_points)
      points_cube = [[0,0,0],[0,1,0],[0,1,-1],[0,0,-1],[1,0,0],[1,1,0],[1,1,-1],[1,0,-1]]
      t_width, t_height = SW::TimberTools.get_active_timber_size() #in preferences.rb

      direction = end_points[0].vector_to(end_points[1])
      direction_blue = end_points[0].vector_to(end_points[2])
      return if direction.length == 0
 
      #scale to the active lumber dimensions
      tr = Geom::Transformation.scaling(ORIGIN,  direction_blue.length, t_width, t_height)

      # rotate around the timbers blue axis
      tr = Geom::Transformation.rotation(ORIGIN, X_AXIS, @@instance_rotation) * tr
      
      # rotate around 3D
      tr = Geom::Transformation.axes(ORIGIN, direction_blue, direction, direction_blue * direction) * tr

      # translate to the first input point
      tr = Geom::Transformation.translation(end_points[0]) * tr
      
      points_out =  points_cube.map { |pt| pt.transform( tr ) }
    end 
    
    #######################
    ###  Add Timber   #####
    #######################
    
    def add_timber_to_model(len = nil)
      return if !len.nil? && (@@latest_timber.nil? && !picked_first_point?)    
      model = Sketchup.active_model
      model.start_operation('Add New Timber', true)
      
      add_timber_instance(len)
      TimberTools.label_timber(@@latest_timber)
      
      model.selection.clear
      model.selection.add(@@latest_timber)
      model.commit_operation
    end

    #####
    # Add a new timber instance to the active_entities
    # len  - is a length typed into the VCB
     
    def add_timber_instance(len = nil)
      @@end_points_saved = @@end_points if picked_first_point? #we are adding a new timber
      
      points_cube = [[0,0,0],[0,1,0],[1,1,0],[1,0,0],[0,0,1],[0,1,1],[1,1,1],[1,0,1]]
      t_width, t_height = SW::TimberTools.get_active_timber_size() #in preferences.rb
      direction = @@end_points_saved[0].vector_to(@@end_points_saved[1])
      direction_blue = @@end_points_saved[0].vector_to(@@end_points_saved[2])

      if !len.nil? # we were called by the VCB
        @@latest_timber.erase! if @@latest_timber
        direction.length = len
      end
      @@instance_rotation_saved = @@instance_rotation
      
      model = Sketchup.active_model
      new_def = model.definitions.add('Component')
      ents = new_def.entities
      
      # transform the group 
      tr = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees)
      tr = Geom::Transformation.rotation(ORIGIN, X_AXIS, @@instance_rotation) * tr
      tr = Geom::Transformation.axes(ORIGIN, direction_blue, direction, direction_blue * direction) * tr
      tr = Geom::Transformation.translation(@@end_points[0]) * tr
      
      @@latest_timber = model.active_entities.add_instance(new_def, tr)
      
      # add a layer for the timbers
      #timber_layer = model.layers.add "timber"
      #@@latest_timber.layer = timber_layer
      
      # add a layer for the timbers
      @timber_layer = model.layers.add('timber') if !@timber_layer
      @timber_layer = model.layers.add('timber') if @timber_layer && @timber_layer.deleted?

      ### add a layer for the timbers
      ###@timber_ends_layer = model.layers.add('timber ends') if !@timber_ends_layer
      ###@timber_ends_layer = model.layers.add('timber ends') if @timber_ends_layer && @timber_ends_layer.deleted?
      
      @@latest_timber.layer = @timber_layer
      
      #scale
      tr = Geom::Transformation.scaling(ORIGIN, t_height,  t_width, direction_blue.length)
      points_out =  points_cube.map { |pt| pt.transform( tr ) }
      
      ents.add_face(points_out[0], points_out[1], points_out[2], points_out[3])
      ents.add_face(points_out[7], points_out[6], points_out[5], points_out[4])
      ents.add_face(points_out[0], points_out[1], points_out[5], points_out[4])
      ents.add_face(points_out[1], points_out[2], points_out[6], points_out[5])
      ents.add_face(points_out[2], points_out[3], points_out[7], points_out[6])
      ents.add_face(points_out[3], points_out[0], points_out[4], points_out[7])
      
      
      ###grp = ents.add_group
      ###grp.layer = @timber_ends_layer
      ###grp.name = 'timber ends'
      ###ents2 = grp.entities
      ###ents2.add_line(points_out[0], points_out[2])
      ###ents2.add_line(points_out[1], points_out[3])
      ###ents2.add_line(points_out[4], points_out[6])
      ###ents2.add_line(points_out[5], points_out[7])

    
    end
  end # class Tool
  
 def self.activate_timber_new_rotate_tool
    Sketchup.active_model.select_tool(TimberNewRotateTool.new)
  end
  
    
end
end
