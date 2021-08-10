# load 'imp_ene_solids/solids.rb'
# for possibly faster algos look at:
# take a look at Shellify by Anders Lyhagen 
# solid tools by ThomThom 
# solidsolver by TIG

#loaded the animated beachball cursor code (if not already installed) 
if !defined? Lulu::Beachballs
  begin
    require(File.join(File.dirname(__FILE__), "Lulu_Beachballs_core"))
  rescue LoadError
  end
end

module SW
module TimberTools

  # Various solid operations.
  #
  # To use these operators in your own project, copy the whole class into it
  # and into your own namespace (module).
  #
  # Face orientation is used on touching solids to determine whether faces
  # should be removed or not. Make sure faces are correctly oriented before
  # using.
  #
  # Differences from native solid tools:
  #  * Preserves original Group/ComponentInstance object with its own material,
  #    layer, attributes and other properties instead of creating a new one.
  #  * Preserves primitives inside groups/components with their own layers,
  #    attributes and other properties instead of creating new ones.
  #  * Ignores nested geometry, a house is for instance still a solid you can
  #    cut away a part of even if there's a cut-opening window component in the
  #    wall.
  #  * Operations on components alters all instances as expected instead of
  #    creating a new unique Group (that's what context menu > Make Unique is
  #    for).
  #  * Doesn't break material inheritance. If a Group/ComponentInstance itself
  #    is painted and child faces are not this will stay the same.
  #
  # I, Eneroth3, is much more of a UX person than an algorithm person. Someone
  # who is more of the latter might be able to optimize these operations and
  # make them more stable.
  #
  # If you contribute to the project, please don't mess up these differences
  # from the native solid tools. They are very much intended, and even the
  # reason why this project was started in the first place.
  class Solids
   
=begin # Trim one container using another.
    #
    # The primary Group/ComponentInstance keeps its material, layer, attributes
    # and other properties. Primitives inside both containers also keep their
    # materials, layers, attributes and other properties.
    #
    # primary          - The primary Group/ComponentInstance to trim using the
    #                    secondary one.
    # secondary        - The secondary Group/ComponentInstance to trim the
    #                    primary one with.
    # wrap_in_operator - True to add an operation so all changes can be undone
    #                    in one step. Set to false when called from custom
    #                    script that already uses an operator. (default: true)
    #
    # Returns true if result is a solid, false if something went wrong.
=end 
    def self.trim(primary, secondary, wrap_in_operator = true)
      subtract(primary, secondary, wrap_in_operator, true)
    end

    # Subtract one container from another.
    #
    # The primary Group/ComponentInstance keeps its material, layer, attributes
    # and other properties. Primitives inside both containers also keep their
    # materials, layers, attributes and other properties.
    #
    # primary          - The primary Group/ComponentInstance the secondary one
    #                    should be subtracted from.
    # secondary        - The secondary Group/ComponentInstance to subtract from
    #                    the primary one.
    # wrap_in_operator - True to add an operation so all changes can be undone
    #                    in one step. Set to false when called from custom
    #                    script that already uses an operator. (default: true)
    # keep_secondary   - Whether secondary should be left untouched. The same as
    #                    whether operation should be trim instead subtract.
    #                    (default: false)
    #
    # Returns true if result is a solid, false if something went wrong.

    def self.subtract(primary, secondary, wrap_in_operator = true, keep_secondary = false, scale = 1000, paint = nil)
      @is_multisub || Lulu::Beachballs.start() if defined? Lulu::Beachballs
      
      #Check if both groups/components are solid, and that there are edges
      return if !entities(primary).any? {|e| e.is_a?(Sketchup::Edge)} #
      return if !is_solid?(primary) || !is_solid?(secondary)
      op_name = keep_secondary ? "Trim" : "Subtract"
      primary.model.start_operation(op_name, true) if wrap_in_operator

      # Older SU versions doesn't automatically make Groups unique when they are
      # edited.
      # Components on the other hand should off course not be made unique here.
      # That is up to the user to do manually if they want to.
      primary.make_unique if primary.is_a?(Sketchup::Group)

      # scale every thing by 1000 or scale in the call
      transP = primary.transformation
      transS = secondary.transformation
      tr = Geom::Transformation.scaling(scale)
      primary.transform!(tr)
      secondary.transform!(tr)
      
      # make a reference copy of the original objects
      # and make a copy of the secondary that will be modified
      secondary_reference_copy = primary.parent.entities.add_group
	    secondary_reference_copy.name = 'secondary_reference_copy'
      move_into(secondary_reference_copy, secondary, true)

      secondary_to_modify = primary.parent.entities.add_group
	    secondary_to_modify.name = 'secondary_to_modify'
      move_into(secondary_to_modify, secondary, keep_secondary)
      
      togo = secondary_to_modify.entities.select{|e| [Sketchup::Group, Sketchup::ComponentInstance].include?(e.class)}
      secondary_to_modify.entities.erase_entities(togo)
      
      primary_reference_copy = primary.parent.entities.add_group
	    primary_reference_copy.name = 'primary_reference_copy'
      move_into(primary_reference_copy, primary, true)
      
      #transform secondary back to original scale if we are keeping it
      secondary.transformation = transS if keep_secondary

      #grab the entities collections
      primary_ents = entities(primary)
      secondary_ents = entities(secondary_to_modify)
      
      # collect the coplanar and unattached edges of the object 
      old_coplanar = cache_stray_edges(primary, secondary_to_modify, true)
      
      # intersect A into B, and B into A
      intersect_wrapper(primary, secondary_to_modify)
      
      # Remove faces in primary that are inside the secondary and faces in
      # secondary that are outside primary.
      to_remove = find_faces_inside_outside(primary, secondary_reference_copy, true)
      to_remove1 = find_faces_inside_outside(secondary_to_modify, primary_reference_copy, false)
      secondary_reference_copy.erase!
	    primary_reference_copy.erase!
      
      # Remove faces that exists in both groups and have opposite orientation.
      corresponding = find_corresponding_faces(primary, secondary_to_modify, true)
      corresponding.each_with_index { |v, i| ((i & 0x01) == 0) ? to_remove << v : to_remove1 << v }
      primary_ents.erase_entities(to_remove)
      secondary_ents.erase_entities(to_remove1)
      
      # Reverse all faces in secondary
      secondary_ents.each { |f| f.reverse! if f.is_a? Sketchup::Face }
         
      # paint the cut faces if paint defined
      secondary_ents.each {|f| f.material = paint if f.is_a? Sketchup::Face} if paint 
           
      # combine the two objects
      move_into(primary, secondary_to_modify, false)
      
      # Purge edges not binding 2 faces
      primary_ents.erase_entities(primary_ents.select {|e| e.is_a?(Sketchup::Edge) && e.faces.length < 2})
          
      # Remove co-planar edges
      primary_ents.erase_entities(find_coplanar_edges(primary_ents))
          
      # restore the coplanar and unattached edges of the object 
      old_coplanar.each {|e| primary_ents.add_edges(e[0], e[1])}
         
      # unscale object
      primary.transformation = transP
      
      primary.model.commit_operation if wrap_in_operator
      
    ensure
      @is_multisub || Lulu::Beachballs.stop() if defined? Lulu::Beachballs
      return is_solid?(primary)
    end

 
=begin    # Unite one container with another.
    #
    # The primary Group/ComponentInstance keeps its material, layer, attributes
    # and other properties. Primitives inside both containers also keep their
    # materials, layers, attributes and other properties.
    #
    # primary          - The primary Group/ComponentInstance the secondary one
    #                    should be added to.
    # secondary        - The secondary Group/ComponentInstance to add to the
    #                    primary one.
    # wrap_in_operator - True to add an operation so all changes can be undone
    #                    in one step. Set to false when called from custom
    #                    script that already uses an operator. (default: true)
    #
    # Returns true if result is a solid, false if something went wrong.
=end
    def self.union(primary, secondary, wrap_in_operator = true)
      Lulu::Beachballs.start() if defined? Lulu::Beachballs
      
      #Check if both groups/components are solid.
      return if !is_solid?(primary) || !is_solid?(secondary)
      primary.model.start_operation("Union", true) if wrap_in_operator

      # Older SU versions doesn't automatically make Groups unique when they are
      # edited.
      # Components on the other hand should off course not be made unique here.
      # That is up to the user to do manually if they want to.
      primary.make_unique if primary.is_a?(Sketchup::Group)

      # scale every thing by 1000
      scale = 1000
      transP = primary.transformation
      transS = secondary.transformation
      tr = Geom::Transformation.scaling(scale)
      primary.transform!(tr)
      secondary.transform!(tr)
      
      # make a reference copy of the original objects
      # make a copy of the secondary that will be modified
      secondary_reference_copy = primary.parent.entities.add_group
	    secondary_reference_copy.name = 'secondary_reference_copy'
      move_into(secondary_reference_copy, secondary, true)
      
      secondary_to_modify = primary.parent.entities.add_group
	    secondary_to_modify.name = 'secondary_to_modify'
      move_into(secondary_to_modify, secondary, false)
           
      primary_reference_copy = primary.parent.entities.add_group
	    primary_reference_copy.name = 'primary_reference_copy'
      move_into(primary_reference_copy, primary, true)
          
      #grab the entities collections
      primary_ents = entities(primary)
      secondary_ents = entities(secondary_to_modify)

      # collect the coplanar and unattached edges of the object 
      old_coplanar = cache_stray_edges(primary, secondary_to_modify, true, true)
      
      # intersect A into B, and B into A
      intersect_wrapper(primary, secondary_to_modify)
      
      # Remove faces inside primary and inside secondary
      to_remove = find_faces_inside_outside(primary, secondary_reference_copy, true)
      to_remove1 = find_faces_inside_outside(secondary_to_modify, primary_reference_copy, true)
	    secondary_reference_copy.erase!
	    primary_reference_copy.erase!
          
      # Remove faces that exists in both groups and have opposite orientation.
      #  todo: the function can return two arrays like  fg, eg = parse_input(sel)
      corresponding = find_corresponding_faces(primary, secondary_to_modify, false)
      corresponding.each_with_index { |v, i| ((i & 0x01) == 0) ? to_remove << v : to_remove1 << v }
          
      primary_ents.erase_entities(to_remove)
      secondary_ents.erase_entities(to_remove1)
      
      # combine the two objects
      move_into(primary, secondary_to_modify, false)
      
      # Purge edges naked edges
      primary_ents.erase_entities(primary_ents.select {|e| e.is_a?(Sketchup::Edge) && e.faces.length == 0})
      
      # Remove co-planar edges
      primary_ents.erase_entities(find_coplanar_edges(primary_ents))
                
      # restore the coplanar and unattached edges of the object 
      old_coplanar.each {|e| primary_ents.add_edges(e[0], e[1])}
      
      # unscale object
      primary.transformation = transP
      
      primary.model.commit_operation if wrap_in_operator
    ensure 
      Lulu::Beachballs.stop() if defined? Lulu::Beachballs
      return is_solid?(primary)
    end


=begin    # Intersect containers.
    #
    # The primary Group/ComponentInstance keeps its material, layer, attributes
    # and other properties. Primitives inside both containers also keep their
    # materials, layers, attributes and other properties.
    #
    # primary          - The primary Group/ComponentInstance the intersect
    #                    intersect result will be put in.
    # secondary        - The secondary Group/ComponentInstance.
    # wrap_in_operator - True to add an operation so all changes can be undone
    #                    in one step. Set to false when called from custom
    #                    script that already uses an operator. (default: true)
    #
    # Returns true if result is a solid, false if something went wrong.
=end
    def self.intersect(primary, secondary, wrap_in_operator = true)
      Lulu::Beachballs.start() if defined? Lulu::Beachballs
      
      #Check if both groups/components are solid.
      return if !is_solid?(primary) || !is_solid?(secondary)
      primary.model.start_operation("Intersect", true) if wrap_in_operator
      
      # Older SU versions doesn't automatically make Groups unique when they are
      # edited.
      # Components on the other hand should off course not be made unique here.
      # That is up to the user to do manually if they want to.
      primary.make_unique if primary.is_a?(Sketchup::Group)
      
      # scale every thing by 1000
      scale = 1000
      transP = primary.transformation
      transS = secondary.transformation
      tr = Geom::Transformation.scaling(scale)
      primary.transform!(tr)
      secondary.transform!(tr)
      
      # make a reference copy of the original objects
      # make a copy of the secondary that will be modified
      secondary_reference_copy = primary.parent.entities.add_group
	    secondary_reference_copy.name = 'secondary_reference_copy'
      move_into(secondary_reference_copy, secondary, true)
      
      secondary_to_modify = primary.parent.entities.add_group
	    secondary_to_modify.name = 'secondary_to_modify'
      move_into(secondary_to_modify, secondary, false)
           
      primary_reference_copy = primary.parent.entities.add_group
	    primary_reference_copy.name = 'primary_reference_copy'
      move_into(primary_reference_copy, primary, true)
      
      #grab the entities collections
      primary_ents = entities(primary)
      secondary_ents = entities(secondary_to_modify)

      # collect the coplanar and unattached edges of the object 
      old_coplanar = cache_stray_edges(primary, secondary_to_modify) #does nothing
      
      # intersect A into B, and B into A
      intersect_wrapper(primary, secondary_to_modify)
        
      # Remove faces in primary that are outside of the secondary
      # and faces in secondary that are outside primary.
      to_remove = find_faces_inside_outside(primary, secondary_reference_copy, false)
      to_remove1 = find_faces_inside_outside(secondary_to_modify, primary_reference_copy, false)
      primary_ents.erase_entities(to_remove)
      secondary_ents.erase_entities(to_remove1)
           
      # done with these!
	    secondary_reference_copy.erase!
	    primary_reference_copy.erase!
      	  
      # combine the two objects
      move_into(primary, secondary_to_modify, false)
        
      # Purge edges not binding 2 faces
      primary_ents.erase_entities(primary_ents.select {|e| e.is_a?(Sketchup::Edge) && e.faces.length < 2})
      
      # restore the coplanar and unattached edges of the object 
      old_coplanar.each {|e| primary_ents.add_edges(e[0], e[1])} #there is nothing to restore
      
      # unscale object
      primary.transformation = transP
      
      primary.model.commit_operation if wrap_in_operator
      
      
    ensure
      Lulu::Beachballs.stop() if defined? Lulu::Beachballs
      return is_solid?(primary)
    end
    
=begin    
    # Multi subtract - trim the secondary object from an array of primary objects
    # primary      array of objects to be cut
    # secondary    group or component to cut with 
    # settings    hash:
    #   cut_sub   if true subtract from subcomponents
    #   hide      if true hide the secondary object after the operation is finished
    #   paint     if true paint the new faces with a 'dark dark grey' material
    #   unique    if true, make each target object unique
    # return value is undefined
=end

    def self.multisub(primary, secondary, settings)
      @progress = 'Working |'
      @is_multisub = true
      Lulu::Beachballs.start() if defined? Lulu::Beachballs
      
      # Create a material to apply to the cut faces if settings[:paint]
      # I can imagine painting cut faces with cross hatching, etc.
      if settings[:paint]
        model = Sketchup.active_model
        materials = model.materials
        paint = materials['Ene_Cut_Face_Color']
        if !paint
          paint = materials.add('Ene_Cut_Face_Color') 
          #@paint.color = 'red'
          paint.color = 'DimGray'
        end 
      else
        paint = nil      
      end
      
      multisub_recurse(primary, secondary, scale = 1000, paint, settings[:cut_sub], settings[:unique])
      
    ensure 
      Lulu::Beachballs.stop() if defined? Lulu::Beachballs
      @is_multisub = nil
    end

  private
    
    # Recursively subtract the secondary object from the primary
    # primary     array of component and group objects
    # secondary   component or a group
    # scale       scale for the top level Dave Method
    # paint       nil or a sketchup material
    # cut_sub     if true then recurse
    # unique      if true make primary objects unique
    
    def self.multisub_recurse(primary, secondary, scale, paint, cut_sub, unique)
      primary.each do |target|
        Sketchup.status_text = @progress
        @progress << '|'
        
        
        # running with scissors?
        next if target == secondary 
        # quick but dirty exclude
        next unless target.bounds.intersect(secondary.bounds) 
        target.make_unique if unique
  
        if !subtract(target, secondary, false, true, scale, paint)  
         # if a primary group/component is totally empty sketchup will mark it as deleted
         # and it will be removed after the model.commit statement in tools.rb
         #puts 'Empty or Not Solid in Solids::multisub'
        end     
        
        next if cut_sub == false
        
        # recurse
        entities(target).select {|e| [Sketchup::Group, Sketchup::ComponentInstance].include?(e.class)}.each do |child|
          tr_save = child.transformation
          child.transformation = target.transformation * child.transformation
          multisub_recurse([child], secondary, 1, paint, cut_sub, unique)
          child.transformation = tr_save 
        end
      end
    end    
      
    # Internal: Get the Entities object for either a Group or ComponentInstance.
    # SU 2014 and lower doesn't support Group#definition.
    #
    # group_or_component - The group or ComponentInstance object.
    #
    # Returns an Entities object.
    def self.entities(group_or_component)
      if group_or_component.is_a?(Sketchup::Group)
        group_or_component.entities
      else
        group_or_component.definition.entities
      end
    end

    # Internal: Intersect solids and get intersection edges in both solids.
    #
    # ent0 - One of the groups or components to intersect.
    # ent1 - The other groups or components to intersect.
    #
    #Returns nothing.
    def self.intersect_wrapper(ent0, ent1)
      #Intersect twice to get coplanar faces.
      #Copy the intersection geometry to both solids.
        ents0 = entities(ent0)
        ents1 = entities(ent1)

        # create a temporary group to hold the result of the intersection
        temp_group = ent0.parent.entities.add_group
        temp_group.name = 'temp_group'
        
        #Only intersect raw geometry at this level of nesting.
        ents0.intersect_with(false, ent0.transformation, temp_group.entities, IDENTITY, true, ents1.select {|e| e.is_a?(Sketchup::Face)})
        
        ents1.intersect_with(false, ent0.transformation.inverse, temp_group.entities, ent0.transformation.inverse, true, ents0.select {|e| e.is_a?(Sketchup::Face)})
        
        
        move_into(ent0, temp_group, true)
        move_into(ent1, temp_group, false)
        
        # fix missing faces. after an intersect_with or move_into() there may be missing faces
        list = ents0.select { |e| e.is_a?(Sketchup::Edge) && e.faces.length == 0 }
        list.each{|e| e.find_faces}
          
        list = ents1.select { |e| e.is_a?(Sketchup::Edge) && e.faces.length == 0 }
        list.each{|e| e.find_faces}
        
    end

    # Internal: Find arbitrary point inside face, not on its edge or corner.
    # face - The face to find a point in.
    # Returns a Point3d object.
    def self.point_in_face(face)
      # Sometimes invalid faces gets created when intersecting.
      # These are removed when validity check run.
      return if face.area == 0

      # First find centroid and check if is within face (not in a hole).
      centroid = face.bounds.center
      return centroid if face.classify_point(centroid) == Sketchup::Face::PointInside
	
      # Find points by combining 3 adjacent corners.
      # If middle corner is convex point should be inside face (or in a hole).
      face.vertices.each_with_index do |v, i|
        c0 = v.position
        c1 = face.vertices[i-1].position
        c2 = face.vertices[i-2].position
        p  = Geom.linear_combination(0.9, c0, 0.1, c2)
        p  = Geom.linear_combination(0.9, p,  0.1, c1)
        return p if face.classify_point(p) == Sketchup::Face::PointInside
      end
		  warn "Algorithm failed to find an arbitrary point on face."
      nil
    end

   
    # Internal: Find faces that exists with same location in both contexts.
    #
    # same_orientation - true to only return those oriented the same direction,
    #                    false to only return those oriented the opposite
    #                    direction and nil to skip direction check.
    #
    # Returns an array of faces, every second being in each drawing context.
    #
     
    
    def self.find_corresponding_faces(ent0, ent1, same_orientation)
      faces = []
      entities(ent0).each do |f0|
        next unless f0.is_a?(Sketchup::Face)
        normal0 = f0.normal.transform(ent0.transformation)
        points0 = f0.vertices.map { |v| v.position.transform(ent0.transformation) }
        entities(ent1).each do |f1|
          next unless f1.is_a?(Sketchup::Face)
          normal1 = f1.normal.transform(ent1.transformation)
          next unless normal0.parallel?(normal1)
          points1 = f1.vertices.map { |v| v.position.transform(ent1.transformation) }
          
          # this code was way too simple. We needed a two way comparison
          #next unless points0.all? { |v| points1.include?(v) }
          
          # Could this faster if we used some sort of lookup?
          # build a table of points..., polygonmesh
          next unless points0.all? { |v| points1.include?(v) } && points1.all? { |v| points0.include?(v) }
          unless same_orientation.nil?
            next if normal0.samedirection?(normal1) != same_orientation
          end
          faces << f0
          faces << f1
        end
      end

      faces
    end

    # Internal: Merges groups/components.
    # Requires both groups/components to be in the same drawing context.
    def self.move_into(destination, source, keep = false)
    
      destination_ents = entities(destination)
      source_def = source.is_a?(Sketchup::Group) ? source.entities.parent : source.definition

      temp = destination_ents.add_instance(source_def, source.transformation * destination.transformation.inverse)
      source.erase! unless keep
      
      temp.explode
    end
    
    
    # collect the coplanar and unattached edges of the object
    # these could for example represent drawing details and text the user wishes to keep
    # the flags offer some granularity 
    # Add this to coplanar? idea from TIG solid solver -&& e.faces[0].material==e.faces[1].material && e.faces[0].back_material==e.faces[1].back_material 
    def self.cache_stray_edges(primary, secondary, include_primary = false, include_secondary = false)
      coplanar = []

      if include_primary
        primary_ents = entities(primary)
        find_coplanar_edges(primary_ents).each {|e| coplanar << [e.start.position, e.end.position]}
        primary_ents.each {|e| coplanar << [e.start.position, e.end.position] if e.is_a?(Sketchup::Edge) && e.faces.length == 0}
      end
      
      if include_secondary
        tr = secondary.transformation * primary.transformation.inverse
        secondary_ents = entities(secondary)
        find_coplanar_edges(secondary_ents).each {|e| coplanar << [e.start.position.transform(tr), e.end.position.transform(tr)]}
        secondary_ents.each {|e| coplanar << [e.start.position.transform(tr), e.end.position.transform(tr)] if e.is_a?(Sketchup::Edge) && e.faces.length == 0}
      end
      
     coplanar
    end

    
    # Internal: Find all co-planar edges
    def self.find_coplanar_edges(ents)
      ents.select do |e|
        next unless e.is_a?(Sketchup::Edge)
        next unless e.faces.length == 2
        e.faces[0].normal == e.faces[1].normal
      end
   end
   
    # Internal: Find faces based on their position relative to the
    # other solid.
    def self.find_faces_inside_outside(source, reference, inside)
    entities(source).select do |f|
        next unless f.is_a?(Sketchup::Face)
        point = point_in_face(f)
        next unless point
        point.transform!(source.transformation)
        next if inside != inside_solid?(point, reference, !inside)
        true
      end
    end
      
    # Check whether Point3d is inside, outside or the surface of solid.
    #
    # point                - Point3d to test (in the coordinate system the
    #                        container lies in, not internal coordinates).
    # container            - Group or component to test point to.
    # on_face_return_value - What to return when point is on face of solid.
    #                        (default: true)
    # verify_solid         - First verify that container actually is
    #                        a solid. (default true)
    #
    # Returns true if point is inside container and false if outside. Returns
    # on_face_return_value when point is on surface itself.
    # Returns nil if container isn't a solid and verify_solid is true.
    #def self.inside_solid?(point, container, on_face_return_value = true)
    def self.inside_solid?(point, container, on_face_return_value)
      #return if verify_solid && !is_solid?(container)

      # Transform point coordinates into the local coordinate system of the
      # container. The original point should be defined relative to the axes of
      # the parent group or component, or, if the user has that drawing context
      # open, the global model axes.
      #
      # All method that return coordinates, e.g. #transformation and #position,
      # returns them local coordinates when the container isn't open and global
      # coordinates when it is. Usually you don't have to think about this but
      # as usual the (undocumented) attempts in the SketchUp API to dumb things
      # down makes it really odd and difficult to understand.
      point = point.transform(container.transformation.inverse)

      # Cast a ray from point in arbitrary direction an check how many times it
      # intersects the mesh.
      # Odd number means it's inside mesh, even means it's outside of it.

      # Use somewhat random vector to reduce risk of ray touching solid without
      # intersecting it.
      vector = Geom::Vector3d.new(234, 1343, 345)
      ray = [point, vector]
	  
      intersection_points = entities(container).map do |face|
        next unless face.is_a?(Sketchup::Face)

        # If point is on face of solid, return value specified for that case.
        clasify_point = face.classify_point(point)
        return on_face_return_value if [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(clasify_point)
          
        intersection = Geom.intersect_line_plane(ray, face.plane)
        next unless intersection
        next if intersection == point

        # Intersection must be in the direction ray is casted to count.
        next unless (intersection - point).samedirection?(vector)

        # Check intersection's relation to face.
        # Counts as intersection if on face, including where cut-opening component cuts it.
        classify_intersection = face.classify_point(intersection)
        next unless [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(classify_intersection)

        intersection
	    end
		
      intersection_points.compact!
      
      # Erase hits that are too close together at the edge of two faces.
      # Not needed(?) with the Dave Method implemented
      # if a is less than .002 from a+1 then delete a
      #(intersection_points.length - 1).times do |a|
      #  next if (intersection_points[a].x - intersection_points[a+1].x).abs > 0.002
      #  next if (intersection_points[a].y - intersection_points[a+1].y).abs > 0.002
      #  next if (intersection_points[a].z - intersection_points[a+1].z).abs > 0.002
      #  intersection_points[a] = nil 
      # end
      #intersection_points.compact!
       
       
      intersection_points = intersection_points.inject([]){ |a, p0| a.any?{ |p| p == p0 } ? a : a << p0 }
 #    intersection_points.length.odd?
      (intersection_points.length & 0x01) == 1
    end
    
    
    # Check if a Group or ComponentInstance is solid. If every edge binds an
    # even faces it is considered a solid. Nested groups and components are
    # ignored.
    #
    # container - The Group or ComponentInstance to test.
    #
    # Returns nil if not a Group or Component || if entities.length == 0
    #      then true/false if each edges is attached to an even number of faces
    def self.is_solid?(container)
      return unless [Sketchup::Group, Sketchup::ComponentInstance].include?(container.class)
      ents = entities(container)
      # return nil if the container is empty
      return if ents.length == 0
      !ents.any? { |e| e.is_a?(Sketchup::Edge) && ((e.faces.length & 0x01) == 1)}
    end
    
  end

end
end