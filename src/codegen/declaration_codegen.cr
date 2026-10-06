module DoisC
  module Codegen
    class DeclarationCodegen < BaseCodegen
      # Define a union type for top-level declarations in AST
      alias TopLevelDecl = ASTData::ProductTypeDeclaration | ASTData::UnionTypeDeclaration | ASTData::FunctionDeclaration

      def initialize(@type_codegen : TypeCodegen, @function_codegen : FunctionCodegen, @emitter : Emitter)
      end

      # Dispatch to the appropriate codegen for the specific top-level declaration
      def emit(decl : TopLevelDecl)
        case decl
        when ASTData::ProductTypeDeclaration
          @type_codegen.emit_product_declaration(decl)
        when ASTData::UnionTypeDeclaration
          @type_codegen.emit_union_declaration(decl)
        when ASTData::FunctionDeclaration
          @function_codegen.emit_function_declaration(decl)
        when ASTData::ProcedureDeclaration
          @function_codegen.emit_procedure_declaration(decl)
        else
          raise "Unsupported top-level declaration for codegen: #{decl.class}"
        end
      end

      # Emit all top-level declarations in the AST
      def emit_all(ast : ASTData::AST)
        ast.module_decl.body.each do |decl|
          case decl
          when TopLevelDecl
            emit(decl)
          end
        end
      end
    end
  end
end
