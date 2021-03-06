# frozen_string_literal: true

require_relative '../lib/cartocss_helper.rb'
require 'spec_helper'

describe SystemHelper do
  it "should return output" do
    expect(SystemHelper.execute_command("echo test")).to eq "test\n"
  end
  it "raise FailedCommandException gives exception" do
    expect { raise FailedCommandException, "describe" }.to raise_error FailedCommandException
  end
  it "raise FailedCommandException gives exception" do
    expect { raise FailedCommandException, "message" }.to raise_error(FailedCommandException, "message")
  end
  it "should raise exception on stderr" do
    expect { SystemHelper.execute_command(">&2 echo error") }.to raise_error FailedCommandException
  end
  it "should raise exception on an error code" do
    expect { SystemHelper.execute_command("exit 180") }.to raise_error FailedCommandException
  end
  it "should not raise exception on an ignored error code" do
    expect(SystemHelper.execute_command("exit 180", allowed_return_codes: [180])).to eq ""
  end
  it "should raise exception on not ignored error code" do
    expect { SystemHelper.execute_command("exit 1", allowed_return_codes: [180]) }.to raise_error FailedCommandException
  end
  it "should not raise exception on a success code" do
    expect(SystemHelper.execute_command("exit 0")).to eq ""
  end
  it "should not raise exception on ignored stderr" do
    expect(SystemHelper.execute_command(">&2 echo error", ignore_stderr_presence: true)).to eq "error\n"
  end
end
