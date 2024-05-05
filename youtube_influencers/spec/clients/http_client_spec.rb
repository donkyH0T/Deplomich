require 'o14/o14'
require 'y_i_parser'

shared_context 'init_stub_modules' do 
    before do
		create_logger_mock
    end
    
    def create_logger_mock
	    logger = double()
		allow(logger).to receive(:debug).and_return(nil)
		allow(logger).to receive(:info).and_return(nil)
		allow(logger).to receive(:warn).and_return(nil)
		allow(logger).to receive(:error).and_return(nil)
		allow(YIParser::HttpClient).to receive(:logger).and_return(logger)
	end
end

describe YIParser::HttpClient do
	include_context 'init_stub_modules'
	
	describe "#get_search_results" do
		it 'check responses of 3 consecutive requests' do
			response = YIParser::HttpClient.get_search_results 'fyp', nil
			users1 = response[:users]
			
			expect(users1.uniq.count).to be > 0
			
			params = {
				key: response[:properties][:key],
				continuation: response[:properties][:continuation]
			}
			response = YIParser::HttpClient.get_search_results nil, params
			users2 = response[:users]
			
			expect((users1 + users2).uniq.count).to be > users1.uniq.count			
			
			params = {
				key: response[:properties][:key],
				continuation: response[:properties][:continuation]
			}
			response = YIParser::HttpClient.get_search_results nil, params
			users3 = response[:users]
			
			expect((users1 + users2 + users3).uniq.count).to be > (users1 + users2).uniq.count
		end
	end
	
	describe "#get_accounts" do
		it 'test' do
			response = YIParser::HttpClient.get_accounts 'fyp', nil
			p response
			
			params = {
				key: response[:properties][:key],
				continuation: response[:properties][:continuation]
			}
			response = YIParser::HttpClient.get_accounts nil, params
			p response
		end
	end
	
	describe "#get_search_result_accounts" do
		it 'check channels search count' do
			response = YIParser::HttpClient.get_search_result_accounts 'channels',  'fyp', nil
			
			expect(response[:users].uniq.count).to be > 0
		end

		it 'check videos search count' do
			response = YIParser::HttpClient.get_search_result_accounts 'videos',  'fyp', nil
			
			expect(response[:users].uniq.count).to be > 0
		end

		it 'check location search count' do
			response = YIParser::HttpClient.get_search_result_accounts 'location',  'moscow', nil
			
			expect(response[:users].uniq.count).to be > 0
		end
	end
	
end