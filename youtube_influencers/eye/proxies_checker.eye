WORKERS = 1

Eye.application 'yi_parser.proxy_checker' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|
			process "worker_#{n}" do
				stdall File.join('logs',"proxy_checker_#{n}.log")
				pid_file File.join('tmp', "proxy_checker_#{n}.pid")

				start_command "bin/run proxy_checker --log_level=DEBUG --log_filename=proxy_checker_log_#{n}.log"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
