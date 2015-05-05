module Pwrake

  class WorkerCommunicator < Communicator

    @@worker_path = (Pathname.new(File.dirname(__FILE__)).expand_path+"../../../bin").realpath
    RE_ID='\d+'
    attr_reader :id, :host, :ncore
    attr_reader :channel

    @@worker_communicators = []

    def initialize(id,host,ncore,dispatcher,opt={})
      @id = id
      @ncore = @n_total_core = ncore
      @channel = {}
      #
      @dispatcher = dispatcher
      @option = opt
      @heartbeat_timeout = @option[:heartbeat_timeout]
      super(host)
      @close_command = "exit_worker"
      @@worker_communicators << self
    end

    def setup_connection(w0,w1,r2)
      cmd = system_cmd
      Log.debug cmd
      @pid = spawn(cmd,:pgroup=>true,:out=>w0,:err=>w1,:in=>r2)
      w0.close
      w1.close
      r2.close
    end

    def pass_env
      @heartbeat = Time.now
      if @path
        @iow.puts "export:PATH='#{path}'"
      end
      if env = @option[:pass_env]
        env.each do |k,v|
          @iow.puts "export:#{k}='#{v}'"
        end
      end
    end

    def system_cmd
      ssh_opt = @option[:ssh_opt]
      cmd = "ruby #{@@worker_path+@option[:worker_cmd]}"
      bd = @option[:base_dir]
      wd = @option[:work_dir]
      ld = @option[:log_dir]
      cmd_line = "#{cmd} \"#{bd}\" \"#{wd}\" \"#{ld}\" \"#{@ncore}\""
      if ['localhost','localhost.localdomain','127.0.0.1'].include? @host
        "cd;#{cmd_line}"
      else
        "ssh -x -T -q #{ssh_opt} #{@host} '#{cmd_line}'"
      end
    end

    def close
      super
    end

    def set_ncore(ncore)
      @ncore = ncore if @ncore.nil?
    end

    def add_channel(id,channel)
      @channel[id] = channel
    end

    def delete_channel(id)
      @channel.delete(id)
    end

    def channel_empty?
      @channel.empty?
    end

    def on_read(io)   # return to Shell#io_read_loop
      s = io.gets
      # $chk.print ">#{s}" if $dbg
      # $stderr.puts ">"+s
      case s
      when /^(#{RE_ID}):(.*)$/
        id,item = $1,$2
        @channel[id].enq([:out,item])
        #
      when /^(#{RE_ID})e:(.*)$/
        id,item = $1,$2
        @channel[id].enq([:err,item])
        #
      when /^start:(#{RE_ID}):(\d*)$/
        id,pid = $1,$2
        @channel[id].enq([:start,pid])
        #
      when /^end:(#{RE_ID})(?::(\d*):(.*))?$/
        id,pid,status = $1,$2,$3
        @channel[id].enq([:end,pid,status])
        #
      when /^err:(#{RE_ID}):(.*)$/
        id,pid,stat_val,stat_cond = $1,$2,$3,$4
        @channel[id].enq([:end,pid,stat_val,stat_cond])
        #
      when /^open:(#{RE_ID})$/
        id = $1
        @channel[id].enq([:open])
        #
      when /^heartbeat$/
        @dispatcher.heartbeat(io)
        #
      when /^ncore:(\d+)$/
        @n_total_core = $1
        #
      when /^worker_end$/
        Log.debug "#{self.class}#on_read: #{s.chomp} id=#{@id} host=#{@host}"
        @@worker_communicators.delete(self)
        return @@worker_communicators.empty?
        #
      when /^exc:(#{RE_ID}):(.*)$/
        id,msg = $1,$2
        Log.error "worker(#{host},id=#{id}) err>#{msg}"
        return true
        #
      when /^log:(.*)$/
        Log.info "worker(#{host})>#{$1}"
        #
      else
        Log.warn "worker(#{host}) out>#{s.chomp}"
      end
      return false
    end

  end
end
