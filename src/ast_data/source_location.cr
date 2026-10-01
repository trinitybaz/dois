module DoisC
  module ASTData

    # Compiler metadata on source location of a lex token
    class SourceLocation
      getter line : Int32
      getter column : Int32
      def initialize(@line : Int32, @column : Int32)
      end
    end

  end
end