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
		allow(YIParser::HashtagsAgent).to receive(:logger).and_return(logger)
	end
end

describe YIParser::HashtagsAgent do
	include_context 'init_stub_modules'
	
	describe "#get_profiles_from_page" do
		it 'check first search page' do
			result = YIParser::HashtagsAgent.get_profiles_from_page nil, 'soccer', nil

			expect(result[:success]).to be true
			
			expect(result[:profile_ids].count).to be > 0
			
			expect(result[:properties][:key]).to_not be_nil
			
			expect(result[:properties][:continuation]).to_not be_nil
		end
	end
end