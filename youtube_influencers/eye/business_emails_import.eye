WORKERS = 1

Eye.application 'yi_parser.business_emails_import' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|		
			process "worker_#{n}" do
				stdall File.join('logs',"business_emails_import_#{n}.log")
				pid_file File.join('tmp', "business_emails_import_#{n}.pid")

				start_command "bin/run business_emails_import --log_level=INFO --log_filename=business_emails_import_log_#{n}.log"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
