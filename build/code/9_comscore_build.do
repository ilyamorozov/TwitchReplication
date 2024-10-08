clear
program drop _all


program main

	* Convert Comcore data from raw to dta *
	build_comscore
	
	* Build twitch and steam tables *
	build_steam_browse
	
	* Build crosswalk *
	build_crosswalk_twitch_steam
	
	* Build purchases *
	build_ecommerce
	build_steam_purchases

end


program build_comscore

	* Import and process raw comscore files (twitch + steam) *
	local counter = 1
	local satafiles: dir  "../input/comscore/csv/" files "*.csv"
	foreach file of local satafiles {
	    
		display "Processing csv file named: `file'"
	
		* Keep Steam observations that look like video game page visits (with appid's) *
		import delimited "../input/comscore/csv/`file'", varnames(1) clear
		drop v1 url_idc person_id time_id mimetype http_rc keywords html_title pattern_id
		keep if domain_name == "steampowered.com" & url_host == "store.steampowered.com"
		keep if (substr(url_refer_dir, 1, 4)=="app/") | (substr(url_refer_dir, 1, 4)=="agecheck/app/") | url_dir == "/app" | url_dir == "app" | url_dir == "appreviewhistogram"
		gen appid = ""                                                                                      // extract 'appid' game identifiers
		split url_refer_dir, p("/")                                                                         // search for appid's in 'url_refer_dir'
		replace appid = url_refer_dir2 if url_refer_dir1 == "app"
		replace appid = url_refer_dir3 if url_refer_dir2 == "app" & url_refer_dir1 == "agecheck"
		gen game_title = url_refer_dir3 if url_refer_dir1 == "app"
		format %15s appid
		format %40s game_title
		replace appid = url_page if url_dir == "app" | url_dir == "/app" | url_dir == "appreviewhistogram"  // search for appid's in 'url_dir' and 'url_page' 
		keep machine_id ss2k domain_name appid game_title year month day
		if `counter' > 1 append using "../output/comscore_steam.dta"
		save "../output/comscore_steam.dta", replace
		
		* Keep Twitch observations that look like channel viewership *
		import delimited "../input/comscore/csv/`file'", varnames(1) clear
		drop v1 url_idc person_id time_id mimetype http_rc keywords html_title pattern_id
		keep if url_host=="www.twitch.tv" & url_dir=="/"
		keep machine_id ss2k domain_name url_page url_refer_page year month day
		foreach var of varlist url_page url_refer_page {
			replace `var' = subinstr(`var', "/", "", .) 
			replace `var' = subinstr(`var', "activate", "", .)
			replace `var' = subinstr(`var', "broadcast", "", .)
			replace `var' = subinstr(`var', "prime", "", .)
			replace `var' = subinstr(`var', "login", "", .)
			replace `var' = subinstr(`var', "search", "", .)
			replace `var' = subinstr(`var', "downloads", "", .)
			replace `var' = subinstr(`var', "inventory", "", .)
			replace `var' = subinstr(`var', "opensearch.xml", "", .)
			replace `var' = subinstr(`var', "open.xml", "", .)
			replace `var' = subinstr(`var', "robots.txt", "", .)
		}
		drop if url_page == "" & url_refer_page == ""
		replace url_page = url_refer_page if url_page == ""
		drop url_refer_page
		sort machine_id ss2k domain_name url_page
		rename url_page streamer
		if `counter' > 1 append using "../output/comscore_twitch.dta"
		save "../output/comscore_twitch.dta", replace
	
		local counter = `counter' + 1
		
	}

end


program build_steam_browse

	* Load steam data and define date/time *
	use "../output/comscore_steam.dta", clear
	gen date = mdy(month, day, year)
	format date %d
	gen double time_stamp = ss2k*1000 + tc("31dec1999 00:00:30") // comscore advertises ss2k = 'seconds since 2000' (not quite correct)
	format time_stamp %tC
// 	generate date_text = string(date, "%td")                     // uncomment this to verify that time stamps match dates
// 	generate date_text2 = string(time_stamp, "%tC")              // uncomment this to verify that time stamps match dates
// 	browse if substr(date_text,1,9) ~= substr(date_text2,1,9)    // uncomment this to verify that time stamps match dates
	gen hour = hh(time_stamp)
	destring appid, gen(steam_id) force
	drop if steam_id == .
	gen browse_steam = 1
	collapse (max) browse_steam, by(machine_id date hour steam_id)
	save "../temp/comscore_steam_hourly.dta", replace
	collapse (max) browse_steam, by(machine_id date steam_id)
	save "../temp/comscore_steam_daily.dta", replace

end


program build_crosswalk_twitch_steam

	* Merge game names with steam IDs, then collapse across streams *
	use "../temp/twitch_tracker_historical.dta", clear
	merge n:1 game_title using "../temp/steam_twitch_crosswalk.dta", keep(1 3) nogenerate
	drop game_title
	collapse (sum) duration, by(streamer date steam_id) 
	drop if steam_id == .
	save "../temp/twitch_tracker_historical_steam_id.dta", replace
	// Helps lookup which game was streamed for a given streamer x date pair

end


program build_ecommerce

	* Organize all video game purchases from Comscore *
	use "../input/comscore/ecommerce.dta", clear             // load Comscore ecommerce table
	assert date > mdy(12,31,2018) &  date < mdy(1,1,2021)    // assert dates are defined correctly
	keep if productCategory == "VIDEO GAMES AND CONSOLES"
	tab domain_name, sort
	keep if domain_name == "amazon.com" | domain_name == "steampowered.com" | domain_name == "walmart.com" | domain_name == "bestbuy.com" | domain_name == "gamestop.com" | domain_name == "target.com" | domain_name == "microsoft.com" 
	gen hour = substr(event_time, 12, 2)
	gen minute = substr(event_time, 15, 2)
	destring hour minute, replace force
	save "../output/ecommerce_video_game.dta", replace
	
	* Save list of all purchasers for later selection *
	keep machine_id 
	duplicates drop machine_id, force
	save "../temp/ecommerce_all_purchasers.dta", replace

end


program build_steam_purchases

	* Organize purchases on Steam *
	use "../output/ecommerce_video_game.dta", clear
	keep if domain_name == "steampowered.com"
	rename raw_itemTotal price
	gen     game_title = upper(itemName) // extract title of purchased game
	replace game_title = regexr(game_title, " BUNDLE", "")
	replace game_title = "THE ELDER SCROLLS V: SKYRIM" if regexm(game_title, "SKYRIM")
	replace game_title = "TOM CLANCYS RAINBOW SIX SIEGE" if game_title == "RAINBOW SIX SIEGE"
	replace game_title = "RESIDENT EVIL 7 BIOHAZARD" if game_title == "RESIDENT EVIL 7"
	replace game_title = "CALL OF DUTY: WORLD AT WAR" if game_title == "WORLD AT WAR"
	replace game_title = "CALL OF DUTY: BLACK OPS II" if game_title == "BLACK OPS II"
	replace game_title = "ARMA 3" if regexm(game_title, "ARMA 3")
	merge n:1 game_title using "../temp/steam_twitch_crosswalk.dta", keep(1 3) nogenerate	     // lookup SteamID and TwitchID using game titles
	collapse (firstnm) price hour, by(machine_id date steam_id)                                  // collapse to the same level as twitch viewership (machine-date-steam_id)
	keep if steam_id != .
	gen purchase_game = 1
	save "../temp/comscore_purchases.dta", replace
	
	* Make list of purchased Steam games *
	use "../temp/comscore_purchases.dta", clear
	collapse (count) nr_purchased = machine_id, by(steam_id) 											// save IDs of games purchased on steampowered
	gsort -nr_purchased
	//keep if _n <= 50 // select subsample of games
	gen new_game_id = _n
	keep new_game_id steam_id
	order new_game_id steam_id
	merge 1:n steam_id using "../temp/steam_twitch_crosswalk.dta", keep(1 3) nogenerate
	gen name = lower(game_title)
	keep steam_id new_game_id name game_title
	save "../temp/steam_game_names.dta", replace

end


main



