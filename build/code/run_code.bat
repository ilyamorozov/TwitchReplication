REM ****************************************************
REM * run_code.bat: double-click to run all scripts
REM ****************************************************

REM SET LOG=..\output\run_code.log

REM DELETE OUTPUT AND TEMP FOLDERS (COMMENTED OUT FOR NOW)
REM DEL /F /Q ..\output\
REM DEL /F /Q ..\output\figures\
REM DEL /F /Q ..\output\tables\

RMDIR ..\temp /S /Q
RMDIR ..\output /S /Q
MKDIR ..\temp
MKDIR ..\output

REM LOG START
REM ECHO run_code.bat started	>%LOG%
REM ECHO %DATE%		>>%LOG%
REM ECHO %TIME%		>>%LOG%
REM dir ..\output\ >>%LOG%

REM RUN CODE
%REXE% CMD BATCH 0_build_main_api_sample.R
%STATAEXE% /e do 1_convert_twitch_api.do
%STATAEXE% /e do 2_build_steam_api_data.do
%STATAEXE% /e do 3_build_daily_subs.do
%REXE% CMD BATCH 4_build_twitch_api_text.R
%STATAEXE% /e do 5_build_twitch_api.do
%STATAEXE% /e do 6_build_streamer_chars.do
%STATAEXE% /e do 7_build_stream_chars.do
%STATAEXE% /e do 8_build_game_chars.do
REM %STATAEXE% /e do 9_comscore_build.do
REM %STATAEXE% /e do 10_comscore_merge.do
REM %STATAEXE% /e do 11_build_comscore_hourly.do

REM COPY %LOG%+0_build_main_api_sample.Rout+1_convert_twitch_api.log+2_build_steam_api_data.log+3_build_daily_subs.log+4_build_twitch_api_text.Rout+5_build_twitch_api.log+6_build_streamer_chars.log+7_build_stream_chars.log+8_build_game_chars.log+9_summary_stats.log+10_comscore_build.log+11_comscore_merge.log+12_build_comscore_hourly.log %LOG%
REM DEL 0_build_main_api_sample.Rout 1_convert_twitch_api.log 2_build_steam_api_data.log 3_build_daily_subs.log 4_build_twitch_api_text.Rout 5_build_twitch_api.log 6_build_streamer_chars.log 7_build_stream_chars.log 8_build_game_chars.log 9_summary_stats.log 10_comscore_build.log 11_comscore_merge.log 12_build_comscore_hourly.log

REM RMDIR ..\temp /S /Q

REM LOG COMPLETE
REM ECHO run_code.bat completed	>>%LOG%
REM ECHO %DATE%		>>%LOG%
REM ECHO %TIME%		>>%LOG%

PAUSE
