# Copyright 2011-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'multi_json'

module Aws
  class ClientFactory

    # @api private
    class NoSuchApiError < RuntimeError
      def initialize(client_factory, api_version)
        super("API #{api_version} not defined for #{client_factory.name}")
      end
    end

    class << self

      # @return [Seahorse::Client::Base] Returns a versioned client.
      def new(options = {})
        version = (Aws.config[method_name] || {})[:api_version]
        version ||= options[:api_version]
        version ||= versions.last
        const_get("V#{version.gsub('-', '')}").new(options)
      end

      # Register an API for this client.
      #
      # @example Register a client with a path to the JSON api.
      #   Aws::S3::Client.add_version('2013-01-02', '/path/to/api/src.json')
      #
      # @example Register a client with a hydrated API.
      #   api = Seahorse::Model::Api.from_hash(api_src)
      #   Aws::S3::Client.add_version('2013-01-02', api)
      #
      # @param [String<YYYY-MM-DD>] api_version
      # @param [String<Pathname>, Seahorse::Model::Api] api
      # @return [void]
      def add_version(api_version, api)
        apis[api_version] = api
      end

      # @return [Array<String>]
      def versions
        apis.keys.sort
      end

      # @api private
      attr_accessor :method_name

      private

      def apis
        @apis ||= {}
      end

      def const_missing(constant)
        if constant =~ /^V\d{8}$/
          api = api_for(constant)
          const_set(constant, Seahorse::Client.define(api: api))
        else
          super
        end
      end

      def api_for(constant)
        api_version = version_for(constant)
        api = apis[api_version]
        case api
        when Seahorse::Model::Api then api
        when String then load_api(api)
        else raise NoSuchApiVersion.new(self, api_version)
        end
      end

      def version_for(constant)
        yyyy = constant[1,4]
        mm = constant[5,2]
        dd = constant[7,2]
        [yyyy, mm, dd].join('-')
      end

      def load_api(path)
        api = MultiJson.load(File.read(path))
        if api.key?('metadata')
          Seahorse::Model::Api.from_hash(api)
        else
          ApiTranslator.translate(api)
        end
      end

    end
  end
end