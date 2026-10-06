# require "../ast_data/token"

module DoisC
  module Parsing
    # Parses declaration of bindings, variables, modules, functions, procedures, and types.
    module DeclarationParser
      private def parse_module_declaration : ModuleDeclaration
        token = consume(TokenType::MODULE, "expected `module` to begin module declaration")
        name = consume(TokenType::IDENTIFIER, "expected module name identifier").lexeme
        consume(TokenType::HAS, "expected `has` after module name")
        statements = [] of Statement
        until match?(TokenType::END)
          statement = parse_statement
          statements << statement if statement
        end
        ModuleDeclaration.new(name, statements, location(token))
      end

      def parse_type_identifier(location : SourceLocation) : TypeID
        inner_types = [] of TypeID
        name = if t = match?(TokenType::IDENTIFIER)
                 t.lexeme
               else
                 "Tuple"
               end

        if match?(TokenType::L_PAREN)
          inner_types << parse_type_identifier(location)
          while match?(TokenType::COMMA)
            inner_types << parse_type_identifier(location)
          end
          consume(TokenType::R_PAREN, "expected ')' to end type args")
        end
        if match?(TokenType::QUESTION)
          inner_types = [TypeID.new(name, inner_types, location)]
          name = "Maybe"
        end
        TypeID.new(name, inner_types, location)
      end

      private def parse_binding : Statement
        token = consume(TokenType::IDENTIFIER, "expected binding identifier name")
        name = token.lexeme
        type_identifier = if colon_token = match?(TokenType::COLON)
                            parse_type_identifier(location(colon_token))
                          end
        consume(TokenType::EQ, "expected '=' after binding name")
        value_expr = parse_expression
        consume(TokenType::SEMICOLON, "expected ';' after binding value")
        Binding.new(name, value_expr, type_identifier, location(token))
      end

      private def parse_var_declaration : Statement
        token = consume(TokenType::IDENTIFIER, "expected variable identifier name")
        name = token.lexeme

        type_identifier = if colon_token = match?(TokenType::COLON)
                            parse_type_identifier(location(colon_token))
                          end

        value_expr = if match?(TokenType::EQ)
                       parse_expression
                     end
        consume(TokenType::SEMICOLON, "expected ';' after declaring var")
        VarDeclaration.new(name, value_expr, type_identifier, location(token))
      end

      private def parse_function_declaration : FunctionDeclaration
        token = consume(TokenType::FN, "expected `fn` to begin function declaration")
        name = consume(TokenType::IDENTIFIER, "expected function name for declaration").lexeme
        generics = parse_generics
        consume(TokenType::FN_APPLY, "expected '$' after function name")
        parameters = parse_parameters
        colon_token = consume(TokenType::COLON, "expected ':' followed by function return type annotation")

        return_type_identifier = parse_type_identifier(location(colon_token))

        consume(TokenType::ARROW, "expected => before function declaration body")
        body = parse_expression
        consume(TokenType::END, "expected 'end' to terminate function declaration body")
        FunctionDeclaration.new(name, parameters, generics, body, return_type_identifier, location(token))
      end

      private def parse_parameters : Array(Parameter)
        parameters = [] of Parameter
        if match?(TokenType::L_PAREN)
          unless peek.type == TokenType::R_PAREN
            parameters << parse_parameter
            while match?(TokenType::COMMA)
              parameters << parse_parameter
            end
          end
          consume(TokenType::R_PAREN, "expected ')' to end fuction args list")
        end
        parameters
      end

      private def parse_parameter : Parameter
        token = consume(TokenType::IDENTIFIER, "expected parameter identifier name")
        name = token.lexeme
        colon_token = consume(TokenType::COLON, "expected ':' followed by type annotation")
        type_identifier = parse_type_identifier(location(colon_token))
        Parameter.new(name, type_identifier, location(token))
      end

      private def parse_procedure_declaration : ProcedureDeclaration
        token = consume(TokenType::IDENTIFIER, "expected procedure name identifier")
        name = token.lexeme
        generics = parse_generics
        parameters = parse_parameters

        consume(TokenType::DO, "expected 'do' after before procedure declaration body")
        body = parse_procedure(TokenType::END)
        consume(TokenType::END, "expected 'end' to terminate function declaration body")
        ProcedureDeclaration.new(name, parameters, generics, body, location(token))
      end

      private def parse_type_declaration : Declaration
        token = consume(TokenType::TYPE, "expected `type` to begin type declaration")
        name = consume(TokenType::IDENTIFIER, "expected type identifier name for type declaration").lexeme
        generics = parse_generics
        return ProductTypeDeclaration.new(name, generics, parse_fields, location(token)) if match?(TokenType::HAS)
        if is_token = match?(TokenType::IS)
          return UnionTypeDeclaration.new(name, generics, parse_variants(location(is_token)), location(token))
        end
        raise error("expected `has` or `is` after type declaration name", peek)
      end

      private def parse_generics : Array(String)
        generics = [] of String
        if match?(TokenType::COMP_LT)
          generics << consume(TokenType::IDENTIFIER, "expected generic type identifier").lexeme
          while match?(TokenType::COMMA)
            generics << consume(TokenType::IDENTIFIER, "expected generic type identifier").lexeme
          end
          consume(TokenType::COMP_GT, "expected '>' to end generic list")
        end
        generics
      end

      private def parse_fields
        fields = [] of Field

        fields << parse_field
        while match?(TokenType::COMMA)
          fields << parse_field
        end
        consume(TokenType::END, "expected 'end' to terminate product type declaration")
        fields
      end

      private def parse_field : Field
        token = consume(TokenType::IDENTIFIER, "expected field name identifier")
        name = token.lexeme
        colon_token = consume(TokenType::COLON, "expected : for field type annotation")
        type_identifier = parse_type_identifier(location(colon_token))
        Field.new(name, type_identifier, location(token))
      end

      private def parse_variants(location : SourceLocation) : Array(TypeID)
        variants = [] of TypeID

        variants << parse_type_identifier(location)
        while match?(TokenType::BAR)
          variants << parse_type_identifier(location)
        end
        consume(TokenType::END, "expected `end` to terminate union type declaration")
        variants
      end
    end
  end
end
