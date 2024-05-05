WORKERS = 1

Eye.application 'yi_parser.business_emails_agent' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|		
			process "worker_#{n}" do
				stdall File.join('logs',"business_emails_agent_#{n}.log")
				pid_file File.join('tmp', "business_emails_agent_#{n}.pid")

				start_command "bin/run business_emails_agent --log_level=DEBUG --log_filename=business_emails_agent_#{n}.log"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
