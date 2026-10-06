require "../environment/global"
require "./error_reporter"

module DoisC
  module TypeChecking
    # The TypeEngine provides core functionality for working with types in the Verifier.
    # It is responsible for:
    #   1. Instantiating type definitions into concrete Types with proper type arguments.
    #   2. Resolving TypeReferences (nominal and function) into concrete Types,
    #      handling generic parameters using the provided generic scope.
    #   3. Determining type assignability, including handling generics, unions, nil, and function types.
    class TypeEngine
      include ErrorReporter
      getter global : Environment::Global

      @next_type_var_id : Int32 = 0

      def initialize(@global : Environment::Global)
      end

      # Instantiate a TypeDefinition with optional type arguments into a concrete Type.
      def instantiate_type(definition : Types::TypeDefinition, type_args = [] of Types::Type) : Types::Type
        Types::NominalType.new(definition, type_args)
      end

      # Resolves a TypeReference into a concrete Type, using the provided generic scope.
      # Handles NominalTypeReference and FunctionTypeReference.
      # Raises an error for unknown or unsupported type references.
      def resolve_reference_to_type(ref : Types::TypeReference, generic_scope : Hash(String, Types::Type)) : Types::Type
        case ref
        when Types::NominalTypeReference
          # Only NominalTypeReference has a name
          if g = generic_scope[ref.name]?
            return g
          end

          type_def = global.type_definition(ref) ||
                     raise "Unknown type reference #{ref.name}"

          # Resolve type arguments recursively
          resolved_args = ref.type_args.map do |arg_ref|
            resolve_reference_to_type(arg_ref, generic_scope).as(Types::Type)
          end

          instantiate_type(type_def, resolved_args)
        when Types::FunctionTypeReference
          # Create a fresh substitutions hash for function generics
          substitutions = Hash(String, DoisC::Types::Type).new
          generic_scope.each do |k, v|
            substitutions[k] = v
          end
          ref.generics.each do |gen|
            substitutions[gen] = fresh_type_variable
          end

          param_types = ref.param_type_refs.keys.map do |key|
            resolve_reference_to_type(ref.param_type_refs[key], substitutions).as(Types::Type)
          end

          return_type = resolve_reference_to_type(ref.return_type_ref, substitutions)

          Types::FunctionType.new(param_types, return_type)
        else
          raise "Unsupported TypeReference #{ref.class}"
        end
      end

      # Determines whether a type `from` can be assigned to type `to`.
      # Handles exact match, generic parameters, unions, nil, and function types.
      def is_assignable?(from : Types::Type, to : Types::Type, bindings = {} of String => Types::Type) : Bool
        if from.is_a?(Types::TypeVariable)
          if from.instance
            return is_assignable?(from.instance.not_nil!, to, bindings)
          end

          # Unbound type variable can become anything
          return true
        end

        if to.is_a?(Types::TypeVariable)
          if to.instance
            return is_assignable?(from, to.instance.not_nil!, bindings)
          end

          # Allow assignment into an unbound variable
          return true
        end
        # Exact match
        return true if from == to

        # Resolve generic parameters
        if from.is_a?(Types::GenericTypeParameter)
          resolved_from = bindings[from.name] || from
          return is_assignable?(resolved_from, to, bindings)
        end

        if to.is_a?(Types::GenericTypeParameter)
          resolved_to = bindings[to.name] || to
          return is_assignable?(from, resolved_to, bindings)
        end

        # Nil handling
        if from.is_a?(Types::NominalType) &&
           from.definition.is_a?(Types::AtomicTypeDefinition) &&
           from.definition.as(Types::AtomicTypeDefinition).atomic == Types::Atomic::NIL
          if to.is_a?(Types::NominalType) && to.definition.is_a?(Types::UnionTypeDefinition)
            union_def = to.definition.as(Types::UnionTypeDefinition)
            return union_def.variants.any? do |vref|
              variant_def = global.type_definition(vref) || raise "Unknown variant #{vref.name}"
              variant_type = Types::NominalType.new(variant_def, [] of Types::Type)
              is_assignable?(from, variant_type, bindings)
            end
          end
        end

        # From is a union
        if from.is_a?(Types::NominalType) && from.definition.is_a?(Types::UnionTypeDefinition)
          union_def = from.definition.as(Types::UnionTypeDefinition)
          return union_def.variants.all? do |vref|
            variant_def = global.type_definition(vref) || raise "Unknown variant #{vref.name}"
            variant_type = Types::NominalType.new(variant_def, from.type_args)
            is_assignable?(variant_type, to, bindings)
          end
        end

        # To is a union
        if to.is_a?(Types::NominalType) && to.definition.is_a?(Types::UnionTypeDefinition)
          union_def = to.definition.as(Types::UnionTypeDefinition)
          return union_def.variants.any? do |vref|
            variant_def = global.type_definition(vref) || raise "Unknown variant #{vref.name}"
            variant_type = Types::NominalType.new(variant_def, to.type_args)
            is_assignable?(from, variant_type, bindings)
          end
        end

        # Nominal types with type args
        if from.is_a?(Types::NominalType) && to.is_a?(Types::NominalType)
          return false unless from.definition.name == to.definition.name
          return from.type_args.each_with_index.all? do |f_arg, i|
            t_arg = to.type_args[i]
            is_assignable?(f_arg, t_arg, bindings)
          end
        end

        # Function types
        if from.is_a?(Types::FunctionType) && to.is_a?(Types::FunctionType)
          return false unless from.param_types.size == to.param_types.size
          params_ok = from.param_types.each_with_index.all? do |f_arg, i|
            is_assignable?(f_arg, to.param_types[i], bindings)
          end
          return params_ok && is_assignable?(from.return_type, to.return_type, bindings)
        end

        false
      end

      # Generates a fresh type variable for Hindley–Milner inference.
      def fresh_type_variable : Types::TypeVariable
        t = Types::TypeVariable.new(@next_type_var_id)
        @next_type_var_id += 1
        t
      end

      # Collect all TypeVariable instances inside a type.
      private def collect_type_variables(type : Types::Type, acc = [] of Types::TypeVariable)
        case type
        when Types::TypeVariable
          acc << type unless acc.includes?(type)
        when Types::NominalType
          type.type_args.each { |t| collect_type_variables(t, acc) }
        when Types::FunctionType
          type.param_types.each { |t| collect_type_variables(t, acc) }
          collect_type_variables(type.return_type, acc)
        end

        acc
      end

      # Generalize a type by converting its TypeVariables into GenericTypeParameters.
      # This is used when storing a value in a let-binding so it can be reused polymorphically.
      def generalize(type : Types::Type) : Types::Type
        vars = collect_type_variables(type)
        mapping = {} of Types::TypeVariable => Types::GenericTypeParameter

        vars.each_with_index do |tv, i|
          mapping[tv] = Types::GenericTypeParameter.new("T#{i}")
        end

        replace_type_variables(type, mapping)
      end

      # Instantiate a generalized type by replacing GenericTypeParameters with fresh TypeVariables.
      # This happens when a variable is read from the environment.
      def instantiate(type : Types::Type) : Types::Type
        case type
        when Types::GenericTypeParameter
          fresh_type_variable
        when Types::NominalType
          # If the definition has generics but no type args, create fresh ones
          generics = case defn = type.definition
                     when Types::ProductTypeDefinition
                       defn.generics
                     when Types::UnionTypeDefinition
                       defn.generics
                     else
                       [] of String
                     end

          if generics.empty?
            return type
          end

          mapping = {} of String => Types::TypeVariable
          generics.each do |gen|
            mapping[gen] = fresh_type_variable
          end

          new_args = generics.map { |gen| mapping[gen].as(Types::Type) }
          Types::NominalType.new(type.definition, new_args)
        when Types::FunctionType
          params = type.param_types.map { |t| instantiate(t).as(Types::Type) }
          ret = instantiate(type.return_type)
          Types::FunctionType.new(params, ret)
        else
          type
        end
      end

      # Replace TypeVariables using a mapping.
      private def replace_type_variables(type : Types::Type, mapping : Hash(Types::TypeVariable, Types::GenericTypeParameter)) : Types::Type
        case type
        when Types::TypeVariable
          mapping[type]? || type
        when Types::NominalType
          new_args = type.type_args.map { |t| replace_type_variables(t, mapping) }
          Types::NominalType.new(type.definition, new_args)
        when Types::FunctionType
          params = type.param_types.map { |t| replace_type_variables(t, mapping) }
          ret = replace_type_variables(type.return_type, mapping)
          Types::FunctionType.new(params, ret)
        else
          type
        end
      end

      # Replace GenericTypeParameters with fresh TypeVariables.
      private def replace_generics_with_fresh(type : Types::Type, mapping : Hash(String, Types::TypeVariable)) : Types::Type
        case type
        when Types::GenericTypeParameter
          mapping[type.name] ||= fresh_type_variable
        when Types::NominalType
          new_args = type.type_args.map { |t| replace_generics_with_fresh(t, mapping) }
          Types::NominalType.new(type.definition, new_args)
        when Types::FunctionType
          params = type.param_types.map { |t| replace_generics_with_fresh(t, mapping) }
          ret = replace_generics_with_fresh(type.return_type, mapping)
          Types::FunctionType.new(params, ret)
        else
          type
        end
      end

      # Hindley–Milner helper functions as instance methods
      def prune(type : Types::Type) : Types::Type
        case type
        when Types::TypeVariable
          if type.instance
            type.instance = prune(type.instance.not_nil!)
            return type.instance.not_nil!
          end
          type
        when Types::NominalType
          new_args = type.type_args.map { |t| prune(t) }
          Types::NominalType.new(type.definition, new_args)
        when Types::FunctionType
          params = type.param_types.map { |t| prune(t) }
          ret = prune(type.return_type)
          Types::FunctionType.new(params, ret)
        else
          type
        end
      end

      def occurs_in_type(var : Types::TypeVariable, type : Types::Type) : Bool
        type = prune(type)

        case type
        when Types::TypeVariable
          type == var
        when Types::NominalType
          type.type_args.any? { |t| occurs_in_type(var, t) }
        when Types::FunctionType
          type.param_types.any? { |t| occurs_in_type(var, t) } ||
            occurs_in_type(var, type.return_type)
        else
          false
        end
      end

      def unify(a : Types::Type, b : Types::Type, loc : ASTData::SourceLocation)
        a = prune(a)
        b = prune(b)

        # variable cases
        if a.is_a?(Types::TypeVariable)
          if a != b
            if occurs_in_type(a, b)
              raise error("Recursive type detected during unification", loc)
            end
            a.instance = b
          end
          return
        end

        if b.is_a?(Types::TypeVariable)
          unify(b, a, loc)
          return
        end

        # nominal types
        if a.is_a?(Types::NominalType) && b.is_a?(Types::NominalType)
          # If definitions differ, check for union/variant relationships
          if a.definition != b.definition
            # check if right is a variant of left union
            if a.definition.is_a?(Types::UnionTypeDefinition)
              union_def = a.definition.as(Types::UnionTypeDefinition)
              if union_def.variants.any? { |v| v.name == b.definition.name }
                # IMPORTANT: propagate union type args, not variant args
                b = Types::NominalType.new(union_def, a.type_args)
              end
            end

            # check opposite direction
            if b.definition.is_a?(Types::UnionTypeDefinition)
              union_def = b.definition.as(Types::UnionTypeDefinition)
              if union_def.variants.any? { |v| v.name == a.definition.name }
                # IMPORTANT: propagate union type args
                a = Types::NominalType.new(union_def, b.type_args)
              end
            end
          end

          # If both now refer to same union, ensure type args unify
          if a.definition == b.definition && a.definition.is_a?(Types::UnionTypeDefinition)
            a.type_args.each_with_index do |t, i|
              unify(t, b.type_args[i], loc)
            end
            return
          end

          # If the names match, allow generic-to-instantiated unification
          if a.definition.name == b.definition.name
            if a.type_args.size != b.type_args.size
              raise error("Type argument mismatch #{a} vs #{b}", loc)
            end
            a.type_args.each_with_index do |t, i|
              unify(t, b.type_args[i], loc)
            end
            return
          end

          # If names differ, it's a type mismatch
          raise error("Type mismatch #{a} is not #{b}", loc)
        end

        # function types
        if a.is_a?(Types::FunctionType) && b.is_a?(Types::FunctionType)
          if a.param_types.size != b.param_types.size
            raise error("Function arity mismatch", loc)
          end

          a.param_types.each_with_index do |p, i|
            unify(p, b.param_types[i], loc)
          end

          unify(a.return_type, b.return_type, loc)
          return
        end

        raise error("Cannot unify #{a} with #{b}", loc)
      end

      def parse_type_identifier(type_id : ASTData::TypeID, generics = [] of String) : Types::Type
        name = type_id.name

        # If the name matches a generic in this scope, return a GenericTypeParameter
        if generics.includes?(name)
          return Types::GenericTypeParameter.new(name)
        end

        # Otherwise, look up the type reference in the global environment
        ref = global.type_reference(name).as?(Types::NominalTypeReference) ||
              raise "Unknown type: #{name}"

        defn = global.type_definition(ref) ||
               raise "Missing type definition for #{name}"

        # For generics (e.g., Maybe(Int)), recursively resolve type arguments
        type_args = type_id.inner_type_ids.map { |inner| parse_type_identifier(inner, generics).as(Types::Type) }

        Types::NominalType.new(defn, type_args)
      end
    end
  end
end
