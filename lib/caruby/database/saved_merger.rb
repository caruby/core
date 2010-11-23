require 'caruby/util/collection'
require 'caruby/util/pretty_print'
require 'caruby/domain/reference_visitor'
require 'caruby/database/fetched_matcher'
require 'caruby/database/store_template_builder'

module CaRuby
  class Database
    # Merges database content sources into saved targets.
    class SavedMerger
      # @param [Database] database the database performing the save
      def initialize(database)
        @database = database
        # the save result matchers
        cr_mtchr = FetchedMatcher.new(:relaxed)
        upd_mtchr = FetchedMatcher.new
        # the save result merge visitors
        @cr_mrg_vstr = MergeVisitor.new(:matcher => cr_mtchr) { |src, tgt| mergeable_saved_attributes(tgt) }
        @upd_mrg_vstr = MergeVisitor.new(:matcher => upd_mtchr) { |src, tgt| mergeable_saved_attributes(tgt) }
      end
      
            
      # Merges the database content into the given saved domain object.
      # Dependents are merged recursively.
      #
      # @param [Resource] obj the saved domain object
      # @param [Resource] result the caCORE result
      # @return [Resource] the object representing the persistent state
      def merge(saved, result)
        # the sync source reflecting the database content
        src = saved_source(saved, result)
        # merge the source into obj, including all cascaded dependents
        merge_saved(saved, src)
        src
      end

      # @param [Resource] obj the saved domain object
      # @param [Resource] result the caCORE result domain object
      # @return [Resource] the source domain object which accurately reflects the database state
      # @see #fetch_saved?
      def saved_source(obj, result)
        # The true stored content might need to be fetched from the database.
        if obj.fetch_saved? then
          tmpl = result.copy(:identifier)
          logger.debug { "Fetching saved #{obj.qp} using template #{tmpl}..." }
          tmpl.find
        else
          result
        end
      end
      
      # Merges the content of the source domain object into the saved domain object obj.
      # If obj differs from source, then obj is resaved. Dependents are merged recursively.
      #
      # @param [Resource] obj the saved domain object
      # @param [Resource] source object holding the stored content
      def merge_saved(obj, source)
        logger.debug { "Merging database content #{source} into saved #{obj.qp}..." }
        visitor = @database.mergeable_autogenerated_operation? ? @cr_mrg_vstr : @upd_mrg_vstr
        visitor.visit(obj, source) do |tgt, src|
          logger.debug { "Saved #{obj.qp} merge visitor merged database content #{src.qp} into #{tgt.qp}..." }
          merge_saved_reference(tgt, src)
        end
      end
      
      # Sets the target snapshot attribute values from the given source, if different.
      #
      # @param [Resource] target the saved domain object
      # @param [Resource] source the domain object reflecting the database state
      # @return [Resource] the synced target
      def merge_saved_reference(target, source)
        # set each unsaved non-domain attribute from the source to reflect the database value
        target.copy_volatile_attributes(source)
        
        # take a snapshot of the saved target
        target.take_snapshot
        logger.debug { "A snapshot was taken of the saved #{target.qp}." }
        
        # the non-domain attribute => [target value, source value] difference hash
        diff = target.diff(source)
        # the difference attribute => source value hash, excluding nil source values
        dvh = diff.transform { |vdiff| vdiff.last }.compact
        return if dvh.empty?
        logger.debug { "Saved #{target} differs from database content #{source.qp} as follows: #{diff.filter_on_key { |attr| dvh.has_key?(attr) }.qp}" }
        logger.debug { "Setting saved #{target.qp} snapshot values from source values to reflect the database state: #{dvh.qp}..." }
        # update the snapshot from the source value to reflect the database state
        target.snapshot.merge!(dvh)
        
        target
      end
    
      # Returns the dependent attributes that can be copied from a save result to
      # the given save argument object. This method qualifies the obj class
      # {AttributeMetadata#copyable_saved_attributes} by whether the attribute is
      # actually auto-generated for the saved object, i.e. the object was itself
      # created or auto-generated. If obj was created or auto-generated, then
      # this method returns the {AttributeMetadata#copyable_saved_attributes}.
      # Otherwise, this method returns the {AttributeMetadata#cascaded_attributes}.
      #
      # @param [Resource] obj the domain object which was saved 
      # @return  [<Symbol>] the attributes to copy
      def mergeable_saved_attributes(obj)
        fa = obj.class.fetched_domain_attributes
        obj.suspend_lazy_loader do
          attrs = obj.class.cascaded_attributes.filter do |attr|
            fa.include?(attr) or not obj.send(attr).nil_or_empty?
          end
          if @database.mergeable_autogenerated_operation? then
            ag_attrs = mergeable_saved_autogenerated_attributes(obj)
            unless ag_attrs.empty? then
              logger.debug { "Adding #{obj.qp} mergeable saved auto-generated #{ag_attrs.to_series} to the merge set..." }
              attrs = attrs.to_set.merge(ag_attrs)
            end
          end
          logger.debug { "Mergeable saved #{obj.qp} attributes: #{attrs.qp}." } unless attrs.empty?
          attrs
        end
      end
      
      # Returns the autogenerated dependent attributes that can be copied from a save result to
      # the given save argument object.
      #
      # @param [Resource] obj the domain object which was saved 
      # @return [<Symbol>] the attributes to copy, or nil if no such attributes
      def mergeable_saved_autogenerated_attributes(obj)
        attrs = obj.class.mergeable_saved_autogenerated_attributes
        attrs.reject { |attr| obj.send(attr).nil_or_empty? }
      end
    end
  end
end