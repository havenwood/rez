require_relative "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

class RevTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @bin = File.expand_path "../bin/rev", __dir__
    @cwd = Dir.pwd
    Dir.chdir @dir
  end

  def teardown
    Dir.chdir @cwd
    FileUtils.rm_rf @dir
  end

  def rev *args
    Open3.capture3 @bin, *args
  end

  def write_file(name = "hello.rb", content = "def hello\n  puts \"hello\"\nend\n")
    File.write name, content
  end

  def save_file(content = nil, msg = "snapshot", name = "hello.rb")
    content ? write_file(name, content) : (write_file(name) unless File.exist? name)
    if File.exist? ".rev/#{name}"
      rev "save", msg
    else
      rev "save", name, msg
    end
  end

  # -- save --

  def test_first_save
    write_file
    _, err, status = rev "save", "hello.rb", "initial"

    assert_predicate status, :success?
    assert_equal "r1\n", err
    assert_path_exists ".rev/hello.rb/log"
    assert_path_exists ".rev/hello.rb/base"
    assert_path_exists ".rev/hello.rb/snapshot"
    assert_equal File.read("hello.rb"), File.read(".rev/hello.rb/base")
    assert_equal File.read("hello.rb"), File.read(".rev/hello.rb/snapshot")
  end

  def test_first_save_no_patch
    write_file
    rev "save", "hello.rb", "initial"

    refute_path_exists ".rev/hello.rb/0.patch"
    refute_path_exists ".rev/hello.rb/1.patch"
  end

  def test_second_save_creates_patch
    save_file
    write_file "hello.rb", "def hello\n  puts \"hello world\"\nend\n"
    _, err, = rev "save", "second"

    assert_equal "r2\n", err
    assert_path_exists ".rev/hello.rb/1.patch"
    assert_equal File.read("hello.rb"), File.read(".rev/hello.rb/snapshot")
  end

  def test_base_unchanged_after_saves
    save_file "original\n"
    base = File.read ".rev/hello.rb/base"
    save_file "changed\n"
    save_file "changed again\n"

    assert_equal base, File.read(".rev/hello.rb/base")
  end

  def test_save_without_file_after_init
    save_file
    _, err, status = rev "save", "again"

    assert_predicate status, :success?
    assert_equal "r2\n", err
  end

  def test_save_without_file_before_init
    write_file
    _, err, status = rev "save"

    refute_predicate status, :success?
    assert_match(/file required/, err)
  end

  def test_save_with_m_flag
    write_file
    rev "save", "hello.rb", "-m", "flagged message"
    out, = rev "log"

    assert_match(/flagged message/, out)
  end

  def test_save_empty_message
    save_file nil, ""
    log_line = File.read(".rev/hello.rb/log").chomp

    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} ?\z/, log_line)
  end

  def test_save_message_with_spaces
    write_file
    rev "save", "hello.rb", "-m", "multi word message"
    log_line = File.read(".rev/hello.rb/log").chomp
    _, msg = log_line.split " ", 2

    assert_equal "multi word message", msg
  end

  # -- log --

  def test_log
    save_file nil, "first"
    rev "save", "second"
    out, _, status = rev "log"

    assert_predicate status, :success?
    lines = out.lines
    assert_equal 2, lines.size
    assert_match(/\Ar1 .+ first\n\z/, lines.first)
    assert_match(/\Ar2 .+ second\n\z/, lines.last)
  end

  def test_log_no_history
    _, _, status = rev "log"

    refute_predicate status, :success?
  end

  # -- diff --

  def test_diff_against_older_rev
    save_file
    write_file "hello.rb", "def hello\n  puts \"hello world\"\nend\n"
    out, _, status = rev "diff", "1"

    assert_equal 1, status.exitstatus
    assert_match(/-  puts "hello"/, out)
    assert_match(/\+  puts "hello world"/, out)
  end

  def test_diff_no_arg_uses_latest
    save_file
    out, = rev "diff"

    assert_empty out
  end

  def test_diff_no_arg_with_changes
    save_file
    write_file "hello.rb", "changed\n"
    out, _, status = rev "diff"

    assert_equal 1, status.exitstatus
    refute_empty out
  end

  def test_diff_no_history
    _, _, status = rev "diff"

    refute_predicate status, :success?
  end

  # -- show --

  def test_show_latest
    save_file "latest content\n"
    out, _, status = rev "show", "1"

    assert_predicate status, :success?
    assert_equal "latest content\n", out
  end

  def test_show_first_revision
    save_file "version one\n", "first"
    save_file "version two\n", "second"
    save_file "version three\n", "third"
    out, = rev "show", "1"

    assert_equal "version one\n", out
  end

  def test_show_middle_revision
    save_file "version one\n", "first"
    save_file "version two\n", "second"
    save_file "version three\n", "third"
    out, = rev "show", "2"

    assert_equal "version two\n", out
  end

  def test_show_missing_rev_arg
    save_file
    _, err, status = rev "show"

    refute_predicate status, :success?
    assert_match(/rev required/, err)
  end

  def test_show_nonexistent_rev
    save_file
    _, _, status = rev "show", "99"

    refute_predicate status, :success?
  end

  # -- restore --

  def test_restore
    save_file
    write_file "hello.rb", "changed\n"
    _, err, status = rev "restore", "1"

    assert_predicate status, :success?
    assert_equal "r1\n", err
    assert_equal "def hello\n  puts \"hello\"\nend\n", File.read("hello.rb")
  end

  def test_restore_middle_revision
    save_file "v1\n", "first"
    save_file "v2\n", "second"
    save_file "v3\n", "third"
    rev "restore", "2"

    assert_equal "v2\n", File.read("hello.rb")
  end

  def test_restore_missing_rev_arg
    save_file
    _, err, status = rev "restore"

    refute_predicate status, :success?
    assert_match(/rev required/, err)
  end

  def test_restore_round_trip
    save_file "original\n", "first"
    save_file "modified\n", "second"
    rev "restore", "1"

    assert_equal "original\n", File.read("hello.rb")

    rev "save", "restored"
    out, = rev "show", "3"

    assert_equal "original\n", out
  end

  def test_restore_then_show_all
    save_file "v1\n", "first"
    save_file "v2\n", "second"
    save_file "v3\n", "third"
    rev "restore", "1"
    rev "save", "rollback"

    out1, = rev "show", "1"
    out2, = rev "show", "2"
    out3, = rev "show", "3"
    out4, = rev "show", "4"

    assert_equal "v1\n", out1
    assert_equal "v2\n", out2
    assert_equal "v3\n", out3
    assert_equal "v1\n", out4
  end

  # -- multiple files --

  def test_two_files_independent
    write_file "foo.rb", "foo v1\n"
    write_file "bar.rb", "bar v1\n"
    rev "save", "foo.rb", "foo first"
    rev "save", "bar.rb", "bar first"

    write_file "foo.rb", "foo v2\n"
    rev "save", "foo.rb", "foo second"

    out, = rev "show", "foo.rb", "1"
    assert_equal "foo v1\n", out

    out, = rev "show", "bar.rb", "1"
    assert_equal "bar v1\n", out

    out, = rev "show", "foo.rb", "2"
    assert_equal "foo v2\n", out
  end

  def test_two_files_log_independent
    write_file "foo.rb", "foo\n"
    write_file "bar.rb", "bar\n"
    rev "save", "foo.rb", "foo msg"
    rev "save", "bar.rb", "bar msg"

    out, = rev "log", "foo.rb"
    assert_match(/foo msg/, out)
    refute_match(/bar msg/, out)
  end

  def test_auto_detect_single_tracked
    save_file "content\n"
    out, = rev "log"

    assert_match(/r1/, out)
  end

  def test_auto_detect_multiple_tracked_errors
    write_file "foo.rb", "foo\n"
    write_file "bar.rb", "bar\n"
    rev "save", "foo.rb", "first"
    rev "save", "bar.rb", "first"
    _, err, status = rev "log"

    refute_predicate status, :success?
    assert_match(/multiple/, err)
  end

  def test_explicit_file_with_multiple_tracked
    write_file "foo.rb", "foo\n"
    write_file "bar.rb", "bar\n"
    rev "save", "foo.rb", "first"
    rev "save", "bar.rb", "first"
    out, _, status = rev "log", "foo.rb"

    assert_predicate status, :success?
    assert_match(/r1/, out)
  end

  # -- storage format --

  def test_storage_namespaced
    write_file
    rev "save", "hello.rb", "initial"

    assert_path_exists ".rev/hello.rb"
    assert_path_exists ".rev/hello.rb/log"
    assert_path_exists ".rev/hello.rb/base"
    assert_path_exists ".rev/hello.rb/snapshot"
  end

  def test_patch_is_forward_diff
    save_file "old line\n", "first"
    save_file "new line\n", "second"

    patch = File.read ".rev/hello.rb/1.patch"
    assert_match(/^-old line$/, patch)
    assert_match(/^\+new line$/, patch)
  end

  def test_snapshot_always_latest
    save_file "v1\n", "first"
    save_file "v2\n", "second"
    save_file "v3\n", "third"

    assert_equal "v3\n", File.read(".rev/hello.rb/snapshot")
  end

  def test_no_patch_when_unchanged
    save_file "same\n", "first"
    save_file "same\n", "no change"

    refute_path_exists ".rev/hello.rb/1.patch"
  end

  # -- flags --

  def test_version
    out, = rev "--version"

    assert_match(/\Arev\S* \d+\.\d+\.\d+\n\z/, out)
  end

  def test_help
    out, = rev "--help"

    assert_match(/Usage/, out)
    assert_match(/save/, out)
  end

  def test_unknown_command
    _, err, status = rev "nope"

    refute_predicate status, :success?
    assert_match(/Usage/, err)
  end
end
