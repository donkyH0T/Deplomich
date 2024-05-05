require 'sequel'

module O14
	module DB
		def self.get_db
			@db ||= begin
				config = O14::Config.get_config

				db_connection_params = {
					 adapter: 'postgres',
					 host: config.db['host'],
					 port: config.db['port'],
					 database: config.db['database'],
					 user: config.db['user'],
					 password: config.db['password'],
					 max_connections: 10,
					 timeout: 30,
			   		 encoding: 'utf8'
				}

				db = Sequel.connect(db_connection_params)

			 db.extension(:connection_validator)

			 at_exit { disconnect }

			 db
			end
		end
		
		def self.create_connection connection_params
	      config = O14::Config.get_config
	
	      db_connection_params = {
	        adapter: 'postgres',
	        host: connection_params['host'],
	        port: connection_params['port'],
	        database: connection_params['database'],
	        user: connection_params['user'],
	        password: connection_params['password'],
	        max_connections: 10,
	        encoding: 'utf8'
	      }
	
	      db = Sequel.connect(db_connection_params)
	
	       db.extension(:connection_validator)
	
	       at_exit { db.disconnect }
	       db
	    end

		def self.disconnect
			@db.disconnect rescue nil
		end
	end
end
