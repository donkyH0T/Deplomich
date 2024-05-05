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
		allow(YIParser::ProfileAgent).to receive(:logger).and_return(logger)
	end
end

describe YIParser::ProfileAgent do
	include_context 'init_stub_modules'

	TEST_DATA_DIR = File.join(__dir__, '..', 'test_data',  'profile_data')

	describe "#parse_channel" do
		it 'check title' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_username_and_nickname.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, 'https://www.youtube.com/channel/UCE6e9tjKl3l3nGlAcxH7GQg'
			expect(result[:data][:channel_info][:title]).to eq '[AmiAmi]아미아미'
		end
		it 'check username' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_username_and_nickname.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, 'https://www.youtube.com/channel/UCE6e9tjKl3l3nGlAcxH7GQg'

			expect(result[:data][:channel_info][:username]).to eq 'AmiAmi-uo5do'
		end

		it 'check not empty user_id' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_empty_user_id.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, '/channel/xxx'

			expect(result[:data][:channel_info][:user_id]).to eq 'UCtGuzHaUsKDHoNzWQy5Ablw'
		end

		it 'check profile with doesnt exist alert' do
			file_content = File.read(TEST_DATA_DIR + '/not_exist_profile.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, '/channel/xxx'

			expect(result[:error]).to eq 'Channel does not exist'
		end

		it 'check profile with no followers count' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_no_followers.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, '/channel/xxx'

			expect(result[:error]).to eq 'Followers count not found'
		end

		it 'check profile type 2 with no followers count' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_no_followers_type_2.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, '/channel/xxx'

			expect(result[:error]).to eq 'Followers count not found 2'
		end

		it 'check videos count with K' do
			file_content = File.read(TEST_DATA_DIR + '/videos_count_k.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, '/channel/xxx'

			expect(result[:data][:channel_info][:posts]).to eq 14000
		end

		it 'check videos count with K' do
			file_content = File.read(TEST_DATA_DIR + '/videos_count.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_channel init_data, '/channel/xxx'

			expect(result[:data][:channel_info][:posts]).to eq 45
		end

	end

	describe "#parse_profile_videos" do
		it 'check videos with hidded duration time' do
			file_content = File.read(TEST_DATA_DIR + '/profile_videos_with_hidden_duration_time.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_profile_videos init_data

			expect(result[:video_ids]).to include('KV-Ta4YABdo')
		end

		it 'check avg post interval' do
			file_content = File.read(TEST_DATA_DIR + '/profile_videos_with_hidden_duration_time.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_profile_videos init_data

			expect(result[:avg_post_interval]).to eq 0.003
		end

		it 'check videos with no upload dates' do
			file_content = File.read(TEST_DATA_DIR + '/profile_videos_with_no_upload_date.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_profile_videos init_data

			expect(result[:avg_post_interval]).to eq -1
		end

		it 'check videos with no richItemRenderer element' do
			file_content = File.read(TEST_DATA_DIR + '/profile_video_with_no_richItemRenderer.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_profile_videos init_data

			expect(result[:video_ids].count).to eq 2
		end
	end

	describe "#parse_about" do

		it 'check profile with business email' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_verified.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:is_business_email_exist]).to be true
		end

		it 'check profile with no business email' do
			file_content = File.read(TEST_DATA_DIR + '/profile_without_country_and_email.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:is_business_email_exist]).to be false
    end



    it 'check profile_with_country' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_country.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:country]).to eq 'United States'
    end

    it 'check profile_without_country' do
			file_content = File.read(TEST_DATA_DIR + '/profile_without_country_and_email.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:country]).to eq ''
    end


		it 'check profile_without_verified' do
			file_content = File.read(TEST_DATA_DIR + '/profile_without_country_and_email.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:verified]).to be false
    end

		it 'check profile_with_verified' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_verified.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:verified]).to be true
    end

		it 'check profile_with_views' do
			file_content = File.read(TEST_DATA_DIR + '/profile_with_verified.json')
			init_data = JSON.parse(file_content)

			result = YIParser::ProfileAgent.parse_about init_data

			expect(result[:views]).to be 1703247239
		end


	end

	describe "#is_profile_exist" do
		it 'check profile with old updatedat' do
			result = YIParser::ProfileAgent.is_profile_exist('UCB6D1Hbtx8Wwf8a8c3xg4CA')

			expect(result).to be false
		end

		it 'check profile with new updatedat' do
			result = YIParser::ProfileAgent.is_profile_exist('UC43YFSlj1XjfLI75O97kXQg')

			expect(result).to be true
		end
	end

end