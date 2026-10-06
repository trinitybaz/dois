module DoisC
  module Codegen
    class TypeCodegen < BaseCodegen
      def initialize(@emitter : Emitter)
      end

      # Maps a resolved Dois type into a concrete C type spelling.
      # This will be used later by expression/function codegen.
      def c_type(type : Types::Type) : String
        case type
        when Types::NominalType
          case type.name
          when "Int"
            "int64_t"
          when "Float"
            "double"
          when "Bool"
            "bool"
          when "String"
            "const char*"
          when "Nil"
            "void"
          else
            "struct #{sanitize_name(type.name)}"
          end
        else
          "void"
        end
      end

      def emit_product_declaration(decl : ASTData::ProductTypeDeclaration)
        name = sanitize_name(decl.name)

        writeln "struct #{name} {"
        with_indent do
          decl.fields.each do |field|
            field_type = !field.resolved_type.nil? ? c_type(field.resolved_type.not_nil!) : "void*"

            writeln "#{field_type} #{field.name};"
          end
        end
        writeln "};"
        newline
      end

      def emit_union_declaration(decl : ASTData::UnionTypeDeclaration)
        name = sanitize_name(decl.name)

        writeln "struct #{name} {"
        with_indent do
          writeln "int tag;"
          writeln "union {"
          with_indent do
            decl.variants.each_with_index do |variant, index|
              variant_name = sanitize_name(variant.name)
              payload_type = "int"
              writeln "#{payload_type} #{variant_name}; // tag #{index}"
            end
          end
          writeln "} as;"
        end
        writeln "};"
        newline
      end

      private def sanitize_name(name : String) : String
        name.gsub(/[^A-Za-z0-9_]/, "_")
      end
    end
  end
end
