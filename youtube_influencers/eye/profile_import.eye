WORKERS = 1

Eye.application 'yi_parser.profile_import' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|
			process "worker_#{n}" do
				stdall File.join('logs',"profile_import_#{n}.log")
				pid_file File.join('tmp', "profile_import_#{n}.pid")

				start_command "bin/run import_agent --log_level=DEBUG --log_filename=profile_import_log_#{n}.log"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
