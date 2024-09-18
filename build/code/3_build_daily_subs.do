clear
program drop _all


program main

	build_subscriptions
	clean_subscriptions
	
end


program build_subscriptions

	* Convert daily_subs tables to dta *
	local satafiles: dir "../input/subs_data/" files "*.xlsx"
	local counter = 1
	foreach file of local satafiles {
		display "Counter value: `counter'"
		import excel "../input/subs_data/`file'", sheet("Sheet1") firstrow clear
		gen file_name = "`file'"
		save "../temp/daily_subs_`counter'.dta", replace
		local counter = `counter' + 1
	}

	* Merge daily_subs tables *
	use "../temp/daily_subs_1.dta", clear
	local max_file = `counter' - 1
	forval z = 1/`max_file' { 
		display "File number: `z' out of `max_file'"
		append using "../temp/daily_subs_`z'.dta"
	}

end


program clean_subscriptions

	* Clean raw data *
	format %25s Time
	drop if Current_Time == ""
	sort Current_Time
	drop if length(Time) >= 100

	* Drop duplicate observations *
	gen date_collected = date(substr(Current_Time, 1, 10), "YMD")
	format date_collected %d
	gen date_stored = date(substr(file_name, 12, 8), "YMD")
	format date_stored %d
	keep if date_collected == date_stored
	drop date_stored file_name
	sort Current_Time

	* Flag strings with streamer names *
	gen letters = ""
	quietly forval j = 1/100 { 
		local arg substr(Time,`j', 1) 
		replace letters = letters + `arg' if inrange(`arg', "A", "Z") 
	}

	* Enumerate variables *
	gen num = .
	replace num = 1 if letters ~= ""
	replace num = num[_n-1] + 1 if num == .
	gen variable = ""
	replace variable = "streamer" if num == 1
	replace variable = "current"  if num == 2
	replace variable = "paid"     if num == 3
	replace variable = "prime"    if num == 4
	replace variable = "gifted"   if num == 5
	replace variable = "tier1"    if num == 6
	replace variable = "tier2"    if num == 7
	replace variable = "tier3"    if num == 8
	drop if num == .
	drop if num > 8

	* Create streamer names *
	rename letters streamer
	replace streamer = streamer[_n-1] if streamer == ""
	replace streamer = lower(streamer)
	drop if variable == "streamer"

	* Convert values to numeric *
	gen value = Time 
	replace value = "" if num == 1
	replace value = "" if value == "?"
	drop if strpos(value, "#") > 0
	destring value, replace ignore(",")

	* Organize data *
	rename date_collected date
	sort streamer variable date value
	keep streamer variable date value

	* Long to wide *
	rename value subs_
	collapse (max) subs_, by(date streamer variable)
	reshape wide subs_, i(date streamer) j(variable) string
	sort streamer date

	* Compute expected sub revenues *
	gen subs_revenue = 0.5 * (4.99 * (subs_tier1 + subs_prime + subs_gifted) + 9.99 * subs_tier2 + 24.99 * subs_tier3)
	reg subs_revenue subs_current subs_tier2 subs_tier3 subs_gifted
	predict subs_revenue_predicted
	replace subs_revenue = subs_revenue_predicted if subs_revenue == .
	keep date streamer subs_current subs_revenue
	sort date streamer
	save "../output/daily_subs.dta", replace

	* Erase temp files *
	forval z = 1/5000 { 
		capture erase "../temp/daily_subs_`z'.dta"
	}

end


main

