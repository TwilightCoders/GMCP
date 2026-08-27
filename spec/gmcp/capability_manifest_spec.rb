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

  let(:connectors) { manifest.fetch('connectors') }

  let(:manifest_pairs) do
    connectors
      .flat_map { |c| c.fetch('capabilities') }
      .flat_map { |cap| cap.fetch('tools').map { |t| [t, cap.fetch('name')] } }
      .to_h
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
    undescribed = connectors.flat_map { |c| c.fetch('capabilities') }
                             .reject { |c| c['description'].to_s.strip.length > 20 }
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

  describe 'connector declarations' do
    it 'gives every connector an account_scoping from the allowed set' do
      connectors.each do |c|
        expect(GMCP::Capabilities::ACCOUNT_SCOPING).to include(c['account_scoping']),
          "#{c['name']} declares account_scoping #{c['account_scoping'].inspect}"
      end
    end

    it 'gives every connector a credential_source from the §3 vocabulary' do
      connectors.each do |c|
        expect(GMCP::Capabilities::CREDENTIAL_SOURCES).to include(c['credential_source']),
          "#{c['name']} declares credential_source #{c['credential_source'].inspect}"
      end
    end

    it 'declares every capability under exactly one connector' do
      names = connectors.flat_map { |c| c.fetch('capabilities').map { |x| x.fetch('name') } }
      expect(names).to eq(names.uniq)
    end

    # The safety property of the grant model is that connector_account always
    # constrains. Voice violates it — its principal is whichever Google account
    # Safari holds, resolved outside GMCP — so it must SAY so in a field a
    # registration UI can read, not in a comment a UI cannot.
    it 'marks Voice as ignoring account scoping' do
      voice = connectors.find { |c| c['name'] == 'voice' }
      expect(voice.fetch('account_scoping')).to eq('ignored')
      expect(voice.fetch('credential_source')).to eq('delegated')
    end

    it 'marks every locally-held-credential connector as enforcing account scoping' do
      oauth = connectors.select { |c| c['credential_source'] == 'local_file' }
      expect(oauth.map { |c| c['name'] }).to contain_exactly('gmcp', 'gmail', 'google_calendar', 'drive')
      expect(oauth.map { |c| c['account_scoping'] }.uniq).to eq(['enforced'])
    end

    it 'reports scoping for every declared capability, so no grant is unclassified' do
      GMCP::Capabilities::ALL.each do |cap|
        expect(GMCP::Capabilities.account_scoping_for(cap)).not_to be_nil, "#{cap} has no connector"
      end
    end

    it 'surfaces exactly the voice capabilities as unscoped grants' do
      original = ENV.fetch('GMCP_CAPABILITIES', :unset)
      ENV['GMCP_CAPABILITIES'] = 'gmail.read,voice.read,voice.trash'
      GMCP::Capabilities.reset!
      expect(GMCP::Capabilities.unscoped_grants).to contain_exactly('voice.read', 'voice.trash')
    ensure
      original == :unset ? ENV.delete('GMCP_CAPABILITIES') : ENV['GMCP_CAPABILITIES'] = original
      GMCP::Capabilities.reset!
    end

    it 'explains any connector that ignores account scoping, since a UI must render it differently' do
      connectors.select { |c| c['account_scoping'] == 'ignored' }.each do |c|
        expect(c['description'].to_s.length).to be > 100,
          "#{c['name']} ignores account scoping but does not explain what it reaches instead"
      end
    end
  end
end
