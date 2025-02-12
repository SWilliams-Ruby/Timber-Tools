# load 'C:/Users/User/Documents/sketchup code/sw_TimberTools/src/sw_timbertools/bridge fixed SU8.rb'
# This is a modfifies version of sketchup-bridge 
# that has been tested with SU8 through SU 2017
# Ruby 1.6.2 through 2.2.4


# Modified from Aerilius sketchup-bridge version 3.0.1 , Latest commit 4dbd3ca  on May 25
# https://github.com/Aerilius/sketchup-bridge/tree/14414c17107cd20a5e2281e67db5d00e3ce61419
#


module SW 
  module TimberTools

      class Bridge

        VERSION = '3.0.1'.freeze unless defined?(self::VERSION)

      end


      class Bridge

        class Promise
          # A simple promise implementation to follow the ES6 (JavaScript) Promise specification:
          # {#link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise }
          #
          # Existing Ruby promise implementations did not satisfy either in simplicity or compliance to the ES6 spec.
          #
          # https://github.com/tobiashm/a-ruby-promise/
          #     Uses instance eval to provide `return`-keyword-like `resolve` and `reject`, but exposes implementation
          #     internals that can have side effects if a same-named instance variable is used in the code block.
          #
          # https://github.com/bachue/ruby-promises/
          #     Uses Ruby's `method_missing` to provide a nice proxy to the promise's result. Unfortunately this can cause
          #     exceptions when a promise is not yet resolved. Also ruby-like proxies can not be realised in JavaScript.

          # @private
          module State
            PENDING  = 0
            RESOLVED = 1
            REJECTED = 2
          end
          private_constant(:State) if methods.include?(:private_constant)

          # A Struct that stores handlers belonging to a promise.
          # If a promise is resolved or rejected, either the `on_resolve` or `on_reject` code block tells what to do (an
          # action that depended on the promise being fulfilled first).
          # Depending on the success of this handler, resolvation/rejection of the next promise will be invoked by
          # `resolve_next`/`reject_next`.
          # resolved/rejected
          # @private
          Handler = Struct.new(:on_resolve, :on_reject, :resolve_next, :reject_next)
          private_constant(:Handler) if methods.include?(:private_constant)

          # Run an asynchronous operation and return a promise that will receive the result.
          # @param executor     [#call(#call(Object),#call(Exception))]
          #   An executor receives a callable to resolve the promise with a result and
          #   a callable to reject the promise in case of an error. The executor must call one of both.
          # @yieldparam resolve [#call(*Object)]   A function to call to fulfill the promise with a result.
          # @yieldparam reject  [#call(Exception)] A function to call to reject the promise.
          def initialize(&executor)
            @state    = State::PENDING
            @values   = []  # all results or rejection reasons if multiple were given
            @handlers = []  # @type [Array<Handler>]
            if block_given? && (executor.arity == 2 || executor.arity < 0)
              begin
                executor.call(method(:resolve), method(:reject))
              rescue Exception => error
                reject(error)
              end
            end
          end

          # Register an action to do when the promise is resolved.
          #
          # @overload then(on_resolve, on_reject)
          #   @param on_resolve   [#call(*Object)]          A function to call when the promise is resolved.
          #   @param on_reject    [#call(String,Exception)] A function to call when the promise is rejected.
          #
          # @overload then{|*results|}
          #   @yield                                        A function to call when the promise is resolved.
          #   @yieldparam results [Array<Object>]           The promised result (or results).
          #
          # @overload then(on_resolve){|reason|}
          #   @param on_resolve   [#call(*Object)]          A function to call when the promise is resolved.
          #   @yield                                        A function to call when the promise is rejected.
          #   @yieldparam reason  [String,Exception]        The reason why the promise was rejected.
          #
          # @return [Promise] A new promise for that the on_resolve or on_reject block has been executed successfully.
          def then(on_resolve=nil, on_reject=nil, &block)
            if block_given?
              if on_resolve.respond_to?(:call)
                # When called as: then(proc{on_resolve}){ on_reject }
                on_reject = block
              else
                # When called as: then{ on_resolve }
                on_resolve = block
              end
            end
            (unhandled_rejection(*@values); return self) if @state == State::REJECTED && !on_reject.respond_to?(:call)

            next_promise = Promise.new { |resolve_next, reject_next| # Do not use self.class.new because a subclass may require arguments.
              @handlers << Handler.new(on_resolve, on_reject, resolve_next, reject_next)
              case @state
                when State::RESOLVED
                  if on_resolve.respond_to?(:call)
                    handle(on_resolve, resolve_next, reject_next)
                  end
                when State::REJECTED
                  if on_reject.respond_to?(:call)
                    handle(on_reject, resolve_next, reject_next)
                  end
              end
            }
            return next_promise
          end

          # Register an action to do when the promise is rejected.
          # @param on_reject   [#call]            A function to call when the promise is rejected.
          #                                       (defaults to the given yield block, can be a Proc or Method)
          # @yieldparam reason [String,Exception] The reason why the promise was rejected
          # @return            [Promise]          A new promise that the on_reject block has been executed successfully.
          def catch(on_reject=nil, &block)
            on_reject = block if block_given?
            return self.then(nil, on_reject)
          end

          # Creates a promise that is resolved from the start with the given value.
          # @param  [Array<Object>]  *results  The result with which to initialize the resolved promise.
          # @return [Promise]                  A new promise that is resolved to the given value.
          def self.resolve(*results)
            return self.new{ |on_resolve, on_reject| on_resolve.call(*results) }
          end

          # Creates a promise that is rejected from the start with the given reason.
          # @param  [Array<Object>]  *reasons  The reason with which to initialize the rejected promise.
          # @return [Promise]                  A new promise that is rejected to the given reason.
          def self.reject(*reasons)
            return self.new{ |on_resolve, on_reject| on_reject.call(*reasons) }
          end

          # Creates a promise that resolves as soon as all of a list of promises have been resolved.
          # When all promises are resolved, the new promise is resolved with a list of the individual promises' results.
          # If instead any of the promises is rejected, it rejects the new promise with the first rejection reason.
          # @param  [Array<Promise>] promises  An array of promises.
          # @return [Promise]                  A new promise about the successful completion of all input promises.
          def self.all(promises)
            return Promise.reject(ArgumentError.new('Argument must be iterable')) unless promises.is_a?(Enumerable)
            return Promise.new{ |resolve, reject|
              if promises.empty?
                resolve.call([])
              else
                pending_counter = promises.length
                results = Array.new(promises.length)
                promises.each_with_index{ |promise, i|
                  if promise.respond_to?(:then)
                  
                  p 'x'
                  #p promise
                  #p promise.methods.sort
                  p promise.method(:then).methods.sort
                  
                  promise.then(Proc.new{ |result|
                      results[i] = result
                      pending_counter -= 1
                      p 'y'
                      
                      resolve.call(results) if pending_counter == 0
                    }, reject) # reject will only run once
                  else
                    results[i] = promise # if it is an arbitrary object, not a promise
                    pending_counter -= 1
                    resolve.call(results) if pending_counter == 0
                  end
                }
              end
            }
          end

          # Creates a promise that resolves or rejects as soon as the first of a list of promises is resolved or rejected.
          # @param  [Array<Promise>] promises  An array of promises.
          # @return [Promise]                  A new promise about the first completion of the any of the input promises.
          def self.race(promises)
            return Promise.reject(ArgumentError.new('Argument must be iterable')) unless promises.is_a?(Enumerable)
            return Promise.new{ |resolve, reject|
              promises.each{ |promise|
                if promise.respond_to?(:then)
                  promise.then(resolve, reject)
                else
                  break resolve.call(promise) # non-Promise value
                end
              }
            }
          end

          private

          # Resolve a promise once a result has been computed.
          #
          # @overload resolve(*results)
          #   Resolve a promise once a result or several results have been computed.
          #   @param *results [Array<Object>]
          #
          # @overload resolve(promise)
          #   Resolve a promise with another promise. It will actually be resolved later as soon as the other is resolved.
          #   @param promise  [Promise]
          #
          # @return           [nil]
          def resolve(*results)
            raise Exception.new("A once rejected promise can not be resolved later") if @state == State::REJECTED
            raise Exception.new("A resolved promise can not be resolved again with different results") if @state == State::RESOLVED && !results.empty? && results != @values
            return nil unless @state == State::PENDING

            # If this promise is resolved with another promise, the final results are not yet
            # known, so we we register this promise to be resolved once all results are resolved.
            raise TypeError.new('A promise cannot be resolved with itself.') if results.include?(self)
            if results.find{ |r| r.respond_to?(:then) }
              self.class.all(results).then(Proc.new{ |results| resolve(*results) }, method(:reject))
              return nil
            end

            # Update the state.
            @values  = results
            @state   = State::RESOLVED

            # Trigger the queued handlers.
            until @handlers.empty?
              handler = @handlers.shift
              if handler.on_resolve.respond_to?(:call)
                handle(handler.on_resolve, handler.resolve_next, handler.reject_next)
              else
                # No on_resolve handler given: equivalent to identity { |*results| *results }, so we call resolve_next
                # See: https://www.promisejs.org/api/#Promise_prototype_then
                if handler.resolve_next.respond_to?(:call)
                  handler.resolve_next.call(*@values)
                end
              end
            end
            # We must return nil, otherwise if this promise is resolved inside the 
            # block of an outer Promise, the block would implicitely return a 
            # resolved Promise and cause complicated errors.
            return nil
          end

          # Reject a promise once it cannot be resolved anymore or an error occured when calculating its result.
          # @param  *reasons [Array<String,Exception,Promise>]
          # @return          [nil]
          def reject(*reasons)
            raise Exception.new("A once resolved promise can not be rejected later") if @state == State::RESOLVED
            raise Exception.new("A rejected promise can not be rejected again with a different reason (#{@values}, #{reasons})") if @state == State::REJECTED && reasons != @values
            return nil unless @state == State::PENDING

            # If this promise is rejected with another promise, the final reasons are not yet
            # known, so we we register this promise to be rejected once all reasons are resolved.
            raise(TypeError, 'A promise cannot be rejected with itself.') if reasons.include?(self)
            # TODO: reject should not do unwrapping according to https://github.com/getify/You-Dont-Know-JS/blob/master/async%20%26%20performance/ch3.md
            #if reasons.find{ |r| r.respond_to?(:then) }
            #  self.class.all(reasons).then(Proc.new{ |reasons| reject(*reasons) }, method(:reject))
            #  return
            #end

            # Update the state.
            @values = reasons
            @state  = State::REJECTED

            # Trigger the queued handlers.
            if @handlers.empty?
              # No "then"/"catch" handlers have been added to the promise.
              unhandled_rejection(*@values)
            else
              # Otherwise: Potentially handlers are awaiting results.
              # If no catch handler is called, the rejection might get unnoticed, so we emit a warning.
              until @handlers.empty?
                handler = @handlers.shift
                if handler.on_reject.respond_to?(:call)
                  handle(handler.on_reject, handler.resolve_next, handler.reject_next)
                else
                  # No on_reject handler given: equivalent to identity { |reason| raise(reason) }, so we call reject_next
                  # See: https://www.promisejs.org/api/#Promise_prototype_then
                  if handler.reject_next.respond_to?(:call)
                    handler.reject_next.call(*@values)
                  end
                end
              end
            end
            # We must return nil, otherwise if this promise is rejected inside the 
            # block of an outer Promise, the block would implicitely return a 
            # resolved Promise and cause complicated errors.
            return nil
          end

          # Executes a handler and passes on its results or error.
          # @param reaction   [Proc]
          # @param on_success [Proc]
          # @param on_failure [Proc]
          # @note  Precondition: Status is already set to State::RESOLVED or State::REJECTED
          def handle(reaction, on_success, on_failure)
            defer{
              begin
                new_results = *reaction.call(*@values)
                
                # SU8 in Ruby 1.8.6 the return value from 'send' was nil
                # when it needed to be []
                new_results = [] if new_results.nil? #SU8 
                
                if new_results.find{ |r| r.respond_to?(:then) }
                  self.class.all(new_results).then(Proc.new{ |results| on_success.call(*results) }, on_failure)
                elsif on_success.respond_to?(:call)
                  on_success.call(*new_results)
                end
              rescue StandardError => error
                if on_failure.respond_to?(:call)
                  on_failure.call(error)
                end
                ConsolePlugin.error(error)
              end
            }
          end

          def unhandled_rejection(*reasons)
            reason = reasons.first
            warn("Uncaught promise rejection with reason [#{reason.class}]: \"#{reason}\"")
            if reason.is_a?(Exception) && reason.backtrace
              # Make use of the backtrace to point at the location of the uncaught rejection.
              filtered_backtrace = reason.backtrace.inject([]){ |lines, line|
                break lines if line.match(__FILE__)
                lines << line
              }
              # the above inject[] didn't work in SU8 and returned nil
              filtered_backtrace = reason.backtrace 

              location = filtered_backtrace.last[/[^\:]+\:\d+/] # /path/filename.rb:linenumber
            else
              filtered_backtrace = caller.inject([]){ |lines, line|
                next lines if line.match(__FILE__)
                lines << line
              }
              location = filtered_backtrace.first[/[^\:]+\:\d+/] # /path/filename.rb:linenumber
            end
            Kernel.warn(filtered_backtrace.join($/))
            Kernel.warn("Tip: Add a Promise#catch block to the promise after the block in #{location}")
          end

          # Redefine the inspect method to give shorter output.
          # @override
          # @return [String]
          def inspect
            return "#<#{self.class}:0x#{(self.object_id << 1).to_s(16)}>"
          end

          def defer(&callback)
            UI.start_timer(0.0, false, &callback)
            return nil
          end

          class Deferred

            def initialize
              @resolve = nil
              @reject = nil
              @promise = Promise.new{ |resolve, reject|
                @resolve = resolve
                @reject = reject
              }
            end
            attr_reader :promise

            def resolve(*results)
              @resolve.call(*results)
            end

            def reject(*reasons)
              @reject.call(*reasons)
            end

          end # class Deferred

        end # class Promise

      end # class Bridge


      # Optionally requires 'json.rb'
      # Requires Sketchup
      class Bridge

        # For serializing objects, we choose JSON.
        # Objects passed between bridge instances must be of JSON-compatible types:
        #     object literal, array, string, number, boolean, null
        # If available and compatible, we prefer JSON from the standard libraries, otherwise we use a fallback JSON converter.
        #
        
        
        #if !defined?(Sketchup) || Sketchup.version.to_i >= 14
          begin
            # `Sketchup::require "json"` raises no error, but displays in the load errors popup.
            # As a workaround, we use `load`.
            load 'json.rb' unless defined?(::JSON)
            # No support for option :quirks_mode ? Fallback to JSON implementation in this library.
            raise(RuntimeError) unless ::JSON::VERSION_MAJOR >= 1 && ::JSON::VERSION_MINOR >= 6

            module JSON
              def self.generate(object)
                # quirks_mode generates JSON from objects other than Hash and Array.
                return ::JSON.generate(object, {:quirks_mode => true})
              end
              def self.parse(string)
                return ::JSON.parse(string, {:quirks_mode => true})
              end
            end

          rescue LoadError, RuntimeError # LoadError when loading 'json.rb', RuntimeError when version mismatch
      
            # Fallback JSON implementation.
            module JSON

              def self.generate(object)
                # Split at every even number of unescaped quotes. This gives either strings
                # or what is between strings.
                object = self.traverse_object(object.clone)
                json_string = object.inspect.split(/("(?:\\"|[^"])*")/).map { |string|
                  next string if string[0..0] == '"' # is a string in quotes
                  # If it's not a string then replace : and null
                  string.gsub(/=>/, ':').gsub(/\bnil\b/, 'null')
                }.join('')
                return json_string
              end

              def self.parse(string)
                # Split at every even number of unescaped quotes. This gives either strings
                # or what is between strings.
                # ruby_string = json_string.split(/(\"(?:.*?[^\\])*?\")/).
                # The outer capturing braces () are important for that ruby keeps the separator patterns in the returned array.
                regexp_separate_strings = /("(?:\\"|[^"])*")/
                regexp_text = /[^\d\-.:{}\[\],\s]+/
                regexp_non_keyword = /^(true|false|null|undefined)$/
                ruby_string = string.split(regexp_separate_strings).
                    map{ |s|
                  # It is a string in quotes.
                  if s[0..0] == '"'
                    # Convert escaped unicode characters because eval won't convert them.
                    # Eval would give "u00fc" instead of "ü" for "\"\\u00fc\"".
                    s.gsub(/\\u([\da-fA-F]{4})/) { |m|
                      [$1].pack('H*').unpack('n*').pack('U*')
                    }
                  else
                    # Don't allow arbitrary textual expressions outside of strings.
                    raise(BridgeInternalError, 'JSON string contains invalid unquoted textual expression') if s[regexp_text] && !s[regexp_text][regexp_non_keyword]
                    # raise if s[/(true|false|null|undefined)/] && !s[/\w+/][//] # TODO
                    # If it's not a string then replace : and null and undefined.
                    s.gsub(/:/, '=>').
                        gsub(/\bnull\b/, 'nil').
                        gsub(/\bundefined\b/, 'nil')
                  end
                }.join('')
                result = eval(ruby_string)
                return result
              end

              #private

              # Traverses containers of a JSON-like object recursively and applies a code block
              # SU8 - I've reimplemented the JSON.traverse function to run properly
              def self.traverse_object(o)
                if o.is_a?(Array)
                  return o.map{ |v| self.traverse_object(v) }
                elsif o.is_a?(Hash)
                  o_copy = {}
                  o.each{ |k, v|
                    o_copy[self.traverse_object(k)] = self.traverse_object(v)
                  }
                  return o_copy
                else
                  o.is_a?(Symbol) ? o.to_s : o
                end
              end
              #private_class_method :traverse_object

            end # module JSON

          end

        #end

      end # class Bridge



      # Optionally requires 'json.rb'



      class Bridge
        # Class for message properties, combining the behavior of WebDialog and Promise.
        # SketchUp's WebDialog action callback procs receive as first argument a reference to the dialog.
        # To direct the return value of asynchronous callbacks to the corresponding JavaScript callback, we need to
        # remember the message ID. We retain SketchUp's default behavior by delegating to the webdialog, while adding
        # the functionality of a promise.
        # @!parse include UI::WebDialog
        class ActionContext < Promise::Deferred

          # @param dialog [UI::WebDialog, UI::HtmlDialog]
          # @param id     [Fixnum, Integer]
          # @private
          def initialize(dialog, request_handler, id)
            super()
            # Resolves a query from JavaScript and returns the result to it.
            on_resolve = Proc.new{ |*results|
              parameters_string = Bridge::JSON.generate(results)[1...-1]
              parameters_string = 'undefined' if parameters_string.nil? || parameters_string.empty?
              request_handler.send({
                :name => 'Bridge.requestHandler.receive',
                :parameters => [@id, {:success => true, :parameters => results}]
              })
              nil
            }
            # Rejects a query from JavaScript and and give the reason/error message.
            on_reject = Proc.new{ |*reasons|
              #raise(ArgumentError, 'Argument `reason` must be an Exception or String.') unless reason.is_a?(Exception) || reason.is_a?(String)
              reasons.map!{ |reason|
                if reason.is_a?(Exception)
                  {
                    :name => reason.class.name,
                    :message => reason.message,
                    :stack => reason.backtrace
                  }
                else
                  reason
                end
              }
              request_handler.send({
                :name => 'Bridge.requestHandler.receive', 
                :parameters => [@id, {:success => false, :parameters => reasons}]
              })
              nil
            }
            # Register these two handlers.
            self.promise.then(on_resolve, on_reject)
            @dialog = dialog
            @id = id
          end

          alias_method :return, :resolve

          # Make this class work as a proxy for dialog.
          # @see UI::WebDialog
          def method_missing(method_name, *parameters, &block)
            return @dialog.__send__(method_name, *parameters, &block)
          end

        end # class ActionContext

      end # class Bridge


      class Bridge


        # @private
        module Utils

          def self.log_error(error, metadata={})
            if defined?(AE::ConsolePlugin)
              AE::ConsolePlugin.error(error, metadata)
            elsif error.is_a?(Exception)
              #$stderr << "#{error.class.name}: #{error.message}" << $/
              #$stderr << error.backtrace.join($/) << $/
              $stderr.write "#{error.class.name}: #{error.message}" + $/
              $stderr.write error.backtrace.join($/) +  $/
            else
              #$stderr << error << $/
              #$stderr << metadata[:backtrace].join($/) << $/ if metadata.include?(:backtrace)
              $stderr.write  error + $/
              $stderr.write  metadata[:backtrace].join($/) + $/ if metadata.include?(:backtrace)
            end
          end


        end


      end



      class Bridge

        # @private
        class RequestHandler # interface

          def send(message)
            raise NotImplementedError
          end

          def receive(action_context, request)
            raise NotImplementedError
          end

        end

        # @private
        class DialogRequestHandler < RequestHandler # abstract class

          def initialize(dialog, bridge=nil)
            super()
            @dialog = dialog
            @bridge = bridge
          end

          def send(message)
            name = message[:name]
            parameters_string = Bridge::JSON.generate(message[:parameters])[1...-1]
            @dialog.execute_script("#{name}(#{parameters_string})")
          end

          private

          def handle_request(action_context, request) # FIXME: Avoid access to Bridge @handlers and @dialog
            unless request.is_a?(Hash) &&
                (defined?(Integer) ? request['id'].is_a?(Integer) : request['id'].is_a?(Fixnum)) &&
                request['name'].is_a?(String) &&
                request['parameters'].is_a?(Array)
              raise(BridgeInternalError, "Bridge received invalid data: \n#{value}")
            end
            id         = request['id']
            name       = request['name']
            parameters = request['parameters'] || []

            # Here we pass a wrapper around the dialog which preserves the message ID to
            # identify the corresponding JavaScript callback.
            # This allows to run asynchronous code (external application etc.) and return
            # later the result to the JavaScript callback even if the dialog has continued
            # sending/receiving messages.
            if request['expectsCallback']
              response = ActionContext.new(@dialog, self, id)
              begin
                # Get the callback.
                unless @bridge.handlers.include?(name)
                  raise(BridgeRemoteError.new("No registered callback `#{name}` for #{@dialog} found."))
                end
                handler = @bridge.handlers[name]
                handler.call(response, *parameters)
              rescue Exception => error
                # Reject the promise.
                response.reject(error)
                # Re-raise for logging.
                raise(error)
              end
            else
              # Get the callback.
              unless @bridge.handlers.include?(name)
                raise(BridgeRemoteError.new("No registered callback `#{name}` for #{@dialog} found."))
              end
              handler = @bridge.handlers[name]
              handler.call(@dialog, *parameters)
            end
          end

        end

        # @private
        class RequestHandlerHtmlDialog < DialogRequestHandler

          # Receives the raw messages from the HtmlDialog (Bridge.call) and chooses the corresponding callbacks.
          # @private Not for public use.
          # @param   action_context [UI::ActionContext]
          # @param   request        [Object]
          # @private
          def receive(action_context, request)
            handle_request(action_context, request)
          rescue Exception => error
            Utils.log_error(error)
          end

        end

        # @private
        class RequestHandlerWebDialog < DialogRequestHandler

          # Receives the raw messages from the WebDialog (Bridge.call) and chooses the corresponding callbacks.
          # @private Not for public use.
          # @param   dialog           [UI::WebDialog]
          # @param   parameter_string [String]
          def receive(action_context, parameter_string)
            # Get message data from the hidden input element.
            # this has nothing to do with SU8 but:"
            # the element name "Bridge.requestField" is wrong in Bridge.js and
            # @dialog is the appropriate object
            #value   = dialog.get_element_value("#{NAMESPACE}.requestField") # returns empty string if element not found
            value   = @dialog.get_element_value("#{NAMESPACE}.Bridge.requestField") # returns empty string if element not found
            request = Bridge::JSON.parse(value)
            handle_request(action_context, request)
          rescue Exception => error
            Utils.log_error(error)
          ensure
            # Acknowledge that the message has been received and enable the bridge to send
            # the next message if available.
            @bridge.call('Bridge.requestHandler.ack')
          end

        end

      end # class Bridge




      # Requires SketchUp module UI

      class Bridge
        # This Bridge provides an intuitive and asynchronous API for message passing between SketchUp's Ruby environment 
        # and dialogs. It supports any amount of parameters of any JSON-compatible type and it uses Promises to 
        # asynchronously access return values on success or handle failures.
        #
        # Ruby methods:
        # - `Bridge.new(dialog)`
        #   Creates a Bridge instance for a UI::WebDialog or UI::HtmlDialog.
        # - `Bridge.decorate(dialog)`
        #   Alternatively adds the Bridge methods to a UI::WebDialog or UI::HtmlDialog.
        # - `Bridge#on(callbackname) { |deferred, *arguments| }`
        #   Registers a callback on the Bridge.
        # - `Bridge#call(js_function_name, *arguments)`
        #   Invokes a JavaScript function with multiple arguments.
        # - `Bridge#get(js_function_name, *arguments).then{ |result| }`
        #   Invokes a JavaScript function and returns a promise that will be resolved 
        #   with the JavaScript function's return value.
        #
        # JavaScript functions:
        # - `Bridge.call(rbCallbackName, ...arguments)`
        #   Invokes a Ruby callback with multiple arguments.
        # - `Bridge.get(rbCallbackName, ...arguments).then(function (result) { })`
        #   Invokes a Ruby callback and returns a promise that will be resolved 
        #   with the callback's return value.
        # - `Bridge.puts(stringOrObject)`
        #   Shorthand to print a string/object to the Ruby console.
        # - `Bridge.error(errorObject)`
        #   Shorthand to print an error to the Ruby console.
        # 
        # Github project: https://github.com/Aerilius/sketchup-bridge/

        # Add the bridge to an existing UI::WebDialog/UI::HtmlDialog.
        # This can be used for convenience and will define the bridge's methods
        # on the dialog and delegate them to the bridge.
        # @param dialog [UI::WebDialog, UI::HtmlDialog]
        # @return       [UI::WebDialog, UI::HtmlDialog] The decorated dialog
        def self.decorate(dialog)
          bridge = self.new(dialog)
          dialog.instance_variable_set(:@bridge, bridge)

          #[:on, :once, :off, :call, :get].each{ |method_name|
          #  define_method on dialog that receives same parameters as bridge.method(method_name)
          #}
          def dialog.bridge
            return @bridge
          end

          def dialog.on(name, &callback)
            @bridge.on(name, &callback)
            return self
          end

          def dialog.once(name, &callback)
            @bridge.once(name, &callback)
            return self
          end

          def dialog.off(name)
            @bridge.off(name)
            return self
          end

          def dialog.call(function, *parameters, &callback)
            @bridge.call(function, *parameters, &callback)
          end

          def dialog.get(function, *parameters)
            return @bridge.get(function, *parameters)
          end

          return dialog
        end

        # Add a callback handler. Overwrites an existing callback handler of the same name.
        # @param name            [String]             The name under which the callback can be called from the dialog.
        # @param callback        [Proc,UnboundMethod] A method or proc for the callback, if no yield block given.
        # @yield                                      A callback to be called from the dialog to execute Ruby code.
        # @yieldparam dialog     [ActionContext]      An object referencing the dialog, enhanced with methods
        #                                             {ActionContext#resolve} and {ActionContext#resolve} to return results to the dialog.
        # @yieldparam parameters [Array<Object>]      The JSON-compatible parameters passed from the dialog.
        # @return                [self]
        def on(name, &callback)
          raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
          raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
          raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given?
          @handlers[name] = callback
          return self
        end

        # Add a callback handler to be called only once. Overwrites an existing callback handler of the same name.
        # @param name            [String]             The name under which the callback can be called from the dialog.
        # @param callback        [Proc,UnboundMethod] A method or proc for the callback, if no yield block given.
        # @yield                                      A callback to be called from the dialog to execute Ruby code.
        # @yieldparam dialog     [ActionContext]      An object referencing the dialog, enhanced with methods
        #                                             {ActionContext#resolve} and {ActionContext#resolve} to return results to the dialog.
        # @yieldparam parameters [Array<Object>]      The JSON-compatible parameters passed from the dialog.
        # @return                [self]
        def once(name, &callback)
          raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
          raise(ArgumentError, "Argument `name` can not be `#{name}`.") if RESERVED_NAMES.include?(name)
          raise(ArgumentError, 'Argument `callback` must be a Proc or UnboundMethod.') unless block_given?
          @handlers[name] = Proc.new { |*parameters|
            @handlers.delete(name)
            callback.call(*parameters)
          }
          return self
        end

        # Remove a callback handler.
        # @param  name [String]
        # @return      [self]
        def off(name)
          raise(ArgumentError, 'Argument `name` must be a String.') unless name.is_a?(String)
          @handlers.delete(name)
          return self
        end

        # Call a JavaScript function with JSON parameters in the webdialog.
        # @param name        [String]        The name of a public JavaScript function
        # @param *parameters [Array<Object>] An array of JSON-compatible objects
        # TODO: Catch JavaScript errors!
        def call(name, *parameters)
          raise(ArgumentError, 'Argument `name` must be a valid method identifier string.') unless name.is_a?(String) && name[/^[\w\.]+$/]
          @request_handler.send({
            :name => name,
            :parameters => parameters
          })
        end

        # Call a JavaScript function with JSON parameters in the webdialog and get the
        # return value in a promise.
        # @param  function_name [String]  The name of a public JavaScript function
        # @param  *parameters   [Object]  An array of JSON-compatible objects
        # @return               [Promise]
        def get(function_name, *parameters)
          raise(ArgumentError, 'Argument `function_name` must be a valid method identifier string.') unless function_name.is_a?(String) && function_name[/^[\w\.]+$/]
          return Promise.new { |resolve, reject|
            handler_name = create_unique_handler_name('resolve/reject')
            once(handler_name) { |action_context, success, *parameters|
              if success
                resolve.call(*parameters)
              else
                reject.call(*parameters)
              end
            }
            @request_handler.send({
              :name => 'Bridge.requestHandler.get',
              :parameters => [handler_name, function_name, *parameters]
            })
          }
        end

        # @private
        attr_reader :handlers

        private

        # The namespace for prefixing internal callback names to avoid clashes with code using this library.
        NAMESPACE = 'Bridge'
        # The module path of the corresponding JavaScript implementation.
        JSMODULE = 'Bridge'
        # Names that are used internally and not allowed to be used as callback handler names.
        RESERVED_NAMES = []
        # Callback name where JavaScript messages are received.
        CALLBACKNAME = 'Bridge.receive'
        attr_reader :dialog

        # Create an instance of the Bridge and associate it with a dialog.
        # @param dialog [UI::HtmlDialog, UI::WebDialog]
        def initialize(dialog, request_handler=nil)
          raise(ArgumentError, 'Argument `dialog` must be a UI::HtmlDialog or UI::WebDialog.') unless defined?(UI::HtmlDialog) && dialog.is_a?(UI::HtmlDialog) || dialog.is_a?(UI::WebDialog)
          @dialog         = dialog
          @handlers       = {}

          if request_handler.nil?
            if defined?(UI::HtmlDialog) && dialog.is_a?(UI::HtmlDialog) # SketchUp 2017+
              @request_handler = RequestHandlerHtmlDialog.new(dialog, self)
            else
              @request_handler = RequestHandlerWebDialog.new(dialog, self)
            end
          else
            @request_handler = request_handler
          end
          @dialog.add_action_callback(CALLBACKNAME, &@request_handler.method(:receive))

          add_default_handlers
        end

        # Add additional optional handlers for calls from JavaScript to Ruby.
        def add_default_handlers
          # Puts (for debugging)
          @handlers["#{NAMESPACE}.puts"] = Proc.new { |dialog, *arguments|
            puts(*arguments.map { |argument| argument.inspect })
          }
          RESERVED_NAMES << "#{NAMESPACE}.puts"

          # Error channel (for debugging)
          @handlers["#{NAMESPACE}.error"] = Proc.new { |dialog, type, message, backtrace|
            Utils.log_error(type + ': ' + message, {:language => 'javascript', :backtrace => backtrace})
          }
          RESERVED_NAMES << "#{NAMESPACE}.error"
        end

        # Create a string which has not yet been registered as callback handler, to avoid collisions.
        # @param  string [String]
        # @return        [String]
        def create_unique_handler_name(string)
          begin
            int = (10000*rand).round
            handler_name = "#{NAMESPACE}.#{string}_#{int}"
          end while @handlers.include?(handler_name)
          return handler_name
        end

        # An error caused by malfunctioning of this library.
        # @private
        class BridgeInternalError < StandardError
          def initialize(exception, type=exception.class.name, backtrace=(exception.respond_to?(:backtrace) ? exception.backtrace : caller))
            super(exception)
            @type = type
            set_backtrace(backtrace)
          end
          attr_reader :type
        end

        # An error caused by the remote counter-part of a bridge instance.
        # @private
        class BridgeRemoteError < StandardError
          def initialize(exception, type=exception.class.name, backtrace=(exception.respond_to?(:backtrace) ? exception.backtrace : caller))
            super(exception)
            @type = type
            set_backtrace(backtrace)
          end
          attr_reader :type
        end

        # @private
        class BridgeRemoteInternalError < BridgeRemoteError
        end

      end # class Bridge


    

  end

end
puts "loaded su bridge"
