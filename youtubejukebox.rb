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
HighLine.track_eof = false   # Fixes weird EOF 'bug'.

class YoutubeJukebox
  attr_accessor :youtube,
                :download_folder,
                :download_buffer,
                :conversion_buffer,
                :max_simultaneous_conversions,
                :max_search_results,
                :current_conversions

  def initialize
    @youtube = YouTubeG::Client.new
    @download_folder = "./downloads"
    @download_buffer = 15 #sec
    @conversion_buffer = 4 #sec
    @max_search_results = 50
#    @max_simultaneous_conversions = 3
#    @current_conversions = 0
  end

  def isint(str)
     return str =~ /^[-+]?[0-9]+$/
  end

  def download_convert_play(video)
    # Downloads and converts a given youtube-g video, and adds the mp3 to vlc.
    url = video.player_url[/^(http:\/\/www.youtube.com\/watch\?v=.+)&/, 1]
    # Remove invalid filename characters
    title = video.title.gsub(/["'\[\]\(\),]/, "").gsub(":", "-")
    download_file = File.join(@download_folder, "youtube-dl-#{rand(1000000)}.flv")
    output_file = File.join(@download_folder, "#{title}.mp3")

    puts "\n\n===== Title: #{title}"
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
        `echo \"\" | ffmpeg -re -i \"#{download_file}\" -acodec libmp3lame -ac 2 -ab 128k -vn -y \"#{output_file}\" > /dev/null 2>&1 && rm \"#{download_file}\"`
      }
      sleep @conversion_buffer
      Thread.new {
        system("vlc --started-from-file --playlist-enqueue \"#{output_file}\" > /dev/null 2>&1")
      }
    }
  end

  def search(query, page = 1)
    # Loops until user presses 'x' to enter another query.
    # Searches for youtube videos and asks user to select desired video from a list of 10.
    puts "Searching for '#{query}'..."
    videos = @youtube.videos_by(:query => query, :per_page => @max_search_results).videos
    if videos.size == 0
      puts "No videos found.\n"
      return false
    end
    char = 0
    while char.chr != "x"
      page_offset = ((page-1)*10)
      puts "\n"
      videos[0 + page_offset, 10].each_with_index do |v, i|
        puts "(#{i}) - #{v.title}"
      end
      total_pages = videos.size / 10 + (videos.size % 10 == 0 ? 0 : 1)
      puts "\nPress 'x' to search for something else. <b or n> to change page of results.    |   page #{page} of #{total_pages}"
      print "Please enter the number of your selected video: "
      char = get_character
      puts char.chr
      # Change the page if user enters 'n' or 'b'
      if char.chr == "n" or char.chr == "b"
        char.chr == "n" ? page += 1 : page -= 1
        page = total_pages if page < 1
        page = 1 if page > total_pages
      end
      # If the user has entered an integer, then play the video at that location in the array.
      if isint(char.chr)
        video = videos[char.chr.to_i + page_offset]
        download_convert_play(video)
        puts "\n"
      end
    end
  end

end

# ------------------------ Start of script ---------------------------

@youtubejb = YoutubeJukebox.new

# If a commandline query was given, perform the search...
@youtubejb.search(ARGV[0]) if ARGV[0]

# Then loop for user input.
while true
  query = ask("\nPlease enter a youtube search query ('' to exit): ") { |q| q.echo = true }
  exit if query == ""
  @youtubejb.search(query)
end

