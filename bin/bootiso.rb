#!/usr/bin/env ruby
# Image boot entry generator for GRUB2
#
# Code by Marco Caimi 

require 'yaml'

# load global parameters
$GLOBAL="/etc/bootiso.yaml"
if File.exist? $GLOBAL
	globals = YAML.load_file($GLOBAL)
	$CFGPATH=globals["global"]["cfgpath"]
	$BLKID=globals["global"]["blkid"]
else
	exit(-1)
end

# UUID matcher
$UUID_REGEX=/UUID="(\S+)"/

# Exceptions
class MissingCodeBlockException < Exception; end

# Patch the built-in String Class to support colored text output
class String
  
  # define color codes
  $COLORS = {:reset => "\033[0m",
    :red => "\033[0;31m",
    :blue => "\033[0;34m",
    :yellow => "\033[1;33m",
    :green => "\033[0;32m",
    :purple => "\033[0;35m"
  }

  # generic colored output method
  # outputs a colored text line to console
  def c_print(color)
    puts $COLORS[color] + self.to_s + $COLORS[:reset]
  end

  # constructs a colored text line 
  # but does not print it to screen
  def colorize(color)
    return $COLORS[color] + self.to_s + $COLORS[:reset]
  end

  # console event reporting metods
  # display event results with different colored strings
  # These methods do not print anything, they just return a string

  # => INFO LEVEL EVENT
  def e_info()
    return $COLORS[:green] + "*" + "\t" + $COLORS[:reset] + self.to_s
  end

  # => WARNING LEVEL EVENT
  def e_warn()
    return $COLORS[:yellow] + "*" + "\t" + $COLORS[:reset] + self.to_s
  end

  # => ERROR LEVEL EVENT
  def e_err()
    return $COLORS[:red] + "*" + "\t" + $COLORS[:reset] + self.to_s
  end
end

# class that handles ISO repository
class Repository
	# constructor
	def initialize(dirname)
		@yaml_repository = dirname
		@dir_accessor = Dir[dirname + "/*.yaml"]
	end
	
	# config file iterator
	def each_file()
		if block_given?
			@dir_accessor.each do |iso_file|
				yield iso_file
			end
		else
			raise MissingCodeBlockException, "Repository::each_file(): Missing Code Block".eerror()
		end
	end
	
	# print a list of all defined configurations
	def list()
		puts "Configuration files currently defined in the Repository:".colorize(:yellow)
		self.each_file { |iso_file| puts "#{EntryGenerator.new(iso_file).entry_name}".e_info() + ", (#{iso_file})".colorize(:yellow) }
		puts ""
	end
end

# Entry generator class 
class EntryGenerator
	# YAML TAGS
	$tags = {:config => "config",
		:use => "use",
		:name => "name",
		:boot_path => "boot_path",
		:kernel => "kernel",
		:initrd => "initrd",
		:root_dev => "root_dev",
		:grub_dev => "grub_dev",
		:iso_path => "iso_path",
		:iso_filename => "iso_filename",
		:boot_opts => "boot_opts"
	}
	
	# attribute accessor
	attr_reader :entry_name, :fs_uuid
	
	# constructor
	def initialize(filename)
		# config specification
		@spec = {}
		
		# parse the YAML file
		@file = YAML.load_file(filename)

		# fill data into the spec
		@spec[:name] = @file[$tags[:config]][$tags[:name]]
		@spec[:use] = @file[$tags[:config]][$tags[:use]]
		@spec[:boot_path] = @file[$tags[:config]][$tags[:boot_path]]
		@spec[:kernel] = @file[$tags[:config]][$tags[:kernel]]
		@spec[:initrd] = @file[$tags[:config]][$tags[:initrd]]
		@spec[:root_dev] = @file[$tags[:config]][$tags[:root_dev]]
		@spec[:grub_dev] = @file[$tags[:config]][$tags[:grub_dev]]
		@spec[:iso_path] = @file[$tags[:config]][$tags[:iso_path]]
		@spec[:iso_filename] = @file[$tags[:config]][$tags[:iso_filename]]
		@spec[:boot_opts] = @file[$tags[:config]][$tags[:boot_opts]]

		# add the file name
		@entry_name = @spec[:iso_filename]
		@fs_uuid = IO.popen($BLKID + " " + @spec[:root_dev]) { |bin| bin.readline.scan($UUID_REGEX) }
	end
	
	# property accessor
	def [](key)
		return @spec[key]
	end
	
	# write entry
	def write_entry()
		puts "# BOOT ENTRY for: #{@spec[:name]}"
		puts "menuentry \"#{@spec[:name]}\" {"
		puts "\t" + "insmod ext2"
		puts "\t" + "set root='#{@spec[:grub_dev]}'"
		puts "\t" + "search --no-floppy --fs-uuid --set #{@fs_uuid}"
		puts "\t" + "loopback loop #{@spec[:iso_path]}#{@spec[:iso_filename]}"
		puts "\t" + "linux (loop)#{@spec[:boot_path]}#{@spec[:kernel]} #{@spec[:use]}=#{@spec[:iso_path]}#{@spec[:iso_filename]} #{@spec[:boot_opts]}"
		puts "\t" + "initrd (loop)#{@spec[:boot_path]}#{@spec[:initrd]}"
		puts "}\n"
	end
end

# MAIN
# Sanity Check
if !File.exist? $CFGPATH
	exit(-1)
end

# open repo
repodir = Repository.new($CFGPATH)

# write boot entries to grub.cfg
puts "# BOOTISO Generated entries below"
repodir.each_file { |cfg| EntryGenerator.new(cfg).write_entry() }

# END
