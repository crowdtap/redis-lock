require "spec_helper"
require "redis"

describe RedisLock, "#lock" do
  let(:locking_key) { "redis-lock-locking-key" }
  let(:redis)       { Redis.new }
  subject           { RedisLock.new(redis, locking_key) }

  before { redis.flushdb }

  it "returns true when it has locked successfully" do
    subject.should_not be_locked
    subject.lock.should be_true
  end

  it "returns false if the key has already been locked" do
    subject.lock
    subject.lock.should be_false
  end

  it "retries a set number of times" do
    subject.lock

    redis_stub = redis.stubs(:setnx).returns(false)
    3.times { redis_stub = redis_stub.then.returns(false) }

    redis_stub.then.returns(true)

    subject.retry(5.times).lock.should be_true

    redis.should have_received(:setnx).times(5)
    subject.should be_locked
  end
end

describe RedisLock, "#unlock" do
  let(:locking_key) { "redis-lock-locking-key" }
  let(:redis)       { Redis.new }
  let(:redis_lock)  { RedisLock.new(redis, locking_key) }
  before { redis.flushdb }

  context "when locked" do
    subject do
      redis_lock.tap do |lock|
        lock.lock
      end
    end

    it "returns true" do
      subject.unlock.should == true
      subject.should_not be_locked
    end

    it "returns false if key isn't present" do
      redis.del(subject.key)
      subject.unlock.should == false
    end
  end

  context "when not locked" do
    subject { redis_lock }

    it "returns false if the key is not locked" do
      subject.unlock.should == false
      subject.should_not be_locked
    end
  end
end

describe RedisLock, "#lock_for_update" do
  let(:locking_key) { "redis-lock-locking-key" }
  let(:redis)       { Redis.new }
  subject           { RedisLock.new(redis, locking_key) }

  before { redis.flushdb }

  context "when a lock can be acquired" do
    it "runs a block" do
      result = "changes within lock"

      subject.lock_for_update do
        result = "changed!"
      end

      result.should == "changed!"
    end

    it "locks the key during execution" do
      subject.lock_for_update do
        subject.should be_locked
      end
    end

    it "unlocks the key after completion" do
      subject.lock_for_update { }
      subject.should_not be_locked
    end

    it "unlocks when the block raises" do
      expect do
        subject.lock_for_update do
          raise RuntimeError, "something went wrong!"
        end
      end.to raise_error(RuntimeError, "something went wrong!")

      subject.should_not be_locked
    end
  end

  context "when a lock cannot be acquired" do
    before { subject.lock }

    it "does not run the block" do
      result = "doesn't change within lock"

      subject.lock_for_update do
        result = "changed!"
      end

      result.should == "doesn't change within lock"
    end

    it "remains locked" do
      subject.lock_for_update { }
      subject.should be_locked
    end
  end
end