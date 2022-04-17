# SW::TimberTools.reload
version = Sketchup.version.split('.').first.to_i
if version >= 17
  require File.join(File.dirname(__FILE__), 'bridge.rb') 
else
  require File.join(File.dirname(__FILE__), 'bridge fixed SU8.rb')
end

module SW

  module TimberTools
    
    # A reference to the current timber tool dialog
    @ttdialog = nil
    
    def self.open_ttdialog()
         # with HTMLdialog we must open a new dialog each time
         # if the user has closed the dialog
         @ttdialog.close if @ttdialog
         @ttdialog = TimberToolsDialog.new.open
    end
    
    class TimberToolsDialog

      def initialize
        @dialog = create_dialog()
      end
      
      def open
        @dialog.show
        return self
      end

      def close
        # and then SU8 does something different, What? 
        @dialog.close if Sketchup.version.to_i > 8 
      end

      def create_dialog()
         properties = {
          :dialog_title    => 'Timber Tools',
          :preferences_key => 'SW::TimberTools',
          :resizable       => true,
          :width           => 250,
          :height          => 500,
          :left            => 200,
          :top             => 200
         }
        
        if defined?(UI::HtmlDialog)
          dialog = UI::HtmlDialog.new(properties) 
        else
          dialog = UI::WebDialog.new("Timber Tools", false, "SW::TimberTools", 250, 500, 200, 200, true)
        end
        
        version = Sketchup.version.split('.').first.to_i
        if version >= 17
          dialog.set_file(File.join(PLUGIN_DIR, 'html', 'dialog.html'))
        else
          dialog.set_file(File.join(PLUGIN_DIR, 'html', 'dialogSU8.html'))
        end

        # Attach the skp-bridge magic.
        Bridge.decorate(dialog)

        # Calbacks from javascript
        dialog.on('change_size') { |deferred, size|
          SW::TimberTools.set_active_timber_size(size)
        }
        
        dialog.on('get_size_buttons') { |deferred|
          deferred.resolve(make_size_buttons())
        }
        
        dialog.on('new_size') { |deferred, size|
          # TODO: move the input checking to the javascript side
          begin
            # check for a valid format   2x4, 2x4*
            if size == 'x0x0x0x0' #special reset preferences key
              SW::TimberTools.reset_timber_size()
            else
              dims = size.split(%r{[xX]})
              raise ArgumentError if dims.size != 2  
              dim2 = dims[1].split('*')
              raise ArgumentError unless dims[0].to_l > 0
              raise ArgumentError unless dim2[0].to_l > 0
              SW::TimberTools.set_new_timber_size(size)
            end
            # return a dummy to java dialog
            deferred.resolve('A-ok')

          rescue ArgumentError
            deferred.reject('Invalid entry. Examples: 2x4, 2x4*')
          end
        }
        
        return dialog
      end # end create_dialog
      
      # Utility methods for the ToolsDialog
      def update_size_buttons()
        @dialog.call('setSizeButtons', make_size_buttons())
      end

      def make_size_buttons()
         # TODO: move the button creation to the javascript side
        result = ''
        prefs = SW::TimberTools.get_preferences()
         prefs[:saved_dimensions].reverse_each {|size|
          if size == prefs[:active_dimensions]
            result << "<button  style= \"color:red;width:100px\" onclick=\"changeSize(event, \'#{size}\')\">#{size}</button><br>"
          else
            result << "<button style= \"width:100px\"  onclick=\"changeSize(event, \'#{size}\')\">#{size} </button><br>"
          end
        }
        result
      end
    end # end class ToolsDialog

  
  end

end
