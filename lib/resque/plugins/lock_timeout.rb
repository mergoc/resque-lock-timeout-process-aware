module Resque
  module Plugins
    # If you want only one instance of your job running at a time,
    # extend it with this module:
    #
    # require 'resque-lock'
    #
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::LockTimeout
    #   @queue = :network_graph
    #
    #   def self.perform(repo_id)
    #     heavy_lifting
    #   end
    # end
    #
    # If you wish to limit the durati on a lock may be held for, you can
    # set/override `lock_timeout`. e.g.
    #
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::LockTimeout
    #   @queue = :network_graph
    #
    #   # lock may be held for upto an hour.
    #   @lock_timeout = 3600
    #
    #   def self.perform(repo_id)
    #     heavy_lifting
    #   end
    # end
    #
    module LockTimeout
      # @abstract You may override to implement a custom identifier,
      #           you should consider doing this if your job arguments
      #           are many/long or may not cleanly cleanly to strings.
      #
      # Builds an identifier using the job arguments. This identifier
      # is used as part of the redis lock key.
      #
      # @param [Array] args job arguments
      # @return [String, nil] job identifier
      def identifier(*args)
        args.join('-')
      end

      # Override to fully control the lock key used. It is passed
      # the job arguments.
      #
      # The default looks like this:
      # `resque-lock-timeout:<class name>:<identifier>`
      #
      # @return [String] redis key
      def redis_lock_key(*args)
        ['lock', name, identifier(*args)].compact.join(":")
      end

      # Number of seconds the lock may be held for.
      # A value of 0 or below will lock without a timeout.
      #
      # @return [Fixnum]
      def lock_timeout
        @lock_timeout ||= 0
      end

      # Try to acquire a lock.
      #
      # * Returns false; when unable to acquire the lock.
      # * Returns true; when lock acquired, without a timeout.
      # * Returns timestamp; when lock acquired with a timeout, timestamp is
      #   when the lock timeout expires.
      #
      # @return [Boolean, Fixnum]
      def acquire_lock!(*args)
        acquired = false
        lock_key = redis_lock_key(*args)

        key_value  = {:lock_until=>0,:pid=>Process.pid}

        unless lock_timeout > 0
          # Acquire without using a timeout.
          acquired = true if Resque.redis.setnx(lock_key, key_value.to_json)
        else
          # Acquire using the timeout algorithm.
          acquired, lock_until = acquire_lock_algorithm!(lock_key,key_value)
        end

        lock_failed(*args) if !acquired && respond_to?(:lock_failed)
        lock_until && acquired ? lock_until : acquired
      end

      # Attempts to aquire the lock using a timeout / deadlock algorithm.
      #
      # Locking algorithm: http://code.google.com/p/redis/wiki/SetnxCommand
      def acquire_lock_algorithm!(lock_key,key_value)
        now = Time.now.to_i
        lock_until = now + lock_timeout
        acquired = false

        key_value[:lock_until] = lock_until

        return [true, lock_until] if Resque.redis.setnx(lock_key, key_value.to_json)
        # Can't acquire the lock, see if it has expired or something happend to the process.
        key_stored = JSON.parse(Resque.redis.get(lock_key))
        lock_expiration = key_stored[:lock_until]
        process_id = key_stored[:pid]
        if (lock_expiration && lock_expiration.to_i < now) && process_alive?(process_id)
          # expired, try to acquire.
          lock_expiration = JSON.parse (Resque.redis.getset(lock_key, key_value.to_json))[:lock_until]
          if lock_expiration.nil? || lock_expiration.to_i < now
            acquired = true
          end
        else
          # Try once more...
          acquired = true if Resque.redis.setnx(lock_key, key_value)
        end

        [acquired, lock_until]
      end

      # Check for process status
      def process_alive?(process_id)
        begin
           Process::kill 0, process_id
           true
         rescue Errno::ESRCH
           false
         end
      end


      # Release the lock.
      def release_lock!(*args)
        Resque.redis.del(redis_lock_key(*args))
      end

      # Convenience method, not used internally.
      #
      # @return [Boolean] true if the job is locked by someone
      def locked?(*args)
        Resque.redis.exists(redis_lock_key(*args))
      end

      # Where the magic happens.
      def around_perform_lock(*args)
        # Abort if another job holds the lock.
        return unless lock_until = acquire_lock!(*args)

        begin
          yield
        ensure
          # Release the lock on success and error. Unless a lock_timeout is
          # used, then we need to be more careful before releasing the lock.
          unless lock_until === true
            now = Time.now.to_i
            if lock_until < now && respond_to?(:lock_expired_before_release)
              # Eeek! Lock expired before perform finished. Trigger callback.
              lock_expired_before_release(*args)
              return # dont relase lock.
            end
          end
          release_lock!(*args)
        end
      end

    end

  end
end
