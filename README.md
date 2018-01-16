# SimpleFuture: Simple, Process-based Concurrency

`SimpleFuture` is a Ruby module that gives you pretty good concurrency
without a lot of work.  It doesn't use threads and so will avoid their
common pitfalls as well working on Rubies that don't support them.

It is a simple implementation of [Future][1] construct.

## Resources

* [Home Page](https://github.com/suetanvil/simple-future/)
* [Issues](https://github.com/suetanvil/simple-future/issues)
* [Reference Docs](http://www.rubydoc.info/gems/simple-future/1.0.0/)


## Basic idea

Suppose you need to do a bunch of long-running things concurrently
(e.g. transcode a bunch of videos) and you don't want to have to deal
with threads.

The easy thing to do is fork a subprocess for each item and then use
`Marshal` and `IO.pipe` to retrieve the result(s).

That's pretty much what `SimpleFuture` does for you.  You pass it a
block and it runs it in a forked child and gives you back the result
when it's ready.  And as a bonus, it will limit the number of children
it creates at one time, so you don't have to.

## Those videos, for example

So let's say you're transcoding a bunch of (legally obtained) video
files:

    for vid in Dir.glob('*.mp4')
      run_transcode(vid, "../transcoded/") or 
        puts "Error transcoding #{vid}"
    end

This is nice and simple, but it isn't taking advantage of the zillions
of cores you have on your fancy modern workstation.  So you use
`SimpleFuture`:

    for vid in Dir.glob('*.mp4')
        SimpleFuture.new { run_transcode(vid, "../transcoded/") }
    end
    
    SimpleFuture.wait_for_all

And this will do what you want.  In particular, it limits itself to
one process per CPU core so you don't thrash your system.  (You can
change this limit via `SimpleFuture.max_tasks`.)

## Wait for it

Notice that we end the script with `wait_for_all`.  This is because
each `SimpleFuture` needs to have its `wait` method called at some
point.  This is what `wait_for_all` does.  (`SimpleFuture.new` will
also sometimes call an existing instance's `wait` but you can't depend
on that.)

Since `wait` blocks until the child process finishes, so will
`wait_for_all`.  If you don't like that, you can also use `all_done?`;
this won't block so you can do other stuff while waiting:

    while !SimpleFuture.all_done?
        puts "Waiting for child processes to finish."
        sleep 1
    end

By the way, it's harmless to call `wait_for_all` if nothing is running
so it's often good practice to just call it before quitting.


## I need answers

But let's say that `transcode()` also returns an important result such
as the compression ratio and you want to know the average. This means
that you need to get a result back from the child
process. Fortunately, `SimpleFuture` handles this.

First, we need to keep all of the `SimpleFuture` objects:

    futures = []
    for vid in Dir.glob('*.mp4')
        futures.push(SimpleFuture.new { run_transcode(vid, "../transcoded/") })
    end

Next, we use `map` to extract the results:

    ratios = futures.map{|f| f.value}

And then compute the average:

    sum = ratios.inject(0.0, :+)
    puts "Average compression ratio: #{sum / ratios.size}" if
        ratios.size > 0

Note that we're not calling `wait_for_all` here.  This is because
`value` already calls `wait` and since it gets called on each
`SimpleFuture`, we know for sure that all child processes have been
cleaned up.

Also, it may be tempting to merge the loop and the map above but this
is a **bad idea**:

    ratios = []
    for vid in Dir.glob('*.mp4')
        f = SimpleFuture.new { run_transcode(vid, "../transcoded/") }
        ratios.push(f.wait)     # BAD IDEA! DON'T DO THIS!
    end

Because `wait` stops until the child process finishes, you're
effectively going back to single-threaded processing.  You need to
create a collection of `SimpleFuture`s first and *then* `wait` on
them.

## Oooopsie!

`SimpleFuture` tries to only throw exceptions in two cases: something
is wrong with your code or something has gone wrong beyond its control
(e.g. Ruby crashed).  In either case, the right thing at this point is
usually to quit. (If that's not an option, the rubydocs will give you
the gory details on what throws what.)

Generally, you should:

1. Never quit the child process; always exit the block with a (simple,
   Marshal-compatible) value.
2. Avoid throwing exceptions out of the child block unless it's to
   avoid breaking rule 1.

Also, you can probably use low-level systems methods to trick
`SimpleFuture` into doing the wrong thing.  Don't do that.


## Installation

SimpleFuture is available as a gem:

    $ [sudo] gem install simple-future

Source code is available at GitHub:

    $ git clone https://github.com/suetanvil/simple-future.git
    $ cd simple-future
    $ rake

To build, you need to install `rake`, `rspec` and `yard`.

It should work on Ruby 2.2.0 or later, provided your Ruby/OS
combination supports `Process.fork()`.  To confirm this, evaluate

    Process.respond_to?(:fork)      # true

If it returns true, you're good to go.  If not, the gem will noisily
fail.


## Bugs and Quirks

`SimpleFuture.new` will block if there are too many child processes.
In this case, it waits for the **oldest** process to finish, even if
other processes have finished in the meantime.

The unit tests use `sleep` to give child processes a relatively
predictable execution times and test based on that.  This means
there's a chance that the tests can fail on a sufficiently slow or
overloaded system.  (It's unlikely that this can happen in real life,
though.)




[1]:https://en.wikipedia.org/wiki/Futures_and_promises
