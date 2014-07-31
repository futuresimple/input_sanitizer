require 'input_sanitizer/restricted_hash'
require 'input_sanitizer/default_converters'

class InputSanitizer::Sanitizer
  def initialize(data)
    @data = symbolize_keys(data)
    @performed = false
    @errors = []
    @cleaned = InputSanitizer::RestrictedHash.new(self.class.fields.keys)
  end

  def self.clean(data)
    new(data).cleaned
  end

  def [](field)
    cleaned[field]
  end

  def cleaned
    return @cleaned if @performed
    self.class.fields.each do |field, hash|
      type = hash[:type]
      required = hash[:options][:required]
      collection = hash[:options][:collection]
      namespace = hash[:options][:namespace]
      default = hash[:options][:default]
      provide = hash[:options][:provide]
      clean_field(field, type, required, collection, namespace, default, provide)
    end
    @performed = true
    @cleaned.freeze
  end

  def valid?
    cleaned
    @errors.empty?
  end

  def errors
    cleaned
    @errors
  end

  def self.converters
    {
      :integer => InputSanitizer::IntegerConverter.new,
      :string => InputSanitizer::StringConverter.new,
      :date => InputSanitizer::DateConverter.new,
      :time => InputSanitizer::TimeConverter.new,
      :boolean => InputSanitizer::BooleanConverter.new,
      :integer_or_blank => InputSanitizer::IntegerConverter.new.extend(InputSanitizer::AllowNil),
      :string_or_blank => InputSanitizer::StringConverter.new.extend(InputSanitizer::AllowNil),
      :date_or_blank => InputSanitizer::DateConverter.new.extend(InputSanitizer::AllowNil),
      :time_or_blank => InputSanitizer::TimeConverter.new.extend(InputSanitizer::AllowNil),
      :boolean_or_blank => InputSanitizer::BooleanConverter.new.extend(InputSanitizer::AllowNil),
    }
  end

  def self.inherited(subclass)
    subclass.fields = self.fields.dup
  end

  converters.keys.each do |name|
    class_eval <<-END
      def self.#{name}(*keys)
        set_keys_to_type(keys, :#{name})
      end
    END
  end

  def self.custom(*keys)
    options = keys.pop
    converter = options.delete(:converter)
    keys.push(options)
    raise "You did not define a converter for a custom type" if converter == nil
    self.set_keys_to_type(keys, converter)
  end

  def self.nested(*keys)
    options = keys.pop
    sanitizer = options.delete(:sanitizer)
    keys.push(options)
    raise "You did not define a sanitizer for nested value" if sanitizer == nil
    converter = lambda { |value|
      sanitizer.clean(value)
    }
    self.set_keys_to_type(keys, converter)
  end

  protected
  def self.fields
    @fields ||= {}
  end

  def self.fields=(new_fields)
    @fields = new_fields
  end

  private
  def self.extract_options!(array)
    array.last.is_a?(Hash) ? array.pop : {}
  end

  def self.extract_options(array)
    array.last.is_a?(Hash) ? array.last : {}
  end

  def clean_field(field, type, required, collection, namespace, default, provide)
    if @data.has_key?(field)
      begin
        @cleaned[field] = convert(field, type, collection, namespace, provide)
      rescue InputSanitizer::ConversionError => ex
        add_error(field, :invalid_value, @data[field], ex.message)
      end
    elsif default
      @cleaned[field] = converter(type).call(default)
    elsif required
      add_missing(field)
    end
  end

  def add_error(field, error_type, value, description = nil)
    @errors << {
      :field => field,
      :type => error_type,
      :value => value,
      :description => description
    }
  end

  def add_missing(field)
    add_error(field, :missing, nil, nil)
  end

  def convert(field, type, collection, namespace, provide)
    if collection
      @data[field].map { |v|
        convert_single(type, v, namespace, provide)
      }
    else
      convert_single(type, @data[field], namespace, provide)
    end
  end

  def convert_single(type, value, namespace, provide)
    if namespace
      { namespace => convert_value(converter(type), value[namespace], provide) }
    else
      convert_value(converter(type), value, provide)
    end
  end

  def convert_value(converter, value, provide)
    if provide
      converter.call(value, @data[provide])
    else
      converter.call(value)
    end
  end

  def converter(type)
    type.respond_to?(:call) ? type : self.class.converters[type]
  end

  def symbolize_keys(data)
    data.inject({}) do |memo, kv|
      memo[kv.first.to_sym] = kv.last
      memo
    end
  end

  def self.set_keys_to_type(keys, type)
    opts = extract_options!(keys)
    keys.each do |key|
      fields[key] = { :type => type, :options => opts }
    end
  end
end
