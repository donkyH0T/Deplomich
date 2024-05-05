WORKERS = 3

Eye.application 'yi_parser.face_agent' do

	working_dir File.expand_path("../../", __FILE__)
	env 'BUNDLE_GEMFILE' => self.working_dir + "/Gemfile"

	group :workers do
		chain grace: 1.seconds
		WORKERS.times do |n|
			process "worker_#{n}" do
				stdall File.join('logs',"face_agent_#{n}.log")
				pid_file File.join('tmp', "face_agent_#{n}.pid")

				start_command "python lib/face/face_agent.py -c config/config.yml -l critical"
				stop_command 'kill -TERM {PID}'

				daemonize true
				stop_on_delete true

				check :memory, every: 20.seconds, below: 200.megabytes, times: 3
			end
		end
	end
end
