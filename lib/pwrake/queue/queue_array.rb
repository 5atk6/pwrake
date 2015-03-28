module Pwrake

#  class TaskConditionVariable < ConditionVariable
#    def signal(hint=nil)
#      super()
#    end
#  end


  class PriorityQueueArray < Array
    def initialize(n)
      super()
    end

    def shift
      pop
    end

    def push(t)
      priority = t.priority
      if empty? || last.priority <= priority
        super(t)
      elsif first.priority > priority
        unshift(t)
      else
        lower = 0
        upper = size-1
        while lower+1 < upper
          mid = ((lower + upper) / 2).to_i
          if self[mid].priority <= priority
            lower = mid
          else
            upper = mid
          end
        end
        insert(upper,t)
      end
    end

    def index(t)
      if size < 40
        return super(t)
      end
      priority = t.priority
      if last.priority < priority || first.priority > priority
        nil
      else
        lower = 0
        upper = size-1
        while lower+1 < upper
          mid = ((lower + upper) / 2).to_i
          if self[mid].priority < priority
            lower = mid
          else
            upper = mid
          end
        end
        mid = upper
        if self[mid].priority == priority
          Log.debug "--- TQA#index=#{mid}, priority=#{priority}"
          mid
        end
      end
    end
  end # PriorityQueueArray


  class LifoQueueArray < Array
    def initialize(n)
      super()
    end

    def shift
      pop
    end
  end


  class FifoQueueArray < Array
    def initialize(n)
      super()
    end
  end

  class RankCounter

    def initialize
      @ntask = []
      @nproc = 0
      @mutex = Mutex.new
    end

    def add_nproc(n)
      @mutex.synchronize do
        @nproc += n
      end
    end

    def incr(r)
      @mutex.synchronize do
        @ntask[r] = (@ntask[r]||0) + 1
      end
    end

    def get_task
      @mutex.synchronize do
        (@ntask.size-1).downto(0) do |r|
          c = @ntask[r]
          if c && c>0
            t = yield(c, @nproc, r)
            #t = (c<=@n) ? pop_last_rank(r) : pop
            if t
              @ntask[t.rank] -= 1
              Log.debug "--- RankCount rank=#{r} nproc=#{@nproc} count=#{c} t.rank=#{t.rank} t.name=#{t.name}"
            end
            return t
          end
        end
      end
      nil
    end
  end

  # HRF mixin module
  module HrfQueue

    def hrf_init(n=nil)
      @nproc = n || 0
      @count = []
    end

    def hrf_push(t)
      if t
        r = t.rank
        @count[r] = (@count[r]||0) + 1
      end
    end

    def hrf_get
      (@count.size-1).downto(0) do |r|
        c = @count[r]
        if c && c>0
          t = (c <= @nproc) ? pop_last_rank(r) : pop_super
          if t
            @count[t.rank] -= 1
          end
          return t
        end
      end
      raise "no element"
      nil
    end

    def pop_last_rank(r)
      (size-1).downto(0) do |i|
        t = at(i)
        if t && t.rank == r
          delete_at(i)
          return t
        end
      end
      nil
    end
  end

  # LIFO + HRF
  class LifoHrfQueueArray < Array
    include HrfQueue

    def initialize(n)
      super()
      hrf_init(n)
    end

    def push(t)
      super(t)
      hrf_push(t)
    end

    def shift
      return nil if empty?
      hrf_get
    end

    def pop_super
      pop
    end
  end

  # Priority + HRF
  class PriorityHrfQueueArray < PriorityQueueArray
    include HrfQueue

    def initialize(n)
      super(n)
      hrf_init(n)
    end

    def push(t)
      super(t)
      hrf_push(t)
    end

    def shift
      return nil if empty?
      hrf_get
    end

    def pop_super
      pop
    end
  end


  # Rank-Even Last In First Out
  class RankQueueArray

    def initialize(n)
      @q = []
      @size = 0
      @n = (n>0) ? n : 1
    end

    def push(t)
      r = t ? t.rank : 0
      a = @q[r]
      if a.nil?
        @q[r] = a = []
      end
      @size += 1
      a.push(t)
    end

    def size
      @size
    end

    def empty?
      @size == 0
    end

    def shift
      if empty?
        return nil
      end
      (@q.size-1).downto(0) do |i|
        a = @q[i]
        next if a.nil? || a.empty?
        @size -= 1
        if a.size <= @n
          return pop_last_max(a)
        else
          return shift_weighted
        end
      end
      raise "ELIFO: @q=#{@q.inspect}"
    end

    def shift_weighted
      weight, weight_avg = RANK_STAT.rank_weight
      wsum = 0.0
      q = []
      @q.each_with_index do |a,i|
        next if a.nil? || a.empty?
        w = weight[i]
        w = weight_avg if w.nil?
        # w *= a.size
        wsum += w
        q << [a,wsum]
      end
      #
      x = rand() * wsum
      Log.debug "--- shift_weighted x=#{x} wsum=#{wsum} weight=#{weight.inspect}"
      q.each do |a,w|
        if w > x
          return a.pop
        end
      end
      raise "ELIFO: wsum=#{wsum} x=#{x}"
    end

    def pop_last_max(a)
      if a.size < 2
        return a.pop
      end
      y_max = nil
      i_max = nil
      n = [@n, a.size].min
      (-n..-1).each do |i|
        y = a[i].input_file_size
        if y_max.nil? || y > y_max
          y_max = y
          i_max = i
        end
      end
      a.delete_at(i_max)
    end

    def first
      return nil if empty?
      @q.size.times do |i|
        a = @q[i]
        unless a.nil? || a.empty?
          return a.first
        end
      end
    end

    def last
      return nil if empty?
      @q.size.times do |i|
        a = @q[-i-1]
        unless a.nil? || a.empty?
          return a.last
        end
      end
    end

    def delete(t)
      n = 0
      @q.each do |a|
        if a
          a.delete(t)
          n += a.size
        end
      end
      @size = n
    end

    def clear
      @q.clear
      @size = 0
    end
  end

end
