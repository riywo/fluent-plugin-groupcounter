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
        its(:count_interval) { should be_nil }
        its(:unit) { should == 'minute' }
        its(:output_per_tag) { should == false }
        its(:aggregate) { should == :tag }
        its(:tag) { should == 'groupcount' }
        its(:tag_prefix) { should be_nil }
        its(:input_tag_remove_prefix) { should be_nil }
        its(:group_by_keys) { should == %w[foo] }
        its(:output_messages) { should == false }
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
        its(:output_messages) { should == false }
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
        {"code" => 200, "method" => "GET", "path" => "/ping"},
        {"code" => 200, "method" => "POST", "path" => "/auth"},
        {"code" => 200, "method" => "GET", "path" => "/ping"},
        {"code" => 400, "method" => "GET", "path" => "/ping"},
      ]
    end
    let(:expected) do
      {
        "200_GET_/ping_count"=>2, "200_GET_/ping_rate"=>2.0, "200_GET_/ping_percentage"=>50.0,
        "200_POST_/auth_count"=>1, "200_POST_/auth_rate"=>1.0, "200_POST_/auth_percentage"=>25.0,
        "400_GET_/ping_count"=>1, "400_GET_/ping_rate"=>1.0, "400_GET_/ping_percentage"=>25.0
      }
    end
    let(:expected_with_tag) do
      Hash[*(expected.map {|key, val| next ["test_#{key}", val] }.flatten)] 
    end

    context 'count_interval' do
      pending
    end

    context 'default' do
      let(:config) { CONFIG }
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
        Fluent::Engine.should_receive(:emit).with("count.all", time, {"200_GET_/ping_count"=>4, "200_GET_/ping_rate"=>4.0, "200_GET_/ping_percentage"=>50.0, "200_POST_/auth_count"=>2, "200_POST_/auth_rate"=>2.0, "200_POST_/auth_percentage"=>25.0, "400_GET_/ping_count"=>2, "400_GET_/ping_rate"=>2.0, "400_GET_/ping_percentage"=>25.0})
      end
      it { emit }
    end
  end
end



