# SW::TimberTools.reload

module SW
module TimberTools

  def self.flip_selected_timber(axis)
    model = Sketchup.active_model
    sel = check_selected_component(model.selection)
    if sel == nil
      return UI.messagebox("not a component instance") 
    end
    model.start_operation("Flip Timber", true)
    timber_flip_along(sel, axis)
    model.commit_operation
  end 

  def self.timber_flip_along(ent, axis)
    point = ent.bounds.center
    tr = Geom::Transformation.scaling(point, -1,1,1) if axis == "x"
    tr = Geom::Transformation.scaling(point, 1,-1,1) if axis == "y"
    tr = Geom::Transformation.scaling(point, 1,1,-1) if axis == "z"
    ent.transform!(tr)
  end

  def self.rotate_selected_timber(axis)
    model = Sketchup.active_model
    sel = check_selected_component(model.selection)
    if sel == nil
      return UI.messagebox("not a component instance")
    end
    model.start_operation("Rotate Timber", true)
    timber_rotate_around(sel, axis)
    model.commit_operation
  end 

  def self.timber_rotate_around(ent, axis)
    point = ent.bounds.center
    tr = Geom::Transformation.rotation(point, Z_AXIS, -90.degrees) if axis == "cw"
    tr = Geom::Transformation.rotation(point, Z_AXIS, 90.degrees) if axis == "ccw"
    tr = Geom::Transformation.rotation(point, Z_AXIS, 180.degrees) if axis == "180"
    ent.transform!(tr)
  end
  
  
  #initialize menus
  if !file_loaded?("timber_flipper.rb")
    UI.add_context_menu_handler do |menu|
        submenu = menu.add_submenu("Timber Flip Rotate Along")
        submenu.add_item("Flip Along Model Red") {flip_selected_timber('x')}
        submenu.add_item("Flip Along Model Green") {flip_selected_timber('y')}
        submenu.add_item("Flip Along Model Blue") {flip_selected_timber('z')}
        submenu.add_item("Rotate 90 Around Blue CW") {rotate_selected_timber('cw')}
        submenu.add_item("Rotate 90 Around Blue CWW") {rotate_selected_timber('ccw')}
        submenu.add_item("Rotate Around Blue 180") {rotate_selected_timber('180')}
    end  
  end
file_loaded("timber_flipper.rb")
end 
end