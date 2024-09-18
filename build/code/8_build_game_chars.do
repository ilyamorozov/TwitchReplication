clear
program drop _all


program main

	organize_game_stats
	organize_game_tags
	organize_ratings
	organize_metacritic
	organize_regular_price
	organize_sponsorship_vars
	game_chars_augment
	organize_game_chars
	organize_game_date_chars

end


program organize_game_stats

	* Load stream-level data *
	use "../output/stream_chars.dta", clear
	drop _merge
	merge m:1 streamer using "../temp/core_streamer.dta", keep(1 3)
	replace is_core_streamer = 0 if is_core_streamer == .
	keep if is_core_streamer == 1
	
	* Make sampling adjustments *
	gen num_streams             =                   1 / scaling_factor
	replace is_big_streamer_p95 = is_big_streamer_p95 / scaling_factor
	replace total_viewers       =       total_viewers / scaling_factor
	replace length_min          =          length_min / scaling_factor
	
	* Compute helpful metrics *
	gen length_hrs = length_min / 60
	gen time_viewed_hrs = total_viewers * 10 / 60
	
	* Compute and save sample length (in days) *
	egen earliest_date = min(start_date)
	egen lastest_date  = max(start_date)
	gen sample_length_days = lastest_date - earliest_date + 1
	
	* Compute game-level stats *
	collapse (sum) hours_streamed=length_hrs num_streams num_top=is_big_streamer_p95 time_viewed_hrs (first) sample_length_days game_title, by(appid)
	gen hours_streamed_per_day   = hours_streamed  / sample_length_days
	gen num_streams_per_day      = num_streams     / sample_length_days
	gen num_top_per_day          = num_top         / sample_length_days
	gen time_viewed_hrs_per_day  = time_viewed_hrs / sample_length_days
	gen hours_streamed_000s  = hours_streamed  / 1000
	gen time_viewed_hrs_000s = time_viewed_hrs / 1000
	keep  appid num_streams num_top hours_streamed_000s time_viewed_hrs_000s num_streams_per_day num_top_per_day hours_streamed_per_day time_viewed_hrs_per_day
	order appid num_streams num_top hours_streamed_000s time_viewed_hrs_000s num_streams_per_day num_top_per_day hours_streamed_per_day time_viewed_hrs_per_day
	drop if appid == .
	gsort -time_viewed_hrs_per_day
	tostring appid, replace
	
	save "../temp/game_stats.dta", replace

end


program organize_game_tags

	* Load data *
	import delimited "../input/game_data/game_tags.txt", delimiter(comma) clear 

	* Extract appid *
	replace v1 = subinstr(v1, "/agecheck", "",.) 
	split v1, p("/")
	rename v1 tag
	rename v15 appid
	drop v*
	gen flag_appid_obs = (appid ~= "")
	replace appid = appid[_n-1] if appid == ""
	drop if flag_appid_obs == 1
	drop flag_appid_obs

	* Remove special symbols *
	replace tag = subinstr(tag, `"""',  "", .)

	* Build variables *
	define_genres
	define_multiplayer
	define_rich_story
	define_crafting
	define_other_variables
	
	* Extend most tagged genre (most frequent tag) to the first obs *
	bysort appid: gen num = _n
	gsort appid -num
	by appid: replace genre = genre[_n-1] if genre == ""
	gsort appid num
	
	* Collapse to game-level *
	collapse (max) multiplayer-retro (first) genre, by(appid)
	
	* Convert genre into dummy variables *
	encode genre, generate(genre_id)
	dummieslab genre_id
	drop genre_id
	
	* Save data *
	save "../temp/game_genres.dta", replace

end


program organize_ratings

	* Load data *
	import excel "../input/game_data/game_ratings.xlsx", sheet("Sheet1") firstrow clear
	drop if Page_Title == ""

	* Extract appid *
	replace Page_URL = subinstr(Page_URL, "https://store.steampowered.com/app/", "",.) 
	replace Page_URL = subinstr(Page_URL, "https://store.steampowered.com/agecheck/app/", "",.) 
	replace Page_URL = substr(Page_URL, 1, strpos(Page_URL, "/")-1) if strpos(Page_URL, "/") > 0
	rename Page_URL appid
	destring appid, replace force
	duplicates drop appid, force
	
	* Extract game title *
	gen title = regexr(Page_Title, " on Steam", "")
	
	* Extract ratings *
	split Text, p("(" ")")
	rename Text2 all
	rename Text4 positive
	rename Text6 negative
	destring all positive negative, ignore(",") replace
	
	* Create two rating variables *
	gen rating_count = all
	gen rating_sharepos = positive / all
	keep appid title rating_count rating_sharepos
	duplicates drop appid, force
	save "../temp/game_ratings.dta", replace
	
	* Export
	gsort -rating_sharepos
	keep if rating_count >= 500
	export excel using "../temp/ratings_view.xlsx", replace
	
end


program organize_metacritic

	** Organize metacritic variances (negative-mixed-positive rating counts) **
	import excel "../input/data_metacritic/metacritic_variances.xlsx", sheet("Sheet1") firstrow clear
	duplicates drop Page_URL, force
	rename Text MetaTitle
	rename Page_URL MetaLink
	keep MetaTitle MetaLink user_pos user_mix user_neg 
	destring user_pos user_mix user_neg, force replace
	replace user_pos = 0 if user_pos == .
	replace user_mix = 0 if user_mix == .
	replace user_neg = 0 if user_neg == .
	save "../temp/metacritic_variances.dta", replace

	** Organize metacritic ratings -> merge with variances **
	import excel "../input/data_metacritic/metacritic_matched_wave5.xlsx", sheet("Sheet1") firstrow clear
	save "../temp/metacritic_original.dta", replace
	import excel "../input/data_metacritic/metacritic_manual.xlsx", sheet("Sheet1") firstrow clear
	save "../temp/metacritic_manual.dta", replace
	import excel "../input/data_metacritic/metacritic_corrections.xlsx", sheet("Sheet1") firstrow clear
	save "../temp/metacritic_corrections.dta", replace

	* Merge parts *
	use "../temp/metacritic_original.dta", clear
	keep if MetaScore != .
	merge 1:1 appid using "../temp/metacritic_corrections.dta"
	append using "../temp/metacritic_manual.dta"	
	* correct metascores
	replace MetaScore = MetaScore_manual if _merge == 3
	replace MetaScore = MetaScore_manual if Notes != "" & MetaScore_manual != .
	drop _merge
	
	* Compute rating variance *
	merge m:1 MetaLink using "../temp/metacritic_variances.dta", keep(1 3) nogenerate
	gen ex_sq = (user_pos * 9 + user_mix * 6 + user_neg * 2.5) / (user_pos + user_mix + user_neg)
	replace ex_sq = ex_sq * ex_sq
	gen ex2 = (user_pos * 81 + user_mix * 36 + user_neg * 6.25) / (user_pos + user_mix + user_neg)
	gen metastd = sqrt(ex2 - ex_sq)
	replace metastd = . if (user_pos + user_mix + user_neg) < 3 // only define variance if more than three users rated the game
	keep MetaScore metastd appid
	rename MetaScore metascore
	save "../temp/metacritic_score.dta", replace
	
end


program organize_regular_price

	* Merge files *
	import delimited "../input/data_steamdb/price_data_new/240670_data_merged.csv", clear
	save "../temp/price_temp.dta", replace
	import delimited "../input/data_steamdb/price_data_new/5021_data_merged.csv", clear
	append using "../temp/price_temp.dta"
	import delimited "../input/data_steamdb/price_data_new/merged_data_with_empty_rows.csv", clear
	append using "../temp/price_temp.dta"
	duplicates drop
	save "../temp/price_data_timestamp.dta", replace
	collapse (firstnm) price discount, by(appid date time)
	drop if price == .
	save "../temp/daily_price_raw.dta", replace

	* how many price changes per day?
	use "../temp/price_data_timestamp.dta", clear
	sort appid unix_timestamp
	collapse (max) max_price = price (min) min_price = price, by(appid date)
	gen price_diff = max_price - min_price
	su price_diff, detail
	gen is_zero = price_diff == 0
	su is_zero
	// among all the price-changing game-date level obs, 97.2% observations have only one price change on that day
	
	* Expand time *
	use "../temp/daily_price_raw.dta", clear
	gen date2 = date(date, "YMD")
	collapse (min) min_date=date2 (max) max_date=date2, by(appid)
	replace max_date = date("2021-09-01", "YMD")
	gen diff = max_date - min_date
	expand diff
	bysort appid: gen date2 = min_date + _n - 1
	format date2 %d
	keep appid date2
	save "../temp/set_game_dates.dta", replace

	* Construct daily prices *
	use "../temp/daily_price_raw.dta", clear
	gen date2 = date(date, "YMD")
	format date2 %d
	merge n:1 appid date2 using "../temp/set_game_dates.dta", keep(2 3)
	bysort appid (date2): replace price = price[_n-1] if price == .
	drop date
	rename date2 date	
	collapse (median) price, by(appid date)
	save "../temp/daily_price.dta", replace
	
	* Construct average price (look at relevant period only) *
	keep if date >= mdy(5,11,2021) // after may 11
	collapse (p95) regular_price = price, by(appid)
	save "../temp/regular_price.dta", replace
	
	* Missing prices *
	import delimited "../input/data_steamdb/price_data_new/missing_prices.csv", clear
	rename id appid
	gen is_missing_price = 1
	save "../temp/mising_prices.dta", replace
	
end


program organize_sponsorship_vars
	
	* Game level sponsor/primary *
	use "../output/stream_chars.dta", clear
	collapse (mean) game_sponsored=is_sponsored game_primary=is_primary, by(appid)
	drop if appid == .
	save "../temp/sponsored_primary.dta", replace
	
	* Game-date level sponsor/primary *
	use "../output/stream_chars.dta", clear
	bysort appid start_date: egen total_viewers_game = sum(total_viewers)
	gen weighted_sponsored = total_viewers / total_viewers_game * is_sponsored	// keep in mind that total viewers is average concurrent viewer * #10-minute time slots, so a proxy of viewer-time
	gen weighted_primary = total_viewers / total_viewers_game * is_primary
	collapse (sum) game_sponsored_daily=weighted_sponsored game_primary_daily=weighted_primary, by(appid start_date)
	rename start_date date
	drop if appid == .
	save "../temp/sponsored_primary_date.dta", replace
	
end


program game_chars_augment

	* Count number of games per publisher *
	import excel using "../input/data_steamdb/game_info/2020_11_15__09_04steamdb_info_.xlsx", sheet("2020_11_15__09_04steamdb_info_") firstrow clear
	keep if AppType == "Game"
	drop if regexm(Title, "Beta|BETA|beta|TEST|test|Test")
	rename Publisher publisher
	rename Developer developer
	replace publisher = developer if publisher == ""
	replace developer = "Unknown" if publisher == ""
	replace publisher = "Unknown" if publisher == ""
	gen obs = 1
	preserve
		collapse (sum) ngames_pub = obs, by(publisher)
		replace ngames_pub = 1 if publisher == "Unknown"
		save "../temp/ngames_pub.dta", replace
	restore
	collapse (sum) ngames_dev = obs, by(developer)
	replace ngames_dev = 1 if developer == "Unknown"
	save "../temp/ngames_dev.dta", replace

	* Augment game characteristics for a few games *
	import delimited using "../input/data_steamdb/game_info/game_info_augment.csv", clear
	save "../temp/additional_games.dta", replace
	import excel using "../input/data_steamdb/game_info/2020_11_15__09_04steamdb_info_.xlsx", sheet("2020_11_15__09_04steamdb_info_") firstrow clear
	rename AppID appid
	merge 1:1 appid using "../temp/additional_games.dta", keep(2 3) nogenerate
	
	gen release_date_2 = date(release_date, "YMD")
	drop release_date
	rename release_date_2 release_date
	format release_date %d
	replace tags = user_tag if user_tag != ""
	gen multiplayer = regexm(tags, "Multiplayer|Co-op|Battle Royale")
	replace multiplayer = 0 if regexm(tags, "Single Player")
	gen difficult = regexm(tags, "Difficult")
	tostring appid, replace
	keep appid steam_title release_date developer publisher multiplayer difficult free_to_play regular_price 
	save "../temp/additional_game_chars.dta", replace
	
	* Load supplementary publisher info data *
	import excel "../input/data_steamdb/game_info/publisher_data_sub_new.xlsx", sheet("Sheet1") firstrow clear
	replace publisher = developer if publisher == ""	// verified that this is true
	clean_publishers	// clean publisher data
	rename publisher publisher_new
	rename game_title steam_title
	save "../temp/additional_publisher_info.dta", replace
	
end


program organize_game_chars
	
	* Load data *
	import excel "../input/game_data/game_info_data.xlsx", sheet("Sheet1") firstrow clear

	* Extract appid *
	replace Page_URL = subinstr(Page_URL, "/agecheck", "",.) 
	split Page_URL, p("/")
	rename Page_URL5 appid

	* Format variables *
	format release_date %d
	format %30s steam_title
	format %20s developer
	format %20s publisher
	
	* Merge additional publisher data *
	merge 1:1 steam_title using "../temp/additional_publisher_info.dta", keep(1 3)
	
	* Add additional games (characteristics are not complete) *
	append using "../temp/additional_game_chars.dta"

	* Keep only relevant variables *
	keep  appid steam_title developer publisher release_date difficult multiplayer publisher_new free_to_play regular_price
	order appid steam_title developer publisher release_date difficult multiplayer publisher_new free_to_play regular_price
	foreach var in difficult multiplayer free_to_play regular_price {
		rename `var' `var'_aug
	}

	* Flag new and very new games based on release dates *
	egen med_release = median(release_date)
	egen q75_release = pctile(release_date), p(75)
	gen is_new       = release_date >= med_release
	gen is_very_new  = release_date >= q75_release
	drop med_release q75_release

	* Flag big and small publishers (within the set of 603 games) *
	replace publisher = publisher_new if publisher == "" 
	replace publisher = "Unknown" if publisher == ""  // only one replacement
	clean_publishers	// clean publisher data
	gen counter = 1
	bysort publisher: egen ngames = sum(counter)
	replace ngames = 1 if publisher == "Unknown"
	drop counter publisher_new
	merge n:1 publisher using "../temp/ngames_pub.dta", keep(1 3) nogenerate
	merge n:1 developer using "../temp/ngames_dev.dta", keep(1 3) nogenerate
	replace ngames_pub = ngames if ngames_pub == .
	replace ngames_dev = ngames if ngames_dev == .

	* small and large publishers
	egen med_ngames = median(ngames)
	gen is_small_publisher = (ngames <= med_ngames)
	gen is_large_publisher = (ngames > med_ngames)
	
	* Merge with previously created genres and game stats *
	merge 1:1 appid using "../temp/game_genres.dta", nogenerate
	merge 1:1 appid using "../temp/game_stats.dta"
	drop if _merge != 3		// leaves 621 games (dropped 3 games where we do not know about characteristics, and 4 games where we track characteristics but are not present in streams)
	drop _merge
	destring appid, replace force
	keep if appid != .
	sort appid
	
	* Build heterogeneity variables *
	gen years_since_release = (mdy(5,11,2021) - release_date) / 365
	gen game_age = ""
	replace game_age = "0-1 years" if inrange(years_since_release,-10,0.99999)  ==1
	replace game_age = "1-3 years" if inrange(years_since_release,1,2.99999)    ==1
	replace game_age = "3-5 years" if inrange(years_since_release,3,4.99999)    ==1
	replace game_age = "5+ years"  if inrange(years_since_release,5,50)         ==1

	gen publisher_size = ""
	replace publisher_size = "1 game"     if inrange(ngames,1,1) == 1
	replace publisher_size = "2-5 games"  if inrange(ngames,2,5) == 1
	replace publisher_size = "6-10 games" if inrange(ngames,6,10) == 1
	replace publisher_size = "11+ games"  if inrange(ngames,11,5000) == 1
	
	* Clearn titles *
	replace steam_title = subinstr(steam_title, "™", "",.)
	replace steam_title = subinstr(steam_title, "®", "",.)
	replace steam_title = subinstr(steam_title, ":", "",.)
	replace steam_title = "FIFA 21" if steam_title == "EA SPORTS FIFA 21"
	replace steam_title = "PUBG" if steam_title == "PLAYERUNKNOWN'S BATTLEGROUNDS"
	
	* Fill in missing chars (Dark Souls Remastered plus the unscraped games) *
	replace difficult = 1 if steam_title == "DARK SOULS REMASTERED"
	replace rich_story = 1 if steam_title == "DARK SOULS REMASTERED"
	replace multiplayer = 0 if steam_title == "DARK SOULS REMASTERED"
	replace difficult = difficult_aug if difficult == .
	replace multiplayer = multiplayer_aug if multiplayer == .
	
	* Merge in game ratings *
	merge 1:1 appid using "../temp/game_ratings.dta", keep(1 3) nogenerate
	
	* Merge in metacritic ratings *
	merge 1:1 appid using "../temp/metacritic_score.dta", keep(1 3) nogenerate 

	* Merge in regular prices *
	merge 1:1 appid using "../temp/regular_price.dta", keep(1 3) nogenerate 
	replace free_to_play = free_to_play_aug if free_to_play == .
	replace regular_price = regular_price_aug if regular_price == .
	replace regular_price = 0 if free_to_play == 1
	
	* Merge in sponsored and primary game frequencies *
	merge 1:1 appid using "../temp/sponsored_primary.dta", keep(1 3) nogenerate
	
	* Manually fix missings in metascore (new games that got ratings after our first wave of scraping) *
	replace metascore = 85 if appid == 13650
	replace metascore = 81 if appid == 8950
	replace metascore = 87 if appid == 12750
	replace metascore = 78 if appid == 212220
	replace metascore = 63 if appid == 224060
	replace metascore = 80 if appid == 238320
	replace metascore = 72 if appid == 1006510
	replace metascore = 71 if appid == 1149620
	replace metascore = 81 if appid == 1466860
	
	* Create an auxiliary metascore variable (for heterogeneity analysis) *
	gen metascore_value = ""
	replace metascore_value = "Rating [0,75)"     if inrange(metascore,0,75)        == 1
	replace metascore_value = "Rating [75,80)"    if inrange(metascore,75.01,80)    == 1
	replace metascore_value = "Rating [80,85)"    if inrange(metascore,80.01,85)    == 1
	replace metascore_value = "Rating [85,100]"   if inrange(metascore,85.01,100.1) == 1
	
	save "../output/game_chars.dta", replace
	
end


program organize_game_date_chars

	* Load data *
	import excel "../input/game_data/game_info_data.xlsx", sheet("Sheet1") firstrow clear

	* Extract appid *
	replace Page_URL = subinstr(Page_URL, "/agecheck", "",.) 
	split Page_URL, p("/")
	rename Page_URL5 appid

	destring appid, replace force
	keep if appid != .
	sort appid
	
	format release_date %d
	keep appid release_date
	
	* Merge with game-date level stream info
	merge 1:n appid using "../temp/sponsored_primary_date.dta", keep(1 3) nogenerate
	
	* Merge with game-date level prices
	merge 1:1 appid date using "../temp/daily_price.dta", keep(1 3) nogenerate
	merge n:1 appid using "../temp/mising_prices.dta", keep(1 3) nogenerate
	
	* Tentative *
	gsort appid date
	bysort appid: replace price = price[_n-1] if price == .
	gsort appid -date
	bysort appid: replace price = price[_n-1] if price == .
	gsort appid date
	replace price = -99 if price == .
	drop is_missing_price
	save "../output/daily_game_chars.dta", replace	// have some holes because no stream on that day
	
/*
	* find the mismatched cases
	gen is_still_missing = price == . & is_missing_price == .
	collapse (max) is_still_missing is_missing_price, by(appid)
	preserve
		keep if is_missing_price == 1
		keep appid
		export excel using "../temp/missing_price_list_1.xlsx", replace
	restore
	preserve		
		keep if is_still_missing == 1
		keep appid
		export excel using "../temp/missing_price_list_2.xlsx", replace
	restore
*/
	
end


program define_genres

	gen genre = ""
	replace genre = "Action & RPG" if tag == "Action"
	replace genre = "Action & RPG" if tag == "Action RPG"
	replace genre = "Action & RPG" if tag == "Party-Based RPG"
	replace genre = "Action & RPG" if tag == "CRPG"
	replace genre = "Action & RPG" if tag == "JRPG"
	replace genre = "Action & RPG" if tag == "RPG"
	replace genre = "Action & RPG" if tag == "Action Roguelike"
	replace genre = "Adventure" if tag == "Adventure"
	replace genre = "Adventure" if tag == "Action-Adventure"
	replace genre = "Adventure" if tag == "Choose Your Own Adventure"
	replace genre = "Simulation" if tag == "Simulation"
	replace genre = "Simulation" if tag == "Walking Simulator"
	replace genre = "Simulation" if tag == "Automobile Sim"
	replace genre = "Simulation" if tag == "Life Sim"
	replace genre = "Simulation" if tag == "Immersive Sim"
	replace genre = "Simulation" if tag == "Farming Sim"
	replace genre = "Simulation" if tag == "Management"
	replace genre = "Simulation" if tag == "Resource Management"
	replace genre = "Simulation" if tag == "Economy"
	replace genre = "Simulation" if tag == "Casual"
	replace genre = "Simulation" if tag == "City Builder"
	replace genre = "Comedy" if tag == "Comedy"
	replace genre = "Comedy" if tag == "Funny"
	replace genre = "Comedy" if tag == "Dark Humor"
	replace genre = "Comedy" if tag == "Dark Comedy"
	replace genre = "Puzzle" if tag == "Puzzle"
	replace genre = "Puzzle" if tag == "Puzzle Platformer"
	replace genre = "Mystery & Detective" if tag == "Mystery"
	replace genre = "Mystery & Detective" if tag == "Detective"
	replace genre = "Mystery & Detective" if tag == "Investigation"
	replace genre = "Horror" if tag == "Horror"
	replace genre = "Horror" if tag == "Psychological Horror"
	replace genre = "Horror" if tag == "Thriller"
	replace genre = "Horror" if tag == "Gore"
	replace genre = "Horror" if tag == "Blood"
	replace genre = "Horror" if tag == "Zombies"
	replace genre = "Horror" if tag == "Post-apocalyptic"
	replace genre = "Survival" if tag == "Survival"
	replace genre = "Survival" if tag == "Survival Horror"
	replace genre = "Survival" if tag == "Tower Defense"
	replace genre = "Survival" if tag == "Open World Survival Craft"
	replace genre = "Shooter" if tag == "Shooter"
	replace genre = "Shooter" if tag == "Third-Person Shooter"
	replace genre = "Shooter" if tag == "FPS"
	replace genre = "Shooter" if tag == "Arena Shooter"
	replace genre = "Fantasy" if tag == "Fantasy"
	replace genre = "Fantasy" if tag == "Dragons"
	replace genre = "Fantasy" if tag == "Demons"
	replace genre = "Fantasy" if tag == "Mythology"
	replace genre = "Animation" if tag == "Anime"
	replace genre = "Animation" if tag == "Cartoony"
	replace genre = "Animation" if tag == "Cartoon"
	replace genre = "Strategy" if tag == "Strategy"
	replace genre = "Strategy" if tag == "RTS"
	replace genre = "Strategy" if tag == "StrategyTrading "
	replace genre = "Strategy" if tag == "Turn-Based Strategy"
	replace genre = "Strategy" if tag == "Grand Strategy"
	replace genre = "Strategy" if tag == "Strategy RPG"
	replace genre = "Strategy" if tag == "IndieStrategy"
	replace genre = "Strategy" if tag == "Tactical"
	replace genre = "Sports" if tag == "Sports"
	replace genre = "Sports" if tag == "Racing"
	replace genre = "Sports" if tag == "Driving"
	replace genre = "Sports" if tag == "Football"
	replace genre = "Sports" if tag == "Soccer"
	replace genre = "Adult" if tag == "Sexual Content"
	replace genre = "Adult" if tag == "Nudity"
	replace genre = "Adult" if tag == "Mature"
	replace genre = "Adult" if tag == "Romance"
	replace genre = "Sci-fi" if tag == "Sci-fi"
	replace genre = "Family" if tag == "Family Friendly"
	replace genre = "Historical" if tag == "Historical"
	replace genre = "Historical" if tag == "World War II"
	replace genre = "Historical" if tag == "Medieval"
	replace genre = "Historical" if tag == "War"
	replace genre = "Historical" if tag == "Cold War"
	replace genre = "Historical" if tag == "Tanks"
	replace genre = "Historical" if tag == "Military"
	replace genre = "Space" if tag == "Space"
	replace genre = "Space" if tag == "Space Sim"
	replace genre = "Space" if tag == "Aliens"
	replace genre = "Space" if tag == "Supernatural"

end

program clean_publishers

	replace publisher = "2K" if publisher == "2K Games"
	replace publisher = "PlayStation Mobile, Inc." if regexm(publisher, "PlayStation")
	replace publisher = "Rockstar Games" if regexm(publisher, "Rockstar")
	replace publisher = "Warner Bros" if regexm(publisher, "Warner Bros") | regexm(publisher, "WB Games")
	replace publisher = "Nexon" if regexm(publisher, "Nexon") 
	
end

program define_multiplayer

	gen multiplayer = 0
	replace multiplayer = 1 if tag == "Multiplayer"
	replace multiplayer = 1 if tag == "Split Screen"
	replace multiplayer = 1 if tag == "Co-op"
	replace multiplayer = 1 if tag == "Online Co-Op"
	replace multiplayer = 1 if tag == "PvP"
	replace multiplayer = 1 if tag == "Local Co-Op"
	replace multiplayer = 1 if tag == "Co-op Campaign"
	replace multiplayer = 1 if tag == "Competitive"
	replace multiplayer = 1 if tag == "Massively Multiplayer"
	replace multiplayer = 1 if tag == "Local Multiplayer"
	replace multiplayer = 1 if tag == "MMORPG"
	replace multiplayer = 1 if tag == "Team-Based"
	replace multiplayer = 1 if tag == "4 Player Local"
	replace multiplayer = 1 if tag == "Battle Royale"
	replace multiplayer = 0 if tag == "Singleplayer" | tag == "PvE"

end


program define_rich_story

	gen rich_story = 0
	replace rich_story = 1 if tag == "Story Rich"
	replace rich_story = 1 if tag == "Open World"
	replace rich_story = 1 if tag == "Open World Survival Craft"
	replace rich_story = 1 if tag == "Replay Value"
	replace rich_story = 1 if tag == "Choices Matter"
	replace rich_story = 1 if tag == "Character Customization"
	replace rich_story = 1 if tag == "Turn-Based"
	replace rich_story = 1 if tag == "Exploration"
	replace rich_story = 1 if tag == "Multiple Endings"

end


program define_crafting

	gen crafting = 0
	replace crafting = 1 if tag == "Sandbox"
	replace crafting = 1 if tag == "Crafting"
	replace crafting = 1 if tag == "Building"
	replace crafting = 1 if tag == "City Builder"
	replace crafting = 1 if tag == "Base Building"

end


program define_other_variables

	gen free_to_play = (tag == "Free to Play")
	gen difficult    = (tag == "Difficult")
	gen early_access = (tag == "Early Access")
	gen indie        = (tag == "Indie")
	gen classic      = (tag == "Classic")
	gen remake       = (tag == "Remake")
	gen retro        = (tag == "Retro")

end


main