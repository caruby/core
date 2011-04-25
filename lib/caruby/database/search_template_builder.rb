require 'caruby/util/log'
require 'caruby/util/pretty_print'

module CaRuby
  # SearchTemplateBuilder builds a template suitable for a caCORE saarch database operation.
  class SearchTemplateBuilder
    # Returns a template for matching the domain object obj and the optional hash values.
    # The default hash attributes are the {ResourceAttributes#searchable_attributes}.
    # The template includes only the non-domain attributes of the hash references.
    #
    # caCORE alert - Because of caCORE API limitations, the obj searchable attribute
    # values are limited to the following:
    # * non-domain attribute values
    # * non-collection domain attribute references which contain a key
    #
    # caCORE alert - the caCORE query builder breaks on reference cycles and
    # is easily confused by extraneous references, so it is necessary to search
    # with a template instead that contains only references essential to the
    # search. Each reference is confirmed to exist and the reference content in
    # the template consists entirely of the fetched identifier attribute.
    def build_template(obj, hash=nil)
      # split the attributes into reference and non-reference attributes.
      # the new search template object is built from the non-reference attributes.
      # the reference attributes values are copied and added.
      logger.debug { "Building search template for #{obj.qp}..." }
      hash ||= obj.value_hash(obj.class.searchable_attributes)
      # the searchable attribute => value hash
      ref_hash, nonref_hash = hash.hash_partition { |attr, value| Resource === value }
      # make the search template from the non-reference attributes
      tmpl = obj.class.new.merge_attributes(nonref_hash)
      # get references for the search template
      unless ref_hash.empty? then
        logger.debug { "Collecting search reference parameters for #{obj.qp} from attributes #{ref_hash.keys.to_series}..." }
      end
      ref_hash.each { |attr, ref| add_search_template_reference(tmpl, ref, attr) }
      tmpl
    end

    private

    # Sets the template attribute to a new search reference object created from the given
    # source domain object. The reference contains only the source identifier, if it exists,
    # or the source non-domain attributes otherwise.
    #
    # @return [Resource] the search reference
    def add_search_template_reference(template, source, attribute)
      ref = source.identifier ? source.copy(:identifier) : source.copy
      # Disable inverse integrity, since the template attribute assignment might have added a reference
      # from ref to template, which introduces a template => ref => template cycle that causes a caCORE
      # search infinite loop. Use the Java property writer instead.
      wtr = template.class.attribute_metadata(attribute).property_writer
      template.send(wtr, ref)
      logger.debug { "Search reference parameter #{attribute} for #{template.qp} set to #{ref} copied from #{source.qp}" }
      ref
    end
  end
end