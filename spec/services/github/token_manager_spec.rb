require 'rails_helper'

RSpec.describe Github::TokenManager, type: :service do
  describe '.resolve_env_private_key' do
    around do |example|
      original_file = ENV["AR_GH_APP_PK_FILE"]
      original_b64  = ENV["AR_GH_APP_PK_BASE64"]
      original_raw  = ENV["AR_GH_APP_PK"]
      ENV.delete("AR_GH_APP_PK_FILE")
      ENV.delete("AR_GH_APP_PK_BASE64")
      ENV.delete("AR_GH_APP_PK")
      example.run
    ensure
      ENV["AR_GH_APP_PK_FILE"]   = original_file
      ENV["AR_GH_APP_PK_BASE64"] = original_b64
      ENV["AR_GH_APP_PK"]        = original_raw
    end

    it 'returns nil when no env vars are set' do
      expect(described_class.resolve_env_private_key).to be_nil
    end

    it 'reads from AR_GH_APP_PK_FILE when file exists' do
      Tempfile.create('test_pk') do |f|
        f.write("-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----\n")
        f.flush
        ENV["AR_GH_APP_PK_FILE"] = f.path
        result = described_class.resolve_env_private_key
        expect(result).to include("BEGIN RSA PRIVATE KEY")
      end
    end

    it 'decodes AR_GH_APP_PK_BASE64 when set' do
      pem = "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----\n"
      ENV["AR_GH_APP_PK_BASE64"] = Base64.encode64(pem)
      expect(described_class.resolve_env_private_key).to eq(pem)
    end

    it 'uses AR_GH_APP_PK raw with newline unescaping' do
      ENV["AR_GH_APP_PK"] = '-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----\n'
      result = described_class.resolve_env_private_key
      expect(result).to include("-----BEGIN RSA PRIVATE KEY-----\ntest\n")
    end

    it 'prefers FILE over BASE64' do
      Tempfile.create('test_pk') do |f|
        f.write("FROM_FILE")
        f.flush
        ENV["AR_GH_APP_PK_FILE"] = f.path
        ENV["AR_GH_APP_PK_BASE64"] = Base64.encode64("FROM_BASE64")
        expect(described_class.resolve_env_private_key).to eq("FROM_FILE")
      end
    end

    it 'prefers BASE64 over raw PK' do
      pem = "FROM_BASE64"
      ENV["AR_GH_APP_PK_BASE64"] = Base64.encode64(pem)
      ENV["AR_GH_APP_PK"] = "FROM_RAW"
      expect(described_class.resolve_env_private_key).to eq(pem)
    end
  end

  describe '#get_token' do
    it 'returns project PAT when available' do
      tm = described_class.new(
        project_pat: "ghp_test123",
        installation_id: nil,
        env_pat: nil,
        project_app_id: nil,
        project_app_pk: nil,
        env_app_id: nil,
        env_app_pk: nil
      )
      expect(tm.get_token).to eq("ghp_test123")
    end

    it 'falls back to env PAT when no installation token' do
      tm = described_class.new(
        project_pat: nil,
        installation_id: nil,
        env_pat: "ghp_env_token",
        project_app_id: nil,
        project_app_pk: nil,
        env_app_id: nil,
        env_app_pk: nil
      )
      expect(tm.get_token).to eq("ghp_env_token")
    end

    it 'returns nil when nothing configured' do
      tm = described_class.new(
        project_pat: nil,
        installation_id: nil,
        env_pat: nil,
        project_app_id: nil,
        project_app_pk: nil,
        env_app_id: nil,
        env_app_pk: nil
      )
      expect(tm.get_token).to be_nil
    end
  end

  describe '#configured?' do
    it 'returns true with project PAT' do
      tm = described_class.new(
        project_pat: "ghp_test", installation_id: nil, env_pat: nil,
        project_app_id: nil, project_app_pk: nil, env_app_id: nil, env_app_pk: nil
      )
      expect(tm.configured?).to be true
    end

    it 'returns true with installation ID' do
      tm = described_class.new(
        project_pat: nil, installation_id: "12345", env_pat: nil,
        project_app_id: nil, project_app_pk: nil, env_app_id: nil, env_app_pk: nil
      )
      expect(tm.configured?).to be true
    end

    it 'returns false with nothing' do
      tm = described_class.new(
        project_pat: nil, installation_id: nil, env_pat: nil,
        project_app_id: nil, project_app_pk: nil, env_app_id: nil, env_app_pk: nil
      )
      expect(tm.configured?).to be false
    end
  end
end
