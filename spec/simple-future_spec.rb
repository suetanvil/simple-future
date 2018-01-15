require 'spec_helper'

def time_it(&blk)
  before = Time.now
  blk.call()
  return Time.now - before
end

class ScratchError < RuntimeError; end
class BogoError < RuntimeError
  def initialize(e)
    super(e)
    @unmarshalableValue = proc{42}
  end
end

describe "SimpleFuture" do
  it "lets you specify the number of tasks" do
    expect(SimpleFuture.max_tasks).to be > 0
    SimpleFuture.max_tasks = 4
    expect(SimpleFuture.max_tasks).to be 4
  end

  it "executes a block without changing the current state" do
    foo = 42
    r = SimpleFuture.new do
      foo += 1
      foo
    end

    expect(r.value).to be 43
    expect(foo).to be 42
  end

  it "allows non-blocking polling" do
    # We use time-based measurements to test this, so there's the
    # potential for unusual timing conditions to break this test.  It
    # shouldn't happen on normal hardware and conditions, though.
    r = SimpleFuture.new do
      sleep 1
      42
    end

    expect(r.check_if_ready).to be false
    sleep 2
    expect(r.check_if_ready).to be true
    expect(r.value).to be 42
  end

  it "correctly returns the block's results" do
    f1 = SimpleFuture.new { sleep 1; 1}
    f2 = SimpleFuture.new { sleep 1; 2}
    f3 = SimpleFuture.new { sleep 1; 3}
    f4 = SimpleFuture.new { sleep 1; 4}

    expect(f1.value).to be 1
    expect(f2.value).to be 2
    expect(f3.value).to be 3
    expect(f4.value).to be 4
  end

  it "allows multiple calls to wait" do
    f1 = SimpleFuture.new { 42 }
    f1.wait
    expect(f1.value).to be 42

    f1.wait
    expect(f1.value).to be 42

    f1.wait
    expect(f1.value).to be 42
  end


  
  it "lets you wait until completion and test for that" do
    r = SimpleFuture.new { 12345 }
    expect(r.complete?).to be false

    r.wait
    expect(r.complete?).to be true

    expect(r.value).to be 12345
  end

  it "gracefully handles exceptions thrown by the child" do
    r = SimpleFuture.new { raise ScratchError.new("Foo!") }
    expect {r.wait}.to raise_error(SimpleFuture::ChildError, /Foo!/)
  end

  it "returns Exception objects if requested" do
    r = SimpleFuture.new { ScratchError.new("not thrown!") }
    r.wait
    expect(r.value.class).to be ScratchError
    expect(r.value.message).to eq "not thrown!"
  end

  it "attaches the original exception to the ChildError" do
    r = SimpleFuture.new { raise ScratchError.new("Foo!") }
    begin
      r.wait
    rescue SimpleFuture::ChildError => e
      expect(e.cause.class).to be ScratchError
      expect(e.cause.message).to match("Foo!")
    end
  end


  it "cleans up completed child processes" do
    first = SimpleFuture.new { sleep 1; 1}
    second = SimpleFuture.new { sleep 2; 2}
    sleep 1.1

    expect(SimpleFuture.all_done?).to be false

    # First should now have completed:
    expect(first.complete?).to be true
    expect(second.complete?).to be false
    expect(second.check_if_ready).to be false

    # Wait for second one to complete, then scrub
    sleep 1
    expect(second.complete?).to be false
    expect(SimpleFuture.all_done?).to be true
    expect(second.complete?).to be true
  end

  it "does not block when free tasks are available" do
    SimpleFuture.max_tasks = 4

    tt = time_it {
      sfs = (0..3).map{|i| SimpleFuture.new {sleep 1; i} }
      sfs.each{|sf| sf.value}
    }
    expect(tt).to be < 1.1
  end

  it "interprets maximum tasks of 0 as meaning no limit on children" do
    SimpleFuture.max_tasks = 0

    tt = time_it {
      sfs = (0..30).map{|i| SimpleFuture.new {sleep 1; i} }
      sfs.each{|sf| sf.value}
    }
    expect(tt).to be < 1.1
  end

  it "blocks when the maximum number of children is reached" do
    SimpleFuture.max_tasks = 4

    tt = time_it {
      sfs = (0..7).map{|i| SimpleFuture.new {sleep 1; i} }
      sfs.each{|sf| sf.value}
    }
    expect(tt).to be > 1
    expect(tt).to be < 2.1
  end

  it "can block until all active children have finished" do
    SimpleFuture.max_tasks = 4
    sfs = (0..3).map{|i| SimpleFuture.new {sleep 1; i} }

    SimpleFuture.wait_for_all

    sfs.each{|sf|
      expect(sf.check_if_ready).to be true
    }
  end

  it "handles the case where the result isn't marshallable" do
    r = SimpleFuture.new { proc{42} }
    expect {r.value}.to raise_error(SimpleFuture::ResultTypeError, /Proc/)
  end

  it "handles the case where the exception contains an unmarshallable item" do
    r = SimpleFuture.new { raise BogoError.new("error!") }
    expect {r.value}.to raise_error(SimpleFuture::ResultTypeError, /dumped/)
  end
  
end
