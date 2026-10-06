require "../ast_data/ast"
require "./type_engine"

module DoisC
  module TypeChecking
    # The Verifier is responsible for walking the AST and checking type correctness.
    # It operates on a given VerificationContext, which provides variable scopes,
    # generic scopes, loop tracking, and the global environment.
    #
    # Responsibilities:
    #   1. Verify expressions and statements recursively, ensuring types match expectations.
    #   2. Handle function and procedure declarations, including generic parameters.
    #   3. Resolve product constructors and union variants with proper generic bindings.
    #   4. Check patterns and bind variables into the context for use in the body.
    #   5. Perform binary/unary operation type checking, including generics.
    #
    # The Verifier interacts closely with:
    #   - TypeEngine: for resolving type references and checking assignability.
    #   - GenericBinder: for binding generic parameters during calls and constructor instantiations.
    class Verifier
      include ASTData
      include ErrorReporter
      getter engine : TypeEngine
      getter global : Environment::Global

      # Initializes the Verifier with a given VerificationContext.
      # The context tracks local scopes, generics, loops, and the global environment.
      def initialize(@ctx : Environment::VerificationContext)
        @global = @ctx.globals
        @engine = TypeEngine.new(@global)
      end

      # Entry point for verifying an entire AST.
      # Iterates over all statements in the top-level procedure and verifies each.
      def verify_all(ast : AST)
        ast.module_decl.body.each do |stmt|
          verify_statement(stmt)
        end
      end

      # Walk each statement in a procedure
      def verify_statement(stmt : Statement)
        case stmt
        when Binding
          verify_binding(stmt)
        when Reassignment
          verify_reassignment(stmt)
        when VarDeclaration
          verify_var_declaration(stmt)
        when ExpressionStatement
          verify_expression(stmt.expression)
        when FunctionDeclaration
          verify_function(stmt)
        when ProcedureDeclaration
          verify_procedure(stmt)
        when ProductTypeDeclaration
          verify_product_type_declaration(stmt)
        when UnionTypeDeclaration
          verify_union_type_declaration(stmt)
        when WhileLoop
          verify_while_loop(stmt)
        when Break
          verify_break(stmt)
        when IfStatement
          verify_if_stmt(stmt)
        else
          raise error("Unsupported statement in verifier: #{stmt.class}", stmt.source_location)
        end
      end

      private def verify_match(expr : MatchExpression, expected_type : Types::Type? = nil) : Types::Type
        matched_type = verify_expression(expr.scrutinee)

        arm_types = expr.branches.map do |arm|
          @ctx.enter_scope

          # Bind pattern variables into scope based on matched type
          bind_pattern(arm.pattern, matched_type)

          arm_type = verify_expression(arm.body, expected_type)

          @ctx.exit_scope
          arm_type
        end

        result_type = arm_types.first

        arm_types.each do |t|
          engine.unify(result_type, t, expr.source_location)
        end

        engine.prune(result_type)
      end

      # Simple pattern verifier
      private def verify_pattern(pattern : Pattern) : Types::Type
        case pattern
        when LiteralPattern
          verify_expression(pattern.value)
        when BindingPattern
          any_def = global.type_definition(global.type_reference("Any").as(Types::NominalTypeReference)) ||
                    raise error("Missing type definition for Any", pattern.source_location)
          Types::NominalType.new(any_def, [] of Types::Type)
        when VariantPattern
          # Resolve the variant type (e.g., Some, Ok, Err)
          variant_name = pattern.name
          type_ref = global.type_reference(variant_name).as?(Types::NominalTypeReference) ||
                     raise error("Unknown variant '#{variant_name}'", pattern.source_location)

          type_def = global.type_definition(type_ref) ||
                     raise error("Missing type definition for variant '#{variant_name}'", pattern.source_location)

          # Return the nominal type for this variant (no generic instantiation yet)
          Types::NominalType.new(type_def, [] of Types::Type)
        else
          raise error("Unsupported pattern type #{pattern.class}", pattern.source_location)
        end
      end

      private def bind_pattern(pattern : Pattern, matched_type : Types::Type)
        case pattern
        when BindingPattern
          # Simple variable binding
          @ctx.declare(pattern.name, matched_type)
        when VariantPattern
          variant_name = pattern.name
          type_ref = global.type_reference(variant_name).as?(Types::NominalTypeReference) ||
                     raise error("Unknown variant '#{variant_name}'", pattern.source_location)

          type_def = global.type_definition(type_ref) ||
                     raise error("Missing type definition for variant '#{variant_name}'", pattern.source_location)

          return unless type_def.is_a?(Types::ProductTypeDefinition)

          generic_scope = @ctx.current_generic_scope
          field_names = type_def.fields.keys
          pattern_fields = pattern.field_patterns

          if pattern_fields.size != field_names.size
            raise error(
              "Variant '#{variant_name}' expects #{field_names.size} field(s), got #{pattern_fields.size}",
              pattern.source_location
            )
          end

          pattern_fields.each_with_index do |subpattern, index|
            field_name = field_names[index]
            field_ref = type_def.fields[field_name]
            field_type = engine.resolve_reference_to_type(field_ref, generic_scope)

            case subpattern
            when BindingPattern
              @ctx.declare(subpattern.name, field_type)
            when Reassignment
              # treat `field = v` as introducing variable `v` (the right-hand identifier)
              rhs = subpattern.value
              # If the right-hand side is an Identifier, declare its name
              if rhs.is_a?(Identifier)
                @ctx.declare(rhs.name, field_type)
                # If the right-hand side is a BindingPattern, declare its name
              elsif rhs.is_a?(BindingPattern)
                @ctx.declare(rhs.name, field_type)
                # If the right-hand side is a Pattern, recursively bind it
              elsif rhs.is_a?(Pattern)
                bind_pattern(rhs, field_type)
              end
            when Pattern
              bind_pattern(subpattern, field_type)
            end
          end
        when NamedFieldPattern
          field_pattern = pattern.pattern
          bind_pattern(field_pattern, matched_type)
        else
          # Other patterns do not introduce bindings
        end
      end

      private def verify_function(func : FunctionDeclaration)
        func.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, func.name)
        @ctx.enter_generic_scope
        func.generics.each do |gen_name|
          @ctx.bind_generic(gen_name, Types::GenericTypeParameter.new(gen_name))
        end

        # Declare function parameters in local scope
        @ctx.enter_scope
        func.params.each do |param|
          type = engine.parse_type_identifier(param.type_id, func.generics)
          param.resolved_type = type
          @ctx.declare(param.name, type)
        end

        # Set expected return type in context
        @ctx.with_return_type(engine.parse_type_identifier(func.return_type_id, func.generics)) do
          expected = engine.parse_type_identifier(func.return_type_id, func.generics)
          func.resolved_type = verify_expression(func.body, expected)
        end

        @ctx.exit_scope
        @ctx.exit_generic_scope
      end

      private def verify_procedure(proc : ProcedureDeclaration)
        proc.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, proc.name)
        @ctx.enter_generic_scope
        proc.generics.each do |gen_name|
          @ctx.bind_generic(gen_name, Types::GenericTypeParameter.new(gen_name))
        end

        @ctx.enter_scope
        proc.params.each do |param|
          type = engine.parse_type_identifier(param.type_id, proc.generics)
          param.resolved_type = type
          @ctx.declare(param.name, type)
        end

        # Construct a NominalType for Result before passing to with_return_type
        result_def = global.type_definition(global.type_reference("Result").as(Types::NominalTypeReference)) ||
                     raise error("Missing type definition for Result", proc.source_location)
        result_type = Types::NominalType.new(result_def, [] of Types::Type)
        proc.resolved_type = result_type

        @ctx.with_return_type(result_type) do
          proc.body.statements.each do |stmt|
            verify_statement(stmt)
          end
        end

        @ctx.exit_scope
        @ctx.exit_generic_scope
      end

      private def verify_var_declaration(decl : VarDeclaration)
        decl.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, decl.name)

        value_type =
          if value = decl.value
            verify_expression(value)
          elsif type_id = decl.type_id
            engine.parse_type_identifier(type_id)
          else
            raise error("Variable declaration '#{decl.name}' must have either a type annotation or an initializer", decl.source_location)
          end

        if type_id = decl.type_id
          annotated_type = engine.parse_type_identifier(type_id)

          if value = decl.value
            unless engine.is_assignable?(value_type, annotated_type)
              raise error(
                "Type mismatch in variable declaration '#{decl.name}': expected #{annotated_type}, got #{value_type}",
                value.source_location
              )
            end
          end

          decl.resolved_type = annotated_type
          @ctx.declare(decl.name, annotated_type, decl.symbol_ref)
        else
          decl.resolved_type = value_type
          @ctx.declare(decl.name, value_type, decl.symbol_ref)
        end
      end

      private def verify_binding(binding : Binding)
        binding.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, binding.name)
        name = binding.name
        value_type =
          if id = binding.type_id
            annotation_type = engine.parse_type_identifier(id)
            verify_expression(binding.value, annotation_type)
          else
            verify_expression(binding.value)
          end
        resolved_type = value_type

        binding.type_id.try do |type_id|
          annotation_type = engine.parse_type_identifier(type_id)

          unless engine.is_assignable?(value_type, annotation_type)
            raise error(
              "Type mismatch in binding '#{name}': expected #{annotation_type}, got #{value_type}",
              type_id.source_location
            )
          end
          resolved_type = annotation_type
        end

        binding.resolved_type = resolved_type
        generalized = engine.generalize(resolved_type)
        @ctx.declare(name, generalized, binding.symbol_ref)
      end

      # Verify an expression and return its resolved type
      private def verify_expression(expr : Expression, expected_type : Types::Type? = nil) : Types::Type
        case expr
        when IntLiteral
          expr.resolved_type = atomic_type("Int")
        when FloatLiteral
          expr.resolved_type = atomic_type("Float")
        when BoolLiteral
          expr.resolved_type = atomic_type("Bool")
        when CharLiteral
          expr.resolved_type = atomic_type("Char")
        when StringLiteral
          expr.resolved_type = atomic_type("String")
        when NilLiteral
          if expected_type && expected_type.is_a?(Types::NominalType)
            if expected_type.definition.is_a?(Types::UnionTypeDefinition)
              return expected_type
            end
          end
          atomic_type("Nil")
        when ArrayLiteral
          verify_array_literal(expr, expected_type)
        when TupleLiteral
          verify_tuple_literal(expr)
        when MapLiteral
          verify_map_literal(expr, expected_type)
        when IdentifierExpression
          expr.resolved_type = verify_identifier_expression(expr)
        when BinaryExpression
          expr.resolved_type = verify_binary(expr)
        when Call
          expr.resolved_type = verify_call(expr)
        when IfExpression
          expr.resolved_type = verify_if_expr(expr, expected_type)
        when MatchExpression
          expr.resolved_type = verify_match(expr, expected_type)
        when UnaryExpression
          expr.resolved_type = verify_unary(expr)
        when Reassignment
          verify_reassignment(expr)
        else
          raise error("Unsupported expression type in verifier: #{expr.class}", expr.source_location)
        end
      end

      private def verify_if_expr(expr : IfExpression, expected_type : Types::Type? = nil) : Types::Type
        branch_types = expr.branches.map do |branch|
          cond_type = verify_expression(branch.condition)
          unless cond_type.is_a?(Types::NominalType) && cond_type.definition.name == "Bool"
            raise error("If condition must be a Bool", branch.condition.source_location)
          end

          verify_expression(branch.body, expected_type)
        end

        # Verify the else branch if present
        else_type = (body = expr.else_body) ? verify_expression(body, expected_type) : nil

        # Combine all branch types
        all_types = branch_types
        all_types << else_type if else_type

        result_type = all_types.first

        all_types.each do |t|
          engine.unify(result_type, t, expr.source_location)
        end

        engine.prune(result_type)
      end

      private def verify_if_stmt(stmt : IfStatement)
        stmt.branches.each do |branch|
          branch.body.statements.each do |stmt|
            verify_statement(stmt)
          end
        end
        if body = stmt.else_body
          body.statements.each do |stmt|
            verify_statement(stmt)
          end
        end
      end

      private def atomic_type(name : String) : Types::NominalType
        ref = global.type_reference(name).as?(Types::NominalTypeReference) ||
              raise "Atomic type #{name} not registered in global env"
        defn = global.type_definition(ref) ||
               raise "Atomic type definition missing for #{name}"
        Types::NominalType.new(defn, [] of Types::Type)
      end

      private def global : Environment::Global
        @ctx.globals
      end

      private def verify_identifier_expression(expr : IdentifierExpression) : Types::Type
        type = verify_identifier(expr.identifier)
        type
      end

      private def verify_identifier(id : Identifier) : Types::Type
        # First, look in local scope
        binding = @ctx.lookup_binding(id.name)
        type = binding ? binding.type : nil

        if binding && binding.symbol_ref
          id.symbol_ref = binding.symbol_ref
        end

        # Instantiate polymorphic types when they are used
        if type
          type = engine.instantiate(type)
        end
        if type.nil?
          # Check if it's a product constructor
          type_ref = global.type_reference(id.name).as?(Types::NominalTypeReference)
          if type_ref
            type_def = global.type_definition(type_ref)
            if type_def.is_a?(Types::ProductTypeDefinition)
              type = Types::NominalType.new(type_def, type_def.generics.map { |_| engine.fresh_type_variable.as(Types::Type) })
              id.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, id.name)
            end
          end
          # Check if it's a global function or procedure
          if type.nil?
            if func_def = global.function_definition(id.name)
              begin
                generic_scope = {} of String => Types::GenericTypeParameter
                func_def.generics.each do |g|
                  generic_scope[g] = Types::GenericTypeParameter.new(g)
                end
                type = engine.resolve_reference_to_type(
                  func_def.type_ref,
                  generic_scope
                )
                type = engine.instantiate(type)
                id.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, id.name)
              rescue e : Exception
                raise error(e.message, id.source_location)
              end
            end
          end

          if type.nil? && global.builtin?(id.name)
            raise error("Builtin #{id.name} must be used in a call position", id.source_location)
          end

          # Still not found → error
          raise error("Undefined identifier #{id.name}", id.source_location) if type.nil?
        end

        # Handle accessor chains as before
        id.accessor_names.each do |accessor_name|
          case type
          when Types::NominalType
            type_def = type.definition

            case type_def
            when Types::ProductTypeDefinition
              field_ref = type_def.fields[accessor_name]? ||
                          raise error("#{type_def.name} has no field #{accessor_name}", id.source_location)
              type = engine.resolve_reference_to_type(field_ref, @ctx.current_generic_scope)
            when Types::UnionTypeDefinition
              variant_field_types = type_def.variants.compact_map do |variant_ref|
                variant_def = global.type_definition(variant_ref) ||
                              raise error("Unknown variant #{variant_ref.name}", id.source_location)

                case variant_def
                when Types::ProductTypeDefinition
                  field_ref = variant_def.fields[accessor_name]?
                  if field_ref
                    engine.resolve_reference_to_type(field_ref, @ctx.current_generic_scope)
                  end
                else
                  nil
                end
              end

              raise error("No variant defines field '#{accessor_name}'", id.source_location) if variant_field_types.empty?

              unique = variant_field_types.uniq
              raise error("Inconsistent field types across union variants", id.source_location) if unique.size != 1

              type = unique.first
            else
              raise error("Type #{type_def.name} does not support field access", id.source_location)
            end
          else
            raise error("Cannot access field '#{accessor_name}' on #{type.class}", id.source_location)
          end
        end

        # Ensure we always return a Types::Type, never nil
        unless type
          raise "Internal error: verify_identifier could not resolve a type for #{id.name}"
        end
        type
      end

      private def verify_call(call_expr : Call) : Types::Type
        callee_expr = call_expr.callee

        if callee_expr.is_a?(IdentifierExpression)
          callee_name = callee_expr.identifier.name

          if global.builtin?(callee_name)
            case callee_name
            when "print"
              return verify_builtin_print(call_expr)
            else
              raise error("Unsupported builtin #{callee_name}", call_expr.source_location)
            end
          end

          type_ref = global.type_reference(callee_name).as?(Types::NominalTypeReference)
          type_def = type_ref && global.type_definition(type_ref)

          if type_def.is_a?(Types::ProductTypeDefinition)
            return verify_constructor_call(call_expr, type_def)
          end
        end

        verify_function_call(call_expr)
      end

      private def verify_builtin_print(call_expr : Call) : Types::Type
        if call_expr.arguments.size != 1
          raise error("print expects exactly 1 argument", call_expr.source_location)
        end

        arg_type = verify_expression(call_expr.arguments.first)

        printable = case arg_type
                    when Types::NominalType
                      ["Int", "Float", "Bool", "Char", "String"].includes?(arg_type.definition.name)
                    else
                      false
                    end

        unless printable
          raise error("print does not support values of type #{arg_type}", call_expr.arguments.first.source_location)
        end

        atomic_type("Nil")
      end

      # Handles product type constructor calls like Some(value = 3)
      private def verify_constructor_call(call_expr : Call, type_def : Types::ProductTypeDefinition) : Types::Type
        callee_expr = call_expr.callee.as(IdentifierExpression)
        callee_name = callee_expr.identifier.name

        # Remove: bindings = {} of String => Types::Type
        # Instead, use a fresh generic_scope with type variables for generics
        generic_scope = {} of String => Types::Type
        type_def.generics.each do |gen|
          generic_scope[gen] = engine.fresh_type_variable
        end

        field_types = type_def.fields
        field_names = field_types.keys

        arg_map = {} of String => Expression
        used_fields = [] of String

        call_expr.arguments.each_with_index do |arg, idx|
          if arg.is_a?(Reassignment)
            field_name = arg.identifier.name

            unless field_types.has_key?(field_name)
              raise error(
                "Unknown field '#{field_name}' for constructor #{callee_name}",
                arg.identifier.source_location
              )
            end

            arg_map[field_name] = arg.value
            used_fields << field_name
          else
            field_name = field_names[idx]?
            raise error(
              "Too many arguments for #{callee_name}",
              call_expr.source_location
            ) unless field_name

            arg_map[field_name] = arg
            used_fields << field_name
          end
        end

        missing_fields = field_types.keys - used_fields
        unless missing_fields.empty?
          raise error(
            "Missing field(s) in constructor call to #{callee_name}: #{missing_fields.join(", ")}",
            call_expr.source_location
          )
        end

        field_types.each do |field_name, field_type_ref|
          arg_expr = arg_map[field_name]
          param_type = engine.resolve_reference_to_type(field_type_ref, generic_scope)
          param_type = engine.instantiate(param_type)

          arg_type =
            case arg_expr
            when IdentifierExpression
              verify_identifier(arg_expr.identifier)
            when Reassignment
              # If reassignment, the identifier may need generic_scope as well
              if arg_expr.identifier.is_a?(Identifier)
                verify_identifier(arg_expr.identifier)
              else
                verify_expression(arg_expr)
              end
            else
              verify_expression(arg_expr)
            end
          arg_type = engine.instantiate(arg_type)
          engine.unify(param_type, arg_type, call_expr.source_location)
        end

        # type_args = type_def.generics.map { |gen| bindings[gen]? || Types::GenericTypeParameter.new(gen) }
        type_args = type_def.generics.map { |gen| engine.prune(generic_scope[gen]) }

        Types::NominalType.new(type_def, type_args)
      end

      # Handles normal function calls
      private def verify_function_call(call_expr : Call) : Types::Type
        # Resolve callee type
        callee_type = verify_expression(call_expr.callee)

        # Enter a fresh generic scope for this call
        callee_type = engine.instantiate(callee_type)

        unless callee_type.is_a?(Types::FunctionType)
          raise error("Expected a function after instantiation", call_expr.source_location)
        end

        func_type = callee_type.as(Types::FunctionType)

        # Verify arguments and unify with parameter types
        call_expr.arguments.each_with_index do |arg_expr, i|
          arg_type = verify_expression(arg_expr)
          engine.unify(func_type.param_types[i], arg_type, arg_expr.source_location)
        end

        engine.prune(func_type.return_type)
      end

      private def verify_binary(expr : BinaryExpression) : Types::Type
        left_type = verify_expression(expr.left)
        right_type = verify_expression(expr.right)

        # If either side is a generic type parameter, defer strict checking
        if left_type.is_a?(Types::GenericTypeParameter) || right_type.is_a?(Types::GenericTypeParameter)
          case expr.operator.type
          when ASTData::OperatorType::ADD, ASTData::OperatorType::SUB,
               ASTData::OperatorType::MULT, ASTData::OperatorType::DIV
            return left_type
          else
            raise error("Unsupported generic binary operator #{expr.operator}", expr.source_location)
          end
        end

        # Ensure operands are NominalTypes
        case left_type
        when Types::FunctionType
          raise error("Cannot use a function as the left operand in a binary expression", expr.left.source_location)
        when Types::NominalType
          left_nominal = left_type
        else
          raise error("Unsupported left operand type #{left_type.class} in binary expression", expr.left.source_location)
        end

        case right_type
        when Types::FunctionType
          raise error("Cannot use a function as the right operand in a binary expression", expr.right.source_location)
        when Types::NominalType
          right_nominal = right_type
        else
          raise error("Unsupported right operand type #{right_type.class} in binary expression", expr.right.source_location)
        end

        case expr.operator.type
        when ASTData::OperatorType::ADD, ASTData::OperatorType::SUB,
             ASTData::OperatorType::MULT, ASTData::OperatorType::DIV
          numeric_types = ["Int", "Float"]
          if numeric_types.includes?(left_nominal.definition.name) && numeric_types.includes?(right_nominal.definition.name)
            result_type = (left_nominal.definition.name == "Float" || right_nominal.definition.name == "Float") ? "Float" : "Int"
            atomic_type(result_type)
          else
            raise error("Arithmetic operator #{expr.operator} applied to non-numeric types: #{left_nominal.definition.name}, #{right_nominal.definition.name}", expr.source_location)
          end
        when ASTData::OperatorType::EQ, ASTData::OperatorType::LT
          # TODO implement when EQ for not nomminal types (i.e. recurse)
          if left_nominal.definition.name == right_nominal.definition.name
            atomic_type("Bool")
          else
            raise error("Boolean operator #{expr.operator} applied to two different types; left: #{left_nominal.definition.name}, right: #{right_nominal.definition.name}", expr.source_location)
          end
        else
          raise error("Unsupported binary operator #{expr.operator}", expr.source_location)
        end
      end

      private def verify_unary(expr : UnaryExpression) : Types::Type
        operand_type = verify_expression(expr.right)

        case expr.operator
        when ASTData::TokenType::NOT
          unless operand_type.is_a?(Types::NominalType) &&
                 operand_type.definition.name == "Bool"
            raise error("Unary NOT requires Bool operand", expr.right.source_location)
          end
          atomic_type("Bool")
        when ASTData::TokenType::SUB
          unless operand_type.is_a?(Types::NominalType) &&
                 ["Int", "Float"].includes?(operand_type.definition.name)
            raise error("Unary - requires numeric operand", expr.right.source_location)
          end
          operand_type
        else
          raise error("Unsupported unary operator #{expr.operator}", expr.source_location)
        end
      end

      private def verify_reassignment(stmt : Reassignment) : Types::Type
        var_type = @ctx.lookup(stmt.identifier.name) ||
                   raise error("Undefined variable #{stmt.identifier.name}", stmt.identifier.source_location)

        value_type = verify_expression(stmt.value)

        unless engine.is_assignable?(value_type, var_type)
          raise error(
            "Type mismatch in reassignment '#{stmt.identifier.name}': expected #{var_type}, got #{value_type}",
            stmt.value.source_location
          )
        end

        var_type
      end

      # Verify a WhileLoop: check the condition is Bool, enter loop context, verify body, return Nil
      private def verify_while_loop(loop : ASTData::WhileLoop) : Types::Type
        cond_type = verify_expression(loop.condition)
        unless cond_type.is_a?(Types::NominalType) && cond_type.definition.name == "Bool"
          raise error("While loop condition must be a Bool", loop.condition.source_location)
        end
        @ctx.enter_loop
        loop.body.statements.each do |stmt|
          verify_statement(stmt)
        end
        @ctx.exit_loop
        atomic_type("Nil")
      end

      # Verify a Break: ensure inside loop, return Nil
      private def verify_break(stmt : ASTData::Break) : Types::Type
        unless @ctx.inside_loop?
          raise error("`break` statement not inside a loop", stmt.source_location)
        end
        atomic_type("Nil")
      end

      private def verify_array_literal(expr : ASTData::ArrayLiteral, expected_type : Types::Type? = nil) : Types::Type
        if expr.items.empty?
          if expected_type && expected_type.is_a?(Types::NominalType) &&
             expected_type.definition.name == "Array" &&
             expected_type.type_args.size == 1
            return expected_type
          else
            raise error("Cannot infer type of empty array without context", expr.source_location)
          end
        end

        item_types = expr.items.map { |item| verify_expression(item).as(Types::Type) }
        first_type = item_types.first

        item_types.each_with_index do |t, i|
          unless engine.is_assignable?(t, first_type) || engine.is_assignable?(first_type, t)
            raise error("Array elements have incompatible types at index #{i}: #{t} vs #{first_type}", expr.items[i].source_location)
          end
        end

        array_def = global.type_definition(global.type_reference("Array").as(Types::NominalTypeReference)) ||
                    raise error("Missing type definition for Array", expr.source_location)

        Types::NominalType.new(array_def, [first_type])
      end

      private def verify_tuple_literal(expr : ASTData::TupleLiteral) : Types::Type
        item_types = expr.items.map { |item| verify_expression(item).as(Types::Type) }

        tuple_def = global.type_definition(global.type_reference("Tuple").as(Types::NominalTypeReference)) ||
                    raise "Missing type definition for Tuple"

        Types::NominalType.new(tuple_def, item_types)
      end

      private def verify_map_literal(expr : ASTData::MapLiteral, expected_type : Types::Type? = nil) : Types::Type
        if expr.mappings.empty?
          if expected_type && expected_type.is_a?(Types::NominalType) &&
             expected_type.definition.name == "Map" &&
             expected_type.type_args.size == 2
            return expected_type
          else
            raise error("Cannot infer type of empty map without context", expr.source_location)
          end
        end

        key_types = expr.mappings.keys.map { |k| verify_expression(k).as(Types::Type) }
        value_types = expr.mappings.values.map { |v| verify_expression(v).as(Types::Type) }

        first_key_type = key_types.first
        first_value_type = value_types.first

        key_types.each_with_index do |k, i|
          unless engine.is_assignable?(k, first_key_type) || engine.is_assignable?(first_key_type, k)
            raise error("Map keys have incompatible types at index #{i}", expr.mappings.keys[i].source_location)
          end
        end

        value_types.each_with_index do |v, i|
          unless engine.is_assignable?(v, first_value_type) || engine.is_assignable?(first_value_type, v)
            raise error("Map values have incompatible types at index #{i}", expr.mappings.values[i].source_location)
          end
        end

        map_def = global.type_definition(global.type_reference("Map").as(Types::NominalTypeReference)) ||
                  raise error("Missing type definition for Map", expr.source_location)

        Types::NominalType.new(map_def, [first_key_type, first_value_type])
      end

      # Verifies a ProductTypeDeclaration: checks field types and registers the type in the current context.
      private def verify_product_type_declaration(decl : ASTData::ProductTypeDeclaration)
        decl.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, decl.name)
        # Parse and verify all field types
        field_types = {} of String => Types::NominalTypeReference
        decl.fields.each do |field|
          # Parse the type identifier of the field
          # The field type_id may refer to generics in decl.generics
          type = engine.parse_type_identifier(field.type_id, decl.generics)
          # Store as a type reference (for field table)
          ref =
            case type
            when Types::NominalType
              Types::NominalTypeReference.new(type.definition.name)
            when Types::GenericTypeParameter
              Types::NominalTypeReference.new(type.name)
            else
              # Fallback: use the type's class name
              Types::NominalTypeReference.new(type.to_s)
            end
          field_types[field.name] = ref
          field.resolved_type = type
        end

        # TODO decide if this was a bug
        # # Build the constructor type reference: zero-parameter function returning this product type
        # # Use the product's own type reference as the return type
        # constructor_type_ref = Types::FunctionTypeReference.new(
        #   {} of String => Types::NominalTypeReference,
        #   Types::NominalTypeReference.new(decl.name),         # return type is the product itself
        #   [] of String
        # )

        # # Create the ProductTypeDefinition with correct arguments: name, generics, fields, constructor_type_ref
        # product_def = Types::ProductTypeDefinition.new(
        #   decl.name,
        #   decl.generics,
        #   field_types,
        #   constructor_type_ref
        # )

        # Instead of registering, verify this product type matches the global definition.
        global_def = global.type_definition(Types::NominalTypeReference.new(decl.name))
        unless global_def && global_def.is_a?(Types::ProductTypeDefinition)
          raise error("Product type '#{decl.name}' not found in global environment", decl.source_location)
        end
        # Check generics match
        if global_def.generics != decl.generics
          raise error("Product type '#{decl.name}' generics mismatch: expected #{global_def.generics.inspect}, got #{decl.generics.inspect}", decl.source_location)
        end
        # Check fields match
        decl.fields.each do |field|
          expected_ref = global_def.fields[field.name]?
          if expected_ref.nil?
            raise error("Product type '#{decl.name}' missing field '#{field.name}' in global definition", field.source_location)
          end
          # Parse the type identifier as in above
          resolved_type = engine.parse_type_identifier(field.type_id, decl.generics)
          # The expected_ref may be a generic or nominal type reference
          # For comparison, resolve the reference to a type (using generics if needed)
          # If it's a generic parameter, just compare names
          if expected_ref.is_a?(Types::NominalTypeReference) && decl.generics.includes?(expected_ref.name)
            unless resolved_type.is_a?(Types::GenericTypeParameter) && resolved_type.name == expected_ref.name
              raise error("Field '#{field.name}' in product type '#{decl.name}' should be generic '#{expected_ref.name}', got #{resolved_type}", field.source_location)
            end
          else
            # Otherwise, resolve expected_ref to a type and compare
            expected_type =
              if g = @ctx.lookup_generic(expected_ref.name)
                g
              else
                type_def = global.type_definition(expected_ref) ||
                           raise error("Unknown type reference '#{expected_ref.name}' for field '#{field.name}'", field.source_location)
                Types::NominalType.new(type_def, [] of Types::Type)
              end
            unless engine.is_assignable?(resolved_type, expected_type) && engine.is_assignable?(expected_type, resolved_type)
              raise error("Field '#{field.name}' type mismatch in product type '#{decl.name}': expected #{expected_type}, got #{resolved_type}", field.source_location)
            end
          end
        end
      end

      # Verifies a UnionTypeDeclaration: checks generics and variants against the global environment,
      # handling generics and generic product variants (e.g., Some(T)).
      private def verify_union_type_declaration(decl : ASTData::UnionTypeDeclaration)
        decl.symbol_ref ||= ASTData::SymbolRef.new(@ctx.current_module_scope, decl.name)
        # Lookup the union type in the global environment.
        global_def = global.type_definition(Types::NominalTypeReference.new(decl.name))
        unless global_def && global_def.is_a?(Types::UnionTypeDefinition)
          raise error("Union type '#{decl.name}' not found in global environment", decl.source_location)
        end
        # Check generics match
        if global_def.generics != decl.generics
          raise error("Union type '#{decl.name}' generics mismatch: expected #{global_def.generics.inspect}, got #{decl.generics.inspect}", decl.source_location)
        end

        # For each variant in the union declaration, resolve its type (with generics), and ensure a corresponding type definition exists.
        decl.variants.each do |variant_type_id|
          # Parse the type identifier of the variant, using the union's generics.
          begin
            resolved_variant_type = engine.parse_type_identifier(variant_type_id, decl.generics)
          rescue ex
            raise error("Failed to resolve variant '#{variant_type_id.name}' in union type '#{decl.name}': #{ex}", variant_type_id.source_location)
          end

          # Find the type definition for this variant in the global environment.
          variant_type_name =
            case resolved_variant_type
            when Types::NominalType
              resolved_variant_type.definition.name
            when Types::GenericTypeParameter
              resolved_variant_type.name
            else
              variant_type_id.name
            end
          variant_type_ref = Types::NominalTypeReference.new(variant_type_name)
          variant_def = global.type_definition(variant_type_ref)
          unless variant_def
            raise error("Union type '#{decl.name}' has variant '#{variant_type_id.name}' which is not defined in the global environment", variant_type_id.source_location)
          end
        end
      end

      private def current_symbol(name : String)
        ASTData::SymbolRef.new(@ctx.current_module_scope, name)
      end
    end
  end
end
