require_relative "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

class RezTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @bin = File.expand_path "../bin/rez", __dir__
    @cwd = Dir.pwd
    Dir.chdir @dir
  end

  def teardown
    Dir.chdir @cwd
    FileUtils.rm_rf @dir
  end

  def rez(*args)
    Open3.capture3 @bin, *args
  end

  def write_file(name = "hello.rb", content = "def hello\n  puts \"hello\"\nend\n")
    File.write name, content
  end

  def save_file(content = nil, msg = "snapshot", name = "hello.rb")
    content ? write_file(name, content) : (write_file(name) unless File.exist? name)
    if File.exist? ".rez/#{name}"
      rez "save", msg
    else
      rez "save", name, msg
    end
  end

  # -- save --

  def test_first_save
    write_file
    _, err, status = rez "save", "hello.rb", "initial"

    assert_predicate status, :success?
    assert_equal "r1\n", err
    assert_path_exists ".rez/hello.rb/log"
    assert_path_exists ".rez/hello.rb/base"
    assert_path_exists ".rez/hello.rb/snapshot"
    assert_equal File.read("hello.rb"), File.read(".rez/hello.rb/base")
    assert_equal File.read("hello.rb"), File.read(".rez/hello.rb/snapshot")
  end

  def test_first_save_no_patch
    write_file
    rez "save", "hello.rb", "initial"

    refute_path_exists ".rez/hello.rb/0.patch"
    refute_path_exists ".rez/hello.rb/1.patch"
  end

  def test_second_save_creates_patch
    save_file
    write_file "hello.rb", "def hello\n  puts \"hello world\"\nend\n"
    _, err, = rez "save", "second"

    assert_equal "r2\n", err
    assert_path_exists ".rez/hello.rb/1.patch"
    assert_equal File.read("hello.rb"), File.read(".rez/hello.rb/snapshot")
  end

  def test_base_unchanged_after_saves
    save_file "original\n"
    base = File.read ".rez/hello.rb/base"
    save_file "changed\n"
    save_file "changed again\n"

    assert_equal base, File.read(".rez/hello.rb/base")
  end

  def test_save_without_file_after_init
    save_file
    _, err, status = rez "save", "again"

    assert_predicate status, :success?
    assert_equal "r2\n", err
  end

  def test_save_without_file_before_init
    write_file
    _, err, status = rez "save"

    refute_predicate status, :success?
    assert_match(/file required/, err)
  end

  def test_save_with_m_flag
    write_file
    rez "save", "hello.rb", "-m", "flagged message"
    out, = rez "log"

    assert_match(/flagged message/, out)
  end

  def test_save_empty_message
    save_file nil, ""
    log_line = File.read(".rez/hello.rb/log").chomp

    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} ?\z/, log_line)
  end

  def test_save_message_with_spaces
    write_file
    rez "save", "hello.rb", "-m", "multi word message"
    log_line = File.read(".rez/hello.rb/log").chomp
    _, msg = log_line.split " ", 2

    assert_equal "multi word message", msg
  end

  # -- log --

  def test_log
    save_file nil, "first"
    rez "save", "second"
    out, _, status = rez "log"

    assert_predicate status, :success?
    lines = out.lines
    assert_equal 2, lines.size
    assert_match(/\Ar1 .+ first\n\z/, lines.first)
    assert_match(/\Ar2 .+ second\n\z/, lines.last)
  end

  def test_log_no_history
    _, _, status = rez "log"

    refute_predicate status, :success?
  end

  # -- diff --

  def test_diff_against_older_rev
    save_file
    write_file "hello.rb", "def hello\n  puts \"hello world\"\nend\n"
    out, _, status = rez "diff", "1"

    assert_equal 1, status.exitstatus
    assert_match(/-  puts "hello"/, out)
    assert_match(/\+  puts "hello world"/, out)
  end

  def test_diff_no_arg_uses_latest
    save_file
    out, = rez "diff"

    assert_empty out
  end

  def test_diff_no_arg_with_changes
    save_file
    write_file "hello.rb", "changed\n"
    out, _, status = rez "diff"

    assert_equal 1, status.exitstatus
    refute_empty out
  end

  def test_diff_no_history
    _, _, status = rez "diff"

    refute_predicate status, :success?
  end

  # -- show --

  def test_show_latest
    save_file "latest content\n"
    out, _, status = rez "show", "1"

    assert_predicate status, :success?
    assert_equal "latest content\n", out
  end

  def test_show_first_revision
    save_file "version one\n", "first"
    save_file "version two\n", "second"
    save_file "version three\n", "third"
    out, = rez "show", "1"

    assert_equal "version one\n", out
  end

  def test_show_middle_revision
    save_file "version one\n", "first"
    save_file "version two\n", "second"
    save_file "version three\n", "third"
    out, = rez "show", "2"

    assert_equal "version two\n", out
  end

  def test_show_missing_rev_arg
    save_file
    _, err, status = rez "show"

    refute_predicate status, :success?
    assert_match(/rev required/, err)
  end

  def test_show_nonexistent_rev
    save_file
    _, _, status = rez "show", "99"

    refute_predicate status, :success?
  end

  # -- restore --

  def test_restore
    save_file
    write_file "hello.rb", "changed\n"
    _, err, status = rez "restore", "1"

    assert_predicate status, :success?
    assert_equal "r1\n", err
    assert_equal "def hello\n  puts \"hello\"\nend\n", File.read("hello.rb")
  end

  def test_restore_middle_revision
    save_file "v1\n", "first"
    save_file "v2\n", "second"
    save_file "v3\n", "third"
    rez "restore", "2"

    assert_equal "v2\n", File.read("hello.rb")
  end

  def test_restore_missing_rev_arg
    save_file
    _, err, status = rez "restore"

    refute_predicate status, :success?
    assert_match(/rev required/, err)
  end

  def test_restore_round_trip
    save_file "original\n", "first"
    save_file "modified\n", "second"
    rez "restore", "1"

    assert_equal "original\n", File.read("hello.rb")

    rez "save", "restored"
    out, = rez "show", "3"

    assert_equal "original\n", out
  end

  def test_restore_then_show_all
    save_file "v1\n", "first"
    save_file "v2\n", "second"
    save_file "v3\n", "third"
    rez "restore", "1"
    rez "save", "rollback"

    out1, = rez "show", "1"
    out2, = rez "show", "2"
    out3, = rez "show", "3"
    out4, = rez "show", "4"

    assert_equal "v1\n", out1
    assert_equal "v2\n", out2
    assert_equal "v3\n", out3
    assert_equal "v1\n", out4
  end

  # -- multiple files --

  def test_two_files_independent
    write_file "foo.rb", "foo v1\n"
    write_file "bar.rb", "bar v1\n"
    rez "save", "foo.rb", "foo first"
    rez "save", "bar.rb", "bar first"

    write_file "foo.rb", "foo v2\n"
    rez "save", "foo.rb", "foo second"

    out, = rez "show", "foo.rb", "1"
    assert_equal "foo v1\n", out

    out, = rez "show", "bar.rb", "1"
    assert_equal "bar v1\n", out

    out, = rez "show", "foo.rb", "2"
    assert_equal "foo v2\n", out
  end

  def test_two_files_log_independent
    write_file "foo.rb", "foo\n"
    write_file "bar.rb", "bar\n"
    rez "save", "foo.rb", "foo msg"
    rez "save", "bar.rb", "bar msg"

    out, = rez "log", "foo.rb"
    assert_match(/foo msg/, out)
    refute_match(/bar msg/, out)
  end

  def test_auto_detect_single_tracked
    save_file "content\n"
    out, = rez "log"

    assert_match(/r1/, out)
  end

  def test_auto_detect_multiple_tracked_errors
    write_file "foo.rb", "foo\n"
    write_file "bar.rb", "bar\n"
    rez "save", "foo.rb", "first"
    rez "save", "bar.rb", "first"
    _, err, status = rez "log"

    refute_predicate status, :success?
    assert_match(/multiple/, err)
  end

  def test_explicit_file_with_multiple_tracked
    write_file "foo.rb", "foo\n"
    write_file "bar.rb", "bar\n"
    rez "save", "foo.rb", "first"
    rez "save", "bar.rb", "first"
    out, _, status = rez "log", "foo.rb"

    assert_predicate status, :success?
    assert_match(/r1/, out)
  end

  # -- storage format --

  def test_storage_namespaced
    write_file
    rez "save", "hello.rb", "initial"

    assert_path_exists ".rez/hello.rb"
    assert_path_exists ".rez/hello.rb/log"
    assert_path_exists ".rez/hello.rb/base"
    assert_path_exists ".rez/hello.rb/snapshot"
  end

  def test_patch_is_forward_diff
    save_file "old line\n", "first"
    save_file "new line\n", "second"

    patch = File.read ".rez/hello.rb/1.patch"
    assert_match(/^-old line$/, patch)
    assert_match(/^\+new line$/, patch)
  end

  def test_snapshot_always_latest
    save_file "v1\n", "first"
    save_file "v2\n", "second"
    save_file "v3\n", "third"

    assert_equal "v3\n", File.read(".rez/hello.rb/snapshot")
  end

  def test_no_patch_when_unchanged
    save_file "same\n", "first"
    save_file "same\n", "no change"

    refute_path_exists ".rez/hello.rb/1.patch"
  end

  # -- flags --

  def test_version
    out, = rez "--version"

    assert_match(/\Arez\S* \d+\.\d+\.\d+\n\z/, out)
  end

  def test_help
    out, = rez "--help"

    assert_match(/Usage/, out)
    assert_match(/save/, out)
  end

  def test_unknown_command
    _, err, status = rez "nope"

    refute_predicate status, :success?
    assert_match(/Usage/, err)
  end
end
