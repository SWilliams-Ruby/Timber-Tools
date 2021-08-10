# Mixin for inference lock in tools.
#
# If any of the following Tool API methods are defined in the Tool class,
# they must call `super` for this mixin to function:
#
# * `activate`
# * `onKeyDown`
# * `onKeyUp`
# * `onKeyUp`
# * `onMouseMove`
#
# `current_ip` must be implemented by the Tool class for this mixin to function.
#
# `start_ip` may be implemented for finer control.
module InferenceLock
  # @api
  # @see https://ruby.sketchup.com/Sketchup/Tool.html
  def activate
    @axis_lock = nil
    @mouse_x = nil
    @mouse_y = nil
  end

  # @api
  # @see https://ruby.sketchup.com/Sketchup/Tool.html
  def onKeyDown(key, _repeat, _flags, view)
    if key == CONSTRAIN_MODIFIER_KEY
      try_lock_constraint(view)
    else
      try_lock_axis(key, view)
    end

    # Emulate mouse move to update InputPoint picking.
    onMouseMove(0, @mouse_x, @mouse_y, view) if @mouse_x && @mouse_y
    view.invalidate
  end

  # @api
  # @see https://ruby.sketchup.com/Sketchup/Tool.html
  def onKeyUp(key, _repeat, _flags, view)
    return unless key == CONSTRAIN_MODIFIER_KEY
    return if @axis_lock

    # Unlock inference.
    view.lock_inference
    # Emulate mouse move to update InputPoint picking.
    onMouseMove(0, @mouse_x, @mouse_y, view) if @mouse_x && @mouse_y
    view.invalidate
  end

  # @api
  # @see https://ruby.sketchup.com/Sketchup/Tool.html
  def onMouseMove(_flags, x, y, _view)
    # Memorize mouse positions to emulate a mouse move when inference is locked
    # or unlocked.
    @mouse_x = x
    @mouse_y = y
    
    # # Memorize edge and face edges if they are in the same context as the start point
    # @edges_count ||= 0
    # if current_ip.edge && (@latest_edge != current_ip.edge)
      # if (@edges_count += 1) == 6
        # @edges_count = 0
        # @latest_edge = current_ip.edge 
        # #p 'change edge'
        # @perp_edge = [current_ip.edge.start.position.transform(current_ip.transformation),
          # current_ip.edge.end.position.transform(current_ip.transformation)]
      # end
    # end

    # # Faces can have many edges so we memorize them only when there is a change
    # if current_ip.face
      # @latest_face_normal =  current_ip.face.normal.transform(current_ip.transformation)
      # @perp_face_edges = []
      # current_ip.face.edges.each {|e|
        # @perp_face_edges << e.start.position.transform(current_ip.transformation)
        # @perp_face_edges << e.end.position.transform(current_ip.transformation)
      # }
    # end
    
    # dir = start_ip.position.vector_to(current_ip.position)
    # if dir.length != 0 
      # if @latest_face_normal && @latest_face_normal.parallel?(dir)
        # @perpendicular_to_face = true
      # else
        # @perpendicular_to_face = false
      # end

      # if @perp_edge
        # dir2 =  @perp_edge[0].vector_to(@perp_edge[1])
        # angle = dir.angle_between(dir2) - 90.degrees
        # #p angle.radians
        
        # if angle.abs < 0.00000001
          # @perpendicular_to_edge = true 
        # else
          # @perpendicular_to_edge = false
        # end
        
      # end

    # end

  end
  
  def draw(view)
   # draw perpendicular referenced face or edge
    if @perpendicular_to_edge && @perp_edge
      view.drawing_color = 'fuchsia'
      view.line_width = 3
      view.line_stipple = ''
      view.draw_lines(*@perp_edge)
    end
    
    if @perpendicular_to_face && @perp_face_edges
      view.drawing_color = 'fuchsia'
      view.line_width = 3
      view.line_stipple = ''
      view.draw_lines(*@perp_face_edges)
    end
      
  end
  

  # Get reference to currently active InputPoint (the one picking a position
  # onMouseMove). Used for constraint (Shift) lock.
  #
  # This method MUST be overridden with a method in your tool class.
  #
  # `nil` or `#valid? == false` denotes constraint lock isn't currently
  # available.
  #
  # @return [Sketchup::InputPoint, nil]
  def current_ip
    raise NotImplementedError( "Override this method in class using mixin.")
  end

  # Get reference to InputPoint of operation start. Used for axis lock.
  #
  # This method MAY be overridden with a method in your tool class.
  #
  # `nil` or `#valid? == false` denotes axis lock isn't currently available.
  # For instance, in native Move tool axis lock isn't available until the
  # first point is selected.
  #
  # @return [Sketchup::InputPoint, nil] Defaults to `current_ip`.
  def start_ip
    current_ip
  end

  private

  # Try picking a constraint lock.
  #
  # @param view [Sketchup::View]
  def try_lock_constraint(view)
    return if @axis_lock
    return unless current_ip
    return unless current_ip.valid?

    view.lock_inference(current_ip)
  end

  # Try picking an axis lock for given keycode.
  #
  # @param key [Integer]
  # @param view [Sketchup::View]
  def try_lock_axis(key, view)
    return unless start_ip
    return unless start_ip.valid?

    case key
    when VK_RIGHT
      lock_inference_axis([start_ip.position, view.model.axes.xaxis], view)
    when VK_LEFT
      lock_inference_axis([start_ip.position, view.model.axes.yaxis], view)
    when VK_UP
      lock_inference_axis([start_ip.position, view.model.axes.zaxis], view)
    end
  end

  # Unlock inference lock to axis if there is any.
  #
  # @param view [Sketchup::view]
  def unlock_axis(view)
    # Any inference lock not done with `lock_inference_axis`, e.g. to the
    # tool's primary InputPoint, should be kept.
    return unless @axis_lock

    @axis_lock = nil
    # Unlock inference.
    view.lock_inference
  end

  # Lock inference to an axis or unlock if already locked to that very axis.
  #
  # @param line [Array<(Geom::Point3d, Geom::Vector3d)>]
  # @param view [Sketchup::View]
  def lock_inference_axis(line, view)
    return unlock_axis(view) if line == @axis_lock

    @axis_lock = line
    view.lock_inference(
      Sketchup::InputPoint.new(line[0]),
      Sketchup::InputPoint.new(line[0].offset(line[1]))
    )
  end
end
