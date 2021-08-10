require "sketchup.rb"
require "extensions.rb"

module SW
module TimberTools

  PLUGIN_DIR_PART_A = File.join(File.dirname(__FILE__), File.basename(__FILE__, ".rb"))
  #REQUIRED_SU_VERSION = 14

  EXTENSION_PART_A = SketchupExtension.new(
    "Timber Tools Part A",
    File.join(PLUGIN_DIR_PART_A, "main")
  )
  EXTENSION_PART_A.creator     = "Skip Williams"
  EXTENSION_PART_A.description = "Timber Tools Part A Description"
  EXTENSION_PART_A.version     = "0.9.0"
  EXTENSION_PART_A.copyright   = "#{EXTENSION_PART_A.creator} #{Time.now.year}"
  Sketchup.register_extension(EXTENSION_PART_A, true)
end
end