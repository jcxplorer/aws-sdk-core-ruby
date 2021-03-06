root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
$:.unshift(File.join(root, 'vendor', 'seahorse', 'lib'))
$:.unshift(File.join(root, 'lib'))

require 'aws-sdk-core'

YARD::Tags::Library.define_tag('CONFIGURATION_OPTIONS', :seahorse_client_option)
YARD::Tags::Library.define_tag('SERVICE', :service)
YARD::Tags::Library.define_tag('API_VERSION', :api_version)

YARD::Templates::Engine.register_template_path(File.join(File.dirname(__FILE__), '..', 'templates'))

YARD::Parser::SourceParser.after_parse_list do
  svc_apis.each do |svc_name, apis|
    document_svc(svc_name, apis)
  end
end

def svc_apis
  Dir.glob('apis/source/*.json').inject({}) do |apis, path|
    if matches = path.match(/^apis\/source\/(\w+)-(\d{4}-\d{2}-\d{2}).json$/)
      api = load_api(path)
      svc_name = api.metadata['service_class_name']
      apis[svc_name] ||= []
      apis[svc_name] << api
    end
    apis
  end
end

def load_api(path)
  Aws::Api::Translator.translate(
    MultiJson.load(File.read(path), max_nesting: nil),
    documentation: true,
    errors: true)
end

def document_svc(svc_name, apis)
  document_svc_helper(svc_name, apis)
  document_svc_class(svc_name, apis)
  apis.each do |api|
    document_svc_api(svc_name, api)
  end
end

def document_svc_helper(svc_name, apis)
  method_name = svc_name.downcase
  m = YARD::CodeObjects::MethodObject.new(YARD::Registry['Aws'], method_name)
  m.scope = :class
  m.parameters << ['options', '{}']
  m.docstring = <<-DOC.strip
Returns a new instance of {#{svc_name}}.
@option (see Aws::#{svc_name}.new)
@return (see Aws::#{svc_name}.new)
  DOC
end

def document_svc_class(svc_name, apis)

  oldest_api = apis.sort_by(&:version).first
  default_api = apis.sort_by(&:version).last
  full_name = default_api.metadata['service_full_name']

  namespace = YARD::Registry['Aws']
  klass = YARD::CodeObjects::ClassObject.new(namespace, svc_name)
  klass.superclass = YARD::Registry['Aws::Service']
  klass.docstring = <<-DOCSTRING
A service client builder for #{full_name}.

## Configuration

You can specify global default configuration options via `Aws.config`.  Values
in `Aws.config` are used as default options for all services.

    Aws.config[:region] = 'us-west-2'

You can specify service specific defaults as well:

    Aws.config[:#{svc_name.downcase}] = { region: 'us-west-1' }

This has a higher precendence that values at the root of `Aws.config` and will
only applied to objects constructed by {new}.

## Regions & Endpoints

You must configure a default region with `Aws.config` or provide a `:region`
when creating a service client.  The regions listed below will connect
to the following endpoints:

#{default_api.metadata['regional_endpoints'].map { |r,e| "* `#{r}` - #{e}"}.join("\n")}

## API Versions

Calling {new} will construct and return a versioned service client. The client
will default to the most recent API version. You can also specify an API version:

    #{svc_name.downcase} = Aws::#{svc_name}.new # Aws::#{svc_name}::V#{default_api.version.gsub(/-/, '')}
    #{svc_name.downcase} = Aws::#{svc_name}.new(api_version: '#{oldest_api.version}') # Aws::#{svc_name}::V#{oldest_api.version.gsub(/-/, '')}

The following API versions are available for Aws::#{svc_name}:

#{apis.map{ |a| "* {V#{a.version.gsub(/-/, '')} #{a.version}}" }.join("\n")}

You can specify the API version for the client by passing `:api_version` to {new}.
  DOCSTRING
  klass.docstring.add_tag(YARD::Tags::Tag.new(:service, svc_name))

  svc = Aws.const_get(svc_name)

  options = {}

  svc.default_client_class.plugins.each do |plugin|
    if p = YARD::Registry[plugin.name]
      p.tags.each do |tag|
        if tag.tag_name == 'seahorse_client_option'
          option_name = tag.text.match(/.+(:\w+)/)[1]
          option_text = "@option options " + tag.text.split("\n").join("\n  ")
          options[option_name] = option_text +
            "  See {#{plugin.name}} for more details."
        end
      end
    end
  end
  options = options.sort_by { |k,v| k }.map(&:last).join("\n")

  docstring = <<-DOCS.strip
Constructs a versioned client for this service.
@option options [String<YYYY-MM-DD>] :api_version ('#{svc.latest_api_version}')
  The API version to use for this service.  Valid values include:

  * #{svc.api_versions.join("\n  * ")}
#{options}
@return [#{svc.default_client_class.name}] Returns a versioned client.
  By default, this will be a client for the latest API version.  Configure
  the `:api_version` option to affect which client class is constructed.
  Possible versioned clients are:

  * #{svc.versioned_clients.map{ |k| "{#{k.name}}" }.join("\n  * ")}

  DOCS

  constructor = YARD::CodeObjects::MethodObject.new(klass, :new)
  constructor.scope = :class
  constructor.parameters << ['options', '{}']
  constructor.docstring = docstring

end

def document_svc_api(svc_name, api)
  namespace = YARD::Registry["Aws::#{svc_name}"]
  name = "V#{api.version.gsub(/-/, '')}"
  full_name = api.metadata['service_full_name']
  klass = YARD::CodeObjects::ClassObject.new(namespace, name)
  klass.superclass = YARD::Registry['Seahorse::Client::Base']
  klass.docstring = "A client for the #{full_name} #{api.version} API."
  klass.docstring.add_tag(YARD::Tags::Tag.new(:api_version, api.version))
  api.operations.each do |method_name, operation|
    document_svc_api_operation(svc_name, klass, method_name, operation)
  end

  constructor = YARD::CodeObjects::MethodObject.new(klass, :initialize)
  constructor.scope = :instance
  constructor.parameters << ['options', '{}']
  constructor.docstring = "@option (see #{svc_name}.new)"
end

class Tabulator

  def initialize
    @tabs = []
    @tab_contents = []
  end

  def tab(method_name, tab_name, &block)
    tab_class = tab_name.downcase.gsub(/[^a-z]+/i, '-')
    tab_id = "#{method_name.gsub(/_/, '-')}-#{tab_class}"
    class_names = ['tab-contents', tab_class]
    @tabs << [tab_id, tab_name]
    @tab_contents << "<div class=\"#{class_names.join(' ')}\" id=\"#{tab_id}\">"
    @tab_contents << yield
    @tab_contents << '</div>'
  end

  def to_html
    lines = []
    lines << '<div class="tab-box">'
    lines << '<ul class="tabs">'
    @tabs.each do |tab_id, tab_name|
      lines << "<li data-tab-id=\"#{tab_id}\">#{tab_name}</li>"
    end
    lines << '</ul>'
    lines.concat(@tab_contents)
    lines << '</div>'
    lines.join
  end
  alias inspect to_html
  alias to_str to_html
  alias to_s to_html

end

def without_docs(value)
  case value
  when Hash
    value.inject({}) do |h,(k,v)|
      h[k] = without_docs(v) unless k == 'documentation'
      h
    end
  when Array then value.map{ |v| without_docs(v) }
  else value
  end
end

def document_svc_api_operation(svc_name, client, method_name, operation)

  documentor = Aws::Api::Documentor.new(svc_name.downcase, method_name, operation)

  tabs = Tabulator.new.tap do |t|
    t.tab(method_name, 'Formatting Example') do
      "<pre><code>#{documentor.example}</code></pre>"
    end
    t.tab(method_name, 'Request Parameters') do
      documentor.input
    end
    t.tab(method_name, 'Response Structure') do
      documentor.output
    end
    t.tab(method_name, 'API Model') do
      "<div class=\"api-src\"><pre><code class=\"json\">#{JSON.pretty_generate(without_docs(operation.to_hash), pretty: true, max_nesting: false)}</pre></code></div>"
    end
  end

  errors = (operation.errors || []).map { |shape| shape.metadata['shape_name'] }
  errors = errors.map { |e| "@raise [Errors::#{e}]" }.join("\n")

  m = YARD::CodeObjects::MethodObject.new(client, method_name)
  m.scope = :instance
  m.parameters << ['params', '{}']
  m.docstring = <<-DOCSTRING.strip
<p>Calls the #{operation.name} operation.<p>
#{documentor.api_ref(operation)}
#{tabs}
@param [Hash] params ({})
@return [Seahorse::Client::Response]
#{errors}
DOCSTRING

end
