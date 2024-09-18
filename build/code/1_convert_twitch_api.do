clear
clear mata
program drop _all
set maxvar 120000


program main

	* Make temp directories *
	capture: mkdir "../temp/game_id/"
	capture: mkdir "../temp/num_viewers/"
	capture: mkdir "../temp/stream_language/"
	capture: mkdir "../temp/stream_type/"

	* Process raw data *
	convert_num_viewers
	convert_stream_type
	convert_game_id
	convert_stream_language

end


program convert_num_viewers

	local satafiles: dir "../input/api_data/num_viewers/" files "*.csv"
	foreach file of local satafiles {

		* Wide to long conversion (in batches of 1000 columns) *
		import delimited "../input/api_data/num_viewers/`file'", varnames(1) clear

		quietly describe
		local num_vars = r(k) - 1
		local num_batches = ceil(`num_vars' / 1000)

		forval z = 1/`num_batches' { 
			
			local first_var = 2 + 1000 * (`z'-1)
			local last_var = 1001 + 1000 * (`z'-1)
			
			if `z' == `num_batches' {
				local last_var = `num_vars' + 1
			}
			
			display "Processing batch `z' out of `num_batches' (observations `first_var' to `last_var')" 
			
			preserve
			keep request_time v`first_var'-v`last_var'
			quietly duplicates drop request_time, force
			quietly greshape long v, by(request_time) keys(num)
			quietly rename v viewers
			quietly save "../temp/num_viewers_batch`z'.dta", replace
			restore

		}

		* Merge batches *
		use "../temp/num_viewers_batch1.dta", clear
		forval z = 2/`num_batches' { 
			append using "../temp/num_viewers_batch`z'.dta"
		}

		* Add time variable and save *
		gen double time = clock(substr(request_time, 1, 6) + "2021" + substr(request_time, 9, 5) + "0:00", "MDY hms") // Round min to 10s and sec to 00s *
		format time %tc
		drop request_time
		sort num time
		order num time viewers
		save "../temp/num_viewers/`file'.dta", replace

		* Erase temp files *
		forval z = 1/`num_batches' { 
			erase "../temp/num_viewers_batch`z'.dta"
		}

	}

end


program convert_stream_type

	local satafiles: dir "../input/api_data/stream_type/" files "*.csv"
	foreach file of local satafiles {

		* Wide to long conversion (in batches of 1000 columns) *
		import delimited "../input/api_data/stream_type/`file'", varnames(1) stringcols(_all) clear 
		
		quietly describe
		local num_vars = r(k) - 1
		local num_batches = ceil(`num_vars' / 1000)

		forval z = 1/`num_batches' { 
			
			local first_var = 2 + 1000 * (`z'-1)
			local last_var = 1001 + 1000 * (`z'-1)
			
			if `z' == `num_batches' {
				local last_var = `num_vars' + 1
			}
			
			display "Processing batch `z' out of `num_batches' (observations `first_var' to `last_var')" 
			
			preserve
			keep request_time v`first_var'-v`last_var'
			quietly duplicates drop request_time, force
			quietly greshape long v, by(request_time) keys(num)
			quietly rename v viewers
			quietly save "../temp/stream_type_batch`z'.dta", replace
			restore

		}

		* Merge batches *
		use "../temp/stream_type_batch1.dta", clear
		forval z = 2/`num_batches' { 
			append using "../temp/stream_type_batch`z'.dta"
		}

		* Add time variable and save *
		gen double time = clock(substr(request_time, 1, 6) + "2021" + substr(request_time, 9, 5) + "0:00", "MDY hms") // Round min to 10s and sec to 00s *
		format time %tc
		drop request_time
		sort num time
		order num time viewers
		save "../temp/stream_type/`file'.dta", replace

		* Erase temp files *
		forval z = 1/`num_batches' { 
			erase "../temp/stream_type_batch`z'.dta"
		}

	}

end


program convert_game_id

	local satafiles: dir "../input/api_data/game_id/" files "*.csv"
	foreach file of local satafiles {

		* Wide to long conversion (in batches of 1000 columns) *
		import delimited "../input/api_data/game_id/`file'", varnames(1) stringcols(_all) clear 
		
		quietly describe
		local num_vars = r(k) - 1
		local num_batches = ceil(`num_vars' / 1000)

		forval z = 1/`num_batches' { 
			
			local first_var = 2 + 1000 * (`z'-1)
			local last_var = 1001 + 1000 * (`z'-1)
			
			if `z' == `num_batches' {
				local last_var = `num_vars' + 1
			}
			
			display "Processing batch `z' out of `num_batches' (observations `first_var' to `last_var')" 
			
			preserve
			keep request_time v`first_var'-v`last_var'
			quietly duplicates drop request_time, force
			quietly greshape long v, by(request_time) keys(num)
			quietly rename v game_id
			quietly save "../temp/game_id_batch`z'.dta", replace
			restore

		}

		* Merge batches *
		use "../temp/game_id_batch1.dta", clear
		forval z = 2/`num_batches' { 
			append using "../temp/game_id_batch`z'.dta"
		}

		* Add time variable and save *
		gen double time = clock(substr(request_time, 1, 6) + "2021" + substr(request_time, 9, 5) + "0:00", "MDY hms") // Round min to 10s and sec to 00s *
		format time %tc
		drop request_time
		sort num time
		order num time game_id
		drop if game_id == ""
		save "../temp/game_id/`file'.dta", replace

		* Erase temp files *
		forval z = 1/`num_batches' { 
			erase "../temp/game_id_batch`z'.dta"
		}

	}

end


program convert_stream_language

	local satafiles: dir "../input/api_data/stream_language/" files "*.csv"
	foreach file of local satafiles {

		* Wide to long conversion (in batches of 1000 columns) *
		import delimited "../input/api_data/stream_language/`file'", varnames(1) stringcols(_all) clear 
		
		quietly describe
		local num_vars = r(k) - 1
		local num_batches = ceil(`num_vars' / 1000)

		forval z = 1/`num_batches' { 
			
			local first_var = 2 + 1000 * (`z'-1)
			local last_var = 1001 + 1000 * (`z'-1)
			
			if `z' == `num_batches' {
				local last_var = `num_vars' + 1
			}
			
			display "Processing batch `z' out of `num_batches' (observations `first_var' to `last_var')" 
			
			preserve
			keep request_time v`first_var'-v`last_var'
			quietly duplicates drop request_time, force
			quietly greshape long v, by(request_time) keys(num)
			quietly rename v language
			quietly save "../temp/stream_language_batch`z'.dta", replace
			restore

		}

		* Merge batches *
		use "../temp/stream_language_batch1.dta", clear
		forval z = 2/`num_batches' { 
		append using "../temp/stream_language_batch`z'.dta"
		}

		* Add time variable and save *
		gen double time = clock(substr(request_time, 1, 6) + "2021" + substr(request_time, 9, 5) + "0:00", "MDY hms") // Round min to 10s and sec to 00s *
		format time %tc
		drop request_time
		sort num time
		order num time language
		drop if language == ""
		save "../temp/stream_language/`file'.dta", replace

		* Erase temp files *
		forval z = 1/`num_batches' { 
		erase "../temp/stream_language_batch`z'.dta"
		}

	}

end


main


