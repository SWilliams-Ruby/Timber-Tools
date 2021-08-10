# SW::TimberTools.reload
# shift and down_arrow will lock to arbitrary if vertex if not inference_locked?

module SW
module TimberTools
  
  class TimberNewTool
    include InferenceLock
    
    def activate
      Sketchup.vcb_label = "Timber Size #{SW::TimberTools.get_active_dimensions}"
      reset_tool()
      
      super
    end
    
    def reset_tool
      @mouse_ip = Sketchup::InputPoint.new
      @picked_first_ip = Sketchup::InputPoint.new
      @timber_start_point = nil
      @timber_end_point = nil
      @context_menu_open = false
      @entered_text = nil
      @protractor_state = 0
      @protractor_points = []
      @instance_rotation = 0.degrees

      reset_inference_locks()
      update_ui
    end
 
    def reset_inference_locks()
      @locked_to_vector = nil
      @locked_to_vk_down = nil 
      @locked_to_slope = nil

      Sketchup.active_model.active_view.lock_inference
    end

    
    def getExtents
      bb = Geom::BoundingBox.new
      bb.add(@timber_start_point) if @timber_start_point
      bb.add(@mouse_ip.position) if @mouse_ip.valid?
      
      # add protractor to BB
      if @protractor_state != 0
        pt = @protractor_points[0]
        size = Sketchup.active_model.active_view.pixels_to_model(400, pt)  
        bb.add([pt.x + size, pt.y + size, pt.z + size])
        bb.add([pt.x - size, pt.y - size, pt.z - size])
      end
      bb
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

    def update_ui
      if @timber_start_point
        Sketchup.status_text = 'Select end point.'
      else
        Sketchup.status_text = 'Select start point.'
      end
    end    
    
    def onSetCursor
      @cursor_normal ||= UI.create_cursor(File.join(PLUGIN_DIR, "images", 'timber new.png'), 1, 7)
      UI.set_cursor(@cursor_normal)
    end
      
    def enableVCB?
      return true
    end

    # Compatible with SketchUp 2014 and older:
    if Sketchup.version.to_i < 15
      def getMenu(menu)
        @context_menu_open = true
      end
    else
      def getMenu(menu, flags, x, y, view)
        @context_menu_open = true
      end
    end
    
    
    
    ### possible entries are 
    ### a length: 24' 5"
    ### a lumber dimension: 2x4, 2x4* nominal dimensions
    ### a locked_to_slope:  4:12
    
    def onUserText(text, view)
      begin
        case
        # is a width x height
        when ( dims = text.split(%r{[xX]}) ).size == 2
          dim2 = dims[1].split('*')
          raise ArgumentError unless dims[0].to_l > 0
          raise ArgumentError unless dim2[0].to_l > 0
          SW::TimberTools.set_new_timber_size(text) #in preferences.rb
          view.invalidate
          
        # is a slope  
        when ( dims = text.split(%r{[:]}) ).size == 2 
          reset_inference_locks()
          
          rise = dims[0].to_l
          run = dims[1].to_l
          @locked_to_slope = Math.atan(rise/run)
          
          # force recalculation of the end point
          onMouseMove(0, @mouse_x, @mouse_y, view) if @mouse_x && @mouse_y
          view.invalidate
           
        else
          # entry was a timber length
          if  @last_timber_added || @timber_start_point
            add_timber_to_model(text.to_l)
          end
          reset_tool()
          Sketchup.vcb_value = "" # erase the last VCB value
        end
        
      rescue ArgumentError
        view.tooltip = 'Invalid text entry'
      end
    end
    
    def current_ip
      @mouse_ip
    end
    
    def start_ip
       @picked_first_ip
    end
     
    def onLButtonDown(flags, x, y, view)
      # skip the first click after the context menu is opened
      if @context_menu_open
        @context_menu_open = false
        return
      end
      
      # if this is the start point
      if !@timber_start_point
        @picked_first_ip.copy!(@mouse_ip)
        @timber_start_point = @mouse_ip.position
        @last_timber_added = nil
        @instance_rotation = 0.0
        
      else
        if @timber_start_point.distance(@timber_end_point) !=  0
           add_timber_to_model()
           reset_tool
        end
      end
      
      update_ui
      reset_inference_locks()
      view.invalidate
    end
     
    def onKeyDown(key, repeat, flags, view)
      super # see Eneroth inference_lock.rb 
      
      if key == VK_DOWN
        # lock to any two arbitrary points
        if !@locked_to_vk_down
           @locked_to_vector = @timber_start_point.vector_to(@mouse_ip.position) 
           @locked_to_vk_down = true
        else 
          reset_inference_locks()
        end
      end
      
      if key == CONSTRAIN_MODIFIER_KEY && @timber_start_point && @mouse_ip.position != @timber_start_point
        # lock to any two arbitrary points
        @locked_to_vector  = @timber_start_point.vector_to(@mouse_ip.position) if @mouse_ip.vertex
      end
          
      # Show the protractor?
      if key == ALT_MODIFIER_KEY
        if @timber_start_point
          @protractor_state = (@protractor_state + 1) % 3
          if @protractor_state == 1
          
            @protractor_points[0] = @timber_start_point
            @protractor_points[1] = Geom::Point3d.new(@mouse_ip.position.x, @mouse_ip.position.y, @timber_start_point.z)
   
            direction = @timber_start_point.vector_to(@protractor_points[1])
            if !((direction.length == 0) || direction.parallel?(Z_AXIS))
              
              @protractor_rot_normal = direction
              @protractor_plane = [@picked_first_ip, direction.cross(Z_AXIS).reverse]
              
            else
              @protractor_state = 0
            end
            view.invalidate
          end
        end
        return true # inform windows that the key was handled
      end
      
      # rotate the timber around the long axis if the Control Key was pressed
      if key == COPY_MODIFIER_KEY 
        @instance_rotation += 90.degrees
        @instance_rotation -= 360.degrees if @instance_rotation >= 360.degrees
        view.invalidate
      end
    end

    def onKeyUp(key, repeat, flags, view)
      super
      if key == CONSTRAIN_MODIFIER_KEY
        reset_inference_locks()
      end
    end

 

    def onMouseMove(flags, x, y, view)
      super
      @context_menu_open = false # reset
      
      if @timber_start_point
        @mouse_ip.pick(view, x, y, @picked_first_ip)
      else
        @mouse_ip.pick(view, x, y)
      end

      
      view.tooltip = @mouse_ip.tooltip if @mouse_ip.valid? 
      
      # find end pont
      @timber_end_point = @mouse_ip.position
      if !view.inference_locked?
        if @locked_to_vector
          @timber_end_point =  @mouse_ip.position.project_to_line(@timber_start_point, @locked_to_vector )
          
        elsif @locked_to_slope 
          direction = @timber_start_point.vector_to( @mouse_ip.position)
          hypo = Math.sqrt(direction.x**2+direction.y**2)
          @timber_end_point.z = hypo * Math.tan(@locked_to_slope) + @timber_start_point.z
          
        elsif @protractor_state != 0
          check_protractor(view)
        end
      end
      
      if @timber_start_point
          Sketchup.set_status_text( (@timber_start_point.distance(@timber_end_point)).to_s, SB_VCB_VALUE)
      end
      
      view.invalidate
    end
    
    def check_protractor(view)
        if @protractor_state != 0
        # find a point on the protractor plane
        ray = view.pickray(@mouse_x, @mouse_y )
        end_pos = Geom::intersect_line_plane( ray, @protractor_plane )
        
        #calculate the angle to the point and round to the "snap" points
        vector_to_end = @timber_start_point.vector_to(end_pos)
        a = @protractor_rot_normal.angle_between(vector_to_end)
        a = a * -1 if vector_to_end.z >= 0
        
        if @protractor_state == 1 
          # protractor with degrees
          snap_angle = 5.degrees
          diff = a % snap_angle

          if diff > snap_angle / 2.0
            nearest_angle = a + (snap_angle - diff)
          else
            nearest_angle = a - diff
          end
          display_angle = -nearest_angle
        
          angle_formatted = Sketchup.format_angle( display_angle )
          Sketchup.vcb_label = 'Angle'
          Sketchup.vcb_value = angle_formatted
          view.tooltip = "Slope: #{angle_formatted} degrees"
          
        else # @protractor_state == 2 
          # rotating in 12ths
          y = 12
          x = (Math::tan(a) * y).round()
          nearest_angle = Math::atan(x.to_f/y)
          nearest_angle = -(180.degrees - nearest_angle)  if a >= 90.degrees || a <= -90.degrees
          
          if (x.abs > 12) && ((x/2).floor == x/2.0)
            x = x/2
            y = y/2
          end
          
          Sketchup.vcb_label = 'Angle'
          Sketchup.vcb_value = "#{-x}:#{y}"
          view.tooltip = "Slope: #{-x}:#{y}"
        end
        
        new_end = Geom::Point3d.new(@protractor_rot_normal.normalize.to_a)
        tr = Geom::Transformation.scaling(vector_to_end.length)
        tr = Geom::Transformation.rotation(ORIGIN, @protractor_plane[1], nearest_angle) * tr
        tr = Geom::Transformation.translation(@picked_first_ip.position) * tr
        @timber_end_point = new_end.transform!(tr)
        
      end # protractor
    end

   
    
    #######################
    ###  Draw  Routines ###
    #######################

    def draw(view)
      draw_outline(view)
      super # draw perpendiculars
      
      @mouse_ip.draw(view) if @mouse_ip.display?
      @picked_first_ip.draw(view) if !@picked_first_ip.nil? && @picked_first_ip.valid? && @picked_first_ip.display?
      #Sketchup.vcb_label = "Timber Size #{SW::TimberTools.get_active_dimensions}"
    end
    
    def draw_outline(view)
      return if !@timber_start_point
      return if !@timber_end_point
      return if @timber_start_point.distance(@timber_end_point) ==  0
      
      timber_points  = calculate_outline_points(@timber_start_point, @timber_end_point)
      
      #draw faces
      points = create_quads(timber_points)
      color = Sketchup.active_model.rendering_options["FaceFrontColor"]
      color.alpha = 170
      view.drawing_color = color
      view.draw(GL_QUADS, points)
      
      # draw edges
      points = create_lines(timber_points)
      view.set_color_from_line(timber_points[0],timber_points[4])
      view.drawing_color = 'fuchsia'  if @perpendicular_to_edge  ||  @perpendicular_to_face
      view.line_width = 1
      view.line_stipple = ''
      view.draw(GL_LINES, points)
      
      # draw protractor
      draw_whirly_gig(view) if @protractor_state != 0
    end
    
    def draw_whirly_gig(view)
      #p 'draw whirly'
      size = view.pixels_to_model(400, @protractor_points[0])
      view.set_color_from_line([0,0,0],@protractor_rot_normal.to_a )
      
      tr = Geom::Transformation.scaling(ORIGIN, size)
      tr = calc_beam_transform(@protractor_points[0], @protractor_points[1]) * tr
      
      view.line_width = 2
      view.line_stipple = ''
      
      if @protractor_state == 1 # this is SU8 compatible - yet ugly
        (0..@@whirly_points.size/2 - 1).each {|i|
            view.draw(GL_LINES, @@whirly_points[2*i].transform(tr),@@whirly_points[2*i+1].transform(tr))
            }
      else
        (0..@@whirly_slope_points.size/2 - 1).each{|i|
            view.draw(GL_LINES, @@whirly_slope_points[2*i].transform(tr),@@whirly_slope_points[2*i+1].transform(tr))
            }
      end
    end
    
    def create_quads(points_out)
      points = []
        points << points_out[0] << points_out[1] << points_out[2] << points_out[3]
        points << points_out[4] << points_out[7] << points_out[6] << points_out[5]
        points << points_out[0] << points_out[1] << points_out[5] << points_out[4]
        points << points_out[1] << points_out[2] << points_out[6] << points_out[5]
        points << points_out[2] << points_out[3] << points_out[7] << points_out[6]
        points << points_out[3] << points_out[0] << points_out[4] << points_out[7]
      points
    end
 
    def create_lines(points_out)
      points = []
        points << points_out[0] << points_out[1] << points_out[1] << points_out[2]
        points << points_out[2] << points_out[3] << points_out[3] << points_out[0]
        points << points_out[0] << points_out[4] << points_out[1] << points_out[5]
        points << points_out[2] << points_out[6] << points_out[3] << points_out[7]
        points << points_out[4] << points_out[5] << points_out[5] << points_out[6]
        points << points_out[6] << points_out[7] << points_out[7] << points_out[4]
      points
    end
    
    def calculate_outline_points(start_point, end_point)
      points_cube = [[0,0,0],[0,1,0],[0,1,-1],[0,0,-1],[1,0,0],[1,1,0],[1,1,-1],[1,0,-1]]
      t_width, t_height = SW::TimberTools.get_active_timber_size() #in preferences.rb
      
      direction = start_point.vector_to(end_point)
      return if direction.length == 0
 
      #scale to the active lumber dimensions
      tr = Geom::Transformation.scaling(ORIGIN,  direction.length, t_width, t_height)
      tr = Geom::Transformation.rotation(ORIGIN, X_AXIS, @instance_rotation) * tr
      tr = calc_beam_transform(start_point, end_point) * tr
      points_out =  points_cube.map { |pt| pt.transform( tr ) }
    end 
    
    # returns a 3D transformation
    def calc_beam_transform(start_point, end_point)
      # vector from start to end
      axis1 = start_point.vector_to(end_point) 

      # create a plane perpendicular to the axis
      plane1 = [start_point, axis1]

      # define a second plane parallel to the X_Y plane at Z height
      plane2 =  [[0, 0, end_point.z] , Z_AXIS]

      # find the intersection and get the cross product
      line = Geom.intersect_plane_plane(plane1, plane2)
      
      # if we are drawing on the Z_axis there is no intersection
      axis2 = line.nil? ? X_AXIS : line[1]

      cross = axis1 * axis2
      
      tr = Geom::Transformation.axes(ORIGIN, axis1, axis2.reverse, cross.reverse)
      tr = Geom::Transformation.translation(start_point) * tr

      tr
    end
    
    #######################
    ###  Add Timber   #####
    #######################
    
    def add_timber_to_model(len = nil)
      model = Sketchup.active_model
      model.start_operation('Add New Timber', true)
      add_timber_instance(len)
      TimberTools.label_timber(@last_timber_added)
      
      model.selection.clear
      model.selection.add(@last_timber_added)
      model.commit_operation
    end

    #####
    # Add a new timber instance or redraw the last timber
    # 
    #
    # 
    # len  - is a length typed into the VCB
    #
    
    def add_timber_instance(len = nil)
      model = Sketchup.active_model
      @end_points_saved = [@timber_start_point, @timber_end_point] if @timber_start_point #if we are adding a new timber
      @instance_rotation_saved = @instance_rotation

      t_width, t_height = SW::TimberTools.get_active_timber_size() #in preferences.rb
      
      # transform for component
      tr = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees)
      tr = Geom::Transformation.rotation(ORIGIN, X_AXIS, @instance_rotation_saved) * tr
      tr = calc_beam_transform(@end_points_saved[0], @end_points_saved[1]) * tr
      
      # re-use or create a new instance
      if @last_timber_added && !@last_timber_added.deleted?
        @last_timber_added.definition.entities.clear!
      else
        new_def = model.definitions.add('Timber ')
        @last_timber_added = model.active_entities.add_instance(new_def, tr)
      end
      ents = @last_timber_added.definition.entities
      
      # add a layer for the timbers
      @timber_layer = model.layers.add('timber') if !@timber_layer
      @timber_layer = model.layers.add('timber') if @timber_layer && @timber_layer.deleted?

      ### add a layer for the timbers ends
      ###@timber_ends_layer = model.layers.add('timber ends') if !@timber_ends_layer
      ###@timber_ends_layer = model.layers.add('timber ends') if @timber_ends_layer && @timber_ends_layer.deleted?
      
      @last_timber_added.layer = @timber_layer
      
      points_cube = [[0,0,0],[0,1,0],[1,1,0],[1,0,0],[0,0,1],[0,1,1],[1,1,1],[1,0,1]]
      t_width, t_height = SW::TimberTools.get_active_timber_size() #in preferences.rb
      direction = @end_points_saved[0].vector_to(@end_points_saved[1])
      
      if !len.nil? # we were called by the VCB
        direction.length = len
      end
            
      #scale
      tr = Geom::Transformation.scaling(ORIGIN, t_height,  t_width, direction.length)
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
  
  def self.activate_timber_new_tool
    Sketchup.active_model.select_tool(TimberNewTool.new)
  end
    
end
end
