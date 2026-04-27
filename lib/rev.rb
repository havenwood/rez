# frozen_string_literal: true

require "optparse"
require "open3"
require "tempfile"
require_relative "rev/version"

module Rev
  DIR = ".rev"

  class << self
    def run
      opts = {}
      parser = ARGV.options do
        it.banner = "Usage: #{it.program_name} <command> [options] [file]\n\nCommands: save, log, diff, show, restore"
        it.version = VERSION
        it.on "-m", "--message=MSG", "Save message"
      end.freeze
      parser.permute! into: opts

      case ARGV.shift
      when "save"
        file = detect_or_init ARGV
        save file, opts.fetch(:message) { ARGV.join " " }
      when "log" then log detect(ARGV)
      when "diff" then diff detect(ARGV), Integer(ARGV.shift, exception: false)
      when "show" then show detect(ARGV), Integer(ARGV.fetch(0) { abort "rev required" })
      when "restore" then restore detect(ARGV), Integer(ARGV.fetch(0) { abort "rev required" })
      else abort parser.to_s
      end
    rescue Errno::ENOENT => e
      abort "#{$PROGRAM_NAME}: #{e.message.sub(/.* @ \w+ - /, "not found: ")}"
    end

    private

    def file_dir(file) = "#{DIR}/#{file}"
    def log_path(file) = "#{file_dir file}/log"
    def base_path(file) = "#{file_dir file}/base"
    def snapshot_path(file) = "#{file_dir file}/snapshot"
    def patch_path(file, rev) = "#{file_dir file}/#{rev}.patch"

    def tracked_files
      return [] unless Dir.exist? DIR
      Dir.children(DIR).select { File.directory? "#{DIR}/#{it}" }
    end

    def detect argv
      file = argv.shift if argv.first && !argv.first.start_with?("-") && File.exist?(argv.first.to_s)
      file ||= case tracked_files.size
      when 0 then abort "no tracked files"
      when 1 then tracked_files.first
      else abort "multiple tracked files: #{tracked_files.join ", "}\nspecify one"
      end
      file
    end

    def detect_or_init argv
      file = argv.shift if argv.first && !argv.first.start_with?("-") && File.exist?(argv.first.to_s)
      return file if file

      case tracked_files.size
      when 0 then abort "#{$PROGRAM_NAME}: file required"
      when 1 then tracked_files.first
      else abort "multiple tracked files: #{tracked_files.join ", "}\nspecify one"
      end
    end

    def latest file
      File.readlines(log_path(file)).size
    rescue Errno::ENOENT
      0
    end

    def save file, msg
      dir = file_dir file
      Dir.mkdir DIR unless Dir.exist? DIR
      Dir.mkdir dir unless Dir.exist? dir

      rev = (latest file).succ
      snap = snapshot_path file
      if File.exist? snap
        patch, = Open3.capture2 "diff", "-u", snap, file
        File.write patch_path(file, rev - 1), patch unless patch.empty?
      else
        IO.copy_stream file, base_path(file)
      end
      IO.copy_stream file, snap
      File.open(log_path(file), "a") { it.puts "#{Time.now.strftime "%FT%T"} #{msg}" }
      warn "r#{rev}"
    end

    def reconstruct file, rev
      cur = latest file
      return File.read snapshot_path(file) if rev == cur
      return File.read base_path(file) if rev == 1

      abort "r#{rev} not found" unless rev >= 1 && rev < cur

      Tempfile.create("rev") do |tmp|
        IO.copy_stream base_path(file), tmp.path
        1.upto(rev - 1) do |r|
          p = patch_path file, r
          abort "r#{rev} not found" unless File.exist? p
          system "patch", "-s", tmp.path, p, [:out, :err] => File::NULL
        end
        File.read tmp.path
      end
    end

    def log file
      lp = log_path file
      abort "no history" unless File.exist? lp
      File.foreach(lp).with_index(1) do |l, rev|
        time, msg = l.chomp.split " ", 2
        puts "r#{rev}  #{time}  #{msg}".rstrip
      end
    end

    def diff file, rev = nil
      abort "no history" unless File.exist? log_path(file)
      rev ||= latest file
      if rev == latest(file)
        run_diff snapshot_path(file), file
      else
        content = reconstruct file, rev
        Tempfile.create("rev") do |tmp|
          tmp.write content
          tmp.flush
          run_diff tmp.path, file
        end
      end
    end

    def run_diff a, b
      exec "git", "diff", "--no-index", "--", a, b
    rescue Errno::ENOENT
      exec "diff", "-u", a, b
    end

    def show(file, rev) = print reconstruct(file, rev)

    def restore file, rev
      File.write file, reconstruct(file, rev)
      warn "r#{rev}"
    end
  end
end
