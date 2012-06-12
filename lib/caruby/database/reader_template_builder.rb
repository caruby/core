require 'jinx/resource'
require 'jinx/helpers/pretty_print'

module CaRuby
  class Database
    module Reader
      # TemplateBuilder builds a template suitable for a caCORE saarch database operation.
      class TemplateBuilder
        # Returns a template for matching the domain object obj and the optional hash values.
        # The default hash attributes are the {Propertied#searchable_attributes}.
        # The template includes only the non-domain attributes of the hash references.
        #
        # @quirk caCORE Because of caCORE API limitations, the obj searchable attribute
        #   values are limited to the following:
        #   * non-domain attribute values
        #   * non-collection domain attribute references which contain a key
        #
        # @quirk caCORE the caCORE query builder breaks on reference cycles and is easily confused
        #   by extraneous references, so it is necessary to search with a template instead that contains
        #   only references essential to the search. Each reference is confirmed to exist and the
        #   reference content in the template consists entirely of the fetched identifier attribute.
        def build_template(obj, hash=nil)
          # split the attributes into reference and non-reference attributes.
          # the new search template object is built from the non-reference attributes.
          # the reference attributes values are copied and added.
          logger.debug { "Building search template for #{obj.qp}..." }
          hash ||= obj.value_hash(obj.class.searchable_attributes)
          # the searchable attribute => value hash
          rh, nrh = hash.split { |pa, value| Jinx::Resource === value }
          # make the search template from the non-reference attributes
          tmpl = obj.class.new.merge_attributes(nrh)
          # get references for the search template
          unless rh.empty? then
            logger.debug { "Collecting search reference parameters for #{obj.qp} from attributes #{rh.keys.to_series}..." }
          end
          rh.each { |pa, ref| add_search_template_reference(tmpl, ref, pa) }
          tmpl
        end

        private

        # Sets the template attribute to a new search reference object created from the given
        # source domain object. The reference contains only the source identifier, if it exists,
        # or the source non-domain attributes otherwise.
        #
        # @quirk caCORE The search template must break inverse integrity by clearing an owner inverse reference,
        #   since a dependent => owner => dependent cycle causes a caCORE search infinite loop.
        #
        # @return [Jinx::Resource] the search reference
        def add_search_template_reference(template, source, attribute)
          ref = source.identifier ? source.copy(:identifier) : source.copy
          # Disable inverse integrity by using the Java property writer instead of the attribute writer.
          # The attribute writer will add a reference from ref to template, which introduces a
          # template => ref => template cycle that causes a caCORE search infinite loop.
          wtr = template.class.property(attribute).java_writer
          template.send(wtr, ref)
          logger.debug { "Search reference parameter #{attribute} for #{template.qp} set to #{ref} copied from #{source.qp}" }
          ref
        end
      end
    end
  end
end