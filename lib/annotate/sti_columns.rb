require 'set'

module Annotate
  module StiColumns
    class << self
      def subclass?(klass)
        klass.superclass < ActiveRecord::Base &&
          klass.table_name == klass.superclass.table_name
      end

      def base_class?(klass)
        klass.column_names.include?(klass.inheritance_column) &&
          klass.subclasses.any? { |d| d.table_name == klass.table_name }
      end

      def columns_referenced_in(klass)
        cols = Set.new
        cols.merge(klass.validators.flat_map { |v| v.attributes.map(&:to_s) })
        if klass.respond_to?(:reflect_on_all_associations)
          cols.merge(
            klass.reflect_on_all_associations(:belongs_to).flat_map { |a|
              fk = [a.foreign_key.to_s]
              fk << "#{a.name}_type" if a.respond_to?(:polymorphic?) && a.polymorphic?
              fk
            }
          )
        end
        cols.merge(klass.defined_enums.keys) if klass.respond_to?(:defined_enums)
        if klass.respond_to?(:stored_attributes) && klass.stored_attributes.any?
          cols.merge(klass.stored_attributes.values.flatten.map(&:to_s))
        end
        cols
      end

      def columns_owned_by(klass)
        return Set.new unless subclass?(klass)

        columns_referenced_in(klass) - columns_referenced_in(klass.superclass)
      end

      def partition(klass, cols)
        if subclass?(klass)
          partition_for_subclass(klass, cols)
        elsif base_class?(klass)
          partition_for_base_class(klass, cols)
        else
          [[nil, cols]]
        end
      end

      private

      def partition_for_subclass(klass, cols)
        owned = columns_owned_by(klass)
        base_name = klass.superclass.name.demodulize
        shared = cols.reject { |c| owned.include?(c.name.to_s) }
        specific = cols.select { |c| owned.include?(c.name.to_s) }

        groups = []
        groups << ["#{base_name} columns", shared] if shared.any?
        groups << ["#{klass.name.demodulize} columns", specific] if specific.any?
        groups
      end

      def partition_for_base_class(klass, cols)
        sti_subclasses = klass.subclasses.select { |d| d.table_name == klass.table_name }.sort_by(&:name)
        ownership = {}

        sti_subclasses.each do |sub|
          columns_owned_by(sub).each do |col_name|
            ownership[col_name] ||= sub.name.demodulize
          end
        end

        base_cols = cols.reject { |c| ownership.key?(c.name.to_s) }
        groups = [["#{klass.name.demodulize} columns", base_cols]]

        sti_subclasses.each do |sub|
          sub_name = sub.name.demodulize
          sub_cols = cols.select { |c| ownership[c.name.to_s] == sub_name }
          groups << ["#{sub_name} columns", sub_cols] if sub_cols.any?
        end
        groups
      end
    end
  end
end
