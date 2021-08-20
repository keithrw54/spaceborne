require 'spec_helper'

describe Spaceborne do
  include Spaceborne
  it 'returns a version' do
    expect(Spaceborne::VERSION).to match(/[^.]+\.[^.]+\.[^.]+$/)
  end
  it 'ensure_array_or_hash' do
    expect(ensure_array_or_hash('root', [])).to be nil
    expect(ensure_array_or_hash('root', {})).to be nil
    expect { ensure_array_or_hash('root', 'string') }.to \
      raise_error(RSpec::Expectations::ExpectationNotMetError)
  end
  it 'json detects json headers' do
    expect(json?('Content-Type' => 'application/json')).to eq(true)
    expect(json?('Content-Type' => 'application/text')).to eq(false)
  end
  context 'wrap_request' do
    specify do
      expect do
        wrap_request do
          mock_get('spaceborne_readme_1')
          get '/spaceborne_readme_1', {}
          expect_status(200)
          expect_json(name: 'Alexandra')
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
    specify do
      expect do
        wrap_request do
          mock_get('spaceborne_readme_1', 'Content-Type' => 'application/json')
          get '/spaceborne_readme_1'
          expect_status(200)
          expect_json(name: 'Alexandra')
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
    specify do
      expect do
        wrap_request do
          expect(1).to eq(2)
        end
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
  context 'readme examples' do
    it 'expectations working for first json response' do
      mock_get('spaceborne_readme_1')
      get '/spaceborne_readme_1', {}
      expect_json(name: 'Alex') # exact match because you asked for Alex
      expect_json_types(
        name: :string, address: { street: :string, city: :string,
                                  state: :string,
                                  coordinates: {
                                    latitude: :float,
                                    longitude: :float
                                  } },
        phones: :array_of_objects
      )
      # all the types and structure (cannot go into arrays this way)
      expect_json('address',
                  state: /^[A-Z]{2}$/)
      # ensures address/state has 2 capital letters
      expect_json_types('phones.*', type: :string, number: :string)
      # looks at all elements in array
      expect_json_types('phones.1', type: :string, number: :string)
      # looks at second element in array
      expect_json_keys('address', %i[street city state coordinates])
      # ensure specified keys present
      expect_json_sizes(phones: 2) # expect the phones array size to be 2
    end
    it 'expectations working for second json response' do
      mock_get('spaceborne_readme_2')
      get '/spaceborne_readme_2'
      expect_json_types('array_of_hashes.*.*', first: :string, last: :string)
      expect_json_types('hash_of_hashes.*', first: :string, last: :string)
    end
    it 'optional lowest level array element' do
      mock_get('spaceborne_readme_2')
      get '/spaceborne_readme_2'
      expect_json_types(optional('lowest_array.*.array.*'), present: :string)
    end
    it 'optional highest level array element' do
      mock_get('spaceborne_readme_2')
      get '/spaceborne_readme_2'
      expect_json_types(optional('highest_array.*.array.*'), present: :string)
    end
  end
  it 'header expectations follow spaceborne format' do
    mock_get('spaceborne_readme_2', foo: 'bar')
    get '/spaceborne_readme_2'
    expect_header(foo: 'bar')
    expect_header_types(foo: :string)
  end
  it 'use_proxy' do
    mock_get('spaceborne_readme_2', use_proxy: 'bar')
    get '/spaceborne_readme_2', use_proxy: 'bar'
    expect_header(use_proxy: 'bar')
  end
  it 'nonjson_data' do
    mock_post('spaceborne_readme_2')
    post '/spaceborne_readme_2', { foo: 'bar' }, nonjson_data: true
    expect_header(nonjson_data: nil)
    expect_header('Content-Type' => nil)
  end
  it 'gives information about path on failure' do
    mock_get('simple_path_get')
    get '/simple_path_get'
    expect_json('address', street: 'Area 51', city: 'Roswell', state: 'NM')
  end
end
