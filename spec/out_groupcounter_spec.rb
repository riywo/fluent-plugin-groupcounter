# encoding: UTF-8
require_relative 'spec_helper'

class Fluent::Test::OutputTestDriver
  def emit_with_tag(record, time=Time.now, tag = nil)
    @tag = tag if tag
    emit(record, time)
  end
end

describe Fluent::GroupCounterOutput do
  before { Fluent::Test.setup }
  CONFIG = %[
    count_interval 5s
    aggragate tag
    output_per_tag true
    tag_prefix count
    group_by_keys code,method,path
  ]

  let(:tag) { 'test' }
  let(:driver) { Fluent::Test::OutputTestDriver.new(Fluent::GroupCounterOutput, tag).configure(config) }

  describe 'test configure' do
    describe 'bad configuration' do
      context 'test empty configuration' do
        let(:config) { %[] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end
    end

    describe 'good configuration' do
      subject { driver.instance }

      context "test least configuration" do
        let(:config) { %[group_by_keys foo] }
        its(:count_interval) { should == 60 }
        its(:unit) { should == 'minute' }
        its(:output_per_tag) { should == false }
        its(:aggregate) { should == :tag }
        its(:tag) { should == 'groupcount' }
        its(:tag_prefix) { should be_nil }
        its(:input_tag_remove_prefix) { should be_nil }
        its(:group_by_keys) { should == %w[foo] }
      end

      context "test template configuration" do
        let(:config) { CONFIG }
        its(:count_interval) { should == 5 }
        its(:unit) { should == 'minute' }
        its(:output_per_tag) { should == true }
        its(:aggregate) { should == :tag }
        its(:tag) { should == 'groupcount' }
        its(:tag_prefix) { should == 'count' }
        its(:input_tag_remove_prefix) { should be_nil }
        its(:group_by_keys) { should == %w[code method path] }
      end
    end
  end

  describe 'test emit' do
    let(:time) { Time.now.to_i }
    let(:emit) do
      driver.run { messages.each {|message| driver.emit(message, time) } }
      driver.instance.flush_emit
    end

    let(:messages) do
      [
        {"code" => 200, "method" => "GET",  "path" => "/ping", "reqtime" => "0.000" },
        {"code" => 200, "method" => "POST", "path" => "/auth", "reqtime" => "1.001" },
        {"code" => 200, "method" => "GET",  "path" => "/ping", "reqtime" => "2.002" },
        {"code" => 400, "method" => "GET",  "path" => "/ping", "reqtime" => "3.003" },
      ]
    end
    let(:expected) do
      {
        "200_GET_/ping_count"=>2,
        "200_POST_/auth_count"=>1,
        "400_GET_/ping_count"=>1,
      }
    end
    let(:expected_with_tag) do
      Hash[*(expected.map {|key, val| next ["test_#{key}", val] }.flatten)] 
    end

    context 'default' do
      let(:config) { CONFIG }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'max_key' do
      let(:config) { CONFIG + %[max_key reqtime] }
      let(:expected) do
        {
          "200_GET_/ping_count"=>2, "200_GET_/ping_max"=>2.002,
          "200_POST_/auth_count"=>1, "200_POST_/auth_max"=>1.001,
          "400_GET_/ping_count"=>1, "400_GET_/ping_max"=>3.003,
        }
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'min_key' do
      let(:config) { CONFIG + %[min_key reqtime] }
      let(:expected) do
        {
          "200_GET_/ping_count"=>2, "200_GET_/ping_min"=>0.000,
          "200_POST_/auth_count"=>1, "200_POST_/auth_min"=>1.001,
          "400_GET_/ping_count"=>1, "400_GET_/ping_min"=>3.003,
        }
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'avg_key' do
      let(:config) { CONFIG + %[avg_key reqtime] }
      let(:expected) do
        {
          "200_GET_/ping_count"=>2, "200_GET_/ping_avg"=>1.001,
          "200_POST_/auth_count"=>1, "200_POST_/auth_avg"=>1.001,
          "400_GET_/ping_count"=>1, "400_GET_/ping_avg"=>3.003,
        }
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'tag' do
      context 'not effective if output_per_tag true' do
        let(:config) do
          CONFIG + %[
          output_per_tag true
          tag foo
          ]
        end
        before do
          Fluent::Engine.stub(:now).and_return(time)
          Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'effective if output_per_tag false' do
        let(:config) do
          CONFIG + %[
          output_per_tag false
          tag foo
          ]
        end
        before do
          Fluent::Engine.stub(:now).and_return(time)
          Fluent::Engine.should_receive(:emit).with("foo", time, expected_with_tag)
        end
        it { emit }
      end
    end

    context 'tag_prefix' do
      let(:config) do
        CONFIG + %[
          tag_prefix foo
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'aggregate all' do
      let(:emit) do
        driver.run { messages.each {|message| driver.emit_with_tag(message, time, 'foo.bar') } }
        driver.run { messages.each {|message| driver.emit_with_tag(message, time, 'foo.bar2') } }
        driver.instance.flush_emit
      end

      let(:config) do
        CONFIG + %[
          aggregate all
          tag_prefix count
        ]
      end

      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.all", time, {
          "200_GET_/ping_count"=>4, "200_POST_/auth_count"=>2, "400_GET_/ping_count"=>2
        })
      end
      it { emit }
    end

    context "store_file" do
      let(:store_file) do
        dirname = "tmp"
        Dir.mkdir dirname unless Dir.exist? dirname
        filename = "#{dirname}/test.dat"
        File.unlink filename if File.exist? filename
        filename
      end

      let(:config) do
        CONFIG + %[
          store_file #{store_file}
          ]
      end

      it 'stored_data and loaded_data should equal' do
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        driver.instance.shutdown
        stored_counts = driver.instance.counts
        stored_saved_at = driver.instance.saved_at
        stored_saved_duration = driver.instance.saved_duration
        driver.instance.counts = {}
        driver.instance.saved_at = nil
        driver.instance.saved_duration = nil

        driver.instance.start
        loaded_counts = driver.instance.counts
        loaded_saved_at = driver.instance.saved_at
        loaded_saved_duration = driver.instance.saved_duration

        loaded_counts.should == stored_counts
        loaded_saved_at.should == stored_saved_at
        loaded_saved_duration.should == stored_saved_duration
      end
    end

    context 'group_by_expression' do
      let(:config) { CONFIG + %[group_by_expression ${method}_${path.split("?")[0].split("/")[2]}/${code[0]}xx] }
      let(:messages) do
        [
          {"code" => "200", "method" => "GET",  "path" => "/api/people/@me/@self?count=1", "reqtime" => 0.000 },
          {"code" => "200", "method" => "POST", "path" => "/api/ngword?_method=check", "reqtime" => 1.001 },
          {"code" => "400", "method" => "GET",  "path" => "/api/messages/@me/@outbox", "reqtime" => 2.002 },
          {"code" => "201", "method" => "GET",  "path" => "/api/people/@me/@self", "reqtime" => 3.003 },
        ]
      end
      let(:expected) do
        {
          "GET_people/2xx_count"=>2,
          "POST_ngword/2xx_count"=>1,
          "GET_messages/4xx_count"=>1,
        }
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

  end
end



