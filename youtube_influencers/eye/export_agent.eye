WORKERS = 10

Eye.application 'yi_parser.export_agent' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|		
			process "worker_#{n}" do
				stdall File.join('logs',"export_agent_#{n}.log")
				pid_file File.join('tmp', "export_agent_#{n}.pid")

				start_command "bin/run export_agent --log_level=INFO --log_filename=export_agent_log_#{n}.log"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
