require "sketchup.rb"
require "extensions.rb"

module SW
module TimberTools

  PLUGIN_DIR = File.join(File.dirname(__FILE__), File.basename(__FILE__, ".rb"))
  REQUIRED_SU_VERSION = 14

  EXTENSION = SketchupExtension.new(
    "Timber Tools",
    File.join(PLUGIN_DIR, "main")
  )
  EXTENSION.creator     = "Skip Williams"
  EXTENSION.description = "Timber Tools Description"
  EXTENSION.version     = "0.9.0"
  EXTENSION.copyright   = "#{EXTENSION.creator} #{Time.now.year}"
  Sketchup.register_extension(EXTENSION, true)

end
end