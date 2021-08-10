# load 'imp_ene_solids/tools.rb'
# 
# I'm fairly certain the ene solid tools work the same as their original design.
# except I've removed the ability to keep the original coplanar edges until this is tested.
#
# About the Multi-Subtract tool
# The multi-subtract tool allows the user to select multiple objects to be 'cut' with a secondary object.
#
# To use the Multi-subtract tool
# Select zero, one or more solids,  'the primary collection'
# Click the multi-subtract tool button
#   add to the primary collection by holding down the Alt/Option on Mac, Ctrl on PC while clicking on an object
#   add or subtract to/from the primary collection by holding down the Shift key while clicking on an object
#
# Click on the secondary object to perform the subtraction
#
# The cursor will change to indicate which of the above operations the tool is expecting
#
# It is also possible to Swap the primary and secondary by holding down Command on Mac, Alt on PC when you click the secondary
# 
# To change the preferences you must activate the Multi-Subtract tool and right click with the mouse
# The options are :
#    Cut into Subcomponents
#    Hide the secondary object after subtraction
#    Paint the new faces (with a default material named 'Ene_Cut_Face_Color')
#    Make each primary object unique
# 

module SW
module TimberTools

  class BaseTool

    NOT_SOLID_ERROR = "Something went wrong :/\n\nOutput is not a solid."

    # Since SketchUp's built checking of tools in menus seems to fail for tools
    # that are subclasses the active tool's class has to be tracked by the
    # plugin.
    @@active_tool_class = nil

    # Perform solid operation on selection if it consists of two or more solids
    # and nothing else, otherwise activate tool.
    def self.perform_or_activate
      model = Sketchup.active_model
      selection = model.selection
      if selection.length > 1 && selection.all? { |e| Solids.is_solid?(e) }

        # Sort by bounding box volume since no order is given.
        # To manually define the what solid to modify and what to modify with
        # user must activate the tool.
        solids = selection.to_a.sort_by { |e| bb = e.bounds; bb.width * bb.depth * bb.height }.reverse

        model.start_operation(self::OPERATOR_NAME, true)
        primary = solids.shift
        until solids.empty?
          if !Solids.send(self::METHOD_NAME, primary, solids.shift, false)
            model.commit_operation
            UI.messagebox(NOT_SOLID_ERROR)
            return
          end
        end
        model.commit_operation

        # Set status text inside 0 timer to override status set by hovering
        # the toolbar button.
        UI.start_timer(0, false){ Sketchup.status_text = self::STATUS_DONE }

      else
        Sketchup.active_model.select_tool(new)
      end
    end
    
    
  
    # Check whether this is the active tool.
    def self.active?
      @@active_tool_class == self
    end

    # SketchUp Tool Interface

    def activate
      @ph = Sketchup.active_model.active_view.pick_helper
      @cursor_normal = UI.create_cursor(File.join(PLUGIN_DIR, "images", self.class::CURSOR_FILENAME), 2, 2)
      @cursor_wait = UI.create_cursor(File.join(PLUGIN_DIR, "images", "BWaitQ0.png"), 2, 2)
      @cursor = @cursor_normal
      @@active_tool_class = self.class
      reset
    end

    def deactivate(view)
      @@active_tool_class = nil
    end

    def onLButtonDown(flags, x, y, view)
      # Get what was clicked, return if not a solid.
      @ph.do_pick(x, y)
      picked = @ph.best_picked
      return unless Solids.is_solid?(picked)

      if !@primary
        Sketchup.status_text = self.class::STATUS_SECONDARY
        @primary = picked
      else
      #### wrap this in a rescue clause
        return if picked == @primary
        secondary = picked
        @cursor = @cursor_wait
        onSetCursor() #update cursor
        Sketchup.status_text = 'Working'
        view.model.start_operation(self.class::OPERATOR_NAME, true)
        if !Solids.send(self.class::METHOD_NAME, @primary, secondary, false)
          UI.messagebox(NOT_SOLID_ERROR)
          reset
        end
        view.model.commit_operation
        @cursor = @cursor_normal
        onSetCursor() #update cursor
        Sketchup.status_text = self.class::STATUS_SECONDARY
      end
    end
    
    def onMouseMove(flags, x, y, view)
      # Highlight hovered solid by making it the only selected entity.
      # Consistent to rotation, move and scale tool.
      selection = Sketchup.active_model.selection
      @ph.do_pick(x, y)
      over = @ph.best_picked
      return if over == @mouse_over

      # mouse is over a new object
      # remove old @mouse_over from model.selection
      if @mouse_over
        selection.remove(@mouse_over) if !@mouse_over.deleted?
        #p 'remove ' + @mouse_over.to_s
        @mouse_over = nil
      end
      
      #add new object to model.selection 
      if over 
        return if selection.include?(over)
        return unless Solids.is_solid?(over)
        @mouse_over = over
        selection.add(over)
        #p 'add ' + over.to_s
      end
    end

    def onCancel(reason, view)
      reset
    end

    def onSetCursor
      UI.set_cursor(@cursor)
    end

    def resume(view)
      Sketchup.status_text = !@primary ? self.class::STATUS_PRIMARY : self.class::STATUS_SECONDARY
    end

    def ene_tool_cycler_icon
      File.join(PLUGIN_DIR, "images", "#{self.class::METHOD_NAME.to_s}.svg")
    end

    private

    def reset
      Sketchup.active_model.selection.clear
      Sketchup.status_text = self.class::STATUS_PRIMARY
      @primary = nil
      @mouse_over = nil
    end
  end #BaseTool
  
  class MultiSubBaseTool

    NOT_SOLID_ERROR = "Something went wrong :\n\nOutput is not a solid."

    # Since SketchUp's built checking of tools in menus seems to fail for tools
    # that are subclasses the active tool's class has to be tracked by the
    # plugin.
    @@active_tool_class = nil
    
    # Perform solid operation on selection if it consists of two or more solids
    # and nothing else, otherwise activate tool.
    def self.perform_or_activate
      Sketchup.active_model.select_tool(new)
    end
    
    # Check whether this is the active tool.
    def self.active?
      @@active_tool_class == self
    end

    # SketchUp Tool Interface

    def activate
      @ph = Sketchup.active_model.active_view.pick_helper
      @@active_tool_class = self.class
      @multisub_state = 0 
      @swap_ps = false
      
      get_settings() # fetch user preferences from the registry
      
      # extra cursors for the multi subtract tool
      @cursor_primary = UI.create_cursor(File.join(PLUGIN_DIR, "images", "cursor_multisub_primary.png"), 2, 2)
      @cursor_secondary = UI.create_cursor(File.join(PLUGIN_DIR, "images", "cursor_multisub_secondary.png"), 2, 2)
      @cursor_plus = UI.create_cursor(File.join(PLUGIN_DIR, "images", "cursor_multisub_plus.png"), 2, 2)
      @cursor_plus_minus = UI.create_cursor(File.join(PLUGIN_DIR, "images", "cursor_multisub_plus_minus.png"), 2, 2)
      @cursor_wait = UI.create_cursor(File.join(PLUGIN_DIR, "images", "BWaitQ1.png"), 2, 2)
      
      # make existing selection the @primary array
      model = Sketchup.active_model
      selection = model.selection
      if selection.length > 0
        @primary = selection.to_a 
        @primary.reject! {|ent| ![Sketchup::Group, Sketchup::ComponentInstance].include?(ent.class)}
        Sketchup.status_text = self.class::STATUS_SECONDARY
        @cursor = @cursor_secondary
      else 
        @primary = []
        @cursor = @cursor_primary
        Sketchup.status_text = self.class::STATUS_PRIMARY
      end
      # Selection Observer to catch the select all(cntl-A) event
      Sketchup.active_model.selection.add_observer(self)
    end

    def deactivate(view)
      Sketchup.active_model.selection.remove_observer(self)
      @@active_tool_class = nil
    end
    
    #CONSTRAIN_MODIFIER_KEY = Shift Key
    #CONSTRAIN_MODIFIER_MASK = Shift Key
    #COPY_MODIFIER_KEY = Alt/Option on Mac, Ctrl on PC
    #COPY_MODIFIER_MASK = Alt/Option on Mac, Ctrl on PC
    #ALT_MODIFIER_KEY = Command on Mac, Alt on PC
    #ALT_MODIFIER_MASK = Command on Mac, Alt on PC
    
    def onKeyDown(key, repeat, flags, view)
      case key
        when COPY_MODIFIER_KEY
          @cursor = @cursor_plus
          @multisub_state = 1
          Sketchup.status_text = self.class::STATUS_PRIMARY_PLUS
          onSetCursor() #update cursor
        when CONSTRAIN_MODIFIER_KEY
          @cursor = @cursor_plus_minus
          @multisub_state = 2
          Sketchup.status_text = self.class::STATUS_PRIMARY_PLUS_MINUS
          onSetCursor() #update cursor
        when ALT_MODIFIER_KEY
          @swap_ps = true
      end
    end
    
    def onKeyUp(key, repeat, flags, view)
      case key
        when COPY_MODIFIER_KEY, CONSTRAIN_MODIFIER_KEY
          @multisub_state = 0
          if @primary.length != 0 
            @cursor = @cursor_secondary
            Sketchup.status_text = self.class::STATUS_SECONDARY
            onSetCursor() #update cursor
          else
            @cursor = @cursor_primary
            Sketchup.status_text = self.class::STATUS_PRIMARY
            onSetCursor() #update cursor
          end
        when ALT_MODIFIER_KEY
          @swap_ps = false
      end 
    end

    def onLButtonDown(flags, x, y, view)
      # Get what was clicked, return if not a solid.
      @ph.do_pick(x, y)
      picked = @ph.best_picked
      return unless Solids.is_solid?(picked)
      
      #Add and remove objects from the @primary array
      case @multisub_state
        when 0 
          if @primary.length == 0 
            @primary << picked 
            Sketchup.status_text = self.class::STATUS_SECONDARY
            @cursor = @cursor_secondary
            onSetCursor() #update cursor
            return
          end
          
        when 1 #add to selection
          @primary << picked
          @primary.uniq!
          return 
        
        when 2 # add/subtract from selection
          #try to delete picked. will equal nil if not present; so do add
          if @primary.delete(picked) == nil
            @primary << picked # add  picked to the array
          else 
            selection = Sketchup.active_model.selection
            selection.remove(picked)
          end
          return 
      end #end case

      # we have clicked on the secondary object
      # Case == 0 and @primary.length != 0
      secondary = picked
      @cursor = @cursor_wait
      onSetCursor() #update cursor
        
      begin
        Sketchup.status_text = 'Working'
        view.model.start_operation(self.class::OPERATOR_NAME, true)
        if !@swap_ps
          Solids.send(self.class::METHOD_NAME, @primary, secondary, @settings)
          secondary.hidden = true if @settings[:hide_sec]
        else
          @primary.each {|pr|
            Solids.send(self.class::METHOD_NAME, [secondary], pr, @settings)
          }
        end
        
        view.model.commit_operation
        #UI.beep #done
        
      rescue => e
        view.model.abort_operation
        puts("Error #<#{e.class.name}:#{e.message}.>")
        puts(e.backtrace) if $VERBOSE
        UI.messagebox("I'm sorry I can't do that\n\n#{e.message}")
      end
      Sketchup.status_text = self.class::STATUS_SECONDARY

      # clean up items that were totally removed by the subtract operation
      @primary.reject! {|ent| ent.deleted?}
      @cursor = @cursor_secondary
      onSetCursor() #update cursor
    end

    def onMouseMove(flags, x, y, view)
      # Highlight hovered solid by making it the only selected entity.
      # Consistent to rotation, move and scale tool.
      selection = Sketchup.active_model.selection
      @ph.do_pick(x, y)
      over = @ph.best_picked
      return if over == @mouse_over

      # mouse is over a new object
      # remove old @mouse_over from model.selection if it isn't included @primary 
      if @mouse_over
        selection.remove(@mouse_over) if !@primary.include?(@mouse_over)
        #p 'remove ' + @mouse_over.to_s
        @mouse_over = nil
      end
      
      #add new object to model.selection 
      if over 
        return if selection.include?(over)
        return unless Solids.is_solid?(over)
        @mouse_over = over
        selection.add(over)
        #p 'add ' + over.to_s
      end
    end
    
    # Selection Observer callback to catch select all(ctrl-A) 
    def onSelectionBulkChange(selection)
      @primary = selection.to_a
      @primary.reject! {|ent| ![Sketchup::Group, Sketchup::ComponentInstance].include?(ent.class)}
    end

    def onCancel(reason, view)
      reset
    end

    def onSetCursor
      UI.set_cursor(@cursor)
    end

    def resume(view)
      Sketchup.status_text = @primary.length == 0 ? self.class::STATUS_PRIMARY : self.class::STATUS_SECONDARY
    end

    def ene_tool_cycler_icon
      File.join(PLUGIN_DIR, "images", "#{self.class::METHOD_NAME.to_s}.svg")
    end

    if Sketchup.version.to_i < 15
      # Compatible with SketchUp 2014 and older:
      def getMenu(menu)
        build_menu(menu)
      end
    else
      def getMenu(menu, flags, x, y, view)
        build_menu(menu)
      end
    end
    
    def build_menu(menu)
      item = menu.add_item('Cut Subcomponents') { update_settings(:cut_sub)}
      status = menu.set_validation_proc(item)  {@settings[:cut_sub] ? MF_CHECKED : MF_UNCHECKED}
      
      item = menu.add_item('Hide Secondary') { update_settings(:hide_sec)}
      status = menu.set_validation_proc(item)  {@settings[:hide_sec]? MF_CHECKED : MF_UNCHECKED}
      
      item = menu.add_item('Texture New Faces') { update_settings(:paint)}
      status = menu.set_validation_proc(item)  {@settings[:paint] ? MF_CHECKED : MF_UNCHECKED}

      item = menu.add_item('Make Primary Unigue') { update_settings(:unique)}
      status = menu.set_validation_proc(item)  {@settings[:unique] ? MF_CHECKED : MF_UNCHECKED}
    end
    
    if Sketchup.version.to_i > 8 # I don't really know at which version  preferences changed
      def get_settings()
        @settings = Sketchup.read_default("LL::Expose", "settings",  {:cut_sub => true,:hide_sec => true,:paint => false,:unique => true})
      end
      
      def update_settings(key)
        @settings[key] = !@settings[key]
        Sketchup.write_default("LL::Expose", "settings", @settings)
      end
      
      def set_settings() # if we need to overwrite the saved settings paste this is the ruby console
        @settings =  {:cut_sub => true,:hide_sec => true,:paint => false,:unique => true}
        Sketchup.write_default("LL::Expose", "settings", @settings)
      end
    else
    
     #this works in SU 8
     def get_settings()
        @settings = eval(Sketchup.read_default("LL::Expose", "settings"))
        set_settings() if !@settings.class === Hash 
      end

      def update_settings(key)
        @settings[key] = !@settings[key]
        Sketchup.write_default("LL::Expose", "settings", @settings.inspect)
      end
      
      def set_settings() # if we need to overwrite the saved settings paste this is the ruby console
        @settings =  {:cut_sub => false,:hide_sec => true,:paint => false,:unique => true}
        Sketchup.write_default("LL::Expose", "settings", @settings.inspect)
      end
    end
    
    private

    def reset
      Sketchup.active_model.selection.clear
      Sketchup.status_text = self.class::STATUS_PRIMARY
      @primary = []
    end

  end
 
  class UnionTool < BaseTool
    CURSOR_FILENAME  = "cursor_union.png"
    STATUS_PRIMARY   = "Click primary solid group/component to add to."
    STATUS_SECONDARY = "Click secondary solid group/component to add with. Esc = Select new primary solid."
    STATUS_DONE      = "Done. By instead activating tool without a selection you can chose which component to alter."
    OPERATOR_NAME    = "Union"
    METHOD_NAME      = :union
  end

  class SubtractTool < BaseTool
    CURSOR_FILENAME  = "cursor_subtract.png"
    STATUS_PRIMARY   = "Click primary solid group/component to subtract from."
    STATUS_SECONDARY = "Click secondary solid group/component to subtract with. Esc = Select new primary solid."
    STATUS_DONE      = "Done. By instead activating tool without a selection you can chose what to subtract from what."
    OPERATOR_NAME    = "Subtract"
    METHOD_NAME      = :subtract
  end

  class TrimTool < BaseTool
    CURSOR_FILENAME  = "cursor_trim.png"
    STATUS_PRIMARY   = "Click primary solid group/component to trim."
    STATUS_SECONDARY = "Click secondary solid group/component to trim away. Esc = Select new primary solid."
    STATUS_DONE      = "Done. By instead activating tool without a selection you can chose what to trim from what."
    OPERATOR_NAME    = "Trim"
    METHOD_NAME      = :trim
  end

  class IntersectTool < BaseTool
    CURSOR_FILENAME  = "cursor_intersect.png"
    STATUS_PRIMARY   = "Click primary solid group/component to intersect."
    STATUS_SECONDARY = "Click secondary solid group/component intersect with. Esc = Select new primary solid."
    STATUS_DONE      = "Done. By instead activating tool without a selection you can chose what solid to modify."
    OPERATOR_NAME    = "Intersect"
    METHOD_NAME      = :intersect
  end
  
 class MultiSubTool < MultiSubBaseTool
    STATUS_PRIMARY   = "Click primary solid groups/components to subtract from."
    STATUS_PRIMARY_PLUS = "Click to ADD to primary solid groups/components to subtract from."
    STATUS_PRIMARY_PLUS_MINUS = "Click to ADD/Subtract to the primary solid groups/components to subtract from."
    STATUS_SECONDARY = "Click secondary solid group/component to subtract. Esc = Select new primary solid."
    STATUS_DONE      = "Done. By instead activating tool without a selection you can chose what solid to modify."
    OPERATOR_NAME    = "MultiSub"
    METHOD_NAME      = :multisub
  end

end  
end
