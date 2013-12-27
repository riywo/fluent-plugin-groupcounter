class Fluent::GroupCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('groupcounter', self)

  PATTERN_MAX_NUM = 20

  def initialize
    super
    require 'pathname'
  end

  config_param :count_interval, :time, :default => nil
  config_param :unit, :string, :default => 'minute'
  config_param :output_per_tag, :bool, :default => false
  config_param :aggregate, :string, :default => 'tag'
  config_param :tag, :string, :default => 'groupcount'
  config_param :tag_prefix, :string, :default => nil # obsolete
  config_param :add_tag_prefix, :string, :default => nil
  config_param :input_tag_remove_prefix, :string, :default => nil # obsolete
  config_param :remove_tag_prefix, :string, :default => nil
  config_param :group_by_keys, :string, :default => nil
  config_param :group_by_expression, :string, :default => nil
  config_param :max_key, :string, :default => nil
  config_param :min_key, :string, :default => nil
  config_param :avg_key, :string, :default => nil
  config_param :delimiter, :string, :default => '_'
  config_param :count_suffix, :string, :default => '_count'
  config_param :max_suffix, :string, :default => '_max'
  config_param :min_suffix, :string, :default => '_min'
  config_param :avg_suffix, :string, :default => '_avg'
  config_param :store_file, :string, :default => nil
  (1..PATTERN_MAX_NUM).each {|i| config_param "pattern#{i}".to_sym, :string, :default => nil }

  attr_accessor :count_interval
  attr_accessor :counts
  attr_accessor :saved_duration
  attr_accessor :saved_at
  attr_accessor :last_checked

  def configure(conf)
    super

    if @count_interval
      @count_interval = @count_interval.to_i
    else
      @count_interval = case @unit
              when 'minute' then 60
              when 'hour' then 3600
              when 'day' then 86400
              else 
                raise RuntimeError, "@unit must be one of minute/hour/day"
              end
    end

    @aggregate = case @aggregate
                 when 'tag' then :tag
                 when 'all' then :all
                 else
                   raise Fluent::ConfigError, "groupcounter aggregate allows tag/all"
                 end

    @add_tag_prefix ||= @tag_prefix
    @remove_tag_prefix ||= @input_tag_remove_prefix
    if @output_per_tag
      raise Fluent::ConfigError, "add_tag_prefix must be specified with output_per_tag" unless @add_tag_prefix
    end
    if @add_tag_prefix
      @tag_prefix_string = @add_tag_prefix + '.'
    else
      @tag_prefix_string = ''
    end
    if @remove_tag_prefix
      @removed_prefix_string = @remove_tag_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    @group_by_keys = @group_by_keys.split(',') if @group_by_keys

    @pattern = {}
    (1..PATTERN_MAX_NUM).each do |i|
      next unless conf["pattern#{i}"]
      replace, regexp = conf["pattern#{i}"].split(/ +/, 2)
      raise Fluent::ConfigError, "pattern#{i} does not contain 2 parameters" unless regexp
      @pattern[replace] = Regexp.compile(regexp)
    end

    if @store_file
      f = Pathname.new(@store_file)
      if (f.exist? && !f.writable_real?) || (!f.exist? && !f.parent.writable_real?)
        raise Fluent::ConfigError, "#{@store_file} is not writable"
      end
    end

    @counts = count_initialized
    @hostname = Socket.gethostname
    @mutex = Mutex.new
  end

  def start
    super
    load_status(@store_file, @count_interval) if @store_file
    start_watch
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
    save_status(@store_file) if @store_file
  end

  def count_initialized
    {}
  end

  def generate_fields(counts_per_tag, output = {}, key_prefix = '')
    return {} unless counts_per_tag
    # total_count = counts_per_tag.delete('__total_count')

    counts_per_tag.each do |group_key, count|
      group_key_with = group_key.empty? ? "" : group_key + @delimiter
      output[key_prefix + group_key + @count_suffix] = count[:count] if count[:count]
      output[key_prefix + group_key_with + "#{@min_key}#{@min_suffix}"] = count[:min] if count[:min]
      output[key_prefix + group_key_with + "#{@max_key}#{@max_suffix}"] = count[:max] if count[:max]
      output[key_prefix + group_key_with + "#{@avg_key}#{@avg_suffix}"] = count[:sum] / (count[:count] * 1.0) if count[:sum] and count[:count] > 0
      # output[key_prefix + group_key_with + "rate"] = ((count[:count] * 100.0) / (1.00 * step)).floor / 100.0
      # output[key_prefix + group_key_with + "percentage"] = count[:count] * 100.0 / (1.00 * total_count) if total_count > 0
    end

    output
  end

  def generate_output(counts)
    if @output_per_tag # tag => output
      return {'all' => generate_fields(counts['all'])} if @aggregate == :all

      output_pairs = {}
      counts.keys.each do |tag|
        output_pairs[stripped_tag(tag)] = generate_fields(counts[tag])
      end
      output_pairs
    else
      return generate_fields(counts['all']) if @aggregate == :all

      output = {}
      counts.keys.each do |tag|
        generate_fields(counts[tag], output, stripped_tag(tag) + @delimiter)
      end
      output
    end
  end

  def flush
    flushed, @counts = @counts, count_initialized()
    generate_output(flushed)
  end

  # this method emits messages (periodically called)
  def flush_emit
    time = Fluent::Engine.now
    if @output_per_tag
      flush.each do |tag, message|
        Fluent::Engine.emit("#{@tag_prefix_string}#{tag}", time, message)
      end
    else
      message = flush
      Fluent::Engine.emit(@tag, time, message) unless message.empty?
    end
  end

  def start_watch
    # for internal, or tests only
    @watcher = Thread.new(&method(:watch))
  end
  
  def watch
    # instance variable, and public accessable, for test
    @last_checked ||= Fluent::Engine.now
    while true
      sleep 0.5
      begin
        if Fluent::Engine.now - @last_checked >= @count_interval
          now = Fluent::Engine.now
          flush_emit
          @last_checked = now
        end
      rescue => e
        $log.warn "#{e.class} #{e.message} #{e.backtrace.first}"
      end
    end
  end

  # recieve messages at here
  def emit(tag, es, chain)
    group_counts = {}

    tags = tag.split('.')
    es.each do |time, record|
      count = {}
      count[:count] = 1
      count[:sum] = record[@avg_key].to_f if @avg_key and record[@avg_key]
      count[:max] = record[@max_key].to_f if @max_key and record[@max_key]
      count[:min] = record[@min_key].to_f if @min_key and record[@min_key]

      group_key = group_key(tag, time, record)

      group_counts[group_key] ||= {}
      countup(group_counts[group_key], count)
    end
    summarize_counts(tag, group_counts)

    chain.next
  rescue => e
    $log.warn "#{e.class} #{e.message} #{e.backtrace.first}"
  end

  # Summarize counts for each tag
  def summarize_counts(tag, group_counts)
    tag = 'all' if @aggregate == :all
    @counts[tag] ||= {}
    
    @mutex.synchronize {
      group_counts.each do |group_key, count|
        @counts[tag][group_key] ||= {}
        countup(@counts[tag][group_key], count)
      end

      # total_count = group_counts.map {|group_key, count| count[:count] }.inject(:+)
      # @counts[tag]['__total_count'] = sum(@counts[tag]['__total_count'], total_count)
    }
  end

  def countup(counts, count)
    counts[:count] = sum(counts[:count], count[:count])
    counts[:sum]   = sum(counts[:sum], count[:sum]) if @avg_key and count[:sum]
    counts[:max]   = max(counts[:max], count[:max]) if @max_key and count[:max]
    counts[:min]   = min(counts[:min], count[:min]) if @min_key and count[:min]
  end

  # Expand record with @group_by_keys, and get a value to be a group_key
  def group_key(tag, time, record)
    if @group_by_expression
      tags = tag.split('.')
      group_key = expand_placeholder(@group_by_expression, record, tag, tags, Time.at(time))
    elsif @group_by_keys
      values = @group_by_keys.map {|key| record[key] || 'undef'}
      group_key = values.join(@delimiter)
    else
      return ""
    end
    group_key = group_key.to_s.force_encoding('ASCII-8BIT')

    @pattern.each {|replace, regexp| break if group_key.gsub!(regexp, replace) }
    group_key
  end

  def sum(a, b)
    a ||= 0
    b ||= 0
    a + b
  end

  def max(a, b)
    return b if a.nil?
    return a if b.nil?
    a > b ? a : b
  end

  def min(a, b)
    return b if a.nil?
    return a if b.nil?
    a > b ? b : a
  end

  def stripped_tag(tag)
    return tag unless @remove_tag_prefix
    return tag[@removed_length..-1] if tag.start_with?(@removed_prefix_string) and tag.length > @removed_length
    tag
  end

  # Store internal status into a file
  #
  # @param [String] file_path
  def save_status(file_path)

    begin
      Pathname.new(file_path).open('wb') do |f|
        @saved_at = Fluent::Engine.now
        @saved_duration = @saved_at - @last_checked
        Marshal.dump({
          :counts           => @counts,
          :saved_at         => @saved_at,
          :saved_duration   => @saved_duration,
          :aggregate        => @aggregate,
          :group_by_keys    => @group_by_keys,
        }, f)
      end
    rescue => e
      $log.warn "out_groupcounter: Can't write store_file #{e.class} #{e.message}"
    end
  end

  # Load internal status from a file
  #
  # @param [String] file_path
  # @param [Interger] count_interval
  def load_status(file_path, count_interval)
    return unless (f = Pathname.new(file_path)).exist?

    begin
      f.open('rb') do |f|
        stored = Marshal.load(f)
        if stored[:aggregate] == @aggregate and
          stored[:group_by_keys] == @group_by_keys and

          if Fluent::Engine.now <= stored[:saved_at] + count_interval
            @counts = stored[:counts]
            @saved_at = stored[:saved_at]
            @saved_duration = stored[:saved_duration]

            # skip the saved duration to continue counting
            @last_checked = Fluent::Engine.now - @saved_duration
          else
            $log.warn "out_groupcounter: stored data is outdated. ignore stored data"
          end
        else
          $log.warn "out_groupcounter: configuration param was changed. ignore stored data"
        end
      end
    rescue => e
      $log.warn "out_groupcounter: Can't load store_file #{e.class} #{e.message}"
    end
  end

  private

  def expand_placeholder(str, record, tag, tags, time)
    struct = UndefOpenStruct.new(record)
    struct.tag  = tag
    struct.tags = tags
    struct.time = time
    struct.hostname = @hostname
    str = str.gsub(/\$\{([^}]+)\}/, '#{\1}') # ${..} => #{..}
    eval "\"#{str}\"", struct.instance_eval { binding }
  end

  class UndefOpenStruct < OpenStruct
    (Object.instance_methods).each do |m|
      undef_method m unless m.to_s =~ /^__|respond_to_missing\?|object_id|public_methods|instance_eval|method_missing|define_singleton_method|respond_to\?|new_ostruct_member/
    end
  end
end
