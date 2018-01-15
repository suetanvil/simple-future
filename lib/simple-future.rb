# SimpleFuture: support for easy process-based concurrency.
#
# Copyright (C) 2018 Chris Reuter
# Released under the MIT license
# USE AT OWN RISK!

# Sanity check; fail if the platform doesn't support Process.fork.
raise "This Ruby does not implement Process.fork" unless
  Process.respond_to? :fork

require 'etc'
require 'io/wait'

# A container holding the (eventual) result of a forked child process
# once that process finishes.  The child process executes the code
# block that must be passed to the constructor:
#
#       sf = SimpleFuture.new { do_slow_thing }
#       ... do stuff ...
#       use(sf.value)
#
# The code block **must** return a value that can be encoded by
# `Marshal` and **must not** exit prematurely.
#
# Exceptions thrown inside the block will trigger a
# `SimpleFuture::ChildError` in the parent process but that exception
# will contain the original in its `cause` field.
# 
class SimpleFuture

  # Exception class for errors related to SimpleFuture.  All
  # exceptions thrown by SimpleFuture are either `Error` or a
  # subclass.
  class Error < RuntimeError; end

  # Exception class for the case(s) where the result is of a type that
  # can't be returned (e.g. because it's one of the types
  # `Marshal.dump()` fails on).  This can also apply to exceptions; if
  # an exception object holds an unmarshallable value, you'll get one
  # of these instead of a `SimpleFuture::ChildError`.
  class ResultTypeError < Error; end

  # Exception class for the case where an uncaught exception is thrown
  # in the child process.
  class ChildError < Error
    # If the child process threw an exception, this is it.  Otherwise,
    # it's nil.
    attr_reader :cause

    # @param msg [String]       The exception text.
    # @param cause [Exception]  If valid, the exception raised in the child
    def initialize(msg, cause = nil)
      super(msg)
      @cause = cause
    end

    def to_s
      result = super.to_s
      result += " (cause: #{cause.class} '#{@cause.to_s}')" if @cause
      return result
    end
  end

  # Container for holding a correct result.  If an error occurred in
  # the child, it will return the raw Exception instead.  Wrapping a
  # value (including an Exception) in a ResultContainer marks it as a
  # correct result.
  class ResultContainer
    attr_reader :value
    def initialize(v)
      @value = v
    end
  end

  private_constant :ResultContainer     # Make this private

  private   # For some reason, YARD shows these if they're not private
  
  @@max_tasks = Etc.nprocessors     # Max. number of concurrent processes
  @@in_progress = []                # List of active child processes

  public

  # In addition to creating a new `SimpleFuture`, the constructor
  # creates a child process and evaluates `action` in it.  If the
  # maximum number of child processes would be exceeded, it will block
  # until a process finishes.
  def initialize(&action)
    @readPipe = nil
    @pid = nil
    @complete = false
    @result = nil

    self.class.all_done?       # Reclaim all completed children
    block_until_clear()
    launch(action)
  end

  # Test if the child process has finished and its result is
  # available.
  #
  # Note that this will only be true after a call to `wait` (i.e. the
  # child process finished **and** its result has been retrieved.)  If
  # you want to see if the result is (probably) available, use
  # `check_if_ready`.
  def complete?()   return @complete; end

  # Return the result of the child process, blocking if it is not yet
  # available.  Blocking is done by calling `wait`, so the process
  # will be cleaned up.
  def value
    wait
    return @result
  end

  # Block until the child process finishes, recover its result and
  # clean up the process.  `wait` **must** be called for each
  # `SimpleFuture` to prevent zombie processes. In practice, this is
  # rarely a problem since `value` calls `wait` and you usually want
  # to get all of the values.  See `wait_for_all`.
  #
  # It is safe to call `wait` multiple times on a `SimpleFuture`.
  #
  # @raise [ChildError] The child process raised an uncaught exception.
  # @raise [ResultTypeError] Marshal cannot encode the result
  # @raise [Error] An error occurred in the IPC system or child process.
  def wait
    # Quit if the child has already exited    
    return if complete?

    # Read the contents; this may block
    data = @readPipe.read

    # Reap the child process; this shouldn't block for long
    Process.wait(@pid)

    # And now we're complete, regardless of what happens next.  (We
    # set it early so that errors later on won't allow waiting again
    # and associated mystery errors.)
    @complete = true

    # Close and discard the pipe; we're done with it
    @readPipe.close
    @readPipe = nil

    # If the child process exited badly, this is an error
    raise Error.new("Error in child process #{@pid}!") unless
      $?.exitstatus == 0 && !data.empty?

    # Decode the result.  If it's an exception object, that's the
    # error that was thrown in the child and that means an error here
    # as well.
    rbox = Marshal.load(data)
    raise rbox if rbox.is_a? ResultTypeError
    raise ChildError.new("Child process failed with an exception.", rbox) if
      rbox.is_a? Exception

    # Ensure rbox is a ResultContainer. This *probably* can't happen.
    raise Error.new("Invalid result object type: #{rbox.class}") unless
      rbox.is_a? ResultContainer    

    # Aaaaaand, retrieve the value.
    @result = rbox.value
    
    return      # return nil
  end


  # Check if the child process has finished evaluating the block and
  # has a result ready.  If `check_if_ready` returns `true`, `wait`
  # will not block when called.
  #
  # Note: `check_if_ready` tests if there's data on the pipe to the
  # child process to see if it has finished.  A sufficiently evil
  # child block might be able to cause a true result while still
  # blocking `wait`.
  #
  # Don't do that.
  #
  # @return [Boolean]
  def check_if_ready
    return true if complete?
    return false unless @readPipe.ready?
    wait
    return true
  end


  # Return the maximum number of concurrent child processes allowed.
  def self.max_tasks()     return @@max_tasks; end

  # Set the maximum number of concurrent child processes allowed.  If
  # set to less than 1, it is interpreted as meaning no limit.
  #
  # It is initially set to the number of available cores as provided
  # by the `Etc` module.
  def self.max_tasks=(value)
    @@max_tasks = value
  end

  # Test if all instances created so far have run to completion.  As a
  # side effect, it will also call `wait` on instances whose child
  # processes are running but have finished (i.e. their
  # `check_if_ready` would return true.)  This lets you use it as a
  # non-blocking way to clean up the remaining children.
  def self.all_done?
    @@in_progress.select!{ |sp| !sp.check_if_ready }
    return @@in_progress.size == 0
  end

  # Wait until all child processes have run to completion and recover
  # their results.  Programs should call this before exiting if there
  # is a chance that an instance was created without having `wait`
  # called on it.
  def self.wait_for_all
    @@in_progress.each{|sp| sp.wait}
    @@in_progress = []
    return
  end
  
  private

  # Create a forked child process connected to this one with a pipe,
  # eval `action` and return the marshalled result (or exception, in
  # case of an error) via the pipe.  Results are wrapped in a
  # `ResultContainer` so that the parent can distinguish between
  # exceptions and legitimately returned Exception objects.
  def launch(action)
    @readPipe, writePipe = IO.pipe
    @pid = Process.fork do
      @readPipe.close()

      result = nil
      begin
        result = ResultContainer.new( action.call() )
      rescue Exception => e
        result = e
      end

      rs = nil
      begin
        rs = Marshal.dump(result)
      rescue TypeError => e
        rv = result
        rv = rv.value if rv.class == ResultContainer
        rs = Marshal.dump(ResultTypeError.new("Type #{rv.class} " +
                                              "cannot be dumped."))
      end

      writePipe.write(rs)
      writePipe.close
      exit!(0)
    end

    writePipe.close

    @@in_progress.push self
  end

  # If we're currently at maximum allowed processes, wait until the
  # oldest of them finishes.  (TO DO: if possible, make it wait until
  # *any* process exits.)
  def block_until_clear
    return unless @@max_tasks > 0 && @@in_progress.size >= @@max_tasks

    @@in_progress.shift.wait()
  end

end

