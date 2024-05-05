WORKERS = 4

Eye.application 'yi_parser.s3_agent' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|
			process "worker_#{n}" do
				stdall File.join('logs',"s3_agent_#{n}.log")
				pid_file File.join('tmp', "s3_agent_#{n}.pid")

				start_command "bin/run s3_agent --log_level=DEBUG --log_filename=s3_agent_log_#{n}.log"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
