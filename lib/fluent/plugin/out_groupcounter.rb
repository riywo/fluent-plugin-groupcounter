class Fluent::GroupCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('groupcounter', self)

  config_param :count_interval, :time, :default => nil
  config_param :unit, :string, :default => 'minute'
  config_param :output_per_tag, :bool, :default => false
  config_param :aggregate, :string, :default => 'tag'
  config_param :tag, :string, :default => 'groupcount'
  config_param :tag_prefix, :string, :default => nil
  config_param :input_tag_remove_prefix, :string, :default => nil
  config_param :group_by_keys, :string
  config_param :output_messages, :bool, :default => false
  config_param :store_file, :string, :default => nil

  attr_accessor :tick
  attr_accessor :counts
  attr_accessor :passed_time
  attr_accessor :last_checked

  def configure(conf)
    super

    if @count_interval
      @tick = @count_interval.to_i
    else
      @tick = case @unit
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

    if @output_per_tag
      raise Fluent::ConfigError, "tag_prefix must be specified with output_per_tag" unless @tag_prefix
      @tag_prefix_string = @tag_prefix + '.'
    end

    if @input_tag_remove_prefix
      @removed_prefix_string = @input_tag_remove_prefix + '.'
      @removed_length = @removed_prefix_string.length
    end

    @group_by_keys = @group_by_keys.split(',')

    if @store_file
      f = Pathname.new(@store_file)
      if (f.exist? && !f.writable_real?) || (!f.exist? && !f.parent.writable_real?)
        raise Fluent::ConfigError, "#{@store_file} is not writable"
      end
    end

    @counts = count_initialized
    @mutex = Mutex.new
  end

  def start
    super
    load_from_file
    start_watch
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
    store_to_file
  end

  def count_initialized
    # counts['tag'][group_by_keys] = count
    # counts['tag'][__sum] = sum
    {}
  end

  def countups(tag, counts)
    if @aggregate == :all
      tag = 'all'
    end
    @counts[tag] ||= {}
    
    @mutex.synchronize {
      sum = 0
      counts.each do |key, count|
        sum += count
        @counts[tag][key] ||= 0
        @counts[tag][key] += count
      end
      @counts[tag]['__sum'] ||= 0
      @counts[tag]['__sum'] += sum
    }
  end

  def stripped_tag(tag)
    return tag unless @input_tag_remove_prefix
    return tag[@removed_length..-1] if tag.start_with?(@removed_prefix_string) and tag.length > @removed_length
    return tag[@removed_length..-1] if tag == @input_tag_remove_prefix
    tag
  end

  def generate_fields(step, target_counts, attr_prefix, output)
    return {} unless target_counts
    sum = target_counts['__sum']
    messages = target_counts.delete('__sum')

    target_counts.each do |key, count|
      output[attr_prefix + key + '_count'] = count
      output[attr_prefix + key + '_rate'] = ((count * 100.0) / (1.00 * step)).floor / 100.0
      output[attr_prefix + key + '_percentage'] = count * 100.0 / (1.00 * sum) if sum > 0
      if @output_messages
        output[attr_prefix + 'messages'] = messages
      end
    end

    output
  end

  def generate_output(counts, step)
    if @aggregate == :all
      return generate_fields(step, counts['all'], '', {})
    end

    output = {}
    counts.keys.each do |tag|
      generate_fields(step, counts[tag], stripped_tag(tag) + '_', output)
    end
    output
  end

  def generate_output_per_tags(counts, step)
    if @aggregate == :all
      return {'all' => generate_fields(step, counts['all'], '', {})}
    end

    output_pairs = {}
    counts.keys.each do |tag|
      output_pairs[stripped_tag(tag)] = generate_fields(step, counts[tag], '', {})
    end
    output_pairs
  end

  def flush(step) # returns one message
    flushed,@counts = @counts,count_initialized()
    generate_output(flushed, step)
  end

  def flush_per_tags(step) # returns map of tag - message
    flushed,@counts = @counts,count_initialized()
    generate_output_per_tags(flushed, step)
  end

  def flush_emit(step = 1)
    if @output_per_tag
      # tag - message maps
      time = Fluent::Engine.now
      flush_per_tags(step).each do |tag,message|
        Fluent::Engine.emit(@tag_prefix_string + tag, time, message)
      end
    else
      message = flush(step)
      if message.keys.size > 0
        Fluent::Engine.emit(@tag, Fluent::Engine.now, message)
      end
    end
  end

  def start_watch
    # for internal, or tests only
    @watcher = Thread.new(&method(:watch))
  end
  
  def watch
    # instance variable, and public accessable, for test
    @last_checked = Fluent::Engine.now
    # skip the passed time when loading @counts form file
    @last_checked -= @passed_time if @passed_time
    while true
      sleep 0.5
      begin
        if Fluent::Engine.now - @last_checked >= @tick
          now = Fluent::Engine.now
          flush_emit(now - @last_checked)
          @last_checked = now
        end
      rescue => e
        $log.warn "#{e.class} #{e.message} #{e.backtrace.first}"
      end
    end
  end

  def emit(tag, es, chain)
    c = {}

    es.each do |time,record|
      values = []
      @group_by_keys.each { |key|
        v = record[key] || 'undef'
        values.push(v)
      }
      value = values.join('_')

      value = value.to_s.force_encoding('ASCII-8BIT')
      c[value] ||= 0
      c[value] += 1
    end
    countups(tag, c)

    chain.next
  rescue => e
    $log.warn "#{e.class} #{e.message} #{e.backtrace.first}"
  end

  def store_to_file
    return unless @store_file

    begin
      Pathname.new(@store_file).open('wb') do |f|
        @passed_time = Fluent::Engine.now - @last_checked
        Marshal.dump({
          :counts           => @counts,
          :passed_time      => @passed_time,
          :aggregate        => @aggregate,
          :group_by_keys    => @group_by_keys,
        }, f)
      end
    rescue => e
      $log.warn "out_groupcounter: Can't write store_file #{e.class} #{e.message}"
    end
  end

  def load_from_file
    return unless @store_file
    return unless (f = Pathname.new(@store_file)).exist?

    begin
      f.open('rb') do |f|
        stored = Marshal.load(f)
        if stored[:aggregate] == @aggregate and
          stored[:group_by_keys] == @group_by_keys and
          @counts = stored[:counts]
          @passed_time = stored[:passed_time]
        else
          $log.warn "out_groupcounter: configuration param was changed. ignore stored data"
        end
      end
    rescue => e
      $log.warn "out_groupcounter: Can't load store_file #{e.class} #{e.message}"
    end
  end
end
