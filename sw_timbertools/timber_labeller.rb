module SW
module TimberTools

  # helper method to make sure that one and only one component is selected
  def	self.check_selected_component(sel)
    return nil if sel.count != 1 || !sel[0].instance_of?(Sketchup::ComponentInstance)
    sel[0]
  end

  def	self.get_dimensions(e)
    scale_x = ((Geom::Vector3d.new 1,0,0).transform! e.transformation).length
    scale_y = ((Geom::Vector3d.new 0,1,0).transform! e.transformation).length
    scale_z = ((Geom::Vector3d.new 0,0,1).transform! e.transformation).length
    bb = e.definition.bounds
    [bb.width  * scale_x, bb.height * scale_y, bb.depth  * scale_z ]
  end

  def self.rotateXYZ(ent, axis,angle)
    rv = Geom::Vector3d.new(0,0,1) if axis == "z"
    rv = Geom::Vector3d.new(0,1,0) if axis == "y"
    rv = Geom::Vector3d.new(1,0,0) if axis == "x"
    ra = angle.degrees
    rp = Geom::Point3d.new(ent.bounds.corner(0)) 		#rotation point lower,left,corner
    ent.transform!(Geom::Transformation.rotation(rp, rv, ra))
  end

  def self.move(ent,x,y,z)
    ent.transform!(Geom::Transformation.new([x,y,z]))
  end

  def self.unlabel_selected_timber
    model = Sketchup.active_model
   
    #check for a single componentInstance 
    sel = check_selected_component(model.selection)
    if sel == nil
      return UI.messagebox ("not a component instance")
    end
    model.start_operation("Remove Timber Labels", true)
      find_erase_labels(sel.definition.entities)
    model.commit_operation
  end
  
  def self.find_erase_labels(ents)
    togo = ents.select {|e|  e.attribute_dictionary "TimberTools"}
    ents.erase_entities(togo)
  end
  

  ###This routine assumes theat the component to be labeled has blue
  ### axis on the long dimension
  ################
  def self.label_selected_timber(start_new_operation = true)
    model = Sketchup.active_model
    model.start_operation("Label Timbers", true)
    sel = check_selected_component(model.selection)
    return UI.messagebox( "not a component instance") if sel == nil
    label_timber(sel)
    model.commit_operation
  end
  
  def self.label_timber(sel)
    model = Sketchup.active_model
    
    # add a layer for the labels
    ref_layer = model.layers.add "timber refs"

    #name the component by the instance name if present
    label_text = sel.name == "" ? sel.definition.name : sel.name

    #erase old labels
    find_erase_labels(sel.definition.entities)
    
    #get the real dimensions of the component
    dimsx,dimsy,dimsz  = get_dimensions(sel)

    #make thte text size be the lesser of the two sides
    dimsx<dimsy ? dimsy=dimsx : dimsx=dimsy
    
    # label 1st reference faces the component
    label_group = sel.definition.entities.add_group
    label_group.layer = ref_layer
    label_group.entities.add_3d_text(label_text, TextAlignLeft, "Arial",false, false, (dimsx*0.6), 0.0, 0, true, 0)
      
    #move 1st label onto beam
    lcz = ((dimsz - label_group.bounds.width)/2) # z distance to move
    lcx = dimsx * 0.9
    move(label_group,lcx,0,lcz)
    rotateXYZ(label_group,"x",90)
    rotateXYZ(label_group,"y",270)
    label_group.set_attribute "TimberTools", "Label", true
    
    
    # label 2nd reference faces the component
    label_group = sel.definition.entities.add_group
    label_group.layer = ref_layer
    label_group.entities.add_3d_text(label_text, TextAlignLeft, "Arial",false, false, (dimsy*0.6), 0.0, 0, true, 0)

    # we rotate around a cpoint
    acpoint = label_group.entities.add_cpoint(Geom::Point3d.new(0,0,0))

    #move 2nd label onto beam
    lcz = dimsz-((dimsz - label_group.bounds.width)/2)  # z distance to move
    lcy = dimsy * 0.9 
    move(label_group,0,lcy,lcz)
    rotateXYZ(label_group,"y",90)
    rotateXYZ(label_group,"z",180)
    sel.definition.entities.erase_entities  acpoint
    
    
    label_group.set_attribute "TimberTools", "Label", true
  

  ########
  ### Add reference arrows to component
  ######
  # dimsx and dimsy are the smaller of the two dimension
  # dimsz is the length
  
    group = sel.definition.entities.add_group # intities to add labels to
    group.layer = ref_layer
    centerz =(dimsz /4) - 4

    widthz = dimsx * 0.75
    topz = centerz+( widthz / 2)
    bottomz = topz-widthz

    pts = []
    pts[0] = [0, 0, centerz]
    pts[1] = [widthz, 0, topz]
    pts[2] = [widthz, 0,bottomz]
    # Add the face to the entities in the model
    group.entities.add_face pts
    
    pts[0] = [0, 0, centerz]
    pts[1] = [0,widthz,topz]
    pts[2] = [0, widthz,bottomz]
    
    # Add the face to the entities in the mode l
    group.entities.add_face pts
    
      # mark groups as timber tools items
    group.set_attribute "TimberTools", "Label", true

  end # label_selected_timber

#initialize menus
if !file_loaded?("timber_labeller.rb")
  UI.add_context_menu_handler do |menu|
    if menu == nil then
      UI.messagebox("Error settting context menu handler")
    else
      menu.add_separator
      menu.add_item("Timber Add Label") {label_selected_timber}
      menu.add_item("Timber Remove Label") {unlabel_selected_timber}
    end	
  end
end
  
file_loaded("timber_labeller.rb")
end # module SW_TFT
end