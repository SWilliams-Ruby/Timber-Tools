module SW
module TimberTools

  # This routine assumes the component to be rolled out has blue
  # axis on the long dimension

  def self.rollout_timbers()
    model = Sketchup.active_model
    model.start_operation("Rollout Timbers", true)
    sel = model.selection[0]
    model.selection.clear
    model.close_active until model.entities == model.active_entities
    return UI.messagebox("not a component instance") if sel.class != Sketchup::ComponentInstance
    rollout_timber(sel)
    model.commit_operation
  end
  
  # roll out a timber
  def self.rollout_timber(sel)
    # create a defalult scene if none exists
    if Sketchup.active_model.pages.size == 0
      Sketchup.active_model.pages.add('Edit')
    end

    sel_def =  sel.definition
    load_style() # load the SW rollout style 
    page, layer = create_renew_scene(sel) # create a scene and a layer
    draw_instances(sel_def, layer) if layer # roll away
    set_camera() if layer
    page.update if page
  end
  
  # create four views of the definition
  def self.draw_instances(sel_def, layer)
    model = Sketchup.active_model
    entities = model.active_entities

    tr = Geom::Transformation.rotation([0, 0, 0], [0, 1, 0], 90.degrees)
    ent = entities.add_instance(sel_def, tr)
    ent.layer = layer
    
    depth =  ent.bounds.depth
    width  =  ent.bounds.height
    spacing = width < depth ? width : depth
    offset = depth + 3 * spacing
    
    tr = Geom::Transformation.rotation([0, width, 0], [0, 1, 0], 90.degrees)
    tr = Geom::Transformation.rotation(ent.bounds.center, [1, 0, 0], 90.degrees) * tr
    tr = Geom::Transformation.translation([0, 0, -offset]) * tr
    entities.add_instance(sel_def, tr).layer = layer

    offset += depth + 3 * spacing
    tr = Geom::Transformation.rotation([0, width, 0], [0, 1, 0], 90.degrees)
    tr = Geom::Transformation.rotation(ent.bounds.center, [1, 0, 0], 180.degrees) * tr
    tr = Geom::Transformation.translation([0, 0, -offset]) * tr
    entities.add_instance(sel_def, tr).layer = layer
    
    offset += depth + 3 * spacing
    tr = Geom::Transformation.rotation([0, width, 0], [0, 1, 0], 90.degrees)
    tr = Geom::Transformation.rotation(ent.bounds.center, [1, 0, 0], 270.degrees) * tr
    tr = Geom::Transformation.translation([0, 0, -offset]) * tr
    entities.add_instance(sel_def, tr).layer = layer
    
  end
  
  def self.create_renew_scene(sel)
    model = Sketchup.active_model
    pages = model.pages
   
    timber_name = sel.name != "" ? sel.name : sel.definition.name
    timber_name = "#{timber_name} detail"
    
    # create/erase the layer or return nil
    if model.layers[timber_name]
      result = UI.messagebox("This page already exists. Do you want to overwrite it?\nProbably not!", MB_YESNO)
      return [nil, nil] if result == IDNO
      return [nil, nil] if result == IDCANCEL
      model.layers.remove(timber_name, true)
    end
    rollout_layer = model.layers.add(timber_name)

    # create/select the page
    if pages[timber_name]
      rollout_page = pages[timber_name]
    else
      rollout_page = pages.add(timber_name)
    end
    pages.selected_page = rollout_page # make this active
      
    # hide the new layer on all other pages
    rollout_layer.page_behavior=LAYER_IS_HIDDEN_ON_NEW_PAGES
    pages.each{|page| page.set_visibility(rollout_layer, false) }
    rollout_page.set_visibility(rollout_layer, true)

    # hide all of the other layers in this scene
    layers = model.layers
    model.active_layer = rollout_layer # make this active
    layers.each {|layer| rollout_page.set_visibility(layer, layer.name == timber_name)}
    
    # show timber refs layer
    refs_layer = model.layers['timber refs']
    rollout_page.set_visibility(refs_layer, true)
    
    [rollout_page, rollout_layer]
  end # 
  
  def self.load_style()
    styles = Sketchup.active_model.styles
    style = styles['SW rollout style']

    unless style
      filename = File.join(PLUGIN_DIR,'styles/SW_rollout.style')
      Sketchup.active_model.styles.add_style(filename, true)
      style = styles['SW rollout style']
    end
    styles.selected_style = style
    styles.update_selected_style
  end
  
  def self.set_camera()
      camera = Sketchup.active_model.active_view.camera
      camera.perspective = false
      camera.set([5, -50000, 0], [ 50, 0, 0], [0, 0, 1])
      Sketchup.active_model.active_view.zoom_extents
  end

#initialize menus
if !file_loaded?("timber_create_rollout.rb")
  UI.add_context_menu_handler do |menu|
    if menu == nil then
      UI.messagebox("Error settting context menu handler")
    else
      menu.add_item("Timber Create RollOut") {rollout_timbers}
    end	
  end
end
  
file_loaded("timber_create_rollout.rb")
end # module SW_TFT
end

nil 