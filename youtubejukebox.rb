#!/usr/bin/env ruby
# Script that plays the audio from youtube videos. Requires vlc.

# --- Coding Notes:
# FFMPEG swallows all input from stdin by default.
# To overcome this, fake input with a 'echo "" |' before the ffmpeg command.

require 'rubygems'
require 'youtube_g'
require "highline/system_extensions"
require 'highline/import'
include HighLine::SystemExtensions

@youtube = YouTubeG::Client.new

@download_buffer = 5 #sec
@conversion_buffer = 3 #sec

def input_track
  return ask("\nPlease enter a query to search for a track: ") { |q| q.echo = true }
end

def find_video(query)
  # Searches for youtube videos and asks user to select desired video from a list of 10.
  videos = @youtube.videos_by(:query => query).videos
  videos[0, 10].each_with_index do |v, i|
    puts "(#{i}) - #{v.title}"
  end
  print "Please enter the number of the video that looks most relevant: "
  char = get_character
  puts char.chr
  video = videos[char.chr.to_i]
  return video
end

def play_video(video)
  # Downloads and converts a given youtube-g video, and adds the mp3 to vlc.
  video_id = video.player_url[/http:\/\/www.youtube.com\/watch\?v=(.+)&/, 1]
  url = "http://www.youtube.com/v/#{video_id}"
  # Remove invalid filename characters
  title = video.title.gsub(/["'\[\]\(\),]/, "")
  download_file = "youtube-dl-#{rand(1000000)}.flv"
  output_file = "#{title}.mp3"

  puts "===== Title: #{title}"
  puts "===== URL: #{url}"
  puts "===== Starting flv download, on-the-fly conversion, then starting vlc & queuing track..."

  # Layered threads for all of the system calls.
  Thread.new {
    Thread.new {
      system("youtube-dl --output=\"#{download_file}\" --format=18 \"#{url}\" > /dev/null 2>&1")
    }
    sleep @download_buffer
    Thread.new {
      # also deletes the downloaded flv file after conversion.
      system("echo \"\" | ffmpeg -re -i \"#{download_file}\" -acodec libmp3lame -ac 2 -ab 128k -vn -y \"#{output_file}\" > /dev/null 2>&1 && rm \"#{download_file}\"")
    }
    sleep @conversion_buffer
    Thread.new {
      system("vlc --started-from-file --playlist-enqueue \"#{output_file}\" > /dev/null 2>&1")
    }
  }
end

# If a commandline query was given, play the inital track...
if query = ARGV[0]
  v = find_video(query)
  play_video(v)
end

# Then loop for user input.
while true
  query = input_track
  v = find_video(query)
  play_video(v)
end

