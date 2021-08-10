# SW::TimberTools.reload
module SW
module TimberTools

  # This version of TimberTools runs on Sketchup 8 or newer
  
  #if Sketchup.version.to_i < REQUIRED_SU_VERSION
  #  msg = "#{EXTENSION.name} requires SketchUp 20#{REQUIRED_SU_VERSION} or later to run."
  #  UI.messagebox(msg)
  #  raise msg
  #end
  Sketchup.require(File.join(PLUGIN_DIR, "preferences"))
  Sketchup.require(File.join(PLUGIN_DIR, "timber_tools_dialog"))

  Sketchup.require(File.join(PLUGIN_DIR, "solidtools/solids"))
  Sketchup.require(File.join(PLUGIN_DIR, "solidtools/tools"))
  Sketchup.require(File.join(PLUGIN_DIR, "menus"))
  
  Sketchup.require(File.join(PLUGIN_DIR, "lib/inference_lock"))
  
  # Sketchup.require(File.join(PLUGIN_DIR, "timber_labeller"))
  # Sketchup.require(File.join(PLUGIN_DIR, "timber_flipper"))
  # Sketchup.require(File.join(PLUGIN_DIR, "timber_create_rollout"))
  
  Sketchup.require(File.join(PLUGIN_DIR, "timber_new_tool"))
  Sketchup.require(File.join(PLUGIN_DIR, "timber_new_rotated_tool"))
  Sketchup.require(File.join(PLUGIN_DIR, "whirly_points"))
  Sketchup.require(File.join(PLUGIN_DIR, "whirly_slope_points"))
  
  Sketchup.require(File.join(PLUGIN_DIR, "timber_stretch_tool"))
  Sketchup.require(File.join(PLUGIN_DIR, "timber_reduction_tool"))

  
  # Reload whole extension (except loader) without littering
  # console. Inspired by ThomTohm's method.
  # Only works before extension has been scrambled.
  #
  # clear_console - Clear console from previous content too (default: false)
  # undo_last     - Undo last operation in model (default: false).
  #
  # Returns nothing.
  def self.reload(clear_console = false, undo_last = false)

    # Hide warnings for already defined constants.
    verbose = $VERBOSE
    $VERBOSE = nil
    
    Dir.glob(File.join(PLUGIN_DIR, "*.rb")).each { |f| load(f)}
    load(File.join(PLUGIN_DIR, "solidtools/solids.rb"))
    load(File.join(PLUGIN_DIR, "solidtools/tools.rb"))
    
    $VERBOSE = verbose
    # Use a timer to make call to method itself register to console.
    # Otherwise the user cannot use up arrow to repeat command.
    UI.start_timer(0) { SKETCHUP_CONSOLE.clear } if clear_console

    Sketchup.undo if undo_last

    nil
  end

  
  # unless file_loaded?(__FILE__)
    # file_loaded(__FILE__)
  # end  
end
end

