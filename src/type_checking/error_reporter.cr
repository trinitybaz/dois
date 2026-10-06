require "./type_error"

module DoisC
  module TypeChecking
    module ErrorReporter
      private def error(message : String?, source_location : ASTData::SourceLocation)
        TypeVerificationError.new(
          "#{source_location.line}:#{source_location.column} : #{message}",
          source_location.line,
          source_location.column
        )
      end
    end
  end
end
