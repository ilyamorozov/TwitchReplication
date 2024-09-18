# build_twitch_api_text.R

library(data.table)
library(rjson)

start_date <- as.Date("2021-4-15", "%Y-%m-%d")
end_date <- as.Date("2021-12-31", "%Y-%m-%d")
set_dates <- gsub("2021-", "", as.character(seq(start_date, end_date, by = "days")))
set_dates <- gsub("-", "_", set_dates)
set_dates <- sub("^0", "", set_dates)
set_dates <- sub("_0", "_", set_dates)


# function to extract titles
extract_titles <- function(dat) {
    
    # define stream content from title
    dat[, stream_title := tolower(stream_title)]
    dat[, is_sponsored := as.integer(grepl("#sponsored|#ad|!sponsored|!ad|werbung", stream_title))]
    dat[, is_tutorial := as.integer(grepl("tutorial|guide|guia|unranked to|advice", stream_title))]
    dat[, is_merch := as.integer(grepl("merch", stream_title))]
    dat[, is_social := as.integer(grepl("social|discord|giveaway", stream_title))]
    dat[, is_video := as.integer(grepl("video|youtube", stream_title))]
    dat[, is_spoiler := as.integer(grepl("spoiler", stream_title))]
    dat[, is_partner := as.integer(grepl("!smitepartner|!BDOpartner|!KOCpartner|#dedafortwitchpartner|#smitepartner|#pubgmpartner|#pubgpartner|#ubipartner|#leaguepartner|#giantspartner|#gamescompartner|#epicpartner|#riotpartner|#knockoutcitypartner|#dbdpartner|#deadbydaylightpartner|#apexpartner|#apexlegendspartner|#codpartner", stream_title))]
    
    # remove stream title, at the moment cannot export it...
    dat[, stream_title := NULL]
    return(dat)
    
}

# function to extract tags
extract_tags <- function(dat) {
    
    # define content from tags
    set_tag_skills <- c("7cefbf30-4c3e-4aa7-99cd-70aabb662f27", "a5067bb9-0567-483b-88a6-7aa79985f272", "d33671c6-d05b-44a6-a548-5d5930365882", "c9193f35-a88f-4f03-af99-b73fe0db60f3", "e03c93a4-74ae-4358-8b3c-8189e5a1fbec")
    set_new_content <- c("8ba227ca-073c-46a7-b3cc-193e52c5ab4d", "2d4c0932-083d-4d39-9475-8a545e6202c7")
    set_tutorial <- "dc709206-c072-4340-a706-694578574c7e"
    
    dat[, is_skill_tag := 0]
    for (t in set_tag_skills) {
        dat[, is_skill_tag := pmax(is_skill_tag, as.integer(grepl(t, stream_tags)))]
    }
    dat[, is_new_tag := 0]
    for (t in set_new_content) {
        dat[, is_new_tag := pmax(is_new_tag, as.integer(grepl(t, stream_tags)))]
    }
    dat[, is_tutorial_tag := as.integer(grepl(set_tutorial, stream_tags))]
    dat[, stream_tags := NULL]
    return(dat)
    
}

# get high-frequency stream level characteristics
#   for now, we're not organizing tag hashes and stream title (should do text processing at this step to make subsequent steps easier)
stream_dat <- data.table(request_time = character(0), streamer_code = integer(0))
set_dat <- c("stream_title", "stream_tags") # "stream_language", 

for (f in 1:length(set_dates)) {
    
    print(f)
    stream_temp <- data.table(request_time = character(0), streamer_code = integer(0))

    # iterate across data sets
    for (d in 1:length(set_dat)) {
        
        f1 <- data.table(request_time = character(0), streamer_code = integer(0))
        dat <- set_dat[d]
        t1 <- paste0("../input/api_data/", dat, "/", dat, "_", set_dates[f], ".csv")
        t1_o <- paste0("../input/api_data/", dat, "/", dat, "_", set_dates[f], "_OLD_SAMPLE", ".csv")
        t1_o2 <- paste0("../input/api_data/", dat, "/", dat, "_", set_dates[f], "_OVERLAP", ".csv")
        
        for (t_temp in c(t1, t1_o, t1_o2)) {
            if (file.exists(t_temp)) {
                f_temp <- fread(t_temp, header = T, sep = ",")
                f_temp <- melt(f_temp, id.vars = "request_time")
                colnames(f_temp)[2:3] <- c("streamer_code", dat)
                f_temp <- f_temp[!is.na(f_temp[[dat]])]  # keep only active streams
                f_temp <- f_temp[f_temp[[dat]] != ""]
                f_temp[, streamer_code := as.integer(as.character(streamer_code))]
                f1 <- rbind(f1, f_temp, fill = T)
            }
        }
        stream_temp <- merge(stream_temp, f1, by = c("request_time", "streamer_code"), all = T)
        
    }
    
    if (file.exists(t1)) {
        
        # extract title and tags
        stream_temp <- extract_titles(stream_temp)
        stream_temp <- extract_tags(stream_temp)
        
        # append
        stream_dat <- rbind(stream_dat, stream_temp, fill = T)
        
    }
    
}

# sort
stream_dat <- stream_dat[order(streamer_code, request_time)]

# eliminate zeros
stream_dat <- stream_dat[!(is_sponsored + is_tutorial + is_merch + is_social + is_video + is_spoiler + is_skill_tag + is_new_tag + is_tutorial_tag == 0)]

# export (elements of) title and tags
fwrite(stream_dat, file = "../temp/stream_text.txt", row.names = F, quote = F, sep = "\t", na = "")

