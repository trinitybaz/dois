require "./token"
require "./source_location"
require "./symbol_ref"
require "../types/type"

module DoisC
  # Data Representations of Abstract Syntax Tree Components
  module ASTData
    # Container for abstract syntax tree (AST) nodes,
    # comprised of a single `Procedure`
    class AST
      getter module_decl : ModuleDeclaration

      def initialize(@module_decl : ModuleDeclaration)
      end
    end

    # Base class that all nodes in the AST derive from
    abstract class Node
      getter source_location : SourceLocation

      def initialize(@source_location : SourceLocation)
      end
    end

    # Base expression class, resolves to a type
    class Expression < Node
      property resolved_type : Types::Type?

      def initialize(source_location : SourceLocation)
        super(source_location)
      end
    end

    # An expression representing a variable or binding
    class IdentifierExpression < Expression
      getter identifier : Identifier

      def initialize(@identifier : Identifier, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Represents a field or property access, i.e. `object.field`
    class AccessExpression < Expression
      getter object : Expression
      getter field : Identifier

      def initialize(@object : Expression, @field : Identifier, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A single operator expression
    class UnaryExpression < Expression
      getter operator : TokenType
      getter right : Expression

      def initialize(@operator : TokenType, @right : Expression, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A two operator expression
    class BinaryExpression < Expression
      getter left : Expression
      getter operator : Operator
      getter right : Expression

      def initialize(@left : Expression, @operator : Operator, @right : Expression, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A conditional branched expression
    class IfExpression < Expression
      getter branches : Array(IfBranch(Expression))
      getter else_body : Expression?

      def initialize(@branches : Array(IfBranch(Expression)), @else_body : Expression?, source_location : SourceLocation)
        super(source_location)
      end
    end

    # FIXME should this be an expression? or something else
    # A reassignment of a variable
    class Reassignment < Expression
      getter identifier : Identifier
      getter value : Expression

      def initialize(@identifier : Identifier, @value : Expression, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Represents a named argument in a call, e.g. `field = value`
    class NamedArgument < Expression
      getter name : String
      getter value : Expression

      def initialize(@name : String, @value : Expression, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Base class for procedure and function calls to inherit from
    # Arguments may be positional (Expression) or named (NamedArgument)
    # Callee can be any Expression (not just Identifier), enabling chaining like a.b().c()
    abstract class Call < Expression
      getter callee : Expression           # can now be IdentifierExpression or AccessExpression, etc.
      getter arguments : Array(Expression) # may include NamedArgument

      def initialize(@callee : Expression, @arguments : Array(Expression), source_location : SourceLocation)
        super(source_location)
      end
    end

    # A call of a procedure in an expression, i.e. `do_thing()`
    # Arguments may be Expressions or NamedArgument for named args
    class ProcedureCall < Call
    end

    # A call of a function in an expression, i.e. `foo()`
    # Arguments may be Expressions or NamedArgument for named args
    class FunctionCall < Call
    end

    # Container for a list of statements
    class Procedure < Node
      getter statements : Array(Statement)

      def initialize(@statements : Array(Statement), source_location : SourceLocation)
        super(source_location)
      end
    end

    # Base class for loops, break, and other misc procedural tools
    abstract class Statement < Node
    end

    # A statement that is just an expression, i.e. a `proc` call
    class ExpressionStatement < Statement
      getter expression : Expression

      def initialize(@expression : Expression, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A while loop statement, i.e. `while x > 2 do...`
    class WhileLoop < Statement
      getter condition : Expression
      getter body : Procedure

      def initialize(@condition : Expression, @body : Procedure, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A break statement in a proceure, i.e. `break`
    class Break < Statement
      def initialize(source_location : SourceLocation)
        super(source_location)
      end
    end

    # A conditional if statement, i.e. `if x > 2 do...`
    class IfStatement < Statement
      getter branches : Array(IfBranch(Procedure))
      getter else_body : Procedure?

      def initialize(@branches : Array(IfBranch(Procedure)), @else_body : Procedure?, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Base class for declaration of a module, identifier, function, etc.
    abstract class Declaration < Statement
      abstract def name : String

      property symbol_ref : SymbolRef?

      def qualified_name : String
        symbol_ref ? symbol_ref.not_nil!.mangled_name : name
      end
    end

    # Declaration of a module, i.e. `module MyModule has...`
    class ModuleDeclaration < Declaration
      getter name : String
      getter body : Array(Statement)

      def initialize(@name : String, @body : Array(Statement), source_location : SourceLocation)
        super(source_location)
      end
    end

    # Declaration of a binding, i.e. `let x = 2`
    class Binding < Declaration
      getter name : String
      getter value : Expression
      getter type_id : TypeID?

      property resolved_type : Types::Type?

      def initialize(@name : String, @value : Expression, @type_id : TypeID?, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Declaration of a variable, i.e. `var y = 3`
    class VarDeclaration < Declaration
      getter name : String
      getter value : Expression?
      getter type_id : TypeID?

      property resolved_type : Types::Type?

      def initialize(@name : String, @value : Expression?, @type_id : TypeID?, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Container for a parameter in function or procedure call
    class Parameter < Node
      getter name : String
      getter type_id : TypeID

      property resolved_scope : Array(String)?

      property resolved_type : Types::Type?

      def initialize(@name : String, @type_id : TypeID, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Declaration of a function, i.e. `fn foo $ ...`
    class FunctionDeclaration < Declaration
      getter name : String
      getter params : Array(Parameter)
      getter generics : Array(String)
      getter body : Expression
      getter return_type_id : TypeID

      property resolved_type : Types::Type?

      def initialize(@name : String, @params : Array(Parameter), @generics : Array(String), @body : Expression, @return_type_id : TypeID, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Declaration of a procedure, i.e. `proc do_thing() ...`
    class ProcedureDeclaration < Declaration
      getter name : String
      getter params : Array(Parameter)
      getter generics : Array(String)
      getter body : Procedure

      property resolved_type : Types::Type?

      def initialize(@name : String, @params : Array(Parameter), @generics : Array(String), @body : Procedure, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Container for field in a type declaration
    class Field < Parameter
    end

    class TypeDeclaration < Declaration
      getter name : String
      getter generics : Array(String)

      def initialize(@name : String, @generics : Array(String), source_location : SourceLocation)
        super(source_location)
      end
    end

    # Declaration of a product type, i.e. `type MyType has...`
    class ProductTypeDeclaration < TypeDeclaration
      getter fields : Array(Field)

      def initialize(name : String, generics : Array(String), @fields : Array(Field), source_location : SourceLocation)
        super(name, generics, source_location)
      end
    end

    # Declaration of a union type, i.e. `type MyType is...`
    class UnionTypeDeclaration < TypeDeclaration
      getter variants : Array(TypeID)

      def initialize(name : String, generics : Array(String), @variants : Array(TypeID), source_location : SourceLocation)
        super(name, generics, source_location)
      end
    end

    # An identifier representing a binding, variable, or function call
    class Identifier < Node
      getter name : String
      getter module_names : Array(String)
      getter accessor_names : Array(String)
      property symbol_ref : SymbolRef?

      def initialize(@name : String, @module_names : Array(String), @accessor_names : Array(String), source_location : SourceLocation)
        super(source_location)
      end

      def to_s
        name
      end
    end

    # Single branch of if expression or statement
    class IfBranch(BodyType) < Node
      getter condition : Expression
      getter body : BodyType

      def initialize(@condition : Expression, @body : BodyType, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Base language literals like characters, nil, integers, etc.
    enum LiteralType
      Char
      String
      Nil
      Bool
      Int
      Float
      Array
      Tuple
      Map
    end

    # Base literal class all literals inherit from
    abstract class Literal < Expression
      abstract def literal_type : LiteralType
    end

    #
    abstract class LiteralValue < Literal
    end

    # Container for String literal, i.e. "Hello"
    class StringLiteral < LiteralValue
      getter value : String

      def initialize(@value : String, source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::String
      end
    end

    # Container for Char literal, i.e. 'c'
    class CharLiteral < LiteralValue
      getter value : Char

      def initialize(@value : Char, source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Char
      end
    end

    # A literal of `nil` of type `Nil`
    class NilLiteral < LiteralValue
      getter value : Nil

      def initialize(@value : Nil, source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Nil
      end
    end

    # Container for `Bool` literal, i.e. `true` or `false`
    class BoolLiteral < LiteralValue
      getter value : Bool

      def initialize(@value : Bool, source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Bool
      end
    end

    # Container for `Int` literal, i.e. `2`, `29`, `42`
    class IntLiteral < LiteralValue
      getter value : Int128

      def initialize(@value : Int128, source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Int
      end
    end

    # Container for `Float` literal, i.e. `3.14`, `1.992`
    class FloatLiteral < LiteralValue
      getter value : Float64

      def initialize(@value : Float64, source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Float
      end
    end

    # Base class for array, tuple, and map literals
    abstract class LiteralCollection < Literal
    end

    # Container for `Array` literal, i.e. `[3, 2, 1]`
    class ArrayLiteral < LiteralCollection
      getter items : Array(Expression)

      def initialize(@items : Array(Expression), source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Array
      end
    end

    # Container for `Tuple` literal, i.e. `('a', 'b', 'c')`
    class TupleLiteral < LiteralCollection
      getter items : Array(Expression)

      def initialize(@items : Array(Expression), source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Tuple
      end
    end

    # Container for `Map` literal, i.e. `{"x" => 1, "y" => 2}
    class MapLiteral < LiteralCollection
      # FIXME Most compilers represent map literals as:
      #   Array({Expression, Expression})
      # instead of Hash
      getter mappings : Hash(Expression, Expression)

      def initialize(@mappings : Hash(Expression, Expression), source_location : SourceLocation)
        super(source_location)
      end

      def literal_type : LiteralType
        LiteralType::Map
      end
    end

    enum OperatorType
      ADD; SUB; MULT; DIV; EQ; LT
    end

    class Operator
      getter type : OperatorType

      def initialize(@type : OperatorType)
      end

      def to_s
        case type
        when OperatorType::ADD
          "+"
        when OperatorType::SUB
          "-"
        when OperatorType::MULT
          "*"
        when OperatorType::DIV
          "/"
        when OperatorType::EQ
          "=="
        when OperatorType::LT
          "<"
        else
          raise "unsupported operator #{type}"
        end
      end
    end

    # A match expression, i.e. `match x then...`
    class MatchExpression < Expression
      getter scrutinee : Expression # can match to any expression ...
      getter branches : Array(MatchBranch)

      def initialize(@scrutinee : Expression, @branches : Array(MatchBranch), source_location : SourceLocation)
        super(source_location)
      end
    end

    # An if-let statement, i.e. `if let y = Some(x)...`
    class IfLetStatement < Statement
      getter pattern : Pattern
      getter scrutinee : Expression
      getter body : Procedure
      getter else_body : Procedure?

      def initialize(@pattern : Pattern, @scrutinee : Expression, @body : Procedure, @else_body : Procedure?, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A single branch in a match expression
    class MatchBranch < Node
      getter pattern : Pattern
      getter body : Expression

      property resolved_type : Types::Type?

      def initialize(@pattern : Pattern, @body : Expression, source_location : SourceLocation)
        super(source_location)
      end
    end

    # Base class for match expression pattern matching
    abstract class Pattern < Node
    end

    # A wildcard match pattern, i.e. `_ => nil`
    class WildCardPattern < Pattern
      property resolved_type : Types::Type?

      def initialize(source_location : SourceLocation)
        super(source_location)
      end
    end

    # A literal match pattern, i.e. `3 => nil`
    class LiteralPattern < Pattern
      getter value : Literal

      def initialize(@value : Literal, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A binding match pattern, i.e. `x => x`
    class BindingPattern < Pattern
      getter name : String

      property resolved_type : Types::Type?

      def initialize(@name : String, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A named field match pattern, i.e. `value = y`
    class NamedFieldPattern < Pattern
      getter field_name : String
      getter pattern : Pattern

      property resolved_type : Types::Type?

      def initialize(@field_name : String, @pattern : Pattern, source_location : SourceLocation)
        super(source_location)
      end
    end

    # A variant match pattern, contains named field patterns
    class VariantPattern < Pattern
      getter name : String
      getter field_patterns : Array(NamedFieldPattern)

      def initialize(
        @name : String,
        @field_patterns : Array(NamedFieldPattern),
        source_location : SourceLocation,
      )
        super(source_location)
      end
    end

    # A tuple match pattern, i.e. `(x, y) => x + y`
    class TuplePattern < Pattern
      getter patterns : Array(Pattern)

      def initialize(@patterns : Array(Pattern), source_location : SourceLocation)
        super(source_location)
      end
    end

    # Type annotation identifier
    class TypeID < Node
      getter name : String
      getter inner_type_ids : Array(TypeID)

      def initialize(@name : String, @inner_type_ids : Array(TypeID), source_location : SourceLocation)
        super(source_location)
      end
    end
  end
end
