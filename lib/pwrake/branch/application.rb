$stderr = $stdout

module Rake
  class << self
    def application
      @application ||= Pwrake::Application.new
    end
  end
end


module Pwrake

  # The TaskManager module is a mixin for managing tasks.
  class Application < ::Rake::Application

    def run
      standard_exception_handling do
        init("pwrake_branch")
        load_rakefile
        begin
          @branch = Branch.new
          @branch.run
        ensure
          @branch.finish if @branch
          Util.dputs "branch/application:end"
        end
      end
    end

    def standard_rake_options
      opts = super
      opts.each_with_index do |a,i|
        if a[0] == '--version'
          a[3] = lambda { |value|
            puts "rake, version #{RAKEVERSION}"
            puts "pwrake, version #{Pwrake::PWRAKEVERSION}"
            exit
          }
        end
      end
      opts
    end

  end
end