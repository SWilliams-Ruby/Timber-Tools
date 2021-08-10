# SW::TimberTools.reload
# TODO:
# wrap these variables and methods in their own name space

module SW
module TimberTools
  @factory_defaults = {:active_dimensions => '8x6', :saved_dimensions => ['1x6*', '2x4*', '6x8', '8x8', '8x10', '8x12', '3x5'],:max_saved_dimensions_count => '8'}
  
  @preferences = nil 
  
  if Sketchup.version.to_i > 8 # I don't really know at which version preferences changed
    def self.get_preferences()
      if @preferences == nil 
        @preferences = Sketchup.read_default("SW::TimberTools", "preferences", @factory_defaults )
      end
      @preferences
    end
    
    def self.update_preferences()
       Sketchup.write_default("SW::TimberTools", "preferences", @preferences)
    end
    
    def self.reset_preferences() # if we need to overwrite the saved preferences paste this is the ruby console
      Sketchup.write_default("SW::TimberTools", "preferences", @factory_defaults)
      # Make a Deep Copy of @factory_defaults
      @preferences = Marshal.load( Marshal.dump(@factory_defaults))
    end

    def self.save_preferences() # if we need to overwrite the saved preferences paste this is the ruby console
      Sketchup.write_default("SW::TimberTools", "preferences", @factory_defaults)
      # Make a Deep Copy of @factory_defaults
      @preferences = Marshal.load( Marshal.dump(@factory_defaults))
    end

    def self.reset_to_factory_preferences() # if we need to overwrite the saved preferences paste this is the ruby console
      Sketchup.write_default("SW::TimberTools", "preferences", @factory_defaults)
      # Make a Deep Copy of @factory_defaults
      @preferences = Marshal.load( Marshal.dump(@factory_defaults))
    end
    
  else
    #this works in SU 8
    def self.get_preferences()
      if @preferences == nil 
        @preferences = Sketchup.read_default("SW::TimberTools", "preferences")
        val = Sketchup.read_default("SW::TimberTools", "preferences")
        @preferences = eval(val) if !val.nil?
        reset_preferences() if @preferences.class != Hash
      end
     # p 'get preferences'
     # p @preferences
      @preferences
    end

    def self.update_preferences()
      Sketchup.write_default("SW::TimberTools", "preferences", @preferences.inspect.gsub(/"/, '\''))
      #p 'update preferences'
      #p @preferences
    end
    
    def self.reset_preferences() # if we need to overwrite the saved preferences paste this is the ruby console
      Sketchup.write_default("SW::TimberTools", "preferences", @factory_defaults.inspect.gsub(/"/, '\''))
      # Make a Deep Copy of @factory_defaults
      @preferences =   Marshal.load( Marshal.dump(@factory_defaults))
    end
    
    def self.save_preferences() # if we need to overwrite the saved preferences paste this is the ruby console
      Sketchup.write_default("SW::TimberTools", "preferences", @factory_defaults)
      # Make a Deep Copy of @factory_defaults
      @preferences = Marshal.load( Marshal.dump(@factory_defaults))
    end

    def self.reset_to_factory_preferences() # if we need to overwrite the saved preferences paste this is the ruby console
      Sketchup.write_default("SW::TimberTools", "preferences", @factory_defaults)
      # Make a Deep Copy of @factory_defaults
      @preferences = Marshal.load( Marshal.dump(@factory_defaults))
    end
  end
  
   
  ##################################
  #### Load the initial preferences
  ##################################
  get_preferences()
  
  #retrieve the active timber size fom the preferences
  ### possible entries are 
  ### a length 
  ### a lumber dimension
  ###   - 2x4  actaul dimension
  ###   - 2x4* nominal dimensions

  def self.get_active_timber_size()
    act = @preferences[:active_dimensions]
    active_dim = act.split(%r{[xX]})
    dim_0 = active_dim[0].to_l
    
    if active_dim[1].include?("*")
      if dim_0 > 6
        dim_0 = dim_0 - 0.75
      elsif dim_0 > 1
        dim_0 = dim_0 - 0.5
      else
        dim_0 = dim_0 - 0.25
      end
      
      dim_1 = active_dim[1].split('*')[0].to_l
      if dim_1 > 6
        dim_1 = dim_1 - 0.75
      elsif dim_1 >  1
        dim_1 = dim_1 - 0.5
      else 
        dim_1 = dim_1 - 0.25
      end
    else
      dim_1 = active_dim[1].to_l
    end
    return dim_0, dim_1
  end
  
  
  def self.get_active_dimensions()
    @preferences[:active_dimensions]
  end
  
  # set the active timber size.
  def self.set_active_timber_size(text)
    @preferences[:active_dimensions] = text
    update_preferences()
    update_dialog_and_tools()
  end
  
  def self.reset_timber_size() 
    reset_preferences()
    update_dialog_and_tools()
  end   
  
  # Add a new timber size to our saved preferences
  # and clip the length of the list to MAX entries
  def self.set_new_timber_size(text)
    @preferences[:active_dimensions] = text
    if !@preferences[:saved_dimensions].include?(text)
      @preferences[:saved_dimensions].push(text)
      num_prefs = @preferences[:saved_dimensions].size - @preferences[:max_saved_dimensions_count].to_i
      if num_prefs > 0
        @preferences[:saved_dimensions] = @preferences[:saved_dimensions][num_prefs..-1]
      end
    end
    update_preferences()
    update_dialog_and_tools()
  end
  
  def self.update_dialog_and_tools()
    # update the timber tool dialog
    @ttdialog.update_size_buttons() if @ttdialog
    Sketchup.vcb_label = "Timber Size #{get_active_dimensions()}"
  end
   
end
end