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

HighLine.track_eof = false

@youtube = YouTubeG::Client.new

@download_buffer = 15 #sec
@conversion_buffer = 4 #sec

@max_simultaneous_conversions = 3
@current_conversions = 0

@download_folder = "./downloads"

def download_convert_play(video)
  # Downloads and converts a given youtube-g video, and adds the mp3 to vlc.
  url = video.player_url[/^(http:\/\/www.youtube.com\/watch\?v=.+)&/, 1]
  # Remove invalid filename characters
  title = video.title.gsub(/["'\[\]\(\),]/, "").gsub(":", "-")
  download_file = File.join(@download_folder, "youtube-dl-#{rand(1000000)}.flv")
  output_file = File.join(@download_folder, "#{title}.mp3")

  puts "===== Title: #{title}"
  puts "===== URL: #{url}"
  puts "===== Starting flv download, on-the-fly conversion, then starting vlc & queuing track..."

  # Layered threads for all of the system calls.
  Thread.new {
    @current_conversions += 1
    # sleep while the no. of conversions is above the max allowed simultaneous conversions
    while @current_conversions >= @max_simultaneous_conversions
      sleep 5
    end
    Thread.new {
      system("youtube-dl --output=\"#{download_file}\" --format=18 \"#{url}\" > /dev/null 2>&1")
    }
    sleep @download_buffer
    Thread.new {
      # also deletes the downloaded flv file after conversion.
      `echo \"\" | ffmpeg -re -i \"#{download_file}\" -acodec libmp3lame -ac 2 -ab 128k -vn -y \"#{output_file}\" > /dev/null 2>&1 && rm \"#{download_file}\"`
      @current_conversions -= 1
    }
    sleep @conversion_buffer
    Thread.new {
      system("vlc --started-from-file --playlist-enqueue \"#{output_file}\" > /dev/null 2>&1")
    }
  }
end

def isint(str)
   return str =~ /^[-+]?[0-9]+$/
end


# If a commandline query was given, perform the search...
get_search_results(ARGV[0]) if ARGV[0]

def get_search_results(query, page = 1)
  # Loops until user presses 'x' to enter another query.
  char = 0

  puts "Searching for '#{query}'..."
  videos = @youtube.videos_by(:query => query).videos
  if videos.size == 0
    puts "No videos found.\n"
    return false
  end

  while char.chr != "x"
    # Searches for youtube videos and asks user to select desired video from a list of 10.
    page_offset = ((page-1)*10)
    puts "\n"
    videos[0 + page_offset, 10].each_with_index do |v, i|
      puts "(#{i}) - #{v.title}"
    end
    total_pages = videos.size / 10 + (videos.size % 10 == 0 ? 0 : 1)
    puts "\nPress 'x' to go back. <b or n> to change page of results.    |   page #{page} of #{total_pages}"
    print "Please enter the number of the video that looks most relevant: "
    char = get_character

    if char.chr == "n" or char.chr == "b"
      page += 1 if char.chr == "n"
      page -= 1 if char.chr == "b"
      page_offset = ((page-1)*10)
      page = total_pages if page_offset < 0
      page = 1 if page_offset > videos.size
    end

    puts char

    if isint(char.chr)
      video = videos[char.chr.to_i + page_offset]
      download_convert_play(video)
      puts "\n"
    end

  end
end

# Then loop for user input.
while true
  query = ask("\nPlease enter a youtube search query ('' to exit): ") { |q| q.echo = true }
  exit if query == ""
  get_search_results(query)
end

