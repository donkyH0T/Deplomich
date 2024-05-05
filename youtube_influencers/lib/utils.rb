module YIParser
  class Utils
	EMAIL_DOMAINS = {
		"gmail" => 'com',
		 "yahoo" => 'com',
		 "hotmail"=> 'com',
		 "aol"=> 'com',
		 "msn"=> 'com',
		 "wanadoo" => 'fr',
		 "orange" => 'fr',
		 "comcast" => 'net',
		 "live"=> 'com',
		 "rediffmail"=> 'com',
		 "free" => 'fr',
		 "gmx" => 'de',
		 "web" => 'de',
		 "yandex" => 'ru',
		 "ya" => 'ru',
		 "ymail" => 'com',
		 "libero" => 'it',
		 "outlook" => 'com',
		 "uol" => 'com.br',
		 "bol" => 'com.br',
		 "mail" => 'ru',
		 "cox" => 'net',
		 "sbcglobal" => 'net',
		 "sfr" => 'fr',
		 "verizon" => 'net',
		 "googlemail" => 'com',
		 "ig" => 'com.br',
		 "bigpond" => 'com',
		 "terra" => 'com.br',
		 "neuf" => 'fr',
		 "alice" => 'it',
		 "rocketmail" => 'com',
		 "att" => 'net',
		 "laposte" => 'net',
		 "facebook" => 'com',
		 "bellsouth" => 'net',
		 "charter" => 'net',
		 "rambler" => 'ru',
		 "tiscali" => 'it',
		 "shaw" => 'ca',
		 "sky" => 'com',
		 "earthlink" => 'net',
		 "optonline" => 'net',
		 "freenet" => 'de',
		 "t-online" => 'de',
		 "aliceadsl" => 'fr',
		 "virgilio" => 'it',
		 "home" => 'nl',
		 "qq" => 'com',
		 "telenet" => 'be',
		 "me" => 'com',
		 "voila" => 'fr',
		 "planet" => 'nl',
		 "tin" => 'it',
		 "ntlworld" => 'com',
		 "arcor" => 'de',
		 "frontiernet" => 'net',
		 "hetnet" => 'nl',
		 "zonnet" => 'nl',
		 "club-internet" => 'fr',
		 "juno" => 'com',
		 "optusnet" => 'com.au',
		 "blueyonder" => 'co.uk',
		 "bluewin" => 'ch',
		 "skynet" => 'be',
		 "sympatico" => 'ca',
		 "windstream" => 'net',
		 "mac" => 'com',
		 "centurytel" => 'net',
		 "chello" => 'nl',
		 "aim" => 'com'
	}
	
	def self.detect_language text
		detection = CLD.detect_language(text)
		detection[:code]
		if detection[:code] == 'un'
			return ''
		end
		if detection[:code].nil?
			return ''
		end
		detection[:code]
	end

    def self.time_ago_to_time ago_time, now_date
      if ago_time.match /second/
        video_date = now_date - ago_time.to_i
      end
      if ago_time.match /minute/
        video_date = now_date - (ago_time.to_i*60)
      end
      if ago_time.match /hour/
        video_date = now_date - (ago_time.to_i*60*60)
      end
      if ago_time.match /day/
        video_date = now_date - (ago_time.to_i*60*60*24)
      end
      if ago_time.match /week/
        video_date = now_date - (ago_time.to_i*60*60*24*7)
      end
      if ago_time.match /month/
        video_date = now_date - (ago_time.to_i*60*60*24*30)
      end
      if ago_time.match /year/
        video_date = now_date - (ago_time.to_i*60*60*24*365)
      end
      video_date
    end
	
	def self.get_email text
      matches = text.match(/\b[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\b/i)
      if !matches.nil?
	    if matches[0].match('/')
		    return nil
		end
        return matches[0]
      end
      return nil
    end
	
	def self.get_all_emails text
	  text = text.to_s
      emails = text.scan(/\b[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\b/i)
      emails = emails.reject do |_e|
	      matched = _e.match(/^(.+?)@/)
	      matched[1].length > 64
	  end
	  emails
    end
    
    def self.complete_email_domain email
	    if email
		    email = email.strip
		    if email.match(/@.+\./).nil?
			    EMAIL_DOMAINS.keys.each do |domain|
				    regex_str = "@#{domain}$"
				    if email.match(Regexp.new regex_str)
					    email = email.gsub(/@.+/, "@#{domain}.#{EMAIL_DOMAINS[domain]}")
					end
				end
			end
		end
		email
	end
    
    def self.is_email_syntax_correct email
	    matched = email.match(/([a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+)@([a-zA-Z0-9_\-\.]+)\.([a-zA-Z]{2,5})/i)
	    if matched.nil?
		    return false
		end
		return true
	end
    
    def self.reject_null_unicode_symbals text
	    text = text.gsub("\u0000", '') if !text.nil?
	    text
	end
	
	def self.extract_linktree_nickname text
		matched = text.match(/linktr\.ee\/([a-zA-Z0-9_\-\.]+)\b/i)
		if matched.nil?
		  matched = text.match(/linktree\.com\/([a-zA-Z0-9_\-\.]+)\b/i)
		end
		if matched
			return matched[1]
		end
		nil
	end
	
	def self.process_hashtags_from_string hashtags_str
		hashtags = []
		return hashtags if hashtags_str.nil?
	  hashtags_str.split(/\p{Z}|,\p{Z}|#|,/).each do |h|
	    h = h.gsub(/[\x00-\x09\x0B-\x0C\x0E-\x1F]/, '').gsub(/\[|\]|#|,|"|'/,'').gsub(/^[\p{P}\p{S}\p{Z}]+|[\p{P}\p{S}\p{Z}]+$/,'').downcase
	    next if h.length < 2
	    hashtags.push(h)
	  end
	  hashtags.uniq
	end
  end
end