# SW::TimberTools.reload

module SW
module TimberTools
  def self.tb_extension
    if Sketchup.version.to_i < 19
      "png"
    elsif Sketchup.platform == :platform_win
      "svg"
    else
      "pdf"
    end
  end

  unless file_loaded?(__FILE__)
    file_loaded(__FILE__)
      
    tb = UI::Toolbar.new(EXTENSION.name)

    cmd = UI::Command.new("Cut Mortise") { TrimTool.perform_or_activate }
    cmd.large_icon = cmd.small_icon = File.join(PLUGIN_DIR, "images", "scissor.#{tb_extension}")
    cmd.tooltip = "Cut Mortise"
    cmd.status_bar_text = "Cut the Mortise"
    #cmd.set_validation_proc { SubtractTool.active? ? MF_CHECKED : MF_UNCHECKED }
    tb.add_item cmd

    cmd = UI::Command.new("Add Timber") {activate_timber_new_tool }
    cmd.large_icon = cmd.small_icon = File.join(PLUGIN_DIR, "images", "timber new.#{tb_extension}")
    cmd.tooltip = "Add a Timber"
    cmd.status_bar_text = "Add a new Timber."
    #cmd.set_validation_proc { TimberNewTool.active? ? MF_CHECKED : MF_UNCHECKED }
    tb.add_item cmd

    cmd = UI::Command.new("Add Rotated Timber") {activate_timber_new_rotate_tool }
    cmd.large_icon = cmd.small_icon = File.join(PLUGIN_DIR, "images", "timber pointer rotate.#{tb_extension}")
    cmd.tooltip = "Add a Rotated Timber"
    cmd.status_bar_text = "Add a Rotated Timber."
    #cmd.set_validation_proc { TimberNewRotateTool.active? ? MF_CHECKED : MF_UNCHECKED }
    tb.add_item cmd

    cmd = UI::Command.new("Timber Push Pull") {activate_timber_stretch_tool() }
    cmd.large_icon = cmd.small_icon = File.join(PLUGIN_DIR, "images", "pull.#{tb_extension}")
    cmd.tooltip = "Timber Push Pull"
    cmd.status_bar_text = "Timber Push Pull."
    #cmd.set_validation_proc { TimberNewRotateTool.active? ? MF_CHECKED : MF_UNCHECKED }
    tb.add_item cmd

    cmd = UI::Command.new("Timber Reduction") {activate_timber_reduction_tool() }
    cmd.large_icon = cmd.small_icon = File.join(PLUGIN_DIR, "images", "reduction.#{tb_extension}")
    cmd.tooltip = "Timber Reduction"
    cmd.status_bar_text = "Timber Reduction."
    #cmd.set_validation_proc { TimberNewRotateTool.active? ? MF_CHECKED : MF_UNCHECKED }
    tb.add_item cmd

    cmd = UI::Command.new("Open Settinggs Dialog") {open_ttdialog() }
    cmd.large_icon = cmd.small_icon = File.join(PLUGIN_DIR, "images", "hamburger.#{tb_extension}")
    cmd.tooltip = "Open Settinggs Dialog"
    cmd.status_bar_text = "Open Settinggs Dialog."
    #cmd.set_validation_proc { TimberNewRotateTool.active? ? MF_CHECKED : MF_UNCHECKED }
    tb.add_item cmd




  

  end

end
end

