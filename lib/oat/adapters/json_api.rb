# http://jsonapi.org/format/#url-based-json-api
require 'active_support/inflector'
require 'active_support/core_ext/string/inflections'
unless defined?(String.new.pluralize)
  class String
    include ActiveSupport::CoreExtensions::String::Inflections
  end
end

module Oat
  module Adapters

    class JsonAPI < Oat::Adapter

      def initialize(*args)
        super
        @entities = {}
        @link_templates = {}
        @meta = {}
        data['id'] = ''
        data['type'] = ''
        data['attributes'] = {}
      end

      def rel(rels)
        # no-op to maintain interface compatibility with the Siren adapter
      end

      def type(*types)
        @root_name = types.first.to_s.pluralize.to_sym
        data['type'] = @root_name
      end

      def link(rel, opts = {})
        templated = false
        if opts.is_a?(Hash)
          templated = opts.delete(:templated)
          if templated
            link_template(rel, opts[:href])
          else
            check_link_keys(opts)
          end
        end
        data[:links][rel] = opts unless templated
      end

      def check_link_keys(opts)
        unsupported_opts = opts.keys - [:href, :id, :ids, :type]

        unless unsupported_opts.empty?
          raise ArgumentError, "Unsupported opts: #{unsupported_opts.join(", ")}"
        end
        if opts.has_key?(:id) && opts.has_key?(:ids)
          raise ArgumentError, "ops canot contain both :id and :ids"
        end
      end
      private :check_link_keys

      def link_template(key, value)
        @link_templates[key] = value
      end
      private :link_template

      def properties(&block)
        data['attributes'].merge! yield_props(&block)
        if data['attributes'].has_key?('id')
          data['id'] =  data['attributes']['id']
          data['attributes'].delete('id')
        end
      end

      def property(key, value)
        if key.to_s == 'id'
          data[key] = value
        else
          data['attributes'][key] = value
        end
      end

      def meta(key, value)
        @meta[key] = value
      end

      def entity(name, obj, serializer_class = nil, context_options = {}, &block)
        ent = serializer_from_block_or_class(obj, serializer_class, context_options, &block)
        if ent
          ent_hash = ent.to_hash
          _name = entity_name(name)
          link_name = _name.to_s.pluralize.to_sym
          data[:links][_name] = ent_hash[:id]

          entity_hash[link_name] ||= []
          unless entity_hash[link_name].include? ent_hash
            entity_hash[link_name] << ent_hash
          end
        end
      end

      def entities(name, collection, serializer_class = nil, context_options = {}, &block)
        return if collection.nil? || collection.empty?
        _name = entity_name(name)
        link_name = _name.to_s.pluralize.to_sym
        data[:links][link_name] = []

        collection.each do |obj|
          entity_hash[link_name] ||= []
          ent = serializer_from_block_or_class(obj, serializer_class, context_options, &block)
          if ent
            ent_hash = ent.to_hash
            data[:links][link_name] << ent_hash[:id]
            unless entity_hash[link_name].include? ent_hash
              entity_hash[link_name] << ent_hash
            end
          end
        end
      end

      def entity_name(name)
        # entity name may be an array, but JSON API only uses the first
        name.respond_to?(:first) ? name.first : name
      end

      private :entity_name

      def collection(name, collection, serializer_class = nil, context_options = {}, &block)
        @treat_as_resource_collection = true
        data[:resource_collection] = [] unless data[:resource_collection].is_a?(Array)

        collection.each do |obj|
          ent = serializer_from_block_or_class(obj, serializer_class, context_options, &block)
          data[:resource_collection] << ent.to_hash if ent
        end
      end

      def to_hash
        raise "JSON API entities MUST define a type. Use type 'user' in your serializers" unless root_name
        if serializer.top != serializer
          return data
        else
          h = {}
          if @treat_as_resource_collection
            h['data'] = data[:resource_collection]
          else
            h['data'] = data
          end
          h[:linked] = @entities if @entities.keys.any?
          links = serializer.instance_variable_get(:@links) || @link_templates
          h[:links] = links if !!links
          h[:meta] = @meta if @meta.keys.any?
          return h
        end
      end

      protected

      attr_reader :root_name

      def entity_hash
        if serializer.top == serializer
          @entities
        else
          serializer.top.adapter.entity_hash
        end
      end

      def entity_without_root(obj, serializer_class = nil, &block)
        ent = serializer_from_block_or_class(obj, serializer_class, &block)
        ent.to_hash.values.first.first if ent
      end

    end
  end
end
