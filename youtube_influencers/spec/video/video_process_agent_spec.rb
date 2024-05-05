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
		allow(YIParser::VideoProcessAgent).to receive(:logger).and_return(logger)
	end
end

describe YIParser::VideoProcessAgent do
	include_context 'init_stub_modules'
	
	TEST_DATA_DIR = File.join(__dir__, '..', 'test_data',  'video_data')
	
	describe "#parse_video_content" do
		it 'check likes, comments and views count' do
			file_content = File.read(TEST_DATA_DIR + '/video1.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:data][:result][:view]).to eq 80
			expect(result[:data][:result][:comment]).to eq 2
			expect(result[:data][:result][:like]).to eq 5
			expect(result[:data][:export_data][:description]).to eq "Click the links below for the most updated mattress discounts!\n\nDreamCloud Premier - https://www.sleepfoundation.org/go/dr...\n\nBrooklyn Bedding Signature Hybrid - https://www.sleepfoundation.org/go/br...\n\nLayla Hybrid - https://www.sleepfoundation.org/go/la...\n\nBear Hybrid - https://www.sleepfoundation.org/go/be...\n\nSaatva Classic - https://www.sleepfoundation.org/go/sa...\n\nHybrid mattresses combine the best of both foam and innerspring mattresses to give you a bed that provides a balance of pressure relief, responsiveness, edge support, and temperature regulation.\nLet’s take a look at some of our favorite hybrid mattresses.\n\n0:00 Introduction\n0:38 DreamCloud Premier\n1:25 Brooklyn Bedding Signature Hybrid\n2:22 Layla Hybrid\n3:14 Bear Hybrid\n4:13 Saatva Classic \n\nFor more information, check out Sleep Foundation's page on the best hybrid mattresses: https://www.sleepfoundation.org/best-...\n\n*Please note: When readers choose to buy our independently chosen editorial picks, we may earn affiliate commissions that support our work.\n\n#bestmattress \n#sleeptips \n#sleep"
		end
		
		it 'check when no comments' do
			file_content = File.read(TEST_DATA_DIR + '/video_0_comments.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:data][:result][:comment]).to eq 0
			expect(result[:data][:export_data][:description]).to eq "I am in conversation with  Dr Marlain is an award Winning Arabic Speaking Consultant Obstetrician and Gynecologist at King’s, with extensive experience in Laparoscopic/Hysteroscopic surgeries. \n\nIn this video, we discuss urinary incontinence. Many women suffer through this there isn't much conversation around it. The stigma around incontinence is vast and wide. The involuntary passing of urine while coughing, sneezing or laughing even happens due to incontinence but because there is not much awareness, women don't even address it to the Doctor out of embarrassment. \n\nIncontinence happens when the pelvic floor muscles are loose and stretched due to giving birth to a child. \nThere are different ways to treat this and Doctor Marlain takes us through some of them and also sheds light upon many other things around Incontinence. \n\n\nIf you want to know more, please drop your questions in the comments below\n\nYou can check Dr Marlain's channel here: \n   / @drmarlainmubarak...  \n\n\nClick here to watch videos by Dr Marlain on the King's College Hospital Dubai, UAE channel:\n   • Dr Marlain Mubara...  \n\n\n\n\nFor more information or to book an appointment with Dr Marlain, call/WhatsApp:\n✆ Dubai Hills Hospital – +971 04 247 7777\n✆ Jumeirah clinic - +971 4 378 9555\n\n\nFollow me on Instagram: https://www.instagram.com/carolinelab...\nVisit Caroline's Website: https://carolinelabouchere.com/"
		end
		
		it 'check when comments are hidden' do
			file_content = File.read(TEST_DATA_DIR + '/video_with_hidden_comments.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:data][:result][:comment]).to eq 0
			expect(result[:data][:export_data][:description]).to eq "To learn more, please visit: https://www.madison-reed.com/haircolo..."
		end
		
		it 'check when comments in some block' do
			file_content = File.read(TEST_DATA_DIR + '/video_comments1.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:data][:result][:comment]).to eq 172
		end
		
		it 'check video with hidden views' do
			file_content = File.read(TEST_DATA_DIR + '/video_with_hidden_views.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:data][:result][:view]).to eq 0
		end
		
		it 'check video with disbled content' do
			file_content = File.read(TEST_DATA_DIR + '/video_with_disabled_content.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be false
			expect(result[:error]).to eq 'video with disabled features'
		end
		
		it 'check video with disbled content' do
			file_content = File.read(TEST_DATA_DIR + '/video_with_not_available_label.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be false
			expect(result[:error]).to eq 'Not available'
		end
		
		it 'check paid video' do
			file_content = File.read(TEST_DATA_DIR + '/paid_video.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be false
			expect(result[:error]).to eq 'Paid video'
		end
		
		it 'check members only video' do
			file_content = File.read(TEST_DATA_DIR + '/members_only_video.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be false
			expect(result[:error]).to eq 'Members only'
		end
		
		it 'check season only video' do
			file_content = File.read(TEST_DATA_DIR + '/season_only_video.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be false
			expect(result[:error]).to eq 'Season only'
		end
		
		it 'check unavailable video' do
			file_content = File.read(TEST_DATA_DIR + '/unavailable_video.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be false
			expect(result[:error]).to eq 'This video is unavailable'
		end
		
		it 'check post description' do
			file_content = File.read(TEST_DATA_DIR + '/video_with_desription.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be true
			expect(result[:data][:export_data][:description]).to eq "Provided to YouTube by Average Joes Entertainment\n\nShe's Crazy · Moonshine Bandits\n\nBlacked Out\n\n℗ 2015 Backroad Records/Average Joes Entertainment\n\nReleased on: 2015-07-17\n\nComposer: Brett Brooks\nComposer: Derek Stephens\nComposer: Dusty Dahlgren\nComposer: Mark Davis\nMusic  Publisher: Minckler Music\nMusic  Publisher: Moonshine Bandit Publishing\nComposer: Ty Weathers\n\nAuto-generated by YouTube."
		end
		
		it 'check video with no description' do
			file_content = File.read(TEST_DATA_DIR + '/video_with_no_description.json')
			video_data = JSON.parse(file_content)
			
			result = YIParser::VideoProcessAgent.parse_video_content video_data, 'http://', 'xxx'

			expect(result[:success]).to be true
			expect(result[:data][:export_data][:description]).to eq ""
		end
		
		
		
		
	end
end