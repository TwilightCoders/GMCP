# frozen_string_literal: true

require 'spec_helper'

describe GMCP do
  it 'has a version number' do
    expect(GMCP::VERSION).not_to be nil
    expect(GMCP::VERSION).to be_a(String)
    expect(GMCP::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  it 'has a root method that returns the gem root' do
    root = GMCP.root
    expect(root).to be_a(Pathname)
    expect(File.exist?(File.join(root, 'lib', 'gmcp.rb'))).to be true
  end
end
