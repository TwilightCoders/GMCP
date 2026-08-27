require 'spec_helper'

# config/capabilities.yml is what the host's registration UI reads to decide
# what may be granted. If it drifts from the tools GMCP actually registers, the
# UI offers grants that do nothing or hides ones that matter. These specs make
# that drift impossible to commit.
RSpec.describe 'capability manifest' do
  # Register every tool against a recording double, with all capabilities
  # granted, so `declarations` reflects the full surface.
  let(:declarations) do
    original = ENV.fetch('GMCP_CAPABILITIES', :unset)
    ENV.delete('GMCP_CAPABILITIES')
    GMCP::Capabilities.reset!
    GMCP::ToolHelpers.reset_declarations!

    server = Object.new
    def server.define_tool(**_kwargs, &_block) = nil

    GMCP::Server.send(:register_auth_tool, server)
    GMCP::Gmail::Tools.register(server)
    GMCP::Calendar::Tools.register(server)
    GMCP::Drive::Tools.register(server)
    GMCP::Voice::Tools.register(server)

    GMCP::ToolHelpers.declarations.dup
  ensure
    original == :unset ? ENV.delete('GMCP_CAPABILITIES') : ENV['GMCP_CAPABILITIES'] = original
    GMCP::Capabilities.reset!
  end

  let(:manifest) { GMCP::Capabilities.manifest }

  let(:manifest_pairs) do
    manifest.fetch('capabilities').flat_map { |c| c.fetch('tools').map { |t| [t, c.fetch('name')] } }.to_h
  end

  it 'declares every capability the tools actually claim' do
    claimed = declarations.values.compact.uniq
    expect(claimed - GMCP::Capabilities::ALL).to be_empty,
      "tools claim capabilities absent from the manifest: #{(claimed - GMCP::Capabilities::ALL).inspect}"
  end

  it 'has no capability that no tool claims' do
    claimed = declarations.values.compact.uniq
    expect(GMCP::Capabilities::ALL - claimed).to be_empty,
      "manifest declares capabilities no tool grants: #{(GMCP::Capabilities::ALL - claimed).inspect}"
  end

  it 'lists exactly the tools that exist, with no phantoms' do
    expect(manifest_pairs.keys.sort - declarations.keys.sort).to be_empty,
      'manifest lists tools that are never registered'
  end

  it 'lists every registered tool somewhere' do
    expect(declarations.keys.sort - manifest_pairs.keys.sort).to be_empty,
      'tools are registered but absent from the manifest'
  end

  it 'files each tool under the capability that tool actually declares' do
    mismatched = declarations.filter_map do |tool, capability|
      expected = manifest_pairs[tool]
      next if expected.nil? || expected == capability

      "#{tool}: code says #{capability.inspect}, manifest says #{expected.inspect}"
    end
    expect(mismatched).to be_empty, mismatched.join('; ')
  end

  it 'gives every tool a capability, so nothing registers ungated' do
    ungated = declarations.select { |_, capability| capability.nil? }.keys
    expect(ungated).to be_empty, "tools registered with no capability: #{ungated.inspect}"
  end

  it 'describes every capability, since the text is what a grant UI shows' do
    undescribed = manifest.fetch('capabilities').reject { |c| c['description'].to_s.strip.length > 20 }
    expect(undescribed.map { |c| c['name'] }).to be_empty
  end

  it 'keeps destructive and outbound verbs separate from ordinary modification' do
    expect(manifest_pairs['gmail_trash_message']).to eq('gmail.trash')
    expect(manifest_pairs['gmail_send']).to eq('gmail.send')
    expect(manifest_pairs['calendar_delete_event']).to eq('calendar.delete')
    expect(manifest_pairs['voice_delete']).to eq('voice.trash')
  end

  it 'names the gmail label verb no more broadly than it reaches' do
    # archive! and modify! both post only addLabelIds/removeLabelIds, so the
    # narrow name is the honest one.
    expect(manifest_pairs['gmail_archive_message']).to eq('gmail.modify_labels')
    expect(manifest_pairs['gmail_label_message']).to eq('gmail.modify_labels')
  end
end
